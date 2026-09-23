-- CG-AUDIT-2026-09-02 UNTRACKED-B8 (the "number counters compound it" second half
-- of the original B8 finding, docs/audit/2026-09-02-independent-launch-readiness-
-- audit.md lines 297-298: "they run one sequence per company per year while
-- invoice numbers are unique only per tenant, so a second company's first invoice
-- of a year collides with the first company's"). The backlog's own B8 row closed
-- only the FIRST half (validating company_id belongs to the caller's tenant, via
-- app.assert_finance_company_org_unit, 20260907120000_validate_finance_company_
-- org_unit_iss_b8.sql) -- this closes the second, untouched half.
--
-- Confirmed live in the CURRENT (not a stale earlier redefinition) body of every
-- affected RPC before writing this migration -- each function has been redefined
-- multiple times since its original migration; the LATEST body of each was
-- checked directly, not assumed from the first hit. Found by a programmatic,
-- exhaustive scan of every `insert into app.finance_*_number_counters` call
-- site across every migration file (not just the 5 RPCs the workflow-driven
-- investigate agent itself cited) -- that scan surfaced a SIXTH function
-- neither the agent's own report nor this migration's own first draft had
-- caught, self-caught only when this migration's own first version was run
-- against `pnpm run db:test` and finance-journal.sql's own historical-import
-- test hit "there is no unique or exclusion constraint matching the ON
-- CONFLICT specification" -- the exact class of drift this session's own
-- standing discipline (never trust an unverified claim, personally re-verify
-- against current code) exists to catch:
--   app.issue_finance_invoice                  -- latest: 20260918010000 (e6)
--   app.post_finance_journal                   -- latest: 20260903132000
--   app.create_and_post_finance_system_journal -- latest: 20260907120000 (b8, ironically)
--   app.post_finance_settlement                -- latest: 20260903132000
--   app.post_finance_vendor_bill               -- latest: 20260903132000
--   app.import_historical_finance_journal      -- latest: 20260907120000 (b8, ironically) -- MISSED by the original investigate agent's own report entirely
-- Every one of these still keys its own number-counter upsert on
-- `(tenant_id, coalesce(company_id, sentinel), year)` while the resulting
-- document's own number is formatted with NO company component
-- (`'INV-' || year || '-' || lpad(seq,6,'0')`, identically for JRNL/SETL/BILL)
-- and the target table's own uniqueness is `(tenant_id, invoice_number)` --
-- tenant-scoped only (finance_invoices_tenant_number_unique and its 3 siblings,
-- all confirmed unchanged since their original migrations). Any tenant with >= 2
-- org_units (company_id sources) both issuing/posting in the same year hits a
-- guaranteed 23505 unique-violation on the second company's first document of
-- that type each year -- a real, deterministic, production-breaking failure for
-- the multi-branch/multi-company feature this repository has already shipped
-- (app.org_units), not a hypothetical.
--
-- The audit's own §6 roadmap (line 574) names the intended target explicitly:
-- "per-tenant number uniqueness" -- i.e. make the counter's own scope match the
-- ALREADY-DECLARED, ALREADY-ENFORCED tenant-only uniqueness constraint, not
-- invent a new company-qualified display format (which would be a genuine
-- product/format decision the audit does not ask for and this migration does
-- not make). Every non-counter reference to these 4 number columns (server/
-- contracts/invoice/invoice.ts, server/documents/generate-invoice.server.ts,
-- every ilike/display/customer-portal lookup) reads or searches the string
-- value, never a (tenant_id, company_id, number) composite key -- confirmed by
-- grep -- so re-scoping the counter changes no downstream contract.
--
-- Fix, per counter table (finance_invoice/journal/settlement/vendor_bill_
-- number_counters): consolidate any existing per-company rows for the same
-- (tenant_id, year) into exactly one row, its next_seq raised to a SAFE FLOOR --
-- the greatest of (a) the highest next_seq already recorded across the rows
-- being consolidated, and (b) one past the highest sequence number already
-- embedded in a real issued/posted document number for that tenant/year (a
-- defensive cross-check against the actual ground truth, never assumed to
-- differ from (a) under this repository's own single-insertion-point design,
-- but cheap and exact to verify) -- then re-scope the table's own unique index
-- from (tenant_id, coalesce(company_id, sentinel), year) to (tenant_id, year).
-- Never decreases a counter (the audit's own "never re-issue a number" safety
-- property, the same discipline app.bootstrap_numbering_counter's own
-- numbering_counter_cannot_decrease guard enforces for the separate, generic
-- platform numbering engine). The company_id column itself is left in place on
-- all 4 tables (never dropped -- confirmed via grep that nothing else in this
-- schema reads it, so leaving it as informational-only, set from whichever
-- request happened to create or last touch the row, carries zero risk and
-- avoids a needless destructive column drop on live tables).
do $$
declare
  v_before integer;
  v_after integer;
begin
  select count(*) into v_before from app.finance_invoice_number_counters;

  create temp table tmp_invoice_counter_targets on commit drop as
  select
    c.tenant_id,
    c.year,
    (array_agg(c.id order by c.next_seq desc, c.id))[1] as survivor_id,
    greatest(
      max(c.next_seq),
      1 + coalesce((
        select max((regexp_match(fi.invoice_number, '^INV-\d{4}-(\d+)$'))[1]::integer)
        from app.finance_invoices fi
        where fi.tenant_id = c.tenant_id and fi.invoice_number like 'INV-' || c.year::text || '-%'
      ), 0)
    ) as consolidated_next_seq
  from app.finance_invoice_number_counters c
  group by c.tenant_id, c.year;

  delete from app.finance_invoice_number_counters c
  using tmp_invoice_counter_targets t
  where c.tenant_id = t.tenant_id and c.year = t.year and c.id <> t.survivor_id;

  update app.finance_invoice_number_counters c
  set next_seq = t.consolidated_next_seq, company_id = null
  from tmp_invoice_counter_targets t
  where c.id = t.survivor_id;

  select count(*) into v_after from app.finance_invoice_number_counters;
  if v_after > v_before then
    raise exception 'untracked_b8_consolidation_grew_row_count: expected consolidation to never increase finance_invoice_number_counters row count, went % -> %', v_before, v_after;
  end if;
end $$;

drop index app.finance_invoice_number_counters_scope_unique;
create unique index finance_invoice_number_counters_scope_unique on app.finance_invoice_number_counters (tenant_id, year);

comment on table app.finance_invoice_number_counters is
  'FIN-197: a simple per-tenant/year sequential counter for invoice numbers, assigned only at issue time. CG-AUDIT-2026-09-02 UNTRACKED-B8: re-scoped from per-tenant/company/year to per-tenant/year to match finance_invoices_tenant_number_unique''s own tenant-only scope -- a per-company counter produced colliding numbers across a tenant''s own org_units (a real, deterministic 23505 on any multi-company tenant''s second company''s first document of a year). company_id is retained as an informational, non-unique column only (whichever request most recently touched the row) -- nothing else in this schema reads it.';

do $$
declare
  v_before integer;
  v_after integer;
begin
  select count(*) into v_before from app.finance_journal_number_counters;

  create temp table tmp_journal_counter_targets on commit drop as
  select
    c.tenant_id,
    c.year,
    (array_agg(c.id order by c.next_seq desc, c.id))[1] as survivor_id,
    greatest(
      max(c.next_seq),
      1 + coalesce((
        select max((regexp_match(fj.journal_number, '^JRNL-\d{4}-(\d+)$'))[1]::integer)
        from app.finance_journals fj
        where fj.tenant_id = c.tenant_id and fj.journal_number like 'JRNL-' || c.year::text || '-%'
      ), 0)
    ) as consolidated_next_seq
  from app.finance_journal_number_counters c
  group by c.tenant_id, c.year;

  delete from app.finance_journal_number_counters c
  using tmp_journal_counter_targets t
  where c.tenant_id = t.tenant_id and c.year = t.year and c.id <> t.survivor_id;

  update app.finance_journal_number_counters c
  set next_seq = t.consolidated_next_seq, company_id = null
  from tmp_journal_counter_targets t
  where c.id = t.survivor_id;

  select count(*) into v_after from app.finance_journal_number_counters;
  if v_after > v_before then
    raise exception 'untracked_b8_consolidation_grew_row_count: expected consolidation to never increase finance_journal_number_counters row count, went % -> %', v_before, v_after;
  end if;
end $$;

drop index app.finance_journal_number_counters_scope_unique;
create unique index finance_journal_number_counters_scope_unique on app.finance_journal_number_counters (tenant_id, year);

comment on table app.finance_journal_number_counters is
  'FIN-203: a simple per-tenant/year sequential counter for journal numbers, assigned only at post time -- shared by both the manual (app.post_finance_journal) and system (app.create_and_post_finance_system_journal) posting paths. CG-AUDIT-2026-09-02 UNTRACKED-B8: re-scoped from per-tenant/company/year to per-tenant/year to match finance_journals_tenant_number_unique''s own tenant-only scope. company_id is retained as an informational, non-unique column only.';

do $$
declare
  v_before integer;
  v_after integer;
begin
  select count(*) into v_before from app.finance_settlement_number_counters;

  create temp table tmp_settlement_counter_targets on commit drop as
  select
    c.tenant_id,
    c.year,
    (array_agg(c.id order by c.next_seq desc, c.id))[1] as survivor_id,
    greatest(
      max(c.next_seq),
      1 + coalesce((
        select max((regexp_match(fs.settlement_number, '^SETL-\d{4}-(\d+)$'))[1]::integer)
        from app.finance_settlements fs
        where fs.tenant_id = c.tenant_id and fs.settlement_number like 'SETL-' || c.year::text || '-%'
      ), 0)
    ) as consolidated_next_seq
  from app.finance_settlement_number_counters c
  group by c.tenant_id, c.year;

  delete from app.finance_settlement_number_counters c
  using tmp_settlement_counter_targets t
  where c.tenant_id = t.tenant_id and c.year = t.year and c.id <> t.survivor_id;

  update app.finance_settlement_number_counters c
  set next_seq = t.consolidated_next_seq, company_id = null
  from tmp_settlement_counter_targets t
  where c.id = t.survivor_id;

  select count(*) into v_after from app.finance_settlement_number_counters;
  if v_after > v_before then
    raise exception 'untracked_b8_consolidation_grew_row_count: expected consolidation to never increase finance_settlement_number_counters row count, went % -> %', v_before, v_after;
  end if;
end $$;

drop index app.finance_settlement_number_counters_scope_unique;
create unique index finance_settlement_number_counters_scope_unique on app.finance_settlement_number_counters (tenant_id, year);

comment on table app.finance_settlement_number_counters is
  'FIN-201: a simple per-tenant/year sequential counter for settlement numbers, assigned only at post time. CG-AUDIT-2026-09-02 UNTRACKED-B8: re-scoped from per-tenant/company/year to per-tenant/year to match finance_settlements_tenant_number_unique''s own tenant-only scope. company_id is retained as an informational, non-unique column only.';

do $$
declare
  v_before integer;
  v_after integer;
begin
  select count(*) into v_before from app.finance_vendor_bill_number_counters;

  create temp table tmp_vendor_bill_counter_targets on commit drop as
  select
    c.tenant_id,
    c.year,
    (array_agg(c.id order by c.next_seq desc, c.id))[1] as survivor_id,
    greatest(
      max(c.next_seq),
      1 + coalesce((
        select max((regexp_match(fvb.bill_number, '^BILL-\d{4}-(\d+)$'))[1]::integer)
        from app.finance_vendor_bills fvb
        where fvb.tenant_id = c.tenant_id and fvb.bill_number like 'BILL-' || c.year::text || '-%'
      ), 0)
    ) as consolidated_next_seq
  from app.finance_vendor_bill_number_counters c
  group by c.tenant_id, c.year;

  delete from app.finance_vendor_bill_number_counters c
  using tmp_vendor_bill_counter_targets t
  where c.tenant_id = t.tenant_id and c.year = t.year and c.id <> t.survivor_id;

  update app.finance_vendor_bill_number_counters c
  set next_seq = t.consolidated_next_seq, company_id = null
  from tmp_vendor_bill_counter_targets t
  where c.id = t.survivor_id;

  select count(*) into v_after from app.finance_vendor_bill_number_counters;
  if v_after > v_before then
    raise exception 'untracked_b8_consolidation_grew_row_count: expected consolidation to never increase finance_vendor_bill_number_counters row count, went % -> %', v_before, v_after;
  end if;
end $$;

drop index app.finance_vendor_bill_number_counters_scope_unique;
create unique index finance_vendor_bill_number_counters_scope_unique on app.finance_vendor_bill_number_counters (tenant_id, year);

comment on table app.finance_vendor_bill_number_counters is
  'FIN-200: a simple per-tenant/year sequential counter for vendor bill numbers, assigned only at post time. CG-AUDIT-2026-09-02 UNTRACKED-B8: re-scoped from per-tenant/company/year to per-tenant/year to match finance_vendor_bills_tenant_number_unique''s own tenant-only scope. company_id is retained as an informational, non-unique column only.';

-- ============================================================================
-- RPC bodies: change the counter-upsert conflict target from
-- (tenant_id, coalesce(company_id, sentinel), year) to (tenant_id, year) in
-- each of the 5 affected functions. Every other line of each function body is
-- copied verbatim from its own current (latest-redefined) source cited in this
-- migration's own header comment -- mechanical, not a reimplementation.
-- ============================================================================

create or replace function app.issue_finance_invoice(p_invoice_id uuid, p_expected_version integer, p_issue_date date, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text DEFAULT NULL::text)
 returns app.finance_invoices
 language plpgsql
 security definer
 set search_path to 'app', 'pg_temp'
as $function$
declare
  v_invoice app.finance_invoices;
  v_period record;
  v_year integer;
  v_seq integer;
  v_number text;
  v_ar_item app.finance_ar_open_items;
  v_due_date date;
  v_lines jsonb;
  v_tax_line app.finance_invoice_lines;
  v_tax_rule app.finance_tax_rule_versions;
  v_tax_code app.finance_tax_codes;
  v_net_collectible numeric(14, 2);
begin
  select * into v_invoice from app.finance_invoices where id = p_invoice_id for update;
  if not found or not app.has_active_tenant_membership(v_invoice.tenant_id, p_actor_auth_user_id) then
    raise exception 'finance_invoice_not_found: %', p_invoice_id using errcode = 'no_data_found';
  end if;
  if v_invoice.status = 'issued' then
    return v_invoice;
  end if;
  if not app.check_finance_invoice_authority('Approve', v_invoice.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_invoice.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-302: IP allowlist, checked after authority is established and before any
  -- state change. Skipped when the caller supplies no address, and bypassable via the
  -- separately-governed app.ip_allowlist_bypass_grants -- the identical composition
  -- 20260826190000 established for the import-commit RPCs.
  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(v_invoice.tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(v_invoice.tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;
  if v_invoice.record_version <> p_expected_version then
    raise exception 'stale_version: invoice % expected version % but found %', p_invoice_id, p_expected_version, v_invoice.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_invoice.status <> 'approved' then
    raise exception 'finance_invoice_not_approved: invoice % is % not approved', p_invoice_id, v_invoice.status
      using errcode = 'check_violation';
  end if;

  -- HDN-374 (Financial Integrity Audit) finding 2: a job order may reach `issued` for at
  -- most one invoice at a time -- backed by finance_invoices_job_order_issued_unique
  -- (Tier C fix), not merely this application-level pre-check. Draft/submitted/approved
  -- invoices from a legitimate re-handoff (OPS-181) remain freely creatable and discardable
  -- (see the migration header); this is the actual AR/GL posting boundary, so it is the one
  -- place a second full-amount bill for the same job's revenue must be refused.
  if exists (
    select 1 from app.finance_invoices
    where tenant_id = v_invoice.tenant_id and job_order_id = v_invoice.job_order_id
      and id <> v_invoice.id and status = 'issued'
  ) then
    raise exception 'finance_invoice_job_order_already_issued: job order % already has a different issued invoice', v_invoice.job_order_id
      using errcode = 'check_violation';
  end if;

  select * into v_period from app.resolve_finance_period_for_date(v_invoice.tenant_id, v_invoice.company_id, p_issue_date);
  if not found then
    raise exception 'finance_invoice_period_not_found: no fiscal period covers %', p_issue_date
      using errcode = 'no_data_found';
  end if;
  if not v_period.posting_eligible then
    raise exception 'finance_invoice_period_not_open: fiscal period % for % is not open', v_period.period_code, p_issue_date
      using errcode = 'check_violation';
  end if;

  v_year := extract(year from p_issue_date)::integer;
  insert into app.finance_invoice_number_counters (tenant_id, company_id, year, next_seq)
  values (v_invoice.tenant_id, v_invoice.company_id, v_year, 2)
  on conflict (tenant_id, year)
  do update set next_seq = app.finance_invoice_number_counters.next_seq + 1
  returning next_seq - 1 into v_seq;
  v_number := 'INV-' || v_year::text || '-' || lpad(v_seq::text, 6, '0');

  v_due_date := p_issue_date + (v_invoice.payment_term_days || ' days')::interval;

  -- CG-AUDIT-2026-09-02 B5: the amount actually collectible in cash is total_amount
  -- LESS any withholding_tax_amount -- the customer withholds that portion at source and
  -- remits it directly to the tax authority, so it is never a real AR balance CargoGrid
  -- can collect or age. See this fix's own migration header.
  v_net_collectible := v_invoice.total_amount - v_invoice.withholding_tax_amount;

  select * into v_ar_item from app.post_finance_ar_open_item(
    v_invoice.tenant_id, v_invoice.company_id, v_invoice.customer_account_id, 'invoice', v_invoice.id,
    v_invoice.currency, v_net_collectible, p_issue_date, v_due_date, p_actor_auth_user_id, p_actor_label
  );

  -- FIN-202: debit AR control for the net amount actually collectible (CG-AUDIT-2026-09-02
  -- B5: total_amount minus withholding_tax_amount); credit revenue for the subtotal;
  -- credit each ADDED (non-withholding) tax line's own governed output account (or the
  -- tax_payable_default posting-map key when none is configured); DEBIT each WITHHELD tax
  -- line's own governed recoverable account (or the withholding_tax_receivable_default
  -- posting-map key) -- a creditable asset to CargoGrid, never a payable, mirroring app.
  -- post_finance_vendor_bill's own established recoverable_account_id-debit pattern for
  -- input tax credits on the AP side. The journal still balances: net-collectible AR debit
  -- plus the withholding-receivable debit sums to total_amount, exactly matching revenue
  -- credit plus any added-tax credit.
  v_lines := jsonb_build_array(
    jsonb_build_object('postingMapKey', 'ar_control', 'direction', 'debit', 'amount', v_net_collectible, 'openItemType', 'ar_open_item', 'openItemId', v_ar_item.id)
  );
  if v_invoice.subtotal_amount > 0 then
    v_lines := v_lines || jsonb_build_array(jsonb_build_object('postingMapKey', 'revenue_default', 'direction', 'credit', 'amount', v_invoice.subtotal_amount));
  end if;
  for v_tax_line in select * from app.finance_invoice_lines where invoice_id = p_invoice_id and line_type = 'tax' and amount > 0 loop
    v_tax_rule := null;
    v_tax_code := null;
    if v_tax_line.tax_rule_version_id is not null then
      select * into v_tax_rule from app.finance_tax_rule_versions where id = v_tax_line.tax_rule_version_id;
    end if;
    if v_tax_line.tax_code_id is not null then
      select * into v_tax_code from app.finance_tax_codes where id = v_tax_line.tax_code_id;
    end if;
    -- CG-AUDIT-2026-09-02 B5 (found while writing this fix's own regression test, not
    -- previously exercised by any test before it -- every prior fixture left both
    -- output_account_id and recoverable_account_id unconfigured): a plpgsql row variable's
    -- own `IS NOT NULL` is true only when EVERY field of the row is non-null (SQL composite-
    -- type semantics), never merely "was a row found". app.finance_tax_rule_versions and
    -- app.finance_tax_codes both carry other nullable columns (e.g. currency) that are null
    -- on an ordinary fetched row, so `v_tax_rule is not null` / `v_tax_code is not null`
    -- would silently read as false even when the SELECT above found a real row -- checking
    -- each row's own guaranteed-NOT-NULL primary key column instead is the correct,
    -- established idiom (mirrors every `if not found then` check elsewhere in this
    -- codebase, just phrased for a value read after the block that set it rather than
    -- immediately after the SELECT itself).
    if v_tax_code.id is not null and v_tax_code.tax_type = 'withholding' then
      if v_tax_rule.id is not null and v_tax_rule.recoverable_account_id is not null then
        v_lines := v_lines || jsonb_build_array(jsonb_build_object('accountId', v_tax_rule.recoverable_account_id, 'direction', 'debit', 'amount', v_tax_line.amount));
      else
        v_lines := v_lines || jsonb_build_array(jsonb_build_object('postingMapKey', 'withholding_tax_receivable_default', 'direction', 'debit', 'amount', v_tax_line.amount));
      end if;
    elsif v_tax_rule.id is not null and v_tax_rule.output_account_id is not null then
      v_lines := v_lines || jsonb_build_array(jsonb_build_object('accountId', v_tax_rule.output_account_id, 'direction', 'credit', 'amount', v_tax_line.amount));
    else
      v_lines := v_lines || jsonb_build_array(jsonb_build_object('postingMapKey', 'tax_payable_default', 'direction', 'credit', 'amount', v_tax_line.amount));
    end if;
  end loop;

  perform app.post_finance_subledger_batch(
    v_invoice.tenant_id, v_invoice.company_id, 'invoice', v_invoice.id, p_issue_date, v_invoice.currency,
    v_lines, p_actor_auth_user_id, p_actor_label
  );

  -- HDN-374 Tier C finding 2: a genuine race between the exists() pre-check above and this
  -- update (two concurrent issue_finance_invoice calls for two DIFFERENT invoices on the
  -- SAME job order, each already past its own exists() check before either commits) is
  -- caught here by finance_invoices_job_order_issued_unique -- the loser's own update
  -- raises unique_violation instead of silently succeeding; re-raised as the same named
  -- exception the non-concurrent pre-check above already gives, never a raw unique_violation.
  begin
    update app.finance_invoices
      set status = 'issued', invoice_number = v_number, issue_date = p_issue_date, due_date = v_due_date,
          posting_period_id = v_period.period_id, ar_open_item_id = v_ar_item.id, issued_by = p_actor_label, issued_at = now()
      where id = p_invoice_id
      returning * into v_invoice;
  exception
    when unique_violation then
      raise exception 'finance_invoice_job_order_already_issued: job order % already has a different issued invoice', v_invoice.job_order_id
        using errcode = 'check_violation';
  end;

  perform app.capture_audit_event(
    v_invoice.tenant_id, p_actor_auth_user_id, p_actor_label, 'issue_finance_invoice',
    'app.finance_invoices', v_invoice.id, 'success', null, null, to_jsonb(v_invoice)
  );

  -- CG-AUDIT-2026-09-02 E6: real business-event trigger, added -- see this
  -- migration's own header for why this is app._enqueue_webhook_delivery
  -- (no authority check) rather than the public app.queue_webhook_delivery.
  -- A curated field set, never the raw row, is sent to a tenant-registered
  -- external endpoint.
  perform app._enqueue_webhook_delivery(
    v_invoice.tenant_id, 'invoice.issued',
    jsonb_build_object(
      'id', v_invoice.id,
      'invoice_number', v_invoice.invoice_number,
      'customer_account_id', v_invoice.customer_account_id,
      'job_order_id', v_invoice.job_order_id,
      'currency', v_invoice.currency,
      'total_amount', v_invoice.total_amount,
      'issue_date', v_invoice.issue_date,
      'due_date', v_invoice.due_date,
      'status', v_invoice.status
    ),
    'invoice-issued:' || v_invoice.id::text, p_actor_auth_user_id, p_actor_label
  );

  return v_invoice;
end;
$function$;

create or replace function app.post_finance_journal(p_journal_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.finance_journals
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_journal app.finance_journals;
  v_period record;
  v_year integer;
  v_seq integer;
  v_number text;
  v_lines jsonb;
begin
  select * into v_journal from app.finance_journals where id = p_journal_id for update;
  if not found or not app.has_active_tenant_membership(v_journal.tenant_id, p_actor_auth_user_id) then
    raise exception 'finance_journal_not_found: %', p_journal_id using errcode = 'no_data_found';
  end if;
  if v_journal.status = 'posted' then
    return v_journal;
  end if;
  if not app.check_finance_journal_authority('Approve', v_journal.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_journal.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-302: IP allowlist, checked after authority is established and before any
  -- state change. Skipped when the caller supplies no address, and bypassable via the
  -- separately-governed app.ip_allowlist_bypass_grants -- the identical composition
  -- 20260826190000 established for the import-commit RPCs.
  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(v_journal.tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(v_journal.tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;
  -- HDN-373 (ISS-2026-181, maker/checker): defense in depth, mirroring this function's own
  -- existing convention of independently re-checking FIN:Approve rather than trusting the
  -- prior step alone -- the preparer may not reach posted status either.
  if v_journal.submitted_by_auth_user_id is not null and v_journal.submitted_by_auth_user_id = p_actor_auth_user_id then
    raise exception 'self_approval_denied: identity % submitted journal % and may not also post it', p_actor_auth_user_id, p_journal_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_journal.record_version <> p_expected_version then
    raise exception 'stale_version: journal % expected version % but found %', p_journal_id, p_expected_version, v_journal.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_journal.status <> 'approved' then
    raise exception 'finance_journal_not_approved: journal % is % not approved', p_journal_id, v_journal.status
      using errcode = 'check_violation';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object('direction', direction, 'amount', amount)), '[]'::jsonb)
    into v_lines
    from app.finance_journal_lines where journal_id = p_journal_id;
  perform app.validate_finance_journal_line_balance(v_lines);

  select * into v_period from app.resolve_finance_period_for_date(v_journal.tenant_id, v_journal.company_id, v_journal.journal_date);
  if not found then
    raise exception 'finance_journal_period_not_found: no fiscal period covers %', v_journal.journal_date
      using errcode = 'no_data_found';
  end if;
  if not v_period.posting_eligible then
    raise exception 'finance_journal_period_not_open: fiscal period % for % is not open', v_period.period_code, v_journal.journal_date
      using errcode = 'check_violation';
  end if;
  perform app.assert_finance_period_open_for_posting(v_journal.tenant_id, v_journal.company_id, v_period.period_id, 'gl');

  v_year := extract(year from v_journal.journal_date)::integer;
  insert into app.finance_journal_number_counters (tenant_id, company_id, year, next_seq)
  values (v_journal.tenant_id, v_journal.company_id, v_year, 2)
  on conflict (tenant_id, year)
  do update set next_seq = app.finance_journal_number_counters.next_seq + 1
  returning next_seq - 1 into v_seq;
  v_number := 'JRNL-' || v_year::text || '-' || lpad(v_seq::text, 6, '0');

  update app.finance_journals
    set status = 'posted', journal_number = v_number, posting_period_id = v_period.period_id, posted_by = p_actor_label, posted_at = now()
    where id = p_journal_id
    returning * into v_journal;

  perform app.capture_audit_event(
    v_journal.tenant_id, p_actor_auth_user_id, p_actor_label, 'post_finance_journal',
    'app.finance_journals', v_journal.id, 'success', null, null, to_jsonb(v_journal)
  );

  return v_journal;
end;
$function$;

create or replace function app.create_and_post_finance_system_journal(p_tenant_id uuid, p_company_id uuid, p_source_type text, p_source_id uuid, p_journal_date date, p_currency text, p_lines jsonb, p_actor_auth_user_id uuid, p_actor_label text, p_lock_scope text DEFAULT 'gl'::text)
 returns app.finance_journals
 language plpgsql
 security definer
 set search_path to 'app', 'pg_temp'
as $function$
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
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  -- HDN-373 Tier C fix: either level is a legitimate caller (app.post_finance_subledger_batch
  -- and app.allocate_finance_receipt both require only FIN:Edit at their own front door;
  -- app.post_finance_correction requires FIN:Approve, which this OR already admits).
  -- Still denies an actor holding neither -- ISS-2026-183's own original concern.
  if not (app.check_finance_journal_authority('Edit', p_tenant_id, p_actor_auth_user_id)
          or app.check_finance_journal_authority('Approve', p_tenant_id, p_actor_auth_user_id)) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit or FIN:Approve for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  perform app.assert_finance_company_org_unit(p_tenant_id, p_company_id);
  if p_source_type not in ('subledger', 'correction') then
    raise exception 'finance_journal_unsupported_source_type: % is not a supported system journal source type', p_source_type
      using errcode = 'check_violation';
  end if;

  select * into v_journal from app.finance_journals where tenant_id = p_tenant_id and source_type = p_source_type and source_id = p_source_id;
  if found then
    return v_journal;
  end if;

  v_total := app.validate_finance_journal_line_balance(p_lines);

  select * into v_period from app.resolve_finance_period_for_date(p_tenant_id, p_company_id, p_journal_date);
  if not found then
    raise exception 'finance_journal_period_not_found: no fiscal period covers %', p_journal_date
      using errcode = 'no_data_found';
  end if;
  if not v_period.posting_eligible then
    raise exception 'finance_journal_period_not_open: fiscal period % for % is not open', v_period.period_code, p_journal_date
      using errcode = 'check_violation';
  end if;
  perform app.assert_finance_period_open_for_posting(p_tenant_id, p_company_id, v_period.period_id, p_lock_scope);

  v_year := extract(year from p_journal_date)::integer;
  insert into app.finance_journal_number_counters (tenant_id, company_id, year, next_seq)
  values (p_tenant_id, p_company_id, v_year, 2)
  on conflict (tenant_id, year)
  do update set next_seq = app.finance_journal_number_counters.next_seq + 1
  returning next_seq - 1 into v_seq;
  v_number := 'JRNL-' || v_year::text || '-' || lpad(v_seq::text, 6, '0');

  -- HDN-374 finding 3 (closes HDN-BLK-010's own required scope): a genuine race between
  -- the select above and this insert (two concurrent callers preparing the same
  -- source_type/source_id) is resolved by re-selecting and returning the winner.
  -- Backed by finance_journals_idempotency_unique.
  begin
    insert into app.finance_journals (
      tenant_id, company_id, journal_number, source_type, source_id, idempotency_key,
      currency, total_amount, journal_date, status, posting_period_id, posted_by, posted_at, created_by
    )
    values (
      p_tenant_id, p_company_id, v_number, p_source_type, p_source_id, p_source_type || ':' || p_source_id::text,
      p_currency, v_total, p_journal_date, 'posted', v_period.period_id, p_actor_label, now(), p_actor_label
    )
    returning * into v_journal;
  exception
    when unique_violation then
      select * into v_journal from app.finance_journals where tenant_id = p_tenant_id and source_type = p_source_type and source_id = p_source_id;
      if found then
        return v_journal;
      end if;
      raise;
  end;

  for v_line in select * from jsonb_array_elements(p_lines) loop
    v_line_number := v_line_number + 1;
    insert into app.finance_journal_lines (journal_id, tenant_id, line_number, account_id, dimension, direction, amount)
    values (v_journal.id, p_tenant_id, v_line_number, (v_line ->> 'accountId')::uuid, v_line -> 'dimension', v_line ->> 'direction', (v_line ->> 'amount')::numeric);
  end loop;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_and_post_finance_system_journal',
    'app.finance_journals', v_journal.id, 'success', null, null, to_jsonb(v_journal)
  );

  return v_journal;
end;
$function$;

create or replace function app.post_finance_settlement(p_settlement_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.finance_settlements
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_settlement app.finance_settlements;
  v_period record;
  v_year integer;
  v_seq integer;
  v_number text;
  v_allocation app.finance_settlement_allocations;
  v_lines jsonb;
begin
  select * into v_settlement from app.finance_settlements where id = p_settlement_id for update;
  if not found or not app.has_active_tenant_membership(v_settlement.tenant_id, p_actor_auth_user_id) then
    raise exception 'finance_settlement_not_found: %', p_settlement_id using errcode = 'no_data_found';
  end if;
  if v_settlement.status = 'posted' then
    return v_settlement;
  end if;
  if not app.check_finance_settlement_authority('Approve', v_settlement.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_settlement.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-302: IP allowlist, checked after authority is established and before any
  -- state change. Skipped when the caller supplies no address, and bypassable via the
  -- separately-governed app.ip_allowlist_bypass_grants -- the identical composition
  -- 20260826190000 established for the import-commit RPCs.
  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(v_settlement.tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(v_settlement.tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;
  if v_settlement.record_version <> p_expected_version then
    raise exception 'stale_version: settlement % expected version % but found %', p_settlement_id, p_expected_version, v_settlement.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_settlement.status <> 'executed' then
    raise exception 'finance_settlement_not_executed: settlement % is % not executed', p_settlement_id, v_settlement.status
      using errcode = 'check_violation';
  end if;

  select * into v_period from app.resolve_finance_period_for_date(v_settlement.tenant_id, v_settlement.company_id, v_settlement.settlement_date);
  if not found then
    raise exception 'finance_settlement_period_not_found: no fiscal period covers %', v_settlement.settlement_date
      using errcode = 'no_data_found';
  end if;
  if not v_period.posting_eligible then
    raise exception 'finance_settlement_period_not_open: fiscal period % for % is not open', v_period.period_code, v_settlement.settlement_date
      using errcode = 'check_violation';
  end if;

  for v_allocation in select * from app.finance_settlement_allocations where settlement_id = p_settlement_id and status = 'applied' order by created_at asc loop
    perform app.apply_finance_ap_settlement(
      v_allocation.ap_open_item_id, v_allocation.amount, 'settlement', v_settlement.id,
      v_settlement.idempotency_key || ':' || v_allocation.ap_open_item_id::text, p_actor_auth_user_id, p_actor_label
    );
  end loop;

  -- FIN-202: debit AP control for the allocated total (plus a governed fee
  -- expense debit when a fee applies); credit cash for the full total.
  v_lines := jsonb_build_array(
    jsonb_build_object('postingMapKey', 'ap_control', 'direction', 'debit', 'amount', v_settlement.allocated_amount)
  );
  if v_settlement.fee_amount > 0 then
    v_lines := v_lines || jsonb_build_array(jsonb_build_object('postingMapKey', 'fee_expense_default', 'direction', 'debit', 'amount', v_settlement.fee_amount));
  end if;
  v_lines := v_lines || jsonb_build_array(jsonb_build_object('postingMapKey', 'cash_default', 'direction', 'credit', 'amount', v_settlement.total_amount));

  perform app.post_finance_subledger_batch(
    v_settlement.tenant_id, v_settlement.company_id, 'settlement', v_settlement.id, v_settlement.settlement_date, v_settlement.currency,
    v_lines, p_actor_auth_user_id, p_actor_label
  );

  v_year := extract(year from v_settlement.settlement_date)::integer;
  insert into app.finance_settlement_number_counters (tenant_id, company_id, year, next_seq)
  values (v_settlement.tenant_id, v_settlement.company_id, v_year, 2)
  on conflict (tenant_id, year)
  do update set next_seq = app.finance_settlement_number_counters.next_seq + 1
  returning next_seq - 1 into v_seq;
  v_number := 'SETL-' || v_year::text || '-' || lpad(v_seq::text, 6, '0');

  update app.finance_settlements
    set status = 'posted', settlement_number = v_number, posting_period_id = v_period.period_id,
        posted_by = p_actor_label, posted_at = now()
    where id = p_settlement_id
    returning * into v_settlement;

  perform app.capture_audit_event(
    v_settlement.tenant_id, p_actor_auth_user_id, p_actor_label, 'post_finance_settlement',
    'app.finance_settlements', v_settlement.id, 'success', null, null, to_jsonb(v_settlement)
  );

  return v_settlement;
end;
$function$;

create or replace function app.post_finance_vendor_bill(p_bill_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text default null)
 RETURNS app.finance_vendor_bills
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_bill app.finance_vendor_bills;
  v_period record;
  v_year integer;
  v_seq integer;
  v_number text;
  v_ap_item app.finance_ap_open_items;
  v_lines jsonb;
  v_tax_line app.finance_vendor_bill_lines;
  v_tax_rule app.finance_tax_rule_versions;
begin
  select * into v_bill from app.finance_vendor_bills where id = p_bill_id for update;
  if not found or not app.has_active_tenant_membership(v_bill.tenant_id, p_actor_auth_user_id) then
    raise exception 'finance_vendor_bill_not_found: %', p_bill_id using errcode = 'no_data_found';
  end if;
  if v_bill.status = 'posted' then
    return v_bill;
  end if;
  if not app.check_finance_vendor_bill_authority('Approve', v_bill.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_bill.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-302: IP allowlist, checked after authority is established and before any
  -- state change. Skipped when the caller supplies no address, and bypassable via the
  -- separately-governed app.ip_allowlist_bypass_grants -- the identical composition
  -- 20260826190000 established for the import-commit RPCs.
  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(v_bill.tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(v_bill.tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;
  if v_bill.record_version <> p_expected_version then
    raise exception 'stale_version: bill % expected version % but found %', p_bill_id, p_expected_version, v_bill.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_bill.status <> 'approved' then
    raise exception 'finance_vendor_bill_not_approved: bill % is % not approved', p_bill_id, v_bill.status
      using errcode = 'check_violation';
  end if;

  select * into v_period from app.resolve_finance_period_for_date(v_bill.tenant_id, v_bill.company_id, v_bill.bill_date);
  if not found then
    raise exception 'finance_vendor_bill_period_not_found: no fiscal period covers %', v_bill.bill_date
      using errcode = 'no_data_found';
  end if;
  if not v_period.posting_eligible then
    raise exception 'finance_vendor_bill_period_not_open: fiscal period % for % is not open', v_period.period_code, v_bill.bill_date
      using errcode = 'check_violation';
  end if;

  v_year := extract(year from v_bill.bill_date)::integer;
  insert into app.finance_vendor_bill_number_counters (tenant_id, company_id, year, next_seq)
  values (v_bill.tenant_id, v_bill.company_id, v_year, 2)
  on conflict (tenant_id, year)
  do update set next_seq = app.finance_vendor_bill_number_counters.next_seq + 1
  returning next_seq - 1 into v_seq;
  v_number := 'BILL-' || v_year::text || '-' || lpad(v_seq::text, 6, '0');

  select * into v_ap_item from app.post_finance_ap_open_item(
    v_bill.tenant_id, v_bill.company_id, v_bill.vendor_master_id, 'vendor_bill', v_bill.id,
    v_bill.currency, v_bill.total_amount, v_bill.bill_date, v_bill.due_date, p_actor_auth_user_id, p_actor_label
  );

  -- FIN-202: debit expense for the subtotal; debit each tax line's own
  -- governed recoverable account (or the input_tax_default posting-map key
  -- when none is configured); credit AP control for the full total.
  v_lines := '[]'::jsonb;
  if v_bill.subtotal_amount > 0 then
    v_lines := v_lines || jsonb_build_array(jsonb_build_object('postingMapKey', 'expense_default', 'direction', 'debit', 'amount', v_bill.subtotal_amount));
  end if;
  for v_tax_line in select * from app.finance_vendor_bill_lines where bill_id = p_bill_id and line_type = 'tax' and amount > 0 loop
    v_tax_rule := null;
    if v_tax_line.tax_rule_version_id is not null then
      select * into v_tax_rule from app.finance_tax_rule_versions where id = v_tax_line.tax_rule_version_id and recoverable_account_id is not null;
    end if;
    if v_tax_rule is not null then
      v_lines := v_lines || jsonb_build_array(jsonb_build_object('accountId', v_tax_rule.recoverable_account_id, 'direction', 'debit', 'amount', v_tax_line.amount));
    else
      v_lines := v_lines || jsonb_build_array(jsonb_build_object('postingMapKey', 'input_tax_default', 'direction', 'debit', 'amount', v_tax_line.amount));
    end if;
  end loop;
  v_lines := v_lines || jsonb_build_array(jsonb_build_object('postingMapKey', 'ap_control', 'direction', 'credit', 'amount', v_bill.total_amount, 'openItemType', 'ap_open_item', 'openItemId', v_ap_item.id));

  perform app.post_finance_subledger_batch(
    v_bill.tenant_id, v_bill.company_id, 'vendor_bill', v_bill.id, v_bill.bill_date, v_bill.currency,
    v_lines, p_actor_auth_user_id, p_actor_label
  );

  update app.finance_vendor_bills
    set status = 'posted', bill_number = v_number, posting_period_id = v_period.period_id, ap_open_item_id = v_ap_item.id,
        posted_by = p_actor_label, posted_at = now()
    where id = p_bill_id
    returning * into v_bill;

  perform app.capture_audit_event(
    v_bill.tenant_id, p_actor_auth_user_id, p_actor_label, 'post_finance_vendor_bill',
    'app.finance_vendor_bills', v_bill.id, 'success', null, null, to_jsonb(v_bill)
  );

  return v_bill;
end;
$function$;

-- The 6th affected function -- shares app.finance_journal_number_counters with
-- app.post_finance_journal/app.create_and_post_finance_system_journal above but
-- is its own separate historical-backdate entry point
-- (20260826160000_create_finance_journal_historical_import.sql), not covered
-- by the "5 RPCs" the workflow-driven investigate agent's own report named.
create or replace function app.import_historical_finance_journal(p_tenant_id uuid, p_company_id uuid, p_source_id uuid, p_journal_date date, p_currency text, p_lines jsonb, p_reason text, p_actor_auth_user_id uuid, p_actor_label text, p_client_ip text DEFAULT NULL::text)
 returns app.finance_journals
 language plpgsql
 security definer
 set search_path to 'app', 'pg_temp'
as $function$
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

  -- ISS-2026-302: IP allowlist, checked after authority is established and before any
  -- state change. Skipped when the caller supplies no address, and bypassable via the
  -- separately-governed app.ip_allowlist_bypass_grants -- the identical composition
  -- 20260826190000 established for the import-commit RPCs.
  if p_client_ip is not null and not app.has_active_ip_allowlist_bypass(p_tenant_id, p_actor_auth_user_id) then
    perform app.assert_ip_allowed(p_tenant_id, p_client_ip, 'admin', p_actor_label);
  end if;
  perform app.assert_finance_company_org_unit(p_tenant_id, p_company_id);

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
  on conflict (tenant_id, year)
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
$function$;
