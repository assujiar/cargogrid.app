-- Commercial capability COM-145 (Contact and Activity Management, CG-S7-COM-004)
-- Canonical, reusable contacts plus a polymorphic relationship link to a Commercial
-- record (lead or prospect today; extended by later capabilities, never forked), and a
-- unified activity timeline (call/email/meeting/visit/follow_up/task) against the same
-- polymorphic target. Reuses COM-143's app.normalize_lead_email/app.normalize_lead_phone
-- directly (generic despite their name -- see that migration's own header) and
-- COM-143's app.lead_record_scope_org_unit_ids for record-scope, rather than duplicating
-- either.
--
-- Scope boundary (disclosed, not silently narrowed): standalone canonical "site/address"
-- entities named in Prompt 145 §13 are deferred to whichever later capability first needs
-- a durable, reusable address master against a real account/customer row (COM-155/156) --
-- app.prospects (COM-144) already carries its own billing_address snapshot for its own
-- narrow need. Building a second interim site/address model here, before any capability
-- actually needs multi-site tracking, would risk exactly the "two masters to reconcile
-- later" duplication this repository's own binding rules forbid.

-- Shared polymorphic-target resolver: every future polymorphic link/activity table this
-- phase adds can reuse this one function rather than re-deriving tenant/owner/org_unit
-- lookup logic per table. Raises on an unknown related_type or a related_id that does not
-- exist -- callers never silently proceed against a dangling reference.
create function app.resolve_commercial_record_ref(
  p_related_type text,
  p_related_id uuid
)
returns table (tenant_id uuid, owner_user_id uuid, org_unit_id uuid)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
begin
  if p_related_type = 'lead' then
    return query select l.tenant_id, l.owner_user_id, l.org_unit_id from app.leads l where l.id = p_related_id;
  elsif p_related_type = 'prospect' then
    return query select p.tenant_id, p.owner_user_id, p.org_unit_id from app.prospects p where p.id = p_related_id;
  else
    raise exception 'unknown_related_type: %', p_related_type using errcode = 'check_violation';
  end if;

  if not found then
    raise exception 'related_record_not_found: % %', p_related_type, p_related_id using errcode = 'no_data_found';
  end if;
end;
$$;

comment on function app.resolve_commercial_record_ref is
  'COM-145: the one shared polymorphic-target resolver for contact_links/activities (and any later Commercial polymorphic table) -- extend the IF/ELSIF chain here, never add a second competing resolver.';

create table app.contacts (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  full_name text not null,
  title text,
  email text,
  phone text,
  normalized_email text,
  normalized_phone text,
  duplicate_fingerprint text not null,
  status text not null default 'active',
  owner_user_id uuid references auth.users (id),
  org_unit_id uuid references app.org_units (id),
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint contacts_status_check check (status in ('active', 'archived')),
  constraint contacts_contact_identifier_check check (email is not null or phone is not null)
);

comment on table app.contacts is
  'COM-145: canonical, tenant-scoped person identity, reusable across lead/prospect/(future account/opportunity/quotation) contexts via app.contact_links -- never re-typed per relationship. Record-scope follows the contact''s own owner_user_id/org_unit_id (a deliberate simplification over per-relationship visibility -- disclosed in COM-145''s own build log).';

create index contacts_tenant_fingerprint_idx on app.contacts (tenant_id, duplicate_fingerprint);
create index contacts_tenant_owner_idx on app.contacts (tenant_id, owner_user_id);
create index contacts_tenant_status_idx on app.contacts (tenant_id, status);

create function app.compute_contact_duplicate_fingerprint(
  p_tenant_id uuid,
  p_normalized_email text,
  p_normalized_phone text
)
returns text
language sql
immutable
as $$
  select md5(
    p_tenant_id::text || '|' ||
    coalesce(p_normalized_email, '') || '|' ||
    coalesce(p_normalized_phone, '')
  );
$$;

comment on function app.compute_contact_duplicate_fingerprint is
  'COM-145: a person-identity fingerprint (email + phone only, no organization name -- unlike app.compute_lead_duplicate_fingerprint/app.compute_prospect_duplicate_fingerprint, a contact is not itself an organization).';

create function app.set_contact_computed_fields()
returns trigger
language plpgsql
as $$
begin
  new.normalized_email := app.normalize_lead_email(new.email);
  new.normalized_phone := app.normalize_lead_phone(new.phone);
  new.duplicate_fingerprint := app.compute_contact_duplicate_fingerprint(new.tenant_id, new.normalized_email, new.normalized_phone);
  new.updated_at := now();
  return new;
end;
$$;

create trigger contacts_set_computed_fields
  before insert or update of email, phone on app.contacts
  for each row
  execute function app.set_contact_computed_fields();

create function app.find_duplicate_contacts(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_email text,
  p_phone text
)
returns setof app.contacts
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_fingerprint text;
begin
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % holds no active membership for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_fingerprint := app.compute_contact_duplicate_fingerprint(
    p_tenant_id, app.normalize_lead_email(p_email), app.normalize_lead_phone(p_phone)
  );

  return query
    select * from app.contacts
    where tenant_id = p_tenant_id
      and duplicate_fingerprint = v_fingerprint
      and status = 'active'
    order by created_at;
end;
$$;

create function app.create_contact(
  p_tenant_id uuid,
  p_full_name text,
  p_title text,
  p_email text,
  p_phone text,
  p_owner_user_id uuid,
  p_org_unit_id uuid,
  p_actor_auth_user_id uuid,
  p_created_by text
)
returns app.contacts
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_contact app.contacts;
  v_decision app.rbac_decision;
begin
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % holds no active membership for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'COM', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  insert into app.contacts (tenant_id, full_name, title, email, phone, owner_user_id, org_unit_id, created_by)
  values (p_tenant_id, p_full_name, p_title, p_email, p_phone, p_owner_user_id, p_org_unit_id, p_created_by)
  returning * into v_contact;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_created_by, 'create_contact',
    'app.contacts', v_contact.id, 'success', null, null, to_jsonb(v_contact)
  );

  return v_contact;
end;
$$;

comment on function app.create_contact is
  'COM-145: always creates a new row -- never idempotent on an external key (unlike app.capture_lead), since a manually-entered contact has no external system of record. Duplicate review is the caller''s own responsibility via app.find_duplicate_contacts before calling this (Prompt 145 §21/§22: reuse or create, never both silently).';

create table app.contact_links (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  contact_id uuid not null references app.contacts (id),
  related_type text not null,
  related_id uuid not null,
  role text not null default 'other',
  is_primary boolean not null default false,
  created_by text,
  created_at timestamptz not null default now(),
  constraint contact_links_related_type_check check (related_type in ('lead', 'prospect')),
  constraint contact_links_role_check check (role in ('primary', 'billing', 'technical', 'decision_maker', 'other')),
  constraint contact_links_unique unique (contact_id, related_type, related_id, role)
);

comment on table app.contact_links is
  'COM-145: the polymorphic contact<->record relationship (Prompt 145 §22 alternative flow: "linked... without copying the contact record"). One contact may hold several roles on the same record (several rows) -- never a second contact row for the same person.';

create index contact_links_related_idx on app.contact_links (related_type, related_id);
create index contact_links_contact_idx on app.contact_links (contact_id);

create function app.link_contact_to_record(
  p_contact_id uuid,
  p_related_type text,
  p_related_id uuid,
  p_role text,
  p_is_primary boolean,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.contact_links
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_contact app.contacts;
  v_ref record;
  v_link app.contact_links;
  v_decision app.rbac_decision;
begin
  select * into v_contact from app.contacts where id = p_contact_id;
  if not found then
    raise exception 'contact_not_found: %', p_contact_id using errcode = 'no_data_found';
  end if;

  select * into v_ref from app.resolve_commercial_record_ref(p_related_type, p_related_id);

  if v_contact.tenant_id <> v_ref.tenant_id then
    raise exception 'cross_tenant_link_denied: contact and record belong to different tenants'
      using errcode = 'insufficient_privilege';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_contact.tenant_id, 'COM', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_contact.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not (
    app.can_access_record(p_actor_auth_user_id, v_contact.tenant_id, v_contact.owner_user_id, app.lead_record_scope_org_unit_ids(v_contact.org_unit_id), null)
    and app.can_access_record(p_actor_auth_user_id, v_ref.tenant_id, v_ref.owner_user_id, app.lead_record_scope_org_unit_ids(v_ref.org_unit_id), null)
  ) then
    raise exception 'insufficient_authority: identity % cannot access both the contact and the record', p_actor_auth_user_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_link from app.contact_links
  where contact_id = p_contact_id and related_type = p_related_type and related_id = p_related_id and role = p_role;
  if found then
    return v_link;
  end if;

  insert into app.contact_links (tenant_id, contact_id, related_type, related_id, role, is_primary, created_by)
  values (v_contact.tenant_id, p_contact_id, p_related_type, p_related_id, p_role, coalesce(p_is_primary, false), p_actor_label)
  returning * into v_link;

  perform app.capture_audit_event(
    v_contact.tenant_id, p_actor_auth_user_id, p_actor_label, 'link_contact_to_record',
    'app.contact_links', v_link.id, 'success', null, null, to_jsonb(v_link)
  );

  return v_link;
exception
  when unique_violation then
    select * into v_link from app.contact_links
    where contact_id = p_contact_id and related_type = p_related_type and related_id = p_related_id and role = p_role;
    return v_link;
end;
$$;

comment on function app.link_contact_to_record is
  'COM-145: idempotent on (contact_id, related_type, related_id, role) including under a concurrent-insert race. Requires record-scope access to both the contact and the target record, and COM:Edit.';

create function app.unlink_contact_from_record(
  p_link_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns void
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_link app.contact_links;
  v_ref record;
  v_decision app.rbac_decision;
begin
  select * into v_link from app.contact_links where id = p_link_id;
  if not found then
    raise exception 'contact_link_not_found: %', p_link_id using errcode = 'no_data_found';
  end if;

  select * into v_ref from app.resolve_commercial_record_ref(v_link.related_type, v_link.related_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_link.tenant_id, 'COM', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_link.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_ref.tenant_id, v_ref.owner_user_id, app.lead_record_scope_org_unit_ids(v_ref.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access the linked record', p_actor_auth_user_id
      using errcode = 'insufficient_privilege';
  end if;

  delete from app.contact_links where id = p_link_id;

  perform app.capture_audit_event(
    v_link.tenant_id, p_actor_auth_user_id, p_actor_label, 'unlink_contact_from_record',
    'app.contact_links', p_link_id, 'success', null, to_jsonb(v_link), null
  );
end;
$$;

create table app.activities (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  type text not null,
  subject text not null,
  notes text,
  status text not null default 'scheduled',
  due_at timestamptz,
  completed_at timestamptz,
  outcome text,
  related_type text not null,
  related_id uuid not null,
  contact_id uuid references app.contacts (id),
  owner_user_id uuid references auth.users (id),
  org_unit_id uuid references app.org_units (id),
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint activities_type_check check (type in ('call', 'email', 'meeting', 'visit', 'follow_up', 'task')),
  constraint activities_status_check check (status in ('scheduled', 'completed', 'cancelled')),
  constraint activities_related_type_check check (related_type in ('lead', 'prospect')),
  constraint activities_completed_check check (
    (status = 'completed' and completed_at is not null)
    or (status <> 'completed')
  )
);

comment on table app.activities is
  'COM-145: append-oriented business history (Prompt 145 §24: "corrections preserve before/after evidence") -- app.capture_audit_event''s own before/after payload is that evidence; a row is never deleted, only transitioned scheduled -> completed/cancelled.';

create index activities_tenant_related_idx on app.activities (tenant_id, related_type, related_id);
create index activities_tenant_owner_idx on app.activities (tenant_id, owner_user_id);
create index activities_tenant_due_idx on app.activities (tenant_id, due_at) where status = 'scheduled';
create index activities_contact_idx on app.activities (contact_id) where contact_id is not null;

create function app.log_activity(
  p_related_type text,
  p_related_id uuid,
  p_contact_id uuid,
  p_type text,
  p_subject text,
  p_notes text,
  p_status text,
  p_due_at timestamptz,
  p_completed_at timestamptz,
  p_outcome text,
  p_owner_user_id uuid,
  p_org_unit_id uuid,
  p_actor_auth_user_id uuid,
  p_created_by text
)
returns app.activities
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_ref record;
  v_activity app.activities;
  v_decision app.rbac_decision;
begin
  select * into v_ref from app.resolve_commercial_record_ref(p_related_type, p_related_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_ref.tenant_id, 'COM', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_ref.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_ref.tenant_id, v_ref.owner_user_id, app.lead_record_scope_org_unit_ids(v_ref.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access the linked record', p_actor_auth_user_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_contact_id is not null and not exists (select 1 from app.contacts where id = p_contact_id and tenant_id = v_ref.tenant_id) then
    raise exception 'contact_not_found: % (or belongs to a different tenant)', p_contact_id using errcode = 'no_data_found';
  end if;

  insert into app.activities (
    tenant_id, type, subject, notes, status, due_at, completed_at, outcome,
    related_type, related_id, contact_id, owner_user_id, org_unit_id, created_by
  ) values (
    v_ref.tenant_id, p_type, p_subject, p_notes, coalesce(p_status, 'scheduled'), p_due_at, p_completed_at, p_outcome,
    p_related_type, p_related_id, p_contact_id, coalesce(p_owner_user_id, v_ref.owner_user_id), coalesce(p_org_unit_id, v_ref.org_unit_id), p_created_by
  )
  returning * into v_activity;

  perform app.capture_audit_event(
    v_activity.tenant_id, p_actor_auth_user_id, p_created_by, 'log_activity',
    'app.activities', v_activity.id, 'success', null, null, to_jsonb(v_activity)
  );

  return v_activity;
end;
$$;

comment on function app.log_activity is
  'COM-145: covers both "already happened" activities (call/email/meeting/visit logged with status=completed and completed_at set directly) and "to do" activities (follow_up/task logged with status=scheduled and due_at set) -- the caller chooses the initial status, this function does not infer it from type.';

create function app.complete_activity(
  p_activity_id uuid,
  p_expected_version integer,
  p_outcome text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.activities
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_activity app.activities;
begin
  select * into v_activity from app.activities where id = p_activity_id;
  if not found then
    raise exception 'activity_not_found: %', p_activity_id using errcode = 'no_data_found';
  end if;

  if v_activity.record_version <> p_expected_version then
    raise exception 'stale_version: activity % expected version % but found %', p_activity_id, p_expected_version, v_activity.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_activity.status <> 'scheduled' then
    raise exception 'invalid_transition: activity % is % and cannot be completed', p_activity_id, v_activity.status
      using errcode = 'check_violation';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_activity.tenant_id, v_activity.owner_user_id, app.lead_record_scope_org_unit_ids(v_activity.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access activity %', p_actor_auth_user_id, p_activity_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.activities
  set status = 'completed', completed_at = now(), outcome = p_outcome, updated_at = now(), record_version = record_version + 1
  where id = p_activity_id and record_version = p_expected_version
  returning * into v_activity;

  perform app.capture_audit_event(
    v_activity.tenant_id, p_actor_auth_user_id, p_actor_label, 'complete_activity',
    'app.activities', v_activity.id, 'success', null, null, jsonb_build_object('outcome', p_outcome)
  );

  return v_activity;
end;
$$;

create function app.reschedule_activity(
  p_activity_id uuid,
  p_expected_version integer,
  p_new_due_at timestamptz,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.activities
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_activity app.activities;
begin
  select * into v_activity from app.activities where id = p_activity_id;
  if not found then
    raise exception 'activity_not_found: %', p_activity_id using errcode = 'no_data_found';
  end if;

  if v_activity.record_version <> p_expected_version then
    raise exception 'stale_version: activity % expected version % but found %', p_activity_id, p_expected_version, v_activity.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_activity.status <> 'scheduled' then
    raise exception 'invalid_transition: activity % is % and cannot be rescheduled', p_activity_id, v_activity.status
      using errcode = 'check_violation';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_activity.tenant_id, v_activity.owner_user_id, app.lead_record_scope_org_unit_ids(v_activity.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access activity %', p_actor_auth_user_id, p_activity_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.activities
  set due_at = p_new_due_at, updated_at = now(), record_version = record_version + 1
  where id = p_activity_id and record_version = p_expected_version
  returning * into v_activity;

  perform app.capture_audit_event(
    v_activity.tenant_id, p_actor_auth_user_id, p_actor_label, 'reschedule_activity',
    'app.activities', v_activity.id, 'success', null, null, jsonb_build_object('new_due_at', p_new_due_at)
  );

  return v_activity;
end;
$$;

create function app.cancel_activity(
  p_activity_id uuid,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.activities
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_activity app.activities;
begin
  select * into v_activity from app.activities where id = p_activity_id;
  if not found then
    raise exception 'activity_not_found: %', p_activity_id using errcode = 'no_data_found';
  end if;

  if v_activity.record_version <> p_expected_version then
    raise exception 'stale_version: activity % expected version % but found %', p_activity_id, p_expected_version, v_activity.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_activity.status <> 'scheduled' then
    raise exception 'invalid_transition: activity % is % and cannot be cancelled', p_activity_id, v_activity.status
      using errcode = 'check_violation';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_activity.tenant_id, v_activity.owner_user_id, app.lead_record_scope_org_unit_ids(v_activity.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access activity %', p_actor_auth_user_id, p_activity_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.activities
  set status = 'cancelled', updated_at = now(), record_version = record_version + 1
  where id = p_activity_id and record_version = p_expected_version
  returning * into v_activity;

  perform app.capture_audit_event(
    v_activity.tenant_id, p_actor_auth_user_id, p_actor_label, 'cancel_activity',
    'app.activities', v_activity.id, 'success', null, null, null
  );

  return v_activity;
end;
$$;

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit, directly-provable revoke
-- of PostgreSQL's PUBLIC-execute default, the standing per-migration convention since
-- PLT-118, applied here before any role-specific grant.
revoke execute on all functions in schema app from public;

alter table app.contacts enable row level security;
alter table app.contact_links enable row level security;
alter table app.activities enable row level security;

create policy contacts_select_scoped on app.contacts
  for select to authenticated
  using (
    app.can_access_record(auth.uid(), tenant_id, owner_user_id, app.lead_record_scope_org_unit_ids(org_unit_id), null)
  );

-- app.contact_links is a thin join record -- tenant-membership-scoped rather than
-- re-deriving contact/record-level scope a second time (the linked contact and record
-- rows themselves already enforce that at their own RLS layer; a tenant member seeing a
-- bare link row learns only that some contact is linked to some record it may or may not
-- itself be able to open). Disclosed trade-off, not an oversight -- see COM-145's build log.
create policy contact_links_select_scoped on app.contact_links
  for select to authenticated
  using (app.has_active_tenant_membership(tenant_id));

create policy activities_select_scoped on app.activities
  for select to authenticated
  using (
    app.can_access_record(auth.uid(), tenant_id, owner_user_id, app.lead_record_scope_org_unit_ids(org_unit_id), null)
  );

grant usage on schema app to authenticated;
grant select on app.contacts to authenticated, service_role;
grant select on app.contact_links to authenticated, service_role;
grant select on app.activities to authenticated, service_role;
grant insert, update, delete on app.contacts to service_role;
grant insert, update, delete on app.contact_links to service_role;
grant insert, update, delete on app.activities to service_role;

grant execute on function app.resolve_commercial_record_ref(text, uuid) to authenticated, service_role;
grant execute on function app.compute_contact_duplicate_fingerprint(uuid, text, text) to authenticated, service_role;
grant execute on function app.find_duplicate_contacts(uuid, uuid, text, text) to authenticated, service_role;
grant execute on function app.create_contact(uuid, text, text, text, text, uuid, uuid, uuid, text) to authenticated, service_role;
grant execute on function app.link_contact_to_record(uuid, text, uuid, text, boolean, uuid, text) to authenticated, service_role;
grant execute on function app.unlink_contact_from_record(uuid, uuid, text) to authenticated, service_role;
grant execute on function app.log_activity(text, uuid, uuid, text, text, text, text, timestamptz, timestamptz, text, uuid, uuid, uuid, text) to authenticated, service_role;
grant execute on function app.complete_activity(uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.reschedule_activity(uuid, integer, timestamptz, uuid, text) to authenticated, service_role;
grant execute on function app.cancel_activity(uuid, integer, uuid, text) to authenticated, service_role;
