-- Real, executable test evidence for OPS-168 (Job Order, CG-S8-OPS-002) -- run via
-- `pnpm run db:test` against a real, disposable Postgres database.

\set ON_ERROR_STOP on

\echo '>> setup: one tenant, a company/team-a/team-b org hierarchy, a rep (COM:Create/Edit/Approve/View/View selling price/View cost + OPS:Create/Edit/Override/View), a restricted ops-only actor (OPS:Create/Edit/View, no COM:View selling price/View cost), a sibling-team outsider (full grants, different team), and a full lead->prospect->contact->opportunity->costing->rate->margin->quotation->acceptance->account->job-order-handoff pipeline'
do $$
declare
  v_tenant1 uuid;
  v_team_a uuid;
  v_team_b uuid;
  v_full_role uuid;
  v_full_draft app.role_versions;
  v_restricted_role uuid;
  v_restricted_draft app.role_versions;
  v_outsider_role uuid;
  v_outsider_draft app.role_versions;
  v_lead app.leads;
  v_prospect app.prospects;
  v_contact app.contacts;
  v_opportunity app.opportunities;
  v_request app.costing_requests;
  v_rate app.vendor_rate_versions;
  v_selection app.rate_selections;
  v_rule app.margin_rule_versions;
  v_calc_id uuid;
  v_quote app.quotations;
  v_send record;
  v_account app.accounts;
  v_handoff app.job_order_handoffs;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000009959', 'admin@acmeops.test'),
    ('00000000-0000-0000-0000-000000009960', 'repa@acmeops.test'),
    ('00000000-0000-0000-0000-000000009961', 'restricted@acmeops.test'),
    ('00000000-0000-0000-0000-000000009962', 'outsider@acmeops.test');

  perform app.provision_tenant('acmeops', 'Acme Operations Co', 'idem-acmeops', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'acmeops');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');

  perform app.create_org_unit(v_tenant1, 'company', null, 'ACMEOPS-CO', 'Acme Operations Co', 'tester');
  perform app.create_org_unit(v_tenant1, 'department', (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEOPS-CO'), 'ACMEOPS-TEAM-A', 'Team A', 'tester');
  v_team_a := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEOPS-TEAM-A');
  perform app.create_org_unit(v_tenant1, 'department', (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEOPS-CO'), 'ACMEOPS-TEAM-B', 'Team B', 'tester');
  v_team_b := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEOPS-TEAM-B');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000009959', 'admin@acmeops.test', 'Ops Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@acmeops.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000009959', 'tenant_admin', v_tenant1, null, 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000009960', 'repa@acmeops.test', 'Rep A', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'repa@acmeops.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000009961', 'restricted@acmeops.test', 'Restricted Ops', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'restricted@acmeops.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000009962', 'outsider@acmeops.test', 'Team B Outsider', v_team_b, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'outsider@acmeops.test'), 'active', 'onboarded', 'tester');

  v_full_role := (app.create_role(v_tenant1, 'Ops Full Rep', 'full access', 'tester')).id;
  v_full_draft := app.create_role_version(v_full_role, 'tester');
  perform app.set_role_version_permissions(
    v_full_draft.id,
    array(select id from app.permissions where (resource_module_code = 'COM' and action in ('Create', 'Edit', 'Approve', 'View', 'View selling price', 'View cost'))
      or (resource_module_code = 'OPS' and action in ('Create', 'Edit', 'Override', 'View'))),
    'tester'
  );
  perform app.publish_role_version(v_full_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_full_role and status = 'published'), '00000000-0000-0000-0000-000000009960', '00000000-0000-0000-0000-000000009959', 'tester');

  v_restricted_role := (app.create_role(v_tenant1, 'Ops Restricted', 'no commercial money visibility', 'tester')).id;
  v_restricted_draft := app.create_role_version(v_restricted_role, 'tester');
  perform app.set_role_version_permissions(
    v_restricted_draft.id,
    array(select id from app.permissions where resource_module_code = 'OPS' and action in ('Create', 'Edit', 'View')),
    'tester'
  );
  perform app.publish_role_version(v_restricted_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_restricted_role and status = 'published'), '00000000-0000-0000-0000-000000009961', '00000000-0000-0000-0000-000000009960', 'tester');

  v_outsider_role := (app.create_role(v_tenant1, 'Ops Outsider', 'sibling team, full grants', 'tester')).id;
  v_outsider_draft := app.create_role_version(v_outsider_role, 'tester');
  perform app.set_role_version_permissions(
    v_outsider_draft.id,
    array(select id from app.permissions where (resource_module_code = 'COM' and action in ('Create', 'Edit', 'View', 'View selling price', 'View cost'))
      or (resource_module_code = 'OPS' and action in ('Create', 'Edit', 'Override', 'View'))),
    'tester'
  );
  perform app.publish_role_version(v_outsider_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_outsider_role and status = 'published'), '00000000-0000-0000-0000-000000009962', '00000000-0000-0000-0000-000000009960', 'tester');

  perform app.capture_lead(v_tenant1, 'manual', null, 'Ops Test Co', 'Jane Ops', 'jane@opstest.test', '0811',
    '00000000-0000-0000-0000-000000009960', v_team_a, '00000000-0000-0000-0000-000000009960', 'tester');
  select * into v_lead from app.leads where email = 'jane@opstest.test';
  perform app.qualify_lead(v_lead.id, v_lead.record_version, '00000000-0000-0000-0000-000000009960', 'tester');
  select * into v_lead from app.leads where id = v_lead.id;
  perform app.convert_lead_to_prospect(v_lead.id, 'Ops Test Co', 'OTC', '66.666.666.6-666.000',
    jsonb_build_object('line1', 'Jl. Rasuna Said 1', 'city', 'Jakarta', 'country', 'ID'),
    '00000000-0000-0000-0000-000000009960', 'tester');
  select * into v_prospect from app.prospects where lead_id = v_lead.id;

  select * into v_contact from app.create_contact(v_tenant1, 'Jane Ops', 'Procurement Lead', 'jane@opstest.test', '0811', '00000000-0000-0000-0000-000000009960', v_team_a, '00000000-0000-0000-0000-000000009960', 'tester');
  perform app.link_contact_to_record(v_contact.id, 'prospect', v_prospect.id, 'primary', true, '00000000-0000-0000-0000-000000009960', 'tester');

  select * into v_opportunity from app.create_opportunity(
    v_tenant1, v_prospect.id, 'Ops test lane',
    jsonb_build_object('service_type', 'ocean_freight', 'cargo_description', 'General cargo', 'origin', 'Jakarta', 'destination', 'Surabaya', 'target_ready_date', '2026-08-01'),
    '00000000-0000-0000-0000-000000009960', v_team_a, '00000000-0000-0000-0000-000000009960', 'tester'
  );
  select * into v_request from app.request_costing(v_opportunity.id, '[]'::jsonb, null, '00000000-0000-0000-0000-000000009960', 'tester');
  select * into v_rate from app.create_rate_version(
    v_tenant1, 'VENDOR-OPS-1', 'Contoso Ocean Line', 'ocean_freight', 'FCL', 'Jakarta', 'Surabaya', '20ft',
    null, null, null, null, 'IDR', 10000000, null, '[]'::jsonb, now(), null, null, '00000000-0000-0000-0000-000000009959', 'tester'
  );
  perform app.approve_rate_version(v_rate.id, v_rate.record_version, '00000000-0000-0000-0000-000000009959', 'tester');
  select * into v_selection from app.select_vendor_rate(v_request.id, v_rate.id, false, null, null, null, '00000000-0000-0000-0000-000000009960', 'tester');

  select * into v_rule from app.create_margin_rule_version(v_tenant1, 20.00, 'half_up', '00000000-0000-0000-0000-000000009960', 'tester');
  perform app.publish_margin_rule_version(v_rule.id, v_rule.record_version, null, '00000000-0000-0000-0000-000000009960', 'tester');
  perform app.calculate_margin(v_selection.id, 15000000, 'IDR', 0, '00000000-0000-0000-0000-000000009960', 'tester');
  select id into v_calc_id from app.margin_calculations where rate_selection_id = v_selection.id and is_current;

  select * into v_quote from app.create_quotation_draft(v_tenant1, v_opportunity.id, 'IDR', now() + interval '14 days', v_contact.id, null, null, '00000000-0000-0000-0000-000000009960', 'tester');
  perform app.add_quotation_line(v_quote.id, v_quote.record_version, 'service', 'Ocean freight ops lane', v_calc_id, 1, 15000000, 0, 0, '00000000-0000-0000-0000-000000009960', 'tester');
  select * into v_quote from app.quotations where id = v_quote.id;
  perform app.submit_quotation(v_quote.id, v_quote.record_version, '00000000-0000-0000-0000-000000009960', 'tester');
  select * into v_send from app.send_quotation_for_acceptance(v_quote.id, null, 'email', '00000000-0000-0000-0000-000000009960', 'tester');
  perform app.record_quotation_customer_decision(v_send.raw_token, 'accepted', 'Jane Ops', null, null, null, null, null);

  select * into v_account from app.convert_quotation_to_account(v_quote.id, null, null, '00000000-0000-0000-0000-000000009960', 'rep');
  select * into v_handoff from app.prepare_job_order_handoff(v_quote.id, '00000000-0000-0000-0000-000000009960', 'rep');
end;
$$;

\echo '>> app.get_job_order_conversion_readiness: ready=true before any conversion; already_converted becomes true after prepare_job_order runs once'
do $$
declare
  v_tenant1 uuid;
  v_handoff_id uuid;
  v_ready boolean;
  v_reasons text[];
  v_existing uuid;
begin
  v_tenant1 := (select id from app.tenants where slug = 'acmeops');
  select id into v_handoff_id from app.job_order_handoffs where tenant_id = v_tenant1;

  select ready, blocking_reasons, existing_job_order_id into v_ready, v_reasons, v_existing
  from app.get_job_order_conversion_readiness(v_handoff_id, '00000000-0000-0000-0000-000000009960');
  if not v_ready or v_existing is not null then
    raise exception 'assertion failed: expected ready=true with no existing job order, got ready=% existing=%', v_ready, v_existing;
  end if;
end;
$$;

\echo '>> app.prepare_job_order: authority-gated (an actor without OPS:Create is denied); creates a real Job Order with every snapshot column populated verbatim from the handoff payload; idempotent on (tenant_id, source_handoff_id) including under a repeated call'
do $$
declare
  v_tenant1 uuid;
  v_handoff_id uuid;
  v_job_order1 app.job_orders;
  v_job_order2 app.job_orders;
  v_job_order_count integer;
begin
  v_tenant1 := (select id from app.tenants where slug = 'acmeops');
  select id into v_handoff_id from app.job_order_handoffs where tenant_id = v_tenant1;

  begin
    perform app.prepare_job_order(v_handoff_id, '00000000-0000-0000-0000-000000009999', 'nobody');
    raise exception 'assertion failed: expected insufficient_privilege for an identity with no active tenant membership';
  exception
    when insufficient_privilege then
      null; -- expected
  end;

  select * into v_job_order1 from app.prepare_job_order(v_handoff_id, '00000000-0000-0000-0000-000000009960', 'rep');
  if v_job_order1.status <> 'draft' or v_job_order1.job_number !~ '^JOB-[0-9]{4}-[0-9]{6}$'
     or v_job_order1.customer_snapshot ->> 'contactName' <> 'Jane Ops'
     or v_job_order1.cargo_service_snapshot ->> 'service_type' <> 'ocean_freight'
     or (v_job_order1.revenue_snapshot ->> 'totalAmount')::numeric <> 15000000 then
    raise exception 'assertion failed: expected a real draft Job Order with verbatim snapshots, got status=% job_number=% customer=% cargo=% revenue=%',
      v_job_order1.status, v_job_order1.job_number, v_job_order1.customer_snapshot, v_job_order1.cargo_service_snapshot, v_job_order1.revenue_snapshot;
  end if;

  select * into v_job_order2 from app.prepare_job_order(v_handoff_id, '00000000-0000-0000-0000-000000009960', 'rep');
  if v_job_order2.id <> v_job_order1.id then
    raise exception 'assertion failed: expected the idempotent retry to return the same job order %, got %', v_job_order1.id, v_job_order2.id;
  end if;

  select count(*) into v_job_order_count from app.job_orders where source_handoff_id = v_handoff_id;
  if v_job_order_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 job order after a repeated call, found %', v_job_order_count;
  end if;
end;
$$;

\echo '>> ISS-2026-203 regression: customer_snapshot/cargo_service_snapshot/revenue_snapshot/acceptance_snapshot each self-embed quotationId/quotationVersion matching the real source quotation row/version, without disturbing any pre-existing snapshot key; contract_snapshot/credit_snapshot are unchanged (not in scope)'
do $$
declare
  v_tenant1 uuid;
  v_handoff_id uuid;
  v_job_order app.job_orders;
  v_quotation_id uuid;
  v_quotation_version integer;
begin
  v_tenant1 := (select id from app.tenants where slug = 'acmeops');
  select id into v_handoff_id from app.job_order_handoffs where tenant_id = v_tenant1;
  select * into v_job_order from app.job_orders where tenant_id = v_tenant1 and source_handoff_id = v_handoff_id;
  select quotation_id into v_quotation_id from app.job_order_handoffs where id = v_handoff_id;
  select version_number into v_quotation_version from app.quotations where id = v_quotation_id;

  if (v_job_order.customer_snapshot ->> 'quotationId')::uuid <> v_quotation_id
     or (v_job_order.cargo_service_snapshot ->> 'quotationId')::uuid <> v_quotation_id
     or (v_job_order.revenue_snapshot ->> 'quotationId')::uuid <> v_quotation_id
     or (v_job_order.acceptance_snapshot ->> 'quotationId')::uuid <> v_quotation_id then
    raise exception 'assertion failed: expected quotationId=% self-embedded in all 4 named snapshots, got customer=% cargo=% revenue=% acceptance=%',
      v_quotation_id, v_job_order.customer_snapshot ->> 'quotationId', v_job_order.cargo_service_snapshot ->> 'quotationId',
      v_job_order.revenue_snapshot ->> 'quotationId', v_job_order.acceptance_snapshot ->> 'quotationId';
  end if;
  if (v_job_order.customer_snapshot ->> 'quotationVersion')::integer <> v_quotation_version
     or (v_job_order.cargo_service_snapshot ->> 'quotationVersion')::integer <> v_quotation_version
     or (v_job_order.revenue_snapshot ->> 'quotationVersion')::integer <> v_quotation_version
     or (v_job_order.acceptance_snapshot ->> 'quotationVersion')::integer <> v_quotation_version then
    raise exception 'assertion failed: expected quotationVersion=% self-embedded in all 4 named snapshots, got customer=% cargo=% revenue=% acceptance=%',
      v_quotation_version, v_job_order.customer_snapshot ->> 'quotationVersion', v_job_order.cargo_service_snapshot ->> 'quotationVersion',
      v_job_order.revenue_snapshot ->> 'quotationVersion', v_job_order.acceptance_snapshot ->> 'quotationVersion';
  end if;

  -- Pre-existing keys survive the merge untouched (additive, not a replacement).
  if v_job_order.customer_snapshot ->> 'contactName' <> 'Jane Ops'
     or v_job_order.cargo_service_snapshot ->> 'service_type' <> 'ocean_freight'
     or (v_job_order.revenue_snapshot ->> 'totalAmount')::numeric <> 15000000 then
    raise exception 'assertion failed: expected pre-existing snapshot keys to survive the quotationId/quotationVersion merge unchanged, got customer=% cargo=% revenue=%',
      v_job_order.customer_snapshot, v_job_order.cargo_service_snapshot, v_job_order.revenue_snapshot;
  end if;

  -- contract_snapshot/credit_snapshot are out of this entry's own named scope, untouched.
  if v_job_order.contract_snapshot ? 'quotationId' or v_job_order.credit_snapshot ? 'quotationId' then
    raise exception 'assertion failed: expected contract_snapshot/credit_snapshot to remain untouched by the ISS-2026-203 fix, got contract=% credit=%',
      v_job_order.contract_snapshot, v_job_order.credit_snapshot;
  end if;
end;
$$;

\echo '>> app.confirm_job_order: optimistic concurrency (stale version rejected), draft -> confirmed, and a second confirm attempt is rejected (not a draft anymore)'
do $$
declare
  v_tenant1 uuid;
  v_job_order app.job_orders;
begin
  v_tenant1 := (select id from app.tenants where slug = 'acmeops');
  select * into v_job_order from app.job_orders where tenant_id = v_tenant1;

  begin
    perform app.confirm_job_order(v_job_order.id, v_job_order.record_version + 99, '00000000-0000-0000-0000-000000009960', 'rep');
    raise exception 'assertion failed: expected stale_version';
  exception
    when others then
      if sqlerrm !~ 'stale_version' then
        raise exception 'assertion failed: expected stale_version, got %', sqlerrm;
      end if;
  end;

  select * into v_job_order from app.confirm_job_order(v_job_order.id, v_job_order.record_version, '00000000-0000-0000-0000-000000009960', 'rep');
  if v_job_order.status <> 'confirmed' then
    raise exception 'assertion failed: expected status=confirmed, got %', v_job_order.status;
  end if;

  begin
    perform app.confirm_job_order(v_job_order.id, v_job_order.record_version, '00000000-0000-0000-0000-000000009960', 'rep');
    raise exception 'assertion failed: expected invalid_transition -- already confirmed';
  exception
    when others then
      if sqlerrm !~ 'invalid_transition' then
        raise exception 'assertion failed: expected invalid_transition, got %', sqlerrm;
      end if;
  end;
end;
$$;

\echo '>> app.override_job_order_field: mandatory reason enforced; a real bounded correction to customer_snapshot is applied, recorded append-only in app.job_order_overrides, and revenue/acceptance snapshots remain untouched'
do $$
declare
  v_tenant1 uuid;
  v_job_order app.job_orders;
  v_override_count integer;
begin
  v_tenant1 := (select id from app.tenants where slug = 'acmeops');
  select * into v_job_order from app.job_orders where tenant_id = v_tenant1;

  begin
    perform app.override_job_order_field(v_job_order.id, v_job_order.record_version, 'customer_snapshot', 'contactPhone', '"0899"'::jsonb, '', '00000000-0000-0000-0000-000000009960', 'rep');
    raise exception 'assertion failed: expected override_reason_required for an empty reason';
  exception
    when others then
      if sqlerrm !~ 'override_reason_required' then
        raise exception 'assertion failed: expected override_reason_required, got %', sqlerrm;
      end if;
  end;

  begin
    perform app.override_job_order_field(v_job_order.id, v_job_order.record_version, 'revenue_snapshot', 'totalAmount', '99'::jsonb, 'attempted financial edit', '00000000-0000-0000-0000-000000009960', 'rep');
    raise exception 'assertion failed: expected invalid_snapshot_column -- revenue_snapshot is not overridable';
  exception
    when others then
      if sqlerrm !~ 'invalid_snapshot_column' then
        raise exception 'assertion failed: expected invalid_snapshot_column, got %', sqlerrm;
      end if;
  end;

  select * into v_job_order from app.override_job_order_field(v_job_order.id, v_job_order.record_version, 'customer_snapshot', 'contactPhone', '"0899"'::jsonb, 'customer provided a new phone number', '00000000-0000-0000-0000-000000009960', 'rep');
  if v_job_order.customer_snapshot ->> 'contactPhone' <> '0899' then
    raise exception 'assertion failed: expected contactPhone=0899 after override, got %', v_job_order.customer_snapshot ->> 'contactPhone';
  end if;

  select count(*) into v_override_count from app.job_order_overrides where job_order_id = v_job_order.id;
  if v_override_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 override evidence row, found %', v_override_count;
  end if;
end;
$$;

\echo '>> app.job_orders_directory: revenue_snapshot/credit_snapshot masked (null, *_masked=true) for the restricted ops-only actor lacking COM:View selling price/View cost; visible for the full-access rep on the identical row'
do $$
declare
  v_tenant1 uuid;
  v_job_order_id uuid;
  v_revenue_masked boolean;
  v_credit_masked boolean;
  v_revenue jsonb;
begin
  v_tenant1 := (select id from app.tenants where slug = 'acmeops');
  select id into v_job_order_id from app.job_orders where tenant_id = v_tenant1;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000009961", "role": "authenticated"}';
  select revenue_masked, credit_masked, revenue_snapshot into v_revenue_masked, v_credit_masked, v_revenue from app.job_orders_directory where id = v_job_order_id;
  if not v_revenue_masked or not v_credit_masked or v_revenue is not null then
    raise exception 'assertion failed: expected the restricted actor to see revenue_masked=true, credit_masked=true, revenue_snapshot=null, got revenue_masked=% credit_masked=% revenue=%', v_revenue_masked, v_credit_masked, v_revenue;
  end if;
  reset role;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000009960", "role": "authenticated"}';
  select revenue_masked, revenue_snapshot into v_revenue_masked, v_revenue from app.job_orders_directory where id = v_job_order_id;
  if v_revenue_masked or v_revenue is null then
    raise exception 'assertion failed: expected the full-access rep to see real revenue_snapshot, got masked=% revenue=%', v_revenue_masked, v_revenue;
  end if;
  reset role;
end;
$$;

\echo '>> record-scope: a sibling-team outsider (different org unit, no ownership stake) cannot access the job order via app.confirm_job_order/app.override_job_order_field despite holding full OPS/COM permissions'
do $$
declare
  v_job_order app.job_orders;
begin
  select * into v_job_order from app.job_orders limit 1;

  begin
    perform app.override_job_order_field(v_job_order.id, v_job_order.record_version, 'customer_snapshot', 'contactPhone', '"0800"'::jsonb, 'outsider attempt', '00000000-0000-0000-0000-000000009962', 'outsider');
    raise exception 'assertion failed: expected insufficient_privilege -- sibling-team outsider has no record access';
  exception
    when insufficient_privilege then
      null; -- expected
  end;
end;
$$;

\echo '>> cross-tenant isolation: app.get_job_order_conversion_readiness/app.prepare_job_order fail closed for an identity with no membership in the handoff''s own tenant'
do $$
declare
  v_tenant2 uuid;
  v_handoff_id uuid;
begin
  insert into auth.users (id, email) values ('00000000-0000-0000-0000-000000009963', 'admin2@acmeops2.test');
  perform app.provision_tenant('acmeops2', 'Acme Operations Two', 'idem-acmeops2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'acmeops2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');
  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000009963', 'admin2@acmeops2.test', 'Tenant 2 Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin2@acmeops2.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000009963', 'tenant_admin', v_tenant2, null, 'tester');

  select id into v_handoff_id from app.job_order_handoffs where tenant_id = (select id from app.tenants where slug = 'acmeops');

  begin
    perform app.get_job_order_conversion_readiness(v_handoff_id, '00000000-0000-0000-0000-000000009963');
    raise exception 'assertion failed: expected insufficient_privilege -- tenant 2''s admin holds no membership in tenant 1';
  exception
    when insufficient_privilege then
      null; -- expected
  end;
end;
$$;

\echo '>> schema-privilege defense in depth: anon holds no EXECUTE on any new Job Order function (ERR-2026-004 regression guard)'
do $$
declare
  v_anon_grant_count integer;
begin
  select count(*) into v_anon_grant_count
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'app'
    and p.proname in ('prepare_job_order', 'confirm_job_order', 'override_job_order_field', 'get_job_order_conversion_readiness', 'next_job_order_number')
    and has_function_privilege('anon', p.oid, 'EXECUTE');
  if v_anon_grant_count <> 0 then
    raise exception 'assertion failed: expected zero anon EXECUTE grants across the 5 new Job Order functions, found %', v_anon_grant_count;
  end if;
end;
$$;

\echo '>> audit trail: prepare/confirm/override each recorded a real app.audit_logs event, tenant-scoped'
do $$
declare
  v_tenant1 uuid;
  v_count integer;
begin
  v_tenant1 := (select id from app.tenants where slug = 'acmeops');
  select count(*) into v_count from app.audit_logs where tenant_id = v_tenant1 and resource_type = 'app.job_orders' and action in ('prepare_job_order', 'confirm_job_order', 'override_job_order_field');
  if v_count <> 3 then
    raise exception 'assertion failed: expected exactly 3 audit events (prepare + confirm + override -- the idempotent retry left no new trace), found %', v_count;
  end if;
end;
$$;
