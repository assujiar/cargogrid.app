-- Phase 8 capability CPL-312 (CG-S13-CPL-014, Prompt 312, "Payment
-- Visibility"). Depends on CPL-311 (supabase/migrations/
-- 20260801120000_create_customer_portal_invoice_billing_visibility.sql,
-- Invoice and Billing Visibility, read in full before this migration was
-- written), whose new `app.evaluate_customer_portal_invoice_access` gate
-- primitive and `app._resolve_customer_portal_invoice` internal gate+fetch
-- helper this migration REUSES BY DIRECT CALL, byte-for-byte, never
-- re-derived a third time (ADR-0024 Part A's own "compose, don't
-- re-derive" discipline, the identical technique CPL-309 already applied
-- to `app.customer_warehouse_eligibility_active`).
--
-- Also read in full before this migration was written:
-- supabase/migrations/20260729120000_create_finance_receipt_allocation.sql
-- (FIN-198, `app.finance_receipts`/`app.finance_receipt_allocations`) and
-- supabase/migrations/20260729100000_create_finance_accounts_receivable.sql
-- (FIN-196, `app.finance_ar_open_items`).
--
-- ===========================================================================
-- Design decisions (disclosed, not re-derived)
-- ===========================================================================
--
-- 1. **The invoice<->payment link is a real two-hop join, confirmed by
--    direct DDL read before writing a single line of this migration --
--    there is NO direct receipt->invoice foreign key anywhere in this
--    repository.** `app.finance_invoices.ar_open_item_id` ->
--    `app.finance_ar_open_items.id` <- `app.finance_receipt_allocations.
--    ar_open_item_id` <- `app.finance_receipt_allocations.receipt_id` ->
--    `app.finance_receipts.id`. `app.get_customer_portal_payment_status`
--    below performs exactly this join, scoped by the SAME already-gated
--    invoice `app._resolve_customer_portal_invoice` returns -- it never
--    accepts a caller-supplied `ar_open_item_id`/`receipt_id` of its own
--    (neither is a parameter anywhere in this migration), precisely because
--    both are the same class of internal linkage CPL-311's own design
--    decision 6 already ruled must never be customer-supplied or
--    customer-visible.
-- 2. **MANDATORY PATTERN, applied from the first draft**: both public
--    functions below call `app.assert_actor_is_session_identity` as their
--    own literal first statement, never relying solely on the transitive
--    check already inside `app._resolve_customer_portal_invoice`/`app.
--    resolve_customer_account_scope` -- mirrors CPL-311's own identical
--    discipline, itself a deliberate widening of CPL-309's looser
--    `language sql` precedent.
-- 3. **Gate reuse, not re-derivation (the batch's own explicit instruction
--    for this prompt).** `app.get_customer_portal_payment_status` calls
--    `app._resolve_customer_portal_invoice` DIRECTLY (CPL-311's own
--    internal, `service_role`-only gate+fetch adapter -- composing an
--    internal `SECURITY DEFINER` helper from another new `SECURITY
--    DEFINER` function in the same schema needs no new grant, the
--    identical composition CPL-311's own `get_customer_portal_invoice`/
--    `get_customer_portal_invoice_lines`/`get_customer_portal_invoice_
--    payment_status` already use), which itself composes `app.evaluate_
--    customer_portal_invoice_access` (resolved against the invoice's own
--    `customer_account_id`) and the identical anti-enumerating
--    `record_not_found` shape -- never a second, independently-evolving
--    copy of either. `app.list_customer_portal_receipts` calls `app.
--    resolve_customer_account_scope` directly, the same widened CPL-300
--    resolver every other Phase 8 list RPC composes. Neither `app.
--    evaluate_customer_portal_invoice_access` nor `app._resolve_customer_
--    portal_invoice` nor `app.resolve_customer_account_scope` is
--    `CREATE OR REPLACE`d anywhere in this migration -- grep-confirmed
--    zero such statement in this file.
--    Not chosen: calling CPL-311's own PUBLIC `app.get_customer_portal_
--    invoice_payment_status` sibling RPC instead of the internal helper.
--    Rejected because that function deliberately never returns `ar_open_
--    item_id` (CPL-311 design decision 6/7's own "never exposed" rule) --
--    exactly the internal linkage this migration's own join needs
--    (internally only, never returned to the client) to reach `app.
--    finance_receipt_allocations`. Composing the SMALLEST shared primitive
--    genuinely available (the gate+fetch helper) is preferred over
--    composing the smallest OBSERVABLE public RPC, mirroring CPL-309's own
--    "compose the shared authority primitive, not necessarily every
--    downstream RPC" discipline. The AR-open-item lookup itself (`status`/
--    `original_amount`/`open_amount`/`is_held` from `app.finance_ar_open_
--    items`, ~10 lines) is therefore duplicated from CPL-311's own `app.
--    get_customer_portal_invoice_payment_status` rather than composed by
--    calling that sibling public RPC a second time -- a small, disclosed
--    duplication in exchange for a strictly smaller, already-proven-safe
--    dependency surface (one internal helper instead of a second public
--    RPC hop with its own redundant `assert_actor_is_session_identity`
--    re-check and a second round of anti-enumeration collapsing).
-- 4. **Anti-enumeration (C-05), inherited, not re-implemented.** `app.
--    get_customer_portal_payment_status` raises the IDENTICAL
--    `record_not_found` (errcode `no_data_found`) CPL-311's own `app.
--    _resolve_customer_portal_invoice` already raises for a genuinely
--    nonexistent invoice id, a cross-tenant id, a real-but-not-yet-issued
--    invoice, or a real issued/void invoice outside this actor's finance
--    scope -- because it IS that same function's own error, propagated
--    unchanged, never re-wrapped or re-worded.
-- 5. **`bank_account_label` is NEVER selected anywhere in this migration --
--    structurally, not merely filtered.** Neither public function's own
--    `RETURNS TABLE`/jsonb payload shape has any column or key capable of
--    carrying it; grep-confirmed zero reference to `bank_account_label`
--    anywhere in this file. `app.finance_receipts`/`app.finance_receipt_
--    allocations`' own already-applied RLS (FIN-198, `has_active_tenant_
--    membership(tenant_id) or is_supreme_admin()`, no owner/customer
--    branch of any kind, re-confirmed by direct read before this migration
--    was written) already denies a `customer_user` actor outright at the
--    raw-table layer -- these two new functions are the only sanctioned
--    customer-facing read path this migration adds, matching every prior
--    Phase 8 Finance-facing capability's own disclosed RLS-untouched
--    posture (CPL-311 design decision 11).
-- 6. **`payer_name` -- explicit judgment, disclosed here rather than
--    silently guessed.** `app.finance_receipts.payer_name` is free text
--    with no structural marker distinguishing "the customer's own legal
--    name" from "a third party who paid on the customer's behalf" (a
--    factor, guarantor, forwarder, or an affiliated but legally distinct
--    entity in the same corporate group) -- confirmed by direct DDL read:
--    the column is a bare nullable `text`, no `payer_type`/`is_self_pay`
--    flag or FK to `app.accounts` exists anywhere to test against. Because
--    this migration cannot programmatically tell "the customer's own name"
--    from "a real third party's name" from the data alone, and because
--    business rule 3 ("Bank account internal details and reconciliation
--    workpapers are hidden") already establishes that receipt-side
--    metadata beyond the payment's OWN economic facts is not customer-safe
--    by default, `payer_name` is HIDDEN GLOBALLY from both functions below
--    -- never returned, whether or not it happens to match the customer's
--    own name in a given row. This is the conservative reading of "hide
--    payer_name only if it can reveal a third party's identity": since
--    there is no reliable way to prove a GIVEN row's payer_name is safe,
--    treating every row identically (always hidden) is the only choice
--    that cannot leak a third party's identity by mistake. `receipt_
--    reference` (a bank/transaction reference the customer themselves
--    would recognize from their own remittance) is kept -- it identifies
--    the payment, not a third party.
-- 7. **`hold_reason` is NEVER exposed, mirroring CPL-311's own already-
--    established precedent for the identical column** (CPL-311 design
--    decision 7's own disclosure: "with its own real hold_reason set,
--    never surfaced by this RPC's own narrow projection"). `hold_reason`
--    is free text written by Finance staff (e.g. "escalate to collections",
--    an internal case reference, a colleague's name) with no CHECK-
--    constrained vocabulary to safely generalize into a customer-facing
--    category. `app.get_customer_portal_payment_status` therefore surfaces
--    ONLY the boolean `is_held` -- a real, honest, customer-safe signal
--    ("this balance is currently on hold") -- never the raw reason text.
--    The existing invoice detail page (CPL-311) already renders a
--    "Payment on hold" banner from this exact boolean; this migration adds
--    no second, redundant masking scheme.
-- 8. **There is NO `reconciliation-status` column anywhere in this schema
--    -- confirmed by direct DDL read of `app.finance_receipts`/`app.
--    finance_receipt_allocations`/`app.finance_ar_open_items` before this
--    migration was written.** The source prompt's own §13/§15/§22 use the
--    phrase loosely ("reconciliation state," "pending reconciliation");
--    this migration maps it to the REAL status values that exist, and
--    states the mapping explicitly rather than inventing a column:
--      - `app.finance_receipts.status` (`captured`/`void`) -- whether the
--        receipt itself is a live, uncancelled cash receipt.
--      - `app.finance_receipt_allocations.status` (`applied`/`reversed`) --
--        whether a specific allocation of that receipt to an AR open item
--        currently counts. `app.get_customer_portal_payment_status` below
--        includes ONLY `status = 'applied'` allocations in its own
--        `allocations` list -- a `reversed` allocation is, by construction,
--        no longer part of this invoice's real payment history (`app.
--        finance_ar_open_items.allocated_amount` is already decremented
--        the moment a reversal posts, `app.reverse_finance_ar_allocation`,
--        FIN-196), so surfacing a reversed line here would show the
--        customer money that no longer counts toward their own balance --
--        a genuine, disclosed exclusion, not an oversight.
--      - `app.finance_ar_open_items.status` (`open`/`partial`/`paid`) plus
--        `is_held`/`hold_reason` -- the real source for the source
--        prompt's own "paid/partial/unpaid" and "blocked" UI language
--        (business rule/§15), reused verbatim from CPL-311's own identical
--        mapping (that migration's design decision 7).
--      - "Pending reconciliation" (source prompt §22 alternative flow) has
--        no dedicated status value anywhere in this schema either -- the
--        closest honest equivalent this migration's own data can support is
--        a receipt whose `unapplied_amount > 0` (cash captured, not yet, or
--        not fully, applied to any open item) -- `app.list_customer_portal_
--        receipts` below returns `unapplied_amount` precisely so the UI can
--        render that state honestly, without this migration inventing a
--        status value the database does not have.
-- 9. **Both real receipt statuses (`captured`/`void`) are portal-visible on
--    the list -- a DELIBERATE divergence from CPL-311's own invoice status
--    filter, disclosed here, not a copy-paste of that filter.** CPL-311
--    hides `draft`/`submitted`/`approved` invoices because those are
--    genuinely not-yet-real financial obligations whose amounts may still
--    change before issuance (CPL-311 design decision 4). A receipt has no
--    equivalent pre-capture lifecycle stage in this schema -- `app.
--    finance_receipts.status` defaults straight to `'captured'` on insert
--    (FIN-198, `app.capture_finance_receipt`) and only ever transitions to
--    `'void'` as a later correction. A voided receipt genuinely happened
--    and was later voided -- showing it (with its own real, unmistakable
--    `void` status badge) is honest disclosure, not a leak of an
--    unfinalized figure, the same reasoning CPL-311 itself already applied
--    to keep a voided INVOICE visible rather than hidden.
-- 10. **jsonb payload keys inside the `allocations` array are camelCase
--    (`receiptReference`/`receiptDate`/`amount`/`currency`), not
--    snake_case -- a deliberate, precedented divergence from this
--    migration's own top-level `RETURNS TABLE` columns, which stay
--    snake_case matching every other Phase 8 RPC's plain column-projection
--    convention.** This mirrors an already-established, non-Phase-8
--    precedent in this exact repository: `app.get_billing_readiness_
--    detail` (`20260728140000_create_operations_billing_readiness.sql:207`)
--    already builds a `jsonb_agg(jsonb_build_object('checklistItemId', ...,
--    'documentTypeCode', ...))` payload with camelCase keys for the
--    identical reason -- a synthesized jsonb payload has no underlying
--    column of its own to name after, so choosing the TypeScript-side
--    field name directly at the SQL layer avoids a redundant snake_case ->
--    camelCase remap step for nested array elements at the contract
--    boundary (`server/contracts/customer-portal-payment/customer-portal-
--    payment.ts` parses these keys directly, with no per-element mapping
--    function).
-- 11. **RPD-032 ("payment documents follow scan and signed URL rules") --
--    disclosed gap, not fabricated, mirroring CPL-311's own identical
--    disclosure for invoice PDFs.** Checked directly before writing this
--    migration, not assumed: `app.finance_receipts` carries no `file_id`/
--    attachment column of any kind (confirmed by direct DDL read, FIN-198)
--    -- there is no receipt-attachment upload path anywhere in this
--    repository to compose. CPL-308's own Document Center
--    (`20260801090000_create_customer_portal_document_center.sql`, already
--    applied, Batch 2, VERIFIED -- never edited by this migration) already
--    recognizes a fixed 4-value `p_source_module` enum
--    (`quote_request`/`epod`/`invoice`/`ticket`) with `invoice`/`ticket`
--    themselves still only "recognized but honestly empty" placeholders
--    (that migration's own design decision 2) -- `receipt` is not a
--    recognized value there at all, and this migration does not add one:
--    doing so would require a `CREATE OR REPLACE` against an already-
--    applied, already-`VERIFIED` migration's function, forbidden by
--    `AGENTS.md`'s "never edit an applied migration" rule, and genuinely
--    out of this prompt's own bounded scope (a receipt-attachment upload
--    pipeline is a capability-sized addition in its own right, not a
--    bounded extension of a read-visibility prompt). No signed-URL, no
--    scan-status field, no fabricated attachment list is invented anywhere
--    in this migration -- `app.list_customer_portal_receipts`' own
--    `RETURNS TABLE` carries no file-shaped column at all. Not registered
--    as a new `docs/runtime/KNOWN_ISSUES.md` entry: this is the identical
--    class of disclosed, non-blocking tooling gap CPL-311 already recorded
--    inline (its own design decision 12, "no fabricated PDF/document-
--    generation/signed-URL pipeline") without a dedicated ledger entry,
--    and CPL-308's own already-`invoice`/`ticket` placeholder gap already
--    covers the general "not every document source is wired yet" shape --
--    adding a fourth near-duplicate disclosure would not surface new,
--    actionable information beyond what this header and the build log
--    already state plainly.
-- 12. **No idempotency-key parameter anywhere** -- both functions are pure,
--    `stable` reads; the mandatory idempotency rule (scope check before the
--    idempotent short-circuit, `exception when unique_violation`) does not
--    apply to a migration with zero `insert`/`update` statements.
-- 13. **Cursor pagination (`tenant_id`, `updated_at desc`, `id desc`), never
--    `OFFSET`** -- `app.list_customer_portal_receipts` mirrors `app.list_
--    customer_portal_invoices`'s own established cursor shape exactly,
--    including the identical half-supplied-cursor `invalid_cursor` guard.
--    One new covering index, `finance_receipts_tenant_updated_id_idx` on
--    `app.finance_receipts (tenant_id, updated_at desc, id desc)`, added
--    inline in this migration (mirrors CPL-300's own established "inline
--    covering index, not a companion migration" precedent) -- FIN-198's own
--    two indexes (`(tenant_id, customer_account_id)`/`(tenant_id, status)`)
--    do not cover the `updated_at`/`id` ordering this new list RPC needs.
-- 14. **`scripts/db-tests/rbac-enforcement.sql` compliance, verified by
--    direct analysis of that file's own closure sweep before writing this
--    migration (mirrors CPL-309/311's own identical discipline), then
--    live-confirmed in this checkpoint's own db-test run.** The `base` CTE
--    already recognizes the literal substring `resolve_customer_account_
--    scope`. `app.list_customer_portal_receipts` calls it directly, so it
--    lands in `base` directly. `app.evaluate_customer_portal_invoice_
--    access` (CPL-311) is already in `base` (it calls `resolve_customer_
--    account_scope` directly, in ITS OWN body); `app._resolve_customer_
--    portal_invoice` (CPL-311) calls `app.evaluate_customer_portal_
--    invoice_access`, landing it in `closure` via one recursion step; `app.
--    get_customer_portal_payment_status` (this migration) calls `app.
--    _resolve_customer_portal_invoice` directly, landing IT in `closure`
--    via one more recursion step -- exactly the same transitive-closure
--    walk CPL-311's own build log already proved for its own three public
--    RPCs, now covering this migration's own new caller with zero edit to
--    that shared file required. The separate side-effecting-actor-authority
--    sweep further down the same file only flags `provolatile = 'v'`
--    (VOLATILE) functions -- both functions in this migration are `stable`,
--    exempting both from that sweep entirely.
-- 15. **RLS on `app.finance_receipts`/`app.finance_receipt_allocations`/
--    `app.finance_ar_open_items` is UNCHANGED BY THIS MIGRATION** --
--    confirmed by direct read of each table's own already-applied RLS
--    `SELECT` policy before writing a single line of this migration:
--    `finance_receipts_select_scoped`/`finance_receipt_allocations_select_
--    scoped`/`finance_ar_open_items_select_scoped` are each `has_active_
--    tenant_membership(tenant_id) or is_supreme_admin()` -- no owner/
--    customer branch of any kind, so a `customer_user` principal (who holds
--    no `app.tenant_user_identities` row) is already unconditionally denied
--    at the raw-table layer, with zero change required. This migration's
--    two new functions are the only sanctioned customer-facing access path
--    added.
-- 16. **REST/GraphQL transport (ADR-0024 Part C)**: service layer + Server
--    Component fetch + UI only, no `app/api/` HTTP route -- identical in
--    kind to CPL-300..311's own disclosed residual gap.
-- 17. Per `ERR-2026-004` (`docs/runtime/ERROR_LEDGER.md`): this migration
--    carries its own explicit `revoke execute on all functions in schema
--    app from public` statement before its final grants.
--
-- No table is created, altered, or dropped by this migration beyond the one
-- new index (decision 13). No existing RLS policy is touched, and no
-- pre-existing function is `CREATE OR REPLACE`d -- grep-confirmed zero such
-- statement anywhere in this file. Purely additive: 1 new index, 2 new
-- functions, their grants, one explicit `revoke execute on all functions in
-- schema app from public` (ERR-2026-004 convention).

-- ===========================================================================
-- 1. New covering index for app.list_customer_portal_receipts' own cursor
-- shape (design decision 13). FIN-198's own two indexes do not cover this
-- ordering.
-- ===========================================================================

create index finance_receipts_tenant_updated_id_idx
  on app.finance_receipts (tenant_id, updated_at desc, id desc);

-- ===========================================================================
-- 2. app.get_customer_portal_payment_status -- reuses app._resolve_
-- customer_portal_invoice (CPL-311) for the gate+fetch, then joins the
-- invoice's own (never-exposed) ar_open_item_id to app.finance_ar_open_items
-- and, through it, to app.finance_receipt_allocations/app.finance_receipts
-- (design decisions 1/3/4/8/10).
-- ===========================================================================

create function app.get_customer_portal_payment_status(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_invoice_id uuid
)
returns table (
  payment_status text,
  original_amount numeric,
  open_amount numeric,
  is_held boolean,
  allocations jsonb
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_invoice app.finance_invoices;
  v_ar app.finance_ar_open_items;
  v_allocations jsonb;
begin
  -- Own literal first statement (design decision 2) -- not merely relying
  -- on the transitive check inside app._resolve_customer_portal_invoice.
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  -- Reuses CPL-311's own internal gate+fetch helper directly (design
  -- decision 3) -- the SAME anti-enumerating record_not_found (design
  -- decision 4) for a nonexistent id, a cross-tenant id, a real-but-not-
  -- yet-issued invoice, or a real invoice out of this actor's finance
  -- scope. Never re-derives app.evaluate_customer_portal_invoice_access.
  v_invoice := app._resolve_customer_portal_invoice(p_tenant_id, p_actor_auth_user_id, p_invoice_id);

  if v_invoice.ar_open_item_id is null then
    -- A void-before-ever-issued invoice was never posted to AR -- the
    -- identical honest "not_posted" state CPL-311's own sibling RPC
    -- already synthesizes, never a fabricated zero. Zero allocations can
    -- exist for an item that was never posted.
    return query select 'not_posted'::text, null::numeric, null::numeric, null::boolean, '[]'::jsonb;
    return;
  end if;

  select * into v_ar from app.finance_ar_open_items where id = v_invoice.ar_open_item_id and tenant_id = p_tenant_id;
  if not found then
    return query select 'not_posted'::text, null::numeric, null::numeric, null::boolean, '[]'::jsonb;
    return;
  end if;

  -- Only status = 'applied' allocations count (design decision 8) -- a
  -- reversed allocation no longer contributes to this invoice's own real
  -- balance (app.finance_ar_open_items.allocated_amount is already
  -- decremented the moment a reversal posts, FIN-196), so surfacing a
  -- reversed line here would show the customer money that no longer
  -- counts. Never bank_account_label/payer_name (design decisions 5/6).
  -- camelCase jsonb keys (design decision 10).
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'receiptReference', r.receipt_reference,
        'receiptDate', r.receipt_date,
        'amount', ra.amount,
        'currency', r.currency
      )
      order by r.receipt_date asc, ra.created_at asc
    ),
    '[]'::jsonb
  )
  into v_allocations
  from app.finance_receipt_allocations ra
  join app.finance_receipts r on r.id = ra.receipt_id and r.tenant_id = p_tenant_id
  where ra.tenant_id = p_tenant_id
    and ra.ar_open_item_id = v_ar.id
    and ra.status = 'applied';

  return query select v_ar.status, v_ar.original_amount, v_ar.open_amount, v_ar.is_held, v_allocations;
end;
$$;

comment on function app.get_customer_portal_payment_status is
  'CPL-312: the invoice''s own real AR status (open/partial/paid, from app.finance_ar_open_items) or the synthesized not_posted state, plus is_held (never the raw hold_reason -- design decision 7), plus a jsonb array of every status=''applied'' receipt allocation against that same AR open item (receiptReference/receiptDate/amount/currency -- NEVER bank_account_label/payer_name, design decisions 5/6). Reuses app._resolve_customer_portal_invoice (CPL-311) for the identical anti-enumerating gate+fetch -- never re-derives app.evaluate_customer_portal_invoice_access. The invoice''s own ar_open_item_id is used internally to join app.finance_receipt_allocations/app.finance_receipts (the real two-hop link, design decision 1) but is never itself returned.';

-- ===========================================================================
-- 3. app.list_customer_portal_receipts -- cursor-paginated, account-scoped
-- via app.resolve_customer_account_scope directly (design decisions 3/9/13).
-- ===========================================================================

create function app.list_customer_portal_receipts(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_status_filter text default null,
  p_cursor_updated_at timestamptz default null,
  p_cursor_id uuid default null,
  p_limit integer default 50
)
returns table (
  id uuid,
  customer_account_id uuid,
  receipt_reference text,
  receipt_date date,
  currency text,
  amount numeric,
  allocated_amount numeric,
  unapplied_amount numeric,
  status text,
  record_version integer,
  updated_at timestamptz
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

  -- A cursor is a (timestamp, id) PAIR -- half-supplied fails loud,
  -- mirroring app.list_customer_portal_invoices' own identical validation.
  if p_cursor_id is not null and p_cursor_updated_at is null then
    raise exception 'invalid_cursor: p_cursor_updated_at is required when p_cursor_id is supplied' using errcode = 'invalid_parameter_value';
  end if;

  v_scope := app.resolve_customer_account_scope(p_actor_auth_user_id, p_tenant_id);
  v_limit := least(greatest(coalesce(p_limit, 50), 1), 200);

  -- Both real statuses (captured/void) are portal-visible (design decision
  -- 9) -- p_status_filter is unconstrained input, but a value outside the
  -- real CHECK-constrained set simply matches zero rows, never an error
  -- (mirrors app.list_customer_portal_invoices' own non-validating-filter
  -- shape). Never bank_account_label/payer_name (design decisions 5/6).
  return query
  select
    r.id, r.customer_account_id, r.receipt_reference, r.receipt_date, r.currency, r.amount,
    r.allocated_amount, r.unapplied_amount, r.status, r.record_version, r.updated_at
  from app.finance_receipts r
  where r.tenant_id = p_tenant_id
    and r.customer_account_id = any (v_scope)
    and (p_status_filter is null or r.status = p_status_filter)
    and (p_cursor_id is null or (r.updated_at, r.id) < (p_cursor_updated_at, p_cursor_id))
  order by r.updated_at desc, r.id desc
  limit v_limit;
end;
$$;

comment on function app.list_customer_portal_receipts is
  'CPL-312: bounded (p_limit default 50, hard-capped 200), keyset-paginated on (updated_at desc, id desc), never OFFSET. Scoped by app.resolve_customer_account_scope (CPL-300 widened resolver) -- a caller whose resolved scope is empty gets zero rows, never an error. Both real app.finance_receipts.status values (captured/void) are returned (design decision 9) -- never bank_account_label/payer_name (design decisions 5/6, structurally absent from this RETURNS TABLE shape).';

-- ===========================================================================
-- Grants (design decision 14 -- rbac-enforcement.sql closure covers both
-- public functions transitively, no edit to that file required).
-- ===========================================================================

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit, directly-provable
-- revoke of PostgreSQL's PUBLIC-execute default, the standing per-migration
-- convention since PLT-118, applied here before any role-specific grant.
revoke execute on all functions in schema app from public;

grant execute on function app.get_customer_portal_payment_status(uuid, uuid, uuid) to authenticated, service_role;
grant execute on function app.list_customer_portal_receipts(uuid, uuid, text, timestamptz, uuid, integer) to authenticated, service_role;
