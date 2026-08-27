-- ISS-2026-265 (Step 16 historical-issue-backlog remediation, docs/runtime/KNOWN_ISSUES.md)
-- -- the composed in-place restore procedure's own TRUNCATE step never fires
-- FOR EACH ROW triggers at all (standard, documented Postgres behavior, independent of
-- pg_restore's own --disable-triggers flag), silently defeating 9 security/integrity
-- row-level triggers (app.files legal-hold protection, app.finance_journals/
-- finance_journal_lines posted-journal immutability, 5 Loyalty append-only-ledger
-- guarantees, app.transaction_lineage_edges append-only lineage) with ZERO row left in
-- app.audit_logs documenting that the restore happened at all.
--
-- What this migration does NOT and cannot fix: TRUNCATE bypassing FOR EACH ROW triggers
-- is fundamental Postgres behavior, not a bug in this schema -- no function-level change
-- can make TRUNCATE fire a trigger it structurally never fires. This migration closes the
-- narrower, genuinely closable half of this finding's own title: "zero audit trail."
-- A single, explicit, mandatory audit_logs entry recording that an in-place restore
-- occurred (who, when, what scope, how many tables) gives a forensic investigator
-- something real to work from afterward, where today there is nothing at all -- it does
-- not retroactively re-verify any individual table's own security invariant (a legal
-- hold, a posted-journal balance) that the bypassed triggers would have protected; that
-- would need a structurally different mechanism (a pre-restore manifest of hold/
-- immutability state to diff against post-restore), disclosed here as still open, not
-- silently claimed as closed by this fix.
--
-- app.audit_logs.tenant_id is nullable (confirmed:
-- supabase/migrations/20260716113048_create_audit_trail.sql:55, no `not null`) -- an
-- in-place restore is a whole-schema, cross-tenant operational event, not scoped to one
-- tenant, so this new function records it with tenant_id = null, the same convention
-- already established for platform-level events. actor_auth_user_id is likewise
-- nullable (the operator running this restore procedure connects directly as the
-- database superuser via DATABASE_ADMIN_URL, per docs/runbooks/database-restore.md's own
-- documented connection model, not as an app.users-linked auth.users identity) --
-- p_actor_label (required, not null on app.audit_logs) is the durable "who" record in
-- that case.

create function app.record_database_restore_event(
  p_actor_label text,
  p_scope text,
  p_tables_truncated integer,
  p_reason text default null,
  p_actor_auth_user_id uuid default null
)
returns app.audit_logs
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_row app.audit_logs;
begin
  if coalesce(length(trim(p_actor_label)), 0) = 0 then
    raise exception 'restore_event_missing_actor_label: a non-empty p_actor_label is required to record who performed this restore' using errcode = 'check_violation';
  end if;
  if p_scope is null or p_scope not in ('in_place_truncate_restore', 'drop_database_restore') then
    raise exception 'restore_event_invalid_scope: % is not a recognized restore procedure scope', p_scope using errcode = 'check_violation';
  end if;
  if p_tables_truncated is null or p_tables_truncated < 0 then
    raise exception 'restore_event_invalid_table_count: p_tables_truncated must be a non-negative integer' using errcode = 'check_violation';
  end if;

  v_row := app.capture_audit_event(
    null, p_actor_auth_user_id, p_actor_label, 'database_restore', 'app.*', null, 'success', p_reason,
    null,
    jsonb_build_object(
      'scope', p_scope,
      'tables_truncated', p_tables_truncated,
      'trigger_note', 'TRUNCATE never fires FOR EACH ROW triggers -- this event does not itself confirm any individual table''s own security/integrity invariant (legal hold, posted-journal immutability, append-only ledger) survived the restore, only that a restore of this scope occurred'
    ),
    gen_random_uuid()
  );

  return v_row;
end;
$$;

comment on function app.record_database_restore_event is 'ISS-2026-265: the one mandatory audit step docs/runbooks/database-restore.md''s composed in-place restore procedure now requires (step (j), after the advisory-lock release) -- closes "zero audit trail" for the fact that a restore occurred; does NOT and cannot re-verify the individual security invariants TRUNCATE bypassed (that needs a structurally different, still-open mechanism -- see ISS-2026-265''s own KNOWN_ISSUES.md entry).';

revoke execute on all functions in schema app from public;
grant execute on function app.record_database_restore_event(text, text, integer, text, uuid) to service_role;

-- Option 2 wrapper (RGL-394): app is not exposed to PostgREST directly -- every
-- externally-callable app.* function needs a matching public.* wrapper, enforced by
-- scripts/db-tests/public-api-wrapper-regression.sql's own zero-tolerance guard.
-- security-mode-matched (this function is SECURITY DEFINER, so is its wrapper).
create function public.record_database_restore_event(p_actor_label text, p_scope text, p_tables_truncated integer, p_reason text DEFAULT NULL::text, p_actor_auth_user_id uuid DEFAULT NULL::uuid)
returns app.audit_logs
language sql
volatile
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select app.record_database_restore_event(p_actor_label, p_scope, p_tables_truncated, p_reason, p_actor_auth_user_id);
$wrap$;

comment on function public.record_database_restore_event(p_actor_label text, p_scope text, p_tables_truncated integer, p_reason text, p_actor_auth_user_id uuid) is
  'RGL-394 Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.record_database_restore_event with an identical grant set, never a reimplementation. See docs/build-log/release-go-live/RGL-394.md.';

revoke execute on function public.record_database_restore_event(p_actor_label text, p_scope text, p_tables_truncated integer, p_reason text, p_actor_auth_user_id uuid) from public;
grant execute on function public.record_database_restore_event(p_actor_label text, p_scope text, p_tables_truncated integer, p_reason text, p_actor_auth_user_id uuid) to service_role;
