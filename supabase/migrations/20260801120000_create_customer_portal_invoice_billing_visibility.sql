-- Phase 8 capability CPL-311 (CG-S13-CPL-013, Prompt 311, "Invoice and
-- Billing Visibility"). The FIRST Finance-facing customer-portal RPC layer
-- in Phase 8 -- no ATW-023-style precedent exists to extend (ATW-023 is
-- Commercial/WMS-facing only; Finance built no customer-facing read path at
-- all before this migration, confirmed by direct read of
-- 20260729110000_create_finance_invoice.sql / 20260729100000_create_finance_
-- accounts_receivable.sql's own RLS -- both are `has_active_tenant_
-- membership(tenant_id) or is_supreme_admin()` only, no owner/customer
-- branch of any kind). Follows ADR-0024 Part A's shape exactly (new
-- SECURITY DEFINER RPCs, deny-by-default, mirroring CPL-309/310's own
-- already-established house style), built fresh for Finance.
--
-- ===========================================================================
-- Design decisions (disclosed, not re-derived)
-- ===========================================================================
--
-- 1. **"Finance scope" is deliberately simpler than the warehouse gate --
--    account scope alone, no second eligibility layer.** CPL-309's
--    `app.evaluate_customer_portal_inventory_access` composes TWO checks
--    (owner-account scope AND per-warehouse eligibility) because a real
--    second eligibility table (`app.warehouse_customer_eligibility`)
--    genuinely exists for that domain. No equivalent per-domain Finance
--    delegation table exists anywhere in this repository (checked before
--    writing this function, not assumed): `app.customer_portal_account_
--    memberships` (CPL-300) carries exactly two roles -- `account_admin`,
--    `member` -- with no domain/module sub-scope column of any kind, and
--    `app.accounts` itself carries no per-domain visibility flag. This
--    checkpoint's own business rule ("invoice visibility requires customer
--    finance scope, not generic shipment access alone") is therefore
--    satisfied the only way this repository's current data model allows:
--    `app.evaluate_customer_portal_invoice_access` is `p_customer_account_id
--    = any(app.resolve_customer_account_scope(...))` alone -- ANY account a
--    customer_user's Layer 4 membership resolves to (whichever role) is
--    treated as in finance scope. A member-role user who can see an
--    account's warehouse orders today also sees that same account's
--    invoices -- disclosed explicitly as `ISS-2026-121`
--    (`docs/runtime/KNOWN_ISSUES.md`), not silently assumed narrower than it
--    is. A future finance-specific delegation (e.g. a `role`-level or new
--    per-module column) is out of this prompt's own bounded scope to invent.
-- 2. **MANDATORY PATTERN, applied from the first draft, not retrofitted**:
--    every actor-taking function below -- INCLUDING the gate primitive
--    itself -- calls `app.assert_actor_is_session_identity` as its own
--    LITERAL FIRST statement, never relying on a transitive check inside a
--    helper. This is a deliberate widening of CPL-309's own precedent:
--    `app.evaluate_customer_portal_inventory_access` (CPL-309) is `language
--    sql` and relies on the transitive check inside `app.resolve_customer_
--    account_scope`; this checkpoint's batch-wide instruction is explicit
--    that this exact shape has been "the single most common Critical defect
--    class across all of Phase 8 so far," so `app.evaluate_customer_portal_
--    invoice_access` here is `language plpgsql` (not `language sql`, a
--    disclosed deviation from this prompt's own illustrative signature
--    text) specifically so it can carry its own literal assert first,
--    mirroring `app.resolve_customer_account_scope`'s (CPL-300) own
--    identical `language sql` -> `language plpgsql` conversion for the
--    identical reason.
-- 3. **One shared, internal-only gate+fetch helper --
--    `app._resolve_customer_portal_invoice` -- composed by all three read
--    RPCs, never re-derived three times.** It is NOT granted to
--    `authenticated` (service_role only, mirrors `app._ticket_link_resolve_
--    candidate`'s/`app._is_ticket_requester_party`'s own established
--    "internal adapter, no grant, no assert of its own -- every public
--    caller already asserts" convention, HRT-292/287) -- every public entry
--    point (`get_customer_portal_invoice`/`get_customer_portal_invoice_
--    lines`/`get_customer_portal_invoice_payment_status`) still calls
--    `assert_actor_is_session_identity` as ITS OWN first statement before
--    ever calling this helper (decision 2), so the helper's own omission of
--    that check is never "relying on a transitive check" -- it is relying on
--    an already-independently-proven precondition its own caller
--    established moments earlier in the SAME function body.
-- 4. **DESIGN DECISION: only `status IN ('issued', 'void')` is
--    portal-visible.** `draft`/`submitted`/`approved` are internal
--    pre-issuance lifecycle states (`app.finance_invoices_status_check`,
--    FIN-197) that must never leak to a customer -- a draft/submitted/
--    approved invoice is not yet a real financial obligation and its
--    contents (amounts, tax lines) may still change before issuance. An
--    issued-but-later-voided invoice stays visible so the customer
--    understands why it disappeared from active billing rather than
--    silently vanishing -- disclosed: no RPC anywhere in this repository
--    today actually drives `issued -> void` (`app.discard_finance_invoice_
--    draft`, FIN-197's own only void-producing RPC, operates on
--    `draft`/`submitted` only; `app.finance_lifecycle_editability` marks
--    `('invoice','issued', ...)` with an EMPTY allowed-actions array,
--    `20260729190000_create_finance_lifecycle_state_control.sql:116` --
--    confirmed by direct read, not assumed). This is forward-compatible,
--    defensive design for FIN-206's own disclosed future governed-reversal
--    scope (`20260729110000_create_finance_invoice.sql`'s own comment:
--    "Governed credit/debit/reversal correction of an issued invoice
--    remains FIN-206's own scope"), not a claim that this state is reachable
--    today. The status filter is applied INSIDE every RPC (never trusted to
--    a caller-supplied filter alone), and the not-found error for a
--    real-but-not-yet-issued invoice is textually IDENTICAL to a genuinely
--    nonexistent id or an out-of-scope one (anti-enumeration, decision 5).
-- 5. **Anti-enumeration (C-05): one shared `record_not_found` message,
--    reused verbatim by every get RPC.** Non-existence, cross-tenant,
--    pre-issuance status, and scope-denial all collapse into the identical
--    outward error inside `app._resolve_customer_portal_invoice` -- a
--    caller cannot distinguish "this invoice does not exist" from "this
--    invoice exists but is still a draft" from "this invoice belongs to a
--    different account you don't have scope over."
-- 6. **Projection never exposes internal linkage.** `company_id`/
--    `job_order_id`/`billing_readiness_handoff_id`/`posting_period_id`/
--    `ar_open_item_id` (internal Finance/Commercial/Operations linkage, not
--    customer-safe) never appear in `app.get_customer_portal_invoice`/`app.
--    list_customer_portal_invoices`'s own `RETURNS TABLE` column list --
--    confirmed by direct read of `app.finance_invoices`'s own full column
--    set before writing this projection, not assumed complete. `app.get_
--    customer_portal_invoice_lines` excludes `tax_code_id`/`tax_rule_
--    version_id` (internal Finance tax-configuration references) for the
--    identical reason. Neither `app.finance_invoices` nor `app.finance_
--    invoice_lines` carries any GL/journal/margin/vendor-cost column at all
--    (confirmed by direct read of both tables' own full DDL) -- field-
--    masking for that class of data is therefore not a concern for this
--    migration's own projection design, only access/lifecycle-state
--    masking is (matches this prompt's own upstream research note).
-- 7. **Payment/aging status is a SEPARATE, narrow read RPC --
--    `app.get_customer_portal_invoice_payment_status` -- sourced from
--    `app.finance_ar_open_items` via the invoice's own (never-exposed)
--    `ar_open_item_id`, never a persisted aging column on the invoice
--    itself (none exists -- FIN-210's own header is explicit: "aging is
--    derived, never manually editable... there is no summary balance table
--    anywhere... bucket definitions are the one governed, versioned object,
--    the aging numbers themselves are never stored, only computed").** This
--    satisfies section 15's "payment status" (open/partial/paid) UI need,
--    which the invoice's own `status` column alone cannot answer (`issued`
--    tells you the invoice was billed, not whether it has been paid) --
--    `app.finance_invoices.due_date`/`app.finance_invoices.status` alone
--    (already in the core projection) are sufficient for simple "Current"
--    vs. "Overdue" bucket display client-side, matching this prompt's own
--    "aging derived client-side or via a read RPC from finance_ar_open_
--    items.due_date" latitude; this RPC additionally surfaces the AR item's
--    own real `status`/`open_amount`/`is_held` for a genuine payment-status
--    display, still gated by the identical `app._resolve_customer_portal_
--    invoice` helper, and still never exposing `ar_open_item_id`/the AR
--    open item's own `id` itself. A `void`-before-ever-issued invoice (no
--    `ar_open_item_id`, never posted to AR) returns `payment_status =
--    'not_posted'` with null amounts -- a real, honest state, never a
--    fabricated zero.
-- 8. **No idempotency-key parameter anywhere in this migration** -- every
--    RPC here is a pure, `stable` read; the mandatory-pattern idempotency
--    rule (scope check before the idempotent short-circuit, `exception when
--    unique_violation`) does not apply to a migration with zero INSERT/
--    UPDATE statements. Disclosed, not overlooked.
-- 9. **Cursor pagination (tenant_id, updated_at desc, id desc), never
--    OFFSET** -- `app.list_customer_portal_invoices` mirrors `app.list_
--    customer_portal_inventory_balances`/`app.list_customer_portal_outbound_
--    orders`'s own established cursor shape exactly (half-supplied cursor
--    fails loud with `invalid_cursor`, hard-capped at 200).
-- 10. **`scripts/db-tests/rbac-enforcement.sql` compliance, verified by
--     direct analysis of that file's own closure sweep before writing this
--     migration, not assumed (mirrors CPL-309 design decision 12's own
--     discipline).** The `base` CTE (that file, line ~554-556) already
--     recognizes the literal substring `resolve_customer_account_scope`.
--     `app.evaluate_customer_portal_invoice_access`'s own compiled source
--     contains that literal substring (it calls the function directly), so
--     it lands in `base` directly. `app._resolve_customer_portal_invoice`
--     calls `app.evaluate_customer_portal_invoice_access`, and each of the
--     three public read RPCs calls `app._resolve_customer_portal_invoice`
--     (or, for the list RPC, `app.resolve_customer_account_scope` directly)
--     -- the `edge`/`closure` recursive CTE (same file, line ~549-568) walks
--     this call graph transitively via a literal `app\.([a-z0-9_]+)\s*\(`
--     regex match against every function's own `prosrc`, so all four public
--     functions land in `closure` without any edit to that file. The
--     SEPARATE side-effecting-actor-authority sweep further down the same
--     file (line ~599-637) only flags `provolatile = 'v'` (VOLATILE)
--     functions -- every function in this migration is `stable`, exempting
--     all of them from that sweep entirely, the identical exemption CPL-309
--     already established for its own four functions.
-- 11. **RLS on `app.finance_invoices`/`app.finance_invoice_lines`/`app.
--     finance_ar_open_items` is UNCHANGED BY THIS MIGRATION** -- confirmed
--     by direct read of each table's own already-applied RLS SELECT policy
--     before writing a single line of this migration: `finance_invoices_
--     select_scoped`/`finance_invoice_lines_select_scoped`/`finance_ar_
--     open_items_select_scoped` are each `has_active_tenant_membership(
--     tenant_id) or is_supreme_admin()` -- no owner/customer branch of any
--     kind. A `customer_user` principal holds no `app.tenant_user_
--     identities` row (`app.has_active_tenant_membership` checks exactly
--     that table), so every one of these three raw tables is ALREADY
--     unconditionally denied to a customer_user actor by construction, with
--     zero change required -- this migration's own RPCs are the only
--     sanctioned access path (ADR-0024 Part A), never a reopened/widened
--     policy.
-- 12. **'Download' is a real, working structured JSON export of the invoice
--     + its lines + its payment status, composed at the TS service layer
--     from the three read RPCs above -- no new RPC, no fabricated PDF/
--     document-generation/signed-URL pipeline.** Confirmed by direct
--     repository-wide search before writing this migration: zero
--     Storage-bucket integration, zero PDF-generation dependency, and zero
--     existing signed-URL pattern for any Finance document anywhere in this
--     repository. Matches the same class of disclosed transport/tooling gap
--     ADR-0024 Part C already accepts for GraphQL parity -- a real,
--     honestly-scoped feature (customer gets their actual billing data in a
--     structured, machine-readable file), not a stub.
-- 13. **'Dispute' composes the ALREADY-VERIFIED HRT-287 customer-ticket
--     flow via the ALREADY-VERIFIED HRT-292 `app.ticket_links` mechanism --
--     no new table, no new RPC in this migration at all.** `app.ticket_
--     links.entity_type` already includes `'invoice'` as an allowed CHECK
--     value and `app.ticket_link_customer_safe_entity_types()` already
--     includes it (`20260731170000_create_ticket_linked_records.sql`,
--     confirmed by direct read) -- `app._ticket_link_resolve_candidate`'s
--     own `'invoice'` branch already composes `app.resolve_customer_owner_
--     account_scope` (the LEGACY resolver, not this migration's own CPL-300
--     widened one) as its customer-owner branch. This is a genuine,
--     disclosed, narrow gap this migration does NOT fix (out of this
--     prompt's own bounded scope -- editing HRT-292's already-applied
--     migration is forbidden, and a `CREATE OR REPLACE` widening of
--     `app._ticket_link_resolve_candidate` to also compose the CPL-300
--     resolver is a genuinely separate, cross-cutting fix in HRT-292's own
--     domain, not CPL-311's): a customer whose invoice access exists ONLY
--     through CPL-300's new multi-account grant table (never the legacy
--     `app.principal_memberships.customer_account_ref` marker) could
--     structurally see that invoice via THIS migration's own new RPCs but
--     be unable to link it to a dispute ticket via the still-legacy-only
--     ticket-link gate -- the identical `ISS-2026-117` under-scoping SHAPE
--     (never an over-scoping leak), now surfacing for invoice ticket-links
--     specifically. This migration's own TS/UI wiring (server/mutations/
--     ticketing.ts's already-shipped `linkTicketRecord`) is otherwise a
--     plain, real, functioning call -- no parallel machinery is built.
--
-- No table is created, altered, or dropped by this migration. No existing
-- RLS policy is touched. Purely additive: 5 new functions, their grants,
-- one explicit `revoke execute on all functions in schema app from public`
-- (ERR-2026-004 convention).

-- ===========================================================================
-- 1. app.evaluate_customer_portal_invoice_access -- the new Finance gate
-- primitive (design decisions 1/2).
-- ===========================================================================

create function app.evaluate_customer_portal_invoice_access(
  p_auth_user_id uuid,
  p_tenant_id uuid,
  p_customer_account_id uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
begin
  -- Own literal first statement (decision 2) -- deliberately NOT relying on
  -- the transitive check inside app.resolve_customer_account_scope alone,
  -- a disclosed widening of CPL-309's own looser `language sql` precedent
  -- for this exact reason.
  perform app.assert_actor_is_session_identity(p_auth_user_id);

  return p_customer_account_id = any (app.resolve_customer_account_scope(p_auth_user_id, p_tenant_id));
end;
$$;

comment on function app.evaluate_customer_portal_invoice_access is
  'CPL-311 (design decision 1): the first Finance-domain customer-portal gate primitive. Deliberately simpler than app.evaluate_customer_portal_inventory_access (CPL-309, which composes a SECOND real eligibility table) -- no per-domain Finance delegation table exists anywhere in this repository today (checked against CPL-300''s own membership/role model: account_admin/member only, no sub-scope column), so account scope alone (app.resolve_customer_account_scope, the CPL-300 widened resolver) is the entire boundary. Disclosed as ISS-2026-121, not silently assumed narrower than it is.';

-- ===========================================================================
-- 2. app._resolve_customer_portal_invoice -- the ONE shared internal gate+
-- fetch helper every public read RPC composes (design decisions 3/4/5).
-- Internal only: NOT granted to authenticated.
-- ===========================================================================

create function app._resolve_customer_portal_invoice(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_invoice_id uuid
)
returns app.finance_invoices
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_invoice app.finance_invoices;
begin
  select * into v_invoice from app.finance_invoices where id = p_invoice_id and tenant_id = p_tenant_id;

  -- Anti-enumeration (decision 5): non-existence, cross-tenant, a real but
  -- not-yet-issued (draft/submitted/approved) invoice (decision 4), and a
  -- real issued/void invoice this actor has no finance scope over all raise
  -- the IDENTICAL record_not_found -- never a distinguishable cause.
  if not found or v_invoice.status not in ('issued', 'void')
     or not app.evaluate_customer_portal_invoice_access(p_actor_auth_user_id, p_tenant_id, v_invoice.customer_account_id) then
    raise exception 'record_not_found: no permitted invoice exists for %', p_invoice_id using errcode = 'no_data_found';
  end if;

  return v_invoice;
end;
$$;

comment on function app._resolve_customer_portal_invoice is
  'CPL-311 (design decision 3): internal-only gate+fetch adapter, service_role only -- mirrors app._ticket_link_resolve_candidate/app._is_ticket_requester_party''s own established "no grant, no assert of its own, every public caller already asserts" convention. Every public read RPC below calls app.assert_actor_is_session_identity as its OWN literal first statement before ever calling this helper (decision 2) -- this helper''s own omission of that check relies on an already-independently-proven precondition, never a transitive shortcut.';

-- ===========================================================================
-- 3. app.get_customer_portal_invoice -- single permitted invoice, customer-
-- safe projection (design decisions 2/4/5/6).
-- ===========================================================================

create function app.get_customer_portal_invoice(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_invoice_id uuid
)
returns table (
  id uuid,
  invoice_number text,
  currency text,
  status text,
  subtotal_amount numeric,
  tax_amount numeric,
  total_amount numeric,
  issue_date date,
  due_date date,
  record_version integer,
  updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_invoice app.finance_invoices;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  v_invoice := app._resolve_customer_portal_invoice(p_tenant_id, p_actor_auth_user_id, p_invoice_id);

  return query
  select
    v_invoice.id, v_invoice.invoice_number, v_invoice.currency, v_invoice.status,
    v_invoice.subtotal_amount, v_invoice.tax_amount, v_invoice.total_amount,
    v_invoice.issue_date, v_invoice.due_date, v_invoice.record_version, v_invoice.updated_at;
end;
$$;

comment on function app.get_customer_portal_invoice is
  'CPL-311: only status IN (issued, void) is ever returned (decision 4). Never company_id/job_order_id/billing_readiness_handoff_id/posting_period_id/ar_open_item_id -- internal linkage, not customer-safe (decision 6). record_not_found (errcode no_data_found) is identical whether the id genuinely does not exist, belongs to a different tenant, is a real but not-yet-issued invoice, or is real/issued but out of this actor''s finance scope (decision 5, anti-enumeration).';

-- ===========================================================================
-- 4. app.list_customer_portal_invoices -- cursor-paginated, same status
-- filter and column projection as the get RPC (design decisions 4/6/9).
-- ===========================================================================

create function app.list_customer_portal_invoices(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_status_filter text default null,
  p_cursor_updated_at timestamptz default null,
  p_cursor_id uuid default null,
  p_limit integer default 50
)
returns table (
  id uuid,
  invoice_number text,
  currency text,
  status text,
  subtotal_amount numeric,
  tax_amount numeric,
  total_amount numeric,
  issue_date date,
  due_date date,
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

  -- A cursor is a (timestamp, id) PAIR -- a half-supplied cursor fails loud,
  -- mirroring app.list_customer_portal_outbound_orders'/app.list_customer_
  -- portal_inventory_balances' own identical validation exactly.
  if p_cursor_id is not null and p_cursor_updated_at is null then
    raise exception 'invalid_cursor: p_cursor_updated_at is required when p_cursor_id is supplied' using errcode = 'invalid_parameter_value';
  end if;

  v_scope := app.resolve_customer_account_scope(p_actor_auth_user_id, p_tenant_id);
  v_limit := least(greatest(coalesce(p_limit, 50), 1), 200);

  -- p_status_filter is unconstrained input, but the status IN ('issued',
  -- 'void') predicate below already bounds every possible row -- a filter
  -- value outside that set (e.g. 'draft') simply matches zero rows, never an
  -- error, mirroring app.list_customer_portal_outbound_orders' own
  -- established non-validating-filter shape (design decision 4 there).
  return query
  select
    i.id, i.invoice_number, i.currency, i.status, i.subtotal_amount, i.tax_amount, i.total_amount,
    i.issue_date, i.due_date, i.record_version, i.updated_at
  from app.finance_invoices i
  where i.tenant_id = p_tenant_id
    and i.status in ('issued', 'void')
    and i.customer_account_id = any (v_scope)
    and (p_status_filter is null or i.status = p_status_filter)
    and (p_cursor_id is null or (i.updated_at, i.id) < (p_cursor_updated_at, p_cursor_id))
  order by i.updated_at desc, i.id desc
  limit v_limit;
end;
$$;

comment on function app.list_customer_portal_invoices is
  'CPL-311: bounded (p_limit default 50, hard-capped 200), keyset-paginated on (updated_at desc, id desc), never OFFSET. Scoped by app.resolve_customer_account_scope (CPL-300 widened resolver) AND status IN (issued, void). A caller whose resolved scope is empty gets zero rows, never an error.';

-- ===========================================================================
-- 5. app.get_customer_portal_invoice_lines -- customer-safe line projection,
-- excludes tax_code_id/tax_rule_version_id (design decision 6).
-- ===========================================================================

create function app.get_customer_portal_invoice_lines(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_invoice_id uuid
)
returns table (
  line_number integer,
  line_type text,
  description text,
  amount numeric
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_invoice app.finance_invoices;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  v_invoice := app._resolve_customer_portal_invoice(p_tenant_id, p_actor_auth_user_id, p_invoice_id);

  return query
  select l.line_number, l.line_type, l.description, l.amount
  from app.finance_invoice_lines l
  where l.invoice_id = v_invoice.id
  order by l.line_number asc;
end;
$$;

comment on function app.get_customer_portal_invoice_lines is
  'CPL-311: never tax_code_id/tax_rule_version_id -- internal Finance tax-configuration references (decision 6). Reuses app._resolve_customer_portal_invoice''s own gate -- record_not_found (identical to app.get_customer_portal_invoice''s own anti-enumerating shape) if the invoice is missing, not yet issued, or out of this actor''s finance scope.';

-- ===========================================================================
-- 6. app.get_customer_portal_invoice_payment_status -- payment/aging status,
-- sourced from app.finance_ar_open_items via the invoice's own (never
-- exposed) ar_open_item_id (design decision 7).
-- ===========================================================================

create function app.get_customer_portal_invoice_payment_status(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_invoice_id uuid
)
returns table (
  payment_status text,
  original_amount numeric,
  open_amount numeric,
  is_held boolean
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_invoice app.finance_invoices;
  v_ar app.finance_ar_open_items;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  v_invoice := app._resolve_customer_portal_invoice(p_tenant_id, p_actor_auth_user_id, p_invoice_id);

  if v_invoice.ar_open_item_id is null then
    -- A void-before-ever-issued invoice was never posted to AR -- a real,
    -- honest state, never a fabricated zero (decision 7).
    return query select 'not_posted'::text, null::numeric, null::numeric, null::boolean;
    return;
  end if;

  select * into v_ar from app.finance_ar_open_items where id = v_invoice.ar_open_item_id and tenant_id = p_tenant_id;
  if not found then
    return query select 'not_posted'::text, null::numeric, null::numeric, null::boolean;
    return;
  end if;

  return query select v_ar.status, v_ar.original_amount, v_ar.open_amount, v_ar.is_held;
end;
$$;

comment on function app.get_customer_portal_invoice_payment_status is
  'CPL-311 (design decision 7): payment_status is app.finance_ar_open_items.status (open/partial/paid) for an issued invoice''s own posted AR item, or the synthesized "not_posted" for the rare void-before-issuance case (no AR item was ever created). Never exposes ar_open_item_id or the AR open item''s own id -- internal linkage only. Gated by the identical app._resolve_customer_portal_invoice helper every other RPC in this migration uses.';

-- ===========================================================================
-- Grants (design decision 10 -- rbac-enforcement.sql closure covers all four
-- public functions transitively, no edit to that file required).
-- ===========================================================================

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit, directly-provable
-- revoke of PostgreSQL's PUBLIC-execute default, the standing per-migration
-- convention since PLT-118, applied here before any role-specific grant.
revoke execute on all functions in schema app from public;

grant execute on function app.evaluate_customer_portal_invoice_access(uuid, uuid, uuid) to authenticated, service_role;
grant execute on function app._resolve_customer_portal_invoice(uuid, uuid, uuid) to service_role;
grant execute on function app.get_customer_portal_invoice(uuid, uuid, uuid) to authenticated, service_role;
grant execute on function app.list_customer_portal_invoices(uuid, uuid, text, timestamptz, uuid, integer) to authenticated, service_role;
grant execute on function app.get_customer_portal_invoice_lines(uuid, uuid, uuid) to authenticated, service_role;
grant execute on function app.get_customer_portal_invoice_payment_status(uuid, uuid, uuid) to authenticated, service_role;
