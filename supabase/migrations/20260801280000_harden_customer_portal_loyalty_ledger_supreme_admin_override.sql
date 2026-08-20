-- Phase 8 Customer Portal and Loyalty (CPL-325, CG-S13-CPL-027, Prompt 325,
-- "Customer Portal and Loyalty Privacy Integrity Hardening") -- explicit
-- ruling on ISS-2026-130 (docs/runtime/KNOWN_ISSUES.md) and the
-- 06_RLS_RBAC_WORKSTREAM.md sec.8/sec.13 tension CPL-324's own build log
-- (sec.10) instructed this checkpoint to resolve rather than let severity
-- alone decide.
--
-- RULING (read verbatim from docs/architecture/06_RLS_RBAC_WORKSTREAM.md,
-- not accepted from any prior batch's own paraphrase, before deciding):
--  - sec.8 (RPD-022, binding): "Supreme Admin has absolute CRUD... This is
--    implemented as a distinct RLS policy on every append_only_ledger-family
--    table (sec.4) that grants UPDATE/DELETE to the Supreme Admin role
--    specifically, alongside (not instead of) the normal-role policy that
--    denies it."
--  - sec.13 (Release blockers): "Every append_only_ledger table must have
--    its Supreme-Admin-exception policy tested (test #8/#9) before that
--    table's phase closes."
--
-- Phase 8 has NOT closed yet -- only Prompt 327 may set PHASE_8_VERIFIED
-- (source spec sec.36; CPL-324's own header states it explicitly reserved
-- PHASE_8_VERIFIED for Prompt 327) -- so sec.13's own literal text is a
-- live, applicable gate for Phase 8's own 5 append_only_ledger-family
-- tables RIGHT NOW, not a stale historical concern to reason away.
--
-- DECISION: option (a) -- build the mechanism now, mirroring
-- supabase/migrations/20260729180000_create_finance_posted_journal_
-- integrity.sql's own FIN-204 app.is_supreme_admin-gated trigger-based
-- exception, scoped to Phase 8's own 5 append_only_ledger-family tables
-- ONLY: app.loyalty_earning_events, app.loyalty_point_ledger_entries,
-- app.loyalty_benefit_entitlement_events, app.loyalty_reward_stock_
-- reservations, app.loyalty_redemption_events. Deliberately does NOT
-- retroactively touch app.inventory_movements (a pre-existing, already-
-- VERIFIED Phase 5 ledger with the identical gap -- ISS-2026-130's own
-- disclosed "mitigating context") or any other append_only_ledger-family
-- table outside Phase 8. This checkpoint's own charter has the authority to
-- make this decision for Phase 8's own tables specifically (the
-- orchestrating task's own explicit grant); a repository-wide sweep of
-- app.inventory_movements and any other pre-Phase-8 ledger remains a future,
-- dedicated cross-cutting task, exactly as ISS-2026-130's own original
-- disclosure named it -- not something this migration decides unilaterally
-- for tables it does not own.
--
-- WHY NOW, NOT DEFERRED A THIRD TIME: this checkpoint's own charter (unlike
-- CPL-324's verification-only one) explicitly names "repair" a first-class
-- deliverable (source spec sec.21: "Hardening attacks and repairs the
-- highest-risk portal and loyalty paths"), and this fix is small, additive,
-- and mirrors an ALREADY-established, already-tested repository pattern
-- (FIN-204) rather than inventing new design -- squarely "minimal
-- registered defect repair" (source spec sec.13), never new capability
-- (forbidden, sec.12). Deferring again, with Phase 8's own closure prompt
-- (327) only two prompts away, would let sec.13's own literal
-- release-blocker text lapse into "phase closed with a known gate still
-- failing" -- exactly what CPL-324 sec.10 instructed this checkpoint not to
-- let happen by severity-only reasoning.
--
-- Unlike FIN-204's own finance_journals/finance_journal_lines (a table with
-- a mutable pre-posted lifecycle, so the guard is conditional on
-- status = 'posted'), every row in these 5 tables is immutable from the
-- moment of INSERT -- there is no pre-ledger mutable state to permit. One
-- shared, generic trigger function (rather than 5 near-duplicated
-- FIN-204-shaped functions) is therefore the correct, minimal
-- generalization -- every one of the 5 tables already carries a direct
-- tenant_id column (grep-confirmed against each CREATE TABLE statement:
-- 20260801180000, 20260801200000, 20260801210000, 20260801220000,
-- 20260801230000), so one function keyed off TG_TABLE_NAME/OLD.tenant_id/
-- OLD.id covers all five without per-table duplication.
--
-- Baseline protection, already real (disclosed, not rebuilt here): none of
-- the 5 tables grants UPDATE/DELETE to `authenticated` anywhere in this
-- repository (grep-confirmed) -- a normal-role direct-table mutation is
-- already structurally impossible; every real mutation is a service_role-
-- only, authority-checked function call (the identical repository-wide
-- convention FIN-204's own header cites). What was MISSING, and what this
-- migration adds, is the Supreme Admin override itself: today, even
-- service_role holds no UPDATE/DELETE grant on any of these 5 tables at
-- all (grep-confirmed: each table's own migration grants only `select,
-- insert` to service_role), so a Supreme Admin has literally no path to
-- exercise RPD-022's own disclosed absolute-CRUD exception today -- not
-- merely a denied path, an ungranted one. This migration additively grants
-- UPDATE/DELETE to service_role (the only role any real correction would
-- ever run as, per this repository's own SECURITY DEFINER-only-mutation
-- convention) and installs a BEFORE UPDATE/DELETE trigger on each table
-- that blocks the mutation outright unless app.is_supreme_admin(auth.uid())
-- is true, in which case it permits the mutation and captures a
-- best-effort app.capture_audit_event row disclosing the bypass -- a
-- detective control, never a preventive guarantee against a Supreme Admin
-- who also controls the database directly, per sec.8's own disclosed
-- RISK-004 residual-risk framing (never claim tamper-proof or
-- immutable-for-all, RPD-022/RPD-034).
--
-- Correction path for a normal role: unchanged -- every one of these 5
-- tables already has its own established "correction is a NEW, linked row"
-- convention (corrects_event_id / corrects_entry_id, or a new
-- status-transition event row), documented on each table's own `comment on
-- table`. This migration does not alter that path; it only adds the
-- disclosed, structurally-gated exception for a genuine Supreme Admin
-- correction of already-posted history, mirroring FIN-204 exactly.
--
-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): this migration carries
-- its own explicit `revoke execute on all functions in schema app from
-- public` statement before its final grants, the standing per-migration
-- convention since PLT-118.

-- ===========================================================================
-- 1. app.protect_loyalty_ledger_append_only -- one shared BEFORE UPDATE/
--    DELETE trigger function for all 5 Phase 8 append_only_ledger-family
--    tables. Every row is immutable from INSERT (no "posted" gate needed,
--    unlike FIN-204's own finance_journals) -- blocks unconditionally unless
--    the acting identity holds a live supreme_admin principal membership.
-- ===========================================================================

create function app.protect_loyalty_ledger_append_only()
returns trigger
language plpgsql
as $$
declare
  v_actor uuid := auth.uid();
begin
  if not app.is_supreme_admin(v_actor) then
    raise exception 'loyalty_ledger_append_only_immutable: normal roles cannot % row % of append-only %.% -- record a new, linked correction row instead (corrects_event_id/corrects_entry_id or a new status-transition event row)', lower(TG_OP), OLD.id, TG_TABLE_SCHEMA, TG_TABLE_NAME
      using errcode = 'insufficient_privilege';
  end if;

  perform app.capture_audit_event(
    OLD.tenant_id, v_actor, 'supreme_admin_absolute_crud', lower(TG_OP) || '_append_only_loyalty_ledger_row',
    TG_TABLE_SCHEMA || '.' || TG_TABLE_NAME, OLD.id, 'success',
    'RPD-022 absolute-CRUD exception invoked (best-effort evidence, not a preventive control) -- ' || TG_TABLE_NAME || ' is otherwise a fully append-only ledger',
    to_jsonb(OLD), case when TG_OP = 'DELETE' then null else to_jsonb(NEW) end
  );

  if TG_OP = 'DELETE' then
    return OLD;
  end if;
  return NEW;
end;
$$;

comment on function app.protect_loyalty_ledger_append_only is
  'CPL-325 (ISS-2026-130 ruling, option (a)): shared BEFORE UPDATE/DELETE guard for all 5 Phase 8 append_only_ledger-family tables. Blocks any mutation unless app.is_supreme_admin(auth.uid()) -- a detective, best-effort-evidenced RPD-022 exception, never a tamper-proof claim. Scoped to Phase 8''s own 5 tables only -- does NOT retroactively cover app.inventory_movements or any other pre-existing append_only_ledger-family table (disclosed, out of this checkpoint''s own authority -- see this migration''s own header).';

create trigger loyalty_earning_events_protect_append_only
  before update or delete on app.loyalty_earning_events
  for each row
  execute function app.protect_loyalty_ledger_append_only();

create trigger loyalty_point_ledger_entries_protect_append_only
  before update or delete on app.loyalty_point_ledger_entries
  for each row
  execute function app.protect_loyalty_ledger_append_only();

create trigger loyalty_benefit_entitlement_events_protect_append_only
  before update or delete on app.loyalty_benefit_entitlement_events
  for each row
  execute function app.protect_loyalty_ledger_append_only();

create trigger loyalty_reward_stock_reservations_protect_append_only
  before update or delete on app.loyalty_reward_stock_reservations
  for each row
  execute function app.protect_loyalty_ledger_append_only();

create trigger loyalty_redemption_events_protect_append_only
  before update or delete on app.loyalty_redemption_events
  for each row
  execute function app.protect_loyalty_ledger_append_only();

-- ===========================================================================
-- 2. Grants -- additive UPDATE/DELETE on service_role only (the only role
--    any real correction runs as, per this repository's SECURITY DEFINER-
--    only-mutation convention); authenticated gets nothing, unchanged.
--    Without this grant, the trigger above is unreachable -- Postgres denies
--    the UPDATE/DELETE at the grant level before the trigger ever fires, and
--    a genuine Supreme Admin would have NO path to exercise RPD-022's own
--    disclosed exception (today's actual gap, per ISS-2026-130).
-- ===========================================================================

grant update, delete on app.loyalty_earning_events to service_role;
grant update, delete on app.loyalty_point_ledger_entries to service_role;
grant update, delete on app.loyalty_benefit_entitlement_events to service_role;
grant update, delete on app.loyalty_reward_stock_reservations to service_role;
grant update, delete on app.loyalty_redemption_events to service_role;

-- Per ERR-2026-004: explicit, directly-provable revoke of PostgreSQL's
-- PUBLIC-execute default, applied before any role-specific grant below.
revoke execute on all functions in schema app from public;

grant execute on function app.protect_loyalty_ledger_append_only() to service_role;

-- app.is_supreme_admin (PLT-113) was previously granted to `authenticated`
-- only (RLS-policy caller context); this trigger's own body calls it while
-- running under whichever role performs the direct table mutation --
-- service_role in every real deployment. Additive grant only; app.is_
-- supreme_admin's own function body is untouched (identical to FIN-204's
-- own precedent, 20260729180000, lines 148-154).
grant execute on function app.is_supreme_admin(uuid) to service_role;

-- This migration's own trigger function calls auth.uid() directly (to
-- capture the acting identity for RPD-022 evidence) -- needs real USAGE on
-- schema auth for whichever role performs the table mutation -- service_role
-- in every real deployment (identical to FIN-204's own precedent, lines
-- 156-167).
grant usage on schema auth to service_role;
