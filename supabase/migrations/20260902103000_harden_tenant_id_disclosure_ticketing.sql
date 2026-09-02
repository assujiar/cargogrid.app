-- ISS-2026-146 -- cross-tenant tenant_id disclosure via exception message text.
-- Part 4 of 5 of a representative repository-wide fix pass (Ticketing).
-- See 20260902100000_harden_tenant_id_disclosure_finance.sql for the full rationale
-- (same fix pattern, same repository-wide precedent, applied here to Ticketing).
-- Every function below is CREATE OR REPLACE against its CURRENT, live body -- signatures
-- are unchanged throughout, so grants are unaffected.

CREATE OR REPLACE FUNCTION app.add_sla_calendar_business_hours(p_calendar_version_id uuid, p_day_of_week smallint, p_start_time time without time zone, p_end_time time without time zone, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.sla_calendar_business_hours
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_version app.sla_calendar_versions;
  v_row app.sla_calendar_business_hours;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_version from app.sla_calendar_versions where id = p_calendar_version_id;
  if not found or not app.has_active_tenant_membership(v_version.tenant_id, p_actor_auth_user_id) then
    raise exception 'sla_calendar_version_not_found: %', p_calendar_version_id using errcode = 'no_data_found';
  end if;
  if not app.check_ticket_authority('Edit', v_version.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks TKT:Edit for tenant %', p_actor_auth_user_id, v_version.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_version.status <> 'draft' then
    raise exception 'invalid_state: calendar version % is % not draft', p_calendar_version_id, v_version.status using errcode = 'check_violation';
  end if;

  begin
    insert into app.sla_calendar_business_hours (calendar_version_id, day_of_week, start_time, end_time)
    values (p_calendar_version_id, p_day_of_week, p_start_time, p_end_time)
    returning * into v_row;
  exception
    when unique_violation then
      update app.sla_calendar_business_hours set start_time = p_start_time, end_time = p_end_time
      where calendar_version_id = p_calendar_version_id and day_of_week = p_day_of_week
      returning * into v_row;
  end;

  return v_row;
end;
$function$;

CREATE OR REPLACE FUNCTION app.add_sla_calendar_holiday(p_calendar_version_id uuid, p_holiday_date date, p_name text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.sla_calendar_holidays
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_version app.sla_calendar_versions;
  v_row app.sla_calendar_holidays;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_version from app.sla_calendar_versions where id = p_calendar_version_id;
  if not found or not app.has_active_tenant_membership(v_version.tenant_id, p_actor_auth_user_id) then
    raise exception 'sla_calendar_version_not_found: %', p_calendar_version_id using errcode = 'no_data_found';
  end if;
  if not app.check_ticket_authority('Edit', v_version.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks TKT:Edit for tenant %', p_actor_auth_user_id, v_version.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_version.status <> 'draft' then
    raise exception 'invalid_state: calendar version % is % not draft', p_calendar_version_id, v_version.status using errcode = 'check_violation';
  end if;
  if p_name is null or length(trim(p_name)) = 0 then
    raise exception 'name_required: a non-empty holiday name is required' using errcode = 'check_violation';
  end if;

  begin
    insert into app.sla_calendar_holidays (calendar_version_id, holiday_date, name)
    values (p_calendar_version_id, p_holiday_date, p_name)
    returning * into v_row;
  exception
    when unique_violation then
      select * into v_row from app.sla_calendar_holidays where calendar_version_id = p_calendar_version_id and holiday_date = p_holiday_date;
  end;

  return v_row;
end;
$function$;

CREATE OR REPLACE FUNCTION app.add_ticket_queue_member(p_queue_id uuid, p_employee_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.ticket_queue_members
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_queue app.ticket_queues;
  v_row app.ticket_queue_members;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_queue from app.ticket_queues where id = p_queue_id;
  if not found or not app.has_active_tenant_membership(v_queue.tenant_id, p_actor_auth_user_id) then
    raise exception 'ticket_queue_not_found: %', p_queue_id using errcode = 'no_data_found';
  end if;
  if not app.check_ticket_authority('Edit', v_queue.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks TKT:Edit for tenant %', p_actor_auth_user_id, v_queue.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not exists (select 1 from app.employees e where e.master_record_id = p_employee_id and e.tenant_id = v_queue.tenant_id) then
    raise exception 'employee_not_found: %', p_employee_id using errcode = 'no_data_found';
  end if;

  select * into v_row from app.ticket_queue_members where queue_id = p_queue_id and employee_id = p_employee_id and status = 'active';
  if found then
    return v_row;
  end if;

  begin
    insert into app.ticket_queue_members (tenant_id, queue_id, employee_id, added_by)
    values (v_queue.tenant_id, p_queue_id, p_employee_id, p_actor_label)
    returning * into v_row;
  exception
    when unique_violation then
      select * into v_row from app.ticket_queue_members where queue_id = p_queue_id and employee_id = p_employee_id and status = 'active';
      if not found then
        raise;
      end if;
  end;

  perform app.capture_audit_event(
    v_queue.tenant_id, p_actor_auth_user_id, p_actor_label, 'add_ticket_queue_member',
    'app.ticket_queue_members', v_row.id, 'success', null, null, jsonb_build_object('queue_id', p_queue_id, 'employee_id', p_employee_id)
  );

  return v_row;
end;
$function$;

CREATE OR REPLACE FUNCTION app.create_sla_calendar_version(p_calendar_id uuid, p_timezone text, p_is_24x7 boolean, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.sla_calendar_versions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_calendar app.sla_calendars;
  v_next_version integer;
  v_row app.sla_calendar_versions;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_calendar from app.sla_calendars where id = p_calendar_id for update;
  if not found or not app.has_active_tenant_membership(v_calendar.tenant_id, p_actor_auth_user_id) then
    raise exception 'sla_calendar_not_found: %', p_calendar_id using errcode = 'no_data_found';
  end if;
  if not app.check_ticket_authority('Edit', v_calendar.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks TKT:Edit for tenant %', p_actor_auth_user_id, v_calendar.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_timezone is null or length(trim(p_timezone)) = 0 then
    raise exception 'timezone_required: a non-empty IANA timezone name is required' using errcode = 'check_violation';
  end if;
  begin
    perform (now() at time zone p_timezone);
  exception
    when invalid_parameter_value or others then
      raise exception 'invalid_timezone: % is not a recognized timezone name', p_timezone using errcode = 'check_violation';
  end;

  select coalesce(max(version_number), 0) + 1 into v_next_version from app.sla_calendar_versions where calendar_id = p_calendar_id;

  insert into app.sla_calendar_versions (calendar_id, tenant_id, version_number, timezone, is_24x7, created_by)
  values (p_calendar_id, v_calendar.tenant_id, v_next_version, p_timezone, coalesce(p_is_24x7, false), p_actor_label)
  returning * into v_row;

  perform app.capture_audit_event(
    v_calendar.tenant_id, p_actor_auth_user_id, p_actor_label, 'create_sla_calendar_version',
    'app.sla_calendar_versions', v_row.id, 'success', null, null,
    jsonb_build_object('calendar_id', p_calendar_id, 'version_number', v_next_version, 'timezone', p_timezone, 'is_24x7', v_row.is_24x7)
  );

  return v_row;
end;
$function$;

CREATE OR REPLACE FUNCTION app.create_sla_policy_version(p_policy_id uuid, p_channel text, p_category_id uuid, p_priority text, p_customer_account_id uuid, p_queue_id uuid, p_support_queue_id uuid, p_calendar_id uuid, p_response_target_minutes integer, p_resolution_target_minutes integer, p_precedence_rank integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.sla_policy_versions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_policy app.sla_policies;
  v_next_version integer;
  v_row app.sla_policy_versions;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_policy from app.sla_policies where id = p_policy_id for update;
  if not found or not app.has_active_tenant_membership(v_policy.tenant_id, p_actor_auth_user_id) then
    raise exception 'sla_policy_not_found: %', p_policy_id using errcode = 'no_data_found';
  end if;
  if not app.check_ticket_authority('Edit', v_policy.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks TKT:Edit for tenant %', p_actor_auth_user_id, v_policy.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_channel is null or not (p_channel = any (array['internal', 'customer', 'helpdesk'])) then
    raise exception 'invalid_channel: % is not one of internal/customer/helpdesk', p_channel using errcode = 'check_violation';
  end if;
  if p_priority is not null and not (p_priority = any (array['low', 'normal', 'high', 'urgent'])) then
    raise exception 'invalid_priority: % is not one of low/normal/high/urgent', p_priority using errcode = 'check_violation';
  end if;
  if coalesce(p_response_target_minutes, 0) <= 0 or coalesce(p_resolution_target_minutes, 0) <= 0 then
    raise exception 'invalid_target: response/resolution target minutes must both be positive' using errcode = 'check_violation';
  end if;
  if not exists (select 1 from app.sla_calendars sc where sc.id = p_calendar_id and sc.tenant_id = v_policy.tenant_id) then
    raise exception 'sla_calendar_not_found: % is not a valid calendar for tenant %', p_calendar_id, v_policy.tenant_id using errcode = 'no_data_found';
  end if;
  if p_category_id is not null and not exists (select 1 from app.ticket_categories tc where tc.id = p_category_id and tc.tenant_id = v_policy.tenant_id) then
    raise exception 'ticket_category_not_found: %', p_category_id using errcode = 'no_data_found';
  end if;
  if p_customer_account_id is not null and (p_channel <> 'customer' or not exists (select 1 from app.accounts a where a.id = p_customer_account_id and a.tenant_id = v_policy.tenant_id)) then
    raise exception 'account_not_available: % is not a valid customer-channel account for tenant %', p_customer_account_id, v_policy.tenant_id using errcode = 'no_data_found';
  end if;
  if p_queue_id is not null and (p_channel not in ('internal', 'customer') or not exists (select 1 from app.ticket_queues tq where tq.id = p_queue_id and tq.tenant_id = v_policy.tenant_id)) then
    raise exception 'ticket_queue_not_found: % is not a valid queue for tenant % channel %', p_queue_id, v_policy.tenant_id, p_channel using errcode = 'no_data_found';
  end if;
  if p_support_queue_id is not null and (p_channel <> 'helpdesk' or not exists (select 1 from app.support_queues sq where sq.id = p_support_queue_id)) then
    raise exception 'support_queue_not_available: % is not a valid support queue for channel %', p_support_queue_id, p_channel using errcode = 'no_data_found';
  end if;

  select coalesce(max(version_number), 0) + 1 into v_next_version from app.sla_policy_versions where policy_id = p_policy_id;

  insert into app.sla_policy_versions (
    policy_id, tenant_id, version_number, channel, category_id, priority, customer_account_id, queue_id,
    support_queue_id, calendar_id, response_target_minutes, resolution_target_minutes, precedence_rank, created_by
  ) values (
    p_policy_id, v_policy.tenant_id, v_next_version, p_channel, p_category_id, p_priority, p_customer_account_id, p_queue_id,
    p_support_queue_id, p_calendar_id, p_response_target_minutes, p_resolution_target_minutes, coalesce(p_precedence_rank, 0), p_actor_label
  )
  returning * into v_row;

  perform app.capture_audit_event(
    v_policy.tenant_id, p_actor_auth_user_id, p_actor_label, 'create_sla_policy_version',
    'app.sla_policy_versions', v_row.id, 'success', null, null,
    jsonb_build_object(
      'policy_id', p_policy_id, 'version_number', v_next_version, 'channel', p_channel, 'category_id', p_category_id,
      'priority', p_priority, 'customer_account_id', p_customer_account_id, 'queue_id', p_queue_id,
      'support_queue_id', p_support_queue_id, 'response_target_minutes', p_response_target_minutes,
      'resolution_target_minutes', p_resolution_target_minutes, 'precedence_rank', v_row.precedence_rank
    )
  );

  return v_row;
end;
$function$;

CREATE OR REPLACE FUNCTION app.publish_sla_calendar_version(p_version_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.sla_calendar_versions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_version app.sla_calendar_versions;
  v_calendar app.sla_calendars;
  v_updated app.sla_calendar_versions;
  v_has_hours boolean;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_version from app.sla_calendar_versions where id = p_version_id for update;
  if not found or not app.has_active_tenant_membership(v_version.tenant_id, p_actor_auth_user_id) then
    raise exception 'sla_calendar_version_not_found: %', p_version_id using errcode = 'no_data_found';
  end if;
  -- Lock order (C-21 discipline): parent calendar row, then the version row
  -- already locked above -- this is the ONLY function in this migration that
  -- locks both, so there is no sibling to deadlock against.
  select * into v_calendar from app.sla_calendars where id = v_version.calendar_id for update;

  if not app.check_ticket_authority('Edit', v_version.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks TKT:Edit for tenant %', p_actor_auth_user_id, v_version.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_version.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_version.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_version.status <> 'draft' then
    raise exception 'invalid_state: calendar version % is % not draft', p_version_id, v_version.status using errcode = 'check_violation';
  end if;

  select exists (select 1 from app.sla_calendar_business_hours h where h.calendar_version_id = p_version_id) into v_has_hours;
  if not v_version.is_24x7 and not v_has_hours then
    raise exception 'calendar_incomplete: version % has no business hours and is not is_24x7' , p_version_id using errcode = 'check_violation';
  end if;

  update app.sla_calendar_versions set status = 'superseded'
  where calendar_id = v_version.calendar_id and status = 'published';

  update app.sla_calendar_versions
  set status = 'published', published_at = now(), published_by = p_actor_label
  where id = p_version_id and record_version = p_expected_version
  returning * into v_updated;
  if not found then
    raise exception 'stale_version: concurrent update detected for calendar version %', p_version_id using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_version.tenant_id, p_actor_auth_user_id, p_actor_label, 'publish_sla_calendar_version',
    'app.sla_calendar_versions', p_version_id, 'success', null, null,
    jsonb_build_object('calendar_id', v_version.calendar_id, 'version_number', v_updated.version_number)
  );

  return v_updated;
end;
$function$;

CREATE OR REPLACE FUNCTION app.publish_sla_policy_version(p_version_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.sla_policy_versions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_version app.sla_policy_versions;
  v_policy app.sla_policies;
  v_updated app.sla_policy_versions;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_version from app.sla_policy_versions where id = p_version_id for update;
  if not found or not app.has_active_tenant_membership(v_version.tenant_id, p_actor_auth_user_id) then
    raise exception 'sla_policy_version_not_found: %', p_version_id using errcode = 'no_data_found';
  end if;
  select * into v_policy from app.sla_policies where id = v_version.policy_id for update;

  if not app.check_ticket_authority('Edit', v_version.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks TKT:Edit for tenant %', p_actor_auth_user_id, v_version.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_version.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_version.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_version.status <> 'draft' then
    raise exception 'invalid_state: policy version % is % not draft', p_version_id, v_version.status using errcode = 'check_violation';
  end if;
  if not exists (select 1 from app.sla_calendar_versions cv where cv.calendar_id = v_version.calendar_id and cv.status = 'published') then
    raise exception 'sla_calendar_not_published: calendar % has no published version yet', v_version.calendar_id using errcode = 'check_violation';
  end if;

  -- Supersede this SAME policy's own prior published version (self-found in
  -- this checkpoint's own adversarial pass: without this, publishing a
  -- revised NARROW v2 left NARROW v1 also status=published, and the two
  -- sibling versions of the SAME policy then tied against each other at
  -- resolution time -- a false sla_policy_ambiguous_match neither version
  -- deserved). Mirrors app.publish_sla_calendar_version's own supersede
  -- exactly, scoped to policy_id under the parent-row lock already taken
  -- above. Deliberately does NOT supersede a DIFFERENT policy's version
  -- (decision 3) -- two DIFFERENT sla_policies may legitimately publish
  -- overlapping-scope versions; that ambiguity is caught at RESOLUTION time
  -- (app.resolve_effective_sla_policy_version), never suppressed here.
  update app.sla_policy_versions
  set status = 'superseded'
  where policy_id = v_version.policy_id and status = 'published';

  update app.sla_policy_versions
  set status = 'published', published_at = now(), published_by = p_actor_label
  where id = p_version_id and record_version = p_expected_version
  returning * into v_updated;
  if not found then
    raise exception 'stale_version: concurrent update detected for policy version %', p_version_id using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_version.tenant_id, p_actor_auth_user_id, p_actor_label, 'publish_sla_policy_version',
    'app.sla_policy_versions', p_version_id, 'success', null, null,
    jsonb_build_object('policy_id', v_version.policy_id, 'version_number', v_updated.version_number)
  );

  return v_updated;
end;
$function$;

CREATE OR REPLACE FUNCTION app.recalculate_ticket_sla_clock(p_ticket_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.ticket_sla_clocks
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_clock app.ticket_sla_clocks;
  v_elapsed integer;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select c.* into v_clock from app.ticket_sla_clocks c where c.ticket_id = p_ticket_id for update;
  if not found or not app.has_active_tenant_membership(v_clock.tenant_id, p_actor_auth_user_id) then
    raise exception 'ticket_sla_clock_not_found: no SLA clock for ticket %', p_ticket_id using errcode = 'no_data_found';
  end if;
  if not app.check_ticket_authority('Close', v_clock.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks TKT:Close (required for an authorized SLA correction) for tenant %', p_actor_auth_user_id, v_clock.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_clock.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_clock.record_version
      using errcode = 'serialization_failure';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a reason is required for an authorized SLA correction' using errcode = 'check_violation';
  end if;

  v_elapsed := app.replay_ticket_sla_clock_elapsed(v_clock.id, now());

  insert into app.ticket_sla_clock_events (tenant_id, clock_id, ticket_id, event_type, business_minutes_elapsed, actor_auth_user_id, actor_label, reason)
  values (v_clock.tenant_id, v_clock.id, p_ticket_id, 'recalculated', v_elapsed, p_actor_auth_user_id, p_actor_label, p_reason);

  update app.ticket_sla_clocks set last_evaluated_at = now() where ticket_id = p_ticket_id and record_version = p_expected_version;

  perform app.capture_audit_event(
    v_clock.tenant_id, p_actor_auth_user_id, p_actor_label, 'recalculate_ticket_sla_clock',
    'app.ticket_sla_clocks', v_clock.id, 'success', null, null, app.ticket_sla_clock_audit_projection(v_clock)
  );

  return app.reconcile_ticket_sla_clock(v_clock.id, p_actor_auth_user_id, p_actor_label);
end;
$function$;

