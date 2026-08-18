-- Tier C review of Phase 8 Batch 3 (Prompts 310-314, `CG-S13-CPL-012..016`)
-- -- closes a CRITICAL-severity defect the security/RLS review lens
-- live-reproduced: a `customer_user` could discover, and then durably link,
-- their own account's `draft`/`submitted`/`approved` invoice via the
-- ALREADY-APPLIED, unmodified HRT-292 typed-ticket-linked-records surface
-- (`app._ticket_link_resolve_candidate`/`app.search_ticket_link_candidates`,
-- `20260731170000_create_ticket_linked_records.sql`) -- defeating CPL-311's
-- own core Finance-visibility gate (`20260801120000_create_customer_portal_
-- invoice_billing_visibility.sql` design decision 4: "only status IN
-- ('issued', 'void') is portal-visible... draft/submitted/approved... must
-- never leak to a customer").
--
-- ===========================================================================
-- Independently re-derived before writing this fix (own reproduction, not
-- accepted from the lens report alone).
-- ===========================================================================
--
-- Direct read of `app._ticket_link_resolve_candidate`'s own `'invoice'`
-- branch (`20260731170000_create_ticket_linked_records.sql:370-378`) and
-- `app.search_ticket_link_candidates`'s own identical branch (same file,
-- lines 482-493) confirms both compose exactly:
--   app.check_finance_invoice_authority('View', fi.tenant_id, p_actor_auth_user_id)
--   or fi.customer_account_id = any (app.resolve_customer_owner_account_scope(p_actor_auth_user_id, fi.tenant_id))
-- with NO `fi.status` predicate anywhere in either function. Composed with
-- the ALREADY-VERIFIED, unmodified `app.link_ticket_record` (same file,
-- `create function`, not touched by this migration), any `customer_user`
-- holding a real `app.link_ticket_record`-callable ticket on their own
-- account can supply their own account's real draft/submitted/approved
-- invoice id directly (the RPC never validates that the id came from its own
-- search sibling) and receive a real, durable `app.ticket_links` row whose
-- `safe_snapshot` permanently captures
-- `coalesce(fi.invoice_number, 'Draft ' || fi.id::text)`/`currency + total_
-- amount`/`status` for that pre-issuance invoice -- readable thereafter by
-- both that customer (`app.list_customer_ticket_links`) and any ticket
-- staff (`app.list_ticket_links`).
--
-- Root cause: this is not a defect HRT-292 (Phase 7) introduced -- Finance
-- had ZERO customer-facing visibility rule of any kind at that time (CPL-311
-- itself is "the FIRST Finance-facing customer-portal RPC layer in Phase
-- 8"), so an unfiltered-by-status invoice branch was correct THEN. CPL-311
-- (this same batch, landed earlier) is what first establishes the
-- draft/submitted/approved-invisible-to-customer rule as a real security
-- boundary; this pre-existing, already-applied HRT-292 surface simply never
-- learned about it, and nothing in CPL-311's own bounded scope (a single
-- capability prompt) required it to retrofit a different phase's already-
-- applied migration -- CPL-311's own design decision 13 already disclosed a
-- narrower, related gap here (the scope RESOLVER staying on the legacy
-- `app.resolve_customer_owner_account_scope`) but did not catch this
-- separate, more severe STATUS gap. CPL-313 (this same batch, three files
-- later) is what newly exposes an additional customer-callable discovery
-- path onto the identical unfiltered predicate
-- (`app.search_customer_ticket_link_candidates_precreate`, fixed directly in
-- its own migration file,
-- `20260801140000_create_customer_portal_ticket_linked_records.sql`, design
-- decision 12) -- but the ACTUAL durable-write exploit path is, and always
-- was, `app.link_ticket_record` itself, which CPL-313 correctly never
-- edited (per its own explicit "never edit an applied migration" charter)
-- and which this migration alone closes.
--
-- ===========================================================================
-- Fix: `CREATE OR REPLACE FUNCTION` against both HRT-292 functions, adding
-- `and fi.status in ('issued', 'void')` to ONLY the customer-owner-scope
-- OR-branch of each -- never touching `20260731170000`'s own file (`AGENTS.
-- md` "never edit an applied migration"), mirroring this repository's own
-- established `harden_*_tierc.sql` pattern (e.g.
-- `20260731300000_harden_ticketing_customer_links_creator_role_hrt295_
-- tierc.sql`, itself a `CREATE OR REPLACE` against two of this SAME
-- migration's own functions for an unrelated Tier C fix).
-- ===========================================================================
--
-- The STAFF branch (`app.check_finance_invoice_authority('View', ...)`) is
-- deliberately left completely unfiltered by status -- staff with real
-- FIN:View authority must still see and link a draft/submitted/approved
-- invoice (that is real, intended, pre-issuance internal visibility, not a
-- leak); only the CUSTOMER-owner-scope branch gains the status filter, so a
-- customer sees and can link exactly the same invoice set CPL-311's own
-- `app.get_customer_portal_invoice`/`app.list_customer_portal_invoices`
-- already expose them -- never a wider or narrower set through this
-- different surface. Every other line of both functions is byte-identical
-- to `20260731170000`'s own body -- no other predicate, column, ordering, or
-- anti-enumeration shape is touched.
--
-- No new GRANT/REVOKE statement is needed (mirrors `20260731300000`'s own
-- identical note): both functions below are `CREATE OR REPLACE` on
-- already-existing, identical signatures -- PostgreSQL preserves the
-- existing ACL across a replace.
--
-- Regression coverage: `scripts/db-tests/ticketing-linked-records.sql`
-- (HRT-292's own protected test file) section 7 gains a new assertion
-- proving a real `customer_user` is denied (`record_not_eligible`, and
-- absent from `app.search_ticket_link_candidates`) linking their own
-- account's `draft` invoice via `app.link_ticket_record` -- the actual
-- exploited path -- while their own `issued` invoice remains linkable
-- exactly as before (the pre-existing fixture invoice, `INV-LNK-0001`, is
-- changed from `'approved'` to `'issued'` for this reason -- see that
-- section's own comment for why this does not weaken any other existing
-- assertion in the file). `scripts/db-tests/customer-complaint-ticket-
-- portal-wiring.sql` gains the analogous coverage for CPL-313's own sibling
-- fix in `app.search_customer_ticket_link_candidates_precreate`.

create or replace function app._ticket_link_resolve_candidate(p_entity_type text, p_tenant_id uuid, p_actor_auth_user_id uuid, p_entity_id uuid)
returns table (primary_label text, secondary_label text, status_label text)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
begin
  if not app._ticket_link_actor_may_view_tenant_data(p_tenant_id, p_actor_auth_user_id) then
    return;
  end if;

  if p_entity_type = 'shipment' then
    return query
    select so.shipment_number, (so.mode || ' / ' || so.service_type), so.status
    from app.shipment_orders so
    where so.id = p_entity_id and so.tenant_id = p_tenant_id
      and (
        app.can_access_record(p_actor_auth_user_id, so.tenant_id, so.owner_user_id, app.lead_record_scope_org_unit_ids(so.org_unit_id), null)
        or so.shipper_account_id = any (app.resolve_customer_owner_account_scope(p_actor_auth_user_id, so.tenant_id))
      );
  elsif p_entity_type = 'invoice' then
    return query
    select coalesce(fi.invoice_number, 'Draft ' || fi.id::text), (fi.currency || ' ' || fi.total_amount::text), fi.status
    from app.finance_invoices fi
    where fi.id = p_entity_id and fi.tenant_id = p_tenant_id
      and (
        app.check_finance_invoice_authority('View', fi.tenant_id, p_actor_auth_user_id)
        or (
          fi.customer_account_id = any (app.resolve_customer_owner_account_scope(p_actor_auth_user_id, fi.tenant_id))
          and fi.status in ('issued', 'void')
        )
      );
  elsif p_entity_type = 'warehouse' then
    return query
    select w.name, w.code, w.status
    from app.warehouses w
    where w.id = p_entity_id and w.tenant_id = p_tenant_id
      and (
        app.can_access_record(p_actor_auth_user_id, w.tenant_id, null, app.lead_record_scope_org_unit_ids(w.company_org_unit_id), null)
        or exists (
          select 1 from unnest(app.resolve_customer_owner_account_scope(p_actor_auth_user_id, w.tenant_id)) as acct (account_id)
          where app.customer_warehouse_eligibility_active(w.tenant_id, w.id, acct.account_id)
        )
      );
  elsif p_entity_type = 'vendor' then
    return query
    select vp.legal_name, coalesce(vp.trade_name, ''), vp.lifecycle_status
    from app.vendor_profiles vp
    where vp.master_record_id = p_entity_id and vp.tenant_id = p_tenant_id
      and (app.evaluate_permission(p_actor_auth_user_id, vp.tenant_id, 'PRC', 'View')).allowed;
  elsif p_entity_type = 'customer' then
    return query
    select a.legal_name, coalesce(a.trade_name, ''), a.status
    from app.accounts a
    where a.id = p_entity_id and a.tenant_id = p_tenant_id
      and (
        (app.has_active_tenant_membership(a.tenant_id, p_actor_auth_user_id) and not app.actor_holds_customer_user_layer(a.tenant_id, p_actor_auth_user_id))
        or app.is_supreme_admin(p_actor_auth_user_id)
        or a.id = any (app.resolve_customer_owner_account_scope(p_actor_auth_user_id, a.tenant_id))
      );
  elsif p_entity_type = 'user' then
    return query
    select u.display_name, null::text, u.status
    from app.users u
    where u.id = p_entity_id and u.tenant_id = p_tenant_id
      and app.has_active_tenant_membership(u.tenant_id, p_actor_auth_user_id)
      and not app.actor_holds_customer_user_layer(u.tenant_id, p_actor_auth_user_id);
  end if;
  return;
end;
$$;

comment on function app._ticket_link_resolve_candidate is
  'HRT-292 (decisions 1/3/4/6): returns AT MOST one row -- found iff the record exists, is tenant-scoped, AND the CURRENT caller independently passes that domain''s own real access predicate (decision 3, plus the composed customer-owner-scope branch of decision 4 for shipment/invoice/warehouse). No row is the SAME outward signal whether the id is forged, cross-tenant, deleted, or merely unauthorized for this caller (C-05) -- every caller (search/link/list/summary) treats "no row" identically, never distinguishing which. Tier C review fix (Batch 3 close, 20260801160000): the ''invoice'' branch''s customer-owner-scope arm now also requires status IN (''issued'', ''void'') -- CPL-311''s own business rule, established after this function was originally authored -- closing a live-reproduced path for a customer_user to durably link (and thereby permanently snapshot) their own account''s pre-issuance invoice. The staff arm (app.check_finance_invoice_authority) is intentionally unfiltered by status -- real FIN:View authority still sees every lifecycle state.';

create or replace function app.search_ticket_link_candidates(
  p_ticket_id uuid,
  p_entity_type text,
  p_search_text text,
  p_actor_auth_user_id uuid,
  p_limit integer default 20
)
returns table (entity_id uuid, primary_label text, secondary_label text, status_label text)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_ticket app.tickets;
  v_search text;
  v_limit integer;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_ticket from app.tickets where id = p_ticket_id;
  if not found or not app.can_access_ticket(p_ticket_id, p_actor_auth_user_id) then
    raise exception 'ticket_not_found: %', p_ticket_id using errcode = 'no_data_found';
  end if;

  if not (p_entity_type = any (app.ticket_link_entity_types())) then
    raise exception 'unsupported_entity_type: % is not a supported ticket link entity type', p_entity_type using errcode = 'check_violation';
  end if;

  if app.actor_holds_customer_user_layer(v_ticket.tenant_id, p_actor_auth_user_id) and not (p_entity_type = any (app.ticket_link_customer_safe_entity_types())) then
    raise exception 'entity_type_not_permitted: % is not a customer-permitted link type', p_entity_type using errcode = 'insufficient_privilege';
  end if;

  v_search := nullif(trim(coalesce(p_search_text, '')), '');
  v_limit := least(greatest(coalesce(p_limit, 20), 1), 50);

  if not app._ticket_link_actor_may_view_tenant_data(v_ticket.tenant_id, p_actor_auth_user_id) then
    insert into app.ticket_link_events (tenant_id, ticket_id, entity_type, event_type, reason, actor_auth_user_id, actor_label)
    values (v_ticket.tenant_id, p_ticket_id, p_entity_type, 'search_denied', 'no_tenant_data_access', p_actor_auth_user_id, null);
    return;
  end if;

  if p_entity_type = 'shipment' then
    return query
    select so.id, so.shipment_number, (so.mode || ' / ' || so.service_type), so.status
    from app.shipment_orders so
    where so.tenant_id = v_ticket.tenant_id
      and (v_search is null or so.shipment_number ilike '%' || v_search || '%')
      and (
        app.can_access_record(p_actor_auth_user_id, so.tenant_id, so.owner_user_id, app.lead_record_scope_org_unit_ids(so.org_unit_id), null)
        or so.shipper_account_id = any (app.resolve_customer_owner_account_scope(p_actor_auth_user_id, so.tenant_id))
      )
    order by so.updated_at desc
    limit v_limit;
  elsif p_entity_type = 'invoice' then
    return query
    select fi.id, coalesce(fi.invoice_number, 'Draft ' || fi.id::text), (fi.currency || ' ' || fi.total_amount::text), fi.status
    from app.finance_invoices fi
    where fi.tenant_id = v_ticket.tenant_id
      and (v_search is null or fi.invoice_number ilike '%' || v_search || '%')
      and (
        app.check_finance_invoice_authority('View', fi.tenant_id, p_actor_auth_user_id)
        or (
          fi.customer_account_id = any (app.resolve_customer_owner_account_scope(p_actor_auth_user_id, fi.tenant_id))
          and fi.status in ('issued', 'void')
        )
      )
    order by fi.updated_at desc
    limit v_limit;
  elsif p_entity_type = 'warehouse' then
    return query
    select w.id, w.name, w.code, w.status
    from app.warehouses w
    where w.tenant_id = v_ticket.tenant_id
      and (v_search is null or w.name ilike '%' || v_search || '%' or w.code ilike '%' || v_search || '%')
      and (
        app.can_access_record(p_actor_auth_user_id, w.tenant_id, null, app.lead_record_scope_org_unit_ids(w.company_org_unit_id), null)
        or exists (
          select 1 from unnest(app.resolve_customer_owner_account_scope(p_actor_auth_user_id, w.tenant_id)) as acct (account_id)
          where app.customer_warehouse_eligibility_active(w.tenant_id, w.id, acct.account_id)
        )
      )
    order by w.updated_at desc
    limit v_limit;
  elsif p_entity_type = 'vendor' then
    return query
    select vp.master_record_id, vp.legal_name, coalesce(vp.trade_name, ''), vp.lifecycle_status
    from app.vendor_profiles vp
    where vp.tenant_id = v_ticket.tenant_id
      and (v_search is null or vp.legal_name ilike '%' || v_search || '%')
      and (app.evaluate_permission(p_actor_auth_user_id, vp.tenant_id, 'PRC', 'View')).allowed
    order by vp.updated_at desc
    limit v_limit;
  elsif p_entity_type = 'customer' then
    return query
    select a.id, a.legal_name, coalesce(a.trade_name, ''), a.status
    from app.accounts a
    where a.tenant_id = v_ticket.tenant_id
      and (v_search is null or a.legal_name ilike '%' || v_search || '%')
      and (
        (app.has_active_tenant_membership(a.tenant_id, p_actor_auth_user_id) and not app.actor_holds_customer_user_layer(a.tenant_id, p_actor_auth_user_id))
        or app.is_supreme_admin(p_actor_auth_user_id)
        or a.id = any (app.resolve_customer_owner_account_scope(p_actor_auth_user_id, a.tenant_id))
      )
    order by a.updated_at desc
    limit v_limit;
  elsif p_entity_type = 'user' then
    return query
    select u.id, u.display_name, null::text, u.status
    from app.users u
    where u.tenant_id = v_ticket.tenant_id
      and (v_search is null or u.display_name ilike '%' || v_search || '%')
      and app.has_active_tenant_membership(u.tenant_id, p_actor_auth_user_id)
      and not app.actor_holds_customer_user_layer(u.tenant_id, p_actor_auth_user_id)
    order by u.updated_at desc
    limit v_limit;
  end if;
end;
$$;

comment on function app.search_ticket_link_candidates is
  'HRT-292 (decisions 5/7/8/9): bounded (default 20, capped 50) candidate search -- every row is independently authorized for THIS caller in the WHERE clause itself (never post-filtered), so an unauthorized candidate is never returned, never even as an empty placeholder (C-05). A tenant-data-view-gate failure (decision 5) returns zero rows AND durably logs search_denied inline (no RAISE, so the log survives -- decision 9). Tier C review fix (Batch 3 close, 20260801160000): the ''invoice'' branch''s customer-owner-scope arm now also requires status IN (''issued'', ''void''), mirroring app._ticket_link_resolve_candidate''s own identical fix -- a customer_user no longer sees their own account''s draft/submitted/approved invoice in this search, matching CPL-311''s own business rule.';
