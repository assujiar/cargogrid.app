-- ISS-2026-138 (docs/runtime/KNOWN_ISSUES.md) -- RPD-023 (MFA/step-up-authorization)
-- disclosure practice was silently dropped for CPL-316-323 (all of Loyalty, including reward
-- approval and fraud release).
--
-- THE ENTRY'S OWN LOAD-BEARING PREMISE HAS CHANGED SINCE IT WAS WRITTEN. It says RPD-023 "has
-- never been built anywhere in this repository", so the fix was framed as documentation only.
-- That is no longer true: `20260807100000_create_intelligence_enterprise_mfa_session_controls.sql`
-- (IAE-027) built app.mfa_tenant_policies, app.mfa_step_up_challenges,
-- app.is_high_risk_action, app.request_mfa_step_up_challenge,
-- app.verify_mfa_step_up_challenge and app.assert_current_step_up_authorization, and
-- `20260830110000_harden_evaluate_permission_step_up_enforcement.sql` put a real step-up-deny
-- branch inside app.evaluate_permission itself -- the single chokepoint nearly every
-- permission-gated RPC in this repository already calls through.
--
-- app.is_high_risk_action classifies exactly SEVEN platform-default (module, action) tuples,
-- read live rather than assumed: (AI,Approve), (IAM,Configure), (SEC,Configure),
-- (SEC,Approve), (FIN,Approve), (HRS,Approve), (INTHUB,Configure). LYL is not one of them. So
-- app.decide_loyalty_redemption (reward approval) and app.decide_loyalty_fraud_review_case
-- (fraud release) -- the exact two actions this entry's own heading names -- sit outside the
-- step-up control even for a tenant that has turned MFA on, and app.request_mfa_step_up_challenge
-- raises mfa_step_up_not_required for the tuple, so a Loyalty admin cannot even voluntarily step
-- up. That is the real, current, closable gap -- narrower and sharper than the entry's own
-- disclosure-only framing, and it is what this migration closes.
--
-- WHY THIS IS ONE TUPLE ADDED TO THE CHOKEPOINT, NOT A NEW GATE INSIDE THE TWO FUNCTIONS.
-- The naive fix -- adding `perform app.assert_current_step_up_authorization(...)` inside
-- app.decide_loyalty_redemption/app.decide_loyalty_fraud_review_case directly -- is precisely
-- the shape CG-S14-IAE-037 shipped, broke 17 verified fixtures with (that helper ignores
-- tenant_wide_required and fires unconditionally), and reverted -- ISS-2026-151's entire
-- history. The chokepoint fix composes for free with the transition path ISS-2026-236 and
-- ISS-2026-151 already made closable: app.evaluate_permission only denies on a high-risk
-- action when the tenant's own app.mfa_tenant_policies.tenant_wide_required is true.
-- app.mfa_tenant_policies has ZERO rows on the live project today, so this migration changes
-- behaviour for exactly zero tenants and zero fixtures right now, while making the control
-- real and reachable the instant a tenant turns MFA on.
--
-- A REAL, DISCLOSED BEHAVIOURAL CONSEQUENCE, stated rather than left to be discovered:
-- `20260810600000_harden_loyalty_redemption_maker_checker.sql` uses
-- `(app.evaluate_permission(...,'LYL','Configure')).allowed` as a boolean PREDICATE inside
-- app.submit_loyalty_redemption's discount_voucher auto-compose branch, not as a hard gate. In
-- an MFA-enabled tenant with no current step-up, that branch will now fall back to
-- pending_approval rather than auto-composing. That is fail-closed and defensible -- an
-- unauthenticated-for-this-action caller getting a queued approval instead of an automatic
-- one -- and it only engages once a tenant has both turned MFA on AND classified LYL as
-- high-risk for itself, which nothing does today.
--
-- SCOPE, STATED HONESTLY RATHER THAN LEFT IMPLICIT. LYL:Configure gates roughly 27 call sites
-- across the Loyalty migration set (tier, points-ledger, reward-catalogue, redemption and
-- reconciliation configuration), not only the two named approvals -- classifying the tuple
-- covers all of them, and a verified step-up challenge (keyed on tenant/actor/module/action,
-- valid for tenant_wide_required policy's own step_up_max_age_minutes, default 15) covers a
-- work session rather than a single call. Narrower per-action granularity would need a new
-- LYL:Approve permission plus a role-version republish -- out of scope for this bounded fix.
-- Also explicitly out of scope, for the same reason ISS-2026-151 excluded
-- app.create_api_key: Phase 8's "privileged customer-admin" actions gate on
-- app.actor_is_active_customer_portal_account_admin, a principal/membership check with no
-- (module, action) shape app.is_high_risk_action can represent.
--
-- Signature kept byte-identical (CREATE OR REPLACE, not DROP + CREATE): public.is_high_risk_action
-- is a language-sql SECURITY DEFINER wrapper holding a real pg_depend edge on this function
-- (ISS-2026-260's own append-a-parameter trap does not apply here -- no parameter is added).
-- Body is the LIVE pg_get_functiondef output with exactly one tuple inserted into the
-- v_platform_default IN-list, not rebuilt from 20260807100000 -- rebuilding from a creating
-- migration is the trap 20260831270000's own header records nearly deleting five live
-- dispatcher branches.

create or replace function app.is_high_risk_action(p_tenant_id uuid, p_module_code text, p_action text)
returns boolean
language plpgsql
stable
security definer
set search_path to 'app', 'pg_temp'
as $function$
declare
  v_policy app.mfa_tenant_policies;
  v_platform_default boolean;
begin
  v_platform_default := (p_module_code, p_action) in (
    ('AI', 'Approve'), ('IAM', 'Configure'), ('SEC', 'Configure'), ('SEC', 'Approve'),
    ('FIN', 'Approve'), ('HRS', 'Approve'), ('INTHUB', 'Configure'), ('LYL', 'Configure')
  );
  if v_platform_default then
    return true;
  end if;

  select * into v_policy from app.mfa_tenant_policies where tenant_id = p_tenant_id;
  if not found then
    return false;
  end if;

  return exists (
    select 1 from jsonb_array_elements(v_policy.additional_high_risk_actions) as elem
    where elem ->> 'moduleCode' = p_module_code and elem ->> 'action' = p_action
  );
end;
$function$;

comment on function app.is_high_risk_action(uuid, text, text) is
  'ISS-2026-138: platform-default high-risk (module, action) classification for MFA step-up (RPD-023), consumed by app.evaluate_permission and app.request_mfa_step_up_challenge. Eight platform-default tuples: AI:Approve, IAM:Configure, SEC:Configure, SEC:Approve, FIN:Approve, HRS:Approve, INTHUB:Configure, LYL:Configure -- the last covers reward-approval and fraud-release decisions plus tier/points-ledger/reward-catalogue configuration, unconditionally true regardless of tenant policy, exactly like its seven siblings. A tenant may additionally classify any other (module, action) pair for itself via app.set_mfa_tenant_policy''s additional_high_risk_actions.';
