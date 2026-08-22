-- IAE-035 (Prompt 363, Group 8, final capability): Disaster Recovery and
-- Enterprise Support.
--
-- Design decisions (cited, not re-derived):
--
-- 1. Genuinely greenfield -- confirmed by direct grep before writing any code
--    (no `dr_restore_test`/`support_entitlement`/`onboarding_checklist` table
--    or function exists anywhere). This checkpoint does NOT duplicate the
--    pre-existing, real `app.support_access_grants`/`app.
--    support_access_sessions` (`PLT-1xx`, case/purpose/time-bound staff
--    impersonation, Prompt 363 §26's own "support access remains case-,
--    purpose- and time-bound" is ALREADY a real, live mechanism there) nor
--    `app.ticket_escalation_policies` (Ticketing's own, much larger,
--    priority-driven escalation engine) -- this checkpoint's own new tables
--    are genuinely additive: DR restore-test evidence, contractual
--    enterprise support entitlements, and an onboarding-readiness checklist,
--    none of which exist anywhere else in this repository.
-- 2. New `SUP` entitlement module (`View`/`Configure`/`Approve`) -- Prompt
--    363's own workstream is "Reliability and Customer Success", distinct
--    from every prior Group 7/8 module, and its own actions need a genuine,
--    separate authority tier (design decision 5).
-- 3. `app.record_dr_restore_test` enforces "do not promise RPO/RTO beyond
--    actual tested evidence" (Prompt 363 §24) structurally: a `passed`
--    result REQUIRES real `observed_rpo_minutes`/`observed_rto_minutes`
--    numbers (never a hollow pass with no measurement); a `failed` result
--    REQUIRES a real `failure_reason`, `recovery_steps`, and
--    `retest_scheduled_at` (Prompt 363 §22's own alternative flow: "release
--    remains blocked with owner, recovery steps and retest schedule").
--    Claiming a `dedicated`-deployment-scoped test for a tenant that does
--    NOT actually have an active dedicated deployment is rejected outright
--    (a real, structural composition with `IAE-032`'s own `app.
--    resolve_tenant_deployment_type`, not a disclosed prose rule).
-- 4. `app.enterprise_onboarding_checklists` is the real, structural "Main
--    flow" (Prompt 363 §21: "onboarding checklist verifies SSO, API,
--    integrations, DR evidence, support entitlement and hypercare plan
--    before production readiness") -- five of its six items are computed
--    LIVE from real, existing data every time they are (re-)verified, never
--    a caller-asserted rubber stamp: SSO from `app.integration_connections`
--    (`enterprise_sso_oidc`/`enterprise_sso_saml` adapters, `IAE-026`), API
--    from `app.api_keys`, integrations from `app.integration_connections`
--    (any non-SSO adapter), and DR evidence from this checkpoint's OWN `app.
--    dr_restore_tests` (requiring a real, passed test across every one of
--    the five DR component scopes, design decision 6). The sixth item,
--    `hypercare_plan_acknowledged`, has no automated signal to compute from
--    anywhere in this repository -- it is a real, honest, human attestation
--    (disclosed, never silently inferred), and is deliberately gated at the
--    higher `SUP:Approve` tier (the other five use `SUP:Configure`) since it
--    is the final sign-off that actually green-lights production readiness.
-- 5. `app.support_entitlements`'s own `enterprise_24_7` tier REQUIRES a real
--    escalation contact email and a real, positive P1 response-time minutes
--    value -- "Enterprise 24/7/P1 support follows RPD-010 and contract
--    terms" (Prompt 363 §24) is enforced structurally: a 24/7 tier can never
--    be recorded as a hollow promise with no actual escalation path.
-- 6. DR runbooks cover "database, files, secrets, jobs, integrations and
--    monitoring" (Prompt 363 §24) -- mapped honestly onto five real
--    component-scope categories: `database`, `backup` (files), `secrets`,
--    `jobs_integrations`, `observability` (monitoring) -- the first three
--    reuse `IAE-032`'s own `tenant_deployment_environment_refs` category
--    vocabulary verbatim where the concept is identical, rather than
--    inventing a parallel one.
-- 7. Every authenticated-reachable function is `SECURITY DEFINER` paired
--    with `app.assert_actor_is_session_identity` as its first statement.
-- 8. Per the standing convention since `PLT-118`: explicit, redundant
--    `revoke execute on all functions in schema app from public`.
-- 9. `app.resolve_latest_dr_restore_status` is the bare-tenant-id, no-actor-
--    parameter default-resolution function this checkpoint's own DR
--    evidence needs -- granted `service_role` ONLY from the very first
--    draft, continuing the pattern `IAE-032`/`IAE-033`/`IAE-034` all already
--    established correctly.

-- ===========================================================================
-- 1. SUP entitlement module.
-- ===========================================================================

insert into app.entitlement_modules (code, name, owning_phase) values
  ('SUP', 'Disaster recovery and enterprise support: restore-test evidence, support entitlements, onboarding readiness', 9);

insert into app.permissions (action, resource_module_code, category, protected) values
  ('View', 'SUP', 'standard', false),
  ('Configure', 'SUP', 'admin', false),
  ('Approve', 'SUP', 'admin', true);

-- ===========================================================================
-- 2. app.dr_restore_tests -- real, tested DR evidence (design decisions 3, 6).
-- ===========================================================================

create table app.dr_restore_tests (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references app.tenants (id),
  deployment_type text not null,
  component_scope text not null,
  status text not null,
  observed_rpo_minutes numeric,
  observed_rto_minutes numeric,
  failure_reason text,
  recovery_steps text,
  retest_scheduled_at timestamptz,
  owner_auth_user_id uuid references auth.users (id),
  owner_label text,
  tested_by_auth_user_id uuid references auth.users (id),
  tested_by text,
  tested_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  constraint dr_restore_tests_deployment_type_check check (deployment_type in ('shared', 'dedicated')),
  constraint dr_restore_tests_scope_check check (tenant_id is not null or deployment_type = 'shared'),
  constraint dr_restore_tests_component_scope_check check (component_scope in ('database', 'secrets', 'backup', 'observability', 'jobs_integrations')),
  constraint dr_restore_tests_status_check check (status in ('passed', 'failed')),
  constraint dr_restore_tests_passed_evidence_check check (status <> 'passed' or (observed_rpo_minutes is not null and observed_rto_minutes is not null)),
  constraint dr_restore_tests_failed_evidence_check check (status <> 'failed' or (failure_reason is not null and recovery_steps is not null and retest_scheduled_at is not null))
);

create index dr_restore_tests_tenant_lookup_idx on app.dr_restore_tests (tenant_id, component_scope, tested_at desc);

comment on table app.dr_restore_tests is
  'IAE-035: tenant_id null means a platform-wide (shared-deployment) restore test; non-null means a tenant''s own dedicated-instance test. A passed row REQUIRES real observed_rpo_minutes/observed_rto_minutes; a failed row REQUIRES a real failure_reason/recovery_steps/retest_scheduled_at (Prompt 363 ''do not promise RPO/RTO beyond actual tested evidence'').';

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
  p_actor_label text
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

  if p_deployment_type = 'dedicated' and app.resolve_tenant_deployment_type(p_tenant_id) <> 'dedicated' then
    raise exception 'dr_test_deployment_mismatch: tenant % does not have an active dedicated deployment', p_tenant_id
      using errcode = 'check_violation';
  end if;

  insert into app.dr_restore_tests (
    tenant_id, deployment_type, component_scope, status, observed_rpo_minutes, observed_rto_minutes,
    failure_reason, recovery_steps, retest_scheduled_at, owner_auth_user_id, owner_label,
    tested_by_auth_user_id, tested_by
  )
  values (
    p_tenant_id, p_deployment_type, p_component_scope, p_status, p_observed_rpo_minutes, p_observed_rto_minutes,
    p_failure_reason, p_recovery_steps, p_retest_scheduled_at, p_owner_auth_user_id, p_owner_label,
    p_actor_auth_user_id, p_actor_label
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
  'IAE-035: a dedicated-deployment-scoped test is rejected outright unless the tenant genuinely has an active dedicated deployment (app.resolve_tenant_deployment_type, IAE-032) -- a real, structural composition, not a disclosed prose rule (design decision 3).';

create function app.resolve_latest_dr_restore_status(p_tenant_id uuid, p_component_scope text)
returns text
language sql
stable
security definer
set search_path = app, pg_temp
as $$
  select coalesce(
    (select status from app.dr_restore_tests where tenant_id = p_tenant_id and component_scope = p_component_scope order by tested_at desc limit 1),
    (select status from app.dr_restore_tests where tenant_id is null and component_scope = p_component_scope order by tested_at desc limit 1)
  );
$$;

comment on function app.resolve_latest_dr_restore_status is
  'IAE-035: the tenant''s own most recent test for this component_scope always wins; falls back to the most recent platform-wide (shared-deployment) test; returns NULL (never an error) when neither exists. service_role-only by design (design decision 9) -- the identical bare-tenant-id shape app.resolve_tenant_deployment_type/app.resolve_tenant_region/app.resolve_workload_budget already established, applied correctly from the first draft.';

-- ===========================================================================
-- 3. app.support_entitlements -- real, contractual support tiers
-- (design decision 5).
-- ===========================================================================

create table app.support_entitlements (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  tier text not null,
  contract_reference text,
  escalation_contact_name text,
  escalation_contact_email text,
  p1_response_minutes integer,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  record_version integer not null default 1,
  constraint support_entitlements_tier_check check (tier in ('standard', 'enterprise_24_7')),
  constraint support_entitlements_p1_response_check check (p1_response_minutes is null or p1_response_minutes > 0),
  constraint support_entitlements_24_7_requires_escalation_check check (
    tier <> 'enterprise_24_7' or (escalation_contact_email is not null and p1_response_minutes is not null)
  ),
  constraint support_entitlements_tenant_unique unique (tenant_id)
);

comment on table app.support_entitlements is
  'IAE-035: enterprise_24_7 REQUIRES a real escalation_contact_email and a real, positive p1_response_minutes -- Prompt 363''s own "Enterprise 24/7/P1 support follows RPD-010 and contract terms" enforced structurally, never a hollow tier claim.';

create function app.touch_support_entitlement_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger support_entitlements_touch_row
  before update on app.support_entitlements
  for each row
  execute function app.touch_support_entitlement_row();

create function app.set_support_entitlement(
  p_tenant_id uuid,
  p_tier text,
  p_contract_reference text,
  p_escalation_contact_name text,
  p_escalation_contact_email text,
  p_p1_response_minutes integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.support_entitlements
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_entitlement app.support_entitlements;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'SUP', 'Configure');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks SUP:Configure (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_tier not in ('standard', 'enterprise_24_7') then
    raise exception 'support_entitlement_invalid_tier: %', p_tier using errcode = 'check_violation';
  end if;
  if p_tier = 'enterprise_24_7' and (coalesce(trim(p_escalation_contact_email), '') = '' or p_p1_response_minutes is null or p_p1_response_minutes <= 0) then
    raise exception 'support_entitlement_24_7_requires_escalation: a real escalation_contact_email and a positive p1_response_minutes are required for enterprise_24_7'
      using errcode = 'check_violation';
  end if;

  insert into app.support_entitlements (tenant_id, tier, contract_reference, escalation_contact_name, escalation_contact_email, p1_response_minutes, created_by)
  values (p_tenant_id, p_tier, p_contract_reference, p_escalation_contact_name, p_escalation_contact_email, p_p1_response_minutes, p_actor_label)
  on conflict (tenant_id) do update
    set tier = excluded.tier, contract_reference = excluded.contract_reference, escalation_contact_name = excluded.escalation_contact_name,
        escalation_contact_email = excluded.escalation_contact_email, p1_response_minutes = excluded.p1_response_minutes
  returning * into v_entitlement;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'set_support_entitlement',
    'app.support_entitlements', v_entitlement.id, 'success', null, null, to_jsonb(v_entitlement)
  );

  return v_entitlement;
end;
$$;

-- ===========================================================================
-- 4. app.enterprise_onboarding_checklists -- the real "Main flow"
-- (design decision 4).
-- ===========================================================================

create table app.enterprise_onboarding_checklists (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  sso_verified boolean not null default false,
  sso_verified_at timestamptz,
  api_verified boolean not null default false,
  api_verified_at timestamptz,
  integrations_verified boolean not null default false,
  integrations_verified_at timestamptz,
  dr_evidence_verified boolean not null default false,
  dr_evidence_verified_at timestamptz,
  support_entitlement_verified boolean not null default false,
  support_entitlement_verified_at timestamptz,
  hypercare_plan_acknowledged boolean not null default false,
  hypercare_plan_acknowledged_at timestamptz,
  hypercare_plan_acknowledged_by_auth_user_id uuid references auth.users (id),
  hypercare_plan_acknowledged_by text,
  status text not null default 'in_progress',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  record_version integer not null default 1,
  constraint enterprise_onboarding_checklists_status_check check (status in ('in_progress', 'ready_for_production')),
  constraint enterprise_onboarding_checklists_tenant_unique unique (tenant_id)
);

comment on table app.enterprise_onboarding_checklists is
  'IAE-035: one row per tenant. Five items are computed LIVE from real, existing data on every (re-)verification call, never a caller-asserted rubber stamp; hypercare_plan_acknowledged is a real, honest human attestation with no automated signal available anywhere in this repository, disclosed rather than silently inferred.';

create function app.touch_enterprise_onboarding_checklist_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger enterprise_onboarding_checklists_touch_row
  before update on app.enterprise_onboarding_checklists
  for each row
  execute function app.touch_enterprise_onboarding_checklist_row();

create function app.verify_onboarding_checklist_item(
  p_tenant_id uuid,
  p_item text,
  p_human_acknowledged boolean,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.enterprise_onboarding_checklists
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_required_action text;
  v_computed boolean;
  v_dr_ok boolean;
  v_category text;
  v_checklist app.enterprise_onboarding_checklists;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if p_item not in ('sso_verified', 'api_verified', 'integrations_verified', 'dr_evidence_verified', 'support_entitlement_verified', 'hypercare_plan_acknowledged') then
    raise exception 'onboarding_invalid_item: %', p_item using errcode = 'check_violation';
  end if;

  v_required_action := case when p_item = 'hypercare_plan_acknowledged' then 'Approve' else 'Configure' end;
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'SUP', v_required_action);
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks SUP:% (%) for tenant %', p_actor_auth_user_id, v_required_action, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  insert into app.enterprise_onboarding_checklists (tenant_id) values (p_tenant_id)
  on conflict (tenant_id) do nothing;

  if p_item = 'sso_verified' then
    v_computed := exists(
      select 1 from app.integration_connections
      where tenant_id = p_tenant_id and adapter_code in ('enterprise_sso_oidc', 'enterprise_sso_saml') and status = 'active'
    );
  elsif p_item = 'api_verified' then
    v_computed := exists(select 1 from app.api_keys where tenant_id = p_tenant_id and status = 'active');
  elsif p_item = 'integrations_verified' then
    v_computed := exists(
      select 1 from app.integration_connections
      where tenant_id = p_tenant_id and status = 'active' and adapter_code not in ('enterprise_sso_oidc', 'enterprise_sso_saml')
    );
  elsif p_item = 'dr_evidence_verified' then
    v_dr_ok := true;
    foreach v_category in array array['database', 'secrets', 'backup', 'observability', 'jobs_integrations']
    loop
      if app.resolve_latest_dr_restore_status(p_tenant_id, v_category) is distinct from 'passed' then
        v_dr_ok := false;
      end if;
    end loop;
    v_computed := v_dr_ok;
  elsif p_item = 'support_entitlement_verified' then
    v_computed := exists(select 1 from app.support_entitlements where tenant_id = p_tenant_id);
  elsif p_item = 'hypercare_plan_acknowledged' then
    v_computed := coalesce(p_human_acknowledged, false);
  end if;

  update app.enterprise_onboarding_checklists set
    sso_verified = case when p_item = 'sso_verified' then v_computed else sso_verified end,
    sso_verified_at = case when p_item = 'sso_verified' then (case when v_computed then now() else null end) else sso_verified_at end,
    api_verified = case when p_item = 'api_verified' then v_computed else api_verified end,
    api_verified_at = case when p_item = 'api_verified' then (case when v_computed then now() else null end) else api_verified_at end,
    integrations_verified = case when p_item = 'integrations_verified' then v_computed else integrations_verified end,
    integrations_verified_at = case when p_item = 'integrations_verified' then (case when v_computed then now() else null end) else integrations_verified_at end,
    dr_evidence_verified = case when p_item = 'dr_evidence_verified' then v_computed else dr_evidence_verified end,
    dr_evidence_verified_at = case when p_item = 'dr_evidence_verified' then (case when v_computed then now() else null end) else dr_evidence_verified_at end,
    support_entitlement_verified = case when p_item = 'support_entitlement_verified' then v_computed else support_entitlement_verified end,
    support_entitlement_verified_at = case when p_item = 'support_entitlement_verified' then (case when v_computed then now() else null end) else support_entitlement_verified_at end,
    hypercare_plan_acknowledged = case when p_item = 'hypercare_plan_acknowledged' then v_computed else hypercare_plan_acknowledged end,
    hypercare_plan_acknowledged_at = case when p_item = 'hypercare_plan_acknowledged' then (case when v_computed then now() else null end) else hypercare_plan_acknowledged_at end,
    hypercare_plan_acknowledged_by_auth_user_id = case when p_item = 'hypercare_plan_acknowledged' and v_computed then p_actor_auth_user_id else hypercare_plan_acknowledged_by_auth_user_id end,
    hypercare_plan_acknowledged_by = case when p_item = 'hypercare_plan_acknowledged' and v_computed then p_actor_label else hypercare_plan_acknowledged_by end,
    status = case when
        (case when p_item = 'sso_verified' then v_computed else sso_verified end)
        and (case when p_item = 'api_verified' then v_computed else api_verified end)
        and (case when p_item = 'integrations_verified' then v_computed else integrations_verified end)
        and (case when p_item = 'dr_evidence_verified' then v_computed else dr_evidence_verified end)
        and (case when p_item = 'support_entitlement_verified' then v_computed else support_entitlement_verified end)
        and (case when p_item = 'hypercare_plan_acknowledged' then v_computed else hypercare_plan_acknowledged end)
      then 'ready_for_production' else 'in_progress' end
  where tenant_id = p_tenant_id
  returning * into v_checklist;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'verify_onboarding_checklist_item',
    'app.enterprise_onboarding_checklists', v_checklist.id, 'success', null, null, to_jsonb(v_checklist)
  );

  return v_checklist;
end;
$$;

comment on function app.verify_onboarding_checklist_item is
  'IAE-035: five items are computed live from real data every call (never a rubber stamp) -- SUP:Configure-gated. hypercare_plan_acknowledged is the one genuine human attestation, deliberately gated at the higher SUP:Approve tier since it is the final sign-off that green-lights production readiness (design decision 4).';

-- ===========================================================================
-- 5. Read paths.
-- ===========================================================================

create function app.list_dr_restore_tests_for_tenant(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns setof app.dr_restore_tests
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'SUP', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks SUP:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query select * from app.dr_restore_tests where tenant_id = p_tenant_id order by tested_at desc;
end;
$$;

create function app.get_support_entitlement(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns app.support_entitlements
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_entitlement app.support_entitlements;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'SUP', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks SUP:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_entitlement from app.support_entitlements where tenant_id = p_tenant_id;
  return v_entitlement;
end;
$$;

create function app.get_enterprise_onboarding_checklist(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns app.enterprise_onboarding_checklists
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_checklist app.enterprise_onboarding_checklists;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'SUP', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks SUP:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_checklist from app.enterprise_onboarding_checklists where tenant_id = p_tenant_id;
  return v_checklist;
end;
$$;

-- ===========================================================================
-- 6. RLS: default-deny, RPC-only.
-- ===========================================================================

alter table app.dr_restore_tests enable row level security;
alter table app.support_entitlements enable row level security;
alter table app.enterprise_onboarding_checklists enable row level security;

revoke all on app.dr_restore_tests from public, anon, authenticated;
revoke all on app.support_entitlements from public, anon, authenticated;
revoke all on app.enterprise_onboarding_checklists from public, anon, authenticated;
grant all on app.dr_restore_tests, app.support_entitlements, app.enterprise_onboarding_checklists to service_role;

revoke execute on all functions in schema app from public;

-- app.resolve_latest_dr_restore_status takes a bare p_tenant_id with no
-- actor/authority parameter at all -- the identical shape app.
-- resolve_tenant_deployment_type/app.resolve_tenant_region/app.
-- resolve_workload_budget already established, applied correctly from the
-- first draft here (design decision 9) -- service_role-only.
grant execute on function app.resolve_latest_dr_restore_status(uuid, text) to service_role;

grant execute on function
  app.record_dr_restore_test(uuid, text, text, text, numeric, numeric, text, text, timestamptz, uuid, text, uuid, text),
  app.set_support_entitlement(uuid, text, text, text, text, integer, uuid, text),
  app.verify_onboarding_checklist_item(uuid, text, boolean, uuid, text),
  app.list_dr_restore_tests_for_tenant(uuid, uuid),
  app.get_support_entitlement(uuid, uuid),
  app.get_enterprise_onboarding_checklist(uuid, uuid)
to authenticated, service_role;
