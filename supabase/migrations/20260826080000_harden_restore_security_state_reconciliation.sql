-- ISS-2026-254 (Step 16 historical-issue-backlog remediation, docs/runtime/KNOWN_ISSUES.md)
-- -- a database restore to a point predating an active legal hold, a revoked API key/
-- webhook endpoint, or a suspended/revoked user/membership silently reverts that
-- decision, with no compensating control: the row that recorded the decision is simply
-- gone after restoring an older backup, and so is any audit_logs trail of it (the SAME
-- backup snapshot that lost the decision also lost its own audit trail -- comparing
-- WITHIN the restored database finds nothing to compare against, by construction).
--
-- What this migration does NOT and cannot fix: there is no way to detect, from inside a
-- restored database alone, that something is now missing which the database itself has
-- no memory of ever having had. This entry's own text correctly says the real fix
-- ("never restore to a point predating the earliest active hold/revocation/suspension,"
-- or "a real, platform-wide, live-queried export/reconciliation tool") is a genuine
-- product/legal/security design decision, not a bounded mechanical repair.
--
-- What this migration DOES provide -- a real, usable, but VOLUNTARY compensating control,
-- honestly disclosed as voluntary, not automatic or enforced: a snapshot function an
-- operator can run BEFORE initiating a restore, capturing the current IDs of every active
-- legal hold, revoked API key, disabled webhook endpoint, and suspended/revoked user/
-- membership into a table that lives in `public` schema specifically so it SURVIVES the
-- in-place restore procedure's own step (a) `app`-schema drop (the identical technique
-- already established for ISS-2026-267's advisory lock and the general Option 2 wrapper
-- layer) -- then a detection function to run AFTER the restore completes, comparing the
-- pre-restore snapshot against the post-restore state and reporting exactly which
-- decisions were silently reverted. This closes the class of case where an operator
-- remembers to run the snapshot step; it does nothing for a restore where no snapshot was
-- ever captured (no trigger or migration-level mechanism forces the snapshot to happen --
-- that would require intercepting the restore procedure itself, which runs entirely
-- outside any RPC this schema controls, via raw psql/pg_restore).

create table public.security_state_snapshots (
  id uuid primary key default gen_random_uuid(),
  captured_at timestamptz not null default now(),
  actor_label text not null,
  legal_hold_ids uuid[] not null default '{}',
  revoked_api_key_ids uuid[] not null default '{}',
  disabled_webhook_endpoint_ids uuid[] not null default '{}',
  non_active_user_ids uuid[] not null default '{}',
  non_active_membership_ids uuid[] not null default '{}'
);

comment on table public.security_state_snapshots is 'ISS-2026-254: a pre-restore snapshot of active legal holds / revoked API keys / disabled webhook endpoints / suspended-or-revoked users and memberships, captured by app.capture_security_state_snapshot(). Deliberately lives in public schema, not app -- the composed in-place restore procedure (docs/runbooks/database-restore.md Sec4 item 4) drops and rebuilds the app schema entirely; a row here survives that drop, exactly like the ISS-2026-267 advisory lock survives it by using a mechanism outside app.';

create function app.capture_security_state_snapshot(p_actor_label text)
returns public.security_state_snapshots
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_row public.security_state_snapshots;
begin
  if coalesce(length(trim(p_actor_label)), 0) = 0 then
    raise exception 'security_snapshot_missing_actor_label: a non-empty p_actor_label is required to record who captured this snapshot' using errcode = 'check_violation';
  end if;

  insert into public.security_state_snapshots (
    actor_label, legal_hold_ids, revoked_api_key_ids, disabled_webhook_endpoint_ids, non_active_user_ids, non_active_membership_ids
  )
  values (
    p_actor_label,
    (select coalesce(array_agg(id), '{}') from app.legal_holds where status = 'active'),
    (select coalesce(array_agg(id), '{}') from app.api_keys where status = 'revoked'),
    (select coalesce(array_agg(id), '{}') from app.webhook_endpoints where status = 'disabled'),
    (select coalesce(array_agg(id), '{}') from app.users where status in ('suspended', 'revoked')),
    (select coalesce(array_agg(id), '{}') from app.principal_memberships where status in ('suspended', 'revoked'))
  )
  returning * into v_row;

  return v_row;
end;
$$;

comment on function app.capture_security_state_snapshot is 'ISS-2026-254: run this BEFORE initiating any restore procedure (docs/runbooks/database-restore.md''s own new step). Captures the current IDs of every active legal hold, revoked API key, disabled webhook endpoint, and suspended/revoked user/membership into public.security_state_snapshots (survives the app-schema drop). Voluntary, not enforced -- no mechanism forces an operator to call this before restoring.';

create function app.detect_reverted_security_state(p_snapshot_id uuid)
returns table (category text, record_id uuid, detail text)
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_snap public.security_state_snapshots;
begin
  select * into v_snap from public.security_state_snapshots where id = p_snapshot_id;
  if not found then
    raise exception 'security_snapshot_not_found: %', p_snapshot_id using errcode = 'no_data_found';
  end if;

  return query
    select 'legal_hold'::text, hold_id, 'no longer status=active after restore (reverted or missing)'::text
    from unnest(v_snap.legal_hold_ids) as hold_id
    where not exists (select 1 from app.legal_holds where id = hold_id and status = 'active');

  return query
    select 'api_key'::text, key_id, 'no longer status=revoked after restore (reverted or missing)'::text
    from unnest(v_snap.revoked_api_key_ids) as key_id
    where not exists (select 1 from app.api_keys where id = key_id and status = 'revoked');

  return query
    select 'webhook_endpoint'::text, endpoint_id, 'no longer status=disabled after restore (reverted or missing)'::text
    from unnest(v_snap.disabled_webhook_endpoint_ids) as endpoint_id
    where not exists (select 1 from app.webhook_endpoints where id = endpoint_id and status = 'disabled');

  return query
    select 'user'::text, user_id, 'no longer suspended/revoked after restore (reverted or missing)'::text
    from unnest(v_snap.non_active_user_ids) as user_id
    where not exists (select 1 from app.users where id = user_id and status in ('suspended', 'revoked'));

  return query
    select 'membership'::text, membership_id, 'no longer suspended/revoked after restore (reverted or missing)'::text
    from unnest(v_snap.non_active_membership_ids) as membership_id
    where not exists (select 1 from app.principal_memberships where id = membership_id and status in ('suspended', 'revoked'));
end;
$$;

comment on function app.detect_reverted_security_state is 'ISS-2026-254: run this AFTER a restore completes, passing the snapshot id captured before the restore began. Reports every legal hold / revoked API key / disabled webhook endpoint / suspended-or-revoked user or membership from the snapshot that no longer holds in the restored database -- a real, live comparison, not a documentation-only warning. Empty result means nothing in the snapshot was reverted (or no snapshot was ever taken -- always confirm a snapshot id was actually captured before trusting an empty result).';

revoke execute on all functions in schema app from public;
grant execute on function app.capture_security_state_snapshot(text) to service_role;
grant execute on function app.detect_reverted_security_state(uuid) to service_role;

-- Option 2 wrapper (RGL-394): app is not exposed to PostgREST directly -- every
-- externally-callable app.* function needs a matching public.* wrapper, enforced by
-- scripts/db-tests/public-api-wrapper-regression.sql's own zero-tolerance guard.
create function public.capture_security_state_snapshot(p_actor_label text)
returns public.security_state_snapshots
language sql
volatile
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select app.capture_security_state_snapshot(p_actor_label);
$wrap$;

comment on function public.capture_security_state_snapshot(p_actor_label text) is
  'RGL-394 Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.capture_security_state_snapshot with an identical grant set, never a reimplementation. See docs/build-log/release-go-live/RGL-394.md.';

-- 20260826010000_harden_public_api_data_wrappers_tierc_fixes.sql's own amended
-- convention (Finding 2 there): Supabase's own platform-level default privilege
-- grants EXECUTE on every new public-schema function to anon/authenticated/service_role
-- automatically at CREATE time -- `revoke ... from public` alone (the PUBLIC
-- pseudo-role) never touches that. Must revoke from the named roles explicitly.
revoke execute on function public.capture_security_state_snapshot(p_actor_label text) from anon, authenticated, service_role, public;
grant execute on function public.capture_security_state_snapshot(p_actor_label text) to service_role;

create function public.detect_reverted_security_state(p_snapshot_id uuid)
returns table (category text, record_id uuid, detail text)
language sql
volatile
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.detect_reverted_security_state(p_snapshot_id);
$wrap$;

comment on function public.detect_reverted_security_state(p_snapshot_id uuid) is
  'RGL-394 Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.detect_reverted_security_state with an identical grant set, never a reimplementation. See docs/build-log/release-go-live/RGL-394.md.';

revoke execute on function public.detect_reverted_security_state(p_snapshot_id uuid) from anon, authenticated, service_role, public;
grant execute on function public.detect_reverted_security_state(p_snapshot_id uuid) to service_role;
