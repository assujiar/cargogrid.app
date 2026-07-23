-- Commercial capability COM-144 (Prospect Lifecycle, CG-S7-COM-003)
-- Prospect is a governed pre-customer commercial identity: a qualified lead converts
-- exactly once (idempotent on lead_id), preserving source lineage, a contact snapshot
-- (never a live re-typed copy), and conversion-readiness evaluation. Prospect is not a
-- customer -- COM-155 (Customer and Account Conversion) owns the actual customer/account
-- master creation; this capability stops at "is this prospect ready," never creates one.
--
-- Reuses COM-143's own app.lead_record_scope_org_unit_ids wrapper for record-scope --
-- despite its lead-specific name, its body is generic (ancestors + self of an org unit),
-- and creating a byte-identical second wrapper here would be exactly the "duplicate
-- utility" AGENTS.md forbids. A future cleanup could rename it; not done here (renaming
-- would require editing COM-143's own applied migration, which this repository's
-- immutable-migrations convention forbids).

create table app.prospects (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  lead_id uuid not null references app.leads (id),
  legal_name text not null,
  trade_name text,
  tax_id text,
  normalized_legal_name text,
  normalized_tax_id text,
  duplicate_fingerprint text not null,
  billing_address jsonb not null default '{}'::jsonb,
  contact_name text not null,
  contact_email text,
  contact_phone text,
  status text not null default 'active',
  disqualify_reason text,
  owner_user_id uuid references auth.users (id),
  org_unit_id uuid references app.org_units (id),
  merged_into_id uuid references app.prospects (id),
  merged_at timestamptz,
  merged_by text,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint prospects_status_check check (status in ('active', 'disqualified', 'archived', 'merged')),
  constraint prospects_lead_unique unique (lead_id),
  constraint prospects_disqualify_reason_check check (
    (status = 'disqualified' and disqualify_reason is not null and length(trim(disqualify_reason)) > 0)
    or (status <> 'disqualified')
  ),
  constraint prospects_merged_check check (
    (status = 'merged' and merged_into_id is not null)
    or (status <> 'merged' and merged_into_id is null)
  ),
  constraint prospects_not_self_merged check (merged_into_id is null or merged_into_id <> id),
  constraint prospects_billing_address_check check (jsonb_typeof(billing_address) = 'object')
);

comment on table app.prospects is
  'COM-144: one row per qualified-lead-to-prospect conversion (unique on lead_id -- "one conversion idempotency key yields one prospect outcome," Prompt 144 §24). contact_name/email/phone are a snapshot taken at conversion time, never a live re-typed copy of the source lead -- the no-reentry binding rule. merged_into_id preserves lineage exactly like app.leads.merged_into_id -- the duplicate row is never deleted.';

create unique index prospects_tenant_lead_unique on app.prospects (tenant_id, lead_id);
create index prospects_tenant_fingerprint_idx on app.prospects (tenant_id, duplicate_fingerprint);
create index prospects_tenant_status_idx on app.prospects (tenant_id, status);
create index prospects_tenant_owner_idx on app.prospects (tenant_id, owner_user_id);
create index prospects_merged_into_idx on app.prospects (merged_into_id) where merged_into_id is not null;

alter table app.leads add column converted_prospect_id uuid references app.prospects (id);

comment on column app.leads.converted_prospect_id is
  'COM-144: set exactly once, by app.convert_lead_to_prospect or app.link_lead_to_existing_prospect, the moment a qualified lead becomes (or links to) a prospect. NULL unless status=''converted''.';

alter table app.leads add constraint leads_converted_prospect_check check (
  (status = 'converted' and converted_prospect_id is not null)
  or (status <> 'converted' and converted_prospect_id is null)
);

create function app.normalize_prospect_identifier(p_value text)
returns text
language sql
immutable
as $$
  select nullif(lower(trim(p_value)), '');
$$;

create function app.compute_prospect_duplicate_fingerprint(
  p_tenant_id uuid,
  p_normalized_legal_name text,
  p_normalized_tax_id text
)
returns text
language sql
immutable
as $$
  select md5(
    p_tenant_id::text || '|' ||
    coalesce(p_normalized_legal_name, '') || '|' ||
    coalesce(p_normalized_tax_id, '')
  );
$$;

comment on function app.compute_prospect_duplicate_fingerprint is
  'COM-144: deterministic identity key over normalized legal name + normalized tax id, scoped per tenant -- the same "tenant id is part of the hash input, never leaks cross-tenant" construction app.compute_lead_duplicate_fingerprint (COM-143) already established.';

create function app.set_prospect_computed_fields()
returns trigger
language plpgsql
as $$
begin
  new.normalized_legal_name := app.normalize_prospect_identifier(new.legal_name);
  new.normalized_tax_id := app.normalize_prospect_identifier(new.tax_id);
  new.duplicate_fingerprint := app.compute_prospect_duplicate_fingerprint(
    new.tenant_id, new.normalized_legal_name, new.normalized_tax_id
  );
  new.updated_at := now();
  return new;
end;
$$;

create trigger prospects_set_computed_fields
  before insert or update of legal_name, tax_id on app.prospects
  for each row
  execute function app.set_prospect_computed_fields();

create function app.find_duplicate_prospects(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_legal_name text,
  p_tax_id text
)
returns setof app.prospects
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

  v_fingerprint := app.compute_prospect_duplicate_fingerprint(
    p_tenant_id, app.normalize_prospect_identifier(p_legal_name), app.normalize_prospect_identifier(p_tax_id)
  );

  return query
    select * from app.prospects
    where tenant_id = p_tenant_id
      and duplicate_fingerprint = v_fingerprint
      and status <> 'merged'
    order by created_at;
end;
$$;

comment on function app.find_duplicate_prospects is
  'COM-144: tenant-scoped only, fails closed on missing membership -- structurally cannot probe another tenant''s prospects, the same discipline app.find_duplicate_leads (COM-143) already established.';

-- Idempotent lead-to-prospect conversion: a repeated call for the same lead_id returns
-- the existing prospect, never a second one (prospects_lead_unique enforces this even
-- under a concurrent-insert race, handled below exactly like app.capture_lead's own
-- unique_violation recovery, COM-143).
create function app.convert_lead_to_prospect(
  p_lead_id uuid,
  p_legal_name text,
  p_trade_name text,
  p_tax_id text,
  p_billing_address jsonb,
  p_actor_auth_user_id uuid,
  p_created_by text
)
returns app.prospects
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_lead app.leads;
  v_existing app.prospects;
  v_prospect app.prospects;
  v_decision app.rbac_decision;
begin
  select * into v_lead from app.leads where id = p_lead_id;
  if not found then
    raise exception 'lead_not_found: %', p_lead_id using errcode = 'no_data_found';
  end if;

  select * into v_existing from app.prospects where lead_id = p_lead_id;
  if found then
    return v_existing;
  end if;

  if v_lead.status <> 'qualified' then
    raise exception 'invalid_transition: lead % is % and cannot convert to a prospect (must be qualified)', p_lead_id, v_lead.status
      using errcode = 'check_violation';
  end if;

  if not app.can_access_record(
    p_actor_auth_user_id, v_lead.tenant_id, v_lead.owner_user_id,
    app.lead_record_scope_org_unit_ids(v_lead.org_unit_id),
    null
  ) then
    raise exception 'insufficient_authority: identity % cannot access lead %', p_actor_auth_user_id, p_lead_id
      using errcode = 'insufficient_privilege';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_lead.tenant_id, 'COM', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_lead.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  insert into app.prospects (
    tenant_id, lead_id, legal_name, trade_name, tax_id, billing_address,
    contact_name, contact_email, contact_phone, owner_user_id, org_unit_id, created_by
  ) values (
    v_lead.tenant_id, p_lead_id, p_legal_name, p_trade_name, p_tax_id, coalesce(p_billing_address, '{}'::jsonb),
    v_lead.contact_name, v_lead.email, v_lead.phone, v_lead.owner_user_id, v_lead.org_unit_id, p_created_by
  )
  returning * into v_prospect;

  update app.leads
  set status = 'converted', converted_at = now(), converted_prospect_id = v_prospect.id, last_activity_at = now(), record_version = record_version + 1
  where id = p_lead_id;

  perform app.capture_audit_event(
    v_lead.tenant_id, p_actor_auth_user_id, p_created_by, 'convert_lead_to_prospect',
    'app.prospects', v_prospect.id, 'success', null, null, to_jsonb(v_prospect)
  );

  return v_prospect;
exception
  when unique_violation then
    select * into v_existing from app.prospects where lead_id = p_lead_id;
    return v_existing;
end;
$$;

comment on function app.convert_lead_to_prospect is
  'COM-144: the main flow (Prompt 144 §21). contact_name/email/phone are snapshotted from the lead row at this exact moment -- never a live FK, so a later lead edit never silently alters an already-converted prospect. Only a qualified lead may convert; disqualified/merged/already-converted leads are rejected.';

-- Alternative flow (Prompt 144 §22): link a qualified lead to an existing, accessible
-- prospect instead of creating a new one -- never a silent second/forked identity.
create function app.link_lead_to_existing_prospect(
  p_lead_id uuid,
  p_prospect_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.prospects
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_lead app.leads;
  v_prospect app.prospects;
begin
  select * into v_lead from app.leads where id = p_lead_id;
  if not found then
    raise exception 'lead_not_found: %', p_lead_id using errcode = 'no_data_found';
  end if;

  select * into v_prospect from app.prospects where id = p_prospect_id;
  if not found then
    raise exception 'prospect_not_found: %', p_prospect_id using errcode = 'no_data_found';
  end if;

  if v_lead.tenant_id <> v_prospect.tenant_id then
    raise exception 'cross_tenant_link_denied: lead and prospect belong to different tenants'
      using errcode = 'insufficient_privilege';
  end if;

  if v_lead.status <> 'qualified' then
    raise exception 'invalid_transition: lead % is % and cannot link to a prospect (must be qualified)', p_lead_id, v_lead.status
      using errcode = 'check_violation';
  end if;

  if v_prospect.status = 'merged' then
    raise exception 'invalid_link: prospect % is merged and cannot accept a new lead link', p_prospect_id
      using errcode = 'check_violation';
  end if;

  if not (
    app.can_access_record(p_actor_auth_user_id, v_lead.tenant_id, v_lead.owner_user_id, app.lead_record_scope_org_unit_ids(v_lead.org_unit_id), null)
    and app.can_access_record(p_actor_auth_user_id, v_prospect.tenant_id, v_prospect.owner_user_id, app.lead_record_scope_org_unit_ids(v_prospect.org_unit_id), null)
  ) then
    raise exception 'insufficient_authority: identity % cannot access both the lead and the prospect', p_actor_auth_user_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.leads
  set status = 'converted', converted_at = now(), converted_prospect_id = v_prospect.id, last_activity_at = now(), record_version = record_version + 1
  where id = p_lead_id;

  perform app.capture_audit_event(
    v_lead.tenant_id, p_actor_auth_user_id, p_actor_label, 'link_lead_to_existing_prospect',
    'app.prospects', v_prospect.id, 'success', null, null, jsonb_build_object('lead_id', p_lead_id)
  );

  return v_prospect;
end;
$$;

comment on function app.link_lead_to_existing_prospect is
  'COM-144: the qualified lead itself converts (status=converted, linked to the existing prospect) -- the prospect row is not modified, only re-confirmed accessible. Never creates a second prospect for the same organization.';

-- Fixed, deterministic conversion-readiness evaluator (Prompt 144 §25: "mandatory legal,
-- billing, service and credit inputs configured for the tenant") -- a bounded, disclosed
-- fixed rule set, not a tenant-configurable rule engine. Platform Core's own Configuration
-- Engine (PLT-121 §25) deliberately deferred the bounded rule-expression evaluator a
-- tenant-configurable version would need to "whichever Phase 2+ capability first needs
-- to evaluate a real rule" -- this checkpoint's own bounded scope (5-15 files) is not
-- that capability; a real, working, non-configurable check is shipped instead of a
-- placeholder, and this gap is disclosed rather than silently built around.
create function app.get_prospect_conversion_readiness(p_prospect_id uuid)
returns table (ready boolean, missing text[])
language plpgsql
stable
as $$
declare
  v_prospect app.prospects;
  v_missing text[] := '{}';
begin
  select * into v_prospect from app.prospects where id = p_prospect_id;
  if not found then
    raise exception 'prospect_not_found: %', p_prospect_id using errcode = 'no_data_found';
  end if;

  if v_prospect.legal_name is null or length(trim(v_prospect.legal_name)) = 0 then
    v_missing := v_missing || 'legal_name'::text;
  end if;
  if v_prospect.tax_id is null or length(trim(v_prospect.tax_id)) = 0 then
    v_missing := v_missing || 'tax_id'::text;
  end if;
  if v_prospect.billing_address = '{}'::jsonb then
    v_missing := v_missing || 'billing_address'::text;
  end if;
  if v_prospect.contact_email is null and v_prospect.contact_phone is null then
    v_missing := v_missing || 'contact_identifier'::text;
  end if;

  return query select (array_length(v_missing, 1) is null), v_missing;
end;
$$;

comment on function app.get_prospect_conversion_readiness is
  'COM-144: read-only, deterministic. Fixed rule set (legal_name, tax_id, billing_address, at least one contact identifier) -- disclosed as a bounded, non-tenant-configurable check, not the deferred Configuration Engine rule evaluator (ADR-CAND-ARCH-014/015, still Phase 2+ open per PLT-121 §25). COM-155 (Customer and Account Conversion) is the actual downstream consumer of this readiness signal.';

create function app.disqualify_prospect(
  p_prospect_id uuid,
  p_expected_version integer,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.prospects
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_prospect app.prospects;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: disqualifying a prospect requires a non-empty reason'
      using errcode = 'not_null_violation';
  end if;

  select * into v_prospect from app.prospects where id = p_prospect_id;
  if not found then
    raise exception 'prospect_not_found: %', p_prospect_id using errcode = 'no_data_found';
  end if;

  if v_prospect.record_version <> p_expected_version then
    raise exception 'stale_version: prospect % expected version % but found %', p_prospect_id, p_expected_version, v_prospect.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_prospect.status <> 'active' then
    raise exception 'invalid_transition: prospect % is % and cannot be disqualified', p_prospect_id, v_prospect.status
      using errcode = 'check_violation';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_prospect.tenant_id, v_prospect.owner_user_id, app.lead_record_scope_org_unit_ids(v_prospect.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access prospect %', p_actor_auth_user_id, p_prospect_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.prospects
  set status = 'disqualified', disqualify_reason = p_reason, updated_at = now(), record_version = record_version + 1
  where id = p_prospect_id and record_version = p_expected_version
  returning * into v_prospect;

  perform app.capture_audit_event(
    v_prospect.tenant_id, p_actor_auth_user_id, p_actor_label, 'disqualify_prospect',
    'app.prospects', v_prospect.id, 'success', null, null, jsonb_build_object('reason', p_reason)
  );

  return v_prospect;
end;
$$;

create function app.archive_prospect(
  p_prospect_id uuid,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.prospects
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_prospect app.prospects;
begin
  select * into v_prospect from app.prospects where id = p_prospect_id;
  if not found then
    raise exception 'prospect_not_found: %', p_prospect_id using errcode = 'no_data_found';
  end if;

  if v_prospect.record_version <> p_expected_version then
    raise exception 'stale_version: prospect % expected version % but found %', p_prospect_id, p_expected_version, v_prospect.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_prospect.status <> 'active' then
    raise exception 'invalid_transition: prospect % is % and cannot be archived', p_prospect_id, v_prospect.status
      using errcode = 'check_violation';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_prospect.tenant_id, v_prospect.owner_user_id, app.lead_record_scope_org_unit_ids(v_prospect.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access prospect %', p_actor_auth_user_id, p_prospect_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.prospects
  set status = 'archived', updated_at = now(), record_version = record_version + 1
  where id = p_prospect_id and record_version = p_expected_version
  returning * into v_prospect;

  perform app.capture_audit_event(
    v_prospect.tenant_id, p_actor_auth_user_id, p_actor_label, 'archive_prospect',
    'app.prospects', v_prospect.id, 'success', null, null, null
  );

  return v_prospect;
end;
$$;

comment on function app.archive_prospect is
  'COM-144: distinct from disqualify -- "no longer pursuing," not a commercial-fit judgment, so no reason is required (Prompt 144 §14 lists disqualify/archive as two separate operations).';

create function app.merge_prospects(
  p_survivor_prospect_id uuid,
  p_duplicate_prospect_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.prospects
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_survivor app.prospects;
  v_duplicate app.prospects;
begin
  if p_survivor_prospect_id = p_duplicate_prospect_id then
    raise exception 'invalid_merge: a prospect cannot be merged into itself' using errcode = 'check_violation';
  end if;

  select * into v_survivor from app.prospects where id = p_survivor_prospect_id;
  select * into v_duplicate from app.prospects where id = p_duplicate_prospect_id;
  if v_survivor.id is null or v_duplicate.id is null then
    raise exception 'prospect_not_found: survivor % or duplicate %', p_survivor_prospect_id, p_duplicate_prospect_id
      using errcode = 'no_data_found';
  end if;

  if v_survivor.tenant_id <> v_duplicate.tenant_id then
    raise exception 'cross_tenant_merge_denied: survivor and duplicate belong to different tenants'
      using errcode = 'insufficient_privilege';
  end if;

  if v_duplicate.status = 'merged' then
    raise exception 'invalid_merge: prospect % is already merged', p_duplicate_prospect_id using errcode = 'check_violation';
  end if;

  if not (
    app.can_access_record(p_actor_auth_user_id, v_survivor.tenant_id, v_survivor.owner_user_id, app.lead_record_scope_org_unit_ids(v_survivor.org_unit_id), null)
    and app.can_access_record(p_actor_auth_user_id, v_duplicate.tenant_id, v_duplicate.owner_user_id, app.lead_record_scope_org_unit_ids(v_duplicate.org_unit_id), null)
  ) then
    raise exception 'insufficient_authority: identity % cannot access both prospects being merged', p_actor_auth_user_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.prospects
  set status = 'merged', merged_into_id = p_survivor_prospect_id, merged_at = now(), merged_by = p_actor_label, updated_at = now(), record_version = record_version + 1
  where id = p_duplicate_prospect_id
  returning * into v_duplicate;

  update app.prospects set updated_at = now() where id = p_survivor_prospect_id returning * into v_survivor;

  perform app.capture_audit_event(
    v_survivor.tenant_id, p_actor_auth_user_id, p_actor_label, 'merge_prospects',
    'app.prospects', v_duplicate.id, 'success', null, null,
    jsonb_build_object('survivor_prospect_id', p_survivor_prospect_id, 'duplicate_prospect_id', p_duplicate_prospect_id)
  );

  return v_survivor;
end;
$$;

comment on function app.merge_prospects is
  'COM-144: never creates or forks a customer identity -- the duplicate row is marked merged, never deleted, mirroring app.merge_leads (COM-143) exactly.';

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit, directly-provable revoke
-- of PostgreSQL's PUBLIC-execute default, the standing per-migration convention since
-- PLT-118, applied here before any role-specific grant.
revoke execute on all functions in schema app from public;

alter table app.prospects enable row level security;

create policy prospects_select_scoped on app.prospects
  for select to authenticated
  using (
    app.can_access_record(
      auth.uid(), tenant_id, owner_user_id,
      app.lead_record_scope_org_unit_ids(org_unit_id),
      null
    )
  );

grant usage on schema app to authenticated;
grant select on app.prospects to authenticated, service_role;
grant insert, update, delete on app.prospects to service_role;

grant execute on function app.normalize_prospect_identifier(text) to authenticated, service_role;
grant execute on function app.compute_prospect_duplicate_fingerprint(uuid, text, text) to authenticated, service_role;
grant execute on function app.find_duplicate_prospects(uuid, uuid, text, text) to authenticated, service_role;
grant execute on function app.convert_lead_to_prospect(uuid, text, text, text, jsonb, uuid, text) to authenticated, service_role;
grant execute on function app.link_lead_to_existing_prospect(uuid, uuid, uuid, text) to authenticated, service_role;
grant execute on function app.get_prospect_conversion_readiness(uuid) to authenticated, service_role;
grant execute on function app.disqualify_prospect(uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.archive_prospect(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.merge_prospects(uuid, uuid, uuid, text) to authenticated, service_role;
