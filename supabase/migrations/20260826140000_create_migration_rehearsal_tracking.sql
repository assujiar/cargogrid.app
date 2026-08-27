-- ISS-2026-272 (Step 16 historical-issue-backlog remediation, docs/runtime/KNOWN_ISSUES.md)
-- -- no mechanism tracks "migration rehearsals completed" for enterprise tenants.
-- Business rule (Prompt 385 section 24) states "Enterprise tenants require at least two
-- rehearsals where contracted" -- app.enterprise_onboarding_checklists (IAE-035) tracks
-- exactly 6 fixed items, none for migration rehearsals, and its own item allow-list is
-- closed (requires a schema migration to extend, not a config change). The identical
-- structural pattern already found for DR communication (ISS-2026-258) and for
-- app.dr_restore_tests' own component_scope enum (ISS-2026-260).
--
-- Fixed: a real evidence table + recording RPC mirroring app.dr_restore_tests/
-- app.record_dr_restore_test (IAE-035) verbatim in shape and honesty discipline, plus a
-- 7th checklist item (migration_rehearsal_verified) computed live from it, exactly like
-- the other 5 automated items on this same table.
--
-- Deliberately does NOT add migration_rehearsal_verified to the status='ready_for_
-- production' composite gate the other 6 items already form: the business rule's own
-- text is "where contracted", and no "is migration rehearsal contracted" flag exists
-- anywhere in this schema today. Wiring an unconditional new item into that gate would
-- newly require EVERY tenant -- including ones without that contract clause -- to
-- complete 2 rehearsals before reaching ready_for_production, a real behavior change to
-- existing tenant onboarding gating, not a pure addition. Confirmed with the operator
-- (AskUserQuestion) before implementing: track the item as a real, live-computed,
-- visible signal without changing any existing tenant's readiness outcome. Wiring it
-- into the gate (once a real "contracted" flag exists to condition it on) is left to a
-- dedicated future task, same as this entry's own original disposition.
create table app.migration_rehearsal_tests (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  status text not null,
  scope_summary text not null,
  failure_reason text,
  recovery_steps text,
  retest_scheduled_at timestamptz,
  owner_auth_user_id uuid references auth.users (id),
  owner_label text,
  tested_by_auth_user_id uuid references auth.users (id),
  tested_by text,
  tested_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  constraint migration_rehearsal_tests_status_check check (status in ('passed', 'failed')),
  constraint migration_rehearsal_tests_scope_summary_check check (coalesce(length(trim(scope_summary)), 0) > 0),
  constraint migration_rehearsal_tests_failed_evidence_check check (status <> 'failed' or (failure_reason is not null and recovery_steps is not null and retest_scheduled_at is not null))
);

create index migration_rehearsal_tests_tenant_lookup_idx on app.migration_rehearsal_tests (tenant_id, tested_at desc);

comment on table app.migration_rehearsal_tests is 'ISS-2026-272: real, tenant-scoped migration-rehearsal evidence, mirroring app.dr_restore_tests'' own honesty discipline. scope_summary is a required, non-empty free-text description of what was rehearsed (this domain has no fixed component taxonomy the way DR does -- migration scope varies per customer/contract). A failed row requires a real failure_reason/recovery_steps/retest_scheduled_at, identical to app.dr_restore_tests.';

create function app.record_migration_rehearsal_test(
  p_tenant_id uuid,
  p_status text,
  p_scope_summary text,
  p_failure_reason text,
  p_recovery_steps text,
  p_retest_scheduled_at timestamptz,
  p_owner_auth_user_id uuid,
  p_owner_label text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.migration_rehearsal_tests
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_test app.migration_rehearsal_tests;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'SUP', 'Configure');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks SUP:Configure (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_status not in ('passed', 'failed') then
    raise exception 'migration_rehearsal_invalid_status: %', p_status using errcode = 'check_violation';
  end if;
  if coalesce(trim(p_scope_summary), '') = '' then
    raise exception 'migration_rehearsal_scope_summary_required: a real, non-empty description of what was rehearsed is required'
      using errcode = 'check_violation';
  end if;
  if p_status = 'failed' and (coalesce(trim(p_failure_reason), '') = '' or coalesce(trim(p_recovery_steps), '') = '') then
    raise exception 'migration_rehearsal_failure_evidence_required: a real, non-empty failure_reason and recovery_steps must be stated for a failed result'
      using errcode = 'check_violation';
  end if;
  if p_status = 'failed' and p_retest_scheduled_at <= now() then
    raise exception 'migration_rehearsal_retest_schedule_must_be_future: retest_scheduled_at % must be after the current time', p_retest_scheduled_at
      using errcode = 'check_violation';
  end if;

  insert into app.migration_rehearsal_tests (
    tenant_id, status, scope_summary, failure_reason, recovery_steps, retest_scheduled_at,
    owner_auth_user_id, owner_label, tested_by_auth_user_id, tested_by
  )
  values (
    p_tenant_id, p_status, p_scope_summary, p_failure_reason, p_recovery_steps, p_retest_scheduled_at,
    p_owner_auth_user_id, p_owner_label, p_actor_auth_user_id, p_actor_label
  )
  returning * into v_test;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'record_migration_rehearsal_test',
    'app.migration_rehearsal_tests', v_test.id, 'success', null, null, to_jsonb(v_test)
  );

  return v_test;
end;
$$;

comment on function app.record_migration_rehearsal_test is 'ISS-2026-272: records one real migration-rehearsal result for a tenant. SUP:Configure-gated, mirroring app.record_dr_restore_test''s own authority model for a tenant-scoped test.';

-- New column pair on the existing checklist table (an already-applied migration, not
-- edited): app.enterprise_onboarding_checklists gains a 7th item, matching the shape of
-- the existing 5 automated items exactly (a boolean + its own _at timestamp).
alter table app.enterprise_onboarding_checklists
  add column migration_rehearsal_verified boolean not null default false,
  add column migration_rehearsal_verified_at timestamptz;

comment on column app.enterprise_onboarding_checklists.migration_rehearsal_verified is 'ISS-2026-272: computed live on every app.verify_onboarding_checklist_item(''migration_rehearsal_verified'', ...) call as >=2 app.migration_rehearsal_tests rows with status=''passed'' for this tenant. Deliberately NOT part of the status=''ready_for_production'' composite gate the other 6 items form -- the underlying business rule is "where contracted" and no contract-flag exists yet to condition the gate on; this item is a real, visible, live-computed signal on its own, not (yet) a blocking requirement for every tenant.';

-- CREATE OR REPLACE on the identical existing signature -- widens the item allow-list,
-- adds the new computation branch, and widens the UPDATE ... SET block for the 2 new
-- columns. The status='ready_for_production' composite at the end is UNCHANGED -- still
-- exactly the original 6 items, per this migration's own header rationale.
create or replace function app.verify_onboarding_checklist_item(
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

  if p_item not in ('sso_verified', 'api_verified', 'integrations_verified', 'dr_evidence_verified', 'support_entitlement_verified', 'hypercare_plan_acknowledged', 'migration_rehearsal_verified') then
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
  elsif p_item = 'migration_rehearsal_verified' then
    v_computed := (select count(*) >= 2 from app.migration_rehearsal_tests where tenant_id = p_tenant_id and status = 'passed');
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
    migration_rehearsal_verified = case when p_item = 'migration_rehearsal_verified' then v_computed else migration_rehearsal_verified end,
    migration_rehearsal_verified_at = case when p_item = 'migration_rehearsal_verified' then (case when v_computed then now() else null end) else migration_rehearsal_verified_at end,
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
  'IAE-035/ISS-2026-272: 6 items are computed live from real data every call (never a rubber stamp) -- SUP:Configure-gated. hypercare_plan_acknowledged is the one genuine human attestation, deliberately gated at the higher SUP:Approve tier since it is the final sign-off that green-lights production readiness (design decision 4). migration_rehearsal_verified (ISS-2026-272) is a 7th, also live-computed item -- deliberately NOT part of the status=''ready_for_production'' composite gate below, since the underlying business rule is "where contracted" and no contract-flag exists yet to condition the gate on; see this migration''s own header.';

revoke execute on all functions in schema app from public;
grant execute on function app.record_migration_rehearsal_test(uuid, text, text, text, text, timestamptz, uuid, text, uuid, text) to authenticated, service_role;
grant execute on function app.verify_onboarding_checklist_item(uuid, text, boolean, uuid, text) to authenticated, service_role;

-- Option 2 wrapper (RGL-394): app is not exposed to PostgREST directly -- every
-- externally-callable app.* function needs a matching public.* wrapper, enforced by
-- scripts/db-tests/public-api-wrapper-regression.sql's own zero-tolerance guard.
-- app.verify_onboarding_checklist_item already has a public.* wrapper on the identical
-- signature (20260826000000_create_public_api_data_wrappers.sql) -- CREATE OR REPLACE on
-- the app.* side needs no wrapper change. app.record_migration_rehearsal_test is new and
-- needs one.
create function public.record_migration_rehearsal_test(p_tenant_id uuid, p_status text, p_scope_summary text, p_failure_reason text, p_recovery_steps text, p_retest_scheduled_at timestamptz, p_owner_auth_user_id uuid, p_owner_label text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.migration_rehearsal_tests
language sql
volatile
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select app.record_migration_rehearsal_test(p_tenant_id, p_status, p_scope_summary, p_failure_reason, p_recovery_steps, p_retest_scheduled_at, p_owner_auth_user_id, p_owner_label, p_actor_auth_user_id, p_actor_label);
$wrap$;

comment on function public.record_migration_rehearsal_test(p_tenant_id uuid, p_status text, p_scope_summary text, p_failure_reason text, p_recovery_steps text, p_retest_scheduled_at timestamptz, p_owner_auth_user_id uuid, p_owner_label text, p_actor_auth_user_id uuid, p_actor_label text) is
  'RGL-394 Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.record_migration_rehearsal_test with an identical grant set, never a reimplementation. See docs/build-log/release-go-live/RGL-394.md.';

-- 20260826010000_harden_public_api_data_wrappers_tierc_fixes.sql's own amended
-- convention (Finding 2 there): Supabase's own platform-level default privilege
-- grants EXECUTE on every new public-schema function to anon/authenticated/service_role
-- automatically at CREATE time -- `revoke ... from public` alone (the PUBLIC
-- pseudo-role) never touches that. Must revoke from the named roles explicitly.
revoke execute on function public.record_migration_rehearsal_test(p_tenant_id uuid, p_status text, p_scope_summary text, p_failure_reason text, p_recovery_steps text, p_retest_scheduled_at timestamptz, p_owner_auth_user_id uuid, p_owner_label text, p_actor_auth_user_id uuid, p_actor_label text) from anon, authenticated, service_role, public;
grant execute on function public.record_migration_rehearsal_test(p_tenant_id uuid, p_status text, p_scope_summary text, p_failure_reason text, p_recovery_steps text, p_retest_scheduled_at timestamptz, p_owner_auth_user_id uuid, p_owner_label text, p_actor_auth_user_id uuid, p_actor_label text) to authenticated, service_role;
