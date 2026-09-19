-- CG-AUDIT-2026-09-02 O1-query-layer remediation -- cluster 7
-- (page-level-direct-reads), the LAST cluster of the whole Ø1 defect.
--
-- Unlike clusters 0-6 (all server/queries/*.ts), every call site here is a raw
-- `.from()` read embedded DIRECTLY in a Server Component page.tsx, against
-- supabase/config.toml's un-exposed "app" schema -- so, exactly like every
-- prior cluster, these reads have NEVER worked in production (PostgREST maps
-- `.from("org_units")` etc. to the nonexistent `public.org_units`, not
-- `app.org_units`). Closes all 10 broken call sites across 6 files:
--
--   app/(tenant)/[tenantSlug]/hris/employees/[masterRecordId]/page.tsx:73   files
--   app/(tenant)/[tenantSlug]/hris/employees/[masterRecordId]/page.tsx:95   org_units
--   app/(tenant)/[tenantSlug]/hris/positions/[positionId]/page.tsx:51       org_units
--   app/(tenant)/[tenantSlug]/hris/positions/[positionId]/page.tsx:55       employee_position_assignments
--   app/(tenant)/[tenantSlug]/hris/positions/bulk-reassign/page.tsx:51      org_units
--   app/(tenant)/[tenantSlug]/hris/positions/page.tsx:39                   org_units
--   app/(tenant)/[tenantSlug]/hris/recruitment/applications/[applicationId]/page.tsx:72  job_offers
--   app/(tenant)/[tenantSlug]/operations/warehouses/[warehouseId]/locations/page.tsx:46   warehouse_locations
--   app/(tenant)/[tenantSlug]/procurement/approvals/[stepId]/page.tsx:26    approval_request_steps
--   app/(tenant)/[tenantSlug]/procurement/approvals/[stepId]/page.tsx:34    approval_requests
--
-- 7 new app.*/public.* Option-2 wrapper pairs (14 functions). The 5 org_units
-- call sites (all functionally identical -- a flat, optionally status/
-- unit_type-filtered picker list) share ONE new function, per the recon's own
-- explicit suggestion, a disclosed implementation choice this migration
-- adopts.
--
-- ===========================================================================
-- SECURITY POSTURE -- per function, independently re-derived rather than
-- copied uncritically from the recon's own suggested designs (2 of the 7
-- functions below deliberately depart from what the recon proposed; both
-- departures are disclosed in that function's own section)
-- ===========================================================================
--
-- 1. app.list_files_for_record -- SECURITY DEFINER, explicit actor (RULE A
--    applies). Mirrors app.list_files_for_tenant (20260831140000) exactly --
--    same per-row app.authorize_file_access('metadata_view', ...) audit-log
--    composition, same [1,200] clamp -- just scoped by (tenant_id,
--    record_type, record_id) instead of tenant_id alone. DEFINER is required
--    here (not a departure): the whole point of this table's own established
--    precedent is that a plain RLS read cannot write the per-row
--    app.file_access_logs entry a SELECT trigger cannot express.
--
-- 2. app.list_org_units -- SECURITY INVOKER, zero actor parameter. Recon
--    flagged this needing "its own authority check... must not hardcode
--    HRS:View" since its 5 call sites span 2 different domains (HRIS,
--    Ticketing). RULE B, fresh grep of both `create policy` and any later
--    `alter policy` for org_units_select_own_tenant -- exactly 2 hits total
--    (20260716105512 original, 20260730560000 current):
--      using (has_active_tenant_membership(tenant_id) and not
--             actor_holds_customer_user_layer(tenant_id));
--    -- "any active tenant member (non-customer-layer)" is EXACTLY the
--    domain-agnostic bar the recon asked for, already live and current. No
--    hand-rolled check needed; app.org_units' own full-row grant to
--    authenticated (never narrowed, confirmed via grep) makes plain
--    `select *` safe.
--
-- 3. app.list_position_incumbents -- SECURITY DEFINER, explicit actor (RULE A
--    applies). Mirrors the CURRENT (post-20260902041000 lineage-column fix)
--    app.get_employee_current_assignment / app.get_employee_position_
--    assignment_history bodies exactly: has_active_tenant_membership +
--    HRS:View, reason_note/decided_reason masked via
--    app.has_view_personal_data, source_import_staging_row_id projected
--    UNMASKED (import lineage metadata, not personal data -- same
--    established rationale). RULE C, live-verified: authenticated's grant on
--    app.employee_position_assignments is the SAME 21-column list
--    (20260731200000), still excluding reason_note/decided_reason AND
--    (confirmed via a fresh grep of every grant/revoke since) never updated
--    to include source_import_staging_row_id (the 24th column,
--    20260902040000) either -- this function selects the table's own full,
--    CURRENT 24-column shape positionally, casting source_import_staging_
--    row_id explicitly rather than assuming it is grantable, since a bare
--    `select *` here would fail outright even under SECURITY DEFINER's
--    elevated privilege the moment `returns setof
--    app.employee_position_assignments` tries to positionally match a query
--    that omits a column the composite type now has.
--
-- 4. app.get_job_offer_for_application -- SECURITY INVOKER, zero actor
--    parameter. DELIBERATE DEPARTURE from the recon's own suggestion (a
--    SECURITY DEFINER function delegating to app.can_view_job_offer's
--    HRS:View-or-eligible-approver-or-already-decided logic). Independently
--    re-derived: app.job_offers' OWN RLS policy (job_offers_select_scoped,
--    RULE B, exactly 1 hit, never altered) is
--      using (has_active_tenant_membership(tenant_id) and not
--             actor_holds_customer_user_layer(tenant_id) or is_supreme_admin());
--    -- plain tenant membership, which is STRICTLY BROADER than
--    can_view_job_offer's own HRS:View-first branch (every HRS:View holder is
--    necessarily an active tenant member; the converse is not required).
--    can_view_job_offer exists to gate a NARROWER surface (deciding a
--    specific pending step) that this read-only "does an offer exist yet"
--    lookup never needed in the first place -- confirmed by this exact query
--    file's own pre-existing page comment ("app.job_offers itself carries a
--    plain RLS-scoped authenticated SELECT grant (no PII, no masking
--    concern)"), which already correctly diagnosed the RLS boundary as
--    sufficient; only the schema-exposure defect (not the authority design)
--    was ever broken. app.job_offers' own grant to authenticated is
--    full-row (never narrowed) -- `select *` is safe.
--
-- 5. app.get_warehouse_location -- SECURITY DEFINER, explicit actor (RULE A
--    applies). Mirrors app.get_warehouse_location_deactivation_impact's own
--    authority chain exactly (both start from a location id, not a warehouse
--    id): location lookup -> parent warehouse lookup -> OPS:View ->
--    app.can_access_record via app.lead_record_scope_org_unit_ids on the
--    warehouse's own company_org_unit_id. `returns setof
--    app.warehouse_locations` (0 or 1 row), never a bare composite -- the
--    standing defect-class check this series has run on every batch.
--
-- 6. app.get_approval_request_step -- SECURITY INVOKER, zero actor
--    parameter. app.approval_request_steps' own full-row grant to
--    authenticated (11 columns, confirmed via a fresh grant/revoke grep --
--    never narrowed) makes plain `select *` safe, and this table's RLS
--    (approval_request_steps_select_scoped, RULE B, exactly 2 hits, current
--    text an EXISTS join to app.approval_requests reproducing that table's
--    own CURRENT predicate) is the exact SAME live, current predicate
--    app.list_approval_request_steps (cluster 6 batch 1,
--    20260913010000) already relies on for the SAME table -- this is that
--    same, already-proven-safe SECURITY INVOKER shape, merely keyed by step
--    id instead of request_id.
--
-- 7. app.get_approval_request_by_id -- SECURITY INVOKER, zero actor
--    parameter. DELIBERATE DEPARTURE from the recon's own suggestion (a
--    SECURITY DEFINER function delegating to app.check_approval_request_
--    authority, or a combined step+request function). RULE C, IMPORTANT:
--    app.check_approval_request_authority (20260719090000, never replaced)
--    was ALREADY independently found stale by cluster 0 batch 3
--    (20260909010000) -- it lacks the `AND NOT
--    actor_holds_customer_user_layer(...)` conjunct approval_requests_
--    select_scoped's own CURRENT text (20260730560000, RULE B re-confirmed
--    live here too) carries. Rather than call that stale helper (which
--    would silently reintroduce the exact customer_user-layer leak cluster 0
--    batch 3 already flagged), this function relies ENTIRELY on live,
--    CURRENT RLS instead -- the same "when a stale helper exists, trust the
--    CURRENT policy text over it" discipline cluster 0 batch 3's own
--    app.get_approval_requests_entity_refs already established for this
--    identical table. authenticated's grant on app.approval_requests is
--    column-restricted to 15 of 16 columns (20260731210000), excluding
--    ended_reason (a free-text cancellation/rejection narrative) -- this
--    function selects those exact 15 columns, casting ended_reason to
--    `null::text` in its correct physical position (13th of 16), the
--    standing column-privilege-restriction discipline this series applies
--    on every batch. Kept as a SEPARATE function from app.get_approval_
--    request_step (not combined, despite the recon floating that as an
--    option) -- each table has its own distinct grant/RLS shape (steps:
--    full-row + EXISTS-join RLS; requests: column-restricted + direct RLS),
--    so one function per table stays the simpler, more legible design; the
--    TS caller (the one real call site) issues both RPCs, exactly as the
--    original code issued both `.from()` reads.
--
-- RULE A applies to functions 1, 3 and 5 (explicit actor parameter, granted
-- to authenticated): each calls `perform
-- app.assert_actor_is_session_identity(p_actor_auth_user_id);` as the first
-- executable statement. It does not apply to functions 2, 4, 6, 7 (zero
-- actor parameter, SECURITY INVOKER, live RLS is the entire authority
-- surface).

-- ---------------------------------------------------------------------------
-- 1. app.list_files_for_record -- replaces app/(tenant)/[tenantSlug]/hris/
--    employees/[masterRecordId]/page.tsx:73
-- ---------------------------------------------------------------------------
create function app.list_files_for_record(
  p_tenant_id uuid,
  p_record_type text,
  p_record_id uuid,
  p_actor_auth_user_id uuid,
  p_correlation_id uuid default null,
  p_limit integer default 200
)
returns setof app.files
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_file app.files;
  v_returned integer := 0;
  v_limit integer := least(greatest(coalesce(p_limit, 200), 1), 200);
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'document_listing_unauthorized: identity % has no active membership in tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  for v_file in
    select f.* from app.files f
    where f.tenant_id = p_tenant_id and f.record_type = p_record_type and f.record_id = p_record_id
    order by f.created_at desc, f.id
  loop
    exit when v_returned >= v_limit;

    begin
      perform app.authorize_file_access(v_file.id, 'metadata_view', p_actor_auth_user_id, p_correlation_id);
    exception
      when insufficient_privilege then continue;
      when no_data_found then continue;
    end;
    v_returned := v_returned + 1;
    return next v_file;
  end loop;
end;
$$;

comment on function app.list_files_for_record(uuid, text, uuid, uuid, uuid, integer) is
  'O1 remediation, cluster 7: one record''s own attachments, replacing app/(tenant)/[tenantSlug]/hris/employees/[masterRecordId]/page.tsx:73''s broken 26-column .from("files") read (app is not exposed to PostgREST). Mirrors app.list_files_for_tenant (20260831140000) exactly, scoped by (tenant_id, record_type, record_id) instead of tenant_id alone -- same per-row app.authorize_file_access(''metadata_view'') composition (so every row returned still leaves a real app.file_access_logs entry) and the same [1,200] clamp.';

create function public.list_files_for_record(
  p_tenant_id uuid,
  p_record_type text,
  p_record_id uuid,
  p_actor_auth_user_id uuid,
  p_correlation_id uuid default null,
  p_limit integer default 200
)
returns setof app.files
language sql
security definer
set search_path = app, public, pg_temp
as $wrap$
  select * from app.list_files_for_record(p_tenant_id, p_record_type, p_record_id, p_actor_auth_user_id, p_correlation_id, p_limit);
$wrap$;

comment on function public.list_files_for_record(uuid, text, uuid, uuid, uuid, integer) is
  'Option-2 wrapper: app is not exposed to PostgREST; a thin security-definer pass-through to app.list_files_for_record, never a reimplementation.';

revoke execute on function app.list_files_for_record(uuid, text, uuid, uuid, uuid, integer) from public;
grant execute on function app.list_files_for_record(uuid, text, uuid, uuid, uuid, integer) to authenticated, service_role;

revoke execute on function public.list_files_for_record(uuid, text, uuid, uuid, uuid, integer) from anon, authenticated, service_role, public;
grant execute on function public.list_files_for_record(uuid, text, uuid, uuid, uuid, integer) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 2. app.list_org_units -- replaces 5 identical/near-identical call sites:
--    hris/employees/[masterRecordId]/page.tsx:95,
--    hris/positions/[positionId]/page.tsx:51,
--    hris/positions/bulk-reassign/page.tsx:51,
--    hris/positions/page.tsx:39
-- ---------------------------------------------------------------------------
create function app.list_org_units(
  p_tenant_id uuid,
  p_status_filter text default null,
  p_unit_type_filter text default null
)
returns setof app.org_units
language sql
stable
as $$
  select * from app.org_units
  where tenant_id = p_tenant_id
    and (p_status_filter is null or status = p_status_filter)
    and (p_unit_type_filter is null or unit_type = p_unit_type_filter)
  order by name asc;
$$;

comment on function app.list_org_units(uuid, text, text) is
  'O1 remediation, cluster 7: a flat, optionally status/unit_type-filtered org-unit picker list, replacing 5 identical/near-identical broken .from("org_units").select("id, name, unit_type")... reads across hris/employees/[masterRecordId], hris/positions/[positionId], hris/positions/bulk-reassign and hris/positions pages (app is not exposed to PostgREST). Security invoker, zero actor parameter -- relies on the calling role''s own live RLS evaluation of org_units_select_own_tenant, CURRENT text (RULE B, only ever one CREATE POLICY plus one ALTER POLICY, no is_supreme_admin() disjunct at the policy level): `has_active_tenant_membership(tenant_id) AND NOT actor_holds_customer_user_layer(tenant_id)` -- domain-agnostic ("any active tenant member"), matching every one of this function''s 5 call sites'' own access guard regardless of which domain (HRIS, Ticketing) resolved it. app.org_units'' own grant to authenticated is full-row (never narrowed) -- `select *` is safe.';

create function public.list_org_units(
  p_tenant_id uuid,
  p_status_filter text default null,
  p_unit_type_filter text default null
)
returns setof app.org_units
language sql
stable
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.list_org_units(p_tenant_id, p_status_filter, p_unit_type_filter);
$wrap$;

comment on function public.list_org_units(uuid, text, text) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin pass-through to app.list_org_units with an identical grant set and an identical security mode (invoker), never a reimplementation.';

revoke execute on function app.list_org_units(uuid, text, text) from public;
grant execute on function app.list_org_units(uuid, text, text) to authenticated, service_role;

revoke execute on function public.list_org_units(uuid, text, text) from anon, authenticated, service_role, public;
grant execute on function public.list_org_units(uuid, text, text) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 3. app.list_position_incumbents -- replaces hris/positions/[positionId]/
--    page.tsx:55
-- ---------------------------------------------------------------------------
create function app.list_position_incumbents(p_position_id uuid, p_actor_auth_user_id uuid)
returns setof app.employee_position_assignments
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_position app.positions;
  v_unmasked boolean;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_position from app.positions p where p.id = p_position_id;
  if not found or not app.has_active_tenant_membership(v_position.tenant_id, p_actor_auth_user_id) then
    raise exception 'position_not_found: %', p_position_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_position.tenant_id, 'HRS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_position.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_unmasked := app.has_view_personal_data(v_position.tenant_id, p_actor_auth_user_id);

  return query
  select
    a.id, a.tenant_id, a.master_record_id, a.position_id, a.grade_id, a.manager_employee_id, a.assignment_type, a.allocation_pct,
    a.effective_start_date, a.effective_end_date, a.validity_range, a.status, a.change_reason,
    case when v_unmasked then a.reason_note else null end,
    a.previous_assignment_id, a.source_config_version_id, a.decided_by, a.decided_at,
    case when v_unmasked then a.decided_reason else null end,
    a.record_version, a.created_by, a.created_at, a.updated_at, a.source_import_staging_row_id
  from app.employee_position_assignments a
  where a.position_id = p_position_id and a.status = 'active'
  order by a.effective_start_date desc;
end;
$$;

comment on function app.list_position_incumbents(uuid, uuid) is
  'O1 remediation, cluster 7: the active incumbents (current holders) of one position, replacing hris/positions/[positionId]/page.tsx:55''s broken 18-column .from("employee_position_assignments").eq("position_id", ...).eq("status", "active") read (app is not exposed to PostgREST). Mirrors the CURRENT (post-20260902041000 lineage-column fix) app.get_employee_current_assignment / app.get_employee_position_assignment_history bodies exactly: has_active_tenant_membership + HRS:View, reason_note/decided_reason masked via app.has_view_personal_data, source_import_staging_row_id projected UNMASKED (import lineage metadata, not personal data). RULE C: authenticated''s grant on this table is the SAME 21-column list from 20260731200000, still excluding reason_note/decided_reason, and was never updated for source_import_staging_row_id (the table''s 24th column, added by 20260902040000) either -- this function projects the table''s own full, CURRENT 24-column positional shape explicitly rather than assuming any column is grantable, the standing column-privilege/positional-matching discipline this series applies on every batch.';

create function public.list_position_incumbents(p_position_id uuid, p_actor_auth_user_id uuid)
returns setof app.employee_position_assignments
language sql
stable
security definer
set search_path = app, public, pg_temp
as $wrap$
  select * from app.list_position_incumbents(p_position_id, p_actor_auth_user_id);
$wrap$;

comment on function public.list_position_incumbents(uuid, uuid) is
  'Option-2 wrapper: app is not exposed to PostgREST; a thin security-definer pass-through to app.list_position_incumbents, never a reimplementation.';

revoke execute on function app.list_position_incumbents(uuid, uuid) from public;
grant execute on function app.list_position_incumbents(uuid, uuid) to authenticated, service_role;

revoke execute on function public.list_position_incumbents(uuid, uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_position_incumbents(uuid, uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 4. app.get_job_offer_for_application -- replaces hris/recruitment/
--    applications/[applicationId]/page.tsx:72
-- ---------------------------------------------------------------------------
create function app.get_job_offer_for_application(p_application_id uuid)
returns setof app.job_offers
language sql
stable
as $$
  select * from app.job_offers where application_id = p_application_id;
$$;

comment on function app.get_job_offer_for_application(uuid) is
  'O1 remediation, cluster 7: the (0 or 1, application_id is unique) offer for one application -- most applications have no offer yet, so a genuinely empty result is the normal case, never an error. Replaces hris/recruitment/applications/[applicationId]/page.tsx:72''s broken .from("job_offers").eq("application_id", ...).maybeSingle() read (app is not exposed to PostgREST). Security invoker, zero actor parameter -- DELIBERATE DEPARTURE from delegating to app.can_view_job_offer (the recon''s own suggestion): app.job_offers'' own RLS (job_offers_select_scoped, RULE B, never altered) is plain tenant membership, which is STRICTLY BROADER than can_view_job_offer''s own HRS:View-first branch (every HRS:View holder is already an active tenant member) -- can_view_job_offer exists to gate a narrower surface (deciding one pending step) this read-only lookup never needed. `returns setof app.job_offers`, never a bare composite.';

create function public.get_job_offer_for_application(p_application_id uuid)
returns setof app.job_offers
language sql
stable
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.get_job_offer_for_application(p_application_id);
$wrap$;

comment on function public.get_job_offer_for_application(uuid) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin pass-through to app.get_job_offer_for_application with an identical grant set and an identical security mode (invoker), never a reimplementation.';

revoke execute on function app.get_job_offer_for_application(uuid) from public;
grant execute on function app.get_job_offer_for_application(uuid) to authenticated, service_role;

revoke execute on function public.get_job_offer_for_application(uuid) from anon, authenticated, service_role, public;
grant execute on function public.get_job_offer_for_application(uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 5. app.get_warehouse_location -- replaces operations/warehouses/
--    [warehouseId]/locations/page.tsx:46
-- ---------------------------------------------------------------------------
create function app.get_warehouse_location(p_location_id uuid, p_actor_auth_user_id uuid)
returns setof app.warehouse_locations
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_location app.warehouse_locations;
  v_warehouse app.warehouses;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_location from app.warehouse_locations where id = p_location_id;
  if not found then
    return;
  end if;
  select * into v_warehouse from app.warehouses where id = v_location.warehouse_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_location.tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_location.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_location.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot view location %', p_actor_auth_user_id, p_location_id using errcode = 'insufficient_privilege';
  end if;

  return next v_location;
end;
$$;

comment on function app.get_warehouse_location(uuid, uuid) is
  'O1 remediation, cluster 7: one warehouse location by id (the ?parent= breadcrumb lookup), replacing operations/warehouses/[warehouseId]/locations/page.tsx:46''s broken .from("warehouse_locations").eq("id", parent).maybeSingle() read (app is not exposed to PostgREST). Mirrors app.get_warehouse_location_deactivation_impact''s own authority chain exactly (location -> parent warehouse -> OPS:View -> app.can_access_record via app.lead_record_scope_org_unit_ids on the warehouse''s own company_org_unit_id) -- the identical "start from a location id, not a warehouse id" shape. A nonexistent location id returns a genuinely empty result (never raises); an authority failure on a real row still raises insufficient_authority, matching every sibling function on this table. `returns setof app.warehouse_locations`, never a bare composite.';

create function public.get_warehouse_location(p_location_id uuid, p_actor_auth_user_id uuid)
returns setof app.warehouse_locations
language sql
stable
security definer
set search_path = app, public, pg_temp
as $wrap$
  select * from app.get_warehouse_location(p_location_id, p_actor_auth_user_id);
$wrap$;

comment on function public.get_warehouse_location(uuid, uuid) is
  'Option-2 wrapper: app is not exposed to PostgREST; a thin security-definer pass-through to app.get_warehouse_location, never a reimplementation.';

revoke execute on function app.get_warehouse_location(uuid, uuid) from public;
grant execute on function app.get_warehouse_location(uuid, uuid) to authenticated, service_role;

revoke execute on function public.get_warehouse_location(uuid, uuid) from anon, authenticated, service_role, public;
grant execute on function public.get_warehouse_location(uuid, uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 6. app.get_approval_request_step -- replaces procurement/approvals/
--    [stepId]/page.tsx:26
-- ---------------------------------------------------------------------------
create function app.get_approval_request_step(p_step_id uuid)
returns setof app.approval_request_steps
language sql
stable
as $$
  select * from app.approval_request_steps where id = p_step_id;
$$;

comment on function app.get_approval_request_step(uuid) is
  'O1 remediation, cluster 7: one approval step by id, replacing procurement/approvals/[stepId]/page.tsx:26''s broken .from("approval_request_steps").eq("id", stepId).maybeSingle() read (app is not exposed to PostgREST). Security invoker, zero actor parameter -- relies on the calling role''s own live RLS evaluation of approval_request_steps_select_scoped, CURRENT text (RULE B, 2 hits, current): an EXISTS join to app.approval_requests requiring `(has_active_tenant_membership(r.tenant_id) AND NOT actor_holds_customer_user_layer(r.tenant_id)) OR is_supreme_admin()` against the PARENT row''s own tenant_id -- the identical, already-proven-safe shape app.list_approval_request_steps (cluster 6 batch 1) already established for this SAME table, merely keyed by step id instead of request_id. app.approval_request_steps'' own grant to authenticated is full-row (11 columns, never narrowed) -- `select *` is safe. `returns setof app.approval_request_steps`, never a bare composite.';

create function public.get_approval_request_step(p_step_id uuid)
returns setof app.approval_request_steps
language sql
stable
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.get_approval_request_step(p_step_id);
$wrap$;

comment on function public.get_approval_request_step(uuid) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin pass-through to app.get_approval_request_step with an identical grant set and an identical security mode (invoker), never a reimplementation.';

revoke execute on function app.get_approval_request_step(uuid) from public;
grant execute on function app.get_approval_request_step(uuid) to authenticated, service_role;

revoke execute on function public.get_approval_request_step(uuid) from anon, authenticated, service_role, public;
grant execute on function public.get_approval_request_step(uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 7. app.get_approval_request_by_id -- replaces procurement/approvals/
--    [stepId]/page.tsx:34
-- ---------------------------------------------------------------------------
create function app.get_approval_request_by_id(p_request_id uuid)
returns setof app.approval_requests
language sql
stable
as $$
  select
    id, tenant_id, config_version_id, entity_type, entity_id, pattern, status, idempotency_key,
    requested_by_auth_user_id, requested_by, started_at, ended_at, null::text as ended_reason,
    record_version, created_at, updated_at
  from app.approval_requests
  where id = p_request_id;
$$;

comment on function app.get_approval_request_by_id(uuid) is
  'O1 remediation, cluster 7: one approval request by id, replacing procurement/approvals/[stepId]/page.tsx:34''s broken .from("approval_requests").eq("id", stepRow.request_id).maybeSingle() read (app is not exposed to PostgREST). Security invoker, zero actor parameter -- DELIBERATE DEPARTURE from delegating to app.check_approval_request_authority (the recon''s own suggestion): that helper (20260719090000, never replaced) was ALREADY independently found stale by cluster 0 batch 3 (20260909010000) -- it lacks the `AND NOT actor_holds_customer_user_layer(...)` conjunct approval_requests_select_scoped''s own CURRENT text (RULE B, re-confirmed live here) carries, so calling it would silently reintroduce that exact leak into brand-new code. This function relies entirely on live, CURRENT RLS instead -- `(has_active_tenant_membership(tenant_id) AND NOT actor_holds_customer_user_layer(tenant_id)) OR is_supreme_admin()`. authenticated''s grant on app.approval_requests is column-restricted to 15 of 16 columns (20260731210000), excluding ended_reason -- selected here as an explicit 16-column positional list with ended_reason cast to `null::text` in its correct (13th) position, the standing column-privilege/positional-matching discipline this series applies on every batch. Kept separate from app.get_approval_request_step (not combined into one function) -- each table has its own distinct grant/RLS shape, so one function per table is the simpler design; the one real call site issues both RPCs, exactly as the original code issued both `.from()` reads.';

create function public.get_approval_request_by_id(p_request_id uuid)
returns setof app.approval_requests
language sql
stable
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.get_approval_request_by_id(p_request_id);
$wrap$;

comment on function public.get_approval_request_by_id(uuid) is
  'Option-2 wrapper: app is not exposed to PostgREST; this is a thin pass-through to app.get_approval_request_by_id with an identical grant set and an identical security mode (invoker), never a reimplementation.';

revoke execute on function app.get_approval_request_by_id(uuid) from public;
grant execute on function app.get_approval_request_by_id(uuid) to authenticated, service_role;

revoke execute on function public.get_approval_request_by_id(uuid) from anon, authenticated, service_role, public;
grant execute on function public.get_approval_request_by_id(uuid) to authenticated, service_role;

-- ===========================================================================
-- TS INTEGRATION
-- ===========================================================================
--
-- server/queries/document.ts: new export listFilesForRecord(client, tenantId,
-- recordType, recordId, actorAuthUserId, correlationId?) -> BoundedList<FileSummary>,
-- calling client.rpc("list_files_for_record", { p_tenant_id, p_record_type,
-- p_record_id, p_actor_auth_user_id, p_correlation_id, p_limit: BOUNDED_LIST_LIMIT }),
-- mirroring listFilesForTenant exactly (toBoundedListByCapReached).
--
-- server/queries/org-hierarchy.ts: new export listOrgUnits(client, tenantId,
-- options?) -> OrgUnitSummary[] ({id, name, unitType}), calling
-- client.rpc("list_org_units", { p_tenant_id, p_status_filter, p_unit_type_filter }).
--
-- server/queries/position.ts: new export listPositionIncumbents(client,
-- positionId, actorAuthUserId) -> EmployeePositionAssignment[], calling
-- client.rpc("list_position_incumbents", { p_position_id, p_actor_auth_user_id }).
--
-- server/queries/recruitment.ts: new export getJobOfferForApplication(client,
-- applicationId) -> JobOffer | null, calling client.rpc("get_job_offer_for_application",
-- { p_application_id }), unwrapping data[0] via parseJobOffer.
--
-- server/queries/bin-racking.ts: new export getWarehouseLocation(client,
-- locationId, actorAuthUserId) -> WarehouseLocation | null, calling
-- client.rpc("get_warehouse_location", { p_location_id, p_actor_auth_user_id }),
-- unwrapping data[0] via parseWarehouseLocation.
--
-- server/queries/approval.ts: two new exports, getApprovalRequestStep(client,
-- stepId) -> ApprovalRequestStep | null and getApprovalRequestById(client,
-- requestId) -> ApprovalRequest | null, calling client.rpc("get_approval_request_step",
-- { p_step_id }) / client.rpc("get_approval_request_by_id", { p_request_id }).
--
-- All 6 page.tsx files updated to call the new query functions instead of
-- their own raw `.from()` reads, keeping every existing catch/notFound/
-- PermissionState/ErrorState branch behavior unchanged.
