-- ISS-2026-057 (docs/runtime/KNOWN_ISSUES.md) -- PRC-251 "Bulk-import staged vendors"
-- (`251_VENDOR_REGISTRATION_ONBOARDING_PROMPT.md:100`, an explicitly named alternative
-- flow) has never existed. The only trace of it in the entire repository was the
-- `bulk_import` value in the `vendor_profiles_intake_source_check` constraint and the
-- matching TypeScript enum -- i.e. a caller could tag exactly ONE vendor draft as
-- `bulk_import`-sourced through the ordinary single-vendor RPC, with no batch ingestion,
-- no staged rows, no review step, and no commit adapter anywhere. Re-verified live this
-- checkpoint before writing a line of this migration: `grep -rln "bulk_import|bulkImport"
-- app/ server/ src/ lib/` still returns only the two contract-file enum definitions.
--
-- This migration closes that gap at exactly the fidelity of its own cited precedent --
-- PRC-255's `vendor_rate_import` adapter (`20260730620000`), the capability
-- `ISS-2026-057`'s own text names as the contrast case ("PRC-255 built a real import
-- adapter and precisely disclosed its own import-scope boundaries -- PRC-251 does
-- neither"). Same three pieces, same shapes, same disclosure discipline:
--
--   1. A registered PLT-131 schema kind (`vendor_import`) plus its per-instance
--      `import_export:vendor_import` config type. A tenant still publishes its own
--      column definition through the ordinary Configuration Engine -- this migration
--      registers the KIND, never a tenant's columns.
--   2. A domain row validator (`app.validate_vendor_import_row`) that calls the generic
--      `app.validate_staging_row` UNCHANGED first and then adds only the cross-table and
--      format checks the generic validator structurally cannot perform.
--   3. A commit adapter (`app.commit_vendor_import_job`) that writes through the
--      canonical `app.create_vendor_profile_draft`, never with a direct INSERT --
--      Prompt 131 §24's own binding rule ("Domain adapter uses canonical service/
--      validation, not direct unsafe writes").
--
-- Design decisions, disclosed rather than left implicit:
--
-- * **`app.create_vendor_profile_draft` is called, not reimplemented, and its signature
--   is NOT widened.** PRC-255 widened `app.create_rate_version` with a trailing
--   `p_source_import_staging_row_id`; that is not repeated here. `create_vendor_profile_draft`
--   has 60+ live callers across `scripts/db-tests/`, a `public.` PostgREST wrapper, and a
--   TypeScript mutation path, and adding a defaulted parameter requires DROP + CREATE
--   (a defaulted parameter cannot be added by CREATE OR REPLACE). The provenance link is
--   instead stamped by this adapter in a second statement inside the same transaction,
--   guarded by a real unique index -- the same durable guarantee with none of the blast
--   radius. Every authority check, idempotency-key behaviour, lifecycle event and audit
--   entry `create_vendor_profile_draft` already performs happens unchanged on every
--   imported row.
--
-- * **Authority is strictly stronger than the single-vendor path, never weaker.** The
--   adapter requires BOTH `app.is_support_grant_authority` AND `PRC:Import` (mirroring
--   `app.commit_vendor_rate_import_job` exactly -- neither alone is sufficient), and the
--   underlying `create_vendor_profile_draft` then separately enforces its own unchanged
--   `PRC:Create` gate on every row. A bulk path that could create vendors an actor could
--   not create one at a time would be a privilege-escalation surface, so the composition
--   is deliberately additive.
--
-- * **`intake_source` is forced to `bulk_import` by the adapter and is NOT an importable
--   column.** Letting a spreadsheet declare its own provenance would make the field
--   worthless as an audit signal -- the whole reason `bulk_import` exists in that CHECK
--   constraint. A file cannot claim its rows were `staff_created`.
--
-- * **Every imported vendor is a `draft`, exactly like a hand-entered one.** Import never
--   submits, approves or activates. The full PRC-251 lifecycle (submit -> review ->
--   approve -> activate), its required-contact/address/service preconditions, and its
--   duplicate-candidate gate all remain deliberate human actions afterwards -- the same
--   discipline `app.commit_employee_import_job` holds for employees ("every created row
--   is a real draft employee -- submit/approve/activate remain separate").
--
-- * **Duplicate detection is wired in, and it is the reason this adapter is safe to
--   exist at all.** Bulk vendor creation is the single most effective way to fill a
--   tenant's canonical vendor master with near-duplicate identities -- and PRC-251
--   already built both the detector (`app.search_vendor_duplicate_candidates`, pg_trgm
--   similarity) and the gate (`app.submit_vendor_profile_for_review` refuses while any
--   `pending` candidate remains, `20260730580000:708`). After each row commits, this
--   adapter runs BOTH sweeps against it: trigram name/trade-name similarity, and an exact
--   punctuation-and-case-insensitive match on `business_registration_number` (an NPWP/NIB
--   collision is a far stronger duplicate signal than any name score, and nothing in the
--   schema constrains it). Matches are FLAGGED, never hard-blocked -- the import still
--   succeeds, and the flagged vendor simply cannot be submitted for review until a human
--   resolves the pairing. This is the `ISS-2026-269` shape applied before the defect
--   rather than after it: `app.commit_employee_import_job` had to be hardened twice
--   (`ISS-2026-269`, `ISS-2026-279`) for exactly this class of silent-duplicate-identity
--   gap, and repeating it in a fresh adapter with the detector already sitting unused in
--   the same schema would be inexcusable.
--
-- * **`unique_violation` is discriminated by constraint name, never caught blanket.**
--   This is the repository's most-repeated defect class (`HDN-385`/`ISS-2026-269`/
--   `ISS-2026-279` on the employee adapter, the post-review CRITICAL fix on the vendor
--   rate adapter). Note the specific shape here, which differs from both precedents and
--   is called out so a future reader does not "restore symmetry" by adding a handler that
--   swallows a real failure: **no `unique_violation` escaping `create_vendor_profile_draft`
--   is ever a safe replay.** That function's own idempotency-key path RETURNS the existing
--   row rather than raising, so a `unique_violation` reaching this adapter can only be a
--   genuine `master_records_tenant_code_unique` collision or an `idempotency_key_conflict`
--   (the same key reused for a different `legal_name`) -- both real failures that must
--   abort the whole commit. It is therefore left deliberately UNHANDLED there. The only
--   handler in this adapter sits on the provenance-stamping UPDATE, and it accepts
--   exactly one constraint name.
--
-- * **No silent no-op path.** The provenance stamp checks the returned profile's existing
--   `source_import_staging_row_id` explicitly and raises a named error if it is already
--   bound to a DIFFERENT staging row, rather than writing a `where ... is null` clause
--   that would update zero rows and report success -- the precise failure mode that made
--   the employee-adapter defect invisible for two checkpoints.
--
-- * **IP-allowlist gating, per `ISS-2026-278`.** `p_client_ip` is an optional trailing
--   parameter enforcing the tenant's own allowlist when supplied, unless the acting
--   identity holds an active bypass grant -- the exact shape `20260826190000` applied to
--   all five pre-existing import commit adapters, adopted here at birth so this adapter
--   never becomes a sixth entry in that remediation.
--
-- * **Per `ERR-2026-004`**: this migration carries its own explicit
--   `revoke execute on all functions in schema app from public;` before its final grants.

-- ===========================================================================
-- 1. Schema-kind registration (PLT-131 registry + per-instance config type).
-- ===========================================================================

insert into app.import_export_schemas (code, name, owner_primitive_code, registered_by)
values ('vendor_import', 'Vendor Import', 'PRC', 'system')
on conflict (code) do nothing;

insert into app.config_types (code, name, owner_primitive_code, registered_by)
values ('import_export:vendor_import', 'Vendor Import', 'PRC', 'system')
on conflict (code) do nothing;

-- ===========================================================================
-- 2. Provenance link: which staged row produced which vendor profile.
-- ===========================================================================

alter table app.vendor_profiles
  add column source_import_staging_row_id uuid references app.import_staging_rows (id);

create unique index vendor_profiles_source_import_row_unique
  on app.vendor_profiles (source_import_staging_row_id)
  where source_import_staging_row_id is not null;

comment on column app.vendor_profiles.source_import_staging_row_id is
  'ISS-2026-057: set only by app.commit_vendor_import_job -- the staged row that produced this vendor profile, uniquely indexed so a staged row can ever produce at most one vendor (idempotent-safe commit replay). Null for every hand-entered, invited or self-registered vendor.';

-- ===========================================================================
-- 3. Domain row validator.
-- ===========================================================================

create function app.validate_vendor_import_row(
  p_staging_row_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.import_staging_rows
language plpgsql
as $$
declare
  v_row app.import_staging_rows;
  v_payload jsonb;
  v_field text;
  v_value text;
  v_errors text[] := array[]::text[];
  v_text_fields text[] := array['legal_name', 'trade_name', 'legal_entity_type', 'business_registration_number', 'vendor_category'];
  v_payment_term text;
begin
  -- The generic structural pass runs FIRST and UNCHANGED (required-ness and declared
  -- data_type shape against the tenant's own published column definition). It is never
  -- reimplemented here -- this function only adds what it structurally cannot do.
  v_row := app.validate_staging_row(p_staging_row_id, p_actor_auth_user_id, p_actor_label);

  if v_row.validation_status <> 'valid' then
    return v_row;
  end if;

  v_payload := v_row.raw_payload;

  -- Formula/spreadsheet-injection-shaped values are REJECTED with a clear reason, never
  -- silently stripped: the raw payload is preserved verbatim so a human can see exactly
  -- what the file contained. Mirrors app.validate_vendor_rate_import_row.
  foreach v_field in array v_text_fields loop
    v_value := v_payload ->> v_field;
    if v_value is not null and v_value ~ '^[-+=@\t\r]' then
      v_errors := v_errors || (v_field || ': value begins with a disallowed formula/spreadsheet-injection prefix (=, +, -, @, tab, or carriage return)');
    end if;
  end loop;

  -- legal_name is the one field with no safe default anywhere downstream: it becomes the
  -- master record's own name. A whitespace-only value passes a generic "required" check
  -- (the key is present, the type is text) but would be refused by
  -- app.create_vendor_profile_draft mid-commit, aborting the whole batch over a row that
  -- should have been marked invalid at validation time.
  if coalesce(trim(v_payload ->> 'legal_name'), '') = '' then
    v_errors := v_errors || 'legal_name: must not be empty or whitespace-only'::text;
  end if;

  -- payment_term_days reaches app.create_vendor_profile_draft as an integer cast. A
  -- non-integer or negative value must fail HERE, as a named row-level error, rather than
  -- as a raw cast error or a check_violation that aborts every other row in the batch.
  v_payment_term := nullif(v_payload ->> 'payment_term_days', '');
  if v_payment_term is not null then
    if v_payment_term !~ '^[0-9]+$' then
      v_errors := v_errors || ('payment_term_days: ' || v_payment_term || ' is not a whole, non-negative number of days');
    elsif v_payment_term::numeric > 2147483647 then
      v_errors := v_errors || ('payment_term_days: ' || v_payment_term || ' exceeds the maximum storable value');
    end if;
  end if;

  -- intake_source is set by the adapter, never by the file (see this migration's header).
  -- A file that supplies it is telling us something about its own provenance claim, so it
  -- is refused rather than silently ignored.
  if v_payload ? 'intake_source' then
    v_errors := v_errors || 'intake_source: is not an importable column -- every imported vendor is recorded as bulk_import by the adapter itself'::text;
  end if;

  -- Likewise every lifecycle field: an import creates drafts, and a file must not be able
  -- to claim a vendor is already approved, active, or (worse) not blacklisted.
  foreach v_field in array array['lifecycle_status', 'approval_status', 'blacklist_reason', 'suspend_reason'] loop
    if v_payload ? v_field then
      v_errors := v_errors || (v_field || ': is not an importable column -- imported vendors are always created as drafts and move through the ordinary review lifecycle');
    end if;
  end loop;

  if array_length(v_errors, 1) is not null then
    update app.import_staging_rows
    set validation_status = 'invalid', error = array_to_string(v_errors, '; ')
    where id = p_staging_row_id
    returning * into v_row;

    update app.jobs
    set valid_row_count = valid_row_count - 1, invalid_row_count = invalid_row_count + 1
    where job_id = v_row.job_id;
  end if;

  return v_row;
end;
$$;

comment on function app.validate_vendor_import_row is
  'ISS-2026-057: domain row validator for the vendor_import schema. Calls app.validate_staging_row UNCHANGED for the structural pass, then adds the checks it cannot perform: formula/spreadsheet-injection prefixes (rejected with a reason, never silently stripped -- the raw payload is preserved verbatim), a whitespace-only legal_name, a non-integer or negative payment_term_days, and any attempt by the file to supply intake_source or a lifecycle/approval/blacklist field the adapter alone controls.';

-- ===========================================================================
-- 4. Commit adapter.
-- ===========================================================================

create function app.commit_vendor_import_job(
  p_job_id uuid,
  p_allow_partial boolean,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  p_client_ip text default null
)
returns app.jobs
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_job app.jobs;
  v_decision app.rbac_decision;
  v_pending_count integer;
  v_row record;
  v_payload jsonb;
  v_legal_name text;
  v_trade_name text;
  v_reg_number text;
  v_reg_number_normalized text;
  v_profile app.vendor_profiles;
  v_dupe record;
  v_created_count integer := 0;
  v_skipped_count integer := 0;
  v_flagged_count integer := 0;
  v_updated app.jobs;
  v_constraint_name text;
begin
  select * into v_job from app.jobs where job_id = p_job_id for update;
  if not found then
    raise exception 'import_export_job_not_found: no job %', p_job_id using errcode = 'no_data_found';
  end if;

  if v_job.job_type <> 'import' or v_job.import_export_schema_code <> 'vendor_import' then
    raise exception 'import_export_wrong_schema: job % is not a vendor_import job', p_job_id using errcode = 'check_violation';
  end if;

  if not app.check_import_export_job_authority(v_job.tenant_id, p_actor_auth_user_id) then
    raise exception 'job_actor_unauthorized: identity % lacks active membership in tenant %', p_actor_auth_user_id, v_job.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- BOTH gates, mirroring app.commit_vendor_rate_import_job. PRC:Import alone must never
  -- be sufficient to create canonical vendor identities in bulk, and the underlying
  -- app.create_vendor_profile_draft still separately enforces its own PRC:Create gate on
  -- every single row -- the bulk path is strictly additive to the single-vendor path's
  -- own authority, never a way around it.
  if not app.is_support_grant_authority(p_actor_auth_user_id, v_job.tenant_id) then
    raise exception 'insufficient_authority: identity % holds neither Supreme Admin nor tenant_admin authority for tenant %', p_actor_auth_user_id, v_job.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_job.tenant_id, 'PRC', 'Import');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Import (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_job.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-278 shape, adopted at birth rather than as a later remediation.
  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(v_job.tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(v_job.tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;

  if v_job.status <> 'in_progress' then
    raise exception 'import_export_job_not_committable: job % is %, only an in_progress job may be committed', p_job_id, v_job.status
      using errcode = 'check_violation';
  end if;

  select count(*) into v_pending_count from app.import_staging_rows where job_id = p_job_id and validation_status = 'pending';
  if v_pending_count > 0 then
    raise exception 'import_export_job_not_fully_validated: job % still has % row(s) pending validation', p_job_id, v_pending_count
      using errcode = 'check_violation';
  end if;

  if v_job.invalid_row_count > 0 and not coalesce(p_allow_partial, false) then
    raise exception 'import_export_job_has_invalid_rows: job % has % invalid row(s); pass p_allow_partial to accept a partial commit', p_job_id, v_job.invalid_row_count
      using errcode = 'check_violation';
  end if;

  -- Job-scoped advisory lock, resolved and taken before any staging row is read,
  -- serializing any concurrent or replayed commit call on this SAME job.
  perform pg_advisory_xact_lock(hashtextextended(p_job_id::text, 205));

  for v_row in
    select * from app.import_staging_rows
    where job_id = p_job_id and validation_status = 'valid'
    order by row_number
  loop
    if exists (select 1 from app.vendor_profiles where source_import_staging_row_id = v_row.id) then
      v_skipped_count := v_skipped_count + 1;
      continue;
    end if;

    v_payload := v_row.raw_payload;
    v_legal_name := v_payload ->> 'legal_name';
    v_trade_name := nullif(v_payload ->> 'trade_name', '');
    v_reg_number := nullif(v_payload ->> 'business_registration_number', '');

    -- The canonical write path -- never a direct INSERT (Prompt 131 §24). Deliberately
    -- WITHOUT a unique_violation handler: see this migration's header. No unique_violation
    -- escaping this call is ever a safe replay, because create_vendor_profile_draft's own
    -- idempotency-key path RETURNS the existing row instead of raising. Anything that does
    -- reach here is a genuine master-record code collision or an idempotency key reused
    -- for a different legal_name -- both must abort the whole commit so the surrounding
    -- transaction rolls back and the job is never marked completed with a dropped row.
    v_profile := app.create_vendor_profile_draft(
      v_job.tenant_id,
      v_legal_name,
      v_trade_name,
      nullif(v_payload ->> 'legal_entity_type', ''),
      v_reg_number,
      nullif(v_payload ->> 'vendor_category', ''),
      nullif(v_payload ->> 'payment_term_days', '')::integer,
      'bulk_import',
      'vendor-import:' || v_row.id::text,
      p_actor_auth_user_id,
      p_actor_label
    );

    -- Provenance stamp. Explicit about every outcome -- never a `where ... is null`
    -- clause that would update zero rows and report success.
    if v_profile.source_import_staging_row_id = v_row.id then
      -- Already committed by this exact staged row (an idempotency-key replay that
      -- returned the row this same adapter previously created).
      v_skipped_count := v_skipped_count + 1;
      continue;
    elsif v_profile.source_import_staging_row_id is not null then
      raise exception 'import_vendor_profile_already_bound: staged row % resolved to vendor profile %, which is already bound to a different staged row (%) -- refusing to rebind', v_row.row_number, v_profile.master_record_id, v_profile.source_import_staging_row_id
        using errcode = 'check_violation';
    end if;

    begin
      update app.vendor_profiles
      set source_import_staging_row_id = v_row.id
      where master_record_id = v_profile.master_record_id
      returning * into v_profile;
    exception
      when unique_violation then
        -- The ONLY safe-replay case in this adapter: a concurrent call committed this
        -- exact staged row between the exists-check above and this UPDATE. Any other
        -- unique_violation is a real failure and must abort the whole commit.
        get stacked diagnostics v_constraint_name = constraint_name;
        if v_constraint_name = 'vendor_profiles_source_import_row_unique' then
          v_skipped_count := v_skipped_count + 1;
          continue;
        end if;
        raise;
    end;

    v_created_count := v_created_count + 1;

    -- Duplicate sweep 1: trigram name/trade-name similarity, the detector PRC-251 already
    -- built and left with no bulk caller. Flagged, never blocking -- the row is created
    -- either way, and app.submit_vendor_profile_for_review's own existing gate then
    -- refuses to advance it until a human decides the pairing.
    for v_dupe in
      select d.master_record_id, d.similarity_score
      from app.search_vendor_duplicate_candidates(v_job.tenant_id, v_legal_name, v_trade_name, p_actor_auth_user_id, 5) d
      where d.master_record_id <> v_profile.master_record_id
    loop
      if not exists (
        select 1 from app.vendor_duplicate_candidates
        where source_master_record_id = v_profile.master_record_id and candidate_master_record_id = v_dupe.master_record_id
      ) then
        perform app.flag_vendor_duplicate_candidate(
          v_profile.master_record_id, v_dupe.master_record_id,
          'bulk_import: name/trade-name similarity against an existing vendor in this tenant',
          v_dupe.similarity_score::numeric, p_actor_auth_user_id, p_actor_label
        );
        v_flagged_count := v_flagged_count + 1;
      end if;
    end loop;

    -- Duplicate sweep 2: an identical business registration number (NPWP/NIB). Nothing in
    -- the schema constrains this column, and a trigram name score can miss it entirely
    -- ("PT Contoso Logistik" vs. "Contoso Trucking Indonesia" with one registration
    -- number between them). Compared with punctuation and case normalized away, since a
    -- spreadsheet's formatting of a registration number is not a business fact.
    if v_reg_number is not null then
      v_reg_number_normalized := upper(regexp_replace(v_reg_number, '[^0-9A-Za-z]', '', 'g'));
      if v_reg_number_normalized <> '' then
        for v_dupe in
          select vp.master_record_id
          from app.vendor_profiles vp
          where vp.tenant_id = v_job.tenant_id
            and vp.master_record_id <> v_profile.master_record_id
            and vp.business_registration_number is not null
            and upper(regexp_replace(vp.business_registration_number, '[^0-9A-Za-z]', '', 'g')) = v_reg_number_normalized
        loop
          if not exists (
            select 1 from app.vendor_duplicate_candidates
            where source_master_record_id = v_profile.master_record_id and candidate_master_record_id = v_dupe.master_record_id
          ) then
            perform app.flag_vendor_duplicate_candidate(
              v_profile.master_record_id, v_dupe.master_record_id,
              'bulk_import: identical business registration number after normalizing punctuation and case',
              1.0, p_actor_auth_user_id, p_actor_label
            );
            v_flagged_count := v_flagged_count + 1;
          end if;
        end loop;
      end if;
    end if;
  end loop;

  update app.jobs
  set status = 'completed', completed_at = now()
  where job_id = p_job_id
  returning * into v_updated;

  perform app.capture_audit_event(
    v_job.tenant_id, p_actor_auth_user_id, p_actor_label, 'commit_vendor_import_job',
    'app.jobs', p_job_id, 'success', null, to_jsonb(v_job),
    jsonb_build_object(
      'status', v_updated.status,
      'vendor_profiles_created', v_created_count,
      'rows_already_committed_skipped', v_skipped_count,
      'duplicate_candidates_flagged', v_flagged_count
    )
  );

  return v_updated;
end;
$$;

comment on function app.commit_vendor_import_job is
  'ISS-2026-057: the PLT-131 domain-write adapter for the vendor_import schema, closing PRC-251''s named-but-never-built "Bulk-import staged vendors" alternative flow. Requires BOTH app.is_support_grant_authority AND PRC:Import; app.create_vendor_profile_draft then separately enforces its own unchanged PRC:Create gate per row -- the bulk path is strictly additive to the single-vendor path''s authority, never a way around it. Writes only through that canonical function, never a direct INSERT. intake_source is forced to bulk_import by the adapter (a file cannot claim its own provenance) and every created vendor is a draft -- submit/review/approve/activate remain deliberate human actions. After each row commits, two duplicate sweeps run against it (trigram name/trade-name similarity, and an exact punctuation-and-case-normalized business_registration_number match) and flag app.vendor_duplicate_candidates rows: never a hard block, but app.submit_vendor_profile_for_review''s own existing gate then refuses to advance the vendor until a human resolves the pairing. Idempotent per staged row (vendor_profiles_source_import_row_unique, defended by a pre-check, an explicit already-bound check, a nested unique_violation handler scoped to that one constraint name, and a job-scoped advisory lock); no unique_violation from create_vendor_profile_draft is ever treated as a safe replay, because its own idempotency-key path returns the existing row rather than raising. p_client_ip is an optional trailing 5th parameter enforcing the tenant''s own IP allowlist when supplied, unless the acting identity holds an active bypass grant (ISS-2026-278).';

-- ===========================================================================
-- 5. PostgREST wrappers (RGL-394 Option 2 -- app is not exposed to PostgREST).
-- ===========================================================================

-- security INVOKER, deliberately -- app.validate_vendor_import_row is itself invoker
-- (matching app.validate_vendor_rate_import_row). A definer wrapper over an invoker
-- function is an RLS-bypass class defect, and scripts/db-tests/public-api-wrapper-
-- regression.sql's own exhaustive mode-parity check catches it -- as it did on this
-- migration's first run.
create function public.validate_vendor_import_row(p_staging_row_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
returns app.import_staging_rows
language sql
set search_path = app, public, pg_temp
as $$
  select app.validate_vendor_import_row(p_staging_row_id, p_actor_auth_user_id, p_actor_label);
$$;

comment on function public.validate_vendor_import_row(uuid, uuid, text) is
  'RGL-394 Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.validate_vendor_import_row with an identical grant set, never a reimplementation.';

create function public.commit_vendor_import_job(p_job_id uuid, p_allow_partial boolean, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
returns app.jobs
language sql
security definer
set search_path = app, public, pg_temp
as $$
  select app.commit_vendor_import_job(p_job_id, p_allow_partial, p_actor_auth_user_id, p_actor_label, p_client_ip);
$$;

comment on function public.commit_vendor_import_job(uuid, boolean, uuid, text, text) is
  'RGL-394 Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.commit_vendor_import_job with an identical grant set, never a reimplementation.';

-- ===========================================================================
-- 6. Grants (ERR-2026-004).
-- ===========================================================================

revoke execute on all functions in schema app from public;

grant execute on function app.validate_vendor_import_row(uuid, uuid, text) to service_role;
grant execute on function app.commit_vendor_import_job(uuid, boolean, uuid, text, text) to service_role;

revoke execute on function public.validate_vendor_import_row(uuid, uuid, text) from anon, authenticated, service_role, public;
grant execute on function public.validate_vendor_import_row(uuid, uuid, text) to service_role;

revoke execute on function public.commit_vendor_import_job(uuid, boolean, uuid, text, text) from anon, authenticated, service_role, public;
grant execute on function public.commit_vendor_import_job(uuid, boolean, uuid, text, text) to service_role;
