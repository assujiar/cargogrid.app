-- Real, executable test evidence for PLT-117 (White-Label Foundation, CG-S6-PLT-014).

\set ON_ERROR_STOP on

\echo '>> setup: two tenants each with a tenant_admin, a regular org_user, and a global Supreme Admin'
do $$
declare
  v_tenant_id uuid;
  v_other_tenant_id uuid;
  v_org_unit_id uuid;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000000901', 'tenantadminwlb@example.test'),
    ('00000000-0000-0000-0000-000000000902', 'regularuserwlb@example.test'),
    ('00000000-0000-0000-0000-000000000903', 'supremewlb@example.test'),
    ('00000000-0000-0000-0000-000000000904', 'othertenantadminwlb@example.test');

  perform app.provision_tenant('acmewlb', 'Acme White-Label Co', 'idem-acmewlb', 'tester');
  v_tenant_id := (select id from app.tenants where slug = 'acmewlb');
  perform app.transition_tenant_status(v_tenant_id, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant_id, 'company', null, 'ACMEWLB-CO', 'Acme White-Label Co HQ', 'tester');
  v_org_unit_id := (select id from app.org_units where tenant_id = v_tenant_id and code = 'ACMEWLB-CO');

  perform app.invite_user(v_tenant_id, '00000000-0000-0000-0000-000000000901', 'tenantadminwlb@example.test', 'Tenant Admin', v_org_unit_id, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'tenantadminwlb@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000000901', 'tenant_admin', v_tenant_id, null, 'tester');

  perform app.invite_user(v_tenant_id, '00000000-0000-0000-0000-000000000902', 'regularuserwlb@example.test', 'Regular User', v_org_unit_id, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'regularuserwlb@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000000902', 'org_user', v_tenant_id, null, 'tester');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000000903', 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('gizmowlb', 'Gizmo White-Label Co', 'idem-gizmowlb', 'tester');
  v_other_tenant_id := (select id from app.tenants where slug = 'gizmowlb');
  perform app.transition_tenant_status(v_other_tenant_id, 'active', 'setup', 'tester');
  perform app.invite_user(v_other_tenant_id, '00000000-0000-0000-0000-000000000904', 'othertenantadminwlb@example.test', 'Other Tenant Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'othertenantadminwlb@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000000904', 'tenant_admin', v_other_tenant_id, null, 'tester');
end;
$$;

\echo '>> app.hex_color_contrast_ratio: known reference pairs (WCAG formula sanity check)'
do $$
declare
  v_ratio numeric;
begin
  v_ratio := app.hex_color_contrast_ratio('#000000', '#ffffff');
  if v_ratio <> 21.0 then
    raise exception 'assertion failed: expected black-on-white contrast ratio 21.0, got %', v_ratio;
  end if;

  v_ratio := app.hex_color_contrast_ratio('#ffffff', '#ffffff');
  if v_ratio <> 1.0 then
    raise exception 'assertion failed: expected identical-color contrast ratio 1.0, got %', v_ratio;
  end if;

  -- Symmetric regardless of argument order.
  if app.hex_color_contrast_ratio('#171717', '#fafafa') <> app.hex_color_contrast_ratio('#fafafa', '#171717') then
    raise exception 'assertion failed: expected contrast ratio to be symmetric';
  end if;

  begin
    perform app.hex_color_contrast_ratio('not-a-color', '#ffffff');
    raise exception 'assertion failed: expected a malformed hex color to raise';
  exception
    when invalid_text_representation then
      null; -- expected
  end;
end;
$$;

\echo '>> app.tenant_brand_versions CHECK constraints: malformed tokens/asset URLs/template refs are rejected structurally'
do $$
declare
  v_tenant_id uuid;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmewlb');

  begin
    insert into app.tenant_brand_versions (tenant_id, version_number, tokens) values (v_tenant_id, 900, '{"primary": "red"}'::jsonb);
    raise exception 'assertion failed: expected a non-hex primary token to be rejected';
  exception
    when check_violation then
      null;
  end;

  begin
    insert into app.tenant_brand_versions (tenant_id, version_number, tokens) values (v_tenant_id, 901, '{"accent": "#ff0000"}'::jsonb);
    raise exception 'assertion failed: expected an out-of-scope token key to be rejected';
  exception
    when check_violation then
      null;
  end;

  begin
    insert into app.tenant_brand_versions (tenant_id, version_number, logo_asset_url) values (v_tenant_id, 902, 'javascript:alert(1)');
    raise exception 'assertion failed: expected a javascript: logo URL to be rejected';
  exception
    when check_violation then
      null;
  end;

  begin
    insert into app.tenant_brand_versions (tenant_id, version_number, logo_asset_url) values (v_tenant_id, 903, 'http://insecure.example.test/logo.png');
    raise exception 'assertion failed: expected a non-https logo URL to be rejected';
  exception
    when check_violation then
      null;
  end;

  begin
    insert into app.tenant_brand_versions (tenant_id, version_number, document_template_refs)
    values (v_tenant_id, 904, '{"email_footer_text": "<script>alert(1)</script>"}'::jsonb);
    raise exception 'assertion failed: expected an angle-bracket template value to be rejected';
  exception
    when check_violation then
      null;
  end;

  begin
    insert into app.tenant_brand_versions (tenant_id, version_number, document_template_refs)
    values (v_tenant_id, 905, '{"unknown_key": "x"}'::jsonb);
    raise exception 'assertion failed: expected an out-of-scope template key to be rejected';
  exception
    when check_violation then
      null;
  end;

  begin
    insert into app.tenant_brand_versions (tenant_id, version_number, email_sender_name)
    values (v_tenant_id, 906, '<b>Acme</b>');
    raise exception 'assertion failed: expected an angle-bracket email sender name to be rejected';
  exception
    when check_violation then
      null;
  end;
end;
$$;

\echo '>> app.create_tenant_brand_draft: idempotent, authority-gated (tenant_admin of own tenant, or Supreme Admin -- never a foreign tenant_admin or a regular org_user)'
do $$
declare
  v_tenant_id uuid;
  v_other_tenant_id uuid;
  v_draft1 app.tenant_brand_versions;
  v_draft2 app.tenant_brand_versions;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmewlb');
  v_other_tenant_id := (select id from app.tenants where slug = 'gizmowlb');

  begin
    perform app.create_tenant_brand_draft(v_tenant_id, '00000000-0000-0000-0000-000000000902', 'regular user');
    raise exception 'assertion failed: expected a regular org_user to be denied draft creation';
  exception
    when insufficient_privilege then
      null;
  end;

  begin
    perform app.create_tenant_brand_draft(v_tenant_id, '00000000-0000-0000-0000-000000000904', 'foreign tenant admin');
    raise exception 'assertion failed: expected a different tenant''s tenant_admin to be denied';
  exception
    when insufficient_privilege then
      null;
  end;

  v_draft1 := app.create_tenant_brand_draft(v_tenant_id, '00000000-0000-0000-0000-000000000901', 'tenant admin');
  if v_draft1.status <> 'draft' or v_draft1.version_number <> 1 then
    raise exception 'assertion failed: expected a fresh version_number=1 draft, got status=% version_number=%', v_draft1.status, v_draft1.version_number;
  end if;

  v_draft2 := app.create_tenant_brand_draft(v_tenant_id, '00000000-0000-0000-0000-000000000901', 'tenant admin');
  if v_draft2.id <> v_draft1.id then
    raise exception 'assertion failed: expected a repeated call to return the same existing draft, not create a second one';
  end if;

  -- Supreme Admin may also manage this tenant's brand (Prompt 117 §26).
  perform app.discard_tenant_brand_draft(v_draft1.id, '00000000-0000-0000-0000-000000000903', 'supreme admin cleanup', 'supreme admin');
  v_draft2 := app.create_tenant_brand_draft(v_tenant_id, '00000000-0000-0000-0000-000000000903', 'supreme admin');
  if v_draft2.version_number <> 2 then
    raise exception 'assertion failed: expected the next draft to be version_number=2 after the discard, got %', v_draft2.version_number;
  end if;
end;
$$;

\echo '>> app.set_tenant_brand_tokens: only mutates a draft; contrast is computed as preview evidence, not yet enforced'
do $$
declare
  v_tenant_id uuid;
  v_draft app.tenant_brand_versions;
  v_updated app.tenant_brand_versions;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmewlb');
  select * into v_draft from app.tenant_brand_versions where tenant_id = v_tenant_id and status = 'draft';

  -- A pale, low-contrast primary (still legal to save as a draft for preview).
  v_updated := app.set_tenant_brand_tokens(
    v_draft.id, '00000000-0000-0000-0000-000000000901', '{"primary": "#eeeeee"}'::jsonb,
    'https://storage.example.test/acmewlb/logo.png', 'Acme White-Label', null, '{}'::jsonb, 'tenant admin'
  );
  if v_updated.contrast_validated is not false then
    raise exception 'assertion failed: expected a low-contrast draft to be saved with contrast_validated=false, not rejected';
  end if;
  if v_updated.logo_asset_url <> 'https://storage.example.test/acmewlb/logo.png' then
    raise exception 'assertion failed: expected the logo asset URL to persist';
  end if;

  -- Replacing with an accessible color updates contrast_validated to true.
  v_updated := app.set_tenant_brand_tokens(
    v_draft.id, '00000000-0000-0000-0000-000000000901', '{"primary": "#1d4ed8", "secondary": "#171717"}'::jsonb,
    null, null, null, '{}'::jsonb, 'tenant admin'
  );
  if v_updated.contrast_validated is not true then
    raise exception 'assertion failed: expected an accessible primary color to set contrast_validated=true, got %', v_updated.contrast_validated;
  end if;

  begin
    perform app.set_tenant_brand_tokens(v_draft.id, '00000000-0000-0000-0000-000000000902', '{}'::jsonb, null, null, null, '{}'::jsonb, 'regular user');
    raise exception 'assertion failed: expected a regular org_user to be denied';
  exception
    when insufficient_privilege then
      null;
  end;
end;
$$;

\echo '>> app.publish_tenant_brand_version: enforces the 4.5:1 contrast gate and rejects a version_id that does not exist'
do $$
declare
  v_tenant_id uuid;
  v_draft app.tenant_brand_versions;
  v_low_contrast_draft app.tenant_brand_versions;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmewlb');
  select * into v_draft from app.tenant_brand_versions where tenant_id = v_tenant_id and status = 'draft';

  begin
    perform app.publish_tenant_brand_version('00000000-0000-0000-0000-000000000999', '00000000-0000-0000-0000-000000000901', null, 'tenant admin');
    raise exception 'assertion failed: expected a nonexistent version_id to raise brand_version_not_found';
  exception
    when no_data_found then
      null;
  end;

  -- Publish is blocked while the current draft still holds a low-contrast primary --
  -- reproduce that state, then attempt publish.
  perform app.set_tenant_brand_tokens(v_draft.id, '00000000-0000-0000-0000-000000000901', '{"primary": "#eeeeee"}'::jsonb, null, null, null, '{}'::jsonb, 'tenant admin');
  begin
    perform app.publish_tenant_brand_version(v_draft.id, '00000000-0000-0000-0000-000000000901', null, 'tenant admin');
    raise exception 'assertion failed: expected the low-contrast primary to block publish';
  exception
    when check_violation then
      null;
  end;

  -- Confirm the version is genuinely still a draft after the rejected publish attempt.
  select * into v_low_contrast_draft from app.tenant_brand_versions where id = v_draft.id;
  if v_low_contrast_draft.status <> 'draft' then
    raise exception 'assertion failed: expected the version to remain draft after a rejected publish, got %', v_low_contrast_draft.status;
  end if;
end;
$$;

\echo '>> app.publish_tenant_brand_version: a version with no primary color at all always publishes (nothing to validate -- the default-theme case)'
do $$
declare
  v_tenant_id uuid;
  v_draft app.tenant_brand_versions;
  v_published app.tenant_brand_versions;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmewlb');
  select * into v_draft from app.tenant_brand_versions where tenant_id = v_tenant_id and status = 'draft';

  perform app.set_tenant_brand_tokens(v_draft.id, '00000000-0000-0000-0000-000000000901', '{}'::jsonb, null, null, null, '{}'::jsonb, 'tenant admin');
  v_published := app.publish_tenant_brand_version(v_draft.id, '00000000-0000-0000-0000-000000000901', null, 'tenant admin');
  if v_published.status <> 'published' then
    raise exception 'assertion failed: expected a token-free version to publish successfully, got status=%', v_published.status;
  end if;
end;
$$;

\echo '>> app.publish_tenant_brand_version: publishing a new draft supersedes (archives) the tenant''s previously published version; at most one published version at a time'
do $$
declare
  v_tenant_id uuid;
  v_first_published_id uuid;
  v_draft app.tenant_brand_versions;
  v_second_published app.tenant_brand_versions;
  v_first_after app.tenant_brand_versions;
  v_published_count integer;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmewlb');
  v_first_published_id := (select id from app.tenant_brand_versions where tenant_id = v_tenant_id and status = 'published');

  v_draft := app.create_tenant_brand_draft(v_tenant_id, '00000000-0000-0000-0000-000000000901', 'tenant admin');
  perform app.set_tenant_brand_tokens(v_draft.id, '00000000-0000-0000-0000-000000000901', '{"primary": "#1d4ed8"}'::jsonb, null, null, null, '{}'::jsonb, 'tenant admin');
  v_second_published := app.publish_tenant_brand_version(v_draft.id, '00000000-0000-0000-0000-000000000901', null, 'tenant admin');

  if v_second_published.status <> 'published' then
    raise exception 'assertion failed: expected the second version to publish';
  end if;

  select * into v_first_after from app.tenant_brand_versions where id = v_first_published_id;
  if v_first_after.status <> 'archived' then
    raise exception 'assertion failed: expected the first published version to be archived after supersession, got %', v_first_after.status;
  end if;

  select count(*) into v_published_count from app.tenant_brand_versions where tenant_id = v_tenant_id and status = 'published';
  if v_published_count <> 1 then
    raise exception 'assertion failed: expected exactly one published version at a time, saw %', v_published_count;
  end if;
end;
$$;

\echo '>> app.rollback_tenant_brand_version: never mutates history -- creates a brand-new version carrying the target''s exact snapshot, then publishes it; rejects rolling back a draft'
do $$
declare
  v_tenant_id uuid;
  v_first_published_id uuid;
  v_current_published_id uuid;
  v_rolled_back app.tenant_brand_versions;
  v_target_still_archived app.tenant_brand_versions;
  v_new_draft app.tenant_brand_versions;
begin
  -- version_number=2 is the tenant's first-ever published version (archived by the
  -- supersession test above); the tenant's *current* published version is a distinct,
  -- later row (version_number=3) -- the rollback target below must be the former.
  v_tenant_id := (select id from app.tenants where slug = 'acmewlb');
  v_first_published_id := (select id from app.tenant_brand_versions where tenant_id = v_tenant_id and version_number = 2);
  v_current_published_id := (select id from app.tenant_brand_versions where tenant_id = v_tenant_id and status = 'published');
  if v_first_published_id = v_current_published_id then
    raise exception 'assertion failed (test setup bug): rollback target must differ from the currently published version';
  end if;

  v_rolled_back := app.rollback_tenant_brand_version(v_first_published_id, '00000000-0000-0000-0000-000000000901', 'reverting to prior brand', 'tenant admin');

  if v_rolled_back.status <> 'published' then
    raise exception 'assertion failed: expected rollback to publish immediately, got status=%', v_rolled_back.status;
  end if;
  if v_rolled_back.id = v_first_published_id then
    raise exception 'assertion failed: expected rollback to create a brand-new version row, not reuse the target''s id';
  end if;
  if v_rolled_back.rollback_of_version_id <> v_first_published_id then
    raise exception 'assertion failed: expected rollback_of_version_id to reference the target version';
  end if;
  if v_rolled_back.tokens is distinct from (select tokens from app.tenant_brand_versions where id = v_first_published_id) then
    raise exception 'assertion failed: expected the rolled-back version to carry the target''s exact token snapshot';
  end if;

  -- The rollback target itself is untouched (still exactly the row it was).
  select * into v_target_still_archived from app.tenant_brand_versions where id = v_first_published_id;
  if v_target_still_archived.status <> 'archived' then
    raise exception 'assertion failed: expected the rollback target to remain archived, not be mutated, got %', v_target_still_archived.status;
  end if;

  -- The version that was live immediately before the rollback is now archived (superseded).
  if (select status from app.tenant_brand_versions where id = v_current_published_id) <> 'archived' then
    raise exception 'assertion failed: expected the version superseded by the rollback to be archived';
  end if;

  -- A draft cannot be a rollback target.
  v_new_draft := app.create_tenant_brand_draft(v_tenant_id, '00000000-0000-0000-0000-000000000901', 'tenant admin');
  begin
    perform app.rollback_tenant_brand_version(v_new_draft.id, '00000000-0000-0000-0000-000000000901', 'x', 'tenant admin');
    raise exception 'assertion failed: expected rolling back a draft to be rejected';
  exception
    when check_violation then
      null;
  end;
  perform app.discard_tenant_brand_draft(v_new_draft.id, '00000000-0000-0000-0000-000000000901', 'cleanup', 'tenant admin');
end;
$$;

\echo '>> every lifecycle mutation self-captures a canonical app.audit_logs entry (Prompt 117 §18) -- no bespoke *_history table exists for this capability'
do $$
declare
  v_tenant_id uuid;
  v_actions text[] := array['create_tenant_brand_draft', 'set_tenant_brand_tokens', 'publish_tenant_brand_version', 'rollback_tenant_brand_version', 'discard_tenant_brand_draft'];
  v_action text;
  v_count integer;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmewlb');

  foreach v_action in array v_actions loop
    select count(*) into v_count
    from app.audit_logs
    where tenant_id = v_tenant_id and action = v_action and resource_type = 'app.tenant_brand_versions';
    if v_count = 0 then
      raise exception 'assertion failed: expected at least one app.audit_logs entry for action=%, saw none', v_action;
    end if;
  end loop;
end;
$$;

\echo '>> app.evaluate_tenant_brand: returns the tenant''s published version when one exists and the tenant is active'
do $$
declare
  v_tenant_id uuid;
  v_current_published app.tenant_brand_versions;
  v_result record;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmewlb');
  select * into v_current_published from app.tenant_brand_versions where tenant_id = v_tenant_id and status = 'published';

  select * into v_result from app.evaluate_tenant_brand(v_tenant_id);
  if v_result.source <> 'tenant' or v_result.version_id <> v_current_published.id then
    raise exception 'assertion failed: expected source=tenant version_id=%, got source=% version_id=%', v_current_published.id, v_result.source, v_result.version_id;
  end if;
  if v_result.tokens is distinct from v_current_published.tokens then
    raise exception 'assertion failed: expected the evaluator''s tokens to match the published row exactly';
  end if;
end;
$$;

\echo '>> app.evaluate_tenant_brand: falls back to the accessible CargoGrid default when a tenant has never published, does not exist, or is inactive'
do $$
declare
  v_tenant_id uuid;
  v_result record;
begin
  -- Never published anything.
  v_tenant_id := (select id from app.tenants where slug = 'gizmowlb');
  select * into v_result from app.evaluate_tenant_brand(v_tenant_id);
  if v_result.source <> 'default' or v_result.version_id is not null then
    raise exception 'assertion failed: expected the default fallback for a tenant with no published version, got source=%', v_result.source;
  end if;
  if v_result.tokens <> '{"primary": "#171717", "secondary": "#171717"}'::jsonb then
    raise exception 'assertion failed: expected the sourced neutral-900 default tokens, got %', v_result.tokens;
  end if;

  -- Nonexistent tenant.
  select * into v_result from app.evaluate_tenant_brand('00000000-0000-0000-0000-000000000000');
  if v_result.source <> 'default' then
    raise exception 'assertion failed: expected the default fallback for a nonexistent tenant';
  end if;

  -- Suspend the tenant that *does* have a published version -- the override must not
  -- leak through to a tenant no longer in good standing.
  v_tenant_id := (select id from app.tenants where slug = 'acmewlb');
  perform app.transition_tenant_status(v_tenant_id, 'suspended', 'billing hold', 'tester');
  select * into v_result from app.evaluate_tenant_brand(v_tenant_id);
  if v_result.source <> 'default' then
    raise exception 'assertion failed: expected a suspended tenant to fall back to the default theme, got source=%', v_result.source;
  end if;
  perform app.transition_tenant_status(v_tenant_id, 'active', 'billing resolved', 'tester');
end;
$$;

\echo '>> schema-privilege defense in depth: authenticated/anon have no direct table access to app.tenant_brand_versions (the only read path is app.evaluate_tenant_brand)'
do $$
declare
  v_has_privilege boolean;
begin
  select has_table_privilege('authenticated', 'app.tenant_brand_versions', 'SELECT') into v_has_privilege;
  if v_has_privilege then
    raise exception 'assertion failed: expected authenticated to hold no direct SELECT privilege on app.tenant_brand_versions';
  end if;

  select has_table_privilege('anon', 'app.tenant_brand_versions', 'SELECT') into v_has_privilege;
  if v_has_privilege then
    raise exception 'assertion failed: expected anon to hold no direct SELECT privilege on app.tenant_brand_versions';
  end if;

  select has_function_privilege('anon', 'app.evaluate_tenant_brand(uuid)', 'EXECUTE') into v_has_privilege;
  if not v_has_privilege then
    raise exception 'assertion failed: expected anon to hold EXECUTE on app.evaluate_tenant_brand (needed pre-authentication for a tenant''s login page)';
  end if;
end;
$$;

\echo '>> app.evaluate_tenant_brand: cross-tenant isolation -- evaluating one tenant never returns another tenant''s published tokens'
do $$
declare
  v_acme_id uuid;
  v_gizmo_id uuid;
  v_gizmo_draft app.tenant_brand_versions;
  v_result record;
begin
  v_acme_id := (select id from app.tenants where slug = 'acmewlb');
  v_gizmo_id := (select id from app.tenants where slug = 'gizmowlb');

  v_gizmo_draft := app.create_tenant_brand_draft(v_gizmo_id, '00000000-0000-0000-0000-000000000904', 'gizmo tenant admin');
  perform app.set_tenant_brand_tokens(v_gizmo_draft.id, '00000000-0000-0000-0000-000000000904', '{"primary": "#b91c1c"}'::jsonb, null, null, null, '{}'::jsonb, 'gizmo tenant admin');
  perform app.publish_tenant_brand_version(v_gizmo_draft.id, '00000000-0000-0000-0000-000000000904', null, 'gizmo tenant admin');

  select * into v_result from app.evaluate_tenant_brand(v_acme_id);
  if v_result.tokens ->> 'primary' = '#b91c1c' then
    raise exception 'assertion failed: acme''s evaluated brand must never leak gizmo''s published primary color';
  end if;

  select * into v_result from app.evaluate_tenant_brand(v_gizmo_id);
  if v_result.tokens ->> 'primary' <> '#b91c1c' then
    raise exception 'assertion failed: expected gizmo''s own evaluated brand to reflect its own publish';
  end if;
end;
$$;

\echo '>> app.discard_tenant_brand_draft: draft -> archived directly; only a draft may be discarded'
do $$
declare
  v_tenant_id uuid;
  v_draft app.tenant_brand_versions;
  v_discarded app.tenant_brand_versions;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmewlb');
  v_draft := app.create_tenant_brand_draft(v_tenant_id, '00000000-0000-0000-0000-000000000901', 'tenant admin');

  v_discarded := app.discard_tenant_brand_draft(v_draft.id, '00000000-0000-0000-0000-000000000901', 'changed my mind', 'tenant admin');
  if v_discarded.status <> 'archived' or v_discarded.archived_reason <> 'changed my mind' then
    raise exception 'assertion failed: expected the draft to be archived with the given reason';
  end if;

  begin
    perform app.discard_tenant_brand_draft(v_discarded.id, '00000000-0000-0000-0000-000000000901', 'x', 'tenant admin');
    raise exception 'assertion failed: expected discarding an already-archived version to be rejected';
  exception
    when check_violation then
      null;
  end;
end;
$$;

\echo '>> at most one draft per tenant at a time (partial unique index)'
do $$
declare
  v_tenant_id uuid;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmewlb');
  perform app.create_tenant_brand_draft(v_tenant_id, '00000000-0000-0000-0000-000000000901', 'tenant admin');

  begin
    insert into app.tenant_brand_versions (tenant_id, version_number, status) values (v_tenant_id, 950, 'draft');
    raise exception 'assertion failed: expected inserting a second concurrent draft to violate the single-draft partial unique index';
  exception
    when unique_violation then
      null;
  end;
end;
$$;
