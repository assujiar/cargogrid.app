-- Real, executable test evidence for COM-162 (Integrated Commercial Verification,
-- CG-S7-COM-021) -- run via `pnpm run db:test` against a real, disposable Postgres
-- database. Composes 15 of Commercial's 20 capabilities (Lead, Prospect, Contact,
-- Opportunity, Costing Request, Rate and Cost Lookup, Margin Calculation, Quotation
-- Builder, Customer Acceptance, Customer and Account Conversion, Credit and Commercial
-- Control, No-Reentry Enforcement, plus the field-masking/RLS/audit conventions every one
-- of them shares) through one continuous two-tenant golden path -- the representative-
-- composition scope decision `PLT-137` (Platform Core Integrated Verification) already
-- established: this suite does not re-prove any single capability's own already-`VERIFIED`
-- internal correctness (each has its own full db-test file), it proves the *composition*
-- holds -- isolation, masking, audit, and lineage all survive contact with every other
-- capability at once, across two tenants sharing an identical company/contact identity
-- (the realistic "same customer name, two different tenants" no-reentry edge case).
-- Contract/Credit-Approval-routing and Dashboard/Reports are deliberately not re-composed
-- here (already exhaustively tested standalone, including the two-tenant isolation
-- dimension, in their own files) -- `app.check_customer_credit`'s own no-profile path is
-- exercised instead, since it needs no Configuration Engine approval-routing setup and
-- still proves the credit capability composes correctly with the rest of the chain.

\set ON_ERROR_STOP on

\echo '>> setup: two tenants (A, B), each with a company/team org hierarchy, a full-access rep (COM:Create/Edit/Approve/View/View selling price/View cost) and a restricted viewer (COM:View only), sharing the identical company/contact identity "Global Freight Co" / "Jane Doe" -- then one continuous lead->prospect->contact->opportunity->costing->rate->margin->quotation->acceptance->account pipeline run independently for each tenant'
do $$
declare
  v_tenant record;
  v_tenant_slug text;
  v_tenant_id uuid;
  v_company uuid;
  v_team uuid;
  v_rep_role uuid;
  v_rep_draft app.role_versions;
  v_viewer_role uuid;
  v_viewer_draft app.role_versions;
  v_admin_id uuid;
  v_rep_id uuid;
  v_viewer_id uuid;
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
begin
  for v_tenant in select * from (values ('A', 'acmeintvera', '00000000-0000-0000-0000-000000009930'::uuid, '00000000-0000-0000-0000-000000009931'::uuid, '00000000-0000-0000-0000-000000009932'::uuid),
                                        ('B', 'acmeintverb', '00000000-0000-0000-0000-000000009940'::uuid, '00000000-0000-0000-0000-000000009941'::uuid, '00000000-0000-0000-0000-000000009942'::uuid))
                 as t(label, slug, admin_id, rep_id, viewer_id)
  loop
    v_tenant_slug := v_tenant.slug;
    v_admin_id := v_tenant.admin_id;
    v_rep_id := v_tenant.rep_id;
    v_viewer_id := v_tenant.viewer_id;

    insert into auth.users (id, email) values
      (v_admin_id, 'admin@' || v_tenant_slug || '.test'),
      (v_rep_id, 'rep@' || v_tenant_slug || '.test'),
      (v_viewer_id, 'viewer@' || v_tenant_slug || '.test');

    perform app.provision_tenant(v_tenant_slug, 'Acme Integrated Verification ' || v_tenant.label, 'idem-' || v_tenant_slug, 'tester');
    v_tenant_id := (select id from app.tenants where slug = v_tenant_slug);
    perform app.transition_tenant_status(v_tenant_id, 'active', 'setup', 'tester');

    perform app.create_org_unit(v_tenant_id, 'company', null, upper(v_tenant_slug) || '-CO', 'Acme ' || v_tenant.label, 'tester');
    v_company := (select id from app.org_units where tenant_id = v_tenant_id and code = upper(v_tenant_slug) || '-CO');
    perform app.create_org_unit(v_tenant_id, 'department', v_company, upper(v_tenant_slug) || '-TEAM', 'Sales Team', 'tester');
    v_team := (select id from app.org_units where tenant_id = v_tenant_id and code = upper(v_tenant_slug) || '-TEAM');

    perform app.invite_user(v_tenant_id, v_admin_id, 'admin@' || v_tenant_slug || '.test', 'Tenant Admin', null, 'tester', now() + interval '7 days');
    perform app.transition_user_status((select id from app.users where email = 'admin@' || v_tenant_slug || '.test'), 'active', 'onboarded', 'tester');
    perform app.grant_principal_membership(v_admin_id, 'tenant_admin', v_tenant_id, null, 'tester');

    perform app.invite_user(v_tenant_id, v_rep_id, 'rep@' || v_tenant_slug || '.test', 'Rep', v_team, 'tester', now() + interval '7 days');
    perform app.transition_user_status((select id from app.users where email = 'rep@' || v_tenant_slug || '.test'), 'active', 'onboarded', 'tester');
    perform app.invite_user(v_tenant_id, v_viewer_id, 'viewer@' || v_tenant_slug || '.test', 'Restricted Viewer', v_team, 'tester', now() + interval '7 days');
    perform app.transition_user_status((select id from app.users where email = 'viewer@' || v_tenant_slug || '.test'), 'active', 'onboarded', 'tester');

    v_rep_role := (app.create_role(v_tenant_id, 'Integrated Verification Rep', 'full access', 'tester')).id;
    v_rep_draft := app.create_role_version(v_rep_role, 'tester');
    perform app.set_role_version_permissions(
      v_rep_draft.id,
      array(select id from app.permissions where resource_module_code = 'COM' and action in ('Create', 'Edit', 'Approve', 'View', 'View selling price', 'View cost')),
      'tester'
    );
    perform app.publish_role_version(v_rep_draft.id, now(), 'tester');
    perform app.assign_role(v_tenant_id, (select id from app.role_versions where role_id = v_rep_role and status = 'published'), v_rep_id, v_admin_id, 'tester');

    v_viewer_role := (app.create_role(v_tenant_id, 'Integrated Verification Viewer', 'restricted -- no money visibility', 'tester')).id;
    v_viewer_draft := app.create_role_version(v_viewer_role, 'tester');
    perform app.set_role_version_permissions(
      v_viewer_draft.id,
      array(select id from app.permissions where resource_module_code = 'COM' and action = 'View'),
      'tester'
    );
    perform app.publish_role_version(v_viewer_draft.id, now(), 'tester');
    perform app.assign_role(v_tenant_id, (select id from app.role_versions where role_id = v_viewer_role and status = 'published'), v_viewer_id, v_admin_id, 'tester');

    -- The identical company/contact identity, deliberately, in both tenants --
    -- the realistic "two different customers happen to share a name" case no-reentry
    -- checking must never conflate across the tenant boundary.
    perform app.capture_lead(v_tenant_id, 'manual', null, 'Global Freight Co', 'Jane Doe IntVer', 'jane@globalfreight-' || v_tenant_slug || '.test', '0811',
      v_rep_id, v_team, v_rep_id, 'tester');
    select * into v_lead from app.leads where tenant_id = v_tenant_id and email = 'jane@globalfreight-' || v_tenant_slug || '.test';
    perform app.qualify_lead(v_lead.id, v_lead.record_version, v_rep_id, 'tester');
    select * into v_lead from app.leads where id = v_lead.id;
    perform app.convert_lead_to_prospect(v_lead.id, 'Global Freight Co', 'GFC', '44.444.444.4-444.000',
      jsonb_build_object('line1', 'Jl. Gatot Subroto 1', 'city', 'Jakarta', 'country', 'ID'), v_rep_id, 'tester');
    select * into v_prospect from app.prospects where lead_id = v_lead.id;

    select * into v_contact from app.create_contact(v_tenant_id, 'Jane Doe IntVer', 'Procurement Lead', 'jane@globalfreight-' || v_tenant_slug || '.test', '0811', v_rep_id, v_team, v_rep_id, 'tester');
    perform app.link_contact_to_record(v_contact.id, 'prospect', v_prospect.id, 'primary', true, v_rep_id, 'tester');

    select * into v_opportunity from app.create_opportunity(
      v_tenant_id, v_prospect.id, 'GFC integrated lane',
      jsonb_build_object('service_type', 'ocean_freight', 'cargo_description', 'General cargo', 'origin', 'Jakarta', 'destination', 'Surabaya', 'target_ready_date', '2026-08-01'),
      v_rep_id, v_team, v_rep_id, 'tester'
    );
    select * into v_request from app.request_costing(v_opportunity.id, '[]'::jsonb, null, v_rep_id, 'tester');
    select * into v_rate from app.create_rate_version(
      v_tenant_id, 'VENDOR-INTVER-1', 'Contoso Ocean Line', 'ocean_freight', 'FCL', 'Jakarta', 'Surabaya', '20ft',
      null, null, null, null, 'IDR', 10000000, null, '[]'::jsonb, now(), null, null, v_admin_id, 'tester'
    );
    perform app.approve_rate_version(v_rate.id, v_rate.record_version, v_admin_id, 'tester');
    select * into v_selection from app.select_vendor_rate(v_request.id, v_rate.id, false, null, null, null, v_rep_id, 'tester');

    select * into v_rule from app.create_margin_rule_version(v_tenant_id, 20.00, 'half_up', v_rep_id, 'tester');
    perform app.publish_margin_rule_version(v_rule.id, v_rule.record_version, null, v_rep_id, 'tester');
    perform app.calculate_margin(v_selection.id, 15000000, 'IDR', 0, v_rep_id, 'tester');
    select id into v_calc_id from app.margin_calculations where rate_selection_id = v_selection.id and is_current;

    select * into v_quote from app.create_quotation_draft(v_tenant_id, v_opportunity.id, 'IDR', now() + interval '14 days', v_contact.id, null, null, v_rep_id, 'tester');
    perform app.add_quotation_line(v_quote.id, v_quote.record_version, 'service', 'Ocean freight GFC lane', v_calc_id, 1, 15000000, 0, 0, v_rep_id, 'tester');
    select * into v_quote from app.quotations where id = v_quote.id;
    -- No approval rule published for either tenant -- every quotation auto-approves
    -- (COM-153's own disclosed "no threshold crossed -> not_required" main flow),
    -- deliberately keeping this composed fixture's scope to the capabilities named above.
    perform app.submit_quotation(v_quote.id, v_quote.record_version, v_rep_id, 'tester');
    select * into v_send from app.send_quotation_for_acceptance(v_quote.id, null, 'email', v_rep_id, 'tester');
    perform app.record_quotation_customer_decision(v_send.raw_token, 'accepted', 'Jane Doe IntVer', null, null, null, null, null);

    select * into v_account from app.convert_quotation_to_account(v_quote.id, null, null, v_rep_id, 'rep');

    -- app.check_customer_credit's own no-profile path -- COM:View-gated only, no
    -- Configuration Engine approval-routing setup needed, still composes the credit
    -- capability's read path with the rest of the chain.
    perform app.check_customer_credit(v_tenant_id, v_account.id, 'IDR', 15000000, 'quotation', v_quote.id, v_rep_id, 'tester');

    perform app.prepare_job_order_handoff(v_quote.id, v_rep_id, 'rep');
  end loop;
end;
$$;

\echo '>> composed RLS sweep: tenant A''s authenticated session sees zero tenant B rows across every major Commercial table touched by the golden path above, checked together in one combined query -- spanning capabilities from COM-143 through COM-161'
do $$
declare
  v_tenant_a uuid;
  v_leaked integer;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmeintvera');

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000009931", "role": "authenticated"}';

  select
    (select count(*) from app.leads where tenant_id <> v_tenant_a) +
    (select count(*) from app.prospects where tenant_id <> v_tenant_a) +
    (select count(*) from app.contacts where tenant_id <> v_tenant_a) +
    (select count(*) from app.opportunities where tenant_id <> v_tenant_a) +
    (select count(*) from app.costing_requests where tenant_id <> v_tenant_a) +
    (select count(*) from app.vendor_rate_versions where tenant_id <> v_tenant_a) +
    (select count(*) from app.margin_calculations where tenant_id <> v_tenant_a) +
    (select count(*) from app.quotations where tenant_id <> v_tenant_a) +
    (select count(*) from app.job_order_handoffs where tenant_id <> v_tenant_a)
  into v_leaked;

  if v_leaked <> 0 then
    raise exception 'assertion failed: expected zero cross-tenant rows visible across the 9 combined tables, found %', v_leaked;
  end if;

  reset role;
end;
$$;

\echo '>> composed RLS sweep, tenant-wide-visible exception: app.accounts is deliberately tenant-wide (ADR-0018), not record-scoped -- confirmed both tenants'' own accounts remain fully isolated from each other despite sharing the identical legal_name "Global Freight Co"'
do $$
declare
  v_tenant_a uuid;
  v_account_a_id uuid;
  v_account_b_id uuid;
  v_visible_count integer;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmeintvera');
  select id into v_account_a_id from app.accounts where tenant_id = v_tenant_a and legal_name = 'Global Freight Co';
  select id into v_account_b_id from app.accounts where tenant_id = (select id from app.tenants where slug = 'acmeintverb') and legal_name = 'Global Freight Co';

  if v_account_a_id is null or v_account_b_id is null or v_account_a_id = v_account_b_id then
    raise exception 'assertion failed: expected two distinct account rows, one per tenant, both named Global Freight Co, got a=% b=%', v_account_a_id, v_account_b_id;
  end if;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000009931", "role": "authenticated"}';
  select count(*) into v_visible_count from app.accounts where id = v_account_b_id;
  if v_visible_count <> 0 then
    raise exception 'assertion failed: expected tenant A''s rep to see zero rows for tenant B''s own account, despite the identical legal_name, found %', v_visible_count;
  end if;
  reset role;
end;
$$;

\echo '>> composed no-reentry check (COM-161), in this same two-tenant golden path: tenant A''s find_existing_accounts_for_lead/for_prospect never surface tenant B''s "Global Freight Co" account despite the identical company name/legal identity -- and each tenant''s own account_id/account_ref agree (zero drift) after this checkpoint''s real conversion'
do $$
declare
  v_tenant_a uuid;
  v_tenant_b uuid;
  v_team_a uuid;
  v_probe_lead app.leads;
  v_probe_prospect app.prospects;
  v_lead2 app.leads;
  v_cross_tenant_matches integer;
  v_drift_count integer;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmeintvera');
  v_tenant_b := (select id from app.tenants where slug = 'acmeintverb');
  v_team_a := (select id from app.org_units where tenant_id = v_tenant_a and code = 'ACMEINTVERA-TEAM');

  perform app.capture_lead(v_tenant_a, 'manual', null, 'Global Freight Co', 'A Second Rep Contacted Them', 'second@globalfreight-probe.test', '0899',
    '00000000-0000-0000-0000-000000009931', v_team_a, '00000000-0000-0000-0000-000000009931', 'tester');
  select * into v_probe_lead from app.leads where email = 'second@globalfreight-probe.test';

  select count(*) into v_cross_tenant_matches
  from app.find_existing_accounts_for_lead(v_tenant_a, '00000000-0000-0000-0000-000000009931', v_probe_lead.id) t
  where t.tenant_id <> v_tenant_a;
  if v_cross_tenant_matches <> 0 then
    raise exception 'assertion failed: expected zero cross-tenant candidates from find_existing_accounts_for_lead, found %', v_cross_tenant_matches;
  end if;

  -- Same check via the Prospect-stage function (fingerprint-based, COM-155's own
  -- app.find_duplicate_accounts reused) -- a second lead converted to a prospect sharing
  -- the identical legal_name/tax_id as tenant A's own already-converted account.
  perform app.qualify_lead(v_probe_lead.id, v_probe_lead.record_version, '00000000-0000-0000-0000-000000009931', 'tester');
  select * into v_probe_lead from app.leads where id = v_probe_lead.id;
  perform app.convert_lead_to_prospect(v_probe_lead.id, 'Global Freight Co', 'GFC', '44.444.444.4-444.000', '{}'::jsonb,
    '00000000-0000-0000-0000-000000009931', 'tester');
  select * into v_probe_prospect from app.prospects where lead_id = v_probe_lead.id;

  select count(*) into v_cross_tenant_matches
  from app.find_existing_accounts_for_prospect(v_tenant_a, '00000000-0000-0000-0000-000000009931', v_probe_prospect.id) t
  where t.tenant_id <> v_tenant_a;
  if v_cross_tenant_matches <> 0 then
    raise exception 'assertion failed: expected zero cross-tenant candidates from find_existing_accounts_for_prospect, found %', v_cross_tenant_matches;
  end if;

  -- Drift check across both tenants' own real conversions from this checkpoint's golden path.
  select count(*) into v_drift_count from app.commercial_opportunity_account_ref_drift where tenant_id in (v_tenant_a, v_tenant_b);
  if v_drift_count <> 0 then
    raise exception 'assertion failed: expected zero account_ref/account_id drift across both tenants'' own conversions, found %', v_drift_count;
  end if;
end;
$$;

\echo '>> composed masking sweep: the restricted viewer (COM:View only, no View selling price/View cost) sees a consistently masked view of the SAME underlying opportunity/quotation/margin-calculation/job-order-handoff rows the full-access rep sees real figures for -- proving masking composes across four independently-authored directory views together, not just each in isolation'
do $$
declare
  v_tenant_a uuid;
  v_opportunity_id uuid;
  v_quotation_id uuid;
  v_margin_calc_id uuid;
  v_handoff_id uuid;
  v_opp_masked boolean;
  v_quote_masked boolean;
  v_margin_sell_masked boolean;
  v_margin_cost_masked boolean;
  v_handoff_masked boolean;
  v_opp_value numeric;
  v_quote_total numeric;
  v_handoff_payload jsonb;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmeintvera');
  select id into v_opportunity_id from app.opportunities where tenant_id = v_tenant_a and name = 'GFC integrated lane';
  select id into v_quotation_id from app.quotations where tenant_id = v_tenant_a and opportunity_id = v_opportunity_id;
  select mc.id into v_margin_calc_id from app.margin_calculations mc join app.rate_selections rs on rs.id = mc.rate_selection_id join app.costing_requests cr on cr.id = rs.costing_request_id where cr.opportunity_id = v_opportunity_id and mc.is_current;
  select id into v_handoff_id from app.job_order_handoffs where quotation_id = v_quotation_id;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000009932", "role": "authenticated"}';

  select value_masked, value_amount into v_opp_masked, v_opp_value from app.opportunities_directory where id = v_opportunity_id;
  select sell_masked, total_amount into v_quote_masked, v_quote_total from app.quotations_directory where id = v_quotation_id;
  select sell_masked, cost_masked into v_margin_sell_masked, v_margin_cost_masked from app.margin_calculations_directory where id = v_margin_calc_id;
  select payload_masked, payload into v_handoff_masked, v_handoff_payload from app.job_order_handoffs_directory where id = v_handoff_id;

  if not (v_opp_masked and v_quote_masked and v_margin_sell_masked and v_margin_cost_masked and v_handoff_masked) then
    raise exception 'assertion failed: expected every one of the four directory views to report masked=true for the restricted viewer, got opp=% quote=% margin_sell=% margin_cost=% handoff=%',
      v_opp_masked, v_quote_masked, v_margin_sell_masked, v_margin_cost_masked, v_handoff_masked;
  end if;
  if v_opp_value is not null or v_quote_total is not null or v_handoff_payload is not null then
    raise exception 'assertion failed: expected every masked money-bearing column to be null, not merely flagged -- got opp_value=% quote_total=% handoff_payload=%', v_opp_value, v_quote_total, v_handoff_payload;
  end if;

  reset role;

  -- The full-access rep, same rows: unmasked, real figures.
  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000009931", "role": "authenticated"}';

  select value_masked, value_amount into v_opp_masked, v_opp_value from app.opportunities_directory where id = v_opportunity_id;
  select sell_masked, total_amount into v_quote_masked, v_quote_total from app.quotations_directory where id = v_quotation_id;

  if v_opp_masked or v_quote_masked then
    raise exception 'assertion failed: expected the full-access rep to see unmasked figures on the identical rows';
  end if;
  if v_quote_total is null then
    raise exception 'assertion failed: expected a real, non-null quotation total for the full-access rep';
  end if;

  reset role;
end;
$$;

\echo '>> audit trail reconciliation: tenant A''s own app.audit_logs trail spans at least 8 distinct resource types across the composed chain (leads, prospects, opportunities, costing/rate, margin, quotations, accounts, credit snapshots, job order handoffs) -- one coherent, tenant-scoped trail across many independently-authored engines, isolated from tenant B''s own identical-shaped trail'
do $$
declare
  v_tenant_a uuid;
  v_tenant_b uuid;
  v_distinct_resource_types integer;
  v_cross_tenant_count integer;
begin
  v_tenant_a := (select id from app.tenants where slug = 'acmeintvera');
  v_tenant_b := (select id from app.tenants where slug = 'acmeintverb');

  select count(distinct resource_type) into v_distinct_resource_types from app.audit_logs where tenant_id = v_tenant_a;
  if v_distinct_resource_types < 8 then
    raise exception 'assertion failed: expected at least 8 distinct resource_type values in tenant A''s own audit trail across the composed chain, found %', v_distinct_resource_types;
  end if;

  -- Every audit row this checkpoint's own golden path created is correctly attributed
  -- to its own tenant -- no row for tenant A's actions carries tenant B's id or vice versa.
  select count(*) into v_cross_tenant_count
  from app.audit_logs
  where tenant_id = v_tenant_a and resource_id in (select id from app.accounts where tenant_id = v_tenant_b);
  if v_cross_tenant_count <> 0 then
    raise exception 'assertion failed: expected zero tenant A audit rows referencing a tenant B resource id, found %', v_cross_tenant_count;
  end if;
end;
$$;

\echo '>> ERR-2026-004 regression guard, composed sweep (not sampled): zero anon EXECUTE across every function this checkpoint''s golden path actually called, spanning 15 Commercial capabilities'' worth of migrations in one combined query'
do $$
declare
  v_anon_grant_count integer;
begin
  select count(*) into v_anon_grant_count
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'app'
    and p.proname in (
      'capture_lead', 'qualify_lead', 'convert_lead_to_prospect', 'create_contact', 'link_contact_to_record',
      'create_opportunity', 'request_costing', 'create_rate_version', 'approve_rate_version', 'select_vendor_rate',
      'create_margin_rule_version', 'publish_margin_rule_version', 'calculate_margin',
      'create_quotation_draft', 'add_quotation_line', 'submit_quotation', 'send_quotation_for_acceptance',
      'record_quotation_customer_decision', 'convert_quotation_to_account', 'check_customer_credit',
      'prepare_job_order_handoff', 'find_existing_accounts_for_lead', 'find_existing_accounts_for_prospect'
    )
    and has_function_privilege('anon', p.oid, 'EXECUTE');

  if v_anon_grant_count <> 0 then
    raise exception 'assertion failed: expected zero anon EXECUTE grants across the 23 composed golden-path functions, found %', v_anon_grant_count;
  end if;
end;
$$;
