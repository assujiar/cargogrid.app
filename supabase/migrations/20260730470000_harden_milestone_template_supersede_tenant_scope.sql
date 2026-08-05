-- CG-S10-ATW-032 (post-Prompt-248 audit) — cross-tenant write in milestone template supersede.
--
-- `app.publish_milestone_template_version` resolves its supersede target by id ALONE:
--
--   select * into v_superseded from app.milestone_template_versions where id = p_supersedes_version_id;
--   ...
--   update app.milestone_template_versions set status = 'archived' where id = p_supersedes_version_id;
--
-- while the authority check above it is evaluated against `v_version.tenant_id` — the tenant
-- of the version being PUBLISHED, not the tenant of the version being archived. A tenant
-- admin acting entirely legitimately within their own tenant could therefore pass another
-- tenant's published template version id and archive it.
--
-- That is a cross-tenant WRITE by an ordinary tenant-scoped actor, which is exactly what
-- `CPD-004` (multi-tenant isolation) and `INV-002` exist to prevent, and it is not covered
-- by the `RPD-022` Supreme Admin exception — this is reachable by a normal tenant admin.
--
-- Repair: require the supersede target to belong to the same tenant as the version being
-- published. It raises the same `milestone_template_not_found` the id-miss path already
-- raises, deliberately — a cross-tenant id must be indistinguishable from a non-existent
-- one, so the error cannot be used to probe for the existence of another tenant's records.
--
-- Found by the ATW-031 audit fan-out and confirmed by direct inspection of the live
-- function definition. Additive: one `CREATE OR REPLACE FUNCTION` on an identical
-- signature; no table, grant or policy touched.
--
-- Per `ERR-2026-004`: this migration carries its own explicit `revoke execute on all
-- functions in schema app from public` before its final grant.

CREATE OR REPLACE FUNCTION app.publish_milestone_template_version(p_version_id uuid, p_expected_version integer, p_supersedes_version_id uuid, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.milestone_template_versions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_version app.milestone_template_versions;
  v_superseded app.milestone_template_versions;
  v_decision app.rbac_decision;
  v_element jsonb;
  v_seen text[] := array[]::text[];
  v_code text;
begin
  select * into v_version from app.milestone_template_versions where id = p_version_id;
  if not found then
    raise exception 'milestone_template_not_found: %', p_version_id using errcode = 'no_data_found';
  end if;
  if v_version.record_version <> p_expected_version then
    raise exception 'stale_version: milestone template % expected version % but found %', p_version_id, p_expected_version, v_version.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_version.status <> 'draft' then
    raise exception 'invalid_transition: milestone template % is % and cannot be published', p_version_id, v_version.status
      using errcode = 'check_violation';
  end if;
  if jsonb_array_length(v_version.sequence) = 0 then
    raise exception 'milestone_invalid_sequence: a milestone template cannot publish with an empty sequence' using errcode = 'check_violation';
  end if;

  for v_element in select * from jsonb_array_elements(v_version.sequence) loop
    v_code := v_element ->> 'code';
    if not exists (select 1 from app.milestone_codes where code = v_code) then
      raise exception 'milestone_unknown_code: % is not a registered milestone code', v_code using errcode = 'check_violation';
    end if;
    if v_code = any (v_seen) then
      raise exception 'milestone_duplicate_code: % appears more than once in the sequence', v_code using errcode = 'check_violation';
    end if;
    v_seen := array_append(v_seen, v_code);
  end loop;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_version.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_version.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_supersedes_version_id is not null then
    select * into v_superseded from app.milestone_template_versions where id = p_supersedes_version_id;
    if not found then
      raise exception 'milestone_template_not_found: supersedes target % not found', p_supersedes_version_id using errcode = 'no_data_found';
    end if;
    -- ATW-032: the supersede target was previously resolved by id ALONE and then archived,
    -- while the authority check above is against the tenant of the version being PUBLISHED.
    -- A tenant admin could therefore pass another tenant's published template version id and
    -- archive it -- a cross-tenant write, and exactly the class CPD-004/INV-002 exist to
    -- prevent. The target must belong to the same tenant as the version being published.
    if v_superseded.tenant_id <> v_version.tenant_id then
      raise exception 'milestone_template_not_found: supersedes target % is not a template version of tenant %', p_supersedes_version_id, v_version.tenant_id
        using errcode = 'no_data_found';
    end if;
    if v_superseded.status = 'published' then
      update app.milestone_template_versions set status = 'archived' where id = p_supersedes_version_id;
    end if;
  end if;

  update app.milestone_template_versions
  set status = 'published', supersedes_version_id = p_supersedes_version_id
  where id = p_version_id and record_version = p_expected_version
  returning * into v_version;

  perform app.capture_audit_event(
    v_version.tenant_id, p_actor_auth_user_id, p_actor_label, 'publish_milestone_template_version',
    'app.milestone_template_versions', v_version.id, 'success', null, null,
    jsonb_build_object('mode', v_version.mode, 'supersedes_version_id', p_supersedes_version_id)
  );

  return v_version;
end;
$function$;


revoke execute on all functions in schema app from public;

grant execute on function app.publish_milestone_template_version(uuid,integer,uuid,uuid,text) to authenticated, service_role;
