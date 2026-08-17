-- Phase 8 (Customer Portal and Loyalty) capability CG-S13-CPL-015 (Complaint
-- and Ticket, Prompt 313). Builds on the already-VERIFIED HRT-287 customer
-- ticket channel (20260731080000), HRT-289 SLA (20260731120000), and HRT-292
-- Typed Ticket-Linked Records (20260731170000_create_ticket_linked_records.sql)
-- -- reuses app.can_access_ticket/app.is_ticket_staff/app._is_ticket_
-- requester_party/app._ticket_link_actor_may_view_tenant_data/app.
-- assert_actor_is_session_identity/app.actor_holds_customer_user_layer
-- verbatim, never re-derived. Also composes CPL-300's app.resolve_customer_
-- account_scope, CPL-309's app.evaluate_customer_portal_inventory_access, and
-- CPL-308's own two real document-source predicates (quote_request/epod)
-- inline (mirrored, not called -- see design note 3 below for why).
--
-- =========================================================================
-- WHY A NEW TABLE/RPC FAMILY, NOT A WIDENED app.ticket_links (the source
-- prompt's own first-suggested shape) -- discovered, not assumed.
-- =========================================================================
--
-- The source prompt's own research suggested widening app.ticket_links.
-- entity_type's CHECK constraint (DROP+ADD, the sanctioned HRT-275-style
-- non-destructive widening) to add 'warehouse_order'/'document' alongside
-- the existing six values. Direct inspection BEFORE writing any code found
-- this is foreclosed by a real, already-applied, PROTECTED test file:
-- scripts/db-tests/ticketing-linked-records.sql line 254 hard-asserts
-- `app.ticket_link_entity_types() = array['shipment','invoice','warehouse',
-- 'vendor','customer','user']` verbatim ("FAIL: ... drifted from the
-- documented six-value registry" on any other result), and
-- server/contracts/ticketing/ticketing.test.ts line 630 hard-asserts the
-- identical six-value list for the TS-side `TICKET_LINK_ENTITY_TYPES`
-- constant. Both are existing, already-passing test files this task's own
-- instructions forbid deleting OR modifying. Widening the shared registry
-- would make both fail -- a real regression, not a cosmetic one, and not an
-- acceptable trade for landing this capability. This migration therefore
-- leaves app.ticket_links, app.ticket_link_events, app.ticket_link_entity_
-- types(), app.ticket_link_customer_safe_entity_types(),
-- app._ticket_link_resolve_candidate, app.search_ticket_link_candidates,
-- app.link_ticket_record, app.unlink_ticket_record, and app.list_ticket_
-- links COMPLETELY UNTOUCHED -- zero `alter table`, zero `create or replace
-- function` against any of them anywhere in this file (grep-verifiable).
--
-- Instead, this migration adds a genuinely new, small, PARALLEL table +
-- RPC family (app.ticket_portal_links) scoped to exactly the two entity
-- types the orchestrating task named that the existing registry cannot
-- reach at the right granularity: 'warehouse_order' (app.wms_outbound_
-- orders, CPL-310's own canonical outbound-order table -- structurally
-- different from the EXISTING 'warehouse' entity type, which resolves to
-- app.warehouses, the facility master record, confirmed by direct read of
-- app._ticket_link_resolve_candidate's actual body before writing a line of
-- this migration, per the orchestrating task's own explicit instruction to
-- check) and 'document' (app.files rows reachable through CPL-308's own two
-- real customer document sources -- quote-request attachment, ePOD
-- evidence -- which the existing six-value registry has never carried at
-- all). 'shipment' and 'invoice' need NO new plumbing -- both are ALREADY
-- in the existing registry AND already in app.ticket_link_customer_safe_
-- entity_types(), confirmed by direct read before writing this migration;
-- this capability's own picker composes the EXISTING app.search_ticket_
-- link_candidates/app.link_ticket_record for those two types unchanged, and
-- ONLY this migration's own new functions for warehouse_order/document.
--
-- Design decisions, disclosed rather than left implicit:
--
-- 1. **A real, CHECK-constrained, small registry, mirroring app.ticket_
--    links' own shape exactly (structure, not values) -- app.ticket_portal_
--    links.entity_type is CHECK-constrained to exactly ('warehouse_order',
--    'document'); app.ticket_portal_link_entity_types() is the SQL-level
--    registry mirror, kept set-equal with the CHECK constraint by this
--    migration's own db-test.** entity_id carries no foreign key (the two
--    types reference two different source tables) -- referential validity
--    is proven live, every read, by app._ticket_portal_link_resolve_
--    candidate, mirroring app._ticket_link_resolve_candidate's own
--    established discipline byte-for-byte.
-- 2. **'warehouse_order' composes REAL, existing predicates, both staff and
--    customer branches -- never re-derived.** Staff branch mirrors app.
--    wms_outbound_orders' own RLS SELECT policy verbatim (`not app.
--    actor_holds_customer_user_layer(...) and app.wms_pick_record_scope_ok
--    (...) and app.actor_can_view_owner_scoped_row(...)`, confirmed by
--    direct read of 20260730311000_harden_customer_inventory_access_rls_
--    isolation.sql before writing this branch). Customer branch reuses
--    app.evaluate_customer_portal_inventory_access (CPL-309) verbatim --
--    the SAME gate app.get_customer_portal_outbound_order (CPL-310) already
--    uses for the identical table, so a candidate this migration's own
--    search surfaces to a customer is ALWAYS the same candidate CPL-310's
--    own detail page would also show them (no divergent scope between the
--    two capabilities).
-- 3. **'document' composes app.customer_portal_quote_requests/app.epod_
--    captures/app.shipment_orders directly, mirroring app.list_customer_
--    documents' (CPL-308) own two real union-arm predicates inline --
--    deliberately NOT calling app.list_customer_documents or app.get_
--    customer_document.** Calling app.get_customer_document as a
--    reauthorization primitive was considered and rejected: that function's
--    own design decision 5 (20260801090000) always writes a durable app.
--    file_access_logs GRANTED/DENIED row on every call, semantically
--    meaning "this document was accessed/downloaded" -- calling it merely
--    to validate a link candidate (search, or a link-time re-check) would
--    fabricate false "access" audit rows for documents nobody actually
--    opened. Calling app.list_customer_documents was also rejected: its own
--    signature has no p_search_text/p_document_id single-row lookup
--    parameter, and widening it would require DROP+CREATE against an
--    already-`VERIFIED` capability's own function purely to serve this
--    one -- out of this task's own bounded scope. Inlining the SAME two
--    real predicates (never a third, independently-invented one) mirrors
--    exactly how app._ticket_link_resolve_candidate/app.search_ticket_
--    link_candidates ALREADY duplicate each of their own six domain
--    predicates between "get one" and "search many" today -- the
--    established convention in this exact file family, not a new pattern.
-- 4. **'document' is customer-portal-only by design, disclosed, not
--    silent.** No staff-facing document-browse/access predicate exists
--    anywhere in this repository (CPL-308's own design decision 4/§9
--    residual-limitations line, confirmed by direct read: "Neither app.
--    check_file_action_authority nor app.authorize_file_access is
--    composed"). app._ticket_portal_link_resolve_candidate's 'document'
--    branch therefore has no staff OR-branch at all -- a staff caller
--    selecting 'document' sees zero candidates, always (safe deny-by-
--    default, not a security gap), never a fabricated result. Recorded as
--    a new KNOWN_ISSUES entry (ISS-2026-122) for a future capability that
--    might build a staff document-browse predicate to compose here.
-- 5. **Both scope resolvers used are the WIDENED CPL-300 resolver (app.
--    resolve_customer_account_scope), consistently, in EVERY new function
--    this migration adds (resolve_candidate, both search variants) -- never
--    the legacy app.resolve_customer_owner_account_scope the PRE-EXISTING
--    app.ticket_links entity types (shipment/invoice/warehouse) still use.**
--    Disclosed explicitly: this makes the two NEW entity types
--    ISS-2026-117-clean from their very first line (a customer_portal user
--    granted a second account ONLY through CPL-300's new grant table sees
--    their own warehouse orders/documents correctly through this
--    migration's own functions), while the three PRE-EXISTING app.ticket_
--    links entity types (shipment/invoice/warehouse) remain on the OLD
--    resolver -- a real, pre-existing gap in a file this task does not own
--    and may not edit (app.ticket_links is HRT-292, Phase 7, already
--    VERIFIED). Recorded as a new KNOWN_ISSUES entry (ISS-2026-122) rather
--    than silently carried forward or silently fixed out of scope.
-- 6. **Pre-creation search has no per-attempt audit-ledger entry --
--    structural, not an oversight.** app.ticket_link_events.ticket_id (the
--    ledger the ORIGINAL HRT-292 capability uses) is NOT NULL by design,
--    and this migration deliberately does not touch that table (see the
--    "why a new table" note above) or invent a second ledger table of its
--    own for the SAME reason app.ticket_portal_links itself stays lean --
--    the row's own created_by/removed_by/removed_reason/timestamps/record_
--    version already carry real, queryable history for every ticket-scoped
--    link/unlink this migration's own app.link_ticket_portal_record/app.
--    unlink_ticket_portal_record perform. The ONE genuinely new gap this
--    introduces: a pre-creation SEARCH (before any ticket exists) has
--    nowhere to durably log a denial, since no ticket_id exists yet to
--    scope a ledger row to. Once the ticket is created and app.link_ticket_
--    portal_record is actually called, that IS captured, on the row itself
--    (create_by/created_at) -- only the earlier, ticket-less "did this
--    person try to link something they were not allowed to see" moment
--    goes unrecorded. Low-risk (search itself is deny-by-default and
--    returns nothing an unauthorized caller could act on) and disclosed as
--    part of the same ISS-2026-122 entry, not hidden.
-- 7. **Anti-enumeration (C-05) mirrors app.link_ticket_record exactly** --
--    app._ticket_portal_link_resolve_candidate collapses "nonexistent,"
--    "cross-tenant," "deleted/soft-deleted," and "exists but unauthorized
--    for THIS caller" into ONE outward `record_not_eligible` at link time,
--    checked BEFORE the duplicate-link short-circuit (the identical
--    ordering app.link_ticket_record's own decision 3 -- and its own
--    self-found ordering defect -- already established as correct).
-- 8. **Idempotency (C-01/C-02): a real partial unique index on (ticket_id,
--    entity_type, entity_id) where status='active', backed by a real
--    `exception when unique_violation` handler in app.link_ticket_portal_
--    record** -- not merely a pre-check SELECT, mirrors app.link_ticket_
--    record's own established shape verbatim.
-- 9. **Every actor-taking function calls app.assert_actor_is_session_
--    identity as its own literal first statement** -- the batch's own
--    single most common Critical defect class, applied from the first
--    draft, never relying on a transitive check inside a composed helper.
-- 10. **RLS is staff-only (customer_user excluded) on the new raw table --
--    every genuine customer read goes through the SECURITY DEFINER RPCs
--    below, never a raw-table grant.** Mirrors app.ticket_links' own
--    established policy shape verbatim (`app.can_access_ticket(ticket_id)
--    and not app.actor_holds_customer_user_layer(tenant_id)) or app.
--    is_supreme_admin()`).
-- 11. Per `ERR-2026-004` (`docs/runtime/ERROR_LEDGER.md`): this migration
--    carries its own explicit `revoke execute on all functions in schema
--    app from public` statement before its final grants.
-- 12. **Tier C review fix (batch close): app.search_customer_ticket_link_
--    candidates_precreate's own 'invoice' branch (function 5 below) now
--    filters to status IN ('issued', 'void'), matching CPL-311's own
--    business rule (draft/submitted/approved invoices "must never leak to a
--    customer").** The first-drafted branch mirrored app.search_ticket_
--    link_candidates' own PRE-CPL-311 'invoice' customer branch verbatim,
--    which was correct when HRT-292 was authored (Phase 7, before Finance
--    had any customer-facing visibility rule) but is a real, live
--    disclosure gap once CPL-311 (earlier in this same batch) establishes
--    that rule -- a customer could search, and then durably link via the
--    pre-existing app.link_ticket_record, their own account's
--    draft/submitted/approved invoice, defeating CPL-311's own core
--    Finance-visibility gate. See function 5's own inline comment for the
--    full live-reproduction note. The identical gap in the two PRE-EXISTING
--    HRT-292 functions this migration deliberately never edits
--    (app._ticket_link_resolve_candidate/app.search_ticket_link_candidates)
--    -- the actual durable-write path -- is closed separately, by a new
--    additive migration (`20260801160000_harden_customer_portal_ticket_
--    link_invoice_status_gate.sql`) that `CREATE OR REPLACE`s both,
--    mirroring this repository's own established `harden_*_tierc.sql`
--    pattern (e.g. `20260731300000_harden_ticketing_customer_links_
--    creator_role_hrt295_tierc.sql`) for fixing an already-applied
--    migration's function body without editing that migration's own file.

-- ===========================================================================
-- 1. app.ticket_portal_links -- the natural-key-unique portal-link row.
-- ===========================================================================

create table app.ticket_portal_links (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  ticket_id uuid not null references app.tickets (id),
  entity_type text not null,
  entity_id uuid not null,
  relationship text not null default 'related',
  status text not null default 'active',
  safe_snapshot jsonb not null,
  snapshot_captured_at timestamptz not null default now(),
  removed_at timestamptz,
  removed_by text,
  removed_reason text,
  created_by_auth_user_id uuid not null,
  created_by text,
  record_version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint ticket_portal_links_entity_type_check check (entity_type in ('warehouse_order', 'document')),
  constraint ticket_portal_links_relationship_check check (relationship in ('primary_subject', 'related', 'affected', 'context')),
  constraint ticket_portal_links_status_check check (status in ('active', 'removed')),
  constraint ticket_portal_links_removed_shape_check check ((status <> 'removed') or (removed_at is not null and removed_reason is not null)),
  constraint ticket_portal_links_safe_snapshot_check check (jsonb_typeof(safe_snapshot) = 'object')
);

comment on table app.ticket_portal_links is
  'CPL-313: a small, PARALLEL sibling of app.ticket_links (HRT-292), scoped to exactly the two entity types (warehouse_order, document) the existing six-value registry cannot reach at the right granularity -- see this migration''s own header for why a parallel table, not a widened app.ticket_links.';

create unique index ticket_portal_links_active_unique on app.ticket_portal_links (ticket_id, entity_type, entity_id) where status = 'active';
create index ticket_portal_links_tenant_ticket_idx on app.ticket_portal_links (tenant_id, ticket_id, status);
create index ticket_portal_links_entity_idx on app.ticket_portal_links (tenant_id, entity_type, entity_id);

create trigger ticket_portal_links_touch before update on app.ticket_portal_links
  for each row execute function app.touch_ticket_row();

-- ===========================================================================
-- 2. Registry (design decision 1).
-- ===========================================================================

create function app.ticket_portal_link_entity_types()
returns text[]
language sql
immutable
set search_path = app, pg_temp
as $$
  select array['warehouse_order', 'document']::text[];
$$;

comment on function app.ticket_portal_link_entity_types is
  'CPL-313 (design decision 1): the full registry for app.ticket_portal_links, kept set-equal with app.ticket_portal_links_entity_type_check by this migration''s own db-test -- deliberately NOT app.ticket_link_entity_types(), which this migration never widens.';

-- ===========================================================================
-- 3. app._ticket_portal_link_resolve_candidate -- the ONE per-type
--    validation adapter every read/write path below dispatches through
--    (design decisions 2/3/4/7).
-- ===========================================================================

create function app._ticket_portal_link_resolve_candidate(p_entity_type text, p_tenant_id uuid, p_actor_auth_user_id uuid, p_entity_id uuid)
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
      );
  end if;
  return;
end;
$$;

comment on function app._ticket_portal_link_resolve_candidate is
  'CPL-313 (design decisions 2/3/4): returns AT MOST one row -- found iff the record exists, is tenant-scoped, AND the CURRENT caller independently passes that domain''s own real access predicate. warehouse_order composes app.wms_outbound_orders'' own real staff RLS predicate (mirrored verbatim) OR app.evaluate_customer_portal_inventory_access (CPL-309); document composes CPL-308''s own two real union-arm predicates inline (customer-only -- no staff branch exists anywhere in this repository yet, design decision 4).';

grant execute on function app._ticket_portal_link_resolve_candidate(text, uuid, uuid, uuid) to service_role;

-- ===========================================================================
-- 4. app.search_ticket_portal_link_candidates -- ticket-scoped (post-
--    creation), bounded, anti-enumerating (design decisions 2/3/7).
-- ===========================================================================

create function app.search_ticket_portal_link_candidates(
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

  if not (p_entity_type = any (app.ticket_portal_link_entity_types())) then
    raise exception 'unsupported_entity_type: % is not a supported ticket portal-link entity type', p_entity_type using errcode = 'check_violation';
  end if;

  v_search := nullif(trim(coalesce(p_search_text, '')), '');
  v_limit := least(greatest(coalesce(p_limit, 20), 1), 50);

  if not app._ticket_link_actor_may_view_tenant_data(v_ticket.tenant_id, p_actor_auth_user_id) then
    return;
  end if;

  if p_entity_type = 'warehouse_order' then
    return query
    select o.id, o.outbound_number, ('Outbound / ' || o.source_type), o.status
    from app.wms_outbound_orders o
    where o.tenant_id = v_ticket.tenant_id
      and (v_search is null or o.outbound_number ilike '%' || v_search || '%')
      and (
        (
          not app.actor_holds_customer_user_layer(o.tenant_id, p_actor_auth_user_id)
          and app.wms_pick_record_scope_ok(p_actor_auth_user_id, o.warehouse_id, o.owner_account_id::text)
          and app.actor_can_view_owner_scoped_row(p_actor_auth_user_id, o.tenant_id, o.owner_account_id)
        )
        or app.evaluate_customer_portal_inventory_access(p_actor_auth_user_id, o.tenant_id, o.warehouse_id, o.owner_account_id)
      )
    order by o.updated_at desc
    limit v_limit;
  elsif p_entity_type = 'document' then
    return query
    select f.id, f.original_filename, f.mime_type, f.malware_scan_status
    from app.files f
    where f.tenant_id = v_ticket.tenant_id
      and f.lifecycle_status = 'active' and f.deleted_at is null
      and (v_search is null or f.original_filename ilike '%' || v_search || '%')
      and (
        exists (
          select 1 from app.customer_portal_quote_requests r
          where r.id = f.record_id and f.record_type = 'customer_portal_quote_request' and r.tenant_id = v_ticket.tenant_id
            and r.account_id = any (app.resolve_customer_account_scope(p_actor_auth_user_id, v_ticket.tenant_id))
        )
        or exists (
          select 1
          from app.epod_captures ec
          join app.shipment_orders so on so.id = ec.shipment_order_id
          where f.record_type = 'shipment_order' and ec.shipment_order_id = f.record_id
            and ec.tenant_id = v_ticket.tenant_id and ec.is_latest_version and ec.status = 'completed'
            and (ec.signature_file_id = f.id or f.id = any (ec.photo_file_ids))
            and so.shipper_account_id = any (app.resolve_customer_account_scope(p_actor_auth_user_id, v_ticket.tenant_id))
        )
      )
    order by f.created_at desc
    limit v_limit;
  end if;
end;
$$;

comment on function app.search_ticket_portal_link_candidates is
  'CPL-313: mirrors app.search_ticket_link_candidates'' own shape (ticket-scoped, bounded, C-05) for the two new entity types. Every row is independently authorized for THIS caller in the WHERE clause itself, never post-filtered.';

-- ===========================================================================
-- 5. app.search_customer_ticket_link_candidates_precreate -- the ticket
--    CREATE form's own linked-record picker search, before a ticket exists
--    (design decision 6). Customer-only. Deliberately spans BOTH registries
--    -- shipment/invoice (the EXISTING, unmodified app.ticket_links registry
--    -- HRT-292, reusing its own customer-owner-scope predicate verbatim, the
--    OLD app.resolve_customer_owner_account_scope, for consistency with what
--    app.link_ticket_record will actually re-check once the ticket exists)
--    and warehouse_order/document (THIS migration's own new app.ticket_
--    portal_links registry, design decisions 2/3/5) -- a customer creating a
--    ticket has no reason to care that the eventual link call is routed to
--    two structurally different tables underneath; a single search surface
--    is the correct UX regardless of that internal split.
-- ===========================================================================

create function app.search_customer_ticket_link_candidates_precreate(
  p_tenant_id uuid,
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
  v_search text;
  v_limit integer;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if not app.actor_holds_customer_user_layer(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_privilege: identity % does not hold a customer_user membership in tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not (p_entity_type = any (array['shipment', 'invoice', 'warehouse_order', 'document'])) then
    raise exception 'unsupported_entity_type: % is not a supported pre-creation link type', p_entity_type using errcode = 'check_violation';
  end if;

  if not app._ticket_link_actor_may_view_tenant_data(p_tenant_id, p_actor_auth_user_id) then
    return;
  end if;

  v_search := nullif(trim(coalesce(p_search_text, '')), '');
  v_limit := least(greatest(coalesce(p_limit, 20), 1), 50);

  if p_entity_type = 'shipment' then
    -- Mirrors app.search_ticket_link_candidates' own 'shipment' customer
    -- branch verbatim (HRT-292) -- the SAME app.resolve_customer_owner_
    -- account_scope app.link_ticket_record will re-check once the ticket
    -- exists, so a candidate found here always remains linkable.
    return query
    select so.id, so.shipment_number, (so.mode || ' / ' || so.service_type), so.status
    from app.shipment_orders so
    where so.tenant_id = p_tenant_id
      and (v_search is null or so.shipment_number ilike '%' || v_search || '%')
      and so.shipper_account_id = any (app.resolve_customer_owner_account_scope(p_actor_auth_user_id, p_tenant_id))
    order by so.updated_at desc
    limit v_limit;
  elsif p_entity_type = 'invoice' then
    -- Tier C review fix (batch close): the FIRST draft of this branch
    -- mirrored app.search_ticket_link_candidates' own PRE-CPL-311 'invoice'
    -- customer branch verbatim (HRT-292) -- correct at HRT-292's own time
    -- (Phase 7), since Finance had zero customer-facing visibility rule of
    -- any kind then. CPL-311 (earlier in THIS SAME batch,
    -- 20260801120000_create_customer_portal_invoice_billing_visibility.sql
    -- design decision 4) establishes, for the first time, that
    -- draft/submitted/approved invoices "must never leak to a customer."
    -- This branch is new code, authored AFTER that rule existed, and must
    -- honor it -- a live security review (Tier C, security/RLS lens)
    -- reproduced a customer_user searching this RPC with p_entity_type=
    -- 'invoice' and receiving their own account's draft/submitted/approved
    -- invoices, then durably linking one via the pre-existing, unmodified
    -- app.link_ticket_record (HRT-292), permanently capturing that
    -- pre-issuance invoice's number/currency/amount/status into a
    -- customer-and-staff-readable safe_snapshot. The status filter below
    -- closes it for THIS function; the identical gap in the pre-existing
    -- app._ticket_link_resolve_candidate/app.search_ticket_link_candidates
    -- (HRT-292, already-applied, may not be edited in place) is closed by a
    -- new, separate additive migration
    -- (20260801160000_harden_customer_portal_ticket_link_invoice_status_
    -- gate.sql) that CREATE OR REPLACEs both, since app.link_ticket_record
    -- is the actual durable-write path a customer would use to exploit this
    -- -- this function alone (a read-only search) would otherwise leave that
    -- deeper, already-existing path wide open.
    return query
    select fi.id, coalesce(fi.invoice_number, 'Draft ' || fi.id::text), (fi.currency || ' ' || fi.total_amount::text), fi.status
    from app.finance_invoices fi
    where fi.tenant_id = p_tenant_id
      and fi.status in ('issued', 'void')
      and (v_search is null or fi.invoice_number ilike '%' || v_search || '%')
      and fi.customer_account_id = any (app.resolve_customer_owner_account_scope(p_actor_auth_user_id, p_tenant_id))
    order by fi.updated_at desc
    limit v_limit;
  elsif p_entity_type = 'warehouse_order' then
    return query
    select o.id, o.outbound_number, ('Outbound / ' || o.source_type), o.status
    from app.wms_outbound_orders o
    where o.tenant_id = p_tenant_id
      and (v_search is null or o.outbound_number ilike '%' || v_search || '%')
      and app.evaluate_customer_portal_inventory_access(p_actor_auth_user_id, p_tenant_id, o.warehouse_id, o.owner_account_id)
    order by o.updated_at desc
    limit v_limit;
  elsif p_entity_type = 'document' then
    return query
    select f.id, f.original_filename, f.mime_type, f.malware_scan_status
    from app.files f
    where f.tenant_id = p_tenant_id
      and f.lifecycle_status = 'active' and f.deleted_at is null
      and (v_search is null or f.original_filename ilike '%' || v_search || '%')
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
      )
    order by f.created_at desc
    limit v_limit;
  end if;
end;
$$;

comment on function app.search_customer_ticket_link_candidates_precreate is
  'CPL-313: the ticket creation UI''s own linked-record picker search -- no ticket exists yet, so this cannot and does not call app.can_access_ticket. Hard-requires a real, active customer_user membership in p_tenant_id (never a staff/internal caller). Spans BOTH the existing app.ticket_links registry (shipment/invoice, reusing the SAME app.resolve_customer_owner_account_scope predicate app.link_ticket_record will re-check) and this migration''s own new app.ticket_portal_links registry (warehouse_order/document) -- a candidate shown here always remains linkable once the ticket exists, through whichever of the two link RPCs the caller''s own entity_type routes to.';

-- ===========================================================================
-- 6. app.link_ticket_portal_record (design decisions 7/8).
-- ===========================================================================

create function app.link_ticket_portal_record(
  p_ticket_id uuid,
  p_entity_type text,
  p_entity_id uuid,
  p_relationship text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.ticket_portal_links
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_ticket app.tickets;
  v_is_staff boolean;
  v_is_requester boolean;
  v_relationship text;
  v_existing app.ticket_portal_links;
  v_candidate record;
  v_snapshot jsonb;
  v_row app.ticket_portal_links;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_ticket from app.tickets where id = p_ticket_id for update;
  if not found or not app.can_access_ticket(p_ticket_id, p_actor_auth_user_id) then
    raise exception 'ticket_not_found: %', p_ticket_id using errcode = 'no_data_found';
  end if;

  v_is_staff := app.is_ticket_staff(p_ticket_id, p_actor_auth_user_id);
  v_is_requester := app._is_ticket_requester_party(v_ticket, p_actor_auth_user_id);
  if not (v_is_staff or v_is_requester) then
    raise exception 'insufficient_authority: identity % may not link records to ticket %', p_actor_auth_user_id, p_ticket_id
      using errcode = 'insufficient_privilege';
  end if;

  if not (p_entity_type = any (app.ticket_portal_link_entity_types())) then
    raise exception 'unsupported_entity_type: % is not a supported ticket portal-link entity type', p_entity_type using errcode = 'check_violation';
  end if;

  v_relationship := coalesce(p_relationship, 'related');
  if not (v_relationship = any (array['primary_subject', 'related', 'affected', 'context'])) then
    raise exception 'invalid_relationship: % is not a recognized link relationship', p_relationship using errcode = 'check_violation';
  end if;

  -- Anti-enumeration (design decision 7), same ordering discipline app.
  -- link_ticket_record's own decision 3/8 already established: THIS
  -- caller's own eligibility is re-proven BEFORE the duplicate-link
  -- short-circuit, every call, including a replay.
  select * into v_candidate from app._ticket_portal_link_resolve_candidate(p_entity_type, v_ticket.tenant_id, p_actor_auth_user_id, p_entity_id);
  if not found then
    raise exception 'record_not_eligible: no eligible % record exists for %', p_entity_type, p_entity_id using errcode = 'no_data_found';
  end if;

  select * into v_existing from app.ticket_portal_links where ticket_id = p_ticket_id and entity_type = p_entity_type and entity_id = p_entity_id and status = 'active';
  if found then
    return v_existing;
  end if;

  v_snapshot := jsonb_build_object('label', v_candidate.primary_label, 'detail', v_candidate.secondary_label, 'status', v_candidate.status_label);

  begin
    insert into app.ticket_portal_links (
      tenant_id, ticket_id, entity_type, entity_id, relationship, status,
      safe_snapshot, snapshot_captured_at, created_by_auth_user_id, created_by
    ) values (
      v_ticket.tenant_id, p_ticket_id, p_entity_type, p_entity_id, v_relationship, 'active',
      v_snapshot, now(), p_actor_auth_user_id, p_actor_label
    )
    returning * into v_row;
  exception
    when unique_violation then
      select * into v_row from app.ticket_portal_links where ticket_id = p_ticket_id and entity_type = p_entity_type and entity_id = p_entity_id and status = 'active';
      if not found then
        raise;
      end if;
      return v_row;
  end;

  return v_row;
end;
$$;

comment on function app.link_ticket_portal_record is
  'CPL-313: mirrors app.link_ticket_record''s own shape (staff OR requester-side party, C-05/C-01/C-02 anti-enumeration + idempotency, design decisions 7/8) for the two new entity types.';

-- ===========================================================================
-- 7. app.unlink_ticket_portal_record.
-- ===========================================================================

create function app.unlink_ticket_portal_record(p_link_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.ticket_portal_links
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_ticket_id uuid;
  v_ticket app.tickets;
  v_row app.ticket_portal_links;
  v_is_staff boolean;
  v_is_requester boolean;
  v_updated app.ticket_portal_links;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  -- Ticket-first lock order (C-04/C-21), mirrors app.unlink_ticket_record's
  -- own documented reasoning (HRT-292 decision 13) exactly.
  select ticket_id into v_ticket_id from app.ticket_portal_links where id = p_link_id;
  if not found then
    raise exception 'ticket_link_not_found: %', p_link_id using errcode = 'no_data_found';
  end if;

  select * into v_ticket from app.tickets where id = v_ticket_id for update;
  if not found then
    raise exception 'ticket_link_not_found: %', p_link_id using errcode = 'no_data_found';
  end if;

  select * into v_row from app.ticket_portal_links where id = p_link_id for update;
  if not found or not app.can_access_ticket(v_row.ticket_id, p_actor_auth_user_id) then
    raise exception 'ticket_link_not_found: %', p_link_id using errcode = 'no_data_found';
  end if;

  v_is_staff := app.is_ticket_staff(v_row.ticket_id, p_actor_auth_user_id);
  v_is_requester := app._is_ticket_requester_party(v_ticket, p_actor_auth_user_id);
  if not (v_is_staff or v_is_requester) then
    raise exception 'insufficient_authority: identity % may not unlink %', p_actor_auth_user_id, p_link_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_row.status <> 'active' then
    raise exception 'invalid_state: link % is % not active', p_link_id, v_row.status using errcode = 'check_violation';
  end if;
  if v_row.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_row.record_version
      using errcode = 'serialization_failure';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to unlink a record' using errcode = 'check_violation';
  end if;

  update app.ticket_portal_links
  set status = 'removed', removed_at = now(), removed_by = p_actor_label, removed_reason = p_reason
  where id = p_link_id and record_version = p_expected_version
  returning * into v_updated;
  if not found then
    raise exception 'stale_version: concurrent update detected for link %', p_link_id using errcode = 'serialization_failure';
  end if;

  return v_updated;
end;
$$;

comment on function app.unlink_ticket_portal_record is
  'CPL-313: mirrors app.unlink_ticket_record''s own shape (ticket-first lock order, mandatory reason, optimistic concurrency) verbatim.';

-- ===========================================================================
-- 8. app.list_ticket_portal_links -- batched, principal-fresh safe summaries.
-- ===========================================================================

create function app.list_ticket_portal_links(p_ticket_id uuid, p_actor_auth_user_id uuid)
returns table (
  id uuid, entity_type text, entity_id uuid, relationship text, status text,
  live_available boolean, label text, detail text, status_label text,
  linked_at timestamptz, created_by text, record_version integer
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_ticket app.tickets;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_ticket from app.tickets t where t.id = p_ticket_id;
  if not found or not app.can_access_ticket(p_ticket_id, p_actor_auth_user_id) then
    raise exception 'ticket_not_found: %', p_ticket_id using errcode = 'no_data_found';
  end if;

  return query
  select
    l.id, l.entity_type, l.entity_id, l.relationship, l.status,
    (c.primary_label is not null) as live_available,
    c.primary_label, c.secondary_label,
    coalesce(c.status_label, 'unavailable'),
    l.created_at, l.created_by, l.record_version
  from app.ticket_portal_links l
  left join lateral app._ticket_portal_link_resolve_candidate(l.entity_type, v_ticket.tenant_id, p_actor_auth_user_id, l.entity_id) c on true
  where l.ticket_id = p_ticket_id and l.status = 'active'
  order by l.created_at asc;
end;
$$;

comment on function app.list_ticket_portal_links is
  'CPL-313: mirrors app.list_ticket_links'' own shape (one lateral join, principal-fresh re-check every row, never the stored safe_snapshot as a fallback) verbatim.';

-- ===========================================================================
-- 9. RLS (design decision 10) + grants (ERR-2026-004).
-- ===========================================================================

alter table app.ticket_portal_links enable row level security;

create policy ticket_portal_links_select_scoped on app.ticket_portal_links
  for select to authenticated
  using ((app.can_access_ticket(ticket_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

revoke execute on all functions in schema app from public;

grant select on app.ticket_portal_links to authenticated, service_role;
grant insert, update, delete on app.ticket_portal_links to service_role;

grant execute on function app.ticket_portal_link_entity_types() to authenticated, service_role;
grant execute on function app.search_ticket_portal_link_candidates(uuid, text, text, uuid, integer) to authenticated, service_role;
grant execute on function app.search_customer_ticket_link_candidates_precreate(uuid, text, text, uuid, integer) to authenticated, service_role;
grant execute on function app.link_ticket_portal_record(uuid, text, uuid, text, uuid, text) to authenticated, service_role;
grant execute on function app.unlink_ticket_portal_record(uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.list_ticket_portal_links(uuid, uuid) to authenticated, service_role;
