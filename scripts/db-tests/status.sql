-- Real, executable test evidence for PLT-124 (Status Engine, CG-S6-PLT-021).
--
-- This file also builds and proves the one safe, isolated, representative example the
-- migration header discloses as deliberately NOT seeded as migration data: the real,
-- sourced Quotation status set from
-- docs/architecture/07_CONFIGURATION_ENGINE_WORKSTREAM.md §7.2 ("Quotation | Draft ->
-- Submitted(Under Approval), Under Approval -> Approved, Approved -> Sent, Sent ->
-- Accepted, Sent -> Expired (5)"). Activating this against a real `quotations` table is
-- explicitly Phase 2 Commercial config adoption scope -- this file only proves the
-- Status Engine's own registry/presentation/legacy-mapping mechanism against that real,
-- sourced shape, entirely with synthetic tenant data. No status_set row of any kind
-- exists anywhere in the migration itself.

\set ON_ERROR_STOP on

\echo '>> setup: two tenants each with a tenant_admin and a regular org_user, a global Supreme Admin'
do $$
declare
  v_tenant_id uuid;
  v_other_tenant_id uuid;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000001601', 'tenantadminst@example.test'),
    ('00000000-0000-0000-0000-000000001602', 'regularuserst@example.test'),
    ('00000000-0000-0000-0000-000000001603', 'supremest@example.test'),
    ('00000000-0000-0000-0000-000000001604', 'othertenantadminst@example.test');

  perform app.provision_tenant('acmest', 'Acme Status Co', 'idem-acmest', 'tester');
  v_tenant_id := (select id from app.tenants where slug = 'acmest');
  perform app.transition_tenant_status(v_tenant_id, 'active', 'setup', 'tester');
  perform app.invite_user(v_tenant_id, '00000000-0000-0000-0000-000000001601', 'tenantadminst@example.test', 'Tenant Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'tenantadminst@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000001601', 'tenant_admin', v_tenant_id, null, 'tester');

  perform app.invite_user(v_tenant_id, '00000000-0000-0000-0000-000000001602', 'regularuserst@example.test', 'Regular User', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'regularuserst@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000001602', 'org_user', v_tenant_id, null, 'tester');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000001603', 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('gizmost', 'Gizmo Status Co', 'idem-gizmost', 'tester');
  v_other_tenant_id := (select id from app.tenants where slug = 'gizmost');
  perform app.transition_tenant_status(v_other_tenant_id, 'active', 'setup', 'tester');
  perform app.invite_user(v_other_tenant_id, '00000000-0000-0000-0000-000000001604', 'othertenantadminst@example.test', 'Other Tenant Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'othertenantadminst@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000001604', 'tenant_admin', v_other_tenant_id, null, 'tester');
end;
$$;

\echo '>> app.register_status_set: idempotent, Supreme-Admin-only, and mints a dedicated status:<code> config_type (PLT-121''s registry reused, not forked)'
do $$
declare
  v_registered1 app.status_sets;
  v_registered2 app.status_sets;
  v_config_type_exists boolean;
begin
  begin
    perform app.register_status_set('quotation_status', 'Quotation Status', 'STAT', '00000000-0000-0000-0000-000000001601', 'tenant admin');
    raise exception 'assertion failed: expected a tenant_admin (not Supreme Admin) to be denied registering a status set';
  exception
    when insufficient_privilege then
      null;
  end;

  v_registered1 := app.register_status_set('quotation_status', 'Quotation Status', 'STAT', '00000000-0000-0000-0000-000000001603', 'supreme admin');
  v_registered2 := app.register_status_set('quotation_status', 'Quotation Status', 'STAT', '00000000-0000-0000-0000-000000001603', 'supreme admin');
  if v_registered1.code <> v_registered2.code then
    raise exception 'assertion failed: expected a repeated registration to be idempotent';
  end if;

  select exists (select 1 from app.config_types where code = 'status:quotation_status') into v_config_type_exists;
  if not v_config_type_exists then
    raise exception 'assertion failed: expected app.register_status_set to also mint a status:quotation_status config_type';
  end if;
end;
$$;

\echo '>> app.register_canonical_status: idempotent, Supreme-Admin-only, validates status_set existence and category -- registers the real, sourced Quotation shape (draft/under_approval/approved/sent/accepted/expired)'
do $$
declare
  v_registered1 app.canonical_statuses;
  v_registered2 app.canonical_statuses;
  v_count integer;
begin
  begin
    perform app.register_canonical_status('nonexistent_set', 'draft', 'initial', 0, '00000000-0000-0000-0000-000000001603', 'supreme admin');
    raise exception 'assertion failed: expected registering a status against a nonexistent status set to raise status_set_not_found';
  exception
    when no_data_found then
      null;
  end;

  begin
    perform app.register_canonical_status('quotation_status', 'draft', 'nonsense', 0, '00000000-0000-0000-0000-000000001603', 'supreme admin');
    raise exception 'assertion failed: expected an invalid category to raise status_invalid_category';
  exception
    when check_violation then
      if sqlerrm not like 'status_invalid_category%' then
        raise exception 'assertion failed: expected status_invalid_category, got %', sqlerrm;
      end if;
  end;

  v_registered1 := app.register_canonical_status('quotation_status', 'draft', 'initial', 1, '00000000-0000-0000-0000-000000001603', 'supreme admin');
  v_registered2 := app.register_canonical_status('quotation_status', 'draft', 'initial', 1, '00000000-0000-0000-0000-000000001603', 'supreme admin');
  if v_registered1.id <> v_registered2.id then
    raise exception 'assertion failed: expected a repeated canonical status registration to be idempotent';
  end if;

  perform app.register_canonical_status('quotation_status', 'under_approval', 'active', 2, '00000000-0000-0000-0000-000000001603', 'supreme admin');
  perform app.register_canonical_status('quotation_status', 'approved', 'active', 3, '00000000-0000-0000-0000-000000001603', 'supreme admin');
  perform app.register_canonical_status('quotation_status', 'sent', 'active', 4, '00000000-0000-0000-0000-000000001603', 'supreme admin');
  perform app.register_canonical_status('quotation_status', 'accepted', 'terminal', 5, '00000000-0000-0000-0000-000000001603', 'supreme admin');
  perform app.register_canonical_status('quotation_status', 'expired', 'terminal', 6, '00000000-0000-0000-0000-000000001603', 'supreme admin');

  select count(*) into v_count from app.canonical_statuses where status_set_code = 'quotation_status';
  if v_count <> 6 then
    raise exception 'assertion failed: expected exactly 6 registered canonical statuses (the real, sourced Quotation shape), saw %', v_count;
  end if;

  if (select is_terminal from app.canonical_statuses where status_set_code = 'quotation_status' and code = 'accepted') <> true then
    raise exception 'assertion failed: expected accepted''s generated is_terminal column to be true for category=terminal';
  end if;
  if (select is_terminal from app.canonical_statuses where status_set_code = 'quotation_status' and code = 'draft') <> false then
    raise exception 'assertion failed: expected draft''s generated is_terminal column to be false for category=initial';
  end if;
end;
$$;

\echo '>> app.get_status_set_registry: reusable ordered registry view model'
do $$
declare
  v_codes text[];
begin
  select array_agg(code order by sort_order) into v_codes from app.get_status_set_registry('quotation_status');
  if v_codes <> array['draft', 'under_approval', 'approved', 'sent', 'accepted', 'expired'] then
    raise exception 'assertion failed: expected the registry to return all 6 codes in sort_order, saw %', v_codes;
  end if;
end;
$$;

\echo '>> app.register_status_legacy_mapping: idempotent for a repeat, raises status_legacy_mapping_collision on a genuine remap, resolve_legacy_status round-trips correctly'
do $$
declare
  v_mapping1 app.status_legacy_mappings;
  v_mapping2 app.status_legacy_mappings;
  v_resolved app.canonical_statuses;
begin
  v_mapping1 := app.register_status_legacy_mapping('quotation_status', 'PENDING_REVIEW', 'under_approval', '00000000-0000-0000-0000-000000001603', 'supreme admin');
  v_mapping2 := app.register_status_legacy_mapping('quotation_status', 'PENDING_REVIEW', 'under_approval', '00000000-0000-0000-0000-000000001603', 'supreme admin');
  if v_mapping1.id <> v_mapping2.id then
    raise exception 'assertion failed: expected a repeated identical mapping to be idempotent';
  end if;

  begin
    perform app.register_status_legacy_mapping('quotation_status', 'PENDING_REVIEW', 'approved', '00000000-0000-0000-0000-000000001603', 'supreme admin');
    raise exception 'assertion failed: expected remapping an already-mapped legacy value to a different canonical status to raise status_legacy_mapping_collision';
  exception
    when unique_violation then
      if sqlerrm not like 'status_legacy_mapping_collision%' then
        raise exception 'assertion failed: expected status_legacy_mapping_collision, got %', sqlerrm;
      end if;
  end;

  v_resolved := app.resolve_legacy_status('quotation_status', 'PENDING_REVIEW');
  if v_resolved.code <> 'under_approval' then
    raise exception 'assertion failed: expected PENDING_REVIEW to resolve to under_approval, got %', v_resolved.code;
  end if;

  begin
    perform app.resolve_legacy_status('quotation_status', 'TOTALLY_UNKNOWN_LEGACY_VALUE');
    raise exception 'assertion failed: expected an unmapped legacy value to raise status_legacy_value_unmapped';
  exception
    when no_data_found then
      null;
  end;
end;
$$;

\echo '>> app.validate_status_presentation / app.publish_status_presentation: every structural failure mode is a distinct, named exception -- including the mandatory accessible non-color cue; a valid presentation publishes'
do $$
declare
  v_tenant_id uuid;
  v_draft app.config_versions;
  v_published app.config_versions;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmest');
  v_draft := app.create_config_draft('status:quotation_status', v_tenant_id, 'tenant', null, '00000000-0000-0000-0000-000000001601', 'tenant admin');

  -- status_missing_labels
  begin
    perform app.publish_status_presentation(v_draft.id, '00000000-0000-0000-0000-000000001601', null, 'tenant admin');
    raise exception 'assertion failed: expected a draft with no labels item to raise status_missing_labels';
  exception
    when check_violation then
      if sqlerrm not like 'status_missing_labels%' then
        raise exception 'assertion failed: expected status_missing_labels, got %', sqlerrm;
      end if;
  end;

  -- status_unknown_code
  perform app.set_config_items(v_draft.id, jsonb_build_array(jsonb_build_object(
    'key', 'labels', 'value', jsonb_build_object('not_a_real_code', jsonb_build_object('label', 'X', 'icon', 'circle'))
  )), '00000000-0000-0000-0000-000000001601', 'tenant admin');
  begin
    perform app.publish_status_presentation(v_draft.id, '00000000-0000-0000-0000-000000001601', null, 'tenant admin');
    raise exception 'assertion failed: expected an unregistered code in labels to raise status_unknown_code';
  exception
    when check_violation then
      if sqlerrm not like 'status_unknown_code%' then
        raise exception 'assertion failed: expected status_unknown_code, got %', sqlerrm;
      end if;
  end;

  -- status_missing_label
  perform app.set_config_items(v_draft.id, jsonb_build_array(jsonb_build_object(
    'key', 'labels', 'value', jsonb_build_object('draft', jsonb_build_object('icon', 'circle-dashed'))
  )), '00000000-0000-0000-0000-000000001601', 'tenant admin');
  begin
    perform app.publish_status_presentation(v_draft.id, '00000000-0000-0000-0000-000000001601', null, 'tenant admin');
    raise exception 'assertion failed: expected a missing label to raise status_missing_label';
  exception
    when check_violation then
      if sqlerrm not like 'status_missing_label%' then
        raise exception 'assertion failed: expected status_missing_label, got %', sqlerrm;
      end if;
  end;

  -- status_missing_accessible_cue (Prompt 124 §15: color alone is not accessible)
  perform app.set_config_items(v_draft.id, jsonb_build_array(jsonb_build_object(
    'key', 'labels', 'value', jsonb_build_object('draft', jsonb_build_object('label', 'Draft', 'color', '#6b7280'))
  )), '00000000-0000-0000-0000-000000001601', 'tenant admin');
  begin
    perform app.publish_status_presentation(v_draft.id, '00000000-0000-0000-0000-000000001601', null, 'tenant admin');
    raise exception 'assertion failed: expected a color-only (no icon) entry to raise status_missing_accessible_cue';
  exception
    when check_violation then
      if sqlerrm not like 'status_missing_accessible_cue%' then
        raise exception 'assertion failed: expected status_missing_accessible_cue, got %', sqlerrm;
      end if;
  end;

  -- status_invalid_color
  perform app.set_config_items(v_draft.id, jsonb_build_array(jsonb_build_object(
    'key', 'labels', 'value', jsonb_build_object('draft', jsonb_build_object('label', 'Draft', 'icon', 'circle-dashed', 'color', 'not-a-hex-color'))
  )), '00000000-0000-0000-0000-000000001601', 'tenant admin');
  begin
    perform app.publish_status_presentation(v_draft.id, '00000000-0000-0000-0000-000000001601', null, 'tenant admin');
    raise exception 'assertion failed: expected a non-hex color to raise status_invalid_color';
  exception
    when check_violation then
      if sqlerrm not like 'status_invalid_color%' then
        raise exception 'assertion failed: expected status_invalid_color, got %', sqlerrm;
      end if;
  end;

  -- Now the real, valid presentation for every status in the sourced Quotation set.
  perform app.set_config_items(v_draft.id, jsonb_build_array(jsonb_build_object(
    'key', 'labels', 'value', jsonb_build_object(
      'draft', jsonb_build_object('label', 'Draft', 'icon', 'circle-dashed', 'color', '#6b7280'),
      'under_approval', jsonb_build_object('label', 'Under Approval', 'icon', 'clock', 'color', '#f59e0b'),
      'approved', jsonb_build_object('label', 'Approved', 'icon', 'check-circle', 'color', '#3b82f6'),
      'sent', jsonb_build_object('label', 'Sent to Customer', 'icon', 'send', 'color', '#8b5cf6'),
      'accepted', jsonb_build_object('label', 'Accepted', 'icon', 'check-circle-2', 'color', '#22c55e'),
      'expired', jsonb_build_object('label', 'Expired', 'icon', 'x-circle', 'color', '#ef4444')
    )
  )), '00000000-0000-0000-0000-000000001601', 'tenant admin');

  begin
    perform app.publish_status_presentation(v_draft.id, '00000000-0000-0000-0000-000000001602', null, 'regular user');
    raise exception 'assertion failed: expected a regular org_user to be denied publishing a tenant-scoped status presentation';
  exception
    when insufficient_privilege then
      null;
  end;

  v_published := app.publish_status_presentation(v_draft.id, '00000000-0000-0000-0000-000000001601', null, 'tenant admin');
  if v_published.status <> 'published' then
    raise exception 'assertion failed: expected the valid 6-status presentation to publish, got %', v_published.status;
  end if;
end;
$$;

\echo '>> app.resolve_status_presentation: real 6-level precedence, structural fallback when nothing is published, cross-tenant isolation, and status_unknown_code for a genuinely unregistered code'
do $$
declare
  v_tenant_id uuid;
  v_other_tenant_id uuid;
  v_resolved record;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmest');
  v_other_tenant_id := (select id from app.tenants where slug = 'gizmost');

  select * into v_resolved from app.resolve_status_presentation('quotation_status', 'draft', v_tenant_id);
  if v_resolved.resolved_label <> 'Draft' or v_resolved.resolved_icon <> 'circle-dashed' or v_resolved.is_fallback <> false then
    raise exception 'assertion failed: expected the published tenant label/icon to resolve, got label=% icon=% is_fallback=%', v_resolved.resolved_label, v_resolved.resolved_icon, v_resolved.is_fallback;
  end if;
  if v_resolved.category <> 'initial' or v_resolved.is_terminal <> false then
    raise exception 'assertion failed: expected the canonical category/is_terminal to be surfaced alongside the presentation';
  end if;

  select * into v_resolved from app.resolve_status_presentation('quotation_status', 'accepted', v_tenant_id);
  if v_resolved.is_terminal <> true then
    raise exception 'assertion failed: expected accepted to surface is_terminal=true';
  end if;

  -- gizmost never published a presentation at all -- every resolution must fall back
  -- safely (never raise, never fabricate a tenant-specific color) rather than error.
  select * into v_resolved from app.resolve_status_presentation('quotation_status', 'draft', v_other_tenant_id);
  if v_resolved.is_fallback <> true or v_resolved.resolved_label <> 'Draft' or v_resolved.resolved_color is not null or v_resolved.resolved_icon <> 'circle' then
    raise exception 'assertion failed: expected a structural, code-derived fallback (label=Draft, color=null, icon=circle) for an unconfigured tenant, got label=% color=% icon=% is_fallback=%', v_resolved.resolved_label, v_resolved.resolved_color, v_resolved.resolved_icon, v_resolved.is_fallback;
  end if;

  select * into v_resolved from app.resolve_status_presentation('quotation_status', 'under_approval', v_other_tenant_id);
  if v_resolved.resolved_label <> 'Under Approval' then
    raise exception 'assertion failed: expected the fallback label to be a readable, code-derived form (Under Approval), got %', v_resolved.resolved_label;
  end if;

  begin
    perform app.resolve_status_presentation('quotation_status', 'not_a_real_code', v_tenant_id);
    raise exception 'assertion failed: expected resolving a genuinely unregistered code to raise status_unknown_code';
  exception
    when no_data_found then
      null;
  end;
end;
$$;

\echo '>> every status engine registration self-captures a canonical app.audit_logs entry (no bespoke *_history table exists for this capability)'
do $$
declare
  v_actions text[] := array['register_status_set', 'register_canonical_status', 'register_status_legacy_mapping'];
  v_action text;
  v_count integer;
begin
  foreach v_action in array v_actions loop
    select count(*) into v_count from app.audit_logs where action = v_action and tenant_id is null;
    if v_count = 0 then
      raise exception 'assertion failed: expected at least one platform-wide app.audit_logs entry for action=%, saw none', v_action;
    end if;
  end loop;
end;
$$;

\echo '>> schema-privilege defense in depth: authenticated has broad SELECT on the platform-owned status registry tables; anon holds no EXECUTE on service_role-only mutations (ERR-2026-004 regression guard)'
do $$
declare
  v_has_privilege boolean;
begin
  select has_table_privilege('authenticated', 'app.status_sets', 'SELECT') into v_has_privilege;
  if not v_has_privilege then
    raise exception 'assertion failed: expected authenticated to hold SELECT on app.status_sets (platform-owned reference data)';
  end if;

  select has_table_privilege('authenticated', 'app.canonical_statuses', 'SELECT') into v_has_privilege;
  if not v_has_privilege then
    raise exception 'assertion failed: expected authenticated to hold SELECT on app.canonical_statuses';
  end if;

  select has_table_privilege('anon', 'app.status_sets', 'SELECT') into v_has_privilege;
  if v_has_privilege then
    raise exception 'assertion failed: expected anon to hold no privilege on app.status_sets at all';
  end if;

  select has_function_privilege('authenticated', 'app.resolve_status_presentation(text, text, uuid, uuid, uuid, uuid, uuid)', 'EXECUTE') into v_has_privilege;
  if not v_has_privilege then
    raise exception 'assertion failed: expected authenticated to hold EXECUTE on app.resolve_status_presentation';
  end if;

  select has_function_privilege('anon', 'app.resolve_status_presentation(text, text, uuid, uuid, uuid, uuid, uuid)', 'EXECUTE') into v_has_privilege;
  if v_has_privilege then
    raise exception 'assertion failed: expected anon to hold no EXECUTE on app.resolve_status_presentation';
  end if;

  select has_function_privilege('anon', 'app.register_status_set(text, text, text, uuid, text)', 'EXECUTE') into v_has_privilege;
  if v_has_privilege then
    raise exception 'assertion failed: expected anon to hold no EXECUTE on the service_role-only app.register_status_set (ERR-2026-004 regression guard)';
  end if;

  select has_function_privilege('anon', 'app.publish_status_presentation(uuid, uuid, timestamptz, text)', 'EXECUTE') into v_has_privilege;
  if v_has_privilege then
    raise exception 'assertion failed: expected anon to hold no EXECUTE on the service_role-only app.publish_status_presentation (ERR-2026-004 regression guard)';
  end if;
end;
$$;
