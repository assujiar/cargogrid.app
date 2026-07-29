-- Finance capability FIN-195 (Tax Baseline, CG-S9-FIN-006)
-- An Indonesia-first, configurable tax baseline: a bounded catalogue of tax
-- codes (PPN/VAT, withholding article types, exempt) plus a versioned,
-- explicitly SME-approved tax rule lifecycle -- draft -> approved -> archived,
-- deterministic tenant-then-global resolution, and an exact-decimal
-- calculation service every later invoicing/billing capability reads rather
-- than reinventing.
--
-- RPD-016/021's own binding boundary (Prompt 195 section 24, 189_FINANCE_README.md
-- section 5): "no rate, filing rule or legal conclusion may be guessed by the
-- coding agent." This migration honours that boundary structurally, not just
-- by disclosure:
-- * `app.finance_tax_codes` seeds five *labels* only (PPN, PPH21, PPH23,
--   PPH4_2, EXEMPT) -- the same class of factual, non-opinionated identifier
--   `FIN-194`'s own currency-code seed (`IDR`/`USD`/`SGD`/`EUR`/`JPY`)
--   already established; a tax-code short name is a public statutory
--   classification, not a rate.
-- * Zero tax *rate* is ever seeded as `approved`. Exactly one illustrative
--   `app.finance_tax_rule_versions` row is seeded, `is_example_fixture = true`,
--   `status = 'draft'`, `rate_value = 0` -- a structurally inert placeholder,
--   never a real percentage, so this migration cannot be read as asserting any
--   specific Indonesian tax rate. `app.approve_finance_tax_rule` refuses to
--   activate any row with `is_example_fixture = true`
--   (`finance_tax_rule_example_fixture_not_activatable`) -- not merely
--   discouraged by convention, structurally blocked in the one function that
--   can ever move a rule to `approved`.
-- * `app.create_finance_tax_rule_draft` (the only INSERT path reachable from
--   the service layer/UI) has no parameter for `is_example_fixture` at all --
--   only this migration's own seed `insert` statement, run once at migration
--   time, can ever create an example-fixture row. A real SME-authored draft is
--   therefore always `is_example_fixture = false` and can be approved once
--   genuine evidence is attached.
--
-- Reuse decisions (disclosed, matching every prior FIN checkpoint's own
-- discipline):
-- * Lifecycle shape (`draft -> approved -> archived`) and the tenant-then-
--   global deterministic resolution order are `FIN-194`'s own
--   `app.finance_exchange_rates` pattern, reused directly rather than
--   inventing a second three-state machine -- a tax rule and an exchange-rate
--   quote are structurally the same shape (a versioned, effective-dated,
--   approval-gated numeric fact).
-- * Rounding tie-in: `app.calculate_finance_tax` resolves the tenant's own
--   effective `finance_rounding` config (`FIN-191`), key `tax_calculation`
--   falling back to `default` falling back to the same disclosed safe default
--   (`round_half_up` at 2 decimal places) `FIN-194`'s own
--   `app.convert_finance_amount` already established -- one rounding
--   authority, never a second competing mechanism.
-- * Account mapping references `app.finance_accounts` (`FIN-192`) directly --
--   an `output_account_id`/`recoverable_account_id` pair, validated
--   active+postable+same-tenant at both draft and approval time. Actual
--   double-entry GL posting is `FIN-202`/`FIN-203`'s own scope (not built
--   yet, per `189_FINANCE_README.md` section 4's dependency order); this
--   migration only captures the governed account-mapping *reference*, the
--   same disclosed forward-reference discipline `FIN-191`'s own
--   `finance_posting_map` class already established for the identical reason.
-- * `rate_basis` is a bounded enum (`percentage`, `fixed_amount`) only --
--   there is no `formula` basis to select in the first place, which is how
--   this migration satisfies Prompt 195 section 23's "keep activation blocked
--   for ... unsupported formula": an unsupported basis is rejected at
--   CHECK-constraint level, before a row can even exist, never merely
--   "blocked at activation."
--
-- Money/decimal discipline: `rate_value` is `numeric(12,6)` (never float);
-- `app.calculate_finance_tax` returns an exact-decimal `numeric` tax amount,
-- rounded once via `app.apply_finance_rounding` (FIN-194), never computed with
-- floating-point arithmetic.
--
-- Per `ERR-2026-004` (`docs/runtime/ERROR_LEDGER.md`): this migration carries
-- its own explicit `REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA app FROM
-- PUBLIC` statement before its final grants, the standing per-migration
-- convention since `PLT-118`.

create table app.finance_tax_codes (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references app.tenants (id),
  code text not null,
  name text not null,
  tax_type text not null,
  jurisdiction_country text not null default 'ID',
  is_recoverable boolean not null default false,
  is_active boolean not null default true,
  created_by text,
  created_at timestamptz not null default now(),
  constraint finance_tax_codes_tax_type_check check (tax_type in ('vat', 'withholding', 'exempt', 'other')),
  constraint finance_tax_codes_jurisdiction_check check (jurisdiction_country ~ '^[A-Z]{2}$'),
  constraint finance_tax_codes_code_check check (code ~ '^[A-Z0-9_]{2,20}$')
);

comment on table app.finance_tax_codes is
  'FIN-195: the bounded tax-code catalogue (labels/classifications only -- never a rate). tenant_id null = platform-wide catalog entry (mirrors FIN-194''s own finance_exchange_rates tenant-scope convention); non-null = a tenant-specific code for a niche jurisdiction/case an SME needs that the platform catalogue does not cover.';

create unique index finance_tax_codes_tenant_code_unique on app.finance_tax_codes (
  coalesce(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid), code
);
create index finance_tax_codes_tenant_id_idx on app.finance_tax_codes (tenant_id);

insert into app.finance_tax_codes (tenant_id, code, name, tax_type, jurisdiction_country, is_recoverable, is_active, created_by) values
  (null, 'PPN', 'Pajak Pertambahan Nilai (Value Added Tax)', 'vat', 'ID', true, true, 'finance-foundation'),
  (null, 'PPH21', 'Withholding Tax Article 21 (Employee Income)', 'withholding', 'ID', false, true, 'finance-foundation'),
  (null, 'PPH23', 'Withholding Tax Article 23 (Services/Royalties/Rent)', 'withholding', 'ID', false, true, 'finance-foundation'),
  (null, 'PPH4_2', 'Final Withholding Tax Article 4(2)', 'withholding', 'ID', false, true, 'finance-foundation'),
  (null, 'EXEMPT', 'Tax Exempt / Zero-Rated', 'exempt', 'ID', false, true, 'finance-foundation');

comment on column app.finance_tax_codes.name is
  'A statutory classification label only (e.g. "PPN" = Indonesia''s VAT article name). No numeric rate is implied or seeded by this column -- see this migration''s own header.';

create table app.finance_tax_rule_versions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references app.tenants (id),
  tax_code_id uuid not null references app.finance_tax_codes (id),
  rate_basis text not null,
  rate_value numeric(12, 6) not null,
  currency text,
  output_account_id uuid references app.finance_accounts (id),
  recoverable_account_id uuid references app.finance_accounts (id),
  effective_from date not null,
  effective_to date,
  status text not null default 'draft',
  is_example_fixture boolean not null default false,
  evidence_reference_file_id uuid references app.files (id),
  evidence_note text,
  approved_by text,
  approved_at timestamptz,
  archived_reason text,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint finance_tax_rule_versions_status_check check (status in ('draft', 'approved', 'archived')),
  constraint finance_tax_rule_versions_rate_basis_check check (rate_basis in ('percentage', 'fixed_amount')),
  constraint finance_tax_rule_versions_rate_value_check check (rate_value >= 0),
  constraint finance_tax_rule_versions_percentage_bound_check check (rate_basis <> 'percentage' or rate_value <= 1),
  constraint finance_tax_rule_versions_fixed_amount_currency_check check (rate_basis <> 'fixed_amount' or currency is not null),
  constraint finance_tax_rule_versions_currency_check check (currency is null or currency ~ '^[A-Z]{3}$'),
  constraint finance_tax_rule_versions_date_order_check check (effective_to is null or effective_to >= effective_from),
  constraint finance_tax_rule_versions_approved_evidence_check check (
    status <> 'approved' or evidence_reference_file_id is not null or (evidence_note is not null and length(trim(evidence_note)) > 0)
  )
);

comment on table app.finance_tax_rule_versions is
  'FIN-195: a versioned, effective-dated, SME-approval-gated tax rule (draft -> approved -> archived, mirrors FIN-194''s own finance_exchange_rates lifecycle exactly). is_example_fixture rows can never reach approved -- see app.approve_finance_tax_rule and this migration''s own header. Actual GL posting of tax accounts is FIN-202/203''s own scope; output_account_id/recoverable_account_id are governed references only.';

create index finance_tax_rule_versions_tenant_code_idx on app.finance_tax_rule_versions (coalesce(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid), tax_code_id, status);
create index finance_tax_rule_versions_tax_code_id_idx on app.finance_tax_rule_versions (tax_code_id);

create function app.touch_finance_tax_rule_version_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger finance_tax_rule_versions_touch_row
  before update on app.finance_tax_rule_versions
  for each row
  execute function app.touch_finance_tax_rule_version_row();

-- The one illustrative example fixture -- see this migration's own header for
-- why rate_value is 0 and why is_example_fixture makes this row structurally
-- unable to ever reach 'approved'.
insert into app.finance_tax_rule_versions (
  tenant_id, tax_code_id, rate_basis, rate_value, currency, effective_from, status, is_example_fixture, evidence_note, created_by
)
select
  null, id, 'percentage', 0, null, '2026-01-01'::date, 'draft', true,
  'EXAMPLE FIXTURE ONLY -- NOT A VERIFIED RATE. rate_value is a structural placeholder (0), not a real Indonesian PPN percentage. An authorized Finance/Tax SME must create a fresh, evidence-backed draft (app.create_finance_tax_rule_draft) and approve it (app.approve_finance_tax_rule) before any real PPN calculation is possible for a tenant. This fixture can never itself be approved -- see app.approve_finance_tax_rule.',
  'finance-foundation'
from app.finance_tax_codes where tenant_id is null and code = 'PPN';

create function app.check_finance_tax_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid)
returns boolean
language sql
stable
as $$
  select case
    when p_tenant_id is null then app.is_supreme_admin(p_actor_auth_user_id)
    else (app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'FIN', p_action)).allowed
  end;
$$;

comment on function app.check_finance_tax_authority is
  'FIN-195: FIN:Edit gates draft/evidence-attach/discard; FIN:Approve gates the explicit SME activation step; FIN:View gates read/resolve/calculate -- the canonical PLT-111 FIN permission catalogue, reused directly. A platform-wide default rule (tenant_id null) falls to Supreme Admin (mirrors FIN-194''s own null-tenant fallback).';

create function app.create_finance_tax_rule_draft(
  p_tenant_id uuid,
  p_tax_code_id uuid,
  p_rate_basis text,
  p_rate_value numeric,
  p_currency text,
  p_output_account_id uuid,
  p_recoverable_account_id uuid,
  p_effective_from date,
  p_effective_to date,
  p_actor_auth_user_id uuid,
  p_created_by text
)
returns app.finance_tax_rule_versions
language plpgsql
as $$
declare
  v_code app.finance_tax_codes;
  v_rule app.finance_tax_rule_versions;
  v_account app.finance_accounts;
begin
  if p_tenant_id is not null and not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % holds no active membership for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.check_finance_tax_authority('Edit', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_code from app.finance_tax_codes where id = p_tax_code_id and is_active;
  if not found then
    raise exception 'finance_tax_rule_unsupported_code: % is not an active tax code', p_tax_code_id
      using errcode = 'check_violation';
  end if;
  if v_code.tenant_id is not null and v_code.tenant_id <> p_tenant_id then
    raise exception 'finance_tax_rule_scope_mismatch: tax code % is scoped to a different tenant', p_tax_code_id
      using errcode = 'check_violation';
  end if;

  if p_rate_basis not in ('percentage', 'fixed_amount') then
    raise exception 'finance_tax_rule_unsupported_basis: % is not a supported rate basis', p_rate_basis
      using errcode = 'check_violation';
  end if;
  if p_rate_value is null or p_rate_value < 0 then
    raise exception 'finance_tax_rule_invalid_rate: rate must be non-negative, got %', p_rate_value
      using errcode = 'check_violation';
  end if;

  -- Platform-wide default rules (p_tenant_id null) cannot reference a
  -- tenant-scoped account -- app.finance_accounts always belongs to exactly
  -- one tenant.
  if p_tenant_id is null and (p_output_account_id is not null or p_recoverable_account_id is not null) then
    raise exception 'finance_tax_rule_account_scope_mismatch: a platform-wide default rule cannot reference a tenant-scoped account'
      using errcode = 'check_violation';
  end if;

  if p_output_account_id is not null then
    select * into v_account from app.finance_accounts where id = p_output_account_id;
    if not found or v_account.tenant_id <> p_tenant_id or v_account.status <> 'active' or not v_account.is_postable then
      raise exception 'finance_tax_rule_invalid_account_mapping: output account % is not an active, postable account for tenant %', p_output_account_id, p_tenant_id
        using errcode = 'check_violation';
    end if;
  end if;
  if p_recoverable_account_id is not null then
    select * into v_account from app.finance_accounts where id = p_recoverable_account_id;
    if not found or v_account.tenant_id <> p_tenant_id or v_account.status <> 'active' or not v_account.is_postable then
      raise exception 'finance_tax_rule_invalid_account_mapping: recoverable account % is not an active, postable account for tenant %', p_recoverable_account_id, p_tenant_id
        using errcode = 'check_violation';
    end if;
  end if;

  insert into app.finance_tax_rule_versions (
    tenant_id, tax_code_id, rate_basis, rate_value, currency, output_account_id, recoverable_account_id, effective_from, effective_to, created_by
  )
  values (
    p_tenant_id, p_tax_code_id, p_rate_basis, p_rate_value, p_currency, p_output_account_id, p_recoverable_account_id, p_effective_from, p_effective_to, p_created_by
  )
  returning * into v_rule;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_created_by, 'create_finance_tax_rule_draft',
    'app.finance_tax_rule_versions', v_rule.id, 'success', null, null, to_jsonb(v_rule)
  );

  return v_rule;
end;
$$;

create function app.attach_finance_tax_rule_evidence(
  p_rule_id uuid,
  p_expected_version integer,
  p_evidence_reference_file_id uuid,
  p_evidence_note text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.finance_tax_rule_versions
language plpgsql
as $$
declare
  v_rule app.finance_tax_rule_versions;
begin
  select * into v_rule from app.finance_tax_rule_versions where id = p_rule_id;
  if not found then
    raise exception 'finance_tax_rule_not_found: %', p_rule_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_tax_authority('Edit', v_rule.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, v_rule.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_rule.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_rule.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_rule.status <> 'draft' then
    raise exception 'finance_tax_rule_not_draft: rule % is % not draft', p_rule_id, v_rule.status
      using errcode = 'check_violation';
  end if;
  if p_evidence_reference_file_id is null and (p_evidence_note is null or length(trim(p_evidence_note)) = 0) then
    raise exception 'finance_tax_rule_evidence_missing: at least one of an evidence file or a non-empty evidence note is required'
      using errcode = 'check_violation';
  end if;

  update app.finance_tax_rule_versions
    set evidence_reference_file_id = coalesce(p_evidence_reference_file_id, evidence_reference_file_id),
        evidence_note = coalesce(p_evidence_note, evidence_note)
    where id = p_rule_id
    returning * into v_rule;

  perform app.capture_audit_event(
    v_rule.tenant_id, p_actor_auth_user_id, p_actor_label, 'attach_finance_tax_rule_evidence',
    'app.finance_tax_rule_versions', v_rule.id, 'success', null, null, jsonb_build_object('evidenceReferenceFileId', v_rule.evidence_reference_file_id)
  );

  return v_rule;
end;
$$;

create function app.discard_finance_tax_rule_draft(
  p_rule_id uuid,
  p_expected_version integer,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.finance_tax_rule_versions
language plpgsql
as $$
declare
  v_rule app.finance_tax_rule_versions;
begin
  select * into v_rule from app.finance_tax_rule_versions where id = p_rule_id;
  if not found then
    raise exception 'finance_tax_rule_not_found: %', p_rule_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_tax_authority('Edit', v_rule.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Edit for tenant %', p_actor_auth_user_id, v_rule.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_rule.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_rule.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_rule.status <> 'draft' then
    raise exception 'finance_tax_rule_not_draft: rule % is % not draft', p_rule_id, v_rule.status
      using errcode = 'check_violation';
  end if;

  update app.finance_tax_rule_versions set status = 'archived', archived_reason = p_reason where id = p_rule_id returning * into v_rule;

  perform app.capture_audit_event(
    v_rule.tenant_id, p_actor_auth_user_id, p_actor_label, 'discard_finance_tax_rule_draft',
    'app.finance_tax_rule_versions', v_rule.id, 'success', p_reason, null, to_jsonb(v_rule)
  );

  return v_rule;
end;
$$;

create function app.approve_finance_tax_rule(
  p_rule_id uuid,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.finance_tax_rule_versions
language plpgsql
as $$
declare
  v_rule app.finance_tax_rule_versions;
  v_overlap_count integer;
begin
  select * into v_rule from app.finance_tax_rule_versions where id = p_rule_id;
  if not found then
    raise exception 'finance_tax_rule_not_found: %', p_rule_id using errcode = 'no_data_found';
  end if;
  if not app.check_finance_tax_authority('Approve', v_rule.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_rule.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_rule.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_rule.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_rule.status <> 'draft' then
    raise exception 'finance_tax_rule_not_draft: rule % is % not draft', p_rule_id, v_rule.status
      using errcode = 'check_violation';
  end if;
  if v_rule.is_example_fixture then
    raise exception 'finance_tax_rule_example_fixture_not_activatable: rule % is a seeded illustrative example and can never be approved -- create a fresh evidence-backed draft', p_rule_id
      using errcode = 'check_violation';
  end if;
  if v_rule.evidence_reference_file_id is null and (v_rule.evidence_note is null or length(trim(v_rule.evidence_note)) = 0) then
    raise exception 'finance_tax_rule_evidence_missing: rule % has no attached SME evidence', p_rule_id
      using errcode = 'check_violation';
  end if;

  select count(*) into v_overlap_count
    from app.finance_tax_rule_versions r
    where r.tax_code_id = v_rule.tax_code_id
      and coalesce(r.tenant_id, '00000000-0000-0000-0000-000000000000'::uuid) = coalesce(v_rule.tenant_id, '00000000-0000-0000-0000-000000000000'::uuid)
      and r.status = 'approved'
      and r.id <> v_rule.id
      and r.effective_from <= coalesce(v_rule.effective_to, 'infinity'::date)
      and coalesce(r.effective_to, 'infinity'::date) >= v_rule.effective_from;
  if v_overlap_count > 0 then
    raise exception 'finance_tax_rule_overlap: an approved rule for this tax code and scope already covers an overlapping effective window'
      using errcode = 'check_violation';
  end if;

  update app.finance_tax_rule_versions
    set status = 'approved', approved_by = p_actor_label, approved_at = now()
    where id = p_rule_id
    returning * into v_rule;

  perform app.capture_audit_event(
    v_rule.tenant_id, p_actor_auth_user_id, p_actor_label, 'approve_finance_tax_rule',
    'app.finance_tax_rule_versions', v_rule.id, 'success', null, null, to_jsonb(v_rule)
  );

  return v_rule;
end;
$$;

-- Deterministic tenant-then-global resolution (mirrors FIN-194's own
-- app.resolve_finance_exchange_rate exactly, including the setof return type
-- -- see FIN-194's own db-test-caught defect note in
-- docs/build-log/phase-04/FIN-194.md section 3.2 for why setof, not a bare
-- composite, is required for correct FOUND semantics in every caller).
create function app.resolve_finance_tax_rule(
  p_tenant_id uuid,
  p_tax_code text,
  p_as_of date
)
returns setof app.finance_tax_rule_versions
language sql
stable
as $$
  with resolved_code as (
    select id from app.finance_tax_codes
    where code = p_tax_code and is_active
      and (tenant_id = p_tenant_id or tenant_id is null)
    order by tenant_id nulls last
    limit 1
  )
  select r.* from app.finance_tax_rule_versions r
  where r.tax_code_id in (select id from resolved_code)
    and r.status = 'approved'
    and (r.tenant_id = p_tenant_id or r.tenant_id is null)
    and r.effective_from <= coalesce(p_as_of, current_date)
    and coalesce(r.effective_to, 'infinity'::date) >= coalesce(p_as_of, current_date)
  order by r.tenant_id nulls last, r.effective_from desc
  limit 1;
$$;

comment on function app.resolve_finance_tax_rule is
  'FIN-195: tenant-specific approved rule wins over the platform-wide default, for whichever tax-code scope (tenant-specific code overrides a platform-wide code with the same string) resolves first. Returns zero rows if no approved rule covers p_as_of at any level -- callers must treat that as "missing rule," never assume one.';

-- Exact-decimal calculation service (Prompt 195 section 14's "calculate"
-- operation). Rejects when no approved rule is found -- never silently
-- substitutes a zero, stale, or guessed rate (Prompt 195 section 24).
create function app.calculate_finance_tax(
  p_tenant_id uuid,
  p_tax_code text,
  p_base_amount numeric,
  p_as_of date,
  p_actor_auth_user_id uuid
)
returns jsonb
language plpgsql
as $$
declare
  v_rule app.finance_tax_rule_versions;
  v_mode text;
  v_precision integer;
  v_raw numeric;
  v_tax_amount numeric;
  v_rounding_row record;
begin
  if not app.check_finance_tax_authority('View', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_base_amount is null or p_base_amount < 0 then
    raise exception 'finance_tax_rule_invalid_base_amount: base amount must be non-negative, got %', p_base_amount
      using errcode = 'check_violation';
  end if;

  select * into v_rule from app.resolve_finance_tax_rule(p_tenant_id, p_tax_code, coalesce(p_as_of, current_date));
  if not found then
    raise exception 'finance_tax_rule_missing: no approved tax rule for % covers %', p_tax_code, coalesce(p_as_of, current_date)
      using errcode = 'no_data_found';
  end if;

  v_raw := case when v_rule.rate_basis = 'percentage' then p_base_amount * v_rule.rate_value else v_rule.rate_value end;

  v_mode := 'round_half_up';
  v_precision := 2;
  for v_rounding_row in select * from app.resolve_finance_config('finance_rounding', p_tenant_id) loop
    if v_rounding_row.items ? 'tax_calculation' then
      v_mode := coalesce(v_rounding_row.items -> 'tax_calculation' ->> 'mode', v_mode);
      v_precision := coalesce((v_rounding_row.items -> 'tax_calculation' ->> 'precision')::integer, v_precision);
    elsif v_rounding_row.items ? 'default' then
      v_mode := coalesce(v_rounding_row.items -> 'default' ->> 'mode', v_mode);
      v_precision := coalesce((v_rounding_row.items -> 'default' ->> 'precision')::integer, v_precision);
    end if;
  end loop;

  v_tax_amount := app.apply_finance_rounding(v_raw, v_precision, v_mode);

  return jsonb_build_object(
    'baseAmount', p_base_amount,
    'taxCode', p_tax_code,
    'ruleVersionId', v_rule.id,
    'rateBasis', v_rule.rate_basis,
    'rateValue', v_rule.rate_value,
    'currency', v_rule.currency,
    'taxAmount', v_tax_amount,
    'roundingMode', v_mode,
    'effectiveFrom', v_rule.effective_from,
    'effectiveTo', v_rule.effective_to
  );
end;
$$;

comment on function app.calculate_finance_tax is
  'FIN-195: the shared, deterministic tax-calculation service every later invoicing/billing capability (FIN-197/200) reads. Resolves the tenant''s own effective finance_rounding config (FIN-191), key tax_calculation falling back to default falling back to the same disclosed safe default FIN-194''s own convert_finance_amount already established -- one rounding authority, never a second.';

create function app.list_finance_tax_codes(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns setof app.finance_tax_codes
language plpgsql
stable
as $$
begin
  if not app.check_finance_tax_authority('View', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  return query select * from app.finance_tax_codes
    where (tenant_id = p_tenant_id or tenant_id is null) and is_active
    order by code;
end;
$$;

create function app.list_finance_tax_rule_versions(p_tenant_id uuid, p_tax_code_id uuid, p_actor_auth_user_id uuid)
returns setof app.finance_tax_rule_versions
language plpgsql
stable
as $$
begin
  if not app.check_finance_tax_authority('View', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  return query select * from app.finance_tax_rule_versions
    where (tenant_id = p_tenant_id or tenant_id is null)
      and (p_tax_code_id is null or tax_code_id = p_tax_code_id)
    order by effective_from desc;
end;
$$;

alter table app.finance_tax_codes enable row level security;
alter table app.finance_tax_rule_versions enable row level security;

create policy finance_tax_codes_select_scoped on app.finance_tax_codes
  for select to authenticated
  using (tenant_id is null or app.has_active_tenant_membership(tenant_id) or app.is_supreme_admin());

create policy finance_tax_rule_versions_select_scoped on app.finance_tax_rule_versions
  for select to authenticated
  using (tenant_id is null or app.has_active_tenant_membership(tenant_id) or app.is_supreme_admin());

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit, directly-provable
-- revoke of PostgreSQL's PUBLIC-execute default, the standing per-migration
-- convention since PLT-118, applied here before any role-specific grant.
revoke execute on all functions in schema app from public;

grant select on app.finance_tax_codes to authenticated, service_role;
grant select on app.finance_tax_rule_versions to authenticated, service_role;
grant insert, update, delete on app.finance_tax_codes to service_role;
grant insert, update, delete on app.finance_tax_rule_versions to service_role;

grant execute on function app.touch_finance_tax_rule_version_row() to service_role;
grant execute on function app.check_finance_tax_authority(text, uuid, uuid) to service_role;
grant execute on function app.create_finance_tax_rule_draft(uuid, uuid, text, numeric, text, uuid, uuid, date, date, uuid, text) to authenticated, service_role;
grant execute on function app.attach_finance_tax_rule_evidence(uuid, integer, uuid, text, uuid, text) to authenticated, service_role;
grant execute on function app.discard_finance_tax_rule_draft(uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.approve_finance_tax_rule(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.resolve_finance_tax_rule(uuid, text, date) to authenticated, service_role;
grant execute on function app.calculate_finance_tax(uuid, text, numeric, date, uuid) to authenticated, service_role;
grant execute on function app.list_finance_tax_codes(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_finance_tax_rule_versions(uuid, uuid, uuid) to authenticated, service_role;
