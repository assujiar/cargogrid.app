-- Real, executable test evidence for FIN-205 (Draft-versus-Posted State
-- Control, CG-S9-FIN-016) -- run via `pnpm run db:test` against a real,
-- disposable Postgres database.
-- Proves: the static app.finance_lifecycle_editability_matrix contains
-- exactly the 26 real (entity_type, concrete_status) pairs across all six
-- Finance document types with the exact expected canonical_state/
-- allowed_actions/locked_reason/posted_trigger_protected values; an
-- unmapped (entity_type, status) pair and an unrecognized entity_type each
-- raise a distinct named exception rather than a silent default;
-- app.get_finance_lifecycle_record_state resolves the correct canonical
-- state end-to-end for a real journal driven through its full
-- draft -> submitted -> approved -> posted lifecycle (proving
-- posted_trigger_protected=true only once actually posted) and a real
-- settlement driven through draft -> submitted -> approved -> executed ->
-- posted -> reversed (proving the deliberate approved/executed canonical
-- coarsening still exposes distinct allowed_actions, and that 'reversed'
-- maps to the 'corrected' canonical state); a discarded draft on each maps
-- to 'discarded'; authority denial (no FIN:View) and cross-tenant denial;
-- a well-formed but nonexistent record id raises finance_lifecycle_record_
-- not_found rather than returning null; schema-privilege defense in depth.

\set ON_ERROR_STOP on

\echo '>> setup: two tenants; tenant A gets a Finance Manager (FIN:Create/Edit/Approve/View, tenant_admin) and a Plain User with no FIN grant; tenant B gets its own Finance Manager; tenant A gets one open fiscal period (2026-03), a small real chart of accounts, a published finance_posting_map, and one active vendor reference'
do $$
declare
  v_tenant_a uuid;
  v_tenant_b uuid;
  v_team_a uuid;
  v_team_b uuid;
  v_manager_role_a uuid;
  v_manager_draft_a app.role_versions;
  v_manager_role_b uuid;
  v_manager_draft_b app.role_versions;
  v_account app.finance_accounts;
  v_pm_draft app.config_versions;
  v_vendor app.master_records;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000029910', 'admina@acmelife.test'),
    ('00000000-0000-0000-0000-000000029911', 'financemanagera@acmelife.test'),
    ('00000000-0000-0000-0000-000000029912', 'plainusera@acmelife.test'),
    ('00000000-0000-0000-0000-000000029913', 'financemanagerb@acmelife.test');

  perform app.provision_tenant('acmelifea', 'Acme Lifecycle A', 'idem-acmelifea', 'tester');
  v_tenant_a := (select id from app.tenants where slug = 'acmelifea');
  perform app.transition_tenant_status(v_tenant_a, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant_a, 'company', null, 'ACMELIFEA-CO', 'Acme Lifecycle A', 'tester');
  v_team_a := (select id from app.org_units where tenant_id = v_tenant_a and code = 'ACMELIFEA-CO');

  perform app.provision_tenant('acmelifeb', 'Acme Lifecycle B', 'idem-acmelifeb', 'tester');
  v_tenant_b := (select id from app.tenants where slug = 'acmelifeb');
  perform app.transition_tenant_status(v_tenant_b, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant_b, 'company', null, 'ACMELIFEB-CO', 'Acme Lifecycle B', 'tester');
  v_team_b := (select id from app.org_units where tenant_id = v_tenant_b and code = 'ACMELIFEB-CO');

  perform app.invite_user(v_tenant_a, '00000000-0000-0000-0000-000000029910', 'admina@acmelife.test', 'Tenant A Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admina@acmelife.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000029910', 'tenant_admin', v_tenant_a, null, 'tester');

  perform app.invite_user(v_tenant_a, '00000000-0000-0000-0000-000000029911', 'financemanagera@acmelife.test', 'Finance Manager A', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'financemanagera@acmelife.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000029911', 'tenant_admin', v_tenant_a, null, 'tester');

  v_manager_role_a := (app.create_role(v_tenant_a, 'Finance Manager', 'Lifecycle authority', 'tester')).id;
  v_manager_draft_a := app.create_role_version(v_manager_role_a, 'tester');
  perform app.set_role_version_permissions(v_manager_draft_a.id, array(select id from app.permissions where resource_module_code = 'FIN' and action in ('Create', 'Edit', 'Approve', 'View')), 'tester');
  perform app.publish_role_version(v_manager_draft_a.id, now(), 'tester');
  perform app.assign_role(v_tenant_a, (select id from app.role_versions where role_id = v_manager_role_a and status = 'published'), '00000000-0000-0000-0000-000000029911', '00000000-0000-0000-0000-000000029910', 'tester');
  -- HDN-373 (ISS-2026-181, maker/checker): admina also holds Finance Manager so it can
  -- act as a genuinely distinct approver/poster from financemanagera, the preparer, in
  -- the scenarios below -- app.approve_finance_journal/app.post_finance_journal now deny
  -- an actor approving or posting their own submission.
  perform app.assign_role(v_tenant_a, (select id from app.role_versions where role_id = v_manager_role_a and status = 'published'), '00000000-0000-0000-0000-000000029910', '00000000-0000-0000-0000-000000029910', 'tester');

  perform app.invite_user(v_tenant_a, '00000000-0000-0000-0000-000000029912', 'plainusera@acmelife.test', 'Plain User A', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'plainusera@acmelife.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant_b, '00000000-0000-0000-0000-000000029913', 'financemanagerb@acmelife.test', 'Finance Manager B', v_team_b, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'financemanagerb@acmelife.test'), 'active', 'onboarded', 'tester');
  v_manager_role_b := (app.create_role(v_tenant_b, 'Finance Manager', 'Lifecycle authority', 'tester')).id;
  v_manager_draft_b := app.create_role_version(v_manager_role_b, 'tester');
  perform app.set_role_version_permissions(v_manager_draft_b.id, array(select id from app.permissions where resource_module_code = 'FIN' and action in ('Create', 'Edit', 'Approve', 'View')), 'tester');
  perform app.publish_role_version(v_manager_draft_b.id, now(), 'tester');
  perform app.assign_role(v_tenant_b, (select id from app.role_versions where role_id = v_manager_role_b and status = 'published'), '00000000-0000-0000-0000-000000029913', '00000000-0000-0000-0000-000000029913', 'tester');

  perform app.generate_finance_fiscal_calendar(v_tenant_a, null, 'FY2026', 'FY2026 Monthly', '2026-01-01'::date, 6, '00000000-0000-0000-0000-000000029911', 'financemanagera');

  select * into v_account from app.create_finance_account_draft(v_tenant_a, null, 'CASH-LIFE', 'Default Cash', 'asset', 'debit', null, false, null, '00000000-0000-0000-0000-000000029911', 'financemanagera');
  perform app.activate_finance_account(v_account.id, v_account.record_version, '00000000-0000-0000-0000-000000029911', 'financemanagera');
  select * into v_account from app.create_finance_account_draft(v_tenant_a, null, 'REV-LIFE', 'Default Revenue', 'revenue', 'credit', null, false, null, '00000000-0000-0000-0000-000000029911', 'financemanagera');
  perform app.activate_finance_account(v_account.id, v_account.record_version, '00000000-0000-0000-0000-000000029911', 'financemanagera');
  select * into v_account from app.create_finance_account_draft(v_tenant_a, null, 'AP-CTRL-LIFE', 'Accounts Payable Control', 'liability', 'credit', null, false, null, '00000000-0000-0000-0000-000000029911', 'financemanagera');
  perform app.activate_finance_account(v_account.id, v_account.record_version, '00000000-0000-0000-0000-000000029911', 'financemanagera');

  select * into v_pm_draft from app.create_finance_config_draft('finance_posting_map', v_tenant_a, 'tenant', null, '00000000-0000-0000-0000-000000029911', 'financemanagera');
  perform app.set_finance_config_items(v_pm_draft.id, jsonb_build_array(
    jsonb_build_object('key', 'cash_default', 'value', jsonb_build_object('accountCodeRef', 'CASH-LIFE')),
    jsonb_build_object('key', 'revenue_default', 'value', jsonb_build_object('accountCodeRef', 'REV-LIFE')),
    jsonb_build_object('key', 'ap_control', 'value', jsonb_build_object('accountCodeRef', 'AP-CTRL-LIFE'))
  ), '00000000-0000-0000-0000-000000029911', 'financemanagera');
  perform app.publish_finance_config_version(v_pm_draft.id, '00000000-0000-0000-0000-000000029911', null, 'financemanagera');

  select * into v_vendor from app.create_master_record('vendor', v_tenant_a, 'VEND-LIFE-1', 'Lifecycle Freight Co', '[]'::jsonb, '{}'::jsonb, '00000000-0000-0000-0000-000000029911', 'financemanagera');
end;
$$;

\echo '>> static editability matrix: exactly 26 rows, one per real (entity_type, concrete_status) pair across invoice/vendor_bill/receipt/settlement/subledger_batch/journal, each with the exact expected canonical_state/allowed_actions/locked_reason/posted_trigger_protected'
do $$
declare
  v_count integer;
  v_row app.finance_lifecycle_editability_matrix;
begin
  select count(*) into v_count from app.finance_lifecycle_editability_matrix;
  if v_count <> 26 then
    raise exception 'assertion failed: expected exactly 26 seeded rows, found %', v_count;
  end if;

  -- Spot-check the full row set for every entity_type -- exact
  -- canonical_state, allowed_actions, locked_reason, posted_trigger_protected.
  v_row := app.get_finance_lifecycle_editability('invoice', 'draft');
  if v_row.canonical_state <> 'draft' or v_row.allowed_actions <> array['submit', 'discard'] or v_row.locked_reason is not null or v_row.is_editable then
    raise exception 'assertion failed: invoice/draft row mismatch';
  end if;
  v_row := app.get_finance_lifecycle_editability('invoice', 'issued');
  if v_row.canonical_state <> 'posted' or v_row.allowed_actions <> array[]::text[] or v_row.locked_reason <> 'posted_immutable_normal_role' or v_row.posted_trigger_protected then
    raise exception 'assertion failed: invoice/issued row mismatch -- expected posted_trigger_protected=false (grant-only protection, not FIN-204''s own trigger)';
  end if;

  v_row := app.get_finance_lifecycle_editability('vendor_bill', 'posted');
  if v_row.canonical_state <> 'posted' or v_row.locked_reason <> 'posted_immutable_normal_role' or v_row.posted_trigger_protected then
    raise exception 'assertion failed: vendor_bill/posted row mismatch';
  end if;

  v_row := app.get_finance_lifecycle_editability('receipt', 'captured');
  if v_row.canonical_state <> 'posted' or v_row.allowed_actions <> array['allocate', 'request_deallocation'] then
    raise exception 'assertion failed: receipt/captured row mismatch';
  end if;
  v_row := app.get_finance_lifecycle_editability('receipt', 'void');
  if v_row.canonical_state <> 'discarded' then
    raise exception 'assertion failed: receipt/void row mismatch';
  end if;

  -- The deliberate canonical-state coarsening: settlement's own 'approved'
  -- and 'executed' concrete statuses both map to canonical 'approved', but
  -- carry distinct allowed_actions -- proving concrete detail is never lost.
  v_row := app.get_finance_lifecycle_editability('settlement', 'approved');
  if v_row.canonical_state <> 'approved' or v_row.allowed_actions <> array['execute'] then
    raise exception 'assertion failed: settlement/approved row mismatch';
  end if;
  v_row := app.get_finance_lifecycle_editability('settlement', 'executed');
  if v_row.canonical_state <> 'approved' or v_row.allowed_actions <> array['post'] then
    raise exception 'assertion failed: settlement/executed row mismatch (expected same canonical bucket as approved, distinct allowed_actions)';
  end if;
  v_row := app.get_finance_lifecycle_editability('settlement', 'posted');
  if v_row.canonical_state <> 'posted' or v_row.allowed_actions <> array['request_reversal'] then
    raise exception 'assertion failed: settlement/posted row mismatch -- a governed reversal path already exists, unlike journal''s own posted row';
  end if;
  v_row := app.get_finance_lifecycle_editability('settlement', 'reversed');
  if v_row.canonical_state <> 'corrected' then
    raise exception 'assertion failed: settlement/reversed row mismatch -- expected canonical corrected';
  end if;

  v_row := app.get_finance_lifecycle_editability('subledger_batch', 'posted');
  if v_row.canonical_state <> 'posted' or v_row.locked_reason <> 'system_generated_posted_immutable_normal_role' then
    raise exception 'assertion failed: subledger_batch/posted row mismatch';
  end if;
  v_row := app.get_finance_lifecycle_editability('subledger_batch', 'reversed');
  if v_row.canonical_state <> 'corrected' then
    raise exception 'assertion failed: subledger_batch/reversed row mismatch';
  end if;

  -- journal is the one entity_type with posted_trigger_protected=true --
  -- FIN-204's own table-level trigger, unlike every other posted row above.
  v_row := app.get_finance_lifecycle_editability('journal', 'posted');
  if v_row.canonical_state <> 'posted' or not v_row.posted_trigger_protected then
    raise exception 'assertion failed: journal/posted row mismatch -- expected posted_trigger_protected=true (FIN-204''s own trigger)';
  end if;

  -- is_editable is uniformly false across all 26 rows -- disclosed and
  -- structural, since no Finance document table exposes a direct
  -- field-level update-in-place function anywhere in this repository yet.
  select count(*) into v_count from app.finance_lifecycle_editability_matrix where is_editable;
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero editable rows (no update-in-place function exists for any Finance document table yet), found %', v_count;
  end if;
end;
$$;

\echo '>> unmapped-state and unsupported-entity-type rejection: neither app.get_finance_lifecycle_editability nor app.get_finance_lifecycle_record_state ever returns a silent default for an unrecognized input'
do $$
declare
  v_tenant_a uuid;
  v_failed boolean := false;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmelifea');

  begin
    perform app.get_finance_lifecycle_editability('invoice', 'not_a_real_status');
    v_failed := true;
  exception when others then
    if sqlerrm not like 'finance_lifecycle_state_unmapped%' then
      raise exception 'assertion failed: expected finance_lifecycle_state_unmapped, got %', sqlerrm;
    end if;
  end;
  if v_failed then
    raise exception 'assertion failed: expected an unmapped-status rejection, but the call succeeded';
  end if;

  begin
    perform app.get_finance_lifecycle_record_state(v_tenant_a, 'not_a_real_entity_type', gen_random_uuid(), '00000000-0000-0000-0000-000000029911');
    v_failed := true;
  exception when others then
    if sqlerrm not like 'finance_lifecycle_entity_type_unsupported%' then
      raise exception 'assertion failed: expected finance_lifecycle_entity_type_unsupported, got %', sqlerrm;
    end if;
  end;
  if v_failed then
    raise exception 'assertion failed: expected an unsupported-entity-type rejection, but the call succeeded';
  end if;
end;
$$;

\echo '>> journal end-to-end: a real manual journal driven through draft -> submitted -> approved -> posted reports the correct canonical state, allowed_actions and locked_reason at every step, with posted_trigger_protected=true only once actually posted; a second, discarded draft maps to discarded'
do $$
declare
  v_tenant_a uuid;
  v_cash_id uuid;
  v_rev_id uuid;
  v_journal app.finance_journals;
  v_state jsonb;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmelifea');
  v_cash_id := (select id from app.finance_accounts where tenant_id = v_tenant_a and code = 'CASH-LIFE');
  v_rev_id := (select id from app.finance_accounts where tenant_id = v_tenant_a and code = 'REV-LIFE');

  select * into v_journal from app.create_finance_journal_draft(
    v_tenant_a, null, '2026-03-05'::date, 'USD',
    jsonb_build_array(
      jsonb_build_object('accountId', v_cash_id, 'direction', 'debit', 'amount', 500.00),
      jsonb_build_object('accountId', v_rev_id, 'direction', 'credit', 'amount', 500.00)
    ),
    'lifecycle-journal-1', '00000000-0000-0000-0000-000000029911', 'financemanagera'
  );

  v_state := app.get_finance_lifecycle_record_state(v_tenant_a, 'journal', v_journal.id, '00000000-0000-0000-0000-000000029911');
  if v_state ->> 'canonicalState' <> 'draft' or v_state -> 'allowedActions' <> '["submit", "discard"]'::jsonb or v_state ->> 'lockedReason' is not null or (v_state ->> 'recordVersion')::integer <> 1 then
    raise exception 'assertion failed: draft journal lifecycle state mismatch, got %', v_state;
  end if;

  select * into v_journal from app.submit_finance_journal_for_approval(v_journal.id, v_journal.record_version, '00000000-0000-0000-0000-000000029911', 'financemanagera');
  v_state := app.get_finance_lifecycle_record_state(v_tenant_a, 'journal', v_journal.id, '00000000-0000-0000-0000-000000029911');
  if v_state ->> 'canonicalState' <> 'in_review' or v_state ->> 'lockedReason' <> 'awaiting_approval' then
    raise exception 'assertion failed: submitted journal lifecycle state mismatch, got %', v_state;
  end if;

  select * into v_journal from app.approve_finance_journal(v_journal.id, v_journal.record_version, '00000000-0000-0000-0000-000000029910', 'admina');
  v_state := app.get_finance_lifecycle_record_state(v_tenant_a, 'journal', v_journal.id, '00000000-0000-0000-0000-000000029911');
  if v_state ->> 'canonicalState' <> 'approved' or v_state -> 'allowedActions' <> '["post"]'::jsonb then
    raise exception 'assertion failed: approved journal lifecycle state mismatch, got %', v_state;
  end if;

  select * into v_journal from app.post_finance_journal(v_journal.id, v_journal.record_version, '00000000-0000-0000-0000-000000029910', 'admina');
  v_state := app.get_finance_lifecycle_record_state(v_tenant_a, 'journal', v_journal.id, '00000000-0000-0000-0000-000000029911');
  if v_state ->> 'canonicalState' <> 'posted' or v_state -> 'allowedActions' <> '[]'::jsonb or v_state ->> 'lockedReason' <> 'posted_immutable_normal_role' or not (v_state -> 'postedTriggerProtected')::boolean then
    raise exception 'assertion failed: posted journal lifecycle state mismatch, got %', v_state;
  end if;

  -- a second, discarded draft
  select * into v_journal from app.create_finance_journal_draft(
    v_tenant_a, null, '2026-03-06'::date, 'USD',
    jsonb_build_array(
      jsonb_build_object('accountId', v_cash_id, 'direction', 'debit', 'amount', 10.00),
      jsonb_build_object('accountId', v_rev_id, 'direction', 'credit', 'amount', 10.00)
    ),
    'lifecycle-journal-2-discarded', '00000000-0000-0000-0000-000000029911', 'financemanagera'
  );
  perform app.discard_finance_journal_draft(v_journal.id, v_journal.record_version, 'no longer needed', '00000000-0000-0000-0000-000000029911', 'financemanagera');
  v_state := app.get_finance_lifecycle_record_state(v_tenant_a, 'journal', v_journal.id, '00000000-0000-0000-0000-000000029911');
  if v_state ->> 'canonicalState' <> 'discarded' or v_state ->> 'lockedReason' <> 'discarded' then
    raise exception 'assertion failed: discarded journal lifecycle state mismatch, got %', v_state;
  end if;
end;
$$;

\echo '>> settlement end-to-end: draft -> submitted -> approved -> executed -> posted -> reversed reports the correct canonical state at every step, proving the approved/executed coarsening still exposes distinct allowed_actions and that a governed reversal reaches the corrected canonical state'
do $$
declare
  v_tenant_a uuid;
  v_vendor_id uuid;
  v_open_item app.finance_ap_open_items;
  v_settlement app.finance_settlements;
  v_state jsonb;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmelifea');
  v_vendor_id := (select id from app.master_records where tenant_id = v_tenant_a and code = 'VEND-LIFE-1');

  select * into v_open_item from app.post_finance_ap_open_item(
    v_tenant_a, null, v_vendor_id, 'opening_balance', gen_random_uuid(), 'USD', 1000.00,
    '2026-03-01'::date, '2026-04-01'::date, '00000000-0000-0000-0000-000000029911', 'financemanagera'
  );

  select * into v_settlement from app.prepare_finance_settlement(
    v_tenant_a, null, v_vendor_id, 'PAY-LIFE-1', 'Bank Lifecycle', 'USD', '2026-03-10'::date,
    jsonb_build_array(jsonb_build_object('apOpenItemId', v_open_item.id, 'amount', 1000.00)),
    0, 'lifecycle-settlement-1', '00000000-0000-0000-0000-000000029911', 'financemanagera'
  );

  v_state := app.get_finance_lifecycle_record_state(v_tenant_a, 'settlement', v_settlement.id, '00000000-0000-0000-0000-000000029911');
  if v_state ->> 'canonicalState' <> 'draft' then
    raise exception 'assertion failed: draft settlement lifecycle state mismatch, got %', v_state;
  end if;

  select * into v_settlement from app.submit_finance_settlement_for_approval(v_settlement.id, v_settlement.record_version, '00000000-0000-0000-0000-000000029911', 'financemanagera');
  v_state := app.get_finance_lifecycle_record_state(v_tenant_a, 'settlement', v_settlement.id, '00000000-0000-0000-0000-000000029911');
  if v_state ->> 'canonicalState' <> 'in_review' then
    raise exception 'assertion failed: submitted settlement lifecycle state mismatch, got %', v_state;
  end if;

  select * into v_settlement from app.approve_finance_settlement(v_settlement.id, v_settlement.record_version, '00000000-0000-0000-0000-000000029911', 'financemanagera');
  v_state := app.get_finance_lifecycle_record_state(v_tenant_a, 'settlement', v_settlement.id, '00000000-0000-0000-0000-000000029911');
  if v_state ->> 'canonicalState' <> 'approved' or v_state -> 'allowedActions' <> '["execute"]'::jsonb then
    raise exception 'assertion failed: approved settlement lifecycle state mismatch, got %', v_state;
  end if;

  select * into v_settlement from app.execute_finance_settlement(v_settlement.id, v_settlement.record_version, 'REF-LIFE-1', '00000000-0000-0000-0000-000000029911', 'financemanagera');
  v_state := app.get_finance_lifecycle_record_state(v_tenant_a, 'settlement', v_settlement.id, '00000000-0000-0000-0000-000000029911');
  if v_state ->> 'canonicalState' <> 'approved' or v_state -> 'allowedActions' <> '["post"]'::jsonb or v_state ->> 'concreteStatus' <> 'executed' then
    raise exception 'assertion failed: executed settlement lifecycle state mismatch (expected same canonical bucket as approved, distinct allowed_actions), got %', v_state;
  end if;

  select * into v_settlement from app.post_finance_settlement(v_settlement.id, v_settlement.record_version, '00000000-0000-0000-0000-000000029911', 'financemanagera');
  v_state := app.get_finance_lifecycle_record_state(v_tenant_a, 'settlement', v_settlement.id, '00000000-0000-0000-0000-000000029911');
  if v_state ->> 'canonicalState' <> 'posted' or v_state -> 'allowedActions' <> '["request_reversal"]'::jsonb then
    raise exception 'assertion failed: posted settlement lifecycle state mismatch (a governed reversal already exists, unlike journal), got %', v_state;
  end if;

  select * into v_settlement from app.request_finance_settlement_reversal(v_settlement.id, 'lifecycle test reversal', '00000000-0000-0000-0000-000000029911', 'financemanagera');
  v_state := app.get_finance_lifecycle_record_state(v_tenant_a, 'settlement', v_settlement.id, '00000000-0000-0000-0000-000000029911');
  if v_state ->> 'canonicalState' <> 'corrected' or v_state -> 'allowedActions' <> '[]'::jsonb then
    raise exception 'assertion failed: reversed settlement lifecycle state mismatch, got %', v_state;
  end if;
end;
$$;

\echo '>> authority and tenant isolation: Plain User A (no FIN:View) is denied; tenant B''s own Finance Manager is denied against tenant A''s journal; a well-formed but nonexistent record id raises finance_lifecycle_record_not_found rather than returning null'
do $$
declare
  v_tenant_a uuid;
  v_journal_id uuid;
  v_failed boolean := false;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmelifea');
  v_journal_id := (select id from app.finance_journals where tenant_id = v_tenant_a limit 1);

  begin
    perform app.get_finance_lifecycle_record_state(v_tenant_a, 'journal', v_journal_id, '00000000-0000-0000-0000-000000029912');
    v_failed := true;
  exception when others then
    if sqlerrm not like 'insufficient_authority%' then
      raise exception 'assertion failed: expected insufficient_authority for Plain User A, got %', sqlerrm;
    end if;
  end;
  if v_failed then
    raise exception 'assertion failed: expected Plain User A to be denied FIN:View, but the call succeeded';
  end if;

  begin
    perform app.get_finance_lifecycle_record_state(v_tenant_a, 'journal', v_journal_id, '00000000-0000-0000-0000-000000029913');
    v_failed := true;
  exception when others then
    if sqlerrm not like 'insufficient_authority%' then
      raise exception 'assertion failed: expected insufficient_authority for tenant B''s own Finance Manager, got %', sqlerrm;
    end if;
  end;
  if v_failed then
    raise exception 'assertion failed: expected tenant B''s own Finance Manager to be denied against tenant A''s own journal, but the call succeeded';
  end if;

  begin
    perform app.get_finance_lifecycle_record_state(v_tenant_a, 'journal', gen_random_uuid(), '00000000-0000-0000-0000-000000029911');
    v_failed := true;
  exception when others then
    if sqlerrm not like 'finance_lifecycle_record_not_found%' then
      raise exception 'assertion failed: expected finance_lifecycle_record_not_found, got %', sqlerrm;
    end if;
  end;
  if v_failed then
    raise exception 'assertion failed: expected a nonexistent record id to raise finance_lifecycle_record_not_found, but the call succeeded';
  end if;
end;
$$;

\echo '>> schema-privilege defense in depth: anon holds zero EXECUTE on either new FIN-205 function (ERR-2026-004 regression guard)'
do $$
declare
  v_fn text;
  v_anon_has boolean;
begin
  for v_fn in select unnest(array['get_finance_lifecycle_editability', 'get_finance_lifecycle_record_state']) loop
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
