-- Phase 8 capability CPL-307 (CG-S13-CPL-009, Prompt 307, "ePOD Access").
-- Read docs/adr/ADR-0024-phase8-customer-portal-access-and-transport-pattern.md,
-- supabase/migrations/20260801010000_create_customer_portal_account_scope.sql
-- (CPL-300), supabase/migrations/20260801050000_create_customer_portal_
-- shipment_order_access.sql (CPL-304, the closest structural sibling: a read
-- projection over an existing table plus a portal-owned request table, incl.
-- its post-Tier-C-fix shape -- the C-01/C-05 lessons below are applied from
-- this migration's own first draft, never retrofitted), supabase/migrations/
-- 20260728100000_create_operations_epod_capture_review.sql (OPS-177, app.
-- epod_captures -- the canonical, Operations-owned source), and supabase/
-- migrations/20260719140000_create_document_file_engine.sql (PLT-128, app.
-- files/app.file_access_logs/app.authorize_file_access) in full before this
-- migration was written.
--
-- ===========================================================================
-- Design decisions (cited where given by the orchestrating task; disclosed
-- where this checkpoint had to resolve something itself)
-- ===========================================================================
--
-- 1. **One new RPC, `app.get_customer_epod(p_tenant_id, p_actor_auth_user_id,
--    p_shipment_order_id)`.** Zero new tables -- a pure read composition over
--    the already-existing, already-VERIFIED `app.epod_captures` (OPS-177) and
--    `app.files` (PLT-128), mirroring ADR-0024 Part A exactly (a new
--    SECURITY DEFINER RPC, never a raw-RLS reopen on either source table).
--    `assert_actor_is_session_identity` is the first statement (CPL-300's own
--    Tier C lesson -- every RPC taking an identity parameter, reads included).
-- 2. **THE KNOWN BLOCKING GAP (00_EXECUTION_INDEX.md's own kickoff research,
--    re-confirmed live by this checkpoint, not merely assumed): `app.
--    epod_captures`/`app.start_epod_capture` never populate `app.files.
--    customer_account_ref`, so the generic `app.can_access_record` customer
--    branch (which composes `customer_account_ref`) can never match for an
--    ePOD evidence file.** Confirmed by direct read of both migrations in
--    full: `app.start_epod_capture` inserts `app.epod_captures` with no
--    `customer_account_ref` write anywhere in its own body or `app.
--    set_epod_evidence`'s; `app.files.customer_account_ref` is populated only
--    by `app.initiate_file_upload`'s own `p_customer_account_ref` parameter,
--    which OPS-176/177's own upload call sites never supply for an ePOD
--    evidence file (ePOD photos/signatures are staff-captured field evidence,
--    uploaded under `record_type='shipment_order'` with no customer-account
--    linkage at upload time -- a genuine, disclosed gap, not a defect this
--    task introduces).
--
--    Backfilling or widening OPS-176/177's own already-applied migrations to
--    populate this column retroactively is explicitly OUT of this bounded
--    task's own scope (a data-migration task of its own, per the
--    orchestrating task's own instruction) -- `app.epod_captures`, `app.
--    files`, `app.start_epod_capture`, `app.set_epod_evidence`, and every
--    other OPS-176/177 function are byte-for-byte untouched by this
--    migration, grep-confirmed.
--
--    Instead, this migration builds a dedicated, self-contained authorization
--    path exactly like `ATW-023`/`CPL-304`'s own pattern: `app.
--    get_customer_epod` (a) asserts caller-is-actor first, (b) scope-checks
--    the shipment order's own `shipper_account_id` against `app.
--    resolve_customer_account_scope` (the SAME anti-enumerating check `app.
--    get_customer_shipment_order`, CPL-304, already uses), (c) finds the
--    latest completed `app.epod_captures` row for that shipment (`is_latest_
--    version and status = 'completed'`), (d) independently re-verifies EVERY
--    referenced evidence file directly against `app.files` -- tenant, record
--    scope (`record_type = 'shipment_order'`, `record_id = p_shipment_order_
--    id`), soft-delete state, and live `malware_scan_status = 'clean'` --
--    never via `app.authorize_file_access`, whose own `customer_account_ref`
--    branch structurally cannot match here (decision 2 above), and (e) logs a
--    durable access-audit row and returns a customer-safe metadata
--    projection, never a fabricated signed URL (decision 8 below).
--
--    This is a deliberate, disclosed, narrower-but-safe alternative to the
--    `customer_account_ref` backfill, matching CPL-300's own precedent of
--    disclosing design alternatives explicitly rather than silently choosing
--    one: a backfill would be a genuine, separate data-migration task (every
--    already-completed ePOD capture repository-wide would need its
--    `customer_account_ref` computed and written, with its own rollback/
--    reconciliation evidence) with a materially larger blast radius than this
--    capability's own 5-15-file, 1-3-migration sizing discipline permits,
--    while this RPC-only path is purely additive, touches zero existing row,
--    and is exactly as safe (it re-derives the SAME scope fact --
--    `shipper_account_id` in this identity's resolved scope -- CPL-304
--    already proved correct for the very same shipment order).
-- 3. **`app.file_access_logs` (PLT-128) is reused directly for per-file access
--    evidence -- its own shape fits exactly** (`tenant_id`, `file_id` ->
--    `app.files`, `accessed_by_auth_user_id`, `access_type='metadata_view'`
--    (Tier C fix -- never `'signed_url_issued'`, per decision 8 below: no
--    signed URL is ever fabricated), `result` `granted`/`denied`, `reason`,
--    `correlation_id`) -- no parallel audit table is built. One row per
--    referenced evidence file,
--    granted or denied, inserted directly by this SECURITY DEFINER function
--    (running as its own owner, the same technique `app.authorize_file_
--    access` itself uses -- that table's own grants are `service_role` only,
--    unreachable directly by `authenticated`, exactly as intended). A file
--    genuinely absent from `app.files` (never actually reachable today, since
--    `app.files` is soft-delete-only and `app.set_epod_evidence` validates
--    every referenced file exists at attach time -- defensive only) is never
--    logged against a nonexistent `file_id`, which the table's own FK would
--    reject.
--
--    For the two states with no real file to log against at all --
--    genuinely-nonexistent-or-out-of-scope shipment, and a shipment with no
--    completed ePOD capture yet -- `app.capture_audit_event` carries the
--    outcome instead, on `app.shipment_orders`/`app.epod_captures` as the
--    resource, `p_reason` always a short machine-readable code, never
--    `review_notes` or any other free-text internal field (C-24 discipline).
--
--    **Disclosed deviation from CPL-300/304/305's own established "read RPCs
--    are not individually audited" precedent**: every call to this RPC
--    writes a durable audit row, successful or denied, unlike every other
--    Phase 8 read RPC to date. This is deliberate, not an oversight -- ePOD
--    evidence (a signature and delivery photos of a real person) is content
--    access in PLT-128's own sense, the exact class `app.file_access_logs`
--    was purpose-built to record ("Record actor, customer scope, ... file
--    access, denial, outcome," source prompt §18, echoing PLT-128's own
--    design), not an ordinary business-data read.
-- 4. **Anti-enumeration is NOT uniform across every failure mode -- a
--    deliberate, narrower rule than every prior Phase 8 RPC's own simpler
--    all-errors-identical shape.** A nonexistent shipment order and an
--    out-of-scope one (this identity has zero relationship to it) are
--    combined into ONE anti-enumerating `record_not_found`, mirroring `app.
--    get_customer_shipment_order` (CPL-304) byte-for-byte -- neither case may
--    ever be distinguished by an unauthorized/unrelated caller. But once
--    scope is genuinely established (the shipment order IS in this
--    identity's resolved scope -- the caller already has legitimate
--    visibility into it via CPL-304's own get/list RPCs), "no completed ePOD
--    capture exists yet" and "a completed capture's evidence is quarantined"
--    are real, honest, DISTINCT, non-error `epod_status` values returned in
--    the SAME row shape, never collapsed into each other or into a generic
--    error -- the source prompt's own alternative flow requires exactly this
--    ("If ePOD is not yet available or quarantined, show exact status").
--    These two states carry no risk of enumerating anything a legitimate,
--    in-scope caller does not already know (this shipment order's own
--    existence and their own standing on it are already established facts by
--    the time either state is reached) -- collapsing them into one generic
--    "unavailable" would actively contradict the source prompt's own literal
--    requirement without buying any real security benefit.
-- 5. **`epod_status` is a whole-capture verdict, not a per-file one.** If ANY
--    referenced evidence file fails its own live re-verification (missing,
--    wrong tenant/record scope, soft-deleted, or `malware_scan_status <>
--    'clean'`), the ENTIRE capture is reported `quarantined` and `files`
--    returns empty -- never a partial list mixing safe and unsafe evidence.
--    Simpler and safer than per-file granularity: a customer viewing "2 of 3
--    files ready, 1 blocked" gains no actionable benefit this capability's
--    own scope needs, while a single compromised/mis-scoped file silently
--    riding alongside clean ones in a partial response is exactly the kind of
--    subtle disclosure this migration's own independent re-verification
--    (decision 2(d)) exists to prevent.
-- 6. **Customer-visible fields follow the source prompt's own "minimize
--    personal data" business rule (§24).** `receiver_name`/`captured_at`/
--    `server_received_at` are returned in EVERY reachable state (`not_
--    available` excepted, where there is no capture at all) -- they are real,
--    trusted `app.epod_captures` column values, never derived from the
--    (potentially unsafe) file content itself, so withholding them while
--    `quarantined` would buy no real safety. Excluded, on direct inspection
--    of `app.epod_captures`' own full column list, as staff-internal or
--    privacy-excessive: `receiver_position` (a role/title detail with no
--    customer-facing purpose named anywhere in the source prompt), `delivery_
--    geog` (a precise `geography(Point,4326)` -- the exact "minimize personal
--    data" concern the business rule names; CPL-305's own tracking capability
--    already established that raw high-precision location data is withheld
--    from the customer projection even for the shipment's OWN vehicle
--    position, coarsening it -- this migration applies the same discipline by
--    omitting delivery_geog entirely rather than inventing a new coarsening
--    function this bounded task has no mandate to design), `reviewed_by_auth_
--    user_id`/`reviewed_at`/`review_notes` (staff-internal review workflow
--    detail -- `review_notes` in particular is free-text staff commentary,
--    the exact class CPL-304's own design decision 1 already excludes for a
--    different table, "no internal notes/reason columns"), and `milestone_
--    event_id`/`version_group_id`/`version_number`/`idempotency_key`/
--    `created_by`/`record_version` (technical/staff plumbing with no
--    customer-facing meaning, the same exclusion class CPL-304's own design
--    decision 1 already applies to `app.shipment_orders`).
-- 7. **`returns table(...)` with EVERY reference qualified by a table alias
--    from the first draft** -- CPL-304's own migration disclosed a real,
--    live-caught defect: a `returns table(...)` function's own field names
--    become implicitly-named OUT parameters visible inside the function
--    body, so an unqualified reference to a same-named real column
--    (`shipment_order_id` collides with `app.epod_captures.shipment_order_
--    id`) is genuinely ambiguous to the planner. This migration's own return
--    shape (`shipment_order_id`, `epod_status`, `epod_capture_id`, `receiver_
--    name`, `captured_at`, `server_received_at`, `files`) collides on
--    `shipment_order_id` with `app.epod_captures` -- every table reference
--    below uses an explicit alias (`so.`/`ec.`/`f.`) throughout, applying
--    CPL-304's own lesson from this migration's first draft rather than
--    retrofitting after a live failure.
-- 8. **No signed URL is fabricated.** Direct inspection of this entire
--    repository (grep across every `.ts`/`.tsx` file and every migration)
--    confirms zero live Supabase Storage integration exists anywhere --
--    `app.authorize_file_access`'s own doc comment names itself "the single
--    gate a real signed-URL-issuing server action calls BEFORE generating
--    one," and its own closest, only real consumer (`app.access_vendor_
--    compliance_document_evidence`, PRC-253) stops at exactly that boundary
--    too: authorize, log, return safe file metadata -- never a working URL
--    string, never a Storage bucket call. `supabase/config.toml` defines no
--    local storage bucket at all. Building a NEW `supabase.storage.from(...).
--    createSignedUrl(...)` call now, against a bucket that has never been
--    provisioned anywhere in this repository, would not be composing an
--    existing mechanism -- it would be inventing new, untested, unprovisioned
--    infrastructure no other capability (including PLT-128, Storage's own
--    canonical owner) has built, the exact scope-creep the orchestrating
--    task's own "compose it, do not reinvent Storage signing" instruction
--    warns against. This migration instead composes up to the SAME disclosed
--    boundary PLT-128/PRC-253 already established: `app.get_customer_epod`
--    performs the FULL authorization chain (identity, scope, evidence
--    discovery, live re-verification, durable audit) and returns granted
--    file metadata (`fileId`/`role`/`originalFilename`/`mimeType`/
--    `sizeBytes`) -- never `storage_path` (excluded from the return shape
--    entirely, mirroring `app.access_vendor_compliance_document_evidence`'s
--    own identical exclusion), never a URL. This is disclosed here, in this
--    migration's own header, exactly as explicitly as CPL-300's own design
--    alternatives -- the reasoning is the same class as decision 2 above: a
--    real, bounded gap in this repository's own current infrastructure
--    maturity, not a shortcut this task is inventing unilaterally.
-- 9. **RLS: this migration touches ZERO table.** No new table is created; no
--    RLS policy on `app.epod_captures`/`app.files`/`app.file_access_logs` is
--    edited, narrowed, or widened. `app.epod_captures`' own pre-existing
--    `epod_captures_select_scoped` policy (`app.can_access_record`, staff-
--    only in effect for a `customer_user` principal) and `app.files`' own
--    `files_select_scoped` policy are completely untouched -- both already
--    correctly deny a bare `customer_user`-layer principal by default
--    (re-verified live in this checkpoint's own db-test, not merely assumed
--    unchanged). `app.get_customer_epod` is the only sanctioned customer-
--    facing access path to ePOD evidence.
-- 10. **REST/GraphQL transport (ADR-0024 Part C)**: service layer + Server
--     Action + UI only, no `app/api/` HTTP route -- identical in kind to
--     CPL-300..306's own disclosed residual gap.
-- 11. **No edit to `scripts/db-tests/rbac-enforcement.sql`** -- `app.get_
--     customer_epod` calls `app.assert_actor_is_session_identity` directly as
--     its own first statement AND calls `app.resolve_customer_account_scope`
--     (both already-recognized base-regex authority primitives since
--     CPL-300) -- confirmed live in this checkpoint's own db-test, no edit
--     required, mirroring CPL-303/304/305/306's own identical precedent.
-- 12. **UI: extends the existing `customer-shipments/[shipmentOrderId]`
--     detail page (CPL-304, already extended by CPL-305/306)** with a new
--     sub-section, per the orchestrating task's own instruction -- never a
--     new sibling route, the same "same detail page, not a new route"
--     convention CPL-305/306 already established for this exact page.
-- 13. Per `ERR-2026-004` (`docs/runtime/ERROR_LEDGER.md`): this migration
--     carries its own explicit `revoke execute on all functions in schema
--     app from public` statement before its final grant.

-- ===========================================================================
-- app.get_customer_epod
-- ===========================================================================

create function app.get_customer_epod(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_shipment_order_id uuid
)
returns table (
  shipment_order_id uuid,
  epod_status text,
  epod_capture_id uuid,
  receiver_name text,
  captured_at timestamptz,
  server_received_at timestamptz,
  files jsonb
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_shipment app.shipment_orders;
  v_capture app.epod_captures;
  v_file app.files;
  v_file_ids uuid[] := array[]::uuid[];
  v_file_roles text[] := array[]::text[];
  v_files jsonb := '[]'::jsonb;
  v_all_clean boolean := true;
  v_deny_reason text;
  v_reason text;
  v_photo_id uuid;
  i integer;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  -- Combined anti-enumerating scope check (decision 4) -- the IDENTICAL
  -- record_not_found the caller already gets from app.get_customer_shipment_
  -- order (CPL-304) for the same shipment order.
  select so.* into v_shipment from app.shipment_orders so where so.id = p_shipment_order_id and so.tenant_id = p_tenant_id;
  if not found or not (v_shipment.shipper_account_id = any (app.resolve_customer_account_scope(p_actor_auth_user_id, p_tenant_id))) then
    perform app.capture_audit_event(
      p_tenant_id, p_actor_auth_user_id, p_actor_auth_user_id::text, 'get_customer_epod',
      'app.shipment_orders', p_shipment_order_id, 'failure', 'record_not_found', null, null
    );
    raise exception 'record_not_found: no permitted shipment order exists for %', p_shipment_order_id using errcode = 'no_data_found';
  end if;

  select ec.* into v_capture
  from app.epod_captures ec
  where ec.tenant_id = p_tenant_id
    and ec.shipment_order_id = p_shipment_order_id
    and ec.is_latest_version
    and ec.status = 'completed'
  order by ec.server_received_at desc, ec.id desc
  limit 1;

  if not found then
    perform app.capture_audit_event(
      p_tenant_id, p_actor_auth_user_id, p_actor_auth_user_id::text, 'get_customer_epod',
      'app.shipment_orders', p_shipment_order_id, 'success', 'epod_not_available', null, null
    );
    return query select p_shipment_order_id, 'not_available'::text, null::uuid, null::text, null::timestamptz, null::timestamptz, '[]'::jsonb;
    return;
  end if;

  -- Independently re-verify EVERY referenced evidence file directly against
  -- app.files -- never via app.authorize_file_access, whose own record/
  -- sensitivity gate composes app.can_access_record, which has no branch
  -- that can ever match a customer_user actor here (decision 2). Re-checks
  -- tenant/record-scope/soft-delete/scan-status LIVE at access time, never
  -- trusting OPS-176/177's own submission-time clean-scan invariant alone
  -- (C-10 discipline) -- RPD-022's own disclosed Supreme Admin absolute-CRUD
  -- residual risk means malware_scan_status is not immutable-for-all even
  -- once a capture reaches 'completed'.
  -- Tier B self-catch (this checkpoint's own first live db-test run, not
  -- reasoned about in advance): an unadorned string literal is `unknown`-
  -- typed, and `text[] || unknown` resolves to the array-concatenation
  -- operator (expecting an array-literal STRING, hence "malformed array
  -- literal") rather than the array-append-element operator. Every literal
  -- appended to v_file_roles below is explicitly cast to `text` to force
  -- scalar-append resolution.
  if v_capture.signature_file_id is not null then
    v_file_ids := v_file_ids || v_capture.signature_file_id;
    v_file_roles := v_file_roles || 'signature'::text;
  end if;
  foreach v_photo_id in array v_capture.photo_file_ids loop
    v_file_ids := v_file_ids || v_photo_id;
    v_file_roles := v_file_roles || 'photo'::text;
  end loop;

  for i in 1 .. coalesce(array_length(v_file_ids, 1), 0) loop
    select f.* into v_file from app.files f where f.id = v_file_ids[i];

    if v_file.id is null then
      v_reason := 'document_deleted';
    elsif v_file.tenant_id <> p_tenant_id or v_file.record_type <> 'shipment_order' or v_file.record_id <> p_shipment_order_id then
      v_reason := 'document_record_access_denied';
    elsif v_file.deleted_at is not null then
      v_reason := 'document_deleted';
    elsif v_file.malware_scan_status = 'infected' then
      v_reason := 'document_infected_quarantined';
    elsif v_file.malware_scan_status <> 'clean' then
      v_reason := 'document_not_yet_scanned';
    else
      v_reason := null;
    end if;

    if v_reason is null then
      v_files := v_files || jsonb_build_object(
        'fileId', v_file.id, 'role', v_file_roles[i], 'originalFilename', v_file.original_filename,
        'mimeType', v_file.mime_type, 'sizeBytes', v_file.size_bytes
      );
    else
      v_all_clean := false;
      v_deny_reason := coalesce(v_deny_reason, v_reason);
    end if;

    -- app.file_access_logs.file_id carries a real FK to app.files -- only
    -- logged when the file genuinely exists (decision 3).
    if v_file.id is not null then
      -- Tier C fix (spec-compliance Finding 1, batch review of CPL-305..309):
      -- 'metadata_view', not 'signed_url_issued' -- this function's own design
      -- decision 8 (below) is explicit that no signed URL is ever fabricated
      -- anywhere in this migration; app.file_access_logs.access_type already
      -- defines 'metadata_view' for exactly this case
      -- (20260719140000_create_document_file_engine.sql:410), and app.
      -- authorize_file_access itself already uses that literal for its own
      -- non-signed-URL metadata reads (same file, line ~640). Logging
      -- 'signed_url_issued' here would durably misrepresent, in the shared
      -- audit trail, an access event that never issued a URL.
      insert into app.file_access_logs (tenant_id, file_id, accessed_by_auth_user_id, access_type, result, reason, correlation_id)
      values (p_tenant_id, v_file.id, p_actor_auth_user_id, 'metadata_view', case when v_reason is null then 'granted' else 'denied' end, v_reason, null);
    end if;
  end loop;

  -- Defensive only -- app.submit_epod_capture (OPS-177) already requires at
  -- least one of signature/photo before a capture may ever reach
  -- 'completed', so this branch should be unreachable in practice. Treated
  -- identically to "no completed capture at all" rather than assumed
  -- impossible.
  if coalesce(array_length(v_file_ids, 1), 0) = 0 then
    perform app.capture_audit_event(
      p_tenant_id, p_actor_auth_user_id, p_actor_auth_user_id::text, 'get_customer_epod',
      'app.epod_captures', v_capture.id, 'success', 'epod_not_available', null, null
    );
    return query select p_shipment_order_id, 'not_available'::text, v_capture.id, null::text, null::timestamptz, null::timestamptz, '[]'::jsonb;
    return;
  end if;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_auth_user_id::text, 'get_customer_epod',
    'app.epod_captures', v_capture.id, case when v_all_clean then 'success' else 'failure' end,
    case when v_all_clean then null else v_deny_reason end, null,
    jsonb_build_object('epod_status', case when v_all_clean then 'available' else 'quarantined' end)
  );

  if v_all_clean then
    return query select p_shipment_order_id, 'available'::text, v_capture.id, v_capture.receiver_name, v_capture.captured_at, v_capture.server_received_at, v_files;
  else
    return query select p_shipment_order_id, 'quarantined'::text, v_capture.id, v_capture.receiver_name, v_capture.captured_at, v_capture.server_received_at, '[]'::jsonb;
  end if;
end;
$$;

comment on function app.get_customer_epod is
  'CPL-307: anti-enumerating (ADR-0024 Part A) customer-facing ePOD read. record_not_found is IDENTICAL for a genuinely nonexistent shipment order and one outside this identity''s resolved scope (mirrors app.get_customer_shipment_order, CPL-304). Once scope is established, epod_status is one of not_available (no completed capture yet) / quarantined (a completed capture exists but at least one referenced evidence file fails live re-verification) / available (every referenced file re-verified clean) -- these three are honest, distinct, non-error states, never collapsed together (decision 4). Never calls app.authorize_file_access (its customer_account_ref branch cannot match an ePOD file, decision 2) -- independently re-verifies tenant/record-scope/malware_scan_status directly against app.files. Logs one app.file_access_logs row per referenced evidence file (granted/denied) plus one app.capture_audit_event summarizing the whole-capture outcome. Returns customer-safe file metadata only -- never storage_path, never a fabricated signed URL (decision 8).';

revoke execute on all functions in schema app from public;

grant execute on function app.get_customer_epod(uuid, uuid, uuid) to authenticated, service_role;
