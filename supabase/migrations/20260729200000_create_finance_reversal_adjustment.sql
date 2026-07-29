-- Finance capability FIN-206 (Reversal and Adjustment, CG-S9-FIN-017)
-- Governed correction of a posted journal (FIN-203) through a new linked
-- record, never a rewrite of normal-role history -- closes FIN-203's own
-- disclosed "reverse posted journal via FIN-206" forward reference and
-- FIN-202's own disclosed `finance_subledger_batches.status = 'reversed'`
-- forward reference.
--
-- Two correction types, one shared lifecycle (draft -> submitted ->
-- approved -> posted, or discarded from draft/submitted):
--  * `reversal` -- the system derives the exact opposite lines of the
--    original posted journal (every debit becomes a credit and vice
--    versa, same account/amount/dimension); at most one non-discarded
--    reversal per original journal (Prompt 206 section 24: "One full
--    reversal per eligible effect").
--  * `adjustment` -- the preparer supplies a new balanced set of lines
--    (validated by FIN-203's own `app.validate_finance_journal_line_balance`,
--    the identical shared balance rule, never a second competing check);
--    multiple adjustments against one original are allowed.
--
-- Posting a correction calls FIN-203's own
-- `app.create_and_post_finance_system_journal` with `source_type =
-- 'correction'` (this migration extends that function's own allowed
-- source-type check via `CREATE OR REPLACE FUNCTION`, the established
-- later-migration-extends-an-earlier-one's-function pattern FIN-203 itself
-- used against FIN-202) -- one more posted journal, never a mutation of
-- the original row. FIN-204's own posted-journal-integrity triggers
-- already make the original row's own UPDATE/DELETE impossible for a
-- normal role; this migration does not need to (and does not) touch it.
--
-- If the original journal is subledger-sourced, a reversal additionally
-- marks that source `app.finance_subledger_batches` row `status =
-- 'reversed'` (a value FIN-202's own migration comment reserved exactly
-- for this checkpoint) -- disclosed bound: this does **not** retroactively
-- touch the AR/AP open item's own balance, which remains FIN-196/199's
-- own separately-governed `app.reverse_finance_ar_allocation`/
-- `app.reverse_finance_ap_settlement` path.
--
-- Per `ERR-2026-004` (`docs/runtime/ERROR_LEDGER.md`): this migration
-- carries its own explicit `REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA app
-- FROM PUBLIC` statement before its final grants, the standing
-- per-migration convention since `PLT-118`.

create table app.finance_journal_corrections (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  company_id uuid references app.org_units (id),
  original_journal_id uuid not null references app.finance_journals (id),
  correction_type text not null,
  correction_date date not null,
  reason text not null,
  evidence_ref text,
  adjustment_lines jsonb,
  status text not null default 'draft',
  idempotency_key text not null,
  correction_journal_id uuid references app.finance_journals (id),
  submitted_by text,
  submitted_at timestamptz,
  approved_by text,
  approved_at timestamptz,
  posted_by text,
  posted_at timestamptz,
  discard_reason text,
  discarded_by text,
  discarded_at timestamptz,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint finance_journal_corrections_type_check check (correction_type in ('reversal', 'adjustment')),
  constraint finance_journal_corrections_status_check check (status in ('draft', 'submitted', 'approved', 'posted', 'discarded')),
  constraint finance_journal_corrections_idempotency_unique unique (tenant_id, idempotency_key),
  constraint finance_journal_corrections_adjustment_lines_check check (
    (correction_type = 'adjustment' and adjustment_lines is not null) or (correction_type = 'reversal' and adjustment_lines is null)
  )
);

comment on table app.finance_journal_corrections is
  'FIN-206: one governed correction request against exactly one posted app.finance_journals row. reversal derives its own lines automatically at post time (the original journal''s own lines with direction flipped); adjustment carries an explicit, already-validated-balanced adjustment_lines jsonb captured at prepare time. correction_journal_id is null until posted, then points at the one new posted journal this correction created.';

-- One full reversal per eligible effect (Prompt 206 section 24): a
-- non-discarded reversal already in flight or posted against the same
-- original journal blocks a second one.
create unique index finance_journal_corrections_one_active_reversal on app.finance_journal_corrections (tenant_id, original_journal_id)
  where correction_type = 'reversal' and status <> 'discarded';

create index finance_journal_corrections_tenant_status_idx on app.finance_journal_corrections (tenant_id, status);
create index finance_journal_corrections_original_idx on app.finance_journal_corrections (original_journal_id);

create function app.touch_finance_journal_correction_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger finance_journal_corrections_touch_row
  before update on app.finance_journal_corrections
  for each row
  execute function app.touch_finance_journal_correction_row();

create function app.check_finance_correction_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid)
returns boolean
language sql
stable
as $$
  select (app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'FIN', p_action)).allowed;
$$;

comment on function app.check_finance_correction_authority is
  'FIN-206: FIN:Edit gates prepare (reversal/adjustment)/submit/discard; FIN:Approve gates approve/post; FIN:View gates read/chain.';

-- Reversal preparation (Prompt 206 section 21/24). Original must be
-- posted; blocks a duplicate active reversal via the partial unique index
-- above (surfaced here as a named exception, not a bare constraint error).
create function app.prepare_finance_journal_reversal(
  p_tenant_id uuid,
  p_company_id uuid,
  p_original_journal_id uuid,
  p_correction_date date,
  p_reason text,
  p_evidence_ref text,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.finance_journal_corrections
language plpgsql
as $$
declare
  v_correction app.finance_journal_corrections;
  v_original app.finance_journals;
begin
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % holds no active membership for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.check_finance_correction_authority('Edit', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'idempotency_key_required: a non-empty idempotency_key is required' using errcode = 'check_violation';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'finance_correction_reason_required: a non-empty reason is required' using errcode = 'check_violation';
  end if;

  select * into v_correction from app.finance_journal_corrections where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
  if found then
    return v_correction;
  end if;

  select * into v_original from app.finance_journals where id = p_original_journal_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'finance_journal_not_found: % is not a known journal for tenant %', p_original_journal_id, p_tenant_id
      using errcode = 'no_data_found';
  end if;
  if v_original.status <> 'posted' then
    raise exception 'finance_correction_original_not_posted: journal % is % not posted', p_original_journal_id, v_original.status
      using errcode = 'check_violation';
  end if;
  if exists (
    select 1 from app.finance_journal_corrections
    where tenant_id = p_tenant_id and original_journal_id = p_original_journal_id
      and correction_type = 'reversal' and status <> 'discarded'
  ) then
    raise exception 'finance_correction_duplicate_reversal: journal % already has an active reversal request', p_original_journal_id
      using errcode = 'check_violation';
  end if;

  insert into app.finance_journal_corrections (
    tenant_id, company_id, original_journal_id, correction_type, correction_date, reason, evidence_ref, idempotency_key, created_by
  )
  values (p_tenant_id, p_company_id, p_original_journal_id, 'reversal', p_correction_date, p_reason, p_evidence_ref, p_idempotency_key, p_actor_label)
  returning * into v_correction;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'prepare_finance_journal_reversal',
    'app.finance_journal_corrections', v_correction.id, 'success', p_reason, null, to_jsonb(v_correction)
  );

  return v_correction;
end;
$$;

-- Adjustment preparation (Prompt 206 section 22). adjustment_lines is
-- validated balanced up front via FIN-203's own shared balance rule --
-- never a second, competing check.
create function app.prepare_finance_journal_adjustment(
  p_tenant_id uuid,
  p_company_id uuid,
  p_original_journal_id uuid,
  p_correction_date date,
  p_reason text,
  p_evidence_ref text,
  p_adjustment_lines jsonb,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.finance_journal_corrections
language plpgsql
as $$
declare
  v_correction app.finance_journal_corrections;
  v_original app.finance_journals;
  v_line jsonb;
  v_account app.finance_accounts;
begin
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % holds no active membership for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.check_finance_correction_authority('Edit', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'idempotency_key_required: a non-empty idempotency_key is required' using errcode = 'check_violation';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'finance_correction_reason_required: a non-empty reason is required' using errcode = 'check_violation';
  end if;

  select * into v_correction from app.finance_journal_corrections where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
  if found then
    return v_correction;
  end if;

  select * into v_original from app.finance_journals where id = p_original_journal_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'finance_journal_not_found: % is not a known journal for tenant %', p_original_journal_id, p_tenant_id
      using errcode = 'no_data_found';
  end if;
  if v_original.status <> 'posted' then
    raise exception 'finance_correction_original_not_posted: journal % is % not posted', p_original_journal_id, v_original.status
      using errcode = 'check_violation';
  end if;

  perform app.validate_finance_journal_line_balance(p_adjustment_lines);

  for v_line in select * from jsonb_array_elements(p_adjustment_lines) loop
    select * into v_account from app.finance_accounts where id = (v_line ->> 'accountId')::uuid and tenant_id = p_tenant_id;
    if not found then
      raise exception 'finance_journal_account_not_found: % is not a known account for tenant %', v_line ->> 'accountId', p_tenant_id
        using errcode = 'no_data_found';
    end if;
    if v_account.status <> 'active' or not v_account.is_postable then
      raise exception 'finance_journal_not_postable_account: account % is not active/postable', v_account.code
        using errcode = 'check_violation';
    end if;
  end loop;

  insert into app.finance_journal_corrections (
    tenant_id, company_id, original_journal_id, correction_type, correction_date, reason, evidence_ref, adjustment_lines, idempotency_key, created_by
  )
  values (p_tenant_id, p_company_id, p_original_journal_id, 'adjustment', p_correction_date, p_reason, p_evidence_ref, p_adjustment_lines, p_idempotency_key, p_actor_label)
  returning * into v_correction;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'prepare_finance_journal_adjustment',
    'app.finance_journal_corrections', v_correction.id, 'success', p_reason, null, to_jsonb(v_correction)
  );

  return v_correction;
end;
$$;

create function app.submit_finance_correction_for_approval(
  p_correction_id uuid,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.finance_journal_corrections
language plpgsql
as $$
declare
  v_correction app.finance_journal_corrections;
begin
  select * into v_correction from app.finance_journal_corrections where id = p_correction_id;
  if not found then
    raise exception 'finance_correction_not_found: %', p_correction_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_correction_authority('Edit', v_correction.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, v_correction.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_correction.record_version <> p_expected_version then
    raise exception 'stale_version: correction % expected version % but found %', p_correction_id, p_expected_version, v_correction.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_correction.status <> 'draft' then
    raise exception 'finance_correction_not_draft: correction % is % not draft', p_correction_id, v_correction.status
      using errcode = 'check_violation';
  end if;

  update app.finance_journal_corrections set status = 'submitted', submitted_by = p_actor_label, submitted_at = now() where id = p_correction_id returning * into v_correction;

  perform app.capture_audit_event(
    v_correction.tenant_id, p_actor_auth_user_id, p_actor_label, 'submit_finance_correction_for_approval',
    'app.finance_journal_corrections', v_correction.id, 'success', null, null, to_jsonb(v_correction)
  );

  return v_correction;
end;
$$;

create function app.discard_finance_correction_draft(
  p_correction_id uuid,
  p_expected_version integer,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.finance_journal_corrections
language plpgsql
as $$
declare
  v_correction app.finance_journal_corrections;
begin
  select * into v_correction from app.finance_journal_corrections where id = p_correction_id;
  if not found then
    raise exception 'finance_correction_not_found: %', p_correction_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_correction_authority('Edit', v_correction.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, v_correction.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_correction.record_version <> p_expected_version then
    raise exception 'stale_version: correction % expected version % but found %', p_correction_id, p_expected_version, v_correction.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_correction.status not in ('draft', 'submitted') then
    raise exception 'finance_correction_not_cancellable: correction % is %, only a draft or submitted correction may be discarded', p_correction_id, v_correction.status
      using errcode = 'check_violation';
  end if;

  update app.finance_journal_corrections
    set status = 'discarded', discard_reason = p_reason, discarded_by = p_actor_label, discarded_at = now()
    where id = p_correction_id
    returning * into v_correction;

  perform app.capture_audit_event(
    v_correction.tenant_id, p_actor_auth_user_id, p_actor_label, 'discard_finance_correction_draft',
    'app.finance_journal_corrections', v_correction.id, 'success', p_reason, null, to_jsonb(v_correction)
  );

  return v_correction;
end;
$$;

create function app.approve_finance_correction(
  p_correction_id uuid,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.finance_journal_corrections
language plpgsql
as $$
declare
  v_correction app.finance_journal_corrections;
begin
  select * into v_correction from app.finance_journal_corrections where id = p_correction_id;
  if not found then
    raise exception 'finance_correction_not_found: %', p_correction_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_correction_authority('Approve', v_correction.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_correction.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_correction.record_version <> p_expected_version then
    raise exception 'stale_version: correction % expected version % but found %', p_correction_id, p_expected_version, v_correction.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_correction.status <> 'submitted' then
    raise exception 'finance_correction_not_submitted: correction % is % not submitted', p_correction_id, v_correction.status
      using errcode = 'check_violation';
  end if;

  update app.finance_journal_corrections set status = 'approved', approved_by = p_actor_label, approved_at = now() where id = p_correction_id returning * into v_correction;

  perform app.capture_audit_event(
    v_correction.tenant_id, p_actor_auth_user_id, p_actor_label, 'approve_finance_correction',
    'app.finance_journal_corrections', v_correction.id, 'success', null, null, to_jsonb(v_correction)
  );

  return v_correction;
end;
$$;

-- Posting (Prompt 206 section 21/32). Idempotent -- a retried call against
-- an already-posted correction returns it unchanged. Builds the reversal's
-- own lines by flipping the original journal's stored lines (never
-- editing them); an adjustment posts its own already-validated
-- adjustment_lines. If the original period is locked and correction_date
-- falls in a different, currently open period, the correction posts there
-- instead (Prompt 206 section 22: "schedule correction into the current
-- open period when original is locked") -- exactly the same period
-- resolution FIN-203's own posting functions already perform for
-- p_journal_date.
create function app.post_finance_correction(
  p_correction_id uuid,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.finance_journal_corrections
language plpgsql
as $$
declare
  v_correction app.finance_journal_corrections;
  v_original app.finance_journals;
  v_lines jsonb := '[]'::jsonb;
  v_line record;
  v_flipped text;
  v_journal app.finance_journals;
  v_batch app.finance_subledger_batches;
begin
  select * into v_correction from app.finance_journal_corrections where id = p_correction_id;
  if not found then
    raise exception 'finance_correction_not_found: %', p_correction_id using errcode = 'no_data_found';
  end if;
  if v_correction.status = 'posted' then
    return v_correction;
  end if;
  if not app.check_finance_correction_authority('Approve', v_correction.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_correction.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_correction.record_version <> p_expected_version then
    raise exception 'stale_version: correction % expected version % but found %', p_correction_id, p_expected_version, v_correction.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_correction.status <> 'approved' then
    raise exception 'finance_correction_not_approved: correction % is % not approved', p_correction_id, v_correction.status
      using errcode = 'check_violation';
  end if;

  select * into v_original from app.finance_journals where id = v_correction.original_journal_id;
  if not found or v_original.status <> 'posted' then
    raise exception 'finance_correction_original_not_posted: journal % is no longer posted', v_correction.original_journal_id
      using errcode = 'check_violation';
  end if;

  if v_correction.correction_type = 'reversal' then
    for v_line in select direction, account_id, amount, dimension from app.finance_journal_lines where journal_id = v_original.id order by line_number asc loop
      v_flipped := case when v_line.direction = 'debit' then 'credit' else 'debit' end;
      v_lines := v_lines || jsonb_build_array(jsonb_build_object('accountId', v_line.account_id, 'direction', v_flipped, 'amount', v_line.amount, 'dimension', v_line.dimension));
    end loop;
  else
    v_lines := v_correction.adjustment_lines;
  end if;

  select * into v_journal from app.create_and_post_finance_system_journal(
    v_correction.tenant_id, v_correction.company_id, 'correction', v_correction.id, v_correction.correction_date,
    v_original.currency, v_lines, p_actor_auth_user_id, p_actor_label, 'gl'
  );

  if v_correction.correction_type = 'reversal' and v_original.source_type = 'subledger' then
    update app.finance_subledger_batches set status = 'reversed' where gl_journal_id = v_original.id and status = 'posted' returning * into v_batch;
  end if;

  update app.finance_journal_corrections
    set status = 'posted', correction_journal_id = v_journal.id, posted_by = p_actor_label, posted_at = now()
    where id = p_correction_id
    returning * into v_correction;

  perform app.capture_audit_event(
    v_correction.tenant_id, p_actor_auth_user_id, p_actor_label, 'post_finance_correction',
    'app.finance_journal_corrections', v_correction.id, 'success', null, null, to_jsonb(v_correction)
  );

  return v_correction;
end;
$$;

create function app.list_finance_journal_corrections(
  p_tenant_id uuid,
  p_company_id uuid,
  p_correction_type text,
  p_status text,
  p_actor_auth_user_id uuid
)
returns setof app.finance_journal_corrections
language plpgsql
stable
as $$
begin
  if not app.check_finance_correction_authority('View', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  return query select * from app.finance_journal_corrections
    where tenant_id = p_tenant_id
      and (p_company_id is null or company_id = p_company_id)
      and (p_correction_type is null or correction_type = p_correction_type)
      and (p_status is null or status = p_status)
    order by created_at desc
    limit 200;
end;
$$;

-- Read-chain (Prompt 206 section 21/35): original journal, the correction
-- request itself, and the posted correction journal (if any) in one call.
create function app.get_finance_correction_chain(p_correction_id uuid, p_actor_auth_user_id uuid)
returns jsonb
language plpgsql
stable
as $$
declare
  v_correction app.finance_journal_corrections;
  v_original app.finance_journals;
  v_correction_journal app.finance_journals;
begin
  select * into v_correction from app.finance_journal_corrections where id = p_correction_id;
  if not found then
    raise exception 'finance_correction_not_found: %', p_correction_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_correction_authority('View', v_correction.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, v_correction.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_original from app.finance_journals where id = v_correction.original_journal_id;
  if v_correction.correction_journal_id is not null then
    select * into v_correction_journal from app.finance_journals where id = v_correction.correction_journal_id;
  end if;

  return jsonb_build_object(
    'correction', to_jsonb(v_correction),
    'originalJournal', to_jsonb(v_original),
    'correctionJournal', case when v_correction.correction_journal_id is not null then to_jsonb(v_correction_journal) else null end
  );
end;
$$;

-- FIN-206 retrofit: FIN-203's own finance_journals_source_type_check and
-- finance_journals_source_check constraints only allowed source_type in
-- ('manual', 'subledger'); each replaced with an identical check that also
-- allows 'correction' (source_id not null, same as 'subledger'). An
-- additive constraint replacement, not an edit to any existing row.
alter table app.finance_journals drop constraint finance_journals_source_type_check;
alter table app.finance_journals add constraint finance_journals_source_type_check check (source_type in ('manual', 'subledger', 'correction'));
alter table app.finance_journals drop constraint finance_journals_source_check;
alter table app.finance_journals add constraint finance_journals_source_check check (
  (source_type = 'manual' and source_id is null) or (source_type in ('subledger', 'correction') and source_id is not null)
);

-- FIN-206 retrofit: extends FIN-203's own allowed system-journal source
-- types with 'correction', and adds an explicit p_lock_scope parameter
-- (appended with a default so every existing call site -- FIN-202's own
-- app.post_finance_subledger_batch -- keeps working unchanged). Every
-- other line of this function's own body is byte-for-byte unchanged from
-- FIN-203's original. A new trailing parameter changes this function's own
-- signature, so `CREATE OR REPLACE FUNCTION` alone would leave the old
-- 9-argument overload in place (ambiguous against a 9-argument call site,
-- since the new parameter carries a default) -- the old overload is
-- explicitly dropped first.
drop function if exists app.create_and_post_finance_system_journal(uuid, uuid, text, uuid, date, text, jsonb, uuid, text);

create function app.create_and_post_finance_system_journal(
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

alter table app.finance_journal_corrections enable row level security;

create policy finance_journal_corrections_select_scoped on app.finance_journal_corrections
  for select to authenticated
  using (app.has_active_tenant_membership(tenant_id) or app.is_supreme_admin());

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit, directly-provable
-- revoke of PostgreSQL's PUBLIC-execute default, the standing per-migration
-- convention since PLT-118, applied here before any role-specific grant.
revoke execute on all functions in schema app from public;

grant select on app.finance_journal_corrections to authenticated, service_role;
grant insert, update, delete on app.finance_journal_corrections to service_role;

grant execute on function app.touch_finance_journal_correction_row() to service_role;
grant execute on function app.check_finance_correction_authority(text, uuid, uuid) to service_role;
grant execute on function app.prepare_finance_journal_reversal(uuid, uuid, uuid, date, text, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.prepare_finance_journal_adjustment(uuid, uuid, uuid, date, text, text, jsonb, text, uuid, text) to authenticated, service_role;
grant execute on function app.submit_finance_correction_for_approval(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.discard_finance_correction_draft(uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.approve_finance_correction(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.post_finance_correction(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.list_finance_journal_corrections(uuid, uuid, text, text, uuid) to authenticated, service_role;
grant execute on function app.get_finance_correction_chain(uuid, uuid) to authenticated, service_role;
grant execute on function app.create_and_post_finance_system_journal(uuid, uuid, text, uuid, date, text, jsonb, uuid, text, text) to authenticated, service_role;
