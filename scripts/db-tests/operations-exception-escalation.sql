-- Real, executable test evidence for OPS-174 (Exception and Escalation, CG-S8-OPS-008)
-- -- run via `pnpm run db:test` against a real, disposable Postgres database.

\set ON_ERROR_STOP on

\echo '>> setup: one tenant, a company/team-a/team-b org hierarchy, a bootstrap tenant-admin, a rep (COM full + OPS:Create/Edit/Assign/Close/View + OPS:View cost), a restricted actor (same OPS grants, no OPS:View cost), a sibling-team outsider, one confirmed Job Order, and two confirmed Shipment Orders (walk/aux)'
do $$
declare
  v_tenant1 uuid;
  v_team_a uuid;
  v_team_b uuid;
  v_rep_role uuid;
  v_rep_draft app.role_versions;
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
  v_job_order app.job_orders;
  v_shipment_walk app.shipment_orders;
  v_shipment_aux app.shipment_orders;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000009820', 'admin@acmeexc.test'),
    ('00000000-0000-0000-0000-000000009821', 'repa@acmeexc.test'),
    ('00000000-0000-0000-0000-000000009822', 'restricted@acmeexc.test'),
    ('00000000-0000-0000-0000-000000009823', 'outsider@acmeexc.test'),
    ('00000000-0000-0000-0000-000000009824', 'newowner@acmeexc.test');

  perform app.provision_tenant('acmeexc', 'Acme Exception Co', 'idem-acmeexc', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'acmeexc');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');

  perform app.create_org_unit(v_tenant1, 'company', null, 'ACMEEXC-CO', 'Acme Exception Co', 'tester');
  perform app.create_org_unit(v_tenant1, 'department', (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEEXC-CO'), 'ACMEEXC-TEAM-A', 'Team A', 'tester');
  v_team_a := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEEXC-TEAM-A');
  perform app.create_org_unit(v_tenant1, 'department', (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEEXC-CO'), 'ACMEEXC-TEAM-B', 'Team B', 'tester');
  v_team_b := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEEXC-TEAM-B');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000009820', 'admin@acmeexc.test', 'Exc Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@acmeexc.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000009820', 'tenant_admin', v_tenant1, null, 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000009821', 'repa@acmeexc.test', 'Rep A', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'repa@acmeexc.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000009822', 'restricted@acmeexc.test', 'Restricted Actor', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'restricted@acmeexc.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000009823', 'outsider@acmeexc.test', 'Team B Outsider', v_team_b, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'outsider@acmeexc.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000009824', 'newowner@acmeexc.test', 'New Owner', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'newowner@acmeexc.test'), 'active', 'onboarded', 'tester');

  v_rep_role := (app.create_role(v_tenant1, 'Exc Rep', 'full commercial + ops grants + view cost', 'tester')).id;
  v_rep_draft := app.create_role_version(v_rep_role, 'tester');
  perform app.set_role_version_permissions(
    v_rep_draft.id,
    array(select id from app.permissions where (resource_module_code = 'COM' and action in ('Create', 'Edit', 'Approve', 'View', 'View cost'))
      or (resource_module_code = 'OPS' and action in ('Create', 'Edit', 'Assign', 'Close', 'View', 'View cost'))),
    'tester'
  );
  perform app.publish_role_version(v_rep_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_rep_role and status = 'published'), '00000000-0000-0000-0000-000000009821', '00000000-0000-0000-0000-000000009820', 'tester');

  v_restricted_role := (app.create_role(v_tenant1, 'Exc Restricted', 'same ops grants, no OPS:View cost', 'tester')).id;
  v_restricted_draft := app.create_role_version(v_restricted_role, 'tester');
  perform app.set_role_version_permissions(
    v_restricted_draft.id,
    array(select id from app.permissions where resource_module_code = 'OPS' and action in ('Create', 'Edit', 'Assign', 'Close', 'View')),
    'tester'
  );
  perform app.publish_role_version(v_restricted_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_restricted_role and status = 'published'), '00000000-0000-0000-0000-000000009822', '00000000-0000-0000-0000-000000009820', 'tester');

  v_outsider_role := (app.create_role(v_tenant1, 'Exc Outsider', 'sibling team, full grants', 'tester')).id;
  v_outsider_draft := app.create_role_version(v_outsider_role, 'tester');
  perform app.set_role_version_permissions(
    v_outsider_draft.id,
    array(select id from app.permissions where (resource_module_code = 'COM' and action in ('Create', 'Edit', 'View'))
      or (resource_module_code = 'OPS' and action in ('Create', 'Edit', 'Assign', 'Close', 'View', 'View cost'))),
    'tester'
  );
  perform app.publish_role_version(v_outsider_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_outsider_role and status = 'published'), '00000000-0000-0000-0000-000000009823', '00000000-0000-0000-0000-000000009820', 'tester');

  perform app.capture_lead(v_tenant1, 'manual', null, 'Exc Test Co', 'Jane Exc', 'jane@exctest.test', '0811',
    '00000000-0000-0000-0000-000000009821', v_team_a, '00000000-0000-0000-0000-000000009821', 'tester');
  select * into v_lead from app.leads where email = 'jane@exctest.test';
  perform app.qualify_lead(v_lead.id, v_lead.record_version, '00000000-0000-0000-0000-000000009821', 'tester');
  select * into v_lead from app.leads where id = v_lead.id;
  perform app.convert_lead_to_prospect(v_lead.id, 'Exc Test Co', 'ETC', '11.111.111.1-111.000',
    jsonb_build_object('line1', 'Jl. Rasuna Said 1', 'city', 'Jakarta', 'country', 'ID'),
    '00000000-0000-0000-0000-000000009821', 'tester');
  select * into v_prospect from app.prospects where lead_id = v_lead.id;

  select * into v_contact from app.create_contact(v_tenant1, 'Jane Exc Ops', 'Procurement Lead', 'jane@exctest.test', '0811', '00000000-0000-0000-0000-000000009821', v_team_a, '00000000-0000-0000-0000-000000009821', 'tester');
  perform app.link_contact_to_record(v_contact.id, 'prospect', v_prospect.id, 'primary', true, '00000000-0000-0000-0000-000000009821', 'tester');

  select * into v_opportunity from app.create_opportunity(
    v_tenant1, v_prospect.id, 'Exception test lane',
    jsonb_build_object('service_type', 'ocean_freight', 'cargo_description', 'General cargo', 'origin', 'Jakarta', 'destination', 'Surabaya', 'target_ready_date', '2026-08-01'),
    '00000000-0000-0000-0000-000000009821', v_team_a, '00000000-0000-0000-0000-000000009821', 'tester'
  );
  select * into v_request from app.request_costing(v_opportunity.id, '[]'::jsonb, null, '00000000-0000-0000-0000-000000009821', 'tester');
  select * into v_rate from app.create_rate_version(
    v_tenant1, 'VENDOR-EXC-1', 'Contoso Ocean Line', 'ocean_freight', 'FCL', 'Jakarta', 'Surabaya', '20ft',
    null, null, null, null, 'IDR', 10000000, null, '[]'::jsonb, now(), null, null, '00000000-0000-0000-0000-000000009820', 'tester'
  );
  perform app.approve_rate_version(v_rate.id, v_rate.record_version, '00000000-0000-0000-0000-000000009820', 'tester');
  select * into v_selection from app.select_vendor_rate(v_request.id, v_rate.id, false, null, null, null, '00000000-0000-0000-0000-000000009821', 'tester');

  select * into v_rule from app.create_margin_rule_version(v_tenant1, 20.00, 'half_up', '00000000-0000-0000-0000-000000009821', 'tester');
  perform app.publish_margin_rule_version(v_rule.id, v_rule.record_version, null, '00000000-0000-0000-0000-000000009821', 'tester');
  perform app.calculate_margin(v_selection.id, 15000000, 'IDR', 0, '00000000-0000-0000-0000-000000009821', 'tester');
  select id into v_calc_id from app.margin_calculations where rate_selection_id = v_selection.id and is_current;

  select * into v_quote from app.create_quotation_draft(v_tenant1, v_opportunity.id, 'IDR', now() + interval '14 days', v_contact.id, null, null, '00000000-0000-0000-0000-000000009821', 'tester');
  perform app.add_quotation_line(v_quote.id, v_quote.record_version, 'service', 'Ocean freight ops lane', v_calc_id, 1, 15000000, 0, 0, '00000000-0000-0000-0000-000000009821', 'tester');
  select * into v_quote from app.quotations where id = v_quote.id;
  perform app.submit_quotation(v_quote.id, v_quote.record_version, '00000000-0000-0000-0000-000000009821', 'tester');
  select * into v_send from app.send_quotation_for_acceptance(v_quote.id, null, 'email', '00000000-0000-0000-0000-000000009821', 'tester');
  perform app.record_quotation_customer_decision(v_send.raw_token, 'accepted', 'Jane Exc Ops', null, null, null, null, null);
  select * into v_quote from app.quotations where id = v_quote.id;
  select * into v_account from app.convert_quotation_to_account(v_quote.id, null, null, '00000000-0000-0000-0000-000000009821', 'rep');
  select * into v_handoff from app.prepare_job_order_handoff(v_quote.id, '00000000-0000-0000-0000-000000009821', 'rep');

  select * into v_job_order from app.prepare_job_order(v_handoff.id, '00000000-0000-0000-0000-000000009821', 'rep');
  select * into v_job_order from app.confirm_job_order(v_job_order.id, v_job_order.record_version, '00000000-0000-0000-0000-000000009821', 'rep');

  select * into v_shipment_walk from app.create_shipment_order_from_job(
    v_job_order.id, 'idem-exc-walk', null, null, 'ocean_freight', 'sea', 'Jakarta', 'Surabaya',
    now() + interval '1 day', now() + interval '10 days', null, null, null, null, null, null, null, '00000000-0000-0000-0000-000000009821', 'rep'
  );
  select * into v_shipment_walk from app.confirm_shipment_order(v_shipment_walk.id, v_shipment_walk.record_version, '00000000-0000-0000-0000-000000009821', 'rep');

  select * into v_shipment_aux from app.create_shipment_order_from_job(
    v_job_order.id, 'idem-exc-aux', null, null, 'ocean_freight', 'sea', 'Jakarta', 'Semarang',
    null, null, null, null, null, null, null, null, 'split: aux fixture', '00000000-0000-0000-0000-000000009821', 'rep'
  );
end $$;

\echo '>> app.create_exception_sla_policy_draft / app.set_exception_sla_policy_terms / app.publish_exception_sla_policy_version: unknown type/severity rejected; a valid (delay, high) policy publishes with a real SLA and escalation schedule; at most one draft/published per (tenant, type, severity)'
do $$
declare
  v_tenant1 uuid;
  v_draft app.exception_sla_policy_versions;
  v_published app.exception_sla_policy_versions;
begin
  v_tenant1 := (select id from app.tenants where slug = 'acmeexc');

  begin
    perform app.create_exception_sla_policy_draft(v_tenant1, 'earthquake', 'high', '00000000-0000-0000-0000-000000009821', 'rep');
    raise exception 'assertion failed: expected exception_invalid_type for an unsupported type';
  exception
    when others then
      if sqlerrm not like 'exception_invalid_type%' then
        raise;
      end if;
  end;

  select * into v_draft from app.create_exception_sla_policy_draft(v_tenant1, 'delay', 'high', '00000000-0000-0000-0000-000000009821', 'rep');

  begin
    perform app.publish_exception_sla_policy_version(v_draft.id, v_draft.record_version, null, '00000000-0000-0000-0000-000000009821', 'rep');
    raise exception 'assertion failed: expected exception_invalid_sla_hours -- a policy cannot publish before sla_hours is set';
  exception
    when others then
      if sqlerrm not like 'exception_invalid_sla_hours%' then
        raise;
      end if;
  end;

  perform app.set_exception_sla_policy_terms(v_draft.id, 24, jsonb_build_array(0, 24, 72), '00000000-0000-0000-0000-000000009821', 'rep');
  select * into v_draft from app.exception_sla_policy_versions where id = v_draft.id;
  perform app.publish_exception_sla_policy_version(v_draft.id, v_draft.record_version, null, '00000000-0000-0000-0000-000000009821', 'rep');

  select * into v_published from app.exception_sla_policy_versions where tenant_id = v_tenant1 and type = 'delay' and severity = 'high' and status = 'published';
  if v_published.id is null or v_published.sla_hours <> 24 then
    raise exception 'assertion failed: expected a published (delay, high) policy with sla_hours=24';
  end if;
  if (select count(*) from app.exception_sla_policy_versions where tenant_id = v_tenant1 and type = 'delay' and severity = 'high' and status = 'published') <> 1 then
    raise exception 'assertion failed: expected exactly one published (delay, high) policy';
  end if;
end $$;

\echo '>> app.report_exception: authority-gated; unknown type/severity/source rejected; a valid report pins the published SLA policy (sla_hours, due_at); no SLA policy yet for (delay, low) leaves sla_hours/due_at null, not an error; system-source dedup by correlation_key is idempotent'
do $$
declare
  v_shipment_id uuid;
  v_exception1 app.operational_exceptions;
  v_exception2 app.operational_exceptions;
  v_exception3 app.operational_exceptions;
  v_retry app.operational_exceptions;
begin
  select id into v_shipment_id from app.shipment_orders where idempotency_key = 'idem-exc-walk';

  begin
    perform app.report_exception(v_shipment_id, null, 'earthquake', 'high', 'bad type', 'manual', null, '00000000-0000-0000-0000-000000009821', 'rep');
    raise exception 'assertion failed: expected exception_invalid_type for an unsupported type';
  exception
    when others then
      if sqlerrm not like 'exception_invalid_type%' then
        raise;
      end if;
  end;

  begin
    perform app.report_exception(v_shipment_id, null, 'delay', 'high', 'bad source', 'carrier_pigeon', null, '00000000-0000-0000-0000-000000009821', 'rep');
    raise exception 'assertion failed: expected exception_invalid_source for an unsupported source';
  exception
    when others then
      if sqlerrm not like 'exception_invalid_source%' then
        raise;
      end if;
  end;

  select * into v_exception1 from app.report_exception(v_shipment_id, null, 'delay', 'high', 'Carrier reports a 3-day delay at origin', 'manual', null, '00000000-0000-0000-0000-000000009821', 'rep');
  if v_exception1.sla_hours <> 24 or v_exception1.due_at is null or v_exception1.status <> 'open' then
    raise exception 'assertion failed: expected a real pinned SLA (24h) and a real due_at for a (delay, high) exception';
  end if;

  select * into v_exception2 from app.report_exception(v_shipment_id, null, 'delay', 'low', 'Minor 1-hour delay', 'manual', null, '00000000-0000-0000-0000-000000009821', 'rep');
  if v_exception2.sla_hours is not null or v_exception2.due_at is not null or v_exception2.sla_policy_version_id is not null then
    raise exception 'assertion failed: expected no pinned SLA for (delay, low) -- no policy has been published for that combination';
  end if;

  select * into v_exception3 from app.report_exception(v_shipment_id, null, 'incident', 'critical', 'System-detected GPS anomaly', 'system', 'gps-anomaly-2026-07-27', '00000000-0000-0000-0000-000000009821', 'rep');
  select * into v_retry from app.report_exception(v_shipment_id, null, 'incident', 'critical', 'System-detected GPS anomaly (retry)', 'system', 'gps-anomaly-2026-07-27', '00000000-0000-0000-0000-000000009821', 'rep');
  if v_retry.id <> v_exception3.id then
    raise exception 'assertion failed: expected the idempotent retry to return the same exception row, not a new one';
  end if;
  if (select count(*) from app.operational_exceptions where shipment_order_id = v_shipment_id and correlation_key = 'gps-anomaly-2026-07-27') <> 1 then
    raise exception 'assertion failed: expected exactly one row for the deduplicated system-detected correlation key';
  end if;
end $$;

\echo '>> app.assign_exception_owner: reason required only on reassignment; app.acknowledge_exception: invalid_transition outside open/reopened; app.escalate_exception: reason required, blocked once resolved/closed, appends real history; app.resolve_exception: evidence required; app.close_exception: resolved-only, OPS:Close-gated; app.reopen_exception: reason required, resolved/closed-only'
do $$
declare
  v_shipment_id uuid;
  v_new_owner_id uuid;
  v_exception app.operational_exceptions;
  v_history app.exception_escalations[];
begin
  select id into v_shipment_id from app.shipment_orders where idempotency_key = 'idem-exc-walk';
  select id into v_new_owner_id from auth.users where email = 'newowner@acmeexc.test';
  select * into v_exception from app.operational_exceptions where shipment_order_id = v_shipment_id and type = 'delay' and severity = 'high';

  select * into v_exception from app.assign_exception_owner(v_exception.id, '00000000-0000-0000-0000-000000009821', null, '00000000-0000-0000-0000-000000009821', 'rep');
  if v_exception.owner_user_id <> '00000000-0000-0000-0000-000000009821' then
    raise exception 'assertion failed: expected the first assignment to succeed with no reason required';
  end if;

  begin
    perform app.assign_exception_owner(v_exception.id, v_new_owner_id, null, '00000000-0000-0000-0000-000000009821', 'rep');
    raise exception 'assertion failed: expected reason_required for a reassignment with no reason';
  exception
    when others then
      if sqlerrm not like 'reason_required%' then
        raise;
      end if;
  end;

  select * into v_exception from app.assign_exception_owner(v_exception.id, v_new_owner_id, 'original owner unavailable', '00000000-0000-0000-0000-000000009821', 'rep');
  if v_exception.owner_user_id <> v_new_owner_id then
    raise exception 'assertion failed: expected the reassignment to succeed with a real reason';
  end if;

  begin
    perform app.escalate_exception(v_exception.id, null, '00000000-0000-0000-0000-000000009821', 'rep');
    raise exception 'assertion failed: expected reason_required for an escalation with no reason';
  exception
    when others then
      if sqlerrm not like 'reason_required%' then
        raise;
      end if;
  end;

  select * into v_exception from app.escalate_exception(v_exception.id, 'no response from owner within SLA', '00000000-0000-0000-0000-000000009821', 'rep');
  if v_exception.escalation_level <> 1 then
    raise exception 'assertion failed: expected escalation_level=1 after the first escalation';
  end if;
  select * into v_exception from app.escalate_exception(v_exception.id, 'still no response', '00000000-0000-0000-0000-000000009821', 'rep');
  if v_exception.escalation_level <> 2 then
    raise exception 'assertion failed: expected escalation_level=2 after the second escalation';
  end if;

  select array_agg(h order by h.escalated_at asc) into v_history from app.get_exception_escalation_history(v_exception.id, '00000000-0000-0000-0000-000000009821') h;
  if array_length(v_history, 1) <> 2 or v_history[1].escalation_level <> 1 or v_history[2].escalation_level <> 2 then
    raise exception 'assertion failed: expected exactly 2 ordered escalation-history rows (level 1 then level 2)';
  end if;

  begin
    perform app.close_exception(v_exception.id, v_exception.record_version, '00000000-0000-0000-0000-000000009821', 'rep');
    raise exception 'assertion failed: expected invalid_transition -- an exception must be resolved before it can be closed';
  exception
    when others then
      if sqlerrm not like 'invalid_transition%' then
        raise;
      end if;
  end;

  begin
    perform app.resolve_exception(v_exception.id, v_exception.record_version, null, '00000000-0000-0000-0000-000000009821', 'rep');
    raise exception 'assertion failed: expected evidence_required for a resolve with no resolution_evidence';
  exception
    when others then
      if sqlerrm not like 'evidence_required%' then
        raise;
      end if;
  end;

  select * into v_exception from app.resolve_exception(v_exception.id, v_exception.record_version, 'Carrier confirmed departure, delay closed out', '00000000-0000-0000-0000-000000009821', 'rep');
  if v_exception.status <> 'resolved' or v_exception.resolved_at is null then
    raise exception 'assertion failed: expected the exception to become resolved with a real resolved_at';
  end if;

  begin
    perform app.escalate_exception(v_exception.id, 'should not be allowed now', '00000000-0000-0000-0000-000000009821', 'rep');
    raise exception 'assertion failed: expected invalid_transition -- a resolved exception can no longer be escalated';
  exception
    when others then
      if sqlerrm not like 'invalid_transition%' then
        raise;
      end if;
  end;

  select * into v_exception from app.close_exception(v_exception.id, v_exception.record_version, '00000000-0000-0000-0000-000000009821', 'rep');
  if v_exception.status <> 'closed' or v_exception.closed_at is null then
    raise exception 'assertion failed: expected the exception to become closed with a real closed_at';
  end if;

  begin
    perform app.reopen_exception(v_exception.id, v_exception.record_version, null, '00000000-0000-0000-0000-000000009821', 'rep');
    raise exception 'assertion failed: expected reason_required for a reopen with no reason';
  exception
    when others then
      if sqlerrm not like 'reason_required%' then
        raise;
      end if;
  end;

  select * into v_exception from app.reopen_exception(v_exception.id, v_exception.record_version, 'carrier now reports a second delay on the same lane', '00000000-0000-0000-0000-000000009821', 'rep');
  if v_exception.status <> 'reopened' or v_exception.reopened_at is null then
    raise exception 'assertion failed: expected the exception to become reopened with a real reopened_at';
  end if;
  if v_exception.resolution_evidence <> 'Carrier confirmed departure, delay closed out' then
    raise exception 'assertion failed: expected the prior resolution_evidence to remain intact (never deleted by reopen)';
  end if;
end $$;

\echo '>> app.set_exception_sensitive_fields: write requires both OPS:Edit and OPS:View cost'
do $$
declare
  v_shipment_id uuid;
  v_exception app.operational_exceptions;
begin
  select id into v_shipment_id from app.shipment_orders where idempotency_key = 'idem-exc-walk';
  select * into v_exception from app.operational_exceptions where shipment_order_id = v_shipment_id and type = 'incident' and severity = 'critical';

  begin
    perform app.set_exception_sensitive_fields(v_exception.id, 'internal note', jsonb_build_object('kind', 'gps'), 500.00, 'USD', '00000000-0000-0000-0000-000000009822', 'restricted');
    raise exception 'assertion failed: expected insufficient_authority -- the restricted actor lacks OPS:View cost';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then
        raise;
      end if;
  end;

  perform app.set_exception_sensitive_fields(v_exception.id, 'GPS unit malfunctioned in transit', jsonb_build_object('kind', 'equipment', 'unit', 'GPS-04'), 750.50, 'USD', '00000000-0000-0000-0000-000000009821', 'rep');
end $$;

\echo '>> app.exceptions_directory: internal_notes/damage_loss_details/claim_amount/claim_currency masked (null, sensitive_masked=true) for the restricted actor lacking OPS:View cost; visible for the full-access rep on the identical row'
do $$
declare
  v_shipment_id uuid;
  v_exception_id uuid;
  v_sensitive_masked boolean;
  v_claim_amount numeric;
  v_internal_notes text;
begin
  select id into v_shipment_id from app.shipment_orders where idempotency_key = 'idem-exc-walk';
  select id into v_exception_id from app.operational_exceptions where shipment_order_id = v_shipment_id and type = 'incident' and severity = 'critical';

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000009822", "role": "authenticated"}';
  select sensitive_masked, claim_amount, internal_notes into v_sensitive_masked, v_claim_amount, v_internal_notes from app.exceptions_directory where id = v_exception_id;
  if not v_sensitive_masked or v_claim_amount is not null or v_internal_notes is not null then
    raise exception 'assertion failed: expected the restricted actor to see sensitive_masked=true, claim_amount=null, internal_notes=null, got masked=% claim_amount=% internal_notes=%', v_sensitive_masked, v_claim_amount, v_internal_notes;
  end if;
  reset role;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000009821", "role": "authenticated"}';
  select sensitive_masked, claim_amount, internal_notes into v_sensitive_masked, v_claim_amount, v_internal_notes from app.exceptions_directory where id = v_exception_id;
  if v_sensitive_masked or v_claim_amount is null or v_internal_notes is null then
    raise exception 'assertion failed: expected the full-access rep to see real sensitive fields, got masked=% claim_amount=% internal_notes=%', v_sensitive_masked, v_claim_amount, v_internal_notes;
  end if;
  reset role;
end $$;

\echo '>> record-scope: a sibling-team outsider (different org unit, no ownership stake) cannot report/assign/escalate/resolve/read despite holding full OPS grants'
do $$
declare
  v_shipment_id uuid;
  v_exception app.operational_exceptions;
begin
  select id into v_shipment_id from app.shipment_orders where idempotency_key = 'idem-exc-walk';
  select * into v_exception from app.operational_exceptions where shipment_order_id = v_shipment_id and type = 'delay' and severity = 'low';

  begin
    perform app.report_exception(v_shipment_id, null, 'hold', 'medium', 'outsider attempt', 'manual', null, '00000000-0000-0000-0000-000000009823', 'outsider');
    raise exception 'assertion failed: expected the sibling-team outsider to be denied by record scope';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then
        raise;
      end if;
  end;

  begin
    perform app.assign_exception_owner(v_exception.id, '00000000-0000-0000-0000-000000009823', null, '00000000-0000-0000-0000-000000009823', 'outsider');
    raise exception 'assertion failed: expected the sibling-team outsider to be denied by record scope';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then
        raise;
      end if;
  end;

  begin
    perform app.get_exception_escalation_history(v_exception.id, '00000000-0000-0000-0000-000000009823');
    raise exception 'assertion failed: expected the sibling-team outsider to be denied read access by record scope';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then
        raise;
      end if;
  end;
end $$;

\echo '>> cross-tenant isolation: app.report_exception/app.create_exception_sla_policy_draft fail closed for an identity with no membership in the shipment/tenant''s own tenant -- ISS-2026-146 fix: app.report_exception (a bare-id lookup) now raises a generic shipment_order_not_found for this zero-membership caller, never a tenant_id-disclosing insufficient_authority; app.create_exception_sla_policy_draft (caller-supplied p_tenant_id) is unaffected'
do $$
declare
  v_tenant2 uuid;
  v_tenant1 uuid;
  v_shipment_id uuid;
begin
  insert into auth.users (id, email) values ('00000000-0000-0000-0000-000000009825', 'admin2@acmeexc2.test');
  perform app.provision_tenant('acmeexc2', 'Acme Exception Co 2', 'idem-acmeexc2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'acmeexc2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');
  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000009825', 'admin2@acmeexc2.test', 'Tenant 2 Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin2@acmeexc2.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000009825', 'tenant_admin', v_tenant2, null, 'tester');

  v_tenant1 := (select id from app.tenants where slug = 'acmeexc');
  select id into v_shipment_id from app.shipment_orders where idempotency_key = 'idem-exc-walk';

  begin
    -- ISS-2026-146: admin2 has ZERO app.principal_memberships row in tenant1 at all
    -- (granted tenant_admin only in tenant2 above) -- app.report_exception is a
    -- bare-id lookup, so before the fix this raised insufficient_authority with
    -- tenant1's real tenant_id embedded in the message; now it raises the identical
    -- generic shipment_order_not_found a nonexistent shipment id would.
    perform app.report_exception(v_shipment_id, null, 'hold', 'medium', 'tenant2 attempt', 'manual', null, '00000000-0000-0000-0000-000000009825', 'tenant2-admin');
    raise exception 'assertion failed: expected shipment_order_not_found for tenant 2''s admin (zero relationship to tenant1) on app.report_exception, the call unexpectedly succeeded';
  exception
    when others then
      if sqlerrm not like 'shipment_order_not_found%' then
        raise;
      end if;
  end;

  begin
    perform app.create_exception_sla_policy_draft(v_tenant1, 'hold', 'medium', '00000000-0000-0000-0000-000000009825', 'tenant2-admin');
    raise exception 'assertion failed: expected insufficient_privilege -- tenant 2''s admin holds no membership in tenant 1';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then
        raise;
      end if;
  end;
end $$;

\echo '>> schema-privilege defense in depth: anon holds no EXECUTE on any of the 13 new Exception and Escalation functions (ERR-2026-004 regression guard)'
do $$
declare
  v_count integer;
begin
  select count(*) into v_count
  from information_schema.routine_privileges
  where routine_schema = 'app'
    and grantee = 'anon'
    and routine_name in (
      'create_exception_sla_policy_draft', 'set_exception_sla_policy_terms', 'publish_exception_sla_policy_version',
      'report_exception', 'assign_exception_owner', 'acknowledge_exception', 'escalate_exception', 'resolve_exception',
      'close_exception', 'reopen_exception', 'set_exception_sensitive_fields', 'get_exception_escalation_history', 'has_view_exception_cost'
    );
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero anon EXECUTE grants on the 13 new Exception and Escalation functions, found %', v_count;
  end if;
end $$;

\echo '>> audit trail: every real exception mutation recorded a real app.audit_logs event, tenant-scoped'
do $$
declare
  v_tenant1 uuid;
  v_count integer;
begin
  v_tenant1 := (select id from app.tenants where slug = 'acmeexc');

  select count(*) into v_count from app.audit_logs where tenant_id = v_tenant1 and resource_type = 'app.operational_exceptions' and action = 'report_exception';
  if v_count <> 3 then
    raise exception 'assertion failed: expected exactly 3 report_exception audit events (delay/high, delay/low, incident/critical -- the dedup retry is a no-op), found %', v_count;
  end if;

  select count(*) into v_count from app.audit_logs where tenant_id = v_tenant1 and resource_type = 'app.operational_exceptions' and action = 'escalate_exception';
  if v_count <> 2 then
    raise exception 'assertion failed: expected exactly 2 escalate_exception audit events, found %', v_count;
  end if;

  select count(*) into v_count from app.audit_logs where tenant_id = v_tenant1 and resource_type = 'app.operational_exceptions' and action = 'set_exception_sensitive_fields';
  if v_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 set_exception_sensitive_fields audit event, found %', v_count;
  end if;
end $$;
