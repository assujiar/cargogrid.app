-- Finance capability FIN-207 (Period Lock and Governed Reopen, CG-S9-FIN-018)
-- Company/ledger/module-aware period locks enforced at the posting
-- boundary with governed reopen and re-lock. A layer *on top of* FIN-193's
-- own fiscal-period lifecycle (open/soft-close/closed/posting_eligible) --
-- not a replacement for it. FIN-193's own `posting_eligible` already blocks
-- posting into a genuinely closed period; this checkpoint adds a finer,
-- explicitly *scoped* lock (e.g. lock only `ar` for a period while `gl`
-- remains open) with its own reason/evidence, a time-boxed governed reopen
-- window, and a mandatory re-lock -- the "Finance completes readiness,
-- previews affected actions, obtains approval and locks a scope" flow
-- Prompt 207 section 21 names.
--
-- One authoritative guard (Prompt 207 section 14/24: "every posting
-- service calls one authoritative guard... never UI-only"):
-- `app.assert_finance_period_open_for_posting`. Every GL-affecting posting
-- path in this repository funnels through exactly two chokepoints --
-- FIN-203's own `app.post_finance_journal` (manual) and
-- `app.create_and_post_finance_system_journal` (system: subledger and
-- FIN-206 correction) -- both `CREATE OR REPLACE`d here to call the guard
-- immediately after resolving the posting period, before any row is
-- written. `app.post_finance_subledger_batch` (FIN-202) is additionally
-- `CREATE OR REPLACE`d to derive the real `ar`/`ap` scope from its own
-- already-known `source_type` and thread it through to
-- `create_and_post_finance_system_journal`'s own `p_lock_scope` parameter
-- (added at FIN-206, previously always defaulted to `gl`) -- so an
-- invoice/receipt posting is checked against an `ar` lock, a vendor-bill/
-- settlement posting against an `ap` lock, and every path is additionally
-- checked against a tenant-wide `all` lock.
--
-- A `reopen` is minimum-scope, approved, reasoned, audited, and
-- time-boxed (Prompt 207 section 24): `app.request_finance_period_reopen`
-- (FIN:Edit, locked -> reopen_requested) then
-- `app.approve_finance_period_reopen` (FIN:Approve, reopen_requested ->
-- reopened, sets `reopen_window_expires_at`). The guard itself treats an
-- expired window as still-locked even before an explicit
-- `app.relock_finance_period` call updates the stored status -- a reopen
-- is never silently permanent.
--
-- RPD-022 disclosure (Prompt 207 section 24): a live Supreme Admin
-- absolute-CRUD exception exists elsewhere in this repository (FIN-204)
-- and is not touched or re-implemented here; this checkpoint makes no
-- claim that a lock is an absolute prevention against that already-
-- disclosed exception.
--
-- Per `ERR-2026-004` (`docs/runtime/ERROR_LEDGER.md`): this migration
-- carries its own explicit `REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA app
-- FROM PUBLIC` statement before its final grants, the standing
-- per-migration convention since `PLT-118`.

create table app.finance_period_locks (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  company_id uuid references app.org_units (id),
  period_id uuid not null references app.finance_fiscal_periods (id),
  lock_scope text not null,
  status text not null default 'locked',
  lock_reason text not null,
  evidence_ref text,
  locked_by text,
  locked_at timestamptz not null default now(),
  reopen_reason text,
  reopen_requested_by text,
  reopen_requested_at timestamptz,
  reopen_approved_by text,
  reopen_window_expires_at timestamptz,
  reopened_at timestamptz,
  relocked_by text,
  relocked_at timestamptz,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint finance_period_locks_scope_check check (lock_scope in ('all', 'gl', 'ar', 'ap', 'tax')),
  constraint finance_period_locks_status_check check (status in ('locked', 'reopen_requested', 'reopened'))
);

comment on table app.finance_period_locks is
  'FIN-207: one governed lock per (tenant, company, period, lock_scope). status locked/reopen_requested/reopened; app.assert_finance_period_open_for_posting treats an expired reopen_window_expires_at as still-locked even before an explicit re-lock call. lock_scope=all matches every posting scope; a narrower scope (gl/ar/ap/tax) matches only its own.';

create unique index finance_period_locks_scope_unique on app.finance_period_locks (
  tenant_id, coalesce(company_id, '00000000-0000-0000-0000-000000000000'::uuid), period_id, lock_scope
);
create index finance_period_locks_tenant_period_idx on app.finance_period_locks (tenant_id, period_id);

create function app.touch_finance_period_lock_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger finance_period_locks_touch_row
  before update on app.finance_period_locks
  for each row
  execute function app.touch_finance_period_lock_row();

create table app.finance_period_lock_events (
  id uuid primary key default gen_random_uuid(),
  lock_id uuid not null references app.finance_period_locks (id),
  tenant_id uuid not null references app.tenants (id),
  action text not null,
  reason text,
  actor_label text,
  created_at timestamptz not null default now(),
  constraint finance_period_lock_events_action_check check (action in ('locked', 'reopen_requested', 'reopened', 'relocked'))
);

comment on table app.finance_period_lock_events is
  'FIN-207: append-only close/reopen/re-lock history per lock row, independent of app.audit_logs, for the close console''s own approval timeline.';

create index finance_period_lock_events_lock_idx on app.finance_period_lock_events (lock_id, created_at);

create function app.check_finance_period_lock_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid)
returns boolean
language sql
stable
as $$
  select (app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'FIN', p_action)).allowed;
$$;

comment on function app.check_finance_period_lock_authority is
  'FIN-207: FIN:Approve gates lock/approve-reopen/relock (Prompt 207 section 26: "Finance Manager prepares; independent close/reopen approver authorizes"); FIN:Edit gates a reopen request; FIN:View gates read.';

-- The one authoritative guard (Prompt 207 section 14/24). Raises a
-- distinct named exception; never silently permits or silently blocks.
create function app.assert_finance_period_open_for_posting(
  p_tenant_id uuid,
  p_company_id uuid,
  p_period_id uuid,
  p_lock_scope text
)
returns void
language plpgsql
stable
as $$
declare
  v_lock app.finance_period_locks;
begin
  for v_lock in
    select * from app.finance_period_locks
    where tenant_id = p_tenant_id
      and period_id = p_period_id
      and (company_id is null or company_id = p_company_id)
      and lock_scope in ('all', p_lock_scope)
  loop
    if v_lock.status = 'locked' or (v_lock.status = 'reopen_requested') then
      raise exception 'finance_period_locked: period % is locked for scope % (lock %)', p_period_id, v_lock.lock_scope, v_lock.id
        using errcode = 'check_violation';
    end if;
    if v_lock.status = 'reopened' and (v_lock.reopen_window_expires_at is null or now() > v_lock.reopen_window_expires_at) then
      raise exception 'finance_period_locked: period % reopen window for scope % has expired (lock %)', p_period_id, v_lock.lock_scope, v_lock.id
        using errcode = 'check_violation';
    end if;
  end loop;
end;
$$;

-- Lock a scope (Prompt 207 section 21). Idempotent when already locked;
-- re-locks a reopened/reopen_requested row in place rather than erroring,
-- since "lock" is also this checkpoint's own explicit relock verb when no
-- separate app.relock_finance_period call has happened yet.
create function app.lock_finance_period(
  p_tenant_id uuid,
  p_company_id uuid,
  p_period_id uuid,
  p_lock_scope text,
  p_reason text,
  p_evidence_ref text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.finance_period_locks
language plpgsql
as $$
declare
  v_lock app.finance_period_locks;
  v_period app.finance_fiscal_periods;
begin
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % holds no active membership for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.check_finance_period_lock_authority('Approve', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'finance_period_lock_reason_required: a non-empty reason is required' using errcode = 'check_violation';
  end if;
  if p_lock_scope not in ('all', 'gl', 'ar', 'ap', 'tax') then
    raise exception 'finance_period_lock_invalid_scope: % is not a supported lock scope', p_lock_scope using errcode = 'check_violation';
  end if;

  select * into v_period from app.finance_fiscal_periods where id = p_period_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'finance_period_not_found: % is not a known fiscal period for tenant %', p_period_id, p_tenant_id
      using errcode = 'no_data_found';
  end if;

  select * into v_lock from app.finance_period_locks
    where tenant_id = p_tenant_id and period_id = p_period_id and lock_scope = p_lock_scope
      and coalesce(company_id, '00000000-0000-0000-0000-000000000000'::uuid) = coalesce(p_company_id, '00000000-0000-0000-0000-000000000000'::uuid);

  if found and v_lock.status = 'locked' then
    return v_lock;
  end if;

  if found then
    update app.finance_period_locks
      set status = 'locked', lock_reason = p_reason, evidence_ref = p_evidence_ref, locked_by = p_actor_label, locked_at = now(),
          relocked_by = p_actor_label, relocked_at = now()
      where id = v_lock.id
      returning * into v_lock;
  else
    insert into app.finance_period_locks (tenant_id, company_id, period_id, lock_scope, lock_reason, evidence_ref, locked_by, created_by)
    values (p_tenant_id, p_company_id, p_period_id, p_lock_scope, p_reason, p_evidence_ref, p_actor_label, p_actor_label)
    returning * into v_lock;
  end if;

  insert into app.finance_period_lock_events (lock_id, tenant_id, action, reason, actor_label) values (v_lock.id, p_tenant_id, 'locked', p_reason, p_actor_label);

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'lock_finance_period',
    'app.finance_period_locks', v_lock.id, 'success', p_reason, null, to_jsonb(v_lock)
  );

  return v_lock;
end;
$$;

create function app.request_finance_period_reopen(
  p_lock_id uuid,
  p_expected_version integer,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.finance_period_locks
language plpgsql
as $$
declare
  v_lock app.finance_period_locks;
begin
  select * into v_lock from app.finance_period_locks where id = p_lock_id;
  if not found then
    raise exception 'finance_period_lock_not_found: %', p_lock_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_period_lock_authority('Edit', v_lock.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, v_lock.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_lock.record_version <> p_expected_version then
    raise exception 'stale_version: lock % expected version % but found %', p_lock_id, p_expected_version, v_lock.record_version
      using errcode = 'serialization_failure';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'finance_period_lock_reason_required: a non-empty reason is required' using errcode = 'check_violation';
  end if;
  if v_lock.status <> 'locked' then
    raise exception 'finance_period_lock_not_locked: lock % is % not locked', p_lock_id, v_lock.status
      using errcode = 'check_violation';
  end if;

  update app.finance_period_locks
    set status = 'reopen_requested', reopen_reason = p_reason, reopen_requested_by = p_actor_label, reopen_requested_at = now()
    where id = p_lock_id
    returning * into v_lock;

  insert into app.finance_period_lock_events (lock_id, tenant_id, action, reason, actor_label) values (v_lock.id, v_lock.tenant_id, 'reopen_requested', p_reason, p_actor_label);

  perform app.capture_audit_event(
    v_lock.tenant_id, p_actor_auth_user_id, p_actor_label, 'request_finance_period_reopen',
    'app.finance_period_locks', v_lock.id, 'success', p_reason, null, to_jsonb(v_lock)
  );

  return v_lock;
end;
$$;

-- Governed approval (Prompt 207 section 24/26: "independent close/reopen
-- approver authorizes"). p_window_hours bounds how long the reopen stays
-- effective before the guard itself treats it as expired.
create function app.approve_finance_period_reopen(
  p_lock_id uuid,
  p_expected_version integer,
  p_window_hours integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.finance_period_locks
language plpgsql
as $$
declare
  v_lock app.finance_period_locks;
begin
  select * into v_lock from app.finance_period_locks where id = p_lock_id;
  if not found then
    raise exception 'finance_period_lock_not_found: %', p_lock_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_period_lock_authority('Approve', v_lock.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_lock.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_lock.record_version <> p_expected_version then
    raise exception 'stale_version: lock % expected version % but found %', p_lock_id, p_expected_version, v_lock.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_lock.status <> 'reopen_requested' then
    raise exception 'finance_period_lock_not_reopen_requested: lock % is % not reopen_requested', p_lock_id, v_lock.status
      using errcode = 'check_violation';
  end if;
  if p_window_hours is null or p_window_hours <= 0 or p_window_hours > 720 then
    raise exception 'finance_period_reopen_window_invalid: % is not a valid reopen window (1-720 hours)', p_window_hours
      using errcode = 'check_violation';
  end if;

  update app.finance_period_locks
    set status = 'reopened', reopen_approved_by = p_actor_label, reopened_at = now(), reopen_window_expires_at = now() + make_interval(hours => p_window_hours)
    where id = p_lock_id
    returning * into v_lock;

  insert into app.finance_period_lock_events (lock_id, tenant_id, action, reason, actor_label) values (v_lock.id, v_lock.tenant_id, 'reopened', v_lock.reopen_reason, p_actor_label);

  perform app.capture_audit_event(
    v_lock.tenant_id, p_actor_auth_user_id, p_actor_label, 'approve_finance_period_reopen',
    'app.finance_period_locks', v_lock.id, 'success', null, null, to_jsonb(v_lock)
  );

  return v_lock;
end;
$$;

-- Mandatory re-lock (Prompt 207 section 21: "it re-locks with
-- reconciliation"). Idempotent -- re-locking an already-locked row (e.g.
-- the guard's own expired-window inference) returns it unchanged.
create function app.relock_finance_period(
  p_lock_id uuid,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.finance_period_locks
language plpgsql
as $$
declare
  v_lock app.finance_period_locks;
begin
  select * into v_lock from app.finance_period_locks where id = p_lock_id;
  if not found then
    raise exception 'finance_period_lock_not_found: %', p_lock_id using errcode = 'no_data_found';
  end if;
  if v_lock.status = 'locked' then
    return v_lock;
  end if;
  if not app.check_finance_period_lock_authority('Approve', v_lock.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_lock.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_lock.record_version <> p_expected_version then
    raise exception 'stale_version: lock % expected version % but found %', p_lock_id, p_expected_version, v_lock.record_version
      using errcode = 'serialization_failure';
  end if;

  update app.finance_period_locks
    set status = 'locked', relocked_by = p_actor_label, relocked_at = now()
    where id = p_lock_id
    returning * into v_lock;

  insert into app.finance_period_lock_events (lock_id, tenant_id, action, reason, actor_label) values (v_lock.id, v_lock.tenant_id, 'relocked', null, p_actor_label);

  perform app.capture_audit_event(
    v_lock.tenant_id, p_actor_auth_user_id, p_actor_label, 'relock_finance_period',
    'app.finance_period_locks', v_lock.id, 'success', null, null, to_jsonb(v_lock)
  );

  return v_lock;
end;
$$;

create function app.list_finance_period_locks(p_tenant_id uuid, p_company_id uuid, p_period_id uuid, p_actor_auth_user_id uuid)
returns setof app.finance_period_locks
language plpgsql
stable
as $$
begin
  if not app.check_finance_period_lock_authority('View', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  return query select * from app.finance_period_locks
    where tenant_id = p_tenant_id
      and (p_company_id is null or company_id = p_company_id)
      and (p_period_id is null or period_id = p_period_id)
    order by created_at desc
    limit 200;
end;
$$;

create function app.get_finance_period_lock_events(p_lock_id uuid, p_actor_auth_user_id uuid)
returns setof app.finance_period_lock_events
language plpgsql
stable
as $$
declare
  v_lock app.finance_period_locks;
begin
  select * into v_lock from app.finance_period_locks where id = p_lock_id;
  if not found then
    raise exception 'finance_period_lock_not_found: %', p_lock_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_period_lock_authority('View', v_lock.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, v_lock.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  return query select * from app.finance_period_lock_events where lock_id = p_lock_id order by created_at asc;
end;
$$;

-- FIN-207 retrofit: manual journal posting now checks the one
-- authoritative guard against lock_scope='gl' immediately after resolving
-- the posting period. Every other line of this function's own body is
-- byte-for-byte unchanged from FIN-203's original.
create or replace function app.post_finance_journal(
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
  perform app.assert_finance_period_open_for_posting(v_journal.tenant_id, v_journal.company_id, v_period.period_id, 'gl');

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

-- FIN-207 retrofit: the system-journal posting entry point now checks the
-- one authoritative guard against its own p_lock_scope (added at FIN-206,
-- defaulted 'gl') immediately after resolving the posting period. Every
-- other line of this function's own body is byte-for-byte unchanged from
-- FIN-206's own extension.
create or replace function app.create_and_post_finance_system_journal(
  p_tenant_id uuid,
  p_company_id uuid,
  p_source_type text,
  p_source_id uuid,
  p_journal_date date,
  p_currency text,
  p_lines jsonb,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  p_lock_scope text default 'gl'
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
    insert into app.finance_journal_lines (journal_id, tenant_id, line_number, account_id, dimension, direction, amount)
    values (v_journal.id, p_tenant_id, v_line_number, (v_line ->> 'accountId')::uuid, v_line -> 'dimension', v_line ->> 'direction', (v_line ->> 'amount')::numeric);
  end loop;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_and_post_finance_system_journal',
    'app.finance_journals', v_journal.id, 'success', null, null, to_jsonb(v_journal)
  );

  return v_journal;
end;
$$;

-- FIN-207 retrofit: derives the real ar/ap lock scope from this
-- function's own already-known p_source_type and threads it through to
-- app.create_and_post_finance_system_journal's own p_lock_scope parameter,
-- so an invoice/receipt posting is checked against an `ar` lock and a
-- vendor-bill/settlement posting against an `ap` lock (both also always
-- checked against a tenant-wide `all` lock by the guard itself). Every
-- other line of this function's own body is byte-for-byte unchanged from
-- FIN-203's own extension.
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
  v_lock_scope text;
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

  v_lock_scope := case when p_source_type in ('invoice', 'receipt_allocation') then 'ar' when p_source_type in ('vendor_bill', 'settlement') then 'ap' else 'gl' end;
  perform app.assert_finance_period_open_for_posting(p_tenant_id, p_company_id, v_period.period_id, v_lock_scope);

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

  select * into v_journal from app.create_and_post_finance_system_journal(
    p_tenant_id, p_company_id, 'subledger', v_batch.id, p_posting_date, p_currency, v_journal_lines, p_actor_auth_user_id, p_actor_label, v_lock_scope
  );
  update app.finance_subledger_batches set gl_journal_id = v_journal.id where id = v_batch.id returning * into v_batch;

  return v_batch;
end;
$$;

alter table app.finance_period_locks enable row level security;
alter table app.finance_period_lock_events enable row level security;

create policy finance_period_locks_select_scoped on app.finance_period_locks
  for select to authenticated
  using (app.has_active_tenant_membership(tenant_id) or app.is_supreme_admin());

create policy finance_period_lock_events_select_scoped on app.finance_period_lock_events
  for select to authenticated
  using (app.has_active_tenant_membership(tenant_id) or app.is_supreme_admin());

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit, directly-provable
-- revoke of PostgreSQL's PUBLIC-execute default, the standing per-migration
-- convention since PLT-118, applied here before any role-specific grant.
revoke execute on all functions in schema app from public;

grant select on app.finance_period_locks to authenticated, service_role;
grant select on app.finance_period_lock_events to authenticated, service_role;
grant insert, update, delete on app.finance_period_locks to service_role;
grant insert, update, delete on app.finance_period_lock_events to service_role;

grant execute on function app.touch_finance_period_lock_row() to service_role;
grant execute on function app.check_finance_period_lock_authority(text, uuid, uuid) to service_role;
grant execute on function app.assert_finance_period_open_for_posting(uuid, uuid, uuid, text) to service_role;
grant execute on function app.lock_finance_period(uuid, uuid, uuid, text, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.request_finance_period_reopen(uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.approve_finance_period_reopen(uuid, integer, integer, uuid, text) to authenticated, service_role;
grant execute on function app.relock_finance_period(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.list_finance_period_locks(uuid, uuid, uuid, uuid) to authenticated, service_role;
grant execute on function app.get_finance_period_lock_events(uuid, uuid) to authenticated, service_role;
grant execute on function app.post_finance_journal(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.create_and_post_finance_system_journal(uuid, uuid, text, uuid, date, text, jsonb, uuid, text, text) to authenticated, service_role;
grant execute on function app.post_finance_subledger_batch(uuid, uuid, text, uuid, date, text, jsonb, uuid, text) to authenticated, service_role;
