-- Phase 9 Integrated Verification (IAE-036, Prompt 364) fix pass, per
-- AGENTS.md's cross-batch review cadence extended to a whole-phase
-- checkpoint. Four parallel independent lenses (traceability/evidence-
-- completeness; security/tenant/access matrix, live-tested; cross-
-- capability critical-flow reconciliation, live-tested; REST/GraphQL
-- parity + full regression/parity gates) reviewed the WHOLE merged,
-- already-`VERIFIED` 34-capability system (`IAE-002`..`IAE-035`) together
-- for the first time. This migration is the bounded, additive fix pass for
-- the two findings that needed a real code change -- consistent with
-- Prompt 364 §12's own explicit "no applied-migration edits" rule, no
-- already-applied migration's own past statements are edited (`create or
-- replace function`/`revoke` only), no gate weakened, no test disabled.
--
-- ===========================================================================
-- Findings fixed
-- ===========================================================================
--
-- 1. (High, cross-capability critical-flow reconciliation lens, live-
--    reproduced). `app.get_enterprise_onboarding_checklist` (IAE-035) was a
--    one-way ratchet, not a live-composed checklist, despite `IAE-363.md`
--    design decision 4 and Group 8's own Tier C review explicitly claiming
--    otherwise. `app.verify_onboarding_checklist_item` genuinely recomputes
--    each of the five automated items live from the composed capability's
--    CURRENT state -- but only at the instant it is explicitly called, and
--    persists the result into a stored boolean column. The read path,
--    `app.get_enterprise_onboarding_checklist`, was a plain `select *` --
--    it never recomputed anything. Once an item was marked true, it stayed
--    true forever unless someone happened to re-call
--    `verify_onboarding_checklist_item` for that exact item again, including
--    the overall `status = 'ready_for_production'` field, regardless of
--    what happened afterward to the SSO connection, API key, or integration
--    connection it was derived from. This is the identical "trust a stored
--    snapshot of another capability's state instead of re-checking it live"
--    pattern already found twice in Group 8's own Tier C review
--    (`app.resolve_tenant_region`, `app.resolve_latest_dr_restore_status`,
--    see `00_EXECUTION_INDEX.md` §17) -- except here it is one level worse,
--    since even `dr_evidence_verified`, which internally composes the now-
--    fixed, genuinely-live `app.resolve_latest_dr_restore_status`, still got
--    frozen into a stale boolean the moment it was computed once. Live-
--    reproduced: a tenant's SSO connection marked verified, then disabled
--    live via `app.set_integration_connection_status` with zero explicit
--    re-verify call -- `get_enterprise_onboarding_checklist` kept reporting
--    `sso_verified = true` and, once every other item was separately
--    completed, `status = 'ready_for_production'`, while the tenant
--    genuinely had zero active SSO connection. Fixed by having
--    `get_enterprise_onboarding_checklist` re-derive `sso_verified`,
--    `api_verified`, `integrations_verified`, `dr_evidence_verified`, and
--    `status` LIVE on every read, using the identical live-check queries
--    `verify_onboarding_checklist_item` already uses -- never persisting the
--    recompute back to the row (a pure read-time correction, not a write),
--    so the stored row and its own `*_at` timestamps remain exactly what
--    they always were: real historical evidence of when each item was last
--    explicitly, successfully confirmed, never retroactively falsified.
--    `hypercare_plan_acknowledged` is left read from the stored row
--    unchanged, since it is a genuine human attestation with no independent
--    live source of truth to re-derive it from.
--
-- 2. (Low, security/tenant/access-matrix lens). `app.is_eta_prediction_
--    enabled_for_tenant` (IAE-022) is a bare-`p_tenant_id`, no-actor-param
--    function -- the recurring defect class this repository has repeatedly
--    caught and fixed (`resolve_tenant_deployment_type`, `resolve_tenant_
--    region`, `resolve_retention_days`, `is_high_risk_action`) -- but,
--    unlike all four of those siblings, it was granted `EXECUTE` to
--    `authenticated` rather than `service_role`-only. Not live-exploitable
--    today: the function is plain SQL (not `SECURITY DEFINER`) reading
--    `app.eta_prediction_tenant_settings` directly, and that table carries
--    zero grant to `authenticated` and zero RLS policy, so a genuine
--    `authenticated` caller always fails closed with `permission denied for
--    table eta_prediction_tenant_settings` before any row is ever read --
--    confirmed live and confirmed dead code (zero references anywhere in
--    `app`/`server`/`components` outside its own db-test). The risk is
--    latent: a future migration granting `authenticated` a real `select` on
--    the underlying table (plausible, since nothing today signals "needs an
--    RLS policy first") would instantly turn this into a live cross-tenant
--    boolean-disclosure oracle, since the `EXECUTE` grant is already sitting
--    there waiting. Fixed by revoking the grant, matching the correct
--    sibling pattern -- it already has zero real callers to break.
--
-- ===========================================================================
-- Findings NOT changed here (disclosed/registered, not code-fixed; see
-- docs/build-log/phase-09/IAE-364.md §14 and docs/runtime/KNOWN_ISSUES.md
-- for the full disposition of every finding from all four lenses)
-- ===========================================================================
--
-- - Stale `docs/runtime/HANDOFF.md`/`TASK_LEDGER.md`/`CARGOGRID_BUILD_
--   STATUS.md` (never updated since the Phase 9 kickoff) -- a
--   documentation-only fix, applied directly to those files, not this
--   migration.
-- - 5 Group 6 db-test files missing their own terminal `ALL ... ASSERTIONS
--   PASSED` marker despite their own build logs citing it as evidence --
--   a documentation/test-file fix, applied directly to those files, not
--   this migration.
-- - Batch 3's own two disclosed-but-never-registered findings (zero test
--   coverage for the 9 new `/api/v1` REST route handlers; IAE-013's own
--   per-connector log-filter claim mismatch), and Phase 9's own total
--   absence of load/performance-test evidence at any declared target
--   volume (mirroring Phase 8's own `ISS-2026-141`) -- registered in
--   `docs/runtime/KNOWN_ISSUES.md`, no code change.
-- - `ISS-2026-146` (cross-tenant `tenant_id` disclosure via exception
--   message text) -- re-confirmed still accurate by the security lens, no
--   change needed to the entry itself.
--
-- ===========================================================================
-- Fix 1: app.get_enterprise_onboarding_checklist re-derives live on every read
-- ===========================================================================

create or replace function app.get_enterprise_onboarding_checklist(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns app.enterprise_onboarding_checklists
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_checklist app.enterprise_onboarding_checklists;
  v_dr_ok boolean;
  v_category text;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'SUP', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks SUP:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_checklist from app.enterprise_onboarding_checklists where tenant_id = p_tenant_id;
  if not found then
    return v_checklist;
  end if;

  -- IAE-036 Tier C fix (Integrated Verification): re-derive every automated
  -- item LIVE on every read, identical to the checks
  -- app.verify_onboarding_checklist_item already performs at write time --
  -- never trust the stored snapshot alone. This is a pure read-time
  -- correction: the row itself, and its own *_at confirmation timestamps,
  -- are never written back to here.
  v_checklist.sso_verified := exists(
    select 1 from app.integration_connections
    where tenant_id = p_tenant_id and adapter_code in ('enterprise_sso_oidc', 'enterprise_sso_saml') and status = 'active'
  );
  v_checklist.api_verified := exists(select 1 from app.api_keys where tenant_id = p_tenant_id and status = 'active');
  v_checklist.integrations_verified := exists(
    select 1 from app.integration_connections
    where tenant_id = p_tenant_id and status = 'active' and adapter_code not in ('enterprise_sso_oidc', 'enterprise_sso_saml')
  );

  v_dr_ok := true;
  foreach v_category in array array['database', 'secrets', 'backup', 'observability', 'jobs_integrations']
  loop
    if app.resolve_latest_dr_restore_status(p_tenant_id, v_category) is distinct from 'passed' then
      v_dr_ok := false;
    end if;
  end loop;
  v_checklist.dr_evidence_verified := v_dr_ok;

  v_checklist.support_entitlement_verified := exists(select 1 from app.support_entitlements where tenant_id = p_tenant_id);

  v_checklist.status := case when
      v_checklist.sso_verified
      and v_checklist.api_verified
      and v_checklist.integrations_verified
      and v_checklist.dr_evidence_verified
      and v_checklist.support_entitlement_verified
      and v_checklist.hypercare_plan_acknowledged
    then 'ready_for_production' else 'in_progress' end;

  return v_checklist;
end;
$$;

comment on function app.get_enterprise_onboarding_checklist is
  'IAE-035. IAE-036 Tier C fix (Integrated Verification): sso_verified/api_verified/integrations_verified/dr_evidence_verified/support_entitlement_verified and the overall status are re-derived LIVE on every read from the composed capabilities'' own current state, never trusted from the stored row alone -- fixes a live-reproduced one-way-ratchet staleness bug (revoking an already-verified SSO connection/API key/integration left the stored row, and therefore status=ready_for_production, silently wrong with zero explicit re-verify call). hypercare_plan_acknowledged and every *_at confirmation timestamp are still read from the stored row unchanged -- the human attestation has no independent live source of truth, and the timestamps remain real historical evidence of when each item was last explicitly confirmed, never retroactively falsified. app.verify_onboarding_checklist_item (the write path) is unaffected by this fix and continues to persist its own live recompute exactly as before.';

-- ===========================================================================
-- Fix 2: app.is_eta_prediction_enabled_for_tenant narrowed off authenticated
-- ===========================================================================

revoke execute on function app.is_eta_prediction_enabled_for_tenant(uuid) from authenticated;

-- ===========================================================================
-- Grants -- no new function, no new table; only the narrowing revoke above
-- and a create-or-replace of an unchanged signature (nothing to re-grant).
-- ===========================================================================

revoke execute on all functions in schema app from public;
