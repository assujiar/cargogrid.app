-- CG-AUDIT-2026-09-02 A3 remediation: publishing a role version silently revokes it from
-- everyone already holding it. `app.role_assignments.role_version_id` binds an assignment
-- to one SPECIFIC version, never the role in general; `app.evaluate_permission` requires
-- that version's own `status = 'published'` (its own header comment already conceded this
-- exact defect: "The join to role_versions on status = 'published' is what makes a stale
-- assignment... fail closed... No auto-reassignment to the new published version happens
-- anywhere in this repository; that is a disclosed, bounded limitation of this checkpoint,
-- not an oversight"). `app.publish_role_version` archives the prior published version but
-- never touches `app.role_assignments` at all -- so every real holder of that role loses
-- every permission it granted the moment ANYONE republishes a new version of the SAME
-- role, with no error, no warning, and no action on the assignment itself.
--
-- Fix: `app.publish_role_version` now migrates every ACTIVE assignment still bound to the
-- version it is about to archive onto the version it is publishing, in the same
-- transaction as the publish itself. Safe as a plain UPDATE -- can never violate
-- `role_assignments_active_unique (tenant_id, role_version_id, auth_user_id) where status =
-- 'active'`: nobody could hold an active assignment on `p_role_version_id` before this
-- function runs, since `app.assign_role` requires `status = 'published'` to assign at all,
-- and `p_role_version_id` was still a `draft` until the status flip a few lines above the
-- new UPDATE. A new `role_lifecycle_history` event, `version_migrated`, is recorded once
-- per migrated assignment (mirroring `assigned`/`revoked`'s own per-row convention) so the
-- migration is a real, auditable event, never a silent side effect.
--
-- Deliberately narrow, matching the audit's own A3 finding exactly: this does not touch
-- any OTHER "published version" binding pattern elsewhere in the repository (automation
-- rules, workflow definitions, approval definitions) -- the evaluator's own comment already
-- disclosed "no auto-reassignment... anywhere in this repository" as a repository-wide
-- posture, and this migration deliberately closes it for role_assignments/role_versions
-- only, the one the audit named and reproduced.

alter table app.role_lifecycle_history drop constraint role_lifecycle_history_event_type_check;
alter table app.role_lifecycle_history add constraint role_lifecycle_history_event_type_check check (event_type in (
  'role_created', 'version_drafted', 'permissions_set', 'published', 'cloned', 'archived', 'assigned', 'revoked',
  'version_migrated'
));

create or replace function app.publish_role_version(
  p_role_version_id uuid,
  p_effective_from timestamptz,
  p_published_by text
)
returns app.role_versions
language plpgsql
as $$
declare
  v_version app.role_versions;
  v_role app.roles;
  v_prior_published app.role_versions;
  v_updated app.role_versions;
begin
  select * into v_version from app.role_versions where id = p_role_version_id;
  if not found then
    raise exception 'role_version_not_found: no role version %', p_role_version_id
      using errcode = 'no_data_found';
  end if;

  if v_version.status <> 'draft' then
    raise exception 'role_version_not_draft: version % is %, only a draft may be published', p_role_version_id, v_version.status
      using errcode = 'check_violation';
  end if;

  select * into v_prior_published from app.role_versions where role_id = v_version.role_id and status = 'published';
  if found then
    update app.role_versions set status = 'archived', archived_at = now(), archived_reason = 'superseded by a newer published version'
    where id = v_prior_published.id;
  end if;

  update app.role_versions
  set status = 'published', published_by = p_published_by, published_at = now(), effective_from = p_effective_from
  where id = p_role_version_id
  returning * into v_updated;

  select * into v_role from app.roles where id = v_version.role_id;
  insert into app.role_lifecycle_history (role_id, role_version_id, tenant_id, event_type, requested_by)
  values (v_version.role_id, p_role_version_id, v_role.tenant_id, 'published', p_published_by);

  -- CG-AUDIT-2026-09-02 A3: carry every active holder of the version just archived above
  -- forward onto the version just published, so publishing never silently revokes access.
  -- One role_lifecycle_history row per migrated assignment, mirroring assign_role's/
  -- revoke_role_assignment's own per-row convention -- a real, auditable event, never a
  -- silent side effect of publishing.
  if v_prior_published.id is not null then
    with migrated as (
      update app.role_assignments
      set role_version_id = p_role_version_id
      where role_version_id = v_prior_published.id and status = 'active'
      returning id
    )
    insert into app.role_lifecycle_history (role_id, role_version_id, role_assignment_id, tenant_id, event_type, requested_by)
    select v_version.role_id, p_role_version_id, migrated.id, v_role.tenant_id, 'version_migrated', p_published_by
    from migrated;
  end if;

  return v_updated;
end;
$$;
