-- Operations capability OPS-177 (ePOD Capture and Review, CG-S8-OPS-011)
-- Online-first, versioned electronic proof-of-delivery capture (receiver, signature,
-- photo, geolocation, timestamp), review/revision, and completion bound to the exact
-- Shipment Order and its `delivered -> epod` lifecycle edge (Prompt 177 §4/§20).
--
-- Scope and design decisions, disclosed rather than left implicit:
--
-- * **A dedicated structured object, not a generic checklist item.** `OPS-176`'s own
--   document checklist handles arbitrary named document types; ePOD is a distinct
--   object model with its own fixed fields (receiver name/position, signature file,
--   photo files, geolocation, captured/server time) that a generic checklist item
--   cannot represent. Both capabilities compose the same Platform Document/File Engine
--   (`PLT-128`) underneath -- `app.epod_captures.signature_file_id`/`photo_file_ids`
--   reference `app.files.id` directly and re-read that row's own live
--   `malware_scan_status`, the same "single source of truth" discipline `OPS-176`
--   already established, never a second scan-result column.
-- * **Versioned like `app.files` itself, never overwritten.** A revision request
--   (`app.revise_epod_capture`) always inserts a new row (`version_group_id` links the
--   lineage, `version_number` increments, `is_latest_version` exclusive via a partial
--   unique index) and flips the prior row's own `is_latest_version` to false -- full
--   history remains exactly as Prompt 177 §22 requires ("a new version
--   supplements/replaces rejected evidence while full history remains").
-- * **Geolocation reuses `PLT-134`'s own governed convention exactly**
--   (`app.geojson_point_to_geography`/`app.validate_geography_point`,
--   `geography(Point,4326)`, RFC 7946 `[longitude, latitude]` axis order) -- the first
--   domain table in this repository to add a real spatial column, proving out that
--   migration's own disclosed forward seam rather than inventing a second convention.
-- * **Trustworthy server time, not client-claimed time, is authoritative** (§25):
--   `captured_at` is recorded as the field user's own claimed capture time (evidence of
--   intent), but `server_received_at` (`default now()`) is the timestamp every
--   downstream consumer (billing readiness, public tracking) must treat as
--   authoritative -- a client clock is never trusted for sequencing or SLA math.
-- * **Completion is a thin wrapper over `OPS-170`'s own already-shipped
--   `delivered -> epod` transition**, the identical "a dedicated command supersedes the
--   generic transition matrix" precedent `OPS-175`'s own `app.dispatch_shipment_order`
--   established: `app.complete_epod_capture` requires `status = 'approved'` on the
--   latest capture version, then calls `app.transition_shipment_order` internally with
--   `evidence_ref` set to the capture's own id -- never a second, parallel status
--   machine for "is this shipment ePOD-complete."
-- * **Normal roles cannot rewrite completed evidence** (§24): every mutating function
--   below refuses once `status = 'completed'`; no correction path is built in this
--   capability (the disclosed RPD-022 Supreme Admin correction precedent already
--   established at `PLT-118`/other capabilities is not re-implemented here -- out of
--   this capability's own 5-15-file sizing discipline).
-- * **Native mobile, offline capture/sync, and the customer-facing masked read are
--   explicitly out of scope** (§24 RPD-004: online-first responsive PWA only; a
--   customer-visible ePOD projection is `OPS-180`'s own Basic Public Tracking, not
--   built here -- no customer-facing route exists anywhere in this checkpoint).
-- * Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): this migration carries its own
--   explicit REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA app FROM PUBLIC statement before
--   its final grants, the standing per-migration convention since PLT-118.

create table app.epod_captures (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  shipment_order_id uuid not null references app.shipment_orders (id),
  milestone_event_id uuid references app.milestone_events (id),
  version_group_id uuid not null,
  version_number integer not null default 1,
  is_latest_version boolean not null default true,
  status text not null default 'draft',
  receiver_name text,
  receiver_position text,
  signature_file_id uuid references app.files (id),
  photo_file_ids uuid[] not null default '{}',
  delivery_geog geography (point, 4326),
  captured_at timestamptz,
  server_received_at timestamptz not null default now(),
  reviewed_by_auth_user_id uuid,
  reviewed_at timestamptz,
  review_notes text,
  idempotency_key text,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint epod_captures_status_check check (status in ('draft', 'submitted', 'approved', 'revision_requested', 'completed')),
  constraint epod_captures_version_number_check check (version_number > 0),
  constraint epod_captures_delivery_geog_check check (delivery_geog is null or app.validate_geography_point(delivery_geog)),
  constraint epod_captures_tenant_idempotency_unique unique (tenant_id, idempotency_key)
);

comment on table app.epod_captures is
  'OPS-177: one versioned ePOD capture per shipment (version_group_id links the lineage across revision requests; is_latest_version exclusive). signature_file_id/photo_file_ids reference app.files.id directly (PLT-128) -- scan status is always re-read live, never copied here. delivery_geog is a governed geography(Point,4326) column (PLT-134''s own app.geojson_point_to_geography/app.validate_geography_point convention). captured_at is the field user''s own claimed time; server_received_at is the authoritative timestamp for every downstream consumer.';

create unique index epod_captures_one_latest_version_idx on app.epod_captures (version_group_id) where is_latest_version;
create index epod_captures_tenant_shipment_idx on app.epod_captures (tenant_id, shipment_order_id);
create index epod_captures_geog_idx on app.epod_captures using gist (delivery_geog);

create function app.touch_epod_captures_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger epod_captures_touch_row
  before update on app.epod_captures
  for each row
  execute function app.touch_epod_captures_row();

-- Idempotent on (tenant, idempotency_key). Requires the shipment to already be
-- 'delivered' (the exact precondition OPS-170's own delivered -> epod transition
-- edge already enforces at completion time -- checked again here, at capture start,
-- so a field user is never allowed to begin capturing evidence for a shipment that
-- has not yet reached the delivery milestone).
create function app.start_epod_capture(
  p_tenant_id uuid,
  p_shipment_order_id uuid,
  p_milestone_event_id uuid,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.epod_captures
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_existing app.epod_captures;
  v_new_id uuid := gen_random_uuid();
  v_capture app.epod_captures;
begin
  select * into v_shipment from app.shipment_orders so where so.id = p_shipment_order_id;
  if not found then
    raise exception 'shipment_order_not_found: %', p_shipment_order_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, p_shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_idempotency_key is not null then
    select * into v_existing from app.epod_captures where tenant_id = v_shipment.tenant_id and idempotency_key = p_idempotency_key;
    if found then
      return v_existing;
    end if;
  end if;

  if v_shipment.status <> 'delivered' then
    raise exception 'epod_shipment_not_delivered: shipment order % is % -- ePOD capture may only begin once a shipment reaches delivered', p_shipment_order_id, v_shipment.status
      using errcode = 'check_violation';
  end if;

  insert into app.epod_captures (id, tenant_id, shipment_order_id, milestone_event_id, version_group_id, version_number, is_latest_version, status, idempotency_key, created_by)
  values (v_new_id, v_shipment.tenant_id, p_shipment_order_id, p_milestone_event_id, v_new_id, 1, true, 'draft', p_idempotency_key, p_actor_label)
  returning * into v_capture;

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'start_epod_capture',
    'app.epod_captures', v_capture.id, 'success', null, null, to_jsonb(v_capture)
  );

  return v_capture;
end;
$$;

-- Only mutates a draft or a revision-requested capture -- never submitted/approved/
-- completed. p_delivery_geojson is a GeoJSON Point object (RFC 7946); null clears it.
create function app.set_epod_evidence(
  p_capture_id uuid,
  p_receiver_name text,
  p_receiver_position text,
  p_signature_file_id uuid,
  p_photo_file_ids uuid[],
  p_delivery_geojson jsonb,
  p_captured_at timestamptz,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.epod_captures
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_capture app.epod_captures;
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_file app.files;
  v_photo_id uuid;
  v_geog public.geography;
  v_updated app.epod_captures;
begin
  select * into v_capture from app.epod_captures where id = p_capture_id;
  if not found then
    raise exception 'epod_capture_not_found: %', p_capture_id using errcode = 'no_data_found';
  end if;
  select * into v_shipment from app.shipment_orders so where so.id = v_capture.shipment_order_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_capture.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_capture.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, v_capture.shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_capture.status not in ('draft', 'revision_requested') then
    raise exception 'invalid_transition: ePOD capture % is % and its evidence can no longer be edited', p_capture_id, v_capture.status
      using errcode = 'check_violation';
  end if;

  if p_signature_file_id is not null then
    select * into v_file from app.files where id = p_signature_file_id;
    if not found or v_file.tenant_id <> v_capture.tenant_id or v_file.record_type <> 'shipment_order' or v_file.record_id <> v_capture.shipment_order_id then
      raise exception 'epod_evidence_file_mismatch: signature file % does not belong to shipment order %', p_signature_file_id, v_capture.shipment_order_id
        using errcode = 'check_violation';
    end if;
  end if;

  if p_photo_file_ids is not null then
    foreach v_photo_id in array p_photo_file_ids loop
      select * into v_file from app.files where id = v_photo_id;
      if not found or v_file.tenant_id <> v_capture.tenant_id or v_file.record_type <> 'shipment_order' or v_file.record_id <> v_capture.shipment_order_id then
        raise exception 'epod_evidence_file_mismatch: photo file % does not belong to shipment order %', v_photo_id, v_capture.shipment_order_id
          using errcode = 'check_violation';
      end if;
    end loop;
  end if;

  if p_delivery_geojson is not null then
    v_geog := app.geojson_point_to_geography(p_delivery_geojson);
  end if;

  update app.epod_captures
  set receiver_name = p_receiver_name,
      receiver_position = p_receiver_position,
      signature_file_id = p_signature_file_id,
      photo_file_ids = coalesce(p_photo_file_ids, '{}'::uuid[]),
      delivery_geog = v_geog,
      captured_at = p_captured_at,
      status = 'draft'
  where id = p_capture_id
  returning * into v_updated;

  perform app.capture_audit_event(
    v_capture.tenant_id, p_actor_auth_user_id, p_actor_label, 'set_epod_evidence',
    'app.epod_captures', v_updated.id, 'success', null, to_jsonb(v_capture), to_jsonb(v_updated)
  );

  return v_updated;
end;
$$;

-- draft -> submitted. Requires a receiver name, at least one of signature/photo
-- evidence, and every referenced file to have resolved malware_scan_status='clean'
-- (RPD-032's "unsafe files never satisfy" rule, the same gate OPS-176 already applies
-- at its own review step).
create function app.submit_epod_capture(
  p_capture_id uuid,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.epod_captures
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_capture app.epod_captures;
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_photo_id uuid;
  v_scan_status text;
  v_updated app.epod_captures;
begin
  select * into v_capture from app.epod_captures where id = p_capture_id;
  if not found then
    raise exception 'epod_capture_not_found: %', p_capture_id using errcode = 'no_data_found';
  end if;
  if v_capture.record_version <> p_expected_version then
    raise exception 'concurrent_modification: ePOD capture % has moved from expected version % to %', p_capture_id, p_expected_version, v_capture.record_version
      using errcode = 'check_violation';
  end if;
  select * into v_shipment from app.shipment_orders so where so.id = v_capture.shipment_order_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_capture.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_capture.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, v_capture.shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_capture.status not in ('draft', 'revision_requested') then
    raise exception 'invalid_transition: ePOD capture % is % and cannot be submitted', p_capture_id, v_capture.status
      using errcode = 'check_violation';
  end if;

  if v_capture.receiver_name is null or length(trim(v_capture.receiver_name)) = 0 then
    raise exception 'epod_missing_receiver: a receiver name is required before submission' using errcode = 'check_violation';
  end if;
  if v_capture.signature_file_id is null and array_length(v_capture.photo_file_ids, 1) is null then
    raise exception 'epod_missing_evidence: at least one of a signature or a photo is required before submission' using errcode = 'check_violation';
  end if;

  if v_capture.signature_file_id is not null then
    select malware_scan_status into v_scan_status from app.files where id = v_capture.signature_file_id;
    if v_scan_status <> 'clean' then
      raise exception 'epod_unsafe_evidence: signature file % has scan status % -- only clean evidence may be submitted', v_capture.signature_file_id, v_scan_status
        using errcode = 'check_violation';
    end if;
  end if;
  foreach v_photo_id in array v_capture.photo_file_ids loop
    select malware_scan_status into v_scan_status from app.files where id = v_photo_id;
    if v_scan_status <> 'clean' then
      raise exception 'epod_unsafe_evidence: photo file % has scan status % -- only clean evidence may be submitted', v_photo_id, v_scan_status
        using errcode = 'check_violation';
    end if;
  end loop;

  update app.epod_captures
  set status = 'submitted'
  where id = p_capture_id
  returning * into v_updated;

  perform app.capture_audit_event(
    v_capture.tenant_id, p_actor_auth_user_id, p_actor_label, 'submit_epod_capture',
    'app.epod_captures', v_updated.id, 'success', null, to_jsonb(v_capture), to_jsonb(v_updated)
  );

  return v_updated;
end;
$$;

-- submitted -> approved | revision_requested.
create function app.review_epod_capture(
  p_capture_id uuid,
  p_decision text,
  p_notes text,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.epod_captures
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_capture app.epod_captures;
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_updated app.epod_captures;
begin
  if p_decision not in ('approved', 'revision_requested') then
    raise exception 'epod_invalid_decision: % is not one of approved/revision_requested', p_decision using errcode = 'check_violation';
  end if;

  select * into v_capture from app.epod_captures where id = p_capture_id;
  if not found then
    raise exception 'epod_capture_not_found: %', p_capture_id using errcode = 'no_data_found';
  end if;
  if v_capture.record_version <> p_expected_version then
    raise exception 'concurrent_modification: ePOD capture % has moved from expected version % to %', p_capture_id, p_expected_version, v_capture.record_version
      using errcode = 'check_violation';
  end if;
  select * into v_shipment from app.shipment_orders so where so.id = v_capture.shipment_order_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_capture.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_capture.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, v_capture.shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_capture.status <> 'submitted' then
    raise exception 'invalid_transition: ePOD capture % is % and cannot be reviewed', p_capture_id, v_capture.status
      using errcode = 'check_violation';
  end if;
  if p_decision = 'revision_requested' and (p_notes is null or length(trim(p_notes)) = 0) then
    raise exception 'epod_revision_reason_required: notes are required when requesting a revision' using errcode = 'check_violation';
  end if;

  update app.epod_captures
  set status = p_decision, reviewed_by_auth_user_id = p_actor_auth_user_id, reviewed_at = now(), review_notes = p_notes
  where id = p_capture_id
  returning * into v_updated;

  perform app.capture_audit_event(
    v_capture.tenant_id, p_actor_auth_user_id, p_actor_label, 'review_epod_capture',
    'app.epod_captures', v_updated.id, 'success', null, to_jsonb(v_capture), to_jsonb(v_updated)
  );

  return v_updated;
end;
$$;

-- revision_requested -> a brand-new draft version. Always inserts, never mutates the
-- rejected row in place (the same versioning discipline app.create_file_version
-- established) -- full history remains, the rejected version's own review_notes stay
-- exactly as recorded.
create function app.revise_epod_capture(
  p_previous_capture_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.epod_captures
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_prev app.epod_captures;
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_new_id uuid := gen_random_uuid();
  v_capture app.epod_captures;
begin
  select * into v_prev from app.epod_captures where id = p_previous_capture_id;
  if not found then
    raise exception 'epod_capture_not_found: %', p_previous_capture_id using errcode = 'no_data_found';
  end if;
  select * into v_shipment from app.shipment_orders so where so.id = v_prev.shipment_order_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_prev.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_prev.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, v_prev.shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_prev.status <> 'revision_requested' then
    raise exception 'invalid_transition: ePOD capture % is % and is not awaiting revision', p_previous_capture_id, v_prev.status
      using errcode = 'check_violation';
  end if;
  if not v_prev.is_latest_version then
    raise exception 'epod_not_latest_version: capture % is not the latest version of its group', p_previous_capture_id
      using errcode = 'check_violation';
  end if;

  update app.epod_captures set is_latest_version = false where id = v_prev.id;

  insert into app.epod_captures (
    id, tenant_id, shipment_order_id, milestone_event_id, version_group_id, version_number, is_latest_version,
    status, receiver_name, receiver_position, signature_file_id, photo_file_ids, delivery_geog, captured_at, created_by
  ) values (
    v_new_id, v_prev.tenant_id, v_prev.shipment_order_id, v_prev.milestone_event_id, v_prev.version_group_id, v_prev.version_number + 1, true,
    'draft', v_prev.receiver_name, v_prev.receiver_position, v_prev.signature_file_id, v_prev.photo_file_ids, v_prev.delivery_geog, v_prev.captured_at, p_actor_label
  )
  returning * into v_capture;

  perform app.capture_audit_event(
    v_prev.tenant_id, p_actor_auth_user_id, p_actor_label, 'revise_epod_capture',
    'app.epod_captures', v_capture.id, 'success', null, to_jsonb(v_prev), to_jsonb(v_capture)
  );

  return v_capture;
end;
$$;

-- approved -> completed. Thin wrapper over OPS-170's own already-shipped
-- delivered -> epod transition -- never a second parallel status machine.
create function app.complete_epod_capture(
  p_capture_id uuid,
  p_expected_capture_version integer,
  p_shipment_expected_version integer,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.epod_captures
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_capture app.epod_captures;
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_updated app.epod_captures;
begin
  select * into v_capture from app.epod_captures where id = p_capture_id;
  if not found then
    raise exception 'epod_capture_not_found: %', p_capture_id using errcode = 'no_data_found';
  end if;
  if v_capture.record_version <> p_expected_capture_version then
    raise exception 'concurrent_modification: ePOD capture % has moved from expected version % to %', p_capture_id, p_expected_capture_version, v_capture.record_version
      using errcode = 'check_violation';
  end if;
  select * into v_shipment from app.shipment_orders so where so.id = v_capture.shipment_order_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_capture.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_capture.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, v_capture.shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_capture.status <> 'approved' then
    raise exception 'invalid_transition: ePOD capture % is % and cannot be completed', p_capture_id, v_capture.status
      using errcode = 'check_violation';
  end if;

  perform app.transition_shipment_order(v_capture.shipment_order_id, 'epod', p_shipment_expected_version, null, p_capture_id::text, p_idempotency_key, p_actor_auth_user_id, p_actor_label);

  update app.epod_captures
  set status = 'completed'
  where id = p_capture_id
  returning * into v_updated;

  perform app.capture_audit_event(
    v_capture.tenant_id, p_actor_auth_user_id, p_actor_label, 'complete_epod_capture',
    'app.epod_captures', v_updated.id, 'success', null, to_jsonb(v_capture), to_jsonb(v_updated)
  );

  return v_updated;
end;
$$;

create function app.get_epod_capture_history(
  p_shipment_order_id uuid,
  p_actor_auth_user_id uuid
)
returns setof app.epod_captures
language plpgsql
security definer
set search_path = app, public, pg_temp
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

  return query select * from app.epod_captures where shipment_order_id = p_shipment_order_id order by version_group_id, version_number asc;
end;
$$;

alter table app.epod_captures enable row level security;

create policy epod_captures_select_scoped on app.epod_captures
  for select to authenticated
  using (
    exists (
      select 1 from app.shipment_orders so
      where so.id = epod_captures.shipment_order_id
        and app.can_access_record(auth.uid(), so.tenant_id, so.owner_user_id, app.lead_record_scope_org_unit_ids(so.org_unit_id), null)
    )
  );

revoke execute on all functions in schema app from public;

grant select on app.epod_captures to authenticated, service_role;
grant insert, update, delete on app.epod_captures to service_role;

grant execute on function app.start_epod_capture(uuid, uuid, uuid, text, uuid, text) to authenticated, service_role;
grant execute on function app.set_epod_evidence(uuid, text, text, uuid, uuid[], jsonb, timestamptz, uuid, text) to authenticated, service_role;
grant execute on function app.submit_epod_capture(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.review_epod_capture(uuid, text, text, integer, uuid, text) to authenticated, service_role;
grant execute on function app.revise_epod_capture(uuid, uuid, text) to authenticated, service_role;
grant execute on function app.complete_epod_capture(uuid, integer, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.get_epod_capture_history(uuid, uuid) to authenticated, service_role;
