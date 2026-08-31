-- Real, executable test evidence for OPS-176 (Document Requirement, CG-S8-OPS-010)
-- -- run via `pnpm run db:test` against a real, disposable Postgres database.

\set ON_ERROR_STOP on

\echo '>> setup: one tenant, a company/team-a/team-b org hierarchy, a bootstrap tenant-admin, a rep (OPS full), a restricted actor (OPS:View only), a sibling-team outsider (OPS full but wrong record scope), a second tenant, one confirmed Job Order, and two confirmed Shipment Orders (sea/ocean_freight) plus one draft (not-found probe)'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
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
  v_shipment_a app.shipment_orders;
  v_shipment_b app.shipment_orders;
  v_shipment_draft app.shipment_orders;
  v_pod_draft app.config_versions;
  v_other_draft app.config_versions;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000023101', 'admin@acmedocreq.test'),
    ('00000000-0000-0000-0000-000000023102', 'repa@acmedocreq.test'),
    ('00000000-0000-0000-0000-000000023103', 'viewer@acmedocreq.test'),
    ('00000000-0000-0000-0000-000000023104', 'outsider@acmedocreq.test'),
    ('00000000-0000-0000-0000-000000023105', 'admin@gizmodocreq.test'),
    ('00000000-0000-0000-0000-000000023106', 'supreme@acmedocreq.test');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000023106', 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('acmedocreq', 'Acme Docreq Co', 'idem-acmedocreq', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'acmedocreq');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');

  perform app.provision_tenant('gizmodocreq', 'Gizmo Docreq Co', 'idem-gizmodocreq', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'gizmodocreq');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');
  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000023105', 'admin@gizmodocreq.test', 'Gizmo Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@gizmodocreq.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000023105', 'tenant_admin', v_tenant2, null, 'tester');

  perform app.create_org_unit(v_tenant1, 'company', null, 'ACMEDOCREQ-CO', 'Acme Docreq Co', 'tester');
  perform app.create_org_unit(v_tenant1, 'department', (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEDOCREQ-CO'), 'ACMEDOCREQ-TEAM-A', 'Team A', 'tester');
  v_team_a := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEDOCREQ-TEAM-A');
  perform app.create_org_unit(v_tenant1, 'department', (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEDOCREQ-CO'), 'ACMEDOCREQ-TEAM-B', 'Team B', 'tester');
  v_team_b := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEDOCREQ-TEAM-B');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000023101', 'admin@acmedocreq.test', 'Docreq Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@acmedocreq.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000023101', 'tenant_admin', v_tenant1, null, 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000023102', 'repa@acmedocreq.test', 'Rep A', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'repa@acmedocreq.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000023103', 'viewer@acmedocreq.test', 'OPS Viewer', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'viewer@acmedocreq.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000023104', 'outsider@acmedocreq.test', 'Team B Outsider', v_team_b, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'outsider@acmedocreq.test'), 'active', 'onboarded', 'tester');

  v_rep_role := (app.create_role(v_tenant1, 'Docreq Rep', 'full commercial + ops grants', 'tester')).id;
  v_rep_draft := app.create_role_version(v_rep_role, 'tester');
  perform app.set_role_version_permissions(
    v_rep_draft.id,
    array(select id from app.permissions where (resource_module_code = 'COM' and action in ('Create', 'Edit', 'Approve', 'View', 'View cost'))
      or (resource_module_code = 'OPS' and action in ('Create', 'Edit', 'Assign', 'View'))),
    'tester'
  );
  perform app.publish_role_version(v_rep_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_rep_role and status = 'published'), '00000000-0000-0000-0000-000000023102', '00000000-0000-0000-0000-000000023101', 'tester');

  v_viewer_role := (app.create_role(v_tenant1, 'Docreq Ops Viewer', 'OPS:View only, no Edit', 'tester')).id;
  v_viewer_draft := app.create_role_version(v_viewer_role, 'tester');
  perform app.set_role_version_permissions(
    v_viewer_draft.id,
    array(select id from app.permissions where resource_module_code = 'OPS' and action in ('View')),
    'tester'
  );
  perform app.publish_role_version(v_viewer_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_viewer_role and status = 'published'), '00000000-0000-0000-0000-000000023103', '00000000-0000-0000-0000-000000023103', 'tester');

  v_outsider_role := (app.create_role(v_tenant1, 'Docreq Outsider', 'sibling team, full grants', 'tester')).id;
  v_outsider_draft := app.create_role_version(v_outsider_role, 'tester');
  perform app.set_role_version_permissions(
    v_outsider_draft.id,
    array(select id from app.permissions where (resource_module_code = 'COM' and action in ('Create', 'Edit', 'View'))
      or (resource_module_code = 'OPS' and action in ('Create', 'Edit', 'Assign', 'View'))),
    'tester'
  );
  perform app.publish_role_version(v_outsider_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_outsider_role and status = 'published'), '00000000-0000-0000-0000-000000023104', '00000000-0000-0000-0000-000000023101', 'tester');

  perform app.capture_lead(v_tenant1, 'manual', null, 'Docreq Test Co', 'Jane Docreq', 'jane@docreqtest.test', '0811',
    '00000000-0000-0000-0000-000000023102', v_team_a, '00000000-0000-0000-0000-000000023102', 'tester');
  select * into v_lead from app.leads where email = 'jane@docreqtest.test';
  perform app.qualify_lead(v_lead.id, v_lead.record_version, '00000000-0000-0000-0000-000000023102', 'tester');
  select * into v_lead from app.leads where id = v_lead.id;
  perform app.convert_lead_to_prospect(v_lead.id, 'Docreq Test Co', 'DRT', '11.111.111.2-222.000',
    jsonb_build_object('line1', 'Jl. Rasuna Said 2', 'city', 'Jakarta', 'country', 'ID'),
    '00000000-0000-0000-0000-000000023102', 'tester');
  select * into v_prospect from app.prospects where lead_id = v_lead.id;

  select * into v_contact from app.create_contact(v_tenant1, 'Jane Docreq Ops', 'Procurement Lead', 'jane@docreqtest.test', '0811', '00000000-0000-0000-0000-000000023102', v_team_a, '00000000-0000-0000-0000-000000023102', 'tester');
  perform app.link_contact_to_record(v_contact.id, 'prospect', v_prospect.id, 'primary', true, '00000000-0000-0000-0000-000000023102', 'tester');

  select * into v_opportunity from app.create_opportunity(
    v_tenant1, v_prospect.id, 'Docreq test lane',
    jsonb_build_object('service_type', 'ocean_freight', 'cargo_description', 'General cargo', 'origin', 'Jakarta', 'destination', 'Surabaya', 'target_ready_date', '2026-08-01'),
    '00000000-0000-0000-0000-000000023102', v_team_a, '00000000-0000-0000-0000-000000023102', 'tester'
  );
  select * into v_request from app.request_costing(v_opportunity.id, '[]'::jsonb, null, '00000000-0000-0000-0000-000000023102', 'tester');
  select * into v_rate from app.create_rate_version(
    v_tenant1, 'VENDOR-DOCREQ-1', 'Contoso Ocean Line', 'ocean_freight', 'FCL', 'Jakarta', 'Surabaya', '20ft',
    null, null, null, null, 'IDR', 10000000, null, '[]'::jsonb, now(), null, null, '00000000-0000-0000-0000-000000023101', 'tester'
  );
  perform app.approve_rate_version(v_rate.id, v_rate.record_version, '00000000-0000-0000-0000-000000023101', 'tester');
  select * into v_selection from app.select_vendor_rate(v_request.id, v_rate.id, false, null, null, null, '00000000-0000-0000-0000-000000023102', 'tester');

  select * into v_rule from app.create_margin_rule_version(v_tenant1, 20.00, 'half_up', '00000000-0000-0000-0000-000000023102', 'tester');
  perform app.publish_margin_rule_version(v_rule.id, v_rule.record_version, null, '00000000-0000-0000-0000-000000023102', 'tester');
  perform app.calculate_margin(v_selection.id, 15000000, 'IDR', 0, '00000000-0000-0000-0000-000000023102', 'tester');
  select id into v_calc_id from app.margin_calculations where rate_selection_id = v_selection.id and is_current;

  select * into v_quote from app.create_quotation_draft(v_tenant1, v_opportunity.id, 'IDR', now() + interval '14 days', v_contact.id, null, null, '00000000-0000-0000-0000-000000023102', 'tester');
  perform app.add_quotation_line(v_quote.id, v_quote.record_version, 'service', 'Ocean freight docreq lane', v_calc_id, 1, 15000000, 0, 0, '00000000-0000-0000-0000-000000023102', 'tester');
  select * into v_quote from app.quotations where id = v_quote.id;
  perform app.submit_quotation(v_quote.id, v_quote.record_version, '00000000-0000-0000-0000-000000023102', 'tester');
  select * into v_send from app.send_quotation_for_acceptance(v_quote.id, null, 'email', '00000000-0000-0000-0000-000000023102', 'tester');
  perform app.record_quotation_customer_decision(v_send.raw_token, 'accepted', 'Jane Docreq Ops', null, null, null, null, null);
  select * into v_quote from app.quotations where id = v_quote.id;
  select * into v_account from app.convert_quotation_to_account(v_quote.id, null, null, '00000000-0000-0000-0000-000000023102', 'rep');
  select * into v_handoff from app.prepare_job_order_handoff(v_quote.id, '00000000-0000-0000-0000-000000023102', 'rep');

  select * into v_job_order from app.prepare_job_order(v_handoff.id, '00000000-0000-0000-0000-000000023102', 'rep');
  select * into v_job_order from app.confirm_job_order(v_job_order.id, v_job_order.record_version, '00000000-0000-0000-0000-000000023102', 'rep');

  select * into v_shipment_a from app.create_shipment_order_from_job(
    v_job_order.id, 'idem-docreq-a', null, null, 'ocean_freight', 'sea', 'Jakarta', 'Surabaya',
    now() + interval '1 day', now() + interval '10 days', null, null, null, null, null, null, null, '00000000-0000-0000-0000-000000023102', 'rep'
  );
  select * into v_shipment_a from app.confirm_shipment_order(v_shipment_a.id, v_shipment_a.record_version, '00000000-0000-0000-0000-000000023102', 'rep');

  select * into v_shipment_b from app.create_shipment_order_from_job(
    v_job_order.id, 'idem-docreq-b', null, null, 'ocean_freight', 'sea', 'Jakarta', 'Bandung',
    now() + interval '1 day', now() + interval '10 days', null, null, null, null, null, null, 'split: docreq second fixture', '00000000-0000-0000-0000-000000023102', 'rep'
  );
  select * into v_shipment_b from app.confirm_shipment_order(v_shipment_b.id, v_shipment_b.record_version, '00000000-0000-0000-0000-000000023102', 'rep');

  select * into v_shipment_draft from app.create_shipment_order_from_job(
    v_job_order.id, 'idem-docreq-draft', null, null, 'ocean_freight', 'sea', 'Jakarta', 'Cirebon',
    now() + interval '1 day', now() + interval '10 days', null, null, null, null, null, null, 'split: docreq draft fixture', '00000000-0000-0000-0000-000000023102', 'rep'
  );

  -- Document type registry: register a 'pod' code (Supreme Admin action) and publish a
  -- tenant-scoped document:pod definition (PLT-128's own config-engine draft/publish
  -- lifecycle), and a second 'invoice' code the mismatch test below deliberately never
  -- links a checklist item to.
  perform app.register_document_type('pod', 'Proof of Delivery', 'DOC', '00000000-0000-0000-0000-000000023106', 'supreme');
  perform app.register_document_type('invoice', 'Invoice', 'DOC', '00000000-0000-0000-0000-000000023106', 'supreme');

  v_pod_draft := app.create_config_draft('document:pod', v_tenant1, 'tenant', null, '00000000-0000-0000-0000-000000023101', 'admin');
  perform app.set_config_items(v_pod_draft.id, jsonb_build_array(
    jsonb_build_object('key', 'allowed_mime_types', 'value', jsonb_build_array('application/pdf', 'image/jpeg')),
    jsonb_build_object('key', 'max_size_bytes', 'value', 5242880),
    jsonb_build_object('key', 'retention_class', 'value', 'operational_contract_plus_90d'),
    jsonb_build_object('key', 'default_classification', 'value', 'internal'),
    jsonb_build_object('key', 'legal_hold_eligible', 'value', false)
  ), '00000000-0000-0000-0000-000000023101', 'admin');
  perform app.publish_document_type_definition(v_pod_draft.id, '00000000-0000-0000-0000-000000023101', now(), 'admin');

  v_other_draft := app.create_config_draft('document:invoice', v_tenant1, 'tenant', null, '00000000-0000-0000-0000-000000023101', 'admin');
  perform app.set_config_items(v_other_draft.id, jsonb_build_array(
    jsonb_build_object('key', 'allowed_mime_types', 'value', jsonb_build_array('application/pdf')),
    jsonb_build_object('key', 'max_size_bytes', 'value', 5242880),
    jsonb_build_object('key', 'retention_class', 'value', 'finance_tax_10y'),
    jsonb_build_object('key', 'default_classification', 'value', 'internal'),
    jsonb_build_object('key', 'legal_hold_eligible', 'value', false)
  ), '00000000-0000-0000-0000-000000023101', 'admin');
  perform app.publish_document_type_definition(v_other_draft.id, '00000000-0000-0000-0000-000000023101', now(), 'admin');

  -- Gizmo (tenant2) also publishes its own document:pod definition -- needed so the
  -- cross-tenant-file fixture below is itself a valid upload, proving the checklist
  -- link function's own tenant-boundary check rather than a Platform-layer rejection.
  v_pod_draft := app.create_config_draft('document:pod', v_tenant2, 'tenant', null, '00000000-0000-0000-0000-000000023105', 'gizmo admin');
  perform app.set_config_items(v_pod_draft.id, jsonb_build_array(
    jsonb_build_object('key', 'allowed_mime_types', 'value', jsonb_build_array('application/pdf')),
    jsonb_build_object('key', 'max_size_bytes', 'value', 5242880),
    jsonb_build_object('key', 'retention_class', 'value', 'operational_contract_plus_90d'),
    jsonb_build_object('key', 'default_classification', 'value', 'internal'),
    jsonb_build_object('key', 'legal_hold_eligible', 'value', false)
  ), '00000000-0000-0000-0000-000000023105', 'gizmo admin');
  perform app.publish_document_type_definition(v_pod_draft.id, '00000000-0000-0000-0000-000000023105', now(), 'gizmo admin');
end $$;

\echo '>> app.create_document_requirement_draft / app.publish_document_requirement_version: authority-gated (viewer denied OPS:Create/Edit), idempotent draft creation, republishing archives the prior published match'
do $$
declare
  v_draft1 app.document_requirement_definitions;
  v_draft2 app.document_requirement_definitions;
  v_published1 app.document_requirement_definitions;
  v_draft3 app.document_requirement_definitions;
  v_published2 app.document_requirement_definitions;
  v_prior app.document_requirement_definitions;
begin
  begin
    perform app.create_document_requirement_draft(
      (select id from app.tenants where slug = 'acmedocreq'), null, null, 'delivered', 'carrier', 'pod', 'mandatory',
      '00000000-0000-0000-0000-000000023103', 'viewer'
    );
    raise exception 'assertion failed: expected OPS:View-only viewer to be denied OPS:Create';
  exception
    when insufficient_privilege then null;
  end;

  v_draft1 := app.create_document_requirement_draft(
    (select id from app.tenants where slug = 'acmedocreq'), null, null, 'delivered', 'carrier', 'pod', 'mandatory',
    '00000000-0000-0000-0000-000000023102', 'rep'
  );
  v_draft2 := app.create_document_requirement_draft(
    (select id from app.tenants where slug = 'acmedocreq'), null, null, 'delivered', 'carrier', 'pod', 'mandatory',
    '00000000-0000-0000-0000-000000023102', 'rep'
  );
  if v_draft1.id <> v_draft2.id then
    raise exception 'assertion failed: expected repeated draft creation with the same match key to be idempotent';
  end if;

  v_published1 := app.publish_document_requirement_version(v_draft1.id, v_draft1.record_version, '00000000-0000-0000-0000-000000023102', 'rep');
  if v_published1.status <> 'published' then
    raise exception 'assertion failed: expected the draft to publish';
  end if;

  v_draft3 := app.create_document_requirement_draft(
    (select id from app.tenants where slug = 'acmedocreq'), null, null, 'delivered', 'carrier', 'pod', 'mandatory',
    '00000000-0000-0000-0000-000000023102', 'rep'
  );
  v_published2 := app.publish_document_requirement_version(v_draft3.id, v_draft3.record_version, '00000000-0000-0000-0000-000000023102', 'rep');
  select * into v_prior from app.document_requirement_definitions where id = v_published1.id;
  if v_prior.status <> 'archived' then
    raise exception 'assertion failed: expected republishing to archive the prior published match, got %', v_prior.status;
  end if;
  if v_published2.supersedes_version_id <> v_published1.id then
    raise exception 'assertion failed: expected the new published version to record supersedes_version_id';
  end if;
end $$;

\echo '>> app.pin_shipment_document_checklist: authority/record-scope gated, additive-only, matches the wildcard mode/service_type requirement'
do $$
declare
  v_items_count integer;
  v_shipment_a_id uuid := (select id from app.shipment_orders where idempotency_key = 'idem-docreq-a');
begin
  begin
    perform app.pin_shipment_document_checklist(v_shipment_a_id, '00000000-0000-0000-0000-000000023103', 'viewer');
    raise exception 'assertion failed: expected OPS:View-only viewer to be denied OPS:Edit';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform app.pin_shipment_document_checklist(v_shipment_a_id, '00000000-0000-0000-0000-000000023104', 'outsider');
    raise exception 'assertion failed: expected the sibling-team outsider to be denied by record scope despite full OPS grants';
  exception
    when insufficient_privilege then null;
  end;

  perform app.pin_shipment_document_checklist(v_shipment_a_id, '00000000-0000-0000-0000-000000023102', 'rep');
  select count(*) into v_items_count from app.shipment_document_checklist_items where shipment_order_id = v_shipment_a_id;
  if v_items_count <> 1 then
    raise exception 'assertion failed: expected exactly 1 pinned checklist item (the published pod/delivered/carrier requirement), got %', v_items_count;
  end if;

  -- Additive-only: re-pinning is a no-op while no new requirement has published.
  perform app.pin_shipment_document_checklist(v_shipment_a_id, '00000000-0000-0000-0000-000000023102', 'rep');
  select count(*) into v_items_count from app.shipment_document_checklist_items where shipment_order_id = v_shipment_a_id;
  if v_items_count <> 1 then
    raise exception 'assertion failed: expected re-pinning to remain idempotent/additive-only, got %', v_items_count;
  end if;

  begin
    perform app.pin_shipment_document_checklist('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000023102', 'rep');
    raise exception 'assertion failed: expected shipment_order_not_found for a non-existent shipment';
  exception
    when no_data_found then null;
  end;
end $$;

\echo '>> upload/link/review lifecycle: unsafe files never satisfy a requirement (scan-gated approval), type/record/tenant mismatches are rejected, a clean-scanned file approves, and completeness reflects it'
do $$
declare
  v_shipment_a_id uuid := (select id from app.shipment_orders where idempotency_key = 'idem-docreq-a');
  v_item app.shipment_document_checklist_items;
  v_file app.files;
  v_wrong_type_file app.files;
  v_other_tenant_file app.files;
  v_updated app.shipment_document_checklist_items;
  v_completeness record;
begin
  select * into v_item from app.shipment_document_checklist_items where shipment_order_id = v_shipment_a_id;

  select * into v_file from app.initiate_file_upload(
    (select id from app.tenants where slug = 'acmedocreq'), 'pod', 'shipment_order', v_shipment_a_id,
    'pod-a.pdf', 'application/pdf', 102400, null, false, null, '{}'::uuid[], null, 'idem-docreq-a-pod', '00000000-0000-0000-0000-000000023102', 'rep'
  );

  select * into v_wrong_type_file from app.initiate_file_upload(
    (select id from app.tenants where slug = 'acmedocreq'), 'invoice', 'shipment_order', v_shipment_a_id,
    'invoice-a.pdf', 'application/pdf', 102400, null, false, null, '{}'::uuid[], null, 'idem-docreq-a-invoice', '00000000-0000-0000-0000-000000023102', 'rep'
  );

  select * into v_other_tenant_file from app.initiate_file_upload(
    (select id from app.tenants where slug = 'gizmodocreq'), 'pod', 'shipment_order', v_shipment_a_id,
    'pod-cross.pdf', 'application/pdf', 102400, 'internal', false, null, '{}'::uuid[], null, 'idem-gizmo-pod', '00000000-0000-0000-0000-000000023105', 'admin'
  );

  begin
    perform app.link_document_to_checklist_item(v_item.id, v_wrong_type_file.id, '00000000-0000-0000-0000-000000023102', 'rep');
    raise exception 'assertion failed: expected document_checklist_type_mismatch for an invoice file against a pod requirement';
  exception
    when check_violation then
      if sqlerrm !~ 'document_checklist_type_mismatch' then raise; end if;
  end;

  begin
    perform app.link_document_to_checklist_item(v_item.id, v_other_tenant_file.id, '00000000-0000-0000-0000-000000023102', 'rep');
    raise exception 'assertion failed: expected document_checklist_cross_tenant for a file belonging to another tenant';
  exception
    when check_violation then
      if sqlerrm !~ 'document_checklist_cross_tenant' then raise; end if;
  end;

  -- ISS-2026-312: the record-scope guard, proven to FIRE rather than merely to exist. The file
  -- below is legitimate in every other respect -- right tenant, right document type, uploaded by
  -- the same actor -- and belongs to a DIFFERENT shipment. That is the case the cross-tenant and
  -- type checks both wave through, so it is the only one that exercises this guard.
  declare
    v_other_shipment_file app.files;
  begin
    select * into v_other_shipment_file from app.initiate_file_upload(
      (select id from app.tenants where slug = 'acmedocreq'), 'pod', 'shipment_order',
      (select id from app.shipment_orders where idempotency_key = 'idem-docreq-b'),
      'pod-b.pdf', 'application/pdf', 102400, null, false, null, '{}'::uuid[], null, 'idem-docreq-b-pod-312', '00000000-0000-0000-0000-000000023102', 'rep'
    );
    begin
      perform app.link_document_to_checklist_item(v_item.id, v_other_shipment_file.id, '00000000-0000-0000-0000-000000023102', 'rep');
      raise exception 'assertion failed: expected document_checklist_record_mismatch for a same-tenant, same-type file uploaded against a DIFFERENT shipment order';
    exception
      when check_violation then
        if sqlerrm !~ 'document_checklist_record_mismatch' then raise; end if;
    end;
  end;

  v_updated := app.link_document_to_checklist_item(v_item.id, v_file.id, '00000000-0000-0000-0000-000000023102', 'rep');
  if v_updated.file_id <> v_file.id or v_updated.review_status <> 'pending' then
    raise exception 'assertion failed: expected the checklist item to link the file and reset to pending review';
  end if;

  begin
    perform app.review_document_checklist_item(v_item.id, 'approved', 'looks fine', null, '00000000-0000-0000-0000-000000023102', 'rep');
    raise exception 'assertion failed: expected document_checklist_unsafe_file while the file is still pending scan';
  exception
    when check_violation then
      if sqlerrm !~ 'document_checklist_unsafe_file' then raise; end if;
  end;

  perform app.record_file_scan_result(v_file.id, 'clean', 'test-scanner-ref', '00000000-0000-0000-0000-000000023102', 'rep');

  v_updated := app.review_document_checklist_item(v_item.id, 'approved', 'signed and dated', null, '00000000-0000-0000-0000-000000023102', 'rep');
  if v_updated.review_status <> 'approved' then
    raise exception 'assertion failed: expected the checklist item to approve once the linked file scanned clean';
  end if;

  select * into v_completeness from app.evaluate_shipment_document_checklist_completeness(v_shipment_a_id, '00000000-0000-0000-0000-000000023102');
  if not v_completeness.is_complete or jsonb_array_length(v_completeness.missing_mandatory) <> 0 then
    raise exception 'assertion failed: expected shipment_a to be complete with zero missing mandatory items, got %/%', v_completeness.is_complete, v_completeness.missing_mandatory;
  end if;
end $$;

\echo '>> app.get_shipment_document_checklist: effective_status is computed live (missing/pending_review/approved/expired/rejected), never a stored fourth column'
do $$
declare
  v_shipment_b_id uuid := (select id from app.shipment_orders where idempotency_key = 'idem-docreq-b');
  v_item app.shipment_document_checklist_items;
  v_file app.files;
  v_row record;
  v_completeness record;
begin
  perform app.pin_shipment_document_checklist(v_shipment_b_id, '00000000-0000-0000-0000-000000023102', 'rep');
  select * into v_item from app.shipment_document_checklist_items where shipment_order_id = v_shipment_b_id;

  select * into v_row from app.get_shipment_document_checklist(v_shipment_b_id, '00000000-0000-0000-0000-000000023102');
  if v_row.effective_status <> 'missing' then
    raise exception 'assertion failed: expected effective_status=missing before any file is linked, got %', v_row.effective_status;
  end if;

  select * into v_file from app.initiate_file_upload(
    (select id from app.tenants where slug = 'acmedocreq'), 'pod', 'shipment_order', v_shipment_b_id,
    'pod-b.pdf', 'application/pdf', 102400, null, false, null, '{}'::uuid[], null, 'idem-docreq-b-pod', '00000000-0000-0000-0000-000000023102', 'rep'
  );
  perform app.link_document_to_checklist_item(v_item.id, v_file.id, '00000000-0000-0000-0000-000000023102', 'rep');
  select * into v_row from app.get_shipment_document_checklist(v_shipment_b_id, '00000000-0000-0000-0000-000000023102');
  if v_row.effective_status <> 'pending_review' then
    raise exception 'assertion failed: expected effective_status=pending_review once a file is linked but unreviewed, got %', v_row.effective_status;
  end if;

  -- Rejection path.
  perform app.review_document_checklist_item(v_item.id, 'rejected', 'illegible scan', null, '00000000-0000-0000-0000-000000023102', 'rep');
  select * into v_row from app.get_shipment_document_checklist(v_shipment_b_id, '00000000-0000-0000-0000-000000023102');
  if v_row.effective_status <> 'rejected' then
    raise exception 'assertion failed: expected effective_status=rejected, got %', v_row.effective_status;
  end if;
  select * into v_completeness from app.evaluate_shipment_document_checklist_completeness(v_shipment_b_id, '00000000-0000-0000-0000-000000023102');
  if v_completeness.is_complete then
    raise exception 'assertion failed: expected shipment_b to remain incomplete while its mandatory requirement is rejected';
  end if;

  -- Replace with a new upload (re-link) and approve with a past expires_at -> expired.
  perform app.record_file_scan_result(v_file.id, 'clean', 'test-scanner-ref', '00000000-0000-0000-0000-000000023102', 'rep');
  perform app.link_document_to_checklist_item(v_item.id, v_file.id, '00000000-0000-0000-0000-000000023102', 'rep');
  perform app.review_document_checklist_item(v_item.id, 'approved', 'accepted, but backdated expiry for this test', now() - interval '1 day', '00000000-0000-0000-0000-000000023102', 'rep');
  select * into v_row from app.get_shipment_document_checklist(v_shipment_b_id, '00000000-0000-0000-0000-000000023102');
  if v_row.effective_status <> 'expired' then
    raise exception 'assertion failed: expected effective_status=expired for an approved item whose expires_at is in the past, got %', v_row.effective_status;
  end if;
  select * into v_completeness from app.evaluate_shipment_document_checklist_completeness(v_shipment_b_id, '00000000-0000-0000-0000-000000023102');
  if v_completeness.is_complete then
    raise exception 'assertion failed: expected an expired mandatory item to keep the shipment incomplete';
  end if;

  -- Every link/review decision is preserved as append-only history, including the
  -- superseded rejected decision (prior evidence remains linked -- §22).
  if (select count(*) from app.document_checklist_events where checklist_item_id = v_item.id) < 4 then
    raise exception 'assertion failed: expected at least 4 checklist events (pinned, linked, rejected, linked, approved)';
  end if;
end $$;

\echo '>> RLS: authenticated record-scope isolation on app.shipment_document_checklist_items/app.document_requirement_definitions; cross-tenant isolation; schema-privilege defense in depth (anon holds zero EXECUTE on all 7 new functions)'
do $$
declare
  v_shipment_a_id uuid := (select id from app.shipment_orders where idempotency_key = 'idem-docreq-a');
  v_count integer;
  v_denied_count integer;
begin
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000023102", "role": "authenticated"}';
  select count(*) into v_count from app.shipment_document_checklist_items where shipment_order_id = v_shipment_a_id;
  if v_count <> 1 then
    raise exception 'assertion failed: expected the owning rep to see exactly 1 checklist row for shipment_a via RLS, got %', v_count;
  end if;
  reset role;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000023104", "role": "authenticated"}';
  select count(*) into v_count from app.shipment_document_checklist_items where shipment_order_id = v_shipment_a_id;
  if v_count <> 0 then
    raise exception 'assertion failed: expected the sibling-team outsider to see zero checklist rows for shipment_a via RLS, got %', v_count;
  end if;
  reset role;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000023105", "role": "authenticated"}';
  select count(*) into v_count from app.document_requirement_definitions where tenant_id = (select id from app.tenants where slug = 'acmedocreq');
  if v_count <> 0 then
    raise exception 'assertion failed: expected a Gizmo (other-tenant) admin to see zero Acme document requirement definitions via RLS, got %', v_count;
  end if;
  reset role;

  select count(*) into v_denied_count
  from information_schema.routine_privileges
  where routine_schema = 'app'
    and routine_name in (
      'create_document_requirement_draft', 'publish_document_requirement_version', 'pin_shipment_document_checklist',
      'link_document_to_checklist_item', 'review_document_checklist_item', 'get_shipment_document_checklist',
      'evaluate_shipment_document_checklist_completeness'
    )
    and grantee = 'anon';
  if v_denied_count <> 0 then
    raise exception 'assertion failed: expected anon to hold zero EXECUTE grants on the 7 new OPS-176 functions, found %', v_denied_count;
  end if;
end $$;

\echo '>> audit trail: every mutation self-captures a canonical app.audit_logs entry'
do $$
declare
  v_count integer;
begin
  select count(*) into v_count from app.audit_logs
  where action in (
    'create_document_requirement_draft', 'publish_document_requirement_version', 'pin_shipment_document_checklist',
    'link_document_to_checklist_item', 'review_document_checklist_item'
  );
  if v_count < 5 then
    raise exception 'assertion failed: expected at least 5 persisted OPS-176 audit events, found %', v_count;
  end if;
end $$;
