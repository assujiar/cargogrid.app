-- ISS-2026-275/ISS-2026-276 (Step 16 historical-issue-backlog remediation,
-- docs/runtime/KNOWN_ISSUES.md) -- app.finance_journals_protect_posted never fires on
-- INSERT (only UPDATE/DELETE), so a direct bulk insert of an already-posted journal is
-- (a) not blocked by the posted-journal-immutability trigger, (b) not checked for a
-- balanced debit=credit total (app.validate_finance_journal_line_balance is only invoked
-- from inside the RPC functions, never at the table layer), and (c) has no legitimate
-- source_type to record its true provenance -- 'migration'/'import' does not exist in
-- app.finance_journals' own source_type vocabulary, the identical root gap ISS-2026-276
-- registered separately.
--
-- This entry's own text names 2 options: widen the UPDATE/DELETE trigger to also guard
-- INSERT, or build a dedicated migration-insert RPC that replicates the RPC-layer
-- validation. The first would make it IMPOSSIBLE to ever load real historical
-- already-posted data (the trigger has no way to distinguish a legitimate migration
-- insert from an illegitimate one) -- confirmed with the operator (AskUserQuestion)
-- before implementing: the second, dedicated-RPC option is correct.
--
-- app.import_historical_finance_journal is modeled directly on the existing
-- app.create_and_post_finance_system_journal (posts immediately, skipping draft/
-- submitted/approved -- replaying that workflow for historical data makes no sense) but
-- differs in the ways that close both entries' own real gaps:
--   - requires real FIN:Approve authority itself (app.create_and_post_finance_system_
--     journal deliberately has none, trusting its own caller -- app.
--     post_finance_subledger_batch -- to have already checked; this new RPC IS the
--     directly-called entry point, so it must check for itself);
--   - re-validates debit=credit balance via the existing app.validate_finance_journal_
--     line_balance before ever writing a row (closing ISS-2026-275's gap (b));
--   - requires a real, non-null source_id and a real, non-empty reason -- source_type
--     'migration' is added to both the source_type and source_check constraints,
--     requiring source_id is not null (closing ISS-2026-276's own vocabulary gap and,
--     together with app.finance_journals_validate_source below, closing ISS-2026-275's
--     gap (c) -- a 'migration' insert can no longer sail through sourceless the way
--     'manual' legitimately does). Both constraint replacements below preserve the
--     existing 'correction' source_type (FIN-206's own retrofit,
--     20260729200000_create_finance_reversal_adjustment.sql) byte-for-byte -- this is
--     an additive replacement, never a narrowing of an already-applied constraint.
--
-- The one real design decision this fix makes, confirmed with the operator before
-- implementing: unlike the live system-journal path, this RPC does NOT require the
-- resolved fiscal period to be posting_eligible (open) -- a real historical migration by
-- definition targets periods that are already closed today; requiring an open period
-- would make this fix useless for its own stated purpose. A period covering the date
-- must still exist (app.resolve_finance_period_for_date returns zero rows otherwise,
-- raised as a clear error) -- this only relaxes the open/closed check, never the
-- date-to-period resolution itself.
alter table app.finance_journals drop constraint finance_journals_source_type_check;
alter table app.finance_journals add constraint finance_journals_source_type_check check (source_type in ('manual', 'subledger', 'correction', 'migration'));

alter table app.finance_journals drop constraint finance_journals_source_check;
alter table app.finance_journals add constraint finance_journals_source_check check (
  (source_type = 'manual' and source_id is null)
  or (source_type in ('subledger', 'correction', 'migration') and source_id is not null)
);

create function app.import_historical_finance_journal(
  p_tenant_id uuid,
  p_company_id uuid,
  p_source_id uuid,
  p_journal_date date,
  p_currency text,
  p_lines jsonb,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.finance_journals
language plpgsql
security definer
set search_path to 'app', 'pg_temp'
as $$
declare
  v_journal app.finance_journals;
  v_line jsonb;
  v_line_number integer := 0;
  v_total numeric(14, 2);
  v_period record;
  v_year integer;
  v_seq integer;
  v_number text;
begin
  if not app.check_finance_journal_authority('Approve', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_source_id is null then
    raise exception 'finance_journal_migration_source_id_required: a real, non-null source_id is required to import a historical journal' using errcode = 'check_violation';
  end if;

  if coalesce(trim(p_reason), '') = '' then
    raise exception 'finance_journal_migration_reason_required: a real, non-empty reason is required to import a historical journal' using errcode = 'check_violation';
  end if;

  select * into v_journal from app.finance_journals where tenant_id = p_tenant_id and source_type = 'migration' and source_id = p_source_id;
  if found then
    return v_journal;
  end if;

  v_total := app.validate_finance_journal_line_balance(p_lines);

  select * into v_period from app.resolve_finance_period_for_date(p_tenant_id, p_company_id, p_journal_date);
  if not found then
    raise exception 'finance_journal_period_not_found: no fiscal period covers % -- create the covering fiscal period before importing historical data into it', p_journal_date
      using errcode = 'no_data_found';
  end if;
  -- Deliberately does NOT require v_period.posting_eligible -- see this migration's own
  -- header for why (confirmed with the operator before implementing).

  v_year := extract(year from p_journal_date)::integer;
  insert into app.finance_journal_number_counters (tenant_id, company_id, year, next_seq)
  values (p_tenant_id, p_company_id, v_year, 2)
  on conflict (tenant_id, coalesce(company_id, '00000000-0000-0000-0000-000000000000'::uuid), year)
  do update set next_seq = app.finance_journal_number_counters.next_seq + 1
  returning next_seq - 1 into v_seq;
  v_number := 'JRNL-' || v_year::text || '-' || lpad(v_seq::text, 6, '0');

  insert into app.finance_journals (
    tenant_id, company_id, journal_number, source_type, source_id, idempotency_key,
    currency, total_amount, journal_date, status, posting_period_id, posted_by, posted_at, created_by
  )
  values (
    p_tenant_id, p_company_id, v_number, 'migration', p_source_id, 'migration:' || p_source_id::text,
    p_currency, v_total, p_journal_date, 'posted', v_period.period_id, p_actor_label, now(), p_actor_label
  )
  returning * into v_journal;

  for v_line in select * from jsonb_array_elements(p_lines) loop
    v_line_number := v_line_number + 1;
    insert into app.finance_journal_lines (journal_id, tenant_id, line_number, account_id, direction, amount)
    values (v_journal.id, p_tenant_id, v_line_number, (v_line ->> 'accountId')::uuid, v_line ->> 'direction', (v_line ->> 'amount')::numeric);
  end loop;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'import_historical_finance_journal',
    'app.finance_journals', v_journal.id, 'success', p_reason, null, to_jsonb(v_journal)
  );

  return v_journal;
end;
$$;

comment on function app.import_historical_finance_journal is 'ISS-2026-275/ISS-2026-276: the sanctioned, validated path for loading a real historical already-posted journal during a data migration -- FIN:Approve-gated, re-validates debit=credit balance, requires a real non-null source_id and non-empty reason, and (the one deliberate difference from the live posting path) does NOT require the resolved fiscal period to still be open, since a real historical migration by definition targets already-closed periods. Idempotent on (tenant_id, source_type=migration, source_id), mirroring app.create_and_post_finance_system_journal''s own idempotency shape.';

revoke execute on all functions in schema app from public;
grant execute on function app.import_historical_finance_journal(uuid, uuid, uuid, date, text, jsonb, text, uuid, text) to authenticated, service_role;

-- Option 2 wrapper (RGL-394): app is not exposed to PostgREST directly -- every
-- externally-callable app.* function needs a matching public.* wrapper, enforced by
-- scripts/db-tests/public-api-wrapper-regression.sql's own zero-tolerance guard. app.
-- import_historical_finance_journal is security definer (matching every other finance
-- write RPC's own current convention -- 20260810700000_harden_finance_authority_chain_
-- security_definer.sql converted the whole domain, including its own direct template
-- app.create_and_post_finance_system_journal) -- matched here (security definer),
-- since public-api-wrapper-regression.sql's own exhaustive check requires every
-- public.* wrapper's security mode to match its app.* counterpart exactly.
create function public.import_historical_finance_journal(p_tenant_id uuid, p_company_id uuid, p_source_id uuid, p_journal_date date, p_currency text, p_lines jsonb, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.finance_journals
language sql
volatile
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select app.import_historical_finance_journal(p_tenant_id, p_company_id, p_source_id, p_journal_date, p_currency, p_lines, p_reason, p_actor_auth_user_id, p_actor_label);
$wrap$;

comment on function public.import_historical_finance_journal(p_tenant_id uuid, p_company_id uuid, p_source_id uuid, p_journal_date date, p_currency text, p_lines jsonb, p_reason text, p_actor_auth_user_id uuid, p_actor_label text) is
  'RGL-394 Option-2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.import_historical_finance_journal with an identical grant set, never a reimplementation. See docs/build-log/release-go-live/RGL-394.md.';

-- 20260826010000_harden_public_api_data_wrappers_tierc_fixes.sql's own amended
-- convention (Finding 2 there): Supabase's own platform-level default privilege
-- grants EXECUTE on every new public-schema function to anon/authenticated/service_role
-- automatically at CREATE time -- `revoke ... from public` alone (the PUBLIC
-- pseudo-role) never touches that. Must revoke from the named roles explicitly.
revoke execute on function public.import_historical_finance_journal(p_tenant_id uuid, p_company_id uuid, p_source_id uuid, p_journal_date date, p_currency text, p_lines jsonb, p_reason text, p_actor_auth_user_id uuid, p_actor_label text) from anon, authenticated, service_role, public;
grant execute on function public.import_historical_finance_journal(p_tenant_id uuid, p_company_id uuid, p_source_id uuid, p_journal_date date, p_currency text, p_lines jsonb, p_reason text, p_actor_auth_user_id uuid, p_actor_label text) to authenticated, service_role;
