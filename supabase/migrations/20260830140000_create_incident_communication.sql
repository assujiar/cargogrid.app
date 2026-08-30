-- ISS-2026-258 (docs/runtime/KNOWN_ISSUES.md, High) -- no real DR/incident communication
-- mechanism exists anywhere: no channel, no template, no notification order, no
-- customer-impact record. Every runbook's Communication section is a bare "notify DevOps",
-- with no named recipient, no channel, no order, and no record of what was said to whom.
-- Cross-referenced with `ISS-2026-251` (no escalation/dispatch for
-- `app.raise_observability_alert`'s own incidents), and that entry's warning is taken
-- seriously here: a fix for one must account for the other rather than building dispatch
-- twice.
--
-- ---------------------------------------------------------------------------------------
-- One claim in that entry is stale, and it changes the whole shape of the fix
-- ---------------------------------------------------------------------------------------
--
-- `ISS-2026-258` states, and its 2026-08-27 disposition repeats, that "no real Slack/email/
-- PagerDuty dispatch integration exists anywhere in this codebase", and concludes that
-- closing it needs a real external product build. Re-verified directly against the
-- migration set this checkpoint, that is no longer true:
--
--   * `PLT-127`'s Notification Engine is real and complete -- `app.notification_types`,
--     `app.notification_preferences`, `app.notifications`,
--     `app.notification_delivery_attempts`, and `app.queue_notification`, which renders a
--     published template, honours per-recipient channel preference, and records delivery
--     attempts.
--   * `IAE-034`'s email/WhatsApp/SMS capability added
--     `app.notification_contact_addresses` on top of it.
--   * `IAE-035`'s Integration Hub carries real adapters for those providers.
--
-- So the channel exists. What genuinely did not exist is everything *between* an incident
-- and that channel: nothing named who should hear about an incident, in what order, with
-- what words, or kept a record of what was actually sent. That is the gap this migration
-- closes, and it is bounded, code-shaped work -- not the external product build the
-- earlier disposition (correctly, at the time) declined.
--
-- ---------------------------------------------------------------------------------------
-- What is built, mapped to the four things the entry says are missing
-- ---------------------------------------------------------------------------------------
--
--   "no channel"          -> composed from app.queue_notification. Not rebuilt. This
--                            migration contains no dispatch logic of its own, which is the
--                            point ISS-2026-251 makes.
--   "no template"         -> a registered `incident_communication` notification type, so a
--                            tenant's own message templates are ordinary published config
--                            versions -- editable without a code release, like every other
--                            template in this system.
--   "no notification order" -> app.incident_communication_audiences: an ordered registry,
--                            data rather than prose, so "internal first, then tenant
--                            admins, then customers" is a row someone can change and a
--                            query can enforce -- not a sentence in a runbook nobody reads
--                            at 3am.
--   "no customer-impact    -> app.incident_communications records audience, severity, the
--    assessment tool"        exact text sent, and a per-recipient child table. After an
--                            incident you can answer "who did we tell, when, and what did
--                            we say" from the database instead of from memory. Business
--                            rule §24 requires customer/SLA communication to match actual
--                            evidence; this is that evidence.
--
-- ---------------------------------------------------------------------------------------
-- Deliberate boundaries, disclosed rather than left implicit
-- ---------------------------------------------------------------------------------------
--
-- * **No public status page.** A customer-facing status page served to unauthenticated
--   visitors is genuinely a separate product surface (and normally a separate host, since
--   a status page that lives inside the system it reports on is useless during the outage
--   it exists to report). The `customer_portal` audience below reaches authenticated portal
--   users through the existing Notification Engine. The unauthenticated public page is NOT
--   built and is NOT claimed -- see this entry's own KNOWN_ISSUES annotation for what
--   remains.
-- * **No SLA clock.** `11_DEVOPS_WORKSTREAM.md` §8.4 describes P1-P4 response SLAs. This
--   migration records when a communication was sent, which is a prerequisite for measuring
--   a response SLA, but it does not implement the clock, alert on breach, or claim to.
-- * **Recipient resolution is real, not a placeholder**, and its limits are explicit: the
--   `internal` audience resolves through the matching `app.alert_routes` owner, and the
--   `tenant_admins`/`customer_portal` audiences resolve through real membership rows. An
--   audience that resolves to zero recipients is recorded with `recipient_count = 0` and
--   raises nothing -- but it is visible as zero, never reported as "sent". A broadcast that
--   silently reached nobody is worse than one that failed loudly.
--
-- Per `ERR-2026-004`: explicit `revoke execute on all functions in schema app from public;`
-- before the final grants. No already-applied migration is edited.

-- ===========================================================================
-- 1. The notification order, as data.
-- ===========================================================================

create table app.incident_communication_audiences (
  code text primary key,
  name text not null,
  dispatch_order integer not null,
  description text not null,
  constraint incident_communication_audiences_order_check check (dispatch_order > 0),
  constraint incident_communication_audiences_order_unique unique (dispatch_order)
);

comment on table app.incident_communication_audiences is
  'ISS-2026-258: who hears about an incident, and in what order. Data rather than runbook prose, so the order is queryable, changeable without a code release, and cannot drift between twelve runbooks that each state it slightly differently -- which is exactly what ISS-2026-258 found when it read all twelve.';

insert into app.incident_communication_audiences (code, name, dispatch_order, description) values
  ('internal', 'Internal owners and on-call', 1,
   'The owning team for the incident''s own alert route, plus tenant administrators when the incident is tenant-scoped. Always first: the people who can act on it hear before the people who are affected by it.'),
  ('tenant_admins', 'Tenant administrators', 2,
   'Every active tenant_admin of the affected tenant. Second: they need to know before their own users start asking, and they decide what their organisation is told.'),
  ('customer_portal', 'Customer portal users', 3,
   'Active customer_user-layer principals of the affected tenant. Last, and deliberately: a message to customers should follow, not precede, the tenant''s own administrators being told.');

-- ===========================================================================
-- 2. What was actually communicated.
-- ===========================================================================

create table app.incident_communications (
  id uuid primary key default gen_random_uuid(),
  incident_id uuid not null references app.incidents (id),
  tenant_id uuid references app.tenants (id),
  audience_code text not null references app.incident_communication_audiences (code),
  severity text not null,
  subject text not null,
  body text not null,
  recipient_count integer not null default 0,
  notification_count integer not null default 0,
  idempotency_key text,
  sent_by text,
  sent_at timestamptz not null default now(),
  constraint incident_communications_severity_check check (severity in ('low', 'medium', 'high', 'critical')),
  constraint incident_communications_subject_check check (length(trim(subject)) > 0),
  constraint incident_communications_body_check check (length(trim(body)) > 0),
  constraint incident_communications_counts_check check (recipient_count >= 0 and notification_count >= 0 and notification_count <= recipient_count)
);

create unique index incident_communications_idempotency_unique
  on app.incident_communications (incident_id, idempotency_key)
  where idempotency_key is not null;

create index incident_communications_incident_idx on app.incident_communications (incident_id, sent_at desc);
create index incident_communications_tenant_idx on app.incident_communications (tenant_id, sent_at desc);

comment on table app.incident_communications is
  'ISS-2026-258: the durable record of what was communicated about an incident -- audience, severity, and the exact subject and body as sent, never a template reference that could be edited afterwards to change what history says was said. Prompt 384 §24 requires customer/SLA communication to match actual evidence; this table is that evidence. recipient_count is stored even when it is 0: a broadcast that silently reached nobody must be visible as such, never reported as sent.';

create table app.incident_communication_recipients (
  id uuid primary key default gen_random_uuid(),
  communication_id uuid not null references app.incident_communications (id) on delete cascade,
  recipient_auth_user_id uuid,
  recipient_email text,
  notification_id uuid references app.notifications (id),
  dispatch_error text,
  constraint incident_communication_recipients_identity_check check (recipient_auth_user_id is not null or recipient_email is not null)
);

create index incident_communication_recipients_communication_idx on app.incident_communication_recipients (communication_id);

comment on table app.incident_communication_recipients is
  'ISS-2026-258: one row per real recipient of one incident communication -- the "to whom" half of the record. notification_id links to the Notification Engine row that carried it (null when the recipient is an alert-route owner_email with no platform identity to queue against, which is recorded honestly rather than dropped). dispatch_error records a per-recipient failure without failing the whole broadcast: telling nine people and failing on the tenth is not a reason to tell nobody.';

-- ===========================================================================
-- 3. Notification type registration, so templates are ordinary config.
-- ===========================================================================

insert into app.notification_types (code, name, owner_primitive_code, registered_by)
values ('incident_communication', 'Incident Communication', 'MON', 'system')
on conflict (code) do nothing;

insert into app.config_types (code, name, owner_primitive_code, registered_by)
values ('notification:incident_communication', 'Incident Communication', 'MON', 'system')
on conflict (code) do nothing;

-- ===========================================================================
-- 3b. Widen the incident timeline's own event-type guard.
--
--     app.incident_timeline_events admits exactly four event types
--     ('opened', 'duplicate_signal', 'acknowledged', 'resolved'). A
--     communication is a real event in an incident's life -- arguably the one
--     an auditor asks about first -- and recording it anywhere other than the
--     incident's own timeline would put half the story in a second place.
--     A CHECK replacement on a table whose existing rows all carry one of the
--     four already-permitted values; no existing row can fail it.
-- ===========================================================================

alter table app.incident_timeline_events
  drop constraint incident_timeline_events_event_type_check;

alter table app.incident_timeline_events
  add constraint incident_timeline_events_event_type_check
  check (event_type in ('opened', 'duplicate_signal', 'acknowledged', 'resolved', 'communicated'));

-- ===========================================================================
-- 4. The broadcast action.
-- ===========================================================================

create function app.broadcast_incident_communication(
  p_incident_id uuid,
  p_audience_code text,
  p_subject text,
  p_body text,
  p_template_config_version_id uuid,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.incident_communications
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_incident app.incidents;
  v_audience app.incident_communication_audiences;
  v_decision app.rbac_decision;
  v_authorized boolean;
  v_existing app.incident_communications;
  v_comm app.incident_communications;
  v_route app.alert_routes;
  v_recipient record;
  v_notification app.notifications;
  v_recipient_count integer := 0;
  v_notification_count integer := 0;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_incident from app.incidents where id = p_incident_id;
  if not found then
    raise exception 'incident_not_found: %', p_incident_id using errcode = 'no_data_found';
  end if;

  select * into v_audience from app.incident_communication_audiences where code = p_audience_code;
  if not found then
    raise exception 'incident_communication_unknown_audience: % is not a registered audience', p_audience_code
      using errcode = 'check_violation';
  end if;

  -- Identical authority to app.acknowledge_incident/app.resolve_incident: a
  -- platform-scoped incident is Supreme Admin only; a tenant-scoped one needs MON:Edit for
  -- that tenant. Speaking on an incident's behalf is not a lesser act than acknowledging
  -- it, so it does not get a lesser gate.
  if v_incident.tenant_id is null then
    v_authorized := app.is_supreme_admin(p_actor_auth_user_id);
  else
    v_decision := app.evaluate_permission(p_actor_auth_user_id, v_incident.tenant_id, 'MON', 'Edit');
    v_authorized := v_decision.allowed;
  end if;
  if not v_authorized then
    raise exception 'insufficient_authority: identity % lacks authority to communicate on incident %', p_actor_auth_user_id, p_incident_id
      using errcode = 'insufficient_privilege';
  end if;

  if coalesce(trim(p_subject), '') = '' or coalesce(trim(p_body), '') = '' then
    raise exception 'incident_communication_empty_message: subject and body are both required'
      using errcode = 'check_violation';
  end if;

  -- A platform-scoped incident has no tenant whose administrators or customers could be
  -- addressed. Refusing is correct: silently sending an "all customers" message to nobody
  -- would read as done in the record.
  if v_incident.tenant_id is null and p_audience_code in ('tenant_admins', 'customer_portal') then
    raise exception 'incident_communication_audience_not_addressable: incident % is platform-scoped and has no tenant %s to address', p_incident_id, p_audience_code
      using errcode = 'check_violation';
  end if;

  if p_idempotency_key is not null then
    select * into v_existing from app.incident_communications
    where incident_id = p_incident_id and idempotency_key = p_idempotency_key;
    if found then
      -- A retry must never re-send. Returning the original record, and refusing when the
      -- key was reused for different words, follows the same target-mismatch discipline
      -- every idempotent RPC in this repository already applies.
      if v_existing.subject is distinct from p_subject or v_existing.body is distinct from p_body then
        raise exception 'idempotency_key_conflict: key % was already used on incident % for a different message', p_idempotency_key, p_incident_id
          using errcode = 'unique_violation';
      end if;
      return v_existing;
    end if;
  end if;

  insert into app.incident_communications (
    incident_id, tenant_id, audience_code, severity, subject, body, idempotency_key, sent_by
  ) values (
    p_incident_id, v_incident.tenant_id, p_audience_code, v_incident.severity,
    p_subject, p_body, p_idempotency_key, p_actor_label
  )
  returning * into v_comm;

  if p_audience_code = 'internal' then
    -- The owning team for THIS incident's own alert route -- the link that never existed
    -- between app.raise_observability_alert and anyone hearing about it (ISS-2026-251).
    select * into v_route from app.alert_routes
    where source_type = v_incident.source_type and signal_type = v_incident.signal_type
      and tenant_id is not distinct from v_incident.tenant_id;
    if found and coalesce(trim(v_route.owner_email), '') <> '' then
      insert into app.incident_communication_recipients (communication_id, recipient_email)
      values (v_comm.id, v_route.owner_email);
      v_recipient_count := v_recipient_count + 1;
    end if;
  end if;

  -- Platform identities, resolved from real membership rows. `internal` also reaches the
  -- tenant's own admins, because on a tenant-scoped incident they are among the people who
  -- can act on it, not merely people affected by it.
  if v_incident.tenant_id is not null then
    for v_recipient in
      select distinct pm.auth_user_id
      from app.principal_memberships pm
      where pm.tenant_id = v_incident.tenant_id
        and pm.status = 'active'
        and pm.layer = case when p_audience_code = 'customer_portal' then 'customer_user' else 'tenant_admin' end
    loop
      v_recipient_count := v_recipient_count + 1;
      v_notification := null;
      if p_template_config_version_id is not null then
        begin
          v_notification := app.queue_notification(
            p_template_config_version_id, v_incident.tenant_id, 'incident_communication',
            v_recipient.auth_user_id, 'in_app', null,
            jsonb_build_object(
              'incidentId', p_incident_id, 'severity', v_incident.severity,
              'title', v_incident.title, 'subject', p_subject, 'body', p_body
            ),
            'incident-comm:' || v_comm.id::text || ':' || v_recipient.auth_user_id::text,
            p_actor_auth_user_id, p_actor_label
          );
          v_notification_count := v_notification_count + 1;
        exception
          when others then
            -- One recipient's dispatch failure must not stop the other nine. It is
            -- recorded per recipient rather than swallowed, so the record shows exactly
            -- who was NOT reached -- which is the number that matters after an incident.
            insert into app.incident_communication_recipients (communication_id, recipient_auth_user_id, dispatch_error)
            values (v_comm.id, v_recipient.auth_user_id, left(sqlerrm, 500));
            continue;
        end;
      end if;
      insert into app.incident_communication_recipients (communication_id, recipient_auth_user_id, notification_id)
      values (v_comm.id, v_recipient.auth_user_id, case when v_notification is null then null else v_notification.id end);
    end loop;
  end if;

  update app.incident_communications
  set recipient_count = v_recipient_count, notification_count = v_notification_count
  where id = v_comm.id
  returning * into v_comm;

  insert into app.incident_timeline_events (incident_id, event_type, detail)
  values (p_incident_id, 'communicated',
          p_audience_code || ': ' || v_recipient_count || ' recipient(s), ' || v_notification_count || ' notification(s) queued -- ' || p_subject);

  perform app.capture_audit_event(
    v_incident.tenant_id, p_actor_auth_user_id, p_actor_label, 'broadcast_incident_communication',
    'app.incident_communications', v_comm.id, 'success', null, null,
    jsonb_build_object('incidentId', p_incident_id, 'audience', p_audience_code,
                       'recipientCount', v_recipient_count, 'notificationCount', v_notification_count)
  );

  return v_comm;
end;
$$;

comment on function app.broadcast_incident_communication is
  'ISS-2026-258: sends one incident communication to one registered audience and records exactly what was said to whom. Composes app.queue_notification (PLT-127) rather than building a second dispatch path -- the warning ISS-2026-251 gives about building dispatch twice. Authority is identical to app.acknowledge_incident: Supreme Admin for a platform-scoped incident, MON:Edit for a tenant-scoped one -- speaking on an incident''s behalf is not a lesser act than acknowledging it. Idempotent per (incident, key), refusing a key reused for different words. A per-recipient dispatch failure is recorded against that recipient and does not stop the rest: telling nine people and failing on the tenth is not a reason to tell nobody. A zero-recipient broadcast is recorded as zero, never reported as sent.';

-- ===========================================================================
-- 5. Reads.
-- ===========================================================================

create function app.list_incident_communications(p_incident_id uuid, p_actor_auth_user_id uuid)
returns setof app.incident_communications
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_incident app.incidents;
  v_decision app.rbac_decision;
  v_authorized boolean;
begin
  select * into v_incident from app.incidents where id = p_incident_id;
  if not found then
    raise exception 'incident_not_found: %', p_incident_id using errcode = 'no_data_found';
  end if;

  if v_incident.tenant_id is null then
    v_authorized := app.is_supreme_admin(p_actor_auth_user_id);
  else
    v_decision := app.evaluate_permission(p_actor_auth_user_id, v_incident.tenant_id, 'MON', 'View');
    v_authorized := v_decision.allowed;
  end if;
  if not v_authorized then
    raise exception 'insufficient_authority: identity % lacks MON:View for incident %', p_actor_auth_user_id, p_incident_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
  select * from app.incident_communications where incident_id = p_incident_id order by sent_at desc;
end;
$$;

comment on function app.list_incident_communications is
  'ISS-2026-258: the communication history of one incident, newest first. MON:View-gated (Supreme Admin for a platform-scoped incident), mirroring app.get_incident_timeline.';

create function app.list_incident_communication_audiences()
returns setof app.incident_communication_audiences
language sql
stable
as $$
  select * from app.incident_communication_audiences order by dispatch_order asc;
$$;

comment on function app.list_incident_communication_audiences is
  'ISS-2026-258: the notification order, in order. Deliberately ungated -- it is a static platform registry describing who gets told when, carries no tenant data and no incident data, and a responder needs it before they have looked anything up. Mirrors app.list_finance_currencies'' own precedent for a global reference registry.';

-- ===========================================================================
-- 6. RLS: default-deny, RPC-only (matching the monitoring capability).
-- ===========================================================================

alter table app.incident_communication_audiences enable row level security;
alter table app.incident_communications enable row level security;
alter table app.incident_communication_recipients enable row level security;

revoke all on app.incident_communication_audiences from public, anon, authenticated;
revoke all on app.incident_communications from public, anon, authenticated;
revoke all on app.incident_communication_recipients from public, anon, authenticated;
grant all on app.incident_communication_audiences, app.incident_communications, app.incident_communication_recipients to service_role;

-- ===========================================================================
-- 7. PostgREST wrappers (mode parity with each app.* counterpart).
-- ===========================================================================

create function public.broadcast_incident_communication(p_incident_id uuid, p_audience_code text, p_subject text, p_body text, p_template_config_version_id uuid, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.incident_communications
language sql
security definer
set search_path = app, public, pg_temp
as $$
  select app.broadcast_incident_communication(p_incident_id, p_audience_code, p_subject, p_body, p_template_config_version_id, p_idempotency_key, p_actor_auth_user_id, p_actor_label);
$$;

create function public.list_incident_communications(p_incident_id uuid, p_actor_auth_user_id uuid)
returns setof app.incident_communications
language sql
stable
security definer
set search_path = app, public, pg_temp
as $$
  select * from app.list_incident_communications(p_incident_id, p_actor_auth_user_id);
$$;

create function public.list_incident_communication_audiences()
returns setof app.incident_communication_audiences
language sql
stable
set search_path = app, public, pg_temp
as $$
  select * from app.list_incident_communication_audiences();
$$;

-- ===========================================================================
-- 8. Grants (ERR-2026-004).
-- ===========================================================================

revoke execute on all functions in schema app from public;

grant execute on function
  app.broadcast_incident_communication(uuid, text, text, text, uuid, text, uuid, text),
  app.list_incident_communications(uuid, uuid),
  app.list_incident_communication_audiences()
to authenticated, service_role;

revoke execute on function public.broadcast_incident_communication(uuid, text, text, text, uuid, text, uuid, text) from anon, authenticated, service_role, public;
grant execute on function public.broadcast_incident_communication(uuid, text, text, text, uuid, text, uuid, text) to authenticated, service_role;

revoke execute on function public.list_incident_communications(uuid, uuid) from anon, authenticated, service_role, public;
grant execute on function public.list_incident_communications(uuid, uuid) to authenticated, service_role;

revoke execute on function public.list_incident_communication_audiences() from anon, authenticated, service_role, public;
grant execute on function public.list_incident_communication_audiences() to authenticated, service_role;
