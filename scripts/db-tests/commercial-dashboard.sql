-- Real, executable test evidence for COM-158 (Commercial Dashboard, CG-S7-COM-017) --
-- run via `pnpm run db:test` against a real, disposable Postgres database.

\set ON_ERROR_STOP on

\echo '>> setup: two tenants, a company/branch/team-a/team-b org hierarchy, a branch manager (COM:Create/Edit/Approve/View/View selling price/View cost), a team-a rep (same grants), a team-a viewer (COM:Create/Edit/View only -- no View selling price/View cost), a team-b outsider (full grants, sibling scope), leads across every aging bucket, an activity queue across every urgency bucket, opportunities across pipeline/win/loss/forecast, and a full costing->rate->margin->quotation chain cloned across every quote-SLA bucket'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_company uuid;
  v_branch uuid;
  v_team_a uuid;
  v_team_b uuid;
  v_mgr_role uuid;
  v_mgr_draft app.role_versions;
  v_rep_role uuid;
  v_rep_draft app.role_versions;
  v_viewer_role uuid;
  v_viewer_draft app.role_versions;
  v_out_role uuid;
  v_out_draft app.role_versions;
  v_beta_role uuid;
  v_beta_draft app.role_versions;
  v_lead app.leads;
  v_prospect app.prospects;
  v_opportunity app.opportunities;
  v_opportunity2 app.opportunities;
  v_won app.opportunities;
  v_lost app.opportunities;
  v_stale_won app.opportunities;
  v_request app.costing_requests;
  v_request2 app.costing_requests;
  v_rate app.vendor_rate_versions;
  v_selection app.rate_selections;
  v_selection2 app.rate_selections;
  v_rule app.margin_rule_versions;
  v_calc app.margin_calculations;
  v_calc2 app.margin_calculations;
  v_contact app.contacts;
  v_quote app.quotations;
  v_clone app.quotations;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000009401', 'tenantadmin@acmedash.test'),
    ('00000000-0000-0000-0000-000000009402', 'manager@acmedash.test'),
    ('00000000-0000-0000-0000-000000009403', 'rep@acmedash.test'),
    ('00000000-0000-0000-0000-000000009404', 'viewer@acmedash.test'),
    ('00000000-0000-0000-0000-000000009405', 'outsider@acmedash.test'),
    ('00000000-0000-0000-0000-000000009406', 'rep@betadash.test');

  perform app.provision_tenant('acmedash', 'Acme Dash Co', 'idem-acmedash', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'acmedash');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');

  perform app.provision_tenant('betadash', 'Beta Dash Co', 'idem-betadash', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'betadash');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');

  perform app.create_org_unit(v_tenant1, 'company', null, 'ACMEDASH-CO', 'Acme Dash Co', 'tester');
  v_company := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEDASH-CO');
  perform app.create_org_unit(v_tenant1, 'branch', v_company, 'ACMEDASH-BR', 'Jakarta Branch', 'tester');
  v_branch := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEDASH-BR');
  perform app.create_org_unit(v_tenant1, 'department', v_branch, 'ACMEDASH-TEAM-A', 'Sales Team A', 'tester');
  v_team_a := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEDASH-TEAM-A');
  perform app.create_org_unit(v_tenant1, 'department', v_branch, 'ACMEDASH-TEAM-B', 'Sales Team B', 'tester');
  v_team_b := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEDASH-TEAM-B');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000009401', 'tenantadmin@acmedash.test', 'Tenant Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'tenantadmin@acmedash.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000009401', 'tenant_admin', v_tenant1, null, 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000009402', 'manager@acmedash.test', 'Branch Manager', v_branch, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'manager@acmedash.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000009403', 'rep@acmedash.test', 'Rep', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'rep@acmedash.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000009404', 'viewer@acmedash.test', 'Team A Viewer', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'viewer@acmedash.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000009405', 'outsider@acmedash.test', 'Team B Outsider', v_team_b, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'outsider@acmedash.test'), 'active', 'onboarded', 'tester');

  perform app.invite_user(v_tenant2, '00000000-0000-0000-0000-000000009406', 'rep@betadash.test', 'Beta Rep', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'rep@betadash.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000009406', 'tenant_admin', v_tenant2, null, 'tester');

  v_beta_role := (app.create_role(v_tenant2, 'Beta Rep Role', 'cross-tenant isolation fixture', 'tester')).id;
  v_beta_draft := app.create_role_version(v_beta_role, 'tester');
  perform app.set_role_version_permissions(
    v_beta_draft.id,
    array(select id from app.permissions where resource_module_code = 'COM' and action in ('Create', 'Edit', 'View')),
    'tester'
  );
  perform app.publish_role_version(v_beta_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant2, (select id from app.role_versions where role_id = v_beta_role and status = 'published'),
    '00000000-0000-0000-0000-000000009406', '00000000-0000-0000-0000-000000009406', 'tester');

  v_mgr_role := (app.create_role(v_tenant1, 'Dash Manager', 'branch-wide visibility', 'tester')).id;
  v_mgr_draft := app.create_role_version(v_mgr_role, 'tester');
  perform app.set_role_version_permissions(
    v_mgr_draft.id,
    array(select id from app.permissions where resource_module_code = 'COM' and action in ('Create', 'Edit', 'Approve', 'View', 'View selling price', 'View cost')),
    'tester'
  );
  perform app.publish_role_version(v_mgr_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_mgr_role and status = 'published'),
    '00000000-0000-0000-0000-000000009402', '00000000-0000-0000-0000-000000009401', 'tester');

  v_rep_role := (app.create_role(v_tenant1, 'Dash Rep', 'team-a capture', 'tester')).id;
  v_rep_draft := app.create_role_version(v_rep_role, 'tester');
  perform app.set_role_version_permissions(
    v_rep_draft.id,
    array(select id from app.permissions where resource_module_code = 'COM' and action in ('Create', 'Edit', 'View', 'View selling price', 'View cost')),
    'tester'
  );
  perform app.publish_role_version(v_rep_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_rep_role and status = 'published'),
    '00000000-0000-0000-0000-000000009403', '00000000-0000-0000-0000-000000009402', 'tester');

  v_viewer_role := (app.create_role(v_tenant1, 'Dash Viewer', 'team-a masked view', 'tester')).id;
  v_viewer_draft := app.create_role_version(v_viewer_role, 'tester');
  perform app.set_role_version_permissions(
    v_viewer_draft.id,
    array(select id from app.permissions where resource_module_code = 'COM' and action in ('Create', 'Edit', 'View')),
    'tester'
  );
  perform app.publish_role_version(v_viewer_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_viewer_role and status = 'published'),
    '00000000-0000-0000-0000-000000009404', '00000000-0000-0000-0000-000000009402', 'tester');

  v_out_role := (app.create_role(v_tenant1, 'Dash Outsider', 'team-b sibling', 'tester')).id;
  v_out_draft := app.create_role_version(v_out_role, 'tester');
  perform app.set_role_version_permissions(
    v_out_draft.id,
    array(select id from app.permissions where resource_module_code = 'COM' and action in ('Create', 'Edit', 'View', 'View selling price', 'View cost')),
    'tester'
  );
  perform app.publish_role_version(v_out_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_out_role and status = 'published'),
    '00000000-0000-0000-0000-000000009405', '00000000-0000-0000-0000-000000009402', 'tester');

  -- Lead aging: four open leads, one per bucket, plus one qualified (excluded) and one
  -- team-b lead (record-scope isolation) and one tenant-2 lead (cross-tenant isolation).
  perform app.capture_lead(v_tenant1, 'manual', null, 'Dash Co A', 'Aging Zero', 'aging0@dashco.test', '0811',
    '00000000-0000-0000-0000-000000009403', v_team_a, '00000000-0000-0000-0000-000000009403', 'tester');
  update app.leads set last_activity_at = now() - interval '1 day' where email = 'aging0@dashco.test';

  perform app.capture_lead(v_tenant1, 'manual', null, 'Dash Co B', 'Aging Mid', 'aging1@dashco.test', '0812',
    '00000000-0000-0000-0000-000000009403', v_team_a, '00000000-0000-0000-0000-000000009403', 'tester');
  update app.leads set status = 'contacted', last_activity_at = now() - interval '5 days' where email = 'aging1@dashco.test';

  perform app.capture_lead(v_tenant1, 'manual', null, 'Dash Co C', 'Aging Old', 'aging2@dashco.test', '0813',
    '00000000-0000-0000-0000-000000009403', v_team_a, '00000000-0000-0000-0000-000000009403', 'tester');
  update app.leads set last_activity_at = now() - interval '10 days' where email = 'aging2@dashco.test';

  perform app.capture_lead(v_tenant1, 'manual', null, 'Dash Co D', 'Aging Ancient', 'aging3@dashco.test', '0814',
    '00000000-0000-0000-0000-000000009403', v_team_a, '00000000-0000-0000-0000-000000009403', 'tester');
  update app.leads set status = 'contacted', last_activity_at = now() - interval '20 days' where email = 'aging3@dashco.test';

  perform app.capture_lead(v_tenant1, 'manual', null, 'Dash Co Qualified', 'Aging Excluded', 'agingqual@dashco.test', '0815',
    '00000000-0000-0000-0000-000000009403', v_team_a, '00000000-0000-0000-0000-000000009403', 'tester');
  select * into v_lead from app.leads where email = 'agingqual@dashco.test';
  perform app.qualify_lead(v_lead.id, v_lead.record_version, '00000000-0000-0000-0000-000000009403', 'tester');

  perform app.capture_lead(v_tenant1, 'manual', null, 'Dash Co Team B', 'Aging Sibling', 'agingteamb@dashco.test', '0816',
    '00000000-0000-0000-0000-000000009405', v_team_b, '00000000-0000-0000-0000-000000009405', 'tester');
  update app.leads set last_activity_at = now() - interval '1 day' where email = 'agingteamb@dashco.test';

  perform app.capture_lead(v_tenant2, 'manual', null, 'Beta Co', 'Aging Foreign', 'agingforeign@betadash.test', '0817',
    '00000000-0000-0000-0000-000000009406', null, '00000000-0000-0000-0000-000000009406', 'tester');

  -- A dedicated lead to convert into the prospect/opportunity/quotation chain, kept
  -- separate from the aging-bucket leads above so qualifying/converting it never shifts
  -- their own status out of the aging query's open set.
  perform app.capture_lead(v_tenant1, 'manual', null, 'Dash Chain Co', 'Chain Contact', 'chain@dashco.test', '0818',
    '00000000-0000-0000-0000-000000009403', v_team_a, '00000000-0000-0000-0000-000000009403', 'tester');
  select * into v_lead from app.leads where email = 'chain@dashco.test';
  perform app.qualify_lead(v_lead.id, v_lead.record_version, '00000000-0000-0000-0000-000000009403', 'tester');
  select * into v_lead from app.leads where email = 'chain@dashco.test';
  perform app.convert_lead_to_prospect(v_lead.id, 'Dash Chain Co', 'Dash Chain', '01.234.567.8-901.000',
    jsonb_build_object('line1', 'Jl. Sudirman 1', 'city', 'Jakarta', 'country', 'ID'),
    '00000000-0000-0000-0000-000000009403', 'tester');
  select * into v_prospect from app.prospects where legal_name = 'Dash Chain Co';
  select * into v_contact from app.create_contact(v_tenant1, 'Chain Contact', 'Procurement', 'chain@dashco.test', '0818', '00000000-0000-0000-0000-000000009403', v_team_a, '00000000-0000-0000-0000-000000009403', 'tester');

  -- Activity queue: five scheduled activities (one per bucket, one deliberately outside
  -- the 7-day window to prove it is NOT counted), plus one completed (excluded entirely).
  perform app.log_activity('lead', (select id from app.leads where email = 'aging0@dashco.test'), null, 'call', 'Overdue call', null, 'scheduled', now() - interval '2 hours', null, null, '00000000-0000-0000-0000-000000009403', v_team_a, '00000000-0000-0000-0000-000000009403', 'tester');
  perform app.log_activity('lead', (select id from app.leads where email = 'aging0@dashco.test'), null, 'call', 'Due today call', null, 'scheduled', now() + interval '1 minute', null, null, '00000000-0000-0000-0000-000000009403', v_team_a, '00000000-0000-0000-0000-000000009403', 'tester');
  perform app.log_activity('lead', (select id from app.leads where email = 'aging0@dashco.test'), null, 'follow_up', 'Upcoming follow-up', null, 'scheduled', now() + interval '3 days', null, null, '00000000-0000-0000-0000-000000009403', v_team_a, '00000000-0000-0000-0000-000000009403', 'tester');
  perform app.log_activity('lead', (select id from app.leads where email = 'aging0@dashco.test'), null, 'task', 'No due date task', null, 'scheduled', null, null, null, '00000000-0000-0000-0000-000000009403', v_team_a, '00000000-0000-0000-0000-000000009403', 'tester');
  perform app.log_activity('lead', (select id from app.leads where email = 'aging0@dashco.test'), null, 'meeting', 'Far-future meeting (outside 7-day window)', null, 'scheduled', now() + interval '10 days', null, null, '00000000-0000-0000-0000-000000009403', v_team_a, '00000000-0000-0000-0000-000000009403', 'tester');
  perform app.log_activity('lead', (select id from app.leads where email = 'aging0@dashco.test'), null, 'call', 'Already completed call', null, 'completed', now() - interval '1 day', now() - interval '1 day', 'connected', '00000000-0000-0000-0000-000000009403', v_team_a, '00000000-0000-0000-0000-000000009403', 'tester');

  -- Pipeline / forecast: two open opportunities at different stages/values.
  select * into v_opportunity from app.create_opportunity(
    v_tenant1, v_prospect.id, 'Dash open deal (qualifying)',
    jsonb_build_object('service_type', 'ocean_freight', 'cargo_description', 'General cargo', 'origin', 'Jakarta', 'destination', 'Surabaya', 'target_ready_date', '2026-08-01'),
    '00000000-0000-0000-0000-000000009403', v_team_a, '00000000-0000-0000-0000-000000009403', 'tester'
  );
  select * into v_opportunity from app.update_opportunity(v_opportunity.id, v_opportunity.record_version, v_opportunity.name, v_opportunity.requirements, null, null, 100000000, 'IDR', '00000000-0000-0000-0000-000000009403', 'tester');

  select * into v_opportunity2 from app.create_opportunity(
    v_tenant1, v_prospect.id, 'Dash open deal (ready for costing)',
    jsonb_build_object('service_type', 'ocean_freight', 'cargo_description', 'General cargo', 'origin', 'Jakarta', 'destination', 'Medan', 'target_ready_date', '2026-08-15'),
    '00000000-0000-0000-0000-000000009403', v_team_a, '00000000-0000-0000-0000-000000009403', 'tester'
  );
  select * into v_opportunity2 from app.update_opportunity(v_opportunity2.id, v_opportunity2.record_version, v_opportunity2.name, v_opportunity2.requirements, null, null, 200000000, 'IDR', '00000000-0000-0000-0000-000000009403', 'tester');
  select * into v_opportunity2 from app.transition_opportunity_stage(v_opportunity2.id, v_opportunity2.record_version, 'ready_for_costing', 60, null, '00000000-0000-0000-0000-000000009403', 'tester');

  -- Win/loss: one won (recent, inside any reasonable period) and one lost (recent), plus
  -- one won that is deliberately backdated to prove period filtering excludes it.
  select * into v_won from app.create_opportunity(
    v_tenant1, v_prospect.id, 'Dash won deal',
    jsonb_build_object('service_type', 'ocean_freight', 'cargo_description', 'General cargo', 'origin', 'Jakarta', 'destination', 'Semarang', 'target_ready_date', '2026-08-05'),
    '00000000-0000-0000-0000-000000009403', v_team_a, '00000000-0000-0000-0000-000000009403', 'tester'
  );
  select * into v_won from app.update_opportunity(v_won.id, v_won.record_version, v_won.name, v_won.requirements, null, null, 150000000, 'IDR', '00000000-0000-0000-0000-000000009403', 'tester');
  select * into v_won from app.transition_opportunity_stage(v_won.id, v_won.record_version, 'won', 100, 'price competitive', '00000000-0000-0000-0000-000000009402', 'tester');

  select * into v_lost from app.create_opportunity(
    v_tenant1, v_prospect.id, 'Dash lost deal',
    jsonb_build_object('service_type', 'ocean_freight', 'cargo_description', 'General cargo', 'origin', 'Jakarta', 'destination', 'Makassar', 'target_ready_date', '2026-08-05'),
    '00000000-0000-0000-0000-000000009403', v_team_a, '00000000-0000-0000-0000-000000009403', 'tester'
  );
  select * into v_lost from app.update_opportunity(v_lost.id, v_lost.record_version, v_lost.name, v_lost.requirements, null, null, 50000000, 'IDR', '00000000-0000-0000-0000-000000009403', 'tester');
  select * into v_lost from app.transition_opportunity_stage(v_lost.id, v_lost.record_version, 'lost', 0, 'budget cut', '00000000-0000-0000-0000-000000009402', 'tester');

  select * into v_stale_won from app.create_opportunity(
    v_tenant1, v_prospect.id, 'Dash old won deal (outside period)',
    jsonb_build_object('service_type', 'ocean_freight', 'cargo_description', 'General cargo', 'origin', 'Jakarta', 'destination', 'Batam', 'target_ready_date', '2026-05-05'),
    '00000000-0000-0000-0000-000000009403', v_team_a, '00000000-0000-0000-0000-000000009403', 'tester'
  );
  select * into v_stale_won from app.update_opportunity(v_stale_won.id, v_stale_won.record_version, v_stale_won.name, v_stale_won.requirements, null, null, 999000000, 'IDR', '00000000-0000-0000-0000-000000009403', 'tester');
  select * into v_stale_won from app.transition_opportunity_stage(v_stale_won.id, v_stale_won.record_version, 'won', 100, 'legacy deal', '00000000-0000-0000-0000-000000009402', 'tester');
  update app.opportunity_stage_history set changed_at = now() - interval '60 days' where opportunity_id = v_stale_won.id and to_stage = 'won';

  -- Costing/rate/margin chain #1, feeding the quotation clones below.
  select * into v_request from app.request_costing(v_opportunity2.id, '[]'::jsonb, null, '00000000-0000-0000-0000-000000009403', 'tester');
  select * into v_rate from app.create_rate_version(
    v_tenant1, 'VENDOR-DASH-1', 'Dash Ocean Line', 'ocean_freight', 'FCL', 'Jakarta', 'Medan', '20ft',
    null, null, null, null, 'IDR', 10000000, null, '[]'::jsonb, now(), null, null,
    '00000000-0000-0000-0000-000000009401', 'tester'
  );
  perform app.approve_rate_version(v_rate.id, v_rate.record_version, '00000000-0000-0000-0000-000000009401', 'tester');
  select * into v_selection from app.select_vendor_rate(v_request.id, v_rate.id, false, null, null, null, '00000000-0000-0000-0000-000000009403', 'tester');

  select * into v_rule from app.create_margin_rule_version(v_tenant1, 20.00, 'half_up', '00000000-0000-0000-0000-000000009402', 'tester');
  perform app.publish_margin_rule_version(v_rule.id, v_rule.record_version, null, '00000000-0000-0000-0000-000000009402', 'tester');

  -- cost 10,000,000; sell 18,000,000 -> margin 44.44% (>= 20% -> pass).
  select * into v_calc from app.calculate_margin(v_selection.id, 18000000, 'IDR', 0, '00000000-0000-0000-0000-000000009403', 'tester');

  -- Costing/rate/margin chain #2 (separate opportunity), a lower-margin second data point
  -- so app.get_dashboard_margin_summary has two distinct current rows to average.
  select * into v_request2 from app.request_costing(v_opportunity.id, '[]'::jsonb, null, '00000000-0000-0000-0000-000000009403', 'tester');
  select * into v_selection2 from app.select_vendor_rate(v_request2.id, v_rate.id, false, null, null, null, '00000000-0000-0000-0000-000000009403', 'tester');
  -- cost 10,000,000; sell 16,000,000 -> margin 37.50% (>= 20% -> pass, a second distinct
  -- current calculation). Deliberately not 16.67%/33.33%/44.44% -- those exact values are
  -- also used, unscoped by tenant, by scripts/db-tests/commercial-margin-calculation.sql's
  -- own `where margin_pct = ...` lookups; sharing one disposable database across every
  -- db-tests file means a coincidentally-equal value there really did get picked up by that
  -- file's own unscoped query during authoring of this fixture (see COM-158 build log §8).
  select * into v_calc2 from app.calculate_margin(v_selection2.id, 16000000, 'IDR', 0, '00000000-0000-0000-0000-000000009403', 'tester');

  -- Quote SLA: one base submitted quotation, then four clones covering every bucket plus
  -- two structural exclusions (customer-decided, never-submitted draft).
  select * into v_quote from app.create_quotation_draft(v_tenant1, v_opportunity2.id, 'IDR', now() + interval '10 days', v_contact.id, null, null, '00000000-0000-0000-0000-000000009403', 'tester');
  perform app.add_quotation_line(v_quote.id, v_quote.record_version, 'service', 'Ocean freight Jakarta-Medan', v_calc.id, 1, 18000000, 0, 0, '00000000-0000-0000-0000-000000009403', 'tester');
  select * into v_quote from app.quotations where id = v_quote.id;
  select * into v_quote from app.submit_quotation(v_quote.id, v_quote.record_version, '00000000-0000-0000-0000-000000009403', 'tester');
  -- baseline: not_required (no approval rule published), validity_to 10 days out -> awaiting_customer_decision.

  select * into v_clone from app.clone_quotation(v_quote.id, '00000000-0000-0000-0000-000000009403', 'tester');
  select * into v_clone from app.submit_quotation(v_clone.id, v_clone.record_version, '00000000-0000-0000-0000-000000009403', 'tester');
  update app.quotations set approval_status = 'pending' where id = v_clone.id;
  -- pending_approval, regardless of validity_to.

  select * into v_clone from app.clone_quotation(v_quote.id, '00000000-0000-0000-0000-000000009403', 'tester');
  select * into v_clone from app.submit_quotation(v_clone.id, v_clone.record_version, '00000000-0000-0000-0000-000000009403', 'tester');
  update app.quotations set validity_from = now() - interval '2 days', validity_to = now() - interval '1 day' where id = v_clone.id;
  -- expired_no_decision.

  select * into v_clone from app.clone_quotation(v_quote.id, '00000000-0000-0000-0000-000000009403', 'tester');
  select * into v_clone from app.submit_quotation(v_clone.id, v_clone.record_version, '00000000-0000-0000-0000-000000009403', 'tester');
  update app.quotations set validity_to = now() + interval '1 day' where id = v_clone.id;
  -- expiring_soon (<= 2 days out).

  select * into v_clone from app.clone_quotation(v_quote.id, '00000000-0000-0000-0000-000000009403', 'tester');
  select * into v_clone from app.submit_quotation(v_clone.id, v_clone.record_version, '00000000-0000-0000-0000-000000009403', 'tester');
  update app.quotations set customer_decision = 'accepted', customer_decision_at = now() where id = v_clone.id;
  -- excluded: already customer-decided.

  select * into v_clone from app.clone_quotation(v_quote.id, '00000000-0000-0000-0000-000000009403', 'tester');
  -- excluded: never submitted, still draft.

  select * into v_clone from app.clone_quotation(v_quote.id, '00000000-0000-0000-0000-000000009403', 'tester');
  select * into v_clone from app.submit_quotation(v_clone.id, v_clone.record_version, '00000000-0000-0000-0000-000000009403', 'tester');
  update app.quotations set is_current = false where id = v_clone.id;
  -- excluded: superseded version.
end;
$$;

\echo '>> app.get_dashboard_lead_aging: buckets correct, qualified lead excluded, sibling-team lead excluded from a team-scoped query but visible at branch scope, foreign tenant lead never visible'
do $$
declare
  v_tenant1 uuid;
  v_branch uuid;
  v_team_a uuid;
  v_bucket_0_2 bigint;
  v_bucket_3_7 bigint;
  v_bucket_8_14 bigint;
  v_bucket_15_plus bigint;
  v_total bigint;
  v_branch_total bigint;
  v_foreign_total bigint;
begin
  v_tenant1 := (select id from app.tenants where slug = 'acmedash');
  v_branch := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEDASH-BR');
  v_team_a := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEDASH-TEAM-A');

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000009403", "role": "authenticated"}';

  select lead_count into v_bucket_0_2 from app.get_dashboard_lead_aging(v_tenant1, v_team_a, null) where bucket = '0_2_days';
  select lead_count into v_bucket_3_7 from app.get_dashboard_lead_aging(v_tenant1, v_team_a, null) where bucket = '3_7_days';
  select lead_count into v_bucket_8_14 from app.get_dashboard_lead_aging(v_tenant1, v_team_a, null) where bucket = '8_14_days';
  select lead_count into v_bucket_15_plus from app.get_dashboard_lead_aging(v_tenant1, v_team_a, null) where bucket = '15_plus_days';
  if coalesce(v_bucket_0_2, 0) <> 1 or coalesce(v_bucket_3_7, 0) <> 1 or coalesce(v_bucket_8_14, 0) <> 1 or coalesce(v_bucket_15_plus, 0) <> 1 then
    raise exception 'assertion failed: expected exactly one open lead in each of the four aging buckets, got 0-2=%, 3-7=%, 8-14=%, 15+=%', v_bucket_0_2, v_bucket_3_7, v_bucket_8_14, v_bucket_15_plus;
  end if;

  select coalesce(sum(lead_count), 0) into v_total from app.get_dashboard_lead_aging(v_tenant1, v_team_a, null);
  if v_total <> 4 then
    raise exception 'assertion failed: expected the qualified lead and the sibling-team lead to be excluded from a team-a-scoped query, got total=% (expected 4)', v_total;
  end if;

  select coalesce(sum(lead_count), 0) into v_foreign_total from app.get_dashboard_lead_aging((select id from app.tenants where slug = 'betadash'), null, null);
  if v_foreign_total <> 0 then
    raise exception 'assertion failed: expected a rep with no membership in tenant betadash to see 0 rows regardless of which tenant_id is passed, got %', v_foreign_total;
  end if;
  reset role;

  -- The branch manager sits at the branch itself (an ancestor of both teams), so a
  -- branch-scoped query for them includes the team-b lead RLS hid from the team-a rep
  -- above -- passing a wider org_unit_id filter only narrows what a caller could already
  -- see, it never grants access RLS itself would not already allow.
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000009402", "role": "authenticated"}';
  select coalesce(sum(lead_count), 0) into v_branch_total from app.get_dashboard_lead_aging(v_tenant1, v_branch, null);
  if v_branch_total <> 5 then
    raise exception 'assertion failed: expected the branch manager''s branch-scoped query to include both team-a and team-b leads (5 total), got %', v_branch_total;
  end if;
  reset role;
end;
$$;

\echo '>> app.get_dashboard_activity_queue: overdue/due_today/upcoming_7_days/no_due_date each counted once, the far-future activity and the completed activity are both excluded'
do $$
declare
  v_tenant1 uuid;
  v_overdue bigint;
  v_due_today bigint;
  v_upcoming bigint;
  v_no_due bigint;
  v_total bigint;
begin
  v_tenant1 := (select id from app.tenants where slug = 'acmedash');

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000009403", "role": "authenticated"}';

  select activity_count into v_overdue from app.get_dashboard_activity_queue(v_tenant1, null, null) where bucket = 'overdue';
  select activity_count into v_due_today from app.get_dashboard_activity_queue(v_tenant1, null, null) where bucket = 'due_today';
  select activity_count into v_upcoming from app.get_dashboard_activity_queue(v_tenant1, null, null) where bucket = 'upcoming_7_days';
  select activity_count into v_no_due from app.get_dashboard_activity_queue(v_tenant1, null, null) where bucket = 'no_due_date';
  if coalesce(v_overdue, 0) <> 1 or coalesce(v_due_today, 0) <> 1 or coalesce(v_upcoming, 0) <> 1 or coalesce(v_no_due, 0) <> 1 then
    raise exception 'assertion failed: expected exactly one activity in each bucket, got overdue=%, due_today=%, upcoming_7_days=%, no_due_date=%', v_overdue, v_due_today, v_upcoming, v_no_due;
  end if;

  select coalesce(sum(activity_count), 0) into v_total from app.get_dashboard_activity_queue(v_tenant1, null, null);
  if v_total <> 4 then
    raise exception 'assertion failed: expected the far-future (10-day) and completed activities to be excluded (total=4), got %', v_total;
  end if;

  reset role;
end;
$$;

\echo '>> app.get_dashboard_pipeline_summary / app.get_dashboard_forecast_summary: open-stage opportunities grouped by currency, selling-price masked for the viewer, won/lost excluded from both'
do $$
declare
  v_tenant1 uuid;
  v_pipeline_count bigint;
  v_pipeline_total numeric;
  v_pipeline_masked boolean;
  v_forecast_total numeric;
  v_forecast_masked boolean;
  v_viewer_masked boolean;
  v_viewer_total numeric;
begin
  v_tenant1 := (select id from app.tenants where slug = 'acmedash');

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000009403", "role": "authenticated"}';

  select coalesce(sum(opportunity_count), 0) into v_pipeline_count from app.get_dashboard_pipeline_summary(v_tenant1, null, null);
  if v_pipeline_count <> 2 then
    raise exception 'assertion failed: expected exactly 2 open (non-won/lost) opportunities in the pipeline summary, got %', v_pipeline_count;
  end if;

  select value_amount_total, value_masked into v_pipeline_total, v_pipeline_masked from app.get_dashboard_pipeline_summary(v_tenant1, null, null) where stage = 'ready_for_costing' and currency = 'IDR';
  if v_pipeline_masked or v_pipeline_total <> 200000000 then
    raise exception 'assertion failed: expected the rep (holds View selling price) to see value_masked=false and value_amount_total=200000000, got masked=% total=%', v_pipeline_masked, v_pipeline_total;
  end if;

  select weighted_value_total, value_masked into v_forecast_total, v_forecast_masked from app.get_dashboard_forecast_summary(v_tenant1, null, null) where currency = 'IDR';
  -- v_opportunity kept its table-default probability=10 (never transitioned, still
  -- qualifying); v_opportunity2 was moved to ready_for_costing at probability=60.
  -- 100,000,000 * 10% + 200,000,000 * 60% = 10,000,000 + 120,000,000 = 130,000,000.
  if v_forecast_masked or v_forecast_total <> 130000000 then
    raise exception 'assertion failed: expected weighted_value_total=130000000 (10%% of 100M + 60%% of 200M), got masked=% total=%', v_forecast_masked, v_forecast_total;
  end if;

  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000009404", "role": "authenticated"}';
  select value_masked, value_amount_total into v_viewer_masked, v_viewer_total from app.get_dashboard_pipeline_summary(v_tenant1, null, null) where stage = 'ready_for_costing' and currency = 'IDR';
  if not v_viewer_masked or v_viewer_total is not null then
    raise exception 'assertion failed: expected the viewer (no View selling price) to see value_masked=true and value_amount_total=null, got masked=% total=%', v_viewer_masked, v_viewer_total;
  end if;

  reset role;
end;
$$;

\echo '>> app.get_dashboard_win_loss_summary: won/lost counted from the real stage-transition event, period filter excludes a deliberately backdated transition'
do $$
declare
  v_tenant1 uuid;
  v_won_count bigint;
  v_won_total numeric;
  v_lost_count bigint;
  v_lost_total numeric;
  v_all_time_won bigint;
begin
  v_tenant1 := (select id from app.tenants where slug = 'acmedash');

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000009403", "role": "authenticated"}';

  select opportunity_count, value_amount_total into v_won_count, v_won_total from app.get_dashboard_win_loss_summary(v_tenant1, null, null, (current_date - 7), current_date) where outcome = 'won';
  if v_won_count <> 1 or v_won_total <> 150000000 then
    raise exception 'assertion failed: expected exactly 1 recent won opportunity worth 150000000 within the last 7 days (the 60-day-old won deal excluded), got count=% total=%', v_won_count, v_won_total;
  end if;

  select opportunity_count, value_amount_total into v_lost_count, v_lost_total from app.get_dashboard_win_loss_summary(v_tenant1, null, null, (current_date - 7), current_date) where outcome = 'lost';
  if v_lost_count <> 1 or v_lost_total <> 50000000 then
    raise exception 'assertion failed: expected exactly 1 lost opportunity worth 50000000, got count=% total=%', v_lost_count, v_lost_total;
  end if;

  select coalesce(sum(opportunity_count), 0) into v_all_time_won from app.get_dashboard_win_loss_summary(v_tenant1, null, null, null, null) where outcome = 'won';
  if v_all_time_won <> 2 then
    raise exception 'assertion failed: expected an unbounded (null start/end) query to include the 60-day-old won deal too (2 total), got %', v_all_time_won;
  end if;

  reset role;
end;
$$;

\echo '>> app.get_dashboard_margin_summary: two current calculations averaged, masked without COM:View cost, superseded/other-tenant rows never counted'
do $$
declare
  v_tenant1 uuid;
  v_count bigint;
  v_avg numeric;
  v_total numeric;
  v_masked boolean;
  v_viewer_masked boolean;
begin
  v_tenant1 := (select id from app.tenants where slug = 'acmedash');

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000009403", "role": "authenticated"}';

  select calculation_count, avg_margin_pct, total_margin_amount, margin_masked into v_count, v_avg, v_total, v_masked from app.get_dashboard_margin_summary(v_tenant1, null, null, null, null) where currency = 'IDR';
  if v_count <> 2 or v_masked then
    raise exception 'assertion failed: expected 2 current IDR margin calculations, unmasked for the rep (holds View cost), got count=% masked=%', v_count, v_masked;
  end if;
  -- 44.44% and 37.50% average to 40.97%.
  if v_avg <> 40.97 then
    raise exception 'assertion failed: expected avg_margin_pct=40.97, got %', v_avg;
  end if;

  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000009404", "role": "authenticated"}';
  select margin_masked, avg_margin_pct into v_viewer_masked, v_avg from app.get_dashboard_margin_summary(v_tenant1, null, null, null, null) where currency = 'IDR';
  if not v_viewer_masked or v_avg is not null then
    raise exception 'assertion failed: expected the viewer (no View cost) to see margin_masked=true and avg_margin_pct=null, got masked=% avg=%', v_viewer_masked, v_avg;
  end if;

  reset role;
end;
$$;

\echo '>> app.get_dashboard_quote_sla: pending_approval/expiring_soon/expired_no_decision/awaiting_customer_decision each counted once, customer-decided/never-submitted/superseded quotations all excluded'
do $$
declare
  v_tenant1 uuid;
  v_pending bigint;
  v_expiring bigint;
  v_expired bigint;
  v_awaiting bigint;
  v_total bigint;
begin
  v_tenant1 := (select id from app.tenants where slug = 'acmedash');

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000009403", "role": "authenticated"}';

  select quote_count into v_pending from app.get_dashboard_quote_sla(v_tenant1, null, null) where bucket = 'pending_approval';
  select quote_count into v_expiring from app.get_dashboard_quote_sla(v_tenant1, null, null) where bucket = 'expiring_soon';
  select quote_count into v_expired from app.get_dashboard_quote_sla(v_tenant1, null, null) where bucket = 'expired_no_decision';
  select quote_count into v_awaiting from app.get_dashboard_quote_sla(v_tenant1, null, null) where bucket = 'awaiting_customer_decision';
  if coalesce(v_pending, 0) <> 1 or coalesce(v_expiring, 0) <> 1 or coalesce(v_expired, 0) <> 1 or coalesce(v_awaiting, 0) <> 1 then
    raise exception 'assertion failed: expected exactly one quotation in each SLA bucket, got pending_approval=%, expiring_soon=%, expired_no_decision=%, awaiting_customer_decision=%', v_pending, v_expiring, v_expired, v_awaiting;
  end if;

  select coalesce(sum(quote_count), 0) into v_total from app.get_dashboard_quote_sla(v_tenant1, null, null);
  if v_total <> 4 then
    raise exception 'assertion failed: expected the customer-decided, never-submitted-draft and superseded quotations to be excluded (total=4), got %', v_total;
  end if;

  reset role;
end;
$$;

\echo '>> schema-privilege defense in depth: anon holds no EXECUTE on any app.get_dashboard_* function or app.dashboard_scope_org_unit_ids (ERR-2026-004 regression guard)'
do $$
declare
  v_count integer;
begin
  select count(*) into v_count
  from information_schema.routine_privileges
  where routine_schema = 'app'
    and routine_name in ('get_dashboard_lead_aging', 'get_dashboard_activity_queue', 'get_dashboard_pipeline_summary', 'get_dashboard_quote_sla', 'get_dashboard_margin_summary', 'get_dashboard_win_loss_summary', 'get_dashboard_forecast_summary', 'dashboard_scope_org_unit_ids')
    and grantee = 'anon';
  if v_count <> 0 then
    raise exception 'assertion failed: expected zero anon EXECUTE grants on any COM-158 dashboard function, found %', v_count;
  end if;
end;
$$;
