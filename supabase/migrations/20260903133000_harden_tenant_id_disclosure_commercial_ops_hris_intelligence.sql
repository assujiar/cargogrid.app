-- ISS-2026-146 -- cross-tenant tenant_id disclosure via exception message text.
-- Lane: Ticketing / white-label / localization / IAM "and the rest" (the residual after the
-- 20260902100000..20260902104000 Finance/HRIS/Procurement/Ticketing/Platform-Core batch).
--
-- Root cause, unchanged from the original disclosure: a SECURITY DEFINER function looks a
-- record up by its own bare id (unscoped, because the caller does not yet know which tenant
-- owns it), THEN evaluates the actor's authority against the looked-up row's own real
-- tenant_id, and on denial raises 'insufficient_authority: ... for tenant %' interpolating
-- that genuine tenant_id -- handing it to a caller with no demonstrated relationship to that
-- tenant at all.
--
-- Fix, identical in shape to the already-merged precedent (20260902100000, ISS-2026-043/048/
-- 054, and 20260730820000 before them): fold
-- app.has_active_tenant_membership(<row>.tenant_id, <actor>) into the SAME not-found branch
-- the row-miss case already raises, reusing that branch's own generic message and
-- errcode='no_data_found'. A caller with zero relationship to the record's tenant now gets
-- byte-for-byte the error a nonexistent id already produces. A SAME-TENANT member who merely
-- lacks the ROLE authority is untouched: they still reach the insufficient_authority raise
-- below with errcode='insufficient_privilege', exactly as before. That distinction is the
-- whole point of the shape and is preserved deliberately.
--
-- No permission check is weakened. The authority check itself (app.evaluate_permission /
-- app.check_*_authority) is byte-for-byte unchanged; only a tenant-membership pre-check was
-- placed ahead of it. app.evaluate_permission has itself required
-- app.has_active_tenant_membership since 20260810300000 (it returns
-- 'not_active_tenant_member' otherwise), and every app.check_*_authority helper is a thin
-- wrapper over it -- so the added gate can never deny a caller that the authority check
-- would have allowed.
--
-- Bodies were taken from each function's CURRENT, LIVE definition -- the LAST migration in
-- filename order that defines that name, not its creating migration. 40 of them were last
-- defined by 20260831270000 (the p_client_ip widening), which DROPped the pre-p_client_ip
-- signature; the p_client_ip signature below is therefore the only live one and CREATE OR
-- REPLACE matches it exactly. Signatures, SECURITY DEFINER, search_path, volatility and
-- return types are unchanged throughout, so no grant and no public.* wrapper is affected.
--
-- Part 4 of 4: Commercial, Operations, WMS, HRIS payroll, vendor rating and Intelligence.
--
-- Seven functions in this part had NO pre-existing "if not found" guard on the specific
-- SELECT that populates the disclosing row variable, because that row is reached through an
-- FK-guaranteed-to-exist parent id (v_component.actual_cost_id, v_selection.
-- costing_request_id, v_version.config_object_id, v_component.contract_id) or through
-- app.resolve_commercial_record_ref, which raises on a genuine miss before returning. For
-- those a NEW guard is added immediately after that SELECT, reusing the identical message
-- and errcode the function's own sibling not-found check already raises one statement above
-- it -- so the two failure paths stay indistinguishable from the caller's side. This is the
-- same treatment 20260902100000 gave app.get_finance_config_version_items and
-- app.set_finance_config_items.
--
-- 24 functions in this part.

-- app.accept_ai_quotation_suggestion_as_draft -- live definition from 20260805080000_create_intelligence_ai_assisted_quotation.sql
create or replace function app.accept_ai_quotation_suggestion_as_draft(
  p_suggestion_id uuid,
  p_currency text,
  p_validity_to timestamptz,
  p_contact_id uuid,
  p_owner_user_id uuid,
  p_org_unit_id uuid,
  p_accepted_lines jsonb,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.quotations
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_suggestion app.ai_quotation_suggestions;
  v_request app.ai_governed_requests;
  v_line jsonb;
  v_row app.ai_quotation_suggestions;
  v_quotation app.quotations;
  v_current_status text;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_suggestion from app.ai_quotation_suggestions where id = p_suggestion_id;
  if not found or not app.has_active_tenant_membership(v_suggestion.tenant_id, p_actor_auth_user_id) then
    raise exception 'ai_quotation_suggestion_not_found: %', p_suggestion_id using errcode = 'no_data_found';
  end if;

  -- C-05: permission checked before any state mutation, not merely relied
  -- on to fail inside app.create_quotation_draft further down.
  if not app.check_ai_quotation_suggestion_authority('Create', v_suggestion.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks COM:Create for tenant %', p_actor_auth_user_id, v_suggestion.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- Cheap, non-authoritative fast-fail -- avoids creating and immediately
  -- discarding a real quotation draft on an obviously-already-decided
  -- suggestion. The atomic UPDATE below (not this read) is the real guard.
  if v_suggestion.status <> 'pending' then
    raise exception 'ai_quotation_suggestion_not_pending: suggestion % is % not pending', p_suggestion_id, v_suggestion.status using errcode = 'check_violation';
  end if;

  select * into v_request from app.ai_governed_requests where id = v_suggestion.ai_governed_request_id;

  -- Design decision 3: the hard, structural gate -- "Low-confidence/no-
  -- source output blocks auto-draft acceptance" (Prompt 348 §24).
  if v_request.confidence_label is null or v_request.confidence_label = 'low' then
    raise exception 'ai_quotation_suggestion_low_confidence_blocked: request % has confidence_label % -- only high/medium may be accepted as a draft', v_suggestion.ai_governed_request_id, v_request.confidence_label
      using errcode = 'check_violation';
  end if;
  if p_accepted_lines is null or jsonb_typeof(p_accepted_lines) <> 'array' or jsonb_array_length(p_accepted_lines) = 0 then
    raise exception 'ai_quotation_suggestion_no_lines_provided: at least one accepted line is required' using errcode = 'check_violation';
  end if;
  for v_line in select * from jsonb_array_elements(p_accepted_lines) loop
    if nullif(v_line ->> 'margin_calculation_id', '') is null then
      raise exception 'ai_quotation_suggestion_missing_source: every accepted line must cite a real margin_calculation_id -- rate/tax/currency values must come from canonical sources'
        using errcode = 'check_violation';
    end if;
  end loop;

  -- Design decisions 1, 5: the EXISTING, UNMODIFIED Commercial RPCs do all
  -- the real work -- created BEFORE the suggestion's own atomic transition
  -- below, so that if any line fails their own independent validation,
  -- this whole function raises and NOTHING it did survives (a single
  -- top-level function call is one atomic statement -- whole-function
  -- rollback, not merely the suggestion's own status flip).
  v_quotation := app.create_quotation_draft(
    v_suggestion.tenant_id, v_suggestion.opportunity_id, p_currency, p_validity_to,
    p_contact_id, p_owner_user_id, p_org_unit_id, p_actor_auth_user_id, p_actor_label
  );

  for v_line in select * from jsonb_array_elements(p_accepted_lines) loop
    v_quotation := app.add_quotation_line(
      v_quotation.id, v_quotation.record_version,
      v_line ->> 'line_type', v_line ->> 'description', (v_line ->> 'margin_calculation_id')::uuid,
      (v_line ->> 'quantity')::numeric, (v_line ->> 'unit_price')::numeric,
      (v_line ->> 'discount_pct')::numeric, (v_line ->> 'tax_pct')::numeric,
      p_actor_auth_user_id, p_actor_label
    );
  end loop;

  -- Atomic pending-only transition LAST -- status and accepted_quotation_id
  -- are set together in ONE statement (the table's own accepted-shape check
  -- constraint requires both change together; a two-step write here would
  -- violate it on the first step). The WHERE clause alone remains the
  -- concurrency guard (Tier C fix 12's own lesson): a losing concurrent
  -- caller's own create_quotation_draft/add_quotation_line calls above are
  -- rolled back along with the raise below, never left as an orphan draft.
  update app.ai_quotation_suggestions
  set status = 'accepted', accepted_quotation_id = v_quotation.id, reviewed_by_auth_user_id = p_actor_auth_user_id, reviewed_by = p_actor_label, reviewed_at = now()
  where id = p_suggestion_id and status = 'pending'
  returning * into v_row;

  if v_row.id is null then
    select status into v_current_status from app.ai_quotation_suggestions where id = p_suggestion_id;
    raise exception 'ai_quotation_suggestion_not_pending: suggestion % is % not pending', p_suggestion_id, v_current_status using errcode = 'check_violation';
  end if;

  perform app.capture_audit_event(
    v_suggestion.tenant_id, p_actor_auth_user_id, p_actor_label, 'accept_ai_quotation_suggestion_as_draft',
    'app.ai_quotation_suggestions', v_suggestion.id, 'success', null, null,
    jsonb_build_object('ai_governed_request_id', v_suggestion.ai_governed_request_id, 'quotation_id', v_quotation.id)
  );

  return v_quotation;
end;
$$;

-- app.accept_vendor_capacity_reservation -- live definition from 20260831150000_add_vendor_capacity_manual_confirmation_evidence.sql
create or replace function app.accept_vendor_capacity_reservation(
  p_reservation_id uuid,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_capacity_reservations
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_reservation app.vendor_capacity_reservations;
begin
  select * into v_reservation from app.vendor_capacity_reservations where id = p_reservation_id;
  if not found or not app.has_active_tenant_membership(v_reservation.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_capacity_reservation_not_found: %', p_reservation_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_reservation.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_reservation.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_reservation.record_version <> p_expected_version then
    raise exception 'stale_version: vendor capacity reservation % expected version % but found %', p_reservation_id, p_expected_version, v_reservation.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_reservation.status <> 'held' then
    raise exception 'invalid_transition: vendor capacity reservation % is % and cannot be accepted', p_reservation_id, v_reservation.status
      using errcode = 'check_violation';
  end if;

  update app.vendor_capacity_reservations
  set status = 'accepted',
      confirmation_method = 'system_accept',
      confirmed_by_auth_user_id = p_actor_auth_user_id,
      confirmed_at = now()
  where id = p_reservation_id and record_version = p_expected_version
  returning * into v_reservation;
  if not found then
    raise exception 'stale_version: vendor capacity reservation % target row was concurrently modified (expected version %)', p_reservation_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_reservation.tenant_id, p_actor_auth_user_id, p_actor_label, 'accept_vendor_capacity_reservation',
    'app.vendor_capacity_reservations', v_reservation.id, 'success', null, null,
    jsonb_build_object('confirmation_method', 'system_accept')
  );

  return v_reservation;
end;
$$;

-- app.attach_training_provider_evidence -- live definition from 20260831190000_add_training_provider_evidence_attachment.sql
create or replace function app.attach_training_provider_evidence(p_provider_id uuid, p_expected_version integer, p_evidence_file_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
returns app.training_providers
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_provider app.training_providers;
  v_file app.files;
begin
  select * into v_provider from app.training_providers where id = p_provider_id for update;
  if not found or not app.has_active_tenant_membership(v_provider.tenant_id, p_actor_auth_user_id) then
    raise exception 'training_provider_not_found: %', p_provider_id using errcode = 'no_data_found';
  end if;
  if not app.check_training_authority('Edit', v_provider.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit for tenant %', p_actor_auth_user_id, v_provider.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_provider.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_provider.record_version
      using errcode = 'serialization_failure';
  end if;

  -- Re-validated here, not trusted from the upload: a file clean at upload may not be clean now,
  -- and one uploaded against a different provider must never count as evidence for this one.
  select * into v_file from app.files where id = p_evidence_file_id;
  if not found or v_file.tenant_id <> v_provider.tenant_id or v_file.record_type <> 'training_provider' or v_file.record_id <> p_provider_id then
    raise exception 'evidence_file_not_found: file % is not a valid evidence file for provider %', p_evidence_file_id, p_provider_id using errcode = 'no_data_found';
  end if;
  if v_file.malware_scan_status = 'infected' then
    raise exception 'evidence_file_infected: file % failed malware scanning and cannot be attached', p_evidence_file_id using errcode = 'check_violation';
  end if;
  if v_file.malware_scan_status <> 'clean' then
    raise exception 'evidence_file_not_scanned: file % has not cleared malware scanning (status %)', p_evidence_file_id, v_file.malware_scan_status
      using errcode = 'check_violation';
  end if;

  update app.training_providers set evidence_file_id = p_evidence_file_id where id = p_provider_id and record_version = p_expected_version
  returning * into v_provider;
  if not found then
    raise exception 'stale_version: concurrent update detected for provider %', p_provider_id using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_provider.tenant_id, p_actor_auth_user_id, p_actor_label, 'attach_training_provider_evidence',
    'app.training_providers', v_provider.id, 'success', null, null, jsonb_build_object('evidence_file_id', p_evidence_file_id)
  );

  return v_provider;
end;
$$;

-- app.calculate_margin -- live definition from 20260724180000_create_commercial_margin_calculation.sql
create or replace function app.calculate_margin(
  p_rate_selection_id uuid,
  p_sell_amount numeric,
  p_sell_currency text,
  p_discount_pct numeric,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.margin_calculations
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_selection app.rate_selections;
  v_request app.costing_requests;
  v_decision_edit app.rbac_decision;
  v_rule app.margin_rule_versions;
  v_discount_pct numeric;
  v_discount_amount numeric;
  v_net_sell numeric;
  v_margin_amount numeric;
  v_margin_pct numeric;
  v_markup_pct numeric;
  v_threshold_outcome text;
  v_new_id uuid := gen_random_uuid();
  v_prior_id uuid;
  v_calc app.margin_calculations;
begin
  select * into v_selection from app.rate_selections where id = p_rate_selection_id;
  if not found then
    raise exception 'rate_selection_not_found: %', p_rate_selection_id using errcode = 'no_data_found';
  end if;

  select * into v_request from app.costing_requests where id = v_selection.costing_request_id;
  if not app.has_active_tenant_membership(v_request.tenant_id, p_actor_auth_user_id) then
    raise exception 'rate_selection_not_found: %', p_rate_selection_id using errcode = 'no_data_found';
  end if;

  v_decision_edit := app.evaluate_permission(p_actor_auth_user_id, v_request.tenant_id, 'COM', 'Edit');
  if not v_decision_edit.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Edit (%) for tenant %', p_actor_auth_user_id, v_decision_edit.reason, v_request.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.has_view_cost(v_request.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks COM:View cost required to calculate a margin', p_actor_auth_user_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_request.tenant_id, v_request.owner_user_id, app.lead_record_scope_org_unit_ids(v_request.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access costing request %', p_actor_auth_user_id, v_request.id
      using errcode = 'insufficient_privilege';
  end if;

  if p_sell_currency is null or p_sell_currency <> v_selection.currency then
    raise exception 'mixed_currency: sell currency % does not match the pinned cost snapshot''s currency %', p_sell_currency, v_selection.currency
      using errcode = 'check_violation';
  end if;

  select * into v_rule from app.margin_rule_versions where tenant_id = v_request.tenant_id and status = 'published';
  if not found then
    raise exception 'no_active_margin_rule: tenant % has no published margin rule -- calculation cannot proceed', v_request.tenant_id
      using errcode = 'check_violation';
  end if;

  v_discount_pct := coalesce(p_discount_pct, 0);
  if v_discount_pct < 0 or v_discount_pct > 100 then
    raise exception 'invalid_discount: discount_pct % is out of the 0..100 range', v_discount_pct
      using errcode = 'check_violation';
  end if;

  v_discount_amount := round(p_sell_amount * v_discount_pct / 100, 2);
  v_net_sell := p_sell_amount - v_discount_amount;
  v_margin_amount := round(v_net_sell - v_selection.amount, 2);
  v_margin_pct := case when v_net_sell = 0 then 0 else round(v_margin_amount / v_net_sell * 100, 2) end;
  v_markup_pct := case when v_selection.amount = 0 then null else round(v_margin_amount / v_selection.amount * 100, 2) end;
  v_threshold_outcome := case when v_margin_pct >= v_rule.minimum_margin_pct then 'pass' else 'requires_approval' end;

  -- Three-step supersede, in this exact order: (1) the prior current row is marked
  -- not-current *before* the new row is inserted, since the partial unique index
  -- margin_calculations_current_unique (rate_selection_id where is_current) would
  -- otherwise reject the new insert while the old row is still is_current=true; (2) the
  -- new row is inserted; (3) only now can the prior row's superseded_by_id (a foreign
  -- key) be set, since it must reference a row that already exists.
  select id into v_prior_id from app.margin_calculations where rate_selection_id = p_rate_selection_id and is_current;

  if v_prior_id is not null then
    update app.margin_calculations
    set is_current = false, updated_at = now(), record_version = record_version + 1
    where id = v_prior_id;
  end if;

  insert into app.margin_calculations (
    id, tenant_id, costing_request_id, rate_selection_id,
    cost_amount, cost_currency, sell_amount, sell_currency,
    discount_pct, discount_amount, net_sell_amount, margin_amount, margin_pct, markup_pct,
    rule_version_id, minimum_margin_pct_snapshot, rounding_mode_snapshot, threshold_outcome,
    owner_user_id, org_unit_id, created_by
  ) values (
    v_new_id, v_request.tenant_id, v_request.id, p_rate_selection_id,
    v_selection.amount, v_selection.currency, p_sell_amount, p_sell_currency,
    v_discount_pct, v_discount_amount, v_net_sell, v_margin_amount, v_margin_pct, v_markup_pct,
    v_rule.id, v_rule.minimum_margin_pct, v_rule.rounding_mode, v_threshold_outcome,
    v_request.owner_user_id, v_request.org_unit_id, p_actor_label
  )
  returning * into v_calc;

  if v_prior_id is not null then
    update app.margin_calculations set superseded_by_id = v_new_id where id = v_prior_id;
  end if;

  perform app.capture_audit_event(
    v_request.tenant_id, p_actor_auth_user_id, p_actor_label, 'calculate_margin',
    'app.margin_calculations', v_calc.id, 'success', null, null,
    jsonb_build_object('margin_pct', v_margin_pct, 'threshold_outcome', v_threshold_outcome, 'rule_version_id', v_rule.id)
  );

  return v_calc;
end;
$$;

-- app.calculate_payroll_run -- live definition from 20260731000000_create_hris_payroll_foundation.sql
create or replace function app.calculate_payroll_run(p_run_id uuid, p_expected_version integer, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.payroll_runs
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_run app.payroll_runs;
  v_period app.payroll_periods;
  v_job app.jobs;
  v_worker_id text;
  v_snapshot app.payroll_input_snapshots;
  v_employee_count integer := 0;
  v_exception_count integer := 0;
  v_chunk_size constant integer := 25;
  v_since_heartbeat integer := 0;
  v_current_job app.jobs;
  v_cancelled boolean := false;
begin
  select * into v_run from app.payroll_runs where id = p_run_id for update;
  if not found or not app.has_active_tenant_membership(v_run.tenant_id, p_actor_auth_user_id) then
    raise exception 'payroll_run_not_found: %', p_run_id using errcode = 'no_data_found';
  end if;
  if not app.check_payroll_authority('Edit', v_run.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit for tenant %', p_actor_auth_user_id, v_run.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_run.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_run.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_run.status not in ('draft', 'calculated', 'exception') then
    raise exception 'invalid_transition: run % is % -- only draft/calculated/exception may (re)calculate', p_run_id, v_run.status
      using errcode = 'check_violation';
  end if;

  select * into v_period from app.payroll_periods where id = v_run.payroll_period_id;
  if v_period.status = 'open' then
    raise exception 'payroll_period_inputs_not_frozen: period % has not had its inputs frozen yet', v_period.id using errcode = 'check_violation';
  end if;

  v_job := app.enqueue_job(
    v_run.tenant_id, 'payroll_calculation', jsonb_build_object('run_id', p_run_id),
    0, coalesce(p_idempotency_key, 'payroll_calc:' || p_run_id::text || ':' || gen_random_uuid()::text), 3, p_actor_auth_user_id, p_actor_label
  );
  -- C-01: full-tuple idempotency replay check -- a key match must target
  -- THIS run, never merely share a key by coincidence.
  if (v_job.payload ->> 'run_id')::uuid <> p_run_id then
    raise exception 'idempotency_key_conflict: key was already used for a different payroll run' using errcode = 'check_violation';
  end if;
  if v_job.status <> 'pending' then
    -- A genuine replay of an already-processed key -- return the run
    -- unchanged, never recompute a second time under the same key.
    return v_run;
  end if;

  v_worker_id := 'inline-payroll-calc:' || p_actor_auth_user_id::text;
  update app.jobs set status = 'in_progress', locked_by = v_worker_id, locked_until = now() + interval '10 minutes'
  where job_id = v_job.job_id and status = 'pending';

  update app.payroll_runs set status = 'calculating' where id = p_run_id;

  delete from app.payroll_calculation_lines where payroll_run_id = p_run_id;
  delete from app.payroll_run_employee_results where payroll_run_id = p_run_id;
  delete from app.payroll_exceptions where payroll_run_id = p_run_id;

  for v_snapshot in select * from app.payroll_input_snapshots where payroll_period_id = v_run.payroll_period_id order by employee_id loop
    v_since_heartbeat := v_since_heartbeat + 1;
    if v_since_heartbeat >= v_chunk_size then
      -- Checkpoint boundary: extend the lease, and honor a concurrent
      -- cancellation request (app.cancel_import_export_job sets status
      -- 'cancelling' on a job already in_progress).
      select * into v_current_job from app.jobs where job_id = v_job.job_id;
      if v_current_job.status = 'cancelling' then
        v_cancelled := true;
        exit;
      end if;
      perform app.heartbeat_job(v_job.job_id, v_worker_id, 600);
      v_since_heartbeat := 0;
    end if;

    begin
      perform app._calculate_payroll_run_for_employee(v_run, v_period.period_end, v_snapshot, p_actor_label);
      v_employee_count := v_employee_count + 1;
    exception
      when others then
        insert into app.payroll_exceptions (tenant_id, payroll_run_id, employee_id, exception_type, severity, message)
        values (v_run.tenant_id, p_run_id, v_snapshot.employee_id, 'calculation_error', 'high', sqlerrm);
        v_exception_count := v_exception_count + 1;
    end;
  end loop;

  if v_cancelled then
    perform app.acknowledge_job_cancellation(v_job.job_id, p_actor_auth_user_id, p_actor_label);
    update app.payroll_runs set status = 'draft' where id = p_run_id returning * into v_run;
    perform app.capture_audit_event(
      v_run.tenant_id, p_actor_auth_user_id, p_actor_label, 'calculate_payroll_run_cancelled',
      'app.payroll_runs', v_run.id, 'success', null, null, jsonb_build_object('processed_before_cancel', v_employee_count)
    );
    return v_run;
  end if;

  perform app.complete_job(v_job.job_id, v_worker_id, null, p_actor_label);

  update app.payroll_runs
  set status = case when v_exception_count > 0 then 'exception' else 'calculated' end,
      employee_count = v_employee_count, exception_count = v_exception_count, calculated_by = p_actor_label, calculated_at = now(), job_id = v_job.job_id
  where id = p_run_id
  returning * into v_run;

  perform app.capture_audit_event(
    v_run.tenant_id, p_actor_auth_user_id, p_actor_label, 'calculate_payroll_run',
    'app.payroll_runs', v_run.id, 'success', null, null,
    jsonb_build_object('employee_count', v_employee_count, 'exception_count', v_exception_count)
  );

  return v_run;
end;
$$;

-- app.calculate_vendor_rate -- live definition from 20260730620000_extend_commercial_vendor_rate_for_procurement.sql
create or replace function app.calculate_vendor_rate(
  p_rate_version_id uuid,
  p_weight numeric,
  p_volume numeric,
  p_quantity numeric,
  p_actor_auth_user_id uuid
)
returns table (
  rate_version_id uuid,
  matched_tier_id uuid,
  currency text,
  base_component numeric,
  tier_component numeric,
  surcharge_component numeric,
  subtotal_amount numeric,
  minimum_amount_applied boolean,
  computed_amount numeric,
  rounding_mode text,
  rounding_precision integer,
  uom_basis jsonb,
  component_breakdown jsonb,
  computed_at timestamptz
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_rate app.vendor_rate_versions;
  v_decision app.rbac_decision;
begin
  select * into v_rate from app.vendor_rate_versions where id = p_rate_version_id;
  if not found or not app.has_active_tenant_membership(v_rate.tenant_id, p_actor_auth_user_id) then
    raise exception 'rate_version_not_found: %', p_rate_version_id using errcode = 'no_data_found';
  end if;

  -- ADR-0020's own directed gate: the entire return shape of this function is cost
  -- data (there is no non-cost-masked variant of "the computed amount"), so
  -- PRC:View cost alone -- not PRC:View + the unrelated COM:View cost -- is the
  -- single, correct authority gate (design note above app.has_prc_view_cost).
  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_rate.tenant_id, 'PRC', 'View cost');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View cost (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_rate.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
  select p_rate_version_id, c.matched_tier_id, v_rate.currency, c.base_component, c.tier_component, c.surcharge_component,
    c.subtotal_amount, c.minimum_amount_applied, c.computed_amount, c.rounding_mode, c.rounding_precision, c.uom_basis, c.component_breakdown, now()
  from app._compute_vendor_rate_amount(v_rate, p_weight, p_volume, p_quantity) c;
end;
$$;

-- app.calculate_vendor_rate_zoned -- live definition from 20260902030000_add_vendor_rate_zone_distance_pricing_iss2026060.sql
create or replace function app.calculate_vendor_rate_zoned(
  p_rate_version_id uuid,
  p_zone_code text,
  p_distance numeric,
  p_weight numeric,
  p_volume numeric,
  p_quantity numeric,
  p_actor_auth_user_id uuid
)
returns table (
  rate_version_id uuid,
  zone_distance_priced boolean,
  matched_tier_id uuid,
  currency text,
  base_component numeric,
  tier_component numeric,
  surcharge_component numeric,
  subtotal_amount numeric,
  minimum_amount_applied boolean,
  computed_amount numeric,
  rounding_mode text,
  rounding_precision integer,
  component_breakdown jsonb,
  computed_at timestamptz
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_rate app.vendor_rate_versions;
  v_decision app.rbac_decision;
  v_has_zone_tiers boolean;
begin
  select * into v_rate from app.vendor_rate_versions where id = p_rate_version_id;
  if not found or not app.has_active_tenant_membership(v_rate.tenant_id, p_actor_auth_user_id) then
    raise exception 'rate_version_not_found: %', p_rate_version_id using errcode = 'no_data_found';
  end if;

  -- Same gate app.calculate_vendor_rate itself requires (ADR-0020's own directed
  -- reuse) -- the entire return shape is cost data either way.
  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_rate.tenant_id, 'PRC', 'View cost');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View cost (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_rate.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select exists(select 1 from app.vendor_rate_zone_distance_tiers z where z.rate_version_id = p_rate_version_id) into v_has_zone_tiers;

  if v_has_zone_tiers then
    return query
    select p_rate_version_id, true, z.matched_tier_id, v_rate.currency, z.base_component, z.tier_component, z.surcharge_component,
      z.subtotal_amount, z.minimum_amount_applied, z.computed_amount, z.rounding_mode, z.rounding_precision, z.component_breakdown, now()
    from app._compute_vendor_rate_zone_distance_amount(v_rate, p_zone_code, p_distance, p_quantity) z;
  else
    -- No zone/distance dimension configured on this rate card: compose with the
    -- existing, UNMODIFIED weight/volume resolution engine -- byte-identical to
    -- app.calculate_vendor_rate's own result for the same inputs (design note 3).
    return query
    select p_rate_version_id, false, c.matched_tier_id, v_rate.currency, c.base_component, c.tier_component, c.surcharge_component,
      c.subtotal_amount, c.minimum_amount_applied, c.computed_amount, c.rounding_mode, c.rounding_precision, c.component_breakdown, now()
    from app._compute_vendor_rate_amount(v_rate, p_weight, p_volume, p_quantity) c;
  end if;
end;
$$;

-- app.commit_position_crosswalk_import_job -- live definition from 20260902040000_create_position_crosswalk_import_adapter.sql
create or replace function app.commit_position_crosswalk_import_job(
  p_job_id uuid,
  p_allow_partial boolean,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  p_client_ip text default null
)
returns app.jobs
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_job app.jobs;
  v_decision app.rbac_decision;
  v_pending_count integer;
  v_row record;
  v_payload jsonb;
  v_employee_id uuid;
  v_employee_version integer;
  v_employee_status text;
  v_position_id uuid;
  v_grade_id uuid;
  v_manager_id uuid;
  v_assignment_type text;
  v_change_reason text;
  v_start_date date;
  v_end_date date;
  v_allocation numeric;
  v_reason_note text;
  v_proposed app.employee_position_assignments;
  v_config_version_id uuid;
  v_created_count integer := 0;
  v_skipped_count integer := 0;
  v_updated app.jobs;
begin
  select * into v_job from app.jobs where job_id = p_job_id for update;
  if not found or not app.has_active_tenant_membership(v_job.tenant_id, p_actor_auth_user_id) then
    raise exception 'import_export_job_not_found: no job %', p_job_id using errcode = 'no_data_found';
  end if;

  if v_job.job_type <> 'import' or v_job.import_export_schema_code <> 'position_crosswalk_import' then
    raise exception 'import_export_wrong_schema: job % is not a position_crosswalk_import job', p_job_id using errcode = 'check_violation';
  end if;

  if not app.check_import_export_job_authority(v_job.tenant_id, p_actor_auth_user_id) then
    raise exception 'job_actor_unauthorized: identity % lacks active membership in tenant %', p_actor_auth_user_id, v_job.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_job.tenant_id, 'HRS', 'Import');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Import (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_job.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- app.propose_employee_position_assignment itself demands HRS:Edit of ITS caller for every
  -- ordinary, single-proposal call -- a bulk crosswalk import is not exempt from that rule just
  -- because it arrives as a file. Checked here, before the loop, so a batch missing only this
  -- authority fails fast with one clear reason instead of failing row-by-row mid-commit.
  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_job.tenant_id, 'HRS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_job.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-278 shape, adopted at birth: reuses the SAME HRS:Import pair already checked above,
  -- never HRS:Edit -- a strict no-op unless this tenant has itself opted (HRS, Import) into its
  -- own additional_high_risk_actions AND turned MFA on.
  perform app.assert_current_step_up_authorization(v_job.tenant_id, p_actor_auth_user_id, 'HRS', 'Import');

  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(v_job.tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(v_job.tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;

  if v_job.status <> 'in_progress' then
    raise exception 'import_export_job_not_committable: job % is %, only an in_progress job may be committed', p_job_id, v_job.status
      using errcode = 'check_violation';
  end if;

  select count(*) into v_pending_count from app.import_staging_rows where job_id = p_job_id and validation_status = 'pending';
  if v_pending_count > 0 then
    raise exception 'import_export_job_not_fully_validated: job % still has % row(s) pending validation', p_job_id, v_pending_count
      using errcode = 'check_violation';
  end if;

  if v_job.invalid_row_count > 0 and not coalesce(p_allow_partial, false) then
    raise exception 'import_export_job_has_invalid_rows: job % has % invalid row(s); pass p_allow_partial to accept a partial commit', p_job_id, v_job.invalid_row_count
      using errcode = 'check_violation';
  end if;

  select config_version_id into v_config_version_id from app.resolve_import_export_schema_columns(v_job.tenant_id, 'position_crosswalk_import');

  -- Job-scoped advisory lock, mirrors every other commit_*_import_job adapter (HRT-275''s own
  -- checkpoint number as the salt, matching app.commit_employee_import_job''s use of 274 for
  -- HRT-274).
  perform pg_advisory_xact_lock(hashtextextended(p_job_id::text, 275));

  for v_row in
    select * from app.import_staging_rows
    where job_id = p_job_id and validation_status = 'valid'
    order by row_number
  loop
    v_payload := v_row.raw_payload;

    if exists (select 1 from app.employee_position_assignments where tenant_id = v_job.tenant_id and source_import_staging_row_id = v_row.id) then
      v_skipped_count := v_skipped_count + 1;
      continue;
    end if;

    select e.master_record_id, e.record_version, e.lifecycle_status into v_employee_id, v_employee_version, v_employee_status
    from app.employees e
    join app.master_records m on m.id = e.master_record_id
    where e.tenant_id = v_job.tenant_id and m.code = trim(v_payload ->> 'employee_number');

    if v_employee_id is null or v_employee_status in ('terminated', 'archived') then
      raise exception 'import_row_no_longer_resolvable: staging row % no longer resolves to a non-terminated/archived employee of this tenant', v_row.id
        using errcode = 'check_violation';
    end if;

    select id into v_position_id from app.positions where tenant_id = v_job.tenant_id and code = trim(v_payload ->> 'position_code') and status = 'active';
    if v_position_id is null then
      raise exception 'import_row_no_longer_resolvable: staging row % no longer resolves to an active position of this tenant', v_row.id
        using errcode = 'check_violation';
    end if;

    v_grade_id := null;
    if coalesce(v_payload ->> 'grade_code', '') <> '' then
      select id into v_grade_id from app.position_grades where tenant_id = v_job.tenant_id and code = trim(v_payload ->> 'grade_code') and status = 'active';
      if v_grade_id is null then
        raise exception 'import_row_no_longer_resolvable: staging row % no longer resolves to an active grade of this tenant', v_row.id
          using errcode = 'check_violation';
      end if;
    end if;

    v_manager_id := null;
    if coalesce(v_payload ->> 'manager_employee_number', '') <> '' then
      select e.master_record_id into v_manager_id
      from app.employees e
      join app.master_records m on m.id = e.master_record_id
      where e.tenant_id = v_job.tenant_id and m.code = trim(v_payload ->> 'manager_employee_number');
      if v_manager_id is null then
        raise exception 'import_row_no_longer_resolvable: staging row % no longer resolves a manager_employee_number to an employee of this tenant', v_row.id
          using errcode = 'check_violation';
      end if;
    end if;

    v_assignment_type := coalesce(nullif(trim(v_payload ->> 'assignment_type'), ''), 'primary');
    v_change_reason := coalesce(nullif(trim(v_payload ->> 'change_reason'), ''), 'correction');
    v_start_date := coalesce(nullif(trim(v_payload ->> 'effective_start_date'), '')::date, current_date);
    v_end_date := nullif(trim(v_payload ->> 'effective_end_date'), '')::date;
    v_allocation := coalesce(nullif(trim(v_payload ->> 'allocation_pct'), '')::numeric, 100.00);
    v_reason_note := coalesce(nullif(trim(v_payload ->> 'reason_note'), ''), 'Bulk position/grade crosswalk import (staging row ' || v_row.id::text || ')');

    v_proposed := app.propose_employee_position_assignment(
      v_employee_id, v_employee_version, v_position_id, v_grade_id, v_manager_id,
      v_assignment_type, v_allocation, v_start_date, v_end_date,
      v_change_reason, v_reason_note, p_actor_auth_user_id, p_actor_label
    );

    update app.employee_position_assignments
    set source_import_staging_row_id = v_row.id, source_config_version_id = coalesce(source_config_version_id, v_config_version_id)
    where id = v_proposed.id;

    v_created_count := v_created_count + 1;
  end loop;

  update app.jobs
  set status = 'completed',
      processed_rows = v_created_count + v_skipped_count,
      completed_at = now(),
      payload = payload || jsonb_build_object('created_count', v_created_count, 'skipped_count', v_skipped_count)
  where job_id = p_job_id
  returning * into v_updated;

  perform app.capture_audit_event(
    v_job.tenant_id, p_actor_auth_user_id, p_actor_label, 'commit_position_crosswalk_import_job',
    'app.jobs', p_job_id, 'success', null, null,
    jsonb_build_object('created_count', v_created_count, 'skipped_count', v_skipped_count, 'allow_partial', coalesce(p_allow_partial, false))
  );

  return v_updated;
end;
$$;

-- app.commit_wms_receipt_line -- live definition from 20260730570000_wire_lot_serial_identity_registration_into_receiving.sql
create or replace function app.commit_wms_receipt_line(p_line_id uuid, p_idempotency_key text, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.wms_receipt_lines
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_decision app.rbac_decision;
  v_line app.wms_receipt_lines;
  v_session app.wms_receipt_sessions;
  v_warehouse app.warehouses;
  v_lines jsonb := '[]'::jsonb;
  v_movement app.inventory_movements;
begin
  -- Row-locked from this first read through commit/rollback (FOR UPDATE) so a second
  -- concurrent call on the same line -- e.g. a client retry that regenerates a fresh
  -- idempotency key after a slow/timed-out first response -- cannot read the
  -- pre-commit status, build its own movement lines, and call
  -- app.post_inventory_movement a second time before the first call's UPDATE has
  -- landed. The second caller instead blocks here until the first transaction
  -- commits, then observes status='committed' and takes the idempotent short-circuit
  -- below -- never a second real ledger movement for the same physical receipt.
  select * into v_line from app.wms_receipt_lines where id = p_line_id for update;
  if not found or not app.has_active_tenant_membership(v_line.tenant_id, p_actor_auth_user_id) then
    raise exception 'line_not_found: %', p_line_id using errcode = 'no_data_found';
  end if;
  select * into v_session from app.wms_receipt_sessions where id = v_line.receipt_session_id;
  select * into v_warehouse from app.warehouses where id = v_session.warehouse_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_line.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_line.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_line.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot commit receipt line %', p_actor_auth_user_id, p_line_id using errcode = 'insufficient_privilege';
  end if;

  -- Idempotent replay short-circuit -- only after authority/tenant-scope is
  -- confirmed above, never before (an already-committed record must never be
  -- readable by a caller who could not otherwise access it).
  if v_line.status = 'committed' then
    return v_line;
  end if;

  if v_session.status <> 'in_progress' then
    raise exception 'session_not_in_progress: session % is % -- lines may only be committed while in_progress', v_session.id, v_session.status using errcode = 'check_violation';
  end if;
  if v_line.status <> 'counted' then
    raise exception 'line_not_counted: % must have a recorded count before it can be committed', p_line_id using errcode = 'check_violation';
  end if;
  if v_line.record_version <> p_expected_version then
    raise exception 'stale_version: receipt line % expected version % but found %', p_line_id, p_expected_version, v_line.record_version using errcode = 'check_violation';
  end if;
  if v_line.over_quantity > 0 and not v_line.over_approved then
    raise exception 'unapproved_overage: receipt line % counted % over the expected % without supervisor approval', p_line_id, v_line.over_quantity, v_line.expected_quantity using errcode = 'check_violation';
  end if;
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'invalid_idempotency_key: an idempotency key is required to commit a receipt line' using errcode = 'check_violation';
  end if;

  if v_line.accepted_quantity > 0 then
    v_lines := v_lines || jsonb_build_array(jsonb_build_object(
      'owner_account_id', v_line.owner_account_id, 'item_master_id', v_line.item_master_id, 'location_id', v_session.receiving_location_id,
      'uom_code', v_line.expected_uom_code, 'signed_quantity', v_line.accepted_quantity,
      'lot_number', v_line.lot_number, 'serial_number', v_line.serial_number, 'expiry_date', v_line.expiry_date, 'status', 'on_hand'
    ));
  end if;
  if v_line.damaged_quantity > 0 then
    v_lines := v_lines || jsonb_build_array(jsonb_build_object(
      'owner_account_id', v_line.owner_account_id, 'item_master_id', v_line.item_master_id, 'location_id', v_session.receiving_location_id,
      'uom_code', v_line.expected_uom_code, 'signed_quantity', v_line.damaged_quantity,
      'lot_number', v_line.lot_number, 'serial_number', v_line.serial_number, 'expiry_date', v_line.expiry_date, 'status', 'damaged'
    ));
  end if;
  if v_line.held_quantity > 0 then
    v_lines := v_lines || jsonb_build_array(jsonb_build_object(
      'owner_account_id', v_line.owner_account_id, 'item_master_id', v_line.item_master_id, 'location_id', v_session.receiving_location_id,
      'uom_code', v_line.expected_uom_code, 'signed_quantity', v_line.held_quantity,
      'lot_number', v_line.lot_number, 'serial_number', v_line.serial_number, 'expiry_date', v_line.expiry_date, 'status', 'held'
    ));
  end if;

  if jsonb_array_length(v_lines) > 0 then
    v_movement := app.post_inventory_movement(
      v_line.tenant_id, v_session.warehouse_id, 'receipt', 'wms_inbound_order', v_session.inbound_order_id, p_idempotency_key, v_line.condition_notes,
      v_lines, p_actor_auth_user_id, p_actor_label
    );
  end if;

  -- ATW-032 (closes ISS-2026-016). app.register_lot_identity / app.register_serial_identity
  -- (ATW-016) were real, tested, independently-callable RPCs that NOTHING in the system ever
  -- called. Receiving stored lot and serial as plain, ungoverned text exactly as it had before
  -- they existed, so app.list_allocation_candidates' hold/expiry/duplicate-serial exclusion --
  -- Prompt 235 §33's "expired/held or duplicate-serial stock cannot be allocated silently" --
  -- was correct code with nothing registered for it to exclude. This is the wiring.
  --
  -- Everything it needs is already on the row: app.wms_receipt_lines carries lot_number,
  -- serial_number, expiry_date AND the lot_controlled/serial_controlled/expiry_controlled
  -- flags. No signature changes, no new column, no new authority. The registry RPCs gate on
  -- OPS:Create, which cannot lock anyone out here because app.start_wms_receipt_session
  -- already requires OPS:Create -- a line cannot reach commit without its session having been
  -- started under that same permission.
  --
  -- Registration runs AFTER the movement, deliberately. Placing it before would put
  -- register_serial_identity's duplicate_serial ahead of app.post_inventory_movement's own
  -- serial_conflict guard, changing the error a caller already handles for the same wrong
  -- thing -- and it buys nothing, because both are in one transaction so nothing outside can
  -- observe a balance before its identity either way. After the movement, the ledger's own
  -- guard stays the first line of defence and only lines that genuinely posted are recorded.
  --
  -- Both RPCs return the existing row when the identity is already registered, so a
  -- multi-line receipt of one lot registers once and every later line is a no-op.
  if v_line.lot_controlled and v_line.lot_number is not null and length(trim(v_line.lot_number)) > 0 then
    perform app.register_lot_identity(
      v_line.item_master_id, v_line.lot_number, null,
      -- expiry_date only when the item is expiry-controlled: register_lot_identity rejects an
      -- expiry on an item that is not, and receiving may legitimately hold neither.
      case when v_line.expiry_controlled then v_line.expiry_date else null end,
      'receipt', v_line.id, null, p_actor_auth_user_id, p_actor_label
    );
  end if;

  if v_line.serial_controlled and v_line.serial_number is not null and length(trim(v_line.serial_number)) > 0 then
    perform app.register_serial_identity(
      v_line.item_master_id, v_line.serial_number,
      case when v_line.lot_controlled then v_line.lot_number else null end,
      null,
      case when v_line.expiry_controlled then v_line.expiry_date else null end,
      'receipt', v_line.id,
      -- The receipt line is the natural idempotency target: one committed line registers one
      -- serial, and a replay of that commit must not be a second registration.
      'wms-receipt-line-' || v_line.id::text,
      p_actor_auth_user_id, p_actor_label
    );
  end if;

  update app.wms_receipt_lines set status = 'committed', movement_id = v_movement.id
  where id = p_line_id
  returning * into v_line;

  perform app.capture_audit_event(
    v_line.tenant_id, p_actor_auth_user_id, p_actor_label, 'commit_wms_receipt_line',
    'app.wms_receipt_lines', v_line.id, 'success', null, null,
    jsonb_build_object('movement_id', v_movement.id, 'accepted_quantity', v_line.accepted_quantity, 'damaged_quantity', v_line.damaged_quantity, 'held_quantity', v_line.held_quantity)
  );

  return v_line;
end;
$function$;

-- app.confirm_vendor_capacity_reservation_manually -- live definition from 20260831150000_add_vendor_capacity_manual_confirmation_evidence.sql
create or replace function app.confirm_vendor_capacity_reservation_manually(
  p_reservation_id uuid,
  p_expected_version integer,
  p_evidence_file_id uuid,
  p_confirmation_note text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_capacity_reservations
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_reservation app.vendor_capacity_reservations;
  v_file app.files;
begin
  select * into v_reservation from app.vendor_capacity_reservations where id = p_reservation_id;
  if not found or not app.has_active_tenant_membership(v_reservation.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_capacity_reservation_not_found: %', p_reservation_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_reservation.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_reservation.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_reservation.record_version <> p_expected_version then
    raise exception 'stale_version: vendor capacity reservation % expected version % but found %', p_reservation_id, p_expected_version, v_reservation.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_reservation.status <> 'held' then
    raise exception 'invalid_transition: vendor capacity reservation % is % and cannot be confirmed', p_reservation_id, v_reservation.status
      using errcode = 'check_violation';
  end if;

  if p_evidence_file_id is null then
    raise exception 'confirmation_evidence_required: a manual confirmation must attach the evidence it rests on'
      using errcode = 'check_violation';
  end if;
  if p_confirmation_note is null or length(trim(p_confirmation_note)) = 0 then
    raise exception 'confirmation_note_required: a manual confirmation must state what was agreed and with whom'
      using errcode = 'check_violation';
  end if;

  -- Re-validate tenant, record scope and scan status at THIS accepting RPC (taxonomy C-10) --
  -- never trust a caller's prior upload success as still valid. Byte-for-byte the shape
  -- app.complete_onboarding_task already established for evidence files.
  select * into v_file from app.files where id = p_evidence_file_id;
  if not found
     or v_file.tenant_id <> v_reservation.tenant_id
     or v_file.record_type <> 'vendor_capacity_reservation'
     or v_file.record_id <> p_reservation_id
  then
    raise exception 'evidence_file_not_found: file % is not a valid evidence file for reservation %', p_evidence_file_id, p_reservation_id
      using errcode = 'no_data_found';
  end if;
  if v_file.malware_scan_status = 'infected' then
    raise exception 'evidence_file_infected: file % failed malware scanning and cannot be attached', p_evidence_file_id
      using errcode = 'check_violation';
  end if;
  if v_file.malware_scan_status <> 'clean' then
    raise exception 'evidence_file_not_scanned: file % has not cleared malware scanning (status %)', p_evidence_file_id, v_file.malware_scan_status
      using errcode = 'check_violation';
  end if;

  update app.vendor_capacity_reservations
  set status = 'accepted',
      confirmation_method = 'manual_with_evidence',
      confirmation_evidence_file_id = p_evidence_file_id,
      confirmation_note = trim(p_confirmation_note),
      confirmed_by_auth_user_id = p_actor_auth_user_id,
      confirmed_at = now()
  where id = p_reservation_id and record_version = p_expected_version
  returning * into v_reservation;
  if not found then
    raise exception 'stale_version: vendor capacity reservation % target row was concurrently modified (expected version %)', p_reservation_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_reservation.tenant_id, p_actor_auth_user_id, p_actor_label, 'confirm_vendor_capacity_reservation_manually',
    'app.vendor_capacity_reservations', v_reservation.id, 'success', null, null,
    jsonb_build_object('confirmation_method', 'manual_with_evidence', 'evidence_file_id', p_evidence_file_id)
  );

  return v_reservation;
end;
$$;

-- app.dismiss_ai_quotation_suggestion -- live definition from 20260805080000_create_intelligence_ai_assisted_quotation.sql
create or replace function app.dismiss_ai_quotation_suggestion(
  p_suggestion_id uuid,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.ai_quotation_suggestions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_suggestion app.ai_quotation_suggestions;
  v_row app.ai_quotation_suggestions;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_suggestion from app.ai_quotation_suggestions where id = p_suggestion_id;
  if not found or not app.has_active_tenant_membership(v_suggestion.tenant_id, p_actor_auth_user_id) then
    raise exception 'ai_quotation_suggestion_not_found: %', p_suggestion_id using errcode = 'no_data_found';
  end if;

  if not app.check_ai_quotation_suggestion_authority('Edit', v_suggestion.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks COM:Edit for tenant %', p_actor_auth_user_id, v_suggestion.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- Atomic pending-only transition (Tier C fix 12's own lesson applied
  -- proactively): the WHERE clause itself is the concurrency guard, not a
  -- separate SELECT-then-check.
  update app.ai_quotation_suggestions
  set status = 'dismissed', dismiss_reason = p_reason, reviewed_by_auth_user_id = p_actor_auth_user_id, reviewed_by = p_actor_label, reviewed_at = now()
  where id = p_suggestion_id and status = 'pending'
  returning * into v_row;

  if v_row.id is null then
    raise exception 'ai_quotation_suggestion_not_pending: suggestion % is % not pending', p_suggestion_id, v_suggestion.status using errcode = 'check_violation';
  end if;

  perform app.capture_audit_event(
    v_suggestion.tenant_id, p_actor_auth_user_id, p_actor_label, 'dismiss_ai_quotation_suggestion',
    'app.ai_quotation_suggestions', v_row.id, 'success', null, to_jsonb(v_suggestion), to_jsonb(v_row)
  );

  return v_row;
end;
$$;

-- app.log_activity -- live definition from 20260723150000_create_commercial_contact_activity_management.sql
create or replace function app.log_activity(
  p_related_type text,
  p_related_id uuid,
  p_contact_id uuid,
  p_type text,
  p_subject text,
  p_notes text,
  p_status text,
  p_due_at timestamptz,
  p_completed_at timestamptz,
  p_outcome text,
  p_owner_user_id uuid,
  p_org_unit_id uuid,
  p_actor_auth_user_id uuid,
  p_created_by text
)
returns app.activities
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_ref record;
  v_activity app.activities;
  v_decision app.rbac_decision;
begin
  select * into v_ref from app.resolve_commercial_record_ref(p_related_type, p_related_id);
  if v_ref.tenant_id is null or not app.has_active_tenant_membership(v_ref.tenant_id, p_actor_auth_user_id) then
    raise exception 'related_record_not_found: % %', p_related_type, p_related_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_ref.tenant_id, 'COM', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_ref.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_ref.tenant_id, v_ref.owner_user_id, app.lead_record_scope_org_unit_ids(v_ref.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access the linked record', p_actor_auth_user_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_contact_id is not null and not exists (select 1 from app.contacts where id = p_contact_id and tenant_id = v_ref.tenant_id) then
    raise exception 'contact_not_found: % (or belongs to a different tenant)', p_contact_id using errcode = 'no_data_found';
  end if;

  insert into app.activities (
    tenant_id, type, subject, notes, status, due_at, completed_at, outcome,
    related_type, related_id, contact_id, owner_user_id, org_unit_id, created_by
  ) values (
    v_ref.tenant_id, p_type, p_subject, p_notes, coalesce(p_status, 'scheduled'), p_due_at, p_completed_at, p_outcome,
    p_related_type, p_related_id, p_contact_id, coalesce(p_owner_user_id, v_ref.owner_user_id), coalesce(p_org_unit_id, v_ref.org_unit_id), p_created_by
  )
  returning * into v_activity;

  perform app.capture_audit_event(
    v_activity.tenant_id, p_actor_auth_user_id, p_created_by, 'log_activity',
    'app.activities', v_activity.id, 'success', null, null, to_jsonb(v_activity)
  );

  return v_activity;
end;
$$;

-- app.record_ai_governed_request_outcome -- live definition from 20260827000000_wire_observability_alert_producers.sql
create or replace function app.record_ai_governed_request_outcome(
  p_request_id uuid,
  p_status text,
  p_output_payload jsonb,
  p_confidence_label text,
  p_model_version text,
  p_provider_unit_cost_amount numeric,
  p_currency text,
  p_error_message text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.ai_governed_requests
language plpgsql
as $$
declare
  v_request app.ai_governed_requests;
  v_billed_amount numeric;
  v_row app.ai_governed_requests;
  v_current_status text;
begin
  select * into v_request from app.ai_governed_requests where id = p_request_id;
  if not found or not app.has_active_tenant_membership(v_request.tenant_id, p_actor_auth_user_id) then
    raise exception 'ai_governed_request_not_found: %', p_request_id using errcode = 'no_data_found';
  end if;

  if not app.check_ai_governance_authority('Create', v_request.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks AI:Create for tenant %', p_actor_auth_user_id, v_request.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_status not in ('succeeded', 'failed') then
    raise exception 'ai_governed_request_invalid_status: % is not one of succeeded/failed', p_status using errcode = 'check_violation';
  end if;
  if p_provider_unit_cost_amount is not null and (
    p_provider_unit_cost_amount < 0
    or p_provider_unit_cost_amount >= 'infinity'::numeric
  ) then
    raise exception 'ai_governed_request_invalid_cost_amount: provider_unit_cost_amount must be a real, non-negative, finite number' using errcode = 'check_violation';
  end if;

  v_billed_amount := app.compute_provider_billed_amount(p_provider_unit_cost_amount);

  update app.ai_governed_requests
  set status = p_status, output_payload = app.redact_ai_output_payload_secret_shaped_values(p_output_payload), confidence_label = p_confidence_label, model_version = p_model_version,
      provider_unit_cost_amount = p_provider_unit_cost_amount, currency = p_currency, billed_amount = v_billed_amount,
      error_message = p_error_message, completed_at = now()
  where id = p_request_id and status = 'pending'
  returning * into v_row;

  if v_row.id is null then
    select status into v_current_status from app.ai_governed_requests where id = p_request_id;
    raise exception 'ai_governed_request_not_pending: request % is % not pending', p_request_id, v_current_status using errcode = 'check_violation';
  end if;

  -- ISS-2026-249: a genuinely-recorded failure (never a race loser -- those
  -- raised above already) alerts. Severity medium: a single failed AI call
  -- is not structurally terminal the way a dead-lettered webhook delivery or
  -- an auto-disabled integration connection is.
  if p_status = 'failed' then
    perform app.raise_observability_alert(
      v_request.tenant_id, 'ai', 'error',
      format('AI governed action failed: %s', v_request.feature_code),
      'medium', p_error_message
    );
  end if;

  perform app.capture_audit_event(
    v_request.tenant_id, p_actor_auth_user_id, p_actor_label, 'record_ai_governed_request_outcome',
    'app.ai_governed_requests', v_row.id, case when p_status = 'succeeded' then 'success' else 'failure' end, p_error_message, null,
    jsonb_build_object('status', v_row.status, 'confidence_label', v_row.confidence_label)
  );

  return v_row;
end;
$$;

-- app.record_eta_prediction_outcome -- live definition from 20260806100000_create_intelligence_predictive_eta.sql
create or replace function app.record_eta_prediction_outcome(
  p_prediction_id uuid,
  p_ai_governed_request_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.eta_predictions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_prediction app.eta_predictions;
  v_request app.ai_governed_requests;
  v_predicted_eta timestamptz;
  v_earliest timestamptz;
  v_latest timestamptz;
  v_row app.eta_predictions;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_prediction from app.eta_predictions where id = p_prediction_id;
  if not found or not app.has_active_tenant_membership(v_prediction.tenant_id, p_actor_auth_user_id) then
    raise exception 'eta_prediction_not_found: %', p_prediction_id using errcode = 'no_data_found';
  end if;

  if not app.check_eta_prediction_authority('Create', v_prediction.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks AI:Create for tenant %', p_actor_auth_user_id, v_prediction.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_prediction.ai_governed_request_id is not null then
    if v_prediction.ai_governed_request_id = p_ai_governed_request_id then
      return v_prediction;
    end if;
    raise exception 'eta_prediction_outcome_already_recorded: prediction % is already linked to a different governed request', p_prediction_id
      using errcode = 'check_violation';
  end if;

  if v_prediction.status <> 'pending' then
    raise exception 'eta_prediction_not_pending: prediction % is % not pending', p_prediction_id, v_prediction.status using errcode = 'check_violation';
  end if;

  select * into v_request from app.ai_governed_requests where id = p_ai_governed_request_id;
  if not found then
    raise exception 'ai_governed_request_not_found: %', p_ai_governed_request_id using errcode = 'no_data_found';
  end if;

  if v_request.tenant_id <> v_prediction.tenant_id then
    raise exception 'eta_prediction_request_tenant_mismatch: governed request % does not belong to tenant %', p_ai_governed_request_id, v_prediction.tenant_id
      using errcode = 'check_violation';
  end if;
  if v_request.feature_code <> 'predictive_eta' then
    raise exception 'eta_prediction_wrong_feature: governed request % has feature_code % not predictive_eta', p_ai_governed_request_id, v_request.feature_code
      using errcode = 'check_violation';
  end if;
  if v_request.correlation_record_type is distinct from 'shipment_order' or v_request.correlation_record_id is distinct from v_prediction.shipment_order_id then
    raise exception 'eta_prediction_correlation_mismatch: governed request % does not correlate to prediction %''s own shipment %', p_ai_governed_request_id, p_prediction_id, v_prediction.shipment_order_id
      using errcode = 'check_violation';
  end if;
  if v_request.status not in ('succeeded', 'failed') then
    raise exception 'eta_prediction_request_not_completed: governed request % is % not succeeded/failed', p_ai_governed_request_id, v_request.status
      using errcode = 'check_violation';
  end if;

  if v_request.status = 'succeeded' then
    v_predicted_eta := app._parse_eta_timestamp(v_request.output_payload -> 'predictedEta');
    v_earliest := app._parse_eta_timestamp(v_request.output_payload -> 'predictedEtaEarliest');
    v_latest := app._parse_eta_timestamp(v_request.output_payload -> 'predictedEtaLatest');
    if v_earliest is not null and v_latest is not null and v_earliest > v_latest then
      v_earliest := null;
      v_latest := null;
    end if;
  end if;

  -- Tier C fix (Group 6 review): the WHERE clause itself is the concurrency
  -- guard against a lost-update race between two concurrent callers each
  -- holding a DIFFERENT real, succeeded governed request for the SAME
  -- still-pending prediction -- live-reproduced before this fix: both
  -- callers returned a false "success" and the loser's own outcome was
  -- silently overwritten with no error. A losing caller now re-selects the
  -- winner's own row and either returns it (if it happens to be its own
  -- request id) or raises the same already-recorded/not-pending errors the
  -- sequential case already uses.
  update app.eta_predictions
  set ai_governed_request_id = p_ai_governed_request_id,
      status = case when v_request.status = 'succeeded' then 'succeeded' else 'failed' end,
      predicted_eta = v_predicted_eta, predicted_eta_earliest = v_earliest, predicted_eta_latest = v_latest,
      completed_at = now()
  where id = p_prediction_id and status = 'pending'
  returning * into v_row;

  if not found then
    select * into v_row from app.eta_predictions where id = p_prediction_id;
    if v_row.ai_governed_request_id = p_ai_governed_request_id then
      return v_row;
    end if;
    raise exception 'eta_prediction_outcome_already_recorded: prediction % is already linked to a different governed request', p_prediction_id
      using errcode = 'check_violation';
  end if;

  perform app.capture_audit_event(
    v_prediction.tenant_id, p_actor_auth_user_id, p_actor_label, 'record_eta_prediction_outcome',
    'app.eta_predictions', v_row.id, case when v_request.status = 'succeeded' then 'success' else 'failure' end, null, null,
    jsonb_build_object('status', v_row.status, 'has_predicted_eta', v_row.predicted_eta is not null)
  );

  return v_row;
end;
$$;

-- app.record_forecast_job_outcome -- live definition from 20260806400000_create_intelligence_forecasting_recommendation.sql
create or replace function app.record_forecast_job_outcome(
  p_job_id uuid,
  p_ai_governed_request_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.forecast_jobs
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_job app.forecast_jobs;
  v_request app.ai_governed_requests;
  v_insufficient_data boolean;
  v_predicted_value numeric;
  v_cohort_size integer;
  v_data_quality_note text;
  v_status text;
  v_row app.forecast_jobs;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_job from app.forecast_jobs where id = p_job_id;
  if not found or not app.has_active_tenant_membership(v_job.tenant_id, p_actor_auth_user_id) then
    raise exception 'forecast_job_not_found: %', p_job_id using errcode = 'no_data_found';
  end if;

  if not app.check_forecast_authority('Create', v_job.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks AI:Create for tenant %', p_actor_auth_user_id, v_job.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_job.ai_governed_request_id is not null then
    if v_job.ai_governed_request_id = p_ai_governed_request_id then
      return v_job;
    end if;
    raise exception 'forecast_job_outcome_already_recorded: job % is already linked to a different governed request', p_job_id
      using errcode = 'check_violation';
  end if;

  if v_job.status <> 'pending' then
    raise exception 'forecast_job_not_pending: job % is % not pending', p_job_id, v_job.status using errcode = 'check_violation';
  end if;

  select * into v_request from app.ai_governed_requests where id = p_ai_governed_request_id;
  if not found then
    raise exception 'ai_governed_request_not_found: %', p_ai_governed_request_id using errcode = 'no_data_found';
  end if;

  if v_request.tenant_id <> v_job.tenant_id then
    raise exception 'forecast_job_request_tenant_mismatch: governed request % does not belong to tenant %', p_ai_governed_request_id, v_job.tenant_id
      using errcode = 'check_violation';
  end if;
  if v_request.feature_code <> 'forecasting_recommendation' then
    raise exception 'forecast_job_wrong_feature: governed request % has feature_code % not forecasting_recommendation', p_ai_governed_request_id, v_request.feature_code
      using errcode = 'check_violation';
  end if;
  if v_request.correlation_record_type is distinct from 'forecast_job' or v_request.correlation_record_id is distinct from v_job.id then
    raise exception 'forecast_job_correlation_mismatch: governed request % does not correlate to job %', p_ai_governed_request_id, p_job_id
      using errcode = 'check_violation';
  end if;
  if v_request.status not in ('succeeded', 'failed') then
    raise exception 'forecast_job_request_not_completed: governed request % is % not succeeded/failed', p_ai_governed_request_id, v_request.status
      using errcode = 'check_violation';
  end if;

  if v_request.status = 'succeeded' then
    v_insufficient_data := app._parse_forecast_bool(v_request.output_payload -> 'insufficientData');
    if v_insufficient_data then
      v_status := 'insufficient_data';
      v_data_quality_note := app._parse_forecast_text(v_request.output_payload -> 'dataQualityNote');
    else
      v_status := 'succeeded';
      v_predicted_value := app._parse_forecast_numeric(v_request.output_payload -> 'predictedValue');
      v_cohort_size := app._parse_forecast_int(v_request.output_payload -> 'cohortSize');
    end if;
  else
    v_status := 'failed';
  end if;

  -- Tier C fix (Group 6 review): the WHERE clause itself is the concurrency
  -- guard against a lost-update race between two concurrent callers each
  -- holding a DIFFERENT real, succeeded governed request for the SAME
  -- still-pending job -- live-reproduced on the sibling IAE-022 function
  -- before this fix, applied proactively here.
  update app.forecast_jobs
  set ai_governed_request_id = p_ai_governed_request_id,
      status = v_status,
      predicted_value = v_predicted_value,
      cohort_size = v_cohort_size,
      is_small_cohort_suppressed = (v_cohort_size is not null and v_cohort_size < 10),
      data_quality_note = v_data_quality_note,
      completed_at = now()
  where id = p_job_id and status = 'pending'
  returning * into v_row;

  if not found then
    select * into v_row from app.forecast_jobs where id = p_job_id;
    if v_row.ai_governed_request_id = p_ai_governed_request_id then
      return v_row;
    end if;
    raise exception 'forecast_job_outcome_already_recorded: job % is already linked to a different governed request', p_job_id
      using errcode = 'check_violation';
  end if;

  perform app.capture_audit_event(
    v_job.tenant_id, p_actor_auth_user_id, p_actor_label, 'record_forecast_job_outcome',
    'app.forecast_jobs', v_row.id, case when v_request.status = 'succeeded' then 'success' else 'failure' end, null, null,
    jsonb_build_object('status', v_row.status, 'is_small_cohort_suppressed', v_row.is_small_cohort_suppressed)
  );

  return v_row;
end;
$$;

-- app.record_ocr_document_job_outcome -- live definition from 20260806000000_create_intelligence_ocr_document_processing.sql
create or replace function app.record_ocr_document_job_outcome(
  p_job_id uuid,
  p_ai_governed_request_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.ocr_document_jobs
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_job app.ocr_document_jobs;
  v_request app.ai_governed_requests;
  v_row app.ocr_document_jobs;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_job from app.ocr_document_jobs where id = p_job_id;
  if not found or not app.has_active_tenant_membership(v_job.tenant_id, p_actor_auth_user_id) then
    raise exception 'ocr_document_job_not_found: %', p_job_id using errcode = 'no_data_found';
  end if;

  if not app.check_ocr_document_authority('Create', v_job.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks AI:Create for tenant %', p_actor_auth_user_id, v_job.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- Idempotent replay: a job already synced to this exact governed request returns as-is.
  if v_job.ai_governed_request_id is not null then
    if v_job.ai_governed_request_id = p_ai_governed_request_id then
      return v_job;
    end if;
    raise exception 'ocr_document_job_outcome_already_recorded: job % is already linked to a different governed request', p_job_id
      using errcode = 'check_violation';
  end if;

  if v_job.status <> 'pending' then
    raise exception 'ocr_document_job_not_pending: job % is % not pending', p_job_id, v_job.status using errcode = 'check_violation';
  end if;

  select * into v_request from app.ai_governed_requests where id = p_ai_governed_request_id;
  if not found then
    raise exception 'ai_governed_request_not_found: %', p_ai_governed_request_id using errcode = 'no_data_found';
  end if;

  if v_request.tenant_id <> v_job.tenant_id then
    raise exception 'ocr_document_job_request_tenant_mismatch: governed request % does not belong to tenant %', p_ai_governed_request_id, v_job.tenant_id
      using errcode = 'check_violation';
  end if;
  if v_request.feature_code <> 'ocr_document_extraction' then
    raise exception 'ocr_document_job_wrong_feature: governed request % has feature_code % not ocr_document_extraction', p_ai_governed_request_id, v_request.feature_code
      using errcode = 'check_violation';
  end if;
  if v_request.correlation_record_type is distinct from 'file' or v_request.correlation_record_id is distinct from v_job.file_id then
    raise exception 'ocr_document_job_correlation_mismatch: governed request % does not correlate to job %''s own file %', p_ai_governed_request_id, p_job_id, v_job.file_id
      using errcode = 'check_violation';
  end if;
  if v_request.status not in ('succeeded', 'failed') then
    raise exception 'ocr_document_job_request_not_completed: governed request % is % not succeeded/failed', p_ai_governed_request_id, v_request.status
      using errcode = 'check_violation';
  end if;

  -- Tier C fix (Group 6 review): the WHERE clause itself is the concurrency
  -- guard against a lost-update race between two concurrent callers each
  -- holding a DIFFERENT real, succeeded governed request for the SAME
  -- still-pending job -- live-reproduced on the sibling IAE-022 function
  -- before this fix (both callers returned a false "success", the loser's
  -- own outcome silently overwritten with no error), applied proactively
  -- here.
  update app.ocr_document_jobs
  set ai_governed_request_id = p_ai_governed_request_id,
      status = case when v_request.status = 'succeeded' then 'extracted' else 'failed' end
  where id = p_job_id and status = 'pending'
  returning * into v_row;

  if not found then
    select * into v_row from app.ocr_document_jobs where id = p_job_id;
    if v_row.ai_governed_request_id = p_ai_governed_request_id then
      return v_row;
    end if;
    raise exception 'ocr_document_job_outcome_already_recorded: job % is already linked to a different governed request', p_job_id
      using errcode = 'check_violation';
  end if;

  perform app.capture_audit_event(
    v_job.tenant_id, p_actor_auth_user_id, p_actor_label, 'record_ocr_document_job_outcome',
    'app.ocr_document_jobs', v_row.id, case when v_request.status = 'succeeded' then 'success' else 'failure' end, null, null,
    jsonb_build_object('status', v_row.status, 'ai_governed_request_id', v_row.ai_governed_request_id)
  );

  return v_row;
end;
$$;

-- app.record_optimization_scenario_outcome -- live definition from 20260806200000_create_intelligence_optimization_assistance.sql
create or replace function app.record_optimization_scenario_outcome(
  p_scenario_id uuid,
  p_ai_governed_request_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.optimization_scenarios
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_scenario app.optimization_scenarios;
  v_request app.ai_governed_requests;
  v_row app.optimization_scenarios;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_scenario from app.optimization_scenarios where id = p_scenario_id;
  if not found or not app.has_active_tenant_membership(v_scenario.tenant_id, p_actor_auth_user_id) then
    raise exception 'optimization_scenario_not_found: %', p_scenario_id using errcode = 'no_data_found';
  end if;

  if not app.check_optimization_authority('Create', v_scenario.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks AI:Create for tenant %', p_actor_auth_user_id, v_scenario.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_scenario.ai_governed_request_id is not null then
    if v_scenario.ai_governed_request_id = p_ai_governed_request_id then
      return v_scenario;
    end if;
    raise exception 'optimization_scenario_outcome_already_recorded: scenario % is already linked to a different governed request', p_scenario_id
      using errcode = 'check_violation';
  end if;

  if v_scenario.status <> 'pending' then
    raise exception 'optimization_scenario_not_pending: scenario % is % not pending', p_scenario_id, v_scenario.status using errcode = 'check_violation';
  end if;

  select * into v_request from app.ai_governed_requests where id = p_ai_governed_request_id;
  if not found then
    raise exception 'ai_governed_request_not_found: %', p_ai_governed_request_id using errcode = 'no_data_found';
  end if;

  if v_request.tenant_id <> v_scenario.tenant_id then
    raise exception 'optimization_scenario_request_tenant_mismatch: governed request % does not belong to tenant %', p_ai_governed_request_id, v_scenario.tenant_id
      using errcode = 'check_violation';
  end if;
  if v_request.feature_code <> 'optimization_assistance' then
    raise exception 'optimization_scenario_wrong_feature: governed request % has feature_code % not optimization_assistance', p_ai_governed_request_id, v_request.feature_code
      using errcode = 'check_violation';
  end if;
  if v_request.correlation_record_type is distinct from 'optimization_scenario' or v_request.correlation_record_id is distinct from v_scenario.id then
    raise exception 'optimization_scenario_correlation_mismatch: governed request % does not correlate to scenario %', p_ai_governed_request_id, p_scenario_id
      using errcode = 'check_violation';
  end if;
  if v_request.status not in ('succeeded', 'failed') then
    raise exception 'optimization_scenario_request_not_completed: governed request % is % not succeeded/failed', p_ai_governed_request_id, v_request.status
      using errcode = 'check_violation';
  end if;

  -- Tier C fix (Group 6 review): the WHERE clause itself is the concurrency
  -- guard against a lost-update race between two concurrent callers each
  -- holding a DIFFERENT real, succeeded governed request for the SAME
  -- still-pending scenario -- live-reproduced on the sibling IAE-022
  -- function before this fix, applied proactively here.
  update app.optimization_scenarios
  set ai_governed_request_id = p_ai_governed_request_id,
      status = case when v_request.status = 'succeeded' then 'succeeded' else 'failed' end,
      completed_at = now()
  where id = p_scenario_id and status = 'pending'
  returning * into v_row;

  if not found then
    select * into v_row from app.optimization_scenarios where id = p_scenario_id;
    if v_row.ai_governed_request_id = p_ai_governed_request_id then
      return v_row;
    end if;
    raise exception 'optimization_scenario_outcome_already_recorded: scenario % is already linked to a different governed request', p_scenario_id
      using errcode = 'check_violation';
  end if;

  perform app.capture_audit_event(
    v_scenario.tenant_id, p_actor_auth_user_id, p_actor_label, 'record_optimization_scenario_outcome',
    'app.optimization_scenarios', v_row.id, case when v_request.status = 'succeeded' then 'success' else 'failure' end, null, null,
    jsonb_build_object('status', v_row.status)
  );

  return v_row;
end;
$$;

-- app.record_payroll_run_calculation_failure -- live definition from 20260902010000_alert_on_payroll_run_calculation_failure_iss2026079.sql
create or replace function app.record_payroll_run_calculation_failure(
  p_run_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  p_error_detail text
)
returns app.incidents
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_run app.payroll_runs;
  v_period app.payroll_periods;
  v_incident app.incidents;
begin
  select * into v_run from app.payroll_runs where id = p_run_id;
  if not found or not app.has_active_tenant_membership(v_run.tenant_id, p_actor_auth_user_id) then
    raise exception 'payroll_run_not_found: %', p_run_id using errcode = 'no_data_found';
  end if;

  -- Same HRS:Edit gate app.calculate_payroll_run itself requires -- this is a report ABOUT a
  -- calculation attempt, so only someone entitled to make that attempt may file one, matching
  -- app.record_authority_denial's own "the recorder enforces its own authority" discipline.
  if not app.check_payroll_authority('Edit', v_run.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit for tenant %', p_actor_auth_user_id, v_run.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_period from app.payroll_periods where id = v_run.payroll_period_id;

  v_incident := app.raise_observability_alert(
    v_run.tenant_id,
    'job',
    'error',
    format('Payroll run %s (period %s) failed to complete calculation', p_run_id, coalesce(v_period.code, '(unknown)')),
    'high',
    format(
      'app.calculate_payroll_run for run %s (tenant %s, period %s, run_type %s) did not complete -- the whole attempt rolled back and left no other durable trace (ISS-2026-079: the job lifecycle runs inside one transaction, with no multi-transaction resumability). Reported by identity %s (%s) immediately after catching the failure. Error: %s. A human must inspect the underlying cause and manually re-trigger app.calculate_payroll_run for this run once resolved -- there is no automatic resumption.',
      p_run_id, v_run.tenant_id, coalesce(v_period.code, '(unknown)'), v_run.run_type,
      coalesce(p_actor_auth_user_id::text, '(unattributed)'), coalesce(p_actor_label, '(unattributed)'),
      coalesce(p_error_detail, '(no detail captured)')
    ),
    -- Dedupe per RUN, not per tenant: two different runs failing inside the same window must
    -- open two incidents, but repeated crashes on the SAME run collapse into one.
    p_run_id::text
  );

  perform app.capture_audit_event(
    v_run.tenant_id, p_actor_auth_user_id, p_actor_label, 'record_payroll_run_calculation_failure',
    'app.payroll_runs', p_run_id, 'success', null, null,
    jsonb_build_object('incident_id', v_incident.id, 'error_detail', p_error_detail)
  );

  return v_incident;
end;
$$;

-- app.record_pipeline_outcome -- live definition from 20260723180000_create_commercial_sales_pipeline.sql
create or replace function app.record_pipeline_outcome(
  p_related_type text,
  p_related_id uuid,
  p_outcome text,
  p_win_loss_reason_id uuid,
  p_notes text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.pipeline_outcomes
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_ref record;
  v_reason app.win_loss_reasons;
  v_decision app.rbac_decision;
  v_previous app.pipeline_outcomes;
  v_outcome app.pipeline_outcomes;
begin
  select * into v_ref from app.resolve_commercial_record_ref(p_related_type, p_related_id);
  if v_ref.tenant_id is null or not app.has_active_tenant_membership(v_ref.tenant_id, p_actor_auth_user_id) then
    raise exception 'related_record_not_found: % %', p_related_type, p_related_id using errcode = 'no_data_found';
  end if;

  select * into v_reason from app.win_loss_reasons where id = p_win_loss_reason_id;
  if not found then
    raise exception 'win_loss_reason_not_found: %', p_win_loss_reason_id using errcode = 'no_data_found';
  end if;

  if v_reason.tenant_id <> v_ref.tenant_id then
    raise exception 'cross_tenant_reason_denied: reason and record belong to different tenants'
      using errcode = 'insufficient_privilege';
  end if;

  if v_reason.outcome <> p_outcome then
    raise exception 'reason_outcome_mismatch: reason % is scoped to outcome % but % was requested', p_win_loss_reason_id, v_reason.outcome, p_outcome
      using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_ref.tenant_id, 'COM', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_ref.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_ref.tenant_id, v_ref.owner_user_id, app.lead_record_scope_org_unit_ids(v_ref.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access the record', p_actor_auth_user_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_previous from app.pipeline_outcomes
  where related_type = p_related_type and related_id = p_related_id and is_current;

  if v_previous.id is not null then
    update app.pipeline_outcomes set is_current = false where id = v_previous.id;
  end if;

  insert into app.pipeline_outcomes (
    tenant_id, related_type, related_id, outcome, win_loss_reason_id, notes, recorded_by
  ) values (
    v_ref.tenant_id, p_related_type, p_related_id, p_outcome, p_win_loss_reason_id, p_notes, p_actor_label
  )
  returning * into v_outcome;

  if v_previous.id is not null then
    update app.pipeline_outcomes set superseded_by_id = v_outcome.id where id = v_previous.id;
  end if;

  perform app.capture_audit_event(
    v_ref.tenant_id, p_actor_auth_user_id, p_actor_label, 'record_pipeline_outcome',
    'app.pipeline_outcomes', v_outcome.id, 'success', null,
    case when v_previous.id is not null then to_jsonb(v_previous) else null end,
    to_jsonb(v_outcome)
  );

  return v_outcome;
end;
$$;

-- app.record_risk_signal_outcome -- live definition from 20260806300000_create_intelligence_fraud_risk_assistance.sql
create or replace function app.record_risk_signal_outcome(
  p_signal_id uuid,
  p_ai_governed_request_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.risk_signals
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_signal app.risk_signals;
  v_request app.ai_governed_requests;
  v_score numeric;
  v_band text;
  v_row app.risk_signals;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_signal from app.risk_signals where id = p_signal_id;
  if not found or not app.has_active_tenant_membership(v_signal.tenant_id, p_actor_auth_user_id) then
    raise exception 'risk_signal_not_found: %', p_signal_id using errcode = 'no_data_found';
  end if;

  if not app.check_risk_authority('Create', v_signal.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks AI:Create for tenant %', p_actor_auth_user_id, v_signal.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_signal.ai_governed_request_id is not null then
    if v_signal.ai_governed_request_id = p_ai_governed_request_id then
      return v_signal;
    end if;
    raise exception 'risk_signal_outcome_already_recorded: signal % is already linked to a different governed request', p_signal_id
      using errcode = 'check_violation';
  end if;

  if v_signal.status <> 'pending' then
    raise exception 'risk_signal_not_pending: signal % is % not pending', p_signal_id, v_signal.status using errcode = 'check_violation';
  end if;

  select * into v_request from app.ai_governed_requests where id = p_ai_governed_request_id;
  if not found then
    raise exception 'ai_governed_request_not_found: %', p_ai_governed_request_id using errcode = 'no_data_found';
  end if;

  if v_request.tenant_id <> v_signal.tenant_id then
    raise exception 'risk_signal_request_tenant_mismatch: governed request % does not belong to tenant %', p_ai_governed_request_id, v_signal.tenant_id
      using errcode = 'check_violation';
  end if;
  if v_request.feature_code <> 'fraud_risk_assistance' then
    raise exception 'risk_signal_wrong_feature: governed request % has feature_code % not fraud_risk_assistance', p_ai_governed_request_id, v_request.feature_code
      using errcode = 'check_violation';
  end if;
  if v_request.correlation_record_type is distinct from v_signal.entity_type or v_request.correlation_record_id is distinct from v_signal.entity_id then
    raise exception 'risk_signal_correlation_mismatch: governed request % does not correlate to signal %''s own entity', p_ai_governed_request_id, p_signal_id
      using errcode = 'check_violation';
  end if;
  if v_request.status not in ('succeeded', 'failed') then
    raise exception 'risk_signal_request_not_completed: governed request % is % not succeeded/failed', p_ai_governed_request_id, v_request.status
      using errcode = 'check_violation';
  end if;

  if v_request.status = 'succeeded' then
    v_score := app._parse_risk_score(v_request.output_payload -> 'score');
    v_band := app._parse_risk_band(v_request.output_payload -> 'band');
  end if;

  -- Tier C fix (Group 6 review): the WHERE clause itself is the concurrency
  -- guard against a lost-update race between two concurrent callers each
  -- holding a DIFFERENT real, succeeded governed request for the SAME
  -- still-pending signal -- live-reproduced on the sibling IAE-022
  -- function before this fix, applied proactively here.
  update app.risk_signals
  set ai_governed_request_id = p_ai_governed_request_id,
      status = case when v_request.status = 'succeeded' then 'succeeded' else 'failed' end,
      score = v_score, band = v_band, completed_at = now()
  where id = p_signal_id and status = 'pending'
  returning * into v_row;

  if not found then
    select * into v_row from app.risk_signals where id = p_signal_id;
    if v_row.ai_governed_request_id = p_ai_governed_request_id then
      return v_row;
    end if;
    raise exception 'risk_signal_outcome_already_recorded: signal % is already linked to a different governed request', p_signal_id
      using errcode = 'check_violation';
  end if;

  perform app.capture_audit_event(
    v_signal.tenant_id, p_actor_auth_user_id, p_actor_label, 'record_risk_signal_outcome',
    'app.risk_signals', v_row.id, case when v_request.status = 'succeeded' then 'success' else 'failure' end, null, null,
    jsonb_build_object('status', v_row.status, 'band', v_row.band)
  );

  return v_row;
end;
$$;

-- app.remove_actual_cost_component -- live definition from 20260728110000_create_operations_actual_cost.sql
create or replace function app.remove_actual_cost_component(
  p_component_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns void
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_component app.shipment_actual_cost_components;
  v_cost app.shipment_actual_costs;
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
begin
  select * into v_component from app.shipment_actual_cost_components where id = p_component_id;
  if not found then
    raise exception 'actual_cost_component_not_found: %', p_component_id using errcode = 'no_data_found';
  end if;
  select * into v_cost from app.shipment_actual_costs where id = v_component.actual_cost_id;
  if not app.has_active_tenant_membership(v_cost.tenant_id, p_actor_auth_user_id) then
    raise exception 'actual_cost_component_not_found: %', p_component_id using errcode = 'no_data_found';
  end if;
  select * into v_shipment from app.shipment_orders so where so.id = v_cost.shipment_order_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_cost.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_cost.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.has_view_actual_cost(v_cost.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks OPS:View cost for tenant %', p_actor_auth_user_id, v_cost.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, v_cost.shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_cost.status <> 'draft' then
    raise exception 'invalid_transition: actual cost % is % and its components can no longer be removed', v_cost.id, v_cost.status
      using errcode = 'check_violation';
  end if;

  delete from app.shipment_actual_cost_components where id = p_component_id;
  perform app.recalculate_actual_cost_total(v_cost.id);

  perform app.capture_audit_event(
    v_cost.tenant_id, p_actor_auth_user_id, p_actor_label, 'remove_actual_cost_component',
    'app.shipment_actual_cost_components', p_component_id, 'success', null, to_jsonb(v_component), null
  );
end;
$$;

-- app.remove_customer_contract_price_component -- live definition from 20260724300000_create_commercial_customer_contract_pricing.sql
create or replace function app.remove_customer_contract_price_component(
  p_component_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns void
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_component app.customer_contract_price_components;
  v_contract app.customer_contracts;
  v_decision app.rbac_decision;
begin
  select * into v_component from app.customer_contract_price_components where id = p_component_id;
  if not found then
    raise exception 'price_component_not_found: %', p_component_id using errcode = 'no_data_found';
  end if;

  select * into v_contract from app.customer_contracts where id = v_component.contract_id;
  if not app.has_active_tenant_membership(v_contract.tenant_id, p_actor_auth_user_id) then
    raise exception 'price_component_not_found: %', p_component_id using errcode = 'no_data_found';
  end if;

  if v_contract.status <> 'draft' then
    raise exception 'invalid_transition: contract % is % and its price components cannot be edited', v_contract.id, v_contract.status
      using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_contract.tenant_id, 'COM', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_contract.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  delete from app.customer_contract_price_components where id = p_component_id;
end;
$$;

-- app.rollback_employee_import_job -- live definition from 20260826150000_create_employee_import_rollback.sql
create or replace function app.rollback_employee_import_job(
  p_job_id uuid,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.jobs
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_job app.jobs;
  v_decision app.rbac_decision;
  v_master_record_ids uuid[];
  v_deleted_lifecycle_events integer;
  v_deleted_employees integer;
  v_deleted_master_records integer;
  v_deleted_staging_rows integer;
  v_updated app.jobs;
begin
  select * into v_job from app.jobs where job_id = p_job_id for update;
  if not found or not app.has_active_tenant_membership(v_job.tenant_id, p_actor_auth_user_id) then
    raise exception 'import_export_job_not_found: no job %', p_job_id using errcode = 'no_data_found';
  end if;

  if v_job.job_type <> 'import' or v_job.import_export_schema_code <> 'employee_import' then
    raise exception 'import_export_wrong_schema: job % is not an employee_import job', p_job_id using errcode = 'check_violation';
  end if;

  if not app.check_import_export_job_authority(v_job.tenant_id, p_actor_auth_user_id) then
    raise exception 'job_actor_unauthorized: identity % lacks active membership in tenant %', p_actor_auth_user_id, v_job.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_job.tenant_id, 'HRS', 'Import');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:Import (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_job.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_job.status <> 'completed' then
    raise exception 'import_export_job_not_rollbackable: job % is %, only a completed job may be rolled back', p_job_id, v_job.status
      using errcode = 'check_violation';
  end if;

  if coalesce(trim(p_reason), '') = '' then
    raise exception 'employee_import_rollback_reason_required: a real, non-empty reason is required to roll back a completed import' using errcode = 'check_violation';
  end if;

  select coalesce(array_agg(distinct master_record_id), '{}')
  into v_master_record_ids
  from app.employee_lifecycle_events
  where tenant_id = v_job.tenant_id and metadata ->> 'job_id' = p_job_id::text;

  if array_length(v_master_record_ids, 1) is null then
    raise exception 'employee_import_rollback_no_records: job % created no employee records to roll back (already rolled back, or nothing was ever committed)', p_job_id
      using errcode = 'no_data_found';
  end if;

  begin
    delete from app.employee_lifecycle_events where master_record_id = any (v_master_record_ids);
    get diagnostics v_deleted_lifecycle_events = row_count;

    delete from app.employees where master_record_id = any (v_master_record_ids);
    get diagnostics v_deleted_employees = row_count;

    delete from app.master_records where id = any (v_master_record_ids);
    get diagnostics v_deleted_master_records = row_count;

    delete from app.import_staging_rows where job_id = p_job_id;
    get diagnostics v_deleted_staging_rows = row_count;
  exception
    when foreign_key_violation then
      raise exception 'employee_import_rollback_blocked_by_downstream_references: job % created % employee record(s), and at least one now has real downstream references (e.g. payroll, position assignment, attendance, leave) that must be removed first -- refusing to silently orphan or cascade-delete them', p_job_id, array_length(v_master_record_ids, 1)
        using errcode = 'foreign_key_violation';
  end;

  update app.jobs
  set status = 'rolled_back', error = p_reason
  where job_id = p_job_id
  returning * into v_updated;

  perform app.capture_audit_event(
    v_job.tenant_id, p_actor_auth_user_id, p_actor_label, 'rollback_employee_import_job',
    'app.jobs', p_job_id, 'success', p_reason,
    to_jsonb(v_job),
    jsonb_build_object(
      'master_records_deleted', v_deleted_master_records,
      'employees_deleted', v_deleted_employees,
      'lifecycle_events_deleted', v_deleted_lifecycle_events,
      'staging_rows_deleted', v_deleted_staging_rows
    )
  );

  return v_updated;
end;
$$;

-- app.submit_payroll_run_for_finalization -- live definition from 20260831250000_scope_approval_routing_per_domain.sql
create or replace function app.submit_payroll_run_for_finalization(p_run_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.payroll_runs
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_run app.payroll_runs;
  v_open_exceptions integer;
  v_version_id uuid;
  v_approval app.approval_requests;
begin
  select * into v_run from app.payroll_runs where id = p_run_id for update;
  if not found or not app.has_active_tenant_membership(v_run.tenant_id, p_actor_auth_user_id) then
    raise exception 'payroll_run_not_found: %', p_run_id using errcode = 'no_data_found';
  end if;
  if not app.check_payroll_authority('Approve', v_run.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Approve for tenant %', p_actor_auth_user_id, v_run.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_run.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_run.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_run.status <> 'calculated' then
    raise exception 'invalid_transition: run % is % -- only a fully calculated run with zero open exceptions may be submitted', p_run_id, v_run.status
      using errcode = 'check_violation';
  end if;

  select count(*) into v_open_exceptions from app.payroll_exceptions where payroll_run_id = p_run_id and status = 'open';
  if v_open_exceptions > 0 then
    raise exception 'payroll_run_has_open_exceptions: run % has % unresolved exception(s)', p_run_id, v_open_exceptions using errcode = 'check_violation';
  end if;

  select cv.id into v_version_id from app.config_versions cv
    join app.config_objects co on co.id = cv.config_object_id
    where co.config_type_code = app._resolve_approval_config_type_code(v_run.tenant_id, 'payroll_run') and co.tenant_id = v_run.tenant_id and co.scope_level = 'tenant' and cv.status = 'published'
    limit 1;
  if v_version_id is null then
    raise exception 'approval_definition_not_configured: tenant % has no published approval routing definition', v_run.tenant_id
      using errcode = 'check_violation';
  end if;

  v_approval := app.request_approval(v_version_id, v_run.tenant_id, 'payroll_run', p_run_id, 'payroll_run_finalize:' || p_run_id::text, p_actor_auth_user_id, p_actor_label);

  update app.payroll_runs set status = 'pending_approval', approval_request_id = v_approval.id, submitted_by = p_actor_label, submitted_at = now()
  where id = p_run_id and record_version = p_expected_version
  returning * into v_run;
  if not found then
    raise exception 'stale_version: concurrent update detected for run %', p_run_id using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_run.tenant_id, p_actor_auth_user_id, p_actor_label, 'submit_payroll_run_for_finalization',
    'app.payroll_runs', v_run.id, 'success', null, null, jsonb_build_object('approval_request_id', v_approval.id)
  );

  return v_run;
end;
$function$;
