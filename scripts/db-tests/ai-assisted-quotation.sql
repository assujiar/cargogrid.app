-- Real, executable test evidence for IAE-020 (AI-Assisted Quotation, Prompt
-- 348) -- run via `pnpm run db:test` against a real, disposable Postgres
-- database. Scoped to this checkpoint's own additive migration
-- (supabase/migrations/20260805080000_create_intelligence_ai_assisted_quotation.sql).
-- Fresh, distinctive tenant fixture (iaeaiq), fixture id range
-- 00000000-0000-0000-0000-000023xxxxxx.

\set ON_ERROR_STOP on

-- ISS-2026-257: fixed test-only key for app.integration_secrets_encryption_key() --
-- production key provisioning/rotation/custody is a disclosed, out-of-scope
-- infrastructure concern (mirrors app.vendor_financial_encryption_keys own pattern).
select set_config('app.integration_secrets_encryption_key', 'test-only-key-not-for-production', false);

\echo '>> setup: tenant iaeaiq with a real openai_multimodal integration connection, a real opportunity->costing->rate->margin chain (mirroring the established costing golden path); rep1 (COM full set + AI:Create/View), viewer1 (COM:View only), juniorrep1 (COM:Create/Edit/View but no View cost/selling price/margin -- can draft a quotation but not see wholesale figures); a second tenant (iaeaiq2) for cross-tenant isolation'
do $$
declare
  v_tenant1 uuid;
  v_tenant2 uuid;
  v_admin1 uuid := '00000000-0000-0000-0000-000023000001';
  v_rep1 uuid := '00000000-0000-0000-0000-000023000002';
  v_viewer1 uuid := '00000000-0000-0000-0000-000023000003';
  v_junior_rep1 uuid := '00000000-0000-0000-0000-000023000004';
  v_admin2 uuid := '00000000-0000-0000-0000-000023000005';
  v_rep_role uuid;
  v_rep_draft app.role_versions;
  v_viewer_role uuid;
  v_viewer_draft app.role_versions;
  v_junior_rep_role uuid;
  v_junior_rep_draft app.role_versions;
  v_admin2_role uuid;
  v_admin2_draft app.role_versions;
  v_lead app.leads;
  v_prospect app.prospects;
  v_opportunity app.opportunities;
  v_request app.costing_requests;
  v_rate app.vendor_rate_versions;
  v_selection app.rate_selections;
  v_rule app.margin_rule_versions;
  v_calc app.margin_calculations;
  v_team_org_unit uuid;
begin
  insert into auth.users (id, email) values
    (v_admin1, 'admin@iaeaiq.test'),
    (v_rep1, 'rep@iaeaiq.test'),
    (v_viewer1, 'viewer@iaeaiq.test'),
    (v_junior_rep1, 'juniorrep@iaeaiq.test'),
    (v_admin2, 'admin@iaeaiq2.test');

  perform app.provision_tenant('iaeaiq', 'IaeAiQ Co', 'idem-iaeaiq', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'iaeaiq');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');
  perform app.provision_tenant('iaeaiq2', 'IaeAiQ Co 2', 'idem-iaeaiq2', 'tester');
  v_tenant2 := (select id from app.tenants where slug = 'iaeaiq2');
  perform app.transition_tenant_status(v_tenant2, 'active', 'setup', 'tester');

  perform app.invite_user(v_tenant1, v_admin1, 'admin@iaeaiq.test', 'IaeAiQ Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@iaeaiq.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(v_admin1, 'tenant_admin', v_tenant1, null, 'tester');

  -- A shared team org unit -- rep1 (the opportunity's own owner) and
  -- juniorrep1 both sit in it, so juniorrep1 passes app.can_access_record's
  -- own shared-org-unit path on rep1's opportunity (record-scope access,
  -- entirely orthogonal to the COM:View cost masking dimension this fixture
  -- exists to prove below).
  perform app.create_org_unit(v_tenant1, 'company', null, 'IAEAIQ-CO', 'IaeAiQ Co', 'tester');
  v_team_org_unit := (select id from app.org_units where tenant_id = v_tenant1 and code = 'IAEAIQ-CO');

  perform app.invite_user(v_tenant1, v_rep1, 'rep@iaeaiq.test', 'IaeAiQ Rep', v_team_org_unit, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'rep@iaeaiq.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, v_viewer1, 'viewer@iaeaiq.test', 'IaeAiQ Viewer', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'viewer@iaeaiq.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, v_junior_rep1, 'juniorrep@iaeaiq.test', 'IaeAiQ Junior Rep', v_team_org_unit, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'juniorrep@iaeaiq.test'), 'active', 'onboarded', 'tester');

  v_rep_role := (app.create_role(v_tenant1, 'AiQ Rep', 'COM full set + AI:Create/View + INTHUB:Configure', 'tester')).id;
  v_rep_draft := app.create_role_version(v_rep_role, 'tester');
  perform app.set_role_version_permissions(
    v_rep_draft.id,
    array(select id from app.permissions where (resource_module_code = 'COM' and action in ('Create', 'Edit', 'Approve', 'View', 'View cost', 'View selling price', 'View margin')) or (resource_module_code = 'AI' and action in ('Create', 'View')) or (resource_module_code = 'INTHUB' and action in ('Configure', 'View'))),
    'tester'
  );
  perform app.publish_role_version(v_rep_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_rep_role and status = 'published'), v_rep1, v_admin1, 'admin');

  v_viewer_role := (app.create_role(v_tenant1, 'AiQ Viewer', 'COM:View only -- no Create/Edit', 'tester')).id;
  v_viewer_draft := app.create_role_version(v_viewer_role, 'tester');
  perform app.set_role_version_permissions(v_viewer_draft.id, array(select id from app.permissions where resource_module_code = 'COM' and action = 'View'), 'tester');
  perform app.publish_role_version(v_viewer_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_viewer_role and status = 'published'), v_viewer1, v_admin1, 'admin');

  -- COM:Create/Edit/View + AI:Create/View -- deliberately NO View cost/View selling price/View margin.
  -- Can draft/request an AI suggestion but must never see wholesale cost/margin figures (Prompt 348 §24).
  v_junior_rep_role := (app.create_role(v_tenant1, 'AiQ Junior Rep', 'COM:Create/Edit/View + AI:Create/View -- no cost/margin visibility', 'tester')).id;
  v_junior_rep_draft := app.create_role_version(v_junior_rep_role, 'tester');
  perform app.set_role_version_permissions(
    v_junior_rep_draft.id,
    array(select id from app.permissions where (resource_module_code = 'COM' and action in ('Create', 'Edit', 'View')) or (resource_module_code = 'AI' and action in ('Create', 'View'))),
    'tester'
  );
  perform app.publish_role_version(v_junior_rep_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_junior_rep_role and status = 'published'), v_junior_rep1, v_admin1, 'admin');

  perform app.invite_user(v_tenant2, v_admin2, 'admin@iaeaiq2.test', 'IaeAiQ2 Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admin@iaeaiq2.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership(v_admin2, 'tenant_admin', v_tenant2, null, 'tester');

  v_admin2_role := (app.create_role(v_tenant2, 'AiQ2 Admin Ops', 'AI:Create/View + INTHUB:Configure/View -- tenant2 cross-check probe actor', 'tester')).id;
  v_admin2_draft := app.create_role_version(v_admin2_role, 'tester');
  perform app.set_role_version_permissions(
    v_admin2_draft.id,
    array(select id from app.permissions where (resource_module_code = 'AI' and action in ('Create', 'View')) or (resource_module_code = 'INTHUB' and action in ('Configure', 'View'))),
    'tester'
  );
  perform app.publish_role_version(v_admin2_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant2, (select id from app.role_versions where role_id = v_admin2_role and status = 'published'), v_admin2, v_admin2, 'admin2');

  perform app.create_integration_connection(v_tenant1, 'openai_multimodal', 'OpenAI Multimodal', 'production', null, null, null, jsonb_build_object('apiUrl', 'https://ai.iaeaiq-provider.test/v1/infer'), 'test-ai-secret', v_rep1, 'rep');

  -- The real costing/rate/margin golden path -- mirrors commercial-integrated-verification.sql's own already-established sequence.
  perform app.capture_lead(v_tenant1, 'manual', null, 'IaeAiQ Freight Co', 'Jane AiQ', 'jane@iaeaiq-lead.test', '0811', v_rep1, null, v_rep1, 'tester');
  select * into v_lead from app.leads where tenant_id = v_tenant1 and email = 'jane@iaeaiq-lead.test';
  perform app.qualify_lead(v_lead.id, v_lead.record_version, v_rep1, 'tester');
  select * into v_lead from app.leads where id = v_lead.id;
  perform app.convert_lead_to_prospect(v_lead.id, 'IaeAiQ Freight Co', 'IAQC', '44.444.444.4-023.000', jsonb_build_object('line1', 'Jl. Sudirman 23', 'city', 'Jakarta', 'country', 'ID'), v_rep1, 'tester');
  select * into v_prospect from app.prospects where lead_id = v_lead.id;

  select * into v_opportunity from app.create_opportunity(
    v_tenant1, v_prospect.id, 'IaeAiQ ocean lane',
    jsonb_build_object('service_type', 'ocean_freight', 'cargo_description', 'General cargo', 'origin', 'Jakarta', 'destination', 'Surabaya', 'target_ready_date', '2026-09-01'),
    v_rep1, v_team_org_unit, v_rep1, 'tester'
  );
  select * into v_request from app.request_costing(v_opportunity.id, '[]'::jsonb, null, v_rep1, 'tester');
  select * into v_rate from app.create_rate_version(
    v_tenant1, 'VENDOR-IAEAIQ-1', 'Contoso Ocean Line', 'ocean_freight', 'FCL', 'Jakarta', 'Surabaya', '20ft',
    null, null, null, null, 'IDR', 10000000, null, '[]'::jsonb, now(), null, null, v_admin1, 'tester'
  );
  perform app.approve_rate_version(v_rate.id, v_rate.record_version, v_admin1, 'tester');
  select * into v_selection from app.select_vendor_rate(v_request.id, v_rate.id, false, null, null, null, v_rep1, 'tester');

  select * into v_rule from app.create_margin_rule_version(v_tenant1, 20.00, 'half_up', v_rep1, 'tester');
  perform app.publish_margin_rule_version(v_rule.id, v_rule.record_version, null, v_rep1, 'tester');
  v_calc := app.calculate_margin(v_selection.id, 15000000, 'IDR', 0, v_rep1, 'tester');
end $$;

\echo '>> app.record_ai_quotation_suggestion: insufficient_authority for a COM:View-only actor; opportunity_not_found for a wrong opportunity; tenant/feature/correlation/status cross-checks all reject; idempotent on a real, succeeded, correctly-correlated request'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaeaiq');
  v_tenant2 uuid := (select id from app.tenants where slug = 'iaeaiq2');
  v_rep1 uuid := '00000000-0000-0000-0000-000023000002';
  v_viewer1 uuid := '00000000-0000-0000-0000-000023000003';
  v_opportunity_id uuid := (select id from app.opportunities where tenant_id = v_tenant1 and name = 'IaeAiQ ocean lane');
  v_connection_id uuid := (select id from app.integration_connections where tenant_id = v_tenant1 and adapter_code = 'openai_multimodal');
  v_ok_request app.ai_governed_requests;
  v_pending_request app.ai_governed_requests;
  v_wrong_feature_request app.ai_governed_requests;
  v_null_correlation_request app.ai_governed_requests;
  v_row1 app.ai_quotation_suggestions;
  v_row2 app.ai_quotation_suggestions;
begin
  v_ok_request := app.request_ai_governed_action(v_tenant1, v_connection_id, 'ai_assisted_quotation', 'opportunity', v_opportunity_id, jsonb_build_object('opportunity', jsonb_build_object('id', v_opportunity_id)), v_rep1, 'rep');
  v_ok_request := app.record_ai_governed_request_outcome(v_ok_request.id, 'succeeded', jsonb_build_object('draftLines', jsonb_build_array(jsonb_build_object('description', 'Ocean freight'))), 'high', 'openai-multimodal', 0.02, 'USD', null, v_rep1, 'rep');

  begin
    perform app.record_ai_quotation_suggestion(v_tenant1, v_opportunity_id, v_ok_request.id, v_viewer1, 'viewer');
    raise exception 'assertion failed: expected insufficient_authority for a COM:View-only actor';
  exception when others then
    if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  begin
    perform app.record_ai_quotation_suggestion(v_tenant1, '00000000-0000-0000-0000-999999999999', v_ok_request.id, v_rep1, 'rep');
    raise exception 'assertion failed: expected ai_quotation_suggestion_opportunity_not_found for a non-existent opportunity';
  exception when others then
    if sqlerrm not like 'ai_quotation_suggestion_opportunity_not_found%' then raise; end if;
  end;

  -- A real, succeeded request that genuinely belongs to tenant2 -- must never be trackable against tenant1's own opportunity.
  declare
    v_tenant2_connection uuid;
    v_tenant2_opportunity uuid;
    v_admin2 uuid := '00000000-0000-0000-0000-000023000005';
    v_cross_tenant_request app.ai_governed_requests;
  begin
    perform app.create_integration_connection(v_tenant2, 'openai_multimodal', 'OpenAI Multimodal', 'production', null, null, null, jsonb_build_object('apiUrl', 'https://ai.iaeaiq2-provider.test/v1/infer'), 'test-ai-secret', v_admin2, 'admin2');
    v_tenant2_connection := (select id from app.integration_connections where tenant_id = v_tenant2 and adapter_code = 'openai_multimodal');
    v_cross_tenant_request := app.request_ai_governed_action(v_tenant2, v_tenant2_connection, 'ai_assisted_quotation', 'opportunity', v_opportunity_id, jsonb_build_object('probe', true), v_admin2, 'admin2');
    v_cross_tenant_request := app.record_ai_governed_request_outcome(v_cross_tenant_request.id, 'succeeded', jsonb_build_object('draftLines', '[]'::jsonb), 'high', 'openai-multimodal', 0.02, 'USD', null, v_admin2, 'admin2');
    begin
      perform app.record_ai_quotation_suggestion(v_tenant1, v_opportunity_id, v_cross_tenant_request.id, v_rep1, 'rep');
      raise exception 'assertion failed: expected ai_quotation_suggestion_request_tenant_mismatch for a tenant2-owned request';
    exception when others then
      if sqlerrm not like 'ai_quotation_suggestion_request_tenant_mismatch%' then raise; end if;
    end;
  end;

  v_wrong_feature_request := app.request_ai_governed_action(v_tenant1, v_connection_id, 'geocode_address', null, null, jsonb_build_object('address', 'Jl. Sudirman'), v_rep1, 'rep');
  v_wrong_feature_request := app.record_ai_governed_request_outcome(v_wrong_feature_request.id, 'succeeded', jsonb_build_object('lat', -6.2), 'high', 'openai-multimodal', 0.01, 'USD', null, v_rep1, 'rep');
  begin
    perform app.record_ai_quotation_suggestion(v_tenant1, v_opportunity_id, v_wrong_feature_request.id, v_rep1, 'rep');
    raise exception 'assertion failed: expected ai_quotation_suggestion_wrong_feature for a geocode_address request';
  exception when others then
    if sqlerrm not like 'ai_quotation_suggestion_wrong_feature%' then raise; end if;
  end;

  -- Tier B self-check fix's own regression proof: a succeeded ai_assisted_quotation
  -- request with NO correlation set at all must be rejected, not silently accepted
  -- (a bare `<>` on these nullable columns would have let this one through).
  v_null_correlation_request := app.request_ai_governed_action(v_tenant1, v_connection_id, 'ai_assisted_quotation', null, null, jsonb_build_object('opportunity', jsonb_build_object('id', v_opportunity_id)), v_rep1, 'rep');
  v_null_correlation_request := app.record_ai_governed_request_outcome(v_null_correlation_request.id, 'succeeded', jsonb_build_object('draftLines', '[]'::jsonb), 'high', 'openai-multimodal', 0.02, 'USD', null, v_rep1, 'rep');
  begin
    perform app.record_ai_quotation_suggestion(v_tenant1, v_opportunity_id, v_null_correlation_request.id, v_rep1, 'rep');
    raise exception 'assertion failed: expected ai_quotation_suggestion_correlation_mismatch for a request with null correlation';
  exception when others then
    if sqlerrm not like 'ai_quotation_suggestion_correlation_mismatch%' then raise; end if;
  end;

  v_pending_request := app.request_ai_governed_action(v_tenant1, v_connection_id, 'ai_assisted_quotation', 'opportunity', v_opportunity_id, jsonb_build_object('opportunity', jsonb_build_object('id', v_opportunity_id)), v_rep1, 'rep');
  begin
    perform app.record_ai_quotation_suggestion(v_tenant1, v_opportunity_id, v_pending_request.id, v_rep1, 'rep');
    raise exception 'assertion failed: expected ai_quotation_suggestion_request_not_succeeded for a still-pending request';
  exception when others then
    if sqlerrm not like 'ai_quotation_suggestion_request_not_succeeded%' then raise; end if;
  end;

  v_row1 := app.record_ai_quotation_suggestion(v_tenant1, v_opportunity_id, v_ok_request.id, v_rep1, 'rep');
  if v_row1.status <> 'pending' or v_row1.ai_governed_request_id <> v_ok_request.id then
    raise exception 'assertion failed: expected a real pending suggestion row, got %', to_jsonb(v_row1);
  end if;

  -- Idempotent: a retried call for the SAME governed request returns the existing row, never a duplicate.
  v_row2 := app.record_ai_quotation_suggestion(v_tenant1, v_opportunity_id, v_ok_request.id, v_rep1, 'rep');
  if v_row2.id <> v_row1.id then
    raise exception 'assertion failed: expected the idempotent retry to return the SAME suggestion id, got % vs %', v_row1.id, v_row2.id;
  end if;
  if (select count(*) from app.ai_quotation_suggestions where ai_governed_request_id = v_ok_request.id) <> 1 then
    raise exception 'assertion failed: expected exactly one suggestion row for this governed request, found a duplicate';
  end if;

  raise notice 'PASS: record_ai_quotation_suggestion enforces authority, opportunity existence, tenant/feature/correlation/status cross-checks (including the null-correlation regression fix), and is idempotent';
end $$;

\echo '>> read paths: app.get_ai_quotation_suggestion/app.list_ai_quotation_suggestions_for_opportunity are COM:View-gated and surface the underlying governed request''s own real evidence (confidence_label/request_status always visible; output_payload masked behind COM:View cost -- see the dedicated Tier C fix regression block below for the full masking proof); a tenant2 actor with zero tenant1 permissions is denied, never merely returns an empty/masked row'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaeaiq');
  v_rep1 uuid := '00000000-0000-0000-0000-000023000002';
  v_viewer1 uuid := '00000000-0000-0000-0000-000023000003';
  v_admin2 uuid := '00000000-0000-0000-0000-000023000005';
  v_opportunity_id uuid := (select id from app.opportunities where tenant_id = v_tenant1 and name = 'IaeAiQ ocean lane');
  v_suggestion_id uuid;
  v_detail record;
  v_list_count integer;
begin
  select id into v_suggestion_id from app.ai_quotation_suggestions where tenant_id = v_tenant1 and opportunity_id = v_opportunity_id and status = 'pending' order by created_at asc limit 1;

  -- viewer1 lacks COM:View cost -- output_payload is correctly masked here
  -- (Tier C fix, spec-compliance lens); confidence_label/request_status are
  -- never masked, since they carry no pricing/margin data.
  select * into v_detail from app.get_ai_quotation_suggestion(v_suggestion_id, v_viewer1);
  if v_detail.output_payload is not null or not v_detail.output_payload_masked or v_detail.confidence_label <> 'high' or v_detail.request_status <> 'succeeded' then
    raise exception 'assertion failed: expected the viewer to see real confidence_label/request_status but a masked (null) output_payload, got %', to_jsonb(v_detail);
  end if;

  select count(*) into v_list_count from app.list_ai_quotation_suggestions_for_opportunity(v_tenant1, v_opportunity_id, v_rep1, 50);
  if v_list_count < 1 then
    raise exception 'assertion failed: expected at least one listed suggestion, got %', v_list_count;
  end if;

  begin
    perform app.get_ai_quotation_suggestion(v_suggestion_id, v_admin2);
    raise exception 'assertion failed: expected insufficient_authority for a tenant2 actor with zero tenant1 grants';
  exception when others then
    if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  raise notice 'PASS: get/list are COM:View-gated and surface real governed-request evidence; a genuine cross-tenant actor is denied';
end $$;

\echo '>> app.dismiss_ai_quotation_suggestion: insufficient_authority for a COM:View-only actor; atomic pending-only transition -- a second dismiss on the same suggestion raises ai_quotation_suggestion_not_pending'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaeaiq');
  v_rep1 uuid := '00000000-0000-0000-0000-000023000002';
  v_viewer1 uuid := '00000000-0000-0000-0000-000023000003';
  v_opportunity_id uuid := (select id from app.opportunities where tenant_id = v_tenant1 and name = 'IaeAiQ ocean lane');
  v_connection_id uuid := (select id from app.integration_connections where tenant_id = v_tenant1 and adapter_code = 'openai_multimodal');
  v_request app.ai_governed_requests;
  v_suggestion app.ai_quotation_suggestions;
  v_row app.ai_quotation_suggestions;
begin
  v_request := app.request_ai_governed_action(v_tenant1, v_connection_id, 'ai_assisted_quotation', 'opportunity', v_opportunity_id, jsonb_build_object('probe', 'dismiss'), v_rep1, 'rep');
  v_request := app.record_ai_governed_request_outcome(v_request.id, 'succeeded', jsonb_build_object('draftLines', '[]'::jsonb), 'low', 'openai-multimodal', 0.01, 'USD', null, v_rep1, 'rep');
  v_suggestion := app.record_ai_quotation_suggestion(v_tenant1, v_opportunity_id, v_request.id, v_rep1, 'rep');

  begin
    perform app.dismiss_ai_quotation_suggestion(v_suggestion.id, 'no real cost source', v_viewer1, 'viewer');
    raise exception 'assertion failed: expected insufficient_authority for a COM:View-only actor';
  exception when others then
    if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  v_row := app.dismiss_ai_quotation_suggestion(v_suggestion.id, 'no real cost source -- routed to Procurement instead', v_rep1, 'rep');
  if v_row.status <> 'dismissed' or v_row.dismiss_reason is null then
    raise exception 'assertion failed: expected a real dismissed row, got %', to_jsonb(v_row);
  end if;

  begin
    perform app.dismiss_ai_quotation_suggestion(v_suggestion.id, 'second attempt', v_rep1, 'rep');
    raise exception 'assertion failed: expected ai_quotation_suggestion_not_pending on a second dismiss';
  exception when others then
    if sqlerrm not like 'ai_quotation_suggestion_not_pending%' then raise; end if;
  end;

  raise notice 'PASS: dismiss enforces COM:Edit authority and the atomic pending-only transition';
end $$;

\echo '>> app.accept_ai_quotation_suggestion_as_draft: insufficient_authority for a COM:View-only actor (never mutates the suggestion); low-confidence and null-confidence both blocked; no-lines and missing-source both blocked; a real high-confidence acceptance produces a real app.quotations row with correctly copied cost_amount_snapshot/margin_pct_snapshot'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaeaiq');
  v_rep1 uuid := '00000000-0000-0000-0000-000023000002';
  v_viewer1 uuid := '00000000-0000-0000-0000-000023000003';
  v_opportunity_id uuid := (select id from app.opportunities where tenant_id = v_tenant1 and name = 'IaeAiQ ocean lane');
  v_connection_id uuid := (select id from app.integration_connections where tenant_id = v_tenant1 and adapter_code = 'openai_multimodal');
  v_calc_id uuid := (select mc.id from app.margin_calculations mc join app.rate_selections rs on rs.id = mc.rate_selection_id join app.costing_requests cr on cr.id = rs.costing_request_id where cr.opportunity_id = v_opportunity_id and mc.is_current);
  v_low_request app.ai_governed_requests;
  v_low_suggestion app.ai_quotation_suggestions;
  v_null_conf_request app.ai_governed_requests;
  v_null_conf_suggestion app.ai_quotation_suggestions;
  v_high_request app.ai_governed_requests;
  v_high_suggestion app.ai_quotation_suggestions;
  v_quotation app.quotations;
  v_line_cost numeric;
  v_line_margin_pct numeric;
  v_pending_before text;
begin
  -- Low confidence.
  v_low_request := app.request_ai_governed_action(v_tenant1, v_connection_id, 'ai_assisted_quotation', 'opportunity', v_opportunity_id, jsonb_build_object('probe', 'low'), v_rep1, 'rep');
  v_low_request := app.record_ai_governed_request_outcome(v_low_request.id, 'succeeded', jsonb_build_object('draftLines', '[]'::jsonb), 'low', 'openai-multimodal', 0.01, 'USD', null, v_rep1, 'rep');
  v_low_suggestion := app.record_ai_quotation_suggestion(v_tenant1, v_opportunity_id, v_low_request.id, v_rep1, 'rep');
  begin
    perform app.accept_ai_quotation_suggestion_as_draft(v_low_suggestion.id, 'IDR', now() + interval '14 days', null, v_rep1, null,
      jsonb_build_array(jsonb_build_object('line_type', 'service', 'description', 'Ocean freight', 'margin_calculation_id', v_calc_id, 'quantity', 1, 'unit_price', 15000000, 'discount_pct', 0, 'tax_pct', 0)),
      v_rep1, 'rep');
    raise exception 'assertion failed: expected ai_quotation_suggestion_low_confidence_blocked for a low-confidence suggestion';
  exception when others then
    if sqlerrm not like 'ai_quotation_suggestion_low_confidence_blocked%' then raise; end if;
  end;
  select status into v_pending_before from app.ai_quotation_suggestions where id = v_low_suggestion.id;
  if v_pending_before <> 'pending' then
    raise exception 'assertion failed: expected the suggestion to remain pending after a blocked accept attempt, got %', v_pending_before;
  end if;

  -- Null confidence (provider returned no confidence label at all).
  v_null_conf_request := app.request_ai_governed_action(v_tenant1, v_connection_id, 'ai_assisted_quotation', 'opportunity', v_opportunity_id, jsonb_build_object('probe', 'null_conf'), v_rep1, 'rep');
  v_null_conf_request := app.record_ai_governed_request_outcome(v_null_conf_request.id, 'succeeded', jsonb_build_object('draftLines', '[]'::jsonb), null, 'openai-multimodal', 0.01, 'USD', null, v_rep1, 'rep');
  v_null_conf_suggestion := app.record_ai_quotation_suggestion(v_tenant1, v_opportunity_id, v_null_conf_request.id, v_rep1, 'rep');
  begin
    perform app.accept_ai_quotation_suggestion_as_draft(v_null_conf_suggestion.id, 'IDR', now() + interval '14 days', null, v_rep1, null,
      jsonb_build_array(jsonb_build_object('line_type', 'service', 'description', 'Ocean freight', 'margin_calculation_id', v_calc_id, 'quantity', 1, 'unit_price', 15000000, 'discount_pct', 0, 'tax_pct', 0)),
      v_rep1, 'rep');
    raise exception 'assertion failed: expected ai_quotation_suggestion_low_confidence_blocked for a null-confidence suggestion';
  exception when others then
    if sqlerrm not like 'ai_quotation_suggestion_low_confidence_blocked%' then raise; end if;
  end;

  -- Real high-confidence suggestion for the remaining checks.
  v_high_request := app.request_ai_governed_action(v_tenant1, v_connection_id, 'ai_assisted_quotation', 'opportunity', v_opportunity_id, jsonb_build_object('opportunity', jsonb_build_object('id', v_opportunity_id)), v_rep1, 'rep');
  v_high_request := app.record_ai_governed_request_outcome(v_high_request.id, 'succeeded', jsonb_build_object('draftLines', jsonb_build_array(jsonb_build_object('description', 'Ocean freight JKT-SBY'))), 'high', 'openai-multimodal', 0.02, 'USD', null, v_rep1, 'rep');
  v_high_suggestion := app.record_ai_quotation_suggestion(v_tenant1, v_opportunity_id, v_high_request.id, v_rep1, 'rep');

  -- insufficient_authority -- never mutates the suggestion.
  begin
    perform app.accept_ai_quotation_suggestion_as_draft(v_high_suggestion.id, 'IDR', now() + interval '14 days', null, v_rep1, null,
      jsonb_build_array(jsonb_build_object('line_type', 'service', 'description', 'Ocean freight', 'margin_calculation_id', v_calc_id, 'quantity', 1, 'unit_price', 15000000, 'discount_pct', 0, 'tax_pct', 0)),
      v_viewer1, 'viewer');
    raise exception 'assertion failed: expected insufficient_authority for a COM:View-only actor';
  exception when others then
    if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;
  select status into v_pending_before from app.ai_quotation_suggestions where id = v_high_suggestion.id;
  if v_pending_before <> 'pending' then
    raise exception 'assertion failed: expected the suggestion to remain pending after an unauthorized accept attempt (C-05: authority checked before mutation), got %', v_pending_before;
  end if;

  -- No lines provided.
  begin
    perform app.accept_ai_quotation_suggestion_as_draft(v_high_suggestion.id, 'IDR', now() + interval '14 days', null, v_rep1, null, '[]'::jsonb, v_rep1, 'rep');
    raise exception 'assertion failed: expected ai_quotation_suggestion_no_lines_provided for an empty lines array';
  exception when others then
    if sqlerrm not like 'ai_quotation_suggestion_no_lines_provided%' then raise; end if;
  end;

  -- Missing source (no margin_calculation_id on the line).
  begin
    perform app.accept_ai_quotation_suggestion_as_draft(v_high_suggestion.id, 'IDR', now() + interval '14 days', null, v_rep1, null,
      jsonb_build_array(jsonb_build_object('line_type', 'service', 'description', 'Ocean freight', 'quantity', 1, 'unit_price', 15000000, 'discount_pct', 0, 'tax_pct', 0)),
      v_rep1, 'rep');
    raise exception 'assertion failed: expected ai_quotation_suggestion_missing_source for a line with no margin_calculation_id';
  exception when others then
    if sqlerrm not like 'ai_quotation_suggestion_missing_source%' then raise; end if;
  end;
  select status into v_pending_before from app.ai_quotation_suggestions where id = v_high_suggestion.id;
  if v_pending_before <> 'pending' then
    raise exception 'assertion failed: expected the suggestion to remain pending after a rejected accept attempt (whole-function rollback), got %', v_pending_before;
  end if;

  -- The real, successful acceptance.
  v_quotation := app.accept_ai_quotation_suggestion_as_draft(v_high_suggestion.id, 'IDR', now() + interval '14 days', null, v_rep1, null,
    jsonb_build_array(jsonb_build_object('line_type', 'service', 'description', 'Ocean freight JKT-SBY', 'margin_calculation_id', v_calc_id, 'quantity', 1, 'unit_price', 15000000, 'discount_pct', 0, 'tax_pct', 0)),
    v_rep1, 'rep');
  if v_quotation.status <> 'draft' or v_quotation.opportunity_id <> v_opportunity_id then
    raise exception 'assertion failed: expected a real draft quotation for the same opportunity, got %', to_jsonb(v_quotation);
  end if;

  select cost_amount_snapshot, margin_pct_snapshot into v_line_cost, v_line_margin_pct from app.quotation_lines where quotation_id = v_quotation.id;
  if v_line_cost is distinct from (select cost_amount from app.margin_calculations where id = v_calc_id) then
    raise exception 'assertion failed: expected the quotation line''s own cost_amount_snapshot to equal the sourcing margin_calculation''s cost_amount, got % vs %', v_line_cost, (select cost_amount from app.margin_calculations where id = v_calc_id);
  end if;
  if v_line_margin_pct is distinct from (select margin_pct from app.margin_calculations where id = v_calc_id) then
    raise exception 'assertion failed: expected the quotation line''s own margin_pct_snapshot to equal the sourcing margin_calculation''s margin_pct, got % vs %', v_line_margin_pct, (select margin_pct from app.margin_calculations where id = v_calc_id);
  end if;

  if (select status || '|' || coalesce(accepted_quotation_id::text, 'null') from app.ai_quotation_suggestions where id = v_high_suggestion.id) <> ('accepted|' || v_quotation.id::text) then
    raise exception 'assertion failed: expected the suggestion to be accepted and point at the real new quotation id';
  end if;

  -- A dismiss attempt on the now-accepted suggestion is also blocked by the same atomic guard.
  begin
    perform app.dismiss_ai_quotation_suggestion(v_high_suggestion.id, 'too late', v_rep1, 'rep');
    raise exception 'assertion failed: expected ai_quotation_suggestion_not_pending for a dismiss attempt on an already-accepted suggestion';
  exception when others then
    if sqlerrm not like 'ai_quotation_suggestion_not_pending%' then raise; end if;
  end;

  raise notice 'PASS: accept_ai_quotation_suggestion_as_draft enforces authority-before-mutation, the confidence gate (low and null), no-lines/missing-source blocks with full rollback, and produces a real quotation with correctly copied cost/margin snapshots';
end $$;

\echo '>> live concurrency proof: N genuinely concurrent psql processes calling accept_ai_quotation_suggestion_as_draft on the SAME pending suggestion -- exactly one wins, the rest see ai_quotation_suggestion_not_pending (the atomic WHERE-clause guard, not a separate SELECT-then-check)'
\echo '   (setup only in this file -- the concurrent race itself is driven by the orchestrating shell around this test run, see the IAE-020 build log)'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaeaiq');
  v_rep1 uuid := '00000000-0000-0000-0000-000023000002';
  v_opportunity_id uuid := (select id from app.opportunities where tenant_id = v_tenant1 and name = 'IaeAiQ ocean lane');
  v_connection_id uuid := (select id from app.integration_connections where tenant_id = v_tenant1 and adapter_code = 'openai_multimodal');
  v_request app.ai_governed_requests;
  v_suggestion app.ai_quotation_suggestions;
begin
  v_request := app.request_ai_governed_action(v_tenant1, v_connection_id, 'ai_assisted_quotation', 'opportunity', v_opportunity_id, jsonb_build_object('probe', 'race'), v_rep1, 'rep');
  v_request := app.record_ai_governed_request_outcome(v_request.id, 'succeeded', jsonb_build_object('draftLines', '[]'::jsonb), 'high', 'openai-multimodal', 0.02, 'USD', null, v_rep1, 'rep');
  v_suggestion := app.record_ai_quotation_suggestion(v_tenant1, v_opportunity_id, v_request.id, v_rep1, 'rep');
  raise notice 'RACE_SUGGESTION_ID:%', v_suggestion.id;
end $$;

\echo '>> cross-tenant isolation: app.ai_quotation_suggestions carries no direct table grant to authenticated at all (RLS enabled, zero policies, SECURITY DEFINER functions are the only read path) -- a real authenticated session is refused at the grant level, not merely filtered to zero rows'
do $$
begin
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000023000002", "role": "authenticated"}';
  begin
    perform count(*) from app.ai_quotation_suggestions;
    raise exception 'assertion failed: expected permission denied for a direct authenticated select (no table grant exists), the select unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;
  reset role;
end;
$$;

\echo '>> ERR-2026-004 regression guard: zero anon EXECUTE across all 6 of this checkpoint''s own functions'
do $$
declare
  v_anon_grant_count integer;
begin
  select count(*) into v_anon_grant_count
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'app'
    and p.proname in (
      'check_ai_quotation_suggestion_authority', 'record_ai_quotation_suggestion', 'get_ai_quotation_suggestion',
      'list_ai_quotation_suggestions_for_opportunity', 'dismiss_ai_quotation_suggestion', 'accept_ai_quotation_suggestion_as_draft'
    )
    and has_function_privilege('anon', p.oid, 'EXECUTE');

  if v_anon_grant_count <> 0 then
    raise exception 'assertion failed: expected zero anon EXECUTE grants across this checkpoint''s 6 functions, found %', v_anon_grant_count;
  end if;
end;
$$;

-- ===========================================================================
-- IAE-020's own trailing Tier C review fix regressions
-- (supabase/migrations/20260805090000_harden_iae020_tier_c_review_fixes.sql)
-- ===========================================================================

\echo '>> Tier C fix (security lens, High): app.create_quotation_draft now rejects a p_owner_user_id/p_org_unit_id belonging to a DIFFERENT tenant -- live-reproduced as a real, committed cross-tenant write before this fix; a real tenant1 org unit + tenant1-member owner still succeeds'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaeaiq');
  v_tenant2 uuid := (select id from app.tenants where slug = 'iaeaiq2');
  v_rep1 uuid := '00000000-0000-0000-0000-000023000002';
  v_admin2 uuid := '00000000-0000-0000-0000-000023000005';
  v_opportunity_id uuid := (select id from app.opportunities where tenant_id = v_tenant1 and name = 'IaeAiQ ocean lane');
  v_tenant1_org_unit uuid;
  v_tenant2_org_unit uuid;
  v_quotation app.quotations;
begin
  -- v_team_org_unit (code IAEAIQ-CO) already exists -- created in the setup
  -- block above, shared by rep1/juniorrep1 and already the opportunity's own org_unit_id.
  v_tenant1_org_unit := (select id from app.org_units where tenant_id = v_tenant1 and code = 'IAEAIQ-CO');
  perform app.create_org_unit(v_tenant2, 'company', null, 'IAEAIQ2-CO', 'IaeAiQ2 Co', 'tester');
  v_tenant2_org_unit := (select id from app.org_units where tenant_id = v_tenant2 and code = 'IAEAIQ2-CO');

  -- Foreign-tenant owner_user_id (v_admin2 holds zero membership in tenant1).
  begin
    perform app.create_quotation_draft(v_tenant1, v_opportunity_id, 'IDR', now() + interval '14 days', null, v_admin2, null, v_rep1, 'rep');
    raise exception 'assertion failed: expected quotation_owner_not_tenant_member for a foreign-tenant owner_user_id';
  exception when others then
    if sqlerrm not like 'quotation_owner_not_tenant_member%' then raise; end if;
  end;

  -- Foreign-tenant org_unit_id.
  begin
    perform app.create_quotation_draft(v_tenant1, v_opportunity_id, 'IDR', now() + interval '14 days', null, v_rep1, v_tenant2_org_unit, v_rep1, 'rep');
    raise exception 'assertion failed: expected quotation_org_unit_not_found for a foreign-tenant org_unit_id';
  exception when others then
    if sqlerrm not like 'quotation_org_unit_not_found%' then raise; end if;
  end;

  -- A genuine, real tenant1 owner + org unit still succeeds (the fix is scoped, not overbroad).
  v_quotation := app.create_quotation_draft(v_tenant1, v_opportunity_id, 'IDR', now() + interval '14 days', null, v_rep1, v_tenant1_org_unit, v_rep1, 'rep');
  if v_quotation.owner_user_id <> v_rep1 or v_quotation.org_unit_id <> v_tenant1_org_unit then
    raise exception 'assertion failed: expected the real tenant1 owner/org_unit to be accepted, got owner=% org_unit=%', v_quotation.owner_user_id, v_quotation.org_unit_id;
  end if;

  raise notice 'PASS: create_quotation_draft now validates p_owner_user_id/p_org_unit_id against the tenant';
end $$;

\echo '>> Tier C fix (spec-compliance lens, High): app.get_ai_quotation_prompt_context reads via an EXPLICIT actor, never auth.uid() -- called here exactly as the service-role orchestration client calls it (no session/JWT claims set at all), still resolves real opportunity/costing/margin data; cost/margin fields are null for an actor holding COM:Create but lacking COM:View cost, populated for one who holds both; an actor lacking COM:Create entirely is denied; a non-existent/inaccessible opportunity returns zero rows'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaeaiq');
  v_rep1 uuid := '00000000-0000-0000-0000-000023000002';
  v_viewer1 uuid := '00000000-0000-0000-0000-000023000003';
  v_junior_rep1 uuid := '00000000-0000-0000-0000-000023000004';
  v_opportunity_id uuid := (select id from app.opportunities where tenant_id = v_tenant1 and name = 'IaeAiQ ocean lane');
  v_row record;
  v_row_count integer;
begin
  -- No session/role change at all -- this IS what a real service-role client
  -- call looks like from the database's own point of view (auth.uid() would
  -- be NULL here too; the function must not depend on it).
  select * into v_row from app.get_ai_quotation_prompt_context(v_tenant1, v_opportunity_id, v_rep1) limit 1;
  if v_row.opportunity_name <> 'IaeAiQ ocean lane' or v_row.sell_amount is null or v_row.margin_pct is null then
    raise exception 'assertion failed: expected rep1 (holds COM:View cost) to see real opportunity name and unmasked cost/margin fields, got %', to_jsonb(v_row);
  end if;

  -- juniorrep1 holds COM:Create (so CAN request an AI suggestion) but lacks
  -- COM:View cost -- cost/margin fields must be null, never surfaced to an
  -- external AI provider on this actor's behalf.
  select * into v_row from app.get_ai_quotation_prompt_context(v_tenant1, v_opportunity_id, v_junior_rep1) limit 1;
  if v_row.opportunity_name <> 'IaeAiQ ocean lane' or v_row.sell_amount is not null or v_row.margin_pct is not null then
    raise exception 'assertion failed: expected juniorrep1 (lacks COM:View cost) to see the real opportunity name but null cost/margin fields, got %', to_jsonb(v_row);
  end if;

  -- viewer1 lacks COM:Create entirely -- denied outright, never reaches the masking logic.
  begin
    perform app.get_ai_quotation_prompt_context(v_tenant1, v_opportunity_id, v_viewer1);
    raise exception 'assertion failed: expected insufficient_authority for viewer1 (lacks COM:Create)';
  exception when others then
    if sqlerrm not like 'insufficient_authority%' then raise; end if;
  end;

  select count(*) into v_row_count from app.get_ai_quotation_prompt_context(v_tenant1, '00000000-0000-0000-0000-999999999999', v_rep1);
  if v_row_count <> 0 then
    raise exception 'assertion failed: expected zero rows for a non-existent opportunity, got %', v_row_count;
  end if;

  raise notice 'PASS: get_ai_quotation_prompt_context resolves real data via an explicit actor, masks cost/margin correctly, and returns zero rows for a non-existent opportunity';
end $$;

\echo '>> Tier C fix (spec-compliance lens, Medium): app.get_ai_quotation_suggestion/app.list_ai_quotation_suggestions_for_opportunity now mask output_payload behind COM:View cost -- viewer1 (COM:View only) sees output_payload=null/output_payload_masked=true on the SAME row rep1 (holds COM:View cost) sees the real payload for'
do $$
declare
  v_tenant1 uuid := (select id from app.tenants where slug = 'iaeaiq');
  v_rep1 uuid := '00000000-0000-0000-0000-000023000002';
  v_viewer1 uuid := '00000000-0000-0000-0000-000023000003';
  v_opportunity_id uuid := (select id from app.opportunities where tenant_id = v_tenant1 and name = 'IaeAiQ ocean lane');
  v_suggestion_id uuid;
  v_detail record;
begin
  select id into v_suggestion_id from app.ai_quotation_suggestions where tenant_id = v_tenant1 and opportunity_id = v_opportunity_id and status = 'pending' order by created_at asc limit 1;

  select * into v_detail from app.get_ai_quotation_suggestion(v_suggestion_id, v_rep1);
  if v_detail.output_payload is null or v_detail.output_payload_masked <> false then
    raise exception 'assertion failed: expected rep1 (holds COM:View cost) to see the real, unmasked output_payload, got %', to_jsonb(v_detail);
  end if;

  select * into v_detail from app.get_ai_quotation_suggestion(v_suggestion_id, v_viewer1);
  if v_detail.output_payload is not null or v_detail.output_payload_masked <> true then
    raise exception 'assertion failed: expected viewer1 (lacks COM:View cost) to see a null, masked output_payload, got %', to_jsonb(v_detail);
  end if;

  -- Same masking dimension through the list path.
  select * into v_detail from app.list_ai_quotation_suggestions_for_opportunity(v_tenant1, v_opportunity_id, v_viewer1, 50) where id = v_suggestion_id;
  if v_detail.output_payload is not null or v_detail.output_payload_masked <> true then
    raise exception 'assertion failed: expected the list path to mask output_payload identically for viewer1, got %', to_jsonb(v_detail);
  end if;

  raise notice 'PASS: output_payload is masked behind COM:View cost on both read paths, consistently';
end $$;

\echo '>> ai-assisted-quotation.sql: ALL PASSED'
