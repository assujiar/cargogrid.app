-- Self-found-and-fixed correctness gap in 20260902070000 (ISS-2026-122 item
-- 2), caught while authoring this same fix's own db-test evidence rather
-- than left for a reviewer: app.authorize_file_access's own real record-
-- access gate (20260719140000_create_document_file_engine.sql) is a THREE-
-- arm OR -- `is_supreme_admin OR can_access_record OR is_support_grant_
-- authority` -- but app.staff_document_ticket_link_access_ok (this same
-- migration set, applied minutes earlier) only composed TWO of the three
-- (uploaded_by=actor as a substitute for the ownership check, plus can_
-- access_record), omitting is_supreme_admin and is_support_grant_authority
-- from that arm entirely (they were only applied to the SEPARATE
-- restricted/credential classification gate below it). A tenant_admin
-- (is_support_grant_authority=true) or a Supreme Admin resolving a document
-- they neither uploaded nor share an org unit/customer-account tie to would
-- have been incorrectly denied -- under-scoped, not over-scoped (never a
-- leak), but not the faithful mirror of app.authorize_file_access's own
-- logic this migration's own header claimed. Fixed here, additively,
-- before any db-test evidence was written against the wrong shape.

create or replace function app.staff_document_ticket_link_access_ok(
  p_actor_auth_user_id uuid,
  p_tenant_id uuid,
  p_uploaded_by_auth_user_id uuid,
  p_shared_org_unit_ids uuid[],
  p_customer_account_ref text,
  p_classification text
)
returns boolean
language sql
stable
security definer
set search_path = app, pg_temp
as $$
  select
    app.check_file_action_authority(p_tenant_id, p_actor_auth_user_id)
    and (
      p_uploaded_by_auth_user_id = p_actor_auth_user_id
      or app.is_supreme_admin(p_actor_auth_user_id)
      or app.can_access_record(p_actor_auth_user_id, p_tenant_id, p_uploaded_by_auth_user_id, p_shared_org_unit_ids, p_customer_account_ref)
      or app.is_support_grant_authority(p_actor_auth_user_id, p_tenant_id)
    )
    and (
      p_classification not in ('restricted', 'credential')
      or p_uploaded_by_auth_user_id = p_actor_auth_user_id
      or app.is_supreme_admin(p_actor_auth_user_id)
      or app.is_support_grant_authority(p_actor_auth_user_id, p_tenant_id)
    );
$$;

comment on function app.staff_document_ticket_link_access_ok is
  'ISS-2026-122 item 2 (2026-09-02, corrected same-day): the read-only subset of app.authorize_file_access''s own per-row authority logic -- its full THREE-arm record-access gate (is_supreme_admin OR can_access_record OR is_support_grant_authority), not a two-arm subset -- plus the same restricted/credential classification gate, factored out as a boolean predicate with no app.file_access_logs write.';
