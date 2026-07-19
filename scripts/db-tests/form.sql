-- Real, executable test evidence for PLT-126 (Form and Custom-Field Builder,
-- CG-S6-PLT-023).
--
-- This file also builds and proves the one safe, isolated, representative example the
-- migration header discloses as deliberately NOT seeded as migration data: a small
-- "Vendor Onboarding" custom-field set (tax_id, is_preferred_vendor, credit_note text
-- visible only when preferred). No form/field row of any kind exists anywhere in the
-- migration itself.

\set ON_ERROR_STOP on

\echo '>> setup: two tenants each with a tenant_admin and a regular org_user, a global Supreme Admin'
do $$
declare
  v_tenant_id uuid;
  v_other_tenant_id uuid;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000001801', 'tenantadminform@example.test'),
    ('00000000-0000-0000-0000-000000001802', 'regularuserform@example.test'),
    ('00000000-0000-0000-0000-000000001803', 'supremeform@example.test'),
    ('00000000-0000-0000-0000-000000001804', 'othertenantadminform@example.test');

  perform app.provision_tenant('acmeform', 'Acme Form Co', 'idem-acmeform', 'tester');
  v_tenant_id := (select id from app.tenants where slug = 'acmeform');
  perform app.transition_tenant_status(v_tenant_id, 'active', 'setup', 'tester');
  perform app.invite_user(v_tenant_id, '00000000-0000-0000-0000-000000001801', 'tenantadminform@example.test', 'Tenant Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'tenantadminform@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000001801', 'tenant_admin', v_tenant_id, null, 'tester');

  perform app.invite_user(v_tenant_id, '00000000-0000-0000-0000-000000001802', 'regularuserform@example.test', 'Regular User', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'regularuserform@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000001802', 'org_user', v_tenant_id, null, 'tester');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000001803', 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('gizmoform', 'Gizmo Form Co', 'idem-gizmoform', 'tester');
  v_other_tenant_id := (select id from app.tenants where slug = 'gizmoform');
  perform app.transition_tenant_status(v_other_tenant_id, 'active', 'setup', 'tester');
  perform app.invite_user(v_other_tenant_id, '00000000-0000-0000-0000-000000001804', 'othertenantadminform@example.test', 'Other Tenant Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'othertenantadminform@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000001804', 'tenant_admin', v_other_tenant_id, null, 'tester');
end;
$$;

\echo '>> app.register_form: idempotent, Supreme-Admin-only, and mints a dedicated form:<code> config_type (PLT-121''s registry reused, not forked)'
do $$
declare
  v_registered1 app.form_registry;
  v_registered2 app.form_registry;
  v_config_type_exists boolean;
begin
  begin
    perform app.register_form('vendor_onboarding', 'Vendor Onboarding', 'FORM', '00000000-0000-0000-0000-000000001801', 'tenant admin');
    raise exception 'assertion failed: expected a tenant_admin (not Supreme Admin) to be denied registering a form';
  exception
    when insufficient_privilege then
      null;
  end;

  v_registered1 := app.register_form('vendor_onboarding', 'Vendor Onboarding', 'FORM', '00000000-0000-0000-0000-000000001803', 'supreme admin');
  v_registered2 := app.register_form('vendor_onboarding', 'Vendor Onboarding', 'FORM', '00000000-0000-0000-0000-000000001803', 'supreme admin');
  if v_registered1.code <> v_registered2.code then
    raise exception 'assertion failed: expected a repeated registration to be idempotent';
  end if;

  select exists (select 1 from app.config_types where code = 'form:vendor_onboarding') into v_config_type_exists;
  if not v_config_type_exists then
    raise exception 'assertion failed: expected app.register_form to also mint a form:vendor_onboarding config_type';
  end if;
end;
$$;

\echo '>> app.evaluate_field_condition: direct-call coverage -- null condition passes unconditionally; equals/not_equals compare against submitted values'
do $$
begin
  if not app.evaluate_field_condition(null, '{}'::jsonb) then
    raise exception 'assertion failed: expected a null condition to unconditionally pass';
  end if;
  if not app.evaluate_field_condition('{"field_code": "is_preferred_vendor", "operator": "equals", "value": true}'::jsonb, '{"is_preferred_vendor": true}'::jsonb) then
    raise exception 'assertion failed: expected equals to pass when the referenced field matches';
  end if;
  if app.evaluate_field_condition('{"field_code": "is_preferred_vendor", "operator": "equals", "value": true}'::jsonb, '{"is_preferred_vendor": false}'::jsonb) then
    raise exception 'assertion failed: expected equals to fail when the referenced field does not match';
  end if;
  if not app.evaluate_field_condition('{"field_code": "is_preferred_vendor", "operator": "not_equals", "value": true}'::jsonb, '{"is_preferred_vendor": false}'::jsonb) then
    raise exception 'assertion failed: expected not_equals to pass when the referenced field differs';
  end if;

  begin
    perform app.evaluate_field_condition('{"field_code": "x", "operator": "greater_than", "value": 1}'::jsonb, '{}'::jsonb);
    raise exception 'assertion failed: expected an unknown operator to raise custom_field_unknown_condition_operator';
  exception
    when check_violation then
      null;
  end;
end;
$$;

\echo '>> app.validate_form_definition / app.publish_form_definition: every structural failure mode is a distinct, named exception -- including condition-cycle-freedom by construction; a valid Vendor Onboarding definition publishes'
do $$
declare
  v_tenant_id uuid;
  v_draft app.config_versions;
  v_published app.config_versions;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmeform');
  v_draft := app.create_config_draft('form:vendor_onboarding', v_tenant_id, 'tenant', null, '00000000-0000-0000-0000-000000001801', 'tenant admin');

  -- custom_field_missing_fields
  begin
    perform app.publish_form_definition(v_draft.id, '00000000-0000-0000-0000-000000001801', null, 'tenant admin');
    raise exception 'assertion failed: expected a draft with no fields item to raise custom_field_missing_fields';
  exception
    when check_violation then
      if sqlerrm not like 'custom_field_missing_fields%' then
        raise exception 'assertion failed: expected custom_field_missing_fields, got %', sqlerrm;
      end if;
  end;

  -- custom_field_duplicate_code
  perform app.set_config_items(v_draft.id, jsonb_build_array(jsonb_build_object('key', 'fields', 'value', jsonb_build_array(
    jsonb_build_object('code', 'tax_id', 'label', 'Tax ID', 'type', 'text'),
    jsonb_build_object('code', 'tax_id', 'label', 'Tax ID Again', 'type', 'text')
  ))), '00000000-0000-0000-0000-000000001801', 'tenant admin');
  begin
    perform app.publish_form_definition(v_draft.id, '00000000-0000-0000-0000-000000001801', null, 'tenant admin');
    raise exception 'assertion failed: expected a duplicated field code to raise custom_field_duplicate_code';
  exception
    when check_violation then
      if sqlerrm not like 'custom_field_duplicate_code%' then
        raise exception 'assertion failed: expected custom_field_duplicate_code, got %', sqlerrm;
      end if;
  end;

  -- custom_field_invalid_type
  perform app.set_config_items(v_draft.id, jsonb_build_array(jsonb_build_object('key', 'fields', 'value', jsonb_build_array(
    jsonb_build_object('code', 'attachment', 'label', 'Attachment', 'type', 'file')
  ))), '00000000-0000-0000-0000-000000001801', 'tenant admin');
  begin
    perform app.publish_form_definition(v_draft.id, '00000000-0000-0000-0000-000000001801', null, 'tenant admin');
    raise exception 'assertion failed: expected type=file (not in the allowlist -- no file storage plumbing exists yet) to raise custom_field_invalid_type';
  exception
    when check_violation then
      if sqlerrm not like 'custom_field_invalid_type%' then
        raise exception 'assertion failed: expected custom_field_invalid_type, got %', sqlerrm;
      end if;
  end;

  -- custom_field_missing_options
  perform app.set_config_items(v_draft.id, jsonb_build_array(jsonb_build_object('key', 'fields', 'value', jsonb_build_array(
    jsonb_build_object('code', 'vendor_category', 'label', 'Vendor Category', 'type', 'select')
  ))), '00000000-0000-0000-0000-000000001801', 'tenant admin');
  begin
    perform app.publish_form_definition(v_draft.id, '00000000-0000-0000-0000-000000001801', null, 'tenant admin');
    raise exception 'assertion failed: expected a select field with no options to raise custom_field_missing_options';
  exception
    when check_violation then
      if sqlerrm not like 'custom_field_missing_options%' then
        raise exception 'assertion failed: expected custom_field_missing_options, got %', sqlerrm;
      end if;
  end;

  -- custom_field_invalid_validator
  perform app.set_config_items(v_draft.id, jsonb_build_array(jsonb_build_object('key', 'fields', 'value', jsonb_build_array(
    jsonb_build_object('code', 'tax_id', 'label', 'Tax ID', 'type', 'text', 'validators', jsonb_build_array(jsonb_build_object('type', 'regex_exec', 'value', 'x')))
  ))), '00000000-0000-0000-0000-000000001801', 'tenant admin');
  begin
    perform app.publish_form_definition(v_draft.id, '00000000-0000-0000-0000-000000001801', null, 'tenant admin');
    raise exception 'assertion failed: expected an unallowlisted validator type to raise custom_field_invalid_validator';
  exception
    when check_violation then
      if sqlerrm not like 'custom_field_invalid_validator%' then
        raise exception 'assertion failed: expected custom_field_invalid_validator, got %', sqlerrm;
      end if;
  end;

  -- custom_field_invalid_condition_reference (forward/self reference)
  perform app.set_config_items(v_draft.id, jsonb_build_array(jsonb_build_object('key', 'fields', 'value', jsonb_build_array(
    jsonb_build_object('code', 'credit_note', 'label', 'Credit Note', 'type', 'text', 'condition', jsonb_build_object('field_code', 'is_preferred_vendor', 'operator', 'equals', 'value', true))
  ))), '00000000-0000-0000-0000-000000001801', 'tenant admin');
  begin
    perform app.publish_form_definition(v_draft.id, '00000000-0000-0000-0000-000000001801', null, 'tenant admin');
    raise exception 'assertion failed: expected a condition referencing a not-yet-declared field to raise custom_field_invalid_condition_reference';
  exception
    when check_violation then
      if sqlerrm not like 'custom_field_invalid_condition_reference%' then
        raise exception 'assertion failed: expected custom_field_invalid_condition_reference, got %', sqlerrm;
      end if;
  end;

  -- Now the real, valid example: Vendor Onboarding (tax_id, is_preferred_vendor,
  -- credit_note[condition: only visible when is_preferred_vendor=true, sensitive]).
  perform app.set_config_items(v_draft.id, jsonb_build_array(jsonb_build_object('key', 'fields', 'value', jsonb_build_array(
    jsonb_build_object('code', 'tax_id', 'label', 'Tax ID', 'type', 'text', 'required', true, 'validators', jsonb_build_array(jsonb_build_object('type', 'min_length', 'value', 5))),
    jsonb_build_object('code', 'is_preferred_vendor', 'label', 'Preferred Vendor', 'type', 'boolean', 'required', false),
    jsonb_build_object('code', 'credit_note', 'label', 'Credit Terms Note', 'type', 'textarea', 'required', true, 'sensitive', true, 'condition', jsonb_build_object('field_code', 'is_preferred_vendor', 'operator', 'equals', 'value', true))
  ))), '00000000-0000-0000-0000-000000001801', 'tenant admin');

  begin
    perform app.publish_form_definition(v_draft.id, '00000000-0000-0000-0000-000000001802', null, 'regular user');
    raise exception 'assertion failed: expected a regular org_user to be denied publishing a tenant-scoped form definition';
  exception
    when insufficient_privilege then
      null;
  end;

  v_published := app.publish_form_definition(v_draft.id, '00000000-0000-0000-0000-000000001801', null, 'tenant admin');
  if v_published.status <> 'published' then
    raise exception 'assertion failed: expected the valid Vendor Onboarding definition to publish, got %', v_published.status;
  end if;
end;
$$;

\echo '>> app.validate_custom_field_values: unknown-field rejection, required-field enforcement (waived when hidden by condition), type checks per field type, and validator enforcement'
do $$
declare
  v_tenant_id uuid;
  v_published_version_id uuid;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmeform');
  select v.id into v_published_version_id
  from app.config_versions v join app.config_objects o on o.id = v.config_object_id
  where o.tenant_id = v_tenant_id and o.config_type_code = 'form:vendor_onboarding' and o.scope_level = 'tenant' and v.status = 'published';

  begin
    perform app.validate_custom_field_values(v_published_version_id, '{"bogus_field": "x", "tax_id": "12345"}'::jsonb);
    raise exception 'assertion failed: expected an undeclared field key to raise custom_field_unknown_field';
  exception
    when check_violation then
      if sqlerrm not like 'custom_field_unknown_field%' then
        raise exception 'assertion failed: expected custom_field_unknown_field, got %', sqlerrm;
      end if;
  end;

  begin
    perform app.validate_custom_field_values(v_published_version_id, '{}'::jsonb);
    raise exception 'assertion failed: expected a missing required tax_id to raise custom_field_required_missing';
  exception
    when check_violation then
      if sqlerrm not like 'custom_field_required_missing%' then
        raise exception 'assertion failed: expected custom_field_required_missing, got %', sqlerrm;
      end if;
  end;

  -- credit_note is required=true, but its condition (is_preferred_vendor=true) is not
  -- met here -- required-ness must be waived while the field is hidden.
  if not app.validate_custom_field_values(v_published_version_id, '{"tax_id": "12345", "is_preferred_vendor": false}'::jsonb) then
    raise exception 'assertion failed: expected a valid submission with credit_note omitted (correctly hidden by its condition) to pass';
  end if;

  begin
    perform app.validate_custom_field_values(v_published_version_id, '{"tax_id": "12345", "is_preferred_vendor": true}'::jsonb);
    raise exception 'assertion failed: expected credit_note to become required once is_preferred_vendor=true makes it visible';
  exception
    when check_violation then
      if sqlerrm not like 'custom_field_required_missing%' then
        raise exception 'assertion failed: expected custom_field_required_missing (credit_note), got %', sqlerrm;
      end if;
  end;

  begin
    perform app.validate_custom_field_values(v_published_version_id, '{"tax_id": 12345, "is_preferred_vendor": false}'::jsonb);
    raise exception 'assertion failed: expected a numeric value for a text field to raise custom_field_invalid_value';
  exception
    when check_violation then
      if sqlerrm not like 'custom_field_invalid_value%' then
        raise exception 'assertion failed: expected custom_field_invalid_value, got %', sqlerrm;
      end if;
  end;

  begin
    perform app.validate_custom_field_values(v_published_version_id, '{"tax_id": "abc", "is_preferred_vendor": false}'::jsonb);
    raise exception 'assertion failed: expected a too-short tax_id to raise custom_field_validator_failed (min_length)';
  exception
    when check_violation then
      if sqlerrm not like 'custom_field_validator_failed%' then
        raise exception 'assertion failed: expected custom_field_validator_failed, got %', sqlerrm;
      end if;
  end;

  if not app.validate_custom_field_values(v_published_version_id, '{"tax_id": "12345", "is_preferred_vendor": true, "credit_note": "Net 60 terms approved"}'::jsonb) then
    raise exception 'assertion failed: expected the fully valid, all-fields-visible submission to pass';
  end if;
end;
$$;

\echo '>> app.set_custom_field_values: requires a published definition, is authority-gated, idempotent on (tenant_id, idempotency_key), runs real validation before ever writing, and one row per entity (never one row per field -- EAV avoided)'
do $$
declare
  v_tenant_id uuid;
  v_published_version_id uuid;
  v_draft_version_id uuid;
  v_entity_id uuid := '00000000-0000-0000-0000-000000009301';
  v_values1 app.custom_field_values;
  v_values2 app.custom_field_values;
  v_row_count integer;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmeform');
  select v.id into v_published_version_id
  from app.config_versions v join app.config_objects o on o.id = v.config_object_id
  where o.tenant_id = v_tenant_id and o.config_type_code = 'form:vendor_onboarding' and o.scope_level = 'tenant' and v.status = 'published';

  v_draft_version_id := (app.create_config_draft('form:vendor_onboarding', v_tenant_id, 'tenant', null, '00000000-0000-0000-0000-000000001801', 'tenant admin')).id;
  begin
    perform app.set_custom_field_values(v_draft_version_id, v_tenant_id, 'vendor', v_entity_id, '{"tax_id": "12345"}'::jsonb, 'form-bad', '00000000-0000-0000-0000-000000001801', 'tenant admin');
    raise exception 'assertion failed: expected writing against a non-published version to raise custom_field_definition_not_published';
  exception
    when check_violation then
      if sqlerrm not like 'custom_field_definition_not_published%' then
        raise exception 'assertion failed: expected custom_field_definition_not_published, got %', sqlerrm;
      end if;
  end;
  perform app.discard_config_draft(v_draft_version_id, '00000000-0000-0000-0000-000000001801', 'cleanup', 'tenant admin');

  begin
    perform app.set_custom_field_values(v_published_version_id, v_tenant_id, 'vendor', v_entity_id, '{"tax_id": "12345"}'::jsonb, 'form-1', '00000000-0000-0000-0000-000000001804', 'other tenant admin');
    raise exception 'assertion failed: expected an identity with no membership in acmeform to be denied writing there';
  exception
    when insufficient_privilege then
      null;
  end;

  begin
    perform app.set_custom_field_values(v_published_version_id, v_tenant_id, 'vendor', v_entity_id, '{"tax_id": 12345}'::jsonb, 'form-invalid', '00000000-0000-0000-0000-000000001802', 'regular user');
    raise exception 'assertion failed: expected real validation to run before ever writing (invalid tax_id type)';
  exception
    when check_violation then
      if sqlerrm not like 'custom_field_invalid_value%' then
        raise exception 'assertion failed: expected custom_field_invalid_value, got %', sqlerrm;
      end if;
  end;
  if exists (select 1 from app.custom_field_values where tenant_id = v_tenant_id and entity_id = v_entity_id) then
    raise exception 'assertion failed: expected the invalid submission to have written nothing at all';
  end if;

  v_values1 := app.set_custom_field_values(v_published_version_id, v_tenant_id, 'vendor', v_entity_id, '{"tax_id": "12345", "is_preferred_vendor": false}'::jsonb, 'form-1', '00000000-0000-0000-0000-000000001802', 'regular user');
  if v_values1.values ->> 'tax_id' <> '12345' then
    raise exception 'assertion failed: expected the stored values to include tax_id=12345';
  end if;

  -- Idempotent replay: the same idempotency_key returns the existing row unchanged, not a second write.
  v_values2 := app.set_custom_field_values(v_published_version_id, v_tenant_id, 'vendor', v_entity_id, '{"tax_id": "99999", "is_preferred_vendor": false}'::jsonb, 'form-1', '00000000-0000-0000-0000-000000001802', 'regular user');
  if v_values2.id <> v_values1.id or v_values2.values ->> 'tax_id' <> '12345' then
    raise exception 'assertion failed: expected a repeated set_custom_field_values call with the same idempotency_key to return the original, unmodified row';
  end if;

  -- Updating the SAME entity under a NEW idempotency_key upserts in place -- still one row.
  perform app.set_custom_field_values(v_published_version_id, v_tenant_id, 'vendor', v_entity_id, '{"tax_id": "67890", "is_preferred_vendor": true, "credit_note": "Net 60 approved"}'::jsonb, 'form-2', '00000000-0000-0000-0000-000000001802', 'regular user');
  select count(*) into v_row_count from app.custom_field_values where tenant_id = v_tenant_id and entity_type = 'vendor' and entity_id = v_entity_id;
  if v_row_count <> 1 then
    raise exception 'assertion failed: expected exactly one row per (tenant, entity_type, entity_id) even after an update -- EAV query explosion structurally avoided, saw % rows', v_row_count;
  end if;
  if (select values ->> 'tax_id' from app.custom_field_values where tenant_id = v_tenant_id and entity_id = v_entity_id) <> '67890' then
    raise exception 'assertion failed: expected the upsert to have replaced tax_id with the new value';
  end if;
end;
$$;

\echo '>> app.get_custom_field_values: sensitive-field-gated read -- the submitter and the tenant_admin (definition-admin-grade authority) may read a row containing a sensitive field, an unrelated regular org_user may not; cross-tenant isolation'
do $$
declare
  v_tenant_id uuid;
  v_other_tenant_id uuid;
  v_entity_id uuid := '00000000-0000-0000-0000-000000009301';
  v_row app.custom_field_values;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmeform');
  v_other_tenant_id := (select id from app.tenants where slug = 'gizmoform');

  -- Submitted by regular org_user (00...1802) in the prior scenario group; the row now
  -- contains a value for the sensitive credit_note field.
  v_row := app.get_custom_field_values(v_tenant_id, 'vendor', v_entity_id, '00000000-0000-0000-0000-000000001802');
  if v_row.values ->> 'credit_note' is null then
    raise exception 'assertion failed: expected the original submitter to read the sensitive credit_note value';
  end if;

  v_row := app.get_custom_field_values(v_tenant_id, 'vendor', v_entity_id, '00000000-0000-0000-0000-000000001801');
  if v_row.values ->> 'credit_note' is null then
    raise exception 'assertion failed: expected the tenant_admin (definition-admin-grade authority) to read the sensitive credit_note value';
  end if;

  -- A second, unrelated regular org_user (not the submitter, not an admin) must be denied.
  insert into auth.users (id, email) values ('00000000-0000-0000-0000-000000001805', 'anotherregularuserform@example.test') on conflict (id) do nothing;
  perform app.invite_user(v_tenant_id, '00000000-0000-0000-0000-000000001805', 'anotherregularuserform@example.test', 'Another Regular User', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'anotherregularuserform@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000001805', 'org_user', v_tenant_id, null, 'tester');

  begin
    perform app.get_custom_field_values(v_tenant_id, 'vendor', v_entity_id, '00000000-0000-0000-0000-000000001805');
    raise exception 'assertion failed: expected an unrelated regular org_user (not the submitter, not an admin) to be denied reading a sensitive-field row';
  exception
    when insufficient_privilege then
      null;
  end;

  begin
    perform app.get_custom_field_values(v_other_tenant_id, 'vendor', v_entity_id, '00000000-0000-0000-0000-000000001804');
    raise exception 'assertion failed: expected cross-tenant isolation -- gizmoform must never see acmeform''s custom field values';
  exception
    when no_data_found then
      null;
  end;
end;
$$;

\echo '>> every form/custom-field lifecycle mutation self-captures a canonical app.audit_logs entry (no bespoke *_history table for this capability)'
do $$
declare
  v_tenant_id uuid;
  v_count integer;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmeform');

  select count(*) into v_count from app.audit_logs where action = 'register_form' and tenant_id is null;
  if v_count = 0 then
    raise exception 'assertion failed: expected a platform-wide (null tenant_id) audit entry for register_form';
  end if;

  select count(*) into v_count from app.audit_logs where tenant_id = v_tenant_id and action = 'set_custom_field_values';
  if v_count = 0 then
    raise exception 'assertion failed: expected at least one app.audit_logs entry for action=set_custom_field_values, saw none';
  end if;
end;
$$;

\echo '>> schema-privilege defense in depth: authenticated has broad SELECT on the platform-owned form registry and RLS-scoped SELECT on custom_field_values; anon holds no EXECUTE on service_role-only mutations (ERR-2026-004 regression guard)'
do $$
declare
  v_has_privilege boolean;
begin
  select has_table_privilege('authenticated', 'app.form_registry', 'SELECT') into v_has_privilege;
  if not v_has_privilege then
    raise exception 'assertion failed: expected authenticated to hold SELECT on app.form_registry (platform-owned reference data)';
  end if;

  select has_table_privilege('authenticated', 'app.custom_field_values', 'SELECT') into v_has_privilege;
  if not v_has_privilege then
    raise exception 'assertion failed: expected authenticated to hold direct RLS-scoped SELECT on app.custom_field_values';
  end if;

  select has_table_privilege('anon', 'app.custom_field_values', 'SELECT') into v_has_privilege;
  if v_has_privilege then
    raise exception 'assertion failed: expected anon to hold no privilege on app.custom_field_values at all';
  end if;

  select has_function_privilege('authenticated', 'app.get_custom_field_values(uuid, text, uuid, uuid)', 'EXECUTE') into v_has_privilege;
  if not v_has_privilege then
    raise exception 'assertion failed: expected authenticated to hold EXECUTE on app.get_custom_field_values';
  end if;

  select has_function_privilege('anon', 'app.get_custom_field_values(uuid, text, uuid, uuid)', 'EXECUTE') into v_has_privilege;
  if v_has_privilege then
    raise exception 'assertion failed: expected anon to hold no EXECUTE on app.get_custom_field_values';
  end if;

  select has_function_privilege('anon', 'app.set_custom_field_values(uuid, uuid, text, uuid, jsonb, text, uuid, text)', 'EXECUTE') into v_has_privilege;
  if v_has_privilege then
    raise exception 'assertion failed: expected anon to hold no EXECUTE on the service_role-only app.set_custom_field_values (ERR-2026-004 regression guard)';
  end if;

  select has_function_privilege('anon', 'app.register_form(text, text, text, uuid, text)', 'EXECUTE') into v_has_privilege;
  if v_has_privilege then
    raise exception 'assertion failed: expected anon to hold no EXECUTE on the service_role-only app.register_form (ERR-2026-004 regression guard)';
  end if;
end;
$$;
