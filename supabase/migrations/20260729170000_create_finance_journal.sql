-- Finance capability FIN-203 (Double-Entry Journal, CG-S9-FIN-014)
-- Canonical double-entry journal: exact debit-equals-credit posting, source
-- lineage, and one shared posting service used by both an authorized manual
-- journal and every system-sourced (subledger) posting -- closing FIN-202's
-- own disclosed `gl_journal_id` forward reference.
--
-- One shared posting service (Prompt 203 section 24: "Every posting uses
-- one shared service and idempotency boundary"): `app.validate_finance_journal_line_balance`
-- (at least two lines, exact nonzero debit=credit) is the one balance rule
-- both `app.create_finance_journal_draft` (manual) and
-- `app.create_and_post_finance_system_journal` (system) call -- never two
-- competing balance checks. `app.post_finance_journal` (manual,
-- approved -> posted) re-validates the same stored lines before assigning a
-- journal_number, the identical re-check `app.create_and_post_finance_system_journal`
-- performs inline at creation, since a system journal has no separate
-- draft/approve stage (its own source event was already authority-checked
-- and approved upstream -- Prompt 203 section 22's own "authorized manual
-- adjustment with full reason/source" is the *manual* path; a subledger
-- batch is never itself an unauthorized "arbitrary source event").
--
-- Closes FIN-202's own disclosed forward reference: this migration
-- `CREATE OR REPLACE FUNCTION`s `app.post_finance_subledger_batch`
-- (FIN-202) -- the established later-migration-extends-an-earlier-one's-
-- function pattern -- to additionally call
-- `app.create_and_post_finance_system_journal` with the exact same
-- already-resolved account/direction/amount lines it just wrote to
-- `app.finance_subledger_lines`, then sets that batch's own `gl_journal_id`.
-- One posted journal per posted subledger batch, never a second.
--
-- Manual journal lifecycle (Prompt 203 section 21/26): Accounting prepares
-- a draft (`FIN:Edit`, direct account references, no posting-map
-- resolution -- a human names each account&mdash;), submits, a configured
-- approver approves (`FIN:Approve`), then posts (`FIN:Approve` -- this
-- checkpoint has no separate treasury/GL-poster role, so approve and post
-- share `FIN:Approve`, the identical disclosed bound `FIN-201`'s own
-- settlement execute/post recorded). System journals skip the draft/
-- approve stages entirely and post immediately, since they represent an
-- already-authorized event, never a silent bypass of the manual path's own
-- controls.
--
-- Reversal is explicitly out of scope (Prompt 203 section 32: "reverse
-- posted journal via FIN-206") -- no reversal function exists here; a
-- posted journal has no direct-edit path for a normal role.
--
-- Money/decimal discipline: every amount column is `numeric(14,2)`, never
-- `float`; a journal is rejected before any row is written unless debit
-- total exactly equals credit total and is nonzero.
--
-- Per `ERR-2026-004` (`docs/runtime/ERROR_LEDGER.md`): this migration
-- carries its own explicit `REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA app
-- FROM PUBLIC` statement before its final grants, the standing
-- per-migration convention since `PLT-118`.

create table app.finance_journals (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  company_id uuid references app.org_units (id),
  journal_number text,
  source_type text not null,
  source_id uuid,
  idempotency_key text not null,
  currency text not null,
  total_amount numeric(14, 2) not null,
  journal_date date not null,
  status text not null default 'draft',
  posting_period_id uuid references app.finance_fiscal_periods (id),
  submitted_by text,
  submitted_at timestamptz,
  approved_by text,
  approved_at timestamptz,
  posted_by text,
  posted_at timestamptz,
  void_reason text,
  voided_by text,
  voided_at timestamptz,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint finance_journals_source_type_check check (source_type in ('manual', 'subledger')),
  constraint finance_journals_status_check check (status in ('draft', 'submitted', 'approved', 'posted', 'void')),
  constraint finance_journals_currency_check check (currency ~ '^[A-Z]{3}$'),
  constraint finance_journals_total_amount_check check (total_amount > 0),
  constraint finance_journals_idempotency_unique unique (tenant_id, idempotency_key),
  constraint finance_journals_source_check check (
    (source_type = 'manual' and source_id is null) or (source_type = 'subledger' and source_id is not null)
  )
);

comment on table app.finance_journals is
  'FIN-203: one balanced double-entry journal (manual or system/subledger-sourced), idempotent on (tenant_id, idempotency_key). total_amount equals both the debit and credit total by construction -- app.validate_finance_journal_line_balance rejects any batch where they differ before a row is written. journal_number is null until posted. A system journal (source_type=subledger) posts immediately, skipping draft/submitted/approved -- its own source event was already authority-checked upstream.';

create unique index finance_journals_tenant_number_unique on app.finance_journals (tenant_id, journal_number) where journal_number is not null;
create unique index finance_journals_tenant_source_unique on app.finance_journals (tenant_id, source_type, source_id) where source_id is not null;
create index finance_journals_tenant_status_idx on app.finance_journals (tenant_id, status);
create index finance_journals_tenant_period_idx on app.finance_journals (tenant_id, posting_period_id);

create function app.touch_finance_journal_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger finance_journals_touch_row
  before update on app.finance_journals
  for each row
  execute function app.touch_finance_journal_row();

create table app.finance_journal_lines (
  id uuid primary key default gen_random_uuid(),
  journal_id uuid not null references app.finance_journals (id),
  tenant_id uuid not null references app.tenants (id),
  line_number integer not null,
  account_id uuid not null references app.finance_accounts (id),
  dimension jsonb,
  direction text not null,
  amount numeric(14, 2) not null,
  description text,
  created_at timestamptz not null default now(),
  constraint finance_journal_lines_direction_check check (direction in ('debit', 'credit')),
  constraint finance_journal_lines_amount_check check (amount > 0),
  constraint finance_journal_lines_journal_line_unique unique (journal_id, line_number)
);

comment on table app.finance_journal_lines is
  'FIN-203: one exact debit/credit line for a double-entry journal. dimension is a free-form jsonb tag (e.g. branch/service/customer-class) -- Prompt 203 section 58''s own "account/dimension" scope is bounded to accepting and storing a caller-supplied dimension tag, not a governed dimension catalogue (FIN-191''s own finance_dimensions config type remains the source of truth for which tags are valid; this checkpoint does not yet validate dimension values against it, disclosed bound).';

create index finance_journal_lines_journal_idx on app.finance_journal_lines (journal_id);
create index finance_journal_lines_account_idx on app.finance_journal_lines (tenant_id, account_id);

create table app.finance_journal_number_counters (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  company_id uuid,
  year integer not null,
  next_seq integer not null default 1
);

comment on table app.finance_journal_number_counters is
  'FIN-203: a simple per-tenant/company/year sequential counter for journal numbers, assigned only at post time -- mirrors FIN-200''s own app.finance_vendor_bill_number_counters exactly. Shared by both the manual (app.post_finance_journal) and system (app.create_and_post_finance_system_journal) posting paths.';

create unique index finance_journal_number_counters_scope_unique on app.finance_journal_number_counters (
  tenant_id, coalesce(company_id, '00000000-0000-0000-0000-000000000000'::uuid), year
);

create function app.check_finance_journal_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid)
returns boolean
language sql
stable
as $$
  select (app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'FIN', p_action)).allowed;
$$;

comment on function app.check_finance_journal_authority is
  'FIN-203: FIN:Edit gates manual prepare/submit/discard; FIN:Approve gates approve/post (this checkpoint has no separate treasury/GL-poster role, so approve and post share FIN:Approve -- the identical disclosed bound FIN-201''s own settlement execute/post recorded); FIN:View gates read.';

-- The one shared balance rule (Prompt 203 section 24/25). Raises a distinct
-- named exception for every failure mode; returns the balanced total.
create function app.validate_finance_journal_line_balance(p_lines jsonb)
returns numeric
language plpgsql
as $$
declare
  v_line jsonb;
  v_direction text;
  v_amount numeric;
  v_debit_total numeric(14, 2) := 0;
  v_credit_total numeric(14, 2) := 0;
  v_line_count integer := 0;
begin
  if p_lines is null or jsonb_array_length(p_lines) < 2 then
    raise exception 'finance_journal_insufficient_lines: at least two lines are required' using errcode = 'check_violation';
  end if;

  for v_line in select * from jsonb_array_elements(p_lines) loop
    v_line_count := v_line_count + 1;
    v_direction := v_line ->> 'direction';
    v_amount := (v_line ->> 'amount')::numeric;
    if v_direction not in ('debit', 'credit') then
      raise exception 'finance_journal_invalid_direction: % is not debit or credit', v_direction using errcode = 'check_violation';
    end if;
    if v_amount is null or v_amount <= 0 then
      raise exception 'finance_journal_invalid_line_amount: line amount must be positive, got %', v_amount using errcode = 'check_violation';
    end if;
    if v_direction = 'debit' then
      v_debit_total := v_debit_total + v_amount;
    else
      v_credit_total := v_credit_total + v_amount;
    end if;
  end loop;

  if v_debit_total <> v_credit_total or v_debit_total = 0 then
    raise exception 'finance_journal_unbalanced: debit total % does not equal credit total % (or is zero)', v_debit_total, v_credit_total
      using errcode = 'check_violation';
  end if;

  return v_debit_total;
end;
$$;

-- Manual journal preparation (Prompt 203 section 21/22). Direct account
-- references chosen by the preparer -- validated active/postable/same
-- tenant, never posting-map-resolved (that is FIN-202's own generic-source
-- idiom, not a human-authored entry).
create function app.create_finance_journal_draft(
  p_tenant_id uuid,
  p_company_id uuid,
  p_journal_date date,
  p_currency text,
  p_lines jsonb,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.finance_journals
language plpgsql
as $$
declare
  v_journal app.finance_journals;
  v_line jsonb;
  v_account app.finance_accounts;
  v_total numeric(14, 2);
  v_line_number integer := 0;
begin
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % holds no active membership for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.check_finance_journal_authority('Edit', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'idempotency_key_required: a non-empty idempotency_key is required' using errcode = 'check_violation';
  end if;
  if not app.validate_currency_code(p_currency) then
    raise exception 'finance_journal_unsupported_currency: % is not a registered, active currency', p_currency
      using errcode = 'check_violation';
  end if;

  select * into v_journal from app.finance_journals where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
  if found then
    return v_journal;
  end if;

  v_total := app.validate_finance_journal_line_balance(p_lines);

  for v_line in select * from jsonb_array_elements(p_lines) loop
    select * into v_account from app.finance_accounts where id = (v_line ->> 'accountId')::uuid and tenant_id = p_tenant_id;
    if not found then
      raise exception 'finance_journal_account_not_found: % is not a known account for tenant %', v_line ->> 'accountId', p_tenant_id
        using errcode = 'no_data_found';
    end if;
    if v_account.status <> 'active' then
      raise exception 'finance_journal_inactive_account: account % is not active (status=%)', v_account.code, v_account.status
        using errcode = 'check_violation';
    end if;
    if not v_account.is_postable then
      raise exception 'finance_journal_not_postable_account: account % is not postable (control account)', v_account.code
        using errcode = 'check_violation';
    end if;
  end loop;

  insert into app.finance_journals (tenant_id, company_id, source_type, currency, total_amount, journal_date, idempotency_key, created_by)
  values (p_tenant_id, p_company_id, 'manual', p_currency, v_total, p_journal_date, p_idempotency_key, p_actor_label)
  returning * into v_journal;

  for v_line in select * from jsonb_array_elements(p_lines) loop
    v_line_number := v_line_number + 1;
    insert into app.finance_journal_lines (journal_id, tenant_id, line_number, account_id, dimension, direction, amount, description)
    values (
      v_journal.id, p_tenant_id, v_line_number, (v_line ->> 'accountId')::uuid, v_line -> 'dimension',
      v_line ->> 'direction', (v_line ->> 'amount')::numeric, v_line ->> 'description'
    );
  end loop;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_finance_journal_draft',
    'app.finance_journals', v_journal.id, 'success', null, null, to_jsonb(v_journal)
  );

  return v_journal;
end;
$$;

create function app.submit_finance_journal_for_approval(
  p_journal_id uuid,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.finance_journals
language plpgsql
as $$
declare
  v_journal app.finance_journals;
begin
  select * into v_journal from app.finance_journals where id = p_journal_id;
  if not found then
    raise exception 'finance_journal_not_found: %', p_journal_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_journal_authority('Edit', v_journal.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, v_journal.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_journal.record_version <> p_expected_version then
    raise exception 'stale_version: journal % expected version % but found %', p_journal_id, p_expected_version, v_journal.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_journal.status <> 'draft' then
    raise exception 'finance_journal_not_draft: journal % is % not draft', p_journal_id, v_journal.status
      using errcode = 'check_violation';
  end if;

  update app.finance_journals set status = 'submitted', submitted_by = p_actor_label, submitted_at = now() where id = p_journal_id returning * into v_journal;

  perform app.capture_audit_event(
    v_journal.tenant_id, p_actor_auth_user_id, p_actor_label, 'submit_finance_journal_for_approval',
    'app.finance_journals', v_journal.id, 'success', null, null, to_jsonb(v_journal)
  );

  return v_journal;
end;
$$;

create function app.discard_finance_journal_draft(
  p_journal_id uuid,
  p_expected_version integer,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.finance_journals
language plpgsql
as $$
declare
  v_journal app.finance_journals;
begin
  select * into v_journal from app.finance_journals where id = p_journal_id;
  if not found then
    raise exception 'finance_journal_not_found: %', p_journal_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_journal_authority('Edit', v_journal.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, v_journal.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_journal.record_version <> p_expected_version then
    raise exception 'stale_version: journal % expected version % but found %', p_journal_id, p_expected_version, v_journal.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_journal.status not in ('draft', 'submitted') then
    raise exception 'finance_journal_not_cancellable: journal % is %, only a draft or submitted journal may be discarded', p_journal_id, v_journal.status
      using errcode = 'check_violation';
  end if;

  update app.finance_journals set status = 'void', void_reason = p_reason, voided_by = p_actor_label, voided_at = now() where id = p_journal_id returning * into v_journal;

  perform app.capture_audit_event(
    v_journal.tenant_id, p_actor_auth_user_id, p_actor_label, 'discard_finance_journal_draft',
    'app.finance_journals', v_journal.id, 'success', p_reason, null, to_jsonb(v_journal)
  );

  return v_journal;
end;
$$;

create function app.approve_finance_journal(
  p_journal_id uuid,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.finance_journals
language plpgsql
as $$
declare
  v_journal app.finance_journals;
begin
  select * into v_journal from app.finance_journals where id = p_journal_id;
  if not found then
    raise exception 'finance_journal_not_found: %', p_journal_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_journal_authority('Approve', v_journal.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_journal.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_journal.record_version <> p_expected_version then
    raise exception 'stale_version: journal % expected version % but found %', p_journal_id, p_expected_version, v_journal.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_journal.status <> 'submitted' then
    raise exception 'finance_journal_not_submitted: journal % is % not submitted', p_journal_id, v_journal.status
      using errcode = 'check_violation';
  end if;

  update app.finance_journals set status = 'approved', approved_by = p_actor_label, approved_at = now() where id = p_journal_id returning * into v_journal;

  perform app.capture_audit_event(
    v_journal.tenant_id, p_actor_auth_user_id, p_actor_label, 'approve_finance_journal',
    'app.finance_journals', v_journal.id, 'success', null, null, to_jsonb(v_journal)
  );

  return v_journal;
end;
$$;

-- Manual journal posting (approved -> posted). Idempotent -- a retried call
-- against an already-posted journal returns it unchanged. Re-validates the
-- stored lines' own balance before assigning a journal_number, the same
-- app.validate_finance_journal_line_balance rule the system path uses.
create function app.post_finance_journal(
  p_journal_id uuid,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.finance_journals
language plpgsql
as $$
declare
  v_journal app.finance_journals;
  v_period record;
  v_year integer;
  v_seq integer;
  v_number text;
  v_lines jsonb;
begin
  select * into v_journal from app.finance_journals where id = p_journal_id;
  if not found then
    raise exception 'finance_journal_not_found: %', p_journal_id using errcode = 'no_data_found';
  end if;
  if v_journal.status = 'posted' then
    return v_journal;
  end if;
  if not app.check_finance_journal_authority('Approve', v_journal.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_journal.tenant_id
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

  v_year := extract(year from v_journal.journal_date)::integer;
  insert into app.finance_journal_number_counters (tenant_id, company_id, year, next_seq)
  values (v_journal.tenant_id, v_journal.company_id, v_year, 2)
  on conflict (tenant_id, coalesce(company_id, '00000000-0000-0000-0000-000000000000'::uuid), year)
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
$$;

-- The system-sourced posting entry point (Prompt 203 section 21's own
-- "Authorized source... service validates... then the journal posts
-- once"). Idempotent on (tenant_id, source_type, source_id). Posts
-- immediately -- no draft/approve stage, since the caller's own source
-- event was already authority-checked upstream (FIN-202's own
-- app.post_finance_subledger_batch, itself FIN:Edit-gated).
create function app.create_and_post_finance_system_journal(
  p_tenant_id uuid,
  p_company_id uuid,
  p_source_type text,
  p_source_id uuid,
  p_journal_date date,
  p_currency text,
  p_lines jsonb,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.finance_journals
language plpgsql
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
  if p_source_type <> 'subledger' then
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
    p_tenant_id, p_company_id, v_number, p_source_type, p_source_id, p_source_type || ':' || p_source_id::text,
    p_currency, v_total, p_journal_date, 'posted', v_period.period_id, p_actor_label, now(), p_actor_label
  )
  returning * into v_journal;

  for v_line in select * from jsonb_array_elements(p_lines) loop
    v_line_number := v_line_number + 1;
    insert into app.finance_journal_lines (journal_id, tenant_id, line_number, account_id, direction, amount)
    values (v_journal.id, p_tenant_id, v_line_number, (v_line ->> 'accountId')::uuid, v_line ->> 'direction', (v_line ->> 'amount')::numeric);
  end loop;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_and_post_finance_system_journal',
    'app.finance_journals', v_journal.id, 'success', null, null, to_jsonb(v_journal)
  );

  return v_journal;
end;
$$;

create function app.list_finance_journals(
  p_tenant_id uuid,
  p_company_id uuid,
  p_source_type text,
  p_status text,
  p_actor_auth_user_id uuid
)
returns setof app.finance_journals
language plpgsql
stable
as $$
begin
  if not app.check_finance_journal_authority('View', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  return query select * from app.finance_journals
    where tenant_id = p_tenant_id
      and (p_company_id is null or company_id = p_company_id)
      and (p_source_type is null or source_type = p_source_type)
      and (p_status is null or status = p_status)
    order by created_at desc
    limit 200;
end;
$$;

create function app.get_finance_journal_lines(p_journal_id uuid, p_actor_auth_user_id uuid)
returns setof app.finance_journal_lines
language plpgsql
stable
as $$
declare
  v_journal app.finance_journals;
begin
  select * into v_journal from app.finance_journals where id = p_journal_id;
  if not found then
    raise exception 'finance_journal_not_found: %', p_journal_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_journal_authority('View', v_journal.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, v_journal.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  return query select * from app.finance_journal_lines where journal_id = p_journal_id order by line_number asc;
end;
$$;

-- FIN-203 retrofit: closes FIN-202's own disclosed gl_journal_id forward
-- reference. Every other line of this function's own body is byte-for-byte
-- unchanged from FIN-202's original; the only addition is the system
-- journal lines accumulator and the app.create_and_post_finance_system_journal
-- call plus the gl_journal_id update immediately before returning.
create or replace function app.post_finance_subledger_batch(
  p_tenant_id uuid,
  p_company_id uuid,
  p_source_type text,
  p_source_id uuid,
  p_posting_date date,
  p_currency text,
  p_lines jsonb,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.finance_subledger_batches
language plpgsql
as $$
declare
  v_batch app.finance_subledger_batches;
  v_period record;
  v_line jsonb;
  v_line_number integer := 0;
  v_debit_total numeric(14, 2) := 0;
  v_credit_total numeric(14, 2) := 0;
  v_direction text;
  v_amount numeric;
  v_account app.finance_accounts;
  v_key text;
  v_journal_lines jsonb := '[]'::jsonb;
  v_journal app.finance_journals;
begin
  if p_source_type not in ('invoice', 'receipt_allocation', 'vendor_bill', 'settlement') then
    raise exception 'finance_subledger_unsupported_source_type: % is not a supported subledger source type', p_source_type
      using errcode = 'check_violation';
  end if;
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % holds no active membership for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.check_finance_subledger_authority('Edit', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_batch from app.finance_subledger_batches where tenant_id = p_tenant_id and source_type = p_source_type and source_id = p_source_id;
  if found then
    return v_batch;
  end if;

  if p_lines is null or jsonb_array_length(p_lines) = 0 then
    raise exception 'finance_subledger_empty_batch: at least one line is required' using errcode = 'check_violation';
  end if;

  select * into v_period from app.resolve_finance_period_for_date(p_tenant_id, p_company_id, p_posting_date);
  if not found then
    raise exception 'finance_subledger_period_not_found: no fiscal period covers %', p_posting_date
      using errcode = 'no_data_found';
  end if;
  if not v_period.posting_eligible then
    raise exception 'finance_subledger_period_not_open: fiscal period % for % is not open', v_period.period_code, p_posting_date
      using errcode = 'check_violation';
  end if;

  for v_line in select * from jsonb_array_elements(p_lines) loop
    v_direction := v_line ->> 'direction';
    v_amount := (v_line ->> 'amount')::numeric;
    if v_direction not in ('debit', 'credit') then
      raise exception 'finance_subledger_invalid_direction: % is not debit or credit', v_direction using errcode = 'check_violation';
    end if;
    if v_amount is null or v_amount <= 0 then
      raise exception 'finance_subledger_invalid_line_amount: line amount must be positive, got %', v_amount using errcode = 'check_violation';
    end if;
    if v_direction = 'debit' then
      v_debit_total := v_debit_total + v_amount;
    else
      v_credit_total := v_credit_total + v_amount;
    end if;
  end loop;

  if v_debit_total <> v_credit_total then
    raise exception 'finance_subledger_unbalanced_batch: debit total % does not equal credit total % for source % %', v_debit_total, v_credit_total, p_source_type, p_source_id
      using errcode = 'check_violation';
  end if;

  insert into app.finance_subledger_batches (tenant_id, company_id, source_type, source_id, currency, total_amount, posting_period_id, posted_by)
  values (p_tenant_id, p_company_id, p_source_type, p_source_id, p_currency, v_debit_total, v_period.period_id, p_actor_label)
  returning * into v_batch;

  for v_line in select * from jsonb_array_elements(p_lines) loop
    v_line_number := v_line_number + 1;

    if v_line ->> 'accountId' is not null then
      select * into v_account from app.finance_accounts where id = (v_line ->> 'accountId')::uuid and tenant_id = p_tenant_id;
      if not found then
        raise exception 'finance_subledger_unresolved_account: % is not a known account for tenant %', v_line ->> 'accountId', p_tenant_id
          using errcode = 'no_data_found';
      end if;
      if v_account.status <> 'active' then
        raise exception 'finance_subledger_inactive_mapped_account: account % is not active (status=%)', v_account.code, v_account.status
          using errcode = 'check_violation';
      end if;
      if not v_account.is_postable then
        raise exception 'finance_subledger_not_postable_mapped_account: account % is not postable (control account)', v_account.code
          using errcode = 'check_violation';
      end if;
      v_key := null;
    else
      v_key := v_line ->> 'postingMapKey';
      v_account := app.resolve_finance_posting_map_account(p_tenant_id, v_key);
    end if;

    insert into app.finance_subledger_lines (batch_id, tenant_id, line_number, account_id, posting_map_key, direction, amount, open_item_type, open_item_id)
    values (
      v_batch.id, p_tenant_id, v_line_number, v_account.id, v_key, v_line ->> 'direction', (v_line ->> 'amount')::numeric,
      v_line ->> 'openItemType', nullif(v_line ->> 'openItemId', '')::uuid
    );

    v_journal_lines := v_journal_lines || jsonb_build_array(jsonb_build_object('accountId', v_account.id, 'direction', v_line ->> 'direction', 'amount', (v_line ->> 'amount')::numeric));
  end loop;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'post_finance_subledger_batch',
    'app.finance_subledger_batches', v_batch.id, 'success', null, null,
    jsonb_build_object('sourceType', p_source_type, 'sourceId', p_source_id, 'totalAmount', v_debit_total)
  );

  -- FIN-203: close the disclosed gl_journal_id forward reference -- one
  -- posted system journal per posted subledger batch, sharing this
  -- function's own already-resolved account/direction/amount lines
  -- exactly.
  select * into v_journal from app.create_and_post_finance_system_journal(
    p_tenant_id, p_company_id, 'subledger', v_batch.id, p_posting_date, p_currency, v_journal_lines, p_actor_auth_user_id, p_actor_label
  );
  update app.finance_subledger_batches set gl_journal_id = v_journal.id where id = v_batch.id returning * into v_batch;

  return v_batch;
end;
$$;

alter table app.finance_journals enable row level security;
alter table app.finance_journal_lines enable row level security;

create policy finance_journals_select_scoped on app.finance_journals
  for select to authenticated
  using (app.has_active_tenant_membership(tenant_id) or app.is_supreme_admin());

create policy finance_journal_lines_select_scoped on app.finance_journal_lines
  for select to authenticated
  using (app.has_active_tenant_membership(tenant_id) or app.is_supreme_admin());

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit, directly-provable
-- revoke of PostgreSQL's PUBLIC-execute default, the standing per-migration
-- convention since PLT-118, applied here before any role-specific grant.
revoke execute on all functions in schema app from public;

grant select on app.finance_journals to authenticated, service_role;
grant select on app.finance_journal_lines to authenticated, service_role;
grant insert, update, delete on app.finance_journals to service_role;
grant insert, update, delete on app.finance_journal_lines to service_role;
grant select, insert, update on app.finance_journal_number_counters to service_role;

grant execute on function app.touch_finance_journal_row() to service_role;
grant execute on function app.check_finance_journal_authority(text, uuid, uuid) to service_role;
grant execute on function app.validate_finance_journal_line_balance(jsonb) to service_role;
grant execute on function app.create_finance_journal_draft(uuid, uuid, date, text, jsonb, text, uuid, text) to authenticated, service_role;
grant execute on function app.submit_finance_journal_for_approval(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.discard_finance_journal_draft(uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.approve_finance_journal(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.post_finance_journal(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.create_and_post_finance_system_journal(uuid, uuid, text, uuid, date, text, jsonb, uuid, text) to authenticated, service_role;
grant execute on function app.list_finance_journals(uuid, uuid, text, text, uuid) to authenticated, service_role;
grant execute on function app.get_finance_journal_lines(uuid, uuid) to authenticated, service_role;
