-- Prompt 276 (CG-S12-HRT-004, Recruitment, Job Portal and ATS) -- Tier C batch
-- review-round fix pass. `supabase/migrations/20260730860000_create_hris_recruitment_
-- ats.sql` is already committed (git log shows it as HEAD at the start of this fix
-- pass), so per this repository's standing convention every fix below is applied via
-- `CREATE OR REPLACE FUNCTION` / `REVOKE`+`GRANT` in this new, later-sorting
-- migration -- the original migration is never edited in place.
--
-- Full disposition of all ten review findings is recorded in
-- `docs/build-log/phase-07/HRT-276.md` section 11. Summary of what this migration
-- changes:
--
-- ===========================================================================
-- Findings 1 (HIGH) / 4 (CRITICAL) / 5 (CRITICAL) -- raw-table SELECT on
-- app.interview_feedback / app.job_offer_versions / app.candidate_assessments
-- bypasses every RPC-level authority/identity gate (business rule 4 / prompt
-- section 16 / section 26). Live-reproduced independently against a fresh
-- disposable Postgres 16 database: a real tenant member holding ZERO app.
-- role_assignments rows (hiringmgr@hrrec1.test, evaluate_permission(...).allowed =
-- false, confirmed directly) could `select rating, recommendation, notes from
-- app.interview_feedback`, `select compensation_amount, compensation_currency from
-- app.job_offer_versions`, and `select score, notes from app.candidate_assessments`
-- as a plain `authenticated`-role PostgREST-shaped session, while the same identity
-- was correctly rejected by app.get_offer_timeline with insufficient_authority.
--
-- Fix: apply the exact, already-proven PLT-114/HRT-274 pattern (`app.users`/`app.
-- employees`; also already applied to `app.candidates` in the original migration,
-- design note 9) -- REVOKE the unrestricted table-level SELECT grant from
-- `authenticated` and re-GRANT SELECT on an explicit column list that excludes the
-- purpose-/field-restricted content columns business rule 4 names (interview
-- rating/recommendation/notes; offer compensation_amount/compensation_currency/
-- benefits_note; assessment score/notes). `service_role` keeps unrestricted SELECT
-- (unchanged). No RPC is affected: every read RPC in the original migration is
-- SECURITY DEFINER, executing as the function owner, which is unaffected by a
-- column-level GRANT to `authenticated` -- exactly how `app.get_candidate_profile`
-- already reads the column-restricted `app.candidates` PII columns today.
--
-- Finding 2 (MEDIUM, test-coverage) is closed by the new db-test block this fix adds
-- to `scripts/db-tests/hris-recruitment-ats.sql` (a zero-HRS-permission, non-
-- interviewer tenant member is proven denied raw-column access to all three tables).
--
-- Finding 3 (LOW, documentation accuracy -- "14 tables carry RLS" vs. the real 13,
-- `app.job_application_intake_attempts` intentionally excluded) is disclosed, not
-- fixed here -- see HRT-276.md section 11 (the original build log narrative is
-- append-only and is not rewritten).
--
-- ===========================================================================
-- Findings 7 (CRITICAL, live-reproduced with two real concurrent psql processes) /
-- 8 (HIGH, same root cause, sequential) -- app.reject_application/app.
-- withdraw_application never cancel the offer's in-flight PLT-123 approval request,
-- and app.decide_job_offer_approval's terminal UPDATE carried NO where-clause guard
-- beyond `id = v_request.entity_id` (not even record_version) -- live-reproduced: a
-- concurrent reject + approval-decide race left `job_applications.stage='rejected'`
-- simultaneously with `job_offers.status='approved'`, and continuing the sequence
-- (extend -> accept) reached `stage='offer_accepted'` -- a committed, illegal
-- transition back out of a declared terminal state.
--
-- Fix (two parts, mirroring the already-established `app.cancel_purchase_order`/
-- `app.cancel_vendor_contract` cross-domain precedent for "cancel a pending approval
-- when its subject is terminated"):
--   (a) app.reject_application / app.withdraw_application now call app.
--       cancel_approval_request(...) on any still-`pending_approval` offer's
--       approval request BEFORE flipping the offer to withdrawn -- exactly the
--       PLT-123 cancellation precedent this domain had skipped. The read of the
--       offer row that decides whether to cancel is deliberately a PLAIN
--       (non-locking) SELECT, not `for update` -- an earlier draft of this fix took
--       the lock first and live-reproduced a genuine two-process `deadlock detected`
--       (SQLSTATE 40P01) against app.decide_job_offer_approval's own reverse lock
--       order (approval-engine tables, then app.job_offers); seeing this instead
--       and doing nothing here defers ALL app.job_offers locking to the ordinary
--       UPDATE at the end of each function, matching (b)'s own order exactly. A
--       concurrent cancel-already-happened/already-decided race on the approval
--       request itself is tolerated (caught and treated as a no-op, since the
--       guarded update in (b) is what actually determines final state).
--   (b) app.decide_job_offer_approval's terminal UPDATE now carries a real guard --
--       `where id = v_request.entity_id and approval_request_id = v_request.id and
--       status = 'pending_approval'` -- and raises `offer_approval_no_longer_
--       applicable` (serialization_failure) if the guard does not match, rolling
--       back the ENTIRE decision (including the already-applied app.
--       decide_approval_step mutation, since this is one atomic function call) --
--       an approval decision that arrives after its offer has been concurrently
--       withdrawn/superseded no longer has anywhere to write, and now says so
--       instead of silently succeeding.
-- Live re-verified: the exact two-process race this finding used to corrupt state
-- now leaves `job_applications.stage='rejected'` and raises
-- `offer_approval_no_longer_applicable` on the concurrent decide call, with
-- `job_offers.status` never leaving `withdrawn`.
--
-- ===========================================================================
-- Finding 9 (MEDIUM, C-01) -- app.apply_to_vacancy's idempotency-key replay check
-- compared only (vacancy_id, candidate_id), silently accepting a same-key
-- resubmission with a materially different `source` as an identical replay.
-- Live-reproduced: a second call with the same idempotency_key but source='referral'
-- (first call used source='staff_created') returned the first row unchanged, no
-- error. Fixed by adding `source` to both comparison sites (pre-insert check and the
-- exception-handler's own disambiguation), matching the already-correct full-tuple
-- pattern `app.assert_candidate_draft_idempotent_replay`/`app.create_candidate`
-- already used.
--
-- Propagation sweep (section 5.4) found the identical narrow-tuple-comparison shape
-- in two more sites in the same migration, neither named by the original finding:
--   - app.create_job_vacancy_draft compared only (title, position_id), ignoring
--     employment_type/headcount/description/requirements/hiring_manager_employee_id.
--     Fixed: full tuple now compared at both the pre-insert check and the
--     exception-handler disambiguation.
--   - app.submit_public_job_application (public intake) compared only the
--     resolved candidate's CURRENT email, ignoring full_name/phone. Fixed: full_name
--     and phone added to the comparison.
--
-- ===========================================================================
-- Finding 6 (MEDIUM, rbac-scoping-gap) -- hiring managers have no self-scoped
-- "assigned slice" read path analogous to app.get_my_assigned_interviews; every read
-- RPC gates solely on tenant-wide HRS:View. CONFIRMED by direct code read (zero read
-- RPC references hiring_manager_employee_id anywhere in the migration's 55
-- functions) but NOT fixed here -- a real self-scoped hiring-manager read surface
-- (new RPC(s) plus query/mutation-layer wrapper plus a UI consumer) is a new
-- capability, not a bounded defect repair, and is out of this fix pass's mandate per
-- section 5.6. Registered as `ISS-2026-068` (OPEN, Medium) in
-- `docs/runtime/KNOWN_ISSUES.md`.
--
-- Finding 10 (MEDIUM, cross-prompt-integration) -- the tenant-wide
-- `config_type_code='approval'` config_object singleton (PLT-121's own unique index,
-- `20260717130000`) is structurally shared by every current approval consumer
-- (Sales quotation COM-153, Commercial credit control, Procurement PRC-259/260, and
-- now HRT-276 job-offer approval) -- at most one published routing definition can
-- exist per tenant at scope_level='tenant', so a tenant cannot run independent
-- approval chains per business domain. CONFIRMED as a real, pre-existing PLT-121
-- (Phase 6) architectural constraint that HRT-276 measurably widens the blast radius
-- of by adding a fourth, HR-specific consumer, but domain-scoping `config_objects`
-- is a shared-schema redesign requiring its own ADR/change control
-- (`AGENTS.md` "Scope and refactoring"), not a bounded fix in this pass. Registered
-- as `ISS-2026-069` (OPEN, Medium) in `docs/runtime/KNOWN_ISSUES.md`.
--
-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): this migration carries its own
-- explicit REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA app FROM PUBLIC statement before
-- its final grants, the standing per-migration convention since PLT-118.

-- ===========================================================================
-- 1. app.create_job_vacancy_draft -- full-tuple idempotency replay comparison.
-- ===========================================================================

create or replace function app.create_job_vacancy_draft(
  p_tenant_id uuid,
  p_position_id uuid,
  p_title text,
  p_employment_type text,
  p_headcount integer,
  p_description text,
  p_requirements text,
  p_hiring_manager_employee_id uuid,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.job_vacancies
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_existing app.job_vacancies;
  v_position app.positions;
  v_vacancy app.job_vacancies;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'HRS', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_title is null or length(trim(p_title)) = 0 then
    raise exception 'invalid_title: title must not be empty' using errcode = 'check_violation';
  end if;
  if coalesce(p_headcount, 0) <= 0 then
    raise exception 'invalid_headcount: headcount must be positive' using errcode = 'check_violation';
  end if;

  select * into v_position from app.positions where id = p_position_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'position_not_found: %', p_position_id using errcode = 'no_data_found';
  end if;
  if v_position.status <> 'active' then
    raise exception 'position_inactive: position % is inactive and cannot receive a new vacancy', p_position_id using errcode = 'check_violation';
  end if;

  if p_hiring_manager_employee_id is not null and not exists (
    select 1 from app.employees where master_record_id = p_hiring_manager_employee_id and tenant_id = p_tenant_id
  ) then
    raise exception 'employee_not_found: hiring manager %', p_hiring_manager_employee_id using errcode = 'no_data_found';
  end if;

  -- Review-round fix (MEDIUM, C-01 propagation sweep, 20260730870000): compare the
  -- FULL request tuple, not just (title, position_id) -- a same-key resubmission
  -- with a materially different employment_type/headcount/description/requirements/
  -- hiring_manager_employee_id must be rejected as a key-reuse conflict, never
  -- silently accepted as an identical replay.
  if p_idempotency_key is not null then
    select * into v_existing from app.job_vacancies where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
    if found then
      if v_existing.title is distinct from p_title
         or v_existing.position_id is distinct from p_position_id
         or v_existing.employment_type is distinct from p_employment_type
         or v_existing.headcount is distinct from p_headcount
         or v_existing.description is distinct from p_description
         or v_existing.requirements is distinct from p_requirements
         or v_existing.hiring_manager_employee_id is distinct from p_hiring_manager_employee_id
      then
        raise exception 'idempotency_key_conflict: idempotency key % was already used for a different vacancy', p_idempotency_key
          using errcode = 'unique_violation';
      end if;
      return v_existing;
    end if;
  end if;

  begin
    insert into app.job_vacancies (
      tenant_id, position_id, title, employment_type, headcount, description, requirements,
      hiring_manager_employee_id, owner_auth_user_id, idempotency_key, created_by
    ) values (
      p_tenant_id, p_position_id, p_title, p_employment_type, p_headcount, p_description, p_requirements,
      p_hiring_manager_employee_id, p_actor_auth_user_id, p_idempotency_key, p_actor_label
    )
    returning * into v_vacancy;
  exception
    when unique_violation then
      select * into v_existing from app.job_vacancies where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
      if not found then
        raise;
      end if;
      if v_existing.title is distinct from p_title
         or v_existing.position_id is distinct from p_position_id
         or v_existing.employment_type is distinct from p_employment_type
         or v_existing.headcount is distinct from p_headcount
         or v_existing.description is distinct from p_description
         or v_existing.requirements is distinct from p_requirements
         or v_existing.hiring_manager_employee_id is distinct from p_hiring_manager_employee_id
      then
        raise exception 'idempotency_key_conflict: idempotency key % was already used for a different vacancy', p_idempotency_key
          using errcode = 'unique_violation';
      end if;
      return v_existing;
  end;

  insert into app.job_vacancy_lifecycle_events (tenant_id, vacancy_id, from_status, to_status, reason, actor_auth_user_id, actor_label)
  values (p_tenant_id, v_vacancy.id, 'none', 'draft', 'created', p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_job_vacancy_draft',
    'app.job_vacancies', v_vacancy.id, 'success', null, null, app.job_vacancy_audit_projection(v_vacancy)
  );

  return v_vacancy;
end;
$$;

comment on function app.create_job_vacancy_draft is 'HRT-276, review-round-fixed by 20260730870000: creates a draft vacancy bound to an active position. Idempotency-key replay now compares the FULL request tuple (C-01 fix), not just (title, position_id).';

-- ===========================================================================
-- 2. app.apply_to_vacancy -- add `source` to the idempotency replay comparison.
-- ===========================================================================

create or replace function app.apply_to_vacancy(
  p_vacancy_id uuid,
  p_candidate_id uuid,
  p_source text,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.job_applications
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_vacancy app.job_vacancies;
  v_candidate app.candidates;
  v_existing app.job_applications;
  v_application app.job_applications;
begin
  select * into v_vacancy from app.job_vacancies where id = p_vacancy_id for update;
  if not found or not app.has_active_tenant_membership(v_vacancy.tenant_id, p_actor_auth_user_id) then
    raise exception 'vacancy_not_found: %', p_vacancy_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_vacancy.tenant_id, 'HRS', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_vacancy.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_vacancy.status <> 'open' then
    raise exception 'vacancy_not_open: vacancy % is % and is not accepting applications', p_vacancy_id, v_vacancy.status using errcode = 'check_violation';
  end if;

  select * into v_candidate from app.candidates where id = p_candidate_id and tenant_id = v_vacancy.tenant_id;
  if not found then
    raise exception 'candidate_not_found: %', p_candidate_id using errcode = 'no_data_found';
  end if;
  if v_candidate.status <> 'active' then
    raise exception 'candidate_not_active: candidate % is % and cannot be applied to a vacancy', p_candidate_id, v_candidate.status using errcode = 'check_violation';
  end if;
  if p_source not in ('staff_created', 'referral', 'agency', 'talent_pool', 'import') then
    raise exception 'invalid_source: % is not valid for staff-initiated application creation', p_source using errcode = 'check_violation';
  end if;

  -- Review-round fix (MEDIUM, C-01, live-reproduced -- 20260730870000): compare the
  -- FULL request tuple including `source`, not just (vacancy_id, candidate_id) -- a
  -- same-key resubmission with a materially different source must be rejected as a
  -- key-reuse conflict, never silently accepted as an identical replay.
  if p_idempotency_key is not null then
    select * into v_existing from app.job_applications where tenant_id = v_vacancy.tenant_id and idempotency_key = p_idempotency_key;
    if found then
      if v_existing.vacancy_id is distinct from p_vacancy_id or v_existing.candidate_id is distinct from p_candidate_id or v_existing.source is distinct from p_source then
        raise exception 'idempotency_key_conflict: idempotency key % was already used for a different application', p_idempotency_key
          using errcode = 'unique_violation';
      end if;
      return v_existing;
    end if;
  end if;

  begin
    insert into app.job_applications (tenant_id, vacancy_id, candidate_id, source, idempotency_key, created_by)
    values (v_vacancy.tenant_id, p_vacancy_id, p_candidate_id, p_source, p_idempotency_key, p_actor_label)
    returning * into v_application;
  exception
    when unique_violation then
      -- Two distinct unique constraints can raise here: the idempotency-key index
      -- (a genuine key-reuse-for-different-target replay) or the one-active-application
      -- partial index (a real duplicate application attempt, independent of any key).
      -- Disambiguate by re-deriving from live state rather than assuming which fired.
      if p_idempotency_key is not null then
        select * into v_existing from app.job_applications where tenant_id = v_vacancy.tenant_id and idempotency_key = p_idempotency_key;
        if found then
          if v_existing.vacancy_id is distinct from p_vacancy_id or v_existing.candidate_id is distinct from p_candidate_id or v_existing.source is distinct from p_source then
            raise exception 'idempotency_key_conflict: idempotency key % was already used for a different application', p_idempotency_key
              using errcode = 'unique_violation';
          end if;
          return v_existing;
        end if;
      end if;
      select * into v_existing from app.job_applications where vacancy_id = p_vacancy_id and candidate_id = p_candidate_id and stage not in ('rejected', 'withdrawn');
      if found then
        raise exception 'application_already_exists: candidate % already has an active application against vacancy %', p_candidate_id, p_vacancy_id
          using errcode = 'unique_violation';
      end if;
      raise;
  end;

  insert into app.application_stage_history (tenant_id, application_id, from_stage, to_stage, actor_auth_user_id, actor_label)
  values (v_vacancy.tenant_id, v_application.id, 'none', 'new', p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_vacancy.tenant_id, p_actor_auth_user_id, p_actor_label, 'apply_to_vacancy',
    'app.job_applications', v_application.id, 'success', null, null, app.job_application_audit_projection(v_application)
  );

  return v_application;
end;
$$;

comment on function app.apply_to_vacancy is 'HRT-276, review-round-fixed by 20260730870000: idempotency-key replay now compares the FULL request tuple (vacancy_id, candidate_id, source), not just (vacancy_id, candidate_id) -- live-reproduced C-01 fix.';

-- ===========================================================================
-- 3. app.submit_public_job_application -- widen the replay-identity comparison.
-- ===========================================================================

create or replace function app.submit_public_job_application(
  p_posting_token text,
  p_client_key text,
  p_full_name text,
  p_email text,
  p_phone text,
  p_consent_given boolean,
  p_consent_version text,
  p_idempotency_key text
)
returns table (submit_status text, application_id uuid)
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_recent_bad_count integer;
  v_posting app.job_vacancy_postings;
  v_vacancy app.job_vacancies;
  v_existing_application app.job_applications;
  v_candidate app.candidates;
  v_application app.job_applications;
begin
  if p_client_key is null or length(trim(p_client_key)) = 0 then
    raise exception 'intake_client_key_required: a client_key is required' using errcode = 'check_violation';
  end if;

  select count(*) into v_recent_bad_count
  from app.job_application_intake_attempts
  where client_key = p_client_key and kind = 'submit_application' and result in ('not_found', 'invalid') and occurred_at > now() - interval '15 minutes';
  if v_recent_bad_count >= 10 then
    insert into app.job_application_intake_attempts (client_key, kind, result) values (p_client_key, 'submit_application', 'rate_limited');
    return query select 'rate_limited'::text, null::uuid;
    return;
  end if;

  if p_posting_token is null or length(p_posting_token) = 0
     or p_full_name is null or length(trim(p_full_name)) = 0
     or p_email is null or p_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'
     or coalesce(p_consent_given, false) = false
     or p_consent_version is null or length(trim(p_consent_version)) = 0
  then
    insert into app.job_application_intake_attempts (client_key, kind, result) values (p_client_key, 'submit_application', 'invalid');
    return query select 'invalid'::text, null::uuid;
    return;
  end if;

  select * into v_posting from app.job_vacancy_postings where posting_token = p_posting_token for update;
  if not found or v_posting.status <> 'active' or v_posting.expires_at <= now() then
    insert into app.job_application_intake_attempts (client_key, kind, result) values (p_client_key, 'submit_application', 'not_found');
    return query select 'not_found'::text, null::uuid;
    return;
  end if;

  select * into v_vacancy from app.job_vacancies where id = v_posting.vacancy_id for update;
  if not found or v_vacancy.status <> 'open' then
    insert into app.job_application_intake_attempts (client_key, kind, result) values (p_client_key, 'submit_application', 'not_found');
    return query select 'not_found'::text, null::uuid;
    return;
  end if;

  if not exists (select 1 from app.tenants where id = v_vacancy.tenant_id and canonical_status = 'active') then
    insert into app.job_application_intake_attempts (client_key, kind, result) values (p_client_key, 'submit_application', 'not_found');
    return query select 'not_found'::text, null::uuid;
    return;
  end if;

  -- Review-round fix (MEDIUM, C-01 propagation sweep -- 20260730870000): widen the
  -- replay-identity comparison to full_name/phone in addition to email -- a same-key
  -- resubmission with a materially different applicant identity must be rejected as
  -- a conflict, never silently accepted as an identical replay.
  if p_idempotency_key is not null then
    select * into v_existing_application from app.job_applications where tenant_id = v_vacancy.tenant_id and idempotency_key = p_idempotency_key;
    if found then
      select * into v_candidate from app.candidates where id = v_existing_application.candidate_id;
      if found and lower(v_candidate.email) = lower(p_email)
         and v_candidate.full_name is not distinct from p_full_name
         and v_candidate.phone is not distinct from p_phone
      then
        insert into app.job_application_intake_attempts (client_key, kind, result) values (p_client_key, 'submit_application', 'success');
        return query select 'ok'::text, v_existing_application.id;
        return;
      end if;
      insert into app.job_application_intake_attempts (client_key, kind, result) values (p_client_key, 'submit_application', 'conflict');
      return query select 'conflict'::text, null::uuid;
      return;
    end if;
  end if;

  select * into v_candidate from app.candidates where tenant_id = v_vacancy.tenant_id and lower(email) = lower(p_email);
  if not found then
    insert into app.candidates (tenant_id, full_name, email, phone, source, consent_given, consent_given_at, consent_version, created_by)
    values (v_vacancy.tenant_id, p_full_name, lower(p_email), p_phone, 'public_application', true, now(), p_consent_version, 'public_job_application')
    returning * into v_candidate;
  elsif not v_candidate.consent_given then
    update app.candidates set consent_given = true, consent_given_at = now(), consent_version = p_consent_version
    where id = v_candidate.id
    returning * into v_candidate;
  end if;

  if v_candidate.status <> 'active' then
    insert into app.job_application_intake_attempts (client_key, kind, result) values (p_client_key, 'submit_application', 'conflict');
    return query select 'conflict'::text, null::uuid;
    return;
  end if;

  begin
    insert into app.job_applications (tenant_id, vacancy_id, candidate_id, source, idempotency_key, created_by)
    values (v_vacancy.tenant_id, v_vacancy.id, v_candidate.id, 'public_application', p_idempotency_key, 'public_job_application')
    returning * into v_application;
  exception
    when unique_violation then
      select * into v_existing_application from app.job_applications where vacancy_id = v_vacancy.id and candidate_id = v_candidate.id and stage not in ('rejected', 'withdrawn');
      if found then
        insert into app.job_application_intake_attempts (client_key, kind, result) values (p_client_key, 'submit_application', 'success');
        return query select 'ok'::text, v_existing_application.id;
        return;
      end if;
      insert into app.job_application_intake_attempts (client_key, kind, result) values (p_client_key, 'submit_application', 'conflict');
      return query select 'conflict'::text, null::uuid;
      return;
  end;

  insert into app.application_stage_history (tenant_id, application_id, from_stage, to_stage, actor_label)
  values (v_vacancy.tenant_id, v_application.id, 'none', 'new', 'public_job_application');

  perform app.capture_audit_event(
    v_vacancy.tenant_id, null, 'public_job_application', 'submit_public_job_application',
    'app.job_applications', v_application.id, 'success', null, null, app.job_application_audit_projection(v_application)
  );

  insert into app.job_application_intake_attempts (client_key, kind, result) values (p_client_key, 'submit_application', 'success');
  return query select 'ok'::text, v_application.id;
end;
$$;

comment on function app.submit_public_job_application is 'HRT-276, review-round-fixed by 20260730870000: genuinely anonymous -- never raises after the rate-limit check passes. Idempotent-replay identity comparison now also checks full_name/phone, not only email (C-01 propagation-sweep fix).';

-- ===========================================================================
-- 4. app.reject_application / app.withdraw_application -- cancel a still-pending
--    PLT-123 approval request before cascading the offer to withdrawn.
-- ===========================================================================

create or replace function app.reject_application(p_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.job_applications
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_application app.job_applications;
  v_from_stage text;
  v_offer app.job_offers;
begin
  select * into v_application from app.job_applications where id = p_id;
  if not found or not app.has_active_tenant_membership(v_application.tenant_id, p_actor_auth_user_id) then
    raise exception 'application_not_found: %', p_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_application.tenant_id, 'HRS', 'Reject');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Reject (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_application.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_application.record_version <> p_expected_version then
    raise exception 'stale_version: application % expected version % but found %', p_id, p_expected_version, v_application.record_version
      using errcode = 'serialization_failure';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to reject an application' using errcode = 'check_violation';
  end if;
  if v_application.stage in ('rejected', 'withdrawn', 'offer_accepted') then
    raise exception 'invalid_transition: application % is % and cannot be rejected', p_id, v_application.stage using errcode = 'check_violation';
  end if;
  v_from_stage := v_application.stage;

  update app.job_applications set stage = 'rejected', stage_since = now(), rejection_reason = p_reason
  where id = p_id and record_version = p_expected_version
  returning * into v_application;
  if not found then
    raise exception 'stale_version: application % target row was concurrently modified (expected version %)', p_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  -- Review-round fix (CRITICAL, live-reproduced two-process race -- 20260730870000):
  -- cancel any still-pending PLT-123 approval request BEFORE flipping the offer to
  -- withdrawn -- mirrors the already-established app.cancel_purchase_order/app.
  -- cancel_vendor_contract precedent for "cancel a pending approval when its subject
  -- is terminated". Deliberately a PLAIN (non-locking) read of v_offer here, not
  -- `for update`: app.decide_job_offer_approval's own call path locks app.
  -- approval_request_steps/app.approval_requests (inside app.decide_approval_step)
  -- BEFORE it ever touches app.job_offers (its own terminal update runs after).
  -- Taking a `for update` lock on app.job_offers here, before calling app.
  -- cancel_approval_request (which locks the SAME approval-engine tables), would
  -- lock job_offers-then-approval_request_steps -- the exact REVERSE order of that
  -- call path, a real lock-order cycle -- live-reproduced as `deadlock detected`
  -- (SQLSTATE 40P01) during this fix's own regression testing. Locking nothing here
  -- and letting app.cancel_approval_request take its own locks (steps, then
  -- request) first, with app.job_offers only ever locked by the ordinary UPDATE
  -- below (last, exactly matching app.decide_job_offer_approval's own order), closes
  -- the deadlock while keeping the race-safety guarantee: a concurrent decide that
  -- has already resolved the request (or a concurrent caller that already cancelled
  -- it) between this read and the cancel call is tolerated -- the guarded update in
  -- app.decide_job_offer_approval is what actually determines the final state.
  select * into v_offer from app.job_offers where application_id = p_id;
  if found and v_offer.status = 'pending_approval' and v_offer.approval_request_id is not null then
    begin
      perform app.cancel_approval_request(v_offer.approval_request_id, p_actor_auth_user_id, p_actor_label, p_reason);
    exception
      when no_data_found or check_violation then
        null;
    end;
  end if;

  update app.job_offers set status = 'withdrawn' where application_id = p_id and status not in ('withdrawn', 'accepted', 'declined');

  insert into app.application_stage_history (tenant_id, application_id, from_stage, to_stage, reason, actor_auth_user_id, actor_label)
  values (v_application.tenant_id, p_id, v_from_stage, 'rejected', p_reason, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_application.tenant_id, p_actor_auth_user_id, p_actor_label, 'reject_application',
    'app.job_applications', v_application.id, 'success', p_reason, null, app.job_application_audit_projection(v_application)
  );

  return v_application;
end;
$$;

comment on function app.reject_application is 'HRT-276, review-round-fixed by 20260730870000: now cancels a still-pending PLT-123 approval request on the bound offer BEFORE cascading it to withdrawn (CRITICAL race fix, live-reproduced) -- previously left a zombie pending approval that could resurrect a rejected application''s offer.';

create or replace function app.withdraw_application(p_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.job_applications
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_application app.job_applications;
  v_from_stage text;
  v_offer app.job_offers;
begin
  select * into v_application from app.job_applications where id = p_id;
  if not found or not app.has_active_tenant_membership(v_application.tenant_id, p_actor_auth_user_id) then
    raise exception 'application_not_found: %', p_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_application.tenant_id, 'HRS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_application.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_application.record_version <> p_expected_version then
    raise exception 'stale_version: application % expected version % but found %', p_id, p_expected_version, v_application.record_version
      using errcode = 'serialization_failure';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to withdraw an application' using errcode = 'check_violation';
  end if;
  if v_application.stage in ('rejected', 'withdrawn', 'offer_accepted') then
    raise exception 'invalid_transition: application % is % and cannot be withdrawn', p_id, v_application.stage using errcode = 'check_violation';
  end if;
  v_from_stage := v_application.stage;

  update app.job_applications set stage = 'withdrawn', stage_since = now(), withdrawal_reason = p_reason
  where id = p_id and record_version = p_expected_version
  returning * into v_application;
  if not found then
    raise exception 'stale_version: application % target row was concurrently modified (expected version %)', p_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  -- Review-round fix (CRITICAL, same root cause AND same live-reproduced deadlock
  -- lock-order fix as app.reject_application above -- 20260730870000): cancel a
  -- still-pending PLT-123 approval request before cascading the offer to withdrawn,
  -- via a deliberately PLAIN (non-locking) read -- see app.reject_application's own
  -- inline comment for the full lock-order rationale.
  select * into v_offer from app.job_offers where application_id = p_id;
  if found and v_offer.status = 'pending_approval' and v_offer.approval_request_id is not null then
    begin
      perform app.cancel_approval_request(v_offer.approval_request_id, p_actor_auth_user_id, p_actor_label, p_reason);
    exception
      when no_data_found or check_violation then
        null;
    end;
  end if;

  update app.job_offers set status = 'withdrawn' where application_id = p_id and status not in ('withdrawn', 'accepted', 'declined');

  insert into app.application_stage_history (tenant_id, application_id, from_stage, to_stage, reason, actor_auth_user_id, actor_label)
  values (v_application.tenant_id, p_id, v_from_stage, 'withdrawn', p_reason, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_application.tenant_id, p_actor_auth_user_id, p_actor_label, 'withdraw_application',
    'app.job_applications', v_application.id, 'success', p_reason, null, app.job_application_audit_projection(v_application)
  );

  return v_application;
end;
$$;

comment on function app.withdraw_application is 'HRT-276, review-round-fixed by 20260730870000: now cancels a still-pending PLT-123 approval request on the bound offer BEFORE cascading it to withdrawn -- same fix as app.reject_application.';

-- ===========================================================================
-- 5. app.decide_job_offer_approval -- guard the terminal write against a
--    concurrently-terminated offer (the other half of the race fix).
-- ===========================================================================

create or replace function app.decide_job_offer_approval(p_request_step_id uuid, p_decision text, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.job_offers
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_step app.approval_request_steps;
  v_request app.approval_requests;
  v_updated_request app.approval_requests;
  v_offer app.job_offers;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_step from app.approval_request_steps where id = p_request_step_id;
  if not found then
    raise exception 'approval_step_not_found: no approval request step %', p_request_step_id using errcode = 'no_data_found';
  end if;

  select * into v_request from app.approval_requests where id = v_step.request_id;
  if v_request.entity_type <> 'job_offer' or v_request.entity_id is null then
    raise exception 'not_a_job_offer_approval: approval request % is not a job offer approval', v_request.id using errcode = 'check_violation';
  end if;

  perform app.decide_approval_step(p_request_step_id, p_decision, p_actor_auth_user_id, p_actor_label, p_reason);

  select * into v_updated_request from app.approval_requests where id = v_request.id;

  -- Review-round fix (CRITICAL, live-reproduced two-process race -- 20260730870000):
  -- the terminal write previously carried NO guard beyond `id = v_request.entity_id`
  -- -- not even record_version -- so it unconditionally overwrote app.job_offers
  -- regardless of any concurrent reject/withdraw of the underlying application. Now
  -- guarded on (approval_request_id = v_request.id AND status = 'pending_approval'):
  -- if the offer is no longer awaiting THIS specific decision (concurrently
  -- withdrawn, or superseded by a newer offer version that reset approval_status),
  -- the whole function raises and rolls back atomically -- including the
  -- app.decide_approval_step mutation just above, in the SAME transaction -- rather
  -- than silently resurrecting a terminated offer.
  if v_updated_request.status = 'approved' then
    update app.job_offers set status = 'approved', approval_status = 'approved'
    where id = v_request.entity_id and approval_request_id = v_request.id and status = 'pending_approval'
    returning * into v_offer;
    if not found then
      raise exception 'offer_approval_no_longer_applicable: offer % is no longer awaiting decision on approval request % (concurrently withdrawn, rejected, or superseded by a newer offer version)', v_request.entity_id, v_request.id
        using errcode = 'serialization_failure';
    end if;
  elsif v_updated_request.status = 'rejected' then
    update app.job_offers set status = 'draft', approval_status = 'rejected'
    where id = v_request.entity_id and approval_request_id = v_request.id and status = 'pending_approval'
    returning * into v_offer;
    if not found then
      raise exception 'offer_approval_no_longer_applicable: offer % is no longer awaiting decision on approval request % (concurrently withdrawn, rejected, or superseded by a newer offer version)', v_request.entity_id, v_request.id
        using errcode = 'serialization_failure';
    end if;
  else
    select * into v_offer from app.job_offers where id = v_request.entity_id;
  end if;

  return v_offer;
end;
$$;

comment on function app.decide_job_offer_approval is 'HRT-276, review-round-fixed by 20260730870000: the terminal update now guards on (approval_request_id, status=''pending_approval'') and raises offer_approval_no_longer_applicable instead of blindly overwriting a concurrently-terminated offer (CRITICAL race fix, live-reproduced with two real concurrent psql processes). A rejected offer approval still returns the offer to draft; a new version after rejection is legal and resets approval_status/status (design note 4, unchanged).';

-- ===========================================================================
-- 6. Column-restricted grants: app.interview_feedback / app.job_offer_versions /
--    app.candidate_assessments -- the PLT-114/HRT-274/app.candidates pattern.
-- ===========================================================================
--
-- A bare `revoke select (col) on t from authenticated` is NOT sufficient (proven
-- empirically at PLT-114, `20260716110430`) -- table-level and column-level ACLs in
-- Postgres are additive, not layered with override semantics. The correct pattern:
-- REVOKE the table-level grant entirely, then re-GRANT SELECT on an explicit column
-- list that omits the purpose-/field-restricted content columns.

revoke select on app.interview_feedback from authenticated;
grant select (id, tenant_id, interview_id, interviewer_employee_id, submitted_at, record_version) on app.interview_feedback to authenticated;

revoke select on app.job_offer_versions from authenticated;
grant select (id, tenant_id, offer_id, version_number, effective_date, expiry_date, title, employment_type, status, created_by, created_at) on app.job_offer_versions to authenticated;

revoke select on app.candidate_assessments from authenticated;
grant select (id, tenant_id, application_id, assessment_type, criteria_version, max_score, pass_threshold, status, assessor_auth_user_id, completed_at, record_version, created_by, created_at, updated_at) on app.candidate_assessments to authenticated;

-- service_role keeps its own separate, unrestricted grant (from the original
-- migration) unchanged -- the REVOKE statements above target `authenticated` only.

revoke execute on all functions in schema app from public;

grant execute on function app.create_job_vacancy_draft(uuid, uuid, text, text, integer, text, text, uuid, text, uuid, text) to authenticated, service_role;
grant execute on function app.apply_to_vacancy(uuid, uuid, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.submit_public_job_application(text, text, text, text, text, boolean, text, text) to service_role;
grant execute on function app.reject_application(uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.withdraw_application(uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.decide_job_offer_approval(uuid, text, text, uuid, text) to authenticated, service_role;
