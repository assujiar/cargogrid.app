-- Real, executable test evidence for PLT-127 (Notification Engine, CG-S6-PLT-024).
--
-- This file also builds and proves the one safe, isolated, representative example the
-- migration header discloses as deliberately NOT seeded as migration data: a
-- `role_assignment_granted`-shaped notification with an in_app + email template.

\set ON_ERROR_STOP on

\echo '>> setup: two tenants each with a tenant_admin and a regular org_user, a global Supreme Admin'
do $$
declare
  v_tenant_id uuid;
  v_other_tenant_id uuid;
begin
  insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000001901', 'tenantadminnotif@example.test'),
    ('00000000-0000-0000-0000-000000001902', 'regularusernotif@example.test'),
    ('00000000-0000-0000-0000-000000001903', 'supremenotif@example.test'),
    ('00000000-0000-0000-0000-000000001904', 'othertenantadminnotif@example.test');

  perform app.provision_tenant('acmenotif', 'Acme Notification Co', 'idem-acmenotif', 'tester');
  v_tenant_id := (select id from app.tenants where slug = 'acmenotif');
  perform app.transition_tenant_status(v_tenant_id, 'active', 'setup', 'tester');
  perform app.invite_user(v_tenant_id, '00000000-0000-0000-0000-000000001901', 'tenantadminnotif@example.test', 'Tenant Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'tenantadminnotif@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000001901', 'tenant_admin', v_tenant_id, null, 'tester');

  perform app.invite_user(v_tenant_id, '00000000-0000-0000-0000-000000001902', 'regularusernotif@example.test', 'Regular User', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'regularusernotif@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000001902', 'org_user', v_tenant_id, null, 'tester');

  perform app.grant_principal_membership('00000000-0000-0000-0000-000000001903', 'supreme_admin', null, null, 'tester');

  perform app.provision_tenant('gizmonotif', 'Gizmo Notification Co', 'idem-gizmonotif', 'tester');
  v_other_tenant_id := (select id from app.tenants where slug = 'gizmonotif');
  perform app.transition_tenant_status(v_other_tenant_id, 'active', 'setup', 'tester');
  perform app.invite_user(v_other_tenant_id, '00000000-0000-0000-0000-000000001904', 'othertenantadminnotif@example.test', 'Other Tenant Admin', null, 'tester', now() + interval '7 days');
  perform app.transition_user_status((select id from app.users where email = 'othertenantadminnotif@example.test'), 'active', 'onboarded', 'tester');
  perform app.grant_principal_membership('00000000-0000-0000-0000-000000001904', 'tenant_admin', v_other_tenant_id, null, 'tester');
end;
$$;

\echo '>> app.register_notification_type: idempotent, Supreme-Admin-only, and mints a dedicated notification:<code> config_type (PLT-121''s registry reused, not forked)'
do $$
declare
  v_registered1 app.notification_types;
  v_registered2 app.notification_types;
  v_config_type_exists boolean;
begin
  begin
    perform app.register_notification_type('role_assignment_granted', 'Role Assignment Granted', 'NOTIF', '00000000-0000-0000-0000-000000001901', 'tenant admin');
    raise exception 'assertion failed: expected a tenant_admin (not Supreme Admin) to be denied registering a notification type';
  exception
    when insufficient_privilege then
      null;
  end;

  v_registered1 := app.register_notification_type('role_assignment_granted', 'Role Assignment Granted', 'NOTIF', '00000000-0000-0000-0000-000000001903', 'supreme admin');
  v_registered2 := app.register_notification_type('role_assignment_granted', 'Role Assignment Granted', 'NOTIF', '00000000-0000-0000-0000-000000001903', 'supreme admin');
  if v_registered1.code <> v_registered2.code then
    raise exception 'assertion failed: expected a repeated registration to be idempotent';
  end if;

  select exists (select 1 from app.config_types where code = 'notification:role_assignment_granted') into v_config_type_exists;
  if not v_config_type_exists then
    raise exception 'assertion failed: expected app.register_notification_type to also mint a notification:role_assignment_granted config_type';
  end if;
end;
$$;

\echo '>> app.validate_notification_template / app.publish_notification_template: every structural failure mode is a distinct, named exception; a valid in_app+email template publishes'
do $$
declare
  v_tenant_id uuid;
  v_draft app.config_versions;
  v_published app.config_versions;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmenotif');
  v_draft := app.create_config_draft('notification:role_assignment_granted', v_tenant_id, 'tenant', null, '00000000-0000-0000-0000-000000001901', 'tenant admin');

  -- notification_missing_channels
  begin
    perform app.publish_notification_template(v_draft.id, '00000000-0000-0000-0000-000000001901', null, 'tenant admin');
    raise exception 'assertion failed: expected a draft with no channels item to raise notification_missing_channels';
  exception
    when check_violation then
      if sqlerrm not like 'notification_missing_channels%' then
        raise exception 'assertion failed: expected notification_missing_channels, got %', sqlerrm;
      end if;
  end;

  -- notification_invalid_channel
  perform app.set_config_items(v_draft.id, jsonb_build_array(jsonb_build_object('key', 'channels', 'value', jsonb_build_array('sms'))), '00000000-0000-0000-0000-000000001901', 'tenant admin');
  begin
    perform app.publish_notification_template(v_draft.id, '00000000-0000-0000-0000-000000001901', null, 'tenant admin');
    raise exception 'assertion failed: expected channel=sms (not in the allowlist) to raise notification_invalid_channel';
  exception
    when check_violation then
      if sqlerrm not like 'notification_invalid_channel%' then
        raise exception 'assertion failed: expected notification_invalid_channel, got %', sqlerrm;
      end if;
  end;

  -- notification_invalid_locale (default_locale)
  perform app.set_config_items(v_draft.id, jsonb_build_array(
    jsonb_build_object('key', 'channels', 'value', jsonb_build_array('in_app')),
    jsonb_build_object('key', 'default_locale', 'value', 'fr')
  ), '00000000-0000-0000-0000-000000001901', 'tenant admin');
  begin
    perform app.publish_notification_template(v_draft.id, '00000000-0000-0000-0000-000000001901', null, 'tenant admin');
    raise exception 'assertion failed: expected default_locale=fr (not a supported PLT-119 locale) to raise notification_invalid_locale';
  exception
    when check_violation then
      if sqlerrm not like 'notification_invalid_locale%' then
        raise exception 'assertion failed: expected notification_invalid_locale, got %', sqlerrm;
      end if;
  end;

  -- notification_missing_default_template
  perform app.set_config_items(v_draft.id, jsonb_build_array(
    jsonb_build_object('key', 'channels', 'value', jsonb_build_array('in_app')),
    jsonb_build_object('key', 'default_locale', 'value', 'en'),
    jsonb_build_object('key', 'templates', 'value', jsonb_build_object('id', jsonb_build_object('subject', 'X', 'body', 'Y')))
  ), '00000000-0000-0000-0000-000000001901', 'tenant admin');
  begin
    perform app.publish_notification_template(v_draft.id, '00000000-0000-0000-0000-000000001901', null, 'tenant admin');
    raise exception 'assertion failed: expected templates missing the default_locale=en entry to raise notification_missing_default_template';
  exception
    when check_violation then
      if sqlerrm not like 'notification_missing_default_template%' then
        raise exception 'assertion failed: expected notification_missing_default_template, got %', sqlerrm;
      end if;
  end;

  -- notification_invalid_template_tokens (unbalanced braces)
  perform app.set_config_items(v_draft.id, jsonb_build_array(
    jsonb_build_object('key', 'channels', 'value', jsonb_build_array('in_app')),
    jsonb_build_object('key', 'default_locale', 'value', 'en'),
    jsonb_build_object('key', 'templates', 'value', jsonb_build_object('en', jsonb_build_object('subject', 'Hi {{role_name}', 'body', 'You got a role')))
  ), '00000000-0000-0000-0000-000000001901', 'tenant admin');
  begin
    perform app.publish_notification_template(v_draft.id, '00000000-0000-0000-0000-000000001901', null, 'tenant admin');
    raise exception 'assertion failed: expected unbalanced {{ }} braces in the subject to raise notification_invalid_template_tokens';
  exception
    when check_violation then
      if sqlerrm not like 'notification_invalid_template_tokens%' then
        raise exception 'assertion failed: expected notification_invalid_template_tokens, got %', sqlerrm;
      end if;
  end;

  -- Now the real, valid example: in_app + email, en + id locales.
  perform app.set_config_items(v_draft.id, jsonb_build_array(
    jsonb_build_object('key', 'channels', 'value', jsonb_build_array('in_app', 'email')),
    jsonb_build_object('key', 'default_locale', 'value', 'en'),
    jsonb_build_object('key', 'templates', 'value', jsonb_build_object(
      'en', jsonb_build_object('subject', 'You were granted the {{role_name}} role', 'body', 'Hi {{recipient_name}}, you now hold the {{role_name}} role in {{tenant_name}}.'),
      'id', jsonb_build_object('subject', 'Anda diberikan peran {{role_name}}', 'body', 'Halo {{recipient_name}}, Anda sekarang memegang peran {{role_name}} di {{tenant_name}}.')
    ))
  ), '00000000-0000-0000-0000-000000001901', 'tenant admin');

  begin
    perform app.publish_notification_template(v_draft.id, '00000000-0000-0000-0000-000000001902', null, 'regular user');
    raise exception 'assertion failed: expected a regular org_user to be denied publishing a tenant-scoped notification template';
  exception
    when insufficient_privilege then
      null;
  end;

  v_published := app.publish_notification_template(v_draft.id, '00000000-0000-0000-0000-000000001901', null, 'tenant admin');
  if v_published.status <> 'published' then
    raise exception 'assertion failed: expected the valid in_app+email template to publish, got %', v_published.status;
  end if;
end;
$$;

\echo '>> app.render_notification_template: locale-aware fallback, {{token}} substitution, unsafe-context-value rejection, and non-https:// link rejection'
do $$
declare
  v_tenant_id uuid;
  v_published_version_id uuid;
  v_rendered record;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmenotif');
  select v.id into v_published_version_id
  from app.config_versions v join app.config_objects o on o.id = v.config_object_id
  where o.tenant_id = v_tenant_id and o.config_type_code = 'notification:role_assignment_granted' and o.scope_level = 'tenant' and v.status = 'published';

  select * into v_rendered from app.render_notification_template(v_published_version_id, 'en', '{"role_name": "Manager", "recipient_name": "Budi", "tenant_name": "Acme Notification Co"}'::jsonb);
  if v_rendered.subject <> 'You were granted the Manager role' or v_rendered.body <> 'Hi Budi, you now hold the Manager role in Acme Notification Co.' then
    raise exception 'assertion failed: expected the en template to render with every token substituted, got subject=% body=%', v_rendered.subject, v_rendered.body;
  end if;

  select * into v_rendered from app.render_notification_template(v_published_version_id, 'id', '{"role_name": "Manajer", "recipient_name": "Budi", "tenant_name": "Acme Notification Co"}'::jsonb);
  if v_rendered.subject <> 'Anda diberikan peran Manajer' then
    raise exception 'assertion failed: expected the id-locale template to render, got %', v_rendered.subject;
  end if;

  -- Requesting an unconfigured locale ('fr') falls back to default_locale ('en').
  select * into v_rendered from app.render_notification_template(v_published_version_id, 'fr', '{"role_name": "Manager", "recipient_name": "Budi", "tenant_name": "Acme Notification Co"}'::jsonb);
  if v_rendered.subject <> 'You were granted the Manager role' then
    raise exception 'assertion failed: expected an unconfigured locale to fall back to default_locale=en, got %', v_rendered.subject;
  end if;

  begin
    perform app.render_notification_template(v_published_version_id, 'en', '{"role_name": "<script>alert(1)</script>", "recipient_name": "Budi", "tenant_name": "Acme"}'::jsonb);
    raise exception 'assertion failed: expected an angle-bracket context value to raise notification_unsafe_context_value';
  exception
    when check_violation then
      if sqlerrm not like 'notification_unsafe_context_value%' then
        raise exception 'assertion failed: expected notification_unsafe_context_value, got %', sqlerrm;
      end if;
  end;

  begin
    perform app.render_notification_template(v_published_version_id, 'en', '{"role_name": "javascript:alert(1)", "recipient_name": "Budi", "tenant_name": "Acme"}'::jsonb);
    raise exception 'assertion failed: expected a non-https:// URL-shaped context value to raise notification_unsafe_link';
  exception
    when check_violation then
      if sqlerrm not like 'notification_unsafe_link%' then
        raise exception 'assertion failed: expected notification_unsafe_link, got %', sqlerrm;
      end if;
  end;

  -- A real https:// link renders fine.
  select * into v_rendered from app.render_notification_template(v_published_version_id, 'en', '{"role_name": "https://acme.example.test/roles/manager", "recipient_name": "Budi", "tenant_name": "Acme"}'::jsonb);
  if v_rendered.subject <> 'You were granted the https://acme.example.test/roles/manager role' then
    raise exception 'assertion failed: expected a real https:// link context value to render fine';
  end if;
end;
$$;

\echo '>> app.queue_notification: requires a published template, is authority-gated, refuses an unauthorized/wrong-tenant recipient, idempotent on dedupe_key, and in_app delivery is real and immediate'
do $$
declare
  v_tenant_id uuid;
  v_published_version_id uuid;
  v_draft_version_id uuid;
  v_notif1 app.notifications;
  v_notif2 app.notifications;
  v_context jsonb := '{"role_name": "Manager", "recipient_name": "Regular User", "tenant_name": "Acme Notification Co"}'::jsonb;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmenotif');
  select v.id into v_published_version_id
  from app.config_versions v join app.config_objects o on o.id = v.config_object_id
  where o.tenant_id = v_tenant_id and o.config_type_code = 'notification:role_assignment_granted' and o.scope_level = 'tenant' and v.status = 'published';

  v_draft_version_id := (app.create_config_draft('notification:role_assignment_granted', v_tenant_id, 'tenant', null, '00000000-0000-0000-0000-000000001901', 'tenant admin')).id;
  begin
    perform app.queue_notification(v_draft_version_id, v_tenant_id, 'role_assignment_granted', '00000000-0000-0000-0000-000000001902', 'in_app', 'en', v_context, 'notif-bad', '00000000-0000-0000-0000-000000001901', 'tenant admin');
    raise exception 'assertion failed: expected queuing against a non-published version to raise notification_template_not_published';
  exception
    when check_violation then
      if sqlerrm not like 'notification_template_not_published%' then
        raise exception 'assertion failed: expected notification_template_not_published, got %', sqlerrm;
      end if;
  end;
  perform app.discard_config_draft(v_draft_version_id, '00000000-0000-0000-0000-000000001901', 'cleanup', 'tenant admin');

  begin
    perform app.queue_notification(v_published_version_id, v_tenant_id, 'role_assignment_granted', '00000000-0000-0000-0000-000000001902', 'in_app', 'en', v_context, 'notif-1', '00000000-0000-0000-0000-000000001904', 'other tenant admin');
    raise exception 'assertion failed: expected an identity with no membership in acmenotif to be denied triggering a send there';
  exception
    when insufficient_privilege then
      null;
  end;

  -- The recipient itself must be an active member of the target tenant, never
  -- a wrong-tenant/deactivated identity (Prompt 127 §16/§23/§25).
  begin
    perform app.queue_notification(v_published_version_id, v_tenant_id, 'role_assignment_granted', '00000000-0000-0000-0000-000000001904', 'in_app', 'en', v_context, 'notif-wrong-tenant', '00000000-0000-0000-0000-000000001901', 'tenant admin');
    raise exception 'assertion failed: expected queuing for a recipient with no membership in the target tenant to raise notification_recipient_unauthorized';
  exception
    when insufficient_privilege then
      if sqlerrm not like 'notification_recipient_unauthorized%' then
        raise exception 'assertion failed: expected notification_recipient_unauthorized, got %', sqlerrm;
      end if;
  end;

  v_notif1 := app.queue_notification(v_published_version_id, v_tenant_id, 'role_assignment_granted', '00000000-0000-0000-0000-000000001902', 'in_app', 'en', v_context, 'notif-1', '00000000-0000-0000-0000-000000001901', 'tenant admin');
  if v_notif1.status <> 'sent' or v_notif1.effective_channel <> 'in_app' or v_notif1.subject <> 'You were granted the Manager role' then
    raise exception 'assertion failed: expected an in_app notification to be delivered (status=sent) immediately with its subject rendered, got status=% channel=% subject=%', v_notif1.status, v_notif1.effective_channel, v_notif1.subject;
  end if;

  -- Idempotent replay: the same dedupe_key never creates a second notification.
  v_notif2 := app.queue_notification(v_published_version_id, v_tenant_id, 'role_assignment_granted', '00000000-0000-0000-0000-000000001902', 'in_app', 'en', v_context, 'notif-1', '00000000-0000-0000-0000-000000001901', 'tenant admin');
  if v_notif2.id <> v_notif1.id then
    raise exception 'assertion failed: expected a repeated queue_notification call with the same dedupe_key to return the existing notification, not create a second one';
  end if;

  -- A non-in_app channel is real only up through "queued" -- no live provider send
  -- exists anywhere in this repository (this migration's own header).
  if (app.queue_notification(v_published_version_id, v_tenant_id, 'role_assignment_granted', '00000000-0000-0000-0000-000000001902', 'email', 'en', v_context, 'notif-2', '00000000-0000-0000-0000-000000001901', 'tenant admin')).status <> 'queued' then
    raise exception 'assertion failed: expected the email channel to stop at status=queued, never a real send';
  end if;
end;
$$;

\echo '>> app.set_notification_preference / preference-aware fallback: a disabled requested channel falls back to in_app when allowed and not itself disabled; otherwise the attempt is recorded as skipped'
do $$
declare
  v_tenant_id uuid;
  v_published_version_id uuid;
  v_context jsonb := '{"role_name": "Manager", "recipient_name": "Regular User", "tenant_name": "Acme Notification Co"}'::jsonb;
  v_pref app.notification_preferences;
  v_fallback_notif app.notifications;
  v_skipped_notif app.notifications;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmenotif');
  select v.id into v_published_version_id
  from app.config_versions v join app.config_objects o on o.id = v.config_object_id
  where o.tenant_id = v_tenant_id and o.config_type_code = 'notification:role_assignment_granted' and o.scope_level = 'tenant' and v.status = 'published';

  begin
    perform app.set_notification_preference(v_tenant_id, '00000000-0000-0000-0000-000000001902', 'role_assignment_granted', 'email', false, '00000000-0000-0000-0000-000000001904', 'other tenant admin');
    raise exception 'assertion failed: expected a non-self, non-support-authority actor to be denied setting someone else''s preference';
  exception
    when insufficient_privilege then
      null;
  end;

  -- Self-service: the regular user disables their own email channel for this type.
  v_pref := app.set_notification_preference(v_tenant_id, '00000000-0000-0000-0000-000000001902', 'role_assignment_granted', 'email', false, '00000000-0000-0000-0000-000000001902', 'regular user');
  if v_pref.enabled <> false then
    raise exception 'assertion failed: expected the email preference to be disabled';
  end if;

  -- Requesting email now falls back to in_app (allowed by the definition, not disabled).
  v_fallback_notif := app.queue_notification(v_published_version_id, v_tenant_id, 'role_assignment_granted', '00000000-0000-0000-0000-000000001902', 'email', 'en', v_context, 'notif-fallback-1', '00000000-0000-0000-0000-000000001901', 'tenant admin');
  if v_fallback_notif.requested_channel <> 'email' or v_fallback_notif.effective_channel <> 'in_app' or v_fallback_notif.status <> 'sent' then
    raise exception 'assertion failed: expected requested_channel=email effective_channel=in_app status=sent (the fallback), got requested=% effective=% status=%', v_fallback_notif.requested_channel, v_fallback_notif.effective_channel, v_fallback_notif.status;
  end if;

  -- Tenant admin (support-grant authority) may set it on the user's behalf: now also disable in_app.
  perform app.set_notification_preference(v_tenant_id, '00000000-0000-0000-0000-000000001902', 'role_assignment_granted', 'in_app', false, '00000000-0000-0000-0000-000000001901', 'tenant admin');

  -- With both channels disabled, the attempt is recorded as skipped, never silently dropped.
  v_skipped_notif := app.queue_notification(v_published_version_id, v_tenant_id, 'role_assignment_granted', '00000000-0000-0000-0000-000000001902', 'email', 'en', v_context, 'notif-skipped-1', '00000000-0000-0000-0000-000000001901', 'tenant admin');
  if v_skipped_notif.status <> 'skipped' then
    raise exception 'assertion failed: expected status=skipped once both requested and fallback channels are disabled, got %', v_skipped_notif.status;
  end if;

  -- app.get_notification_preferences: self-service read, and denial for an unrelated actor.
  if (select count(*) from app.get_notification_preferences(v_tenant_id, '00000000-0000-0000-0000-000000001902', '00000000-0000-0000-0000-000000001902')) <> 2 then
    raise exception 'assertion failed: expected exactly 2 preference rows (email, in_app) for the regular user';
  end if;
  begin
    perform app.get_notification_preferences(v_tenant_id, '00000000-0000-0000-0000-000000001902', '00000000-0000-0000-0000-000000001904');
    raise exception 'assertion failed: expected an unrelated actor (no self-match, no support-grant authority in this tenant) to be denied reading another identity''s preferences';
  exception
    when insufficient_privilege then
      null;
  end;
end;
$$;

\echo '>> app.record_notification_delivery_attempt (the bounded adapter interface) / app.mark_notification_read / app.list_notifications_for_recipient / app.count_unread_notifications'
do $$
declare
  v_tenant_id uuid;
  v_queued_notif_id uuid;
  v_attempt1 app.notification_delivery_attempts;
  v_attempt2 app.notification_delivery_attempts;
  v_updated app.notifications;
  v_unread_before integer;
  v_unread_after integer;
  v_inbox_count integer;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmenotif');
  select id into v_queued_notif_id from app.notifications where tenant_id = v_tenant_id and dedupe_key = 'notif-2';

  v_attempt1 := app.record_notification_delivery_attempt(v_queued_notif_id, 'failed', 'provider timeout', '00000000-0000-0000-0000-000000001901', 'tenant admin');
  if v_attempt1.attempt_number <> 1 or v_attempt1.status <> 'failed' then
    raise exception 'assertion failed: expected attempt_number=1 status=failed, got attempt_number=% status=%', v_attempt1.attempt_number, v_attempt1.status;
  end if;
  if (select status from app.notifications where id = v_queued_notif_id) <> 'failed' then
    raise exception 'assertion failed: expected the notification''s own status to flip to failed after a failed attempt';
  end if;

  -- A second, successful attempt -- real retry evidence (Prompt 127 §17/§28).
  v_attempt2 := app.record_notification_delivery_attempt(v_queued_notif_id, 'success', null, '00000000-0000-0000-0000-000000001901', 'tenant admin');
  if v_attempt2.attempt_number <> 2 or v_attempt2.status <> 'success' then
    raise exception 'assertion failed: expected attempt_number=2 status=success on retry, got attempt_number=% status=%', v_attempt2.attempt_number, v_attempt2.status;
  end if;
  if (select status from app.notifications where id = v_queued_notif_id) <> 'sent' then
    raise exception 'assertion failed: expected the notification''s own status to flip to sent after a successful retry';
  end if;

  v_unread_before := app.count_unread_notifications(v_tenant_id, '00000000-0000-0000-0000-000000001902', '00000000-0000-0000-0000-000000001902');
  if v_unread_before < 2 then
    raise exception 'assertion failed: expected at least 2 unread in_app notifications for the regular user, saw %', v_unread_before;
  end if;

  begin
    perform app.mark_notification_read((select id from app.notifications where tenant_id = v_tenant_id and dedupe_key = 'notif-1'), '00000000-0000-0000-0000-000000001904', 'other tenant admin');
    raise exception 'assertion failed: expected an identity that is not the recipient to be denied marking a notification read';
  exception
    when insufficient_privilege then
      null;
  end;

  v_updated := app.mark_notification_read((select id from app.notifications where tenant_id = v_tenant_id and dedupe_key = 'notif-1'), '00000000-0000-0000-0000-000000001902', 'regular user');
  if v_updated.read_at is null then
    raise exception 'assertion failed: expected read_at to be set after marking read';
  end if;

  v_unread_after := app.count_unread_notifications(v_tenant_id, '00000000-0000-0000-0000-000000001902', '00000000-0000-0000-0000-000000001902');
  if v_unread_after <> v_unread_before - 1 then
    raise exception 'assertion failed: expected the unread count to drop by exactly 1, was % now %', v_unread_before, v_unread_after;
  end if;

  select count(*) into v_inbox_count from app.list_notifications_for_recipient(v_tenant_id, '00000000-0000-0000-0000-000000001902', '00000000-0000-0000-0000-000000001902', false);
  if v_inbox_count < 3 then
    raise exception 'assertion failed: expected the regular user''s full inbox to contain at least 3 notifications, saw %', v_inbox_count;
  end if;

  begin
    perform app.list_notifications_for_recipient(v_tenant_id, '00000000-0000-0000-0000-000000001902', '00000000-0000-0000-0000-000000001904', false);
    raise exception 'assertion failed: expected an unrelated identity to be denied listing another identity''s inbox';
  exception
    when insufficient_privilege then
      null;
  end;
end;
$$;

\echo '>> every notification lifecycle mutation self-captures a canonical app.audit_logs entry (no bespoke *_history table -- app.notification_delivery_attempts exists only for retry evidence, and is itself audited too)'
do $$
declare
  v_tenant_id uuid;
  v_actions text[] := array['queue_notification', 'set_notification_preference', 'record_notification_delivery_attempt', 'mark_notification_read'];
  v_action text;
  v_count integer;
begin
  v_tenant_id := (select id from app.tenants where slug = 'acmenotif');

  foreach v_action in array v_actions loop
    select count(*) into v_count from app.audit_logs where tenant_id = v_tenant_id and action = v_action;
    if v_count = 0 then
      raise exception 'assertion failed: expected at least one app.audit_logs entry for action=%, saw none', v_action;
    end if;
  end loop;

  select count(*) into v_count from app.audit_logs where action = 'register_notification_type' and tenant_id is null;
  if v_count = 0 then
    raise exception 'assertion failed: expected a platform-wide (null tenant_id) audit entry for register_notification_type';
  end if;
end;
$$;

\echo '>> schema-privilege defense in depth: authenticated has self-scoped SELECT on notifications/preferences but none on delivery_attempts; anon holds no EXECUTE on service_role-only mutations (ERR-2026-004 regression guard)'
do $$
declare
  v_has_privilege boolean;
begin
  select has_table_privilege('authenticated', 'app.notifications', 'SELECT') into v_has_privilege;
  if not v_has_privilege then
    raise exception 'assertion failed: expected authenticated to hold direct SELECT on app.notifications (self-scoped by RLS)';
  end if;

  select has_table_privilege('authenticated', 'app.notification_delivery_attempts', 'SELECT') into v_has_privilege;
  if v_has_privilege then
    raise exception 'assertion failed: expected authenticated to hold no direct SELECT on app.notification_delivery_attempts';
  end if;

  select has_table_privilege('anon', 'app.notifications', 'SELECT') into v_has_privilege;
  if v_has_privilege then
    raise exception 'assertion failed: expected anon to hold no privilege on app.notifications at all';
  end if;

  select has_function_privilege('authenticated', 'app.mark_notification_read(uuid, uuid, text)', 'EXECUTE') into v_has_privilege;
  if not v_has_privilege then
    raise exception 'assertion failed: expected authenticated to hold EXECUTE on app.mark_notification_read';
  end if;

  select has_function_privilege('anon', 'app.mark_notification_read(uuid, uuid, text)', 'EXECUTE') into v_has_privilege;
  if v_has_privilege then
    raise exception 'assertion failed: expected anon to hold no EXECUTE on app.mark_notification_read';
  end if;

  select has_function_privilege('anon', 'app.queue_notification(uuid, uuid, text, uuid, text, text, jsonb, text, uuid, text)', 'EXECUTE') into v_has_privilege;
  if v_has_privilege then
    raise exception 'assertion failed: expected anon to hold no EXECUTE on the service_role-only app.queue_notification (ERR-2026-004 regression guard)';
  end if;

  select has_function_privilege('anon', 'app.register_notification_type(text, text, text, uuid, text)', 'EXECUTE') into v_has_privilege;
  if v_has_privilege then
    raise exception 'assertion failed: expected anon to hold no EXECUTE on the service_role-only app.register_notification_type (ERR-2026-004 regression guard)';
  end if;
end;
$$;
