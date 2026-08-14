-- Phase 7 (HRIS and Ticketing) capability CG-S12-HRT-016 (Tenant-to-CargoGrid
-- Helpdesk, Prompt 288) -- the THIRD and LAST founding channel of the Ticket
-- workstream, extending HRT-286/287's canonical ticket model with a genuinely
-- new principal shape: a TENANT itself (not a specific employee, not a
-- customer account) as requester, and CargoGrid Platform support as staff.
-- This migration is this prompt's own chartered resolution of the SECOND,
-- still-open half of ISS-2026-085 (docs/runtime/KNOWN_ISSUES.md) -- the
-- Prompt-287/customer half was already resolved at CG-S12-HRT-015 using the
-- identical generalized-dispatch shape this migration now extends with a
-- THIRD branch, never a fourth mechanism. Additive/expand-and-contract only
-- -- 20260731060000/070000/080000/090000 are NOT edited in place, per
-- AGENTS.md.
--
-- MANDATORY reading this migration is built against and does not repeat:
-- 288_CARGOGRID_HELPDESK_PROMPT.md; ISS-2026-085's full entry including its
-- HRT-287 Tier C batch review addendum; HRT-286.md's own foundation-quality
-- observation ("app.ticket_queues is tenant_id + org_unit_id scoped ... this
-- shape cannot represent 'Platform support queue/team' ... Prompt 288 will
-- need a parallel queue concept, not a widened app.ticket_queues row");
-- supabase/migrations/20260716111315_create_support_access.sql (PLT-115,
-- the pre-existing support-access/impersonation mechanism this migration
-- correlates with but NEVER rebuilds, bypasses, or extends access through).
--
-- Design decisions, disclosed (mirrors HRT-286/287's own discipline exactly):
--
-- 1. **No second ticket table, no second ticket service, no fourth access
--    layer.** Every table this migration touches is one of HRT-286's own
--    eight (plus one genuinely NEW, Platform-wide catalog table, decision 2
--    below). The helpdesk channel is represented by widening
--    `app.tickets.channel`'s CHECK to add `'helpdesk'`, and by a THIRD
--    branch on the SAME two structural-scope helpers HRT-287 already
--    generalized: `app._is_ticket_requester_party` (which channel-appropriate
--    party is the "requester side" for this ticket) and `app.is_ticket_staff`
--    (who counts as "staff" -- i.e. may read internal notes and act with
--    elevated authority). Business rule (Prompt 288 section 24), reiterated
--    because it is the single most important constraint on this whole
--    migration: "Helpdesk is a canonical ticket channel; it does NOT make
--    CargoGrid support a tenant user or create a fifth access layer" and "A
--    support ticket ALONE grants no tenant data access; privileged access
--    uses SEPARATE Platform support/impersonation controls." Nothing in this
--    migration reads, writes, extends, shortens, or bypasses
--    `app.support_access_grants`/`app.support_access_sessions` (PLT-115) in
--    any way other than a single, explicit, read-only, DISPLAY-ONLY
--    correlation column validated against that table's own `case_id`
--    (decision 7) -- proven, not merely asserted, by dedicated adversarial
--    tests in `scripts/db-tests/ticketing-helpdesk.sql`.
--
-- 2. **The Platform-support-queue design decision (HRT-286's own diagnosed
--    gap) -- a genuinely parallel, Platform-wide catalog, never a widened
--    `app.ticket_queues` row.** `app.support_queues` is a NEW table with NO
--    `tenant_id` and NO `org_unit_id` -- CargoGrid support is not an org
--    unit of any customer's tenant, and `app.ticket_queues`'s own
--    `tenant_id`+`org_unit_id`-both-required shape structurally cannot
--    represent it (HRT-286.md's own diagnosis, confirmed correct here, not
--    rediscovered). `app.tickets.support_queue_id` (new, nullable) is the
--    helpdesk-channel counterpart to `queue_id` (now relaxed to nullable, a
--    structural CHECK -- `tickets_queue_shape` -- enforces exactly one of
--    `queue_id`/`support_queue_id` populated, matching channel, the same
--    "structural shape CHECK" discipline `tickets_requester_identity_shape`
--    already established). `support_queue_id` is a pure ROUTING/TRIAGE label
--    (e.g. "Billing", "Platform Ops") -- it deliberately does NOT double as
--    an access-granting roster (decision 3 explains why).
--
-- 3. **The Platform-support-staff-role decision: Supreme-Admin-authority
--    actors ONLY, a deliberate, disclosed, bounded-scope choice -- not a
--    rediscovery, a decision.** Per this prompt's own mandatory reading
--    (`app.is_supreme_admin`, PLT-108/PLT-113): "There is currently no
--    dedicated 'Platform Support Team' role distinct from Supreme Admin."
--    `app.principal_memberships`'s four layers (`supreme_admin`/
--    `tenant_admin`/`org_user`/`customer_user`) are DELIBERATELY closed
--    (that migration's own header) -- inventing a fifth, global,
--    non-tenant-scoped layer for "Platform Support Staff" here would be
--    real, unreviewed identity-model surgery on a foundation table three
--    unrelated capabilities already depend on, wildly out of this single
--    prompt's own bounded scope, and exactly the kind of "invent a fourth
--    mechanism" this migration's own charter forbids. Instead: `app.
--    is_ticket_staff` is hardened so that, for a `channel = 'helpdesk'`
--    ticket SPECIFICALLY, staff status is `app.is_supreme_admin(actor)` and
--    NOTHING else -- explicitly EXCLUDING the tenant-wide `TKT:Edit`
--    fallback, queue-membership fallback, and assignee-employee fallback
--    that legitimately apply to internal/customer tickets. Without this
--    explicit exclusion, a TENANT's own `TKT:Edit` holder (a real, tenant-
--    scoped permission, unrelated to CargoGrid Platform support) would
--    otherwise satisfy `is_ticket_staff` on a HELPDESK ticket belonging to
--    their own tenant -- letting a tenant read Platform-internal notes on
--    their own governed support case, the single most direct violation of
--    this prompt's own "internal notes remain hidden from tenant
--    projections" business rule this migration could ship. `app.
--    support_queues`/`support_queue_id` are therefore pure metadata, never
--    membership -- disclosed, bounded LIMITATION: this prompt does not
--    build a narrower, non-Supreme-Admin "support agent" role; a future
--    prompt wanting one should add it as its OWN deliberate principal-layer
--    or grant-table decision, never inferred from this migration's queue
--    catalog.
--
-- 4. **Tenant-requester identity: `app.principal_memberships`/`app.
--    has_active_tenant_membership`-based, deliberately employee-INDEPENDENT
--    -- per this prompt's own explicit instruction, NOT HRT-274's employee
--    model.** A tenant must be able to file a Platform support case
--    regardless of HR-track onboarding state (a brand-new tenant with zero
--    `app.employees` rows must still be able to ask CargoGrid for help). The
--    new `app._is_tenant_helpdesk_authorized(tenant_id, auth_user_id)`
--    helper answers "is this identity a real, tenant-scoped `tenant_admin`,
--    or a tenant-scoped role-holder of `TKT:Edit`" via a DIRECT query
--    against `app.principal_memberships`/`app.role_assignments` -- never via
--    `app.get_self_employee` (no `app.employees` row required) and, just as
--    importantly, NEVER via `app.check_ticket_authority`/`app.
--    evaluate_permission` (whose RPD-022 Supreme-Admin bypass would
--    otherwise make a Platform Supreme Admin ALSO satisfy "is the tenant-
--    side requester party," conflating the two sides of the exact boundary
--    this migration exists to keep separate -- found and fixed during this
--    migration's own design, live-adversarially confirmed in
--    `scripts/db-tests/ticketing-helpdesk.sql`, see decision 3's own "no
--    fifth layer" note and the db-test's own dedicated assertion group).
--
-- 5. **A real, structural tenant-visible-vs-Platform-internal distinction --
--    the SAME `ticket_messages.visibility`/`is_ticket_staff` mechanism
--    HRT-286 already built, reused verbatim, never re-derived.** No new
--    visibility column, no new message table. `app.reply_to_helpdesk_ticket`
--    (tenant-side entry point) is a thin defense-in-depth wrapper mirroring
--    `app.reply_to_customer_ticket` exactly -- hardcodes `visibility :=
--    'public'` at the SQL call site and independently re-verifies
--    `channel = 'helpdesk'`. Platform staff (Supreme Admin) posts internal
--    notes through the EXISTING, unmodified `app.reply_to_ticket` directly
--    (mirroring how internal-channel staff already do), which already,
--    correctly, gates `visibility = 'internal'` on `is_ticket_staff` --
--    hardened by decision 3 to mean Supreme-Admin-only for this channel.
--
-- 6. **Redaction and the three existing generic staff-lifecycle RPCs
--    (`assign_ticket`/`transfer_ticket_queue`/`update_ticket_classification`)
--    explicitly REJECT a helpdesk-channel ticket rather than silently
--    misbehaving.** Those three RPCs validate against `app.employees`/
--    `app.ticket_queues`/`app.ticket_queue_members`, none of which apply to
--    a helpdesk ticket's Platform-side staffing model -- left unguarded, a
--    TENANT's own `TKT:Assign`/tenant-scoped authority could otherwise call
--    them against their own tenant's helpdesk ticket (structurally
--    meaningless at best, a real authority-boundary violation at worst; see
--    `redact_ticket_message`'s own pre-existing lack of an `is_ticket_staff`
--    gate, which THIS migration closes for the helpdesk channel
--    specifically -- a tenant's `TKT:Edit` must never be able to DESTROY a
--    Platform-internal note it cannot even read). Dedicated, Supreme-Admin-
--    gated siblings (`assign_helpdesk_ticket`/
--    `transfer_helpdesk_support_queue`/`update_helpdesk_ticket_classification`)
--    exist instead -- never a shared RPC silently branching on channel with
--    two different authority models glued together.
--
-- 7. **Support-session correlation is DISPLAY/AUDIT ONLY, provably never an
--    access shortcut.** `app.tickets.support_access_case_ref` (new, nullable
--    text) may be set ONLY by `app.link_helpdesk_support_grant`
--    (Supreme-Admin-gated), which validates a REAL
--    `app.support_access_grants` row exists for
--    `(tenant_id, case_id = the given ref)` before accepting it (typo/
--    forgery defense -- not required to be an ACTIVE grant, since displaying
--    a past/expired/revoked case's correlation is legitimate history, never
--    itself a live grant). NO function in this migration reads
--    `app.support_access_grants`/`app.support_access_sessions` for any
--    purpose OTHER than this one read-only, LEFT-JOINed display in
--    `app.get_platform_helpdesk_ticket` (grant status/expiry/revocation
--    shown for triage convenience) -- and NO function in this migration or
--    anywhere else grants, extends, revokes, or otherwise mutates a support
--    access grant. The existing, UNMODIFIED PLT-115 flow
--    (`app.request_support_access`/`app.approve_support_access`/
--    `app.start_support_session`/...) remains the ONLY path to actual
--    tenant business-data access -- live-adversarially proven in
--    `scripts/db-tests/ticketing-helpdesk.sql`: an expired/revoked grant's
--    `case_id` still correlates for DISPLAY, but confers zero access;
--    linking/unlinking a correlation ref never creates, approves, starts,
--    or extends a grant or session.
--
-- 8. **Diagnostic attachments reuse PLT-128 verbatim -- no second scanner,
--    no new document type.** `app.reply_to_ticket`'s existing
--    `p_attachment_file_ids`/malware-scan-gating logic (`document_type_code
--    = 'ticket_attachment'`, `record_type = 'ticket'`) is already
--    channel-agnostic (keyed on the ticket id, not the channel) -- both
--    `app.reply_to_helpdesk_ticket` (tenant side) and direct `app.
--    reply_to_ticket` calls (Platform staff side) inherit it unchanged.
--    "Redacted diagnostic attachment handling" is the SAME `app.
--    redact_ticket_message` mechanism HRT-286 built, now additionally
--    hardened (decision 6) so a tenant's own `TKT:Edit` can never redact
--    Platform-internal content on a helpdesk case.
--
-- 9. **Severity/product-area/environment/reference metadata are generic,
--    nullable columns on `app.tickets`** (not a channel-restricted CHECK,
--    since a future prompt may find them useful elsewhere) -- populated by
--    `app.create_helpdesk_ticket`/`app.update_helpdesk_ticket_classification`
--    only; left `null` for internal/customer tickets, disclosed as an
--    honestly-unused-elsewhere-today column set, matching HRT-286's own
--    "a column no code populates is worse than an honestly absent one"
--    discipline applied here in the opposite direction (the column exists
--    AND is populated, just only by one channel's own entry points today).
--
-- 10. **`cancelled_reason_authored_by_customer`/
--     `last_reopen_reason_authored_by_customer`** (added at the HRT-287
--     Tier C batch review, `20260731090000`) are REUSED, not duplicated,
--     for the helpdesk channel -- `app.transition_ticket_status`'s existing
--     gating (`v_actor_is_requester and v_ticket.channel = 'customer'`) is
--     widened to `v_ticket.channel in ('customer', 'helpdesk')`. The column
--     NAMES still say "customer" (renaming an already-`VERIFIED` column
--     would be unwarranted churn for a single prompt) -- disclosed via a
--     fresh `comment on column` clarifying the now-generalized meaning
--     ("authored by the ticket's own requester-side party, per channel").
--     `app.get_tenant_helpdesk_ticket` reads the SAME two columns with the
--     SAME "only echo back if the requester themself authored it" discipline
--     `app.get_customer_ticket` already established, never `resolution_
--     summary` (always staff-authored by construction, same as customer).
--
-- 11. **Every hardened staff-facing read RPC that now needs to distinguish
--     "is this specific caller genuinely Platform staff for THIS ticket"
--     rather than merely "is this caller not customer_user-layer"** (`app.
--     get_ticket`/`list_tickets`/`list_ticket_messages`/`list_ticket_
--     watchers`/`list_ticket_events`) gains a PER-TICKET (not per-actor-
--     layer) exclusion: a helpdesk-channel ticket is only reachable through
--     these staff-projection RPCs by `app.is_supreme_admin(actor)` --
--     everyone else (including the ticket's own tenant-side requester
--     party, a real `tenant_admin`/`TKT:Edit` holder who otherwise
--     legitimately uses these SAME RPCs for their tenant's internal-channel
--     tickets) is refused, forced through the dedicated, tenant-safe
--     `app.get_tenant_helpdesk_ticket`/`list_tenant_helpdesk_tickets`/
--     `list_tenant_helpdesk_ticket_messages` instead -- this is deliberately
--     a PER-TICKET-CHANNEL check, not a per-actor-LAYER check like HRT-287's
--     `customer_user`-layer exclusion, because the SAME `org_user`/
--     `tenant_admin` actor legitimately needs the staff projection for
--     their tenant's internal tickets but never for a helpdesk case (their
--     own tenant's case towards CargoGrid, where THEY are the requester
--     side, not staff). Raw-table RLS on `app.tickets`/`app.ticket_
--     messages`/`app.ticket_watchers`/`app.ticket_events` is additionally
--     narrowed with the identical per-row `channel <> 'helpdesk'`
--     exclusion (mirroring the ATW-023/HRT-287 `not actor_holds_customer_
--     user_layer(...)` RLS-hardening precedent exactly) -- a helpdesk
--     ticket's ONLY sanctioned non-Supreme-Admin read path is genuinely the
--     new tenant-safe RPCs, never a raw `.from("tickets")` call.
--
-- 12. **`get_ticket`/`list_tickets` convert their `app.ticket_queues` JOIN
--     from INNER to LEFT** -- `queue_id` is now nullable (helpdesk), and an
--     INNER JOIN against a NULL FK would silently exclude every helpdesk
--     ticket from these RPCs even for a Supreme Admin caller who is
--     otherwise correctly admitted by decision 11's own guard. The exact
--     "INNER JOIN silently drops a legitimately-nullable-FK row" class
--     ISS-2026-085 already named and HRT-287 already fixed once for
--     `app.employees` -- applied here to `app.ticket_queues` for the same
--     reason.

-- ===========================================================================
-- 1. app.support_queues -- the parallel Platform support queue catalog
--    (decision 2). Genuinely global: no tenant_id, no org_unit_id.
-- ===========================================================================

create table app.support_queues (
  id uuid primary key default gen_random_uuid(),
  code text not null,
  name text not null,
  description text,
  status text not null default 'active',
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint support_queues_status_check check (status in ('active', 'inactive')),
  constraint support_queues_code_check check (length(trim(code)) > 0),
  constraint support_queues_name_check check (length(trim(name)) > 0),
  constraint support_queues_code_unique unique (code)
);

comment on table app.support_queues is
  'HRT-288 (decision 2): the parallel "Platform support queue/team" concept HRT-286''s own build log diagnosed as required (docs/build-log/phase-07/HRT-286.md section 3, decision 2''s own gap note) -- genuinely global, unlike app.ticket_queues (tenant_id+org_unit_id both required). Pure routing/triage metadata, NEVER an access-granting roster (decision 3) -- staff authority for a helpdesk ticket is app.is_supreme_admin(actor), not queue membership.';

create trigger support_queues_touch before update on app.support_queues
  for each row execute function app.touch_ticket_row();

alter table app.support_queues enable row level security;

create policy support_queues_select_scoped on app.support_queues
  for select to authenticated
  using (app.is_supreme_admin());

comment on policy support_queues_select_scoped on app.support_queues is
  'HRT-288: Platform-internal catalog, Supreme-Admin-visible only (decision 3) -- a tenant never sees CargoGrid''s own internal team/queue names, matching the "internal routing never leaks to a tenant projection" discipline already established for app.ticket_queues/assignee identity on the customer channel.';

-- ===========================================================================
-- 2. app.ticket_categories -- helpdesk-visibility flag (mirrors customer_
--    visible exactly).
-- ===========================================================================

alter table app.ticket_categories add column helpdesk_visible boolean not null default false;

create index ticket_categories_tenant_helpdesk_visible_idx on app.ticket_categories (tenant_id, helpdesk_visible) where helpdesk_visible = true and status = 'active';

comment on table app.ticket_categories is
  'HRT-286/287/288: ticket category catalog. customer_visible (HRT-287) marks a category selectable via app.create_customer_ticket; helpdesk_visible (HRT-288) marks a category selectable via app.create_helpdesk_ticket -- unlike customer_visible, no default_queue_id requirement (a helpdesk ticket''s app.tickets.queue_id is always null; Platform-side routing uses the separate app.support_queues catalog, assigned later by staff triage, never chosen by the tenant at creation).';

-- ===========================================================================
-- 3. Schema widen: app.tickets -- channel, requester-identity shape, queue
--    shape, and new helpdesk-specific columns (decisions 1/2/4/9/10).
-- ===========================================================================

alter table app.tickets drop constraint tickets_channel_check;
alter table app.tickets add constraint tickets_channel_check check (channel in ('internal', 'customer', 'helpdesk'));

alter table app.tickets drop constraint tickets_requester_identity_shape;
alter table app.tickets add constraint tickets_requester_identity_shape check (
  (channel = 'internal' and requester_employee_id is not null and requester_customer_account_id is null)
  or (channel = 'customer' and requester_customer_account_id is not null and requester_employee_id is null)
  or (channel = 'helpdesk' and requester_employee_id is null and requester_customer_account_id is null)
);

alter table app.tickets alter column queue_id drop not null;
alter table app.tickets add column support_queue_id uuid references app.support_queues (id);

alter table app.tickets add constraint tickets_queue_shape check (
  (channel in ('internal', 'customer') and queue_id is not null and support_queue_id is null)
  or (channel = 'helpdesk' and queue_id is null)
);

alter table app.tickets add column severity text;
alter table app.tickets add constraint tickets_severity_check check (severity is null or severity in ('low', 'medium', 'high', 'critical'));

alter table app.tickets add column product_area text;
alter table app.tickets add constraint tickets_product_area_check check (product_area is null or length(trim(product_area)) > 0);

alter table app.tickets add column environment text;
alter table app.tickets add constraint tickets_environment_check check (environment is null or environment in ('production', 'staging', 'sandbox', 'other'));

alter table app.tickets add column external_reference text;
alter table app.tickets add constraint tickets_external_reference_check check (external_reference is null or length(trim(external_reference)) > 0);

alter table app.tickets add column assignee_support_auth_user_id uuid references auth.users (id);

alter table app.tickets add column support_access_case_ref text;

create unique index tickets_idempotency_helpdesk_unique on app.tickets (tenant_id, requested_by_auth_user_id, idempotency_key) where idempotency_key is not null and channel = 'helpdesk';

create index tickets_support_queue_idx on app.tickets (support_queue_id, status) where channel = 'helpdesk' and support_queue_id is not null;
create index tickets_helpdesk_status_idx on app.tickets (status, created_at desc) where channel = 'helpdesk';
create index tickets_helpdesk_severity_idx on app.tickets (severity, created_at desc) where channel = 'helpdesk' and severity is not null;
create index tickets_helpdesk_assignee_idx on app.tickets (assignee_support_auth_user_id) where channel = 'helpdesk' and assignee_support_auth_user_id is not null;
create index tickets_tenant_helpdesk_idx on app.tickets (tenant_id, status) where channel = 'helpdesk';

comment on table app.tickets is
  'HRT-286/287/288 (decisions 1/2/7 of 20260731060000; decisions 1/2 of 20260731080000; decisions 1/2/9 of this migration). channel in (''internal'',''customer'',''helpdesk''). Requester identity is exactly one of requester_employee_id (internal), requester_customer_account_id (customer), or NEITHER (helpdesk -- the requester is the tenant itself, resolved via app._is_tenant_helpdesk_authorized, never a specific employee/account row) -- enforced by tickets_requester_identity_shape. Queue identity is exactly one of queue_id (internal/customer, app.ticket_queues) or support_queue_id (helpdesk, app.support_queues, Platform-global) -- enforced by tickets_queue_shape. ISS-2026-085 (docs/runtime/KNOWN_ISSUES.md) tracked the helpdesk half of this expand-and-contract work as the remaining open item after the customer half; resolved by this migration.';

comment on column app.tickets.cancelled_reason_authored_by_customer is
  'CG-S12-HRT-015 Tier C batch review fix, GENERALIZED at HRT-288 (this migration): true only when the actor who moved this ticket to cancelled was itself the ticket''s own requester-side party (app._is_ticket_requester_party) for a requester_allowed transition -- the requester''s OWN submitted text, never a staff member''s internal note, for BOTH the customer channel (a customer_user) and the helpdesk channel (an authorized tenant_admin/TKT:Edit holder, app._is_tenant_helpdesk_authorized). The column name still says "customer" (an already-VERIFIED column, not renamed to avoid unwarranted churn) but its gating condition now covers both channels -- see app.transition_ticket_status.';

comment on column app.tickets.last_reopen_reason_authored_by_customer is
  'CG-S12-HRT-015 Tier C batch review fix, GENERALIZED at HRT-288 (this migration): same shape and now-widened (customer + helpdesk) meaning as cancelled_reason_authored_by_customer, for the reopen transition.';

-- ===========================================================================
-- 4. app.ticket_events -- widen event_type to add support_grant_linked
--    (decision 7).
-- ===========================================================================

alter table app.ticket_events drop constraint ticket_events_event_type_check;
alter table app.ticket_events add constraint ticket_events_event_type_check check (event_type in (
  'create', 'status_change', 'assignment', 'queue_transfer', 'classification_change',
  'watcher_added', 'watcher_removed', 'message_redacted', 'support_grant_linked'
));

-- ===========================================================================
-- 5. app._is_tenant_helpdesk_authorized -- the tenant-requester identity
--    resolution (decision 4). Deliberately employee-independent (no app.
--    employees dependency) AND deliberately NOT routed through app.
--    check_ticket_authority/app.evaluate_permission, whose RPD-022 Supreme-
--    Admin bypass would otherwise make a Platform Supreme Admin ALSO count
--    as "the tenant-side requester party" -- a direct query against app.
--    principal_memberships/app.role_assignments instead.
-- ===========================================================================

create function app._is_tenant_helpdesk_authorized(p_tenant_id uuid, p_auth_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = app, pg_temp
as $$
  select exists (
    select 1 from app.principal_memberships pm
    where pm.auth_user_id = p_auth_user_id
      and pm.tenant_id = p_tenant_id
      and pm.layer = 'tenant_admin'
      and pm.status = 'active'
  )
  or exists (
    select 1
    from app.role_assignments ra
    join app.role_versions rv on rv.id = ra.role_version_id
    join app.role_version_permissions rvp on rvp.role_version_id = rv.id
    join app.permissions perm on perm.id = rvp.permission_id
    where ra.tenant_id = p_tenant_id
      and ra.auth_user_id = p_auth_user_id
      and ra.status = 'active'
      and rv.status = 'published'
      and perm.resource_module_code = 'TKT'
      and perm.action = 'Edit'
  );
$$;

comment on function app._is_tenant_helpdesk_authorized is
  'HRT-288 (decision 4): "is this identity an authorized tenant user for opening/managing a CargoGrid support case" -- a real, active tenant_admin principal membership, OR a real, tenant-scoped, published-role TKT:Edit grant. Deliberately NOT app.get_self_employee (a tenant must be able to file a case with zero app.employees rows) and deliberately NOT app.check_ticket_authority/app.evaluate_permission (whose RPD-022 Supreme-Admin bypass would incorrectly admit a Platform Supreme Admin as "the tenant side" of its own governed support case -- found and fixed during this migration''s own design, live-adversarially confirmed in scripts/db-tests/ticketing-helpdesk.sql). Reused by app._is_ticket_requester_party''s helpdesk branch and app.create_helpdesk_ticket -- never re-derived.';

grant execute on function app._is_tenant_helpdesk_authorized(uuid, uuid) to service_role;

-- ===========================================================================
-- 6. app._is_ticket_requester_party -- third branch (decision 1/4). Same
--    external signature; grants preserved by CREATE OR REPLACE.
-- ===========================================================================

create or replace function app._is_ticket_requester_party(p_ticket app.tickets, p_auth_user_id uuid)
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

  if p_ticket.channel = 'helpdesk' then
    return app._is_tenant_helpdesk_authorized(p_ticket.tenant_id, p_auth_user_id);
  end if;

  v_self := app.get_self_employee(p_ticket.tenant_id, p_auth_user_id);
  return v_self.master_record_id is not null and v_self.master_record_id = p_ticket.requester_employee_id;
end;
$$;

comment on function app._is_ticket_requester_party is
  'HRT-287/288 (decision 3 of 20260731080000; decision 1/4 of this migration): the ONE structural "is this identity the requester-side party for this ticket" predicate, dispatching on ticket.channel -- internal is the app.get_self_employee match; customer is app.resolve_customer_owner_account_scope membership; helpdesk (HRT-288, new) is app._is_tenant_helpdesk_authorized -- an authorized TENANT user (tenant_admin or TKT:Edit), never a specific employee/account row, matching "the tenant itself is the requester" (tenant-admin-level access, not per-individual, mirroring the customer channel''s own account-level-not-per-individual decision). Reused by app.can_access_ticket, app.reply_to_ticket, app.add_ticket_watcher/remove_ticket_watcher, and app._ticket_transition_authority -- never re-derived, and NONE of those four call sites needed their own body changed by this migration, since all four already dispatch generically through this one helper.';

-- ===========================================================================
-- 7. app.is_ticket_staff -- hardened for the helpdesk channel (decision 3).
--    Same external signature; grants preserved.
-- ===========================================================================

create or replace function app.is_ticket_staff(p_ticket_id uuid, p_auth_user_id uuid default auth.uid())
returns boolean
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_ticket app.tickets;
  v_self app.employees;
begin
  select * into v_ticket from app.tickets where id = p_ticket_id;
  if not found then
    return false;
  end if;
  if app.is_supreme_admin(p_auth_user_id) then
    return true;
  end if;

  -- HRT-288 (decision 3): Platform-support staff status for a helpdesk case
  -- is Supreme-Admin-only in this prompt's own bounded scope -- a tenant's
  -- own TKT:Edit (tenant-wide, decision 5 of 20260731060000)/queue-
  -- membership/assignee-employee authority must NEVER grant staff status
  -- here. Without this explicit exclusion, a tenant's TKT:Edit holder would
  -- otherwise satisfy is_ticket_staff on their OWN tenant's helpdesk ticket
  -- (v_ticket.tenant_id = their own tenant), letting them read Platform-
  -- internal notes on a case where they are structurally the REQUESTER
  -- side, not staff -- the single most direct violation of this migration''s
  -- own "internal notes remain hidden from tenant projections" business
  -- rule it could ship. v_ticket.queue_id is always null for a helpdesk
  -- ticket (tickets_queue_shape), so the queue-membership branch below is
  -- already naturally false too -- this explicit early return is
  -- belt-and-suspenders defense in depth, not relying on that null
  -- semantics alone.
  if v_ticket.channel = 'helpdesk' then
    return false;
  end if;

  if app.check_ticket_authority('Edit', v_ticket.tenant_id, p_auth_user_id) then
    return true;
  end if;
  v_self := app.get_self_employee(v_ticket.tenant_id, p_auth_user_id);
  if v_self.master_record_id is not null and v_self.master_record_id = v_ticket.assignee_employee_id then
    return true;
  end if;
  return app.is_ticket_queue_member(v_ticket.queue_id, p_auth_user_id);
end;
$$;

comment on function app.is_ticket_staff is
  'HRT-286/288 (decision 5 of 20260731060000, corrected at the CG-S12-HRT-014 Tier C batch review; decision 3 of this migration): true if the caller is Supreme Admin (always, every channel, RPD-022); OR, for internal/customer channels only, holds tenant-wide TKT:Edit, is the ticket''s own assignee, or is an active member of the ticket''s queue. For a HELPDESK-channel ticket specifically, staff status is Supreme-Admin-only -- a deliberate, disclosed bounded-scope decision (no dedicated non-Supreme-Admin "Platform support agent" role exists in this repository, decision 3 of this migration''s own header) -- the tenant-wide TKT:Edit/queue/assignee-employee fallbacks below are structurally unreachable for helpdesk by this explicit early return, never merely by the coincidental nullness of queue_id.';

-- ===========================================================================
-- 8. app.ticket_audit_projection -- widened allowlist (still structural
--    fields only, C-24 discipline unchanged). Same signature; grants
--    preserved.
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
    'support_queue_id', p_ticket.support_queue_id,
    'priority', p_ticket.priority,
    'severity', p_ticket.severity,
    'status', p_ticket.status,
    'requester_employee_id', p_ticket.requester_employee_id,
    'requester_customer_account_id', p_ticket.requester_customer_account_id,
    'assignee_employee_id', p_ticket.assignee_employee_id,
    'assignee_support_auth_user_id', p_ticket.assignee_support_auth_user_id,
    'support_access_case_ref', p_ticket.support_access_case_ref,
    'record_version', p_ticket.record_version,
    'reopen_count', p_ticket.reopen_count
  );
$$;

comment on function app.ticket_audit_projection is
  'HRT-286/287/288 (C-24 discipline unchanged across all three): explicit structural-fields-only allowlist -- deliberately excludes subject/resolution_summary/cancelled_reason/last_reopen_reason/product_area/environment/external_reference (free text). support_access_case_ref IS included -- it is an identifier/correlation key, not free-text rationale, same sensitivity class as ticket_number.';

-- ===========================================================================
-- 9. app._create_ticket -- three-way channel handling (decisions 1/2/4/9).
--    Signature widened (new trailing metadata params) -- explicit
--    drop-then-create, per this repository's own established discipline for
--    an internal (service_role-only), non-authenticated-facing function
--    whose parameter list changes (CREATE OR REPLACE cannot add parameters
--    without leaving a stale, ambiguous second overload behind).
-- ===========================================================================

drop function if exists app._create_ticket(uuid, text, uuid, uuid, uuid, uuid, text, text, text, text, uuid, text);

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
  p_actor_label text,
  p_severity text default null,
  p_product_area text default null,
  p_environment text default null,
  p_external_reference text default null
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
  if p_channel is null or not (p_channel = any (array['internal', 'customer', 'helpdesk'])) then
    raise exception 'invalid_channel: % is not one of internal/customer/helpdesk', p_channel using errcode = 'check_violation';
  end if;
  if p_channel = 'internal' then
    if p_requester_employee_id is null or p_requester_customer_account_id is not null then
      raise exception 'invalid_requester_identity: internal channel requires exactly a requester_employee_id' using errcode = 'check_violation';
    end if;
  elsif p_channel = 'customer' then
    if p_requester_customer_account_id is null or p_requester_employee_id is not null then
      raise exception 'invalid_requester_identity: customer channel requires exactly a requester_customer_account_id' using errcode = 'check_violation';
    end if;
  else
    if p_requester_employee_id is not null or p_requester_customer_account_id is not null then
      raise exception 'invalid_requester_identity: helpdesk channel requires neither a requester_employee_id nor a requester_customer_account_id (the tenant itself is the requester)' using errcode = 'check_violation';
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

  if p_channel in ('internal', 'customer') then
    v_resolved_queue_id := coalesce(p_queue_id, v_category.default_queue_id);
    if v_resolved_queue_id is null then
      raise exception 'queue_required: no queue was supplied and category % has no default queue', p_category_id using errcode = 'check_violation';
    end if;
    if not exists (select 1 from app.ticket_queues where id = v_resolved_queue_id and tenant_id = p_tenant_id and status = 'active') then
      raise exception 'queue_not_available: % is not an active queue for this tenant', v_resolved_queue_id using errcode = 'no_data_found';
    end if;
  else
    -- HRT-288 (decision 2): a helpdesk ticket's queue is ALWAYS null at
    -- creation -- Platform-internal routing (app.support_queues) is a
    -- staff-side triage action performed later (app.
    -- transfer_helpdesk_support_queue), never chosen or forged by the
    -- filing tenant.
    v_resolved_queue_id := null;
  end if;

  if p_idempotency_key is not null then
    if p_channel = 'internal' then
      select * into v_existing from app.tickets
      where tenant_id = p_tenant_id and channel = 'internal' and requester_employee_id = p_requester_employee_id and idempotency_key = p_idempotency_key;
    elsif p_channel = 'customer' then
      select * into v_existing from app.tickets
      where tenant_id = p_tenant_id and channel = 'customer' and requested_by_auth_user_id = p_actor_auth_user_id
        and requester_customer_account_id = p_requester_customer_account_id and idempotency_key = p_idempotency_key;
    else
      select * into v_existing from app.tickets
      where tenant_id = p_tenant_id and channel = 'helpdesk' and requested_by_auth_user_id = p_actor_auth_user_id and idempotency_key = p_idempotency_key;
    end if;
    if found then
      select m.body into v_existing_body from app.ticket_messages m where m.ticket_id = v_existing.id order by m.created_at asc limit 1;
      if v_existing.category_id = p_category_id and coalesce(v_existing.queue_id::text, '') = coalesce(v_resolved_queue_id::text, '') and v_existing.priority = v_priority
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
      requester_employee_id, requester_customer_account_id, requested_by_auth_user_id, requested_by,
      idempotency_key, created_by, severity, product_area, environment, external_reference
    ) values (
      p_tenant_id, v_number, p_channel, p_category_id, v_resolved_queue_id, v_priority, p_subject, 'new',
      p_requester_employee_id, p_requester_customer_account_id, p_actor_auth_user_id, p_actor_label,
      p_idempotency_key, p_actor_label, p_severity, p_product_area, p_environment, p_external_reference
    )
    returning * into v_ticket;
  exception
    when unique_violation then
      if p_idempotency_key is not null then
        if p_channel = 'internal' then
          select * into v_ticket from app.tickets
          where tenant_id = p_tenant_id and channel = 'internal' and requester_employee_id = p_requester_employee_id and idempotency_key = p_idempotency_key;
        elsif p_channel = 'customer' then
          select * into v_ticket from app.tickets
          where tenant_id = p_tenant_id and channel = 'customer' and requested_by_auth_user_id = p_actor_auth_user_id
            and requester_customer_account_id = p_requester_customer_account_id and idempotency_key = p_idempotency_key;
        else
          select * into v_ticket from app.tickets
          where tenant_id = p_tenant_id and channel = 'helpdesk' and requested_by_auth_user_id = p_actor_auth_user_id and idempotency_key = p_idempotency_key;
        end if;
        if found then
          select m.body into v_existing_body from app.ticket_messages m where m.ticket_id = v_ticket.id order by m.created_at asc limit 1;
          if v_ticket.category_id = p_category_id and coalesce(v_ticket.queue_id::text, '') = coalesce(v_resolved_queue_id::text, '') and v_ticket.priority = v_priority
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
  'HRT-286/287/288 (decision 4/ISS-2026-085 fully resolved): the shared ticket-creation engine, now taking p_channel in (''internal'',''customer'',''helpdesk''), validated to have EXACTLY the requester identity shape matching that channel (belt-and-suspenders alongside the table CHECK tickets_requester_identity_shape). Queue resolution/requirement is SKIPPED entirely for helpdesk (queue_id always null at creation, decision 2). Called by app.create_ticket/app.create_ticket_for_employee (channel:=''internal''), app.create_customer_ticket (channel:=''customer''), and app.create_helpdesk_ticket (channel:=''helpdesk''). Idempotency replay is keyed per channel: requester_employee_id (internal); requested_by_auth_user_id + requester_customer_account_id (customer); requested_by_auth_user_id alone (helpdesk -- there is no per-ticket customer-account-style scope to additionally key on, since the requester IS the tenant).';

grant execute on function app._create_ticket(uuid, text, uuid, uuid, uuid, uuid, text, text, text, text, uuid, text, text, text, text, text) to service_role;

-- ===========================================================================
-- 10. app.create_ticket / app.create_ticket_for_employee / app.
--     create_customer_ticket -- external signatures UNCHANGED, bodies pass
--     the new trailing metadata params as null. Grants preserved.
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
  return app._create_ticket(p_tenant_id, 'internal', v_self.master_record_id, null, p_category_id, p_queue_id, p_priority, p_subject, p_body, p_idempotency_key, p_actor_auth_user_id, p_actor_label, null, null, null, null);
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

  return app._create_ticket(p_tenant_id, 'internal', v_employee.master_record_id, null, p_category_id, p_queue_id, p_priority, p_subject, p_body, p_idempotency_key, p_actor_auth_user_id, p_actor_label, null, null, null, null);
end;
$$;

create or replace function app.create_customer_ticket(
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

  return app._create_ticket(p_tenant_id, 'customer', null, p_account_id, p_category_id, v_category.default_queue_id, p_priority, p_subject, p_body, p_idempotency_key, p_actor_auth_user_id, p_actor_label, null, null, null, null);
end;
$$;

-- ===========================================================================
-- 11. app.create_helpdesk_ticket -- new tenant-side self-service entry
--     point (decisions 4/9). Scope always validated via app._is_tenant_
--     helpdesk_authorized, never trusted from the payload.
-- ===========================================================================

create function app.create_helpdesk_ticket(
  p_tenant_id uuid,
  p_category_id uuid,
  p_priority text,
  p_severity text,
  p_product_area text,
  p_environment text,
  p_external_reference text,
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

  if not app._is_tenant_helpdesk_authorized(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % is not authorized to open a CargoGrid support case for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_category from app.ticket_categories where id = p_category_id and tenant_id = p_tenant_id and status = 'active' and helpdesk_visible = true;
  if not found then
    raise exception 'category_not_available: % is not an active helpdesk-visible category for this tenant', p_category_id using errcode = 'no_data_found';
  end if;

  if p_severity is not null and not (p_severity = any (array['low', 'medium', 'high', 'critical'])) then
    raise exception 'invalid_severity: % is not one of low/medium/high/critical', p_severity using errcode = 'check_violation';
  end if;
  if p_environment is not null and not (p_environment = any (array['production', 'staging', 'sandbox', 'other'])) then
    raise exception 'invalid_environment: % is not one of production/staging/sandbox/other', p_environment using errcode = 'check_violation';
  end if;

  return app._create_ticket(
    p_tenant_id, 'helpdesk', null, null, p_category_id, null, p_priority, p_subject, p_body,
    p_idempotency_key, p_actor_auth_user_id, p_actor_label, p_severity, p_product_area, p_environment, p_external_reference
  );
end;
$$;

comment on function app.create_helpdesk_ticket is
  'HRT-288: tenant-side self-service creation of a CargoGrid support case. p_account_id/p_queue_id/p_support_queue_id do not exist as parameters at all -- there is nothing for a caller to spoof (mirrors app.create_ticket''s own "no field to spoof" design). Authority is app._is_tenant_helpdesk_authorized (decision 4) -- an authorized tenant user (tenant_admin or TKT:Edit), never any app.employees dependency.';

grant execute on function app.create_helpdesk_ticket(uuid, uuid, text, text, text, text, text, text, text, text, uuid, text) to authenticated, service_role;

-- ===========================================================================
-- 12. app.reply_to_helpdesk_ticket -- thin defense-in-depth wrapper
--     (decision 5), mirrors app.reply_to_customer_ticket exactly.
-- ===========================================================================

create function app.reply_to_helpdesk_ticket(
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
  if not found or v_ticket.channel <> 'helpdesk' then
    raise exception 'ticket_not_found: %', p_ticket_id using errcode = 'no_data_found';
  end if;

  return app.reply_to_ticket(p_ticket_id, p_body, 'public', p_attachment_file_ids, p_idempotency_key, p_actor_auth_user_id, p_actor_label);
end;
$$;

comment on function app.reply_to_helpdesk_ticket is
  'HRT-288 (decision 5): thin wrapper over app.reply_to_ticket (unmodified) -- hardcodes visibility=''public'' at the call site itself and independently confirms channel=''helpdesk'' before delegating. Platform staff (Supreme Admin) posts internal notes through app.reply_to_ticket directly, whose own visibility=internal guard is gated by app.is_ticket_staff -- hardened by this migration to mean Supreme-Admin-only for a helpdesk ticket.';

grant execute on function app.reply_to_helpdesk_ticket(uuid, text, uuid[], text, uuid, text) to authenticated, service_role;

-- ===========================================================================
-- 13. app.transition_ticket_status -- widen the requester-authored tracking
--     gate to cover helpdesk too (decision 10). Same external signature;
--     grants preserved.
-- ===========================================================================

create or replace function app.transition_ticket_status(p_ticket_id uuid, p_expected_version integer, p_to_status text, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.tickets
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_ticket app.tickets;
  v_transition app.ticket_status_transitions;
  v_updated app.tickets;
  v_is_reopen boolean;
  v_actor_is_requester boolean;
  v_requester_tracked_channel boolean;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_ticket from app.tickets where id = p_ticket_id for update;
  if not found then
    raise exception 'ticket_not_found: %', p_ticket_id using errcode = 'no_data_found';
  end if;
  if not app.can_access_ticket(p_ticket_id, p_actor_auth_user_id) then
    raise exception 'ticket_not_found: %', p_ticket_id using errcode = 'no_data_found';
  end if;

  if v_ticket.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_ticket.record_version
      using errcode = 'serialization_failure';
  end if;

  select * into v_transition from app.ticket_status_transitions where from_status = v_ticket.status and to_status = p_to_status;
  if not found then
    raise exception 'invalid_transition: % -> % is not a legal ticket status transition', v_ticket.status, p_to_status using errcode = 'check_violation';
  end if;

  if not app._ticket_transition_authority(v_ticket, p_to_status, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % may not move ticket % from % to %', p_actor_auth_user_id, p_ticket_id, v_ticket.status, p_to_status
      using errcode = 'insufficient_privilege';
  end if;

  if v_transition.requires_reason and (p_reason is null or length(trim(p_reason)) = 0) then
    raise exception 'reason_required: a reason is required to move this ticket from % to %', v_ticket.status, p_to_status using errcode = 'check_violation';
  end if;

  v_is_reopen := v_ticket.status in ('resolved', 'closed') and p_to_status = 'open';

  v_actor_is_requester := app._is_ticket_requester_party(v_ticket, p_actor_auth_user_id);
  -- HRT-288 (decision 10): widened from channel = 'customer' alone to cover
  -- helpdesk too -- both are the "requester-side party is not the ticket's
  -- employee/staff side" shape these tracking columns exist to distinguish.
  v_requester_tracked_channel := v_ticket.channel in ('customer', 'helpdesk');

  update app.tickets set
    status = p_to_status,
    resolution_summary = case when p_to_status = 'resolved' then p_reason else resolution_summary end,
    resolved_by = case when p_to_status = 'resolved' then p_actor_label else resolved_by end,
    resolved_at = case when p_to_status = 'resolved' then now() else resolved_at end,
    closed_by = case when p_to_status = 'closed' then p_actor_label else closed_by end,
    closed_at = case when p_to_status = 'closed' then now() else closed_at end,
    cancelled_reason = case when p_to_status = 'cancelled' then p_reason else cancelled_reason end,
    cancelled_by = case when p_to_status = 'cancelled' then p_actor_label else cancelled_by end,
    cancelled_at = case when p_to_status = 'cancelled' then now() else cancelled_at end,
    cancelled_reason_authored_by_customer = case when p_to_status = 'cancelled' then v_actor_is_requester and v_requester_tracked_channel else cancelled_reason_authored_by_customer end,
    reopen_count = case when v_is_reopen then reopen_count + 1 else reopen_count end,
    last_reopened_by = case when v_is_reopen then p_actor_label else last_reopened_by end,
    last_reopened_at = case when v_is_reopen then now() else last_reopened_at end,
    last_reopen_reason = case when v_is_reopen then p_reason else last_reopen_reason end,
    last_reopen_reason_authored_by_customer = case when v_is_reopen then v_actor_is_requester and v_requester_tracked_channel else last_reopen_reason_authored_by_customer end
  where id = p_ticket_id and record_version = p_expected_version
  returning * into v_updated;
  if not found then
    raise exception 'stale_version: concurrent update detected for ticket %', p_ticket_id using errcode = 'serialization_failure';
  end if;

  insert into app.ticket_events (tenant_id, ticket_id, event_type, from_value, to_value, reason, actor_auth_user_id, actor_label)
  values (v_ticket.tenant_id, p_ticket_id, 'status_change', v_ticket.status, p_to_status, p_reason, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_ticket.tenant_id, p_actor_auth_user_id, p_actor_label, 'transition_ticket_status',
    'app.tickets', p_ticket_id, 'success', null, app.ticket_audit_projection(v_ticket), app.ticket_audit_projection(v_updated)
  );

  return v_updated;
end;
$$;

comment on function app.transition_ticket_status is
  'HRT-286/287/288 (decision 6 of 20260731060000, corrected at the CG-S12-HRT-014 Tier C batch review; decision 1 of 20260731090000; decision 10 of this migration): the ONE generic lifecycle RPC, unchanged in shape across all three channels -- record_version checked before the transition-graph lookup/authority check; cancelled_reason_authored_by_customer/last_reopen_reason_authored_by_customer now track "authored by the ticket''s own requester-side party" for BOTH customer and helpdesk channels (never internal, which has no such distinction to make -- an internal-channel requester IS an ordinary employee, not a separately-hidden-content audience).';

-- ===========================================================================
-- 14. app.assign_ticket / app.transfer_ticket_queue / app.
--     update_ticket_classification -- explicit helpdesk rejection
--     (decision 6). Same external signatures; grants preserved.
-- ===========================================================================

create or replace function app.assign_ticket(p_ticket_id uuid, p_expected_version integer, p_assignee_employee_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
returns app.tickets
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_ticket app.tickets;
  v_updated app.tickets;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_ticket from app.tickets where id = p_ticket_id for update;
  if not found then
    raise exception 'ticket_not_found: %', p_ticket_id using errcode = 'no_data_found';
  end if;
  if not app.can_access_ticket(p_ticket_id, p_actor_auth_user_id) then
    raise exception 'ticket_not_found: %', p_ticket_id using errcode = 'no_data_found';
  end if;
  if v_ticket.channel = 'helpdesk' then
    raise exception 'channel_not_supported: ticket % is a helpdesk case -- use app.assign_helpdesk_ticket instead', p_ticket_id using errcode = 'check_violation';
  end if;
  if not app.check_ticket_authority('Assign', v_ticket.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks TKT:Assign for tenant %', p_actor_auth_user_id, v_ticket.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_ticket.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_ticket.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_ticket.status in ('closed', 'cancelled') then
    raise exception 'invalid_transition: cannot reassign a % ticket', v_ticket.status using errcode = 'check_violation';
  end if;

  if p_assignee_employee_id is not null then
    if not exists (select 1 from app.employees e where e.master_record_id = p_assignee_employee_id and e.tenant_id = v_ticket.tenant_id) then
      raise exception 'employee_not_found: %', p_assignee_employee_id using errcode = 'no_data_found';
    end if;
    if not exists (select 1 from app.ticket_queue_members m where m.queue_id = v_ticket.queue_id and m.employee_id = p_assignee_employee_id and m.status = 'active') then
      raise exception 'assignee_not_queue_member: employee % is not an active member of queue %', p_assignee_employee_id, v_ticket.queue_id using errcode = 'check_violation';
    end if;
  end if;

  update app.tickets set assignee_employee_id = p_assignee_employee_id, assigned_by = p_actor_label, assigned_at = now()
  where id = p_ticket_id and record_version = p_expected_version
  returning * into v_updated;
  if not found then
    raise exception 'stale_version: concurrent update detected for ticket %', p_ticket_id using errcode = 'serialization_failure';
  end if;

  insert into app.ticket_events (tenant_id, ticket_id, event_type, from_value, to_value, actor_auth_user_id, actor_label)
  values (v_ticket.tenant_id, p_ticket_id, 'assignment', v_ticket.assignee_employee_id::text, p_assignee_employee_id::text, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_ticket.tenant_id, p_actor_auth_user_id, p_actor_label, 'assign_ticket',
    'app.tickets', p_ticket_id, 'success', null, app.ticket_audit_projection(v_ticket), app.ticket_audit_projection(v_updated)
  );

  return v_updated;
end;
$$;

create or replace function app.transfer_ticket_queue(p_ticket_id uuid, p_expected_version integer, p_new_queue_id uuid, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.tickets
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_ticket app.tickets;
  v_updated app.tickets;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_ticket from app.tickets where id = p_ticket_id for update;
  if not found then
    raise exception 'ticket_not_found: %', p_ticket_id using errcode = 'no_data_found';
  end if;
  if not app.can_access_ticket(p_ticket_id, p_actor_auth_user_id) then
    raise exception 'ticket_not_found: %', p_ticket_id using errcode = 'no_data_found';
  end if;
  if v_ticket.channel = 'helpdesk' then
    raise exception 'channel_not_supported: ticket % is a helpdesk case -- use app.transfer_helpdesk_support_queue instead', p_ticket_id using errcode = 'check_violation';
  end if;
  if not app.is_ticket_staff(p_ticket_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % is not ticket staff on %', p_actor_auth_user_id, p_ticket_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_ticket.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_ticket.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_ticket.status in ('closed', 'cancelled') then
    raise exception 'invalid_transition: cannot transfer a % ticket', v_ticket.status using errcode = 'check_violation';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a reason is required to transfer a ticket to another queue' using errcode = 'check_violation';
  end if;
  if not exists (select 1 from app.ticket_queues where id = p_new_queue_id and tenant_id = v_ticket.tenant_id and status = 'active') then
    raise exception 'queue_not_available: % is not an active queue for this tenant', p_new_queue_id using errcode = 'no_data_found';
  end if;

  update app.tickets set queue_id = p_new_queue_id, assignee_employee_id = null, assigned_by = null, assigned_at = null
  where id = p_ticket_id and record_version = p_expected_version
  returning * into v_updated;
  if not found then
    raise exception 'stale_version: concurrent update detected for ticket %', p_ticket_id using errcode = 'serialization_failure';
  end if;

  insert into app.ticket_events (tenant_id, ticket_id, event_type, from_value, to_value, reason, actor_auth_user_id, actor_label)
  values (v_ticket.tenant_id, p_ticket_id, 'queue_transfer', v_ticket.queue_id::text, p_new_queue_id::text, p_reason, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_ticket.tenant_id, p_actor_auth_user_id, p_actor_label, 'transfer_ticket_queue',
    'app.tickets', p_ticket_id, 'success', null, app.ticket_audit_projection(v_ticket), app.ticket_audit_projection(v_updated)
  );

  return v_updated;
end;
$$;

create or replace function app.update_ticket_classification(p_ticket_id uuid, p_expected_version integer, p_category_id uuid, p_priority text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.tickets
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_ticket app.tickets;
  v_updated app.tickets;
  v_priority text := coalesce(p_priority, 'normal');
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_ticket from app.tickets where id = p_ticket_id for update;
  if not found then
    raise exception 'ticket_not_found: %', p_ticket_id using errcode = 'no_data_found';
  end if;
  if not app.can_access_ticket(p_ticket_id, p_actor_auth_user_id) then
    raise exception 'ticket_not_found: %', p_ticket_id using errcode = 'no_data_found';
  end if;
  if v_ticket.channel = 'helpdesk' then
    raise exception 'channel_not_supported: ticket % is a helpdesk case -- use app.update_helpdesk_ticket_classification instead', p_ticket_id using errcode = 'check_violation';
  end if;
  if not app.is_ticket_staff(p_ticket_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % is not ticket staff on %', p_actor_auth_user_id, p_ticket_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_ticket.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_ticket.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_ticket.status in ('closed', 'cancelled') then
    raise exception 'invalid_transition: cannot reclassify a % ticket', v_ticket.status using errcode = 'check_violation';
  end if;
  if not (v_priority = any (array['low', 'normal', 'high', 'urgent'])) then
    raise exception 'invalid_priority: % is not one of low/normal/high/urgent', v_priority using errcode = 'check_violation';
  end if;
  if not exists (select 1 from app.ticket_categories where id = p_category_id and tenant_id = v_ticket.tenant_id and status = 'active') then
    raise exception 'category_not_available: % is not an active category for this tenant', p_category_id using errcode = 'no_data_found';
  end if;

  update app.tickets set category_id = p_category_id, priority = v_priority
  where id = p_ticket_id and record_version = p_expected_version
  returning * into v_updated;
  if not found then
    raise exception 'stale_version: concurrent update detected for ticket %', p_ticket_id using errcode = 'serialization_failure';
  end if;

  insert into app.ticket_events (tenant_id, ticket_id, event_type, from_value, to_value, actor_auth_user_id, actor_label)
  values (
    v_ticket.tenant_id, p_ticket_id, 'classification_change',
    v_ticket.category_id::text || '/' || v_ticket.priority, p_category_id::text || '/' || v_priority,
    p_actor_auth_user_id, p_actor_label
  );

  perform app.capture_audit_event(
    v_ticket.tenant_id, p_actor_auth_user_id, p_actor_label, 'update_ticket_classification',
    'app.tickets', p_ticket_id, 'success', null, app.ticket_audit_projection(v_ticket), app.ticket_audit_projection(v_updated)
  );

  return v_updated;
end;
$$;

-- ===========================================================================
-- 15. app.redact_ticket_message -- helpdesk redaction is Platform-staff-only
--     (decision 6/8). Same external signature; grants preserved.
-- ===========================================================================

create or replace function app.redact_ticket_message(p_message_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.ticket_messages
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_message app.ticket_messages;
  v_ticket app.tickets;
  v_updated app.ticket_messages;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_message from app.ticket_messages where id = p_message_id for update;
  if not found then
    raise exception 'ticket_message_not_found: %', p_message_id using errcode = 'no_data_found';
  end if;

  if not app.can_access_ticket(v_message.ticket_id, p_actor_auth_user_id) then
    raise exception 'ticket_message_not_found: %', p_message_id using errcode = 'no_data_found';
  end if;

  select * into v_ticket from app.tickets where id = v_message.ticket_id;

  if v_ticket.channel = 'helpdesk' then
    -- HRT-288 (decision 6/8): redaction of ANY content (public or Platform-
    -- internal) on a helpdesk case is Platform-support-staff-only (Supreme
    -- Admin, per this migration's own bounded staff-role decision) -- a
    -- tenant's own tenant-wide TKT:Edit authority must NEVER be able to
    -- destroy Platform-internal diagnostic notes it cannot even read.
    if not app.is_ticket_staff(v_ticket.id, p_actor_auth_user_id) then
      raise exception 'insufficient_authority: identity % lacks Platform support authority to redact content on helpdesk ticket %', p_actor_auth_user_id, v_ticket.id
        using errcode = 'insufficient_privilege';
    end if;
  elsif not app.check_ticket_authority('Edit', v_message.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks TKT:Edit for tenant %', p_actor_auth_user_id, v_message.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_message.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_message.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_message.is_redacted then
    return v_message;
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a reason is required to redact a message' using errcode = 'check_violation';
  end if;

  update app.ticket_messages
  set body = '[redacted]', attachment_file_ids = '{}'::uuid[], is_redacted = true, redacted_at = now(), redacted_by = p_actor_label, redacted_reason = p_reason
  where id = p_message_id and record_version = p_expected_version
  returning * into v_updated;
  if not found then
    raise exception 'stale_version: concurrent update detected for ticket message %', p_message_id using errcode = 'serialization_failure';
  end if;

  insert into app.ticket_events (tenant_id, ticket_id, event_type, actor_auth_user_id, actor_label)
  values (v_message.tenant_id, v_message.ticket_id, 'message_redacted', p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_message.tenant_id, p_actor_auth_user_id, p_actor_label, 'redact_ticket_message',
    'app.ticket_messages', v_message.id, 'success', null,
    jsonb_build_object('ticket_id', v_message.ticket_id, 'visibility', v_message.visibility, 'is_redacted', false),
    jsonb_build_object('ticket_id', v_updated.ticket_id, 'visibility', v_updated.visibility, 'is_redacted', true)
  );

  return v_updated;
end;
$$;

-- ===========================================================================
-- 16. Platform-side (Supreme-Admin-only) helpdesk write RPCs (decisions
--     3/6/7).
-- ===========================================================================

create function app.assign_helpdesk_ticket(p_ticket_id uuid, p_expected_version integer, p_assignee_auth_user_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
returns app.tickets
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_ticket app.tickets;
  v_updated app.tickets;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if not app.is_supreme_admin(p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks Platform support authority to assign helpdesk tickets', p_actor_auth_user_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_ticket from app.tickets where id = p_ticket_id for update;
  if not found or v_ticket.channel <> 'helpdesk' then
    raise exception 'ticket_not_found: %', p_ticket_id using errcode = 'no_data_found';
  end if;
  if v_ticket.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_ticket.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_ticket.status in ('closed', 'cancelled') then
    raise exception 'invalid_transition: cannot reassign a % ticket', v_ticket.status using errcode = 'check_violation';
  end if;
  if p_assignee_auth_user_id is not null and not app.is_supreme_admin(p_assignee_auth_user_id) then
    raise exception 'assignee_not_support_staff: % does not hold Platform support (Supreme Admin) authority', p_assignee_auth_user_id using errcode = 'check_violation';
  end if;

  update app.tickets set assignee_support_auth_user_id = p_assignee_auth_user_id, assigned_by = p_actor_label, assigned_at = now()
  where id = p_ticket_id and record_version = p_expected_version
  returning * into v_updated;
  if not found then
    raise exception 'stale_version: concurrent update detected for ticket %', p_ticket_id using errcode = 'serialization_failure';
  end if;

  insert into app.ticket_events (tenant_id, ticket_id, event_type, from_value, to_value, actor_auth_user_id, actor_label)
  values (v_ticket.tenant_id, p_ticket_id, 'assignment', v_ticket.assignee_support_auth_user_id::text, p_assignee_auth_user_id::text, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_ticket.tenant_id, p_actor_auth_user_id, p_actor_label, 'assign_helpdesk_ticket',
    'app.tickets', p_ticket_id, 'success', null, app.ticket_audit_projection(v_ticket), app.ticket_audit_projection(v_updated)
  );

  return v_updated;
end;
$$;

create function app.transfer_helpdesk_support_queue(p_ticket_id uuid, p_expected_version integer, p_new_support_queue_id uuid, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.tickets
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_ticket app.tickets;
  v_updated app.tickets;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if not app.is_supreme_admin(p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks Platform support authority to triage helpdesk tickets', p_actor_auth_user_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_ticket from app.tickets where id = p_ticket_id for update;
  if not found or v_ticket.channel <> 'helpdesk' then
    raise exception 'ticket_not_found: %', p_ticket_id using errcode = 'no_data_found';
  end if;
  if v_ticket.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_ticket.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_ticket.status in ('closed', 'cancelled') then
    raise exception 'invalid_transition: cannot transfer a % ticket', v_ticket.status using errcode = 'check_violation';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a reason is required to transfer a helpdesk ticket to another support queue' using errcode = 'check_violation';
  end if;
  if not exists (select 1 from app.support_queues where id = p_new_support_queue_id and status = 'active') then
    raise exception 'support_queue_not_available: % is not an active support queue', p_new_support_queue_id using errcode = 'no_data_found';
  end if;

  update app.tickets set support_queue_id = p_new_support_queue_id, assignee_support_auth_user_id = null, assigned_by = null, assigned_at = null
  where id = p_ticket_id and record_version = p_expected_version
  returning * into v_updated;
  if not found then
    raise exception 'stale_version: concurrent update detected for ticket %', p_ticket_id using errcode = 'serialization_failure';
  end if;

  insert into app.ticket_events (tenant_id, ticket_id, event_type, from_value, to_value, reason, actor_auth_user_id, actor_label)
  values (v_ticket.tenant_id, p_ticket_id, 'queue_transfer', v_ticket.support_queue_id::text, p_new_support_queue_id::text, p_reason, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_ticket.tenant_id, p_actor_auth_user_id, p_actor_label, 'transfer_helpdesk_support_queue',
    'app.tickets', p_ticket_id, 'success', null, app.ticket_audit_projection(v_ticket), app.ticket_audit_projection(v_updated)
  );

  return v_updated;
end;
$$;

create function app.update_helpdesk_ticket_classification(
  p_ticket_id uuid, p_expected_version integer, p_category_id uuid, p_priority text,
  p_severity text, p_product_area text, p_environment text, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.tickets
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_ticket app.tickets;
  v_updated app.tickets;
  v_priority text := coalesce(p_priority, 'normal');
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if not app.is_supreme_admin(p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks Platform support authority to reclassify helpdesk tickets', p_actor_auth_user_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_ticket from app.tickets where id = p_ticket_id for update;
  if not found or v_ticket.channel <> 'helpdesk' then
    raise exception 'ticket_not_found: %', p_ticket_id using errcode = 'no_data_found';
  end if;
  if v_ticket.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_ticket.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_ticket.status in ('closed', 'cancelled') then
    raise exception 'invalid_transition: cannot reclassify a % ticket', v_ticket.status using errcode = 'check_violation';
  end if;
  if not (v_priority = any (array['low', 'normal', 'high', 'urgent'])) then
    raise exception 'invalid_priority: % is not one of low/normal/high/urgent', v_priority using errcode = 'check_violation';
  end if;
  if p_severity is not null and not (p_severity = any (array['low', 'medium', 'high', 'critical'])) then
    raise exception 'invalid_severity: % is not one of low/medium/high/critical', p_severity using errcode = 'check_violation';
  end if;
  if p_environment is not null and not (p_environment = any (array['production', 'staging', 'sandbox', 'other'])) then
    raise exception 'invalid_environment: % is not one of production/staging/sandbox/other', p_environment using errcode = 'check_violation';
  end if;
  if not exists (select 1 from app.ticket_categories where id = p_category_id and tenant_id = v_ticket.tenant_id and status = 'active') then
    raise exception 'category_not_available: % is not an active category for this tenant', p_category_id using errcode = 'no_data_found';
  end if;

  update app.tickets set category_id = p_category_id, priority = v_priority, severity = p_severity, product_area = p_product_area, environment = p_environment
  where id = p_ticket_id and record_version = p_expected_version
  returning * into v_updated;
  if not found then
    raise exception 'stale_version: concurrent update detected for ticket %', p_ticket_id using errcode = 'serialization_failure';
  end if;

  insert into app.ticket_events (tenant_id, ticket_id, event_type, from_value, to_value, actor_auth_user_id, actor_label)
  values (
    v_ticket.tenant_id, p_ticket_id, 'classification_change',
    v_ticket.category_id::text || '/' || v_ticket.priority, p_category_id::text || '/' || v_priority,
    p_actor_auth_user_id, p_actor_label
  );

  perform app.capture_audit_event(
    v_ticket.tenant_id, p_actor_auth_user_id, p_actor_label, 'update_helpdesk_ticket_classification',
    'app.tickets', p_ticket_id, 'success', null, app.ticket_audit_projection(v_ticket), app.ticket_audit_projection(v_updated)
  );

  return v_updated;
end;
$$;

create function app.link_helpdesk_support_grant(p_ticket_id uuid, p_expected_version integer, p_case_ref text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.tickets
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_ticket app.tickets;
  v_updated app.tickets;
  v_normalized_ref text := nullif(trim(coalesce(p_case_ref, '')), '');
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if not app.is_supreme_admin(p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks Platform support authority to correlate a support access case', p_actor_auth_user_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_ticket from app.tickets where id = p_ticket_id for update;
  if not found or v_ticket.channel <> 'helpdesk' then
    raise exception 'ticket_not_found: %', p_ticket_id using errcode = 'no_data_found';
  end if;
  if v_ticket.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_ticket.record_version
      using errcode = 'serialization_failure';
  end if;

  -- HRT-288 (decision 7): DISPLAY/AUDIT correlation only -- this function
  -- never creates, approves, starts, extends, or otherwise mutates a
  -- support access grant/session, and never reaches app.support_access_
  -- grants for any purpose beyond this one existence check (typo/forgery
  -- defense). A real grant is requested through the SEPARATE, UNMODIFIED
  -- app.request_support_access (PLT-115) flow -- never through this ticket
  -- mechanism.
  if v_normalized_ref is not null and not exists (
    select 1 from app.support_access_grants g where g.tenant_id = v_ticket.tenant_id and g.case_id = v_normalized_ref
  ) then
    raise exception 'support_grant_not_found: no support access grant exists for case % in tenant % -- this correlation is display-only and never itself grants access; request a real grant via app.request_support_access first', v_normalized_ref, v_ticket.tenant_id
      using errcode = 'no_data_found';
  end if;

  update app.tickets set support_access_case_ref = v_normalized_ref
  where id = p_ticket_id and record_version = p_expected_version
  returning * into v_updated;
  if not found then
    raise exception 'stale_version: concurrent update detected for ticket %', p_ticket_id using errcode = 'serialization_failure';
  end if;

  insert into app.ticket_events (tenant_id, ticket_id, event_type, from_value, to_value, actor_auth_user_id, actor_label)
  values (v_ticket.tenant_id, p_ticket_id, 'support_grant_linked', v_ticket.support_access_case_ref, v_normalized_ref, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_ticket.tenant_id, p_actor_auth_user_id, p_actor_label, 'link_helpdesk_support_grant',
    'app.tickets', p_ticket_id, 'success', null, app.ticket_audit_projection(v_ticket), app.ticket_audit_projection(v_updated)
  );

  return v_updated;
end;
$$;

comment on function app.link_helpdesk_support_grant is
  'HRT-288 (decision 7, the correlation-not-access-grant guarantee this whole migration is chartered to prove): sets/clears app.tickets.support_access_case_ref for DISPLAY ONLY, after verifying a real app.support_access_grants row exists for (tenant_id, case_id) -- ANY status (a past/expired/revoked grant may legitimately still be referenced for history), never required to be currently active. This function never touches app.support_access_grants/app.support_access_sessions beyond that one read-only existence check -- it cannot create, approve, start, extend, or revoke a grant or session. Live-adversarially proven in scripts/db-tests/ticketing-helpdesk.sql: linking a case ref confers zero tenant business-data access on its own, and an expired/revoked grant''s case_id still correlates for display without resurrecting access.';

-- ===========================================================================
-- 17. app.support_queues catalog CRUD (decisions 2/3) -- Supreme-Admin-only.
-- ===========================================================================

create function app.create_support_queue(p_code text, p_name text, p_description text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.support_queues
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_existing app.support_queues;
  v_queue app.support_queues;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if not app.is_supreme_admin(p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks Supreme Admin authority to manage support queues', p_actor_auth_user_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_code is null or length(trim(p_code)) = 0 then
    raise exception 'code_required: a non-empty code is required' using errcode = 'check_violation';
  end if;
  if p_name is null or length(trim(p_name)) = 0 then
    raise exception 'name_required: a non-empty name is required' using errcode = 'check_violation';
  end if;

  select * into v_existing from app.support_queues where code = p_code;
  if found then
    return v_existing;
  end if;

  begin
    insert into app.support_queues (code, name, description, created_by)
    values (p_code, p_name, p_description, p_actor_label)
    returning * into v_queue;
  exception
    when unique_violation then
      select * into v_queue from app.support_queues where code = p_code;
      if not found then
        raise;
      end if;
  end;

  perform app.capture_audit_event(null, p_actor_auth_user_id, p_actor_label, 'create_support_queue', 'app.support_queues', v_queue.id, 'success', null, null, jsonb_build_object('code', v_queue.code));

  return v_queue;
end;
$$;

create function app.list_support_queues(p_actor_auth_user_id uuid)
returns table (id uuid, code text, name text, description text, status text, record_version integer)
language plpgsql
security definer
set search_path = app, pg_temp
stable
as $$
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if not app.is_supreme_admin(p_actor_auth_user_id) then
    return;
  end if;
  return query
  select q.id, q.code, q.name, q.description, q.status, q.record_version
  from app.support_queues q
  order by q.code asc;
end;
$$;

-- ===========================================================================
-- 18. app.set_ticket_category_helpdesk_visibility -- mirrors app.
--     set_ticket_category_customer_visibility exactly (TKT:Edit-gated, the
--     TENANT's own authority over its own category catalog).
-- ===========================================================================

create function app.set_ticket_category_helpdesk_visibility(p_category_id uuid, p_helpdesk_visible boolean, p_actor_auth_user_id uuid, p_actor_label text)
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

  update app.ticket_categories set helpdesk_visible = p_helpdesk_visible
  where id = p_category_id
  returning * into v_updated;

  perform app.capture_audit_event(
    v_category.tenant_id, p_actor_auth_user_id, p_actor_label, 'set_ticket_category_helpdesk_visibility',
    'app.ticket_categories', v_updated.id, 'success', null,
    jsonb_build_object('helpdesk_visible', v_category.helpdesk_visible),
    jsonb_build_object('helpdesk_visible', v_updated.helpdesk_visible)
  );

  return v_updated;
end;
$$;

-- list_ticket_categories -- output widened with helpdesk_visible. Explicit
-- DROP+CREATE (output column list changes).
drop function if exists app.list_ticket_categories(uuid, uuid);

create function app.list_ticket_categories(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns table (id uuid, code text, name text, default_queue_id uuid, customer_visible boolean, helpdesk_visible boolean, status text, record_version integer)
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
  select c.id, c.code, c.name, c.default_queue_id, c.customer_visible, c.helpdesk_visible, c.status, c.record_version
  from app.ticket_categories c
  where c.tenant_id = p_tenant_id
  order by c.code asc;
end;
$$;

-- ===========================================================================
-- 19. Staff-facing read RPCs -- exclude a helpdesk-channel ticket for a
--     non-Supreme-Admin caller (decision 11), and convert the app.
--     ticket_queues JOIN to LEFT (decision 12). Same external
--     signatures/output columns; grants preserved by CREATE OR REPLACE.
-- ===========================================================================

create or replace function app.get_ticket(p_ticket_id uuid, p_actor_auth_user_id uuid)
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
  v_channel text;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if not app.can_access_ticket(p_ticket_id, p_actor_auth_user_id) then
    return;
  end if;

  select t0.tenant_id, t0.channel into v_tenant_id, v_channel from app.tickets t0 where t0.id = p_ticket_id;

  -- HRT-288 (decision 11): a helpdesk-channel ticket is only reachable
  -- through this staff projection by Supreme Admin -- everyone else,
  -- INCLUDING this ticket's own tenant-side requester party, is refused,
  -- forced through app.get_tenant_helpdesk_ticket instead.
  if v_channel = 'helpdesk' and not app.is_supreme_admin(p_actor_auth_user_id) then
    return;
  end if;

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
  left join app.ticket_queues q on q.id = t.queue_id
  left join app.employees re on re.master_record_id = t.requester_employee_id
  left join app.accounts ac on ac.id = t.requester_customer_account_id
  left join app.employees ae on ae.master_record_id = t.assignee_employee_id
  where t.id = p_ticket_id;
end;
$$;

create or replace function app.list_tickets(
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
  left join app.ticket_queues q on q.id = t.queue_id
  left join app.employees re on re.master_record_id = t.requester_employee_id
  left join app.accounts ac on ac.id = t.requester_customer_account_id
  left join app.employees ae on ae.master_record_id = t.assignee_employee_id
  where t.tenant_id = p_tenant_id
    and app.can_access_ticket(t.id, p_actor_auth_user_id)
    and (t.channel <> 'helpdesk' or app.is_supreme_admin(p_actor_auth_user_id))
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
  v_channel text;
  v_is_staff boolean;
  v_limit integer := least(greatest(coalesce(p_limit, 100), 1), 500);
  v_after_created_at timestamptz;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if not app.can_access_ticket(p_ticket_id, p_actor_auth_user_id) then
    return;
  end if;
  select t0.tenant_id, t0.channel into v_tenant_id, v_channel from app.tickets t0 where t0.id = p_ticket_id;
  if v_channel = 'helpdesk' and not app.is_supreme_admin(p_actor_auth_user_id) then
    return;
  end if;
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
  v_channel text;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if not app.can_access_ticket(p_ticket_id, p_actor_auth_user_id) then
    return;
  end if;
  select t0.tenant_id, t0.channel into v_tenant_id, v_channel from app.tickets t0 where t0.id = p_ticket_id;
  if v_channel = 'helpdesk' and not app.is_supreme_admin(p_actor_auth_user_id) then
    return;
  end if;
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
  v_channel text;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if not app.can_access_ticket(p_ticket_id, p_actor_auth_user_id) then
    return;
  end if;
  select t0.tenant_id, t0.channel into v_tenant_id, v_channel from app.tickets t0 where t0.id = p_ticket_id;
  if v_channel = 'helpdesk' and not app.is_supreme_admin(p_actor_auth_user_id) then
    return;
  end if;
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
    -- HRT-288 (decision 11, conservative bound consistent with this
    -- function's own established "conservative bound against bulk
    -- free-text leakage" posture): helpdesk-channel tickets are excluded
    -- from this tenant-scoped bulk export entirely -- app.
    -- list_platform_helpdesk_tickets is the dedicated cross-tenant Platform
    -- surface; app.list_tenant_helpdesk_tickets is the dedicated tenant-
    -- scoped one. Neither is a bulk CSV-style export in this bounded prompt
    -- (disclosed residual gap, matches this function's own precedent).
    and t.channel <> 'helpdesk'
  order by t.created_at asc;
end;
$$;

-- ===========================================================================
-- 20. Tenant-side helpdesk read RPCs (decisions 4/5/9/11) -- dedicated,
--     tenant-safe projections, mirroring the customer-channel read set
--     exactly. No queue_id/support_queue_id/assignee identity exposure.
-- ===========================================================================

create function app.list_helpdesk_ticket_categories(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns table (id uuid, code text, name text)
language plpgsql
security definer
set search_path = app, pg_temp
stable
as $$
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if not app._is_tenant_helpdesk_authorized(p_tenant_id, p_actor_auth_user_id) then
    return;
  end if;
  return query
  select c.id, c.code, c.name
  from app.ticket_categories c
  where c.tenant_id = p_tenant_id and c.status = 'active' and c.helpdesk_visible = true
  order by c.name asc;
end;
$$;

create function app.get_tenant_helpdesk_ticket(p_ticket_id uuid, p_actor_auth_user_id uuid)
returns table (
  id uuid, ticket_number text, subject text, status text, priority text,
  severity text, product_area text, environment text, external_reference text,
  category_name text,
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

  -- Anti-enumeration (mirrors app.get_customer_ticket exactly): the channel
  -- filter runs FIRST, before any scope check, so an internal/customer
  -- ticket id, another tenant's helpdesk ticket id, and a genuinely
  -- nonexistent id are all indistinguishable (zero rows) here.
  select * into v_ticket from app.tickets t0 where t0.id = p_ticket_id and t0.channel = 'helpdesk';
  if not found then
    return;
  end if;
  if not app.can_access_ticket(p_ticket_id, p_actor_auth_user_id) then
    return;
  end if;

  return query
  select t.id, t.ticket_number, t.subject, t.status, t.priority,
         t.severity, t.product_area, t.environment, t.external_reference,
         c.name,
         null::text,
         case when t.cancelled_reason_authored_by_customer then t.cancelled_reason else null end,
         case when t.last_reopen_reason_authored_by_customer then t.last_reopen_reason else null end,
         t.reopen_count, t.record_version,
         t.created_at, t.updated_at, t.resolved_at, t.closed_at
  from app.tickets t
  join app.ticket_categories c on c.id = t.category_id
  where t.id = p_ticket_id;
end;
$$;

comment on function app.get_tenant_helpdesk_ticket is
  'HRT-288 (decisions 4/9/11): the tenant-safe helpdesk projection -- deliberately excludes support_queue_id/support_queue_code (Platform-internal routing), assignee_support_auth_user_id (Platform staff identity), and support_access_case_ref (a governed correlation the tenant does not need and should not see, since it names a support-access grant reference). resolution_summary is ALWAYS null (staff-authored by construction, same discipline as app.get_customer_ticket); cancelled_reason/last_reopen_reason are returned ONLY when app.tickets.cancelled_reason_authored_by_customer/last_reopen_reason_authored_by_customer is true (i.e. the tenant''s own requester-side party authored that specific text, never a staff member''s internal rationale).';

create function app.list_tenant_helpdesk_tickets(p_tenant_id uuid, p_actor_auth_user_id uuid, p_status text, p_limit integer, p_after_id uuid)
returns table (id uuid, ticket_number text, subject text, status text, priority text, severity text, category_name text, record_version integer, created_at timestamptz, updated_at timestamptz)
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
  if not app._is_tenant_helpdesk_authorized(p_tenant_id, p_actor_auth_user_id) then
    return;
  end if;

  if p_after_id is not null then
    select t0.created_at into v_after_created_at from app.tickets t0 where t0.id = p_after_id;
  end if;

  return query
  select t.id, t.ticket_number, t.subject, t.status, t.priority, t.severity, c.name,
         t.record_version, t.created_at, t.updated_at
  from app.tickets t
  join app.ticket_categories c on c.id = t.category_id
  where t.tenant_id = p_tenant_id and t.channel = 'helpdesk'
    and (p_status is null or t.status = p_status)
    and (p_after_id is null or t.created_at < v_after_created_at or (t.created_at = v_after_created_at and t.id < p_after_id))
  order by t.created_at desc, t.id desc
  limit v_limit;
end;
$$;

create function app.list_tenant_helpdesk_ticket_messages(p_ticket_id uuid, p_actor_auth_user_id uuid, p_limit integer, p_after_id uuid)
returns table (id uuid, ticket_id uuid, body text, is_redacted boolean, attachment_file_ids uuid[], author_role text, author_display text, created_at timestamptz, record_version integer)
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

  select * into v_ticket from app.tickets t0 where t0.id = p_ticket_id and t0.channel = 'helpdesk';
  if not found then
    return;
  end if;
  if not app.can_access_ticket(p_ticket_id, p_actor_auth_user_id) then
    return;
  end if;

  if p_after_id is not null then
    select m0.created_at into v_after_created_at from app.ticket_messages m0 where m0.id = p_after_id;
  end if;

  -- Decision 5: visibility is hard-filtered to 'public' -- this function
  -- accepts no visibility parameter at all, so a Platform-internal note can
  -- never reach a tenant caller through this path structurally. A staff
  -- author's real identity is replaced with a fixed generic label
  -- ('CargoGrid Support').
  return query
  select m.id, m.ticket_id, m.body, m.is_redacted, m.attachment_file_ids,
         m.author_role,
         case when m.author_role = 'staff' then 'CargoGrid Support' else coalesce(m.author_label, 'You') end,
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
-- 21. Platform-side (Supreme-Admin-only) cross-tenant helpdesk queue reads
--     (decisions 2/3/7) -- the one deliberate cross-tenant read surface in
--     this migration, carefully bounded to channel='helpdesk' only.
-- ===========================================================================

create function app.list_platform_helpdesk_tickets(
  p_actor_auth_user_id uuid, p_status text, p_severity text, p_support_queue_id uuid, p_tenant_id uuid,
  p_limit integer, p_after_id uuid
)
returns table (
  id uuid, ticket_number text, tenant_id uuid, tenant_name text, subject text, status text, priority text,
  severity text, product_area text, support_queue_id uuid, support_queue_code text,
  assignee_support_auth_user_id uuid, assignee_email text, support_access_case_ref text,
  record_version integer, created_at timestamptz, updated_at timestamptz
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
  if not app.is_supreme_admin(p_actor_auth_user_id) then
    return;
  end if;

  if p_after_id is not null then
    select t0.created_at into v_after_created_at from app.tickets t0 where t0.id = p_after_id;
  end if;

  return query
  select t.id, t.ticket_number, t.tenant_id, tn.name, t.subject, t.status, t.priority,
         t.severity, t.product_area, t.support_queue_id, sq.code,
         t.assignee_support_auth_user_id, au.email, t.support_access_case_ref,
         t.record_version, t.created_at, t.updated_at
  from app.tickets t
  join app.tenants tn on tn.id = t.tenant_id
  left join app.support_queues sq on sq.id = t.support_queue_id
  left join auth.users au on au.id = t.assignee_support_auth_user_id
  where t.channel = 'helpdesk'
    and (p_status is null or t.status = p_status)
    and (p_severity is null or t.severity = p_severity)
    and (p_support_queue_id is null or t.support_queue_id = p_support_queue_id)
    and (p_tenant_id is null or t.tenant_id = p_tenant_id)
    and (p_after_id is null or t.created_at < v_after_created_at or (t.created_at = v_after_created_at and t.id < p_after_id))
  order by t.created_at desc, t.id desc
  limit v_limit;
end;
$$;

create function app.get_platform_helpdesk_ticket(p_ticket_id uuid, p_actor_auth_user_id uuid)
returns table (
  id uuid, ticket_number text, tenant_id uuid, tenant_name text, subject text, status text, priority text,
  severity text, product_area text, environment text, external_reference text,
  category_name text, support_queue_id uuid, support_queue_code text,
  assignee_support_auth_user_id uuid, assignee_email text,
  support_access_case_ref text, support_grant_status text, support_grant_expires_at timestamptz, support_grant_revoked_at timestamptz,
  resolution_summary text, cancelled_reason text, last_reopen_reason text, reopen_count integer,
  record_version integer, created_at timestamptz, updated_at timestamptz, resolved_at timestamptz, closed_at timestamptz
)
language plpgsql
security definer
set search_path = app, pg_temp
stable
as $$
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if not app.is_supreme_admin(p_actor_auth_user_id) then
    return;
  end if;

  return query
  select t.id, t.ticket_number, t.tenant_id, tn.name, t.subject, t.status, t.priority,
         t.severity, t.product_area, t.environment, t.external_reference,
         c.name, t.support_queue_id, sq.code,
         t.assignee_support_auth_user_id, au.email,
         t.support_access_case_ref, g.status, g.expires_at, g.revoked_at,
         t.resolution_summary, t.cancelled_reason, t.last_reopen_reason, t.reopen_count,
         t.record_version, t.created_at, t.updated_at, t.resolved_at, t.closed_at
  from app.tickets t
  join app.tenants tn on tn.id = t.tenant_id
  join app.ticket_categories c on c.id = t.category_id
  left join app.support_queues sq on sq.id = t.support_queue_id
  left join auth.users au on au.id = t.assignee_support_auth_user_id
  left join lateral (
    select g2.status, g2.expires_at, g2.revoked_at
    from app.support_access_grants g2
    where g2.tenant_id = t.tenant_id and g2.case_id = t.support_access_case_ref
    order by g2.requested_at desc
    limit 1
  ) g on t.support_access_case_ref is not null
  where t.id = p_ticket_id and t.channel = 'helpdesk';
end;
$$;

comment on function app.get_platform_helpdesk_ticket is
  'HRT-288 (decision 7): the Platform-side staff triage projection. support_grant_status/support_grant_expires_at/support_grant_revoked_at are a READ-ONLY LEFT JOIN correlation against app.support_access_grants (the LATEST grant, by requested_at, for this ticket''s own tenant_id+support_access_case_ref) -- display/audit only, never itself a source of access; a revoked or expired grant still correlates here (its real status/expiry is shown, never hidden), proving this join cannot be mistaken for a live access channel.';

-- ===========================================================================
-- 22. RLS -- narrow the four ticket-domain SELECT policies to exclude a
--     helpdesk-channel ticket for a non-Supreme-Admin actor (decision 11),
--     mirroring the already-established ATW-023/HRT-287 hardening precedent
--     exactly, but keyed on ticket.channel rather than actor layer (since
--     the SAME org_user/tenant_admin actor legitimately needs raw access to
--     their tenant's OWN internal-channel tickets).
-- ===========================================================================

create function app.ticket_channel_of(p_ticket_id uuid)
returns text
language sql
stable
security definer
set search_path = app, pg_temp
as $$
  select channel from app.tickets where id = p_ticket_id;
$$;

comment on function app.ticket_channel_of is
  'HRT-288: small RLS-support helper -- the channel of a given ticket id, used only by the ticket_messages/ticket_watchers/ticket_events SELECT policies below (which have no channel column of their own) to apply the same helpdesk exclusion app.tickets'' own policy applies directly.';

grant execute on function app.ticket_channel_of(uuid) to authenticated, service_role;

drop policy if exists tickets_select_scoped on app.tickets;
create policy tickets_select_scoped on app.tickets
  for select to authenticated
  using (
    (app.can_access_ticket(id) and not app.actor_holds_customer_user_layer(tenant_id) and channel <> 'helpdesk')
    or app.is_supreme_admin()
  );

drop policy if exists ticket_messages_select_scoped on app.ticket_messages;
create policy ticket_messages_select_scoped on app.ticket_messages
  for select to authenticated
  using (
    (app.can_access_ticket(ticket_id) and (visibility = 'public' or app.is_ticket_staff(ticket_id)) and not app.actor_holds_customer_user_layer(tenant_id) and app.ticket_channel_of(ticket_id) <> 'helpdesk')
    or app.is_supreme_admin()
  );

drop policy if exists ticket_watchers_select_scoped on app.ticket_watchers;
create policy ticket_watchers_select_scoped on app.ticket_watchers
  for select to authenticated
  using (
    (app.can_access_ticket(ticket_id) and not app.actor_holds_customer_user_layer(tenant_id) and app.ticket_channel_of(ticket_id) <> 'helpdesk')
    or app.is_supreme_admin()
  );

drop policy if exists ticket_events_select_scoped on app.ticket_events;
create policy ticket_events_select_scoped on app.ticket_events
  for select to authenticated
  using (
    (app.can_access_ticket(ticket_id) and not app.actor_holds_customer_user_layer(tenant_id) and app.ticket_channel_of(ticket_id) <> 'helpdesk')
    or app.is_supreme_admin()
  );

comment on policy tickets_select_scoped on app.tickets is
  'HRT-286/287/288: raw-table read is scoped by app.can_access_ticket, excludes a customer_user-layer actor entirely (HRT-287), and now ALSO excludes a helpdesk-channel ticket for a non-Supreme-Admin actor (HRT-288, decision 11) -- the ONLY sanctioned non-Supreme-Admin read path for a helpdesk ticket is the dedicated app.get_tenant_helpdesk_ticket/app.list_tenant_helpdesk_tickets RPCs, never a raw .from("tickets") call, even for the ticket''s own tenant-side requester party (who is otherwise correctly admitted by can_access_ticket).';

-- ===========================================================================
-- 23. Grants -- explicit, deliberate (never blanket), per this
--     repository's own standing convention.
-- ===========================================================================

revoke execute on all functions in schema app from public;

grant select on app.support_queues to authenticated;
grant select on app.support_queues to service_role;

grant execute on function app.create_support_queue(text, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.list_support_queues(uuid) to authenticated, service_role;

grant execute on function app.create_helpdesk_ticket(uuid, uuid, text, text, text, text, text, text, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.reply_to_helpdesk_ticket(uuid, text, uuid[], text, uuid, text) to authenticated, service_role;
grant execute on function app.assign_helpdesk_ticket(uuid, integer, uuid, uuid, text) to authenticated, service_role;
grant execute on function app.transfer_helpdesk_support_queue(uuid, integer, uuid, text, uuid, text) to authenticated, service_role;
grant execute on function app.update_helpdesk_ticket_classification(uuid, integer, uuid, text, text, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.link_helpdesk_support_grant(uuid, integer, text, uuid, text) to authenticated, service_role;

grant execute on function app.set_ticket_category_helpdesk_visibility(uuid, boolean, uuid, text) to authenticated, service_role;
grant execute on function app.list_ticket_categories(uuid, uuid) to authenticated, service_role;

grant execute on function app.list_helpdesk_ticket_categories(uuid, uuid) to authenticated, service_role;
grant execute on function app.get_tenant_helpdesk_ticket(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_tenant_helpdesk_tickets(uuid, uuid, text, integer, uuid) to authenticated, service_role;
grant execute on function app.list_tenant_helpdesk_ticket_messages(uuid, uuid, integer, uuid) to authenticated, service_role;

grant execute on function app.list_platform_helpdesk_tickets(uuid, text, text, uuid, uuid, integer, uuid) to authenticated, service_role;
grant execute on function app.get_platform_helpdesk_ticket(uuid, uuid) to authenticated, service_role;
