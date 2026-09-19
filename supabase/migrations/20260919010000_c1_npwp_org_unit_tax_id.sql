-- CG-AUDIT-2026-09-02 C1 (bounded core): "No NPWP on tenant/org unit; no
-- faktur pajak/NSFP/e-Faktur at all" -- carried as one undivided
-- DEFERRED_LARGE item ("compliance-domain modeling, needs a tax SME") and
-- never itself independently re-verified since.
--
-- A dedicated research pass, the same "verify before trusting a deferred
-- label" discipline that found B7's/B2a's/E6's/B4's/A2b's/E3's own real
-- bounded cores, found C1 bundles two very different kinds of work:
--
--   * Faktur pajak/NSFP/e-Faktur generation is confirmed absent code-wide
--     (zero hits for "faktur"/"NSFP"/"efaktur" anywhere in server/, app/,
--     supabase/migrations/, scripts/ beyond comments already disclosing the
--     gap) and genuinely requires real tax-SME judgment (NSFP government-
--     allocated numbering, DJP e-Faktur export format, PPh21 PTKP/bracket
--     rates -- C2's own already-correctly-deferred scope, mirrored by app.
--     payroll_components' own "EXAMPLE FIXTURE VERSIONS ARE NOT VERIFIED
--     RATES" fixture comment). Stays DEFERRED_LARGE, untouched by this
--     migration.
--
--   * NPWP-as-a-data-field, by contrast, needs zero tax expertise -- it is
--     exactly as bounded as any other master-data identifier column.
--     app.accounts.tax_id has existed since `20260724290000_create_
--     commercial_customer_account_conversion.sql` as unvalidated free
--     text (no format/regex check), used today for every Commercial
--     customer/vendor account and already correctly printed as "Bill to
--     Tax ID" on this session's own A7 invoice PDF (server/documents/
--     generate-invoice.server.ts, billToTaxId). But the TENANT'S OWN tax
--     ID -- the "Seller Tax ID" every outgoing invoice/purchase order
--     needs to print -- was never captured anywhere: app.tenants (Supreme-
--     Admin-only control plane, no tenant self-service) and app.org_units
--     (PLT-109, the tenant-scoped legal-entity hierarchy company/branch/
--     department/business_unit -- the correct home, since app.finance_
--     invoices.company_id/app.purchase_orders.org_unit_id already
--     reference it) both have no npwp/tax_id column at all, confirmed by a
--     full-migration-history grep of every ALTER on either table. The
--     invoice PDF genuinely has a blank line where "Seller Tax ID" should
--     print -- a real, visible, currently-shipped defect, independent of
--     whether full e-Faktur compliance is ever built. `admin/tax-settings/`
--     (RPD-016) already establishes the right posture for this class of
--     gap in this same codebase: infrastructure to hold a number an SME/
--     the tenant already knows, stored as-is, no validation logic invented
--     ahead of a real requirement.
--
-- Fix: app.org_units gains a nullable tax_id column (unvalidated free
-- text, mirroring app.accounts.tax_id's own precedent exactly -- storing
-- it is not a risky shortcut, it is the same posture this codebase already
-- uses for the identical identifier type). A new app.set_org_unit_tax_id
-- RPC mirrors app.rename_org_unit's own exact shape (service_role-only,
-- no authority check in its own body -- consistent with every other
-- org_units mutation RPC in this family, whose real authority gate is
-- lib/portal/resolve-tenant-admin-access.server.ts at the Server Action
-- layer, "the explicit actor, service-role execution pattern every other
-- privileged mutation in this repository already follows" per this
-- family's own existing header comment) -- optimistic concurrency, a new
-- org_unit_history 'tax_id_change' event. app.list_org_units already
-- returns `select *` (full-row, never narrowed, its own header's own
-- words) so the new column flows through automatically with zero RPC
-- signature change there.
--
-- The TS/UI blast radius: server/contracts/org-hierarchy/org-hierarchy.ts
-- (taxId field + SetOrgUnitTaxIdInputSchema), server/mutations/org-
-- hierarchy.ts (setOrgUnitTaxId wrapper) -- admin/organization/ (audit
-- remediation A2's own org-unit master-data UI) gains a "Tax ID" column
-- with an inline edit form, mirroring the existing Rename column's own
-- shape exactly. server/documents/generate-invoice.server.ts and
-- generate-purchase-order.server.ts (both A7 printables that already
-- reference an org unit via company_id/orgUnitId) now resolve that org
-- unit's own tax_id via the already-existing, already-`authenticated`-
-- callable app.list_org_units and print it as "Seller Tax ID" -- no new
-- RPC needed for the read side, reusing list_org_units rather than adding
-- a narrower get-by-id RPC purely for this one lookup.

alter table app.org_units add column tax_id text;

comment on column app.org_units.tax_id is
  'CG-AUDIT-2026-09-02 C1: the legal entity''s own NPWP (or other jurisdiction tax ID), unvalidated free text -- mirrors app.accounts.tax_id''s own precedent exactly (no format/regex check; this codebase''s established posture for this identifier class). Nullable: most org units, and every pre-existing one, have none captured yet.';

alter table app.org_unit_history add column before_tax_id text;
alter table app.org_unit_history add column after_tax_id text;

alter table app.org_unit_history drop constraint org_unit_history_event_type_check;
alter table app.org_unit_history add constraint org_unit_history_event_type_check
  check (event_type in ('create', 'move', 'rename', 'status_change', 'tax_id_change'));

-- ===========================================================================
-- app.set_org_unit_tax_id -- mirrors app.rename_org_unit's own exact shape
-- ===========================================================================

create function app.set_org_unit_tax_id(
  p_id uuid,
  p_new_tax_id text,
  p_expected_version integer,
  p_requested_by text
)
returns app.org_units
language plpgsql
as $$
declare
  v_current app.org_units;
  v_updated app.org_units;
begin
  select * into v_current from app.org_units where id = p_id for update;
  if not found then
    raise exception 'org_unit_not_found: no org unit %', p_id
      using errcode = 'no_data_found';
  end if;

  if v_current.record_version <> p_expected_version then
    raise exception 'org_unit_version_conflict: expected version %, found %', p_expected_version, v_current.record_version
      using errcode = 'check_violation';
  end if;

  update app.org_units set tax_id = p_new_tax_id where id = p_id returning * into v_updated;

  insert into app.org_unit_history (org_unit_id, tenant_id, event_type, before_tax_id, after_tax_id, requested_by)
  values (p_id, v_current.tenant_id, 'tax_id_change', v_current.tax_id, p_new_tax_id, p_requested_by);

  return v_updated;
end;
$$;

comment on function app.set_org_unit_tax_id is
  'CG-AUDIT-2026-09-02 C1: sets an org unit''s own tax_id (unvalidated free text). Mirrors app.rename_org_unit exactly -- optimistic concurrency (org_unit_version_conflict), an org_unit_history ''tax_id_change'' event, no authority check in its own body (service_role-only grant, consistent with every sibling in this RPC family -- the real authority gate is the calling Server Action''s own lib/portal/resolve-tenant-admin-access.server.ts guard).';

revoke execute on function app.set_org_unit_tax_id(uuid, text, integer, text) from public;
grant execute on function app.set_org_unit_tax_id(uuid, text, integer, text) to service_role;

-- ===========================================================================
-- RGL-394 Option-2 public.* wrapper -- mirrors public.rename_org_unit's own
-- exact shape (security invoker, service_role-only, matching the app.*
-- function's own invoker mode)
-- ===========================================================================

create function public.set_org_unit_tax_id(p_id uuid, p_new_tax_id text, p_expected_version integer, p_requested_by text)
returns app.org_units
language sql
volatile
set search_path = pg_catalog, pg_temp
as $wrap$
  select app.set_org_unit_tax_id(p_id, p_new_tax_id, p_expected_version, p_requested_by);
$wrap$;

comment on function public.set_org_unit_tax_id(p_id uuid, p_new_tax_id text, p_expected_version integer, p_requested_by text) is
  'RGL-394 Option-2 wrapper: app is not exposed to PostgREST; this is a thin pass-through to app.set_org_unit_tax_id with an identical grant set and an identical security mode (invoker), never a reimplementation. See docs/build-log/release-go-live/RGL-394.md.';

-- ERR-2026-004: a fresh CREATE FUNCTION in schema public silently inherits the
-- platform-level "ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
-- GRANT EXECUTE ON FUNCTIONS TO anon, authenticated, service_role" rule --
-- revoking from public alone does not undo the anon/authenticated portion of
-- that default. Explicit, directly-provable revoke of all four before the
-- real, narrower re-grant below.
revoke execute on function public.set_org_unit_tax_id(p_id uuid, p_new_tax_id text, p_expected_version integer, p_requested_by text) from anon, authenticated, service_role, public;
grant execute on function public.set_org_unit_tax_id(p_id uuid, p_new_tax_id text, p_expected_version integer, p_requested_by text) to service_role;
