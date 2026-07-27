-- Operations capability OPS-173 (Milestone Management, CG-S8-OPS-007)
-- Configurable shipment milestones and append-oriented event capture with ETA/ETD,
-- location, source and a reliable, deterministic timeline/status projection
-- (Prompt 173 §4/§20).
--
-- Engine-reuse research, disclosed rather than silently skipped (the same discipline
-- `OPS-170` established): the Configuration Engine (`PLT-121`) is the standing reuse
-- vehicle every prior versioned-tenant-definition capability in this repository has
-- used (Status Engine `PLT-124`, Numbering Engine `PLT-125`, Notification Templates,
-- Feature Flags) -- but its own precedence model resolves across company/branch/role/
-- user, an org-hierarchy dimension. This capability's own versioning axis is `mode`
-- (land/air/sea, the same fixed 3-value set `OPS-171` already established on
-- `app.shipment_orders.mode`), not an org-hierarchy scope -- forcing it through
-- Configuration Engine's precedence walk would not fit any of its real dimensions
-- without inventing a fake "role" standing in for "mode." This migration instead
-- mirrors `COM-150`'s own simpler, directly-tenant-scoped versioned-definition
-- pattern (`app.margin_rule_versions`: draft -> published -> archived, at most one
-- published row at a time, `record_version` optimistic concurrency), extended by one
-- extra dimension (`mode`) rather than reusing Configuration Engine at all.
--
-- Milestone *codes* are a separate, permanent, platform-wide registry
-- (`app.milestone_codes`), the same "canonical meaning is permanent, presentation/
-- template membership is the only configurable surface" split Status Engine (`PLT-124`)
-- already established for statuses (Prompt 173 §24: "canonical code and projection
-- semantics remain stable"). `is_customer_visible`/`affects_eta`/`is_terminal` are
-- properties of the *code* itself, not of any one tenant's template -- a tenant may
-- choose which codes appear in its own service/mode sequence, never redefine what a
-- code means once registered.
--
-- Event time and received time are two distinct, both-retained columns on
-- `app.milestone_events` (§24). Corrections are additive: `app.ingest_milestone_event`
-- never updates or deletes a prior row -- a correction is a new event row whose own
-- `corrects_event_id` points at the event it corrects, with a mandatory non-empty
-- `reason` (§24: "corrections link new evidence instead of silently rewriting
-- history"). `app.shipment_milestone_projections` is the one deterministic, replay-safe
-- current-state projection per shipment, recalculated in full from every event on that
-- shipment each time a new event is ingested (never an incremental patch that could
-- drift under out-of-order/duplicate delivery, Prompt 173 §25).
--
-- External-source authentication (Prompt 173 §16/§26: "external ingestion
-- authenticates source") is not reinvented here -- this migration's own
-- `app.ingest_milestone_event` still requires a real `p_actor_auth_user_id` passing
-- `OPS:Create`, the same actor-identity contract every other Operations mutation in
-- this session already uses; `source` is a descriptive/audit classification column
-- (`manual`/`api`/`webhook`/`import`), never an alternate authentication path of its
-- own. A real scoped-credential-to-identity binding for API/webhook callers is
-- Platform Core's own already-shipped `app.api_keys`/webhook infrastructure (`PLT-129`),
-- reused as the caller's own resolved identity, not duplicated here.
--
-- This capability does not build a second parallel shipment state machine --
-- `app.shipment_orders.status`/`app.transition_shipment_order` (`OPS-170`) remains the
-- one authoritative canonical lifecycle; milestone events are a supplementary,
-- deterministic visibility/ETA projection layer that never itself transitions a
-- shipment's own canonical status.
--
-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): this migration carries its own
-- explicit `REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA app FROM PUBLIC` statement
-- before its final grants, the standing per-migration convention since `PLT-118`.

create table app.milestone_codes (
  code text primary key,
  name text not null,
  category text not null,
  is_customer_visible boolean not null default false,
  affects_eta boolean not null default false,
  is_terminal boolean not null default false,
  registered_by text,
  created_at timestamptz not null default now(),
  constraint milestone_codes_category_check check (category in ('pickup', 'in_transit', 'exception', 'delivery', 'administrative'))
);

comment on table app.milestone_codes is
  'OPS-173: the permanent, platform-wide canonical milestone code registry (Supreme-only, idempotent registration, mirroring PLT-124''s own canonical_statuses precedent). is_customer_visible/affects_eta/is_terminal are permanent properties of the code itself -- never overridden per-tenant, per Prompt 173 §24''s "canonical code and projection semantics remain stable."';

create function app.register_milestone_code(
  p_code text,
  p_name text,
  p_category text,
  p_is_customer_visible boolean,
  p_affects_eta boolean,
  p_is_terminal boolean,
  p_actor_auth_user_id uuid,
  p_registered_by text
)
returns app.milestone_codes
language plpgsql
as $$
declare
  v_existing app.milestone_codes;
  v_code app.milestone_codes;
begin
  if not app.is_supreme_admin(p_actor_auth_user_id) then
    raise exception 'insufficient_authority: only Supreme Admin may register a milestone code'
      using errcode = 'insufficient_privilege';
  end if;
  if p_category not in ('pickup', 'in_transit', 'exception', 'delivery', 'administrative') then
    raise exception 'milestone_invalid_category: % is not one of pickup/in_transit/exception/delivery/administrative', p_category
      using errcode = 'check_violation';
  end if;

  select * into v_existing from app.milestone_codes where code = p_code;
  if found then
    return v_existing;
  end if;

  insert into app.milestone_codes (code, name, category, is_customer_visible, affects_eta, is_terminal, registered_by)
  values (p_code, p_name, p_category, coalesce(p_is_customer_visible, false), coalesce(p_affects_eta, false), coalesce(p_is_terminal, false), p_registered_by)
  returning * into v_code;

  perform app.capture_audit_event(
    null, p_actor_auth_user_id, p_registered_by, 'register_milestone_code',
    'app.milestone_codes', null, 'success', null, null, to_jsonb(v_code)
  );

  return v_code;
end;
$$;

comment on function app.register_milestone_code is
  'OPS-173: idempotent (a repeated call with an existing code returns that row, never raises), Supreme-Admin-only. Platform-wide (no tenant_id) -- a milestone code''s meaning is never tenant-scoped, only its membership in a tenant''s own template sequence is.';

create table app.milestone_template_versions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  mode text not null,
  status text not null default 'draft',
  sequence jsonb not null default '[]'::jsonb,
  supersedes_version_id uuid references app.milestone_template_versions (id),
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint milestone_template_versions_mode_check check (mode in ('land', 'air', 'sea')),
  constraint milestone_template_versions_status_check check (status in ('draft', 'published', 'archived')),
  constraint milestone_template_versions_not_self_supersede check (supersedes_version_id is null or supersedes_version_id <> id)
);

comment on table app.milestone_template_versions is
  'OPS-173: a versioned, tenant-scoped, per-mode expected milestone sequence (draft -> published -> archived, mirroring app.margin_rule_versions''/COM-150''s own simpler tenant-scoped versioned-definition pattern rather than Configuration Engine, whose precedence dimensions do not fit "by mode"). sequence is a jsonb array of {"code": "<milestone_code>"} objects, validated against app.milestone_codes at publish time. At most one published (and one draft) version per (tenant_id, mode) at a time.';

create unique index milestone_template_versions_tenant_mode_published_unique on app.milestone_template_versions (tenant_id, mode) where status = 'published';
create unique index milestone_template_versions_tenant_mode_draft_unique on app.milestone_template_versions (tenant_id, mode) where status = 'draft';
create index milestone_template_versions_tenant_mode_idx on app.milestone_template_versions (tenant_id, mode, status);

create function app.touch_milestone_template_version_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger milestone_template_versions_touch_row
  before update on app.milestone_template_versions
  for each row
  execute function app.touch_milestone_template_version_row();

-- Idempotent: a repeated call while a draft already exists for this (tenant, mode)
-- returns that same draft, mirroring PLT-117's own single-draft-per-tenant convention,
-- extended by mode.
create function app.create_milestone_template_draft(
  p_tenant_id uuid,
  p_mode text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.milestone_template_versions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_existing_draft app.milestone_template_versions;
  v_decision app.rbac_decision;
  v_version app.milestone_template_versions;
begin
  if p_mode not in ('land', 'air', 'sea') then
    raise exception 'invalid_mode: % is not a supported mode', p_mode using errcode = 'check_violation';
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

  select * into v_existing_draft from app.milestone_template_versions where tenant_id = p_tenant_id and mode = p_mode and status = 'draft';
  if found then
    return v_existing_draft;
  end if;

  insert into app.milestone_template_versions (tenant_id, mode, created_by)
  values (p_tenant_id, p_mode, p_actor_label)
  returning * into v_version;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_milestone_template_draft',
    'app.milestone_template_versions', v_version.id, 'success', null, null, jsonb_build_object('mode', p_mode)
  );

  return v_version;
end;
$$;

-- Only ever mutates a draft (mirroring app.set_tenant_brand_tokens''/PLT-117's own
-- "only mutates a draft" discipline). Each element''s own code is validated against
-- app.milestone_codes immediately, so a typo is caught at authoring time, not only at
-- publish.
create function app.set_milestone_template_sequence(
  p_version_id uuid,
  p_sequence jsonb,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.milestone_template_versions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_version app.milestone_template_versions;
  v_decision app.rbac_decision;
  v_element jsonb;
  v_code text;
begin
  select * into v_version from app.milestone_template_versions where id = p_version_id;
  if not found then
    raise exception 'milestone_template_not_found: %', p_version_id using errcode = 'no_data_found';
  end if;
  if v_version.status <> 'draft' then
    raise exception 'invalid_transition: milestone template % is % and can no longer be edited', p_version_id, v_version.status
      using errcode = 'check_violation';
  end if;

  if p_sequence is null or jsonb_typeof(p_sequence) <> 'array' then
    raise exception 'milestone_invalid_sequence: sequence must be a jsonb array' using errcode = 'check_violation';
  end if;

  for v_element in select * from jsonb_array_elements(p_sequence) loop
    v_code := v_element ->> 'code';
    if v_code is null or length(v_code) = 0 then
      raise exception 'milestone_invalid_sequence: every sequence element requires a non-empty code' using errcode = 'check_violation';
    end if;
    if not exists (select 1 from app.milestone_codes where code = v_code) then
      raise exception 'milestone_unknown_code: % is not a registered milestone code', v_code using errcode = 'check_violation';
    end if;
  end loop;

  if not app.has_active_tenant_membership(v_version.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % holds no active membership for tenant %', p_actor_auth_user_id, v_version.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_version.tenant_id, 'OPS', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_version.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.milestone_template_versions
  set sequence = p_sequence
  where id = p_version_id
  returning * into v_version;

  perform app.capture_audit_event(
    v_version.tenant_id, p_actor_auth_user_id, p_actor_label, 'set_milestone_template_sequence',
    'app.milestone_template_versions', v_version.id, 'success', null, null, jsonb_build_object('sequence', p_sequence)
  );

  return v_version;
end;
$$;

-- Publish-time structural gate: non-empty, every code real, no duplicate code.
create function app.publish_milestone_template_version(
  p_version_id uuid,
  p_expected_version integer,
  p_supersedes_version_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.milestone_template_versions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_version app.milestone_template_versions;
  v_superseded app.milestone_template_versions;
  v_decision app.rbac_decision;
  v_element jsonb;
  v_seen text[] := array[]::text[];
  v_code text;
begin
  select * into v_version from app.milestone_template_versions where id = p_version_id;
  if not found then
    raise exception 'milestone_template_not_found: %', p_version_id using errcode = 'no_data_found';
  end if;
  if v_version.record_version <> p_expected_version then
    raise exception 'stale_version: milestone template % expected version % but found %', p_version_id, p_expected_version, v_version.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_version.status <> 'draft' then
    raise exception 'invalid_transition: milestone template % is % and cannot be published', p_version_id, v_version.status
      using errcode = 'check_violation';
  end if;
  if jsonb_array_length(v_version.sequence) = 0 then
    raise exception 'milestone_invalid_sequence: a milestone template cannot publish with an empty sequence' using errcode = 'check_violation';
  end if;

  for v_element in select * from jsonb_array_elements(v_version.sequence) loop
    v_code := v_element ->> 'code';
    if not exists (select 1 from app.milestone_codes where code = v_code) then
      raise exception 'milestone_unknown_code: % is not a registered milestone code', v_code using errcode = 'check_violation';
    end if;
    if v_code = any (v_seen) then
      raise exception 'milestone_duplicate_code: % appears more than once in the sequence', v_code using errcode = 'check_violation';
    end if;
    v_seen := array_append(v_seen, v_code);
  end loop;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_version.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_version.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_supersedes_version_id is not null then
    select * into v_superseded from app.milestone_template_versions where id = p_supersedes_version_id;
    if not found then
      raise exception 'milestone_template_not_found: supersedes target % not found', p_supersedes_version_id using errcode = 'no_data_found';
    end if;
    if v_superseded.status = 'published' then
      update app.milestone_template_versions set status = 'archived' where id = p_supersedes_version_id;
    end if;
  end if;

  update app.milestone_template_versions
  set status = 'published', supersedes_version_id = p_supersedes_version_id
  where id = p_version_id and record_version = p_expected_version
  returning * into v_version;

  perform app.capture_audit_event(
    v_version.tenant_id, p_actor_auth_user_id, p_actor_label, 'publish_milestone_template_version',
    'app.milestone_template_versions', v_version.id, 'success', null, null,
    jsonb_build_object('mode', v_version.mode, 'supersedes_version_id', p_supersedes_version_id)
  );

  return v_version;
end;
$$;

create table app.milestone_events (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  shipment_order_id uuid not null references app.shipment_orders (id),
  milestone_code text not null references app.milestone_codes (code),
  event_time timestamptz not null,
  received_time timestamptz not null default now(),
  location jsonb,
  source text not null,
  reason text,
  corrects_event_id uuid references app.milestone_events (id),
  idempotency_key text not null,
  sequence_no integer not null,
  created_by text,
  created_at timestamptz not null default now(),
  constraint milestone_events_source_check check (source in ('manual', 'api', 'webhook', 'import')),
  constraint milestone_events_tenant_shipment_idempotency_unique unique (tenant_id, shipment_order_id, idempotency_key),
  constraint milestone_events_not_self_corrects check (corrects_event_id is null or corrects_event_id <> id)
);

comment on table app.milestone_events is
  'OPS-173: append-only (no update/delete path exists anywhere in this migration -- a correction is a new row whose corrects_event_id points backward, per Prompt 173 §24). event_time is when the milestone actually occurred; received_time is when the platform learned about it -- deliberately distinct, both retained. Idempotent on (tenant_id, shipment_order_id, idempotency_key); sequence_no is a server-assigned per-shipment monotonic ordinal, never caller-supplied, used only as a deterministic tie-break in projection recalculation, never as a state-machine transition validator (that remains OPS-170''s own app.transition_shipment_order, not duplicated here).';

create index milestone_events_tenant_shipment_idx on app.milestone_events (tenant_id, shipment_order_id, event_time);
create index milestone_events_tenant_code_idx on app.milestone_events (tenant_id, milestone_code);

create table app.shipment_milestone_projections (
  shipment_order_id uuid primary key references app.shipment_orders (id),
  tenant_id uuid not null references app.tenants (id),
  last_milestone_code text references app.milestone_codes (code),
  last_milestone_event_time timestamptz,
  last_milestone_received_time timestamptz,
  current_eta timestamptz,
  current_location jsonb,
  is_delayed boolean not null default false,
  event_count integer not null default 0,
  record_version integer not null default 1,
  updated_at timestamptz not null default now()
);

comment on table app.shipment_milestone_projections is
  'OPS-173: the one deterministic, replay-safe current-state projection per Shipment Order -- fully recalculated from every app.milestone_events row on that shipment each time a new event is ingested (never an incremental patch), so duplicate/out-of-order/replayed events always converge to the same result (Prompt 173 §25). current_eta is this MVP''s own disclosed simplification: the most recent event_time among affects_eta-flagged events (an observed/projected marker, never a predictive ETA algorithm, which remains out of this bounded capability''s scope). is_delayed is a simple, deterministic heuristic: the shipment''s own planned_delivery_at has passed and no terminal milestone has yet been reached.';

create function app.touch_shipment_milestone_projection_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger shipment_milestone_projections_touch_row
  before update on app.shipment_milestone_projections
  for each row
  execute function app.touch_shipment_milestone_projection_row();

-- Internal-only recompute, called by app.ingest_milestone_event after every real
-- event insert. Never exposed to authenticated -- there is no user-facing "recompute"
-- action in this bounded capability.
create function app.recalculate_shipment_milestone_projection(p_shipment_order_id uuid)
returns app.shipment_milestone_projections
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_shipment app.shipment_orders;
  v_last record;
  v_last_eta record;
  v_last_location record;
  v_event_count integer;
  v_is_delayed boolean;
  v_projection app.shipment_milestone_projections;
begin
  select * into v_shipment from app.shipment_orders where id = p_shipment_order_id;
  if not found then
    raise exception 'shipment_order_not_found: %', p_shipment_order_id using errcode = 'no_data_found';
  end if;

  select e.milestone_code, e.event_time, e.received_time into v_last
  from app.milestone_events e
  where e.shipment_order_id = p_shipment_order_id
  order by e.event_time desc, e.received_time desc, e.sequence_no desc
  limit 1;

  select e.event_time into v_last_eta
  from app.milestone_events e
  join app.milestone_codes mc on mc.code = e.milestone_code
  where e.shipment_order_id = p_shipment_order_id and mc.affects_eta
  order by e.event_time desc, e.received_time desc, e.sequence_no desc
  limit 1;

  select e.location into v_last_location
  from app.milestone_events e
  where e.shipment_order_id = p_shipment_order_id and e.location is not null
  order by e.event_time desc, e.received_time desc, e.sequence_no desc
  limit 1;

  select count(*) into v_event_count from app.milestone_events where shipment_order_id = p_shipment_order_id;

  v_is_delayed := (
    v_shipment.planned_delivery_at is not null
    and v_shipment.planned_delivery_at < now()
    and not exists (
      select 1 from app.milestone_events e
      join app.milestone_codes mc on mc.code = e.milestone_code
      where e.shipment_order_id = p_shipment_order_id and mc.is_terminal
    )
  );

  insert into app.shipment_milestone_projections (
    shipment_order_id, tenant_id, last_milestone_code, last_milestone_event_time, last_milestone_received_time,
    current_eta, current_location, is_delayed, event_count
  ) values (
    p_shipment_order_id, v_shipment.tenant_id, v_last.milestone_code, v_last.event_time, v_last.received_time,
    v_last_eta.event_time, v_last_location.location, v_is_delayed, v_event_count
  )
  on conflict (shipment_order_id) do update set
    last_milestone_code = excluded.last_milestone_code,
    last_milestone_event_time = excluded.last_milestone_event_time,
    last_milestone_received_time = excluded.last_milestone_received_time,
    current_eta = excluded.current_eta,
    current_location = excluded.current_location,
    is_delayed = excluded.is_delayed,
    event_count = excluded.event_count
  returning * into v_projection;

  return v_projection;
end;
$$;

-- The one path that creates a milestone event -- idempotent on (tenant_id,
-- shipment_order_id, idempotency_key); sequence_no is server-assigned, never
-- caller-supplied. A correction (p_corrects_event_id not null) requires a non-empty
-- reason and must reference a real, prior event on the same shipment.
create function app.ingest_milestone_event(
  p_shipment_order_id uuid,
  p_milestone_code text,
  p_event_time timestamptz,
  p_received_time timestamptz,
  p_location jsonb,
  p_source text,
  p_reason text,
  p_corrects_event_id uuid,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.milestone_events
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_corrected app.milestone_events;
  v_next_seq integer;
  v_event app.milestone_events;
begin
  if p_source not in ('manual', 'api', 'webhook', 'import') then
    raise exception 'milestone_invalid_source: % is not one of manual/api/webhook/import', p_source using errcode = 'check_violation';
  end if;
  if not exists (select 1 from app.milestone_codes where code = p_milestone_code) then
    raise exception 'milestone_unknown_code: % is not a registered milestone code', p_milestone_code using errcode = 'check_violation';
  end if;

  select * into v_shipment from app.shipment_orders where id = p_shipment_order_id;
  if not found then
    raise exception 'shipment_order_not_found: %', p_shipment_order_id using errcode = 'no_data_found';
  end if;
  if v_shipment.status = 'cancelled' then
    raise exception 'invalid_transition: shipment order % is cancelled and can no longer receive milestone events', p_shipment_order_id
      using errcode = 'check_violation';
  end if;

  if p_corrects_event_id is not null then
    if p_reason is null or length(trim(p_reason)) = 0 then
      raise exception 'reason_required: a correction requires a non-empty reason' using errcode = 'check_violation';
    end if;
    select * into v_corrected from app.milestone_events where id = p_corrects_event_id and shipment_order_id = p_shipment_order_id;
    if not found then
      raise exception 'milestone_event_not_found: % is not a prior event on shipment order %', p_corrects_event_id, p_shipment_order_id
        using errcode = 'no_data_found';
    end if;
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

  select * into v_event from app.milestone_events where tenant_id = v_shipment.tenant_id and shipment_order_id = p_shipment_order_id and idempotency_key = p_idempotency_key;
  if found then
    return v_event;
  end if;

  select coalesce(max(sequence_no), 0) + 1 into v_next_seq from app.milestone_events where shipment_order_id = p_shipment_order_id;

  insert into app.milestone_events (
    tenant_id, shipment_order_id, milestone_code, event_time, received_time, location, source, reason, corrects_event_id, idempotency_key, sequence_no, created_by
  ) values (
    v_shipment.tenant_id, p_shipment_order_id, p_milestone_code, p_event_time, coalesce(p_received_time, now()), p_location, p_source, p_reason, p_corrects_event_id, p_idempotency_key, v_next_seq, p_actor_label
  )
  returning * into v_event;

  perform app.recalculate_shipment_milestone_projection(p_shipment_order_id);

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'ingest_milestone_event',
    'app.milestone_events', v_event.id, 'success', null, null,
    jsonb_build_object('shipment_order_id', p_shipment_order_id, 'milestone_code', p_milestone_code, 'source', p_source, 'corrects_event_id', p_corrects_event_id)
  );

  return v_event;
exception
  when unique_violation then
    select * into v_event from app.milestone_events where tenant_id = v_shipment.tenant_id and shipment_order_id = p_shipment_order_id and idempotency_key = p_idempotency_key;
    return v_event;
end;
$$;

comment on function app.ingest_milestone_event is
  'OPS-173: the one path that ingests a milestone event -- idempotent on (tenant_id, shipment_order_id, idempotency_key), never blocked by out-of-order event_time (an earlier-dated event may be ingested after a later one; the projection recalculation, not insertion order, is what stays deterministic). Blocked only once the shipment is cancelled. A correction requires a non-empty reason and a real prior event on the same shipment.';

create function app.get_shipment_milestone_timeline(
  p_shipment_order_id uuid,
  p_actor_auth_user_id uuid,
  p_customer_visible_only boolean default false
)
returns setof app.milestone_events
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
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

  return query
    select e.* from app.milestone_events e
    join app.milestone_codes mc on mc.code = e.milestone_code
    where e.shipment_order_id = p_shipment_order_id
      and (not p_customer_visible_only or mc.is_customer_visible)
    order by e.event_time asc, e.received_time asc, e.sequence_no asc;
end;
$$;

comment on function app.get_shipment_milestone_timeline is
  'OPS-173: authority-gated (OPS:View + record scope), ordered oldest-first. p_customer_visible_only=true filters to only app.milestone_codes.is_customer_visible codes -- the one mechanism Prompt 173 §25''s "customer-visible timeline excludes internal/sensitive events... by policy" requires; the actual customer/public-facing tracking surface itself is a later, separate capability (Basic Public Tracking) that will consume this same filtered projection, not built here.';

create function app.get_shipment_milestone_projection(
  p_shipment_order_id uuid,
  p_actor_auth_user_id uuid
)
returns app.shipment_milestone_projections
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_projection app.shipment_milestone_projections;
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

  select * into v_projection from app.shipment_milestone_projections where shipment_order_id = p_shipment_order_id;
  return v_projection;
end;
$$;

alter table app.milestone_codes enable row level security;
alter table app.milestone_template_versions enable row level security;
alter table app.milestone_events enable row level security;
alter table app.shipment_milestone_projections enable row level security;

create policy milestone_codes_select_authenticated on app.milestone_codes
  for select to authenticated
  using (true);

create policy milestone_template_versions_select_scoped on app.milestone_template_versions
  for select to authenticated
  using (app.has_active_tenant_membership(tenant_id) or app.is_supreme_admin());

create policy milestone_events_select_scoped on app.milestone_events
  for select to authenticated
  using (
    exists (
      select 1 from app.shipment_orders so
      where so.id = milestone_events.shipment_order_id
        and app.can_access_record(auth.uid(), so.tenant_id, so.owner_user_id, app.lead_record_scope_org_unit_ids(so.org_unit_id), null)
    )
  );

create policy shipment_milestone_projections_select_scoped on app.shipment_milestone_projections
  for select to authenticated
  using (
    exists (
      select 1 from app.shipment_orders so
      where so.id = shipment_milestone_projections.shipment_order_id
        and app.can_access_record(auth.uid(), so.tenant_id, so.owner_user_id, app.lead_record_scope_org_unit_ids(so.org_unit_id), null)
    )
  );

revoke execute on all functions in schema app from public;

grant select on app.milestone_codes to authenticated, service_role;
grant insert, update, delete on app.milestone_codes to service_role;
grant select on app.milestone_template_versions to authenticated, service_role;
grant insert, update, delete on app.milestone_template_versions to service_role;
grant select on app.milestone_events to authenticated, service_role;
grant insert, update, delete on app.milestone_events to service_role;
grant select on app.shipment_milestone_projections to authenticated, service_role;
grant insert, update, delete on app.shipment_milestone_projections to service_role;

grant execute on function app.register_milestone_code(text, text, text, boolean, boolean, boolean, uuid, text) to service_role;
grant execute on function app.create_milestone_template_draft(uuid, text, uuid, text) to authenticated, service_role;
grant execute on function app.set_milestone_template_sequence(uuid, jsonb, uuid, text) to authenticated, service_role;
grant execute on function app.publish_milestone_template_version(uuid, integer, uuid, uuid, text) to authenticated, service_role;
grant execute on function app.recalculate_shipment_milestone_projection(uuid) to service_role;
grant execute on function app.ingest_milestone_event(uuid, text, timestamptz, timestamptz, jsonb, text, text, uuid, text, uuid, text) to authenticated, service_role;
grant execute on function app.get_shipment_milestone_timeline(uuid, uuid, boolean) to authenticated, service_role;
grant execute on function app.get_shipment_milestone_projection(uuid, uuid) to authenticated, service_role;
