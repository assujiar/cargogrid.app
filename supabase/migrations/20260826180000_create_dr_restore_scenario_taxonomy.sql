-- ISS-2026-260 (Step 16 historical-issue-backlog remediation, docs/runtime/KNOWN_ISSUES.md)
-- -- app.dr_restore_tests.component_scope (IAE-035) is CHECK-constrained to
-- ('database', 'secrets', 'backup', 'observability', 'jobs_integrations') -- a
-- component/mechanism taxonomy, not a scenario taxonomy. Prompt 384 section 4/24 names 4
-- DR scenarios this repository's own DR rehearsal charter is built around: data
-- corruption, security incident, provider failure, and major outage. Data corruption maps
-- reasonably onto 'database'/'backup', but the other 3 have no natural component_scope
-- slot -- recording rehearsal evidence for them would have to be shoehorned into an
-- ill-fitting component scope (losing the scenario framing entirely) or left unrecorded
-- structurally.
--
-- Confirmed with the operator (AskUserQuestion) before implementing: add a NEW, parallel,
-- nullable dr_scenario column alongside the existing component_scope, rather than widening
-- component_scope's own CHECK constraint to also accept scenario values. Mixing a
-- mechanism taxonomy and a scenario taxonomy into one enum would make every future query
-- against component_scope (app.resolve_latest_dr_restore_status, the onboarding checklist
-- computation) ambiguous about which taxonomy a given row's value belongs to.
-- component_scope keeps its original, correct, unwidened meaning; dr_scenario is a purely
-- additive second dimension a rehearsal MAY also record. Nullable, never required --
-- every already-applied row (and every future component-only rehearsal that genuinely has
-- no distinct scenario framing) remains valid with dr_scenario left null.
alter table app.dr_restore_tests add column dr_scenario text;

alter table app.dr_restore_tests add constraint dr_restore_tests_dr_scenario_check
  check (dr_scenario is null or dr_scenario in ('data_corruption', 'security_incident', 'provider_failure', 'major_outage'));

comment on column app.dr_restore_tests.dr_scenario is
  'ISS-2026-260: an optional, parallel SCENARIO dimension (Prompt 384 section 4/24''s own 4 named DR scenarios) alongside the existing component_scope MECHANISM dimension -- a rehearsal may record either, both, or (for a pre-existing component-only test) neither. Never required: NULL is the correct value for a rehearsal with no distinct scenario framing, not a gap.';

-- Widens app.record_dr_restore_test with one new, trailing, DEFAULT-valued parameter.
-- CREATE OR REPLACE FUNCTION cannot be used for this: Postgres identifies a function by
-- its name PLUS its full parameter type list, so appending a parameter -- even one with a
-- default -- changes that identity and creates a SECOND, DISTINCT overload alongside the
-- original, rather than truly replacing it (verified directly against a real disposable
-- Postgres instance before writing this migration: a bare 2-arg call against a
-- 2-arg-original/3-arg-with-default-pair became genuinely ambiguous, `function ... is not
-- unique`, exactly the failure mode a silent second overload would produce for every
-- existing 13-argument call site here). The original 13-argument function must be
-- explicitly dropped first so exactly one function (accepting 13 or 14 arguments, the
-- 14th defaulting to null) exists afterward.
drop function app.record_dr_restore_test(uuid, text, text, text, numeric, numeric, text, text, timestamptz, uuid, text, uuid, text);

create function app.record_dr_restore_test(
  p_tenant_id uuid,
  p_deployment_type text,
  p_component_scope text,
  p_status text,
  p_observed_rpo_minutes numeric,
  p_observed_rto_minutes numeric,
  p_failure_reason text,
  p_recovery_steps text,
  p_retest_scheduled_at timestamptz,
  p_owner_auth_user_id uuid,
  p_owner_label text,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  p_dr_scenario text default null
)
returns app.dr_restore_tests
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_authorized boolean;
  v_decision app.rbac_decision;
  v_test app.dr_restore_tests;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if p_tenant_id is null then
    v_authorized := app.is_supreme_admin(p_actor_auth_user_id);
  else
    v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'SUP', 'Configure');
    v_authorized := v_decision.allowed;
  end if;

  if not v_authorized then
    raise exception 'insufficient_authority: identity % lacks authority to record this DR restore test (tenant %)', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_deployment_type not in ('shared', 'dedicated') then
    raise exception 'dr_test_invalid_deployment_type: %', p_deployment_type using errcode = 'check_violation';
  end if;
  if p_component_scope not in ('database', 'secrets', 'backup', 'observability', 'jobs_integrations') then
    raise exception 'dr_test_invalid_component_scope: %', p_component_scope using errcode = 'check_violation';
  end if;
  if p_status not in ('passed', 'failed') then
    raise exception 'dr_test_invalid_status: %', p_status using errcode = 'check_violation';
  end if;
  if p_dr_scenario is not null and p_dr_scenario not in ('data_corruption', 'security_incident', 'provider_failure', 'major_outage') then
    raise exception 'dr_test_invalid_dr_scenario: %', p_dr_scenario using errcode = 'check_violation';
  end if;

  if p_status = 'failed' and (coalesce(trim(p_failure_reason), '') = '' or coalesce(trim(p_recovery_steps), '') = '') then
    raise exception 'dr_test_failure_evidence_required: a real, non-empty failure_reason and recovery_steps must be stated for a failed result'
      using errcode = 'check_violation';
  end if;

  -- Tier C review fix (correctness/concurrency lens): a retest_scheduled_at
  -- in the past provided no real remediation timeline (Prompt 363 §22's own
  -- alternative flow: "release remains blocked with owner, recovery steps
  -- and retest schedule" implies a genuine forward-looking commitment).
  if p_status = 'failed' and p_retest_scheduled_at <= now() then
    raise exception 'dr_test_retest_schedule_must_be_future: retest_scheduled_at % must be after the current time' , p_retest_scheduled_at
      using errcode = 'check_violation';
  end if;

  if p_deployment_type = 'dedicated' and app.resolve_tenant_deployment_type(p_tenant_id) <> 'dedicated' then
    raise exception 'dr_test_deployment_mismatch: tenant % does not have an active dedicated deployment', p_tenant_id
      using errcode = 'check_violation';
  end if;

  insert into app.dr_restore_tests (
    tenant_id, deployment_type, component_scope, status, observed_rpo_minutes, observed_rto_minutes,
    failure_reason, recovery_steps, retest_scheduled_at, owner_auth_user_id, owner_label,
    tested_by_auth_user_id, tested_by, dr_scenario
  )
  values (
    p_tenant_id, p_deployment_type, p_component_scope, p_status, p_observed_rpo_minutes, p_observed_rto_minutes,
    p_failure_reason, p_recovery_steps, p_retest_scheduled_at, p_owner_auth_user_id, p_owner_label,
    p_actor_auth_user_id, p_actor_label, p_dr_scenario
  )
  returning * into v_test;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'record_dr_restore_test',
    'app.dr_restore_tests', v_test.id, 'success', null, null, to_jsonb(v_test)
  );

  return v_test;
end;
$$;

comment on function app.record_dr_restore_test is
  'IAE-035: a dedicated-deployment-scoped test is rejected outright unless the tenant genuinely has an active dedicated deployment (app.resolve_tenant_deployment_type, IAE-032) -- a real, structural composition, not a disclosed prose rule (design decision 3). ISS-2026-260 (Step 16 historical-issue-backlog remediation): p_dr_scenario is an optional, trailing 14th parameter (default null) recording which of Prompt 384''s own 4 named DR scenarios this rehearsal exercised, alongside (never instead of) the existing component_scope mechanism dimension.';

revoke execute on all functions in schema app from public;
grant execute on function app.record_dr_restore_test(uuid, text, text, text, numeric, numeric, text, text, timestamptz, uuid, text, uuid, text, text) to service_role, authenticated;

-- Widens the matching Option 2 public.* wrapper (RGL-394) with the identical trailing
-- default parameter, so a caller reaching this RPC only through PostgREST (app is not
-- exposed directly) can also set p_dr_scenario -- otherwise every call through the public
-- surface would be structurally unable to ever populate the new column. Same reasoning
-- as above: drop the old 13-argument wrapper explicitly first, never CREATE OR REPLACE
-- across a changed argument list.
drop function public.record_dr_restore_test(p_tenant_id uuid, p_deployment_type text, p_component_scope text, p_status text, p_observed_rpo_minutes numeric, p_observed_rto_minutes numeric, p_failure_reason text, p_recovery_steps text, p_retest_scheduled_at timestamp with time zone, p_owner_auth_user_id uuid, p_owner_label text, p_actor_auth_user_id uuid, p_actor_label text);

create function public.record_dr_restore_test(p_tenant_id uuid, p_deployment_type text, p_component_scope text, p_status text, p_observed_rpo_minutes numeric, p_observed_rto_minutes numeric, p_failure_reason text, p_recovery_steps text, p_retest_scheduled_at timestamp with time zone, p_owner_auth_user_id uuid, p_owner_label text, p_actor_auth_user_id uuid, p_actor_label text, p_dr_scenario text default null)
returns app.dr_restore_tests
language sql
volatile
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select app.record_dr_restore_test(p_tenant_id, p_deployment_type, p_component_scope, p_status, p_observed_rpo_minutes, p_observed_rto_minutes, p_failure_reason, p_recovery_steps, p_retest_scheduled_at, p_owner_auth_user_id, p_owner_label, p_actor_auth_user_id, p_actor_label, p_dr_scenario);
$wrap$;

comment on function public.record_dr_restore_test(p_tenant_id uuid, p_deployment_type text, p_component_scope text, p_status text, p_observed_rpo_minutes numeric, p_observed_rto_minutes numeric, p_failure_reason text, p_recovery_steps text, p_retest_scheduled_at timestamp with time zone, p_owner_auth_user_id uuid, p_owner_label text, p_actor_auth_user_id uuid, p_actor_label text, p_dr_scenario text) is
  'RGL-394 Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.record_dr_restore_test with an identical grant set, never a reimplementation. See docs/build-log/release-go-live/RGL-394.md.';

revoke execute on function public.record_dr_restore_test(p_tenant_id uuid, p_deployment_type text, p_component_scope text, p_status text, p_observed_rpo_minutes numeric, p_observed_rto_minutes numeric, p_failure_reason text, p_recovery_steps text, p_retest_scheduled_at timestamp with time zone, p_owner_auth_user_id uuid, p_owner_label text, p_actor_auth_user_id uuid, p_actor_label text, p_dr_scenario text) from anon, authenticated, service_role, public;
grant execute on function public.record_dr_restore_test(p_tenant_id uuid, p_deployment_type text, p_component_scope text, p_status text, p_observed_rpo_minutes numeric, p_observed_rto_minutes numeric, p_failure_reason text, p_recovery_steps text, p_retest_scheduled_at timestamp with time zone, p_owner_auth_user_id uuid, p_owner_label text, p_actor_auth_user_id uuid, p_actor_label text, p_dr_scenario text) to service_role, authenticated;
