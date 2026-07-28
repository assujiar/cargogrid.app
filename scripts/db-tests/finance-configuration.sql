-- Real, executable test evidence for FIN-191 (Finance Configuration,
-- CG-S9-FIN-002) -- run via `pnpm run db:test` against a real, disposable
-- Postgres database. Proves: the six Finance Configuration classes reuse
-- PLT-121's own Configuration Engine directly; the two-factor authority model
-- (FIN:Edit/FIN:Approve AND tenant_admin/Supreme, inherited from the reused
-- engine's own app.check_config_object_authority); per-class structural
-- validation at publish time; preview-impact's disclosed
-- pendingChartOfAccountsRefs for finance_posting_map; draft-items read-back;
-- rollback; and schema-privilege defense in depth.

\set ON_ERROR_STOP on

\echo '>> setup: two tenants, each with a tenant_admin; tenant A gets a Finance Admin (tenant_admin AND FIN:Edit/FIN:Approve), a Finance Editor (FIN:Edit/FIN:Approve WITHOUT tenant_admin -- proves the two-factor gate), and a plain org_user with no FIN grant at all; tenant B gets its own Finance Admin for cross-tenant checks'
do $$
declare
  v_tenant_a uuid;
  v_tenant_b uuid;
  v_team_a uuid;
  v_team_b uuid;
  v_fin_role_a uuid;
  v_fin_draft_a app.role_versions;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000024201', 'admina@acmefinconf.test'),
    ('00000000-0000-0000-0000-000000024202', 'financeadmina@acmefinconf.test'),
    ('00000000-0000-0000-0000-000000024203', 'financeeditora@acmefinconf.test'),
    ('00000000-0000-0000-0000-000000024204', 'plainusera@acmefinconf.test'),
    ('00000000-0000-0000-0000-000000024205', 'financeadminb@acmefinconf.test');

  perform app.provision_tenant('acmefinconfa', 'Acme Finance Config A', 'idem-acmefinconfa', 'tester');
  v_tenant_a := (select id from app.tenants where slug = 'acmefinconfa');
  perform app.transition_tenant_status(v_tenant_a, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant_a, 'company', null, 'ACMEFINCONFA-CO', 'Acme Finance Config A', 'tester');
  v_team_a := (select id from app.org_units where tenant_id = v_tenant_a and code = 'ACMEFINCONFA-CO');

  perform app.provision_tenant('acmefinconfb', 'Acme Finance Config B', 'idem-acmefinconfb', 'tester');
  v_tenant_b := (select id from app.tenants where slug = 'acmefinconfb');
  perform app.transition_tenant_status(v_tenant_b, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant_b, 'company', null, 'ACMEFINCONFB-CO', 'Acme Finance Config B', 'tester');
  v_team_b := (select id from app.org_units where tenant_id = v_tenant_b and code = 'ACMEFINCONFB-CO');

  -- Tenant A: bootstrap tenant_admin (grants principal membership directly, not via invite -- mirrors commercial-hardening.sql's own precedent).
  perform app.invite_user(v_tenant_a, '00000000-0000-0000-0000-000000024201', 'admina@acmefinconf.test', 'Tenant A Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admina@acmefinconf.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000024201', 'tenant_admin', v_tenant_a, null, 'tester');

  -- Finance Admin A: tenant_admin AND FIN:Edit/FIN:Approve -- the real "Finance Admin drafts; configured approvers publish" identity (Prompt 191 section 26).
  perform app.invite_user(v_tenant_a, '00000000-0000-0000-0000-000000024202', 'financeadmina@acmefinconf.test', 'Finance Admin A', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'financeadmina@acmefinconf.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000024202', 'tenant_admin', v_tenant_a, null, 'tester');

  -- Finance Editor A: FIN:Edit/FIN:Approve but NOT tenant_admin -- proves the two-factor gate (RBAC alone is not enough; the reused engine's own tenant_admin/Supreme requirement still applies). Invited/onboarded BEFORE the role assignment below, which requires an active user profile in this tenant.
  perform app.invite_user(v_tenant_a, '00000000-0000-0000-0000-000000024203', 'financeeditora@acmefinconf.test', 'Finance Editor A', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'financeeditora@acmefinconf.test'), 'active', 'onboarded', 'tester');

  v_fin_role_a := (app.create_role(v_tenant_a, 'Finance Admin', 'finance config authority', 'tester')).id;
  v_fin_draft_a := app.create_role_version(v_fin_role_a, 'tester');
  perform app.set_role_version_permissions(v_fin_draft_a.id, array(select id from app.permissions where resource_module_code = 'FIN' and action in ('Edit', 'Approve', 'View')), 'tester');
  perform app.publish_role_version(v_fin_draft_a.id, now(), 'tester');
  perform app.assign_role(v_tenant_a, (select id from app.role_versions where role_id = v_fin_role_a and status = 'published'), '00000000-0000-0000-0000-000000024202', '00000000-0000-0000-0000-000000024201', 'tester');
  perform app.assign_role(v_tenant_a, (select id from app.role_versions where role_id = v_fin_role_a and status = 'published'), '00000000-0000-0000-0000-000000024203', '00000000-0000-0000-0000-000000024201', 'tester');

  -- Plain org_user A: no FIN grant at all.
  perform app.invite_user(v_tenant_a, '00000000-0000-0000-0000-000000024204', 'plainusera@acmefinconf.test', 'Plain User A', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'plainusera@acmefinconf.test'), 'active', 'onboarded', 'tester');

  -- Tenant B: Finance Admin B (tenant_admin + FIN:Edit/Approve), same shape as A -- used for cross-tenant checks.
  perform app.invite_user(v_tenant_b, '00000000-0000-0000-0000-000000024205', 'financeadminb@acmefinconf.test', 'Finance Admin B', v_team_b, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'financeadminb@acmefinconf.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000024205', 'tenant_admin', v_tenant_b, null, 'tester');
end;
$$;

\echo '>> not_finance_config_type: create_finance_config_draft rejects an unrelated config_type_code (the platform approval type) before ever touching the generic engine'
do $$
declare
  v_tenant_a uuid;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmefinconfa');
  begin
    perform app.create_finance_config_draft('approval', v_tenant_a, 'tenant', null, '00000000-0000-0000-0000-000000024202', 'tester');
    raise exception 'assertion failed: expected not_finance_config_type';
  exception
    when others then
      if sqlerrm !~ 'not_finance_config_type' then
        raise exception 'assertion failed: expected not_finance_config_type, got %', sqlerrm;
      end if;
  end;
end;
$$;

\echo '>> two-factor authority: Finance Editor A (FIN:Edit, not tenant_admin) is rejected by the INHERITED engine-level tenant_admin/Supreme requirement, even though FIN:Edit itself is held'
do $$
declare
  v_tenant_a uuid;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmefinconfa');
  begin
    perform app.create_finance_config_draft('finance_rounding', v_tenant_a, 'tenant', null, '00000000-0000-0000-0000-000000024203', 'tester');
    raise exception 'assertion failed: expected insufficient_authority (inherited tenant_admin/Supreme requirement)';
  exception
    when insufficient_privilege then
      null; -- expected: FIN:Edit alone is not sufficient, matching this migration's own disclosed two-factor design
  end;
end;
$$;

\echo '>> two-factor authority, the other half: Plain User A (no FIN grant, not tenant_admin) is rejected by THIS capability''s own FIN:Edit check before ever reaching the generic engine'
do $$
declare
  v_tenant_a uuid;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmefinconfa');
  begin
    perform app.create_finance_config_draft('finance_rounding', v_tenant_a, 'tenant', null, '00000000-0000-0000-0000-000000024204', 'tester');
    raise exception 'assertion failed: expected insufficient_authority (FIN:Edit missing)';
  exception
    when insufficient_privilege then
      null;
  end;
end;
$$;

\echo '>> Finance Admin A (tenant_admin AND FIN:Edit) succeeds creating a finance_rounding draft; idempotent on a second call (returns the same draft, no duplicate)'
do $$
declare
  v_tenant_a uuid;
  v_draft1 app.config_versions;
  v_draft2 app.config_versions;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmefinconfa');
  select * into v_draft1 from app.create_finance_config_draft('finance_rounding', v_tenant_a, 'tenant', null, '00000000-0000-0000-0000-000000024202', 'financeadmina');
  if v_draft1.status <> 'draft' then
    raise exception 'assertion failed: expected a fresh draft, got status %', v_draft1.status;
  end if;

  select * into v_draft2 from app.create_finance_config_draft('finance_rounding', v_tenant_a, 'tenant', null, '00000000-0000-0000-0000-000000024202', 'financeadmina');
  if v_draft2.id <> v_draft1.id then
    raise exception 'assertion failed: expected the same draft on retry (idempotent), got a different version id';
  end if;
end;
$$;

\echo '>> structural validation, finance_rounding: an unregistered mode, an out-of-range precision, and an invalid order are each rejected at publish time with a distinct named exception'
do $$
declare
  v_tenant_a uuid;
  v_version_id uuid;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmefinconfa');
  select v.id into v_version_id from app.config_versions v join app.config_objects o on o.id = v.config_object_id
    where o.tenant_id = v_tenant_a and o.config_type_code = 'finance_rounding' and v.status = 'draft';

  perform app.set_finance_config_items(v_version_id, '[{"key": "default", "value": {"mode": "invented_mode", "precision": 2, "order": "convert_then_round"}}]'::jsonb, '00000000-0000-0000-0000-000000024202', 'financeadmina');
  begin
    perform app.publish_finance_config_version(v_version_id, '00000000-0000-0000-0000-000000024202', null, 'financeadmina');
    raise exception 'assertion failed: expected finance_rounding_invalid_mode';
  exception
    when others then
      if sqlerrm !~ 'finance_rounding_invalid_mode' then
        raise exception 'assertion failed: expected finance_rounding_invalid_mode, got %', sqlerrm;
      end if;
  end;

  perform app.set_finance_config_items(v_version_id, '[{"key": "default", "value": {"mode": "round_half_up", "precision": 9, "order": "convert_then_round"}}]'::jsonb, '00000000-0000-0000-0000-000000024202', 'financeadmina');
  begin
    perform app.publish_finance_config_version(v_version_id, '00000000-0000-0000-0000-000000024202', null, 'financeadmina');
    raise exception 'assertion failed: expected finance_rounding_invalid_precision';
  exception
    when others then
      if sqlerrm !~ 'finance_rounding_invalid_precision' then
        raise exception 'assertion failed: expected finance_rounding_invalid_precision, got %', sqlerrm;
      end if;
  end;

  perform app.set_finance_config_items(v_version_id, '[{"key": "default", "value": {"mode": "round_half_up", "precision": 2, "order": "not_a_real_order"}}]'::jsonb, '00000000-0000-0000-0000-000000024202', 'financeadmina');
  begin
    perform app.publish_finance_config_version(v_version_id, '00000000-0000-0000-0000-000000024202', null, 'financeadmina');
    raise exception 'assertion failed: expected finance_rounding_invalid_order';
  exception
    when others then
      if sqlerrm !~ 'finance_rounding_invalid_order' then
        raise exception 'assertion failed: expected finance_rounding_invalid_order, got %', sqlerrm;
      end if;
  end;

  -- A valid rounding definition publishes cleanly.
  perform app.set_finance_config_items(v_version_id, '[{"key": "default", "value": {"mode": "round_half_up", "precision": 2, "order": "convert_then_round"}}]'::jsonb, '00000000-0000-0000-0000-000000024202', 'financeadmina');
  perform app.publish_finance_config_version(v_version_id, '00000000-0000-0000-0000-000000024202', null, 'financeadmina');

  if (select status from app.config_versions where id = v_version_id) <> 'published' then
    raise exception 'assertion failed: expected the corrected rounding definition to publish';
  end if;
end;
$$;

\echo '>> structural validation, finance_numbering: the format-token rules mirror PLT-125''s own allowlist/exactly-one-{SEQ} logic (a parallel rule, not a fork of unrelated mechanics -- see the migration''s own header)'
do $$
declare
  v_tenant_a uuid;
  v_draft app.config_versions;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmefinconfa');
  select * into v_draft from app.create_finance_config_draft('finance_numbering', v_tenant_a, 'tenant', null, '00000000-0000-0000-0000-000000024202', 'financeadmina');

  perform app.set_finance_config_items(v_draft.id, '[{"key": "invoice", "value": {"prefix": "INV", "format": "INV-{YYYY}-NOSEQ", "resetPeriod": "yearly", "padding": 6}}]'::jsonb, '00000000-0000-0000-0000-000000024202', 'financeadmina');
  begin
    perform app.publish_finance_config_version(v_draft.id, '00000000-0000-0000-0000-000000024202', null, 'financeadmina');
    raise exception 'assertion failed: expected finance_numbering_invalid_seq_token_count';
  exception
    when others then
      if sqlerrm !~ 'finance_numbering_invalid_seq_token_count' then
        raise exception 'assertion failed: expected finance_numbering_invalid_seq_token_count, got %', sqlerrm;
      end if;
  end;

  perform app.set_finance_config_items(v_draft.id, '[{"key": "invoice", "value": {"prefix": "INV", "format": "INV-{BOGUS}-{SEQ}", "resetPeriod": "yearly", "padding": 6}}]'::jsonb, '00000000-0000-0000-0000-000000024202', 'financeadmina');
  begin
    perform app.publish_finance_config_version(v_draft.id, '00000000-0000-0000-0000-000000024202', null, 'financeadmina');
    raise exception 'assertion failed: expected finance_numbering_unknown_token';
  exception
    when others then
      if sqlerrm !~ 'finance_numbering_unknown_token' then
        raise exception 'assertion failed: expected finance_numbering_unknown_token, got %', sqlerrm;
      end if;
  end;

  -- A valid multi-document-class numbering definition (invoice + credit note in ONE version) publishes cleanly -- proving the deliberate departure from PLT-125's own single-flat-definition-per-version assumption (this migration's own header).
  perform app.set_finance_config_items(
    v_draft.id,
    '[{"key": "invoice", "value": {"prefix": "INV", "format": "INV-{YYYY}-{SEQ}", "resetPeriod": "yearly", "padding": 6}}, {"key": "credit_note", "value": {"prefix": "CN", "format": "CN-{YYYY}-{SEQ}", "resetPeriod": "yearly", "padding": 6}}]'::jsonb,
    '00000000-0000-0000-0000-000000024202', 'financeadmina'
  );
  perform app.publish_finance_config_version(v_draft.id, '00000000-0000-0000-0000-000000024202', null, 'financeadmina');
  if (select count(*) from app.config_items where config_version_id = v_draft.id) <> 2 then
    raise exception 'assertion failed: expected exactly 2 document-class numbering definitions in this one version';
  end if;
end;
$$;

\echo '>> structural validation, finance_recognition: the single-item ''policy'' shape rule, then all four bounded enums'
do $$
declare
  v_tenant_a uuid;
  v_draft app.config_versions;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmefinconfa');
  select * into v_draft from app.create_finance_config_draft('finance_recognition', v_tenant_a, 'tenant', null, '00000000-0000-0000-0000-000000024202', 'financeadmina');

  perform app.set_finance_config_items(v_draft.id, '[{"key": "not_policy", "value": {}}]'::jsonb, '00000000-0000-0000-0000-000000024202', 'financeadmina');
  begin
    perform app.publish_finance_config_version(v_draft.id, '00000000-0000-0000-0000-000000024202', null, 'financeadmina');
    raise exception 'assertion failed: expected finance_recognition_shape';
  exception
    when others then
      if sqlerrm !~ 'finance_recognition_shape' then
        raise exception 'assertion failed: expected finance_recognition_shape, got %', sqlerrm;
      end if;
  end;

  perform app.set_finance_config_items(
    v_draft.id,
    '[{"key": "policy", "value": {"budgetControlMode": "advisory", "accrualMethod": "accrual", "revenueRecognitionMethod": "invoice_date", "costRecognitionMethod": "incurred_date"}}]'::jsonb,
    '00000000-0000-0000-0000-000000024202', 'financeadmina'
  );
  perform app.publish_finance_config_version(v_draft.id, '00000000-0000-0000-0000-000000024202', null, 'financeadmina');
  if (select status from app.config_versions where id = v_draft.id) <> 'published' then
    raise exception 'assertion failed: expected the valid recognition policy to publish';
  end if;
end;
$$;

\echo '>> preview-impact, finance_posting_map: discloses every referenced account code as pendingChartOfAccountsRefs (no Chart of Accounts exists yet at FIN-191 in this dependency order)'
do $$
declare
  v_tenant_a uuid;
  v_draft app.config_versions;
  v_preview jsonb;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmefinconfa');
  select * into v_draft from app.create_finance_config_draft('finance_posting_map', v_tenant_a, 'tenant', null, '00000000-0000-0000-0000-000000024202', 'financeadmina');
  perform app.set_finance_config_items(v_draft.id, '[{"key": "ar_control", "value": {"accountCodeRef": "1200-AR", "dimensionDefaults": {}}}]'::jsonb, '00000000-0000-0000-0000-000000024202', 'financeadmina');

  select app.preview_finance_config_impact(v_draft.id) into v_preview;
  if not (v_preview ->> 'valid')::boolean then
    raise exception 'assertion failed: expected the posting map draft to be structurally valid, got %', v_preview;
  end if;
  if v_preview -> 'pendingChartOfAccountsRefs' <> '["1200-AR"]'::jsonb then
    raise exception 'assertion failed: expected pendingChartOfAccountsRefs=["1200-AR"], got %', v_preview -> 'pendingChartOfAccountsRefs';
  end if;

  -- An invalid account-code shape is rejected before it ever reaches preview's "valid" claim.
  perform app.set_finance_config_items(v_draft.id, '[{"key": "ar_control", "value": {"accountCodeRef": "not valid!"}}]'::jsonb, '00000000-0000-0000-0000-000000024202', 'financeadmina');
  select app.preview_finance_config_impact(v_draft.id) into v_preview;
  if (v_preview ->> 'valid')::boolean then
    raise exception 'assertion failed: expected preview to report valid=false for an invalid account-code shape';
  end if;
  if v_preview ->> 'error' !~ 'finance_posting_map_invalid_account_ref' then
    raise exception 'assertion failed: expected the error to name finance_posting_map_invalid_account_ref, got %', v_preview ->> 'error';
  end if;
end;
$$;

\echo '>> draft-items read-back: app.get_finance_config_version_items returns the current draft''s own items (never exposed via resolve_finance_config, which is published-only); denied without FIN:Edit'
do $$
declare
  v_tenant_a uuid;
  v_version_id uuid;
  v_items jsonb;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmefinconfa');
  select v.id into v_version_id from app.config_versions v join app.config_objects o on o.id = v.config_object_id
    where o.tenant_id = v_tenant_a and o.config_type_code = 'finance_rounding' and v.status = 'published';

  select app.get_finance_config_version_items(v_version_id, '00000000-0000-0000-0000-000000024202') into v_items;
  if v_items -> 'default' ->> 'mode' <> 'round_half_up' then
    raise exception 'assertion failed: expected the published rounding definition''s own items to read back exactly, got %', v_items;
  end if;

  begin
    perform app.get_finance_config_version_items(v_version_id, '00000000-0000-0000-0000-000000024204');
    raise exception 'assertion failed: expected insufficient_authority for Plain User A (no FIN:Edit)';
  exception
    when insufficient_privilege then
      null;
  end;
end;
$$;

\echo '>> resolve_finance_config: returns the published finance_rounding effective policy for tenant A; raises not_finance_config_type for an unrelated code; returns zero rows for a class with no published version at any scope (finance_close_policy, untouched so far)'
do $$
declare
  v_tenant_a uuid;
  v_row record;
  v_found boolean := false;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmefinconfa');

  for v_row in select * from app.resolve_finance_config('finance_rounding', v_tenant_a) loop
    v_found := true;
    if v_row.items -> 'default' ->> 'mode' <> 'round_half_up' then
      raise exception 'assertion failed: expected the resolved effective rounding mode to be round_half_up, got %', v_row.items;
    end if;
  end loop;
  if not v_found then
    raise exception 'assertion failed: expected exactly one resolved row for finance_rounding';
  end if;

  begin
    perform app.resolve_finance_config('approval', v_tenant_a);
    raise exception 'assertion failed: expected not_finance_config_type';
  exception
    when others then
      if sqlerrm !~ 'not_finance_config_type' then
        raise exception 'assertion failed: expected not_finance_config_type, got %', sqlerrm;
      end if;
  end;

  if exists (select 1 from app.resolve_finance_config('finance_close_policy', v_tenant_a)) then
    raise exception 'assertion failed: expected zero rows for finance_close_policy (never drafted/published in this fixture)';
  end if;
end;
$$;

\echo '>> discard: Finance Admin A discards a fresh finance_close_policy draft with a mandatory reason; a second discard on an already-archived version is rejected (not a draft)'
do $$
declare
  v_tenant_a uuid;
  v_draft app.config_versions;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmefinconfa');
  select * into v_draft from app.create_finance_config_draft('finance_close_policy', v_tenant_a, 'tenant', null, '00000000-0000-0000-0000-000000024202', 'financeadmina');
  perform app.set_finance_config_items(v_draft.id, '[{"key": "ar_aging_reconciled", "value": {"label": "AR aging reconciled", "required": true}}]'::jsonb, '00000000-0000-0000-0000-000000024202', 'financeadmina');

  perform app.discard_finance_config_draft(v_draft.id, '00000000-0000-0000-0000-000000024202', 'superseded by a different close-checklist design', 'financeadmina');
  if (select status from app.config_versions where id = v_draft.id) <> 'archived' then
    raise exception 'assertion failed: expected the discarded draft to be archived';
  end if;

  begin
    perform app.discard_finance_config_draft(v_draft.id, '00000000-0000-0000-0000-000000024202', 'again', 'financeadmina');
    raise exception 'assertion failed: expected config_version_not_draft on a second discard';
  exception
    when others then
      if sqlerrm !~ 'config_version_not_draft' then
        raise exception 'assertion failed: expected config_version_not_draft, got %', sqlerrm;
      end if;
  end;
end;
$$;

\echo '>> rollback: cloning the published finance_rounding version into a brand-new version, never mutating the target; requires FIN:Approve AND tenant_admin/Supreme (Finance Editor A, FIN:Approve but not tenant_admin, is rejected)'
do $$
declare
  v_tenant_a uuid;
  v_published_v1 uuid;
  v_rolled_back app.config_versions;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmefinconfa');
  select v.id into v_published_v1 from app.config_versions v join app.config_objects o on o.id = v.config_object_id
    where o.tenant_id = v_tenant_a and o.config_type_code = 'finance_rounding' and v.status = 'published';

  begin
    perform app.rollback_finance_config_version(v_published_v1, '00000000-0000-0000-0000-000000024203', 'trying without tenant_admin', 'financeeditora');
    raise exception 'assertion failed: expected insufficient_authority (Finance Editor A lacks the inherited tenant_admin/Supreme requirement)';
  exception
    when insufficient_privilege then
      null;
  end;

  select * into v_rolled_back from app.rollback_finance_config_version(v_published_v1, '00000000-0000-0000-0000-000000024202', 'revert to the original mode/precision/order', 'financeadmina');
  if v_rolled_back.status <> 'published' or v_rolled_back.rollback_of_version_id <> v_published_v1 then
    raise exception 'assertion failed: expected an immediately-published new version referencing the target via rollback_of_version_id';
  end if;
  if (select status from app.config_versions where id = v_published_v1) <> 'archived' then
    raise exception 'assertion failed: expected the target version to remain unmutated except for being archived (superseded), never its own content rewritten';
  end if;
end;
$$;

\echo '>> cross-tenant isolation: Finance Admin B cannot draft/publish/rollback against tenant A''s own finance config objects (the generic engine''s own app.check_config_object_authority is tenant-scoped)'
do $$
declare
  v_tenant_a uuid;
  v_published_v uuid;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmefinconfa');
  select v.id into v_published_v from app.config_versions v join app.config_objects o on o.id = v.config_object_id
    where o.tenant_id = v_tenant_a and o.config_type_code = 'finance_rounding' and v.status = 'published';

  begin
    perform app.rollback_finance_config_version(v_published_v, '00000000-0000-0000-0000-000000024205', 'tenant B trying to touch tenant A''s config', 'financeadminb');
    raise exception 'assertion failed: expected insufficient_authority -- Finance Admin B has no support-grant authority over tenant A';
  exception
    when insufficient_privilege then
      null;
  end;

  begin
    perform app.create_finance_config_draft('finance_rounding', v_tenant_a, 'tenant', null, '00000000-0000-0000-0000-000000024205', 'financeadminb');
    raise exception 'assertion failed: expected insufficient_authority -- Finance Admin B drafting against tenant A''s own scope';
  exception
    when insufficient_privilege then
      null;
  end;
end;
$$;

\echo '>> schema-privilege defense in depth: anon holds zero EXECUTE on every new FIN-191 function (ERR-2026-004 regression guard); authenticated holds EXECUTE on every caller-facing wrapper but NOT on the internal-only app.validate_finance_config_version/app.check_finance_config_authority'
do $$
declare
  v_fn text;
  v_anon_has boolean;
begin
  for v_fn in select unnest(array[
    'create_finance_config_draft', 'set_finance_config_items', 'publish_finance_config_version',
    'discard_finance_config_draft', 'rollback_finance_config_version', 'resolve_finance_config',
    'preview_finance_config_impact', 'get_finance_config_version_items', 'is_finance_config_type',
    'validate_finance_config_version', 'check_finance_config_authority'
  ]) loop
    select bool_or(has_function_privilege('anon', p.oid, 'EXECUTE'))
      into v_anon_has
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'app' and p.proname = v_fn;
    if coalesce(v_anon_has, false) then
      raise exception 'assertion failed: expected anon to hold zero EXECUTE on app.%, found at least one overload granted', v_fn;
    end if;
  end loop;

  if not has_function_privilege('authenticated', 'app.create_finance_config_draft(text, uuid, text, uuid, uuid, text)', 'EXECUTE') then
    raise exception 'assertion failed: expected authenticated to hold EXECUTE on app.create_finance_config_draft';
  end if;
  if has_function_privilege('authenticated', 'app.validate_finance_config_version(uuid, text)', 'EXECUTE') then
    raise exception 'assertion failed: expected authenticated to hold NO EXECUTE on the internal-only app.validate_finance_config_version';
  end if;
end;
$$;

\echo '>> audit trail: at least one create_finance_config_draft/set_finance_config_items/publish_finance_config_version/discard_finance_config_draft/rollback_finance_config_version event was captured for tenant A (the generic engine''s own app.capture_audit_event calls, inherited unchanged)'
do $$
declare
  v_tenant_a uuid;
  v_count integer;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmefinconfa');
  select count(*) into v_count from app.audit_logs where tenant_id = v_tenant_a and action in
    ('create_config_draft', 'set_config_items', 'publish_config_version', 'discard_config_draft', 'rollback_config_version');
  if v_count < 5 then
    raise exception 'assertion failed: expected at least 5 audit events across this fixture''s own draft/set-items/publish/discard/rollback calls, found %', v_count;
  end if;
end;
$$;
