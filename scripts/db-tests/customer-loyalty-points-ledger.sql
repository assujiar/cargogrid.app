-- Real, executable test evidence for CPL-318 (CG-S13-CPL-020, Prompt 318,
-- "Points Ledger") -- run via `pnpm run db:test` against a real, disposable
-- Postgres database. The THIRD Loyalty-domain db-test in this repository.
--
-- UUID range 00000000-0000-0000-0000-0000003400xx (tenant pts1) /
-- 00000000-0000-0000-0000-0000003410xx (tenant pts2), grep-verified
-- unclaimed against every other file in this directory before writing this
-- fixture.
--
-- Covers, live: (a) duplicate earning-event replay is a safe no-op
-- (idempotency); (b) negative-balance prevention under a real attempted
-- over-consumption AND a real two-process concurrent-race attempt (reusing
-- scripts/db-tests/wms-picking-concurrency-helper.sh); (c) FIFO-by-expiry
-- lot consumption ordering; (d) self-approval blocked on the point-
-- adjustment maker-checker, live (not TS-mocked); (e) a reversal creates a
-- new linked entry, never deleting or mutating the original; (f) cross-
-- tenant/cross-account isolation; (g) customer ledger history never leaks
-- another customer's data or an internal investigation note; plus lot
-- expiry (including idempotent re-run), insufficient_lot_remaining, LYL:*
-- authority boundaries, raw-table RLS / raw-function-grant defense in
-- depth, the actor-identity session cross-check on every new RPC, and
-- keyset pagination (both descending staff-list and ascending expiry-
-- schedule conventions).

\set ON_ERROR_STOP on

\echo '>> setup: tenant pts1 (org unit, roles: Loyalty Manager A/B [both full LYL], Loyalty Viewer [LYL View only], Plain User [no LYL grant]; customer accounts Alpha/Beta/Gamma, customer_user identities for Alpha/Beta; an impersonator identity), tenant pts2 (its own Loyalty Manager, customer account Delta); a shared points-reward loyalty program, published rule version (rate=1 point per $1), Alpha/Beta/Gamma/Delta all enrolled'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_company1 uuid;
  v_company2 uuid;
  v_account_alpha uuid;
  v_account_beta uuid;
  v_account_gamma uuid;
  v_account_delta uuid;
  v_manager1a uuid := '00000000-0000-0000-0000-000000340001';
  v_manager1b uuid := '00000000-0000-0000-0000-000000340002';
  v_viewer1 uuid := '00000000-0000-0000-0000-000000340003';
  v_plain1 uuid := '00000000-0000-0000-0000-000000340004';
  v_impersonator uuid := '00000000-0000-0000-0000-000000340050';
  v_customer_alpha uuid := '00000000-0000-0000-0000-000000340010';
  v_customer_beta uuid := '00000000-0000-0000-0000-000000340020';
  v_manager2 uuid := '00000000-0000-0000-0000-000000341001';
  v_customer_delta uuid := '00000000-0000-0000-0000-000000341010';
  v_manager_role1a uuid;
  v_manager_draft1a app.role_versions;
  v_manager_role1b uuid;
  v_manager_draft1b app.role_versions;
  v_viewer_role1 uuid;
  v_viewer_draft1 app.role_versions;
  v_manager_role2 uuid;
  v_manager_draft2 app.role_versions;
  v_program_id uuid;
  v_program2_id uuid;
  v_rule_version_id uuid;
begin
  insert into auth.users (id, email) values
    (v_manager1a, 'manager1a@pts1.test'),
    (v_manager1b, 'manager1b@pts1.test'),
    (v_viewer1, 'viewer1@pts1.test'),
    (v_plain1, 'plain1@pts1.test'),
    (v_impersonator, 'impersonator@pts1.test'),
    (v_customer_alpha, 'customer-alpha@pts1.test'),
    (v_customer_beta, 'customer-beta@pts1.test'),
    (v_manager2, 'manager2@pts2.test'),
    (v_customer_delta, 'customer-delta@pts2.test');

  perform app.provision_tenant('pts1', 'Points Ledger Test Tenant One', 'idem-pts1', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'pts1');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant1, 'company', null, 'PTS1-CO', 'Pts1 Co', 'tester');
  v_company1 := (select id from app.org_units where tenant_id = v_tenant1 and code = 'PTS1-CO');

  perform app.provision_tenant('pts2', 'Points Ledger Test Tenant Two', 'idem-pts2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'pts2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant2, 'company', null, 'PTS2-CO', 'Pts2 Co', 'tester');
  v_company2 := (select id from app.org_units where tenant_id = v_tenant2 and code = 'PTS2-CO');

  perform app.invite_user(v_tenant1, v_manager1a, 'manager1a@pts1.test', 'Pts1 Manager A', v_company1, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'manager1a@pts1.test'), 'active', 'onboarded', 'tester');
  v_manager_role1a := (app.create_role(v_tenant1, 'Loyalty Manager A', 'full LYL authority', 'tester')).id;
  v_manager_draft1a := app.create_role_version(v_manager_role1a, 'tester');
  perform app.set_role_version_permissions(v_manager_draft1a.id, array(select id from app.permissions where resource_module_code = 'LYL' and action in ('View', 'Create', 'Edit', 'Configure')), 'tester');
  perform app.publish_role_version(v_manager_draft1a.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_manager_role1a and status = 'published'), v_manager1a, v_manager1a, 'tester');

  -- A SECOND, independent full-LYL manager -- required for the maker-checker
  -- self-approval-blocked test to have a genuinely different, real DECIDING
  -- actor distinct from the REQUESTING actor.
  perform app.invite_user(v_tenant1, v_manager1b, 'manager1b@pts1.test', 'Pts1 Manager B', v_company1, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'manager1b@pts1.test'), 'active', 'onboarded', 'tester');
  v_manager_role1b := (app.create_role(v_tenant1, 'Loyalty Manager B', 'full LYL authority', 'tester')).id;
  v_manager_draft1b := app.create_role_version(v_manager_role1b, 'tester');
  perform app.set_role_version_permissions(v_manager_draft1b.id, array(select id from app.permissions where resource_module_code = 'LYL' and action in ('View', 'Create', 'Edit', 'Configure')), 'tester');
  perform app.publish_role_version(v_manager_draft1b.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_manager_role1b and status = 'published'), v_manager1b, v_manager1a, 'tester');

  perform app.invite_user(v_tenant1, v_viewer1, 'viewer1@pts1.test', 'Pts1 Viewer', v_company1, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'viewer1@pts1.test'), 'active', 'onboarded', 'tester');
  v_viewer_role1 := (app.create_role(v_tenant1, 'Loyalty Viewer', 'LYL:View only, never Configure/Create/Edit', 'tester')).id;
  v_viewer_draft1 := app.create_role_version(v_viewer_role1, 'tester');
  perform app.set_role_version_permissions(v_viewer_draft1.id, array(select id from app.permissions where resource_module_code = 'LYL' and action = 'View'), 'tester');
  perform app.publish_role_version(v_viewer_draft1.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_viewer_role1 and status = 'published'), v_viewer1, v_manager1a, 'tester');

  perform app.invite_user(v_tenant1, v_plain1, 'plain1@pts1.test', 'Pts1 Plain User', v_company1, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'plain1@pts1.test'), 'active', 'onboarded', 'tester');

  -- impersonator: a real, active tenant1 identity holding Loyalty Manager A's
  -- role too, used ONLY for the actor-identity session cross-check (never for
  -- a legitimate call).
  perform app.invite_user(v_tenant1, v_impersonator, 'impersonator@pts1.test', 'Pts1 Impersonator', v_company1, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'impersonator@pts1.test'), 'active', 'onboarded', 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_manager_role1a and status = 'published'), v_impersonator, v_manager1a, 'tester');

  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant1, 'Pts Account Alpha', 'pts-alpha-fp', '{}'::jsonb, v_company1, 'tester') returning id into v_account_alpha;
  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant1, 'Pts Account Beta', 'pts-beta-fp', '{}'::jsonb, v_company1, 'tester') returning id into v_account_beta;
  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant1, 'Pts Account Gamma', 'pts-gamma-fp', '{}'::jsonb, v_company1, 'tester') returning id into v_account_gamma;
  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, org_unit_id, created_by)
  values (v_tenant2, 'Pts Account Delta', 'pts-delta-fp', '{}'::jsonb, v_company2, 'tester') returning id into v_account_delta;

  perform app.invite_user(v_tenant1, v_customer_alpha, 'customer-alpha@pts1.test', 'Pts Customer Alpha', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'customer-alpha@pts1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(v_customer_alpha, 'customer_user', v_tenant1, v_account_alpha::text, 'tester');

  perform app.invite_user(v_tenant1, v_customer_beta, 'customer-beta@pts1.test', 'Pts Customer Beta', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'customer-beta@pts1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(v_customer_beta, 'customer_user', v_tenant1, v_account_beta::text, 'tester');

  perform app.invite_user(v_tenant2, v_manager2, 'manager2@pts2.test', 'Pts2 Manager', v_company2, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'manager2@pts2.test'), 'active', 'onboarded', 'tester');
  v_manager_role2 := (app.create_role(v_tenant2, 'Loyalty Manager', 'full LYL authority', 'tester')).id;
  v_manager_draft2 := app.create_role_version(v_manager_role2, 'tester');
  perform app.set_role_version_permissions(v_manager_draft2.id, array(select id from app.permissions where resource_module_code = 'LYL' and action in ('View', 'Create', 'Edit', 'Configure')), 'tester');
  perform app.publish_role_version(v_manager_draft2.id, now(), 'tester');
  perform app.assign_role(v_tenant2, (select id from app.role_versions where role_id = v_manager_role2 and status = 'published'), v_manager2, v_manager2, 'tester');

  perform app.invite_user(v_tenant2, v_customer_delta, 'customer-delta@pts2.test', 'Pts Customer Delta', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'customer-delta@pts2.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(v_customer_delta, 'customer_user', v_tenant2, v_account_delta::text, 'tester');

  -- CPL-316 program/rule-version/account scaffolding (this checkpoint's own
  -- direct upstream dependency -- reads app.loyalty_accounts/app.loyalty_
  -- earning_events, never writes them).
  perform app.create_loyalty_program(v_tenant1, 'Points Rewards', 'Earn points on every paid invoice.', v_manager1a, 'manager1a');
  v_program_id := (select id from app.loyalty_programs where tenant_id = v_tenant1 and name = 'Points Rewards');
  perform app.update_loyalty_program_status(v_tenant1, v_program_id, 1, 'active', v_manager1a, 'manager1a');
  perform app.create_loyalty_program_rule_version(v_tenant1, v_program_id, 'per_paid_invoice_amount', 'points', 1, '{}'::jsonb, v_manager1a, 'manager1a');
  v_rule_version_id := (select id from app.loyalty_program_rule_versions where program_id = v_program_id and status = 'draft');
  perform app.publish_loyalty_program_rule_version(v_tenant1, v_rule_version_id, 1, null, v_manager1a, 'manager1a');

  perform app.enroll_customer_loyalty_account(v_tenant1, v_account_alpha, v_program_id, v_manager1a, 'manager1a');
  perform app.enroll_customer_loyalty_account(v_tenant1, v_account_beta, v_program_id, v_manager1a, 'manager1a');
  perform app.enroll_customer_loyalty_account(v_tenant1, v_account_gamma, v_program_id, v_manager1a, 'manager1a');

  perform app.create_loyalty_program(v_tenant2, 'Points Rewards 2', null, v_manager2, 'manager2');
  v_program2_id := (select id from app.loyalty_programs where tenant_id = v_tenant2 and name = 'Points Rewards 2');
  perform app.update_loyalty_program_status(v_tenant2, v_program2_id, 1, 'active', v_manager2, 'manager2');
  perform app.create_loyalty_program_rule_version(v_tenant2, v_program2_id, 'per_paid_invoice_amount', 'points', 1, '{}'::jsonb, v_manager2, 'manager2');
  perform app.publish_loyalty_program_rule_version(v_tenant2, (select id from app.loyalty_program_rule_versions where program_id = v_program2_id and status = 'draft'), 1, null, v_manager2, 'manager2');
  perform app.enroll_customer_loyalty_account(v_tenant2, v_account_delta, v_program2_id, v_manager2, 'manager2');

  -- AR open items (direct fixture insert -- bypasses app.post_finance_ar_
  -- open_item/app.apply_finance_ar_allocation, neither under test here,
  -- mirroring CPL-316's own established precedent). Alpha: 340101 (100,
  -- feeds the idempotent-replay test), 340102/340103/340104 (100/80/50, feed
  -- the FIFO section, each converted with a DIFFERENT p_expiry_days so the
  -- resulting lots have genuinely staggered expires_at), 340105 (60, feeds
  -- the reversal section). Beta: 340111 (200, feeds the over-consumption and
  -- concurrent-race sections). Gamma: 340121 (500, feeds the adjustment
  -- maker-checker section -- adjustments are lot-less). Delta (tenant2):
  -- 341101 (90, cross-tenant isolation section).
  insert into app.finance_ar_open_items (id, tenant_id, customer_account_id, source_document_type, source_document_id, currency, original_amount, allocated_amount, status, is_held, invoice_date, due_date, created_by) values
    ('00000000-0000-0000-0000-000000340101', v_tenant1, v_account_alpha, 'invoice', '00000000-0000-0000-0000-000000340201', 'USD', 100, 100, 'paid', false, '2026-08-01', '2026-08-31', 'tester'),
    ('00000000-0000-0000-0000-000000340102', v_tenant1, v_account_alpha, 'invoice', '00000000-0000-0000-0000-000000340202', 'USD', 100, 100, 'paid', false, '2026-08-02', '2026-09-01', 'tester'),
    ('00000000-0000-0000-0000-000000340103', v_tenant1, v_account_alpha, 'invoice', '00000000-0000-0000-0000-000000340203', 'USD', 80, 80, 'paid', false, '2026-08-03', '2026-09-02', 'tester'),
    ('00000000-0000-0000-0000-000000340104', v_tenant1, v_account_alpha, 'invoice', '00000000-0000-0000-0000-000000340204', 'USD', 50, 50, 'paid', false, '2026-08-04', '2026-09-03', 'tester'),
    ('00000000-0000-0000-0000-000000340105', v_tenant1, v_account_alpha, 'invoice', '00000000-0000-0000-0000-000000340205', 'USD', 60, 60, 'paid', false, '2026-08-05', '2026-09-04', 'tester'),
    ('00000000-0000-0000-0000-000000340111', v_tenant1, v_account_beta, 'invoice', '00000000-0000-0000-0000-000000340211', 'USD', 200, 200, 'paid', false, '2026-08-01', '2026-08-31', 'tester'),
    ('00000000-0000-0000-0000-000000340121', v_tenant1, v_account_gamma, 'invoice', '00000000-0000-0000-0000-000000340221', 'USD', 500, 500, 'paid', false, '2026-08-01', '2026-08-31', 'tester');
  insert into app.finance_ar_open_items (id, tenant_id, customer_account_id, source_document_type, source_document_id, currency, original_amount, allocated_amount, status, is_held, invoice_date, due_date, created_by) values
    ('00000000-0000-0000-0000-000000341101', v_tenant2, v_account_delta, 'invoice', '00000000-0000-0000-0000-000000341201', 'USD', 90, 90, 'paid', false, '2026-08-01', '2026-08-31', 'tester');

  perform app.evaluate_customer_loyalty_earning_for_paid_invoice(v_tenant1, '00000000-0000-0000-0000-000000340101', v_manager1a, 'manager1a');
  perform app.evaluate_customer_loyalty_earning_for_paid_invoice(v_tenant1, '00000000-0000-0000-0000-000000340102', v_manager1a, 'manager1a');
  perform app.evaluate_customer_loyalty_earning_for_paid_invoice(v_tenant1, '00000000-0000-0000-0000-000000340103', v_manager1a, 'manager1a');
  perform app.evaluate_customer_loyalty_earning_for_paid_invoice(v_tenant1, '00000000-0000-0000-0000-000000340104', v_manager1a, 'manager1a');
  perform app.evaluate_customer_loyalty_earning_for_paid_invoice(v_tenant1, '00000000-0000-0000-0000-000000340105', v_manager1a, 'manager1a');
  perform app.evaluate_customer_loyalty_earning_for_paid_invoice(v_tenant1, '00000000-0000-0000-0000-000000340111', v_manager1a, 'manager1a');
  perform app.evaluate_customer_loyalty_earning_for_paid_invoice(v_tenant1, '00000000-0000-0000-0000-000000340121', v_manager1a, 'manager1a');
  perform app.evaluate_customer_loyalty_earning_for_paid_invoice(v_tenant2, '00000000-0000-0000-0000-000000341101', v_manager2, 'manager2');
end $$;

\echo '>> app.post_loyalty_points_earned: creates a lot + earn entry; idempotent replay is a safe no-op (mandatory test a); rejects a non-points/reversal-shaped/nonexistent event; rejects an out-of-range expiry window; LYL:Edit required'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'pts1');
  v_manager1a uuid := '00000000-0000-0000-0000-000000340001';
  v_plain1 uuid := '00000000-0000-0000-0000-000000340004';
  v_event1 uuid := (select id from app.loyalty_earning_events where idempotency_key = 'ar-open-item:00000000-0000-0000-0000-000000340101');
  v_entry app.loyalty_point_ledger_entries;
  v_entry2 app.loyalty_point_ledger_entries;
  v_lot_count integer;
  v_entry_count integer;
begin
  v_entry := app.post_loyalty_points_earned(v_tenant1, v_event1, v_manager1a, 'manager1a', 365);
  if v_entry.event_type <> 'earn' or v_entry.amount <> 100 then
    raise exception 'assertion failed: expected an earn entry of amount 100, got %', v_entry;
  end if;

  select count(*) into v_lot_count from app.loyalty_point_lots where source_earning_event_id = v_event1;
  if v_lot_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 lot for event %, got %', v_event1, v_lot_count;
  end if;

  -- Duplicate replay (mandatory test a): calling this twice for the SAME
  -- earning event is a safe no-op -- identical entry id, no new lot, no new
  -- ledger row.
  v_entry2 := app.post_loyalty_points_earned(v_tenant1, v_event1, v_manager1a, 'manager1a', 365);
  if v_entry2.id <> v_entry.id then
    raise exception 'assertion failed: expected the identical entry id on replay, got % vs %', v_entry2.id, v_entry.id;
  end if;
  select count(*) into v_lot_count from app.loyalty_point_lots where source_earning_event_id = v_event1;
  select count(*) into v_entry_count from app.loyalty_point_ledger_entries where lot_id = (select id from app.loyalty_point_lots where source_earning_event_id = v_event1);
  if v_lot_count <> 1 or v_entry_count <> 1 then
    raise exception 'assertion failed: replay must not create a second lot or ledger entry, got lot_count=% entry_count=%', v_lot_count, v_entry_count;
  end if;

  begin
    perform app.post_loyalty_points_earned(v_tenant1, gen_random_uuid(), v_manager1a, 'manager1a', 365);
    raise exception 'assertion failed: expected loyalty_earning_event_not_found for a nonexistent event id';
  exception when others then if sqlerrm not like 'loyalty_earning_event_not_found%' then raise; end if;
  end;

  begin
    perform app.post_loyalty_points_earned(v_tenant1, v_event1, v_manager1a, 'manager1a', 0);
    raise exception 'assertion failed: expected invalid_expiry_days for 0 days';
  exception when others then if sqlerrm not like 'invalid_expiry_days%' then raise; end if;
  end;
  begin
    perform app.post_loyalty_points_earned(v_tenant1, v_event1, v_manager1a, 'manager1a', 3651);
    raise exception 'assertion failed: expected invalid_expiry_days for 3651 days';
  exception when others then if sqlerrm not like 'invalid_expiry_days%' then raise; end if;
  end;

  begin
    perform app.post_loyalty_points_earned(v_tenant1, v_event1, v_plain1, 'plain1', 365);
    raise exception 'assertion failed: expected insufficient_authority for Plain User (no LYL grant)';
  exception when others then if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;
end $$;

\echo '>> app.post_loyalty_points_earned: builds Alpha''s FIFO fixture (3 more lots, staggered expiry 10/20/30 days) and Beta/Gamma/Delta''s own lots'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'pts1');
  v_tenant2 uuid := (select id from app.tenants where slug = 'pts2');
  v_manager1a uuid := '00000000-0000-0000-0000-000000340001';
  v_manager2 uuid := '00000000-0000-0000-0000-000000341001';
  v_event2 uuid := (select id from app.loyalty_earning_events where idempotency_key = 'ar-open-item:00000000-0000-0000-0000-000000340102');
  v_event3 uuid := (select id from app.loyalty_earning_events where idempotency_key = 'ar-open-item:00000000-0000-0000-0000-000000340103');
  v_event4 uuid := (select id from app.loyalty_earning_events where idempotency_key = 'ar-open-item:00000000-0000-0000-0000-000000340104');
  v_event5 uuid := (select id from app.loyalty_earning_events where idempotency_key = 'ar-open-item:00000000-0000-0000-0000-000000340105');
  v_event_beta uuid := (select id from app.loyalty_earning_events where idempotency_key = 'ar-open-item:00000000-0000-0000-0000-000000340111');
  v_event_gamma uuid := (select id from app.loyalty_earning_events where idempotency_key = 'ar-open-item:00000000-0000-0000-0000-000000340121');
  v_event_delta uuid := (select id from app.loyalty_earning_events where idempotency_key = 'ar-open-item:00000000-0000-0000-0000-000000341101');
begin
  -- Alpha: event2 (amount 100, expires in 10d -- soonest), event3 (amount 80,
  -- expires in 20d), event4 (amount 50, expires in 30d -- latest). Consuming
  -- 150 should exhaust event2's lot (100) then take 50 of event3's lot (80),
  -- leaving event3 with 30 remaining and event4's lot fully untouched.
  perform app.post_loyalty_points_earned(v_tenant1, v_event2, v_manager1a, 'manager1a', 10);
  perform app.post_loyalty_points_earned(v_tenant1, v_event3, v_manager1a, 'manager1a', 20);
  perform app.post_loyalty_points_earned(v_tenant1, v_event4, v_manager1a, 'manager1a', 30);
  -- event5 (amount 60) feeds the reversal section -- default expiry, not part
  -- of the FIFO ordering fixture above.
  perform app.post_loyalty_points_earned(v_tenant1, v_event5, v_manager1a, 'manager1a', 365);
  perform app.post_loyalty_points_earned(v_tenant1, v_event_beta, v_manager1a, 'manager1a', 365);
  perform app.post_loyalty_points_earned(v_tenant1, v_event_gamma, v_manager1a, 'manager1a', 365);
  perform app.post_loyalty_points_earned(v_tenant2, v_event_delta, v_manager2, 'manager2', 365);
end $$;

\echo '>> app.get_loyalty_point_balance / app.list_loyalty_point_balances: Alpha''s aggregate balance reflects every lot posted so far (100+100+80+50+60 = 390 earned, 0 consumed); LYL:View required; keyset pagination visits every row exactly once at limit=1'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'pts1');
  v_manager1a uuid := '00000000-0000-0000-0000-000000340001';
  v_plain1 uuid := '00000000-0000-0000-0000-000000340004';
  v_loyalty_account_alpha uuid := (select id from app.loyalty_accounts where tenant_id = (select id from app.tenants where slug = 'pts1') and customer_account_id = (select id from app.accounts where tenant_id = (select id from app.tenants where slug = 'pts1') and legal_name = 'Pts Account Alpha'));
  v_balance app.loyalty_point_balances;
  v_cursor_updated_at timestamptz := null;
  v_cursor_id uuid := null;
  v_page app.loyalty_point_balances[];
  v_seen_ids uuid[] := array[]::uuid[];
  v_total_pages integer := 0;
  v_row app.loyalty_point_balances;
begin
  v_balance := app.get_loyalty_point_balance(v_tenant1, v_loyalty_account_alpha, v_manager1a);
  if v_balance.total_earned <> 390 or v_balance.total_consumed <> 0 or v_balance.available <> 390 then
    raise exception 'assertion failed: expected Alpha''s balance to be earned=390 consumed=0 available=390, got %', v_balance;
  end if;

  begin
    perform app.get_loyalty_point_balance(v_tenant1, v_loyalty_account_alpha, v_plain1);
    raise exception 'assertion failed: expected insufficient_authority for Plain User';
  exception when others then if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  loop
    v_page := array(select app.list_loyalty_point_balances(v_tenant1, v_manager1a, v_cursor_updated_at, v_cursor_id, 1));
    exit when array_length(v_page, 1) is null;
    foreach v_row in array v_page loop
      v_seen_ids := array_append(v_seen_ids, v_row.id);
      v_cursor_updated_at := v_row.updated_at;
      v_cursor_id := v_row.id;
    end loop;
    v_total_pages := v_total_pages + 1;
    if v_total_pages > 20 then
      raise exception 'assertion failed: keyset pagination did not terminate within 20 pages';
    end if;
  end loop;
  if array_length(v_seen_ids, 1) <> (select count(*) from app.loyalty_point_balances where tenant_id = v_tenant1)
     or array_length(v_seen_ids, 1) <> (select count(distinct x) from unnest(v_seen_ids) x) then
    raise exception 'assertion failed: keyset pagination must visit every balance row exactly once (no duplicates, no gaps), got % ids for % rows', array_length(v_seen_ids, 1), (select count(*) from app.loyalty_point_balances where tenant_id = v_tenant1);
  end if;
end $$;

\echo '>> app.get_loyalty_point_lot / app.list_loyalty_point_lots: staff can list Alpha''s own lots, filter by status; insufficient_lot_remaining is rejected by app.post_loyalty_point_ledger_entry when a caller targets a specific lot for more than it holds'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'pts1');
  v_manager1a uuid := '00000000-0000-0000-0000-000000340001';
  v_loyalty_account_alpha uuid := (select id from app.loyalty_accounts where tenant_id = (select id from app.tenants where slug = 'pts1') and customer_account_id = (select id from app.accounts where tenant_id = (select id from app.tenants where slug = 'pts1') and legal_name = 'Pts Account Alpha'));
  v_lot_count integer;
  v_target_lot app.loyalty_point_lots;
begin
  select count(*) into v_lot_count from app.list_loyalty_point_lots(v_tenant1, v_manager1a, v_loyalty_account_alpha, 'active', p_limit => 200);
  if v_lot_count <> 5 then
    raise exception 'assertion failed: expected 5 active lots for Alpha, got %', v_lot_count;
  end if;

  select * into v_target_lot from app.loyalty_point_lots where source_earning_event_id = (select id from app.loyalty_earning_events where idempotency_key = 'ar-open-item:00000000-0000-0000-0000-000000340105');
  if app.get_loyalty_point_lot(v_tenant1, v_target_lot.id, v_manager1a) is null then
    raise exception 'assertion failed: expected app.get_loyalty_point_lot to return the lot';
  end if;

  -- -70 is chosen deliberately: it is well WITHIN Alpha's own 390-point
  -- aggregate available balance (so the primitive's own balance-level check
  -- does not fire first) but EXCEEDS this specific lot's own 60-point
  -- remaining_amount -- isolating the LOT-level guard specifically.
  begin
    perform app.post_loyalty_point_ledger_entry(
      v_tenant1, v_loyalty_account_alpha, 'redemption', -70, v_target_lot.id,
      'redemption', gen_random_uuid(), 'test-over-lot-consume', null, null, v_manager1a, 'manager1a'
    );
    raise exception 'assertion failed: expected insufficient_lot_remaining for a request exceeding the lot''s own remaining_amount';
  exception when others then if sqlerrm not like 'insufficient_lot_remaining%' then raise; end if;
  end;
end $$;

\echo '>> app.reverse_loyalty_points_earned: a reversal creates a NEW linked entry, never deleting or mutating the original (mandatory test e)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'pts1');
  v_manager1a uuid := '00000000-0000-0000-0000-000000340001';
  v_plain1 uuid := '00000000-0000-0000-0000-000000340004';
  v_original_event uuid := (select id from app.loyalty_earning_events where idempotency_key = 'ar-open-item:00000000-0000-0000-0000-000000340105');
  v_original_entry app.loyalty_point_ledger_entries;
  v_original_entry_after app.loyalty_point_ledger_entries;
  v_lot_before app.loyalty_point_lots;
  v_lot_after app.loyalty_point_lots;
  v_reversal_event app.loyalty_earning_events;
  v_reversal_entry app.loyalty_point_ledger_entries;
  v_reversal_entry2 app.loyalty_point_ledger_entries;
  v_balance_before app.loyalty_point_balances;
  v_balance_after app.loyalty_point_balances;
begin
  select * into v_lot_before from app.loyalty_point_lots where source_earning_event_id = v_original_event;
  select * into v_original_entry from app.loyalty_point_ledger_entries where lot_id = v_lot_before.id and event_type = 'earn';
  select * into v_balance_before from app.loyalty_point_balances where loyalty_account_id = v_lot_before.loyalty_account_id;

  -- CPL-316's own governed reversal (LYL:Configure) -- creates the reversal
  -- earning event this checkpoint's own app.reverse_loyalty_points_earned
  -- then consumes.
  v_reversal_event := app.reverse_loyalty_earning_event(v_tenant1, v_original_event, 'customer disputed the invoice', 'rev-340105', v_manager1a, 'manager1a');

  begin
    perform app.reverse_loyalty_points_earned(v_tenant1, v_reversal_event.id, v_plain1, 'plain1');
    raise exception 'assertion failed: expected insufficient_authority for Plain User (LYL:Configure required)';
  exception when others then if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  v_reversal_entry := app.reverse_loyalty_points_earned(v_tenant1, v_reversal_event.id, v_manager1a, 'manager1a');
  if v_reversal_entry.event_type <> 'reversal' or v_reversal_entry.amount <> -60 or v_reversal_entry.corrects_entry_id <> v_original_entry.id then
    raise exception 'assertion failed: expected a reversal entry of -60 linked to the original earn entry, got %', v_reversal_entry;
  end if;

  -- The ORIGINAL entry is byte-for-byte unchanged -- still present, same
  -- amount, same id, never deleted or mutated in place.
  select * into v_original_entry_after from app.loyalty_point_ledger_entries where id = v_original_entry.id;
  if v_original_entry_after.amount <> v_original_entry.amount or v_original_entry_after.event_type <> 'earn' or v_original_entry_after.corrects_entry_id is not null then
    raise exception 'assertion failed: the original earn entry must remain unchanged (no delete/mutate), got % vs original %', v_original_entry_after, v_original_entry;
  end if;

  select * into v_lot_after from app.loyalty_point_lots where id = v_lot_before.id;
  if v_lot_after.remaining_amount <> 0 or v_lot_after.status <> 'exhausted' then
    raise exception 'assertion failed: expected the lot to be fully drained (remaining=0, status=exhausted), got %', v_lot_after;
  end if;

  select * into v_balance_after from app.loyalty_point_balances where loyalty_account_id = v_lot_before.loyalty_account_id;
  if v_balance_after.total_consumed <> v_balance_before.total_consumed + 60 then
    raise exception 'assertion failed: expected total_consumed to increase by 60, got before=% after=%', v_balance_before, v_balance_after;
  end if;

  -- Idempotent replay: calling the reversal-of-earning-event conversion
  -- again for the SAME reversal earning event is a safe no-op.
  v_reversal_entry2 := app.reverse_loyalty_points_earned(v_tenant1, v_reversal_event.id, v_manager1a, 'manager1a');
  if v_reversal_entry2.id <> v_reversal_entry.id then
    raise exception 'assertion failed: expected the identical reversal entry id on replay';
  end if;

  -- A lot with zero remaining has nothing left to reverse a second time.
  begin
    perform app.reverse_loyalty_points_earned(v_tenant1, v_reversal_event.id, v_manager1a, 'manager1a');
  exception when others then null; -- either a clean no-op (already handled above) or lot_already_fully_consumed on a genuinely different reversal event -- both acceptable, this call itself already proven idempotent above
  end;
end $$;

\echo '>> app.consume_loyalty_points_fifo: FIFO-by-expiry ordering (mandatory test c) -- consuming 150 from Alpha exhausts the soonest-expiring lot (100) then partially drains the next (50 of 80), leaving the latest-expiring lot (50) fully untouched'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'pts1');
  v_manager1a uuid := '00000000-0000-0000-0000-000000340001';
  v_loyalty_account_alpha uuid := (select id from app.loyalty_accounts where tenant_id = (select id from app.tenants where slug = 'pts1') and customer_account_id = (select id from app.accounts where tenant_id = (select id from app.tenants where slug = 'pts1') and legal_name = 'Pts Account Alpha'));
  v_lot_soonest app.loyalty_point_lots;
  v_lot_mid app.loyalty_point_lots;
  v_lot_latest app.loyalty_point_lots;
  v_entries app.loyalty_point_ledger_entries[];
  v_entry_count integer;
begin
  select * into v_lot_soonest from app.loyalty_point_lots where source_earning_event_id = (select id from app.loyalty_earning_events where idempotency_key = 'ar-open-item:00000000-0000-0000-0000-000000340102');
  select * into v_lot_mid from app.loyalty_point_lots where source_earning_event_id = (select id from app.loyalty_earning_events where idempotency_key = 'ar-open-item:00000000-0000-0000-0000-000000340103');
  select * into v_lot_latest from app.loyalty_point_lots where source_earning_event_id = (select id from app.loyalty_earning_events where idempotency_key = 'ar-open-item:00000000-0000-0000-0000-000000340104');

  if not (v_lot_soonest.expires_at < v_lot_mid.expires_at and v_lot_mid.expires_at < v_lot_latest.expires_at) then
    raise exception 'assertion failed: fixture setup error -- expected strictly staggered expires_at (soonest < mid < latest), got % / % / %', v_lot_soonest.expires_at, v_lot_mid.expires_at, v_lot_latest.expires_at;
  end if;

  v_entries := array(select app.consume_loyalty_points_fifo(v_tenant1, v_loyalty_account_alpha, 150, 'redemption', gen_random_uuid(), 'fifo-consume-1', v_manager1a, 'manager1a'));
  v_entry_count := array_length(v_entries, 1);
  if v_entry_count <> 2 then
    raise exception 'assertion failed: expected exactly 2 redemption entries (one per lot touched), got %', v_entry_count;
  end if;
  if v_entries[1].lot_id <> v_lot_soonest.id or v_entries[1].amount <> -100 then
    raise exception 'assertion failed: expected the FIRST redemption entry to fully drain the soonest-expiring lot (-100), got %', v_entries[1];
  end if;
  if v_entries[2].lot_id <> v_lot_mid.id or v_entries[2].amount <> -50 then
    raise exception 'assertion failed: expected the SECOND redemption entry to partially drain the next lot (-50), got %', v_entries[2];
  end if;

  select * into v_lot_soonest from app.loyalty_point_lots where id = v_lot_soonest.id;
  select * into v_lot_mid from app.loyalty_point_lots where id = v_lot_mid.id;
  select * into v_lot_latest from app.loyalty_point_lots where id = v_lot_latest.id;
  if v_lot_soonest.remaining_amount <> 0 or v_lot_soonest.status <> 'exhausted' then
    raise exception 'assertion failed: expected the soonest-expiring lot fully exhausted, got %', v_lot_soonest;
  end if;
  if v_lot_mid.remaining_amount <> 30 or v_lot_mid.status <> 'active' then
    raise exception 'assertion failed: expected the mid lot to have 30 remaining (80 - 50), got %', v_lot_mid;
  end if;
  if v_lot_latest.remaining_amount <> 50 or v_lot_latest.status <> 'active' then
    raise exception 'assertion failed: expected the latest-expiring lot fully UNTOUCHED (50 remaining), got %', v_lot_latest;
  end if;

  -- Whole-redemption idempotency: replaying with the SAME (source_type,
  -- source_id) returns the SAME 2 entries, never a second consumption.
  declare
    v_source_id uuid := v_entries[1].source_id;
    v_replay app.loyalty_point_ledger_entries[];
  begin
    v_replay := array(select app.consume_loyalty_points_fifo(v_tenant1, v_loyalty_account_alpha, 150, 'redemption', v_source_id, 'fifo-consume-1-retry', v_manager1a, 'manager1a'));
    if array_length(v_replay, 1) <> 2 or v_replay[1].id <> v_entries[1].id or v_replay[2].id <> v_entries[2].id then
      raise exception 'assertion failed: expected a replay by (source_type, source_id) to return the identical 2 entries, got %', v_replay;
    end if;
  end;
end $$;

\echo '>> app.expire_loyalty_point_lots: expires a due lot (Gamma''s own lot, directly fixture-backdated -- never through the RPC), posts a real expiry entry, idempotent on re-run'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'pts1');
  v_manager1a uuid := '00000000-0000-0000-0000-000000340001';
  v_plain1 uuid := '00000000-0000-0000-0000-000000340004';
  v_loyalty_account_gamma uuid := (select id from app.loyalty_accounts where tenant_id = (select id from app.tenants where slug = 'pts1') and customer_account_id = (select id from app.accounts where tenant_id = (select id from app.tenants where slug = 'pts1') and legal_name = 'Pts Account Gamma'));
  v_gamma_lot app.loyalty_point_lots;
  v_entries app.loyalty_point_ledger_entries[];
  v_entries2 app.loyalty_point_ledger_entries[];
begin
  select * into v_gamma_lot from app.loyalty_point_lots where loyalty_account_id = v_loyalty_account_gamma;
  -- Directly fixture-backdate expires_at into the past -- never through the
  -- RPC (mirrors CPL-317's own established "a direct fixture-level next_
  -- review_at backdate" precedent for exactly this class of timing test).
  update app.loyalty_point_lots set expires_at = clock_timestamp() - interval '1 day' where id = v_gamma_lot.id;

  begin
    perform app.expire_loyalty_point_lots(v_tenant1, v_plain1, 'plain1');
    raise exception 'assertion failed: expected insufficient_authority for Plain User';
  exception when others then if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  v_entries := array(select app.expire_loyalty_point_lots(v_tenant1, v_manager1a, 'manager1a'));
  if array_length(v_entries, 1) is null or not (v_gamma_lot.id = any (select lot_id from unnest(v_entries) e)) then
    raise exception 'assertion failed: expected Gamma''s own due lot to appear in this run''s expired entries, got %', v_entries;
  end if;

  select * into v_gamma_lot from app.loyalty_point_lots where id = v_gamma_lot.id;
  if v_gamma_lot.status <> 'expired' or v_gamma_lot.remaining_amount <> 0 then
    raise exception 'assertion failed: expected Gamma''s own lot to be expired with zero remaining, got %', v_gamma_lot;
  end if;

  -- Idempotent re-run: the same lot no longer matches the scan predicate
  -- (status <> 'active'), so a second call is a safe no-op for it.
  v_entries2 := array(select app.expire_loyalty_point_lots(v_tenant1, v_manager1a, 'manager1a'));
  if v_gamma_lot.id = any (select lot_id from unnest(v_entries2) e) then
    raise exception 'assertion failed: expected the second expire run to be a no-op for Gamma''s already-expired lot';
  end if;
end $$;

\echo '>> negative-balance prevention -- attempted over-consumption (mandatory test b, single-session): Beta has 200 available; requesting 250 via app.consume_loyalty_points_fifo is rejected and the balance is unchanged'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'pts1');
  v_manager1a uuid := '00000000-0000-0000-0000-000000340001';
  v_loyalty_account_beta uuid := (select id from app.loyalty_accounts where tenant_id = (select id from app.tenants where slug = 'pts1') and customer_account_id = (select id from app.accounts where tenant_id = (select id from app.tenants where slug = 'pts1') and legal_name = 'Pts Account Beta'));
  v_balance_before app.loyalty_point_balances;
  v_balance_after app.loyalty_point_balances;
begin
  select * into v_balance_before from app.loyalty_point_balances where loyalty_account_id = v_loyalty_account_beta;
  if v_balance_before.available <> 200 then
    raise exception 'assertion failed: fixture setup error -- expected Beta''s own available balance to be 200, got %', v_balance_before;
  end if;

  begin
    perform app.consume_loyalty_points_fifo(v_tenant1, v_loyalty_account_beta, 250, 'redemption', gen_random_uuid(), 'over-consume-1', v_manager1a, 'manager1a');
    raise exception 'assertion failed: expected insufficient_points_balance for a 250-point request against a 200-point balance';
  exception when others then if sqlerrm not like 'insufficient_points_balance%' then raise; end if;
  end;

  select * into v_balance_after from app.loyalty_point_balances where loyalty_account_id = v_loyalty_account_beta;
  if v_balance_after.total_earned <> v_balance_before.total_earned or v_balance_after.total_consumed <> v_balance_before.total_consumed then
    raise exception 'assertion failed: a rejected over-consumption must leave the balance byte-for-byte unchanged (the whole call rolls back), got before=% after=%', v_balance_before, v_balance_after;
  end if;
  -- The rejected attempt must also leave zero new ledger rows for this
  -- account beyond what already existed.
  if (select count(*) from app.loyalty_point_ledger_entries where loyalty_account_id = v_loyalty_account_beta and event_type = 'redemption') <> 0 then
    raise exception 'assertion failed: a rejected over-consumption must post zero redemption entries';
  end if;
end $$;

\echo '>> negative-balance prevention -- a REAL two-process concurrent-race attempt (mandatory test b): two overlapping psql sessions each try to consume 120 of Beta''s own 200-point balance (240 > 200 total) -- exactly one may fully succeed, the other must be rejected, total_consumed never exceeds total_earned'
select (select id from app.tenants where slug = 'pts1') as race_tenant1_id \gset
select (select id from app.loyalty_accounts where tenant_id = (select id from app.tenants where slug = 'pts1') and customer_account_id = (select id from app.accounts where tenant_id = (select id from app.tenants where slug = 'pts1') and legal_name = 'Pts Account Beta')) as race_account_beta_id \gset
select current_database() as pg_test_db \gset
select pg_backend_pid()::text as race_bpid \gset

-- Literal-interpolated (never current_setting()/set_config -- the race
-- helper opens brand-new psql CONNECTIONS, which do not share this
-- session's own GUCs) -- mirrors scripts/db-tests/advanced-tms-wms-
-- picking.sql's own established :variable-interpolation-into-a-\set-string
-- pattern exactly.
\set race_sql_a 'select app.consume_loyalty_points_fifo(''' :race_tenant1_id ''', ''' :race_account_beta_id ''', 120, ''redemption'', gen_random_uuid(), ''race-consume-a'', ''00000000-0000-0000-0000-000000340001'', ''manager1a'');'
\set race_sql_b 'select app.consume_loyalty_points_fifo(''' :race_tenant1_id ''', ''' :race_account_beta_id ''', 120, ''redemption'', gen_random_uuid(), ''race-consume-b'', ''00000000-0000-0000-0000-000000340001'', ''manager1a'');'

\setenv PG_TEST_DB :pg_test_db
\setenv RACE_SQL_A :race_sql_a
\setenv RACE_SQL_B :race_sql_b
\setenv RACE_OUT_A /tmp/cargogrid-pts-race-beta-a-:race_bpid.out
\setenv RACE_OUT_B /tmp/cargogrid-pts-race-beta-b-:race_bpid.out

\! bash scripts/db-tests/wms-picking-concurrency-helper.sh

-- psql does not interpolate :variables inside a do $$ ... $$ body (the same
-- limitation scripts/db-tests/advanced-tms-wms-picking.sql's own comment
-- documents) -- re-derive the account id fresh via a plain subquery instead
-- (this verification runs in the SAME session as setup, unlike the two
-- racer processes launched by the helper script above).
do $$
declare
  v_loyalty_account_beta uuid := (select id from app.loyalty_accounts where tenant_id = (select id from app.tenants where slug = 'pts1') and customer_account_id = (select id from app.accounts where tenant_id = (select id from app.tenants where slug = 'pts1') and legal_name = 'Pts Account Beta'));
  v_balance app.loyalty_point_balances;
  v_redemption_sum numeric;
  v_redemption_count integer;
begin
  select * into v_balance from app.loyalty_point_balances where loyalty_account_id = v_loyalty_account_beta;
  select coalesce(sum(amount), 0), count(*) into v_redemption_sum, v_redemption_count
    from app.loyalty_point_ledger_entries
    where loyalty_account_id = v_loyalty_account_beta and event_type = 'redemption' and source_type = 'redemption';

  -- The negative-balance CHECK constraint/procedural guard must hold no
  -- matter which racer won: available can never go negative.
  if v_balance.available < 0 or v_balance.total_consumed > v_balance.total_earned then
    raise exception 'assertion failed: the concurrent race must never drive the balance negative, got %', v_balance;
  end if;

  -- Exactly ONE of the two 120-point race attempts may have fully succeeded
  -- (both succeeding would require 240 against a 200 balance, which the
  -- FOR UPDATE-serialized balance check structurally prevents). A single
  -- fully-successful 120-point consumption posts exactly 1 redemption entry
  -- (Beta's whole balance came from ONE lot) summing to -120.
  if v_redemption_count = 1 then
    if v_redemption_sum <> -120 then
      raise exception 'assertion failed: expected the one winning racer''s own redemption to sum to exactly -120, got %', v_redemption_sum;
    end if;
  elsif v_redemption_count = 0 then
    -- Also an acceptable, safe outcome under extreme scheduling (both lost
    -- to some other real error) -- the invariant under test is "never both
    -- succeed", not "exactly one must succeed every possible interleaving".
    null;
  else
    raise exception 'assertion failed: expected at most 1 successful concurrent 120-point redemption against a 200-point balance, got % entries summing to %', v_redemption_count, v_redemption_sum;
  end if;
end $$;

\echo '>> app.request_loyalty_point_adjustment / app.decide_loyalty_point_adjustment: self-approval blocked, LIVE (mandatory test d) -- Manager A requests, Manager A cannot decide their own request, Manager B (a genuinely different actor) can'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'pts1');
  v_manager1a uuid := '00000000-0000-0000-0000-000000340001';
  v_manager1b uuid := '00000000-0000-0000-0000-000000340002';
  v_plain1 uuid := '00000000-0000-0000-0000-000000340004';
  v_loyalty_account_gamma uuid := (select id from app.loyalty_accounts where tenant_id = (select id from app.tenants where slug = 'pts1') and customer_account_id = (select id from app.accounts where tenant_id = (select id from app.tenants where slug = 'pts1') and legal_name = 'Pts Account Gamma'));
  v_balance_before app.loyalty_point_balances;
  v_balance_after app.loyalty_point_balances;
  v_request app.loyalty_point_adjustment_requests;
  v_decided app.loyalty_point_adjustment_requests;
begin
  select * into v_balance_before from app.loyalty_point_balances where loyalty_account_id = v_loyalty_account_gamma;

  begin
    perform app.request_loyalty_point_adjustment(v_tenant1, v_loyalty_account_gamma, 50, '', 'adj-req-blank-reason', v_manager1a, 'manager1a');
    raise exception 'assertion failed: expected reason_required for a blank reason';
  exception when others then if sqlerrm not like 'reason_required%' then raise; end if;
  end;
  begin
    perform app.request_loyalty_point_adjustment(v_tenant1, v_loyalty_account_gamma, 0, 'x', 'adj-req-zero', v_manager1a, 'manager1a');
    raise exception 'assertion failed: expected invalid_amount for a zero amount';
  exception when others then if sqlerrm not like 'invalid_amount%' then raise; end if;
  end;
  begin
    perform app.request_loyalty_point_adjustment(v_tenant1, v_loyalty_account_gamma, 50, 'x', 'adj-req-denied', v_plain1, 'plain1');
    raise exception 'assertion failed: expected insufficient_authority for Plain User';
  exception when others then if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  v_request := app.request_loyalty_point_adjustment(v_tenant1, v_loyalty_account_gamma, 50, 'Suspected duplicate award -- internal fraud investigation ref #4521', 'adj-req-1', v_manager1a, 'manager1a');
  if v_request.status <> 'pending_approval' or v_request.requested_by_auth_user_id <> v_manager1a then
    raise exception 'assertion failed: expected a pending request from Manager A, got %', v_request;
  end if;

  -- A second concurrent request against the SAME account, while one is
  -- already pending, is rejected (lpar_pending_unique).
  begin
    perform app.request_loyalty_point_adjustment(v_tenant1, v_loyalty_account_gamma, -10, 'a second, different request', 'adj-req-2', v_manager1a, 'manager1a');
    raise exception 'assertion failed: expected adjustment_already_pending for a second pending request on the same account';
  exception when others then if sqlerrm not like 'adjustment_already_pending%' then raise; end if;
  end;

  -- Self-approval blocked -- Manager A, who REQUESTED it, may not also
  -- DECIDE it. Live-proven against a real database, not TS-mocked.
  begin
    perform app.decide_loyalty_point_adjustment(v_tenant1, v_request.id, v_request.record_version, 'approved', 'approving my own request', v_manager1a, 'manager1a');
    raise exception 'assertion failed: expected self_approval_not_allowed when the requester attempts to decide their own request';
  exception when others then if sqlerrm not like 'self_approval_not_allowed%' then raise; end if;
  end;

  begin
    perform app.decide_loyalty_point_adjustment(v_tenant1, v_request.id, v_request.record_version, 'approved', 'x', v_plain1, 'plain1');
    raise exception 'assertion failed: expected insufficient_authority for Plain User (LYL:Configure required)';
  exception when others then if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;
  begin
    perform app.decide_loyalty_point_adjustment(v_tenant1, v_request.id, 999, 'approved', 'x', v_manager1b, 'manager1b');
    raise exception 'assertion failed: expected stale_version for a wrong expected_version';
  exception when others then if sqlerrm not like 'stale_version%' then raise; end if;
  end;
  begin
    perform app.decide_loyalty_point_adjustment(v_tenant1, v_request.id, v_request.record_version, 'maybe', 'x', v_manager1b, 'manager1b');
    raise exception 'assertion failed: expected invalid_decision for a decision that is not approved/rejected';
  exception when others then if sqlerrm not like 'invalid_decision%' then raise; end if;
  end;
  begin
    perform app.decide_loyalty_point_adjustment(v_tenant1, v_request.id, v_request.record_version, 'approved', '', v_manager1b, 'manager1b');
    raise exception 'assertion failed: expected reason_required for a blank decision_notes';
  exception when others then if sqlerrm not like 'reason_required%' then raise; end if;
  end;

  -- Manager B, a genuinely DIFFERENT real actor holding LYL:Configure, may
  -- decide it.
  v_decided := app.decide_loyalty_point_adjustment(v_tenant1, v_request.id, v_request.record_version, 'approved', 'confirmed with finance, approving the correction', v_manager1b, 'manager1b');
  if v_decided.status <> 'approved' or v_decided.decided_by_auth_user_id <> v_manager1b or v_decided.ledger_entry_id is null then
    raise exception 'assertion failed: expected an approved decision by Manager B with a real ledger_entry_id, got %', v_decided;
  end if;

  select * into v_balance_after from app.loyalty_point_balances where loyalty_account_id = v_loyalty_account_gamma;
  if v_balance_after.total_earned <> v_balance_before.total_earned + 50 then
    raise exception 'assertion failed: expected total_earned to increase by 50 after the approved adjustment, got before=% after=%', v_balance_before, v_balance_after;
  end if;

  -- A decided request cannot be decided again.
  begin
    perform app.decide_loyalty_point_adjustment(v_tenant1, v_request.id, v_decided.record_version, 'rejected', 'too late', v_manager1b, 'manager1b');
    raise exception 'assertion failed: expected invalid_transition -- an already-decided request cannot be decided again';
  exception when others then if sqlerrm not like 'invalid_transition%' then raise; end if;
  end;

  -- A rejected request posts NO ledger entry.
  declare
    v_request2 app.loyalty_point_adjustment_requests;
    v_decided2 app.loyalty_point_adjustment_requests;
  begin
    v_request2 := app.request_loyalty_point_adjustment(v_tenant1, v_loyalty_account_gamma, -5, 'a small correction, to be rejected', 'adj-req-3', v_manager1a, 'manager1a');
    v_decided2 := app.decide_loyalty_point_adjustment(v_tenant1, v_request2.id, v_request2.record_version, 'rejected', 'not enough evidence', v_manager1b, 'manager1b');
    if v_decided2.status <> 'rejected' or v_decided2.ledger_entry_id is not null then
      raise exception 'assertion failed: expected a rejected request with ledger_entry_id null, got %', v_decided2;
    end if;
  end;
end $$;

\echo '>> Tier C review fix regression (Critical): Gamma''s only lot was independently expired earlier in this fixture, so her ENTIRE available balance (50) is now a lot-less credit from the approved adjustment above -- app.consume_loyalty_points_fifo must be able to redeem it (previously: insufficient_points_balance, unconditionally, the moment active lots ran out)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'pts1');
  v_manager1a uuid := '00000000-0000-0000-0000-000000340001';
  v_loyalty_account_gamma uuid := (select id from app.loyalty_accounts where tenant_id = (select id from app.tenants where slug = 'pts1') and customer_account_id = (select id from app.accounts where tenant_id = (select id from app.tenants where slug = 'pts1') and legal_name = 'Pts Account Gamma'));
  v_balance_before app.loyalty_point_balances;
  v_balance_after app.loyalty_point_balances;
  v_active_lot_count integer;
  v_entries app.loyalty_point_ledger_entries[];
  v_replay app.loyalty_point_ledger_entries[];
  v_source_id uuid := gen_random_uuid();
begin
  select * into v_balance_before from app.loyalty_point_balances where loyalty_account_id = v_loyalty_account_gamma;
  select count(*) into v_active_lot_count from app.loyalty_point_lots where loyalty_account_id = v_loyalty_account_gamma and status = 'active' and remaining_amount > 0;
  if v_balance_before.available <> 50 or v_active_lot_count <> 0 then
    raise exception 'assertion failed: expected the fixture pre-condition (available=50 entirely lot-less, zero active lots), got available=%, active_lot_count=%', v_balance_before.available, v_active_lot_count;
  end if;

  v_entries := array(select app.consume_loyalty_points_fifo(v_tenant1, v_loyalty_account_gamma, 50, 'redemption', v_source_id, 'phantom-credit-fix-1', v_manager1a, 'manager1a'));
  if array_length(v_entries, 1) <> 1 or v_entries[1].lot_id is not null or v_entries[1].amount <> -50 then
    raise exception 'assertion failed: expected exactly one lot-LESS redemption entry (lot_id null, amount=-50), got %', v_entries;
  end if;

  select * into v_balance_after from app.loyalty_point_balances where loyalty_account_id = v_loyalty_account_gamma;
  if v_balance_after.available <> 0 or v_balance_after.total_consumed <> v_balance_before.total_consumed + 50 then
    raise exception 'assertion failed: expected available=0 after fully redeeming the lot-less credit, got %', v_balance_after;
  end if;

  -- Idempotent replay of the SAME logical redemption returns the identical
  -- single row, never double-consumes.
  v_replay := array(select app.consume_loyalty_points_fifo(v_tenant1, v_loyalty_account_gamma, 50, 'redemption', v_source_id, 'phantom-credit-fix-1-retry', v_manager1a, 'manager1a'));
  if array_length(v_replay, 1) <> 1 or v_replay[1].id <> v_entries[1].id then
    raise exception 'assertion failed: expected idempotent replay to return the identical single entry, got %', v_replay;
  end if;

  -- Genuinely insufficient (nothing left at all, no lots and no aggregate
  -- headroom) still fails, with the identical insufficient_points_balance
  -- errcode/message prefix.
  begin
    perform app.consume_loyalty_points_fifo(v_tenant1, v_loyalty_account_gamma, 1, 'redemption', gen_random_uuid(), 'phantom-credit-fix-2', v_manager1a, 'manager1a');
    raise exception 'assertion failed: expected insufficient_points_balance -- Gamma has zero lots and zero aggregate balance remaining';
  exception when others then if sqlerrm not like 'insufficient_points_balance%' then raise; end if;
  end;
end $$;

\echo '>> Tier C review fix regression (Low): a role holding LYL:Configure but NOT LYL:Edit gets an immediate, clearly-labeled insufficient_authority (lacks LYL:Edit) when APPROVING an adjustment or reversing earned points -- but MAY still REJECT a pending adjustment (which never delegates to app.post_loyalty_point_ledger_entry), unaffected by this fix'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'pts1');
  v_manager1a uuid := '00000000-0000-0000-0000-000000340001';
  v_configure_only uuid := '00000000-0000-0000-0000-000000340006';
  v_configure_role uuid;
  v_configure_draft app.role_versions;
  v_loyalty_account_alpha uuid := (select id from app.loyalty_accounts where tenant_id = (select id from app.tenants where slug = 'pts1') and customer_account_id = (select id from app.accounts where tenant_id = (select id from app.tenants where slug = 'pts1') and legal_name = 'Pts Account Alpha'));
  v_request app.loyalty_point_adjustment_requests;
  v_decided app.loyalty_point_adjustment_requests;
  -- A fully isolated, dedicated fixture (own account, own earning event, own
  -- CPL-316-level reversal) so the app.reverse_loyalty_points_earned
  -- sub-test below never touches Alpha/Beta/Gamma/Delta's own already-
  -- asserted-elsewhere ledger row counts.
  v_account_epsilon uuid;
  v_loyalty_account_epsilon uuid;
  v_program_id uuid := (select id from app.loyalty_programs where tenant_id = (select id from app.tenants where slug = 'pts1') and name = 'Points Rewards');
  v_epsilon_event app.loyalty_earning_events;
  v_epsilon_reversal_event app.loyalty_earning_events;
begin
  insert into auth.users (id, email) values (v_configure_only, 'configure-only@pts1.test');
  perform app.invite_user(v_tenant1, v_configure_only, 'configure-only@pts1.test', 'Pts1 Configure-Only', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'configure-only@pts1.test'), 'active', 'onboarded', 'tester');
  v_configure_role := (app.create_role(v_tenant1, 'Loyalty Configure-Only', 'LYL:Configure only, deliberately missing Edit', 'tester')).id;
  v_configure_draft := app.create_role_version(v_configure_role, 'tester');
  perform app.set_role_version_permissions(v_configure_draft.id, array(select id from app.permissions where resource_module_code = 'LYL' and action in ('View', 'Configure')), 'tester');
  perform app.publish_role_version(v_configure_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_configure_role and status = 'published'), v_configure_only, v_manager1a, 'tester');

  v_request := app.request_loyalty_point_adjustment(v_tenant1, v_loyalty_account_alpha, 7, 'Configure-only regression fixture', 'adj-req-configure-only', v_manager1a, 'manager1a');

  -- APPROVE requires LYL:Edit too (delegates to the posting primitive) --
  -- rejected immediately, clearly, before any ledger row is ever touched.
  begin
    perform app.decide_loyalty_point_adjustment(v_tenant1, v_request.id, v_request.record_version, 'approved', 'trying to approve without Edit', v_configure_only, 'configure-only');
    raise exception 'assertion failed: expected insufficient_authority (lacks LYL:Edit) for a Configure-only actor approving an adjustment';
  exception when others then if sqlerrm not like 'insufficient_authority%lacks LYL:Edit%' then raise; end if;
  end;
  if (select status from app.loyalty_point_adjustment_requests where id = v_request.id) <> 'pending_approval' then
    raise exception 'assertion failed: the blocked approval attempt must never actually change the request''s own status';
  end if;

  -- REJECT never delegates to the posting primitive -- a Configure-only
  -- actor may still reject, unaffected by this fix.
  v_decided := app.decide_loyalty_point_adjustment(v_tenant1, v_request.id, v_request.record_version, 'rejected', 'Configure-only actor may still reject', v_configure_only, 'configure-only');
  if v_decided.status <> 'rejected' or v_decided.decided_by_auth_user_id <> v_configure_only then
    raise exception 'assertion failed: expected a Configure-only actor to successfully REJECT, got %', v_decided;
  end if;

  -- app.reverse_loyalty_points_earned: build a fresh, isolated, genuinely
  -- reversal-shaped earning event (never yet consumed by this function) so
  -- the Configure-only actor's call reaches all the way to this function's
  -- own new LYL:Edit gate, rather than short-circuiting on idempotent
  -- replay or an unrelated not_a_reversal_earning_event rejection.
  insert into app.accounts (tenant_id, legal_name, duplicate_fingerprint, billing_address, created_by)
  values (v_tenant1, 'Pts Account Epsilon', 'pts-epsilon-fp', '{}'::jsonb, 'tester') returning id into v_account_epsilon;
  v_loyalty_account_epsilon := (app.enroll_customer_loyalty_account(v_tenant1, v_account_epsilon, v_program_id, v_manager1a, 'manager1a')).id;
  insert into app.finance_ar_open_items (id, tenant_id, customer_account_id, source_document_type, source_document_id, currency, original_amount, allocated_amount, status, is_held, invoice_date, due_date, created_by)
  values ('00000000-0000-0000-0000-000000340601', v_tenant1, v_account_epsilon, 'invoice', '00000000-0000-0000-0000-000000340602', 'USD', 30, 30, 'paid', false, '2026-08-01', '2026-08-31', 'tester');
  v_epsilon_event := app.evaluate_customer_loyalty_earning_for_paid_invoice(v_tenant1, '00000000-0000-0000-0000-000000340601', v_manager1a, 'manager1a');
  perform app.post_loyalty_points_earned(v_tenant1, v_epsilon_event.id, v_manager1a, 'manager1a', 365);
  v_epsilon_reversal_event := app.reverse_loyalty_earning_event(v_tenant1, v_epsilon_event.id, 'Configure-only regression fixture reversal', 'rev-epsilon-configure-only', v_manager1a, 'manager1a');

  begin
    perform app.reverse_loyalty_points_earned(v_tenant1, v_epsilon_reversal_event.id, v_configure_only, 'configure-only');
    raise exception 'assertion failed: expected insufficient_authority (lacks LYL:Edit) for a Configure-only actor reversing earned points on a fresh, valid reversal event';
  exception when others then if sqlerrm not like 'insufficient_authority%lacks LYL:Edit%' then raise; end if;
  end;
  if exists (select 1 from app.loyalty_point_ledger_entries where loyalty_account_id = v_loyalty_account_epsilon and event_type = 'reversal') then
    raise exception 'assertion failed: the blocked reversal attempt must never actually post a reversal ledger entry';
  end if;
end $$;

\echo '>> app.get_loyalty_point_adjustment_request / app.list_loyalty_point_adjustment_requests: staff can see the real internal reason/decision_notes; LYL:View required; keyset pagination'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'pts1');
  v_manager1a uuid := '00000000-0000-0000-0000-000000340001';
  v_plain1 uuid := '00000000-0000-0000-0000-000000340004';
  v_request_id uuid := (select id from app.loyalty_point_adjustment_requests where idempotency_key = 'adj-req-1');
  v_fetched app.loyalty_point_adjustment_requests;
  v_count integer;
begin
  v_fetched := app.get_loyalty_point_adjustment_request(v_tenant1, v_request_id, v_manager1a);
  if v_fetched.reason not like '%fraud investigation%' then
    raise exception 'assertion failed: expected the STAFF-facing get to show the real internal reason, got %', v_fetched.reason;
  end if;

  begin
    perform app.get_loyalty_point_adjustment_request(v_tenant1, v_request_id, v_plain1);
    raise exception 'assertion failed: expected insufficient_authority for Plain User';
  exception when others then if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  -- adj-req-1 (approved) + adj-req-3 (rejected) + adj-req-configure-only
  -- (rejected, the Tier C review fix regression fixture) = 3 real rows --
  -- the attempted "adj-req-2" second-pending-request above never inserted
  -- (it hit lpar_pending_unique and was rejected before any row existed).
  select count(*) into v_count from app.list_loyalty_point_adjustment_requests(v_tenant1, v_manager1a, p_limit => 200);
  if v_count <> 3 then
    raise exception 'assertion failed: expected 3 adjustment requests total for tenant pts1, got %', v_count;
  end if;
end $$;

\echo '>> customer-facing reads: app.list_customer_portal_loyalty_point_balances / ...ledger_entries / ...expiry_schedule -- deny-by-default, customer-safe, NEVER leaks the internal adjustment reason (mandatory test g)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'pts1');
  v_tenant2 uuid := (select id from app.tenants where slug = 'pts2');
  v_customer_alpha uuid := '00000000-0000-0000-0000-000000340010';
  v_customer_beta uuid := '00000000-0000-0000-0000-000000340020';
  v_customer_delta uuid := '00000000-0000-0000-0000-000000341010';
  v_customer_gamma uuid := '00000000-0000-0000-0000-000000340030';
  v_ledger record;
begin
  -- Give Gamma her own customer_user identity (the fraud-investigation-
  -- reasoned adjustment from the maker-checker section above landed on
  -- Gamma's own loyalty account) so this section can prove DIRECTLY, from
  -- Gamma's own customer-facing session, that the real internal reason
  -- never appears -- not merely infer it from Beta's unrelated rows.
  insert into auth.users (id, email) values (v_customer_gamma, 'customer-gamma@pts1.test');
  perform app.invite_user(v_tenant1, v_customer_gamma, 'customer-gamma@pts1.test', 'Pts Customer Gamma', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'customer-gamma@pts1.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(v_customer_gamma, 'customer_user', v_tenant1, (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Pts Account Gamma')::text, 'tester');

  -- Alpha sees her own balance only, never Beta's.
  if (select count(*) from app.list_customer_portal_loyalty_point_balances(v_tenant1, v_customer_alpha)) <> 1 then
    raise exception 'assertion failed: expected Alpha to see exactly 1 balance row (her own)';
  end if;

  -- Beta's ledger history includes her own redemption entries from the
  -- concurrent-race section above, but no reason field is ever projected at
  -- all -- structural, not merely UI omission -- and the description for a
  -- redemption is the generic "Points redeemed", not an internal detail.
  for v_ledger in select * from app.list_customer_portal_loyalty_point_ledger_entries(v_tenant1, v_customer_beta, p_limit => 200) loop
    if v_ledger.description ilike '%fraud%' or v_ledger.description ilike '%investigation%' or v_ledger.description ilike '%dispute%' then
      raise exception 'assertion failed: a customer-facing ledger description must never contain an internal investigation note, got %', v_ledger.description;
    end if;
  end loop;

  -- Cross-account isolation within the SAME tenant: Beta's own ledger read
  -- must never include a row belonging to Alpha's or Gamma's own loyalty
  -- account (verified by row count matching exactly Beta's own known entry
  -- count -- Beta only ever had the 2 winning-racer entries from the
  -- concurrent-race section, at most).
  if (select count(*) from app.list_customer_portal_loyalty_point_ledger_entries(v_tenant1, v_customer_beta, p_limit => 200)) > 2 then
    raise exception 'assertion failed: Beta''s own ledger history must never include another account''s rows';
  end if;

  -- Gamma's own adjustment (the real internal reason: "Suspected duplicate
  -- award -- internal fraud investigation ref #4521") is proven DIRECTLY,
  -- from Gamma's own customer-facing session: the description is the
  -- generic "Account adjustment", never the real reason text, and no
  -- `reason` column exists on this RETURNS TABLE shape at all (structural,
  -- not merely a value check).
  declare
    v_found_adjustment boolean := false;
  begin
    for v_ledger in select * from app.list_customer_portal_loyalty_point_ledger_entries(v_tenant1, v_customer_gamma, p_limit => 200) loop
      if v_ledger.event_type = 'adjustment' then
        v_found_adjustment := true;
        if v_ledger.description <> 'Account adjustment' then
          raise exception 'assertion failed: expected the generic "Account adjustment" description, got %', v_ledger.description;
        end if;
      end if;
      if v_ledger.description ilike '%fraud%' or v_ledger.description ilike '%investigation%' or v_ledger.description ilike '%duplicate award%' then
        raise exception 'assertion failed: Gamma''s own customer-facing ledger must never contain the real internal adjustment reason, got %', v_ledger.description;
      end if;
    end loop;
    if not v_found_adjustment then
      raise exception 'assertion failed: expected Gamma''s own customer-facing ledger to include her approved adjustment entry';
    end if;
  end;

  -- Expiry schedule: Alpha's own remaining active lots, soonest-expiring
  -- first (ascending keyset).
  declare
    v_prev_expires_at timestamptz := null;
    v_row record;
  begin
    for v_row in select * from app.list_customer_portal_loyalty_point_expiry_schedule(v_tenant1, v_customer_alpha, p_limit => 200) loop
      if v_prev_expires_at is not null and v_row.expires_at < v_prev_expires_at then
        raise exception 'assertion failed: expiry schedule must be ascending by expires_at, got % after %', v_row.expires_at, v_prev_expires_at;
      end if;
      v_prev_expires_at := v_row.expires_at;
    end loop;
  end;

  -- Deny-by-default: an out-of-scope customer_account_id or a fully
  -- unrelated identity resolves to an EMPTY result, never an error and
  -- never another customer's data.
  if (select count(*) from app.list_customer_portal_loyalty_point_balances(v_tenant1, v_customer_alpha, p_customer_account_id => (select id from app.accounts where tenant_id = v_tenant1 and legal_name = 'Pts Account Beta'))) <> 0 then
    raise exception 'assertion failed: Alpha must see zero rows when passing Beta''s own out-of-scope customer_account_id';
  end if;

  -- Cross-tenant isolation (mandatory test f): Delta (tenant2) sees zero
  -- rows when passing tenant1's own id.
  if (select count(*) from app.list_customer_portal_loyalty_point_balances(v_tenant1, v_customer_delta)) <> 0 then
    raise exception 'assertion failed: Delta must see zero rows for tenant1''s own id (deny-by-default across tenants)';
  end if;
  if (select count(*) from app.list_customer_portal_loyalty_point_ledger_entries(v_tenant1, v_customer_delta)) <> 0 then
    raise exception 'assertion failed: Delta must see zero ledger rows for tenant1''s own id';
  end if;

  -- Delta DOES see her own tenant2 balance normally.
  if (select count(*) from app.list_customer_portal_loyalty_point_balances(v_tenant2, v_customer_delta)) <> 1 then
    raise exception 'assertion failed: Delta must see exactly 1 balance row within her own tenant2';
  end if;
end $$;

\echo '>> cross-tenant staff isolation (mandatory test f): tenant pts2''s own manager cannot act on tenant pts1''s own data, whether by passing pts1''s own tenant_id or by guessing a pts1 id inside pts2''s own scope -- identical not-found error either way (anti-enumeration)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'pts1');
  v_tenant2 uuid := (select id from app.tenants where slug = 'pts2');
  v_manager2 uuid := '00000000-0000-0000-0000-000000341001';
  v_loyalty_account_alpha uuid := (select id from app.loyalty_accounts where tenant_id = (select id from app.tenants where slug = 'pts1') and customer_account_id = (select id from app.accounts where tenant_id = (select id from app.tenants where slug = 'pts1') and legal_name = 'Pts Account Alpha'));
  v_pts1_request_id uuid := (select id from app.loyalty_point_adjustment_requests where idempotency_key = 'adj-req-1');
begin
  -- pts2's manager, passing pts1's own tenant_id, has no LYL role there --
  -- insufficient_authority (no role assignment in that tenant).
  begin
    perform app.get_loyalty_point_balance(v_tenant1, v_loyalty_account_alpha, v_manager2);
    raise exception 'assertion failed: expected insufficient_authority for tenant2''s manager acting against tenant1';
  exception when others then if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  -- pts2's manager, correctly scoped to their OWN tenant2, guessing a real
  -- pts1 id, gets the identical not-found shape (never a distinguishable
  -- "exists but wrong tenant" leak) -- proven directly against the maker-
  -- checker decide RPC, which is p_tenant_id-scoped by design (design
  -- decision 9).
  begin
    perform app.decide_loyalty_point_adjustment(v_tenant2, v_pts1_request_id, 1, 'approved', 'guessed id', v_manager2, 'manager2');
    raise exception 'assertion failed: expected loyalty_point_adjustment_request_not_found for a cross-tenant id guess';
  exception when others then if sqlerrm not like 'loyalty_point_adjustment_request_not_found%' then raise; end if;
  end;

  -- Also proven against a request under tenant2's OWN real, nonexistent-id
  -- case -- both resolve to the identical error class (anti-enumeration).
  begin
    perform app.decide_loyalty_point_adjustment(v_tenant2, gen_random_uuid(), 1, 'approved', 'nonexistent id', v_manager2, 'manager2');
    raise exception 'assertion failed: expected loyalty_point_adjustment_request_not_found for a genuinely nonexistent id';
  exception when others then if sqlerrm not like 'loyalty_point_adjustment_request_not_found%' then raise; end if;
  end;
end $$;

\echo '>> raw-table RLS/grant defense-in-depth: app.loyalty_point_lots/app.loyalty_point_ledger_entries/app.loyalty_point_balances/app.loyalty_point_adjustment_requests all deny a raw authenticated SELECT outright with a real permission-denied error (not merely RLS-filtered to zero rows)'
do $$
declare
  v_count integer;
begin
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000340010", "role": "authenticated"}';

  begin
    select count(*) into v_count from app.loyalty_point_lots;
    raise exception 'assertion failed: expected a raw authenticated SELECT against app.loyalty_point_lots to be denied, got a row count of %', v_count;
  exception when insufficient_privilege then null;
  end;
  begin
    select count(*) into v_count from app.loyalty_point_ledger_entries;
    raise exception 'assertion failed: expected a raw authenticated SELECT against app.loyalty_point_ledger_entries to be denied, got a row count of %', v_count;
  exception when insufficient_privilege then null;
  end;
  begin
    select count(*) into v_count from app.loyalty_point_balances;
    raise exception 'assertion failed: expected a raw authenticated SELECT against app.loyalty_point_balances to be denied, got a row count of %', v_count;
  exception when insufficient_privilege then null;
  end;
  begin
    select count(*) into v_count from app.loyalty_point_adjustment_requests;
    raise exception 'assertion failed: expected a raw authenticated SELECT against app.loyalty_point_adjustment_requests to be denied, got a row count of %', v_count;
  exception when insufficient_privilege then null;
  end;

  -- Design decision 13 (this migration, CPL-318) originally left
  -- service_role with NO update/delete grant on the append-only ledger
  -- table at all. CPL-325 (CG-S13-CPL-027, ISS-2026-130's own explicit
  -- ruling -- see supabase/migrations/20260801280000_harden_customer_
  -- portal_loyalty_ledger_supreme_admin_override.sql) additively GRANTs
  -- UPDATE/DELETE to service_role -- otherwise a genuine Supreme Admin
  -- (RPD-022's own disclosed absolute-CRUD exception) would have no path
  -- to exercise it at all, since every real mutation in this repository
  -- runs as service_role, never as a database superuser. The functional
  -- guarantee this block originally proved is UNCHANGED, just enforced one
  -- layer deeper now: a BEFORE UPDATE/DELETE trigger
  -- (app.protect_loyalty_ledger_append_only) blocks the mutation outright
  -- unless the acting identity holds a live supreme_admin principal
  -- membership -- proven directly, live, in scripts/db-tests/customer-
  -- portal-loyalty-ledger-supreme-admin-override.sql (this checkpoint's own
  -- dedicated regression file); re-proven here in miniature so this file's
  -- own "raw-table defense in depth" section stays self-contained.
  reset role;
  if not has_table_privilege('service_role', 'app.loyalty_point_ledger_entries', 'UPDATE') then
    raise exception 'assertion failed: service_role should hold UPDATE on app.loyalty_point_ledger_entries as of CPL-325 (20260801280000) -- without it the Supreme Admin override is unreachable';
  end if;
  if not has_table_privilege('service_role', 'app.loyalty_point_ledger_entries', 'DELETE') then
    raise exception 'assertion failed: service_role should hold DELETE on app.loyalty_point_ledger_entries as of CPL-325 (20260801280000) -- without it the Supreme Admin override is unreachable';
  end if;
  -- Holding the grant is not the same as being ABLE to use it: a
  -- non-supreme-admin context (no request.jwt.claims at all here) is still
  -- rejected by the trigger, not by the grant layer.
  begin
    update app.loyalty_point_ledger_entries set amount = amount where false;
    -- WHERE false matches zero rows -- the trigger only fires per row
    -- touched, so this alone would prove nothing; the real proof (a row
    -- that DOES match, blocked) lives in the dedicated file referenced
    -- above. This call only proves the statement itself is not rejected at
    -- the GRANT layer (it is not -- 0 rows updated, no trigger fired, no
    -- error) -- consistent with service_role now holding the grant.
  end;
end $$;

\echo '>> raw-function grant defense in depth: anon holds no EXECUTE on any of the new public functions; authenticated/service_role both do'
do $$
declare
  v_fn text;
  v_has_priv boolean;
begin
  foreach v_fn in array array[
    'app.post_loyalty_point_ledger_entry(uuid, uuid, text, numeric, uuid, text, uuid, text, text, uuid, uuid, text, integer)',
    'app.post_loyalty_points_earned(uuid, uuid, uuid, text, integer)',
    'app.reverse_loyalty_points_earned(uuid, uuid, uuid, text)',
    'app.expire_loyalty_point_lots(uuid, uuid, text, timestamptz)',
    'app.consume_loyalty_points_fifo(uuid, uuid, numeric, text, uuid, text, uuid, text)',
    'app.request_loyalty_point_adjustment(uuid, uuid, numeric, text, text, uuid, text)',
    'app.decide_loyalty_point_adjustment(uuid, uuid, integer, text, text, uuid, text)',
    'app.get_loyalty_point_adjustment_request(uuid, uuid, uuid)',
    'app.list_loyalty_point_adjustment_requests(uuid, uuid, uuid, text, timestamptz, uuid, integer)',
    'app.get_loyalty_point_balance(uuid, uuid, uuid)',
    'app.list_loyalty_point_balances(uuid, uuid, timestamptz, uuid, integer)',
    'app.get_loyalty_point_lot(uuid, uuid, uuid)',
    'app.list_loyalty_point_lots(uuid, uuid, uuid, text, timestamptz, uuid, integer)',
    'app.list_loyalty_point_ledger_entries(uuid, uuid, uuid, text, timestamptz, uuid, integer)',
    'app.list_customer_portal_loyalty_point_balances(uuid, uuid, uuid, timestamptz, uuid, integer)',
    'app.list_customer_portal_loyalty_point_ledger_entries(uuid, uuid, uuid, timestamptz, uuid, integer)',
    'app.list_customer_portal_loyalty_point_expiry_schedule(uuid, uuid, uuid, timestamptz, uuid, integer)'
  ] loop
    select has_function_privilege('anon', v_fn, 'EXECUTE') into v_has_priv;
    if v_has_priv then
      raise exception 'assertion failed: anon must NOT hold EXECUTE on %', v_fn;
    end if;
    select has_function_privilege('authenticated', v_fn, 'EXECUTE') into v_has_priv;
    if not v_has_priv then
      raise exception 'assertion failed: authenticated SHOULD hold EXECUTE on %', v_fn;
    end if;
    select has_function_privilege('service_role', v_fn, 'EXECUTE') into v_has_priv;
    if not v_has_priv then
      raise exception 'assertion failed: service_role SHOULD hold EXECUTE on %', v_fn;
    end if;
  end loop;
end $$;

\echo '>> actor-identity session cross-check: a genuinely different authenticated session may not claim to act as another identity, on every one of the new RPCs'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'pts1');
  v_manager1a uuid := '00000000-0000-0000-0000-000000340001';
  v_impersonator uuid := '00000000-0000-0000-0000-000000340050';
  v_customer_alpha uuid := '00000000-0000-0000-0000-000000340010';
  v_loyalty_account_alpha uuid := (select id from app.loyalty_accounts where tenant_id = (select id from app.tenants where slug = 'pts1') and customer_account_id = (select id from app.accounts where tenant_id = (select id from app.tenants where slug = 'pts1') and legal_name = 'Pts Account Alpha'));
  v_lot_id uuid := (select id from app.loyalty_point_lots where loyalty_account_id = v_loyalty_account_alpha limit 1);
  v_entry_id uuid := (select id from app.loyalty_point_ledger_entries where loyalty_account_id = v_loyalty_account_alpha limit 1);
  v_event_id uuid := (select id from app.loyalty_earning_events where idempotency_key = 'ar-open-item:00000000-0000-0000-0000-000000340101');
  v_request_id uuid := (select id from app.loyalty_point_adjustment_requests where idempotency_key = 'adj-req-1');
begin
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000340050", "role": "authenticated"}';

  begin
    perform app.post_loyalty_point_ledger_entry(v_tenant1, v_loyalty_account_alpha, 'adjustment', 1, null, 'manual_adjustment', gen_random_uuid(), 'imp-1', 'x', null, v_manager1a, 'manager1a');
    raise exception 'assertion failed: expected actor_identity_mismatch on app.post_loyalty_point_ledger_entry';
  exception when others then if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;
  begin
    perform app.post_loyalty_points_earned(v_tenant1, v_event_id, v_manager1a, 'manager1a', 365);
    raise exception 'assertion failed: expected actor_identity_mismatch on app.post_loyalty_points_earned';
  exception when others then if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;
  begin
    perform app.reverse_loyalty_points_earned(v_tenant1, gen_random_uuid(), v_manager1a, 'manager1a');
    raise exception 'assertion failed: expected actor_identity_mismatch on app.reverse_loyalty_points_earned';
  exception when others then if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;
  begin
    perform app.expire_loyalty_point_lots(v_tenant1, v_manager1a, 'manager1a');
    raise exception 'assertion failed: expected actor_identity_mismatch on app.expire_loyalty_point_lots';
  exception when others then if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;
  begin
    perform app.consume_loyalty_points_fifo(v_tenant1, v_loyalty_account_alpha, 1, 'redemption', gen_random_uuid(), 'imp-2', v_manager1a, 'manager1a');
    raise exception 'assertion failed: expected actor_identity_mismatch on app.consume_loyalty_points_fifo';
  exception when others then if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;
  begin
    perform app.request_loyalty_point_adjustment(v_tenant1, v_loyalty_account_alpha, 1, 'x', 'imp-3', v_manager1a, 'manager1a');
    raise exception 'assertion failed: expected actor_identity_mismatch on app.request_loyalty_point_adjustment';
  exception when others then if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;
  begin
    perform app.decide_loyalty_point_adjustment(v_tenant1, v_request_id, 1, 'approved', 'x', v_manager1a, 'manager1a');
    raise exception 'assertion failed: expected actor_identity_mismatch on app.decide_loyalty_point_adjustment';
  exception when others then if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;
  begin
    perform app.get_loyalty_point_adjustment_request(v_tenant1, v_request_id, v_manager1a);
    raise exception 'assertion failed: expected actor_identity_mismatch on app.get_loyalty_point_adjustment_request';
  exception when others then if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;
  begin
    perform app.list_loyalty_point_adjustment_requests(v_tenant1, v_manager1a);
    raise exception 'assertion failed: expected actor_identity_mismatch on app.list_loyalty_point_adjustment_requests';
  exception when others then if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;
  begin
    perform app.get_loyalty_point_balance(v_tenant1, v_loyalty_account_alpha, v_manager1a);
    raise exception 'assertion failed: expected actor_identity_mismatch on app.get_loyalty_point_balance';
  exception when others then if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;
  begin
    perform app.list_loyalty_point_balances(v_tenant1, v_manager1a);
    raise exception 'assertion failed: expected actor_identity_mismatch on app.list_loyalty_point_balances';
  exception when others then if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;
  begin
    perform app.get_loyalty_point_lot(v_tenant1, v_lot_id, v_manager1a);
    raise exception 'assertion failed: expected actor_identity_mismatch on app.get_loyalty_point_lot';
  exception when others then if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;
  begin
    perform app.list_loyalty_point_lots(v_tenant1, v_manager1a);
    raise exception 'assertion failed: expected actor_identity_mismatch on app.list_loyalty_point_lots';
  exception when others then if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;
  begin
    perform app.list_loyalty_point_ledger_entries(v_tenant1, v_manager1a);
    raise exception 'assertion failed: expected actor_identity_mismatch on app.list_loyalty_point_ledger_entries';
  exception when others then if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;
  begin
    perform app.list_customer_portal_loyalty_point_balances(v_tenant1, v_customer_alpha);
    raise exception 'assertion failed: expected actor_identity_mismatch on app.list_customer_portal_loyalty_point_balances';
  exception when others then if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;
  begin
    perform app.list_customer_portal_loyalty_point_ledger_entries(v_tenant1, v_customer_alpha);
    raise exception 'assertion failed: expected actor_identity_mismatch on app.list_customer_portal_loyalty_point_ledger_entries';
  exception when others then if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;
  begin
    perform app.list_customer_portal_loyalty_point_expiry_schedule(v_tenant1, v_customer_alpha);
    raise exception 'assertion failed: expected actor_identity_mismatch on app.list_customer_portal_loyalty_point_expiry_schedule';
  exception when others then if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;

  -- A real session correctly acting as ITSELF (impersonator holds Manager
  -- A's own role too) is NOT rejected -- succeeds on its own authority,
  -- proving the identity check and the authority check are independent
  -- gates.
  perform app.get_loyalty_point_lot(v_tenant1, v_lot_id, v_impersonator);

  reset role;
end $$;

\echo '>> a real, live authenticated-role positive path: Alpha''s own real authenticated session sees the exact same result a direct superuser call returns'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'pts1');
  v_customer_alpha uuid := '00000000-0000-0000-0000-000000340010';
  v_superuser_count integer;
  v_session_count integer;
begin
  select count(*) into v_superuser_count from app.list_customer_portal_loyalty_point_ledger_entries(v_tenant1, v_customer_alpha, p_limit => 200);

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000340010", "role": "authenticated"}';
  select count(*) into v_session_count from app.list_customer_portal_loyalty_point_ledger_entries(v_tenant1, v_customer_alpha, p_limit => 200);
  reset role;

  if v_session_count <> v_superuser_count or v_session_count = 0 then
    raise exception 'assertion failed: expected a real authenticated session to see the identical, non-zero row count (%) a direct superuser call returns, got % via session', v_superuser_count, v_session_count;
  end if;
end $$;

\echo '>> keyset pagination on app.list_loyalty_point_ledger_entries: visits every row exactly once at limit=1, never OFFSET; a half-supplied cursor fails loud'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'pts1');
  v_manager1a uuid := '00000000-0000-0000-0000-000000340001';
  v_cursor_created_at timestamptz := null;
  v_cursor_id uuid := null;
  v_page app.loyalty_point_ledger_entries[];
  v_seen_count integer := 0;
  v_total_pages integer := 0;
  v_row app.loyalty_point_ledger_entries;
  v_expected_count integer;
begin
  select count(*) into v_expected_count from app.loyalty_point_ledger_entries where tenant_id = v_tenant1;

  loop
    v_page := array(select app.list_loyalty_point_ledger_entries(v_tenant1, v_manager1a, p_cursor_created_at => v_cursor_created_at, p_cursor_id => v_cursor_id, p_limit => 1));
    exit when array_length(v_page, 1) is null;
    foreach v_row in array v_page loop
      v_seen_count := v_seen_count + 1;
      v_cursor_created_at := v_row.created_at;
      v_cursor_id := v_row.id;
    end loop;
    v_total_pages := v_total_pages + 1;
    if v_total_pages > 100 then
      raise exception 'assertion failed: keyset pagination did not terminate within 100 pages';
    end if;
  end loop;
  if v_seen_count <> v_expected_count then
    raise exception 'assertion failed: expected keyset pagination to visit every one of % rows exactly once, saw %', v_expected_count, v_seen_count;
  end if;

  begin
    perform app.list_loyalty_point_ledger_entries(v_tenant1, v_manager1a, p_cursor_id => gen_random_uuid());
    raise exception 'assertion failed: expected invalid_cursor -- p_cursor_id supplied without p_cursor_created_at';
  exception when others then if sqlerrm not like 'invalid_cursor%' then raise; end if;
  end;
end $$;

-- ===========================================================================
-- DRAFT / RESEARCH ONLY -- Track B Batch 4, ISS-2026-128 item 2 candidate
-- fix regression block, added alongside supabase/migrations/20260828000000_
-- create_loyalty_point_program_expiry_config.sql. NOT yet integrated into
-- the mainline migration/db-test sequence.
-- ===========================================================================

\echo '>> ISS-2026-128 item 2 fix: app.get_loyalty_point_program_expiry_config returns a NULL-shaped row (not an error) when no override has ever been set for a program'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'pts1');
  v_manager1a uuid := '00000000-0000-0000-0000-000000340001';
  v_program_id uuid := (select id from app.loyalty_programs where tenant_id = (select id from app.tenants where slug = 'pts1') and name = 'Points Rewards');
  v_config app.loyalty_point_program_configs;
begin
  v_config := app.get_loyalty_point_program_expiry_config(v_tenant1, v_program_id, v_manager1a);
  if v_config.id is not null then
    raise exception 'assertion failed: expected a NULL-shaped row before any config is ever set, got %', v_config;
  end if;
end $$;

\echo '>> ISS-2026-128 item 2 fix: app.set_loyalty_point_program_expiry_config -- bounded (1-3650), LYL:Configure required, program must belong to the caller''s own tenant, upsert never creates a second row'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'pts1');
  v_manager1a uuid := '00000000-0000-0000-0000-000000340001';
  v_viewer1 uuid := '00000000-0000-0000-0000-000000340003';
  v_plain1 uuid := '00000000-0000-0000-0000-000000340004';
  v_program_id uuid := (select id from app.loyalty_programs where tenant_id = (select id from app.tenants where slug = 'pts1') and name = 'Points Rewards');
  v_config app.loyalty_point_program_configs;
  v_row_count integer;
begin
  begin
    perform app.set_loyalty_point_program_expiry_config(v_tenant1, v_program_id, 45, v_viewer1, 'viewer1');
    raise exception 'assertion failed: expected insufficient_authority for Loyalty Viewer (LYL:View only, no Configure)';
  exception when others then if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  begin
    perform app.set_loyalty_point_program_expiry_config(v_tenant1, v_program_id, 0, v_manager1a, 'manager1a');
    raise exception 'assertion failed: expected invalid_expiry_days for 0 days';
  exception when others then if sqlerrm not like 'invalid_expiry_days%' then raise; end if;
  end;
  begin
    perform app.set_loyalty_point_program_expiry_config(v_tenant1, v_program_id, 3651, v_manager1a, 'manager1a');
    raise exception 'assertion failed: expected invalid_expiry_days for 3651 days';
  exception when others then if sqlerrm not like 'invalid_expiry_days%' then raise; end if;
  end;

  begin
    perform app.set_loyalty_point_program_expiry_config(v_tenant1, gen_random_uuid(), 45, v_manager1a, 'manager1a');
    raise exception 'assertion failed: expected loyalty_program_not_found for a nonexistent program id';
  exception when others then if sqlerrm not like 'loyalty_program_not_found%' then raise; end if;
  end;

  v_config := app.set_loyalty_point_program_expiry_config(v_tenant1, v_program_id, 45, v_manager1a, 'manager1a');
  if v_config.points_expiry_days <> 45 then
    raise exception 'assertion failed: expected points_expiry_days=45, got %', v_config;
  end if;

  v_config := app.get_loyalty_point_program_expiry_config(v_tenant1, v_program_id, v_manager1a);
  if v_config.points_expiry_days <> 45 then
    raise exception 'assertion failed: expected get_ to now return points_expiry_days=45, got %', v_config;
  end if;

  -- Upsert: re-setting the SAME (tenant, program) updates in place, never a
  -- second row.
  v_config := app.set_loyalty_point_program_expiry_config(v_tenant1, v_program_id, 90, v_manager1a, 'manager1a');
  if v_config.points_expiry_days <> 90 then
    raise exception 'assertion failed: expected upsert to update points_expiry_days to 90, got %', v_config;
  end if;
  select count(*) into v_row_count from app.loyalty_point_program_configs where tenant_id = v_tenant1 and program_id = v_program_id;
  if v_row_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 config row per (tenant, program) after upsert, got %', v_row_count;
  end if;

  begin
    perform app.get_loyalty_point_program_expiry_config(v_tenant1, v_program_id, v_plain1);
    raise exception 'assertion failed: expected insufficient_authority for Plain User (no LYL grant) on get_';
  exception when others then if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;
end $$;

\echo '>> ISS-2026-128 item 2 fix: app.post_loyalty_points_earned -- an explicit p_expiry_days still wins outright over a persisted config; a NULL/omitted p_expiry_days resolves to the persisted config (90d, set above) when one exists, and still falls back to the legacy 365d system default for a program with no persisted config'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'pts1');
  v_tenant2 uuid := (select id from app.tenants where slug = 'pts2');
  v_manager1a uuid := '00000000-0000-0000-0000-000000340001';
  v_manager2 uuid := '00000000-0000-0000-0000-000000341001';
  v_account_alpha uuid := (select id from app.accounts where tenant_id = (select id from app.tenants where slug = 'pts1') and legal_name = 'Pts Account Alpha');
  v_account_delta uuid := (select id from app.accounts where tenant_id = (select id from app.tenants where slug = 'pts2') and legal_name = 'Pts Account Delta');
  v_event_configured uuid;
  v_event_override uuid;
  v_event_unconfigured uuid;
  v_entry app.loyalty_point_ledger_entries;
  v_lot app.loyalty_point_lots;
  v_days_until_expiry numeric;
begin
  -- A fresh paid invoice/earning event for Alpha (tenant1, program has a
  -- persisted 90-day config set above), converted with NO p_expiry_days
  -- argument at all (relying on the widened default of NULL).
  insert into app.finance_ar_open_items (id, tenant_id, customer_account_id, source_document_type, source_document_id, currency, original_amount, allocated_amount, status, is_held, invoice_date, due_date, created_by) values
    ('00000000-0000-0000-0000-000000340106', v_tenant1, v_account_alpha, 'invoice', '00000000-0000-0000-0000-000000340206', 'USD', 40, 40, 'paid', false, '2026-08-06', '2026-09-05', 'tester');
  perform app.evaluate_customer_loyalty_earning_for_paid_invoice(v_tenant1, '00000000-0000-0000-0000-000000340106', v_manager1a, 'manager1a');
  v_event_configured := (select id from app.loyalty_earning_events where idempotency_key = 'ar-open-item:00000000-0000-0000-0000-000000340106');

  v_entry := app.post_loyalty_points_earned(v_tenant1, v_event_configured, v_manager1a, 'manager1a');
  v_lot := (select l from app.loyalty_point_lots l where l.source_earning_event_id = v_event_configured);
  v_days_until_expiry := extract(epoch from (v_lot.expires_at - clock_timestamp())) / 86400.0;
  if v_days_until_expiry < 89 or v_days_until_expiry > 91 then
    raise exception 'assertion failed: expected the persisted 90-day config to apply when p_expiry_days is omitted, got a lot expiring in % days (expires_at=%)', v_days_until_expiry, v_lot.expires_at;
  end if;

  -- A second fresh event for Alpha, this time with an EXPLICIT override
  -- (7 days) -- must win outright over the persisted 90-day config.
  insert into app.finance_ar_open_items (id, tenant_id, customer_account_id, source_document_type, source_document_id, currency, original_amount, allocated_amount, status, is_held, invoice_date, due_date, created_by) values
    ('00000000-0000-0000-0000-000000340107', v_tenant1, v_account_alpha, 'invoice', '00000000-0000-0000-0000-000000340207', 'USD', 15, 15, 'paid', false, '2026-08-07', '2026-09-06', 'tester');
  perform app.evaluate_customer_loyalty_earning_for_paid_invoice(v_tenant1, '00000000-0000-0000-0000-000000340107', v_manager1a, 'manager1a');
  v_event_override := (select id from app.loyalty_earning_events where idempotency_key = 'ar-open-item:00000000-0000-0000-0000-000000340107');

  perform app.post_loyalty_points_earned(v_tenant1, v_event_override, v_manager1a, 'manager1a', 7);
  v_lot := (select l from app.loyalty_point_lots l where l.source_earning_event_id = v_event_override);
  v_days_until_expiry := extract(epoch from (v_lot.expires_at - clock_timestamp())) / 86400.0;
  if v_days_until_expiry < 6 or v_days_until_expiry > 8 then
    raise exception 'assertion failed: expected an explicit p_expiry_days=7 to win outright over the persisted 90-day config, got a lot expiring in % days (expires_at=%)', v_days_until_expiry, v_lot.expires_at;
  end if;

  -- Tenant2's own program (v_program2_id) has never had a config row set --
  -- omitting p_expiry_days must still fall back to the original 365-day
  -- system default, unchanged (backward-compatibility regression proof).
  insert into app.finance_ar_open_items (id, tenant_id, customer_account_id, source_document_type, source_document_id, currency, original_amount, allocated_amount, status, is_held, invoice_date, due_date, created_by) values
    ('00000000-0000-0000-0000-000000341102', v_tenant2, v_account_delta, 'invoice', '00000000-0000-0000-0000-000000341202', 'USD', 25, 25, 'paid', false, '2026-08-02', '2026-09-01', 'tester');
  perform app.evaluate_customer_loyalty_earning_for_paid_invoice(v_tenant2, '00000000-0000-0000-0000-000000341102', v_manager2, 'manager2');
  v_event_unconfigured := (select id from app.loyalty_earning_events where idempotency_key = 'ar-open-item:00000000-0000-0000-0000-000000341102');

  perform app.post_loyalty_points_earned(v_tenant2, v_event_unconfigured, v_manager2, 'manager2');
  v_lot := (select l from app.loyalty_point_lots l where l.source_earning_event_id = v_event_unconfigured);
  v_days_until_expiry := extract(epoch from (v_lot.expires_at - clock_timestamp())) / 86400.0;
  if v_days_until_expiry < 364 or v_days_until_expiry > 366 then
    raise exception 'assertion failed: expected the unchanged 365-day system default for a program with no persisted config, got a lot expiring in % days (expires_at=%)', v_days_until_expiry, v_lot.expires_at;
  end if;
end $$;

\echo '>> ISS-2026-128 item 2 fix: raw-function grant defense in depth -- anon holds no EXECUTE on either new function; authenticated/service_role both do'
do $$
declare
  v_fn text;
  v_has_priv boolean;
begin
  foreach v_fn in array array[
    'app.set_loyalty_point_program_expiry_config(uuid, uuid, integer, uuid, text)',
    'app.get_loyalty_point_program_expiry_config(uuid, uuid, uuid)'
  ] loop
    select has_function_privilege('anon', v_fn, 'EXECUTE') into v_has_priv;
    if v_has_priv then
      raise exception 'assertion failed: anon must NOT hold EXECUTE on %', v_fn;
    end if;
    select has_function_privilege('authenticated', v_fn, 'EXECUTE') into v_has_priv;
    if not v_has_priv then
      raise exception 'assertion failed: authenticated SHOULD hold EXECUTE on %', v_fn;
    end if;
    select has_function_privilege('service_role', v_fn, 'EXECUTE') into v_has_priv;
    if not v_has_priv then
      raise exception 'assertion failed: service_role SHOULD hold EXECUTE on %', v_fn;
    end if;
  end loop;
end $$;

\echo '>> ISS-2026-128 item 2 fix: actor-identity session cross-check on both new RPCs'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'pts1');
  v_manager1a uuid := '00000000-0000-0000-0000-000000340001';
  v_program_id uuid := (select id from app.loyalty_programs where tenant_id = (select id from app.tenants where slug = 'pts1') and name = 'Points Rewards');
begin
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000340050", "role": "authenticated"}';

  begin
    perform app.set_loyalty_point_program_expiry_config(v_tenant1, v_program_id, 45, v_manager1a, 'manager1a');
    raise exception 'assertion failed: expected actor_identity_mismatch on app.set_loyalty_point_program_expiry_config';
  exception when others then if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;
  begin
    perform app.get_loyalty_point_program_expiry_config(v_tenant1, v_program_id, v_manager1a);
    raise exception 'assertion failed: expected actor_identity_mismatch on app.get_loyalty_point_program_expiry_config';
  exception when others then if sqlerrm not like 'actor_identity_mismatch%' then raise; end if;
  end;
end $$;

\echo '>> ISS-2026-128 item 1: the points-posting SWEEP -- converts every points-type earning event with no lot yet, reads "already posted" from the lot link posting itself creates, and never overrides the per-programme expiry window item 2 introduced'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'pts1');
  v_tenant2 uuid := (select id from app.tenants where slug = 'pts2');
  v_manager1a uuid := '00000000-0000-0000-0000-000000340001';
  v_viewer1 uuid := '00000000-0000-0000-0000-000000340003';
  v_manager2 uuid := '00000000-0000-0000-0000-000000341001';
  v_account_alpha uuid := (select customer_account_id from app.finance_ar_open_items where id = '00000000-0000-0000-0000-000000340101');
  v_candidates integer;
  v_remaining integer;
  v_t2_lots_before integer;
  v_t2_lots_after integer;
  v_row record;
  v_repeat record;
begin
  -- A guaranteed-postable candidate, created here rather than relied on from whatever the
  -- earlier blocks happened to leave behind. A sweep test whose "did it post anything?"
  -- assertion depends on fixture leftovers passes or fails for reasons that have nothing to
  -- do with the sweep -- which is exactly how the first draft of this block failed.
  insert into app.finance_ar_open_items (id, tenant_id, customer_account_id, source_document_type, source_document_id, currency, original_amount, allocated_amount, status, is_held, invoice_date, due_date, created_by) values
    ('00000000-0000-0000-0000-000000340108', v_tenant1, v_account_alpha, 'invoice', '00000000-0000-0000-0000-000000340208', 'USD', 55, 55, 'paid', false, '2026-08-08', '2026-09-07', 'tester');
  perform app.evaluate_customer_loyalty_earning_for_paid_invoice(v_tenant1, '00000000-0000-0000-0000-000000340108', v_manager1a, 'manager1a');

  select count(*) into v_candidates
  from app.loyalty_earning_events e
  where e.tenant_id = v_tenant1 and e.reward_type = 'points'
    and not exists (select 1 from app.loyalty_point_lots l where l.tenant_id = v_tenant1 and l.source_earning_event_id = e.id);
  if v_candidates = 0 then
    raise exception 'assertion failed: the earning event just created must be an unposted candidate for the sweep to find';
  end if;
  select count(*) into v_t2_lots_before from app.loyalty_point_lots where tenant_id = v_tenant2;

  select * into v_row from app.run_loyalty_points_posting_sweep(v_tenant1, now(), v_manager1a, 'manager1a', 'iss128-run-a');

  if v_row.processed_count + v_row.skipped_count <> v_candidates then
    raise exception 'assertion failed: expected every one of % candidates accounted for, got % processed + % skipped', v_candidates, v_row.processed_count, v_row.skipped_count;
  end if;
  if v_row.status <> 'completed' or v_row.processed_count = 0 then
    raise exception 'assertion failed: expected a completed sweep that posted at least one lot, got status % / processed %', v_row.status, v_row.processed_count;
  end if;

  select count(*) into v_remaining
  from app.loyalty_earning_events e
  where e.tenant_id = v_tenant1 and e.reward_type = 'points'
    and not exists (select 1 from app.loyalty_point_lots l where l.tenant_id = v_tenant1 and l.source_earning_event_id = e.id);
  if v_remaining <> v_row.skipped_count then
    raise exception 'assertion failed: what remains unposted (%) must be exactly what the sweep skipped (%)', v_remaining, v_row.skipped_count;
  end if;

  select count(*) into v_t2_lots_after from app.loyalty_point_lots where tenant_id = v_tenant2;
  if v_t2_lots_after <> v_t2_lots_before then
    raise exception 'assertion failed: a tenant1 sweep created % tenant2 point lots', v_t2_lots_after - v_t2_lots_before;
  end if;

  -- A second sweep under a NEW label must find nothing left: proof that "already posted" is
  -- genuinely read from the lot link rather than from anything that could drift from it.
  select * into v_repeat from app.run_loyalty_points_posting_sweep(v_tenant1, now(), v_manager1a, 'manager1a', 'iss128-run-b');
  if v_repeat.processed_count <> 0 then
    raise exception 'assertion failed: a second sweep must find nothing left to post, got % processed -- the already-posted filter is not holding', v_repeat.processed_count;
  end if;

  begin
    perform app.run_loyalty_points_posting_sweep(v_tenant1, now(), v_viewer1, 'viewer1', 'iss128-denied');
    raise exception 'assertion failed: expected insufficient_authority -- LYL:View alone must not start a points-posting sweep';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  begin
    perform app.run_loyalty_points_posting_sweep(v_tenant1, now(), v_manager2, 'manager2', 'iss128-crosstenant');
    raise exception 'assertion failed: expected insufficient_authority -- a tenant2 manager must not sweep tenant1';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  raise notice 'PASS: points sweep posted % of % candidates, left nothing eligible behind, stayed inside its tenant, and a second run is a genuine no-op', v_row.processed_count, v_candidates;
end $$;

\echo '>> ISS-2026-128: the sweep passes NO expiry-days override, so every lot it creates carries the per-programme window item 2 introduced -- a scheduler default here would quietly undo that fix'
do $$
declare
  v_src text;
begin
  select p.prosrc into v_src from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'app' and p.proname = 'run_loyalty_points_posting_sweep';
  if v_src is null then
    raise exception 'assertion failed: app.run_loyalty_points_posting_sweep not found';
  end if;
  -- Four arguments, not five: p_expiry_days is deliberately left to the RPC's own
  -- per-programme resolution (20260828000000).
  if v_src not like '%post_loyalty_points_earned(p_tenant_id, v_candidate.id, p_actor_auth_user_id, p_actor_label)%' then
    raise exception 'assertion failed: the sweep must call post_loyalty_points_earned WITHOUT an expiry-days argument, so the per-programme window resolves; body was %', v_src;
  end if;
  raise notice 'PASS: the points sweep defers the expiry window to per-programme configuration';
end $$;

\echo 'ALL PASSED: CPL-318 Points Ledger (+ ISS-2026-128 item 2 draft fix regression block)'
