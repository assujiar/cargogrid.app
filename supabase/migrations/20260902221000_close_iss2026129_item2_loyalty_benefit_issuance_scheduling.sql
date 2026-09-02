-- ISS-2026-129 item 2 (docs/runtime/KNOWN_ISSUES.md) -- issuance-scheduling half.
-- The entry's own 2026-08-31 update explains precisely why the three ISS-2026-126/127/128
-- sweeps (20260831230000) could not simply be repeated for issuance: those three each find
-- a real, pre-existing BACKLOG (an unevaluated paid invoice, an active enrolment due for
-- tier recalculation, an unposted earning event) and drive an existing per-record RPC over
-- it. Issuance has no such backlog -- "this customer is owed a voucher and has not been
-- given one" is not a fact recorded anywhere, because issuing a benefit is a STAFF DECISION,
-- not a state waiting to be discovered.
--
-- That is still true, and this migration does not contradict it: it does not build a
-- business-event-triggered issuance engine (an automatic voucher off a paid invoice or a
-- completed shipment remains a genuinely new, undirected rules-engine capability, not
-- attempted here). What it builds instead is narrower and real: a TENANT-CONFIGURED,
-- RECURRING issuance RULE -- staff explicitly define what to issue (benefit_type, amount,
-- currency, an optional minimum tier), how often (a recurrence interval), and to whom (every
-- active account enrolled in a program, optionally tier-gated) -- and the already-shipped
-- tenant-configurable scheduler (20260831090000) runs it periodically. This is now a real
-- backlog in the exact sense the sibling sweeps require: "every active, eligible account this
-- rule has not yet issued to within its own recurrence window" is a fact the sweep can find,
-- because the RULE itself, once configured, is the fact that was previously missing.
--
-- Mirrors app.run_loyalty_earning_evaluation_sweep/app.run_loyalty_tier_recalculation_sweep/
-- app.run_loyalty_points_posting_sweep (20260831230000) exactly: app.enqueue_job wrapping,
-- per-record subtransaction isolation (one ineligible/misconfigured pairing is a counted skip,
-- never an aborted run), a capped 20-reason skip list, and (tenant, run_label) idempotency via
-- app.enqueue_job. Not one line of eligibility or issuance logic is reimplemented -- every
-- actual issuance goes through the existing, unmodified, already-hardened
-- app.issue_loyalty_benefit_entitlement (CPL-319), which supplies its own idempotency,
-- validation, and audit trail.

-- ===========================================================================
-- 1. app.loyalty_benefit_issuance_rules -- the tenant-configured rule itself.
-- ===========================================================================

create table app.loyalty_benefit_issuance_rules (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  program_id uuid not null references app.loyalty_programs (id),
  benefit_type text not null,
  value_amount numeric not null,
  value_cap numeric,
  currency text not null,
  min_tier_id uuid references app.loyalty_tier_definitions (id),
  expires_in_days integer,
  recurrence_interval_days integer not null,
  status text not null default 'active',
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  constraint lbir_benefit_type_check check (benefit_type in ('cashback', 'discount', 'voucher')),
  constraint lbir_value_amount_check check (value_amount > 0),
  constraint lbir_value_cap_check check (value_cap is null or value_cap > 0),
  constraint lbir_value_cap_ge_amount_check check (value_cap is null or value_amount <= value_cap),
  constraint lbir_currency_check check (currency ~ '^[A-Z]{3}$'),
  constraint lbir_expires_in_days_check check (expires_in_days is null or expires_in_days > 0),
  constraint lbir_recurrence_interval_days_check check (recurrence_interval_days > 0),
  constraint lbir_status_check check (status in ('active', 'inactive'))
);

comment on table app.loyalty_benefit_issuance_rules is
  'ISS-2026-129 item 2: a tenant-configured recurring issuance rule -- staff decide what to issue (benefit_type/value_amount/value_cap/currency, the exact shape app.issue_loyalty_benefit_entitlement itself requires), how often (recurrence_interval_days), and to whom (every ACTIVE app.loyalty_accounts row in program_id, optionally gated by min_tier_id via the account''s own latest app.loyalty_account_tier_movements row -- the identical tier-rank check app.submit_loyalty_redemption already uses). Never a business-event trigger (no paid-invoice/completed-shipment detection) -- a disclosed, narrower, but real scheduling capability. status=inactive pauses a rule without deleting its own issuance history (every entitlement it ever issued stays attributed to it via source_type=''loyalty_benefit_issuance_rule''/source_id).';

create index lbir_tenant_status_idx on app.loyalty_benefit_issuance_rules (tenant_id, status);
create index lbir_tenant_updated_id_idx on app.loyalty_benefit_issuance_rules (tenant_id, updated_at desc, id desc);

create function app.touch_loyalty_benefit_issuance_rule_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := clock_timestamp();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger loyalty_benefit_issuance_rules_touch_row
  before update on app.loyalty_benefit_issuance_rules
  for each row
  execute function app.touch_loyalty_benefit_issuance_rule_row();

-- ===========================================================================
-- 2. Configuration RPCs -- LYL:Configure, mirroring app.set_loyalty_reward_
-- voucher_value_config's own narrow, single-purpose shape (CPL-320/ISS-2026-129
-- item 3). Update requires a real, non-null p_expected_version -- the
-- established NULL-bypass-hardening discipline (20260801260000) applied from
-- the start, never retrofitted.
-- ===========================================================================

create function app.create_loyalty_benefit_issuance_rule(
  p_tenant_id uuid,
  p_program_id uuid,
  p_benefit_type text,
  p_value_amount numeric,
  p_value_cap numeric,
  p_currency text,
  p_min_tier_id uuid,
  p_expires_in_days integer,
  p_recurrence_interval_days integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.loyalty_benefit_issuance_rules
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_program app.loyalty_programs;
  v_rule app.loyalty_benefit_issuance_rules;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'Configure');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks LYL:Configure (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_program from app.loyalty_programs where id = p_program_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'loyalty_program_not_found: %', p_program_id using errcode = 'no_data_found';
  end if;

  if p_min_tier_id is not null and not exists (
    select 1 from app.loyalty_tier_definitions td where td.id = p_min_tier_id and td.tenant_id = p_tenant_id and td.program_id = p_program_id
  ) then
    raise exception 'loyalty_tier_not_found: % is not a tier of program %', p_min_tier_id, p_program_id using errcode = 'no_data_found';
  end if;

  if p_benefit_type not in ('cashback', 'discount', 'voucher') then
    raise exception 'invalid_benefit_type: % is not one of cashback/discount/voucher', p_benefit_type using errcode = 'check_violation';
  end if;
  if p_value_amount is null or p_value_amount <= 0 then
    raise exception 'invalid_value_amount: value_amount must be greater than zero' using errcode = 'check_violation';
  end if;
  if p_currency is null or p_currency !~ '^[A-Z]{3}$' then
    raise exception 'invalid_currency: % is not a 3-letter uppercase currency code', p_currency using errcode = 'check_violation';
  end if;
  if p_recurrence_interval_days is null or p_recurrence_interval_days <= 0 then
    raise exception 'invalid_recurrence_interval_days: recurrence_interval_days must be greater than zero' using errcode = 'check_violation';
  end if;

  insert into app.loyalty_benefit_issuance_rules (
    tenant_id, program_id, benefit_type, value_amount, value_cap, currency, min_tier_id,
    expires_in_days, recurrence_interval_days, created_by
  ) values (
    p_tenant_id, p_program_id, p_benefit_type, p_value_amount, p_value_cap, p_currency, p_min_tier_id,
    p_expires_in_days, p_recurrence_interval_days, p_actor_label
  )
  returning * into v_rule;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_loyalty_benefit_issuance_rule',
    'app.loyalty_benefit_issuance_rules', v_rule.id, 'success', null, null, to_jsonb(v_rule)
  );

  return v_rule;
end;
$$;

create function app.update_loyalty_benefit_issuance_rule(
  p_tenant_id uuid,
  p_rule_id uuid,
  p_expected_version integer,
  p_value_amount numeric,
  p_value_cap numeric,
  p_currency text,
  p_min_tier_id uuid,
  p_expires_in_days integer,
  p_recurrence_interval_days integer,
  p_status text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.loyalty_benefit_issuance_rules
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_rule app.loyalty_benefit_issuance_rules;
  v_updated app.loyalty_benefit_issuance_rules;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'Configure');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks LYL:Configure (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- NULL-bypass hardening (20260801260000's own established class): a null
  -- p_expected_version is rejected outright, never treated as "skip the check."
  if p_expected_version is null then
    raise exception 'expected_version_required: p_expected_version must be provided' using errcode = 'check_violation';
  end if;

  select * into v_rule from app.loyalty_benefit_issuance_rules where id = p_rule_id and tenant_id = p_tenant_id for update;
  if not found then
    raise exception 'loyalty_benefit_issuance_rule_not_found: %', p_rule_id using errcode = 'no_data_found';
  end if;
  if v_rule.record_version <> p_expected_version then
    raise exception 'stale_version: rule % was expected at version % but is at %', p_rule_id, p_expected_version, v_rule.record_version
      using errcode = 'serialization_failure';
  end if;

  if p_min_tier_id is not null and not exists (
    select 1 from app.loyalty_tier_definitions td where td.id = p_min_tier_id and td.tenant_id = p_tenant_id and td.program_id = v_rule.program_id
  ) then
    raise exception 'loyalty_tier_not_found: % is not a tier of program %', p_min_tier_id, v_rule.program_id using errcode = 'no_data_found';
  end if;
  if p_value_amount is null or p_value_amount <= 0 then
    raise exception 'invalid_value_amount: value_amount must be greater than zero' using errcode = 'check_violation';
  end if;
  if p_currency is null or p_currency !~ '^[A-Z]{3}$' then
    raise exception 'invalid_currency: % is not a 3-letter uppercase currency code', p_currency using errcode = 'check_violation';
  end if;
  if p_recurrence_interval_days is null or p_recurrence_interval_days <= 0 then
    raise exception 'invalid_recurrence_interval_days: recurrence_interval_days must be greater than zero' using errcode = 'check_violation';
  end if;
  if p_status is null or p_status not in ('active', 'inactive') then
    raise exception 'invalid_status: % is not active or inactive', p_status using errcode = 'check_violation';
  end if;

  update app.loyalty_benefit_issuance_rules
  set value_amount = p_value_amount, value_cap = p_value_cap, currency = p_currency, min_tier_id = p_min_tier_id,
      expires_in_days = p_expires_in_days, recurrence_interval_days = p_recurrence_interval_days, status = p_status
  where id = p_rule_id and record_version = p_expected_version
  returning * into v_updated;
  if not found then
    raise exception 'stale_version: rule % was concurrently modified', p_rule_id using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'update_loyalty_benefit_issuance_rule',
    'app.loyalty_benefit_issuance_rules', p_rule_id, 'success', null, to_jsonb(v_rule), to_jsonb(v_updated)
  );

  return v_updated;
end;
$$;

create function app.get_loyalty_benefit_issuance_rule(p_tenant_id uuid, p_rule_id uuid, p_actor_auth_user_id uuid)
returns app.loyalty_benefit_issuance_rules
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_rule app.loyalty_benefit_issuance_rules;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks LYL:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_rule from app.loyalty_benefit_issuance_rules where id = p_rule_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'loyalty_benefit_issuance_rule_not_found: %', p_rule_id using errcode = 'no_data_found';
  end if;

  return v_rule;
end;
$$;

create function app.list_loyalty_benefit_issuance_rules(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_before_created_at timestamptz default null,
  p_before_id uuid default null,
  p_limit integer default 50
)
returns setof app.loyalty_benefit_issuance_rules
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_limit integer;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks LYL:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_limit := least(greatest(coalesce(p_limit, 50), 1), 200);

  return query
  select r.*
  from app.loyalty_benefit_issuance_rules r
  where r.tenant_id = p_tenant_id
    and (p_before_created_at is null or (r.created_at, r.id) < (p_before_created_at, p_before_id))
  order by r.created_at desc, r.id desc
  limit v_limit;
end;
$$;

-- ===========================================================================
-- 3. app.run_loyalty_benefit_issuance_rule_sweep -- the periodic sweep, mirroring
-- app.run_loyalty_earning_evaluation_sweep/app.run_loyalty_tier_recalculation_
-- sweep/app.run_loyalty_points_posting_sweep (20260831230000) exactly.
-- ===========================================================================

alter table app.jobs drop constraint jobs_job_type_check;
alter table app.jobs add constraint jobs_job_type_check check (
  job_type = any (array[
    'import', 'export', 'report_generation', 'notification_batch', 'webhook_retry',
    'document_generation', 'dashboard_refresh', 'loyalty_expiration', 'recurring_billing',
    'integration_sync', 'route_load_planning', 'print_label', 'roster_generation',
    'leave_accrual', 'leave_carry_forward_expiry', 'payroll_calculation',
    'training_certificate_expiry', 'training_certificate_expiry_reminder',
    'ticket_sla_evaluation', 'kb_article_expiry', 'ticket_escalation_evaluation',
    'loyalty_expiry_sweep', 'automation_action_execution', 'logistics_partner_sync',
    'finance_bank_feed_sync', 'external_sync', 'audit_export', 'retention_archive',
    'incident_escalation_sweep',
    'loyalty_earning_evaluation_sweep', 'loyalty_tier_recalculation_sweep', 'loyalty_points_posting_sweep',
    -- ISS-2026-129 item 2:
    'loyalty_benefit_issuance_sweep'
  ])
);

create or replace function app.generic_job_types()
returns text[]
language sql
immutable
set search_path = app, pg_temp
as $$
  select array[
    'report_generation', 'notification_batch', 'webhook_retry', 'document_generation',
    'dashboard_refresh', 'loyalty_expiration', 'recurring_billing', 'integration_sync',
    'route_load_planning', 'print_label', 'roster_generation', 'leave_accrual', 'leave_carry_forward_expiry',
    'payroll_calculation', 'training_certificate_expiry', 'training_certificate_expiry_reminder',
    'ticket_sla_evaluation', 'kb_article_expiry', 'ticket_escalation_evaluation', 'loyalty_expiry_sweep',
    'automation_action_execution', 'logistics_partner_sync', 'finance_bank_feed_sync', 'external_sync',
    'audit_export', 'retention_archive', 'incident_escalation_sweep',
    'loyalty_earning_evaluation_sweep', 'loyalty_tier_recalculation_sweep', 'loyalty_points_posting_sweep',
    -- ISS-2026-129 item 2:
    'loyalty_benefit_issuance_sweep'
  ]::text[];
$$;

create function app.run_loyalty_benefit_issuance_rule_sweep(
  p_tenant_id uuid,
  p_as_of timestamptz default now(),
  p_actor_auth_user_id uuid default null,
  p_actor_label text default null,
  p_run_label text default null
)
returns table (job_id uuid, status text, run_label text, processed_count integer, skipped_count integer)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_as_of timestamptz := coalesce(p_as_of, now());
  v_run_label text;
  v_job app.jobs;
  v_final app.jobs;
  v_worker_id text;
  v_candidate record;
  v_processed integer := 0;
  v_skipped integer := 0;
  v_skips jsonb := '[]'::jsonb;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks LYL:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_run_label := coalesce(nullif(trim(p_run_label), ''), to_char(v_as_of, 'YYYY-MM-DD'));

  v_job := app.enqueue_job(
    p_tenant_id, 'loyalty_benefit_issuance_sweep', jsonb_build_object('run_label', v_run_label),
    0, 'loyalty_benefit_issuance_sweep:' || p_tenant_id::text || ':' || v_run_label, 1, p_actor_auth_user_id, p_actor_label
  );

  if v_job.status = 'pending' then
    v_worker_id := 'inline-loyalty-benefit-issuance-sweep:' || p_actor_auth_user_id::text;
    update app.jobs j set status = 'in_progress', locked_by = v_worker_id, locked_until = clock_timestamp() + interval '10 minutes'
    where j.job_id = v_job.job_id and j.status = 'pending';

    -- Every ACTIVE rule, crossed with every ACTIVE account enrolled in that rule's own
    -- program, tier-gated the SAME way app.submit_loyalty_redemption already resolves a
    -- current tier (latest app.loyalty_account_tier_movements row, joined to tier_rank).
    -- "Not yet due" is read from app.loyalty_benefit_entitlements itself -- the most
    -- recent entitlement THIS rule issued to THIS account -- rather than a second,
    -- parallel bookkeeping table: source_type/source_id is the real, durable link
    -- app.issue_loyalty_benefit_entitlement already writes, never re-derived elsewhere.
    for v_candidate in
      select r.id as rule_id, a.id as account_id, r.benefit_type, r.value_amount, r.value_cap, r.currency, r.expires_in_days
      from app.loyalty_benefit_issuance_rules r
      join app.loyalty_accounts a on a.tenant_id = r.tenant_id and a.program_id = r.program_id and a.status = 'active'
      left join lateral (
        select td.tier_rank
        from app.loyalty_account_tier_movements tm
        join app.loyalty_tier_definitions td on td.id = tm.to_tier_id
        where tm.tenant_id = r.tenant_id and tm.loyalty_account_id = a.id
        order by tm.created_at desc, tm.id desc
        limit 1
      ) cur_tier on true
      left join app.loyalty_tier_definitions min_td on min_td.id = r.min_tier_id
      where r.tenant_id = p_tenant_id and r.status = 'active'
        and (r.min_tier_id is null or (cur_tier.tier_rank is not null and cur_tier.tier_rank >= min_td.tier_rank))
        and not exists (
          select 1 from app.loyalty_benefit_entitlements e
          where e.tenant_id = r.tenant_id and e.loyalty_account_id = a.id
            and e.source_type = 'loyalty_benefit_issuance_rule' and e.source_id = r.id
            and e.created_at > v_as_of - (r.recurrence_interval_days || ' days')::interval
        )
      order by r.id, a.id
    loop
      begin
        perform app.issue_loyalty_benefit_entitlement(
          p_tenant_id, v_candidate.account_id, v_candidate.benefit_type, v_candidate.value_amount, v_candidate.value_cap, v_candidate.currency,
          'loyalty_benefit_issuance_rule', v_candidate.rule_id,
          case when v_candidate.expires_in_days is not null then v_as_of + (v_candidate.expires_in_days || ' days')::interval else null end,
          'loyalty-issuance-rule:' || v_candidate.rule_id::text || ':' || v_candidate.account_id::text || ':' || to_char(v_as_of, 'YYYY-MM-DD'),
          p_actor_auth_user_id, p_actor_label
        );
        v_processed := v_processed + 1;
      exception
        when others then
          -- One misconfigured rule or ineligible account must never stop the eligible
          -- pairings behind it. The subtransaction this block opens rolls back only
          -- this one candidate.
          v_skipped := v_skipped + 1;
          if jsonb_array_length(v_skips) < 20 then
            v_skips := v_skips || jsonb_build_object('rule_id', v_candidate.rule_id, 'loyalty_account_id', v_candidate.account_id, 'reason', split_part(sqlerrm, ':', 1));
          end if;
      end;
    end loop;

    update app.jobs j
    set payload = j.payload || jsonb_build_object(
      'processed_count', v_processed, 'skipped_count', v_skipped, 'skips', v_skips,
      'swept_at', v_as_of, 'requested_as_of', p_as_of)
    where j.job_id = v_job.job_id;

    v_final := app.complete_job(v_job.job_id, v_worker_id, null, p_actor_label);

    perform app.capture_audit_event(
      p_tenant_id, p_actor_auth_user_id, p_actor_label, 'run_loyalty_benefit_issuance_rule_sweep',
      'app.jobs', v_job.job_id, 'success', null, null,
      jsonb_build_object('run_label', v_run_label, 'processed_count', v_processed, 'skipped_count', v_skipped)
    );
  else
    v_final := v_job;
    v_processed := coalesce((v_final.payload->>'processed_count')::integer, 0);
    v_skipped := coalesce((v_final.payload->>'skipped_count')::integer, 0);
  end if;

  job_id := v_final.job_id;
  status := v_final.status;
  run_label := v_run_label;
  processed_count := v_processed;
  skipped_count := v_skipped;
  return next;
end;
$$;

comment on function app.run_loyalty_benefit_issuance_rule_sweep is
  'ISS-2026-129 item 2: for every ACTIVE app.loyalty_benefit_issuance_rules row, issues its configured benefit to every ACTIVE, eligible (tier-gated) enrolled account not yet issued to within its own recurrence_interval_days window, via the existing, unmodified app.issue_loyalty_benefit_entitlement. "Not yet due" is read from that RPC''s own durable source_type/source_id link, never a second bookkeeping table. Per-record subtransaction isolation (a misconfigured rule or ineligible account is a counted skip, never an aborted run), first-twenty skip reasons on the job row, (tenant, run_label) idempotency via app.enqueue_job -- identical shape to app.run_loyalty_earning_evaluation_sweep/app.run_loyalty_tier_recalculation_sweep/app.run_loyalty_points_posting_sweep (20260831230000). LYL:Edit here AND again inside app.issue_loyalty_benefit_entitlement per record, on purpose, for the same reason those three sweeps already give: the outer gate stops an unauthorised run starting, the inner gate stops a sweep ever doing what its caller could not do one issuance at a time.';

-- ===========================================================================
-- 4. Scheduler catalogue registration + dispatch branch (mirrors 20260831230000
-- section 6 exactly). Same signature on app._run_scheduled_task_once, so
-- `create or replace` genuinely replaces (ISS-2026-260) -- rebuilt from the
-- LIVE definition (pg_get_functiondef-verified before drafting, not from the
-- CREATING migration -- the exact trap 20260831230000's own header already
-- names and the near-miss it caught), every existing branch byte-identical,
-- one new branch added.
-- ===========================================================================

insert into app.scheduled_task_definitions
  (task_code, display_name, description, tenant_admin_configurable, min_interval_minutes, default_interval_minutes, required_params)
values
  ('loyalty_benefit_issuance_sweep', 'Loyalty benefit issuance',
   'Issues each configured, tenant-owned recurring benefit rule to every eligible, not-yet-due enrolled account.', true, 60, 1440, '{}')
on conflict (task_code) do nothing;

-- Rebuilt from the LIVE definition (pg_get_functiondef against the hosted project,
-- verified immediately before drafting this migration -- NOT from any migration file):
-- the live body already carries a 'loyalty_liability_reconciliation' branch (added after
-- 20260831230000, by 20260831240000) and an 'onboarding_offboarding_overdue_task_sweep'
-- branch (added later still, by 20260902043000) -- NEITHER of which appears in
-- 20260831230000's own on-disk text. Rebuilding from that file, as an earlier draft of
-- this exact migration did, would have silently deleted both live dispatch branches --
-- precisely the trap 20260831230000's own header already names and the near-miss it
-- caught. Every branch below is byte-identical to the live definition; exactly one new
-- branch (loyalty_benefit_issuance_sweep) is added.
create or replace function app._run_scheduled_task_once(p_schedule app.tenant_scheduled_tasks, p_now timestamptz)
returns void
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_actor uuid := p_schedule.authorized_by_auth_user_id;
  v_label text := 'scheduler:' || p_schedule.task_code;
  v_period text := to_char(p_now, 'YYYY-MM-DD');
begin
  case p_schedule.task_code
    when 'loyalty_expiry_sweep' then
      perform app.run_loyalty_expiry_sweep(p_schedule.tenant_id, p_now, v_actor, v_label, v_period);
    when 'loyalty_point_lot_expiry' then
      perform app.expire_loyalty_point_lots(p_schedule.tenant_id, v_actor, v_label, p_now);
    when 'loyalty_benefit_entitlement_expiry' then
      perform app.expire_loyalty_benefit_entitlements(p_schedule.tenant_id, v_actor, v_label, p_now);
    when 'loyalty_earning_evaluation_sweep' then
      perform app.run_loyalty_earning_evaluation_sweep(p_schedule.tenant_id, p_now, v_actor, v_label, v_period);
    when 'loyalty_tier_recalculation_sweep' then
      perform app.run_loyalty_tier_recalculation_sweep(p_schedule.tenant_id, p_now, v_actor, v_label, v_period);
    when 'loyalty_points_posting_sweep' then
      perform app.run_loyalty_points_posting_sweep(p_schedule.tenant_id, p_now, v_actor, v_label, v_period);
    when 'loyalty_liability_reconciliation' then
      perform app.execute_loyalty_liability_reconciliation_run(
        p_schedule.tenant_id, p_now, p_schedule.params ->> 'currency', v_actor, v_label,
        'scheduler:' || p_schedule.task_code || ':' || (p_schedule.params ->> 'currency') || ':' || v_period, 1);
    -- ISS-2026-129 item 2:
    when 'loyalty_benefit_issuance_sweep' then
      perform app.run_loyalty_benefit_issuance_rule_sweep(p_schedule.tenant_id, p_now, v_actor, v_label, v_period);
    when 'employee_position_activation' then
      perform app.activate_due_employee_position_assignments(p_schedule.tenant_id, v_actor, v_label);
    when 'onboarding_offboarding_overdue_task_sweep' then
      perform app.run_onboarding_overdue_task_sweep(p_schedule.tenant_id, p_now, v_period, v_actor, v_label);
    when 'leave_accrual_batch' then
      perform app.run_leave_accrual_batch(
        p_schedule.tenant_id, (p_schedule.params ->> 'leave_type_id')::uuid, p_now::date, v_period, v_actor, v_label);
    when 'leave_carry_forward_batch' then
      perform app.run_leave_carry_forward_batch(
        p_schedule.tenant_id, (p_schedule.params ->> 'leave_type_id')::uuid, p_now::date, v_period, v_actor, v_label);
    when 'training_certificate_expiry' then
      perform app.run_training_certificate_expiry_batch(p_schedule.tenant_id, p_now::date, v_period, v_actor, v_label);
    when 'training_certificate_expiry_reminder' then
      perform app.run_training_certificate_expiry_reminder_batch(
        p_schedule.tenant_id, p_now::date, (p_schedule.params ->> 'lookahead_days')::integer, v_period, v_actor, v_label);
    when 'incident_escalation_sweep' then
      perform app.run_incident_escalation_sweep(p_schedule.tenant_id, p_now, v_period, v_actor, v_label);
    when 'ticket_sla_evaluation' then
      perform app.run_ticket_sla_evaluation_batch(p_schedule.tenant_id, p_now, v_period, v_actor, v_label);
    when 'ticket_escalation_evaluation' then
      perform app.run_ticket_escalation_evaluation_batch(p_schedule.tenant_id, p_now, v_period, v_actor, v_label);
    when 'authority_denial_anomaly_sweep' then
      perform app.run_authority_denial_anomaly_sweep(
        p_schedule.tenant_id, p_now,
        (p_schedule.params ->> 'window_minutes')::integer,
        (p_schedule.params ->> 'threshold')::integer,
        v_actor, v_label);
    when 'employee_lifecycle_activation' then
      perform app.activate_due_employee_lifecycle_transitions(p_schedule.tenant_id, v_actor, v_label);
    when 'kb_article_version_expiry' then
      perform app.expire_kb_article_versions_batch(p_schedule.tenant_id, p_now, v_period, v_actor, v_label);
    when 'vendor_compliance_waiver_expiry' then
      perform app.expire_vendor_compliance_waivers(
        p_schedule.tenant_id, v_actor, v_label, (p_schedule.params ->> 'max_rows')::integer);
    when 'vendor_compliance_status_refresh' then
      perform app.recalculate_tenant_vendor_compliance_status(
        p_schedule.tenant_id, v_actor, v_label, (p_schedule.params ->> 'max_vendors')::integer);
    else
      raise exception 'scheduled_task_not_dispatchable: % has a catalogue row but no dispatch branch', p_schedule.task_code
        using errcode = 'check_violation';
  end case;
end;
$$;

comment on function app._run_scheduled_task_once is
  'Internal (app._ prefix, service_role-only): the explicit per-task dispatch, now twenty-two enumerated calls after ISS-2026-129 item 2 added the benefit-issuance sweep. Deliberately a CASE rather than dynamic SQL assembled from the row -- task_code is catalogue-controlled today, but a scheduler that EXECUTEs a statement built from a table column is one bad migration away from an injection surface. Every call passes the schedule''s own authorized_by_auth_user_id as the actor, which is what makes a scheduled run attributable to a person. A catalogue row with no dispatch branch raises rather than silently doing nothing.';

revoke execute on function app._run_scheduled_task_once(app.tenant_scheduled_tasks, timestamptz) from public, anon, authenticated;
grant execute on function app._run_scheduled_task_once(app.tenant_scheduled_tasks, timestamptz) to service_role;

-- ===========================================================================
-- 5. Grants + public.* wrappers (RGL-394 Option 2). `revoke ... from anon,
-- authenticated, service_role, public` rather than `from public` alone --
-- Supabase's ALTER DEFAULT PRIVILEGES grants anon EXECUTE explicitly at
-- CREATE time, and an explicit grant survives a PUBLIC revoke (ISS-2026-309).
-- ===========================================================================

revoke execute on all functions in schema app from public;

grant execute on function app.create_loyalty_benefit_issuance_rule(uuid, uuid, text, numeric, numeric, text, uuid, integer, integer, uuid, text) to authenticated, service_role;
grant execute on function app.update_loyalty_benefit_issuance_rule(uuid, uuid, integer, numeric, numeric, text, uuid, integer, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.get_loyalty_benefit_issuance_rule(uuid, uuid, uuid) to authenticated, service_role;
grant execute on function app.list_loyalty_benefit_issuance_rules(uuid, uuid, timestamptz, uuid, integer) to authenticated, service_role;
grant execute on function app.run_loyalty_benefit_issuance_rule_sweep(uuid, timestamptz, uuid, text, text) to authenticated, service_role;

create function public.create_loyalty_benefit_issuance_rule(
  p_tenant_id uuid, p_program_id uuid, p_benefit_type text, p_value_amount numeric, p_value_cap numeric,
  p_currency text, p_min_tier_id uuid, p_expires_in_days integer, p_recurrence_interval_days integer,
  p_actor_auth_user_id uuid, p_actor_label text
)
returns app.loyalty_benefit_issuance_rules
language sql
security definer
set search_path = app, public, pg_temp
as $wrap$
  select app.create_loyalty_benefit_issuance_rule(p_tenant_id, p_program_id, p_benefit_type, p_value_amount, p_value_cap, p_currency, p_min_tier_id, p_expires_in_days, p_recurrence_interval_days, p_actor_auth_user_id, p_actor_label);
$wrap$;

comment on function public.create_loyalty_benefit_issuance_rule(uuid, uuid, text, numeric, numeric, text, uuid, integer, integer, uuid, text) is
  'RGL-394 Option-2 wrapper: a thin security-definer pass-through to app.create_loyalty_benefit_issuance_rule, never a reimplementation.';

revoke execute on function public.create_loyalty_benefit_issuance_rule(uuid, uuid, text, numeric, numeric, text, uuid, integer, integer, uuid, text) from anon, authenticated, service_role, public;
grant execute on function public.create_loyalty_benefit_issuance_rule(uuid, uuid, text, numeric, numeric, text, uuid, integer, integer, uuid, text) to authenticated, service_role;

create function public.update_loyalty_benefit_issuance_rule(
  p_tenant_id uuid, p_rule_id uuid, p_expected_version integer, p_value_amount numeric, p_value_cap numeric,
  p_currency text, p_min_tier_id uuid, p_expires_in_days integer, p_recurrence_interval_days integer,
  p_status text, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.loyalty_benefit_issuance_rules
language sql
security definer
set search_path = app, public, pg_temp
as $wrap$
  select app.update_loyalty_benefit_issuance_rule(p_tenant_id, p_rule_id, p_expected_version, p_value_amount, p_value_cap, p_currency, p_min_tier_id, p_expires_in_days, p_recurrence_interval_days, p_status, p_actor_auth_user_id, p_actor_label);
$wrap$;

comment on function public.update_loyalty_benefit_issuance_rule(uuid, uuid, integer, numeric, numeric, text, uuid, integer, integer, text, uuid, text) is
  'RGL-394 Option-2 wrapper: a thin security-definer pass-through to app.update_loyalty_benefit_issuance_rule, never a reimplementation.';

revoke execute on function public.update_loyalty_benefit_issuance_rule(uuid, uuid, integer, numeric, numeric, text, uuid, integer, integer, text, uuid, text) from anon, authenticated, service_role, public;
grant execute on function public.update_loyalty_benefit_issuance_rule(uuid, uuid, integer, numeric, numeric, text, uuid, integer, integer, text, uuid, text) to authenticated, service_role;

create function public.get_loyalty_benefit_issuance_rule(p_tenant_id uuid, p_rule_id uuid, p_actor_auth_user_id uuid)
returns app.loyalty_benefit_issuance_rules
language sql
security definer
set search_path = app, public, pg_temp
as $wrap$
  select app.get_loyalty_benefit_issuance_rule(p_tenant_id, p_rule_id, p_actor_auth_user_id);
$wrap$;

comment on function public.get_loyalty_benefit_issuance_rule(uuid, uuid, uuid) is
  'RGL-394 Option-2 wrapper: a thin security-definer pass-through to app.get_loyalty_benefit_issuance_rule, never a reimplementation.';

revoke execute on function public.get_loyalty_benefit_issuance_rule(uuid, uuid, uuid) from anon, authenticated, service_role, public;
grant execute on function public.get_loyalty_benefit_issuance_rule(uuid, uuid, uuid) to authenticated, service_role;

create function public.list_loyalty_benefit_issuance_rules(
  p_tenant_id uuid, p_actor_auth_user_id uuid, p_before_created_at timestamptz default null,
  p_before_id uuid default null, p_limit integer default 50
)
returns setof app.loyalty_benefit_issuance_rules
language sql
security definer
set search_path = app, public, pg_temp
as $wrap$
  select * from app.list_loyalty_benefit_issuance_rules(p_tenant_id, p_actor_auth_user_id, p_before_created_at, p_before_id, p_limit);
$wrap$;

comment on function public.list_loyalty_benefit_issuance_rules(uuid, uuid, timestamptz, uuid, integer) is
  'RGL-394 Option-2 wrapper: a thin security-definer pass-through to app.list_loyalty_benefit_issuance_rules, never a reimplementation.';

revoke execute on function public.list_loyalty_benefit_issuance_rules(uuid, uuid, timestamptz, uuid, integer) from anon, authenticated, service_role, public;
grant execute on function public.list_loyalty_benefit_issuance_rules(uuid, uuid, timestamptz, uuid, integer) to authenticated, service_role;

create function public.run_loyalty_benefit_issuance_rule_sweep(
  p_tenant_id uuid, p_as_of timestamptz default now(), p_actor_auth_user_id uuid default null,
  p_actor_label text default null, p_run_label text default null
)
returns table (job_id uuid, status text, run_label text, processed_count integer, skipped_count integer)
language sql
security definer
set search_path = app, public, pg_temp
as $wrap$
  select * from app.run_loyalty_benefit_issuance_rule_sweep(p_tenant_id, p_as_of, p_actor_auth_user_id, p_actor_label, p_run_label);
$wrap$;

comment on function public.run_loyalty_benefit_issuance_rule_sweep(uuid, timestamptz, uuid, text, text) is
  'RGL-394 Option-2 wrapper: a thin security-definer pass-through to app.run_loyalty_benefit_issuance_rule_sweep, never a reimplementation.';

revoke execute on function public.run_loyalty_benefit_issuance_rule_sweep(uuid, timestamptz, uuid, text, text) from anon, authenticated, service_role, public;
grant execute on function public.run_loyalty_benefit_issuance_rule_sweep(uuid, timestamptz, uuid, text, text) to authenticated, service_role;
