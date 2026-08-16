-- Phase 8 capability CPL-303 (CG-S13-CPL-005, Prompt 303, "Booking"). Read
-- docs/adr/ADR-0024-phase8-customer-portal-access-and-transport-pattern.md,
-- supabase/migrations/20260801010000_create_customer_portal_account_scope.sql
-- (CPL-300) and supabase/migrations/20260801030000_create_customer_portal_
-- quote_requests.sql (CPL-302) in full before this migration was written --
-- this capability follows CPL-302's own already-proven request/intent shape
-- exactly: a new portal-owned table, never a direct write into any staff-
-- gated canonical mutation RPC (app.prepare_job_order_handoff/app.
-- prepare_job_order/app.create_shipment_order_from_job all stay byte-for-
-- byte untouched, confirmed unmodified by this migration -- see design
-- decision 1), and staff conversion stays a real, separate, RBAC-gated
-- acknowledgement RPC.
--
-- ===========================================================================
-- Design decisions (cited, not re-derived -- given by the orchestrating task)
-- ===========================================================================
--
-- 1. **A new portal-owned booking request/intent table, never a direct call
--    into app.job_order_handoffs/app.job_orders/app.shipment_orders' own
--    staff-gated creation RPCs.** app.prepare_job_order_handoff (COM:Edit,
--    20260724340000_create_commercial_job_order_lineage.sql) and app.
--    prepare_job_order/app.create_shipment_order_from_job (both OPS:Create,
--    20260727090000/20260727100000) are read in full and confirmed staff-
--    RBAC-gated -- none is called from any function in this migration. A
--    customer submits a REQUEST; a staff/system actor runs the real,
--    unmodified canonical pipeline separately and then acknowledges the
--    outcome back onto this table via the one staff-gated RPC below (item
--    8). linked_quote_request_id (nullable) supports the accepted-quote
--    origin flow; a null value supports the "direct service booking"
--    alternative flow the source prompt's own §21/§9 (upstream: CPL-300,
--    CPL-302) explicitly allows -- both are first-class, not one a fallback
--    of the other.
-- 2. **pickup/delivery are bounded jsonb address+contact snapshots, not a
--    location/contact master.** Mirrors CPL-302's own origin/destination
--    design decision 2 exactly -- no canonical address/contact master exists
--    yet in this repository. Each must be a JSON object (never a scalar/
--    array), matching CPL-302's own cpqr_origin_check/cpqr_destination_check
--    convention.
-- 3. **A booking "accepted quote" origin means the linked quote request has
--    already reached CPL-302's own `converted` status** (staff has already
--    turned it into a real app.quotations row via app.link_customer_quote_
--    request_to_quotation) -- the closest concept this repository has to "an
--    accepted quote" (CPL-302's own status machine has no separate
--    "accepted" state; `converted` is the point a customer-visible request
--    became a real quotation). A still-draft/submitted/cancelled quote
--    request may not be linked (quote_request_not_accepted) -- disclosed
--    interpretation, not given verbatim by the source prompt, which only
--    said "an accepted quote request." Also enforced: the linked quote
--    request must belong to the SAME account_id as the booking
--    (quote_request_account_mismatch) and must itself be within this
--    identity's resolved scope (the same anti-enumeration-shaped
--    quote_request_not_found a forged/unowned/nonexistent id would produce).
-- 4. **Two distinct concurrency-relevant behaviors are DELIBERATELY simpler
--    than CPL-302's own two-idempotency-key split**, because the given
--    column list for this table (the orchestrating task's own instruction,
--    followed literally) carries exactly ONE `idempotency_key` column, used
--    only by app.create_customer_booking_request_draft (the general CPL-300
--    "idempotency_key on every create" house style). app.submit_customer_
--    booking_request therefore does not take or require a second key at
--    all -- draft -> submitted is a pure status flip with no other side
--    effect (no external system call, no canonical mutation), so a genuine
--    retry is made safe simply by treating an ALREADY-submitted row as an
--    idempotent no-op return (status check, not key comparison) rather than
--    raising invalid_transition. This is safe specifically because, unlike
--    CPL-302's submit (which needed to additionally detect a colliding key
--    reused against a DIFFERENT row), there is no second key here that
--    could ever collide. Disclosed, deliberate simplification matching the
--    schema actually given, not a silent gap.
-- 5. **Status machine is the 6-value set given verbatim**: draft ->
--    submitted | cancelled; submitted -> cancelled | converted |
--    reschedule_requested; converted -> reschedule_requested |
--    cancel_requested; cancelled/reschedule_requested/cancel_requested are
--    all terminal WITHIN THIS CHECKPOINT's own RPC surface (see design
--    decision 9's disclosed boundary). The split between "cancels directly"
--    and "cancels via a request" is a disclosed interpretation this
--    checkpoint had to resolve (the orchestrating task's own item 2 did not
--    spell out which statuses land where, unlike its explicit "submitted/
--    converted -> reschedule_requested" wording for reschedule): draft/
--    submitted (no operational truth committed yet, mirrors CPL-302's own
--    draft-or-submitted-cancels-directly precedent) cancel straight to
--    `cancelled`; converted (real app.job_orders/app.shipment_orders rows
--    already exist) instead becomes `cancel_requested` -- matches the
--    business rule "changes after operational assignment become requests,
--    not direct edits to dispatch/WMS/Finance" literally, the same
--    distinction the source prompt draws for reschedule.
-- 6. **cancelled_reason is reused for BOTH the `cancel_requested` and the
--    final `cancelled` outcome** -- the given column list carries exactly
--    one reason column for cancellation (unlike reschedule, which gets its
--    own dedicated reschedule_reason/reschedule_requested_at/reschedule_
--    requested_pickup_at/reschedule_requested_delivery_at columns since a
--    reschedule reason is conceptually distinct from a cancellation
--    reason). "Mandatory new requested date" (source prompt) is
--    interpreted as "at least one of pickup or delivery must be supplied,"
--    since either alone is a genuine reschedule ask.
-- 7. **The staff conversion RPC structurally verifies account ownership,
--    unlike CPL-302's own disclosed inability to do so for
--    app.quotations.** app.job_orders carries a live account_id FK and app.
--    shipment_orders carries a live shipper_account_id FK (both confirmed
--    by direct migration inspection, 20260727090000/100000) -- so app.
--    link_customer_booking_request_to_operational_records below verifies
--    the supplied job order's account_id and the supplied shipment order's
--    shipper_account_id both equal the booking's OWN account_id, and that
--    the supplied shipment order's own job_order_id equals the supplied job
--    order id, before linking -- a real structural check CPL-302 could not
--    make for app.quotations (no account reference exists there), not
--    merely relying on the OPS:Edit-holding staff actor's own unconditional
--    authority the way CPL-302 had to.
-- 8. **Both p_job_order_id and p_shipment_order_id are mandatory (NOT NULL)
--    on the staff RPC, set together in exactly one atomic call** -- mirrors
--    "both set only by staff conversion, mirroring CPL-302's own linked_
--    quotation_id pattern" (the orchestrating task's own instruction)
--    literally: CPL-302 sets its one linked_* column exactly once, atomically,
--    never in two partial steps, so this migration does the same for BOTH
--    columns together. Disclosed boundary: a Job Order that is later split
--    into several Shipment Orders (app.create_shipment_order_from_job's own
--    p_split_reason parameter) is not modeled here -- this table links to
--    at most one representative Shipment Order per booking request, matching
--    the given simple nullable-uuid column shape exactly, not a one-to-many
--    relationship. A future capability that needs multi-shipment visibility
--    per booking is a disclosed, separate follow-up.
-- 9. **Credit gate: deliberately NOT surfaced from any customer RPC in this
--    migration.** app.check_customer_credit (COM-157, 20260724310000) is
--    FIN/COM-gated internally (app.evaluate_permission(..., 'COM', 'View')
--    inside its own body) and is never called from here. Per the
--    orchestrating task's own explicit instruction: when staff link a
--    booking to real operational records via item 8's RPC, they are
--    implicitly asserting credit was already checked through the normal
--    internal flow (app.prepare_job_order_handoff's own downstream Commercial/
--    Operations pipeline) -- no new credit-surfacing mechanism is built this
--    checkpoint. A customer-visible "credit hold" status display, if wanted,
--    belongs with Prompt 311/312's own Finance-visibility work, which is the
--    checkpoint that actually builds the customer-safe reason-code RPC this
--    would need. This is a deliberate, disclosed scope boundary, not an
--    oversight.
-- 10. **Reschedule/cancel-request terminal-within-this-checkpoint (disclosed
--    boundary).** Neither `reschedule_requested` nor `cancel_requested` has
--    any RPC in this migration that transitions it onward (back to
--    submitted/converted, or on to cancelled) -- the orchestrating task's
--    own RPC list names exactly 7 customer RPCs + 1 staff RPC, none of which
--    is a "resolve reschedule/cancellation request" function. These two
--    statuses are real, persisted, staff-actionable-in-principle states (a
--    future Operations-facing booking-management checkpoint's natural job,
--    mirroring CPL-302's own disclosed "no staff UI to accept/link yet"
--    precedent) rather than a dead end -- get/list continue to surface them
--    correctly, and app.customer_portal_booking_request_history (item 11)
--    keeps a real, queryable append-only record of how the row got there.
-- 11. **A dedicated append-only history table, mirroring app.customer_
--    portal_account_membership_history (CPL-300) exactly** -- not given
--    verbatim by the task's own column list, but every sibling status-
--    machine table in this repository's own Phase 8 slice keeps one, and
--    audit_logs alone (capture_audit_event, still called on every mutation
--    here too) does not give a dedicated, booking-scoped, cheaply queryable
--    transition timeline the way this table does for the UI's own status
--    timeline (mirrors CPL-302's UI-level StatusTimeline, built from the
--    row's own real timestamps there since it had only 4 statuses; this
--    table has 6 including two "stuck" ones, so a real history row per
--    transition is a better foundation for a future staff-resolution UI).
-- 12. **RLS: authenticated holds ZERO direct grant**, mirroring CPL-300/
--    CPL-302's app.customer_portal_account_memberships/app.customer_portal_
--    quote_requests convention exactly.
-- 13. **REST/GraphQL transport (ADR-0024 Part C)**: service layer + Server
--    Actions + UI only, no app/api/ HTTP route -- identical in kind to
--    CPL-300/301/302's own disclosed residual gap.
-- 14. Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): this migration
--    carries its own explicit `revoke execute on all functions in schema
--    app from public` before its final grants.

-- ===========================================================================
-- 1. app.customer_portal_booking_requests
-- ===========================================================================

create table app.customer_portal_booking_requests (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  account_id uuid not null references app.accounts (id),
  requested_by_auth_user_id uuid not null references auth.users (id),
  status text not null default 'draft',
  linked_quote_request_id uuid references app.customer_portal_quote_requests (id),
  cargo_description text,
  pickup jsonb not null default '{}'::jsonb,
  delivery jsonb not null default '{}'::jsonb,
  requested_pickup_at timestamptz,
  requested_delivery_at timestamptz,
  special_instructions text,
  idempotency_key text,
  linked_job_order_id uuid references app.job_orders (id),
  linked_shipment_order_id uuid references app.shipment_orders (id),
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  submitted_at timestamptz,
  cancelled_at timestamptz,
  cancelled_reason text,
  reschedule_requested_pickup_at timestamptz,
  reschedule_requested_delivery_at timestamptz,
  reschedule_reason text,
  reschedule_requested_at timestamptz,
  constraint cpbr_status_check check (status in ('draft', 'submitted', 'reschedule_requested', 'cancel_requested', 'cancelled', 'converted')),
  constraint cpbr_pickup_check check (jsonb_typeof(pickup) = 'object'),
  constraint cpbr_delivery_check check (jsonb_typeof(delivery) = 'object'),
  constraint cpbr_dates_check check (
    requested_pickup_at is null or requested_delivery_at is null or requested_delivery_at >= requested_pickup_at
  ),
  constraint cpbr_cancelled_reason_check check (
    (status in ('cancel_requested', 'cancelled') and cancelled_reason is not null and length(trim(cancelled_reason)) > 0)
    or (status not in ('cancel_requested', 'cancelled'))
  ),
  constraint cpbr_reschedule_check check (
    (status = 'reschedule_requested' and reschedule_reason is not null and length(trim(reschedule_reason)) > 0
      and (reschedule_requested_pickup_at is not null or reschedule_requested_delivery_at is not null))
    or (status <> 'reschedule_requested')
  ),
  -- One-directional implication, NOT a biconditional: `converted` REQUIRES
  -- both linked ids, but a converted booking that later moves to
  -- reschedule_requested/cancel_requested (design decision 5 -- `converted`
  -- is NOT terminal here, unlike CPL-302's own quote request `converted`,
  -- which is terminal) correctly KEEPS its linked_job_order_id/linked_
  -- shipment_order_id as real historical evidence while status is no longer
  -- literally `converted`. A biconditional would incorrectly reject that
  -- legitimate transition.
  constraint cpbr_converted_requires_links check (
    status <> 'converted' or (linked_job_order_id is not null and linked_shipment_order_id is not null)
  )
);

comment on table app.customer_portal_booking_requests is
  'CPL-303: the portal-owned booking REQUEST -- never a direct write into app.job_order_handoffs/app.job_orders/app.shipment_orders. linked_job_order_id/linked_shipment_order_id are set exactly once, together, only by app.link_customer_booking_request_to_operational_records below, and only alongside status=converted (cpbr_converted_requires_links). RLS enabled, authenticated holds zero direct grant (design decision 12) -- the 7 customer-facing RPCs plus the 1 staff-gated RPC below are the only sanctioned access path.';

create unique index cpbr_tenant_idempotency_key_uq
  on app.customer_portal_booking_requests (tenant_id, idempotency_key)
  where idempotency_key is not null;

create index cpbr_tenant_updated_id_idx
  on app.customer_portal_booking_requests (tenant_id, updated_at desc, id desc);

create index cpbr_account_idx on app.customer_portal_booking_requests (account_id);
create index cpbr_linked_quote_request_idx on app.customer_portal_booking_requests (linked_quote_request_id) where linked_quote_request_id is not null;
create index cpbr_linked_job_order_idx on app.customer_portal_booking_requests (linked_job_order_id) where linked_job_order_id is not null;
create index cpbr_linked_shipment_order_idx on app.customer_portal_booking_requests (linked_shipment_order_id) where linked_shipment_order_id is not null;

create table app.customer_portal_booking_request_history (
  id uuid primary key default gen_random_uuid(),
  booking_request_id uuid not null,
  tenant_id uuid not null,
  account_id uuid not null,
  from_status text,
  to_status text not null,
  reason text,
  requested_by text,
  created_at timestamptz not null default now()
);

comment on table app.customer_portal_booking_request_history is
  'CPL-303: append-only state-transition history for app.customer_portal_booking_requests, mirroring app.customer_portal_account_membership_history (CPL-300) exactly (design decision 11). Written by every state-changing RPC below -- never updated or deleted.';

create index cpbrh_booking_request_id_created_at_idx
  on app.customer_portal_booking_request_history (booking_request_id, created_at desc);

-- ===========================================================================
-- 2. Triggers -- mirror CPL-302's app.customer_portal_quote_requests
--    triggers exactly (design decision 5)
-- ===========================================================================

create function app.enforce_customer_portal_booking_request_transition()
returns trigger
language plpgsql
as $$
begin
  if new.status = old.status then
    return new;
  end if;

  if old.status in ('cancelled', 'reschedule_requested', 'cancel_requested') then
    raise exception 'invalid_cpbr_transition: booking request % is % and is terminal, no further transition is allowed', old.id, old.status
      using errcode = 'check_violation';
  end if;

  if not (
    (old.status = 'draft' and new.status in ('submitted', 'cancelled'))
    or (old.status = 'submitted' and new.status in ('cancelled', 'converted', 'reschedule_requested'))
    or (old.status = 'converted' and new.status in ('reschedule_requested', 'cancel_requested'))
  ) then
    raise exception 'invalid_cpbr_transition: % -> % is not a canonical transition', old.status, new.status
      using errcode = 'check_violation';
  end if;

  return new;
end;
$$;

create trigger customer_portal_booking_requests_enforce_transition
  before update of status on app.customer_portal_booking_requests
  for each row
  execute function app.enforce_customer_portal_booking_request_transition();

create function app.touch_customer_portal_booking_request_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger customer_portal_booking_requests_touch_row
  before update on app.customer_portal_booking_requests
  for each row
  execute function app.touch_customer_portal_booking_request_row();

-- ===========================================================================
-- 3. app.create_customer_booking_request_draft
-- ===========================================================================

create function app.create_customer_booking_request_draft(
  p_tenant_id uuid,
  p_account_id uuid,
  p_linked_quote_request_id uuid,
  p_cargo_description text,
  p_pickup jsonb,
  p_delivery jsonb,
  p_requested_pickup_at timestamptz,
  p_requested_delivery_at timestamptz,
  p_special_instructions text,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.customer_portal_booking_requests
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_existing app.customer_portal_booking_requests;
  v_booking app.customer_portal_booking_requests;
  v_pickup jsonb := coalesce(p_pickup, '{}'::jsonb);
  v_delivery jsonb := coalesce(p_delivery, '{}'::jsonb);
  v_scope uuid[];
  v_quote_request app.customer_portal_quote_requests;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_scope := app.resolve_customer_account_scope(p_actor_auth_user_id, p_tenant_id);
  if not (p_account_id = any (v_scope)) then
    raise exception 'account_not_available: % is not an account this identity may book a shipment for', p_account_id using errcode = 'no_data_found';
  end if;

  -- Tier C fix (C-01 discipline): the idempotent short-circuit must verify
  -- the found row actually belongs to the SAME account this call targets
  -- before ever returning it. A colliding key belonging to a DIFFERENT
  -- account -- whether guessed, or a genuine same-actor multi-account
  -- collision -- is a real idempotency_key_conflict, never a silent
  -- cross-account disclosure of another account's cargo/instructions.
  -- Mirrors CPL-302's identical fix (app.create_customer_quote_request_draft).
  if p_idempotency_key is not null then
    select * into v_existing from app.customer_portal_booking_requests where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
    if found then
      if v_existing.account_id = p_account_id then
        return v_existing;
      end if;
      raise exception 'idempotency_key_conflict: key % was already used for a different account''s booking request %', p_idempotency_key, v_existing.id
        using errcode = 'unique_violation';
    end if;
  end if;

  if jsonb_typeof(v_pickup) <> 'object' or jsonb_typeof(v_delivery) <> 'object' then
    raise exception 'invalid_location: pickup/delivery must each be a JSON object' using errcode = 'check_violation';
  end if;

  if p_requested_pickup_at is not null and p_requested_delivery_at is not null and p_requested_delivery_at < p_requested_pickup_at then
    raise exception 'invalid_dates: requested_delivery_at cannot be before requested_pickup_at' using errcode = 'check_violation';
  end if;

  -- Design decision 3: a linked quote request must be a real, in-scope,
  -- SAME-account, already-converted (staff-accepted) row.
  if p_linked_quote_request_id is not null then
    select * into v_quote_request from app.customer_portal_quote_requests where id = p_linked_quote_request_id and tenant_id = p_tenant_id;
    if not found or not (v_quote_request.account_id = any (v_scope)) then
      raise exception 'quote_request_not_found: no permitted quote request exists for %', p_linked_quote_request_id using errcode = 'no_data_found';
    end if;
    if v_quote_request.account_id <> p_account_id then
      raise exception 'quote_request_account_mismatch: quote request % does not belong to account %', p_linked_quote_request_id, p_account_id
        using errcode = 'check_violation';
    end if;
    if v_quote_request.status <> 'converted' then
      raise exception 'quote_request_not_accepted: quote request % is % and is not yet an accepted quotation', p_linked_quote_request_id, v_quote_request.status
        using errcode = 'check_violation';
    end if;
  end if;

  -- Tier C fix (C-01 discipline): a REAL exception handler, not merely a
  -- pre-check select -- two genuinely concurrent calls carrying the
  -- identical key can both pass the pre-check above before either commits;
  -- the race LOSER's own INSERT must recover via the SAME account-scoped
  -- re-select, never surface a raw unique_violation to the caller.
  begin
    insert into app.customer_portal_booking_requests (
      tenant_id, account_id, requested_by_auth_user_id, linked_quote_request_id, cargo_description, pickup, delivery,
      requested_pickup_at, requested_delivery_at, special_instructions, idempotency_key, created_by
    ) values (
      p_tenant_id, p_account_id, p_actor_auth_user_id, p_linked_quote_request_id, p_cargo_description, v_pickup, v_delivery,
      p_requested_pickup_at, p_requested_delivery_at, p_special_instructions, p_idempotency_key, p_actor_label
    )
    returning * into v_booking;
  exception
    when unique_violation then
      if p_idempotency_key is null then
        raise;
      end if;
      select * into v_booking from app.customer_portal_booking_requests where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
      if not found or v_booking.account_id <> p_account_id then
        raise;
      end if;
      -- Race LOSER recovering onto the WINNER's already-committed row:
      -- return it as-is, exactly like the pre-check idempotent-return path
      -- above -- never fall through to a second, spurious history row/audit
      -- event for a row this call did not actually create.
      return v_booking;
  end;

  insert into app.customer_portal_booking_request_history (booking_request_id, tenant_id, account_id, from_status, to_status, reason, requested_by)
  values (v_booking.id, v_booking.tenant_id, v_booking.account_id, null, 'draft', 'booking request created', p_actor_label);

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_customer_booking_request_draft',
    'app.customer_portal_booking_requests', v_booking.id, 'success', null, null, to_jsonb(v_booking)
  );

  return v_booking;
end;
$$;

comment on function app.create_customer_booking_request_draft is
  'CPL-303: creates a draft booking request, optionally originating from an already-converted (staff-accepted) quote request on the SAME account (design decision 3), or a direct service booking (p_linked_quote_request_id null). p_account_id must already be in app.resolve_customer_account_scope(actor, tenant). Idempotent on (tenant_id, idempotency_key) when a key is supplied, for the SAME account only -- the SAME key against a DIFFERENT account is a real idempotency_key_conflict, never a silent cross-account return (Tier C fix, C-01 discipline, mirrors CPL-302). The INSERT itself is wrapped in a real unique_violation handler, not only a pre-check, so a genuine two-process race on the same key converges on one row (Tier C fix).';

-- ===========================================================================
-- 4. app.update_customer_booking_request_draft -- draft-only
-- ===========================================================================

create function app.update_customer_booking_request_draft(
  p_booking_request_id uuid,
  p_expected_version integer,
  p_cargo_description text,
  p_pickup jsonb,
  p_delivery jsonb,
  p_requested_pickup_at timestamptz,
  p_requested_delivery_at timestamptz,
  p_special_instructions text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.customer_portal_booking_requests
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_booking app.customer_portal_booking_requests;
  v_updated app.customer_portal_booking_requests;
  v_pickup jsonb := coalesce(p_pickup, '{}'::jsonb);
  v_delivery jsonb := coalesce(p_delivery, '{}'::jsonb);
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_booking from app.customer_portal_booking_requests where id = p_booking_request_id for update;
  if not found or not (v_booking.account_id = any (app.resolve_customer_account_scope(p_actor_auth_user_id, v_booking.tenant_id))) then
    raise exception 'record_not_found: no permitted booking request exists for %', p_booking_request_id using errcode = 'no_data_found';
  end if;

  if v_booking.status <> 'draft' then
    raise exception 'invalid_transition: booking request % is % and can no longer be edited', p_booking_request_id, v_booking.status
      using errcode = 'check_violation';
  end if;

  if v_booking.record_version <> p_expected_version then
    raise exception 'stale_version: booking request % expected version % but found %', p_booking_request_id, p_expected_version, v_booking.record_version
      using errcode = 'serialization_failure';
  end if;

  if jsonb_typeof(v_pickup) <> 'object' or jsonb_typeof(v_delivery) <> 'object' then
    raise exception 'invalid_location: pickup/delivery must each be a JSON object' using errcode = 'check_violation';
  end if;

  if p_requested_pickup_at is not null and p_requested_delivery_at is not null and p_requested_delivery_at < p_requested_pickup_at then
    raise exception 'invalid_dates: requested_delivery_at cannot be before requested_pickup_at' using errcode = 'check_violation';
  end if;

  update app.customer_portal_booking_requests
  set cargo_description = p_cargo_description,
      pickup = v_pickup,
      delivery = v_delivery,
      requested_pickup_at = p_requested_pickup_at,
      requested_delivery_at = p_requested_delivery_at,
      special_instructions = p_special_instructions
  where id = p_booking_request_id
  returning * into v_updated;

  perform app.capture_audit_event(
    v_updated.tenant_id, p_actor_auth_user_id, p_actor_label, 'update_customer_booking_request_draft',
    'app.customer_portal_booking_requests', v_updated.id, 'success', null, to_jsonb(v_booking), to_jsonb(v_updated)
  );

  return v_updated;
end;
$$;

comment on function app.update_customer_booking_request_draft is
  'CPL-303: draft-only edit of cargo/pickup/delivery/schedule/instructions. Any active member of the request''s own account may edit it (mirrors CPL-302 design decision 9), not only its original requester. linked_quote_request_id is immutable after creation -- not one of this function''s own parameters. Optimistic concurrency via select ... for update + explicit stale_version raise.';

-- ===========================================================================
-- 5. app.submit_customer_booking_request -- draft -> submitted
-- ===========================================================================

create function app.submit_customer_booking_request(
  p_booking_request_id uuid,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.customer_portal_booking_requests
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_booking app.customer_portal_booking_requests;
  v_updated app.customer_portal_booking_requests;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_booking from app.customer_portal_booking_requests where id = p_booking_request_id for update;
  if not found or not (v_booking.account_id = any (app.resolve_customer_account_scope(p_actor_auth_user_id, v_booking.tenant_id))) then
    raise exception 'record_not_found: no permitted booking request exists for %', p_booking_request_id using errcode = 'no_data_found';
  end if;

  -- Idempotent no-op (design decision 4): a genuine retry of an
  -- already-submitted row is a safe, unchanged return -- draft -> submitted
  -- is a pure status flip with no other side effect, so no separate
  -- submit-stage idempotency key is needed the way CPL-302's own submit
  -- required one (that RPC additionally had to detect a colliding key reused
  -- against a DIFFERENT row; there is no second key here that could ever
  -- collide).
  if v_booking.status = 'submitted' then
    return v_booking;
  end if;

  if v_booking.status <> 'draft' then
    raise exception 'invalid_transition: booking request % is % and cannot be submitted', p_booking_request_id, v_booking.status
      using errcode = 'check_violation';
  end if;

  if v_booking.record_version <> p_expected_version then
    raise exception 'stale_version: booking request % expected version % but found %', p_booking_request_id, p_expected_version, v_booking.record_version
      using errcode = 'serialization_failure';
  end if;

  update app.customer_portal_booking_requests
  set status = 'submitted', submitted_at = now()
  where id = p_booking_request_id
  returning * into v_updated;

  insert into app.customer_portal_booking_request_history (booking_request_id, tenant_id, account_id, from_status, to_status, reason, requested_by)
  values (v_updated.id, v_updated.tenant_id, v_updated.account_id, 'draft', 'submitted', 'booking request submitted', p_actor_label);

  perform app.capture_audit_event(
    v_updated.tenant_id, p_actor_auth_user_id, p_actor_label, 'submit_customer_booking_request',
    'app.customer_portal_booking_requests', v_updated.id, 'success', null, null, to_jsonb(v_updated)
  );

  return v_updated;
end;
$$;

comment on function app.submit_customer_booking_request is
  'CPL-303: draft -> submitted, hands the request to Operations/Commercial''s own intake for staff review and eventual canonical handoff (app.prepare_job_order_handoff and downstream) -- never itself a canonical job/shipment order. Idempotent no-op if already submitted (design decision 4).';

-- ===========================================================================
-- 6. app.request_customer_booking_reschedule -- submitted|converted -> reschedule_requested
-- ===========================================================================

create function app.request_customer_booking_reschedule(
  p_booking_request_id uuid,
  p_expected_version integer,
  p_requested_pickup_at timestamptz,
  p_requested_delivery_at timestamptz,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.customer_portal_booking_requests
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_booking app.customer_portal_booking_requests;
  v_updated app.customer_portal_booking_requests;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to request a reschedule' using errcode = 'not_null_violation';
  end if;

  if p_requested_pickup_at is null and p_requested_delivery_at is null then
    raise exception 'reschedule_date_required: at least one new requested pickup or delivery date/time is required' using errcode = 'not_null_violation';
  end if;

  if p_requested_pickup_at is not null and p_requested_delivery_at is not null and p_requested_delivery_at < p_requested_pickup_at then
    raise exception 'invalid_dates: requested_delivery_at cannot be before requested_pickup_at' using errcode = 'check_violation';
  end if;

  select * into v_booking from app.customer_portal_booking_requests where id = p_booking_request_id for update;
  if not found or not (v_booking.account_id = any (app.resolve_customer_account_scope(p_actor_auth_user_id, v_booking.tenant_id))) then
    raise exception 'record_not_found: no permitted booking request exists for %', p_booking_request_id using errcode = 'no_data_found';
  end if;

  if v_booking.status not in ('submitted', 'converted') then
    raise exception 'invalid_transition: booking request % is % and cannot be rescheduled', p_booking_request_id, v_booking.status
      using errcode = 'check_violation';
  end if;

  if v_booking.record_version <> p_expected_version then
    raise exception 'stale_version: booking request % expected version % but found %', p_booking_request_id, p_expected_version, v_booking.record_version
      using errcode = 'serialization_failure';
  end if;

  update app.customer_portal_booking_requests
  set status = 'reschedule_requested',
      reschedule_requested_pickup_at = p_requested_pickup_at,
      reschedule_requested_delivery_at = p_requested_delivery_at,
      reschedule_reason = p_reason,
      reschedule_requested_at = now()
  where id = p_booking_request_id
  returning * into v_updated;

  insert into app.customer_portal_booking_request_history (booking_request_id, tenant_id, account_id, from_status, to_status, reason, requested_by)
  values (v_updated.id, v_updated.tenant_id, v_updated.account_id, v_booking.status, 'reschedule_requested', p_reason, p_actor_label);

  perform app.capture_audit_event(
    v_updated.tenant_id, p_actor_auth_user_id, p_actor_label, 'request_customer_booking_reschedule',
    'app.customer_portal_booking_requests', v_updated.id, 'success', p_reason, to_jsonb(v_booking), to_jsonb(v_updated)
  );

  return v_updated;
end;
$$;

comment on function app.request_customer_booking_reschedule is
  'CPL-303: submitted or converted -> reschedule_requested (source prompt''s own literal mapping). Mandatory non-empty reason and at least one new proposed pickup/delivery date/time (design decision 6). This is a REQUEST only -- the real requested_pickup_at/requested_delivery_at columns and any already-linked job/shipment order are never mutated here; changing dispatch/WMS/Finance stays Operations'' own job (business rule, source prompt §24). Terminal within this checkpoint''s own RPC surface (design decision 10) -- a real, disclosed, staff-actionable-in-principle state.';

-- ===========================================================================
-- 7. app.request_customer_booking_cancellation
-- ===========================================================================

create function app.request_customer_booking_cancellation(
  p_booking_request_id uuid,
  p_expected_version integer,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.customer_portal_booking_requests
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_booking app.customer_portal_booking_requests;
  v_updated app.customer_portal_booking_requests;
  v_target_status text;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to cancel a booking request' using errcode = 'not_null_violation';
  end if;

  select * into v_booking from app.customer_portal_booking_requests where id = p_booking_request_id for update;
  if not found or not (v_booking.account_id = any (app.resolve_customer_account_scope(p_actor_auth_user_id, v_booking.tenant_id))) then
    raise exception 'record_not_found: no permitted booking request exists for %', p_booking_request_id using errcode = 'no_data_found';
  end if;

  -- Design decision 5: draft/submitted (no operational truth committed yet)
  -- cancel straight to `cancelled`; converted (real job/shipment order rows
  -- already exist) instead becomes `cancel_requested` for staff review.
  if v_booking.status in ('draft', 'submitted') then
    v_target_status := 'cancelled';
  elsif v_booking.status = 'converted' then
    v_target_status := 'cancel_requested';
  else
    raise exception 'invalid_transition: booking request % is % and can no longer be cancelled', p_booking_request_id, v_booking.status
      using errcode = 'check_violation';
  end if;

  if v_booking.record_version <> p_expected_version then
    raise exception 'stale_version: booking request % expected version % but found %', p_booking_request_id, p_expected_version, v_booking.record_version
      using errcode = 'serialization_failure';
  end if;

  update app.customer_portal_booking_requests
  set status = v_target_status,
      cancelled_reason = p_reason,
      cancelled_at = case when v_target_status = 'cancelled' then now() else cancelled_at end
  where id = p_booking_request_id
  returning * into v_updated;

  insert into app.customer_portal_booking_request_history (booking_request_id, tenant_id, account_id, from_status, to_status, reason, requested_by)
  values (v_updated.id, v_updated.tenant_id, v_updated.account_id, v_booking.status, v_target_status, p_reason, p_actor_label);

  perform app.capture_audit_event(
    v_updated.tenant_id, p_actor_auth_user_id, p_actor_label, 'request_customer_booking_cancellation',
    'app.customer_portal_booking_requests', v_updated.id, 'success', p_reason, to_jsonb(v_booking), to_jsonb(v_updated)
  );

  return v_updated;
end;
$$;

comment on function app.request_customer_booking_cancellation is
  'CPL-303: mandatory non-empty reason (reused for both the cancel_requested and the terminal cancelled outcome, design decision 6). draft/submitted cancel directly to cancelled; converted becomes cancel_requested (design decision 5) -- terminal within this checkpoint''s own RPC surface (design decision 10). A booking already cancelled/reschedule_requested/cancel_requested correctly refuses with invalid_transition.';

-- ===========================================================================
-- 8. app.get_customer_booking_request -- anti-enumerating get-by-id
-- ===========================================================================

create function app.get_customer_booking_request(p_tenant_id uuid, p_booking_request_id uuid, p_actor_auth_user_id uuid)
returns app.customer_portal_booking_requests
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_booking app.customer_portal_booking_requests;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_booking from app.customer_portal_booking_requests where id = p_booking_request_id and tenant_id = p_tenant_id;
  if not found or not (v_booking.account_id = any (app.resolve_customer_account_scope(p_actor_auth_user_id, p_tenant_id))) then
    raise exception 'record_not_found: no permitted booking request exists for %', p_booking_request_id using errcode = 'no_data_found';
  end if;

  return v_booking;
end;
$$;

comment on function app.get_customer_booking_request is
  'CPL-303: anti-enumerating get-by-id (ADR-0024 Part A) -- raises the IDENTICAL record_not_found (errcode no_data_found) whether p_booking_request_id genuinely does not exist, belongs to a different tenant, or exists but its account is outside this identity''s resolved scope. Mirrors app.get_customer_quote_request (CPL-302) exactly.';

-- ===========================================================================
-- 9. app.list_customer_booking_requests -- keyset paginated
-- ===========================================================================

create function app.list_customer_booking_requests(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_account_id uuid default null,
  p_status text default null,
  p_cursor_updated_at timestamptz default null,
  p_cursor_id uuid default null,
  p_limit integer default 50
)
returns setof app.customer_portal_booking_requests
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

  if p_cursor_id is not null and p_cursor_updated_at is null then
    raise exception 'invalid_cursor: p_cursor_updated_at is required when p_cursor_id is supplied' using errcode = 'invalid_parameter_value';
  end if;

  v_scope := app.resolve_customer_account_scope(p_actor_auth_user_id, p_tenant_id);
  if array_length(v_scope, 1) is null then
    return;
  end if;
  if p_account_id is not null and not (p_account_id = any (v_scope)) then
    return;
  end if;

  v_limit := least(greatest(coalesce(p_limit, 50), 1), 200);

  return query
  select b.*
  from app.customer_portal_booking_requests b
  where b.tenant_id = p_tenant_id
    and b.account_id = any (v_scope)
    and (p_account_id is null or b.account_id = p_account_id)
    and (p_status is null or b.status = p_status)
    and (p_cursor_id is null or (b.updated_at, b.id) < (p_cursor_updated_at, p_cursor_id))
  order by b.updated_at desc, b.id desc
  limit v_limit;
end;
$$;

comment on function app.list_customer_booking_requests is
  'CPL-303: keyset-paginated (tenant_id, updated_at desc, id desc), never OFFSET, hard-capped at 200 -- mirrors app.list_customer_quote_requests (CPL-302) exactly. Deny-by-default: zero scope or an out-of-scope p_account_id both return an empty result, never an error.';

-- ===========================================================================
-- 10. app.link_customer_booking_request_to_operational_records -- staff,
--     OPS:Edit (the ONLY staff-RBAC touchpoint in this migration, design
--     decisions 7/8)
-- ===========================================================================

create function app.link_customer_booking_request_to_operational_records(
  p_booking_request_id uuid,
  p_job_order_id uuid,
  p_shipment_order_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.customer_portal_booking_requests
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_booking app.customer_portal_booking_requests;
  v_job_order app.job_orders;
  v_shipment_order app.shipment_orders;
  v_decision app.rbac_decision;
  v_updated app.customer_portal_booking_requests;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_booking from app.customer_portal_booking_requests where id = p_booking_request_id for update;
  -- Tier C fix (C-05 discipline): fold a tenant-standing check into the SAME
  -- not-found branch, BEFORE the specific-permission check, so an identity
  -- with zero relationship to this row's own tenant learns nothing beyond
  -- "this id does not exist" -- mirrors app.get_rfq's own established fix
  -- (supabase/migrations/20260730670000_harden_procurement_batch_257_259_
  -- review_fixes.sql) and CPL-302's identical Tier C fix. "Standing" here is
  -- deliberately wider than staff-only has_active_tenant_membership alone:
  -- this RPC is reachable by BOTH a staff caller AND a genuine
  -- customer_user-layer caller with real portal scope in this tenant
  -- (resolve_customer_account_scope) -- that identity's own app.
  -- tenant_user_identities row is deliberately NEVER 'active' (CPL-302
  -- design decision 4(b)), so has_active_tenant_membership alone would
  -- wrongly hide insufficient_authority from a customer who is genuinely a
  -- member of this tenant (a live-tested case: a customer, Layer 4, not
  -- staff, must still get insufficient_authority, never not_found). A
  -- caller satisfying EITHER predicate still reaches the informative
  -- insufficient_authority branch below; a caller satisfying NEITHER (e.g.
  -- a customer_user of a completely different tenant) gets the identical
  -- not-found error a missing row would produce.
  if not found or not (
    app.has_active_tenant_membership(v_booking.tenant_id, p_actor_auth_user_id)
    or array_length(app.resolve_customer_account_scope(p_actor_auth_user_id, v_booking.tenant_id), 1) is not null
  ) then
    raise exception 'booking_request_not_found: %', p_booking_request_id using errcode = 'no_data_found';
  end if;

  -- Reuse the already-existing OPS:Edit action (the same module/action app.
  -- confirm_job_order/app.confirm_shipment_order already require) --
  -- checked before app.entitlement_modules/app.permissions per this task's
  -- own instruction; no new module/action added.
  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_booking.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_booking.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_job_order_id is null then
    raise exception 'job_order_id_required: a job order id is required to convert a booking request' using errcode = 'not_null_violation';
  end if;
  if p_shipment_order_id is null then
    raise exception 'shipment_order_id_required: a shipment order id is required to convert a booking request' using errcode = 'not_null_violation';
  end if;

  -- Idempotent: re-acknowledging the SAME (job order, shipment order) pair is
  -- a no-op return; converting an already-converted request to DIFFERENT
  -- operational records is a real conflict, never a silent overwrite of
  -- canonical linkage evidence (mirrors app.link_customer_quote_request_to_
  -- quotation, CPL-302, exactly).
  if v_booking.status = 'converted' then
    if v_booking.linked_job_order_id = p_job_order_id and v_booking.linked_shipment_order_id = p_shipment_order_id then
      return v_booking;
    end if;
    raise exception 'already_converted: booking request % is already linked to job order %/shipment order %, not %/%',
      p_booking_request_id, v_booking.linked_job_order_id, v_booking.linked_shipment_order_id, p_job_order_id, p_shipment_order_id
      using errcode = 'check_violation';
  end if;

  if v_booking.status <> 'submitted' then
    raise exception 'invalid_transition: booking request % is % and cannot be converted (only a submitted request may be)', p_booking_request_id, v_booking.status
      using errcode = 'check_violation';
  end if;

  select * into v_job_order from app.job_orders where id = p_job_order_id and tenant_id = v_booking.tenant_id;
  if not found then
    raise exception 'job_order_not_found: no job order % in tenant %', p_job_order_id, v_booking.tenant_id using errcode = 'no_data_found';
  end if;
  -- Design decision 7: a REAL structural check, unlike CPL-302's own
  -- disclosed inability to verify app.quotations' account ownership.
  if v_job_order.account_id <> v_booking.account_id then
    raise exception 'job_order_account_mismatch: job order % does not belong to booking request %''s own account', p_job_order_id, p_booking_request_id
      using errcode = 'check_violation';
  end if;

  select * into v_shipment_order from app.shipment_orders where id = p_shipment_order_id and tenant_id = v_booking.tenant_id;
  if not found then
    raise exception 'shipment_order_not_found: no shipment order % in tenant %', p_shipment_order_id, v_booking.tenant_id using errcode = 'no_data_found';
  end if;
  if v_shipment_order.job_order_id <> p_job_order_id then
    raise exception 'shipment_order_job_order_mismatch: shipment order % does not belong to job order %', p_shipment_order_id, p_job_order_id
      using errcode = 'check_violation';
  end if;
  if v_shipment_order.shipper_account_id <> v_booking.account_id then
    raise exception 'shipment_order_account_mismatch: shipment order % does not belong to booking request %''s own account', p_shipment_order_id, p_booking_request_id
      using errcode = 'check_violation';
  end if;

  update app.customer_portal_booking_requests
  set status = 'converted', linked_job_order_id = p_job_order_id, linked_shipment_order_id = p_shipment_order_id
  where id = p_booking_request_id
  returning * into v_updated;

  insert into app.customer_portal_booking_request_history (booking_request_id, tenant_id, account_id, from_status, to_status, reason, requested_by)
  values (v_updated.id, v_updated.tenant_id, v_updated.account_id, v_booking.status, 'converted', 'linked to canonical job/shipment order', p_actor_label);

  perform app.capture_audit_event(
    v_updated.tenant_id, p_actor_auth_user_id, p_actor_label, 'link_customer_booking_request_to_operational_records',
    'app.customer_portal_booking_requests', v_updated.id, 'success', null, to_jsonb(v_booking), to_jsonb(v_updated)
  );

  return v_updated;
end;
$$;

comment on function app.link_customer_booking_request_to_operational_records is
  'CPL-303: staff-only (OPS:Edit), the sole conversion acknowledgement -- a submitted booking request becomes converted, linked_job_order_id/linked_shipment_order_id set exactly once, together (cpbr_converted_requires_links enforces the pairing at the row level). Both ids are mandatory and structurally verified against the booking''s own account_id (design decision 7 -- unlike CPL-302''s own disclosed inability to do this for app.quotations) and against each other (shipment order must belong to the given job order). Idempotent for the SAME pair; a different pair on an already-converted request is a real already_converted conflict. Tier C fix (C-05 discipline): the not-found branch now also requires has_active_tenant_membership on the row''s own tenant, BEFORE the OPS:Edit check runs, so a non-member cannot learn the row''s real tenant_id from a distinguishable insufficient_authority error -- this migration''s own earlier design-decision-9 comment claiming this was already handled was inaccurate; it is fixed here, not merely re-disclosed.';

-- ===========================================================================
-- 11. RLS -- enable, grant service_role only (design decision 12)
-- ===========================================================================

alter table app.customer_portal_booking_requests enable row level security;
alter table app.customer_portal_booking_request_history enable row level security;

grant select, insert, update, delete
  on app.customer_portal_booking_requests, app.customer_portal_booking_request_history
  to service_role;

-- Per ERR-2026-004: explicit, directly-provable revoke of PostgreSQL's
-- PUBLIC-execute default before any role-specific grant (standing
-- per-migration convention since PLT-118).
revoke execute on all functions in schema app from public;

grant execute on function app.create_customer_booking_request_draft(uuid, uuid, uuid, text, jsonb, jsonb, timestamptz, timestamptz, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.update_customer_booking_request_draft(uuid, integer, text, jsonb, jsonb, timestamptz, timestamptz, text, uuid, text) to authenticated, service_role;
grant execute on function app.submit_customer_booking_request(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.request_customer_booking_reschedule(uuid, integer, timestamptz, timestamptz, text, uuid, text) to authenticated, service_role;
grant execute on function app.request_customer_booking_cancellation(uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.get_customer_booking_request(uuid, uuid, uuid) to authenticated, service_role;
grant execute on function app.list_customer_booking_requests(uuid, uuid, uuid, text, timestamptz, uuid, integer) to authenticated, service_role;
grant execute on function app.link_customer_booking_request_to_operational_records(uuid, uuid, uuid, uuid, text) to authenticated, service_role;
