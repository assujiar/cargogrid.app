-- Security/hardening: relocate `pg_trgm` and `btree_gist` out of the `public` schema
-- (closes the `pg_trgm`/`btree_gist` portion of the `extension_in_public` Supabase
-- linter advisories; part of the full-system-hardening matrix).
--
-- Both extensions were created unqualified (`create extension if not exists pg_trgm`
-- / `create extension if not exists btree_gist` with no `schema` clause), which lands
-- them in `public` -- a schema every authenticated role can create objects in. An
-- extension's functions/operators living in `public` means any role that can widen
-- its own `search_path` (or any function that resolves `public` ahead of a
-- more-trusted schema) can potentially get a same-named user-defined function/operator
-- resolved instead of the extension's, a function-shadowing / search-path-hijack
-- surface. Both `pg_trgm` and `btree_gist` are relocatable (their control files do not
-- set `relocatable = false`), so `ALTER EXTENSION ... SET SCHEMA` is a safe, in-place,
-- non-destructive move: the extension keeps its existing objects and OIDs, only the
-- schema they resolve from changes.
--
-- `postgis` is explicitly OUT OF SCOPE for this migration and is NOT touched here.
-- `postgis`'s own control file sets `relocatable = false` -- `ALTER EXTENSION postgis
-- SET SCHEMA ...` fails outright. Moving it would require `DROP EXTENSION postgis
-- CASCADE` + recreate in a new schema, which cascades and destroys the 15 live
-- `geography`-typed columns across 12 tables that depend on the `postgis` extension's
-- types. That is a materially larger, destructive, non-additive change and is out of
-- scope for this bounded migration; it is being registered separately in
-- docs/runtime/KNOWN_ISSUES.md by the orchestrating session, not fixed here.
--
-- `btree_gist` is consumed only via GIST index / EXCLUDE-constraint operator classes,
-- which bind by OID at DDL time -- moving the extension's schema does not change those
-- OIDs, so no index/constraint DDL and no function bodies need any change for
-- `btree_gist`; the `ALTER EXTENSION ... SET SCHEMA` statement below is sufficient on
-- its own.
--
-- `pg_trgm` additionally requires each function that calls its `similarity()` operator
-- directly (not via an operator class bound by OID) to have `extensions` on its own
-- pinned `search_path` GUC, otherwise `similarity(...)` fails to resolve once the
-- function is no longer found in `public`. Exactly 3 live functions call bare
-- `similarity()` inside a pinned `search_path` that does not already include wherever
-- pg_trgm ends up: `app.search_employee_duplicate_candidates`,
-- `app.search_vendor_duplicate_candidates`, `app.search_candidate_duplicates`. Each is
-- redefined below with `extensions` added to its existing `search_path` (before
-- `pg_temp`); the body and signature of each are otherwise byte-identical to their
-- current live definition (supabase/migrations/20260730830000_create_hris_employee_
-- master.sql, 20260730580000_create_procurement_vendor_registration.sql,
-- 20260730860000_create_hris_recruitment_ats.sql respectively) -- copied, not
-- rewritten. All other functions that reference `similarity`/`%`/GIST operators do so
-- only through operator invocations bound by OID at DDL time (e.g. `col % pattern`,
-- GIN/GIST index expressions), which are unaffected by the extension's schema move.

create schema if not exists extensions;

alter extension pg_trgm set schema extensions;
alter extension btree_gist set schema extensions;

-- app.search_employee_duplicate_candidates (HRT-274) -- body/signature unchanged from
-- supabase/migrations/20260730830000_create_hris_employee_master.sql; only
-- `search_path` gains `extensions` (added before `pg_temp`).
create or replace function app.search_employee_duplicate_candidates(p_tenant_id uuid, p_full_name text, p_national_id_number text, p_work_email text, p_personal_email text, p_actor_auth_user_id uuid, p_limit integer default 10)
returns table (master_record_id uuid, employee_number text, full_name text, similarity_score real, match_basis text)
language plpgsql
security definer
set search_path = app, public, extensions, pg_temp
as $$
declare
  v_decision app.rbac_decision;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'HRS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
  select e.master_record_id, m.code, e.full_name,
         case
           when p_national_id_number is not null and e.national_id_number = p_national_id_number then 1.0::real
           when p_work_email is not null and e.work_email = p_work_email then 1.0::real
           when p_personal_email is not null and e.personal_email = p_personal_email then 1.0::real
           else similarity(e.full_name, coalesce(p_full_name, ''))
         end as score,
         case
           when p_national_id_number is not null and e.national_id_number = p_national_id_number then 'national_id_number exact match'
           when p_work_email is not null and e.work_email = p_work_email then 'work_email exact match'
           when p_personal_email is not null and e.personal_email = p_personal_email then 'personal_email exact match'
           else 'full_name trigram similarity'
         end as basis
  from app.employees e
  join app.master_records m on m.id = e.master_record_id
  where e.tenant_id = p_tenant_id
    and (
      (p_national_id_number is not null and e.national_id_number = p_national_id_number)
      or (p_work_email is not null and e.work_email = p_work_email)
      or (p_personal_email is not null and e.personal_email = p_personal_email)
      or (p_full_name is not null and e.full_name % p_full_name)
    )
  order by score desc
  limit least(coalesce(p_limit, 10), 50);
end;
$$;

-- app.search_vendor_duplicate_candidates (PRC-251) -- body/signature unchanged from
-- supabase/migrations/20260730580000_create_procurement_vendor_registration.sql; only
-- `search_path` gains `extensions` (added before `pg_temp`).
create or replace function app.search_vendor_duplicate_candidates(p_tenant_id uuid, p_legal_name text, p_trade_name text, p_actor_auth_user_id uuid, p_limit integer default 10)
returns table (master_record_id uuid, vendor_code text, legal_name text, trade_name text, similarity_score real)
language plpgsql
security definer
set search_path = app, public, extensions, pg_temp
as $$
declare
  v_decision app.rbac_decision;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_legal_name is null or length(trim(p_legal_name)) = 0 then
    raise exception 'invalid_legal_name: legal_name must not be empty' using errcode = 'check_violation';
  end if;

  return query
  select vp.master_record_id, m.code, vp.legal_name, vp.trade_name,
         greatest(similarity(vp.legal_name, p_legal_name), coalesce(similarity(vp.trade_name, coalesce(p_trade_name, p_legal_name)), 0)) as score
  from app.vendor_profiles vp
  join app.master_records m on m.id = vp.master_record_id
  where vp.tenant_id = p_tenant_id
    and (vp.legal_name % p_legal_name or (p_trade_name is not null and vp.trade_name % p_trade_name))
  order by score desc
  limit least(coalesce(p_limit, 10), 50);
end;
$$;

-- app.search_candidate_duplicates (recruitment ATS) -- body/signature unchanged from
-- supabase/migrations/20260730860000_create_hris_recruitment_ats.sql; only
-- `search_path` gains `extensions` (added before `pg_temp`).
create or replace function app.search_candidate_duplicates(p_tenant_id uuid, p_full_name text, p_email text, p_phone text, p_actor_auth_user_id uuid, p_limit integer default 10)
returns table (id uuid, full_name text, similarity_basis text, similarity_score numeric)
language plpgsql
stable
security definer
set search_path = app, public, extensions, pg_temp
as $$
declare
  v_decision app.rbac_decision;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'HRS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks HRS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
  select * from (
    select c.id, c.full_name, 'exact_email'::text as similarity_basis, 1.0::numeric as similarity_score
    from app.candidates c
    where c.tenant_id = p_tenant_id and p_email is not null and lower(c.email) = lower(p_email)
    union all
    select c.id, c.full_name, 'exact_phone'::text, 1.0::numeric
    from app.candidates c
    where c.tenant_id = p_tenant_id and p_phone is not null and c.phone = p_phone
    union all
    select c.id, c.full_name, 'fuzzy_name'::text, similarity(c.full_name, coalesce(p_full_name, ''))::numeric
    from app.candidates c
    where c.tenant_id = p_tenant_id and p_full_name is not null and similarity(c.full_name, p_full_name) > 0.4
  ) matches
  order by similarity_score desc
  limit least(coalesce(p_limit, 10), 50);
end;
$$;
