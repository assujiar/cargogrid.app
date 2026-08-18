-- Phase 8 capability CPL-308 (CG-S13-CPL-010, Prompt 308, "Document Center").
-- Read docs/adr/ADR-0024-phase8-customer-portal-access-and-transport-pattern.md,
-- supabase/migrations/20260801010000_create_customer_portal_account_scope.sql
-- (CPL-300), supabase/migrations/20260801030000_create_customer_portal_
-- quote_requests.sql (CPL-302, app.list_customer_quote_request_files -- the
-- quote-request-attachment read path this migration's own quote_request
-- union arm mirrors), and supabase/migrations/20260801080000_create_
-- customer_portal_epod_access.sql (CPL-307, app.get_customer_epod -- the
-- ePOD evidence-file re-verification logic this migration's own epod union
-- arm mirrors) in full before this migration was written.
--
-- Source prompt's own database-impact line: "file bytes remain Platform-
-- owned" -- this is a composition/index capability over already-existing
-- customer-facing document sources, never a new file store and never a new
-- upload path. Zero new table. Two new SECURITY DEFINER RPCs: a list/search
-- across sources, and a per-document scoped "download" access+audit RPC.
--
-- ===========================================================================
-- Design decisions
-- ===========================================================================
--
-- 1. **Live UNION ALL, never a durable index table.** The orchestrating
--    task's own instruction offered a choice: a new `app.customer_document_
--    index` table, OR a single new RPC composing a live UNION ALL across the
--    already-existing sources. This migration picks the live UNION,
--    mirroring CPL-301's own already-established precedent
--    (`20260801020000_create_customer_portal_dashboard_summary.sql` design
--    decision 1): that migration's own header explicitly rejected a
--    persisted dashboard cache/snapshot table for the identical reason this
--    migration now applies to documents -- "this repository has no
--    scheduler/job-refresh infrastructure to keep a cache fresh," and
--    building one would be new, out-of-scope infrastructure. A durable
--    `app.customer_document_index` table would need its own write-time
--    population trigger/hook at every one of `app.initiate_file_upload`
--    (quote-request attachments), `app.complete_epod_capture`/`app.
--    record_file_scan_result` (ePOD evidence), and every future document
--    source (Prompts 311/313) -- a second, independently-evolving source of
--    truth that could silently drift from the canonical tables it indexes,
--    the exact class of defect `20260730310000_create_advanced_tms_
--    customer_inventory_access.sql` design note 6 already named and
--    `20260730311000_harden_customer_inventory_access_rls_isolation.sql` had
--    to correct once. A live UNION reads `app.files`/`app.epod_captures`/
--    `app.customer_portal_quote_requests`/`app.shipment_orders` directly, on
--    every call, so it can never be stale and needs no reconciliation job.
--    Trade-off, disclosed: a durable index would paginate more cleanly
--    across heterogeneous sources once there are many of them (a single
--    covering index vs. this migration's own `UNION ALL` + application-level
--    keyset merge) -- accepted for now, at 2 real sources, revisit if/when
--    Prompts 311/313 land and the union arm count grows enough that a
--    reviewer judges the live-composition cost too high (the same "revisit
--    when it stops being genuinely simpler" latitude CPL-301's own design
--    decision 1 already accepted for the dashboard).
-- 2. **Two real source-module union arms today; two more recognized but
--    honestly empty.** `quote_request` (an `app.files` row under
--    `record_type='customer_portal_quote_request'`, scoped through `app.
--    customer_portal_quote_requests.account_id`, mirroring `app.list_
--    customer_quote_request_files`'s own join shape exactly) and `epod` (an
--    `app.files` row referenced by `app.epod_captures.signature_file_id`/
--    `photo_file_ids` for a `completed`, `is_latest_version` capture on an
--    in-scope shipment order, mirroring `app.get_customer_epod`'s own
--    discovery logic exactly, minus that function's own whole-capture
--    quarantine collapse -- see decision 5 below for why that collapse is
--    deliberately NOT repeated here). `invoice` (Prompt 311, Finance) and
--    `ticket` (Prompt 313, Ticketing) do not exist as document sources
--    anywhere in this repository yet (confirmed by direct grep -- neither
--    Finance invoice attachments nor a customer-facing ticket-attachment
--    read RPC exists today) -- both are still recognized, validated
--    `p_source_module` values (never `invalid_source_module`) that
--    deterministically return zero rows, exactly like CPL-301's own honest
--    "not yet available" stub-card pattern (`available = false`, never
--    sample/fake data) applied here to a filter option instead of a
--    dashboard card. `app.customer_portal_booking_requests` (CPL-303) and
--    `app.customer_portal_shipment_change_requests` (CPL-304) are
--    deliberately NOT a fifth/sixth union arm and NOT a recognized
--    `p_source_module` value -- direct inspection of both migrations
--    (grep-confirmed) shows neither ever registers a PLT-128 `document_type`
--    or calls `app.initiate_file_upload` against its own table, so neither
--    is a genuinely "already-existing document source" this capability could
--    compose without inventing a new upload path of its own -- out of this
--    capability's own bounded scope (design decision 1's own "never a new
--    file store" constraint), not a silent omission.
-- 3. **No new upload path.** Business rule 1 ("file bytes remain
--    Platform-owned") and the orchestrating task's own framing ("a
--    composition/index capability") together mean this migration adds no
--    `initiate_file_upload`-calling wrapper of its own. A customer who wants
--    to add a NEW quote-request attachment still does so on the existing
--    `customer-quotes/[requestId]` page (CPL-302, already live); ePOD
--    evidence is staff-captured field evidence and was never
--    customer-uploadable in the first place (CPL-307 design decision 2). The
--    Document Center is a read-only, cross-source view plus a scoped
--    download/access action -- disclosed, not a silent scope cut.
-- 4. **`app.get_customer_document` takes the underlying `app.files.id`
--    directly as `p_document_id`, never a synthetic composite key.** Both
--    real sources are, structurally, `app.files` rows -- reusing the file's
--    own primary key as this capability's own document id avoids inventing
--    a parallel identifier space. The function independently re-derives
--    which source a given file id belongs to (by its own `record_type`) and
--    re-applies that source's own scope check from first principles -- it
--    never trusts a `source_module`/`source_entity_id` pair the client might
--    supply, precisely because business rule 4 ("a document link grants no
--    access to its source record or other linked documents") means a
--    forged/tampered client-supplied source hint must never widen access. A
--    file whose `record_type` is neither `customer_portal_quote_request` nor
--    `shipment_order`, or a `shipment_order`-typed file that is NOT actually
--    referenced by any `completed`, `is_latest_version` ePOD capture (e.g. a
--    future non-ePOD Operations document living under the same
--    `record_type`), is treated identically to a genuinely nonexistent file
--    -- this capability is never a back door into a source it does not
--    itself compose.
-- 5. **Malware/quarantine states are surfaced PER DOCUMENT on the list, never
--    collapsed -- a deliberate, disclosed divergence from `app.get_customer_
--    epod`'s own whole-capture quarantine collapse (CPL-307 design decision
--    5).** Business rule 5 ("malware-scan/quarantine states must be honestly
--    surfaced per document... never hidden or defaulted to available")
--    governs THIS capability directly, and a list/search surface is a
--    different shape than a single-shipment detail read: `app.list_customer_
--    documents` returns every in-scope document's own real, live `app.
--    files.malware_scan_status` (`pending`/`clean`/`infected`/`error`)
--    exactly as stored, never filtered out and never defaulted to `clean`.
--    `app.get_customer_document` (the actual "download" action) still
--    refuses to actually serve a non-`clean` file (business rule: "unscanned/
--    quarantined files are never downloadable, previewed, indexed or
--    emailed") -- but this is not a new disclosure, since the caller already
--    saw the real status on the list before attempting the download.
--    **Tier B self-catch, this migration's own first live db-test run, not
--    reasoned about in advance**: the refusal is deliberately NOT expressed
--    as a raised database exception. `app.get_customer_document` itself
--    always returns a normal, successful row once scope is established
--    (writing a GRANTED or DENIED `app.file_access_logs` row accordingly,
--    decision 7) -- a `raise exception` at that point would roll back the
--    very `app.file_access_logs` INSERT it just made, the moment an
--    uncaught caller (the ordinary `client.rpc(...)` calling shape) lets
--    that exception propagate: PostgreSQL rolls back a failed statement's
--    entire set of side effects atomically, and this repository has no
--    autonomous-transaction primitive to isolate the log write from the
--    raise. The refusal is instead enforced one layer up, at the
--    TypeScript service boundary (`server/mutations/customer-document.ts`),
--    which raises `document_not_downloadable` from an otherwise-successful,
--    non-`clean` row -- after the RPC's own audit trail has already durably
--    committed. Mirrors `app.get_customer_epod`'s own non-raising
--    `quarantined` convention (CPL-307) more literally than this
--    migration's own first draft did.
-- 6. **Anti-enumeration shape mirrors CPL-307's own non-uniform precedent.**
--    `app.list_customer_documents` is deny-by-default (empty scope or an
--    out-of-scope `p_account_id`/`p_shipment_order_id` filter both return an
--    empty result, never an error -- list convention). `app.get_customer_
--    document` combines "genuinely nonexistent," "wrong tenant," "a file
--    type this capability does not compose," and "exists but out of scope"
--    into ONE anti-enumerating `document_not_found` -- mirrors `app.get_
--    customer_shipment_order` (CPL-304)/`app.get_customer_epod` (CPL-307)
--    byte-for-byte, and remains the ONLY case this function raises at all
--    (decision 5). A non-`clean` scan status is reachable only AFTER a
--    caller's own scope is genuinely established -- never a distinguishable
--    signal for an out-of-scope caller.
-- 7. **`app.file_access_logs`/`app.capture_audit_event` reused directly,
--    exactly like CPL-307** -- no parallel audit table. `app.get_customer_
--    document` writes exactly one `app.file_access_logs` row per matched
--    call (granted or denied by real scan status, `access_type=
--    'metadata_view'` (Tier C fix -- never `'signed_url_issued'`, mirroring
--    CPL-307's own identical Tier C fix: no signed URL is fabricated by
--    either capability) as part of
--    its own normal, successful return (decision 5) -- and one `app.
--    capture_audit_event` row for the zero-match "not found" case (no real
--    `file_id` to log against; this raising path's own audit durability is
--    a shared, pre-existing question across every "capture_audit_event then
--    raise" call site this repository's Phase 8 capabilities already use
--    identically, e.g. CPL-307's own `record_not_found` path -- not unique
--    to or newly introduced by this migration, and out of this bounded
--    capability's own scope to redesign repository-wide). `app.list_
--    customer_documents` is a plain, unaudited read/search, exactly like
--    every other Phase 8 list RPC (CPL-300/302/303/304's own established
--    "list RPCs are not individually audited" precedent) -- only the
--    per-document access/download action carries the CPL-307-style audit
--    discipline, since that is the actual content-access moment.
-- 8. **`p_source_module` validation is application code, not a CHECK
--    constraint** -- this migration creates zero table, so there is no
--    column to constrain; the 4-value enum (`quote_request`/`epod`/
--    `invoice`/`ticket`) is enforced by an explicit `if ... not in (...)`
--    guard inside `app.list_customer_documents` itself, raising
--    `invalid_source_module` for anything else, and independently
--    cross-checked at the TypeScript boundary by a matching Zod enum.
-- 9. **No new index.** Every join predicate this migration's own queries use
--    is already covered by an existing, already-applied index: `app.files
--    (tenant_id, record_type, record_id)` (`files_tenant_record_idx`,
--    PLT-128), `app.customer_portal_quote_requests (account_id)` (`cpqr_
--    account_idx`, CPL-302) and its own primary key for the `record_id`
--    join, `app.epod_captures (tenant_id, shipment_order_id)` (`epod_
--    captures_tenant_shipment_idx`, OPS-177) and `app.epod_captures
--    (version_group_id) where is_latest_version` (OPS-177), and `app.
--    shipment_orders (tenant_id, shipper_account_id)` (`shipment_orders_
--    tenant_shipper_account_idx`, CPL-304). At this capability's own
--    customer-portal scale (one identity's own bounded account/shipment
--    scope, never a tenant-wide scan), no new covering index is justified --
--    disclosed as a considered decision, not an oversight, mirroring CPL-307
--    (also zero new index, also composing already-indexed sources only).
-- 10. **RLS: this migration touches ZERO table.** No new table; no RLS
--    policy on `app.files`/`app.epod_captures`/`app.customer_portal_quote_
--    requests`/`app.shipment_orders`/`app.file_access_logs` is edited,
--    narrowed, or widened. Every one of those tables' own pre-existing
--    policies already correctly deny a bare `customer_user`-layer principal
--    by default (re-verified live in this checkpoint's own db-test). The 2
--    new functions below are the only sanctioned customer-facing access path
--    this migration adds.
-- 11. **REST/GraphQL transport (ADR-0024 Part C)**: service layer + Server
--    Actions + UI only, no `app/api/` HTTP route -- identical in kind to
--    CPL-300..307's own disclosed residual gap.
-- 12. **No edit to `scripts/db-tests/rbac-enforcement.sql`** -- both new
--    functions call `app.assert_actor_is_session_identity` directly as their
--    own first statement, and `app.list_customer_documents`/`app.get_
--    customer_document` both call `app.resolve_customer_account_scope`
--    (already-recognized `rbac-enforcement.sql` base-regex authority
--    primitives since CPL-300) -- confirmed live in this checkpoint's own
--    db-test, no edit required, mirroring CPL-303/304/305/306/307's own
--    identical precedent.
-- 13. **UI: a new standalone route, `app/(tenant)/[tenantSlug]/customer-
--    documents/`**, per the orchestrating task's own instruction -- list with
--    filters, no detail sub-route (each row's own scoped download action is
--    sufficient, business rule 4's own "never grants access to its source
--    record" is satisfied precisely by NOT building a document detail page
--    that would need to re-project the source entity's own other fields).
-- 14. Per `ERR-2026-004` (`docs/runtime/ERROR_LEDGER.md`): this migration
--    carries its own explicit `revoke execute on all functions in schema
--    app from public` statement before its final grants.

-- ===========================================================================
-- app.list_customer_documents -- live UNION ALL across every real source
-- (design decisions 1/2/9)
-- ===========================================================================

create function app.list_customer_documents(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_account_id uuid default null,
  p_shipment_order_id uuid default null,
  p_source_module text default null,
  p_date_from timestamptz default null,
  p_date_to timestamptz default null,
  p_cursor_created_at timestamptz default null,
  p_cursor_id uuid default null,
  p_limit integer default 50
)
returns table (
  document_id uuid,
  source_module text,
  source_entity_id uuid,
  document_type text,
  original_filename text,
  mime_type text,
  size_bytes bigint,
  malware_scan_status text,
  account_id uuid,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_scope uuid[];
  v_limit integer;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if p_cursor_id is not null and p_cursor_created_at is null then
    raise exception 'invalid_cursor: p_cursor_created_at is required when p_cursor_id is supplied' using errcode = 'invalid_parameter_value';
  end if;

  -- Design decision 8: 4-value enum, application-enforced (no table to
  -- CHECK-constrain). 'invoice'/'ticket' are recognized but currently have
  -- no backing union arm below (design decision 2) -- never an error, always
  -- a real, honestly empty result.
  if p_source_module is not null and p_source_module not in ('quote_request', 'epod', 'invoice', 'ticket') then
    raise exception 'invalid_source_module: % is not a recognized document source module', p_source_module using errcode = 'invalid_parameter_value';
  end if;

  if p_date_from is not null and p_date_to is not null and p_date_to < p_date_from then
    raise exception 'invalid_date_range: p_date_to cannot be before p_date_from' using errcode = 'invalid_parameter_value';
  end if;

  -- Deny-by-default (ADR-0024 Part A): an empty resolved scope, or an
  -- explicitly out-of-scope p_account_id filter, both short-circuit to an
  -- empty result before either union arm below ever runs -- mirrors every
  -- other Phase 8 list RPC's own convention.
  v_scope := app.resolve_customer_account_scope(p_actor_auth_user_id, p_tenant_id);
  if array_length(v_scope, 1) is null then
    return;
  end if;
  if p_account_id is not null and not (p_account_id = any (v_scope)) then
    return;
  end if;

  v_limit := least(greatest(coalesce(p_limit, 50), 1), 200);

  return query
  with quote_request_docs as (
    -- Mirrors app.list_customer_quote_request_files' own join shape exactly
    -- (CPL-302), widened here to every in-scope request at once rather than
    -- one request at a time.
    select
      f.id as document_id,
      'quote_request'::text as source_module,
      r.id as source_entity_id,
      'quote_request_attachment'::text as document_type,
      f.original_filename,
      f.mime_type,
      f.size_bytes,
      f.malware_scan_status,
      r.account_id,
      f.created_at
    from app.customer_portal_quote_requests r
    join app.files f
      on f.tenant_id = r.tenant_id
      and f.record_type = 'customer_portal_quote_request'
      and f.record_id = r.id
      and f.lifecycle_status = 'active'
      and f.deleted_at is null
    where r.tenant_id = p_tenant_id
      and r.account_id = any (v_scope)
      and (p_source_module is null or p_source_module = 'quote_request')
      and (p_account_id is null or r.account_id = p_account_id)
      -- p_shipment_order_id has no meaning on this source -- a supplied
      -- filter correctly excludes every quote-request document rather than
      -- silently ignoring the filter (design decision 2).
      and p_shipment_order_id is null
  ),
  epod_captures_scope as (
    -- Mirrors app.get_customer_epod's own discovery logic exactly (latest
    -- version, completed only, CPL-307) -- a still-in-review capture is
    -- never surfaced here, matching that same customer-facing boundary.
    select so.id as shipment_order_id, so.shipper_account_id as account_id, ec.signature_file_id, ec.photo_file_ids
    from app.shipment_orders so
    join app.epod_captures ec
      on ec.tenant_id = so.tenant_id
      and ec.shipment_order_id = so.id
      and ec.is_latest_version
      and ec.status = 'completed'
    where so.tenant_id = p_tenant_id
      and so.shipper_account_id = any (v_scope)
      and (p_shipment_order_id is null or so.id = p_shipment_order_id)
      and (p_account_id is null or so.shipper_account_id = p_account_id)
      and (p_source_module is null or p_source_module = 'epod')
  ),
  -- Every column reference below is qualified with the "ecs" alias, never
  -- bare -- this function's own `returns table (..., account_id uuid, ...)`
  -- shape creates an implicitly-named OUT parameter `account_id` visible
  -- inside this function's body, which would otherwise make an unqualified
  -- `account_id`/`shipment_order_id` reference against epod_captures_scope's
  -- own same-named columns genuinely ambiguous to the planner (the exact
  -- defect class CPL-304/CPL-307's own headers already warn about -- live-
  -- caught by this migration's own first db-test run, not merely reasoned
  -- about in advance).
  epod_file_refs as (
    select ecs.shipment_order_id, ecs.account_id, ecs.signature_file_id as file_id, 'epod_signature'::text as document_type
    from epod_captures_scope ecs
    where ecs.signature_file_id is not null
    union all
    select ecs.shipment_order_id, ecs.account_id, unnest(ecs.photo_file_ids) as file_id, 'epod_photo'::text as document_type
    from epod_captures_scope ecs
  ),
  epod_docs as (
    select
      f.id as document_id,
      'epod'::text as source_module,
      efr.shipment_order_id as source_entity_id,
      efr.document_type,
      f.original_filename,
      f.mime_type,
      f.size_bytes,
      f.malware_scan_status,
      efr.account_id,
      f.created_at
    from epod_file_refs efr
    join app.files f
      on f.id = efr.file_id
      and f.tenant_id = p_tenant_id
      and f.record_type = 'shipment_order'
      and f.record_id = efr.shipment_order_id
      and f.lifecycle_status = 'active'
      and f.deleted_at is null
  ),
  -- Explicit column list, never select * (C-17 discipline) -- both arms
  -- above already curate exactly this capability's own customer-safe
  -- 10-column shape, so this is a plain re-selection of already-projected
  -- columns, not a raw base-table read. Every reference is qualified with
  -- the "q"/"e" alias, never bare -- the identical OUT-parameter-collision
  -- reason documented on epod_file_refs above applies here too
  -- (document_id/account_id/created_at are all OUT-parameter names).
  combined as (
    select q.document_id, q.source_module, q.source_entity_id, q.document_type, q.original_filename, q.mime_type, q.size_bytes, q.malware_scan_status, q.account_id, q.created_at from quote_request_docs q
    union all
    select e.document_id, e.source_module, e.source_entity_id, e.document_type, e.original_filename, e.mime_type, e.size_bytes, e.malware_scan_status, e.account_id, e.created_at from epod_docs e
  )
  select c.document_id, c.source_module, c.source_entity_id, c.document_type, c.original_filename, c.mime_type, c.size_bytes, c.malware_scan_status, c.account_id, c.created_at
  from combined c
  where (p_date_from is null or c.created_at >= p_date_from)
    and (p_date_to is null or c.created_at <= p_date_to)
    and (p_cursor_id is null or (c.created_at, c.document_id) < (p_cursor_created_at, p_cursor_id))
  order by c.created_at desc, c.document_id desc
  limit v_limit;
end;
$$;

comment on function app.list_customer_documents is
  'CPL-308: live UNION ALL across every real customer-facing document source (design decisions 1/2) -- quote_request (app.files under customer_portal_quote_request, scoped via app.customer_portal_quote_requests.account_id) and epod (app.files referenced by a completed, is_latest_version app.epod_captures row on an in-scope shipment order). invoice/ticket are recognized p_source_module values with no backing union arm yet (Prompts 311/313) -- never an error, always an honestly empty result, never fabricated (design decision 2). Every document''s own real malware_scan_status is returned as-is, never filtered or defaulted to clean (design decision 5, business rule 5). Keyset-paginated on (created_at desc, document_id desc), never OFFSET, hard-capped at 200. Deny-by-default: zero scope or an out-of-scope account/shipment filter both return an empty result, never an error.';

-- ===========================================================================
-- app.get_customer_document -- the scoped, audited "download" access action
-- (design decisions 4/6/7)
-- ===========================================================================

create function app.get_customer_document(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_document_id uuid
)
returns table (
  document_id uuid,
  source_module text,
  source_entity_id uuid,
  document_type text,
  original_filename text,
  mime_type text,
  size_bytes bigint,
  malware_scan_status text,
  account_id uuid,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_file app.files;
  v_request app.customer_portal_quote_requests;
  v_shipment app.shipment_orders;
  v_capture app.epod_captures;
  v_source_module text;
  v_source_entity_id uuid;
  v_document_type text;
  v_account_id uuid;
  v_matched boolean := false;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select f.* into v_file
  from app.files f
  where f.id = p_document_id and f.tenant_id = p_tenant_id and f.lifecycle_status = 'active' and f.deleted_at is null;

  -- Design decision 4: independently re-derives which source (if any) this
  -- file genuinely belongs to and re-applies that source's own scope check
  -- from first principles -- never trusts a client-supplied source hint. A
  -- record_type this capability does not compose at all, or a shipment_order
  -- file not actually referenced by any completed capture, falls through to
  -- v_matched = false, treated identically to a nonexistent file.
  if found then
    if v_file.record_type = 'customer_portal_quote_request' then
      select r.* into v_request from app.customer_portal_quote_requests r where r.id = v_file.record_id and r.tenant_id = p_tenant_id;
      if found and (v_request.account_id = any (app.resolve_customer_account_scope(p_actor_auth_user_id, p_tenant_id))) then
        v_source_module := 'quote_request';
        v_source_entity_id := v_request.id;
        v_document_type := 'quote_request_attachment';
        v_account_id := v_request.account_id;
        v_matched := true;
      end if;
    elsif v_file.record_type = 'shipment_order' then
      select so.* into v_shipment from app.shipment_orders so where so.id = v_file.record_id and so.tenant_id = p_tenant_id;
      if found and (v_shipment.shipper_account_id = any (app.resolve_customer_account_scope(p_actor_auth_user_id, p_tenant_id))) then
        select ec.* into v_capture
        from app.epod_captures ec
        where ec.tenant_id = p_tenant_id
          and ec.shipment_order_id = v_shipment.id
          and ec.is_latest_version
          and ec.status = 'completed'
          and (ec.signature_file_id = v_file.id or v_file.id = any (ec.photo_file_ids));
        if found then
          v_source_module := 'epod';
          v_source_entity_id := v_shipment.id;
          v_document_type := case when v_capture.signature_file_id = v_file.id then 'epod_signature' else 'epod_photo' end;
          v_account_id := v_shipment.shipper_account_id;
          v_matched := true;
        end if;
      end if;
    end if;
  end if;

  if not v_matched then
    -- No real file_id to log a app.file_access_logs row against in every
    -- sub-case (a genuinely nonexistent id has no row at all) -- app.
    -- capture_audit_event carries the outcome instead (design decision 7),
    -- p_reason a short machine-readable code, never free text (C-24
    -- discipline).
    perform app.capture_audit_event(
      p_tenant_id, p_actor_auth_user_id, p_actor_auth_user_id::text, 'get_customer_document',
      'app.files', p_document_id, 'failure', 'document_not_found', null, null
    );
    raise exception 'document_not_found: no permitted document exists for %', p_document_id using errcode = 'no_data_found';
  end if;

  -- Business rule: "Unscanned/quarantined files are never downloadable,
  -- previewed, indexed or emailed." Tier B self-catch (this migration's own
  -- first live db-test run, not reasoned about in advance): a `raise
  -- exception` here -- even one preceded by its own INSERT into app.
  -- file_access_logs -- rolls the ENTIRE statement back atomically the
  -- moment it propagates to an uncaught top-level caller (the ordinary
  -- calling shape for a single `client.rpc(...)` call), discarding that same
  -- INSERT along with it. A denied access attempt is therefore never
  -- expressed as a raised exception in this function -- it is a normal,
  -- successful return (mirroring app.get_customer_epod's own non-raising
  -- `quarantined` state, CPL-307) so the app.file_access_logs row it writes
  -- durably commits. Once scope is genuinely established (design decision
  -- 6), this is not a new disclosure -- the caller's own prior app.list_
  -- customer_documents call already showed this exact malware_scan_status
  -- (design decision 5). The actual "is this really downloadable" refusal is
  -- enforced one layer up, at the TypeScript service boundary (server/
  -- mutations/customer-document.ts), which raises its own document_not_
  -- downloadable error from a non-clean malware_scan_status on an otherwise
  -- successful row -- after this RPC's own audit trail has already durably
  -- committed.
  -- Tier C fix (spec-compliance Finding 2, batch review of CPL-305..309):
  -- 'metadata_view', not 'signed_url_issued' -- no signed URL is ever
  -- fabricated by this function (it returns customer-safe metadata only,
  -- never a working file URL or storage_path), so 'metadata_view' is the
  -- correct app.file_access_logs.access_type literal, exactly as app.
  -- authorize_file_access itself already uses for its own non-signed-URL
  -- metadata reads (20260719140000_create_document_file_engine.sql:640).
  -- This mirrors the identical CPL-307 fix -- both capabilities never issue
  -- a signed URL, so neither should claim to have via this literal.
  insert into app.file_access_logs (tenant_id, file_id, accessed_by_auth_user_id, access_type, result, reason, correlation_id)
  values (
    p_tenant_id, v_file.id, p_actor_auth_user_id, 'metadata_view',
    case when v_file.malware_scan_status = 'clean' then 'granted' else 'denied' end,
    case
      when v_file.malware_scan_status = 'clean' then null
      when v_file.malware_scan_status = 'infected' then 'document_infected_quarantined'
      else 'document_not_yet_scanned'
    end,
    null
  );

  return query
  select v_file.id, v_source_module, v_source_entity_id, v_document_type, v_file.original_filename, v_file.mime_type, v_file.size_bytes, v_file.malware_scan_status, v_account_id, v_file.created_at;
end;
$$;

comment on function app.get_customer_document is
  'CPL-308: the ONE scoped, audited per-document access/"download" action (design decision 4) -- takes app.files.id directly, never a synthetic key or a client-supplied source hint. Independently re-derives which source the file belongs to from its own record_type and re-applies that source''s own scope check; a file this capability does not compose, or a shipment_order file not genuinely referenced by any completed ePOD capture, is treated identically to a nonexistent one (document_not_found, the ONLY case this function raises). A non-clean malware_scan_status is a normal, successful return with a DENIED app.file_access_logs row -- never a raised exception (Tier B self-catch: raising here would roll back that same INSERT the moment an uncaught caller propagates it) -- the actual document_not_downloadable refusal is enforced one layer up, at the TypeScript service boundary, after this RPC''s own audit trail has already durably committed. A clean file writes a GRANTED app.file_access_logs row. Either way, returns the same customer-safe projection app.list_customer_documents uses -- never storage_path, never a fabricated signed URL (mirrors CPL-307''s own disclosed no-live-Storage boundary).';

-- ===========================================================================
-- Grants -- zero new table, so no table grant applies (design decision 10)
-- ===========================================================================

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit, directly-provable
-- revoke of PostgreSQL's PUBLIC-execute default, the standing per-migration
-- convention since PLT-118, applied here before any role-specific grant.
revoke execute on all functions in schema app from public;

grant execute on function app.list_customer_documents(uuid, uuid, uuid, uuid, text, timestamptz, timestamptz, timestamptz, uuid, integer) to authenticated, service_role;
grant execute on function app.get_customer_document(uuid, uuid, uuid) to authenticated, service_role;
