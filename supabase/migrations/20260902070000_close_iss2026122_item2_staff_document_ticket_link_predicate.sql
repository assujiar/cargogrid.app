-- ISS-2026-122 item 2 (CPL-313 disclosed boundary) -- gives
-- app._ticket_portal_link_resolve_candidate's 'document' branch a real
-- staff-facing document-access predicate, closing the "safe deny-by-default,
-- not yet a real staff capability" gap this entry's own text names.
--
-- Live-verified before writing anything (pg_get_functiondef, not the
-- migration files that originally created these): neither
-- app.check_file_action_authority (a coarse tenant-membership/supreme-admin/
-- customer-user-layer gate -- already widened since this entry's own last
-- re-verification to also admit customer_user, confirmed live) nor
-- app.authorize_file_access (a MUTATING, exception-raising function that
-- writes an app.file_access_logs row on every call) composes cleanly into a
-- read-only candidate-resolution predicate, exactly as this entry's own
-- 2026-09-01 update already found. What DOES compose cleanly, because it is
-- already the exact per-row authority logic app.authorize_file_access itself
-- calls internally (its own "record/sensitivity access gate"): app.
-- can_access_record (PLT-114, the real ownership/org-unit-sharing/customer-
-- account-ref predicate) plus the same restricted/credential classification
-- gate app.authorize_file_access applies. This migration factors that
-- READ-ONLY subset out into its own boolean predicate -- no log row, no
-- malware-scan/deleted-at gate (the calling WHERE clause already filters
-- lifecycle_status='active' and deleted_at is null, identically to the
-- customer branch beside it) -- and composes it with app.
-- check_file_action_authority for the coarse tenant-standing gate, mirroring
-- the exact shape the warehouse_order branch already uses one line above
-- (app.wms_pick_record_scope_ok + app.actor_can_view_owner_scoped_row,
-- gated by "not a customer_user" to keep the OR-arms mutually exclusive by
-- caller kind, not by outcome).
--
-- This is a mechanical composition of two already-existing, already-real
-- authority primitives, not new authority logic invented for this gap --
-- the C-25 concern this entry's own text raised against reusing the
-- files_select_scoped RLS policy (a second, independently-maintained copy of
-- the same rule) does not apply here, since app.can_access_record is a
-- single shared function both the RLS policy and app.authorize_file_access
-- already call, not a second implementation of it.

create or replace function app.staff_document_ticket_link_access_ok(
  p_actor_auth_user_id uuid,
  p_tenant_id uuid,
  p_uploaded_by_auth_user_id uuid,
  p_shared_org_unit_ids uuid[],
  p_customer_account_ref text,
  p_classification text
)
returns boolean
language sql
stable
security definer
set search_path = app, pg_temp
as $$
  select
    app.check_file_action_authority(p_tenant_id, p_actor_auth_user_id)
    and (
      p_uploaded_by_auth_user_id = p_actor_auth_user_id
      or app.can_access_record(p_actor_auth_user_id, p_tenant_id, p_uploaded_by_auth_user_id, p_shared_org_unit_ids, p_customer_account_ref)
    )
    and (
      p_classification not in ('restricted', 'credential')
      or p_uploaded_by_auth_user_id = p_actor_auth_user_id
      or app.is_supreme_admin(p_actor_auth_user_id)
      or app.is_support_grant_authority(p_actor_auth_user_id, p_tenant_id)
    );
$$;

comment on function app.staff_document_ticket_link_access_ok is
  'ISS-2026-122 item 2: the read-only subset of app.authorize_file_access''s own per-row authority logic (record/org-unit/customer-account-ref access plus the restricted/credential classification gate), factored out as a boolean predicate with no app.file_access_logs write -- so a candidate-search/resolve path can call it without logging a spurious access event per row scanned. Composed with app.check_file_action_authority for the coarse tenant-standing gate.';

grant execute on function app.staff_document_ticket_link_access_ok(uuid, uuid, uuid, uuid[], text, text) to service_role;

-- app._ticket_portal_link_resolve_candidate (CPL-313): CREATE OR REPLACE
-- against the CURRENT live body (confirmed identical to the original
-- migration's text for this function -- no intervening hardening pass has
-- touched it), restating language/stable/security definer/search_path
-- unchanged, mirroring 20260901130000's own established technique for
-- safely modifying an already-applied function without resetting an
-- omitted attribute (the ISS-2026-318 failure shape). Adds ONE new OR-arm
-- to the 'document' branch's WHERE clause -- the two existing customer
-- OR-arms (quote-request attachment, completed ePOD signature/photo) are
-- byte-identical, untouched. The warehouse_order branch is untouched.
create or replace function app._ticket_portal_link_resolve_candidate(p_entity_type text, p_tenant_id uuid, p_actor_auth_user_id uuid, p_entity_id uuid)
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

  if p_entity_type = 'warehouse_order' then
    return query
    select o.outbound_number, ('Outbound / ' || o.source_type), o.status
    from app.wms_outbound_orders o
    where o.id = p_entity_id and o.tenant_id = p_tenant_id
      and (
        (
          not app.actor_holds_customer_user_layer(o.tenant_id, p_actor_auth_user_id)
          and app.wms_pick_record_scope_ok(p_actor_auth_user_id, o.warehouse_id, o.owner_account_id::text)
          and app.actor_can_view_owner_scoped_row(p_actor_auth_user_id, o.tenant_id, o.owner_account_id)
        )
        or app.evaluate_customer_portal_inventory_access(p_actor_auth_user_id, o.tenant_id, o.warehouse_id, o.owner_account_id)
      );
  elsif p_entity_type = 'document' then
    return query
    select f.original_filename, f.mime_type, f.malware_scan_status
    from app.files f
    where f.id = p_entity_id and f.tenant_id = p_tenant_id
      and f.lifecycle_status = 'active' and f.deleted_at is null
      and (
        exists (
          select 1 from app.customer_portal_quote_requests r
          where r.id = f.record_id and f.record_type = 'customer_portal_quote_request' and r.tenant_id = p_tenant_id
            and r.account_id = any (app.resolve_customer_account_scope(p_actor_auth_user_id, p_tenant_id))
        )
        or exists (
          select 1
          from app.epod_captures ec
          join app.shipment_orders so on so.id = ec.shipment_order_id
          where f.record_type = 'shipment_order' and ec.shipment_order_id = f.record_id
            and ec.tenant_id = p_tenant_id and ec.is_latest_version and ec.status = 'completed'
            and (ec.signature_file_id = f.id or f.id = any (ec.photo_file_ids))
            and so.shipper_account_id = any (app.resolve_customer_account_scope(p_actor_auth_user_id, p_tenant_id))
        )
        or (
          not app.actor_holds_customer_user_layer(p_tenant_id, p_actor_auth_user_id)
          and app.staff_document_ticket_link_access_ok(p_actor_auth_user_id, p_tenant_id, f.uploaded_by_auth_user_id, f.shared_org_unit_ids, f.customer_account_ref, f.classification)
        )
      );
  end if;
  return;
end;
$$;

comment on function app._ticket_portal_link_resolve_candidate is
  'CPL-313 (design decisions 2/3/4), ISS-2026-122 item 2 (2026-09-02): returns AT MOST one row -- found iff the record exists, is tenant-scoped, AND the CURRENT caller independently passes that domain''s own real access predicate. warehouse_order composes app.wms_outbound_orders'' own real staff RLS predicate (mirrored verbatim) OR app.evaluate_customer_portal_inventory_access (CPL-309); document composes CPL-308''s own two real customer-only union-arms plus a real staff-only third arm (app.staff_document_ticket_link_access_ok, ISS-2026-122 item 2) -- a staff caller with real record/classification authority over the file can now resolve a document candidate, never merely by tenant membership alone.';

grant execute on function app._ticket_portal_link_resolve_candidate(text, uuid, uuid, uuid) to service_role;
