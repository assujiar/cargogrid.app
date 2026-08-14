-- Phase 7 (HRIS and Ticketing) capability CG-S12-HRT-020 (Typed
-- Ticket-Linked Records, Prompt 292). Builds on app.tickets/app.
-- can_access_ticket/app.is_ticket_staff/app._is_ticket_requester_party
-- (HRT-286/287/288), app.actor_holds_customer_user_layer (the RLS-hardening
-- migration, 20260730311000), app.resolve_customer_owner_account_scope/app.
-- customer_warehouse_eligibility_active (ATW-242, 20260730310000 -- the
-- closest existing precedent for exactly this problem: authorized-but-narrow
-- cross-domain visibility without duplicating the source's own ownership),
-- app.can_access_record (PLT-114), app.check_finance_invoice_authority
-- (FIN-197), app.evaluate_permission (PLT-112), and app.has_active_support_
-- grant (PLT-115) -- never a second ticket, RBAC, or support-grant
-- mechanism. Zero lines of any prior migration (<= 20260731160000) are
-- touched.
--
-- Design decisions, disclosed rather than left implicit:
--
-- 1. **A real entity-type registry, never a bare polymorphic (text, uuid)
--    pair with no referential/authorization backing.** app.ticket_links.
--    entity_type is CHECK-constrained to exactly six values (shipment,
--    invoice, warehouse, vendor, customer, user); app.ticket_link_entity_
--    types()/app.ticket_link_customer_safe_entity_types() are the SQL-level
--    registry mirror every RPC below validates against (kept set-equal with
--    the CHECK constraint by db-test, the same ATW-031 drift-gate
--    discipline app.generic_job_types()/jobs_job_type_check already uses).
--    app._ticket_link_resolve_candidate is the one per-type validation
--    adapter every read/write path dispatches through -- never re-derived
--    per call site. entity_id itself carries NO foreign key to any of the
--    six tables (they live in five different, already-applied migrations
--    this task may never edit, and a single column cannot FK-reference six
--    different tables) -- referential validity is instead PROVEN, every
--    time a link is created or a link's summary is read, by a live query
--    against the real source table (never trusted from a cached flag).
-- 2. **Canonical source domain owns the record; this migration stores
--    reference + a minimal, uniformly-shaped safe snapshot only.** Rather
--    than six differently-shaped per-type jsonb snapshot schemas, every
--    snapshot is the SAME bounded three-field shape --
--    {label, detail, status} -- populated per type from exactly the fields
--    the business rule names (shipment number + status; invoice number +
--    amount + status; warehouse/vendor/customer name; user display name)
--    and NOTHING else (C-07: never a full-row dump). This snapshot is
--    captured once, at link time, for history/offline reference ONLY --
--    every live read (list/search/summary) re-fetches and re-authorizes
--    fresh from the source table and NEVER falls back to the stored
--    snapshot's content when the fresh check fails (decision 6).
-- 3. **A link never grants access -- every read independently re-checks the
--    linked record's OWN domain authorization for the CURRENT caller, using
--    that domain's real, existing access predicate, never a new one
--    invented from scratch:**
--      - shipment (app.shipment_orders): app.can_access_record(...) with
--        the SAME owner_user_id/app.lead_record_scope_org_unit_ids(...)
--        arguments its own RLS policy uses, verbatim.
--      - invoice (app.finance_invoices): app.check_finance_invoice_
--        authority('View', ...), the SAME FIN:View gate app.get_finance_
--        invoice_lines/app.list_finance_invoices already require.
--      - warehouse (app.warehouses): app.can_access_record(...) with the
--        SAME app.lead_record_scope_org_unit_ids(company_org_unit_id)
--        argument its own RLS policy uses, verbatim.
--      - vendor (app.vendor_profiles): app.evaluate_permission(..., 'PRC',
--        'View'), the SAME gate app.get_vendor_profile/app.list_vendor_
--        profiles already require.
--      - customer (app.accounts): app.has_active_tenant_membership(...) AND
--        NOT app.actor_holds_customer_user_layer(...), the SAME gate its
--        own RLS policy uses, verbatim.
--      - user (app.users): app.has_active_tenant_membership(...) AND NOT
--        app.actor_holds_customer_user_layer(...), the SAME gate its own
--        RLS policy uses, verbatim.
--    Every one of the six is composed, never copy-edited into a new
--    authorization rule -- confirmed by direct inspection of each table's
--    own migration (RLS policy or RPC-layer gate) before writing its
--    adapter branch.
-- 4. **A genuinely new, narrow, ADDITIONAL customer-owner-scope branch is
--    composed onto three of the six adapters (shipment/invoice/warehouse)
--    for a customer_user caller -- disclosed as new capability, not merely
--    "reused."** Direct inspection (not assumed) found app.shipment_orders'
--    own RLS policy passes NULL for can_access_record's customer_account_
--    ref argument (so a customer_user actor is structurally denied ANY
--    shipment via raw RLS today) and app.finance_invoices' own RLS carries
--    no customer branch at all -- there is genuinely no existing customer-
--    facing read path for either table in this repository (grepped). Since
--    this prompt's own business rule explicitly expects a customer to see
--    their OWN account-scoped shipment/invoice/warehouse links (decision 7
--    below), this migration composes app.resolve_customer_owner_account_
--    scope (ATW-242, already-applied, not touched) against each table's OWN
--    existing owner-account column (shipment_orders.shipper_account_id,
--    finance_invoices.customer_account_id) as an OR-branch -- and for
--    warehouse, reuses app.customer_warehouse_eligibility_active (ATW-242)
--    verbatim, the exact existing "is this customer eligible for this
--    warehouse" predicate, rather than inventing a new one. This can ONLY
--    ever admit a genuine, active customer_user membership scoped to the
--    row's own owning account (resolve_customer_owner_account_scope always
--    returns an empty array for a non-customer_user actor -- ATW-242's own
--    established, re-verified guarantee) -- it never widens what an
--    INTERNAL actor could already see (C-08).
-- 5. **Helpdesk-channel access additionally requires a real, case-bound
--    presence in the target tenant -- app._ticket_link_actor_may_view_
--    tenant_data.** Staff status on a helpdesk ticket is Supreme-Admin-only
--    (HRT-288 decision 3), and app.evaluate_permission/app.can_access_
--    record/app.has_active_tenant_membership all structurally bypass EVERY
--    check for a Supreme Admin (confirmed by direct inspection of each).
--    Composing six domains' worth of read access through one new capability
--    would otherwise let ANY Supreme Admin browse ANY tenant's shipments,
--    invoices, vendors, accounts and users merely by opening a helpdesk
--    ticket into that tenant -- a genuinely NEW, broader exposure this
--    capability itself would introduce (C-08), not a pre-existing one this
--    migration merely inherits. This is closed, specifically for ticket
--    linking, by requiring the caller to ALSO hold one of: a real app.
--    tenant_user_identities membership in that tenant, a live app.support_
--    access_grants grant into that tenant (PLT-115, case-bound by
--    construction -- case_id is NOT NULL on that table), or an active
--    customer_user app.principal_memberships row in that tenant -- checked
--    BEFORE any per-type domain predicate runs, for every read/write path.
--    This does not, and cannot, touch the platform-wide Supreme Admin
--    bypass baked into evaluate_permission/can_access_record/has_active_
--    tenant_membership elsewhere (out of this migration's own file scope,
--    per AGENTS.md) -- it is a capability-specific, disclosed, additional
--    gate, live-tested (db-test section 8).
-- 6. **The persisted snapshot is NEVER used to answer "is this record
--    currently visible" -- only a live re-check is.** app._ticket_link_
--    resolve_candidate is the ONE function every read path (list/search/
--    summary) calls; when it returns no row (record hard-deleted, or the
--    CURRENT caller's access has since been revoked/expired/never held),
--    the caller is shown a single, undifferentiated `unavailable` status
--    with NO label/detail from the stored snapshot -- never the frozen
--    historical values, which would otherwise leak exactly the "record
--    still exists, here is what it looked like" signal to a caller who has
--    since lost the right to know that. This deliberately collapses
--    deleted/revoked/never-existed into ONE outward state (matches the
--    anti-enumeration discipline of decision 3 below, extended from
--    "candidate search" to "already-linked record read").
-- 7. **Customer (customer_user-layer) callers see a NARROWER entity-type
--    registry -- app.ticket_link_customer_safe_entity_types() -- shipment,
--    invoice, warehouse, customer. Never vendor or user.** No existing
--    customer-facing read path for app.vendor_profiles/app.users exists
--    anywhere in this repository (both structurally exclude customer_user
--    via `NOT app.actor_holds_customer_user_layer` in their own RLS), and
--    exposing either would leak internal supplier/staff-directory
--    structure to an external customer -- disclosed, deliberate, not
--    silently narrower than the task's own illustrative example. This is
--    gated on the ACTOR (app.actor_holds_customer_user_layer), never on the
--    ticket's channel column directly -- a customer_user is only ever able
--    to reach a customer-channel ticket in the first place (app.
--    can_access_ticket's own customer-admission branch), so the two are
--    equivalent in practice, but gating on the actor is the structurally
--    correct predicate (a helpdesk-channel ticket's own requester party is
--    a real tenant_admin/TKT:Edit-holding TENANT identity, not a
--    customer_user, and correctly gets the FULL registry).
-- 8. **Anti-enumeration (C-05), extended consistently across every new
--    surface.** app.search_ticket_link_candidates never returns a candidate
--    the caller is not independently authorized to see (excluded from the
--    result set entirely, never a distinguishable per-row denial).
--    app.link_ticket_record raises the IDENTICAL record_not_eligible
--    whether the target id genuinely does not exist, belongs to a
--    different tenant, was hard-deleted, or exists but fails the caller's
--    own independent domain check -- mirrors app.get_customer_inventory_
--    balance's own established anti-enumerating design (ATW-242) exactly.
--    A structurally invalid entity_type (not in the registry) or a
--    structurally forbidden entity_type for a customer caller both raise a
--    DIFFERENT, distinguishable error -- these are statements about a
--    RULE, not about a specific record's existence, and disclosing them is
--    safe (mirrors ATW-242's own "invalid_cursor" vs. "record_not_found"
--    distinction).
-- 9. **Denial durably audited without the same-transaction-rollback trap.**
--    A RAISE inside app.link_ticket_record/app.search_ticket_link_
--    candidates aborts the whole transaction, so an audit INSERT performed
--    moments earlier in the SAME call never survives (ATW-242's own
--    design note 9, empirically proven there, reused here rather than
--    rediscovered). app.search_ticket_link_candidates does not raise on a
--    tenant-data-view-gate failure (decision 5) -- it returns zero rows and
--    durably logs 'search_denied' inline (a normal, committing return, not
--    a rollback). app.link_ticket_record's own anti-enumerating RAISE
--    cannot self-log; app.record_ticket_link_access_denial (mirrors app.
--    record_customer_inventory_access_denial, ATW-242, verbatim) is a
--    genuinely separate RPC the TS service layer calls, in a NEW
--    transaction, after catching that error.
-- 10. **This capability's own append-only ledger, app.ticket_link_events,
--    IS the audit trail for link/unlink/access/denial -- never app.
--    audit_logs.** Mirrors app.ticket_escalation_events' own decision 15
--    (HRT-291) exactly: governed by the SAME RLS as the parent ticket
--    (staff-only raw-table read, customer_user excluded -- decision 11),
--    carrying the real reason/relationship/actor free text safely because
--    its readership never exceeds the ticket's own staff population. No
--    app.capture_audit_event call exists anywhere in this migration --
--    there is no separate "policy/config authoring" surface here the way
--    HRT-291 had (policy/level authoring) to justify one; link/unlink are
--    themselves the only mutations, and both are ticket-scoped exactly like
--    escalate/acknowledge/suppress, which HRT-291 also routed to its own
--    ledger only. Disclosed, not an oversight.
-- 11. **RLS is staff-only (customer_user excluded) on both new raw tables --
--    every genuine customer read goes through the SECURITY DEFINER RPCs
--    below, never a raw-table grant.** Mirrors app.ticket_watchers/app.
--    ticket_events/app.ticket_escalation_events' own established pattern
--    exactly (`app.can_access_ticket(ticket_id) AND NOT app.
--    actor_holds_customer_user_layer(tenant_id)`, `OR app.is_supreme_
--    admin()`) -- applied from the start, not discovered by a later
--    hardening migration.
-- 12. **Idempotency (C-01/C-02): a real partial unique index on the natural
--    key (ticket_id, entity_type, entity_id) WHERE status='active', backed
--    by a real `exception when unique_violation` handler in app.link_
--    ticket_record** -- not merely a pre-check SELECT (which cannot close
--    the race between two concurrent identical link attempts). A link that
--    was unlinked and re-linked later is intentionally a NEW row (fresh
--    id, fresh snapshot, fresh created_at) -- preserves the removed row's
--    own history rather than resurrecting it in place.
-- 13. **Locking discipline (C-04/C-21).** app.link_ticket_record locks app.
--    tickets first (naturally, since it starts from p_ticket_id). app.
--    unlink_ticket_record does NOT take p_ticket_id as a parameter (only
--    p_link_id) -- to preserve the SAME ticket-first lock order without
--    requiring the caller to already know the ticket id, it reads the
--    link's own ticket_id via a plain (unlocked) SELECT first, locks app.
--    tickets, THEN locks the app.ticket_links row -- mirrors app.revoke_
--    ticket_escalation_suppression's own documented reasoning (HRT-291
--    decision 14) for the identical shape.
-- 14. **Customer Portal expansion (Step 13) and AI-suggested related
--    records (Step 14) are out of scope, per the spec's own explicit
--    business rule -- not built, not stubbed.** app.ticket_links.source is
--    CHECK-constrained to ('manual', 'system') so a future automatic/system
--    linker has a real column to populate without a schema change, but
--    every RPC in this migration inserts 'manual' only -- no autonomous
--    linker of any kind exists or is invoked here.

-- ===========================================================================
-- 1. app.ticket_links -- the natural-key-unique link row (decisions 1/2/12).
-- ===========================================================================

create table app.ticket_links (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  ticket_id uuid not null references app.tickets (id),
  entity_type text not null,
  entity_id uuid not null,
  relationship text not null default 'related',
  source text not null default 'manual',
  status text not null default 'active',
  safe_snapshot jsonb not null,
  snapshot_captured_at timestamptz not null default now(),
  snapshot_schema_version integer not null default 1,
  removed_at timestamptz,
  removed_by text,
  removed_reason text,
  created_by_auth_user_id uuid not null,
  created_by text,
  record_version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint ticket_links_entity_type_check check (entity_type in ('shipment', 'invoice', 'warehouse', 'vendor', 'customer', 'user')),
  constraint ticket_links_relationship_check check (relationship in ('primary_subject', 'related', 'affected', 'context')),
  constraint ticket_links_source_check check (source in ('manual', 'system')),
  constraint ticket_links_status_check check (status in ('active', 'removed')),
  constraint ticket_links_removed_shape_check check ((status <> 'removed') or (removed_at is not null and removed_reason is not null)),
  constraint ticket_links_safe_snapshot_check check (jsonb_typeof(safe_snapshot) = 'object')
);

comment on table app.ticket_links is
  'HRT-292 (decisions 1/2/12): typed ticket-to-canonical-record reference. entity_type is a CHECK-constrained enum (the registry, decision 1) -- entity_id carries NO foreign key (cannot, across six different source tables in five different migrations) and is instead re-validated live on every write/read via app._ticket_link_resolve_candidate. safe_snapshot is the UNIFORM {label, detail, status} shape (decision 2), captured once at link time for history only -- every live read re-fetches fresh (decision 6), never trusting this column as currently authoritative.';

create unique index ticket_links_active_unique on app.ticket_links (ticket_id, entity_type, entity_id) where status = 'active';
create index ticket_links_tenant_ticket_idx on app.ticket_links (tenant_id, ticket_id, status);
create index ticket_links_entity_idx on app.ticket_links (tenant_id, entity_type, entity_id);

create trigger ticket_links_touch before update on app.ticket_links
  for each row execute function app.touch_ticket_row();

-- ===========================================================================
-- 2. app.ticket_link_events -- append-only ledger (decisions 9/10).
-- ===========================================================================

create table app.ticket_link_events (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  ticket_id uuid not null references app.tickets (id),
  link_id uuid references app.ticket_links (id),
  entity_type text,
  entity_id uuid,
  relationship text,
  event_type text not null,
  reason text,
  actor_auth_user_id uuid,
  actor_label text,
  occurred_at timestamptz not null default now(),
  constraint ticket_link_events_entity_type_check check (entity_type is null or entity_type in ('shipment', 'invoice', 'warehouse', 'vendor', 'customer', 'user')),
  constraint ticket_link_events_event_type_check check (event_type in (
    'linked', 'unlinked', 'link_denied', 'search_denied', 'summary_accessed', 'deep_link_accessed'
  ))
);

comment on table app.ticket_link_events is
  'HRT-292 (decisions 9/10/11): the append-only compliance ledger -- the ONLY authoritative source of link history/access/denial. Governed by the SAME RLS as the parent ticket (app.can_access_ticket), staff-only (decision 11), never app.audit_logs (decision 10), mirroring app.ticket_escalation_events (HRT-291) exactly.';

create index ticket_link_events_ticket_idx on app.ticket_link_events (ticket_id, occurred_at asc);
create index ticket_link_events_tenant_type_idx on app.ticket_link_events (tenant_id, event_type);

-- ===========================================================================
-- 3. Registry + tenant-data-view gate (decisions 1/5/7).
-- ===========================================================================

create function app.ticket_link_entity_types()
returns text[]
language sql
immutable
set search_path = app, pg_temp
as $$
  select array['shipment', 'invoice', 'warehouse', 'vendor', 'customer', 'user']::text[];
$$;

comment on function app.ticket_link_entity_types is
  'HRT-292 (decision 1): the full registry, kept set-equal with app.ticket_links_entity_type_check by db-test (the same ATW-031 drift-gate discipline app.generic_job_types() uses).';

create function app.ticket_link_customer_safe_entity_types()
returns text[]
language sql
immutable
set search_path = app, pg_temp
as $$
  select array['shipment', 'invoice', 'warehouse', 'customer']::text[];
$$;

comment on function app.ticket_link_customer_safe_entity_types is
  'HRT-292 (decision 7): the subset of the registry a customer_user-layer caller may search/link/see -- never vendor or user (no existing customer-facing read path for either exists anywhere in this repository).';

create function app._ticket_link_actor_may_view_tenant_data(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = app, pg_temp
as $$
  select
    exists (
      select 1 from app.tenant_user_identities t
      where t.tenant_id = p_tenant_id and t.auth_user_id = p_actor_auth_user_id and t.status = 'active'
    )
    or app.has_active_support_grant(p_tenant_id, p_actor_auth_user_id)
    or exists (
      select 1 from app.principal_memberships pm
      where pm.auth_user_id = p_actor_auth_user_id and pm.tenant_id = p_tenant_id and pm.layer = 'customer_user' and pm.status = 'active'
    );
$$;

comment on function app._ticket_link_actor_may_view_tenant_data is
  'HRT-292 (decision 5): a real, case-bound presence in the target tenant -- a genuine app.tenant_user_identities membership, a LIVE app.support_access_grants grant (PLT-115, case-bound by construction), or an active customer_user membership. Deliberately composed from primitives rather than app.has_active_tenant_membership() directly -- that function''s own is_supreme_admin() OR-branch would otherwise let a Supreme Admin bypass this gate entirely, exactly the C-08 widening decision 5 exists to close.';

grant execute on function app._ticket_link_actor_may_view_tenant_data(uuid, uuid) to service_role;

-- ===========================================================================
-- 4. app._ticket_link_resolve_candidate -- the ONE per-type validation
--    adapter every read/write path dispatches through (decisions 1/3/4/6).
-- ===========================================================================

create function app._ticket_link_resolve_candidate(p_entity_type text, p_tenant_id uuid, p_actor_auth_user_id uuid, p_entity_id uuid)
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
        or fi.customer_account_id = any (app.resolve_customer_owner_account_scope(p_actor_auth_user_id, fi.tenant_id))
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
  'HRT-292 (decisions 1/3/4/6): returns AT MOST one row -- found iff the record exists, is tenant-scoped, AND the CURRENT caller independently passes that domain''s own real access predicate (decision 3, plus the composed customer-owner-scope branch of decision 4 for shipment/invoice/warehouse). No row is the SAME outward signal whether the id is forged, cross-tenant, deleted, or merely unauthorized for this caller (C-05) -- every caller (search/link/list/summary) treats "no row" identically, never distinguishing which.';

grant execute on function app._ticket_link_resolve_candidate(text, uuid, uuid, uuid) to service_role;

-- ===========================================================================
-- 5. app.search_ticket_link_candidates -- bounded, per-type, anti-
--    enumerating, principal-scoped (decisions 5/7/8/9).
-- ===========================================================================

create function app.search_ticket_link_candidates(
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
        or fi.customer_account_id = any (app.resolve_customer_owner_account_scope(p_actor_auth_user_id, fi.tenant_id))
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
  'HRT-292 (decisions 5/7/8/9): bounded (default 20, capped 50) candidate search -- every row is independently authorized for THIS caller in the WHERE clause itself (never post-filtered), so an unauthorized candidate is never returned, never even as an empty placeholder (C-05). A tenant-data-view-gate failure (decision 5) returns zero rows AND durably logs search_denied inline (no RAISE, so the log survives -- decision 9).';

-- ===========================================================================
-- 6. app.link_ticket_record (decisions 3/4/7/8/12/13).
-- ===========================================================================

create function app.link_ticket_record(
  p_ticket_id uuid,
  p_entity_type text,
  p_entity_id uuid,
  p_relationship text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.ticket_links
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_ticket app.tickets;
  v_is_staff boolean;
  v_is_requester boolean;
  v_relationship text;
  v_existing app.ticket_links;
  v_candidate record;
  v_snapshot jsonb;
  v_row app.ticket_links;
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

  if not (p_entity_type = any (app.ticket_link_entity_types())) then
    raise exception 'unsupported_entity_type: % is not a supported ticket link entity type', p_entity_type using errcode = 'check_violation';
  end if;

  if app.actor_holds_customer_user_layer(v_ticket.tenant_id, p_actor_auth_user_id) and not (p_entity_type = any (app.ticket_link_customer_safe_entity_types())) then
    raise exception 'entity_type_not_permitted: % is not a customer-permitted link type', p_entity_type using errcode = 'insufficient_privilege';
  end if;

  v_relationship := coalesce(p_relationship, 'related');
  if not (v_relationship = any (array['primary_subject', 'related', 'affected', 'context'])) then
    raise exception 'invalid_relationship: % is not a recognized link relationship', p_relationship using errcode = 'check_violation';
  end if;

  -- Anti-enumeration (decisions 3/4/8): existence, tenant scope, and this
  -- caller's OWN independent domain authorization collapse into ONE
  -- outcome here -- a forged id, a cross-tenant id, a deleted record, and
  -- an unauthorized-but-real candidate are all indistinguishable.
  --
  -- Deliberately runs BEFORE the duplicate-policy short-circuit below (a
  -- self-found ordering defect, live-caught by this migration's own
  -- db-test, not by review): an EARLIER draft checked for an existing
  -- active link FIRST and returned it unconditionally on a match, which
  -- would let caller B silently receive (and read the safe_snapshot of)
  -- a record caller A already linked, even when B has NO independent
  -- domain authorization of their own -- exactly the "a link grants
  -- access" violation this capability''s own business rule forbids. Every
  -- link_ticket_record call, including a fully idempotent replay, now
  -- re-proves the CURRENT caller''s own eligibility every time.
  select * into v_candidate from app._ticket_link_resolve_candidate(p_entity_type, v_ticket.tenant_id, p_actor_auth_user_id, p_entity_id);
  if not found then
    raise exception 'record_not_eligible: no eligible % record exists for %', p_entity_type, p_entity_id using errcode = 'no_data_found';
  end if;

  -- Duplicate policy (decision 12): an already-active link for the
  -- identical natural key is a clean, idempotent no-op return -- never a
  -- duplicate row, never an error -- but ONLY once the caller''s own
  -- eligibility (immediately above) has already been proven.
  select * into v_existing from app.ticket_links where ticket_id = p_ticket_id and entity_type = p_entity_type and entity_id = p_entity_id and status = 'active';
  if found then
    return v_existing;
  end if;

  v_snapshot := jsonb_build_object('label', v_candidate.primary_label, 'detail', v_candidate.secondary_label, 'status', v_candidate.status_label);

  begin
    insert into app.ticket_links (
      tenant_id, ticket_id, entity_type, entity_id, relationship, source, status,
      safe_snapshot, snapshot_captured_at, created_by_auth_user_id, created_by
    ) values (
      v_ticket.tenant_id, p_ticket_id, p_entity_type, p_entity_id, v_relationship, 'manual', 'active',
      v_snapshot, now(), p_actor_auth_user_id, p_actor_label
    )
    returning * into v_row;
  exception
    when unique_violation then
      select * into v_row from app.ticket_links where ticket_id = p_ticket_id and entity_type = p_entity_type and entity_id = p_entity_id and status = 'active';
      if not found then
        raise;
      end if;
      return v_row;
  end;

  insert into app.ticket_link_events (tenant_id, ticket_id, link_id, entity_type, entity_id, relationship, event_type, actor_auth_user_id, actor_label)
  values (v_ticket.tenant_id, p_ticket_id, v_row.id, p_entity_type, p_entity_id, v_relationship, 'linked', p_actor_auth_user_id, p_actor_label);

  return v_row;
end;
$$;

comment on function app.link_ticket_record is
  'HRT-292: link authority mirrors app.add_ticket_watcher exactly (decision: staff OR requester-side party, never a plain watcher) -- is_ticket_staff OR app._is_ticket_requester_party. Idempotent on the (ticket_id, entity_type, entity_id) natural key (decision 12, real partial unique index + exception handler). Anti-enumerating record_not_eligible (decision 8) on any invalid/unauthorized candidate -- the caller cannot distinguish forged/cross-tenant/deleted/unauthorized.';

-- ===========================================================================
-- 7. app.unlink_ticket_record (decisions 12/13).
-- ===========================================================================

create function app.unlink_ticket_record(p_link_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.ticket_links
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_ticket_id uuid;
  v_ticket app.tickets;
  v_row app.ticket_links;
  v_is_staff boolean;
  v_is_requester boolean;
  v_updated app.ticket_links;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  -- Ticket-first lock order (decision 13, C-04/C-21): a plain, unlocked read
  -- to discover the owning ticket, THEN lock app.tickets, THEN lock this
  -- row -- mirrors app.revoke_ticket_escalation_suppression's own
  -- documented reasoning (HRT-291 decision 14) for the identical shape.
  select ticket_id into v_ticket_id from app.ticket_links where id = p_link_id;
  if not found then
    raise exception 'ticket_link_not_found: %', p_link_id using errcode = 'no_data_found';
  end if;

  select * into v_ticket from app.tickets where id = v_ticket_id for update;
  if not found then
    raise exception 'ticket_link_not_found: %', p_link_id using errcode = 'no_data_found';
  end if;

  select * into v_row from app.ticket_links where id = p_link_id for update;
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

  update app.ticket_links
  set status = 'removed', removed_at = now(), removed_by = p_actor_label, removed_reason = p_reason
  where id = p_link_id and record_version = p_expected_version
  returning * into v_updated;
  if not found then
    raise exception 'stale_version: concurrent update detected for link %', p_link_id using errcode = 'serialization_failure';
  end if;

  insert into app.ticket_link_events (tenant_id, ticket_id, link_id, entity_type, entity_id, relationship, event_type, reason, actor_auth_user_id, actor_label)
  values (v_updated.tenant_id, v_updated.ticket_id, v_updated.id, v_updated.entity_type, v_updated.entity_id, v_updated.relationship, 'unlinked', p_reason, p_actor_auth_user_id, p_actor_label);

  return v_updated;
end;
$$;

comment on function app.unlink_ticket_record is
  'HRT-292 (decision 13): ticket-first lock order, preserved without requiring the caller to already know the ticket id. Reason is mandatory (business rule "record link/unlink source/reason"). Removing a link never deletes the row -- status=removed, a real removed_at/removed_by/removed_reason, so the ledger and the row itself both keep full history.';

-- ===========================================================================
-- 8. app.list_ticket_links -- batched, principal-fresh safe summaries
--    (decisions 2/6).
-- ===========================================================================

create function app.list_ticket_links(p_ticket_id uuid, p_actor_auth_user_id uuid)
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
  -- Table-qualified (t.id, not bare id) -- app.list_ticket_links' own
  -- RETURNS TABLE declares an OUT parameter also named "id", which would
  -- otherwise shadow app.tickets.id and raise a genuine "ambiguous column"
  -- compile error (caught live against a real Postgres, not by inspection
  -- alone).
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
  from app.ticket_links l
  left join lateral app._ticket_link_resolve_candidate(l.entity_type, v_ticket.tenant_id, p_actor_auth_user_id, l.entity_id) c on true
  where l.ticket_id = p_ticket_id and l.status = 'active'
  order by l.created_at asc;
end;
$$;

comment on function app.list_ticket_links is
  'HRT-292 (decisions 2/6): batched (one lateral join, no per-row N+1 round trip), principal-fresh -- every row''s label/detail/status_label is a LIVE re-check for the CURRENT caller, never the stored safe_snapshot. live_available=false (deleted OR revoked OR never-eligible -- deliberately undifferentiated, decision 6) shows NO label/detail at all, only the generic status_label="unavailable" -- the stored snapshot is never surfaced as a fallback, which would otherwise leak stale content past a caller who has since lost access.';

-- ===========================================================================
-- 9. Denial/access audit companions (decision 9), mirrors app.record_
--    customer_inventory_access_denial (ATW-242) exactly.
-- ===========================================================================

create function app.record_ticket_link_access_denial(
  p_tenant_id uuid, p_ticket_id uuid, p_actor_auth_user_id uuid, p_actor_label text,
  p_entity_type text, p_entity_id uuid, p_reason text
)
returns void
language plpgsql
security definer
set search_path = app, pg_temp
as $$
begin
  -- Two self-found gaps (both caught live by the repository''s own standing
  -- rbac-enforcement.sql sweeps, ATW-032/ISS-2026-033 and ISS-2026-032 --
  -- not by this migration''s own review) on an EARLIER draft that omitted
  -- both checks below:
  --  1. Without assert_session_identity_in_tenant, any authenticated
  --     identity with NO standing whatsoever in p_tenant_id could inject a
  --     fabricated ledger row into an UNRELATED tenant''s ticket_link_events
  --     merely by passing its id as p_tenant_id/p_ticket_id. Mirrors app.
  --     record_customer_inventory_access_denial''s own identical,
  --     already-reviewed fix (ATW-242) verbatim.
  --  2. Separately (C-13, ISS-2026-032): this function takes
  --     p_actor_auth_user_id, which the standing sweep treats as a claim to
  --     ACT AS that identity regardless of what a caller-side comment says
  --     -- assert_session_identity_in_tenant alone proves the session has
  --     tenant standing, never that p_actor_auth_user_id is the caller''s
  --     own id, so a tenant member could still attribute a denial ledger
  --     row to a DIFFERENT colleague''s identity. assert_actor_is_session_
  --     identity closes that distinct gap, exactly the same guard every
  --     other client-callable function in this migration already opens
  --     with.
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  perform app.assert_session_identity_in_tenant(p_tenant_id);

  insert into app.ticket_link_events (tenant_id, ticket_id, entity_type, entity_id, event_type, reason, actor_auth_user_id, actor_label)
  values (p_tenant_id, p_ticket_id, p_entity_type, p_entity_id, 'link_denied', coalesce(p_reason, 'denied'), p_actor_auth_user_id, p_actor_label);
end;
$$;

comment on function app.record_ticket_link_access_denial is
  'HRT-292 (decision 9): a genuinely separate RPC, called by the TS service layer in a NEW transaction after catching app.link_ticket_record''s own anti-enumerating record_not_eligible/entity_type_not_permitted -- a RAISE inside that function aborts its own transaction, so it cannot durably self-log (ATW-242''s own design note 9, reused verbatim). Always succeeds identically regardless of the real denial cause, so it introduces no enumeration surface of its own. Gated by app.assert_session_identity_in_tenant (ATW-032 self-found fix, mirrors app.record_customer_inventory_access_denial verbatim) so an unrelated tenant''s member cannot inject a fabricated ledger row.';

create function app.record_ticket_link_summary_access(
  p_link_id uuid, p_actor_auth_user_id uuid, p_actor_label text, p_access_type text
)
returns void
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_link app.ticket_links;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_link from app.ticket_links where id = p_link_id;
  if not found or not app.can_access_ticket(v_link.ticket_id, p_actor_auth_user_id) then
    raise exception 'ticket_link_not_found: %', p_link_id using errcode = 'no_data_found';
  end if;
  if not (p_access_type = any (array['summary_viewed', 'deep_link_opened'])) then
    raise exception 'invalid_access_type: %', p_access_type using errcode = 'check_violation';
  end if;

  insert into app.ticket_link_events (tenant_id, ticket_id, link_id, entity_type, entity_id, relationship, event_type, actor_auth_user_id, actor_label)
  values (
    v_link.tenant_id, v_link.ticket_id, v_link.id, v_link.entity_type, v_link.entity_id, v_link.relationship,
    case p_access_type when 'deep_link_opened' then 'deep_link_accessed' else 'summary_accessed' end,
    p_actor_auth_user_id, p_actor_label
  );
end;
$$;

comment on function app.record_ticket_link_summary_access is
  'HRT-292 (audit impact "safe-summary/deep-link access... audited"): an explicit, caller-invoked event -- fired when a viewer actually expands a summary card or follows a deep link, never on every list render (which would spam the ledger on each page view with no signal). Re-validates ticket+link access before logging (so this cannot become its own enumeration probe).';

-- ===========================================================================
-- 10. app.list_ticket_link_events -- staff-only ledger reader, cursor-
--     paginated.
-- ===========================================================================

create function app.list_ticket_link_events(
  p_ticket_id uuid, p_actor_auth_user_id uuid,
  p_cursor_occurred_at timestamptz default null, p_cursor_id uuid default null, p_limit integer default 50
)
returns table (
  id uuid, entity_type text, entity_id uuid, relationship text, event_type text, reason text,
  actor_auth_user_id uuid, actor_label text, occurred_at timestamptz
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_limit integer;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if not app.can_access_ticket(p_ticket_id, p_actor_auth_user_id) or not app.is_ticket_staff(p_ticket_id, p_actor_auth_user_id) then
    raise exception 'ticket_not_found: %', p_ticket_id using errcode = 'no_data_found';
  end if;
  if p_cursor_id is not null and p_cursor_occurred_at is null then
    raise exception 'invalid_cursor: p_cursor_occurred_at is required when p_cursor_id is supplied' using errcode = 'invalid_parameter_value';
  end if;
  v_limit := least(greatest(coalesce(p_limit, 50), 1), 200);

  return query
  select e.id, e.entity_type, e.entity_id, e.relationship, e.event_type, e.reason, e.actor_auth_user_id, e.actor_label, e.occurred_at
  from app.ticket_link_events e
  where e.ticket_id = p_ticket_id
    and (p_cursor_id is null or (e.occurred_at, e.id) < (p_cursor_occurred_at, p_cursor_id))
  order by e.occurred_at desc, e.id desc
  limit v_limit;
end;
$$;

comment on function app.list_ticket_link_events is
  'HRT-292: staff-only (is_ticket_staff), cursor-paginated (occurred_at, id) desc, never OFFSET -- mirrors app.list_ticket_escalation_events'' own cursor shape.';

-- ===========================================================================
-- 11. RLS (decision 11) + grants (ERR-2026-004).
-- ===========================================================================

alter table app.ticket_links enable row level security;
alter table app.ticket_link_events enable row level security;

create policy ticket_links_select_scoped on app.ticket_links
  for select to authenticated
  using ((app.can_access_ticket(ticket_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy ticket_link_events_select_scoped on app.ticket_link_events
  for select to authenticated
  using ((app.can_access_ticket(ticket_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

revoke execute on all functions in schema app from public;

grant select on app.ticket_links, app.ticket_link_events to authenticated, service_role;
grant insert, update, delete on app.ticket_links, app.ticket_link_events to service_role;

grant execute on function app.ticket_link_entity_types() to authenticated, service_role;
grant execute on function app.ticket_link_customer_safe_entity_types() to authenticated, service_role;
grant execute on function app.search_ticket_link_candidates(uuid, text, text, uuid, integer) to authenticated, service_role;
grant execute on function app.link_ticket_record(uuid, text, uuid, text, uuid, text) to authenticated, service_role;
grant execute on function app.unlink_ticket_record(uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.list_ticket_links(uuid, uuid) to authenticated, service_role;
grant execute on function app.record_ticket_link_access_denial(uuid, uuid, uuid, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.record_ticket_link_summary_access(uuid, uuid, text, text) to authenticated, service_role;
grant execute on function app.list_ticket_link_events(uuid, uuid, timestamptz, uuid, integer) to authenticated, service_role;
