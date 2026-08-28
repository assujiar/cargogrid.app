-- Real, executable regression evidence for ISS-2026-259 (Step 16 historical-issue-backlog
-- remediation, Track B Batch 8, docs/runtime/KNOWN_ISSUES.md): app.audit_logs is
-- structurally blind to raw-SQL/infra-level data corruption. This proves the new
-- app._raw_mutation_tripwire trigger + app.list_untracked_table_mutations() mechanism
-- (supabase/migrations/20260828200000_create_raw_mutation_tripwire.sql) genuinely detects
-- exactly that gap on the 2 tables it protects (app.leads, app.audit_logs), for
-- DELETE/UPDATE, while correctly NOT flagging the legitimate, already-self-auditing paths
-- this repository already has.
--
-- Deliberately one top-level `do $$ ... $$;` block PER case, not one block for everything
-- -- psql's default autocommit mode gives each top-level statement (a DO block is one
-- statement) its own transaction, and this mechanism's own correlation key is
-- txid_current(), scoped to a single transaction. Cramming every case into one shared
-- transaction would make every mutation in it share one txid regardless of which
-- individual statement was actually audited, silently defeating the very isolation this
-- test exists to prove. tenant/actor ids are handed between blocks via set_config, the
-- same technique scripts/db-tests/database-restore-lock.sql already uses to pass state
-- between separate processes/statements.
--
-- Deliberately does NOT exercise TRUNCATE here: the trigger exists and is attached (see
-- the migration itself), but `TRUNCATE app.leads` is a database-wide, cross-tenant,
-- destructive statement, and this suite runs every *.sql file here in file-name order
-- against ONE shared disposable database (scripts/db-tests/run.sh) -- truncating a table
-- other, earlier-run test files may have seeded rows into would risk breaking them
-- (nothing later re-reads pre-existing app.leads rows today, but relying on that
-- happening to be true, forever, across every future test file, is not a real safety
-- margin). Real TRUNCATE coverage for this mechanism, using an isolated database, is
-- disclosed as a follow-up rather than risked here -- the same honest "not exercised in
-- the shared suite" disclosure this repository already makes elsewhere (e.g. ISS-2026-268
-- for app.files in DR drills).

\set ON_ERROR_STOP on

\echo '>> ISS-2026-259 setup: tenant + actor'
do $$
declare
  v_tenant app.tenants;
  v_actor_auth uuid := '00000000-0000-0000-0000-000000000259';
begin
  insert into auth.users (id, email) values (v_actor_auth, 'iss259-actor@example.test');
  select * into v_tenant from app.provision_tenant('iss259tenant', 'ISS-2026-259 Regression Tenant', 'idem-iss259-1', 'tester');
  perform app.transition_tenant_status(v_tenant.id, 'active', 'bootstrap complete', 'tester');
  -- Case 4/5 below exercise app.supreme_admin_delete_audit_log, which requires a real
  -- global supreme_admin principal membership -- granted here, once, for the whole file.
  perform app.grant_principal_membership(v_actor_auth, 'supreme_admin', null, null, 'tester');

  perform set_config('cargogrid.iss259_tenant_id', v_tenant.id::text, false);
  perform set_config('cargogrid.iss259_actor_id', v_actor_auth::text, false);
end $$;

\echo '>> ISS-2026-259 Case 1: delete + capture_audit_event in the SAME transaction must NOT be flagged'
do $$
declare
  v_tenant_id uuid := current_setting('cargogrid.iss259_tenant_id')::uuid;
  v_actor_auth uuid := current_setting('cargogrid.iss259_actor_id')::uuid;
  v_lead app.leads;
begin
  insert into app.leads (tenant_id, source, contact_name, email, phone, company_name)
  values (v_tenant_id, 'manual', 'ISS-2026-259 Tracked Lead', 'iss259-tracked@example.test', '+10000000001', 'Tracked Co')
  returning * into v_lead;

  delete from app.leads where id = v_lead.id;
  perform app.capture_audit_event(
    v_tenant_id, v_actor_auth, 'tester', 'delete_lead_simulated_rpc',
    'app.leads', v_lead.id, 'success', 'ISS-2026-259 regression: simulated legitimate delete', null, null
  );

  perform 1 from app.list_untracked_table_mutations(now() - interval '1 hour')
    where table_name = 'app.leads' and operation = 'DELETE' and detected_at >= now() - interval '1 minute';
  if found then
    raise exception 'assertion failed: a delete followed by capture_audit_event in the same transaction was incorrectly reported as untracked';
  end if;

  raise notice 'ISS-2026-259 Case 1 proof: same-transaction delete + capture_audit_event is correctly NOT flagged';
end $$;

\echo '>> ISS-2026-259 Case 2: a raw DELETE on app.leads with no audit call anywhere in the transaction (HDN-384''s own live-reproduced scenario) MUST be flagged'
do $$
declare
  v_tenant_id uuid := current_setting('cargogrid.iss259_tenant_id')::uuid;
  v_lead app.leads;
begin
  insert into app.leads (tenant_id, source, contact_name, email, phone, company_name)
  values (v_tenant_id, 'manual', 'ISS-2026-259 Untracked Lead', 'iss259-untracked@example.test', '+10000000002', 'Untracked Co')
  returning * into v_lead;

  delete from app.leads where id = v_lead.id;

  perform 1 from app.list_untracked_table_mutations(now() - interval '1 hour')
    where table_name = 'app.leads' and operation = 'DELETE' and affected_row_count = 1
      and detected_at >= now() - interval '1 minute';
  if not found then
    raise exception 'assertion failed: expected the raw, unaudited DELETE FROM app.leads to be reported by app.list_untracked_table_mutations';
  end if;

  raise notice 'ISS-2026-259 Case 2 proof: a raw, unaudited DELETE on app.leads is correctly flagged, with affected_row_count = 1';
end $$;

\echo '>> ISS-2026-259 Case 3: a raw UPDATE (no audit call) is flagged too, not just DELETE'
do $$
declare
  v_tenant_id uuid := current_setting('cargogrid.iss259_tenant_id')::uuid;
  v_lead app.leads;
begin
  insert into app.leads (tenant_id, source, contact_name, email, phone, company_name)
  values (v_tenant_id, 'manual', 'ISS-2026-259 Update Probe Lead', 'iss259-update@example.test', '+10000000003', 'Update Co')
  returning * into v_lead;

  update app.leads set status = 'contacted' where id = v_lead.id;

  perform 1 from app.list_untracked_table_mutations(now() - interval '1 hour')
    where table_name = 'app.leads' and operation = 'UPDATE' and affected_row_count = 1
      and detected_at >= now() - interval '1 minute';
  if not found then
    raise exception 'assertion failed: expected the raw, unaudited UPDATE on app.leads to be reported by app.list_untracked_table_mutations';
  end if;

  raise notice 'ISS-2026-259 Case 3 proof: a raw, unaudited UPDATE on app.leads is correctly flagged, with affected_row_count = 1';
end $$;

\echo '>> ISS-2026-259 Case 4: app.audit_logs''s own self-auditing delete path (app.supreme_admin_delete_audit_log) must NOT be flagged'
do $$
declare
  v_tenant_id uuid := current_setting('cargogrid.iss259_tenant_id')::uuid;
  v_actor_auth uuid := current_setting('cargogrid.iss259_actor_id')::uuid;
  v_probe app.audit_logs;
begin
  v_probe := app.capture_audit_event(
    v_tenant_id, v_actor_auth, 'tester', 'iss259_probe_event_tracked', 'app.leads', gen_random_uuid(), 'success', 'ISS-2026-259 regression probe row (tracked case)', null, null
  );

  perform app.supreme_admin_delete_audit_log(v_actor_auth, v_probe.id, 'ISS-2026-259 regression: exercising the self-auditing delete path');

  perform 1 from app.list_untracked_table_mutations(now() - interval '1 hour')
    where table_name = 'app.audit_logs' and operation = 'DELETE' and detected_at >= now() - interval '1 minute';
  if found then
    raise exception 'assertion failed: app.supreme_admin_delete_audit_log''s own self-auditing delete of app.audit_logs was incorrectly reported as untracked';
  end if;

  raise notice 'ISS-2026-259 Case 4 proof: app.supreme_admin_delete_audit_log''s own same-transaction self-audit is correctly NOT flagged';
end $$;

\echo '>> ISS-2026-259 Case 5: a raw DELETE directly against app.audit_logs, bypassing both dedicated RPCs, MUST be flagged (the audit-trail-tampering scenario this table''s own inclusion exists to catch)'
do $$
declare
  v_tenant_id uuid := current_setting('cargogrid.iss259_tenant_id')::uuid;
  v_actor_auth uuid := current_setting('cargogrid.iss259_actor_id')::uuid;
  v_probe app.audit_logs;
begin
  -- Seed one throwaway row the ordinary way, then delete it RAW in a separate
  -- transaction (below) with no accompanying capture_audit_event call of any kind --
  -- once deleted, the only audit_logs row that ever shared this delete's own future
  -- txid is gone, so NOT EXISTS(... xact_id ...) correctly finds nothing.
  v_probe := app.capture_audit_event(
    v_tenant_id, v_actor_auth, 'tester', 'iss259_probe_event_untracked', 'app.leads', gen_random_uuid(), 'success', 'ISS-2026-259 regression probe row (untracked case)', null, null
  );
  perform set_config('cargogrid.iss259_probe_audit_id', v_probe.id::text, false);
end $$;

do $$
declare
  v_probe_id uuid := current_setting('cargogrid.iss259_probe_audit_id')::uuid;
begin
  delete from app.audit_logs where id = v_probe_id;

  perform 1 from app.list_untracked_table_mutations(now() - interval '1 hour')
    where table_name = 'app.audit_logs' and operation = 'DELETE' and affected_row_count = 1
      and detected_at >= now() - interval '1 minute';
  if not found then
    raise exception 'assertion failed: expected a raw DELETE FROM app.audit_logs (no accompanying capture_audit_event in the same transaction) to be reported by app.list_untracked_table_mutations';
  end if;

  raise notice 'ISS-2026-259 Case 5 proof: a raw, unaudited DELETE directly against app.audit_logs is correctly flagged';
end $$;

\echo '>> ISS-2026-259 regression: public.raw_mutation_tripwire_log carries no anon/authenticated table privilege and has RLS enabled (learned from ISS-2026-299, applied from creation this time)'
do $$
declare
  v_rls_enabled boolean;
begin
  select relrowsecurity into v_rls_enabled from pg_class where oid = 'public.raw_mutation_tripwire_log'::regclass;
  if not v_rls_enabled then
    raise exception 'assertion failed: expected RLS to be enabled on public.raw_mutation_tripwire_log';
  end if;

  if has_table_privilege('anon', 'public.raw_mutation_tripwire_log', 'SELECT') then
    raise exception 'assertion failed: expected anon to hold no SELECT privilege on public.raw_mutation_tripwire_log';
  end if;
  if has_table_privilege('authenticated', 'public.raw_mutation_tripwire_log', 'SELECT') then
    raise exception 'assertion failed: expected authenticated to hold no SELECT privilege on public.raw_mutation_tripwire_log';
  end if;
  if has_table_privilege('anon', 'public.raw_mutation_tripwire_log', 'INSERT') then
    raise exception 'assertion failed: expected anon to hold no INSERT privilege on public.raw_mutation_tripwire_log';
  end if;
  if not has_table_privilege('service_role', 'public.raw_mutation_tripwire_log', 'SELECT') then
    raise exception 'assertion failed: expected service_role to retain full access to public.raw_mutation_tripwire_log';
  end if;

  if has_function_privilege('anon', 'app.list_untracked_table_mutations(timestamptz)', 'EXECUTE') then
    raise exception 'assertion failed: expected anon to hold no EXECUTE privilege on app.list_untracked_table_mutations';
  end if;
  if has_function_privilege('authenticated', 'app.list_untracked_table_mutations(timestamptz)', 'EXECUTE') then
    raise exception 'assertion failed: expected authenticated to hold no EXECUTE privilege on app.list_untracked_table_mutations';
  end if;
  if has_function_privilege('anon', 'public.list_untracked_table_mutations(timestamptz)', 'EXECUTE') then
    raise exception 'assertion failed: expected anon to hold no EXECUTE privilege on public.list_untracked_table_mutations (the platform-default-grant leak class, ISS-2026-298)';
  end if;
  if has_function_privilege('authenticated', 'public.list_untracked_table_mutations(timestamptz)', 'EXECUTE') then
    raise exception 'assertion failed: expected authenticated to hold no EXECUTE privilege on public.list_untracked_table_mutations (the platform-default-grant leak class, ISS-2026-298)';
  end if;

  raise notice 'ISS-2026-259 privilege proof: public.raw_mutation_tripwire_log is RLS-enabled with zero anon/authenticated table privilege, and app.list_untracked_table_mutations / public.list_untracked_table_mutations are both service_role-only -- neither the ISS-2026-298 (function) nor ISS-2026-299 (table) platform-default-grant leak class reproduces here';
end $$;

\echo '>> ISS-2026-259 regression evidence complete'
