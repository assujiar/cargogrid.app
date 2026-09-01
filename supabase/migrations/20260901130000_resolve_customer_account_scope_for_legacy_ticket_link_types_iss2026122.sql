-- ISS-2026-122 item 4 -- the three PRE-EXISTING app.ticket_links entity types
-- (shipment/invoice/warehouse) remain on the legacy app.resolve_customer_owner_
-- account_scope, never CPL-300's widened app.resolve_customer_account_scope.
--
-- ===========================================================================
-- Re-verified live before writing this migration (against a disposable database
-- built from every migration up to and including 20260901100000), per the
-- entry's own recommended fix and this task's own instruction to check live
-- bodies, never on-disk migration files that may be stale.
-- ===========================================================================
--
-- app._ticket_link_resolve_candidate's and app.search_ticket_link_candidates's
-- LIVE bodies (both HRT-292, 20260731170000_create_ticket_linked_records.sql,
-- last touched by 20260801160000's own invoice-status-gate fix) still compose
-- exactly app.resolve_customer_owner_account_scope(p_actor_auth_user_id,
-- <tenant>) in the customer-owner-scope OR-branch of the 'shipment', 'invoice',
-- and 'warehouse' entity-type branches -- confirmed byte-for-byte against
-- pg_get_functiondef, not the migration file. No branch of either function
-- has drifted from that file since.
--
-- app.resolve_customer_account_scope(p_auth_user_id uuid, p_tenant_id uuid)
-- returns uuid[] -- the IDENTICAL signature as app.resolve_customer_owner_
-- account_scope, confirmed live -- so this is a genuine drop-in replacement,
-- not a reshape. It is also, by construction, a strict superset for any given
-- (actor, tenant): its own body unions the legacy marker (excluded only where
-- the new grant table already carries a row for that exact triple) with every
-- 'active' row in app.customer_portal_account_memberships (CPL-300). Swapping
-- the call therefore only ever ADDS visibility for accounts granted solely
-- through the newer table -- it cannot narrow what any existing caller already
-- sees through the legacy marker. app.resolve_customer_account_scope also
-- calls app.assert_actor_is_session_identity(p_auth_user_id) itself; every
-- caller that can reach these two functions' customer-owner-scope branch
-- (app.link_ticket_record, app.list_customer_ticket_links, app.list_ticket_
-- links, app.search_customer_ticket_link_candidates_precreate, and app.search_
-- ticket_link_candidates itself) already asserts the identical check on
-- p_actor_auth_user_id before ever reaching this branch -- confirmed live
-- against each of those five functions' own bodies -- so the extra assertion
-- inside the new resolver is redundant, not a new failure mode.
--
-- Scope note: the entry's own item 4 text names exactly three entity types
-- (shipment/invoice/warehouse). The sixth registry value's own 'customer'
-- branch (linking a ticket directly to the app.accounts row itself) also
-- composes the legacy resolver, but is a structurally different case -- not
-- named by this entry, not part of its own recommended fix, and out of this
-- migration's bounded scope; left untouched, exactly as found. 'vendor' and
-- 'user' never composed either resolver and are unaffected by this migration.
--
-- ===========================================================================
-- The fix
-- ===========================================================================
--
-- CREATE OR REPLACE FUNCTION against both functions, swapping ONLY
-- app.resolve_customer_owner_account_scope -> app.resolve_customer_account_
-- scope in the 'shipment'/'invoice'/'warehouse' branches. Every other line of
-- both bodies is byte-identical to the current live definition (itself
-- byte-identical to 20260801160000's own text) -- no other predicate, column,
-- ordering, or anti-enumeration shape is touched.
--
-- Mirrors 20260801160000_harden_customer_portal_ticket_link_invoice_status_
-- gate.sql's own technique for safely modifying these exact two HRT-292
-- functions: a full CREATE OR REPLACE FUNCTION restating every attribute
-- (`language plpgsql`, `stable` where the original has it, `security
-- definer`, `set search_path = app, pg_temp`, every parameter and default)
-- explicitly and unchanged, never a bare replace that omits one. Omitting any
-- of these on a bare CREATE OR REPLACE FUNCTION silently resets the attribute
-- to its default (`security invoker`, default search_path) -- a real,
-- previously-fixed recurrence in this exact codebase (ISS-2026-318, repaired
-- at 20260831290000_restore_security_definer_on_drifted_finance_wrappers.sql;
-- that migration's own header documents exactly this failure mode --
-- "replacing a function does not reliably reset its security attribute").
-- Neither function's parameter list changes at all, so this is not the C-29
-- added-parameter overload class either (RECURRING_DEFECT_TAXONOMY.md) --
-- confirmed post-migration below that exactly one overload of each exists.
--
-- No new GRANT/REVOKE statement is needed, mirroring 20260801160000's own
-- identical note: both functions are CREATE OR REPLACE on already-existing,
-- identical signatures -- PostgreSQL preserves the existing ACL across a
-- replace.
--
-- Regression coverage: scripts/db-tests/ticketing-linked-records.sql gains a
-- new section proving a customer_user whose ONLY grant to a second account
-- comes through app.customer_portal_account_memberships (CPL-300), never the
-- legacy customer_account_ref marker, can now see that account's shipment/
-- invoice/warehouse ticket-link candidates (previously invisible) through
-- both app._ticket_link_resolve_candidate (indirectly, via app.link_ticket_
-- record) and app.search_ticket_link_candidates directly -- while a second
-- fixture identity, scoped only via the legacy marker exactly as before,
-- continues to see its own candidates unchanged. The file's own protected
-- six-value registry assertion (line 254) is not touched.

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
        or so.shipper_account_id = any (app.resolve_customer_account_scope(p_actor_auth_user_id, so.tenant_id))
      );
  elsif p_entity_type = 'invoice' then
    return query
    select coalesce(fi.invoice_number, 'Draft ' || fi.id::text), (fi.currency || ' ' || fi.total_amount::text), fi.status
    from app.finance_invoices fi
    where fi.id = p_entity_id and fi.tenant_id = p_tenant_id
      and (
        app.check_finance_invoice_authority('View', fi.tenant_id, p_actor_auth_user_id)
        or (
          fi.customer_account_id = any (app.resolve_customer_account_scope(p_actor_auth_user_id, fi.tenant_id))
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
          select 1 from unnest(app.resolve_customer_account_scope(p_actor_auth_user_id, w.tenant_id)) as acct (account_id)
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
  'HRT-292 (decisions 1/3/4/6): returns AT MOST one row -- found iff the record exists, is tenant-scoped, AND the CURRENT caller independently passes that domain''s own real access predicate (decision 3, plus the composed customer-owner-scope branch of decision 4 for shipment/invoice/warehouse). No row is the SAME outward signal whether the id is forged, cross-tenant, deleted, or merely unauthorized for this caller (C-05) -- every caller (search/link/list/summary) treats "no row" identically, never distinguishing which. Tier C review fix (Batch 3 close, 20260801160000): the ''invoice'' branch''s customer-owner-scope arm now also requires status IN (''issued'', ''void'') -- CPL-311''s own business rule. ISS-2026-122 item 4 fix (20260901130000): the ''shipment''/''invoice''/''warehouse'' branches'' customer-owner-scope arms now compose app.resolve_customer_account_scope (CPL-300''s widened resolver, which is a strict superset of the legacy one) instead of app.resolve_customer_owner_account_scope -- a customer_user granted a second account only through app.customer_portal_account_memberships now sees that account''s candidates here too, matching what this checkpoint''s own newer app._ticket_portal_link_resolve_candidate (warehouse_order/document) already did from the start. The ''customer'' branch is unaffected -- out of this fix''s own named scope. The staff arm (app.check_finance_invoice_authority) is intentionally unfiltered by status -- real FIN:View authority still sees every lifecycle state.';

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
        or so.shipper_account_id = any (app.resolve_customer_account_scope(p_actor_auth_user_id, so.tenant_id))
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
          fi.customer_account_id = any (app.resolve_customer_account_scope(p_actor_auth_user_id, fi.tenant_id))
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
          select 1 from unnest(app.resolve_customer_account_scope(p_actor_auth_user_id, w.tenant_id)) as acct (account_id)
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
  'HRT-292 (decisions 5/7/8/9): bounded (default 20, capped 50) candidate search -- every row is independently authorized for THIS caller in the WHERE clause itself (never post-filtered), so an unauthorized candidate is never returned, never even as an empty placeholder (C-05). A tenant-data-view-gate failure (decision 5) returns zero rows AND durably logs search_denied inline (no RAISE, so the log survives -- decision 9). Tier C review fix (Batch 3 close, 20260801160000): the ''invoice'' branch''s customer-owner-scope arm now also requires status IN (''issued'', ''void''), mirroring app._ticket_link_resolve_candidate''s own identical fix. ISS-2026-122 item 4 fix (20260901130000): the ''shipment''/''invoice''/''warehouse'' branches'' customer-owner-scope arms now compose app.resolve_customer_account_scope instead of app.resolve_customer_owner_account_scope, mirroring app._ticket_link_resolve_candidate''s own identical fix -- a customer_user granted a second account only through app.customer_portal_account_memberships now sees that account''s candidates in this search too. The ''customer'' branch is unaffected -- out of this fix''s own named scope.';

-- Post-migration sanity: exactly one overload of each function (guards against
-- the C-29 added-parameter-overload class -- neither signature changed here,
-- but confirmed anyway since both functions are touched).
do $$
declare
  v_count integer;
begin
  select count(*) into v_count from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app' and p.proname = '_ticket_link_resolve_candidate';
  if v_count <> 1 then
    raise exception 'iss2026122_item4_overload_guard: expected exactly 1 overload of app._ticket_link_resolve_candidate, found %', v_count;
  end if;

  select count(*) into v_count from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app' and p.proname = 'search_ticket_link_candidates';
  if v_count <> 1 then
    raise exception 'iss2026122_item4_overload_guard: expected exactly 1 overload of app.search_ticket_link_candidates, found %', v_count;
  end if;
end $$;
