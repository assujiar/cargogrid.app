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

\echo '>> ISS-2026-259 coverage sweep: all 9 tables ISS-2026-265 named as carrying a security/integrity row-level trigger that TRUNCATE silently defeats now carry the statement-level tripwire, on all three events -- this is the assertion that catches a tenth such table being added later without one'
do $$
declare
  v_protected text[] := array[
    'files',
    'finance_journals',
    'finance_journal_lines',
    'loyalty_earning_events',
    'loyalty_point_ledger_entries',
    'loyalty_benefit_entitlement_events',
    'loyalty_reward_stock_reservations',
    'loyalty_redemption_events',
    'transaction_lineage_edges',
    -- The original two from 20260828200000, asserted here too so this sweep is the single
    -- place that answers "what is watched", rather than one of two lists that can diverge.
    'leads',
    'audit_logs'
  ];
  v_table text;
  v_events text[];
  v_missing text[] := array[]::text[];
begin
  foreach v_table in array v_protected loop
    select array_agg(distinct e order by e) into v_events
    from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
    join pg_proc p on p.oid = t.tgfoid
    cross join lateral (
      -- tgtype bit 3 = DELETE, bit 4 = UPDATE, bit 5 = TRUNCATE (see pg_trigger's own layout).
      select unnest(array_remove(array[
        case when (t.tgtype & 8) <> 0 then 'DELETE' end,
        case when (t.tgtype & 16) <> 0 then 'UPDATE' end,
        case when (t.tgtype & 32) <> 0 then 'TRUNCATE' end
      ], null)) as e
    ) ev
    where n.nspname = 'app' and c.relname = v_table
      and p.proname = '_raw_mutation_tripwire'
      and not t.tgisinternal;

    if coalesce(v_events, array[]::text[]) <> array['DELETE', 'TRUNCATE', 'UPDATE'] then
      v_missing := v_missing || (v_table || ' has ' || coalesce(array_to_string(v_events, '+'), 'none'));
    end if;
  end loop;

  if array_length(v_missing, 1) is not null then
    raise exception 'assertion failed: % protected table(s) do not carry the tripwire on all three events -- %',
      array_length(v_missing, 1), array_to_string(v_missing, '; ');
  end if;

  raise notice 'ISS-2026-259 coverage proof: all 11 protected tables carry the statement-level tripwire on DELETE, UPDATE and TRUNCATE';
end $$;

\echo '>> ISS-2026-259 Case 6: a raw, unaudited DELETE against an append-only loyalty ledger is flagged -- one of the 9 tables whose own row-level protection this mechanism exists to compensate for'
do $$
declare
  v_tenant_id uuid := current_setting('cargogrid.iss259_tenant_id')::uuid;
  v_edge_id uuid;
begin
  -- app.transaction_lineage_edges is used rather than a loyalty ledger because it needs no
  -- customer/account/programme fixture to hold a row: it is a bare polymorphic edge, which
  -- makes the tripwire the only thing under test here.
  insert into app.transaction_lineage_edges (tenant_id, relation_type, source_type, source_id, target_type, target_id, created_by_label)
  values (v_tenant_id, 'quote_to_job', 'job_order_handoff', gen_random_uuid(), 'job_order', gen_random_uuid(), 'iss259-tester')
  returning id into v_edge_id;

  -- A raw DELETE. The table's own BEFORE DELETE guard refuses this from an ordinary path, so
  -- the guard is disabled for exactly this statement -- which is the point: the scenario being
  -- reproduced IS an intervention that has the privilege to get past the row-level guard, and
  -- the question is whether it leaves a trace.
  alter table app.transaction_lineage_edges disable trigger user;
  -- Re-enabling only the tripwire triggers: `disable trigger user` turns off the row-level
  -- guard AND the statement-level tripwire, and disabling the thing under test would make this
  -- case prove nothing.
  alter table app.transaction_lineage_edges enable trigger transaction_lineage_edges_raw_mutation_tripwire_delete;
  delete from app.transaction_lineage_edges where id = v_edge_id;
  alter table app.transaction_lineage_edges enable trigger user;

  perform 1 from app.list_untracked_table_mutations(now() - interval '1 hour')
    where table_name = 'app.transaction_lineage_edges' and operation = 'DELETE' and affected_row_count = 1
      and detected_at >= now() - interval '1 minute';
  if not found then
    raise exception 'assertion failed: expected the raw, unaudited DELETE on app.transaction_lineage_edges to be reported by app.list_untracked_table_mutations';
  end if;

  raise notice 'ISS-2026-259 Case 6 proof: a raw, unaudited DELETE against an append-only lineage table is flagged, with affected_row_count = 1';
end $$;

\echo '>> ISS-2026-259 Case 7: TRUNCATE -- the operation ISS-2026-265 live-proved defeats every row-level guard on these 9 tables, and the reason the tripwire is statement-level rather than row-level'
do $$
declare
  v_before integer;
  v_after integer;
begin
  select count(*) into v_before from public.raw_mutation_tripwire_log
  where table_name = 'app.transaction_lineage_edges' and operation = 'TRUNCATE';

  -- No `disable trigger` needed and none used: TRUNCATE never fires a FOR EACH ROW trigger at
  -- all, which is precisely the gap. The row-level guard is fully armed here and does not stop
  -- this.
  truncate app.transaction_lineage_edges;

  select count(*) into v_after from public.raw_mutation_tripwire_log
  where table_name = 'app.transaction_lineage_edges' and operation = 'TRUNCATE';

  if v_after <> v_before + 1 then
    raise exception 'assertion failed: expected TRUNCATE to record exactly one tripwire row (% -> %)', v_before, v_after;
  end if;

  -- affected_row_count is null on TRUNCATE and that is deliberate, not an oversight: Postgres
  -- provides no transition table for it, so the count is genuinely unknown rather than zero.
  -- Recording a zero here would be a fabricated number in a forensic log.
  if exists (
    select 1 from public.raw_mutation_tripwire_log
    where table_name = 'app.transaction_lineage_edges' and operation = 'TRUNCATE'
      and affected_row_count is not null
  ) then
    raise exception 'assertion failed: TRUNCATE must record a NULL affected_row_count -- an unknown count must never be written as a number';
  end if;

  raise notice 'ISS-2026-259 Case 7 proof: TRUNCATE, which defeats every row-level guard on these 9 tables, is recorded by the statement-level tripwire with a NULL (unknown, not zero) row count';
end $$;

\echo '>> ISS-2026-259 regression evidence complete'
