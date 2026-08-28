-- Track B Batch 6 (RLS/RBAC hardening) -- ISS-2026-186 partial fix.
--
-- ===========================================================================
-- Background: ISS-2026-186 re-derived
-- ===========================================================================
--
-- `ISS-2026-186` (`HDN-BLK-014`/`ISS-2026-179` carried forward) registered ~14 residual
-- `SECURITY DEFINER` boolean/scope-oracle primitives as "genuinely shared across
-- first-party and third-party actor call sites, cannot be fixed with the blind assert
-- pattern `20260810400000_harden_crm_ops_actor_identity_gaps.sql` used for the other 16"
-- -- and left all 14 unfixed pending "a per-call-site audit (which call sites are
-- self-referential vs. genuinely third-party)". That audit is what this migration does.
--
-- Re-deriving the entry's own named list against the CURRENT schema (a repo-wide grep of
-- every call site in `supabase/migrations/`, not the original static candidate sweep)
-- finds it is stale in two ways not previously caught:
--
--   1. `app.current_support_session` is NOT still open -- it was already one of the 16
--      fixed at `20260810400000_harden_crm_ops_actor_identity_gaps.sql` (that migration's
--      own header text names it explicitly, §3, as the one LANGUAGE sql exception to the
--      "15 of 16 are plpgsql" rule). It was carried into `ISS-2026-186`'s list by copying
--      forward `ISS-2026-179`'s original PRE-fix candidate list without removing the one
--      candidate that migration had already closed. No action needed here beyond noting
--      the correction (KNOWN_ISSUES.md text correction owed, not a code change).
--
--   2. Three of the remaining candidates -- `app.claim_case_record_scope_ok`, `app.
--      label_subject_record_scope_ok`, `app.wms_pick_record_scope_ok` -- have ZERO
--      third-party call sites anywhere in `supabase/migrations/`. Every one of the ~60
--      combined call sites across `advanced-tms-claim-incident-operations.sql`,
--      `advanced-tms-label-barcode-operations.sql`, `advanced-tms-wms-picking.sql`,
--      `advanced-tms-wms-packing.sql`, `advanced-tms-wms-outbound.sql`,
--      `advanced-tms-cycle-count-adjustment.sql`, `advanced-tms-warehouse-billing-
--      events.sql`, `create_customer_portal_ticket_linked_records.sql` and the Tier-C
--      hardening migrations that touch them passes either `p_actor_auth_user_id`
--      (straight pass-through of the CALLING function's own actor parameter, unmutated)
--      or `(select auth.uid())` (an RLS `using` clause, inherently self-referential).
--      `ISS-2026-186`'s own cited evidence for "genuinely third-party" (`p_owner_user_id`,
--      `p_recipient_auth_user_id`, `p_target_auth_user_id`) greps exclusively to `app.
--      has_active_tenant_membership` (and one `app.actor_holds_customer_user_layer` call)
--      -- never to any of these three. They match the EXACT criteria
--      `20260810400000`'s own header used to justify its 16: "self-referential: its actor
--      parameter names the caller itself, and at every internal call site ... that
--      parameter is passed straight through, unmutated". They were bundled into the ~14
--      by the original wide closure sweep without the individual per-candidate
--      verification `ISS-2026-179` itself disclosed was incomplete ("only 3 of ~24
--      spot-checked live... the remaining ~21 are statically identified... only").
--
-- Three further candidates on the list are a THIRD, distinct disposition, not "genuinely
-- shared" and not "newly fixable" -- they take NO actor parameter at all, so the
-- assert-actor-is-session-identity fix does not apply to their signature shape in the
-- first place: `app.pipeline_scope_org_unit_ids(p_org_unit_id uuid)`, `app.
-- evaluate_dispatch_readiness(p_shipment_order_id uuid)`, `app.
-- customer_warehouse_eligibility_active(p_tenant_id, p_warehouse_id, p_owner_account_id)`
-- (the last takes a customer ACCOUNT id, never an auth identity). No change needed or
-- possible here; `ISS-2026-186`'s "cannot be fixed with the blind assert pattern"
-- framing is technically imprecise for these three (there is no actor argument to bind),
-- though the practical conclusion -- not fixed by this pattern -- is unchanged.
--
-- `app.is_ticket_queue_member` also has zero third-party call sites in this same grep,
-- but is left untouched here: it already carries its own specific, independently-reasoned
-- "genuinely correct-by-design" disposition in `scripts/db-tests/rbac-enforcement.sql`
-- (the ATW-032 `v_expected` sweep, HRT-286's own comment) on DIFFERENT grounds -- the
-- boolean it discloses ("is employee X on queue Y") is already visible to any tenant
-- member via the separately, correctly-gated `app.list_ticket_queue_members` RPC, so a
-- forged actor discloses nothing incremental. Adding the assert here would be harmless
-- but is not a fix for a live gap; left as-is per that existing, reasoned disposition
-- rather than re-litigated.
--
-- The remaining six stay open, unchanged, confirmed still accurate by this same
-- call-site re-grep: `app.has_active_tenant_membership`, `app.can_access_record`, `app.
-- is_supreme_admin`, `app.actor_holds_customer_user_layer` (hundreds of combined
-- call sites, many genuinely third-party -- e.g. an invite/assignment/notification-
-- recipient flow checking ANOTHER identity's membership before granting them
-- something); `app.has_active_support_grant` (nested inside `app.
-- has_active_tenant_membership` itself with that function's own actor parameter, so it
-- inherits the same third-party-callable nature transitively); and `app.
-- resolve_locale_context` (granted directly to `anon`, so an unconditional assert would
-- break every anonymous locale-resolution call -- `auth.uid()` is NULL for anon and the
-- function's own `p_user_auth_user_id` is deliberately independent of session identity by
-- design, matching this repo's own pre-existing "anon-facing by design" exemption for it).
--
-- ===========================================================================
-- Fix: the exact `20260810400000` pattern, applied to the 3 genuinely self-referential
-- candidates only. Each function below is reproduced from its own current EFFECTIVE
-- definition -- byte-identical signature, return type, language, volatility, security
-- mode, search_path and body -- with exactly one line inserted. `app.
-- claim_case_record_scope_ok`/`app.wms_pick_record_scope_ok` are `LANGUAGE sql`
-- (no BEGIN block), so the assert is written as a non-final statement, its result
-- discarded, exactly mirroring `app.current_support_session`'s own already-shipped
-- convention (`20260810400000`, lines 731-749) rather than converting to plpgsql just to
-- gain one. `app.label_subject_record_scope_ok` is already `LANGUAGE plpgsql` and takes
-- the standard `perform app.assert_actor_is_session_identity(...)` form as its first
-- statement.
-- ===========================================================================

create or replace function app.claim_case_record_scope_ok(p_auth_user_id uuid, p_tenant_id uuid, p_operational_exception_id uuid)
returns boolean
language sql
stable
security definer
set search_path = app, pg_temp
as $$
  select app.assert_actor_is_session_identity(p_auth_user_id);
  select exists (
    select 1 from app.operational_exceptions oe
    join app.shipment_orders so on so.id = oe.shipment_order_id
    where oe.id = p_operational_exception_id
      and oe.tenant_id = p_tenant_id
      and app.can_access_record(p_auth_user_id, so.tenant_id, so.owner_user_id, app.lead_record_scope_org_unit_ids(so.org_unit_id), null)
  );
$$;

comment on function app.claim_case_record_scope_ok is
  'ATW-025, Track B Batch 6 (ISS-2026-186 partial fix): the single record-scope predicate every claim/incident RLS policy and RPC shares -- joins operational_exceptions -> shipment_orders and delegates to app.can_access_record, the exact template app.report_exception (OPS-174) already uses for the same underlying exception/shipment pair. Now asserts the claimed actor is the real session identity first (every call site across this schema passes its own caller''s actor parameter straight through, unmutated -- never a third party''s -- so this closes the ATW-031 forgery shape with no behavior change for any legitimate caller).';

create or replace function app.wms_pick_record_scope_ok(p_auth_user_id uuid, p_warehouse_id uuid, p_owner_account_ref text)
returns boolean
language sql
stable
security definer
set search_path = app, pg_temp
as $$
  select app.assert_actor_is_session_identity(p_auth_user_id);
  select coalesce((
    select app.can_access_record(p_auth_user_id, w.tenant_id, null, app.lead_record_scope_org_unit_ids(w.company_org_unit_id), p_owner_account_ref)
    from app.warehouses w
    where w.id = p_warehouse_id
  ), false);
$$;

comment on function app.wms_pick_record_scope_ok is
  'ATW-017, Track B Batch 6 (ISS-2026-186 partial fix): SECURITY DEFINER helper used by this schema''s own WMS pick/pack/outbound/cycle-count/billing-event RLS policies and RPCs -- resolves a warehouse''s tenant_id/company_org_unit_id and evaluates app.can_access_record against it while bypassing app.warehouses'' own RLS (which always passes p_customer_account_ref=null and therefore always denies a customer_user actor, even one who legitimately owns the outer row). Now asserts the claimed actor is the real session identity first (every call site across this schema passes its own caller''s actor parameter straight through, unmutated -- never a third party''s -- so this closes the ATW-031 forgery shape with no behavior change for any legitimate caller).';

create or replace function app.label_subject_record_scope_ok(
  p_actor_auth_user_id uuid,
  p_tenant_id uuid,
  p_subject_type text,
  p_subject_id uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_location app.warehouse_locations;
  v_warehouse app.warehouses;
  v_item app.item_masters;
  v_lot app.lot_identities;
  v_serial app.serial_identities;
  v_package app.wms_packages;
  v_task app.wms_pick_tasks;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if p_subject_type = 'bin' then
    select * into v_location from app.warehouse_locations where id = p_subject_id and tenant_id = p_tenant_id;
    if not found then
      return false;
    end if;
    select * into v_warehouse from app.warehouses where id = v_location.warehouse_id;
    return app.can_access_record(p_actor_auth_user_id, p_tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null);
  elsif p_subject_type = 'item' then
    select * into v_item from app.item_masters where id = p_subject_id and tenant_id = p_tenant_id;
    if not found then
      return false;
    end if;
    return app.actor_can_view_owner_scoped_row(p_actor_auth_user_id, p_tenant_id, v_item.owner_account_id);
  elsif p_subject_type = 'lot' then
    select * into v_lot from app.lot_identities where id = p_subject_id and tenant_id = p_tenant_id;
    if not found then
      return false;
    end if;
    return app.actor_can_view_owner_scoped_row(p_actor_auth_user_id, p_tenant_id, v_lot.owner_account_id);
  elsif p_subject_type = 'serial' then
    select * into v_serial from app.serial_identities where id = p_subject_id and tenant_id = p_tenant_id;
    if not found then
      return false;
    end if;
    return app.actor_can_view_owner_scoped_row(p_actor_auth_user_id, p_tenant_id, v_serial.owner_account_id);
  elsif p_subject_type in ('package', 'pallet') then
    select * into v_package from app.wms_packages where id = p_subject_id and tenant_id = p_tenant_id;
    if not found then
      return false;
    end if;
    return app.wms_pick_record_scope_ok(p_actor_auth_user_id, v_package.warehouse_id, v_package.owner_account_id::text)
      and app.actor_can_view_owner_scoped_row(p_actor_auth_user_id, p_tenant_id, v_package.owner_account_id);
  elsif p_subject_type = 'task' then
    select * into v_task from app.wms_pick_tasks where id = p_subject_id and tenant_id = p_tenant_id;
    if not found then
      return false;
    end if;
    return app.wms_pick_record_scope_ok(p_actor_auth_user_id, v_task.warehouse_id, v_task.owner_account_id::text)
      and app.actor_can_view_owner_scoped_row(p_actor_auth_user_id, p_tenant_id, v_task.owner_account_id);
  else
    return false;
  end if;
end;
$$;

comment on function app.label_subject_record_scope_ok is
  'ATW-021, Track B Batch 6 (ISS-2026-186 partial fix): the one shared record-scope dispatch app.print_label/app.reprint_label (via app.execute_label_print)/app.void_label/app.get_label_instance/app.resolve_label all call -- always re-reads the LIVE subject row, never the label''s own cached owner_account_id/warehouse_id. Now asserts the claimed actor is the real session identity first (every call site across this schema passes its own caller''s actor parameter straight through, unmutated -- never a third party''s -- so this closes the ATW-031 forgery shape with no behavior change for any legitimate caller).';

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit, directly-provable revoke of
-- PostgreSQL's PUBLIC-execute default, the standing per-migration convention since
-- PLT-118, applied here before any role-specific grant. Each grant below reproduces the
-- function's own currently-live grant statement verbatim -- same signature, same
-- grantees; CREATE OR REPLACE does not itself drop an existing grant, but this migration
-- follows the established convention of re-asserting it explicitly rather than relying on
-- that Postgres behavior implicitly.
revoke execute on all functions in schema app from public;

grant execute on function app.claim_case_record_scope_ok(uuid, uuid, uuid) to authenticated, service_role;
grant execute on function app.wms_pick_record_scope_ok(uuid, uuid, text) to authenticated, service_role;
grant execute on function app.label_subject_record_scope_ok(uuid, uuid, text, uuid) to authenticated, service_role;
