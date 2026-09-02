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
-- Part 1 of 4: Ticketing -- ticket messages, category visibility, the knowledge base,
-- routing-rule versions and escalation policy versions.
--
-- 14 functions in this part.

-- app.add_ticket_escalation_level -- live definition from 20260731160000_create_ticket_escalation.sql
create or replace function app.add_ticket_escalation_level(
  p_policy_version_id uuid, p_level_number integer, p_trigger_type text, p_threshold_minutes integer, p_min_priority text,
  p_target_type text, p_target_queue_id uuid, p_target_employee_id uuid, p_action_notify boolean, p_action_reassign boolean,
  p_cooldown_minutes integer, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.ticket_escalation_levels
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_version app.ticket_escalation_policy_versions;
  v_row app.ticket_escalation_levels;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_version from app.ticket_escalation_policy_versions where id = p_policy_version_id for update;
  if not found or not app.has_active_tenant_membership(v_version.tenant_id, p_actor_auth_user_id) then
    raise exception 'ticket_escalation_policy_version_not_found: %', p_policy_version_id using errcode = 'no_data_found';
  end if;
  if not app.check_ticket_authority('Edit', v_version.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks TKT:Edit for tenant %', p_actor_auth_user_id, v_version.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_version.status <> 'draft' then
    raise exception 'invalid_state: policy version % is % not draft', p_policy_version_id, v_version.status using errcode = 'check_violation';
  end if;
  if p_level_number is null or p_level_number <= 0 then
    raise exception 'invalid_level_number: level_number must be a positive integer' using errcode = 'check_violation';
  end if;
  if not (p_trigger_type = any (array['sla_response_warning', 'sla_response_breach', 'sla_resolution_warning', 'sla_resolution_breach', 'priority_threshold', 'inactivity', 'assignment_failure'])) then
    raise exception 'invalid_trigger_type: % is not a recognized escalation trigger type', p_trigger_type using errcode = 'check_violation';
  end if;
  if p_trigger_type in ('inactivity', 'assignment_failure') and coalesce(p_threshold_minutes, 0) <= 0 then
    raise exception 'threshold_minutes_required: a positive threshold_minutes is required for trigger_type %', p_trigger_type using errcode = 'check_violation';
  end if;
  if p_trigger_type not in ('inactivity', 'assignment_failure') and p_threshold_minutes is not null then
    raise exception 'threshold_minutes_not_applicable: threshold_minutes only applies to inactivity/assignment_failure' using errcode = 'check_violation';
  end if;
  if p_trigger_type = 'priority_threshold' and p_min_priority is null then
    raise exception 'min_priority_required: priority_threshold requires a min_priority' using errcode = 'check_violation';
  end if;
  if p_min_priority is not null and not (p_min_priority = any (array['low', 'normal', 'high', 'urgent'])) then
    raise exception 'invalid_priority: % is not one of low/normal/high/urgent', p_min_priority using errcode = 'check_violation';
  end if;
  if not (p_target_type = any (array['queue', 'employee'])) then
    raise exception 'invalid_target_type: % is not one of queue/employee (decision 2 -- no role/team target)', p_target_type using errcode = 'check_violation';
  end if;
  if p_target_type = 'queue' then
    if p_target_queue_id is null or p_target_employee_id is not null then
      raise exception 'invalid_target: target_type=queue requires target_queue_id only' using errcode = 'check_violation';
    end if;
    if not exists (select 1 from app.ticket_queues q where q.id = p_target_queue_id and q.tenant_id = v_version.tenant_id) then
      raise exception 'ticket_queue_not_found: %', p_target_queue_id using errcode = 'no_data_found';
    end if;
  else
    if p_target_employee_id is null or p_target_queue_id is not null then
      raise exception 'invalid_target: target_type=employee requires target_employee_id only' using errcode = 'check_violation';
    end if;
    if not exists (select 1 from app.employees e where e.master_record_id = p_target_employee_id and e.tenant_id = v_version.tenant_id) then
      raise exception 'employee_not_found: %', p_target_employee_id using errcode = 'no_data_found';
    end if;
  end if;
  if coalesce(p_action_reassign, false) and p_target_type <> 'employee' then
    raise exception 'invalid_target: reassignment requires an employee target' using errcode = 'check_violation';
  end if;
  if coalesce(p_cooldown_minutes, 60) <= 0 then
    raise exception 'invalid_cooldown: cooldown_minutes must be positive' using errcode = 'check_violation';
  end if;

  begin
    insert into app.ticket_escalation_levels (
      policy_version_id, tenant_id, level_number, trigger_type, threshold_minutes, min_priority,
      target_type, target_queue_id, target_employee_id, action_notify, action_reassign, cooldown_minutes, created_by
    ) values (
      p_policy_version_id, v_version.tenant_id, p_level_number, p_trigger_type, p_threshold_minutes, p_min_priority,
      p_target_type, p_target_queue_id, p_target_employee_id, coalesce(p_action_notify, true), coalesce(p_action_reassign, false), coalesce(p_cooldown_minutes, 60), p_actor_label
    )
    returning * into v_row;
  exception
    when unique_violation then
      update app.ticket_escalation_levels set
        trigger_type = p_trigger_type, threshold_minutes = p_threshold_minutes, min_priority = p_min_priority,
        target_type = p_target_type, target_queue_id = p_target_queue_id, target_employee_id = p_target_employee_id,
        action_notify = coalesce(p_action_notify, true), action_reassign = coalesce(p_action_reassign, false),
        cooldown_minutes = coalesce(p_cooldown_minutes, 60), updated_at = now()
      where policy_version_id = p_policy_version_id and level_number = p_level_number
      returning * into v_row;
  end;

  return v_row;
end;
$$;

-- app.archive_kb_article_version -- live definition from 20260731130000_create_ticket_knowledge_base.sql
create or replace function app.archive_kb_article_version(p_version_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.kb_article_versions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_version app.kb_article_versions;
  v_updated app.kb_article_versions;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_version from app.kb_article_versions where id = p_version_id for update;
  if not found or not app.has_active_tenant_membership(v_version.tenant_id, p_actor_auth_user_id) then
    raise exception 'kb_article_version_not_found: %', p_version_id using errcode = 'no_data_found';
  end if;
  if not app.check_ticket_authority('Edit', v_version.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks TKT:Edit for tenant %', p_actor_auth_user_id, v_version.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_version.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_version.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_version.status = 'archived' then
    raise exception 'invalid_state: article version % is already archived', p_version_id using errcode = 'check_violation';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a reason is required to archive an article version' using errcode = 'check_violation';
  end if;

  update app.kb_article_versions set status = 'archived', archived_at = now(), archived_by = p_actor_label, archived_reason = p_reason
  where id = p_version_id and record_version = p_expected_version
  returning * into v_updated;
  if not found then
    raise exception 'stale_version: concurrent update detected for article version %', p_version_id using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_version.tenant_id, p_actor_auth_user_id, p_actor_label, 'archive_kb_article_version',
    'app.kb_article_versions', p_version_id, 'success', null, app.kb_article_version_audit_projection(v_version), app.kb_article_version_audit_projection(v_updated)
  );

  return v_updated;
end;
$$;

-- app.create_kb_article_version -- live definition from 20260731130000_create_ticket_knowledge_base.sql
create or replace function app.create_kb_article_version(
  p_article_id uuid, p_title text, p_summary text, p_body text, p_tags text[],
  p_audience_internal boolean, p_audience_customer boolean, p_audience_helpdesk boolean,
  p_actor_auth_user_id uuid, p_actor_label text
)
returns app.kb_article_versions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_article app.kb_articles;
  v_next_version integer;
  v_row app.kb_article_versions;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_article from app.kb_articles where id = p_article_id for update;
  if not found or not app.has_active_tenant_membership(v_article.tenant_id, p_actor_auth_user_id) then
    raise exception 'kb_article_not_found: %', p_article_id using errcode = 'no_data_found';
  end if;
  if not app.check_ticket_authority('Edit', v_article.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks TKT:Edit for tenant %', p_actor_auth_user_id, v_article.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_title is null or length(trim(p_title)) = 0 then
    raise exception 'title_required: a non-empty title is required' using errcode = 'check_violation';
  end if;
  if p_body is null or length(trim(p_body)) = 0 then
    raise exception 'body_required: a non-empty body is required' using errcode = 'check_violation';
  end if;

  select coalesce(max(version_number), 0) + 1 into v_next_version from app.kb_article_versions where article_id = p_article_id;

  insert into app.kb_article_versions (
    article_id, tenant_id, version_number, title, summary, body, tags,
    audience_internal, audience_customer, audience_helpdesk, author_auth_user_id, author_label, created_by
  ) values (
    p_article_id, v_article.tenant_id, v_next_version, p_title, p_summary, p_body, coalesce(p_tags, '{}'::text[]),
    coalesce(p_audience_internal, false), coalesce(p_audience_customer, false), coalesce(p_audience_helpdesk, false),
    p_actor_auth_user_id, p_actor_label, p_actor_label
  )
  returning * into v_row;

  perform app.capture_audit_event(
    v_article.tenant_id, p_actor_auth_user_id, p_actor_label, 'create_kb_article_version',
    'app.kb_article_versions', v_row.id, 'success', null, null, app.kb_article_version_audit_projection(v_row)
  );

  return v_row;
end;
$$;

-- app.create_ticket_escalation_policy_version -- live definition from 20260731160000_create_ticket_escalation.sql
create or replace function app.create_ticket_escalation_policy_version(
  p_policy_id uuid, p_channel text, p_category_id uuid, p_priority text, p_queue_id uuid, p_precedence_rank integer,
  p_actor_auth_user_id uuid, p_actor_label text
)
returns app.ticket_escalation_policy_versions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_policy app.ticket_escalation_policies;
  v_next_version integer;
  v_row app.ticket_escalation_policy_versions;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_policy from app.ticket_escalation_policies where id = p_policy_id for update;
  if not found or not app.has_active_tenant_membership(v_policy.tenant_id, p_actor_auth_user_id) then
    raise exception 'ticket_escalation_policy_not_found: %', p_policy_id using errcode = 'no_data_found';
  end if;
  if not app.check_ticket_authority('Edit', v_policy.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks TKT:Edit for tenant %', p_actor_auth_user_id, v_policy.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_channel is null or not (p_channel = any (array['internal', 'customer'])) then
    raise exception 'invalid_channel: % is not one of internal/customer -- helpdesk escalation has no non-Supreme-Admin model (decision 1)', p_channel using errcode = 'check_violation';
  end if;
  if p_priority is not null and not (p_priority = any (array['low', 'normal', 'high', 'urgent'])) then
    raise exception 'invalid_priority: % is not one of low/normal/high/urgent', p_priority using errcode = 'check_violation';
  end if;
  if p_category_id is not null and not exists (select 1 from app.ticket_categories c where c.id = p_category_id and c.tenant_id = v_policy.tenant_id) then
    raise exception 'ticket_category_not_found: %', p_category_id using errcode = 'no_data_found';
  end if;
  if p_queue_id is not null and not exists (select 1 from app.ticket_queues q where q.id = p_queue_id and q.tenant_id = v_policy.tenant_id) then
    raise exception 'ticket_queue_not_found: %', p_queue_id using errcode = 'no_data_found';
  end if;

  select coalesce(max(version_number), 0) + 1 into v_next_version from app.ticket_escalation_policy_versions where policy_id = p_policy_id;

  insert into app.ticket_escalation_policy_versions (
    policy_id, tenant_id, version_number, channel, category_id, priority, queue_id, precedence_rank, created_by
  ) values (
    p_policy_id, v_policy.tenant_id, v_next_version, p_channel, p_category_id, p_priority, p_queue_id, coalesce(p_precedence_rank, 0), p_actor_label
  )
  returning * into v_row;

  perform app.capture_audit_event(
    v_policy.tenant_id, p_actor_auth_user_id, p_actor_label, 'create_ticket_escalation_policy_version',
    'app.ticket_escalation_policy_versions', v_row.id, 'success', null, null,
    jsonb_build_object('policy_id', p_policy_id, 'version_number', v_next_version, 'channel', p_channel, 'category_id', p_category_id, 'priority', p_priority, 'queue_id', p_queue_id, 'precedence_rank', v_row.precedence_rank)
  );

  return v_row;
end;
$$;

-- app.create_ticket_routing_rule_version -- live definition from 20260731140000_create_ticket_assignment.sql
create or replace function app.create_ticket_routing_rule_version(
  p_rule_id uuid, p_channel text, p_category_id uuid, p_priority text, p_target_queue_id uuid,
  p_assignment_mode text, p_max_active_assignments_per_member integer, p_precedence_rank integer,
  p_actor_auth_user_id uuid, p_actor_label text
)
returns app.ticket_routing_rule_versions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_rule app.ticket_routing_rules;
  v_next_version integer;
  v_row app.ticket_routing_rule_versions;
  v_mode text := coalesce(p_assignment_mode, 'manual');
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_rule from app.ticket_routing_rules where id = p_rule_id for update;
  if not found or not app.has_active_tenant_membership(v_rule.tenant_id, p_actor_auth_user_id) then
    raise exception 'ticket_routing_rule_not_found: %', p_rule_id using errcode = 'no_data_found';
  end if;
  if not app.check_ticket_authority('Edit', v_rule.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks TKT:Edit for tenant %', p_actor_auth_user_id, v_rule.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_channel is null or not (p_channel = any (array['internal', 'customer'])) then
    raise exception 'invalid_channel: % is not one of internal/customer -- helpdesk routing has no eligibility model (decision 2), see app.assign_helpdesk_ticket', p_channel using errcode = 'check_violation';
  end if;
  if p_priority is not null and not (p_priority = any (array['low', 'normal', 'high', 'urgent'])) then
    raise exception 'invalid_priority: % is not one of low/normal/high/urgent', p_priority using errcode = 'check_violation';
  end if;
  if not (v_mode = any (array['manual', 'least_loaded'])) then
    raise exception 'invalid_assignment_mode: % is not one of manual/least_loaded', v_mode using errcode = 'check_violation';
  end if;
  if p_max_active_assignments_per_member is not null and p_max_active_assignments_per_member <= 0 then
    raise exception 'invalid_workload_limit: max_active_assignments_per_member must be positive when set' using errcode = 'check_violation';
  end if;
  if p_category_id is not null and not exists (select 1 from app.ticket_categories c where c.id = p_category_id and c.tenant_id = v_rule.tenant_id) then
    raise exception 'ticket_category_not_found: %', p_category_id using errcode = 'no_data_found';
  end if;
  if not exists (select 1 from app.ticket_queues q where q.id = p_target_queue_id and q.tenant_id = v_rule.tenant_id and q.status = 'active') then
    raise exception 'ticket_queue_not_found: % is not a valid active queue for tenant %', p_target_queue_id, v_rule.tenant_id using errcode = 'no_data_found';
  end if;

  select coalesce(max(version_number), 0) + 1 into v_next_version from app.ticket_routing_rule_versions where rule_id = p_rule_id;

  insert into app.ticket_routing_rule_versions (
    rule_id, tenant_id, version_number, channel, category_id, priority, target_queue_id,
    assignment_mode, max_active_assignments_per_member, precedence_rank, created_by
  ) values (
    p_rule_id, v_rule.tenant_id, v_next_version, p_channel, p_category_id, p_priority, p_target_queue_id,
    v_mode, p_max_active_assignments_per_member, coalesce(p_precedence_rank, 0), p_actor_label
  )
  returning * into v_row;

  perform app.capture_audit_event(
    v_rule.tenant_id, p_actor_auth_user_id, p_actor_label, 'create_ticket_routing_rule_version',
    'app.ticket_routing_rule_versions', v_row.id, 'success', null, null,
    jsonb_build_object(
      'rule_id', p_rule_id, 'version_number', v_next_version, 'channel', p_channel, 'category_id', p_category_id,
      'priority', p_priority, 'target_queue_id', p_target_queue_id, 'assignment_mode', v_mode,
      'max_active_assignments_per_member', p_max_active_assignments_per_member, 'precedence_rank', v_row.precedence_rank
    )
  );

  return v_row;
end;
$$;

-- app.publish_kb_article_version -- live definition from 20260731130000_create_ticket_knowledge_base.sql
create or replace function app.publish_kb_article_version(p_version_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
returns app.kb_article_versions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_version app.kb_article_versions;
  v_article app.kb_articles;
  v_updated app.kb_article_versions;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_version from app.kb_article_versions where id = p_version_id for update;
  if not found or not app.has_active_tenant_membership(v_version.tenant_id, p_actor_auth_user_id) then
    raise exception 'kb_article_version_not_found: %', p_version_id using errcode = 'no_data_found';
  end if;
  -- Lock order (C-21 discipline): version row already locked above, then the
  -- parent article row -- the only function in this migration that locks
  -- both, so there is no sibling ordering to deadlock against.
  select * into v_article from app.kb_articles where id = v_version.article_id for update;

  if not app.check_ticket_authority('Edit', v_version.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks TKT:Edit for tenant %', p_actor_auth_user_id, v_version.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_version.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_version.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_version.status <> 'approved' then
    raise exception 'invalid_state: article version % is % not approved -- publish requires a reviewer approval first (decision 3, no bypass)', p_version_id, v_version.status
      using errcode = 'check_violation';
  end if;
  if not (v_version.audience_internal or v_version.audience_customer or v_version.audience_helpdesk) then
    raise exception 'audience_required: at least one audience flag must be true before publish' using errcode = 'check_violation';
  end if;

  update app.kb_article_versions set status = 'archived', archived_at = now(), archived_by = p_actor_label, archived_reason = 'superseded_by_publish'
  where article_id = v_version.article_id and status = 'published';

  update app.kb_article_versions
  set status = 'published', published_at = now(), published_by = p_actor_label
  where id = p_version_id and record_version = p_expected_version
  returning * into v_updated;
  if not found then
    raise exception 'stale_version: concurrent update detected for article version %', p_version_id using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_version.tenant_id, p_actor_auth_user_id, p_actor_label, 'publish_kb_article_version',
    'app.kb_article_versions', p_version_id, 'success', null, null, app.kb_article_version_audit_projection(v_updated)
  );

  return v_updated;
end;
$$;

-- app.publish_ticket_escalation_policy_version -- live definition from 20260731160000_create_ticket_escalation.sql
create or replace function app.publish_ticket_escalation_policy_version(p_version_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
returns app.ticket_escalation_policy_versions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_version app.ticket_escalation_policy_versions;
  v_policy app.ticket_escalation_policies;
  v_updated app.ticket_escalation_policy_versions;
  v_has_levels boolean;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_version from app.ticket_escalation_policy_versions where id = p_version_id for update;
  if not found or not app.has_active_tenant_membership(v_version.tenant_id, p_actor_auth_user_id) then
    raise exception 'ticket_escalation_policy_version_not_found: %', p_version_id using errcode = 'no_data_found';
  end if;
  select * into v_policy from app.ticket_escalation_policies where id = v_version.policy_id for update;

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

  select exists (select 1 from app.ticket_escalation_levels l where l.policy_version_id = p_version_id) into v_has_levels;
  if not v_has_levels then
    raise exception 'escalation_policy_incomplete: version % has no escalation levels configured', p_version_id using errcode = 'check_violation';
  end if;

  -- Supersede this SAME policy's own prior published version, applied FROM
  -- THE START (HRT-289/290's own self-found fix, reused precedent) --
  -- deliberately does NOT supersede a DIFFERENT policy's version; that
  -- ambiguity is caught at RESOLUTION time (ticket_escalation_policy_
  -- ambiguous_match), never suppressed here.
  update app.ticket_escalation_policy_versions
  set status = 'superseded'
  where policy_id = v_version.policy_id and status = 'published';

  update app.ticket_escalation_policy_versions
  set status = 'published', published_at = now(), published_by = p_actor_label
  where id = p_version_id and record_version = p_expected_version
  returning * into v_updated;
  if not found then
    raise exception 'stale_version: concurrent update detected for policy version %', p_version_id using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_version.tenant_id, p_actor_auth_user_id, p_actor_label, 'publish_ticket_escalation_policy_version',
    'app.ticket_escalation_policy_versions', p_version_id, 'success', null, null,
    jsonb_build_object('policy_id', v_version.policy_id, 'version_number', v_updated.version_number)
  );

  return v_updated;
end;
$$;

-- app.publish_ticket_routing_rule_version -- live definition from 20260731140000_create_ticket_assignment.sql
create or replace function app.publish_ticket_routing_rule_version(p_version_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
returns app.ticket_routing_rule_versions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_version app.ticket_routing_rule_versions;
  v_rule app.ticket_routing_rules;
  v_updated app.ticket_routing_rule_versions;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_version from app.ticket_routing_rule_versions where id = p_version_id for update;
  if not found or not app.has_active_tenant_membership(v_version.tenant_id, p_actor_auth_user_id) then
    raise exception 'ticket_routing_rule_version_not_found: %', p_version_id using errcode = 'no_data_found';
  end if;
  select * into v_rule from app.ticket_routing_rules where id = v_version.rule_id for update;

  if not app.check_ticket_authority('Edit', v_version.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks TKT:Edit for tenant %', p_actor_auth_user_id, v_version.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_version.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_version.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_version.status <> 'draft' then
    raise exception 'invalid_state: routing rule version % is % not draft', p_version_id, v_version.status using errcode = 'check_violation';
  end if;

  -- Supersede this SAME rule's own prior published version under the parent
  -- row lock already taken above -- HRT-289's own self-found fix
  -- (app.publish_sla_policy_version: "a revised version tied against its own
  -- predecessor at resolution time"), applied here from the start rather
  -- than rediscovered (decision 4). Deliberately does NOT supersede a
  -- DIFFERENT rule's version -- two different rules may legitimately publish
  -- overlapping-scope versions; app._resolve_ticket_routing_rule_for_ticket
  -- raises ticket_routing_rule_ambiguous_match at MATCH time instead of
  -- suppressing the ambiguity here.
  update app.ticket_routing_rule_versions
  set status = 'superseded'
  where rule_id = v_version.rule_id and status = 'published';

  update app.ticket_routing_rule_versions
  set status = 'published', published_at = now(), published_by = p_actor_label
  where id = p_version_id and record_version = p_expected_version
  returning * into v_updated;
  if not found then
    raise exception 'stale_version: concurrent update detected for routing rule version %', p_version_id using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_version.tenant_id, p_actor_auth_user_id, p_actor_label, 'publish_ticket_routing_rule_version',
    'app.ticket_routing_rule_versions', p_version_id, 'success', null, null,
    jsonb_build_object('rule_id', v_version.rule_id, 'version_number', v_updated.version_number)
  );

  return v_updated;
end;
$$;

-- app.redact_ticket_message -- live definition from 20260731100000_extend_ticketing_helpdesk_channel.sql
create or replace function app.redact_ticket_message(p_message_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.ticket_messages
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_message app.ticket_messages;
  v_ticket app.tickets;
  v_updated app.ticket_messages;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_message from app.ticket_messages where id = p_message_id for update;
  if not found or not app.has_active_tenant_membership(v_message.tenant_id, p_actor_auth_user_id) then
    raise exception 'ticket_message_not_found: %', p_message_id using errcode = 'no_data_found';
  end if;

  if not app.can_access_ticket(v_message.ticket_id, p_actor_auth_user_id) then
    raise exception 'ticket_message_not_found: %', p_message_id using errcode = 'no_data_found';
  end if;

  select * into v_ticket from app.tickets where id = v_message.ticket_id;

  if v_ticket.channel = 'helpdesk' then
    -- HRT-288 (decision 6/8): redaction of ANY content (public or Platform-
    -- internal) on a helpdesk case is Platform-support-staff-only (Supreme
    -- Admin, per this migration's own bounded staff-role decision) -- a
    -- tenant's own tenant-wide TKT:Edit authority must NEVER be able to
    -- destroy Platform-internal diagnostic notes it cannot even read.
    if not app.is_ticket_staff(v_ticket.id, p_actor_auth_user_id) then
      raise exception 'insufficient_authority: identity % lacks Platform support authority to redact content on helpdesk ticket %', p_actor_auth_user_id, v_ticket.id
        using errcode = 'insufficient_privilege';
    end if;
  elsif not app.check_ticket_authority('Edit', v_message.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks TKT:Edit for tenant %', p_actor_auth_user_id, v_message.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_message.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_message.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_message.is_redacted then
    return v_message;
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a reason is required to redact a message' using errcode = 'check_violation';
  end if;

  update app.ticket_messages
  set body = '[redacted]', attachment_file_ids = '{}'::uuid[], is_redacted = true, redacted_at = now(), redacted_by = p_actor_label, redacted_reason = p_reason
  where id = p_message_id and record_version = p_expected_version
  returning * into v_updated;
  if not found then
    raise exception 'stale_version: concurrent update detected for ticket message %', p_message_id using errcode = 'serialization_failure';
  end if;

  insert into app.ticket_events (tenant_id, ticket_id, event_type, actor_auth_user_id, actor_label)
  values (v_message.tenant_id, v_message.ticket_id, 'message_redacted', p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    v_message.tenant_id, p_actor_auth_user_id, p_actor_label, 'redact_ticket_message',
    'app.ticket_messages', v_message.id, 'success', null,
    jsonb_build_object('ticket_id', v_message.ticket_id, 'visibility', v_message.visibility, 'is_redacted', false),
    jsonb_build_object('ticket_id', v_updated.ticket_id, 'visibility', v_updated.visibility, 'is_redacted', true)
  );

  return v_updated;
end;
$$;

-- app.set_kb_article_expiry -- live definition from 20260731130000_create_ticket_knowledge_base.sql
create or replace function app.set_kb_article_expiry(p_version_id uuid, p_expected_version integer, p_expires_at timestamptz, p_actor_auth_user_id uuid, p_actor_label text)
returns app.kb_article_versions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_version app.kb_article_versions;
  v_updated app.kb_article_versions;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_version from app.kb_article_versions where id = p_version_id for update;
  if not found or not app.has_active_tenant_membership(v_version.tenant_id, p_actor_auth_user_id) then
    raise exception 'kb_article_version_not_found: %', p_version_id using errcode = 'no_data_found';
  end if;
  if not app.check_ticket_authority('Edit', v_version.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks TKT:Edit for tenant %', p_actor_auth_user_id, v_version.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_version.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_version.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_version.status not in ('draft', 'in_review', 'approved', 'published') then
    raise exception 'invalid_state: article version % is %', p_version_id, v_version.status using errcode = 'check_violation';
  end if;

  update app.kb_article_versions set expires_at = p_expires_at
  where id = p_version_id and record_version = p_expected_version
  returning * into v_updated;
  if not found then
    raise exception 'stale_version: concurrent update detected for article version %', p_version_id using errcode = 'serialization_failure';
  end if;

  return v_updated;
end;
$$;

-- app.set_ticket_category_customer_visibility -- live definition from 20260731080000_extend_ticketing_customer_channel.sql
create or replace function app.set_ticket_category_customer_visibility(p_category_id uuid, p_customer_visible boolean, p_actor_auth_user_id uuid, p_actor_label text)
returns app.ticket_categories
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_category app.ticket_categories;
  v_updated app.ticket_categories;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_category from app.ticket_categories where id = p_category_id for update;
  if not found or not app.has_active_tenant_membership(v_category.tenant_id, p_actor_auth_user_id) then
    raise exception 'ticket_category_not_found: %', p_category_id using errcode = 'no_data_found';
  end if;
  if not app.check_ticket_authority('Edit', v_category.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks TKT:Edit for tenant %', p_actor_auth_user_id, v_category.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_customer_visible and v_category.default_queue_id is null then
    raise exception 'queue_required: a customer-visible category must have a default queue configured first' using errcode = 'check_violation';
  end if;

  update app.ticket_categories set customer_visible = p_customer_visible
  where id = p_category_id
  returning * into v_updated;

  perform app.capture_audit_event(
    v_category.tenant_id, p_actor_auth_user_id, p_actor_label, 'set_ticket_category_customer_visibility',
    'app.ticket_categories', v_updated.id, 'success', null,
    jsonb_build_object('customer_visible', v_category.customer_visible),
    jsonb_build_object('customer_visible', v_updated.customer_visible)
  );

  return v_updated;
end;
$$;

-- app.set_ticket_category_helpdesk_visibility -- live definition from 20260731100000_extend_ticketing_helpdesk_channel.sql
create or replace function app.set_ticket_category_helpdesk_visibility(p_category_id uuid, p_helpdesk_visible boolean, p_actor_auth_user_id uuid, p_actor_label text)
returns app.ticket_categories
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_category app.ticket_categories;
  v_updated app.ticket_categories;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_category from app.ticket_categories where id = p_category_id for update;
  if not found or not app.has_active_tenant_membership(v_category.tenant_id, p_actor_auth_user_id) then
    raise exception 'ticket_category_not_found: %', p_category_id using errcode = 'no_data_found';
  end if;
  if not app.check_ticket_authority('Edit', v_category.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks TKT:Edit for tenant %', p_actor_auth_user_id, v_category.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.ticket_categories set helpdesk_visible = p_helpdesk_visible
  where id = p_category_id
  returning * into v_updated;

  perform app.capture_audit_event(
    v_category.tenant_id, p_actor_auth_user_id, p_actor_label, 'set_ticket_category_helpdesk_visibility',
    'app.ticket_categories', v_updated.id, 'success', null,
    jsonb_build_object('helpdesk_visible', v_category.helpdesk_visible),
    jsonb_build_object('helpdesk_visible', v_updated.helpdesk_visible)
  );

  return v_updated;
end;
$$;

-- app.submit_kb_article_version_for_review -- live definition from 20260731130000_create_ticket_knowledge_base.sql
create or replace function app.submit_kb_article_version_for_review(p_version_id uuid, p_expected_version integer, p_reviewer_auth_user_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
returns app.kb_article_versions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_version app.kb_article_versions;
  v_reviewer_label text;
  v_updated app.kb_article_versions;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_version from app.kb_article_versions where id = p_version_id for update;
  if not found or not app.has_active_tenant_membership(v_version.tenant_id, p_actor_auth_user_id) then
    raise exception 'kb_article_version_not_found: %', p_version_id using errcode = 'no_data_found';
  end if;
  if not app.check_ticket_authority('Edit', v_version.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks TKT:Edit for tenant %', p_actor_auth_user_id, v_version.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_version.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_version.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_version.status <> 'draft' then
    raise exception 'invalid_state: article version % is % not draft', p_version_id, v_version.status using errcode = 'check_violation';
  end if;
  if p_reviewer_auth_user_id is null then
    raise exception 'reviewer_required: a reviewer is required' using errcode = 'check_violation';
  end if;
  if p_reviewer_auth_user_id = v_version.author_auth_user_id then
    raise exception 'self_review_forbidden: the author (%) may not review their own article version', v_version.author_auth_user_id
      using errcode = 'check_violation';
  end if;
  if not app.has_active_tenant_membership(v_version.tenant_id, p_reviewer_auth_user_id) or app.actor_holds_customer_user_layer(v_version.tenant_id, p_reviewer_auth_user_id) then
    raise exception 'reviewer_not_eligible: % is not an active internal member of tenant %', p_reviewer_auth_user_id, v_version.tenant_id
      using errcode = 'check_violation';
  end if;

  select u.display_name into v_reviewer_label from app.users u where u.auth_user_id = p_reviewer_auth_user_id;

  update app.kb_article_versions set
    status = 'in_review', reviewer_auth_user_id = p_reviewer_auth_user_id, reviewer_label = v_reviewer_label,
    submitted_for_review_by = p_actor_label, submitted_for_review_at = now(), review_decision = null, reviewed_at = null, review_notes = null
  where id = p_version_id and record_version = p_expected_version
  returning * into v_updated;
  if not found then
    raise exception 'stale_version: concurrent update detected for article version %', p_version_id using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_version.tenant_id, p_actor_auth_user_id, p_actor_label, 'submit_kb_article_version_for_review',
    'app.kb_article_versions', p_version_id, 'success', null, app.kb_article_version_audit_projection(v_version), app.kb_article_version_audit_projection(v_updated)
  );

  return v_updated;
end;
$$;

-- app.update_kb_article_version -- live definition from 20260731130000_create_ticket_knowledge_base.sql
create or replace function app.update_kb_article_version(
  p_version_id uuid, p_expected_version integer, p_title text, p_summary text, p_body text, p_tags text[],
  p_audience_internal boolean, p_audience_customer boolean, p_audience_helpdesk boolean,
  p_actor_auth_user_id uuid, p_actor_label text
)
returns app.kb_article_versions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_version app.kb_article_versions;
  v_updated app.kb_article_versions;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_version from app.kb_article_versions where id = p_version_id for update;
  if not found or not app.has_active_tenant_membership(v_version.tenant_id, p_actor_auth_user_id) then
    raise exception 'kb_article_version_not_found: %', p_version_id using errcode = 'no_data_found';
  end if;
  if not app.check_ticket_authority('Edit', v_version.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks TKT:Edit for tenant %', p_actor_auth_user_id, v_version.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_version.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_version.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_version.status <> 'draft' then
    raise exception 'invalid_state: article version % is % not draft', p_version_id, v_version.status using errcode = 'check_violation';
  end if;
  if p_title is null or length(trim(p_title)) = 0 then
    raise exception 'title_required: a non-empty title is required' using errcode = 'check_violation';
  end if;
  if p_body is null or length(trim(p_body)) = 0 then
    raise exception 'body_required: a non-empty body is required' using errcode = 'check_violation';
  end if;

  update app.kb_article_versions set
    title = p_title, summary = p_summary, body = p_body, tags = coalesce(p_tags, '{}'::text[]),
    audience_internal = coalesce(p_audience_internal, false), audience_customer = coalesce(p_audience_customer, false),
    audience_helpdesk = coalesce(p_audience_helpdesk, false)
  where id = p_version_id and record_version = p_expected_version
  returning * into v_updated;
  if not found then
    raise exception 'stale_version: concurrent update detected for article version %', p_version_id using errcode = 'serialization_failure';
  end if;

  return v_updated;
end;
$$;
