-- Real, executable test evidence for PLT-121 (Configuration Engine, CG-S6-PLT-018).

\set ON_ERROR_STOP on

\echo '>> setup: two tenants each with a tenant_admin and a regular org_user, a global Supreme Admin, plus one org unit and one role per tenant for scope tests'
do $$
declare
  v_tenant_id uuid;
  v_other_tenant_id uuid;
  v_role app.roles;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000001301', 'tenantadmincfg@example.test'),
    ('00000000-0000-0000-0000-000000001302', 'regularusercfg@example.test'),
    ('00000000-0000-0000-0000-000000001303', 'supremecfg@example.test'),
    ('00000000-0000-0000-0000-000000001304', 'othertenantadmincfg@example.test');

  perform app.provision_tenant('acmecfg', 'Acme Config Co', 'idem-acmecfg', 'tester');
  v_tenant_id := (select id from app.tenants where slug = 'acmecfg');
  perform app.transition_tenant_status(v_tenant_id, 'active', 'setup', 'tester');
  perform app.invite_user(v_tenant_id, '00000000-0000-0000-0000-000000001301', 'tenantadmincfg@example.test', 'Tenant Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'tenantadmincfg@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000001301', 'tenant_admin', v_tenant_id, null, 'tester');

  perform app.invite_user(v_tenant_id, '00000000-0000-0000-0000-000000001302', 'regularusercfg@example.test', 'Regular User', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'regularusercfg@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000001302', 'org_user', v_tenant_id, null, 'tester');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000001303', 'supreme_admin', null, null, 'tester');

  perform app.create_role(v_tenant_id, 'Finance Approver Cfg', 'test role', 'tester');

  perform app.provision_tenant('gizmocfg', 'Gizmo Config Co', 'idem-gizmocfg', 'tester');
  v_other_tenant_id := (select id from app.tenants where slug = 'gizmocfg');
  perform app.transition_tenant_status(v_other_tenant_id, 'active', 'setup', 'tester');
  perform app.invite_user(v_other_tenant_id, '00000000-0000-0000-0000-000000001304', 'othertenantadmincfg@example.test', 'Other Tenant Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'othertenantadmincfg@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000001304', 'tenant_admin', v_other_tenant_id, null, 'tester');
end;
$$;

\echo '>> app.config_types: the 10 Phase-1-bootstrapped types are seeded; app.register_config_type is idempotent and Supreme-Admin-only'
do $$
declare
  v_count integer;
  v_registered1 app.config_types;
  v_registered2 app.config_types;
begin
  select count(*) into v_count from app.config_types where code in ('workflow', 'approval', 'status', 'numbering', 'form', 'field', 'notification', 'feature', 'branding', 'terminology');
  if v_count <> 10 then
    raise exception 'assertion failed: expected exactly the 10 Phase-1 config types seeded, saw %', v_count;
  end if;

  begin
    perform app.register_config_type('rule', 'Business Rule', 'CFG', '00000000-0000-0000-0000-000000001301', 'tenant admin');
    raise exception 'assertion failed: expected a tenant_admin (not Supreme Admin) to be denied registering a config type';
  exception
    when insufficient_privilege then
      null;
  end;

  v_registered1 := app.register_config_type('rule', 'Business Rule', 'CFG', '00000000-0000-0000-0000-000000001303', 'supreme admin');
  v_registered2 := app.register_config_type('rule', 'Business Rule', 'CFG', '00000000-0000-0000-0000-000000001303', 'supreme admin');
  if v_registered1.code <> v_registered2.code then
    raise exception 'assertion failed: expected a repeated registration to be idempotent';
  end if;
end;
$$;

\echo '>> app.config_objects CHECK constraint: scope shape (global/tenant/company-branch-role-user) is enforced structurally'
do $$
declare
  v_tenant_id uuid;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmecfg');

  begin
    insert into app.config_objects (config_type_code, tenant_id, scope_level, scope_id) values ('approval', v_tenant_id, 'global', null);
    raise exception 'assertion failed: expected a global-scope object with a non-null tenant_id to be rejected';
  exception
    when check_violation then
      null;
  end;

  begin
    insert into app.config_objects (config_type_code, tenant_id, scope_level, scope_id) values ('approval', null, 'tenant', null);
    raise exception 'assertion failed: expected a tenant-scope object with a null tenant_id to be rejected';
  exception
    when check_violation then
      null;
  end;

  begin
    insert into app.config_objects (config_type_code, tenant_id, scope_level, scope_id) values ('approval', v_tenant_id, 'role', null);
    raise exception 'assertion failed: expected a role-scope object with a null scope_id to be rejected';
  exception
    when check_violation then
      null;
  end;
end;
$$;

\echo '>> app.create_config_draft: idempotent, authority-gated per scope (Supreme for global, tenant_admin/Supreme for tenant+)'
do $$
declare
  v_tenant_id uuid;
  v_draft1 app.config_versions;
  v_draft2 app.config_versions;
  v_global_draft app.config_versions;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmecfg');

  begin
    perform app.create_config_draft('approval', v_tenant_id, 'tenant', null, '00000000-0000-0000-0000-000000001302', 'regular user');
    raise exception 'assertion failed: expected a regular org_user to be denied';
  exception
    when insufficient_privilege then
      null;
  end;

  v_draft1 := app.create_config_draft('approval', v_tenant_id, 'tenant', null, '00000000-0000-0000-0000-000000001301', 'tenant admin');
  if v_draft1.status <> 'draft' or v_draft1.version_number <> 1 then
    raise exception 'assertion failed: expected a fresh version_number=1 draft, got status=% version_number=%', v_draft1.status, v_draft1.version_number;
  end if;

  v_draft2 := app.create_config_draft('approval', v_tenant_id, 'tenant', null, '00000000-0000-0000-0000-000000001301', 'tenant admin');
  if v_draft2.id <> v_draft1.id then
    raise exception 'assertion failed: expected a repeated call to return the same existing draft, not create a second one';
  end if;

  begin
    perform app.create_config_draft('approval', null, 'global', null, '00000000-0000-0000-0000-000000001301', 'tenant admin');
    raise exception 'assertion failed: expected a tenant_admin (not Supreme Admin) to be denied creating a global-scoped config object';
  exception
    when insufficient_privilege then
      null;
  end;

  v_global_draft := app.create_config_draft('approval', null, 'global', null, '00000000-0000-0000-0000-000000001303', 'supreme admin');
  if v_global_draft.status <> 'draft' then
    raise exception 'assertion failed: expected the global-scoped draft to be created';
  end if;
end;
$$;

\echo '>> app.set_config_items: only mutates a draft, applies structural safety validation'
do $$
declare
  v_tenant_id uuid;
  v_draft app.config_versions;
  v_item_count integer;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmecfg');
  select v.* into v_draft
  from app.config_versions v
  join app.config_objects o on o.id = v.config_object_id
  where o.tenant_id = v_tenant_id and o.config_type_code = 'approval' and v.status = 'draft';

  v_item_count := app.set_config_items(
    v_draft.id,
    '[{"key": "quotation.threshold_amount", "value": {"amount": 50000000, "currency": "IDR"}}, {"key": "quotation.approver_role", "value": "manager"}]'::jsonb,
    '00000000-0000-0000-0000-000000001301', 'tenant admin'
  );
  if v_item_count <> 2 then
    raise exception 'assertion failed: expected 2 items to be set, saw %', v_item_count;
  end if;

  begin
    perform app.set_config_items(v_draft.id, '[{"key": "unsafe", "value": "<script>alert(1)</script>"}]'::jsonb, '00000000-0000-0000-0000-000000001301', 'tenant admin');
    raise exception 'assertion failed: expected an angle-bracket item value to be rejected by the CHECK constraint';
  exception
    when check_violation then
      null;
  end;

  begin
    perform app.set_config_items(v_draft.id, '[]'::jsonb, '00000000-0000-0000-0000-000000001302', 'regular user');
    raise exception 'assertion failed: expected a regular org_user to be denied';
  exception
    when insufficient_privilege then
      null;
  end;

  -- Restore the valid item set (the failed unsafe-value attempt did not persist).
  perform app.set_config_items(
    v_draft.id,
    '[{"key": "quotation.threshold_amount", "value": {"amount": 50000000, "currency": "IDR"}}, {"key": "quotation.approver_role", "value": "manager"}]'::jsonb,
    '00000000-0000-0000-0000-000000001301', 'tenant admin'
  );
end;
$$;

\echo '>> app.publish_config_version: publishing supersedes the prior published version for the same object; at most one published version at a time'
do $$
declare
  v_tenant_id uuid;
  v_draft app.config_versions;
  v_published app.config_versions;
  v_second_draft app.config_versions;
  v_second_published app.config_versions;
  v_first_after app.config_versions;
  v_published_count integer;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmecfg');
  select v.* into v_draft
  from app.config_versions v
  join app.config_objects o on o.id = v.config_object_id
  where o.tenant_id = v_tenant_id and o.config_type_code = 'approval' and v.status = 'draft';

  begin
    perform app.publish_config_version('00000000-0000-0000-0000-000000001399', '00000000-0000-0000-0000-000000001301', null, 'tenant admin');
    raise exception 'assertion failed: expected a nonexistent version_id to raise config_version_not_found';
  exception
    when no_data_found then
      null;
  end;

  v_published := app.publish_config_version(v_draft.id, '00000000-0000-0000-0000-000000001301', null, 'tenant admin');
  if v_published.status <> 'published' then
    raise exception 'assertion failed: expected the draft to publish successfully, got %', v_published.status;
  end if;

  v_second_draft := app.create_config_draft('approval', v_tenant_id, 'tenant', null, '00000000-0000-0000-0000-000000001301', 'tenant admin');
  perform app.set_config_items(v_second_draft.id, '[{"key": "quotation.threshold_amount", "value": {"amount": 75000000, "currency": "IDR"}}]'::jsonb, '00000000-0000-0000-0000-000000001301', 'tenant admin');
  v_second_published := app.publish_config_version(v_second_draft.id, '00000000-0000-0000-0000-000000001301', null, 'tenant admin');

  select * into v_first_after from app.config_versions where id = v_published.id;
  if v_first_after.status <> 'archived' then
    raise exception 'assertion failed: expected the first published version to be archived after supersession, got %', v_first_after.status;
  end if;

  select count(*) into v_published_count
  from app.config_versions v join app.config_objects o on o.id = v.config_object_id
  where o.tenant_id = v_tenant_id and o.config_type_code = 'approval' and v.status = 'published';
  if v_published_count <> 1 then
    raise exception 'assertion failed: expected exactly one published version at a time, saw %', v_published_count;
  end if;
end;
$$;

\echo '>> app.detect_config_dependency_cycle / publish gate: a circular dependency blocks publish; a non-circular chain publishes fine'
do $$
declare
  v_tenant_id uuid;
  v_draft app.config_versions;
  v_item_a uuid;
  v_item_b uuid;
  v_item_c uuid;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmecfg');
  v_draft := app.create_config_draft('numbering', v_tenant_id, 'tenant', null, '00000000-0000-0000-0000-000000001301', 'tenant admin');
  perform app.set_config_items(
    v_draft.id,
    '[{"key": "invoice_number_pattern", "value": "INV-{seq}"}, {"key": "invoice_reset_rule", "value": "yearly"}, {"key": "invoice_prefix_rule", "value": "tenant-code"}]'::jsonb,
    '00000000-0000-0000-0000-000000001301', 'tenant admin'
  );

  select id into v_item_a from app.config_items where config_version_id = v_draft.id and key = 'invoice_number_pattern';
  select id into v_item_b from app.config_items where config_version_id = v_draft.id and key = 'invoice_reset_rule';
  select id into v_item_c from app.config_items where config_version_id = v_draft.id and key = 'invoice_prefix_rule';

  -- A -> B -> C, no cycle: publish should succeed.
  insert into app.config_dependencies (config_item_id, depends_on_config_item_id) values (v_item_a, v_item_b), (v_item_b, v_item_c);
  if app.detect_config_dependency_cycle(v_item_a) then
    raise exception 'assertion failed: expected A -> B -> C (no cycle) to be detected as acyclic';
  end if;
  perform app.publish_config_version(v_draft.id, '00000000-0000-0000-0000-000000001301', null, 'tenant admin');

  -- Now build a genuinely circular chain in a fresh draft: A -> B -> C -> A.
  v_draft := app.create_config_draft('numbering', v_tenant_id, 'tenant', null, '00000000-0000-0000-0000-000000001301', 'tenant admin');
  perform app.set_config_items(
    v_draft.id,
    '[{"key": "invoice_number_pattern", "value": "INV-{seq}"}, {"key": "invoice_reset_rule", "value": "yearly"}, {"key": "invoice_prefix_rule", "value": "tenant-code"}]'::jsonb,
    '00000000-0000-0000-0000-000000001301', 'tenant admin'
  );
  select id into v_item_a from app.config_items where config_version_id = v_draft.id and key = 'invoice_number_pattern';
  select id into v_item_b from app.config_items where config_version_id = v_draft.id and key = 'invoice_reset_rule';
  select id into v_item_c from app.config_items where config_version_id = v_draft.id and key = 'invoice_prefix_rule';

  insert into app.config_dependencies (config_item_id, depends_on_config_item_id) values (v_item_a, v_item_b), (v_item_b, v_item_c), (v_item_c, v_item_a);
  if not app.detect_config_dependency_cycle(v_item_a) then
    raise exception 'assertion failed: expected A -> B -> C -> A to be detected as a real cycle';
  end if;

  begin
    perform app.publish_config_version(v_draft.id, '00000000-0000-0000-0000-000000001301', null, 'tenant admin');
    raise exception 'assertion failed: expected publish to be blocked by the circular dependency';
  exception
    when check_violation then
      null;
  end;

  begin
    insert into app.config_dependencies (config_item_id, depends_on_config_item_id) values (v_item_a, v_item_a);
    raise exception 'assertion failed: expected a self-referential dependency to be rejected structurally';
  exception
    when check_violation then
      null;
  end;
end;
$$;

\echo '>> app.resolve_config: the 6-level precedence walk -- a role-level override beats the tenant-level default, which beats the platform-neutral empty result'
do $$
declare
  v_tenant_id uuid;
  v_role_id uuid;
  v_role_draft app.config_versions;
  v_resolved record;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmecfg');
  v_role_id := (select id from app.roles where tenant_id = v_tenant_id and name = 'Finance Approver Cfg');

  -- Only the tenant-level version is published so far (from the earlier publish test).
  select * into v_resolved from app.resolve_config('approval', v_tenant_id);
  if v_resolved.resolved_scope_level <> 'tenant' then
    raise exception 'assertion failed: expected the tenant-level published version to resolve, got %', v_resolved.resolved_scope_level;
  end if;
  if (v_resolved.items ->> 'quotation.threshold_amount')::jsonb ->> 'amount' <> '75000000' then
    raise exception 'assertion failed: expected the tenant-level items to be returned';
  end if;

  -- A role-level override for the same config_type must now win over the tenant default.
  v_role_draft := app.create_config_draft('approval', v_tenant_id, 'role', v_role_id, '00000000-0000-0000-0000-000000001301', 'tenant admin');
  perform app.set_config_items(v_role_draft.id, '[{"key": "quotation.threshold_amount", "value": {"amount": 10000000, "currency": "IDR"}}]'::jsonb, '00000000-0000-0000-0000-000000001301', 'tenant admin');
  perform app.publish_config_version(v_role_draft.id, '00000000-0000-0000-0000-000000001301', null, 'tenant admin');

  select * into v_resolved from app.resolve_config('approval', v_tenant_id, null, null, v_role_id, null);
  if v_resolved.resolved_scope_level <> 'role' then
    raise exception 'assertion failed: expected the role-level override to win over the tenant default, got %', v_resolved.resolved_scope_level;
  end if;

  -- Without the role_id parameter, the tenant-level version still resolves (the role
  -- override is only relevant when that specific role is in scope).
  select * into v_resolved from app.resolve_config('approval', v_tenant_id);
  if v_resolved.resolved_scope_level <> 'tenant' then
    raise exception 'assertion failed: expected the tenant-level version to resolve when no role_id is given';
  end if;

  -- A config_type with no published version anywhere for this tenant resolves to
  -- nothing (not even a fabricated global default -- this migration''s own header:
  -- "configuration content itself has no universal, honest default this early").
  if exists (select 1 from app.resolve_config('branding', v_tenant_id)) then
    raise exception 'assertion failed: expected an unconfigured config_type to resolve to zero rows';
  end if;
end;
$$;

\echo '>> app.resolve_config: cross-tenant isolation -- gizmocfg never resolves acmecfg''s tenant-level configuration'
do $$
declare
  v_other_tenant_id uuid;
begin
  v_other_tenant_id := (select id from app.tenants where slug = 'gizmocfg');
  if exists (select 1 from app.resolve_config('approval', v_other_tenant_id)) then
    raise exception 'assertion failed: expected gizmocfg to have no resolved approval configuration of its own';
  end if;
end;
$$;

\echo '>> app.verify_config_version_current (EXC-CFG-001): true while unchanged, false the instant a newer version publishes'
do $$
declare
  v_tenant_id uuid;
  v_role_id uuid;
  v_resolved record;
  v_is_current boolean;
  v_new_draft app.config_versions;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmecfg');
  v_role_id := (select id from app.roles where tenant_id = v_tenant_id and name = 'Finance Approver Cfg');

  select * into v_resolved from app.resolve_config('approval', v_tenant_id, null, null, v_role_id, null);

  v_is_current := app.verify_config_version_current('approval', v_tenant_id, v_resolved.resolved_version_id, null, null, v_role_id, null);
  if not v_is_current then
    raise exception 'assertion failed: expected the just-resolved version_id to still be current';
  end if;

  v_new_draft := app.create_config_draft('approval', v_tenant_id, 'role', v_role_id, '00000000-0000-0000-0000-000000001301', 'tenant admin');
  perform app.set_config_items(v_new_draft.id, '[{"key": "quotation.threshold_amount", "value": {"amount": 5000000, "currency": "IDR"}}]'::jsonb, '00000000-0000-0000-0000-000000001301', 'tenant admin');
  perform app.publish_config_version(v_new_draft.id, '00000000-0000-0000-0000-000000001301', null, 'tenant admin');

  v_is_current := app.verify_config_version_current('approval', v_tenant_id, v_resolved.resolved_version_id, null, null, v_role_id, null);
  if v_is_current then
    raise exception 'assertion failed: expected the stale version_id to no longer be current after a new publish (EXC-CFG-001)';
  end if;
end;
$$;

\echo '>> app.rollback_config_version: never mutates history -- creates a brand-new version carrying the target''s exact item snapshot; rejects rolling back a draft'
do $$
declare
  v_tenant_id uuid;
  v_role_id uuid;
  v_target_id uuid;
  v_current_published_id uuid;
  v_rolled_back app.config_versions;
  v_rolled_back_items integer;
  v_new_draft app.config_versions;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmecfg');
  v_role_id := (select id from app.roles where tenant_id = v_tenant_id and name = 'Finance Approver Cfg');

  select v.id into v_target_id
  from app.config_versions v join app.config_objects o on o.id = v.config_object_id
  where o.tenant_id = v_tenant_id and o.config_type_code = 'approval' and o.scope_level = 'role' and v.version_number = 1;
  select v.id into v_current_published_id
  from app.config_versions v join app.config_objects o on o.id = v.config_object_id
  where o.tenant_id = v_tenant_id and o.config_type_code = 'approval' and o.scope_level = 'role' and v.status = 'published';
  if v_target_id = v_current_published_id then
    raise exception 'assertion failed (test setup bug): rollback target must differ from the currently published version';
  end if;

  v_rolled_back := app.rollback_config_version(v_target_id, '00000000-0000-0000-0000-000000001301', 'reverting to prior threshold', 'tenant admin');
  if v_rolled_back.status <> 'published' or v_rolled_back.id = v_target_id then
    raise exception 'assertion failed: expected rollback to publish a brand-new version, not reuse the target''s id';
  end if;

  select count(*) into v_rolled_back_items from app.config_items where config_version_id = v_rolled_back.id;
  if v_rolled_back_items <> (select count(*) from app.config_items where config_version_id = v_target_id) then
    raise exception 'assertion failed: expected the rolled-back version to carry the same item count as the target snapshot';
  end if;

  if (select status from app.config_versions where id = v_target_id) <> 'archived' then
    raise exception 'assertion failed: expected the rollback target itself to remain untouched (still archived, not mutated)';
  end if;

  v_new_draft := app.create_config_draft('approval', v_tenant_id, 'role', v_role_id, '00000000-0000-0000-0000-000000001301', 'tenant admin');
  begin
    perform app.rollback_config_version(v_new_draft.id, '00000000-0000-0000-0000-000000001301', 'x', 'tenant admin');
    raise exception 'assertion failed: expected rolling back a draft to be rejected';
  exception
    when check_violation then
      null;
  end;
  perform app.discard_config_draft(v_new_draft.id, '00000000-0000-0000-0000-000000001301', 'cleanup', 'tenant admin');
end;
$$;

\echo '>> every lifecycle mutation self-captures a canonical app.audit_logs entry (no bespoke *_history table exists for this capability)'
do $$
declare
  v_tenant_id uuid;
  v_actions text[] := array['create_config_draft', 'set_config_items', 'publish_config_version', 'rollback_config_version', 'discard_config_draft'];
  v_action text;
  v_count integer;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmecfg');

  foreach v_action in array v_actions loop
    select count(*) into v_count
    from app.audit_logs
    where tenant_id = v_tenant_id and action = v_action;
    if v_count = 0 then
      raise exception 'assertion failed: expected at least one app.audit_logs entry for action=%, saw none', v_action;
    end if;
  end loop;

  select count(*) into v_count
  from app.audit_logs
  where action = 'register_config_type' and tenant_id is null;
  if v_count = 0 then
    raise exception 'assertion failed: expected a platform-wide (null tenant_id) audit entry for register_config_type';
  end if;
end;
$$;

\echo '>> schema-privilege defense in depth: authenticated has no direct access to draft-bearing tables; anon is denied entirely; anon holds no EXECUTE on service_role-only mutations'
do $$
declare
  v_has_privilege boolean;
begin
  select has_table_privilege('authenticated', 'app.config_versions', 'SELECT') into v_has_privilege;
  if v_has_privilege then
    raise exception 'assertion failed: expected authenticated to hold no direct SELECT privilege on app.config_versions';
  end if;

  select has_table_privilege('authenticated', 'app.config_items', 'SELECT') into v_has_privilege;
  if v_has_privilege then
    raise exception 'assertion failed: expected authenticated to hold no direct SELECT privilege on app.config_items';
  end if;

  select has_table_privilege('anon', 'app.config_objects', 'SELECT') into v_has_privilege;
  if v_has_privilege then
    raise exception 'assertion failed: expected anon to hold no privilege on app.config_objects at all';
  end if;

  select has_function_privilege('authenticated', 'app.resolve_config(text, uuid, uuid, uuid, uuid, uuid)', 'EXECUTE') into v_has_privilege;
  if not v_has_privilege then
    raise exception 'assertion failed: expected authenticated to hold EXECUTE on app.resolve_config';
  end if;

  select has_function_privilege('anon', 'app.resolve_config(text, uuid, uuid, uuid, uuid, uuid)', 'EXECUTE') into v_has_privilege;
  if v_has_privilege then
    raise exception 'assertion failed: expected anon to hold no EXECUTE on app.resolve_config (no pre-authentication use case, unlike PLT-117/118/119''s evaluators)';
  end if;

  select has_function_privilege('anon', 'app.create_config_draft(text, uuid, text, uuid, uuid, text)', 'EXECUTE') into v_has_privilege;
  if v_has_privilege then
    raise exception 'assertion failed: expected anon to hold no EXECUTE on the service_role-only app.create_config_draft (ERR-2026-004 regression guard)';
  end if;
end;
$$;

\echo '>> ISS-2026-069: approval routing resolves per domain, falling back to the shared definition -- so seven already-live domains could adopt domain-scoped chains without any tenant being required to do anything'
do $$
declare
  v_tenant_id uuid := (select id from app.tenants where slug = 'acmecfg');
  v_other_tenant_id uuid := (select id from app.tenants where slug = 'gizmocfg');
  v_admin uuid := '00000000-0000-0000-0000-000000001301';
  v_draft app.config_versions;
  v_code text;
begin
  -- Before this fix, seven domains selected `config_type_code = 'approval'` literally, so one
  -- routing definition governed sales quotations, credit overrides, purchase orders, job
  -- offers, leave, onboarding finalisation and payroll finalisation alike. A chain a tenant
  -- meant for HR instantly governed every pending quotation.

  -- The default, and the reason this was safe to apply to seven live domains at once: with no
  -- domain-scoped definition published, every domain still resolves the shared code.
  foreach v_code in array array['quotation', 'credit_profile', 'procurement_entity', 'job_offer', 'leave_request', 'onboarding_case', 'payroll_run'] loop
    if app._resolve_approval_config_type_code(v_tenant_id, v_code) <> 'approval' then
      raise exception 'assertion failed: with nothing domain-scoped published, % must fall back to the shared approval definition, got %', v_code, app._resolve_approval_config_type_code(v_tenant_id, v_code);
    end if;
  end loop;

  -- A registered-but-unpublished DRAFT must not switch anything. Publishing is the act that
  -- changes routing; drafting is not, or a half-configured chain would silently take over.
  v_draft := app.create_config_draft('approval:job_offer', v_tenant_id, 'tenant', null, v_admin, 'tenant admin');
  if app._resolve_approval_config_type_code(v_tenant_id, 'job_offer') <> 'approval' then
    raise exception 'assertion failed: an unpublished draft must not change routing';
  end if;

  -- Published: this domain switches, and only this domain.
  perform app.publish_config_version(v_draft.id, v_admin, null, 'tenant admin');
  if app._resolve_approval_config_type_code(v_tenant_id, 'job_offer') <> 'approval:job_offer' then
    raise exception 'assertion failed: a published approval:job_offer definition must govern job offers, got %', app._resolve_approval_config_type_code(v_tenant_id, 'job_offer');
  end if;
  foreach v_code in array array['quotation', 'credit_profile', 'procurement_entity', 'leave_request', 'onboarding_case', 'payroll_run'] loop
    if app._resolve_approval_config_type_code(v_tenant_id, v_code) <> 'approval' then
      raise exception 'assertion failed: scoping job offers must leave % on the shared definition -- that separation is the entire point, got %', v_code, app._resolve_approval_config_type_code(v_tenant_id, v_code);
    end if;
  end loop;

  -- Tenant isolation: one tenant's domain-scoped definition never governs another's.
  if app._resolve_approval_config_type_code(v_other_tenant_id, 'job_offer') <> 'approval' then
    raise exception 'assertion failed: acmecfg''s approval:job_offer definition must not govern gizmocfg';
  end if;

  -- An unknown domain code resolves to the shared definition rather than to a code nobody has
  -- registered -- a typo in a caller must degrade to the old behaviour, never to nothing.
  if app._resolve_approval_config_type_code(v_tenant_id, 'no_such_domain') <> 'approval' then
    raise exception 'assertion failed: an unknown domain must fall back to the shared definition';
  end if;

  raise notice 'PASS: job offers route through their own published definition while six sibling domains stay on the shared one, and neither crosses a tenant boundary';
end $$;

\echo '>> ISS-2026-069: all seven consumers genuinely go through the resolver -- a domain left on the hardcoded literal would look fixed while silently sharing the singleton'
do $$
declare
  v_fn text;
  v_src text;
  v_expected text;
  v_missing text[] := array[]::text[];
  v_still_literal text[] := array[]::text[];
begin
  for v_fn, v_expected in
    select * from (values
      ('_request_procurement_entity_approval', 'procurement_entity'),
      ('request_customer_credit_profile', 'credit_profile'),
      ('submit_job_offer_for_approval', 'job_offer'),
      ('submit_leave_request', 'leave_request'),
      ('submit_onboarding_case_for_finalize_approval', 'onboarding_case'),
      ('submit_payroll_run_for_finalization', 'payroll_run'),
      ('submit_quotation', 'quotation')
    ) as t(fn, domain)
  loop
    select p.prosrc into v_src from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app' and p.proname = v_fn;
    if v_src is null then
      raise exception 'assertion failed: app.% not found', v_fn;
    end if;
    if v_src not like '%resolve_approval_config_type_code(%''' || v_expected || '''%' then
      v_missing := array_append(v_missing, v_fn);
    end if;
    -- The literal must be GONE from the selector, not merely accompanied by the resolver.
    if v_src like '%config_type_code = ''approval'' and%' then
      v_still_literal := array_append(v_still_literal, v_fn);
    end if;
  end loop;

  if array_length(v_missing, 1) is not null then
    raise exception 'assertion failed: these consumers do not resolve their own domain: %', v_missing;
  end if;
  if array_length(v_still_literal, 1) is not null then
    raise exception 'assertion failed: these consumers still hardcode the shared approval literal: %', v_still_literal;
  end if;

  -- And nothing ELSE in the schema still hardcodes it, which is how the entry's own
  -- undercount (four consumers named, seven actually present) happened in the first place.
  select array_agg(p.proname order by p.proname) into v_missing
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'app' and p.prosrc like '%config_type_code = ''approval'' and%';
  if v_missing is not null then
    raise exception 'assertion failed: a consumer outside the known seven still hardcodes the shared approval definition: % -- add it to the resolver rather than letting the singleton grow again', v_missing;
  end if;

  raise notice 'PASS: all seven consumers resolve their own domain, and no function anywhere still hardcodes the shared approval literal';
end $$;
