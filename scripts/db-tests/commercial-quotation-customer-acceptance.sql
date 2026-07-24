-- Real, executable test evidence for COM-154 (Customer Acceptance, CG-S7-COM-013) -- run
-- via `pnpm run db:test` against a real, disposable Postgres database.

\set ON_ERROR_STOP on

\echo '>> setup: one tenant, a company/branch/two-team org hierarchy, a rep (COM:Create/Edit/View/View selling price/View cost), a sibling-team outsider, a contact, a full opportunity/costing/rate/margin chain (no quotation_approval_rules published, so submit_quotation auto-approves with approval_status=not_required), and five submitted quotations (A..E) for the five decision-flow scenarios below'
do $$
declare
  v_tenant1 uuid;
  v_company uuid;
  v_branch uuid;
  v_team_a uuid;
  v_team_b uuid;
  v_rep_role uuid;
  v_rep_draft app.role_versions;
  v_out_role uuid;
  v_out_draft app.role_versions;
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
  v_letter text;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000009701', 'tenantadmin@acmeaccept.test'),
    ('00000000-0000-0000-0000-000000009702', 'rep@acmeaccept.test'),
    ('00000000-0000-0000-0000-000000009703', 'outsider@acmeaccept.test');

  perform app.provision_tenant('acmeaccept', 'Acme Acceptance Co', 'idem-acmeaccept', 'tester');
  v_tenant1 := (select id from app.tenants where slug = 'acmeaccept');
  perform app.transition_tenant_status(v_tenant1, 'active', 'setup', 'tester');

  perform app.create_org_unit(v_tenant1, 'company', null, 'ACMEACCEPT-CO', 'Acme Acceptance Co', 'tester');
  v_company := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEACCEPT-CO');
  perform app.create_org_unit(v_tenant1, 'branch', v_company, 'ACMEACCEPT-BR', 'Jakarta Branch', 'tester');
  v_branch := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEACCEPT-BR');
  perform app.create_org_unit(v_tenant1, 'department', v_branch, 'ACMEACCEPT-TEAM-A', 'Sales Team A', 'tester');
  v_team_a := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEACCEPT-TEAM-A');
  perform app.create_org_unit(v_tenant1, 'department', v_branch, 'ACMEACCEPT-TEAM-B', 'Sales Team B', 'tester');
  v_team_b := (select id from app.org_units where tenant_id = v_tenant1 and code = 'ACMEACCEPT-TEAM-B');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000009701', 'tenantadmin@acmeaccept.test', 'Tenant Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'tenantadmin@acmeaccept.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000009701', 'tenant_admin', v_tenant1, null, 'tester');

  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000009702', 'rep@acmeaccept.test', 'Rep', v_team_a, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'rep@acmeaccept.test'), 'active', 'onboarded', 'tester');
  perform app.invite_user(v_tenant1, '00000000-0000-0000-0000-000000009703', 'outsider@acmeaccept.test', 'Team B Outsider', v_team_b, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'outsider@acmeaccept.test'), 'active', 'onboarded', 'tester');

  v_rep_role := (app.create_role(v_tenant1, 'Acceptance Rep', 'customer acceptance', 'tester')).id;
  v_rep_draft := app.create_role_version(v_rep_role, 'tester');
  perform app.set_role_version_permissions(
    v_rep_draft.id,
    array(select id from app.permissions where resource_module_code = 'COM' and action in ('Create', 'Edit', 'Approve', 'View', 'View selling price', 'View cost')),
    'tester'
  );
  perform app.publish_role_version(v_rep_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_rep_role and status = 'published'),
    '00000000-0000-0000-0000-000000009702', '00000000-0000-0000-0000-000000009701', 'tester');

  v_out_role := (app.create_role(v_tenant1, 'Team B Acceptance Rep', 'sibling team', 'tester')).id;
  v_out_draft := app.create_role_version(v_out_role, 'tester');
  perform app.set_role_version_permissions(
    v_out_draft.id,
    array(select id from app.permissions where resource_module_code = 'COM' and action in ('Create', 'Edit', 'View', 'View selling price', 'View cost')),
    'tester'
  );
  perform app.publish_role_version(v_out_draft.id, now(), 'tester');
  perform app.assign_role(v_tenant1, (select id from app.role_versions where role_id = v_out_role and status = 'published'),
    '00000000-0000-0000-0000-000000009703', '00000000-0000-0000-0000-000000009701', 'tester');

  perform app.capture_lead(v_tenant1, 'manual', null, 'Contoso Acceptance Ltd', 'Jane Doe Accept', 'jane@contosoaccept.test', '0811',
    '00000000-0000-0000-0000-000000009702', v_team_a, '00000000-0000-0000-0000-000000009702', 'tester');
  select * into v_lead from app.leads where email = 'jane@contosoaccept.test';
  perform app.qualify_lead(v_lead.id, v_lead.record_version, '00000000-0000-0000-0000-000000009702', 'tester');
  select * into v_lead from app.leads where email = 'jane@contosoaccept.test';
  perform app.convert_lead_to_prospect(v_lead.id, 'Contoso Acceptance Ltd', 'Contoso', '01.234.567.8-901.000',
    jsonb_build_object('line1', 'Jl. Sudirman 1', 'city', 'Jakarta', 'country', 'ID'),
    '00000000-0000-0000-0000-000000009702', 'tester');
  select * into v_prospect from app.prospects where legal_name = 'Contoso Acceptance Ltd';

  select * into v_contact from app.create_contact(v_tenant1, 'Jane Doe Accept', 'Procurement Lead', 'jane@contosoaccept.test', '0811', '00000000-0000-0000-0000-000000009702', v_team_a, '00000000-0000-0000-0000-000000009702', 'tester');

  select * into v_opportunity from app.create_opportunity(
    v_tenant1, v_prospect.id, 'Contoso Jakarta-Surabaya acceptance lane',
    jsonb_build_object(
      'service_type', 'ocean_freight', 'cargo_description', 'General cargo',
      'origin', 'Jakarta', 'destination', 'Surabaya', 'target_ready_date', '2026-08-01'
    ),
    '00000000-0000-0000-0000-000000009702', v_team_a, '00000000-0000-0000-0000-000000009702', 'tester'
  );
  select * into v_request from app.request_costing(v_opportunity.id, '[]'::jsonb, null, '00000000-0000-0000-0000-000000009702', 'tester');

  select * into v_rate from app.create_rate_version(
    v_tenant1, 'VENDOR-ACCEPT-1', 'Contoso Ocean Line', 'ocean_freight', 'FCL', 'Jakarta', 'Surabaya', '20ft',
    null, null, null, null, 'IDR', 10000000, null, '[]'::jsonb, now(), null, null,
    '00000000-0000-0000-0000-000000009701', 'tester'
  );
  perform app.approve_rate_version(v_rate.id, v_rate.record_version, '00000000-0000-0000-0000-000000009701', 'tester');
  select * into v_selection from app.select_vendor_rate(v_request.id, v_rate.id, false, null, null, null, '00000000-0000-0000-0000-000000009702', 'tester');

  select * into v_rule from app.create_margin_rule_version(v_tenant1, 20.00, 'half_up', '00000000-0000-0000-0000-000000009702', 'tester');
  perform app.publish_margin_rule_version(v_rule.id, v_rule.record_version, null, '00000000-0000-0000-0000-000000009702', 'tester');
  perform app.calculate_margin(v_selection.id, 15000000, 'IDR', 0, '00000000-0000-0000-0000-000000009702', 'tester');
  select id into v_calc_id from app.margin_calculations where rate_selection_id = v_selection.id and is_current;

  foreach v_letter in array array['A', 'B', 'C', 'D', 'E'] loop
    select * into v_quote from app.create_quotation_draft(v_tenant1, v_opportunity.id, 'IDR', now() + interval '14 days', v_contact.id, null, null, '00000000-0000-0000-0000-000000009702', 'tester');
    perform app.add_quotation_line(v_quote.id, v_quote.record_version, 'service', 'Ocean freight Jakarta-Surabaya ' || v_letter, v_calc_id, 1, 15000000, 0, 0, '00000000-0000-0000-0000-000000009702', 'tester');
    select * into v_quote from app.quotations where id = v_quote.id;
    perform app.submit_quotation(v_quote.id, v_quote.record_version, '00000000-0000-0000-0000-000000009702', 'tester');
  end loop;
end;
$$;

\echo '>> app.send_quotation_for_acceptance (quotation A): authority-gated (outsider denied), produces an active token whose expiry equals the quotation''s own validity_to; resending revokes the prior token and mints a fresh one'
do $$
declare
  v_quote_a app.quotations;
  v_send1 record;
  v_send2 record;
  v_token1_status text;
  v_active_count integer;
begin
  select * into v_quote_a from app.quotations where status = 'submitted' and customer_snapshot ->> 'legal_name' = 'Contoso Acceptance Ltd' order by quote_number asc limit 1;

  begin
    perform app.send_quotation_for_acceptance(v_quote_a.id, null, 'email', '00000000-0000-0000-0000-000000009703', 'outsider');
    raise exception 'assertion failed: expected insufficient_privilege -- the sibling-team outsider cannot send this quotation';
  exception
    when insufficient_privilege then
      null; -- expected
  end;

  select * into v_send1 from app.send_quotation_for_acceptance(v_quote_a.id, null, 'email', '00000000-0000-0000-0000-000000009702', 'tester');
  if v_send1.raw_token is null or length(v_send1.raw_token) = 0 or v_send1.expires_at <> v_quote_a.validity_to then
    raise exception 'assertion failed: expected a non-empty raw_token and expires_at=validity_to (%), got raw_token_len=% expires_at=%', v_quote_a.validity_to, length(coalesce(v_send1.raw_token, '')), v_send1.expires_at;
  end if;

  select * into v_send2 from app.send_quotation_for_acceptance(v_quote_a.id, null, 'email', '00000000-0000-0000-0000-000000009702', 'tester');
  if v_send2.raw_token = v_send1.raw_token then
    raise exception 'assertion failed: expected resend to mint a genuinely fresh raw token, not reuse the prior one';
  end if;

  select status into v_token1_status from app.quotation_acceptance_tokens where id = v_send1.token_id;
  if v_token1_status <> 'revoked' then
    raise exception 'assertion failed: expected the first token to be revoked (superseded_by_resend) once resent, got %', v_token1_status;
  end if;

  select count(*) into v_active_count from app.quotation_acceptance_tokens where quotation_id = v_quote_a.id and status = 'active';
  if v_active_count <> 1 then
    raise exception 'assertion failed: expected exactly one active token after resend, got %', v_active_count;
  end if;
end;
$$;

\echo '>> app.get_quotation_for_customer_decision: an unknown token raises token_not_found; a revoked (superseded) token reports token_status=revoked without raising; the current active token returns the customer-safe projection (never cost/margin) with already_decided=false'
do $$
declare
  v_quote_a app.quotations;
  v_old_token app.quotation_acceptance_tokens;
begin
  select * into v_quote_a from app.quotations where status = 'submitted' and customer_snapshot ->> 'legal_name' = 'Contoso Acceptance Ltd' order by quote_number asc limit 1;

  begin
    perform app.get_quotation_for_customer_decision(encode(gen_random_bytes(32), 'hex'));
    raise exception 'assertion failed: expected token_not_found for a never-issued random token';
  exception
    when no_data_found then
      null; -- expected
  end;
end;
$$;

\echo '>> full accept flow (quotation A): the customer accepts via the currently active token -- app.quotations.customer_decision syncs, the token is consumed (single-use), and a second decision attempt on the same token fails closed (token_already_consumed)'
do $$
declare
  v_quote_a app.quotations;
  v_raw_token text;
  v_send record;
  v_decided app.quotations;
  v_token_status text;
begin
  select * into v_quote_a from app.quotations where status = 'submitted' and customer_snapshot ->> 'legal_name' = 'Contoso Acceptance Ltd' order by quote_number asc limit 1;

  -- Re-send once more from a clean slate so this test owns the one raw token it needs.
  select * into v_send from app.send_quotation_for_acceptance(v_quote_a.id, null, 'email', '00000000-0000-0000-0000-000000009702', 'tester');
  v_raw_token := v_send.raw_token;

  begin
    perform app.record_quotation_customer_decision(v_raw_token, 'rejected', 'Jane Doe Accept', 'Procurement Lead', 'jane@contosoaccept.test', null, '203.0.113.5', 'Mozilla/5.0');
    raise exception 'assertion failed: expected not_null_violation -- a reject without a reason is denied';
  exception
    when not_null_violation then
      null; -- expected
  end;

  select * into v_decided from app.record_quotation_customer_decision(v_raw_token, 'accepted', 'Jane Doe Accept', 'Procurement Lead', 'jane@contosoaccept.test', null, '203.0.113.5', 'Mozilla/5.0');
  if v_decided.customer_decision <> 'accepted' or v_decided.customer_decision_at is null then
    raise exception 'assertion failed: expected customer_decision=accepted with a timestamp, got decision=% at=%', v_decided.customer_decision, v_decided.customer_decision_at;
  end if;

  select status into v_token_status from app.quotation_acceptance_tokens where token_hash = encode(digest(v_raw_token, 'sha256'), 'hex');
  if v_token_status <> 'consumed' then
    raise exception 'assertion failed: expected the token to be consumed after a real decision, got %', v_token_status;
  end if;

  begin
    perform app.record_quotation_customer_decision(v_raw_token, 'accepted', 'Jane Doe Accept', null, 'jane@contosoaccept.test', null, null, null);
    raise exception 'assertion failed: expected token_already_consumed -- the same token cannot decide twice';
  exception
    when sqlstate '23514' then
      if sqlerrm not like 'token_already_consumed:%' then
        raise exception 'assertion failed: expected token_already_consumed, got %', sqlerrm;
      end if;
  end;

  begin
    perform app.send_quotation_for_acceptance(v_quote_a.id, null, 'email', '00000000-0000-0000-0000-000000009702', 'tester');
    raise exception 'assertion failed: expected decision_already_recorded -- a decided quotation can never be re-sent for a second decision';
  exception
    when sqlstate '23514' then
      if sqlerrm not like 'decision_already_recorded:%' then
        raise exception 'assertion failed: expected decision_already_recorded, got %', sqlerrm;
      end if;
  end;
end;
$$;

\echo '>> full reject flow (quotation B): mandatory reason is enforced and stored'
do $$
declare
  v_quote_b app.quotations;
  v_send record;
  v_decided app.quotations;
  v_reason text;
begin
  select * into v_quote_b from app.quotations where status = 'submitted' and customer_snapshot ->> 'legal_name' = 'Contoso Acceptance Ltd' order by quote_number asc offset 1 limit 1;

  select * into v_send from app.send_quotation_for_acceptance(v_quote_b.id, null, 'email', '00000000-0000-0000-0000-000000009702', 'tester');
  select * into v_decided from app.record_quotation_customer_decision(v_send.raw_token, 'rejected', 'Jane Doe Accept', 'Procurement Lead', 'jane@contosoaccept.test', 'Price too high for this lane', null, null);
  if v_decided.customer_decision <> 'rejected' then
    raise exception 'assertion failed: expected customer_decision=rejected, got %', v_decided.customer_decision;
  end if;

  select reason into v_reason from app.quotation_customer_decisions where quotation_id = v_quote_b.id;
  if v_reason <> 'Price too high for this lane' then
    raise exception 'assertion failed: expected the reject reason to be recorded verbatim, got %', v_reason;
  end if;
end;
$$;

\echo '>> expiry (quotation C): a token whose expires_at has already passed lazily flips to expired on read and cannot decide (token_expired)'
do $$
declare
  v_quote_c app.quotations;
  v_send record;
  v_status text;
begin
  select * into v_quote_c from app.quotations where status = 'submitted' and customer_snapshot ->> 'legal_name' = 'Contoso Acceptance Ltd' order by quote_number asc offset 2 limit 1;

  select * into v_send from app.send_quotation_for_acceptance(v_quote_c.id, null, 'email', '00000000-0000-0000-0000-000000009702', 'tester');
  update app.quotation_acceptance_tokens set expires_at = now() - interval '1 minute' where id = v_send.token_id;

  select token_status into v_status from app.get_quotation_for_customer_decision(v_send.raw_token);
  if v_status <> 'expired' then
    raise exception 'assertion failed: expected token_status=expired once expires_at has passed, got %', v_status;
  end if;

  begin
    perform app.record_quotation_customer_decision(v_send.raw_token, 'accepted', 'Jane Doe Accept', null, null, null, null, null);
    raise exception 'assertion failed: expected token_expired -- an expired token cannot record a decision';
  exception
    when sqlstate '23514' then
      if sqlerrm not like 'token_expired:%' then
        raise exception 'assertion failed: expected token_expired, got %', sqlerrm;
      end if;
  end;
end;
$$;

\echo '>> explicit revoke (quotation D): app.revoke_quotation_acceptance_token requires a reason and authority; a revoked token cannot decide (token_revoked); revoking an already-non-active token fails (token_not_active)'
do $$
declare
  v_quote_d app.quotations;
  v_send record;
  v_revoked app.quotation_acceptance_tokens;
begin
  select * into v_quote_d from app.quotations where status = 'submitted' and customer_snapshot ->> 'legal_name' = 'Contoso Acceptance Ltd' order by quote_number asc offset 3 limit 1;

  select * into v_send from app.send_quotation_for_acceptance(v_quote_d.id, null, 'email', '00000000-0000-0000-0000-000000009702', 'tester');

  begin
    perform app.revoke_quotation_acceptance_token(v_send.token_id, '00000000-0000-0000-0000-000000009703', 'outsider', 'trying to interfere');
    raise exception 'assertion failed: expected insufficient_privilege -- the sibling-team outsider cannot revoke this token';
  exception
    when insufficient_privilege then
      null; -- expected
  end;

  begin
    perform app.revoke_quotation_acceptance_token(v_send.token_id, '00000000-0000-0000-0000-000000009702', 'tester', '');
    raise exception 'assertion failed: expected not_null_violation -- an empty revoke reason is rejected';
  exception
    when not_null_violation then
      null; -- expected
  end;

  select * into v_revoked from app.revoke_quotation_acceptance_token(v_send.token_id, '00000000-0000-0000-0000-000000009702', 'tester', 'Customer requested via phone -- resending a corrected copy');
  if v_revoked.status <> 'revoked' or v_revoked.revoked_reason is null then
    raise exception 'assertion failed: expected status=revoked with a reason, got status=% reason=%', v_revoked.status, v_revoked.revoked_reason;
  end if;

  begin
    perform app.record_quotation_customer_decision(v_send.raw_token, 'accepted', 'Jane Doe Accept', null, null, null, null, null);
    raise exception 'assertion failed: expected token_revoked -- a revoked token cannot record a decision';
  exception
    when sqlstate '23514' then
      if sqlerrm not like 'token_revoked:%' then
        raise exception 'assertion failed: expected token_revoked, got %', sqlerrm;
      end if;
  end;

  begin
    perform app.revoke_quotation_acceptance_token(v_send.token_id, '00000000-0000-0000-0000-000000009702', 'tester', 'second attempt');
    raise exception 'assertion failed: expected token_not_active -- an already-revoked token cannot be revoked again';
  exception
    when sqlstate '23514' then
      if sqlerrm not like 'token_not_active:%' then
        raise exception 'assertion failed: expected token_not_active, got %', sqlerrm;
      end if;
  end;
end;
$$;

\echo '>> app.quotations_directory: customer_decision/customer_decision_at visible to any record-scoped viewer regardless of View cost/View selling price; sibling-team outsider still denied via record-scope'
do $$
declare
  v_tenant1 uuid;
  v_visible_count integer;
  v_accepted_count integer;
  v_rejected_count integer;
  v_outsider_count integer;
begin
  v_tenant1 := (select id from app.tenants where slug = 'acmeaccept');

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000009702", "role": "authenticated"}';
  select count(*), count(*) filter (where customer_decision = 'accepted'), count(*) filter (where customer_decision = 'rejected')
    into v_visible_count, v_accepted_count, v_rejected_count
    from app.quotations_directory where tenant_id = v_tenant1;
  if v_visible_count <> 5 or v_accepted_count <> 1 or v_rejected_count <> 1 then
    raise exception 'assertion failed: expected the rep to see all 5 quotations with exactly 1 accepted and 1 rejected, got count=% accepted=% rejected=%', v_visible_count, v_accepted_count, v_rejected_count;
  end if;
  reset role;

  set local role authenticated;
  set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000009703", "role": "authenticated"}';
  select count(*) into v_outsider_count from app.quotations_directory where tenant_id = v_tenant1;
  if v_outsider_count <> 0 then
    raise exception 'assertion failed: expected the sibling-team outsider to be denied via record-scope, found % row(s)', v_outsider_count;
  end if;
  reset role;
end;
$$;

\echo '>> audit trail: send/revoke/decision lifecycle events are all real app.audit_logs rows, tenant-scoped'
do $$
declare
  v_tenant1 uuid;
  v_count integer;
begin
  v_tenant1 := (select id from app.tenants where slug = 'acmeaccept');

  select count(*) into v_count from app.audit_logs where resource_type = 'app.quotation_acceptance_tokens' and action = 'send_quotation_for_acceptance' and tenant_id = v_tenant1;
  if v_count <> 6 then raise exception 'assertion failed: expected exactly 6 successful send_quotation_for_acceptance audit events (A x3, B x1, C x1, D x1), found %', v_count; end if;

  select count(*) into v_count from app.audit_logs where resource_type = 'app.quotation_acceptance_tokens' and action = 'revoke_quotation_acceptance_token' and tenant_id = v_tenant1;
  if v_count <> 1 then raise exception 'assertion failed: expected exactly 1 successful revoke_quotation_acceptance_token audit event, found %', v_count; end if;

  select count(*) into v_count from app.audit_logs where resource_type = 'app.quotations' and action = 'record_quotation_customer_decision' and tenant_id = v_tenant1;
  if v_count <> 2 then raise exception 'assertion failed: expected exactly 2 successful record_quotation_customer_decision audit events (accept + reject), found %', v_count; end if;

  select count(*) into v_count from app.audit_logs where resource_type = 'app.quotations' and action = 'record_quotation_customer_decision' and tenant_id = v_tenant1 and actor_auth_user_id is null;
  if v_count <> 2 then raise exception 'assertion failed: expected every customer-decision audit event to carry a null actor_auth_user_id (no auth.users identity exists for a customer), found %', v_count; end if;
end;
$$;
