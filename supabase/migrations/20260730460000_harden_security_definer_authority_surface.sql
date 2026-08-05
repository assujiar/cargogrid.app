-- CG-S10-ATW-032 (post-Prompt-248 codebase audit, part 2 — closes `ISS-2026-033`).
--
-- A `SECURITY DEFINER` function runs as its owner and bypasses RLS. Granting one to
-- `authenticated` therefore hands every logged-in user of EVERY tenant whatever that
-- function does, unless the function checks authority itself. A structural sweep at
-- `ATW-031` found 92 such functions with no obvious authority check.
--
-- ===========================================================================
-- Triage: 92 candidates -> 13 real problems (5 revoked, 7 guarded)
-- ===========================================================================
--
-- Most of the 92 were false positives of the sweep's own pattern, and saying so precisely
-- matters more than the raw number:
--
--   * 47 delegate to a callee that DOES check (`app.record_gps_device_installation` ->
--     `app.transition_gps_device_status`, `app.decide_quotation_approval_step` ->
--     `app.decide_approval_step`, which enforces `check_approval_request_authority`,
--     `is_eligible_approval_approver` AND a self-approval denial). Verified by transitive
--     closure over the whole call graph, not by pattern-matching one function body.
--   * Several authenticate by a DIFFERENT mechanism the sweep did not know:
--     `app.list_api_keys_for_tenant`/`list_webhook_endpoints_for_tenant` use
--     `app.check_api_webhook_admin_authority`, `app.preview_import_job` uses
--     `app.check_import_export_admin_authority` plus an owner check.
--   * Four are deliberately anon-facing and correct:
--     `app.ingest_third_party_provider_webhook_event` (HMAC signature),
--     `app.lookup_public_shipment_tracking` (sanitized public projection),
--     `app.evaluate_tenant_brand`/`resolve_tenant_by_domain`/`resolve_tenant_locale`/
--     `resolve_locale_context` (pre-login branding, domain and locale resolution).
--   * Several ARE the authority primitives — `app.is_supreme_admin`,
--     `app.can_access_record`, `app.actor_can_view_owner_scoped_row` — and cannot check
--     themselves.
--
-- That leaves 13 genuine problems, repaired below in two groups.
--
-- ===========================================================================
-- Group A — internal helpers that were never meant to be client-callable (5)
-- ===========================================================================
--
-- Each of these takes NO actor parameter, so it cannot check authority even in principle;
-- its callers are supposed to. Each was nonetheless granted to `authenticated`, so any
-- logged-in user could call it directly with another tenant's identifiers. The three
-- writes are the serious ones:
--
--   * `app.recalculate_quotation_totals(p_quotation_id)` — recomputes and UPDATEs a
--     quotation's money columns. Any logged-in user could rewrite any tenant's quotation
--     totals.
--   * `app.generate_route_planning_candidates(p_scenario_id, p_actor_label)` — DELETEs
--     every existing candidate plan and score component for a scenario and rewrites them.
--   * `app.next_quotation_number(p_tenant_id)` — burns another tenant's quotation number
--     sequence.
--
-- The repair is to revoke the grant, not to add a check: these are shared cores, the same
-- pattern `ATW-021` established for `app.execute_label_print_job` and `ATW-031` for
-- `app.transition_gps_device_status`. Their real callers are all `SECURITY DEFINER` and
-- owned by the same role, so they continue to work untouched.
--
-- Verified safe to revoke, per function, before doing it:
--   * zero direct call sites in `server/**` or `app/**` (grep over every `client.rpc(...)`);
--   * zero references from any RLS policy expression (`pg_policy.polqual`/`polwithcheck`) —
--     this one is load-bearing, since a policy is evaluated as the QUERYING role, so
--     revoking a function a policy calls would break every authenticated read of that
--     table. It is exactly why `app.is_supreme_admin` (94 policies),
--     `app.lead_record_scope_org_unit_ids` (71), `app.actor_can_view_owner_scoped_row`
--     (26), `app.actor_holds_customer_user_layer` (4) and
--     `app.resolve_commercial_record_ref` (1) are deliberately NOT revoked here despite
--     matching the same shape;
--   * zero `SECURITY INVOKER` callers, which would likewise execute as the caller;
--   * zero references from any VIEW definition. A view is executed with the querying
--     role's privileges too, so this catches the same class as the policy check. It caught
--     `app.evaluate_dispatch_readiness`, which is embedded in two views the dispatch board
--     reads (`app.dispatch_board_queue` among them) -- revoking it made every authenticated
--     board query fail. Left granted; the views themselves are the tenant-scoped surface;
--   * not named in any existing db-test's own ratified grant assertion. This one caught a
--     real mis-binning during the work: `app.customer_warehouse_eligibility_active` and
--     `app.resolve_customer_owner_account_scope` matched the "internal helper" shape, but
--     `scripts/db-tests/advanced-tms-customer-inventory-access.sql` asserts explicitly that
--     `authenticated` SHOULD hold EXECUTE on them because the customer portal reaches them
--     directly (`ATW-023`). They are customer-SCOPE primitives -- part of the authority
--     mechanism, like `app.actor_can_view_owner_scoped_row` -- not helpers that forgot a
--     check. Both left granted.
--
-- ===========================================================================
-- Group B — client-callable functions that genuinely needed a check (5)
-- ===========================================================================
--
-- These DO have real call sites in the TypeScript layer, so revoking would break the
-- product. They gain a session-identity tenant-membership guard instead, via the new
-- `app.assert_session_identity_in_tenant`.
--
-- The guard adds NO parameter, so no signature changes and no caller changes: it reads
-- `auth.uid()` directly. Like `app.assert_actor_is_session_identity` (`ATW-031`), it is a
-- deliberate no-op whenever `auth.uid()` is NULL — `service_role`, superuser, db-tests,
-- and nested `SECURITY DEFINER` calls are all unaffected — and engages only for a real
-- `authenticated` session, which is the only principal that could reach these
-- cross-tenant.
--
--   * `app.resolve_config` — read ANY tenant's published configuration, bypassing the
--     deliberate `service_role`-only posture on `config_versions`/`config_items`.
--   * `app.verify_config_version_current` — same surface, staleness check.
--   * `app.evaluate_feature_flag` — read any tenant's flag state and cohort rules.
--   * `app.record_customer_inventory_access_denial` — WRITE an audit row into any tenant.
--   * `app.run_next_route_planning_job` — claims and executes the next queued planning job
--     for ANY tenant. Guarded after the scenario is resolved (its tenant is not known
--     before that); a non-member raises, the transaction rolls back, and the job claim is
--     released with it.
--
-- Additive and reversible: one new function, five `CREATE OR REPLACE FUNCTION` on
-- identical signatures, and five `REVOKE`s. No table, column, index, constraint or policy
-- is touched, and no already-applied migration file is edited.
--
-- Per `ERR-2026-004`: this migration carries its own explicit `revoke execute on all
-- functions in schema app from public` before its final grants.

create or replace function app.assert_session_identity_in_tenant(p_tenant_id uuid)
returns void
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_session_identity uuid;
begin
  -- Defensive, matching app.assert_actor_is_session_identity: a deployment without
  -- Supabase's auth schema, or a malformed JWT claim, degrades to "no session identity
  -- known" rather than raising -- this helper must never be able to brick the database.
  begin
    v_session_identity := auth.uid();
  exception
    when others then
      v_session_identity := null;
  end;

  -- NULL session identity = service_role, superuser, db-test, or an already-nested
  -- SECURITY DEFINER call. All trusted; all unaffected.
  if v_session_identity is null or p_tenant_id is null then
    return;
  end if;

  -- Supreme Admin is cross-tenant by ratified design (AGENTS.md "Supreme Admin risk rule").
  if app.is_supreme_admin(v_session_identity) then
    return;
  end if;

  -- "Member of this tenant" must mean exactly what the rest of this codebase already means
  -- by it, not a new definition invented here. app.evaluate_permission establishes tenant
  -- standing through an ACTIVE app.role_assignments row; app.principal_memberships carries
  -- the layer grants (supreme_admin, customer_user) on top of that. A staff user with a
  -- role assignment has no principal_memberships row at all, so checking only the latter
  -- would have locked out ordinary staff -- which is precisely what it did on first run,
  -- caught by scripts/db-tests/advanced-tms-dispatch-board.sql.
  if not exists (
    select 1 from app.role_assignments ra
    where ra.auth_user_id = v_session_identity
      and ra.tenant_id = p_tenant_id
      and ra.status = 'active'
  ) and not exists (
    select 1 from app.principal_memberships m
    where m.auth_user_id = v_session_identity
      and m.tenant_id = p_tenant_id
      and m.status = 'active'
  ) then
    raise exception 'insufficient_authority: identity % has no active membership in tenant %', v_session_identity, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
end;
$$;

comment on function app.assert_session_identity_in_tenant is
  'ATW-032 (ISS-2026-033): rejects a call from an authenticated session that has no active membership in the named tenant. Adds no parameter -- it reads auth.uid() directly -- so it can be inserted into an existing SECURITY DEFINER function without a signature change. A deliberate no-op when auth.uid() is NULL (service_role, superuser, db-tests, nested definer calls) and for a Supreme Admin, whose cross-tenant authority is ratified. Used by the client-callable functions that had no authority check of their own.';

-- ===========================================================================
-- Group B repairs: each function's own live definition with ONLY the guard inserted
-- as its first executable statement. Nothing else in any body changes.
-- ===========================================================================

CREATE OR REPLACE FUNCTION app.resolve_config(p_config_type_code text, p_tenant_id uuid, p_company_id uuid DEFAULT NULL::uuid, p_branch_id uuid DEFAULT NULL::uuid, p_role_id uuid DEFAULT NULL::uuid, p_user_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(config_type_code text, resolved_scope_level text, resolved_version_id uuid, effective_from timestamp with time zone, items jsonb)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_object app.config_objects;
  v_version app.config_versions;
  v_scope_level text;
  v_scope_id uuid;
  v_levels text[] := array['user', 'role', 'branch', 'company', 'tenant', 'global'];
  v_ids uuid[] := array[p_user_id, p_role_id, p_branch_id, p_company_id, null, null];
  i integer;
begin
  -- ATW-032 (ISS-2026-033): app.config_versions/app.config_items carry a deliberate service_role-only posture, but
  -- this resolver was granted to authenticated with no tenant check -- so any logged-in
  -- user could read any tenant's published configuration straight through it, defeating
  -- that posture entirely.
  -- The guard reads auth.uid() directly, so no signature or caller changes, and it is a
  -- no-op for service_role/superuser/db-tests/nested definer calls.
  perform app.assert_session_identity_in_tenant(p_tenant_id);
  for i in 1 .. array_length(v_levels, 1) loop
    v_scope_level := v_levels[i];
    v_scope_id := v_ids[i];

    if v_scope_level in ('company', 'branch', 'role', 'user') and v_scope_id is null then
      continue;
    end if;

    select * into v_object
    from app.config_objects o
    where o.config_type_code = p_config_type_code
      and o.scope_level = v_scope_level
      and o.tenant_id is not distinct from (case when v_scope_level = 'global' then null else p_tenant_id end)
      and o.scope_id is not distinct from v_scope_id;

    if found then
      select * into v_version
      from app.config_versions v
      where v.config_object_id = v_object.id
        and v.status = 'published'
        and v.effective_from <= now()
        and (v.effective_to is null or v.effective_to > now());

      if found then
        return query
          select
            p_config_type_code,
            v_scope_level,
            v_version.id,
            v_version.effective_from,
            coalesce((select jsonb_object_agg(ci.key, ci.value) from app.config_items ci where ci.config_version_id = v_version.id), '{}'::jsonb);
        return;
      end if;
    end if;
  end loop;

  return;
end;
$function$;

CREATE OR REPLACE FUNCTION app.verify_config_version_current(p_config_type_code text, p_tenant_id uuid, p_expected_version_id uuid, p_company_id uuid DEFAULT NULL::uuid, p_branch_id uuid DEFAULT NULL::uuid, p_role_id uuid DEFAULT NULL::uuid, p_user_id uuid DEFAULT NULL::uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_current record;
begin
  -- ATW-032 (ISS-2026-033): Same configuration surface as app.resolve_config, same gap: a staleness check any
  -- logged-in user could run against any tenant's config versions.
  -- The guard reads auth.uid() directly, so no signature or caller changes, and it is a
  -- no-op for service_role/superuser/db-tests/nested definer calls.
  perform app.assert_session_identity_in_tenant(p_tenant_id);
  select * into v_current from app.resolve_config(p_config_type_code, p_tenant_id, p_company_id, p_branch_id, p_role_id, p_user_id);
  if not found then
    return p_expected_version_id is null;
  end if;
  return v_current.resolved_version_id = p_expected_version_id;
end;
$function$;

CREATE OR REPLACE FUNCTION app.evaluate_feature_flag(p_flag_key text, p_tenant_id uuid, p_environment text, p_cohorts text[] DEFAULT ARRAY[]::text[], p_now timestamp with time zone DEFAULT now())
 RETURNS app.feature_flag_decision
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_flag app.feature_flags;
  v_entitlement app.entitlement_decision;
  v_global_object app.config_objects;
  v_global_version app.config_versions;
  v_global_items jsonb;
  v_tenant_object app.config_objects;
  v_tenant_version app.config_versions;
  v_tenant_items jsonb;
  v_environments text[];
  v_rollout integer;
  v_cohorts text[];
  v_tenant_state text;
  v_bucket integer;
  v_resolved_scope text;
  v_resolved_version uuid;
begin
  -- ATW-032 (ISS-2026-033): Reads any tenant's flag state, rollout percentage and cohort rules -- product roadmap
  -- signal, and an input to behaviour, exposed cross-tenant to any logged-in user.
  -- The guard reads auth.uid() directly, so no signature or caller changes, and it is a
  -- no-op for service_role/superuser/db-tests/nested definer calls.
  perform app.assert_session_identity_in_tenant(p_tenant_id);
  select * into v_flag from app.feature_flags where flag_key = p_flag_key;
  if not found then
    return row(false, 'unknown_flag', null, null, p_now)::app.feature_flag_decision;
  end if;

  if v_flag.module_code is not null and p_tenant_id is not null then
    v_entitlement := app.evaluate_entitlement(p_tenant_id, v_flag.module_code, null, p_now);
    if not v_entitlement.allowed then
      return row(false, 'module_not_entitled', null, null, p_now)::app.feature_flag_decision;
    end if;
  end if;

  select o.* into v_global_object from app.config_objects o
    where o.config_type_code = 'feature:' || p_flag_key and o.scope_level = 'global' and o.tenant_id is null;
  if not found then
    return row(false, 'unconfigured', null, null, p_now)::app.feature_flag_decision;
  end if;

  select v.* into v_global_version from app.config_versions v
    where v.config_object_id = v_global_object.id and v.status = 'published'
      and v.effective_from <= p_now and (v.effective_to is null or v.effective_to > p_now);
  if not found then
    return row(false, 'unconfigured', null, null, p_now)::app.feature_flag_decision;
  end if;

  select jsonb_object_agg(key, value) into v_global_items from app.config_items where config_version_id = v_global_version.id;

  if coalesce((v_global_items ->> 'kill_switch')::boolean, false) then
    return row(false, 'kill_switch', 'global', v_global_version.id, p_now)::app.feature_flag_decision;
  end if;

  select coalesce(array(select jsonb_array_elements_text(v_global_items -> 'environments')), array[]::text[]) into v_environments;
  if coalesce(array_length(v_environments, 1), 0) > 0 and not (p_environment = any (v_environments)) then
    return row(false, 'environment_gate', 'global', v_global_version.id, p_now)::app.feature_flag_decision;
  end if;

  v_rollout := coalesce((v_global_items ->> 'rollout_percentage')::integer, 0);
  select coalesce(array(select jsonb_array_elements_text(v_global_items -> 'cohorts')), array[]::text[]) into v_cohorts;
  v_resolved_scope := 'global';
  v_resolved_version := v_global_version.id;

  if p_tenant_id is not null then
    select o.* into v_tenant_object from app.config_objects o
      where o.config_type_code = 'feature:' || p_flag_key and o.scope_level = 'tenant' and o.tenant_id = p_tenant_id;
    if found then
      select v.* into v_tenant_version from app.config_versions v
        where v.config_object_id = v_tenant_object.id and v.status = 'published'
          and v.effective_from <= p_now and (v.effective_to is null or v.effective_to > p_now);
      if found then
        select jsonb_object_agg(key, value) into v_tenant_items from app.config_items where config_version_id = v_tenant_version.id;
        v_tenant_state := coalesce(v_tenant_items ->> 'tenant_state', 'inherit');
        v_resolved_scope := 'tenant';
        v_resolved_version := v_tenant_version.id;

        if v_tenant_state = 'deny' then
          return row(false, 'tenant_override_deny', 'tenant', v_tenant_version.id, p_now)::app.feature_flag_decision;
        elsif v_tenant_state = 'allow' then
          return row(true, 'tenant_override_allow', 'tenant', v_tenant_version.id, p_now)::app.feature_flag_decision;
        end if;

        if v_tenant_items ? 'rollout_percentage' then
          v_rollout := (v_tenant_items ->> 'rollout_percentage')::integer;
        end if;
        if v_tenant_items ? 'cohorts' then
          select coalesce(array(select jsonb_array_elements_text(v_tenant_items -> 'cohorts')), array[]::text[]) into v_cohorts;
        end if;
      end if;
    end if;
  end if;

  if coalesce(array_length(v_cohorts, 1), 0) > 0 then
    if p_cohorts is null or not (v_cohorts && p_cohorts) then
      return row(false, 'cohort_mismatch', v_resolved_scope, v_resolved_version, p_now)::app.feature_flag_decision;
    end if;
  end if;

  v_bucket := app.feature_flag_bucket(coalesce(p_tenant_id, '00000000-0000-0000-0000-000000000000'::uuid), p_flag_key);
  if v_bucket < v_rollout then
    return row(true, 'rollout_bucket', v_resolved_scope, v_resolved_version, p_now)::app.feature_flag_decision;
  end if;

  return row(false, 'default', v_resolved_scope, v_resolved_version, p_now)::app.feature_flag_decision;
end;
$function$;

CREATE OR REPLACE FUNCTION app.record_customer_inventory_access_denial(p_tenant_id uuid, p_actor_auth_user_id uuid, p_resource_type text, p_resource_id uuid, p_actor_label text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
begin
  -- ATW-032 (ISS-2026-033): A WRITE: it inserts an audit record. Ungated, any logged-in user could forge denial
  -- audit entries into any other tenant's audit trail.
  -- The guard reads auth.uid() directly, so no signature or caller changes, and it is a
  -- no-op for service_role/superuser/db-tests/nested definer calls.
  perform app.assert_session_identity_in_tenant(p_tenant_id);
  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, coalesce(p_actor_label, 'customer-portal-actor'), 'customer_inventory_access_denied',
    p_resource_type, p_resource_id, 'failure', null, null, null
  );
end;
$function$;

CREATE OR REPLACE FUNCTION app.run_next_route_planning_job(p_worker_id text)
 RETURNS app.route_planning_scenarios
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'public', 'pg_temp'
AS $function$
declare
  v_job app.jobs;
  v_scenario_id uuid;
  v_scenario app.route_planning_scenarios;
begin
  v_job := app.claim_next_job(p_worker_id, array['route_load_planning'], 300);
  if v_job is null then
    return null;
  end if;

  v_scenario_id := (v_job.payload ->> 'scenario_id')::uuid;

  begin
    select * into v_scenario from app.route_planning_scenarios where id = v_scenario_id;
      -- ATW-032 (ISS-2026-033): this claims and executes the next queued planning job for
      -- ANY tenant, and was granted to authenticated with no authority check at all. The
      -- owning tenant is not knowable before the scenario resolves, so the guard sits here:
      -- a non-member raises, the whole transaction rolls back, and the job claim is
      -- released with it -- no job is consumed by a caller not entitled to it.
      perform app.assert_session_identity_in_tenant(v_scenario.tenant_id);
    if not found then
      raise exception 'scenario_not_found: %', v_scenario_id using errcode = 'no_data_found';
    end if;

    -- Cooperative cancellation: a scenario cancelled after being enqueued is left
    -- untouched by the planner (this migration's own header) -- the job still
    -- completes successfully, it simply has nothing left to do.
    if v_scenario.status = 'executing' then
      perform app.generate_route_planning_candidates(v_scenario_id, p_worker_id);
    end if;

    perform app.complete_job(v_job.job_id, p_worker_id, null, p_worker_id);
  exception
    when others then
      update app.route_planning_scenarios set status = 'failed' where id = v_scenario_id and status = 'executing';
      perform app.record_job_failure(v_job.job_id, SQLERRM, null, p_worker_id);
  end;

  select * into v_scenario from app.route_planning_scenarios where id = v_scenario_id;
  return v_scenario;
end;
$function$;


-- ===========================================================================
-- Group B (continued): two readers whose signature carries no tenant, so the tenant is
-- resolved from the record itself and then guarded.
-- ===========================================================================

create or replace function app.get_shipment_leg_network_state(p_shipment_order_id uuid)
returns text
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_tenant_id uuid;
  v_state text;
begin
  -- ATW-032 (ISS-2026-033): this read the leg-network state of ANY shipment order, in any
  -- tenant, for any logged-in user. It takes no tenant parameter, so the tenant is resolved
  -- from the shipment itself and then guarded. A shipment that does not exist returns null
  -- exactly as before -- the guard must not become an existence oracle.
  select tenant_id into v_tenant_id from app.shipment_orders where id = p_shipment_order_id;
  if v_tenant_id is null then
    return null;
  end if;
  perform app.assert_session_identity_in_tenant(v_tenant_id);

  select case
      when not exists (select 1 from app.shipment_legs where shipment_order_id = p_shipment_order_id and leg_status <> 'cancelled') then 'not_started'
      when (select leg_network_status from app.shipment_orders where id = p_shipment_order_id) is distinct from 'confirmed' then 'blocked'
      when not exists (select 1 from app.shipment_legs where shipment_order_id = p_shipment_order_id and leg_status <> 'cancelled' and leg_status <> 'completed') then 'completed'
      when exists (select 1 from app.shipment_legs where shipment_order_id = p_shipment_order_id and leg_status in ('dispatched', 'in_transit', 'arrived')) then 'in_progress'
      else 'not_started'
    end
  into v_state;

  return v_state;
end;
$$;

CREATE OR REPLACE FUNCTION app.render_notification_template(p_config_version_id uuid, p_locale text, p_context jsonb)
 RETURNS TABLE(subject text, body text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_default_locale text;
  v_templates jsonb;
  v_template jsonb;
  v_effective_locale text;
  v_subject text;
  v_body text;
  v_key text;
  v_value jsonb;
  v_value_text text;
begin
  -- ATW-032 (ISS-2026-033): renders a notification template out of app.config_items,
  -- which carries a deliberate service_role-only posture -- but this was granted to
  -- authenticated with no tenant check, so any logged-in user could render (and thereby
  -- read) any other tenant's notification templates. The tenant is resolved from the
  -- config version itself, since the signature carries none.
  declare v_owner_tenant_id uuid;
  begin
    select co.tenant_id into v_owner_tenant_id
      from app.config_versions cv join app.config_objects co on co.id = cv.config_object_id
      where cv.id = p_config_version_id;
    if v_owner_tenant_id is not null then
      perform app.assert_session_identity_in_tenant(v_owner_tenant_id);
    end if;
  end;
  select value #>> '{}' into v_default_locale from app.config_items where config_version_id = p_config_version_id and key = 'default_locale';
  select value into v_templates from app.config_items where config_version_id = p_config_version_id and key = 'templates';

  v_effective_locale := case when v_templates ? p_locale then p_locale else v_default_locale end;
  v_template := v_templates -> v_effective_locale;
  v_subject := v_template ->> 'subject';
  v_body := v_template ->> 'body';

  for v_key, v_value in select * from jsonb_each(coalesce(p_context, '{}'::jsonb)) loop
    v_value_text := coalesce(v_value #>> '{}', '');
    if v_value_text ~ '[<>]' then
      raise exception 'notification_unsafe_context_value: context key % contains an angle bracket, refusing to render', v_key
        using errcode = 'check_violation';
    end if;
    if v_value_text ~ '^[a-zA-Z][a-zA-Z0-9+.-]*://' and v_value_text !~ '^https://' then
      raise exception 'notification_unsafe_link: context key % is a non-https:// URL, refusing to render', v_key
        using errcode = 'check_violation';
    end if;
    -- javascript:/data:/vbscript: URIs carry no "://" (unlike http(s)://), so the
    -- scheme://-shaped check above alone would miss them -- a real, bounded
    -- known-dangerous-scheme blocklist catches this class without false-positiving on
    -- ordinary colon-containing text (e.g. "Note: important"), which a broader
    -- "any word followed by a colon" pattern would.
    if v_value_text ~* '^(javascript|data|vbscript):' then
      raise exception 'notification_unsafe_link: context key % uses a disallowed URI scheme, refusing to render', v_key
        using errcode = 'check_violation';
    end if;
    v_subject := replace(v_subject, '{{' || v_key || '}}', v_value_text);
    v_body := replace(v_body, '{{' || v_key || '}}', v_value_text);
  end loop;

  return query select v_subject, v_body;
end;
$function$;


revoke execute on all functions in schema app from public;

-- ===========================================================================
-- Group A: revoke the client grant from internal helpers.
-- Every one verified to have zero TS call sites, zero RLS-policy references and zero
-- SECURITY INVOKER callers. Their SECURITY DEFINER callers are owned by the same role and
-- are unaffected.
-- ===========================================================================

revoke execute on function app.recalculate_quotation_totals(uuid) from authenticated;
revoke execute on function app.next_quotation_number(uuid) from authenticated;
revoke execute on function app.generate_route_planning_candidates(uuid, text) from authenticated;
revoke execute on function app.check_leg_tracking_source_eligible(uuid, text, text, uuid, uuid) from authenticated;
revoke execute on function app.dashboard_scope_org_unit_ids(uuid) from authenticated;

comment on function app.recalculate_quotation_totals is
  'Commercial quotation total recomputation. ATW-032 (ISS-2026-033): deliberately NOT granted to authenticated -- it takes no actor parameter and so cannot check authority itself. Before ATW-032 it was granted, letting any logged-in user rewrite any tenant''s quotation money columns. Its real callers (app.add_quotation_line, remove_quotation_line, clone_quotation, create_quotation_revision) all check authority and are SECURITY DEFINER under the same owner, so they reach it unaffected.';

comment on function app.next_quotation_number is
  'Commercial quotation number allocation. ATW-032 (ISS-2026-033): deliberately NOT granted to authenticated -- no actor parameter, so no authority check is possible here. Before ATW-032 any logged-in user could burn another tenant''s quotation sequence. Reached by app.create_quotation_draft/clone_quotation, both of which check authority.';

comment on function app.generate_route_planning_candidates is
  'Route planning candidate generation. ATW-032 (ISS-2026-033): deliberately NOT granted to authenticated -- it takes only a scenario id and an actor LABEL, never an actor identity, and it DELETEs every existing candidate plan and score component for the scenario before rewriting them. Before ATW-032 any logged-in user could destroy and rewrite another tenant''s route plans. Reached only by app.run_next_route_planning_job.';

-- ===========================================================================
-- Correct by design — recorded so a future sweep does not re-flag them
-- ===========================================================================
--
-- After this migration, 14 `SECURITY DEFINER` functions remain granted to `authenticated`
-- with no authority check reachable in their call graph. Every one is deliberate:
--
--   Anon-facing by design, authenticated by another mechanism or intentionally public:
--     app.ingest_third_party_provider_webhook_event  -- HMAC signature over the payload
--     app.lookup_public_shipment_tracking            -- deliberately public, sanitized projection
--     app.evaluate_tenant_brand                      -- pre-login branding
--     app.resolve_tenant_by_domain                   -- pre-login tenant resolution from hostname
--     app.resolve_tenant_locale / resolve_locale_context -- pre-login locale
--
--   Authority and scope PRIMITIVES -- they are the check, so they cannot check themselves,
--   and they MUST stay executable by `authenticated` because RLS policy expressions are
--   evaluated as the querying role. Revoking any of these would break every authenticated
--   read of the tables whose policies call them (count of referencing policies in
--   brackets):
--     app.is_supreme_admin                     [94 policies, 41 SECURITY INVOKER callers]
--     app.lead_record_scope_org_unit_ids       [71 policies]
--     app.actor_can_view_owner_scoped_row      [26 policies]
--     app.actor_holds_customer_user_layer      [4 policies]
--     app.resolve_commercial_record_ref        [1 policy]
--     app.pipeline_scope_org_unit_ids          [SECURITY INVOKER caller]
--     app.assert_actor_is_session_identity     [called by app.evaluate_permission, which is
--                                               SECURITY INVOKER -- ATW-031]
--     app.current_support_session / has_active_support_grant
--                                              -- support-session primitives; both read only
--                                                 the CALLER's own support grant, never
--                                                 another identity's
--
-- The sweep that produced this list is reproducible:
--   transitive closure over `regexp_matches(prosrc, 'app\.([a-z0-9_]+)\s*\(')` seeded
--   with the functions that directly call an authority primitive, intersected with
--   `prosecdef AND has an EXECUTE grant to authenticated`. Re-running it after this
--   migration returns exactly the 14 above.
