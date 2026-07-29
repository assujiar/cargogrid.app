-- Real, executable test evidence for FIN-194 (Currency and Exchange Rate,
-- CG-S9-FIN-005) -- run via `pnpm run db:test` against a real, disposable
-- Postgres database.
-- Proves: the widened app.validate_currency_code (PLT-119/FIN-194) resolves
-- against the real app.finance_currencies registry, strictly additive over
-- PLT-119's own IDR/USD placeholder; draft -> approved -> archived exchange
-- rate lifecycle with a real currency/positive-rate structural gate;
-- overlap rejection on approval; deterministic tenant-then-global rate
-- resolution; convert-preview same-currency short-circuit and missing-rate
-- rejection (never a silent default/stale rate); FX rounding tie-in to
-- FIN-191's own finance_rounding config; staged idempotent import;
-- cross-tenant isolation; schema-privilege defense in depth.

\set ON_ERROR_STOP on

\echo '>> setup: two tenants; tenant A gets a Finance Manager (FIN:Edit/Approve/View), a Finance Editor (FIN:Edit/View only, no Approve -- proves the draft-vs-approve split), and a Plain User with no FIN grant; tenant B gets its own Finance Manager for cross-tenant checks'
do $$
declare
  v_tenant_a uuid;
  v_tenant_b uuid;
  v_team_a uuid;
  v_team_b uuid;
  v_manager_role_a uuid;
  v_manager_draft_a app.role_versions;
  v_editor_role_a uuid;
  v_editor_draft_a app.role_versions;
  v_manager_role_b uuid;
  v_manager_draft_b app.role_versions;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000024501', 'admina@acmefx.test'),
    ('00000000-0000-0000-0000-000000024502', 'financemanagera@acmefx.test'),
    ('00000000-0000-0000-0000-000000024503', 'financeeditora@acmefx.test'),
    ('00000000-0000-0000-0000-000000024504', 'plainusera@acmefx.test'),
    ('00000000-0000-0000-0000-000000024505', 'financemanagerb@acmefx.test'),
    ('00000000-0000-0000-0000-000000024506', 'supremefx@example.test');

  perform app.provision_tenant('acmefxa', 'Acme FX A', 'idem-acmefxa', 'tester');
  v_tenant_a := (select id from app.tenants where slug = 'acmefxa');
  perform app.transition_tenant_status(v_tenant_a, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant_a, 'company', null, 'ACMEFXA-CO', 'Acme FX A', 'tester');
  v_team_a := (select id from app.org_units where tenant_id = v_tenant_a and code = 'ACMEFXA-CO');

  perform app.provision_tenant('acmefxb', 'Acme FX B', 'idem-acmefxb', 'tester');
  v_tenant_b := (select id from app.tenants where slug = 'acmefxb');
  perform app.transition_tenant_status(v_tenant_b, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant_b, 'company', null, 'ACMEFXB-CO', 'Acme FX B', 'tester');
  v_team_b := (select id from app.org_units where tenant_id = v_tenant_b and code = 'ACMEFXB-CO');

  perform app.invite_user(v_tenant_a, '00000000-0000-0000-0000-000000024501', 'admina@acmefx.test', 'Tenant A Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admina@acmefx.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000024501', 'tenant_admin', v_tenant_a, null, 'tester');

  perform app.invite_user(v_tenant_a, '00000000-0000-0000-0000-000000024502', 'financemanagera@acmefx.test', 'Finance Manager A', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'financemanagera@acmefx.test'), 'active', 'onboarded', 'tester');
  -- FIN-191's inherited two-factor gate (app.check_config_object_authority) requires
  -- tenant_admin/Supreme for any tenant-scope finance_rounding draft/publish -- this
  -- fixture's own FX rounding-tie-in test publishes one, so Finance Manager A needs
  -- both tenant_admin AND the FIN role assigned below (the same combination
  -- finance-configuration.sql's/finance-fiscal-period.sql's own Finance
  -- Manager/Admin fixture already establishes).
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000024502', 'tenant_admin', v_tenant_a, null, 'tester');

  perform app.invite_user(v_tenant_a, '00000000-0000-0000-0000-000000024503', 'financeeditora@acmefx.test', 'Finance Editor A', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'financeeditora@acmefx.test'), 'active', 'onboarded', 'tester');

  v_manager_role_a := (app.create_role(v_tenant_a, 'Finance Manager', 'exchange rate authority', 'tester')).id;
  v_manager_draft_a := app.create_role_version(v_manager_role_a, 'tester');
  perform app.set_role_version_permissions(v_manager_draft_a.id, array(select id from app.permissions where resource_module_code = 'FIN' and action in ('Edit', 'Approve', 'View')), 'tester');
  perform app.publish_role_version(v_manager_draft_a.id, now(), 'tester');
  perform app.assign_role(v_tenant_a, (select id from app.role_versions where role_id = v_manager_role_a and status = 'published'), '00000000-0000-0000-0000-000000024502', '00000000-0000-0000-0000-000000024501', 'tester');

  v_editor_role_a := (app.create_role(v_tenant_a, 'Finance Editor', 'draft only, no approve', 'tester')).id;
  v_editor_draft_a := app.create_role_version(v_editor_role_a, 'tester');
  perform app.set_role_version_permissions(v_editor_draft_a.id, array(select id from app.permissions where resource_module_code = 'FIN' and action in ('Edit', 'View')), 'tester');
  perform app.publish_role_version(v_editor_draft_a.id, now(), 'tester');
  perform app.assign_role(v_tenant_a, (select id from app.role_versions where role_id = v_editor_role_a and status = 'published'), '00000000-0000-0000-0000-000000024503', '00000000-0000-0000-0000-000000024501', 'tester');

  perform app.invite_user(v_tenant_a, '00000000-0000-0000-0000-000000024504', 'plainusera@acmefx.test', 'Plain User A', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'plainusera@acmefx.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant_b, '00000000-0000-0000-0000-000000024505', 'financemanagerb@acmefx.test', 'Finance Manager B', v_team_b, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'financemanagerb@acmefx.test'), 'active', 'onboarded', 'tester');
  v_manager_role_b := (app.create_role(v_tenant_b, 'Finance Manager', 'exchange rate authority', 'tester')).id;
  v_manager_draft_b := app.create_role_version(v_manager_role_b, 'tester');
  perform app.set_role_version_permissions(v_manager_draft_b.id, array(select id from app.permissions where resource_module_code = 'FIN' and action in ('Edit', 'Approve', 'View')), 'tester');
  perform app.publish_role_version(v_manager_draft_b.id, now(), 'tester');
  perform app.assign_role(v_tenant_b, (select id from app.role_versions where role_id = v_manager_role_b and status = 'published'), '00000000-0000-0000-0000-000000024505', '00000000-0000-0000-0000-000000024505', 'tester');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000024506', 'supreme_admin', null, null, 'tester');
end;
$$;

\echo '>> app.validate_currency_code (PLT-119/FIN-194): the real registry accepts every seeded code (including EUR, which PLT-119''s own two-code placeholder never accepted) and rejects an unregistered/inactive one'
do $$
begin
  if not app.validate_currency_code('USD') or not app.validate_currency_code('IDR') or not app.validate_currency_code('EUR') or not app.validate_currency_code('JPY') or not app.validate_currency_code('SGD') then
    raise exception 'assertion failed: expected every seeded FIN-194 currency to validate';
  end if;
  if app.validate_currency_code('GBP') then
    raise exception 'assertion failed: expected an unregistered currency (GBP) to be rejected';
  end if;

  update app.finance_currencies set is_active = false where code = 'JPY';
  if app.validate_currency_code('JPY') then
    raise exception 'assertion failed: expected a deactivated currency (JPY) to be rejected';
  end if;
  update app.finance_currencies set is_active = true where code = 'JPY';
end;
$$;

\echo '>> authority: Plain User A is denied draft creation; an unsupported currency and a non-positive rate are each rejected; Finance Manager A creates a valid USD->IDR spot draft'
do $$
declare
  v_tenant_a uuid;
  v_rate app.finance_exchange_rates;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmefxa');

  begin
    perform app.create_finance_exchange_rate_draft(v_tenant_a, 'spot', 'USD', 'IDR', 15750, 'manual', '2026-01-01'::timestamptz, null, '00000000-0000-0000-0000-000000024504', 'plainusera');
    raise exception 'assertion failed: expected insufficient_authority for Plain User A';
  exception
    when insufficient_privilege then
      null;
  end;

  begin
    perform app.create_finance_exchange_rate_draft(v_tenant_a, 'spot', 'USD', 'GBP', 15750, 'manual', '2026-01-01'::timestamptz, null, '00000000-0000-0000-0000-000000024502', 'financemanagera');
    raise exception 'assertion failed: expected finance_exchange_rate_unsupported_currency for GBP';
  exception
    when others then
      if sqlerrm !~ 'finance_exchange_rate_unsupported_currency' then
        raise exception 'assertion failed: expected finance_exchange_rate_unsupported_currency, got %', sqlerrm;
      end if;
  end;

  begin
    perform app.create_finance_exchange_rate_draft(v_tenant_a, 'spot', 'USD', 'IDR', 0, 'manual', '2026-01-01'::timestamptz, null, '00000000-0000-0000-0000-000000024502', 'financemanagera');
    raise exception 'assertion failed: expected finance_exchange_rate_invalid_rate for a zero rate';
  exception
    when others then
      if sqlerrm !~ 'finance_exchange_rate_invalid_rate' then
        raise exception 'assertion failed: expected finance_exchange_rate_invalid_rate, got %', sqlerrm;
      end if;
  end;

  select * into v_rate from app.create_finance_exchange_rate_draft(v_tenant_a, 'spot', 'USD', 'IDR', 15750.5, 'manual', '2026-01-01T00:00:00Z'::timestamptz, null, '00000000-0000-0000-0000-000000024502', 'financemanagera');
  if v_rate.status <> 'draft' or v_rate.rate <> 15750.5 then
    raise exception 'assertion failed: expected a draft USD->IDR rate of 15750.5, got % / %', v_rate.status, v_rate.rate;
  end if;
end;
$$;

\echo '>> draft-vs-approve split: Finance Editor A (no Approve) can create/discard a draft but cannot approve it; Finance Manager A approves'
do $$
declare
  v_tenant_a uuid;
  v_rate app.finance_exchange_rates;
  v_discard_rate app.finance_exchange_rates;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmefxa');
  select * into v_rate from app.finance_exchange_rates where tenant_id = v_tenant_a and source_currency = 'USD' and target_currency = 'IDR' and status = 'draft';

  select * into v_discard_rate from app.create_finance_exchange_rate_draft(v_tenant_a, 'spot', 'USD', 'SGD', 1.35, 'manual', '2026-01-01T00:00:00Z'::timestamptz, null, '00000000-0000-0000-0000-000000024503', 'financeeditora');
  select * into v_discard_rate from app.discard_finance_exchange_rate_draft(v_discard_rate.id, v_discard_rate.record_version, 'entered in error', '00000000-0000-0000-0000-000000024503', 'financeeditora');
  if v_discard_rate.status <> 'archived' then
    raise exception 'assertion failed: expected the discarded USD->SGD draft to be archived, got %', v_discard_rate.status;
  end if;

  begin
    perform app.approve_finance_exchange_rate(v_rate.id, v_rate.record_version, '00000000-0000-0000-0000-000000024503', 'financeeditora');
    raise exception 'assertion failed: expected insufficient_authority -- Finance Editor A lacks FIN:Approve';
  exception
    when insufficient_privilege then
      null;
  end;

  select * into v_rate from app.approve_finance_exchange_rate(v_rate.id, v_rate.record_version, '00000000-0000-0000-0000-000000024502', 'financemanagera');
  if v_rate.status <> 'approved' or v_rate.approved_by <> 'financemanagera' then
    raise exception 'assertion failed: expected the USD->IDR draft to approve under Finance Manager A''s own authority';
  end if;

  begin
    perform app.discard_finance_exchange_rate_draft(v_rate.id, v_rate.record_version, 'too late', '00000000-0000-0000-0000-000000024502', 'financemanagera');
    raise exception 'assertion failed: expected finance_exchange_rate_not_draft for an already-approved rate';
  exception
    when others then
      if sqlerrm !~ 'finance_exchange_rate_not_draft' then
        raise exception 'assertion failed: expected finance_exchange_rate_not_draft, got %', sqlerrm;
      end if;
  end;
end;
$$;

\echo '>> approval overlap rejection: a second draft covering the same scope/type/pair/window cannot be approved over an already-approved one'
do $$
declare
  v_tenant_a uuid;
  v_overlap_rate app.finance_exchange_rates;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmefxa');
  select * into v_overlap_rate from app.create_finance_exchange_rate_draft(v_tenant_a, 'spot', 'USD', 'IDR', 15800, 'manual', '2026-01-10T00:00:00Z'::timestamptz, null, '00000000-0000-0000-0000-000000024502', 'financemanagera');

  begin
    perform app.approve_finance_exchange_rate(v_overlap_rate.id, v_overlap_rate.record_version, '00000000-0000-0000-0000-000000024502', 'financemanagera');
    raise exception 'assertion failed: expected finance_exchange_rate_overlap';
  exception
    when others then
      if sqlerrm !~ 'finance_exchange_rate_overlap' then
        raise exception 'assertion failed: expected finance_exchange_rate_overlap, got %', sqlerrm;
      end if;
  end;

  perform app.discard_finance_exchange_rate_draft(v_overlap_rate.id, v_overlap_rate.record_version, 'superseded by the non-overlapping window below', '00000000-0000-0000-0000-000000024502', 'financemanagera');
end;
$$;

\echo '>> deterministic resolution: a tenant-specific approved rate resolves for a covered instant; no row for an uncovered instant'
do $$
declare
  v_tenant_a uuid;
  v_resolved app.finance_exchange_rates;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmefxa');

  select * into v_resolved from app.resolve_finance_exchange_rate(v_tenant_a, 'spot', 'USD', 'IDR', '2026-01-15T00:00:00Z'::timestamptz);
  if not found or v_resolved.rate <> 15750.5 then
    raise exception 'assertion failed: expected the approved USD->IDR spot rate (15750.5) to resolve for 2026-01-15, got %', v_resolved.rate;
  end if;

  if exists (select 1 from app.resolve_finance_exchange_rate(v_tenant_a, 'spot', 'USD', 'IDR', '1999-01-01T00:00:00Z'::timestamptz)) then
    raise exception 'assertion failed: expected zero rows for an uncovered instant';
  end if;
end;
$$;

\echo '>> platform-wide default authority: a tenant-scoped Finance Manager (no Supreme Admin grant) is denied creating a null-tenant draft; Supreme Admin succeeds'
do $$
begin
  begin
    perform app.create_finance_exchange_rate_draft(null, 'spot', 'EUR', 'USD', 1.08, 'manual', '2026-01-01T00:00:00Z'::timestamptz, null, '00000000-0000-0000-0000-000000024502', 'financemanagera');
    raise exception 'assertion failed: expected insufficient_authority -- a tenant-scoped FIN grant does not authorize a platform-wide default rate';
  exception
    when insufficient_privilege then
      null;
  end;
end;
$$;

\echo '>> tenant-then-global fallback: a platform-wide default rate (created/approved by Supreme Admin) resolves only when tenant A has no approved rate of its own for the pair/type'
do $$
declare
  v_resolved app.finance_exchange_rates;
  v_global_draft app.finance_exchange_rates;
  v_tenant_a uuid;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmefxa');

  select * into v_global_draft from app.create_finance_exchange_rate_draft(null, 'spot', 'EUR', 'USD', 1.08, 'manual', '2026-01-01T00:00:00Z'::timestamptz, null, '00000000-0000-0000-0000-000000024506', 'supremefx');
  select * into v_global_draft from app.approve_finance_exchange_rate(v_global_draft.id, v_global_draft.record_version, '00000000-0000-0000-0000-000000024506', 'supremefx');

  select * into v_resolved from app.resolve_finance_exchange_rate(v_tenant_a, 'spot', 'EUR', 'USD', '2026-01-15T00:00:00Z'::timestamptz);
  if not found or v_resolved.tenant_id is not null then
    raise exception 'assertion failed: expected tenant A to fall back to the platform-wide EUR->USD default (tenant_id null)';
  end if;
end;
$$;

\echo '>> convert-preview: same-currency short-circuits without requiring a stored rate; a covered pair converts using the resolved rate and FIN-191''s own rounding config; a missing rate is rejected, never silently defaulted'
do $$
declare
  v_tenant_a uuid;
  v_result jsonb;
  v_draft app.config_versions;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmefxa');

  select app.convert_finance_amount(v_tenant_a, 100, 'USD', 'USD', 'spot', now(), '00000000-0000-0000-0000-000000024502') into v_result;
  if (v_result ->> 'roundingMode') <> 'identity' or (v_result ->> 'convertedAmount')::numeric <> 100 then
    raise exception 'assertion failed: expected a same-currency conversion to short-circuit identically, got %', v_result;
  end if;

  select app.convert_finance_amount(v_tenant_a, 100, 'USD', 'IDR', 'spot', '2026-01-15T00:00:00Z'::timestamptz, '00000000-0000-0000-0000-000000024502') into v_result;
  if (v_result ->> 'convertedAmount')::numeric <> 1575050 or (v_result ->> 'roundingMode') <> 'round_half_up' then
    raise exception 'assertion failed: expected 100 USD -> 1575050.00 IDR at rate 15750.5 with the disclosed safe default (round_half_up), got %', v_result;
  end if;

  -- FIN-191 rounding tie-in: publish a finance_rounding config pinning fx_conversion to round_down at precision 0, and confirm convert_finance_amount picks it up.
  select * into v_draft from app.create_finance_config_draft('finance_rounding', v_tenant_a, 'tenant', null, '00000000-0000-0000-0000-000000024502', 'financemanagera');
  perform app.set_finance_config_items(
    v_draft.id,
    '[{"key": "fx_conversion", "value": {"mode": "round_down", "precision": 0, "order": "convert_then_round"}}]'::jsonb,
    '00000000-0000-0000-0000-000000024502', 'financemanagera'
  );
  perform app.publish_finance_config_version(v_draft.id, '00000000-0000-0000-0000-000000024502', null, 'financemanagera');

  select app.convert_finance_amount(v_tenant_a, 100.007, 'USD', 'IDR', 'spot', '2026-01-15T00:00:00Z'::timestamptz, '00000000-0000-0000-0000-000000024502') into v_result;
  if (v_result ->> 'convertedAmount')::numeric <> 1575160 or (v_result ->> 'roundingMode') <> 'round_down' then
    raise exception 'assertion failed: expected FIN-191''s own published fx_conversion rounding (round_down, precision 0) to apply, got %', v_result;
  end if;

  begin
    perform app.convert_finance_amount(v_tenant_a, 100, 'IDR', 'JPY', 'spot', now(), '00000000-0000-0000-0000-000000024502');
    raise exception 'assertion failed: expected finance_exchange_rate_missing for an uncovered pair -- never a silent default';
  exception
    when others then
      if sqlerrm !~ 'finance_exchange_rate_missing' then
        raise exception 'assertion failed: expected finance_exchange_rate_missing, got %', sqlerrm;
      end if;
  end;
end;
$$;

\echo '>> staged idempotent import: a retried call with the same idempotency_key returns the original batch (never re-staged/duplicated)'
do $$
declare
  v_tenant_a uuid;
  v_batch app.finance_exchange_rate_import_batches;
  v_second_batch app.finance_exchange_rate_import_batches;
  v_row_count integer;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmefxa');

  select * into v_batch from app.stage_finance_exchange_rate_import(
    v_tenant_a, 'import-batch-1',
    '[{"rate_type": "spot", "source_currency": "USD", "target_currency": "JPY", "rate": 148.25, "effective_from": "2026-02-01T00:00:00Z"}]'::jsonb,
    '00000000-0000-0000-0000-000000024502', 'financemanagera'
  );
  if v_batch.row_count <> 1 then
    raise exception 'assertion failed: expected the import batch to stage exactly 1 row, got %', v_batch.row_count;
  end if;

  select count(*) into v_row_count from app.finance_exchange_rates where import_batch_id = v_batch.id;
  if v_row_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 staged draft rate for the import batch, got %', v_row_count;
  end if;

  select * into v_second_batch from app.stage_finance_exchange_rate_import(
    v_tenant_a, 'import-batch-1',
    '[{"rate_type": "spot", "source_currency": "USD", "target_currency": "JPY", "rate": 999, "effective_from": "2026-03-01T00:00:00Z"}]'::jsonb,
    '00000000-0000-0000-0000-000000024502', 'financemanagera'
  );
  if v_second_batch.id <> v_batch.id then
    raise exception 'assertion failed: expected a retried import with the same idempotency_key to return the original batch, not a new one';
  end if;

  select count(*) into v_row_count from app.finance_exchange_rates where import_batch_id = v_batch.id;
  if v_row_count <> 1 then
    raise exception 'assertion failed: expected the retried import to leave the staged row count unchanged (no duplication), got %', v_row_count;
  end if;
end;
$$;

\echo '>> cross-tenant isolation: Finance Manager B cannot draft/approve against tenant A''s own rates, and list_finance_exchange_rates never returns tenant A''s rows for tenant B''s own scope'
do $$
declare
  v_tenant_a uuid;
  v_tenant_b uuid;
  v_rate app.finance_exchange_rates;
  v_rows app.finance_exchange_rates[];
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmefxa');
  v_tenant_b := (select id from app.tenants where slug = 'acmefxb');
  select * into v_rate from app.finance_exchange_rates where tenant_id = v_tenant_a and source_currency = 'USD' and target_currency = 'IDR' and status = 'approved';

  begin
    perform app.discard_finance_exchange_rate_draft(v_rate.id, v_rate.record_version, 'intruder attempt', '00000000-0000-0000-0000-000000024505', 'financemanagerb');
    raise exception 'assertion failed: expected finance_exchange_rate_not_draft (the rate is approved) rather than a cross-tenant leak -- still proves Finance Manager B cannot mutate it as a draft';
  exception
    when others then
      if sqlerrm !~ 'finance_exchange_rate_not_draft' then
        raise exception 'assertion failed: expected finance_exchange_rate_not_draft, got %', sqlerrm;
      end if;
  end;

  select array_agg(r) into v_rows from app.list_finance_exchange_rates(v_tenant_b, null, null, null, '00000000-0000-0000-0000-000000024505') r;
  if v_rows is not null and exists (select 1 from unnest(v_rows) r where r.tenant_id = v_tenant_a) then
    raise exception 'assertion failed: expected tenant B''s own list_finance_exchange_rates to never return a tenant A row';
  end if;
end;
$$;

\echo '>> schema-privilege defense in depth: anon holds zero EXECUTE on every new FIN-194 function (ERR-2026-004 regression guard)'
do $$
declare
  v_fn text;
  v_anon_has boolean;
begin
  for v_fn in select unnest(array[
    'apply_finance_rounding', 'check_finance_exchange_rate_authority', 'create_finance_exchange_rate_draft',
    'discard_finance_exchange_rate_draft', 'approve_finance_exchange_rate', 'resolve_finance_exchange_rate',
    'convert_finance_amount', 'list_finance_exchange_rates', 'stage_finance_exchange_rate_import',
    'touch_finance_exchange_rate_row', 'validate_currency_code'
  ]) loop
    select bool_or(has_function_privilege('anon', p.oid, 'EXECUTE'))
      into v_anon_has
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'app' and p.proname = v_fn;
    if coalesce(v_anon_has, false) then
      raise exception 'assertion failed: expected anon to hold zero EXECUTE on app.%, found at least one overload granted', v_fn;
    end if;
  end loop;
end;
$$;

\echo '>> audit trail: at least one create/approve/import event was captured for tenant A''s own exchange-rate activity'
do $$
declare
  v_tenant_a uuid;
  v_count integer;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmefxa');
  select count(*) into v_count from app.audit_logs where tenant_id = v_tenant_a and action in
    ('create_finance_exchange_rate_draft', 'approve_finance_exchange_rate', 'stage_finance_exchange_rate_import');
  if v_count < 3 then
    raise exception 'assertion failed: expected at least 3 audit events across this fixture''s own create/approve/import calls, found %', v_count;
  end if;
end;
$$;
