-- Phase 7 (HRIS and Ticketing) capability CG-S12-HRT-015 (Customer-to-Tenant
-- Ticket, Prompt 287) -- the SECOND capability of the Ticket workstream,
-- extending HRT-286's canonical ticket model with a genuinely new,
-- non-employee principal type: a Layer 4 customer_user. This migration is
-- this prompt's own chartered resolution of ISS-2026-085 (docs/runtime/
-- KNOWN_ISSUES.md), the disclosed gap HRT-286's own Tier C review found and
-- registered rather than fixed ("channel extensibility is a pure additive
-- CHECK-widen, never a redesign" does not hold for a non-employee
-- requester). Additive/expand-and-contract only -- 20260731060000 and
-- 20260731070000 are NOT edited in place, per AGENTS.md. Every function
-- whose BODY changes below is `create or replace`d (same signature, same
-- OID, grants preserved); every function whose SIGNATURE or OUTPUT COLUMN
-- LIST changes is explicitly `drop function if exists` first, then
-- re-created with a fresh, explicit grant -- CREATE OR REPLACE cannot change
-- a function's parameter or RETURNS TABLE column list, and silently leaving
-- a stale, differently-shaped overload behind is exactly the kind of
-- ambiguous-signature defect this phase's own taxonomy (C-02 and its
-- siblings) exists to catch.
--
-- Design decisions, disclosed (mirrors HRT-286's own discipline exactly):
--
-- 1. **No second ticket table, no second ticket service.** Every table this
--    migration touches is one of HRT-286's own eight. The customer channel
--    is represented by widening `app.tickets.channel`'s CHECK constraint
--    (the one narrow claim HRT-286's own Tier C review confirmed WAS
--    accurate) and by a genuine expand-and-contract identity change: a new
--    nullable `requester_customer_account_id` column (FK to
--    `app.accounts`, COM-155's own canonical customer/account master),
--    `requester_employee_id` relaxed from NOT NULL to nullable, and a
--    structural CHECK (`tickets_requester_identity_shape`) enforcing
--    "exactly one of the two, matching channel" -- so an internal ticket
--    can never end up with a customer requester and vice versa, checked by
--    the database itself, not merely by RPC discipline.
--
-- 2. **Account/company/site mapping decision (explicit, since the prompt's
--    own section 13 names all three and no dedicated "site" concept exists
--    in this repository).** `app.accounts` (COM-155,
--    20260724290000_create_commercial_customer_account_conversion.sql) is
--    the ONE canonical customer/account master, and it already carries
--    `parent_account_id` -- a real, self-referencing hierarchy. This
--    migration does NOT introduce a separate "company" or "site" table.
--    Instead: "account" is the scope grain `app.principal_memberships.
--    customer_account_ref` and `app.resolve_customer_owner_account_scope`
--    (ATW-242, already VERIFIED) already operate at -- a single
--    `app.accounts.id`. "Company" and "site" are BOTH represented by
--    `app.accounts` rows related via `parent_account_id`: a tenant's
--    Commercial team may create a parent "company" account and child
--    "site" accounts underneath it (or a flat single account, for a
--    customer with only one location) using COM-155's own existing
--    mechanism, unchanged by this migration. A customer_user's own
--    membership scope (granted via `app.grant_principal_membership(...,
--    'customer_user', tenant_id, account_id::text, ...)`, PLT-108, already
--    VERIFIED, unchanged here) determines EXACTLY which account rows
--    (parent, child, or several) that identity may file/see tickets
--    against -- a customer admin granted membership on a parent account
--    sees only that one account's tickets, not its children's, UNLESS
--    ALSO separately granted on each child -- this migration does not
--    invent implicit hierarchy-cascading access, which would silently
--    widen scope beyond what was explicitly granted. This is a genuine
--    design decision, not an oversight: implicit cascade is a real,
--    separate feature a future prompt could add deliberately (e.g. an
--    explicit `p_include_child_accounts` parameter), not something to
--    infer silently inside this bounded slice.
--
-- 3. **A single, generalized structural-scope predicate, mirroring
--    PLT-114's `app.can_access_record` shape, per this prompt's own
--    mandatory reading (HRT-286 Tier C integration lens Finding 2).**
--    `app._is_ticket_requester_party(ticket, auth_user_id)` is the ONE
--    function that answers "is this identity the legitimate requester-side
--    party for this ticket" -- dispatching on `ticket.channel` internally
--    (employee-match for `internal`, account-membership-scope match via
--    `app.resolve_customer_owner_account_scope` for `customer`). Every
--    call site that previously inlined `app.get_self_employee(...)
--    = requester_employee_id` (can_access_ticket, reply_to_ticket,
--    add_ticket_watcher, remove_ticket_watcher, _ticket_transition_
--    authority) now calls this one helper instead -- never a second,
--    divergent identity check. For the `internal` channel this is
--    byte-for-byte the SAME logic HRT-286 shipped, proven unchanged by
--    re-running `scripts/db-tests/ticketing-internal.sql` byte-for-byte
--    against this migration (see build log).
--
-- 4. **`app._create_ticket` gains a real `p_channel` parameter and
--    per-channel identity resolution, exactly as ISS-2026-085 named.** The
--    OLD 10-argument overload is dropped (not merely shadowed) and
--    replaced by a 12-argument version taking `p_channel` and
--    `p_requester_customer_account_id` explicitly, validating "exactly one
--    identity column set, matching channel" at the RPC layer too (belt and
--    suspenders alongside the table CHECK). `app.create_ticket`/`app.
--    create_ticket_for_employee` (external signatures UNCHANGED) now pass
--    `p_channel := 'internal'` explicitly instead of relying on the
--    column's own default. `app.create_customer_ticket` is the new,
--    genuinely bounded customer entry point.
--
-- 5. **Customer scope is derived from authenticated membership, never
--    trusted from a request payload (business rule, section 24) --
--    verified, not merely assumed.** `app.create_customer_ticket` accepts
--    `p_account_id` (a real parameter, since a customer admin may be
--    scoped to several accounts and must be able to choose which one a new
--    ticket belongs to -- section 21 "creates a ticket within an allowed
--    account/site") but VALIDATES it against
--    `app.resolve_customer_owner_account_scope(actor, tenant)` before
--    ever using it -- a forged/unowned account id is rejected with the
--    same `account_not_available` a customer cannot use to distinguish
--    "this account does not exist" from "you are not scoped to it"
--    (anti-enumeration, mirrors ATW-242's own established discipline
--    exactly). `app.create_customer_ticket` never accepts a `p_queue_id`
--    at all -- the queue is ALWAYS resolved via the chosen category's own
--    `default_queue_id`, so a customer can never probe/forge an arbitrary
--    internal queue id; a category with no configured default queue is
--    structurally unusable for customer intake (checked at both category-
--    visibility-toggle time and ticket-creation time).
--
-- 6. **Every customer-facing READ is its own explicit, customer-safe
--    projection -- never the staff projection with fields merely omitted
--    client-side (business rule, section 24).** `app.get_customer_ticket`/
--    `app.list_customer_tickets`/`app.list_customer_ticket_messages` are
--    NEW functions with their own, deliberately narrow `RETURNS TABLE`
--    column lists: no `queue_id`/`queue_code`/`queue_name` (internal
--    routing), no `assignee_employee_id`/`assignee_name` (internal staff
--    identity -- a customer never learns which named employee is working
--    their ticket, matching common support-desk UX and this prompt's own
--    "support metadata... must never leak" instruction), no
--    `ticket_events` exposure at all (staff transfer/reassignment
--    reasons). `app.list_customer_ticket_messages` hard-filters
--    `visibility = 'public'` (never accepts a visibility parameter, unlike
--    the staff-facing `list_ticket_messages`) and replaces a staff
--    author's real name/label with a fixed generic `'Support Team'` label
--    -- a deliberate, disclosed choice, not an oversight (see the
--    function's own comment). The staff-facing `get_ticket`/`list_tickets`/
--    `list_ticket_messages`/`list_ticket_watchers`/`list_ticket_events`/
--    `export_tickets` are ALL explicitly hardened to REFUSE a
--    `customer_user`-layer caller entirely (`app.actor_holds_customer_user_
--    layer` guard added to every one) -- otherwise, widening `app.
--    can_access_ticket` to admit a customer's own ticket would have let
--    that same customer call the STAFF projection directly and see
--    internal fields it was never meant to receive. This is the single
--    most security-relevant change in this migration and is independently
--    live-tested (build log).
--
-- 7. **Raw-table access for a `customer_user`-layer actor is fully closed on
--    every ticket-domain table, mirroring the already-established ATW-023
--    hardening precedent (20260730311000_harden_customer_inventory_access_
--    rls_isolation.sql) exactly.** `app.can_access_ticket`'s widened
--    predicate is used ONLY by the SECURITY DEFINER RPC layer (which
--    bypasses RLS as the function owner and returns the customer-safe
--    projection); the RLS SELECT policies on `app.tickets`/`app.
--    ticket_messages`/`app.ticket_watchers`/`app.ticket_events` are
--    narrowed with an added `not app.actor_holds_customer_user_layer(...)`
--    clause (DROP POLICY/CREATE POLICY, the exact technique
--    20260730311000 already used) -- so a `customer_user` actor's ONLY
--    read path for these tables is genuinely the new customer RPCs below,
--    never a raw `.from("tickets")` PostgREST/supabase-js call, even
--    though the underlying `can_access_ticket` function would now
--    correctly admit them structurally. `app.ticket_queues`/`app.
--    ticket_categories`/`app.ticket_queue_members` already excluded
--    `customer_user` entirely (HRT-286's own original RLS) -- unchanged.
--
-- 8. **Watchers remain an employee/staff-only mechanism.** `app.
--    ticket_watchers.employee_id` is an `app.employees` FK -- a customer
--    contact is not an employee and cannot be added as a watcher. Rather
--    than silently no-op or error confusingly, `app.add_ticket_watcher`/
--    `app.remove_ticket_watcher` now explicitly restrict watcher
--    management to ticket STAFF ONLY when `ticket.channel = 'customer'`
--    (a customer-channel requester never manages an internal watcher
--    roster, even for their own ticket) -- disclosed, not silent.
--    Per-ticket customer PARTICIPANT management (section 22's "adds a
--    permitted company participant") is deliberately NOT built this
--    prompt: access is granted at the ACCOUNT level (any active
--    customer_user membership scoped to the ticket's own account sees
--    every ticket for that account, matching section 26 "customer admins
--    may see configured company scope"), which already satisfies the
--    stated business need without inventing a second, customer-account-
--    shaped watcher table under this bounded slice's own time budget --
--    disclosed as a residual gap in the build log, not silently dropped
--    (taxonomy C-23).
--
-- 9. **Close/reopen-as-configured reuses `app.transition_ticket_status`
--    verbatim -- no new customer-specific transition RPC.** The existing,
--    already-`VERIFIED` `app.ticket_status_transitions.requester_allowed`
--    graph (cancel, reopen) is channel-agnostic by construction; once
--    `_ticket_transition_authority`'s own `v_is_requester` resolves via the
--    new `app._is_ticket_requester_party` helper (decision 3), a
--    customer's own cancel/reopen action is authorized by the exact same
--    generic mechanism an internal requester already uses, satisfying
--    section 14's "shared... tenant service operations from the same
--    ticket service" as literally as possible. `app.reply_to_ticket` is
--    likewise reused directly (customer replies flow through it,
--    identity-resolved via the same helper) -- but a thin, additional
--    `app.reply_to_customer_ticket` wrapper is added as defense in depth:
--    it independently re-verifies the ticket is genuinely a customer-
--    channel ticket AND hardcodes `p_visibility := 'public'` at the SQL
--    call site itself, rather than relying solely on `reply_to_ticket`'s
--    own internal `v_visibility = 'internal' and not v_is_staff` guard --
--    two independent enforcement points for the one guarantee this whole
--    capability exists to prove ("a customer never posts / never reads an
--    internal note").
--
-- 10. **Linked-record leakage (section 24, "a ticket link... grants NO
--     customer access to that linked record") is honestly N/A this
--     prompt, not silently ignored.** Prompt 292 (Linked Records) has not
--     shipped -- no `app.tickets`/`app.ticket_messages` column or sibling
--     table references a shipment/invoice/warehouse/vendor/user id
--     anywhere in this schema today (grep-confirmed against the full
--     20260731060000/070000/080000 set). This migration adds NO
--     linked-record mechanism of its own. When Prompt 292 lands, it must
--     independently gate any linked-record's own customer visibility
--     (through THAT record's own owner/customer-account scope check, the
--     same `app.resolve_customer_owner_account_scope` primitive this
--     migration reuses) -- never inherit visibility from ticket access
--     alone. Flagged here as guidance for that future prompt, not
--     fabricated as a feature this prompt does not actually build.
--
-- 11. **Category customer-visibility is a separate, authority-gated
--     toggle RPC (`app.set_ticket_category_customer_visibility`), not an
--     added parameter on `app.create_ticket_category`.** Adding a new
--     parameter to an existing function changes its argument-type
--     signature even with a DEFAULT, which would either require dropping
--     the old overload (churn for a marginal convenience) or risk a
--     genuine PostgREST/named-argument ambiguity between two co-existing
--     overloads sharing the same leading parameter names -- exactly the
--     ambiguous-signature shape this phase's own taxonomy warns about.
--     A dedicated toggle RPC avoids the problem entirely, is independently
--     TKT:Edit-gated and audited, and refuses to mark a category
--     customer-visible while it has no `default_queue_id` (the invariant
--     `app.create_customer_ticket` itself depends on).

-- ===========================================================================
-- 1. Schema widen: app.tickets identity shape + channel CHECK.
-- ===========================================================================

alter table app.tickets drop constraint tickets_channel_check;
alter table app.tickets add constraint tickets_channel_check check (channel in ('internal', 'customer'));

alter table app.tickets alter column requester_employee_id drop not null;
alter table app.tickets add column requester_customer_account_id uuid references app.accounts (id);

alter table app.tickets add constraint tickets_requester_identity_shape check (
  (channel = 'internal' and requester_employee_id is not null and requester_customer_account_id is null)
  or (channel = 'customer' and requester_customer_account_id is not null and requester_employee_id is null)
);

create index tickets_requester_customer_account_idx on app.tickets (tenant_id, requester_customer_account_id) where requester_customer_account_id is not null;

-- New, channel-scoped idempotency guard (decision 4/HRT-286's own C-01
-- discipline). The EXISTING tickets_idempotency_unique index
-- (tenant_id, requester_employee_id, idempotency_key) does NOT protect
-- concurrent customer-channel creates -- requester_employee_id is NULL for
-- every customer ticket, and Postgres treats each NULL as distinct in a
-- unique index, so it silently enforces nothing among them. Customer-channel
-- idempotency is keyed by the ACTUAL submitting person
-- (requested_by_auth_user_id), not the account -- a second, different
-- company user reusing the same idempotency key by coincidence must not be
-- treated as a replay of someone else's request.
create unique index tickets_idempotency_customer_unique on app.tickets (tenant_id, requested_by_auth_user_id, idempotency_key) where idempotency_key is not null and channel = 'customer';

comment on table app.tickets is
  'HRT-286/287 (decisions 1/2/7 of 20260731060000; decisions 1/2 of this migration). channel in (''internal'',''customer''). requester identity is exactly one of requester_employee_id (internal, app.employees FK) or requester_customer_account_id (customer, app.accounts FK) -- enforced by tickets_requester_identity_shape, never both, never neither, matching channel. ISS-2026-085 (docs/runtime/KNOWN_ISSUES.md) tracked this as the required expand-and-contract work; resolved by this migration.';

-- ===========================================================================
-- 2. Schema widen: app.ticket_categories customer-visibility flag.
-- ===========================================================================

alter table app.ticket_categories add column customer_visible boolean not null default false;

create index ticket_categories_tenant_customer_visible_idx on app.ticket_categories (tenant_id, customer_visible) where customer_visible = true and status = 'active';

comment on table app.ticket_categories is
  'HRT-286/287: ticket category catalog. customer_visible (HRT-287) marks a category selectable by a Layer 4 customer via app.create_customer_ticket -- gated by app.set_ticket_category_customer_visibility (TKT:Edit), which refuses to enable it unless default_queue_id is already set (app.create_customer_ticket never accepts a caller-supplied queue id, decision 5).';

-- ===========================================================================
-- 3. app._is_ticket_requester_party -- the one generalized structural-scope
--    helper (decision 3). Internal-only (service_role), called exclusively
--    from other SECURITY DEFINER functions in this schema, mirroring
--    app._ticket_transition_authority's own established internal-engine
--    convention exactly.
-- ===========================================================================

create function app._is_ticket_requester_party(p_ticket app.tickets, p_auth_user_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_self app.employees;
begin
  if p_ticket.channel = 'customer' then
    return p_ticket.requester_customer_account_id is not null
      and p_ticket.requester_customer_account_id = any (app.resolve_customer_owner_account_scope(p_auth_user_id, p_ticket.tenant_id));
  end if;

  v_self := app.get_self_employee(p_ticket.tenant_id, p_auth_user_id);
  return v_self.master_record_id is not null and v_self.master_record_id = p_ticket.requester_employee_id;
end;
$$;

comment on function app._is_ticket_requester_party is
  'HRT-287 (decision 3): the ONE structural "is this identity the requester-side party for this ticket" predicate, dispatching on ticket.channel -- internal channel is byte-for-byte the same app.get_self_employee match HRT-286 shipped; customer channel checks the ticket''s own requester_customer_account_id against app.resolve_customer_owner_account_scope (ATW-242) for this actor/tenant, so ANY active customer_user membership scoped to that account is a legitimate requester-side party (account-level access, decision 8 -- no separate per-ticket customer participant grant this prompt). Reused by app.can_access_ticket, app.reply_to_ticket, app.add_ticket_watcher/remove_ticket_watcher, and app._ticket_transition_authority -- never re-derived.';

-- ===========================================================================
-- 4. app.can_access_ticket -- generalized (decision 3). Same external
--    signature; grants preserved by CREATE OR REPLACE.
-- ===========================================================================

create or replace function app.can_access_ticket(p_ticket_id uuid, p_auth_user_id uuid default auth.uid())
returns boolean
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_ticket app.tickets;
begin
  select * into v_ticket from app.tickets where id = p_ticket_id;
  if not found then
    return false;
  end if;
  if app.is_ticket_staff(p_ticket_id, p_auth_user_id) then
    return true;
  end if;
  if app._is_ticket_requester_party(v_ticket, p_auth_user_id) then
    return true;
  end if;
  return exists (
    select 1
    from app.ticket_watchers w
    join app.employees e on e.master_record_id = w.employee_id
    join app.users u on u.id = e.user_id
    where w.ticket_id = p_ticket_id
      and w.status = 'active'
      and u.auth_user_id = p_auth_user_id
  );
end;
$$;

comment on function app.can_access_ticket is
  'HRT-286/287 (decision 5 of 20260731060000; decision 3 of this migration): true if the caller is ticket staff (app.is_ticket_staff, employee-only by construction), the requester-side party for this ticket regardless of channel (app._is_ticket_requester_party), or an active employee watcher. The single predicate every RLS SELECT policy on tickets/messages/watchers/events references -- but for a customer_user-layer actor, RLS additionally narrows with app.actor_holds_customer_user_layer (decision 7 of this migration) so this function''s customer-admitting branch is reachable ONLY through the dedicated customer-safe SECURITY DEFINER RPCs, never a raw table read.';

-- ===========================================================================
-- 5. app._ticket_transition_authority -- generalized (decision 3/9). Same
--    external signature; grants preserved.
-- ===========================================================================

create or replace function app._ticket_transition_authority(p_ticket app.tickets, p_to_status text, p_actor_auth_user_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_is_requester boolean;
  v_transition app.ticket_status_transitions;
begin
  select * into v_transition from app.ticket_status_transitions where from_status = p_ticket.status and to_status = p_to_status;
  if not found then
    return false;
  end if;

  v_is_requester := app._is_ticket_requester_party(p_ticket, p_actor_auth_user_id);

  if v_transition.requester_allowed and v_is_requester then
    return true;
  end if;

  if not app.is_ticket_staff(p_ticket.id, p_actor_auth_user_id) then
    return false;
  end if;

  if p_to_status in ('resolved', 'closed') then
    return app.check_ticket_authority('Close', p_ticket.tenant_id, p_actor_auth_user_id);
  end if;
  if p_ticket.status in ('resolved', 'closed') and p_to_status = 'open' then
    return app.check_ticket_authority('Reopen', p_ticket.tenant_id, p_actor_auth_user_id);
  end if;

  return true;
end;
$$;

comment on function app._ticket_transition_authority is
  'HRT-286/287: resolve/close additionally require TKT:Close; staff-side reopen additionally requires TKT:Reopen; every other staff-side transition needs only app.is_ticket_staff. The ticket''s own requester-side party (app._is_ticket_requester_party, decision 3 of this migration -- employee OR customer-account-scoped, per channel) may additionally perform any transition flagged requester_allowed (cancel, reopen) with no TKT permission at all -- this is how "close/reopen-as-configured" (section 14) reaches the customer channel with zero new transition RPC (decision 9).';

-- ===========================================================================
-- 6. app.ticket_audit_projection -- widened allowlist (still structural
--    fields only, C-24 discipline unchanged). Same signature (jsonb
--    return); grants preserved.
-- ===========================================================================

create or replace function app.ticket_audit_projection(p_ticket app.tickets)
returns jsonb
language sql
immutable
as $$
  select jsonb_build_object(
    'id', p_ticket.id,
    'tenant_id', p_ticket.tenant_id,
    'ticket_number', p_ticket.ticket_number,
    'channel', p_ticket.channel,
    'category_id', p_ticket.category_id,
    'queue_id', p_ticket.queue_id,
    'priority', p_ticket.priority,
    'status', p_ticket.status,
    'requester_employee_id', p_ticket.requester_employee_id,
    'requester_customer_account_id', p_ticket.requester_customer_account_id,
    'assignee_employee_id', p_ticket.assignee_employee_id,
    'record_version', p_ticket.record_version,
    'reopen_count', p_ticket.reopen_count
  );
$$;

-- ===========================================================================
-- 7. app._create_ticket -- replaced with a real p_channel parameter
--    (decision 4/ISS-2026-085). Old 10-arg overload dropped explicitly.
-- ===========================================================================

drop function if exists app._create_ticket(uuid, uuid, uuid, uuid, text, text, text, text, uuid, text);

create function app._create_ticket(
  p_tenant_id uuid,
  p_channel text,
  p_requester_employee_id uuid,
  p_requester_customer_account_id uuid,
  p_category_id uuid,
  p_queue_id uuid,
  p_priority text,
  p_subject text,
  p_body text,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.tickets
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_category app.ticket_categories;
  v_resolved_queue_id uuid;
  v_priority text := coalesce(p_priority, 'normal');
  v_existing app.tickets;
  v_existing_body text;
  v_ticket app.tickets;
  v_number text;
begin
  if p_channel is null or not (p_channel = any (array['internal', 'customer'])) then
    raise exception 'invalid_channel: % is not one of internal/customer', p_channel using errcode = 'check_violation';
  end if;
  if p_channel = 'internal' then
    if p_requester_employee_id is null or p_requester_customer_account_id is not null then
      raise exception 'invalid_requester_identity: internal channel requires exactly a requester_employee_id' using errcode = 'check_violation';
    end if;
  else
    if p_requester_customer_account_id is null or p_requester_employee_id is not null then
      raise exception 'invalid_requester_identity: customer channel requires exactly a requester_customer_account_id' using errcode = 'check_violation';
    end if;
  end if;

  if p_subject is null or length(trim(p_subject)) = 0 then
    raise exception 'subject_required: a non-empty subject is required' using errcode = 'check_violation';
  end if;
  if p_body is null or length(trim(p_body)) = 0 then
    raise exception 'body_required: a non-empty ticket description is required' using errcode = 'check_violation';
  end if;
  if not (v_priority = any (array['low', 'normal', 'high', 'urgent'])) then
    raise exception 'invalid_priority: % is not one of low/normal/high/urgent', v_priority using errcode = 'check_violation';
  end if;

  select * into v_category from app.ticket_categories where id = p_category_id and tenant_id = p_tenant_id and status = 'active';
  if not found then
    raise exception 'category_not_available: % is not an active category for this tenant', p_category_id using errcode = 'no_data_found';
  end if;

  v_resolved_queue_id := coalesce(p_queue_id, v_category.default_queue_id);
  if v_resolved_queue_id is null then
    raise exception 'queue_required: no queue was supplied and category % has no default queue', p_category_id using errcode = 'check_violation';
  end if;
  if not exists (select 1 from app.ticket_queues where id = v_resolved_queue_id and tenant_id = p_tenant_id and status = 'active') then
    raise exception 'queue_not_available: % is not an active queue for this tenant', v_resolved_queue_id using errcode = 'no_data_found';
  end if;

  if p_idempotency_key is not null then
    if p_channel = 'internal' then
      select * into v_existing from app.tickets
      where tenant_id = p_tenant_id and channel = 'internal' and requester_employee_id = p_requester_employee_id and idempotency_key = p_idempotency_key;
    else
      select * into v_existing from app.tickets
      where tenant_id = p_tenant_id and channel = 'customer' and requested_by_auth_user_id = p_actor_auth_user_id and idempotency_key = p_idempotency_key;
    end if;
    if found then
      select m.body into v_existing_body from app.ticket_messages m where m.ticket_id = v_existing.id order by m.created_at asc limit 1;
      if v_existing.category_id = p_category_id and v_existing.queue_id = v_resolved_queue_id and v_existing.priority = v_priority
         and v_existing.subject = p_subject and coalesce(v_existing_body, '') = p_body then
        return v_existing;
      else
        raise exception 'idempotency_key_conflict: key % was already used for a different ticket', p_idempotency_key using errcode = 'unique_violation';
      end if;
    end if;
  end if;

  v_number := app.next_ticket_number(p_tenant_id);

  begin
    insert into app.tickets (
      tenant_id, ticket_number, channel, category_id, queue_id, priority, subject, status,
      requester_employee_id, requester_customer_account_id, requested_by_auth_user_id, requested_by, idempotency_key, created_by
    ) values (
      p_tenant_id, v_number, p_channel, p_category_id, v_resolved_queue_id, v_priority, p_subject, 'new',
      p_requester_employee_id, p_requester_customer_account_id, p_actor_auth_user_id, p_actor_label, p_idempotency_key, p_actor_label
    )
    returning * into v_ticket;
  exception
    when unique_violation then
      if p_idempotency_key is not null then
        if p_channel = 'internal' then
          select * into v_ticket from app.tickets
          where tenant_id = p_tenant_id and channel = 'internal' and requester_employee_id = p_requester_employee_id and idempotency_key = p_idempotency_key;
        else
          select * into v_ticket from app.tickets
          where tenant_id = p_tenant_id and channel = 'customer' and requested_by_auth_user_id = p_actor_auth_user_id and idempotency_key = p_idempotency_key;
        end if;
        if found then
          select m.body into v_existing_body from app.ticket_messages m where m.ticket_id = v_ticket.id order by m.created_at asc limit 1;
          if v_ticket.category_id = p_category_id and v_ticket.queue_id = v_resolved_queue_id and v_ticket.priority = v_priority
             and v_ticket.subject = p_subject and coalesce(v_existing_body, '') = p_body then
            return v_ticket;
          end if;
        end if;
      end if;
      raise;
  end;

  insert into app.ticket_messages (tenant_id, ticket_id, visibility, body, author_auth_user_id, author_label, author_role)
  values (p_tenant_id, v_ticket.id, 'public', p_body, p_actor_auth_user_id, p_actor_label, 'requester');

  insert into app.ticket_events (tenant_id, ticket_id, event_type, from_value, to_value, actor_auth_user_id, actor_label)
  values (p_tenant_id, v_ticket.id, 'create', null, 'new', p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_ticket',
    'app.tickets', v_ticket.id, 'success', null, null, app.ticket_audit_projection(v_ticket)
  );

  return v_ticket;
end;
$$;

comment on function app._create_ticket is
  'HRT-286/287 (decision 4/ISS-2026-085 resolved): the shared ticket-creation engine, now taking a real p_channel and per-channel requester identity parameter, validated to be exactly one of employee/customer-account matching that channel (belt-and-suspenders alongside the table CHECK tickets_requester_identity_shape). Called by app.create_ticket/app.create_ticket_for_employee (channel:=''internal'') and app.create_customer_ticket (channel:=''customer''). Idempotency replay is keyed differently per channel (requester_employee_id for internal, requested_by_auth_user_id for customer) -- see tickets_idempotency_unique / tickets_idempotency_customer_unique.';

grant execute on function app._create_ticket(uuid, text, uuid, uuid, uuid, uuid, text, text, text, text, uuid, text) to service_role;
grant execute on function app._is_ticket_requester_party(app.tickets, uuid) to service_role;

-- ===========================================================================
-- 8. app.create_ticket / app.create_ticket_for_employee -- external
--    signatures UNCHANGED, bodies updated to pass p_channel explicitly.
--    Grants preserved by CREATE OR REPLACE.
-- ===========================================================================

create or replace function app.create_ticket(
  p_tenant_id uuid, p_category_id uuid, p_queue_id uuid, p_priority text, p_subject text, p_body text,
  p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.tickets
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_self app.employees;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'employee_not_found: no linked employee profile' using errcode = 'no_data_found';
  end if;
  v_self := app.get_self_employee(p_tenant_id, p_actor_auth_user_id);
  if v_self.master_record_id is null then
    raise exception 'employee_not_found: no linked employee profile' using errcode = 'no_data_found';
  end if;
  return app._create_ticket(p_tenant_id, 'internal', v_self.master_record_id, null, p_category_id, p_queue_id, p_priority, p_subject, p_body, p_idempotency_key, p_actor_auth_user_id, p_actor_label);
end;
$$;

create or replace function app.create_ticket_for_employee(
  p_tenant_id uuid, p_requester_employee_id uuid, p_category_id uuid, p_queue_id uuid, p_priority text, p_subject text, p_body text,
  p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.tickets
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_employee app.employees;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'TKT', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks TKT:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_employee from app.employees where master_record_id = p_requester_employee_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'employee_not_found: %', p_requester_employee_id using errcode = 'no_data_found';
  end if;

  return app._create_ticket(p_tenant_id, 'internal', v_employee.master_record_id, null, p_category_id, p_queue_id, p_priority, p_subject, p_body, p_idempotency_key, p_actor_auth_user_id, p_actor_label);
end;
$$;

-- ===========================================================================
-- 9. app.create_customer_ticket -- new Layer 4 self-service entry point
--    (decision 5). Scope is always validated against membership, never
--    trusted from the payload; queue is never caller-supplied.
-- ===========================================================================

create function app.create_customer_ticket(
  p_tenant_id uuid,
  p_account_id uuid,
  p_category_id uuid,
  p_priority text,
  p_subject text,
  p_body text,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.tickets
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_category app.ticket_categories;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  -- Decision 5: p_account_id is a real parameter (a customer admin may hold
  -- membership on several accounts), but it is ALWAYS checked against the
  -- membership-derived scope before use -- never trusted as given. The same
  -- error covers "not your account" and "no such account" (anti-
  -- enumeration, mirrors ATW-242's own established discipline).
  if p_account_id is null or not (p_account_id = any (app.resolve_customer_owner_account_scope(p_actor_auth_user_id, p_tenant_id))) then
    raise exception 'account_not_available: % is not an account this identity may file a ticket for', p_account_id using errcode = 'no_data_found';
  end if;

  select * into v_category from app.ticket_categories where id = p_category_id and tenant_id = p_tenant_id and status = 'active' and customer_visible = true;
  if not found then
    raise exception 'category_not_available: % is not an active customer-visible category for this tenant', p_category_id using errcode = 'no_data_found';
  end if;
  if v_category.default_queue_id is null then
    raise exception 'queue_required: customer-visible category % has no default queue configured', p_category_id using errcode = 'check_violation';
  end if;

  return app._create_ticket(p_tenant_id, 'customer', null, p_account_id, p_category_id, v_category.default_queue_id, p_priority, p_subject, p_body, p_idempotency_key, p_actor_auth_user_id, p_actor_label);
end;
$$;

comment on function app.create_customer_ticket is
  'HRT-287: Layer 4 customer self-service creation. p_account_id must already be in app.resolve_customer_owner_account_scope(actor, tenant) -- a forged/unowned id is rejected with the same account_not_available a nonexistent id would produce. No p_queue_id parameter exists -- the queue is always the chosen category''s own default_queue_id (customer-visible categories are required to have one, enforced by app.set_ticket_category_customer_visibility), so a customer can never probe or forge an internal queue id.';

grant execute on function app.create_customer_ticket(uuid, uuid, uuid, text, text, text, text, uuid, text) to authenticated, service_role;

-- ===========================================================================
-- 10. app.set_ticket_category_customer_visibility -- TKT:Edit-gated toggle
--     (decision 11).
-- ===========================================================================

create function app.set_ticket_category_customer_visibility(p_category_id uuid, p_customer_visible boolean, p_actor_auth_user_id uuid, p_actor_label text)
returns app.ticket_categories
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_category app.ticket_categories;
  v_updated app.ticket_categories;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_category from app.ticket_categories where id = p_category_id for update;
  if not found then
    raise exception 'ticket_category_not_found: %', p_category_id using errcode = 'no_data_found';
  end if;
  if not app.check_ticket_authority('Edit', v_category.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks TKT:Edit for tenant %', p_actor_auth_user_id, v_category.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_customer_visible and v_category.default_queue_id is null then
    raise exception 'queue_required: a customer-visible category must have a default queue configured first' using errcode = 'check_violation';
  end if;

  update app.ticket_categories set customer_visible = p_customer_visible
  where id = p_category_id
  returning * into v_updated;

  perform app.capture_audit_event(
    v_category.tenant_id, p_actor_auth_user_id, p_actor_label, 'set_ticket_category_customer_visibility',
    'app.ticket_categories', v_updated.id, 'success', null,
    jsonb_build_object('customer_visible', v_category.customer_visible),
    jsonb_build_object('customer_visible', v_updated.customer_visible)
  );

  return v_updated;
end;
$$;

grant execute on function app.set_ticket_category_customer_visibility(uuid, boolean, uuid, text) to authenticated, service_role;

-- ===========================================================================
-- 11. app.reply_to_ticket -- generalized identity resolution (decision 3).
--     Same external signature; grants preserved.
-- ===========================================================================

create or replace function app.reply_to_ticket(
  p_ticket_id uuid, p_body text, p_visibility text, p_attachment_file_ids uuid[], p_idempotency_key text,
  p_actor_auth_user_id uuid, p_actor_label text
)
returns app.ticket_messages
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_ticket app.tickets;
  v_is_requester boolean;
  v_is_staff boolean;
  v_visibility text := coalesce(p_visibility, 'public');
  v_author_role text;
  v_existing app.ticket_messages;
  v_message app.ticket_messages;
  v_file app.files;
  v_file_id uuid;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_ticket from app.tickets where id = p_ticket_id for update;
  if not found then
    raise exception 'ticket_not_found: %', p_ticket_id using errcode = 'no_data_found';
  end if;

  -- C-05: a caller with NO relationship to this ticket at all gets the SAME
  -- ticket_not_found a genuinely missing id would produce.
  if not app.can_access_ticket(p_ticket_id, p_actor_auth_user_id) then
    raise exception 'ticket_not_found: %', p_ticket_id using errcode = 'no_data_found';
  end if;

  if v_ticket.status = 'cancelled' then
    raise exception 'ticket_cancelled: cancelled ticket % cannot receive new messages', p_ticket_id using errcode = 'check_violation';
  end if;

  v_is_requester := app._is_ticket_requester_party(v_ticket, p_actor_auth_user_id);
  v_is_staff := app.is_ticket_staff(p_ticket_id, p_actor_auth_user_id);

  if not (v_is_requester or v_is_staff) then
    raise exception 'insufficient_authority: identity % is not a participant on ticket %', p_actor_auth_user_id, p_ticket_id
      using errcode = 'insufficient_privilege';
  end if;

  if not (v_visibility = any (array['public', 'internal'])) then
    raise exception 'invalid_visibility: % is not one of public/internal', v_visibility using errcode = 'check_violation';
  end if;
  if v_visibility = 'internal' and not v_is_staff then
    raise exception 'insufficient_authority: only ticket staff may post an internal note' using errcode = 'insufficient_privilege';
  end if;
  if p_body is null or length(trim(p_body)) = 0 then
    raise exception 'body_required: a non-empty message body is required' using errcode = 'check_violation';
  end if;

  v_author_role := case when v_is_staff then 'staff' else 'requester' end;

  if p_idempotency_key is not null then
    select * into v_existing from app.ticket_messages
    where tenant_id = v_ticket.tenant_id and ticket_id = p_ticket_id and idempotency_key = p_idempotency_key;
    if found then
      if v_existing.visibility = v_visibility and v_existing.body = p_body then
        return v_existing;
      else
        raise exception 'idempotency_key_conflict: key % was already used for a different message', p_idempotency_key using errcode = 'unique_violation';
      end if;
    end if;
  end if;

  if p_attachment_file_ids is not null then
    foreach v_file_id in array p_attachment_file_ids loop
      select * into v_file from app.files where id = v_file_id;
      if not found or v_file.tenant_id <> v_ticket.tenant_id or v_file.record_type <> 'ticket' or v_file.record_id <> p_ticket_id then
        raise exception 'evidence_file_not_found: file % is not a valid attachment for ticket %', v_file_id, p_ticket_id using errcode = 'no_data_found';
      end if;
      if v_file.malware_scan_status = 'infected' then
        raise exception 'evidence_file_infected: file % failed malware scanning and cannot be attached', v_file_id using errcode = 'check_violation';
      end if;
      if v_file.malware_scan_status <> 'clean' then
        raise exception 'evidence_file_not_scanned: file % has not cleared malware scanning (status %)', v_file_id, v_file.malware_scan_status
          using errcode = 'check_violation';
      end if;
    end loop;
  end if;

  begin
    insert into app.ticket_messages (tenant_id, ticket_id, visibility, body, attachment_file_ids, author_auth_user_id, author_label, author_role, idempotency_key)
    values (v_ticket.tenant_id, p_ticket_id, v_visibility, p_body, coalesce(p_attachment_file_ids, '{}'::uuid[]), p_actor_auth_user_id, p_actor_label, v_author_role, p_idempotency_key)
    returning * into v_message;
  exception
    when unique_violation then
      if p_idempotency_key is not null then
        select * into v_message from app.ticket_messages
        where tenant_id = v_ticket.tenant_id and ticket_id = p_ticket_id and idempotency_key = p_idempotency_key;
        if found and v_message.visibility = v_visibility and v_message.body = p_body then
          return v_message;
        end if;
      end if;
      raise;
  end;

  perform app.capture_audit_event(
    v_ticket.tenant_id, p_actor_auth_user_id, p_actor_label, 'reply_to_ticket',
    'app.ticket_messages', v_message.id, 'success', null, null,
    jsonb_build_object('ticket_id', p_ticket_id, 'visibility', v_message.visibility, 'attachment_count', coalesce(array_length(v_message.attachment_file_ids, 1), 0))
  );

  return v_message;
end;
$$;

-- ===========================================================================
-- 12. app.reply_to_customer_ticket -- thin defense-in-depth wrapper
--     (decision 9). Hardcodes visibility=public at the SQL call site.
-- ===========================================================================

create function app.reply_to_customer_ticket(
  p_ticket_id uuid, p_body text, p_attachment_file_ids uuid[], p_idempotency_key text,
  p_actor_auth_user_id uuid, p_actor_label text
)
returns app.ticket_messages
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_ticket app.tickets;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_ticket from app.tickets where id = p_ticket_id;
  if not found or v_ticket.channel <> 'customer' then
    raise exception 'ticket_not_found: %', p_ticket_id using errcode = 'no_data_found';
  end if;

  return app.reply_to_ticket(p_ticket_id, p_body, 'public', p_attachment_file_ids, p_idempotency_key, p_actor_auth_user_id, p_actor_label);
end;
$$;

comment on function app.reply_to_customer_ticket is
  'HRT-287 (decision 9): thin wrapper over app.reply_to_ticket -- hardcodes visibility=''public'' at the call site itself (a customer caller has no way to even attempt visibility=''internal'' through this entry point) and independently confirms the target ticket is genuinely channel=''customer'' before delegating. app.reply_to_ticket''s own internal guard (only staff may set visibility=internal) is unchanged and still applies -- two independent enforcement points for the one guarantee.';

grant execute on function app.reply_to_customer_ticket(uuid, text, uuid[], text, uuid, text) to authenticated, service_role;

-- ===========================================================================
-- 13. app.add_ticket_watcher / app.remove_ticket_watcher -- generalized
--     identity resolution, staff-only for a customer-channel ticket
--     (decisions 3/8). Same external signatures; grants preserved.
-- ===========================================================================

create or replace function app.add_ticket_watcher(p_ticket_id uuid, p_employee_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
returns app.ticket_watchers
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_ticket app.tickets;
  v_is_requester boolean;
  v_is_staff boolean;
  v_row app.ticket_watchers;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_ticket from app.tickets where id = p_ticket_id;
  if not found then
    raise exception 'ticket_not_found: %', p_ticket_id using errcode = 'no_data_found';
  end if;

  if not app.can_access_ticket(p_ticket_id, p_actor_auth_user_id) then
    raise exception 'ticket_not_found: %', p_ticket_id using errcode = 'no_data_found';
  end if;

  v_is_staff := app.is_ticket_staff(p_ticket_id, p_actor_auth_user_id);
  v_is_requester := app._is_ticket_requester_party(v_ticket, p_actor_auth_user_id);

  if v_ticket.channel = 'customer' then
    -- Decision 8: watchers are an employee/staff mechanism -- a
    -- customer-channel requester never manages this roster, even for
    -- their own ticket.
    if not v_is_staff then
      raise exception 'insufficient_authority: identity % may not add a watcher to ticket %', p_actor_auth_user_id, p_ticket_id
        using errcode = 'insufficient_privilege';
    end if;
  elsif not (v_is_requester or v_is_staff) then
    raise exception 'insufficient_authority: identity % may not add a watcher to ticket %', p_actor_auth_user_id, p_ticket_id
      using errcode = 'insufficient_privilege';
  end if;

  if not exists (select 1 from app.employees e where e.master_record_id = p_employee_id and e.tenant_id = v_ticket.tenant_id) then
    raise exception 'employee_not_found: %', p_employee_id using errcode = 'no_data_found';
  end if;

  select * into v_row from app.ticket_watchers where ticket_id = p_ticket_id and employee_id = p_employee_id and status = 'active';
  if found then
    return v_row;
  end if;

  begin
    insert into app.ticket_watchers (tenant_id, ticket_id, employee_id, added_by)
    values (v_ticket.tenant_id, p_ticket_id, p_employee_id, p_actor_label)
    returning * into v_row;
  exception
    when unique_violation then
      select * into v_row from app.ticket_watchers where ticket_id = p_ticket_id and employee_id = p_employee_id and status = 'active';
      if not found then
        raise;
      end if;
  end;

  insert into app.ticket_events (tenant_id, ticket_id, event_type, to_value, actor_auth_user_id, actor_label)
  values (v_ticket.tenant_id, p_ticket_id, 'watcher_added', p_employee_id::text, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_ticket.tenant_id, p_actor_auth_user_id, p_actor_label, 'add_ticket_watcher',
    'app.ticket_watchers', v_row.id, 'success', null, null, jsonb_build_object('ticket_id', p_ticket_id, 'employee_id', p_employee_id)
  );

  return v_row;
end;
$$;

create or replace function app.remove_ticket_watcher(p_watcher_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
returns app.ticket_watchers
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_row app.ticket_watchers;
  v_ticket app.tickets;
  v_is_requester boolean;
  v_is_staff boolean;
  v_is_self_watcher boolean;
  v_self app.employees;
  v_updated app.ticket_watchers;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_row from app.ticket_watchers where id = p_watcher_id for update;
  if not found then
    raise exception 'ticket_watcher_not_found: %', p_watcher_id using errcode = 'no_data_found';
  end if;
  select * into v_ticket from app.tickets where id = v_row.ticket_id;

  if not app.can_access_ticket(v_ticket.id, p_actor_auth_user_id) then
    raise exception 'ticket_watcher_not_found: %', p_watcher_id using errcode = 'no_data_found';
  end if;

  v_is_staff := app.is_ticket_staff(v_ticket.id, p_actor_auth_user_id);
  v_is_requester := app._is_ticket_requester_party(v_ticket, p_actor_auth_user_id);
  v_self := app.get_self_employee(v_ticket.tenant_id, p_actor_auth_user_id);
  v_is_self_watcher := v_self.master_record_id is not null and v_self.master_record_id = v_row.employee_id;

  if v_ticket.channel = 'customer' then
    if not (v_is_staff or v_is_self_watcher) then
      raise exception 'insufficient_authority: identity % may not remove watcher %', p_actor_auth_user_id, p_watcher_id
        using errcode = 'insufficient_privilege';
    end if;
  elsif not (v_is_requester or v_is_staff or v_is_self_watcher) then
    raise exception 'insufficient_authority: identity % may not remove watcher %', p_actor_auth_user_id, p_watcher_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_row.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_row.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_row.status <> 'active' then
    raise exception 'invalid_transition: watcher % is % not active', p_watcher_id, v_row.status using errcode = 'check_violation';
  end if;

  update app.ticket_watchers set status = 'removed', removed_by = p_actor_label, removed_at = now()
  where id = p_watcher_id and record_version = p_expected_version
  returning * into v_updated;
  if not found then
    raise exception 'stale_version: concurrent update detected for ticket watcher %', p_watcher_id using errcode = 'serialization_failure';
  end if;

  insert into app.ticket_events (tenant_id, ticket_id, event_type, from_value, actor_auth_user_id, actor_label)
  values (v_ticket.tenant_id, v_ticket.id, 'watcher_removed', v_updated.employee_id::text, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_ticket.tenant_id, p_actor_auth_user_id, p_actor_label, 'remove_ticket_watcher',
    'app.ticket_watchers', v_updated.id, 'success', null, null, jsonb_build_object('ticket_id', v_ticket.id, 'employee_id', v_updated.employee_id)
  );

  return v_updated;
end;
$$;

-- ===========================================================================
-- 14. Staff-facing read RPCs -- hardened to refuse a customer_user-layer
--     caller entirely (decision 6), and INNER JOIN -> LEFT JOIN on the
--     requester so a customer-channel ticket is still readable to STAFF
--     (ISS-2026-085's own named fix). get_ticket/list_tickets/
--     list_ticket_categories change OUTPUT COLUMNS -- explicit DROP+CREATE
--     with fresh grants; the rest are CREATE OR REPLACE (grants preserved).
-- ===========================================================================

drop function if exists app.get_ticket(uuid, uuid);

create function app.get_ticket(p_ticket_id uuid, p_actor_auth_user_id uuid)
returns table (
  id uuid, tenant_id uuid, ticket_number text, channel text,
  category_id uuid, category_code text, category_name text,
  queue_id uuid, queue_code text, queue_name text,
  priority text, subject text, status text,
  requester_employee_id uuid, requester_customer_account_id uuid, requester_name text,
  requested_by_auth_user_id uuid, requested_by text,
  assignee_employee_id uuid, assignee_name text, assigned_at timestamptz,
  resolution_summary text, resolved_at timestamptz, closed_at timestamptz,
  cancelled_reason text, cancelled_at timestamptz, reopen_count integer,
  record_version integer, created_at timestamptz, updated_at timestamptz,
  is_staff_viewer boolean, is_requester_viewer boolean
)
language plpgsql
security definer
set search_path = app, pg_temp
stable
as $$
declare
  v_tenant_id uuid;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if not app.can_access_ticket(p_ticket_id, p_actor_auth_user_id) then
    return;
  end if;

  select t0.tenant_id into v_tenant_id from app.tickets t0 where t0.id = p_ticket_id;

  -- Decision 6: this is the STAFF projection (internal queue/assignee
  -- identity). A customer_user-layer actor is refused here even though
  -- can_access_ticket now legitimately admits them to their OWN ticket --
  -- app.get_customer_ticket is their dedicated, customer-safe projection.
  if app.actor_holds_customer_user_layer(v_tenant_id, p_actor_auth_user_id) then
    return;
  end if;

  return query
  select
    t.id, t.tenant_id, t.ticket_number, t.channel,
    t.category_id, c.code, c.name,
    t.queue_id, q.code, q.name,
    t.priority, t.subject, t.status,
    t.requester_employee_id, t.requester_customer_account_id, coalesce(re.full_name, ac.legal_name),
    t.requested_by_auth_user_id, t.requested_by,
    t.assignee_employee_id, ae.full_name, t.assigned_at,
    t.resolution_summary, t.resolved_at, t.closed_at,
    t.cancelled_reason, t.cancelled_at, t.reopen_count,
    t.record_version, t.created_at, t.updated_at,
    app.is_ticket_staff(t.id, p_actor_auth_user_id),
    app._is_ticket_requester_party(t, p_actor_auth_user_id)
  from app.tickets t
  join app.ticket_categories c on c.id = t.category_id
  join app.ticket_queues q on q.id = t.queue_id
  left join app.employees re on re.master_record_id = t.requester_employee_id
  left join app.accounts ac on ac.id = t.requester_customer_account_id
  left join app.employees ae on ae.master_record_id = t.assignee_employee_id
  where t.id = p_ticket_id;
end;
$$;

grant execute on function app.get_ticket(uuid, uuid) to authenticated, service_role;

drop function if exists app.list_tickets(uuid, uuid, text, uuid, uuid, text, uuid, integer, uuid);

create function app.list_tickets(
  p_tenant_id uuid, p_actor_auth_user_id uuid, p_status text, p_queue_id uuid, p_category_id uuid,
  p_priority text, p_assignee_employee_id uuid, p_limit integer, p_after_id uuid
)
returns table (
  id uuid, ticket_number text, subject text, status text, priority text,
  category_code text, queue_code text, requester_employee_id uuid, requester_customer_account_id uuid, requester_name text,
  assignee_employee_id uuid, assignee_name text, record_version integer, created_at timestamptz, updated_at timestamptz
)
language plpgsql
security definer
set search_path = app, pg_temp
stable
as $$
declare
  v_limit integer := least(greatest(coalesce(p_limit, 50), 1), 200);
  v_after_created_at timestamptz;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if app.actor_holds_customer_user_layer(p_tenant_id, p_actor_auth_user_id) then
    return;
  end if;

  if p_after_id is not null then
    select t0.created_at into v_after_created_at from app.tickets t0 where t0.id = p_after_id;
  end if;

  return query
  select t.id, t.ticket_number, t.subject, t.status, t.priority, c.code, q.code,
         t.requester_employee_id, t.requester_customer_account_id, coalesce(re.full_name, ac.legal_name),
         t.assignee_employee_id, ae.full_name,
         t.record_version, t.created_at, t.updated_at
  from app.tickets t
  join app.ticket_categories c on c.id = t.category_id
  join app.ticket_queues q on q.id = t.queue_id
  left join app.employees re on re.master_record_id = t.requester_employee_id
  left join app.accounts ac on ac.id = t.requester_customer_account_id
  left join app.employees ae on ae.master_record_id = t.assignee_employee_id
  where t.tenant_id = p_tenant_id
    and app.can_access_ticket(t.id, p_actor_auth_user_id)
    and (p_status is null or t.status = p_status)
    and (p_queue_id is null or t.queue_id = p_queue_id)
    and (p_category_id is null or t.category_id = p_category_id)
    and (p_priority is null or t.priority = p_priority)
    and (p_assignee_employee_id is null or t.assignee_employee_id = p_assignee_employee_id)
    and (p_after_id is null or t.created_at < v_after_created_at or (t.created_at = v_after_created_at and t.id < p_after_id))
  order by t.created_at desc, t.id desc
  limit v_limit;
end;
$$;

grant execute on function app.list_tickets(uuid, uuid, text, uuid, uuid, text, uuid, integer, uuid) to authenticated, service_role;

create or replace function app.list_my_tickets(p_tenant_id uuid, p_actor_auth_user_id uuid, p_status text, p_limit integer, p_after_id uuid)
returns table (
  id uuid, ticket_number text, subject text, status text, priority text,
  category_code text, queue_code text, assignee_employee_id uuid, assignee_name text,
  record_version integer, created_at timestamptz, updated_at timestamptz
)
language plpgsql
security definer
set search_path = app, pg_temp
stable
as $$
declare
  v_self app.employees;
  v_limit integer := least(greatest(coalesce(p_limit, 50), 1), 200);
  v_after_created_at timestamptz;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if app.actor_holds_customer_user_layer(p_tenant_id, p_actor_auth_user_id) then
    return;
  end if;
  v_self := app.get_self_employee(p_tenant_id, p_actor_auth_user_id);
  if v_self.master_record_id is null then
    return;
  end if;

  if p_after_id is not null then
    select t0.created_at into v_after_created_at from app.tickets t0 where t0.id = p_after_id;
  end if;

  return query
  select t.id, t.ticket_number, t.subject, t.status, t.priority, c.code, q.code,
         t.assignee_employee_id, ae.full_name, t.record_version, t.created_at, t.updated_at
  from app.tickets t
  join app.ticket_categories c on c.id = t.category_id
  join app.ticket_queues q on q.id = t.queue_id
  left join app.employees ae on ae.master_record_id = t.assignee_employee_id
  where t.tenant_id = p_tenant_id
    and t.requester_employee_id = v_self.master_record_id
    and (p_status is null or t.status = p_status)
    and (p_after_id is null or t.created_at < v_after_created_at or (t.created_at = v_after_created_at and t.id < p_after_id))
  order by t.created_at desc, t.id desc
  limit v_limit;
end;
$$;

create or replace function app.list_ticket_messages(p_ticket_id uuid, p_actor_auth_user_id uuid, p_limit integer, p_after_id uuid)
returns table (
  id uuid, ticket_id uuid, visibility text, body text, is_redacted boolean, attachment_file_ids uuid[],
  author_auth_user_id uuid, author_label text, author_role text, created_at timestamptz, record_version integer
)
language plpgsql
security definer
set search_path = app, pg_temp
stable
as $$
declare
  v_tenant_id uuid;
  v_is_staff boolean;
  v_limit integer := least(greatest(coalesce(p_limit, 100), 1), 500);
  v_after_created_at timestamptz;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if not app.can_access_ticket(p_ticket_id, p_actor_auth_user_id) then
    return;
  end if;
  select t0.tenant_id into v_tenant_id from app.tickets t0 where t0.id = p_ticket_id;
  if app.actor_holds_customer_user_layer(v_tenant_id, p_actor_auth_user_id) then
    return;
  end if;
  v_is_staff := app.is_ticket_staff(p_ticket_id, p_actor_auth_user_id);

  if p_after_id is not null then
    select m0.created_at into v_after_created_at from app.ticket_messages m0 where m0.id = p_after_id;
  end if;

  return query
  select m.id, m.ticket_id, m.visibility, m.body, m.is_redacted, m.attachment_file_ids,
         m.author_auth_user_id, m.author_label, m.author_role, m.created_at, m.record_version
  from app.ticket_messages m
  where m.ticket_id = p_ticket_id
    and (m.visibility = 'public' or v_is_staff)
    and (p_after_id is null or m.created_at > v_after_created_at or (m.created_at = v_after_created_at and m.id > p_after_id))
  order by m.created_at asc, m.id asc
  limit v_limit;
end;
$$;

create or replace function app.list_ticket_watchers(p_ticket_id uuid, p_actor_auth_user_id uuid)
returns table (id uuid, ticket_id uuid, employee_id uuid, employee_name text, status text, added_by text, added_at timestamptz, record_version integer)
language plpgsql
security definer
set search_path = app, pg_temp
stable
as $$
declare
  v_tenant_id uuid;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if not app.can_access_ticket(p_ticket_id, p_actor_auth_user_id) then
    return;
  end if;
  select t0.tenant_id into v_tenant_id from app.tickets t0 where t0.id = p_ticket_id;
  if app.actor_holds_customer_user_layer(v_tenant_id, p_actor_auth_user_id) then
    return;
  end if;
  return query
  select w.id, w.ticket_id, w.employee_id, e.full_name, w.status, w.added_by, w.added_at, w.record_version
  from app.ticket_watchers w
  join app.employees e on e.master_record_id = w.employee_id
  where w.ticket_id = p_ticket_id and w.status = 'active'
  order by w.added_at asc;
end;
$$;

create or replace function app.list_ticket_events(p_ticket_id uuid, p_actor_auth_user_id uuid)
returns table (id uuid, ticket_id uuid, event_type text, from_value text, to_value text, reason text, actor_auth_user_id uuid, actor_label text, occurred_at timestamptz)
language plpgsql
security definer
set search_path = app, pg_temp
stable
as $$
declare
  v_tenant_id uuid;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if not app.can_access_ticket(p_ticket_id, p_actor_auth_user_id) then
    return;
  end if;
  select t0.tenant_id into v_tenant_id from app.tickets t0 where t0.id = p_ticket_id;
  if app.actor_holds_customer_user_layer(v_tenant_id, p_actor_auth_user_id) then
    return;
  end if;
  return query
  select ev.id, ev.ticket_id, ev.event_type, ev.from_value, ev.to_value, ev.reason, ev.actor_auth_user_id, ev.actor_label, ev.occurred_at
  from app.ticket_events ev
  where ev.ticket_id = p_ticket_id
  order by ev.occurred_at asc;
end;
$$;

create or replace function app.export_tickets(p_tenant_id uuid, p_actor_auth_user_id uuid, p_from_date date, p_to_date date)
returns table (
  ticket_number text, subject text, status text, priority text, category_code text, queue_code text,
  requester_name text, assignee_name text, created_at timestamptz, resolved_at timestamptz, closed_at timestamptz
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'TKT', 'Export');
  if not v_decision.allowed or app.actor_holds_customer_user_layer(p_tenant_id, p_actor_auth_user_id) then
    return;
  end if;

  if p_from_date is null or p_to_date is null or (p_to_date - p_from_date) > 366 then
    raise exception 'invalid_date_range: export date range must be non-empty and at most 366 days' using errcode = 'check_violation';
  end if;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_auth_user_id::text, 'export_tickets',
    'app.tickets', null, 'success', null, null, jsonb_build_object('from_date', p_from_date, 'to_date', p_to_date)
  );

  return query
  select t.ticket_number, t.subject, t.status, t.priority, c.code, q.code, coalesce(re.full_name, ac.legal_name), ae.full_name, t.created_at, t.resolved_at, t.closed_at
  from app.tickets t
  join app.ticket_categories c on c.id = t.category_id
  join app.ticket_queues q on q.id = t.queue_id
  left join app.employees re on re.master_record_id = t.requester_employee_id
  left join app.accounts ac on ac.id = t.requester_customer_account_id
  left join app.employees ae on ae.master_record_id = t.assignee_employee_id
  where t.tenant_id = p_tenant_id and t.created_at::date between p_from_date and p_to_date
  order by t.created_at asc;
end;
$$;

-- list_ticket_categories -- output widened with customer_visible for the
-- admin UI toggle. Explicit DROP+CREATE (output column list changes).
drop function if exists app.list_ticket_categories(uuid, uuid);

create function app.list_ticket_categories(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns table (id uuid, code text, name text, default_queue_id uuid, customer_visible boolean, status text, record_version integer)
language plpgsql
security definer
set search_path = app, pg_temp
stable
as $$
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) or app.actor_holds_customer_user_layer(p_tenant_id, p_actor_auth_user_id) then
    return;
  end if;
  return query
  select c.id, c.code, c.name, c.default_queue_id, c.customer_visible, c.status, c.record_version
  from app.ticket_categories c
  where c.tenant_id = p_tenant_id
  order by c.code asc;
end;
$$;

grant execute on function app.list_ticket_categories(uuid, uuid) to authenticated, service_role;

-- ===========================================================================
-- 15. Customer-facing RPCs -- bounded, customer-safe surface (decision 6),
--     sufficient for section 15's "create/list/detail/thread... isolation
--     and contract verification" -- never the full Step 13 portal.
-- ===========================================================================

create function app.list_customer_accounts_for_actor(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns table (account_id uuid, legal_name text, parent_account_id uuid)
language plpgsql
security definer
set search_path = app, pg_temp
stable
as $$
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  return query
  select a.id, a.legal_name, a.parent_account_id
  from app.accounts a
  where a.id = any (app.resolve_customer_owner_account_scope(p_actor_auth_user_id, p_tenant_id))
    and a.status = 'active'
  order by a.legal_name asc;
end;
$$;

comment on function app.list_customer_accounts_for_actor is
  'HRT-287 (decision 2): every app.accounts row this identity''s active customer_user membership(s) resolve to (app.resolve_customer_owner_account_scope, ATW-242) -- "account"/"company"/"site" are all the same app.accounts row shape, related via parent_account_id; this function does not distinguish them structurally, since membership scope (not row depth) is what determines visibility.';

create function app.list_customer_ticket_categories(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns table (id uuid, code text, name text)
language plpgsql
security definer
set search_path = app, pg_temp
stable
as $$
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if not app.actor_holds_customer_user_layer(p_tenant_id, p_actor_auth_user_id) then
    return;
  end if;
  return query
  select c.id, c.code, c.name
  from app.ticket_categories c
  where c.tenant_id = p_tenant_id and c.status = 'active' and c.customer_visible = true and c.default_queue_id is not null
  order by c.name asc;
end;
$$;

create function app.get_customer_ticket(p_ticket_id uuid, p_actor_auth_user_id uuid)
returns table (
  id uuid, ticket_number text, subject text, status text, priority text,
  category_name text, account_id uuid, account_name text,
  resolution_summary text, cancelled_reason text, last_reopen_reason text,
  reopen_count integer, record_version integer,
  created_at timestamptz, updated_at timestamptz, resolved_at timestamptz, closed_at timestamptz
)
language plpgsql
security definer
set search_path = app, pg_temp
stable
as $$
declare
  v_ticket app.tickets;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  -- Anti-enumeration: an internal-channel ticket id, another tenant's id,
  -- and a genuinely nonexistent id are ALL indistinguishable (zero rows) to
  -- a customer caller here -- the channel filter is applied FIRST, before
  -- any scope check, so this function never even evaluates
  -- can_access_ticket for a non-customer-channel ticket.
  select * into v_ticket from app.tickets t0 where t0.id = p_ticket_id and t0.channel = 'customer';
  if not found then
    return;
  end if;
  if not app.can_access_ticket(p_ticket_id, p_actor_auth_user_id) then
    return;
  end if;

  return query
  select t.id, t.ticket_number, t.subject, t.status, t.priority,
         c.name, t.requester_customer_account_id, a.legal_name,
         t.resolution_summary, t.cancelled_reason, t.last_reopen_reason,
         t.reopen_count, t.record_version,
         t.created_at, t.updated_at, t.resolved_at, t.closed_at
  from app.tickets t
  join app.ticket_categories c on c.id = t.category_id
  join app.accounts a on a.id = t.requester_customer_account_id
  where t.id = p_ticket_id;
end;
$$;

comment on function app.get_customer_ticket is
  'HRT-287 (decision 6): the customer-safe ticket projection -- deliberately excludes queue_id/queue_code/queue_name (internal routing) and assignee_employee_id/assignee_name (internal staff identity), unlike app.get_ticket. resolution_summary/cancelled_reason/last_reopen_reason ARE included -- these free-text fields exist specifically to communicate outcome/rationale back to the requester (resolution_summary is only ever set via a staff-authorized transition; cancelled_reason/last_reopen_reason are frequently the customer''s OWN submitted text), a deliberate, disclosed choice distinct from app.ticket_events (never exposed to a customer at all, since it can carry internal transfer/reassignment reasoning).';

create function app.list_customer_tickets(p_tenant_id uuid, p_actor_auth_user_id uuid, p_account_id uuid, p_status text, p_limit integer, p_after_id uuid)
returns table (
  id uuid, ticket_number text, subject text, status text, priority text,
  category_name text, account_id uuid, account_name text,
  record_version integer, created_at timestamptz, updated_at timestamptz
)
language plpgsql
security definer
set search_path = app, pg_temp
stable
as $$
declare
  v_scope uuid[];
  v_limit integer := least(greatest(coalesce(p_limit, 50), 1), 200);
  v_after_created_at timestamptz;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  v_scope := app.resolve_customer_owner_account_scope(p_actor_auth_user_id, p_tenant_id);
  if array_length(v_scope, 1) is null then
    return;
  end if;
  if p_account_id is not null and not (p_account_id = any (v_scope)) then
    return;
  end if;

  if p_after_id is not null then
    select t0.created_at into v_after_created_at from app.tickets t0 where t0.id = p_after_id;
  end if;

  return query
  select t.id, t.ticket_number, t.subject, t.status, t.priority,
         c.name, t.requester_customer_account_id, a.legal_name,
         t.record_version, t.created_at, t.updated_at
  from app.tickets t
  join app.ticket_categories c on c.id = t.category_id
  join app.accounts a on a.id = t.requester_customer_account_id
  where t.tenant_id = p_tenant_id
    and t.channel = 'customer'
    and t.requester_customer_account_id = any (v_scope)
    and (p_account_id is null or t.requester_customer_account_id = p_account_id)
    and (p_status is null or t.status = p_status)
    and (p_after_id is null or t.created_at < v_after_created_at or (t.created_at = v_after_created_at and t.id < p_after_id))
  order by t.created_at desc, t.id desc
  limit v_limit;
end;
$$;

create function app.list_customer_ticket_messages(p_ticket_id uuid, p_actor_auth_user_id uuid, p_limit integer, p_after_id uuid)
returns table (
  id uuid, ticket_id uuid, body text, is_redacted boolean, attachment_file_ids uuid[],
  author_role text, author_display text, created_at timestamptz, record_version integer
)
language plpgsql
security definer
set search_path = app, pg_temp
stable
as $$
declare
  v_ticket app.tickets;
  v_limit integer := least(greatest(coalesce(p_limit, 100), 1), 500);
  v_after_created_at timestamptz;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_ticket from app.tickets t0 where t0.id = p_ticket_id and t0.channel = 'customer';
  if not found then
    return;
  end if;
  if not app.can_access_ticket(p_ticket_id, p_actor_auth_user_id) then
    return;
  end if;

  if p_after_id is not null then
    select m0.created_at into v_after_created_at from app.ticket_messages m0 where m0.id = p_after_id;
  end if;

  -- Decision 6: visibility is hard-filtered to 'public' -- this function
  -- accepts no visibility parameter at all, so an internal note can never
  -- reach a customer caller through this path structurally. A staff
  -- author's real name/label is replaced with a fixed generic label
  -- ('Support Team') -- deliberate, matches common support-desk UX and
  -- this prompt's own "support metadata... must never leak" instruction; a
  -- customer-authored message keeps its own real author_label (their own
  -- text, safe to echo back).
  return query
  select m.id, m.ticket_id, m.body, m.is_redacted, m.attachment_file_ids,
         m.author_role,
         case when m.author_role = 'staff' then 'Support Team' else coalesce(m.author_label, 'You') end,
         m.created_at, m.record_version
  from app.ticket_messages m
  where m.ticket_id = p_ticket_id
    and m.visibility = 'public'
    and (p_after_id is null or m.created_at > v_after_created_at or (m.created_at = v_after_created_at and m.id > p_after_id))
  order by m.created_at asc, m.id asc
  limit v_limit;
end;
$$;

-- ===========================================================================
-- 16. RLS -- narrow the four ticket-domain SELECT policies to exclude a
--     customer_user-layer actor entirely (decision 7), mirroring the
--     already-established ATW-023 hardening precedent
--     (20260730311000_harden_customer_inventory_access_rls_isolation.sql)
--     exactly. app.ticket_queues/app.ticket_categories/app.ticket_queue_
--     members already excluded customer_user in HRT-286's own original
--     migration -- unchanged here.
-- ===========================================================================

drop policy if exists tickets_select_scoped on app.tickets;
create policy tickets_select_scoped on app.tickets
  for select to authenticated
  using ((app.can_access_ticket(id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

drop policy if exists ticket_messages_select_scoped on app.ticket_messages;
create policy ticket_messages_select_scoped on app.ticket_messages
  for select to authenticated
  using ((app.can_access_ticket(ticket_id) and (visibility = 'public' or app.is_ticket_staff(ticket_id)) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

drop policy if exists ticket_watchers_select_scoped on app.ticket_watchers;
create policy ticket_watchers_select_scoped on app.ticket_watchers
  for select to authenticated
  using ((app.can_access_ticket(ticket_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

drop policy if exists ticket_events_select_scoped on app.ticket_events;
create policy ticket_events_select_scoped on app.ticket_events
  for select to authenticated
  using ((app.can_access_ticket(ticket_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

-- ===========================================================================
-- 17. Grants -- explicit, deliberate (never blanket), per
--     ERR-2026-004/PLT-118's standing convention.
-- ===========================================================================

revoke execute on all functions in schema app from public;

grant execute on function app.list_customer_accounts_for_actor(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_customer_ticket_categories(uuid, uuid) to authenticated, service_role;
grant execute on function app.get_customer_ticket(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_customer_tickets(uuid, uuid, uuid, text, integer, uuid) to authenticated, service_role;
grant execute on function app.list_customer_ticket_messages(uuid, uuid, integer, uuid) to authenticated, service_role;
