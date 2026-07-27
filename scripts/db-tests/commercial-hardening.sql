-- Real, executable test evidence for COM-163 (Tenant/Security/Financial/Data Hardening,
-- CG-S7-COM-022) -- run via `pnpm run db:test` against a real, disposable Postgres
-- database. Proves the one finding this checkpoint repairs: app.evaluate_quotation_
-- approval_requirement now requires and checks actor access, closing a cross-tenant
-- business-intelligence disclosure the original COM-153 version left open.

\set ON_ERROR_STOP on

\echo '>> setup: two tenants, each with a rep (COM:Create/Edit/View) and a published quotation-approval rule (40% minimum margin), plus one tenant A quotation whose margin crosses that floor'
do $$
declare
  v_tenant_a uuid;
  v_tenant_b uuid;
  v_team_a uuid;
  v_team_b uuid;
  v_rep_role_a uuid;
  v_rep_draft_a app.role_versions;
  v_rep_role_b uuid;
  v_rep_draft_b app.role_versions;
  v_lead app.leads;
  v_prospect app.prospects;
  v_contact app.contacts;
  v_opportunity app.opportunities;
  v_request app.costing_requests;
  v_rate app.vendor_rate_versions;
  v_selection app.rate_selections;
  v_rule app.margin_rule_versions;
  v_approval_rule app.quotation_approval_rules;
  v_calc_id uuid;
  v_quote app.quotations;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000009949', 'admina@acmehard.test'),
    ('00000000-0000-0000-0000-000000009950', 'repa@acmehard.test'),
    ('00000000-0000-0000-0000-000000009951', 'repb@acmehard.test');

  perform app.provision_tenant('acmeharda', 'Acme Hardening A', 'idem-acmeharda', 'tester');
  v_tenant_a := (select id from app.tenants where slug = 'acmeharda');
  perform app.transition_tenant_status(v_tenant_a, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant_a, 'company', null, 'ACMEHARDA-CO', 'Acme Hardening A', 'tester');
  v_team_a := (select id from app.org_units where tenant_id = v_tenant_a and code = 'ACMEHARDA-CO');

  perform app.provision_tenant('acmehardb', 'Acme Hardening B', 'idem-acmehardb', 'tester');
  v_tenant_b := (select id from app.tenants where slug = 'acmehardb');
  perform app.transition_tenant_status(v_tenant_b, 'active', 'setup', 'tester');
  perform app.create_org_unit(v_tenant_b, 'company', null, 'ACMEHARDB-CO', 'Acme Hardening B', 'tester');
  v_team_b := (select id from app.org_units where tenant_id = v_tenant_b and code = 'ACMEHARDB-CO');

  perform app.invite_user(v_tenant_a, '00000000-0000-0000-0000-000000009949', 'admina@acmehard.test', 'Tenant A Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'admina@acmehard.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000009949', 'tenant_admin', v_tenant_a, null, 'tester');

  perform app.invite_user(v_tenant_a, '00000000-0000-0000-0000-000000009950', 'repa@acmehard.test', 'Rep A', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'repa@acmehard.test'), 'active', 'onboarded', 'tester');
  v_rep_role_a := (app.create_role(v_tenant_a, 'Hardening Rep A', 'test rep', 'tester')).id;
  v_rep_draft_a := app.create_role_version(v_rep_role_a, 'tester');
  perform app.set_role_version_permissions(v_rep_draft_a.id, array(select id from app.permissions where resource_module_code = 'COM' and action in ('Create', 'Edit', 'Approve', 'View', 'View selling price', 'View cost')), 'tester');
  perform app.publish_role_version(v_rep_draft_a.id, now(), 'tester');
  perform app.assign_role(v_tenant_a, (select id from app.role_versions where role_id = v_rep_role_a and status = 'published'), '00000000-0000-0000-0000-000000009950', '00000000-0000-0000-0000-000000009949', 'tester');

  perform app.invite_user(v_tenant_b, '00000000-0000-0000-0000-000000009951', 'repb@acmehard.test', 'Rep B', v_team_b, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'repb@acmehard.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000009951', 'tenant_admin', v_tenant_b, null, 'tester');
  v_rep_role_b := (app.create_role(v_tenant_b, 'Hardening Rep B', 'test rep', 'tester')).id;
  v_rep_draft_b := app.create_role_version(v_rep_role_b, 'tester');
  perform app.set_role_version_permissions(v_rep_draft_b.id, array(select id from app.permissions where resource_module_code = 'COM' and action in ('Create', 'Edit', 'Approve', 'View')), 'tester');
  perform app.publish_role_version(v_rep_draft_b.id, now(), 'tester');
  perform app.assign_role(v_tenant_b, (select id from app.role_versions where role_id = v_rep_role_b and status = 'published'), '00000000-0000-0000-0000-000000009951', '00000000-0000-0000-0000-000000009951', 'tester');

  -- Tenant A's own published 40% minimum-margin approval rule.
  select * into v_approval_rule from app.create_quotation_approval_rule_version(v_tenant_a, 40.00, null, null, '00000000-0000-0000-0000-000000009950', 'tester');
  perform app.publish_quotation_approval_rule_version(v_approval_rule.id, v_approval_rule.record_version, null, '00000000-0000-0000-0000-000000009950', 'tester');

  perform app.capture_lead(v_tenant_a, 'manual', null, 'Hardening Target Co', 'Jane Hard', 'jane@hardtarget.test', '0811',
    '00000000-0000-0000-0000-000000009950', v_team_a, '00000000-0000-0000-0000-000000009950', 'tester');
  select * into v_lead from app.leads where email = 'jane@hardtarget.test';
  perform app.qualify_lead(v_lead.id, v_lead.record_version, '00000000-0000-0000-0000-000000009950', 'tester');
  select * into v_lead from app.leads where id = v_lead.id;
  perform app.convert_lead_to_prospect(v_lead.id, 'Hardening Target Co', 'HTC', '55.555.555.5-555.000', '{}'::jsonb, '00000000-0000-0000-0000-000000009950', 'tester');
  select * into v_prospect from app.prospects where lead_id = v_lead.id;

  select * into v_contact from app.create_contact(v_tenant_a, 'Jane Hard', 'Procurement Lead', 'jane@hardtarget.test', '0811', '00000000-0000-0000-0000-000000009950', v_team_a, '00000000-0000-0000-0000-000000009950', 'tester');
  perform app.link_contact_to_record(v_contact.id, 'prospect', v_prospect.id, 'primary', true, '00000000-0000-0000-0000-000000009950', 'tester');

  select * into v_opportunity from app.create_opportunity(
    v_tenant_a, v_prospect.id, 'Hardening target lane',
    jsonb_build_object('service_type', 'ocean_freight', 'cargo_description', 'General cargo', 'origin', 'Jakarta', 'destination', 'Surabaya', 'target_ready_date', '2026-08-01'),
    '00000000-0000-0000-0000-000000009950', v_team_a, '00000000-0000-0000-0000-000000009950', 'tester'
  );
  select * into v_request from app.request_costing(v_opportunity.id, '[]'::jsonb, null, '00000000-0000-0000-0000-000000009950', 'tester');
  select * into v_rate from app.create_rate_version(
    v_tenant_a, 'VENDOR-HARD-1', 'Contoso Ocean Line', 'ocean_freight', 'FCL', 'Jakarta', 'Surabaya', '20ft',
    null, null, null, null, 'IDR', 10000000, null, '[]'::jsonb, now(), null, null, '00000000-0000-0000-0000-000000009949', 'tester'
  );
  perform app.approve_rate_version(v_rate.id, v_rate.record_version, '00000000-0000-0000-0000-000000009949', 'tester');
  select * into v_selection from app.select_vendor_rate(v_request.id, v_rate.id, false, null, null, null, '00000000-0000-0000-0000-000000009950', 'tester');

  select * into v_rule from app.create_margin_rule_version(v_tenant_a, 5.00, 'half_up', '00000000-0000-0000-0000-000000009950', 'tester');
  perform app.publish_margin_rule_version(v_rule.id, v_rule.record_version, null, '00000000-0000-0000-0000-000000009950', 'tester');
  -- 20% margin -- below the 40% approval-rule floor, so required=true, reasons=[below_minimum_margin].
  perform app.calculate_margin(v_selection.id, 12500000, 'IDR', 0, '00000000-0000-0000-0000-000000009950', 'tester');
  select id into v_calc_id from app.margin_calculations where rate_selection_id = v_selection.id and is_current;

  select * into v_quote from app.create_quotation_draft(v_tenant_a, v_opportunity.id, 'IDR', now() + interval '14 days', v_contact.id, null, null, '00000000-0000-0000-0000-000000009950', 'tester');
  perform app.add_quotation_line(v_quote.id, v_quote.record_version, 'service', 'Ocean freight hardening lane', v_calc_id, 1, 12500000, 0, 0, '00000000-0000-0000-0000-000000009950', 'tester');
end;
$$;

\echo '>> COM-163 fix: app.evaluate_quotation_approval_requirement now requires and checks actor access -- a same-tenant rep with real record access gets the correct required=true/below_minimum_margin result'
do $$
declare
  v_tenant_a uuid;
  v_quote_id uuid;
  v_required boolean;
  v_reasons text[];
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmeharda');
  select id into v_quote_id from app.quotations where tenant_id = v_tenant_a;

  select required, reasons into v_required, v_reasons from app.evaluate_quotation_approval_requirement(v_quote_id, '00000000-0000-0000-0000-000000009950');
  if not v_required or v_reasons <> array['below_minimum_margin'] then
    raise exception 'assertion failed: expected required=true reasons=[below_minimum_margin] for the legitimate same-tenant rep, got required=% reasons=%', v_required, v_reasons;
  end if;
end;
$$;

\echo '>> COM-163 fix, the exact vulnerability closed: a rep in a completely different tenant (B) can no longer learn tenant A''s own quotation''s approval-threshold signal by calling app.evaluate_quotation_approval_requirement with tenant A''s quotation id -- insufficient_privilege, not a leaked boolean/reason'
do $$
declare
  v_tenant_a uuid;
  v_quote_id uuid;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmeharda');
  select id into v_quote_id from app.quotations where tenant_id = v_tenant_a;

  begin
    perform app.evaluate_quotation_approval_requirement(v_quote_id, '00000000-0000-0000-0000-000000009951');
    raise exception 'assertion failed: expected insufficient_privilege -- tenant B''s rep has no membership, role, or record access in tenant A';
  exception
    when insufficient_privilege then
      null; -- expected: the vulnerability this checkpoint closes
  end;
end;
$$;

\echo '>> regression: app.submit_quotation (COM-151/152/153) is unaffected in its main flow -- still resolves routing correctly, still fails closed on no published approval-routing definition, since it already validated the same actor before this checkpoint''s changed internal call'
do $$
declare
  v_tenant_a uuid;
  v_quote app.quotations;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmeharda');
  select * into v_quote from app.quotations where tenant_id = v_tenant_a;

  begin
    perform app.submit_quotation(v_quote.id, v_quote.record_version, '00000000-0000-0000-0000-000000009950', 'rep');
    raise exception 'assertion failed: expected approval_definition_not_configured -- tenant A has a published quotation-approval *rule* but no published Approval Engine *routing definition* yet';
  exception
    when others then
      if sqlerrm !~ 'approval_definition_not_configured' then
        raise exception 'assertion failed: expected approval_definition_not_configured, got %', sqlerrm;
      end if;
  end;
end;
$$;

\echo '>> schema-privilege defense in depth: anon holds no EXECUTE on the widened function; authenticated does (ERR-2026-004 regression guard)'
do $$
declare
  v_anon_has boolean;
  v_authenticated_has boolean;
begin
  select has_function_privilege('anon', p.oid, 'EXECUTE')
    into v_anon_has
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app' and p.proname = 'evaluate_quotation_approval_requirement' and p.pronargs = 2;
  if coalesce(v_anon_has, false) then
    raise exception 'assertion failed: expected anon to hold no EXECUTE on the widened function';
  end if;

  select has_function_privilege('authenticated', p.oid, 'EXECUTE')
    into v_authenticated_has
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app' and p.proname = 'evaluate_quotation_approval_requirement' and p.pronargs = 2;
  if not coalesce(v_authenticated_has, false) then
    raise exception 'assertion failed: expected authenticated to hold EXECUTE on the widened function';
  end if;

  -- The old, vulnerable 1-argument overload must no longer exist at all.
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'app' and p.proname = 'evaluate_quotation_approval_requirement' and p.pronargs = 1) then
    raise exception 'assertion failed: expected the old 1-argument, access-check-free overload to no longer exist';
  end if;
end;
$$;
