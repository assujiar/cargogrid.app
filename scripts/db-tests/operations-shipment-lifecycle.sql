-- Real, executable test evidence for OPS-170 (Shipment Lifecycle, CG-S8-OPS-004) -- run
-- via `pnpm run db:test` against a real, disposable Postgres database.

\set ON_ERROR_STOP on

\echo '>> setup: one tenant, a company/team-a/team-b org hierarchy, a bootstrap tenant-admin, a rep (COM:Create/Edit/Approve/View/View cost + OPS:Create/Edit), an OPS-viewer-only actor, a sibling-team outsider, a global Supreme Admin, one confirmed Job Order, and two confirmed Shipment Orders (one for the full lifecycle walk, one kept simple for auxiliary checks)'
do $$
declare
  v_tenant1 uuid;
  v_team_a uuid;
  v_team_b uuid;
  v_rep_role uuid;
  v_rep_draft app.role_versions;
  v_viewer_role uuid;
  v_viewer_draft app.role_versions;
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
    ('00000000-0000-0000-0000-000000009980', 'admin@acmelife.test'),
    ('00000000-0000-0000-0000-000000009981', 'repa@acmelife.test'),
    ('00000000-0000-0000-0000-000000009982', 'viewer@acmelife.test'),
    ('00000000-0000-0000-0000-000000009983', 'outsider@acmelife.test'),
    ('00000000-0000-0000-0000-000000009984', 'supreme@acmelife.test');

  perform app.provision_tenant('acmelife', 'Acme Lifecycle Co', 'idem-acmelife', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'acmelife');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');

  perform app.create_org_unit(v_tenant1, 'company', null, 'ACMELIFE-CO', 'Acme Lifecycle Co', 'tester');
  perform app.create_org_unit(v_tenant1, 'department', (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMELIFE-CO'), 'ACMELIFE-TEAM-A', 'Team A', 'tester');
  v_team_a := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMELIFE-TEAM-A');
  perform app.create_org_unit(v_tenant1, 'department', (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMELIFE-CO'), 'ACMELIFE-TEAM-B', 'Team B', 'tester');
  v_team_b := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMELIFE-TEAM-B');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000009980', 'admin@acmelife.test', 'Life Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@acmelife.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000009980', 'tenant_admin', v_tenant1, null, 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000009981', 'repa@acmelife.test', 'Rep A', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'repa@acmelife.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000009982', 'viewer@acmelife.test', 'OPS Viewer', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'viewer@acmelife.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000009983', 'outsider@acmelife.test', 'Team B Outsider', v_team_b, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'outsider@acmelife.test'), 'active', 'onboarded', 'tester');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000009984', 'supreme_admin', null, null, 'tester');

  v_rep_role := (app.create_role(v_tenant1, 'Life Rep', 'full commercial + ops grants', 'tester')).id;
  v_rep_draft := app.create_role_version(v_rep_role, 'tester');
  perform app.set_role_version_permissions(
    v_rep_draft.id,
    array(select id from app.permissions where (resource_module_code = 'COM' and action in ('Create', 'Edit', 'Approve', 'View', 'View cost'))
      or (resource_module_code = 'OPS' and action in ('Create', 'Edit', 'View'))),
    'tester'
  );
  perform app.publish_role_version(v_rep_draft.id, now(), 'tester');
  -- Granter is the bootstrap tenant-admin (9980), never 9981 itself -- 'View cost' is
  -- a protected permission and app.assign_role's own self_escalation guard blocks an
  -- actor from granting themselves a role version carrying one.
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_rep_role and status = 'published'), '00000000-0000-0000-0000-000000009981', '00000000-0000-0000-0000-000000009980', 'tester');

  v_viewer_role := (app.create_role(v_tenant1, 'Life Ops Viewer', 'OPS:View only, no Edit', 'tester')).id;
  v_viewer_draft := app.create_role_version(v_viewer_role, 'tester');
  perform app.set_role_version_permissions(
    v_viewer_draft.id,
    array(select id from app.permissions where resource_module_code = 'OPS' and action in ('View')),
    'tester'
  );
  perform app.publish_role_version(v_viewer_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_viewer_role and status = 'published'), '00000000-0000-0000-0000-000000009982', '00000000-0000-0000-0000-000000009982', 'tester');

  v_outsider_role := (app.create_role(v_tenant1, 'Life Outsider', 'sibling team, full grants', 'tester')).id;
  v_outsider_draft := app.create_role_version(v_outsider_role, 'tester');
  perform app.set_role_version_permissions(
    v_outsider_draft.id,
    array(select id from app.permissions where (resource_module_code = 'COM' and action in ('Create', 'Edit', 'View'))
      or (resource_module_code = 'OPS' and action in ('Create', 'Edit', 'View'))),
    'tester'
  );
  perform app.publish_role_version(v_outsider_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_outsider_role and status = 'published'), '00000000-0000-0000-0000-000000009983', '00000000-0000-0000-0000-000000009981', 'tester');

  perform app.capture_lead(v_tenant1, 'manual', null, 'Life Test Co', 'Jane Life', 'jane@lifetest.test', '0811',
    '00000000-0000-0000-0000-000000009981', v_team_a, '00000000-0000-0000-0000-000000009981', 'tester');
  select * into v_lead from app.leads where email = 'jane@lifetest.test';
  perform app.qualify_lead(v_lead.id, v_lead.record_version, '00000000-0000-0000-0000-000000009981', 'tester');
  select * into v_lead from app.leads where id = v_lead.id;
  perform app.convert_lead_to_prospect(v_lead.id, 'Life Test Co', 'LTC', '99.999.999.9-999.000',
    jsonb_build_object('line1', 'Jl. Rasuna Said 1', 'city', 'Jakarta', 'country', 'ID'),
    '00000000-0000-0000-0000-000000009981', 'tester');
  select * into v_prospect from app.prospects where lead_id = v_lead.id;

  select * into v_contact from app.create_contact(v_tenant1, 'Jane Life Ops', 'Procurement Lead', 'jane@lifetest.test', '0811', '00000000-0000-0000-0000-000000009981', v_team_a, '00000000-0000-0000-0000-000000009981', 'tester');
  perform app.link_contact_to_record(v_contact.id, 'prospect', v_prospect.id, 'primary', true, '00000000-0000-0000-0000-000000009981', 'tester');

  select * into v_opportunity from app.create_opportunity(
    v_tenant1, v_prospect.id, 'Life test lane',
    jsonb_build_object('service_type', 'ocean_freight', 'cargo_description', 'General cargo', 'origin', 'Jakarta', 'destination', 'Surabaya', 'target_ready_date', '2026-08-01'),
    '00000000-0000-0000-0000-000000009981', v_team_a, '00000000-0000-0000-0000-000000009981', 'tester'
  );
  select * into v_request from app.request_costing(v_opportunity.id, '[]'::jsonb, null, '00000000-0000-0000-0000-000000009981', 'tester');
  select * into v_rate from app.create_rate_version(
    v_tenant1, 'VENDOR-LIFE-1', 'Contoso Ocean Line', 'ocean_freight', 'FCL', 'Jakarta', 'Surabaya', '20ft',
    null, null, null, null, 'IDR', 10000000, null, '[]'::jsonb, now(), null, null, '00000000-0000-0000-0000-000000009980', 'tester'
  );
  perform app.approve_rate_version(v_rate.id, v_rate.record_version, '00000000-0000-0000-0000-000000009980', 'tester');
  select * into v_selection from app.select_vendor_rate(v_request.id, v_rate.id, false, null, null, null, '00000000-0000-0000-0000-000000009981', 'tester');

  select * into v_rule from app.create_margin_rule_version(v_tenant1, 20.00, 'half_up', '00000000-0000-0000-0000-000000009981', 'tester');
  perform app.publish_margin_rule_version(v_rule.id, v_rule.record_version, null, '00000000-0000-0000-0000-000000009981', 'tester');
  perform app.calculate_margin(v_selection.id, 15000000, 'IDR', 0, '00000000-0000-0000-0000-000000009981', 'tester');
  select id into v_calc_id from app.margin_calculations where rate_selection_id = v_selection.id and is_current;

  select * into v_quote from app.create_quotation_draft(v_tenant1, v_opportunity.id, 'IDR', now() + interval '14 days', v_contact.id, null, null, '00000000-0000-0000-0000-000000009981', 'tester');
  perform app.add_quotation_line(v_quote.id, v_quote.record_version, 'service', 'Ocean freight ops lane', v_calc_id, 1, 15000000, 0, 0, '00000000-0000-0000-0000-000000009981', 'tester');
  select * into v_quote from app.quotations where id = v_quote.id;
  perform app.submit_quotation(v_quote.id, v_quote.record_version, '00000000-0000-0000-0000-000000009981', 'tester');
  select * into v_send from app.send_quotation_for_acceptance(v_quote.id, null, 'email', '00000000-0000-0000-0000-000000009981', 'tester');
  perform app.record_quotation_customer_decision(v_send.raw_token, 'accepted', 'Jane Life Ops', null, null, null, null, null);
  select * into v_quote from app.quotations where id = v_quote.id;
  select * into v_account from app.convert_quotation_to_account(v_quote.id, null, null, '00000000-0000-0000-0000-000000009981', 'rep');
  select * into v_handoff from app.prepare_job_order_handoff(v_quote.id, '00000000-0000-0000-0000-000000009981', 'rep');

  select * into v_job_order from app.prepare_job_order(v_handoff.id, '00000000-0000-0000-0000-000000009981', 'rep');
  select * into v_job_order from app.confirm_job_order(v_job_order.id, v_job_order.record_version, '00000000-0000-0000-0000-000000009981', 'rep');

  select * into v_shipment_walk from app.create_shipment_order_from_job(
    v_job_order.id, 'idem-life-walk', null, null, 'ocean_freight', 'sea', 'Jakarta', 'Surabaya',
    now() + interval '2 days', now() + interval '5 days', 10, 1000, 20, 10, 1000, 20, null,
    '00000000-0000-0000-0000-000000009981', 'rep'
  );
  select * into v_shipment_walk from app.confirm_shipment_order(v_shipment_walk.id, v_shipment_walk.record_version, '00000000-0000-0000-0000-000000009981', 'rep');

  select * into v_shipment_aux from app.create_shipment_order_from_job(
    v_job_order.id, 'idem-life-aux', null, null, 'ocean_freight', 'sea', 'Jakarta', 'Surabaya',
    now() + interval '2 days', now() + interval '5 days', null, null, null, null, null, null, 'auxiliary fixture split',
    '00000000-0000-0000-0000-000000009981', 'rep'
  );
  select * into v_shipment_aux from app.confirm_shipment_order(v_shipment_aux.id, v_shipment_aux.record_version, '00000000-0000-0000-0000-000000009981', 'rep');
end $$;

\echo '>> app.transition_shipment_order: authority-gated (an OPS:View-only actor denied); rejects an illegal skip-ahead transition; requires a non-empty reason entering held; a valid confirmed -> planned transition succeeds'
do $$
declare
  v_shipment app.shipment_orders;
begin
  select * into v_shipment from app.shipment_orders where idempotency_key = 'idem-life-walk';

  begin
    perform app.transition_shipment_order(v_shipment.id, 'planned', v_shipment.record_version, null, null, 'idem-viewer-attempt', '00000000-0000-0000-0000-000000009982', 'viewer');
    raise exception 'assertion failed: expected insufficient_authority for an OPS:View-only actor';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then
        raise;
      end if;
  end;

  begin
    perform app.transition_shipment_order(v_shipment.id, 'delivered', v_shipment.record_version, null, 'POD-0001', 'idem-skip-ahead', '00000000-0000-0000-0000-000000009981', 'rep');
    raise exception 'assertion failed: expected invalid_transition for confirmed -> delivered (an illegal skip-ahead)';
  exception
    when others then
      if sqlerrm not like 'invalid_transition%' then
        raise;
      end if;
  end;

  begin
    perform app.transition_shipment_order(v_shipment.id, 'held', v_shipment.record_version, null, null, 'idem-hold-no-reason', '00000000-0000-0000-0000-000000009981', 'rep');
    raise exception 'assertion failed: expected reason_required entering held without a reason';
  exception
    when others then
      if sqlerrm not like 'reason_required%' then
        raise;
      end if;
  end;

  select * into v_shipment from app.transition_shipment_order(v_shipment.id, 'planned', v_shipment.record_version, null, null, 'idem-confirmed-to-planned', '00000000-0000-0000-0000-000000009981', 'rep');
  if v_shipment.status <> 'planned' then
    raise exception 'assertion failed: expected confirmed -> planned to succeed';
  end if;
end $$;

\echo '>> app.transition_shipment_order: hold/resume -- planned -> held (reason recorded, held_from_status = planned) -> resume only into held_from_status, never an arbitrary state'
do $$
declare
  v_shipment app.shipment_orders;
begin
  select * into v_shipment from app.shipment_orders where idempotency_key = 'idem-life-walk';

  select * into v_shipment from app.transition_shipment_order(v_shipment.id, 'held', v_shipment.record_version, 'customer requested a hold pending payment', null, 'idem-hold-1', '00000000-0000-0000-0000-000000009981', 'rep');
  if v_shipment.status <> 'held' or v_shipment.held_from_status <> 'planned' then
    raise exception 'assertion failed: expected held with held_from_status=planned, got status=% held_from_status=%', v_shipment.status, v_shipment.held_from_status;
  end if;

  begin
    perform app.transition_shipment_order(v_shipment.id, 'assigned', v_shipment.record_version, null, null, 'idem-resume-wrong-target', '00000000-0000-0000-0000-000000009981', 'rep');
    raise exception 'assertion failed: expected invalid_transition -- a held shipment may only resume into its own held_from_status (planned), not an arbitrary state';
  exception
    when others then
      if sqlerrm not like 'invalid_transition%' then
        raise;
      end if;
  end;

  select * into v_shipment from app.transition_shipment_order(v_shipment.id, 'planned', v_shipment.record_version, null, null, 'idem-resume-1', '00000000-0000-0000-0000-000000009981', 'rep');
  if v_shipment.status <> 'planned' or v_shipment.held_from_status is not null then
    raise exception 'assertion failed: expected resume back to planned with held_from_status cleared';
  end if;
end $$;

\echo '>> app.transition_shipment_order: the remaining forward path (planned -> assigned -> dispatched -> in_transit), evidence_required entering delivered without an evidence_ref, and a valid in_transit -> delivered -> epod -> closed walk'
do $$
declare
  v_shipment app.shipment_orders;
begin
  select * into v_shipment from app.shipment_orders where idempotency_key = 'idem-life-walk';

  select * into v_shipment from app.transition_shipment_order(v_shipment.id, 'assigned', v_shipment.record_version, null, null, 'idem-assigned', '00000000-0000-0000-0000-000000009981', 'rep');
  select * into v_shipment from app.transition_shipment_order(v_shipment.id, 'dispatched', v_shipment.record_version, null, null, 'idem-dispatched', '00000000-0000-0000-0000-000000009981', 'rep');
  select * into v_shipment from app.transition_shipment_order(v_shipment.id, 'in_transit', v_shipment.record_version, null, null, 'idem-in-transit', '00000000-0000-0000-0000-000000009981', 'rep');

  begin
    perform app.transition_shipment_order(v_shipment.id, 'delivered', v_shipment.record_version, null, null, 'idem-delivered-no-evidence', '00000000-0000-0000-0000-000000009981', 'rep');
    raise exception 'assertion failed: expected evidence_required entering delivered without an evidence_ref';
  exception
    when others then
      if sqlerrm not like 'evidence_required%' then
        raise;
      end if;
  end;

  select * into v_shipment from app.transition_shipment_order(v_shipment.id, 'delivered', v_shipment.record_version, null, 'POD-0001', 'idem-delivered', '00000000-0000-0000-0000-000000009981', 'rep');
  if v_shipment.status <> 'delivered' then
    raise exception 'assertion failed: expected in_transit -> delivered to succeed';
  end if;

  select * into v_shipment from app.transition_shipment_order(v_shipment.id, 'epod', v_shipment.record_version, null, 'EPOD-0001', 'idem-epod', '00000000-0000-0000-0000-000000009981', 'rep');
  select * into v_shipment from app.transition_shipment_order(v_shipment.id, 'closed', v_shipment.record_version, null, 'CLOSE-0001', 'idem-closed', '00000000-0000-0000-0000-000000009981', 'rep');
  if v_shipment.status <> 'closed' then
    raise exception 'assertion failed: expected epod -> closed to succeed';
  end if;
end $$;

\echo '>> app.transition_shipment_order: a closed shipment is terminal for an ordinary transition attempt, and reopening (-> delivered/epod) requires Supreme Admin (RPD-022) -- an ordinary rep is denied, Supreme succeeds'
do $$
declare
  v_shipment app.shipment_orders;
begin
  select * into v_shipment from app.shipment_orders where idempotency_key = 'idem-life-walk';

  begin
    perform app.transition_shipment_order(v_shipment.id, 'planned', v_shipment.record_version, null, null, 'idem-closed-invalid', '00000000-0000-0000-0000-000000009981', 'rep');
    raise exception 'assertion failed: expected invalid_transition -- closed may only reopen into delivered/epod';
  exception
    when others then
      if sqlerrm not like 'invalid_transition%' then
        raise;
      end if;
  end;

  begin
    perform app.transition_shipment_order(v_shipment.id, 'delivered', v_shipment.record_version, null, 'POD-0001', 'idem-reopen-rep-attempt', '00000000-0000-0000-0000-000000009981', 'rep');
    raise exception 'assertion failed: expected insufficient_authority -- reopening a closed shipment requires Supreme Admin';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then
        raise;
      end if;
  end;

  select * into v_shipment from app.transition_shipment_order(v_shipment.id, 'delivered', v_shipment.record_version, null, 'POD-0001', 'idem-reopen-supreme', '00000000-0000-0000-0000-000000009984', 'supreme');
  if v_shipment.status <> 'delivered' then
    raise exception 'assertion failed: expected Supreme Admin to successfully reopen closed -> delivered';
  end if;
end $$;

\echo '>> app.transition_shipment_order: idempotent on (tenant_id, shipment_order_id, idempotency_key) -- a repeated call with the same key returns the unchanged current row, never reprocessed; a stale expected_version is rejected; a cancelled shipment is a terminal state'
do $$
declare
  v_shipment app.shipment_orders;
  v_before app.shipment_orders;
  v_retry app.shipment_orders;
begin
  select * into v_shipment from app.shipment_orders where idempotency_key = 'idem-life-aux';
  v_before := v_shipment;

  select * into v_shipment from app.transition_shipment_order(v_shipment.id, 'planned', v_shipment.record_version, null, null, 'idem-aux-to-planned', '00000000-0000-0000-0000-000000009981', 'rep');

  select * into v_retry from app.transition_shipment_order(v_shipment.id, 'planned', v_before.record_version, null, null, 'idem-aux-to-planned', '00000000-0000-0000-0000-000000009981', 'rep');
  if v_retry.status <> v_shipment.status or v_retry.record_version <> v_shipment.record_version then
    raise exception 'assertion failed: expected the idempotent retry to return the identical current row unchanged';
  end if;

  begin
    perform app.transition_shipment_order(v_shipment.id, 'assigned', v_shipment.record_version + 99, null, null, 'idem-aux-stale', '00000000-0000-0000-0000-000000009981', 'rep');
    raise exception 'assertion failed: expected stale_version to be rejected';
  exception
    when others then
      if sqlerrm not like 'stale_version%' then
        raise;
      end if;
  end;

  select * into v_shipment from app.transition_shipment_order(v_shipment.id, 'cancelled', v_shipment.record_version, 'customer no longer needs this split', null, 'idem-aux-cancel', '00000000-0000-0000-0000-000000009981', 'rep');
  if v_shipment.status <> 'cancelled' then
    raise exception 'assertion failed: expected planned -> cancelled to succeed';
  end if;

  begin
    perform app.transition_shipment_order(v_shipment.id, 'planned', v_shipment.record_version, null, null, 'idem-aux-post-cancel', '00000000-0000-0000-0000-000000009981', 'rep');
    raise exception 'assertion failed: expected invalid_transition -- cancelled is a terminal state';
  exception
    when others then
      if sqlerrm not like 'invalid_transition%' then
        raise;
      end if;
  end;
end $$;

\echo '>> record-scope: a sibling-team outsider (different org unit, no ownership stake) cannot access the Shipment Order via app.transition_shipment_order/app.get_shipment_status_history despite holding full OPS/COM permissions'
do $$
declare
  v_shipment app.shipment_orders;
begin
  select * into v_shipment from app.shipment_orders where idempotency_key = 'idem-life-walk';

  begin
    perform app.transition_shipment_order(v_shipment.id, 'epod', v_shipment.record_version, null, 'EPOD-0002', 'idem-outsider-attempt', '00000000-0000-0000-0000-000000009983', 'outsider');
    raise exception 'assertion failed: expected the sibling-team outsider to be denied by record scope';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then
        raise;
      end if;
  end;

  begin
    perform app.get_shipment_status_history(v_shipment.id, '00000000-0000-0000-0000-000000009983');
    raise exception 'assertion failed: expected the sibling-team outsider to be denied reading the transition history';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then
        raise;
      end if;
  end;
end $$;

\echo '>> cross-tenant isolation: app.transition_shipment_order/app.get_shipment_status_history fail closed for an identity with no membership in the Shipment Order''s own tenant -- ISS-2026-146 fix: app.transition_shipment_order (a bare-id lookup) now raises a generic shipment_order_not_found for this zero-membership caller, never a tenant_id-disclosing insufficient_authority; app.get_shipment_status_history (not part of this fix) is unaffected'
do $$
declare
  v_tenant2 uuid;
  v_shipment app.shipment_orders;
begin
  insert into auth.users (id, email) values ('00000000-0000-0000-0000-000000009985', 'admin2@acmelife2.test');
  perform app.provision_tenant('acmelife2', 'Acme Lifecycle Co 2', 'idem-acmelife2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'acmelife2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');
  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000009985', 'admin2@acmelife2.test', 'Tenant 2 Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin2@acmelife2.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000009985', 'tenant_admin', v_tenant2, null, 'tester');

  select * into v_shipment from app.shipment_orders where idempotency_key = 'idem-life-walk';

  begin
    -- ISS-2026-146: admin2 has ZERO app.principal_memberships row in tenant1 at all
    -- (granted tenant_admin only in tenant2 above) -- before the fix this raised
    -- insufficient_authority with tenant1's real tenant_id embedded in the message;
    -- now it raises the identical generic shipment_order_not_found a nonexistent
    -- shipment id would.
    perform app.transition_shipment_order(v_shipment.id, 'epod', v_shipment.record_version, null, 'EPOD-0003', 'idem-cross-tenant', '00000000-0000-0000-0000-000000009985', 'tenant2-admin');
    raise exception 'assertion failed: expected shipment_order_not_found for tenant 2''s admin (zero relationship to tenant1) on app.transition_shipment_order, the call unexpectedly succeeded';
  exception
    when others then
      if sqlerrm not like 'shipment_order_not_found%' then
        raise;
      end if;
  end;

  begin
    perform app.get_shipment_status_history(v_shipment.id, '00000000-0000-0000-0000-000000009985');
    raise exception 'assertion failed: expected insufficient_privilege -- tenant 2''s admin holds no membership in tenant 1';
  exception
    when others then
      if sqlerrm not like 'insufficient_authority%' then
        raise;
      end if;
  end;
end $$;

\echo '>> schema-privilege defense in depth: anon holds no EXECUTE on either new Shipment Lifecycle function (ERR-2026-004 regression guard)'
do $$
declare
  v_count integer;
begin
  select count(*) into v_count
  from information_schema.routine_privileges
  where routine_schema = 'app'
    and grantee = 'anon'
    and routine_name in ('transition_shipment_order', 'get_shipment_status_history');
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero anon EXECUTE grants on the 2 new Shipment Lifecycle functions, found %', v_count;
  end if;
end $$;

\echo '>> app.get_shipment_status_history: authority-gated read, ordered oldest-first, and reflects every real transition on the shipment (confirmed->planned->held->planned(resume)->assigned->dispatched->in_transit->delivered->epod->closed->delivered(reopen))'
do $$
declare
  v_shipment app.shipment_orders;
  v_history app.shipment_status_transitions[];
  v_count integer;
begin
  select * into v_shipment from app.shipment_orders where idempotency_key = 'idem-life-walk';

  select array_agg(t order by t.occurred_at asc) into v_history from app.get_shipment_status_history(v_shipment.id, '00000000-0000-0000-0000-000000009981') t;
  select count(*) into v_count from unnest(v_history);
  if v_count <> 10 then
    raise exception 'assertion failed: expected exactly 10 recorded transitions, found %', v_count;
  end if;
  if v_history[1].from_status <> 'confirmed' or v_history[1].to_status <> 'planned' then
    raise exception 'assertion failed: expected the oldest transition to be confirmed -> planned, found % -> %', v_history[1].from_status, v_history[1].to_status;
  end if;
  if v_history[10].from_status <> 'closed' or v_history[10].to_status <> 'delivered' then
    raise exception 'assertion failed: expected the most recent transition to be the Supreme reopen (closed -> delivered), found % -> %', v_history[10].from_status, v_history[10].to_status;
  end if;
end $$;

\echo '>> audit trail: every real transition_shipment_order call recorded a real app.audit_logs event, tenant-scoped (12 total across both fixtures -- 10 on the walk shipment, 2 on the auxiliary shipment: to-planned and to-cancelled; the idempotent retry and the post-cancel invalid-transition attempt are both no-ops)'
do $$
declare
  v_tenant1 uuid;
  v_count integer;
begin
  v_tenant1 := (select id from app.tenants where slug = 'acmelife');
  select count(*) into v_count
  from app.audit_logs
  where tenant_id = v_tenant1
    and resource_type = 'app.shipment_orders'
    and action = 'transition_shipment_order';
  if v_count <> 12 then
    raise exception 'assertion failed: expected exactly 12 transition_shipment_order audit events (10 walk + 2 aux: to-planned, to-cancelled), found %', v_count;
  end if;
end $$;
