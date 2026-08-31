-- Closes the last two open items of `ISS-2026-249` (High) and all of `ISS-2026-313`.
--
-- ===========================================================================
-- ISS-2026-249 -- the two producers that were left, and the reason they were hard
-- ===========================================================================
--
--   "Still open on this entry: `app.evaluate_permission`'s general RBAC-denial path
--    (false-positive flood by design) and `app.assert_current_step_up_authorization` (no durable
--    evidence today, and `stable`, so it needs a new log table plus a volatility change). Both
--    remain genuinely architectural, not one-line mirrors."
--
--   That assessment was right, and it understated the problem by one step. The real obstacle is
--   not volatility. It is this:
--
--     **A database function that RAISES cannot durably record the denial it raises on.** The
--     INSERT and the RAISE are in the same transaction, so the raise rolls the record back.
--
--   Which is exactly why `20260827000000_wire_observability_alert_producers.sql` placed every one
--   of its alert calls "immediately before that branch's own normal `return`, never before a
--   `raise exception`". Making `app.assert_current_step_up_authorization` volatile would let it
--   INSERT and would still record nothing, because it raises three lines later. Changing it to
--   return a decision instead of raising would change the contract of every call site.
--
-- THE RULING: RECORD AT THE BOUNDARY, DETECT ON A THRESHOLD
--
--   Two separate problems, two separate answers.
--
--   1. **Durability.** The denial is recorded from OUTSIDE the failed transaction, by the
--      application boundary that catches the error — a Server Action or route handler, in a new
--      statement, after the rollback. `app.record_authority_denial` is that recorder. This is not
--      a workaround; it is the only place in the stack where the fact "this call was denied" both
--      exists and can be written down.
--
--   2. **The false-positive flood.** Alerting per denial would be useless: a denial is the
--      authorization layer working. `app.run_authority_denial_anomaly_sweep` alerts on a
--      *pattern* instead — one actor accumulating more than a threshold of denials inside a
--      window — and raises ONE deduplicated incident per (tenant, actor) burst rather than one
--      per denial. A person hitting a permission they do not have produces nothing; somebody
--      probing produces one actionable incident.
--
--   Step-up denials need no separate machinery: `app.evaluate_permission` already RETURNS
--   `reason = 'mfa_step_up_required'` (ISS-2026-236, 20260830110000) rather than raising, so a
--   step-up refusal is just another denial reason flowing through the same recorder. The second
--   open item closes as a consequence of the first being done properly, which is a better outcome
--   than the new log table plus volatility change the entry proposed.
--
-- ===========================================================================
-- ISS-2026-313 -- four sweeps the catalogue was seeded without
-- ===========================================================================
--
--   Registered against the scheduler migration by the same pass that wrote it: the catalogue was
--   seeded from what the backlog complained about rather than from what the schema offers, so
--   four existing tenant-wide sweeps of exactly the right shape were left out. They are added
--   here, along with the denial sweep above, and the dispatcher gains a branch for each.

-- ===========================================================================
-- 1. The denial ledger
-- ===========================================================================

create table app.authority_denials (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  actor_auth_user_id uuid references auth.users (id),
  -- 'rbac' for an ordinary permission denial, 'step_up' for mfa_step_up_required, 'ip' for an
  -- IP-allowlist block. Deliberately open-ended text rather than an enum: a new denial class
  -- should be recordable without a migration, and the sweep groups rather than branches on it.
  denial_kind text not null,
  module_code text,
  action text,
  reason text,
  resource_type text,
  resource_id uuid,
  correlation_id uuid,
  occurred_at timestamptz not null default now(),
  constraint authority_denials_kind_check check (length(trim(denial_kind)) > 0)
);

comment on table app.authority_denials is
  'ISS-2026-249: durable evidence of an authorization refusal, written from OUTSIDE the transaction that was refused. It has to be, and that is the whole finding: a function that raises cannot record the denial it raises on, because the raise rolls the record back. So the boundary that catches the error records it here in a fresh statement. Append-only in practice -- no UPDATE or DELETE is granted to any role. Consumed by app.run_authority_denial_anomaly_sweep, which alerts on a burst rather than on each row, because a single denial is the authorization layer working correctly and alerting on it would be noise.';

comment on column app.authority_denials.denial_kind is
  'rbac | step_up | ip, and whatever a future denial class needs. Deliberately text rather than an enum so a new class is recordable without a migration; the sweep groups by actor, not by kind, so it needs no branch per value.';

create index authority_denials_tenant_actor_idx on app.authority_denials (tenant_id, actor_auth_user_id, occurred_at desc);
create index authority_denials_occurred_idx on app.authority_denials (occurred_at desc);

alter table app.authority_denials enable row level security;

-- `(select auth.uid())`, not a bare call: inside a policy clause the bare form is re-evaluated
-- per row. scripts/security/check-rls-initplan.ts enforces this repository-wide.
create policy authority_denials_select_scoped on app.authority_denials
  for select to authenticated
  using (app.is_support_grant_authority((select auth.uid()), tenant_id));

grant select, insert on app.authority_denials to service_role;

create function app.record_authority_denial(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_denial_kind text,
  p_module_code text default null,
  p_action text default null,
  p_reason text default null,
  p_resource_type text default null,
  p_resource_id uuid default null,
  p_correlation_id uuid default null
)
returns app.authority_denials
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_denial app.authority_denials;
begin
  -- No authority check on the recorder itself, and that is deliberate rather than an oversight:
  -- it is service_role-only (the application boundary, never a browser), it writes a
  -- caller-supplied observation about a call that has ALREADY been refused, and it grants
  -- nothing. Requiring the denied actor's own authority to record their own denial would be
  -- circular -- the whole point is that they did not have it.
  --
  -- What it does refuse is a denial for a tenant that does not exist, because an unbounded
  -- insert keyed on a caller-supplied tenant_id would let a bug fill this table with orphans.
  if not exists (select 1 from app.tenants t where t.id = p_tenant_id) then
    raise exception 'tenant_not_found: %', p_tenant_id using errcode = 'no_data_found';
  end if;

  insert into app.authority_denials
    (tenant_id, actor_auth_user_id, denial_kind, module_code, action, reason, resource_type, resource_id, correlation_id)
  values
    (p_tenant_id, p_actor_auth_user_id, p_denial_kind, p_module_code, p_action, p_reason, p_resource_type, p_resource_id, p_correlation_id)
  returning * into v_denial;

  return v_denial;
end;
$$;

comment on function app.record_authority_denial is
  'ISS-2026-249: records one authorization refusal. Called by the application boundary AFTER it catches the refusal, in a fresh statement, because the refusing transaction has already rolled back and cannot have written anything. service_role-only: this is a server-side observation, never something a browser session reports about itself. It deliberately performs no authority check on the acting identity -- the identity in question is by definition the one that just failed an authority check -- but it does reject an unknown tenant_id, so a bug cannot fill the table with orphaned rows.';

revoke execute on function app.record_authority_denial(uuid, uuid, text, text, text, text, text, uuid, uuid) from public;
grant execute on function app.record_authority_denial(uuid, uuid, text, text, text, text, text, uuid, uuid) to service_role;

create function public.record_authority_denial(
  p_tenant_id uuid, p_actor_auth_user_id uuid, p_denial_kind text,
  p_module_code text default null, p_action text default null, p_reason text default null,
  p_resource_type text default null, p_resource_id uuid default null, p_correlation_id uuid default null
)
returns app.authority_denials
language sql
security definer
set search_path = app, public, pg_temp
as $wrap$
  select * from app.record_authority_denial(p_tenant_id, p_actor_auth_user_id, p_denial_kind, p_module_code, p_action, p_reason, p_resource_type, p_resource_id, p_correlation_id);
$wrap$;

comment on function public.record_authority_denial(uuid, uuid, text, text, text, text, text, uuid, uuid) is
  'RGL-394 Option-2 wrapper: a thin security-definer pass-through to app.record_authority_denial, never a reimplementation. service_role-only, matching the app.* grant set exactly.';

-- `from anon, ...`, not `from public` alone: Supabase's ALTER DEFAULT PRIVILEGES grants anon
-- EXECUTE explicitly at CREATE time and an explicit grant survives a PUBLIC revoke (ISS-2026-309).
revoke execute on function public.record_authority_denial(uuid, uuid, text, text, text, text, text, uuid, uuid) from anon, authenticated, service_role, public;
grant execute on function public.record_authority_denial(uuid, uuid, text, text, text, text, text, uuid, uuid) to service_role;

-- ===========================================================================
-- 2. The threshold sweep -- what turns a flood into one actionable incident
-- ===========================================================================

create function app.run_authority_denial_anomaly_sweep(
  p_tenant_id uuid,
  p_as_of timestamptz,
  p_window_minutes integer,
  p_threshold integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns integer
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_window_minutes integer := greatest(coalesce(p_window_minutes, 60), 1);
  v_threshold integer := greatest(coalesce(p_threshold, 10), 2);
  v_burst record;
  v_raised integer := 0;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if not app.is_support_grant_authority(p_actor_auth_user_id, p_tenant_id) then
    raise exception 'insufficient_authority: identity % may not run the authority-denial sweep for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  for v_burst in
    select d.actor_auth_user_id,
           count(*) as denial_count,
           count(distinct d.module_code) as module_count,
           max(d.occurred_at) as last_denial_at,
           bool_or(d.denial_kind = 'step_up') as includes_step_up
    from app.authority_denials d
    where d.tenant_id = p_tenant_id
      and d.occurred_at > p_as_of - make_interval(mins => v_window_minutes)
      and d.occurred_at <= p_as_of
    group by d.actor_auth_user_id
    having count(*) >= v_threshold
  loop
    perform app.raise_observability_alert(
      p_tenant_id,
      'security',
      'authority_denial_burst',
      format('%s authorization refusals for one identity in %s minutes', v_burst.denial_count, v_window_minutes),
      -- Denials spread across SEVERAL modules read as probing rather than as one person hitting
      -- one wall they do not have access to, so they earn the higher severity. A burst confined
      -- to a single module is far more often a misconfigured role.
      case when v_burst.module_count > 2 then 'high' else 'medium' end,
      format(
        'Identity %s was refused %s times across %s module(s) between %s and %s%s. A single refusal is the authorization layer working; this many in one window is worth a look -- either a role that needs granting, or somebody probing for one.',
        coalesce(v_burst.actor_auth_user_id::text, '(unattributed)'),
        v_burst.denial_count, v_burst.module_count,
        (p_as_of - make_interval(mins => v_window_minutes))::text, p_as_of::text,
        case when v_burst.includes_step_up then ', including at least one MFA step-up refusal' else '' end
      ),
      -- Deduplicated per actor, not per tenant: two different people probing at once must not
      -- collapse into one incident, and the same person continuing must not open a second.
      coalesce(v_burst.actor_auth_user_id::text, 'unattributed')
    );
    v_raised := v_raised + 1;
  end loop;

  return v_raised;
end;
$$;

comment on function app.run_authority_denial_anomaly_sweep is
  'ISS-2026-249: the answer to the "false-positive flood by design" that kept the RBAC-denial producer open. It does not alert per denial -- a denial is the authorization layer working, and one alert each would be pure noise. It alerts per BURST: an identity accumulating p_threshold or more refusals inside p_window_minutes produces exactly one incident, deduplicated on that identity so a second person probing at the same time gets their own and the same person continuing does not get a second. Severity rises to high when the refusals span more than two modules, because breadth reads as probing while a burst inside one module usually means a role that needs granting. Step-up refusals need no separate path: app.evaluate_permission RETURNS reason=mfa_step_up_required rather than raising (ISS-2026-236), so they arrive through the same recorder as any other denial.';

revoke execute on function app.run_authority_denial_anomaly_sweep(uuid, timestamptz, integer, integer, uuid, text) from public;
grant execute on function app.run_authority_denial_anomaly_sweep(uuid, timestamptz, integer, integer, uuid, text) to authenticated, service_role;

create function public.run_authority_denial_anomaly_sweep(
  p_tenant_id uuid, p_as_of timestamptz, p_window_minutes integer,
  p_threshold integer, p_actor_auth_user_id uuid, p_actor_label text
)
returns integer
language sql
security definer
set search_path = app, public, pg_temp
as $wrap$
  select app.run_authority_denial_anomaly_sweep(p_tenant_id, p_as_of, p_window_minutes, p_threshold, p_actor_auth_user_id, p_actor_label);
$wrap$;

comment on function public.run_authority_denial_anomaly_sweep(uuid, timestamptz, integer, integer, uuid, text) is
  'RGL-394 Option-2 wrapper: a thin security-definer pass-through to app.run_authority_denial_anomaly_sweep, never a reimplementation.';

revoke execute on function public.run_authority_denial_anomaly_sweep(uuid, timestamptz, integer, integer, uuid, text) from anon, authenticated, service_role, public;
grant execute on function public.run_authority_denial_anomaly_sweep(uuid, timestamptz, integer, integer, uuid, text) to authenticated, service_role;

-- ===========================================================================
-- 3. Catalogue: the denial sweep plus ISS-2026-313's four
-- ===========================================================================
--
-- All five are Supreme-Admin-only to start (tenant_admin_configurable = false). Vendor
-- compliance, knowledge-base expiry and the security sweep are platform-integrity machinery
-- rather than a tenant's own business rhythm; employee lifecycle activation is arguably the
-- tenant's, but it moves real employment records, so it starts closed and a Supreme Admin can
-- delegate it per tenant without a migration -- which is what the delegation switch is for.

insert into app.scheduled_task_definitions
  (task_code, display_name, description, tenant_admin_configurable, min_interval_minutes, default_interval_minutes, required_params)
values
  ('authority_denial_anomaly_sweep', 'Authorization refusal monitoring',
   'Raises one alert when an identity accumulates an unusual number of authorization refusals in a short window. A single refusal is normal and produces nothing.',
   false, 15, 60, '{window_minutes,threshold}'),
  ('employee_lifecycle_activation', 'Future-dated employee lifecycle activation',
   'Applies employee lifecycle transitions whose effective date has arrived.', false, 60, 1440, '{}'),
  ('kb_article_version_expiry', 'Knowledge-base article expiry',
   'Expires knowledge-base article versions that have passed their review or expiry date.', false, 60, 1440, '{}'),
  ('vendor_compliance_waiver_expiry', 'Vendor compliance waiver expiry',
   'Expires vendor compliance waivers whose validity has ended, so a vendor stops holding a waiver it is no longer entitled to.', false, 60, 1440, '{max_rows}'),
  ('vendor_compliance_status_refresh', 'Vendor compliance status refresh',
   'Recomputes every vendor''s compliance status across the tenant.', false, 60, 1440, '{max_vendors}')
on conflict (task_code) do nothing;

-- ===========================================================================
-- 4. Dispatcher -- five more explicit branches, still never dynamic SQL
-- ===========================================================================

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
    when 'employee_position_activation' then
      perform app.activate_due_employee_position_assignments(p_schedule.tenant_id, v_actor, v_label);
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
    -- ISS-2026-249
    when 'authority_denial_anomaly_sweep' then
      perform app.run_authority_denial_anomaly_sweep(
        p_schedule.tenant_id, p_now,
        (p_schedule.params ->> 'window_minutes')::integer,
        (p_schedule.params ->> 'threshold')::integer,
        v_actor, v_label);
    -- ISS-2026-313
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
  'Internal (app._ prefix, service_role-only): the explicit per-task dispatch, now 16 branches. Deliberately a CASE over enumerated calls rather than dynamic SQL assembled from the row -- task_code is catalogue-controlled today, but a scheduler that EXECUTEs a statement built from a table column is one bad migration away from an injection surface. Every call passes the schedule''s own authorized_by_auth_user_id as the actor, which is what makes a scheduled run attributable to a person. A catalogue row with no dispatch branch raises rather than silently doing nothing. Extended by 20260831100000 with the ISS-2026-249 authority-denial sweep and ISS-2026-313''s four missing sweeps.';

revoke execute on function app._run_scheduled_task_once(app.tenant_scheduled_tasks, timestamptz) from public;
grant execute on function app._run_scheduled_task_once(app.tenant_scheduled_tasks, timestamptz) to service_role;
