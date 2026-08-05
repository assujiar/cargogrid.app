-- LOAD-TEST-ONLY helper functions (CG-S10-ATW-024, Prompt 243). Never a
-- migration, never applied to a real database -- loaded only by scripts/load-
-- tests/run.sh into its own disposable load-test database, after every real
-- supabase/migrations/*.sql has already been applied. Mirrors scripts/db-tests/
-- fixtures/auth-schema-stub.sql's own "local test fixture only" convention.
--
-- Why these exist: app.claim_wms_pick_task/app.claim_wms_putaway_task each claim
-- ONE SPECIFIC already-known task_id + record_version (design: the caller already
-- knows which task it wants, e.g. from a worklist UI). A load-test worker instead
-- needs to behave like N independent pickers/putaway staff polling for "any next
-- available task" -- there is no production RPC for that (by design: task
-- assignment/worklist UX is out of this repository's own scope, ISS-2026-015).
-- These two functions do ONLY the candidate-selection half (SELECT ... FOR UPDATE
-- SKIP LOCKED, so many concurrent pollers never pile up blocking each other for a
-- task some other poller is about to claim) and then delegate the actual mutation
-- to the real, unmodified app.claim_wms_pick_task/app.claim_wms_putaway_task RPCs
-- -- the real FOR UPDATE + record_version check inside those functions is exactly
-- what this load scenario measures for exactly-once-claim safety, never bypassed
-- or reimplemented here.

create schema if not exists loadtest;

comment on schema loadtest is
  'LOAD-TEST-ONLY, never a real product schema -- see this file''s own header. Holds only the two candidate-selection helpers below.';

create or replace function loadtest.claim_any_pick_task(p_actor_auth_user_id uuid, p_actor_label text)
returns app.wms_pick_tasks
language plpgsql
as $$
declare
  v_candidate record;
begin
  select id, record_version into v_candidate
  from app.wms_pick_tasks
  where status = 'unclaimed'
  order by id
  for update skip locked
  limit 1;

  if not found then
    return null;
  end if;

  return app.claim_wms_pick_task(v_candidate.id, v_candidate.record_version, p_actor_auth_user_id, p_actor_label);
end;
$$;

create or replace function loadtest.claim_any_putaway_task(p_actor_auth_user_id uuid, p_actor_label text)
returns app.wms_putaway_tasks
language plpgsql
as $$
declare
  v_candidate record;
begin
  select id, record_version into v_candidate
  from app.wms_putaway_tasks
  where status = 'unclaimed'
  order by id
  for update skip locked
  limit 1;

  if not found then
    return null;
  end if;

  return app.claim_wms_putaway_task(v_candidate.id, v_candidate.record_version, p_actor_auth_user_id, p_actor_label);
end;
$$;
