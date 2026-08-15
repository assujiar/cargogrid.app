-- Phase 7 (HRIS and Ticketing) hardening -- Prompt 295 (CG-S12-HRT-023),
-- repair group "Recruitment -> Onboarding position headcount". Closes the
-- one HRT-294 (Prompt 294) finding owned by this group, scoped explicitly
-- to Prompt 295 in docs/runtime/KNOWN_ISSUES.md:
--
--   ISS-2026-107 (High) -- app.start_onboarding_case's own job_offer source
--   branch called app.create_employee_draft with ONLY a free-text
--   p_position_title -- it never resolved, or otherwise touched, the
--   accepted offer's own REAL, capacity-tracked app.job_vacancies.
--   position_id, and never called app.propose_employee_position_assignment/
--   app.decide_employee_position_assignment (HRT-275's own governed
--   linkage RPCs). app.employees.position_id has exactly ONE writer in the
--   whole repository (app.sync_employee_current_assignment_cache, reachable
--   only via decide_employee_position_assignment/activate_due_employee_
--   position_assignments) -- neither ever reached by the conversion.
--   Position headcount/capacity enforcement (app.publish_job_vacancy) counts
--   exclusively from app.employee_position_assignments, a table the
--   conversion never inserted into -- live-proven to let a second vacancy
--   publish against an already-fully-occupied position with zero warning.
--
-- Root cause: the job_offer branch treated "create an employee record" and
-- "consume a real position seat" as the same step -- they are not. Every
-- OTHER hire path that ends with a governed position (a direct
-- app.propose_employee_position_assignment + app.decide_employee_position_
-- assignment call pair, e.g. an existing_employee transfer/promotion) always
-- performs both steps; this ONE path, added later by HRT-277, silently
-- skipped the second one.
--
-- Fix: once the employee draft exists, the job_offer branch resolves the
-- vacancy's own position_id (job_offer -> job_application -> job_vacancy --
-- job_vacancies.position_id is NOT NULL and immutable after creation,
-- HRT-276's own schema comment) and calls app.propose_employee_position_
-- assignment then app.decide_employee_position_assignment, in the SAME
-- transaction, against that real position. This is a CREATE OR REPLACE of
-- app.start_onboarding_case with an IDENTICAL signature -- mirroring this
-- repository's own established "never break an existing caller/grant"
-- discipline; no new GRANT statements are needed.
--
-- Disclosed design decisions (per ISS-2026-107's own Disposition, and this
-- checkpoint's own charter -- named here so they are never left implicit):
--
-- 1. Auto-approve, not a second, independent PLT-123-routed human approval
--    step. The underlying job offer already completed a real, unconditional
--    PLT-123 approval (app.submit_job_offer_for_approval / app.decide_job_
--    offer_approval) before it could ever reach 'accepted' -- routing the
--    resulting, structurally-guaranteed-single position assignment through
--    a SECOND, independent approval gate would be redundant scope creep,
--    not a genuine new control. "Auto-approve" here means precisely: no new
--    pending_approval wait state, no second call, no second person -- both
--    app.propose_employee_position_assignment and app.decide_employee_
--    position_assignment run inside this one transaction.
-- 2. Which actor is recorded as the decider: the SAME p_actor_auth_user_id
--    who is already authorized (HRS:Create) to run this entire governed
--    conversion. This deliberately does NOT invent a "system" identity or
--    any bypass of either RPC's own real app.evaluate_permission check --
--    no such bypass exists anywhere else in this repository, and adding one
--    here would be the actual scope-creep/privilege-escalation risk. The
--    practical, disclosed consequence: completing a job_offer-sourced
--    conversion now requires the calling actor to ALSO hold HRS:Edit and
--    HRS:Approve, not merely HRS:Create. This is a deliberate tightening,
--    not an oversight -- it is EXACTLY the authority a manual propose+decide
--    call pair already requires today for every other governed hire path;
--    the bug being fixed is that the job_offer path alone was silently
--    exempt from it. A caller lacking Edit/Approve now gets a clear
--    insufficient_authority exception and the WHOLE conversion rolls back
--    -- never a partial hire with unconsumed headcount, which is the exact
--    defect this migration closes.
-- 3. direct_hire branch: left UNCHANGED. app.start_onboarding_case's own
--    signature has no p_position_id parameter reachable from direct_hire at
--    all (only free-text p_position_title) -- inventing a new parameter to
--    let a direct_hire caller select a real position would be exactly the
--    "new unplanned capability" this checkpoint's own charter forbids
--    (section 12), not a bounded repair of the registered finding, which is
--    scoped to the job_offer path's own resolvable-but-unused position_id.
--    This narrower gap (a direct_hire conversion still cannot consume real
--    position headcount, structurally, because it is never given a
--    position to consume) stays OPEN and disclosed -- see the KNOWN_ISSUES.md
--    resolution note this migration accompanies.
-- 4. existing_employee source (offboarding/transfer/onboarding-rehire): out
--    of scope -- ISS-2026-107's own Code section names only the job_offer
--    branch's missing position_id resolution; the existing_employee branch
--    never creates a new employee or a new hire at all (app.propose_
--    employee_position_assignment is already the correct, separately-
--    callable governed path for a transfer against an existing employee,
--    unaffected by this fix).

create or replace function app.start_onboarding_case(
  p_tenant_id uuid, p_case_type text, p_source_type text,
  p_source_job_offer_id uuid, p_employee_master_record_id uuid,
  p_checklist_template_version_id uuid, p_effective_date date,
  p_full_name text, p_employment_type text, p_work_email text, p_personal_email text,
  p_personal_phone text, p_national_id_number text, p_date_of_birth date, p_gender text,
  p_company_org_unit_id uuid, p_branch_org_unit_id uuid, p_department_org_unit_id uuid,
  p_position_title text, p_manager_employee_id uuid,
  p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.onboarding_offboarding_cases
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_existing app.onboarding_offboarding_cases;
  v_offer app.job_offers;
  v_application app.job_applications;
  v_candidate app.candidates;
  v_offer_version app.job_offer_versions;
  v_employee app.employees;
  v_case app.onboarding_offboarding_cases;
  v_template_version app.onboarding_checklist_template_versions;
  v_template app.onboarding_checklist_templates;
  v_task app.onboarding_checklist_template_tasks;
  v_case_task_id uuid;
  v_key_to_case_task_id jsonb := '{}'::jsonb;
  v_dep record;
  v_source_candidate_id uuid;
  v_offer_position_id uuid;
  v_assignment app.employee_position_assignments;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'HRS', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_case_type not in ('onboarding', 'offboarding', 'transfer') then
    raise exception 'invalid_case_type: %', p_case_type using errcode = 'check_violation';
  end if;
  if p_source_type not in ('job_offer', 'direct_hire', 'existing_employee') then
    raise exception 'invalid_source_type: %', p_source_type using errcode = 'check_violation';
  end if;

  -- Idempotent replay by the case's own idempotency_key (a caller-supplied key,
  -- used for the direct_hire/existing_employee paths; the job_offer path ALSO
  -- gets a structural guarantee via onboarding_offboarding_cases_source_offer_
  -- unique, checked below). Full-tuple compared (taxonomy C-01, hardened
  -- further by the Tier C review-round fix pass for the direct_hire path's
  -- own identity fields) -- a same-key/different-request call raises
  -- idempotency_key_conflict instead of silently returning the first case.
  if p_idempotency_key is not null then
    select * into v_existing from app.onboarding_offboarding_cases where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
    if found then
      perform app.assert_onboarding_case_start_idempotent_replay(
        v_existing, p_case_type, p_source_type, p_employee_master_record_id, p_effective_date,
        p_full_name, p_employment_type, p_work_email,
        p_company_org_unit_id, p_branch_org_unit_id, p_department_org_unit_id,
        p_position_title, p_manager_employee_id, p_idempotency_key
      );
      return v_existing;
    end if;
  end if;

  if p_source_type = 'job_offer' then
    if p_source_job_offer_id is null then
      raise exception 'source_job_offer_id_required: source_type job_offer requires source_job_offer_id' using errcode = 'check_violation';
    end if;

    -- Structural idempotency for the job_offer path: onboarding_offboarding_
    -- cases_source_offer_unique means a second start against the SAME offer
    -- always returns the FIRST case, never a duplicate (acceptance criterion 1)
    -- -- checked explicitly here (not only relying on the exception handler
    -- below) so a caller who omits p_idempotency_key still gets the safe reuse.
    -- Full-tuple compared (taxonomy C-01): a caller who reuses the SAME
    -- accepted offer but supplies a mismatched case_type (e.g. 'offboarding'
    -- against a source_type that only ever creates 'onboarding' cases) is
    -- rejected, never silently handed back the pre-existing, differently-typed
    -- case.
    select * into v_existing from app.onboarding_offboarding_cases where source_job_offer_id = p_source_job_offer_id;
    if found then
      perform app.assert_onboarding_case_start_idempotent_replay(
        v_existing, p_case_type, p_source_type, null, p_effective_date,
        p_full_name, p_employment_type, p_work_email,
        p_company_org_unit_id, p_branch_org_unit_id, p_department_org_unit_id,
        p_position_title, p_manager_employee_id, p_source_job_offer_id::text
      );
      return v_existing;
    end if;

    select * into v_offer from app.job_offers where id = p_source_job_offer_id and tenant_id = p_tenant_id;
    if not found then
      raise exception 'offer_not_found: %', p_source_job_offer_id using errcode = 'no_data_found';
    end if;
    if v_offer.status <> 'accepted' then
      raise exception 'offer_not_accepted: offer % is %, only an accepted offer can start an onboarding case', p_source_job_offer_id, v_offer.status
        using errcode = 'check_violation';
    end if;
    if p_case_type <> 'onboarding' then
      raise exception 'invalid_case_type_for_source: source_type job_offer requires case_type onboarding, got %', p_case_type using errcode = 'check_violation';
    end if;

    select * into v_application from app.job_applications where id = v_offer.application_id;
    select * into v_candidate from app.candidates where id = v_application.candidate_id;
    select * into v_offer_version from app.job_offer_versions where id = v_offer.current_version_id;
    v_source_candidate_id := v_candidate.id;

    v_employee := app.create_employee_draft(
      p_tenant_id,
      coalesce(nullif(trim(p_full_name), ''), v_candidate.full_name),
      coalesce(p_employment_type, app.map_offer_employment_type_to_employee(v_offer_version.employment_type)),
      p_work_email,
      coalesce(p_personal_email, v_candidate.email),
      coalesce(p_personal_phone, v_candidate.phone),
      coalesce(p_national_id_number, v_candidate.national_id_number),
      coalesce(p_date_of_birth, v_candidate.date_of_birth),
      p_gender,
      coalesce(p_effective_date, v_offer_version.effective_date),
      p_company_org_unit_id, p_branch_org_unit_id, p_department_org_unit_id,
      coalesce(nullif(trim(p_position_title), ''), v_offer_version.title),
      p_manager_employee_id,
      null,
      null,
      'hr_created',
      'hrt277-onboarding-conversion:' || p_source_job_offer_id::text,
      p_actor_auth_user_id, p_actor_label
    );

    -- HRT-295 (ISS-2026-107) fix -- see this migration's own header for the
    -- full disposition. The vacancy this offer was actually for is reachable
    -- through the SAME v_application row already selected above
    -- (job_application.vacancy_id -> job_vacancies.position_id, not-null,
    -- immutable). Propose then immediately decide (auto-approve, design
    -- decision 1 above), consuming real headcount and populating
    -- app.employees.position_id via app.sync_employee_current_assignment_
    -- cache -- the SAME governed path every other hire in this system
    -- already uses. A caller lacking HRS:Edit/HRS:Approve (design decision 2
    -- above) raises insufficient_authority here and the entire conversion,
    -- including the just-created employee draft, rolls back -- there is no
    -- code path left where a job_offer-sourced case exists without a real,
    -- active position assignment behind it.
    select position_id into v_offer_position_id from app.job_vacancies where id = v_application.vacancy_id;

    v_assignment := app.propose_employee_position_assignment(
      v_employee.master_record_id, v_employee.record_version, v_offer_position_id, null, p_manager_employee_id,
      'primary', null, coalesce(p_effective_date, v_offer_version.effective_date), null,
      'hire', 'hrt295-onboarding-conversion: system-proposed from accepted offer ' || p_source_job_offer_id::text,
      p_actor_auth_user_id, p_actor_label
    );
    v_assignment := app.decide_employee_position_assignment(
      v_assignment.id, v_assignment.record_version, 'approve',
      'hrt295-onboarding-conversion: auto-approved -- offer ' || p_source_job_offer_id::text || ' already completed its own PLT-123 approval before reaching accepted',
      p_actor_auth_user_id, p_actor_label
    );
  elsif p_source_type = 'direct_hire' then
    if p_case_type <> 'onboarding' then
      raise exception 'invalid_case_type_for_source: source_type direct_hire requires case_type onboarding, got %', p_case_type using errcode = 'check_violation';
    end if;
    if p_full_name is null or length(trim(p_full_name)) = 0 then
      raise exception 'invalid_full_name: direct_hire requires full_name' using errcode = 'check_violation';
    end if;
    if p_employment_type is null then
      raise exception 'invalid_employment_type: direct_hire requires employment_type' using errcode = 'check_violation';
    end if;
    if p_idempotency_key is null then
      raise exception 'idempotency_key_required: direct_hire requires a caller-supplied idempotency_key' using errcode = 'check_violation';
    end if;

    -- HRT-295 (ISS-2026-107) design decision 3 above: direct_hire has no
    -- position_id reachable anywhere in this function's own signature (only
    -- free-text p_position_title) -- left as a disclosed, narrower, still-
    -- open gap rather than adding a new parameter this checkpoint's own
    -- charter does not authorize. This branch is otherwise UNCHANGED.
    v_employee := app.create_employee_draft(
      p_tenant_id, p_full_name, p_employment_type, p_work_email, p_personal_email, p_personal_phone,
      p_national_id_number, p_date_of_birth, p_gender, p_effective_date,
      p_company_org_unit_id, p_branch_org_unit_id, p_department_org_unit_id, p_position_title, p_manager_employee_id,
      null, null, 'hr_created', 'hrt277-direct-hire:' || p_idempotency_key,
      p_actor_auth_user_id, p_actor_label
    );
  else -- existing_employee (offboarding, transfer, or onboarding-rehire)
    if p_employee_master_record_id is null then
      raise exception 'employee_master_record_id_required: source_type existing_employee requires employee_master_record_id' using errcode = 'check_violation';
    end if;
    select * into v_employee from app.employees where master_record_id = p_employee_master_record_id and tenant_id = p_tenant_id;
    if not found then
      raise exception 'employee_not_found: %', p_employee_master_record_id using errcode = 'no_data_found';
    end if;
    if p_case_type = 'offboarding' and v_employee.lifecycle_status not in ('active', 'on_leave', 'suspended') then
      raise exception 'invalid_transition: employee % is %, cannot start an offboarding case', p_employee_master_record_id, v_employee.lifecycle_status
        using errcode = 'check_violation';
    end if;
    if p_case_type = 'transfer' and v_employee.lifecycle_status not in ('active', 'on_leave') then
      raise exception 'invalid_transition: employee % is %, cannot start a transfer case', p_employee_master_record_id, v_employee.lifecycle_status
        using errcode = 'check_violation';
    end if;
  end if;

  -- Resolve checklist template version: caller-supplied (validated: published,
  -- correct tenant/case_type), or the tenant's current published default for
  -- this case_type. Locked in on the case (RPD-040).
  if p_checklist_template_version_id is not null then
    select * into v_template_version from app.onboarding_checklist_template_versions where id = p_checklist_template_version_id;
    if not found or v_template_version.tenant_id <> p_tenant_id or v_template_version.status <> 'published' then
      raise exception 'template_version_not_available: % is not a published template version for this tenant', p_checklist_template_version_id
        using errcode = 'check_violation';
    end if;
    select * into v_template from app.onboarding_checklist_templates where id = v_template_version.template_id;
    if v_template.case_type <> p_case_type then
      raise exception 'template_case_type_mismatch: template version % is for case_type %, not %', p_checklist_template_version_id, v_template.case_type, p_case_type
        using errcode = 'check_violation';
    end if;
  else
    select tv.* into v_template_version
    from app.onboarding_checklist_template_versions tv
    join app.onboarding_checklist_templates t on t.id = tv.template_id
    where t.tenant_id = p_tenant_id and t.case_type = p_case_type and tv.status = 'published'
    order by tv.published_at desc
    limit 1;
    if not found then
      raise exception 'no_published_checklist_template: tenant % has no published % checklist template', p_tenant_id, p_case_type
        using errcode = 'check_violation';
    end if;
  end if;

  begin
    insert into app.onboarding_offboarding_cases (
      tenant_id, case_type, source_type, source_job_offer_id, source_job_application_id, source_candidate_id,
      employee_master_record_id, checklist_template_version_id, status, effective_date, initiated_by,
      idempotency_key, created_by
    ) values (
      p_tenant_id, p_case_type, p_source_type, p_source_job_offer_id, v_application.id, v_source_candidate_id,
      v_employee.master_record_id, v_template_version.id, 'active', coalesce(p_effective_date, v_offer_version.effective_date), p_actor_label,
      p_idempotency_key, p_actor_label
    )
    returning * into v_case;
  exception
    when unique_violation then
      -- Concurrent-race recovery (taxonomy C-01: full-tuple compared, not
      -- merely key/offer-matched, mirroring the pre-insert checks above).
      if p_source_job_offer_id is not null then
        select * into v_case from app.onboarding_offboarding_cases where source_job_offer_id = p_source_job_offer_id;
        if found then
          perform app.assert_onboarding_case_start_idempotent_replay(
            v_case, p_case_type, p_source_type, null, p_effective_date,
            p_full_name, p_employment_type, p_work_email,
            p_company_org_unit_id, p_branch_org_unit_id, p_department_org_unit_id,
            p_position_title, p_manager_employee_id, p_source_job_offer_id::text
          );
          return v_case;
        end if;
      end if;
      if p_idempotency_key is not null then
        select * into v_case from app.onboarding_offboarding_cases where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
        if found then
          perform app.assert_onboarding_case_start_idempotent_replay(
            v_case, p_case_type, p_source_type, p_employee_master_record_id, p_effective_date,
            p_full_name, p_employment_type, p_work_email,
            p_company_org_unit_id, p_branch_org_unit_id, p_department_org_unit_id,
            p_position_title, p_manager_employee_id, p_idempotency_key
          );
          return v_case;
        end if;
      end if;
      raise;
  end;

  -- Instantiate tasks (copied at instantiation -- a later template edit never
  -- retroactively changes this case, section 24's own versioning rule).
  for v_task in select * from app.onboarding_checklist_template_tasks where template_version_id = v_template_version.id order by sort_order loop
    insert into app.onboarding_case_tasks (
      case_id, tenant_id, template_task_key, title, description, task_type, handoff_category,
      owner_type, is_mandatory, due_at, sort_order
    ) values (
      v_case.id, p_tenant_id, v_task.task_key, v_task.title, v_task.description, v_task.task_type, v_task.handoff_category,
      v_task.owner_type, v_task.is_mandatory, now() + make_interval(days => v_task.sla_days), v_task.sort_order
    )
    returning id into v_case_task_id;
    v_key_to_case_task_id := v_key_to_case_task_id || jsonb_build_object(v_task.task_key, v_case_task_id::text);
  end loop;

  for v_dep in select * from app.onboarding_checklist_template_task_dependencies where template_version_id = v_template_version.id loop
    insert into app.onboarding_case_task_dependencies (case_id, tenant_id, task_id, depends_on_task_id)
    values (
      v_case.id, p_tenant_id,
      (v_key_to_case_task_id ->> v_dep.task_key)::uuid,
      (v_key_to_case_task_id ->> v_dep.depends_on_task_key)::uuid
    );
  end loop;

  -- A task with an incomplete dependency starts blocked (section 15 "due/
  -- blocked state"), computed once at instantiation from a real dependency
  -- edge, then re-evaluated at every completion (app.complete_onboarding_task/
  -- app.waive_onboarding_task both re-derive downstream blocked state).
  update app.onboarding_case_tasks t
  set status = 'blocked'
  where t.case_id = v_case.id and t.status = 'pending'
    and exists (select 1 from app.onboarding_case_task_dependencies d where d.task_id = t.id);

  insert into app.onboarding_case_events (case_id, tenant_id, event_type, from_status, to_status, actor_auth_user_id, actor_label)
  values (v_case.id, p_tenant_id, 'start', null, 'active', p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'start_onboarding_case',
    'app.onboarding_offboarding_cases', v_case.id, 'success', null, null, app.onboarding_case_audit_projection(v_case)
  );

  return v_case;
end;
$$;

comment on function app.start_onboarding_case is 'HRT-277, hardened by the Tier C review-round fix pass (20260730890000) and by HRT-295 (ISS-2026-107, 20260731250000): the job_offer branch now resolves the accepted offer''s own real, capacity-tracked position (job_offer -> job_application -> job_vacancy.position_id) and calls app.propose_employee_position_assignment + app.decide_employee_position_assignment (auto-approved, same transaction) so the conversion genuinely consumes position headcount and populates app.employees.position_id -- previously it called ONLY app.create_employee_draft with a free-text position title, consuming zero headcount. direct_hire is unchanged (no position_id reachable from that path, disclosed as a narrower, still-open gap). Never inserts into app.master_records/app.employees/app.users/app.employee_position_assignments directly -- always through the existing governed RPCs.';
