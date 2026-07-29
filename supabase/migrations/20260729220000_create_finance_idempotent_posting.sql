-- Finance capability FIN-208 (Idempotent Posting, CG-S9-FIN-019)
-- One shared idempotent-posting protocol: a stable scoped key, a canonical
-- request fingerprint, and a claim/result record -- reused across every
-- retriable financial mutation, one real adopter wired this checkpoint.
--
-- Gap this checkpoint actually closes (Prompt 208 section 4/23/25):
-- FIN-197/198/200/201/203 each already shipped their own idempotent
-- creation ("select existing row by idempotency_key, return it unchanged
-- on retry") -- genuinely idempotent for a *byte-identical* retry, but
-- none of them detected a **different** payload arriving under the same
-- reused key; each one silently returned the *original* result instead of
-- rejecting the mismatch ("reject key reuse with a different fingerprint"
-- -- the one gap this checkpoint closes, not a rebuild of five already-
-- working idempotent-creation paths).
--
-- `app.finance_idempotency_claims` is the one shared claim ledger:
-- `app.claim_finance_idempotency_key` atomically inserts a new claim (or
-- returns the identical existing one when the fingerprint matches) and
-- raises `finance_idempotency_fingerprint_conflict` the instant a caller
-- reuses a key with a different fingerprint -- before any domain-specific
-- row is ever written. `app.complete_finance_idempotency_claim` links the
-- claim to the one real result it produced; `app.fail_finance_idempotency_claim`
-- records a distinct terminal outcome for a genuinely failed attempt
-- (Prompt 208 section 22: "resume a failed-before-effect attempt"),
-- disclosed but not wired to any caller this checkpoint.
--
-- One real adopter (Prompt 208 section 4's own "one idempotent posting
-- protocol... invoice, bill, receipt allocation, settlement, subledger,
-- journal, reversal and imports" is the target end-state, not this single
-- checkpoint's own bound): `app.create_finance_journal_draft` (FIN-203) is
-- `CREATE OR REPLACE`d to call the shared claim first, replacing its own
-- prior "select by idempotency_key" ad hoc check. The other five listed
-- domains keep their own existing idempotent-creation behavior unchanged
-- -- a disclosed forward-integration bound, not silently implied to be
-- done everywhere already.
--
-- Known, disclosed race (Prompt 208 section 23's own "simultaneous
-- conflicting claim"): two genuinely concurrent callers racing the exact
-- same brand-new key both observe a `claimed` (not yet `completed`) claim
-- and both proceed to attempt the domain insert; the loser fails on that
-- domain table's own pre-existing idempotency unique constraint (e.g.
-- `finance_journals_idempotency_unique`), not a newly-invented distinct
-- exception here -- a real, safe rejection (no double effect), just not
-- yet surfaced under its own named error code. Documented, not silently
-- claimed to be fully solved.
--
-- Per `ERR-2026-004` (`docs/runtime/ERROR_LEDGER.md`): this migration
-- carries its own explicit `REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA app
-- FROM PUBLIC` statement before its final grants, the standing
-- per-migration convention since `PLT-118`.

create table app.finance_idempotency_claims (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  scope text not null,
  idempotency_key text not null,
  request_fingerprint text not null,
  status text not null default 'claimed',
  result_entity_type text,
  result_entity_id uuid,
  error_message text,
  claimed_by text,
  claimed_at timestamptz not null default now(),
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  constraint finance_idempotency_claims_status_check check (status in ('claimed', 'completed', 'failed')),
  constraint finance_idempotency_claims_unique unique (tenant_id, scope, idempotency_key),
  constraint finance_idempotency_claims_result_check check (
    (status = 'completed' and result_entity_type is not null and result_entity_id is not null) or (status <> 'completed')
  )
);

comment on table app.finance_idempotency_claims is
  'FIN-208: one shared idempotency claim per (tenant, scope, idempotency_key). request_fingerprint is a caller-computed canonical digest of every business-significant input; a retried claim with a matching fingerprint returns the identical existing row, a mismatched fingerprint is a named conflict, never a silent overwrite or a silently accepted different result.';

create index finance_idempotency_claims_tenant_scope_idx on app.finance_idempotency_claims (tenant_id, scope, status);

create function app.check_finance_idempotency_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid)
returns boolean
language sql
stable
as $$
  select (app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'FIN', p_action)).allowed;
$$;

comment on function app.check_finance_idempotency_authority is
  'FIN-208: FIN:View gates a direct claim-status read; claim/complete/fail are internal building blocks called by an already-authority-checked domain function, so they only require an active tenant membership, not a separate FIN grant of their own.';

-- The one shared claim primitive (Prompt 208 section 21/25). Atomic:
-- `insert ... on conflict do nothing` either wins (a brand-new claim) or
-- loses (an existing claim already occupies this key), resolved with one
-- follow-up read -- never a read-then-write race window of its own.
create function app.claim_finance_idempotency_key(
  p_tenant_id uuid,
  p_scope text,
  p_idempotency_key text,
  p_request_fingerprint text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.finance_idempotency_claims
language plpgsql
as $$
declare
  v_claim app.finance_idempotency_claims;
begin
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % holds no active membership for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'idempotency_key_required: a non-empty idempotency_key is required' using errcode = 'check_violation';
  end if;
  if p_request_fingerprint is null or length(trim(p_request_fingerprint)) = 0 then
    raise exception 'finance_idempotency_fingerprint_required: a non-empty request_fingerprint is required' using errcode = 'check_violation';
  end if;

  insert into app.finance_idempotency_claims (tenant_id, scope, idempotency_key, request_fingerprint, claimed_by)
  values (p_tenant_id, p_scope, p_idempotency_key, p_request_fingerprint, p_actor_label)
  on conflict (tenant_id, scope, idempotency_key) do nothing
  returning * into v_claim;

  if found then
    return v_claim;
  end if;

  select * into v_claim from app.finance_idempotency_claims where tenant_id = p_tenant_id and scope = p_scope and idempotency_key = p_idempotency_key;

  if v_claim.request_fingerprint <> p_request_fingerprint then
    raise exception 'finance_idempotency_fingerprint_conflict: idempotency key % (scope %) was already used with a different request', p_idempotency_key, p_scope
      using errcode = 'unique_violation';
  end if;

  return v_claim;
end;
$$;

-- Idempotent -- completing an already-completed claim returns it
-- unchanged rather than erroring, so a caller need not special-case a
-- retried completion.
create function app.complete_finance_idempotency_claim(
  p_claim_id uuid,
  p_result_entity_type text,
  p_result_entity_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.finance_idempotency_claims
language plpgsql
as $$
declare
  v_claim app.finance_idempotency_claims;
begin
  select * into v_claim from app.finance_idempotency_claims where id = p_claim_id;
  if not found then
    raise exception 'finance_idempotency_claim_not_found: %', p_claim_id using errcode = 'no_data_found';
  end if;
  if not app.has_active_tenant_membership(v_claim.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % holds no active membership for tenant %', p_actor_auth_user_id, v_claim.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_claim.status = 'completed' then
    return v_claim;
  end if;

  update app.finance_idempotency_claims
    set status = 'completed', result_entity_type = p_result_entity_type, result_entity_id = p_result_entity_id, completed_at = now()
    where id = p_claim_id
    returning * into v_claim;

  return v_claim;
end;
$$;

-- Records a genuinely failed (not double-posted) attempt (Prompt 208
-- section 22: "resume a failed-before-effect attempt"). Disclosed
-- primitive, not yet called by any adopter this checkpoint -- every
-- domain function this checkpoint touches only ever reaches
-- app.complete_finance_idempotency_claim on its own success path; a raised
-- exception during that same transaction rolls the claim insert back too,
-- so no orphaned `claimed` row survives a synchronous failure today.
create function app.fail_finance_idempotency_claim(
  p_claim_id uuid,
  p_error_message text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.finance_idempotency_claims
language plpgsql
as $$
declare
  v_claim app.finance_idempotency_claims;
begin
  select * into v_claim from app.finance_idempotency_claims where id = p_claim_id;
  if not found then
    raise exception 'finance_idempotency_claim_not_found: %', p_claim_id using errcode = 'no_data_found';
  end if;
  if not app.has_active_tenant_membership(v_claim.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % holds no active membership for tenant %', p_actor_auth_user_id, v_claim.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_claim.status = 'completed' then
    raise exception 'finance_idempotency_claim_already_completed: claim % already completed, cannot mark failed', p_claim_id
      using errcode = 'check_violation';
  end if;

  update app.finance_idempotency_claims set status = 'failed', error_message = p_error_message where id = p_claim_id returning * into v_claim;

  return v_claim;
end;
$$;

create function app.get_finance_idempotency_claim(p_tenant_id uuid, p_scope text, p_idempotency_key text, p_actor_auth_user_id uuid)
returns app.finance_idempotency_claims
language plpgsql
stable
as $$
declare
  v_claim app.finance_idempotency_claims;
begin
  if not app.check_finance_idempotency_authority('View', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  select * into v_claim from app.finance_idempotency_claims where tenant_id = p_tenant_id and scope = p_scope and idempotency_key = p_idempotency_key;
  if not found then
    raise exception 'finance_idempotency_claim_not_found: no claim for scope % key %', p_scope, p_idempotency_key using errcode = 'no_data_found';
  end if;
  return v_claim;
end;
$$;

-- FIN-208 retrofit: app.create_finance_journal_draft (FIN-203) now claims
-- a shared idempotency key first -- computed from every business-
-- significant input (company/date/currency/lines) -- instead of its own
-- prior ad hoc "select existing by idempotency_key" check, so a retried
-- key with a *different* payload is rejected (finance_idempotency_
-- fingerprint_conflict) rather than silently returning the original
-- draft. Every other line of this function's own body is byte-for-byte
-- unchanged from FIN-203's original; the function's own signature is
-- unchanged.
create or replace function app.create_finance_journal_draft(
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
  v_fingerprint text;
  v_claim app.finance_idempotency_claims;
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

  v_fingerprint := md5(jsonb_build_object('companyId', p_company_id, 'journalDate', p_journal_date, 'currency', p_currency, 'lines', p_lines)::text);
  v_claim := app.claim_finance_idempotency_key(p_tenant_id, 'journal', p_idempotency_key, v_fingerprint, p_actor_auth_user_id, p_actor_label);

  if v_claim.status = 'completed' then
    select * into v_journal from app.finance_journals where id = v_claim.result_entity_id;
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

  perform app.complete_finance_idempotency_claim(v_claim.id, 'journal', v_journal.id, p_actor_auth_user_id, p_actor_label);

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_finance_journal_draft',
    'app.finance_journals', v_journal.id, 'success', null, null, to_jsonb(v_journal)
  );

  return v_journal;
end;
$$;

alter table app.finance_idempotency_claims enable row level security;

create policy finance_idempotency_claims_select_scoped on app.finance_idempotency_claims
  for select to authenticated
  using (app.has_active_tenant_membership(tenant_id) or app.is_supreme_admin());

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit, directly-provable
-- revoke of PostgreSQL's PUBLIC-execute default, the standing per-migration
-- convention since PLT-118, applied here before any role-specific grant.
revoke execute on all functions in schema app from public;

grant select on app.finance_idempotency_claims to authenticated, service_role;
grant insert, update, delete on app.finance_idempotency_claims to service_role;

grant execute on function app.check_finance_idempotency_authority(text, uuid, uuid) to service_role;
grant execute on function app.claim_finance_idempotency_key(uuid, text, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.complete_finance_idempotency_claim(uuid, text, uuid, uuid, text) to authenticated, service_role;
grant execute on function app.fail_finance_idempotency_claim(uuid, text, uuid, text) to authenticated, service_role;
grant execute on function app.get_finance_idempotency_claim(uuid, text, text, uuid) to authenticated, service_role;
grant execute on function app.create_finance_journal_draft(uuid, uuid, date, text, jsonb, text, uuid, text) to authenticated, service_role;
