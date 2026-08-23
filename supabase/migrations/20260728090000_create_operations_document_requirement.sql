-- Operations capability OPS-176 (Document Requirement, CG-S8-OPS-010)
-- Versioned shipment document requirements (by mode/service/status/party) plus a
-- pinned per-shipment checklist and a private upload/link/review lifecycle layered on
-- top of the existing Platform Document/File Engine (PLT-128, app.files/app.document_types)
-- (Prompt 176 §4/§20).
--
-- Scope and design decisions, disclosed rather than left implicit:
--
-- * **This capability never re-implements file storage, malware scanning, or the
--   private/signed-URL access gate** -- all of that is PLT-128's own job
--   (app.files/app.initiate_file_upload/app.authorize_file_access), already shipped.
--   This migration owns exactly one new thing: *which* document type is required, for
--   *which* shipment, and the *review* verdict once a file has been linked. A checklist
--   item never stores file bytes or a scan result of its own -- it references
--   app.files.id and re-reads that row's own malware_scan_status live, the same
--   "single source of truth, never a second copy that could drift" discipline this
--   session applies everywhere (Job Order's customer_snapshot is the one disclosed
--   counter-example, and even that is an explicit governed snapshot, not silent drift).
-- * **Requirement definitions are versioned, tenant-scoped draft -> published -> archived
--   rows**, one active match per (tenant_id, mode, service_type, applicable_status,
--   party, document_type_code) -- the same considered choice OPS-173/174 already made
--   (a directly tenant-scoped versioned-definition table, not Configuration Engine,
--   whose precedence dimensions do not fit "by mode/service/status/party" any better
--   than they fit those two capabilities' own dimensions). mode/service_type are
--   nullable wildcards (null matches any shipment's mode/service_type) so a tenant can
--   define a requirement that applies regardless of mode (e.g. an invoice) without
--   enumerating every mode explicitly.
-- * **The checklist is pinned once, re-synced only on explicit request** (§24: "active
--   shipment keeps its snapshot unless explicit reevaluation occurs"). app.pin_shipment_
--   document_checklist_items is additive-only -- inserting rows for any currently-
--   published requirement not yet pinned to the shipment, never removing or overwriting
--   an already-pinned row, mirroring OPS-175's own "readiness recheck never mutates
--   history" posture.
-- * **A rejected/expired document is replaced, never deleted** (§22): app.link_document_
--   to_checklist_item always overwrites the checklist item's own current file_id
--   pointer and resets its review verdict to pending, but every link/review decision is
--   independently preserved in the append-only app.document_checklist_events table --
--   "prior evidence remains linked" is satisfied by that history trail, not by keeping
--   multiple live file_id columns on one checklist row.
-- * **Approval requires a clean scan, rejection does not** -- app.review_document_
--   checklist_item refuses to approve a checklist item whose linked file has not
--   resolved to malware_scan_status='clean' (RPD-032, "unsafe files never satisfy
--   requirements"), the literal enforcement of that business rule at this capability's
--   own boundary, composed with (never replacing) PLT-128's own independent
--   authorize_file_access gate.
-- * **Completeness is evaluated live, never stored** -- app.evaluate_shipment_document_
--   checklist_completeness is a pure, side-effect-free read (STABLE) any downstream
--   capability (ePOD's Prompt 177, Billing Readiness's Prompt 181) can call as their own
--   disclosed forward-compatible seam, the same "mechanism proven, live wiring deferred
--   until the real dependent capability ships" posture OPS-175 already used for this
--   exact document-readiness gate (§27 of OPS-175.md).
-- * Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): this migration carries its own
--   explicit REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA app FROM PUBLIC statement before
--   its final grants, the standing per-migration convention since PLT-118.

create table app.document_requirement_definitions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  mode text,
  service_type text,
  applicable_status text not null,
  party text not null,
  document_type_code text not null references app.document_types (code),
  criticality text not null default 'mandatory',
  status text not null default 'draft',
  supersedes_version_id uuid references app.document_requirement_definitions (id),
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint document_requirement_definitions_mode_check check (mode is null or mode in ('land', 'air', 'sea')),
  constraint document_requirement_definitions_applicable_status_check check (applicable_status in ('draft', 'confirmed', 'planned', 'assigned', 'dispatched', 'in_transit', 'delivered', 'epod', 'closed')),
  constraint document_requirement_definitions_party_check check (party in ('shipper', 'carrier', 'consignee', 'ops')),
  constraint document_requirement_definitions_criticality_check check (criticality in ('mandatory', 'optional')),
  constraint document_requirement_definitions_status_check check (status in ('draft', 'published', 'archived')),
  constraint document_requirement_definitions_not_self_supersede check (supersedes_version_id is null or supersedes_version_id <> id)
);

comment on table app.document_requirement_definitions is
  'OPS-176: a versioned, tenant-scoped document requirement (draft -> published -> archived) matched against a shipment by mode/service_type (both nullable wildcards)/applicable_status/party/document_type_code. Mirrors app.exception_sla_policy_versions'' own simpler tenant-scoped versioned-definition pattern (OPS-174).';

create unique index document_requirement_definitions_published_match_unique on app.document_requirement_definitions (tenant_id, coalesce(mode, ''), coalesce(service_type, ''), applicable_status, party, document_type_code) where status = 'published';
create unique index document_requirement_definitions_draft_match_unique on app.document_requirement_definitions (tenant_id, coalesce(mode, ''), coalesce(service_type, ''), applicable_status, party, document_type_code) where status = 'draft';
create index document_requirement_definitions_tenant_status_idx on app.document_requirement_definitions (tenant_id, status);

create function app.touch_document_requirement_definitions_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger document_requirement_definitions_touch_row
  before update on app.document_requirement_definitions
  for each row
  execute function app.touch_document_requirement_definitions_row();

create function app.create_document_requirement_draft(
  p_tenant_id uuid,
  p_mode text,
  p_service_type text,
  p_applicable_status text,
  p_party text,
  p_document_type_code text,
  p_criticality text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.document_requirement_definitions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_existing_draft app.document_requirement_definitions;
  v_decision app.rbac_decision;
  v_definition app.document_requirement_definitions;
begin
  if not exists (select 1 from app.document_types where code = p_document_type_code) then
    raise exception 'document_requirement_unknown_document_type: % is not a registered document type', p_document_type_code
      using errcode = 'check_violation';
  end if;

  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % holds no active membership for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'OPS', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_existing_draft
  from app.document_requirement_definitions
  where tenant_id = p_tenant_id and status = 'draft'
    and coalesce(mode, '') = coalesce(p_mode, '') and coalesce(service_type, '') = coalesce(p_service_type, '')
    and applicable_status = p_applicable_status and party = p_party and document_type_code = p_document_type_code;
  if found then
    return v_existing_draft;
  end if;

  insert into app.document_requirement_definitions (tenant_id, mode, service_type, applicable_status, party, document_type_code, criticality, created_by)
  values (p_tenant_id, p_mode, p_service_type, p_applicable_status, p_party, p_document_type_code, coalesce(p_criticality, 'mandatory'), p_actor_label)
  returning * into v_definition;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_document_requirement_draft',
    'app.document_requirement_definitions', v_definition.id, 'success', null, null, to_jsonb(v_definition)
  );

  return v_definition;
end;
$$;

create function app.publish_document_requirement_version(
  p_version_id uuid,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.document_requirement_definitions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_version app.document_requirement_definitions;
  v_superseded app.document_requirement_definitions;
  v_decision app.rbac_decision;
begin
  select * into v_version from app.document_requirement_definitions where id = p_version_id;
  if not found then
    raise exception 'document_requirement_not_found: %', p_version_id using errcode = 'no_data_found';
  end if;
  if v_version.record_version <> p_expected_version then
    raise exception 'concurrent_modification: document requirement % has moved from expected version % to %', p_version_id, p_expected_version, v_version.record_version
      using errcode = 'check_violation';
  end if;
  if v_version.status <> 'draft' then
    raise exception 'invalid_transition: document requirement % is % and cannot be published', p_version_id, v_version.status
      using errcode = 'check_violation';
  end if;

  if not app.has_active_tenant_membership(v_version.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % holds no active membership for tenant %', p_actor_auth_user_id, v_version.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_version.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_version.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_superseded
  from app.document_requirement_definitions
  where tenant_id = v_version.tenant_id and status = 'published'
    and coalesce(mode, '') = coalesce(v_version.mode, '') and coalesce(service_type, '') = coalesce(v_version.service_type, '')
    and applicable_status = v_version.applicable_status and party = v_version.party and document_type_code = v_version.document_type_code;
  if found then
    update app.document_requirement_definitions set status = 'archived' where id = v_superseded.id;
  end if;

  update app.document_requirement_definitions
  set status = 'published', supersedes_version_id = v_superseded.id
  where id = p_version_id
  returning * into v_version;

  perform app.capture_audit_event(
    v_version.tenant_id, p_actor_auth_user_id, p_actor_label, 'publish_document_requirement_version',
    'app.document_requirement_definitions', v_version.id, 'success', null, null, to_jsonb(v_version)
  );

  return v_version;
end;
$$;

-- The pinned per-shipment checklist snapshot. file_id always points at the checklist
-- item's own single current linked file (never a second live column) -- history of
-- every prior link/review decision lives in app.document_checklist_events instead.
create table app.shipment_document_checklist_items (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  shipment_order_id uuid not null references app.shipment_orders (id),
  requirement_definition_id uuid not null references app.document_requirement_definitions (id),
  party text not null,
  document_type_code text not null references app.document_types (code),
  criticality text not null,
  file_id uuid references app.files (id),
  review_status text not null default 'pending',
  reviewed_by_auth_user_id uuid,
  reviewed_at timestamptz,
  review_notes text,
  expires_at timestamptz,
  pinned_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint shipment_document_checklist_items_review_status_check check (review_status in ('pending', 'approved', 'rejected')),
  constraint shipment_document_checklist_items_unique unique (tenant_id, shipment_order_id, requirement_definition_id)
);

comment on table app.shipment_document_checklist_items is
  'OPS-176: one pinned requirement per (shipment, requirement_definition) at the moment app.pin_shipment_document_checklist ran, carrying its own criticality/party/document_type_code snapshot (never re-read from the definition, so a later republish never silently changes an already-pinned shipment''s own checklist -- OPS-174''s exact "pinned at detection" precedent). file_id/review_status track the current linked evidence only; expired is a computed status (review_status=''approved'' and expires_at in the past), never a fourth stored value, so a scheduler-less repository never needs to sweep rows to keep this column truthful.';

create index shipment_document_checklist_items_tenant_shipment_idx on app.shipment_document_checklist_items (tenant_id, shipment_order_id);
create index shipment_document_checklist_items_file_idx on app.shipment_document_checklist_items (file_id);

create function app.touch_shipment_document_checklist_items_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger shipment_document_checklist_items_touch_row
  before update on app.shipment_document_checklist_items
  for each row
  execute function app.touch_shipment_document_checklist_items_row();

-- Append-only link/review history, distinct from app.file_access_logs (PLT-128's own
-- content-access evidence) -- this is requirement-fulfillment evidence instead.
create table app.document_checklist_events (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  checklist_item_id uuid not null references app.shipment_document_checklist_items (id),
  event_type text not null,
  file_id uuid references app.files (id),
  actor_auth_user_id uuid not null,
  notes text,
  occurred_at timestamptz not null default now(),
  constraint document_checklist_events_event_type_check check (event_type in ('pinned', 'linked', 'approved', 'rejected'))
);

comment on table app.document_checklist_events is
  'OPS-176: append-only evidence of every checklist pin/link/review decision, preserving prior linked file_ids even after a checklist item''s own file_id pointer moves on to a replacement version (§22, "prior evidence remains linked").';

create index document_checklist_events_item_idx on app.document_checklist_events (checklist_item_id, occurred_at desc);

create function app.pin_shipment_document_checklist(
  p_shipment_order_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns setof app.shipment_document_checklist_items
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_def record;
  v_item app.shipment_document_checklist_items;
begin
  select * into v_shipment from app.shipment_orders where id = p_shipment_order_id;
  if not found then
    raise exception 'shipment_order_not_found: %', p_shipment_order_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, p_shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  for v_def in
    select * from app.document_requirement_definitions
    where tenant_id = v_shipment.tenant_id and status = 'published'
      and (mode is null or mode = v_shipment.mode)
      and (service_type is null or service_type = v_shipment.service_type)
  loop
    insert into app.shipment_document_checklist_items (tenant_id, shipment_order_id, requirement_definition_id, party, document_type_code, criticality)
    values (v_shipment.tenant_id, v_shipment.id, v_def.id, v_def.party, v_def.document_type_code, v_def.criticality)
    on conflict (tenant_id, shipment_order_id, requirement_definition_id) do nothing
    returning * into v_item;

    if found then
      insert into app.document_checklist_events (tenant_id, checklist_item_id, event_type, actor_auth_user_id, notes)
      values (v_shipment.tenant_id, v_item.id, 'pinned', p_actor_auth_user_id, 'requirement=' || v_def.id::text);
    end if;
  end loop;

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'pin_shipment_document_checklist',
    'app.shipment_orders', v_shipment.id, 'success', null, null, '{}'::jsonb
  );

  return query select * from app.shipment_document_checklist_items where shipment_order_id = p_shipment_order_id order by pinned_at asc;
end;
$$;

comment on function app.pin_shipment_document_checklist is
  'OPS-176: additive-only checklist sync -- inserts a pinned row for every currently-published requirement definition matching the shipment''s mode/service_type not yet pinned; never removes or overwrites an already-pinned row (§24, "keeps its snapshot unless explicit reevaluation occurs" -- reevaluation here means calling this function again after a new definition publishes, not mutating history).';

create function app.link_document_to_checklist_item(
  p_checklist_item_id uuid,
  p_file_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.shipment_document_checklist_items
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_item app.shipment_document_checklist_items;
  v_shipment app.shipment_orders;
  v_file app.files;
  v_decision app.rbac_decision;
  v_updated app.shipment_document_checklist_items;
begin
  select * into v_item from app.shipment_document_checklist_items where id = p_checklist_item_id;
  if not found then
    raise exception 'document_checklist_item_not_found: %', p_checklist_item_id using errcode = 'no_data_found';
  end if;
  select * into v_shipment from app.shipment_orders where id = v_item.shipment_order_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_item.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_item.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, v_item.shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_file from app.files where id = p_file_id;
  if not found then
    raise exception 'document_file_not_found: %', p_file_id using errcode = 'no_data_found';
  end if;
  if v_file.tenant_id <> v_item.tenant_id then
    raise exception 'document_checklist_cross_tenant: file % does not belong to tenant %', p_file_id, v_item.tenant_id
      using errcode = 'check_violation';
  end if;
  if v_file.record_type <> 'shipment_order' or v_file.record_id <> v_item.shipment_order_id then
    raise exception 'document_checklist_record_mismatch: file % is not linked to shipment order %', p_file_id, v_item.shipment_order_id
      using errcode = 'check_violation';
  end if;
  if v_file.document_type_code <> v_item.document_type_code then
    raise exception 'document_checklist_type_mismatch: file % is a % document, checklist item requires %', p_file_id, v_file.document_type_code, v_item.document_type_code
      using errcode = 'check_violation';
  end if;
  if v_file.deleted_at is not null then
    raise exception 'document_checklist_file_deleted: file % has been deleted', p_file_id using errcode = 'check_violation';
  end if;

  update app.shipment_document_checklist_items
  set file_id = p_file_id, review_status = 'pending', reviewed_by_auth_user_id = null, reviewed_at = null, review_notes = null, expires_at = null
  where id = p_checklist_item_id
  returning * into v_updated;

  insert into app.document_checklist_events (tenant_id, checklist_item_id, event_type, file_id, actor_auth_user_id)
  values (v_item.tenant_id, v_updated.id, 'linked', p_file_id, p_actor_auth_user_id);

  perform app.capture_audit_event(
    v_item.tenant_id, p_actor_auth_user_id, p_actor_label, 'link_document_to_checklist_item',
    'app.shipment_document_checklist_items', v_updated.id, 'success', null, to_jsonb(v_item), to_jsonb(v_updated)
  );

  return v_updated;
end;
$$;

create function app.review_document_checklist_item(
  p_checklist_item_id uuid,
  p_decision text,
  p_notes text,
  p_expires_at timestamptz,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.shipment_document_checklist_items
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_item app.shipment_document_checklist_items;
  v_shipment app.shipment_orders;
  v_file app.files;
  v_decision app.rbac_decision;
  v_updated app.shipment_document_checklist_items;
begin
  if p_decision not in ('approved', 'rejected') then
    raise exception 'document_checklist_invalid_decision: % is not one of approved/rejected', p_decision using errcode = 'check_violation';
  end if;

  select * into v_item from app.shipment_document_checklist_items where id = p_checklist_item_id;
  if not found then
    raise exception 'document_checklist_item_not_found: %', p_checklist_item_id using errcode = 'no_data_found';
  end if;
  select * into v_shipment from app.shipment_orders where id = v_item.shipment_order_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_item.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_item.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, v_item.shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_item.file_id is null then
    raise exception 'document_checklist_no_linked_file: checklist item % has no linked file to review', p_checklist_item_id
      using errcode = 'check_violation';
  end if;

  if p_decision = 'approved' then
    select * into v_file from app.files where id = v_item.file_id;
    if v_file.malware_scan_status <> 'clean' then
      raise exception 'document_checklist_unsafe_file: linked file % has scan status % -- only clean evidence may be approved', v_item.file_id, v_file.malware_scan_status
        using errcode = 'check_violation';
    end if;
  end if;

  update app.shipment_document_checklist_items
  set review_status = p_decision,
      reviewed_by_auth_user_id = p_actor_auth_user_id,
      reviewed_at = now(),
      review_notes = p_notes,
      expires_at = case when p_decision = 'approved' then p_expires_at else null end
  where id = p_checklist_item_id
  returning * into v_updated;

  insert into app.document_checklist_events (tenant_id, checklist_item_id, event_type, file_id, actor_auth_user_id, notes)
  values (v_item.tenant_id, v_updated.id, p_decision, v_item.file_id, p_actor_auth_user_id, p_notes);

  perform app.capture_audit_event(
    v_item.tenant_id, p_actor_auth_user_id, p_actor_label, 'review_document_checklist_item',
    'app.shipment_document_checklist_items', v_updated.id, 'success', null, to_jsonb(v_item), to_jsonb(v_updated)
  );

  return v_updated;
end;
$$;

-- The one live-evaluated read every checklist/panel UI and downstream capability
-- (ePOD Prompt 177, Billing Readiness Prompt 181) calls -- effective_status is computed
-- fresh from review_status/expires_at/the linked file's own current scan status, never
-- a fourth stored column a scheduler-less repository would have to sweep.
create function app.get_shipment_document_checklist(
  p_shipment_order_id uuid,
  p_actor_auth_user_id uuid
)
returns table (
  id uuid,
  requirement_definition_id uuid,
  party text,
  document_type_code text,
  criticality text,
  file_id uuid,
  malware_scan_status text,
  review_status text,
  reviewed_by_auth_user_id uuid,
  reviewed_at timestamptz,
  review_notes text,
  expires_at timestamptz,
  effective_status text
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
begin
  select * into v_shipment from app.shipment_orders so where so.id = p_shipment_order_id;
  if not found then
    raise exception 'shipment_order_not_found: %', p_shipment_order_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, p_shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
  select
    ci.id, ci.requirement_definition_id, ci.party, ci.document_type_code, ci.criticality,
    ci.file_id, f.malware_scan_status, ci.review_status, ci.reviewed_by_auth_user_id, ci.reviewed_at, ci.review_notes, ci.expires_at,
    case
      when ci.review_status = 'approved' and (ci.expires_at is null or ci.expires_at > now()) then 'approved'
      when ci.review_status = 'approved' and ci.expires_at <= now() then 'expired'
      when ci.review_status = 'rejected' then 'rejected'
      when ci.file_id is not null then 'pending_review'
      else 'missing'
    end as effective_status
  from app.shipment_document_checklist_items ci
  left join app.files f on f.id = ci.file_id
  where ci.shipment_order_id = p_shipment_order_id
  order by ci.pinned_at asc;
end;
$$;

-- Pure, side-effect-free (STABLE) completeness evaluation -- the disclosed forward
-- seam ePOD (177) and Billing Readiness (181) will call, mirroring OPS-175's own
-- app.evaluate_dispatch_readiness precedent of a shared, once-defined checklist.
create function app.evaluate_shipment_document_checklist_completeness(
  p_shipment_order_id uuid,
  p_actor_auth_user_id uuid
)
returns table (
  is_complete boolean,
  missing_mandatory jsonb
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_missing jsonb;
begin
  select * into v_shipment from app.shipment_orders where id = p_shipment_order_id;
  if not found then
    raise exception 'shipment_order_not_found: %', p_shipment_order_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, p_shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object('checklist_item_id', ci.id, 'document_type_code', ci.document_type_code, 'party', ci.party)), '[]'::jsonb)
  into v_missing
  from app.shipment_document_checklist_items ci
  left join app.files f on f.id = ci.file_id
  where ci.shipment_order_id = p_shipment_order_id
    and ci.criticality = 'mandatory'
    and not (
      ci.review_status = 'approved'
      and (ci.expires_at is null or ci.expires_at > now())
      and f.malware_scan_status = 'clean'
    );

  return query select (jsonb_array_length(v_missing) = 0), v_missing;
end;
$$;

alter table app.document_requirement_definitions enable row level security;
alter table app.shipment_document_checklist_items enable row level security;
alter table app.document_checklist_events enable row level security;

create policy document_requirement_definitions_select_scoped on app.document_requirement_definitions
  for select to authenticated
  using (app.has_active_tenant_membership(tenant_id) or app.is_supreme_admin());

create policy shipment_document_checklist_items_select_scoped on app.shipment_document_checklist_items
  for select to authenticated
  using (
    exists (
      select 1 from app.shipment_orders so
      where so.id = shipment_document_checklist_items.shipment_order_id
        and app.can_access_record((select auth.uid()), so.tenant_id, so.owner_user_id, app.lead_record_scope_org_unit_ids(so.org_unit_id), null)
    )
  );

create policy document_checklist_events_select_scoped on app.document_checklist_events
  for select to authenticated
  using (
    exists (
      select 1 from app.shipment_document_checklist_items ci
      join app.shipment_orders so on so.id = ci.shipment_order_id
      where ci.id = document_checklist_events.checklist_item_id
        and app.can_access_record((select auth.uid()), so.tenant_id, so.owner_user_id, app.lead_record_scope_org_unit_ids(so.org_unit_id), null)
    )
  );

revoke execute on all functions in schema app from public;

grant select on app.document_requirement_definitions to authenticated, service_role;
grant insert, update, delete on app.document_requirement_definitions to service_role;
grant select on app.shipment_document_checklist_items to authenticated, service_role;
grant insert, update, delete on app.shipment_document_checklist_items to service_role;
grant select on app.document_checklist_events to authenticated, service_role;
grant insert, update, delete on app.document_checklist_events to service_role;

grant execute on function app.create_document_requirement_draft(uuid, text, text, text, text, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.publish_document_requirement_version(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.pin_shipment_document_checklist(uuid, uuid, text) to authenticated, service_role;
grant execute on function app.link_document_to_checklist_item(uuid, uuid, uuid, text) to authenticated, service_role;
grant execute on function app.review_document_checklist_item(uuid, text, text, timestamptz, uuid, text) to authenticated, service_role;
grant execute on function app.get_shipment_document_checklist(uuid, uuid) to authenticated, service_role;
grant execute on function app.evaluate_shipment_document_checklist_completeness(uuid, uuid) to authenticated, service_role;
