-- Commercial capability COM-160 (Full Lineage into Job Order, CG-S7-COM-019)
-- The idempotent accepted-quote -> JobOrderDraftInput handoff contract Commercial owns
-- and Phase 3 Operations is the disclosed, not-yet-built consumer of. Commercial's own
-- scope ends at producing one immutable, versioned, lineage-complete snapshot per
-- accepted quotation -- **no Job Order table, route, or domain logic is implemented
-- here** (Prompt 160 §12/§24's own explicit forbidden-scope line, structural in this
-- migration: zero references to any "job_order" concept beyond this one handoff record).
--
-- Scope boundaries (disclosed, not silently narrowed, matching every prior checkpoint):
--
-- * **Every payload field is a reference to, or a verbatim snapshot of, an already-
--   canonical Commercial source -- never retyped or re-derived.** Customer/billing
--   identity comes from `app.quotations.customer_snapshot` (COM-151's own pinned
--   snapshot, not re-read from `app.accounts` at handoff time, since the quotation's own
--   snapshot is what the customer actually accepted); cargo/service comes from
--   `app.opportunities.requirements` (COM-147); pricing comes from `app.quotations`/
--   `app.quotation_lines`'s own real, server-computed totals (COM-151); acceptance
--   evidence comes from `app.quotation_customer_decisions` (COM-154); the converted
--   account comes from `app.account_conversions` (COM-155, `unique(quotation_id)` --
--   the natural, already-`VERIFIED` one-quotation-one-account edge); the contract, if
--   any, comes from `app.customer_contracts.source_quotation_id` (COM-156); the credit
--   signal, if any, comes from the account's most recent `app.credit_check_snapshots`
--   row (COM-157) -- **only its `outcome`/`checked_at`, never a dollar limit figure**,
--   sidestepping any need for fine-grained masking inside the credit portion of the
--   payload entirely, a deliberate scope-narrowing disclosed here rather than silently
--   omitted.
-- * **Idempotency key is `(tenant_id, quotation_id, purpose)`** -- Prompt 160 §24's own
--   "one accepted quote/version... cannot create duplicate downstream outcome," and
--   `account_conversions_quotation_unique` already established this exact one-row-per-
--   quotation-ever shape for the adjacent COM-155 capability. `purpose` is a forward-
--   compatible column bounded to one real value (`'job_order_draft'`) today, mirroring
--   `app.report_runs.run_type`'s own bounded-enum-today shape.
-- * **`app.prepare_job_order_handoff` is synchronous and deterministic, not a queued
--   job.** Every source it reads is already-live Commercial data with no external
--   dependency -- unlike `COM-159`'s export (which genuinely does async work a worker
--   would perform), assembling this snapshot is bounded, fast, and has no real failure
--   mode beyond "the source data does not yet satisfy the preconditions," which raises a
--   named exception and creates no row at all -- retrying after the blocker is fixed
--   succeeds cleanly with no separate "failed" state to reconcile. `downstream_reference`/
--   `delivered_at` are the real, structurally-ready columns a future Phase 3 Operations
--   consumer would populate once it exists -- both stay null in this environment,
--   disclosed, not fabricated.
-- * **The full `payload` (and its `payload_hash`) is masked wholesale, not per-key**,
--   behind the already-established `COM:View selling price` gate (`COM-147`) via
--   `app.job_order_handoffs_directory` -- the same coarser-grained-but-correct choice
--   this checkpoint makes deliberately rather than attempting unproven fine-grained
--   partial-jsonb-key masking. `app.prepare_job_order_handoff` itself is gated only on
--   `COM:Edit`, not `COM:View selling price` (preparing a handoff should not require
--   seeing prices) -- so it also masks its own *returned* payload/payload_hash per-caller
--   directly in the function body, the same "mask the function's own output" technique
--   `app.check_customer_credit` (`COM-157`) and `app.get_effective_customer_price`
--   (`COM-156`) already established; the row it inserts always carries the real payload
--   regardless of who called it. `authenticated` has no direct column grant on `payload`/
--   `payload_hash` on the base table at all, forcing every subsequent read through the
--   directory,
--   the identical database guarantee `app.quotations_directory` already established.
-- * Per `ERR-2026-004` (`docs/runtime/ERROR_LEDGER.md`): this migration carries its own
--   explicit `REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA app FROM PUBLIC` statement before
--   its final grants, the standing per-migration convention since `PLT-118`. Every
--   function that reads a column outside `authenticated`'s own grant (quotation/line
--   money columns) is `security definer` from the start -- the `COM-158` lesson applied
--   proactively this checkpoint, not rediscovered a third time.

create table app.job_order_handoffs (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  quotation_id uuid not null references app.quotations (id),
  account_id uuid not null references app.accounts (id),
  purpose text not null default 'job_order_draft',
  schema_version integer not null default 1,
  status text not null default 'prepared',
  payload jsonb not null,
  payload_hash text not null,
  downstream_reference text,
  delivered_at timestamptz,
  prepared_by_auth_user_id uuid not null references auth.users (id),
  owner_user_id uuid references auth.users (id),
  org_unit_id uuid references app.org_units (id),
  created_by text,
  created_at timestamptz not null default now(),
  constraint job_order_handoffs_status_check check (status in ('prepared', 'delivered')),
  constraint job_order_handoffs_schema_version_check check (schema_version > 0),
  constraint job_order_handoffs_payload_check check (jsonb_typeof(payload) = 'object'),
  constraint job_order_handoffs_delivered_check check (
    (status = 'delivered' and delivered_at is not null and downstream_reference is not null)
    or (status = 'prepared')
  ),
  constraint job_order_handoffs_tenant_quotation_purpose_unique unique (tenant_id, quotation_id, purpose)
);

comment on table app.job_order_handoffs is
  'COM-160: one immutable, versioned JobOrderDraftInput snapshot per accepted quotation (unique on tenant_id/quotation_id/purpose -- the real idempotency key). Commercial''s own scope ends here; status/downstream_reference/delivered_at are the real, disclosed NOT_RUN target shape Phase 3 Operations would populate once a live consumer exists.';

create index job_order_handoffs_tenant_account_idx on app.job_order_handoffs (tenant_id, account_id);
create index job_order_handoffs_tenant_status_idx on app.job_order_handoffs (tenant_id, status);

-- Assembles the deterministic JobOrderDraftInput snapshot from canonical sources only.
-- security definer: reads quotation/quotation_line money columns and account billing
-- fields outside authenticated's own column grant (the COM-158 lesson applied from the
-- start, see this migration's own header). Never called directly by an ordinary
-- session -- app.prepare_job_order_handoff is the one gated entrypoint.
create function app.build_job_order_draft_payload(p_quotation_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_quotation app.quotations;
  v_opportunity app.opportunities;
  v_conversion app.account_conversions;
  v_account app.accounts;
  v_contact app.contacts;
  v_decision app.quotation_customer_decisions;
  v_contract app.customer_contracts;
  v_credit_snapshot app.credit_check_snapshots;
  v_lines jsonb;
begin
  select * into v_quotation from app.quotations where id = p_quotation_id;
  if not found then
    raise exception 'quotation_not_found: %', p_quotation_id using errcode = 'no_data_found';
  end if;

  select * into v_opportunity from app.opportunities where id = v_quotation.opportunity_id;
  select * into v_conversion from app.account_conversions where quotation_id = p_quotation_id;
  if not found then
    raise exception 'account_not_converted: quotation % has not been converted to an account', p_quotation_id using errcode = 'check_violation';
  end if;
  select * into v_account from app.accounts where id = v_conversion.account_id;
  select * into v_decision from app.quotation_customer_decisions where quotation_id = p_quotation_id;
  if v_quotation.contact_id is not null then
    select * into v_contact from app.contacts where id = v_quotation.contact_id;
  end if;
  select * into v_contract from app.customer_contracts where source_quotation_id = p_quotation_id order by created_at desc limit 1;
  select * into v_credit_snapshot from app.credit_check_snapshots where account_id = v_account.id order by checked_at desc limit 1;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'lineNo', l.line_no, 'lineType', l.line_type, 'description', l.description,
      'quantity', l.quantity, 'unitPrice', l.unit_price, 'discountPct', l.discount_pct,
      'taxPct', l.tax_pct, 'lineGrossAmount', l.line_gross_amount, 'lineDiscountAmount', l.line_discount_amount,
      'lineTaxAmount', l.line_tax_amount, 'lineTotal', l.line_total
    ) order by l.line_no
  ), '[]'::jsonb) into v_lines
  from app.quotation_lines l
  where l.quotation_id = p_quotation_id;

  return jsonb_build_object(
    'schemaVersion', 1,
    'source', jsonb_build_object(
      'quotationId', v_quotation.id, 'quoteNumber', v_quotation.quote_number, 'versionNumber', v_quotation.version_number,
      'opportunityId', v_quotation.opportunity_id, 'prospectId', v_quotation.prospect_id, 'accountConversionId', v_conversion.id
    ),
    'customer', jsonb_build_object(
      'accountId', v_account.id, 'customerSnapshot', v_quotation.customer_snapshot,
      'contactId', v_contact.id, 'contactName', v_contact.full_name, 'contactEmail', v_contact.email, 'contactPhone', v_contact.phone
    ),
    'cargoService', coalesce(v_opportunity.requirements, '{}'::jsonb),
    'pricing', jsonb_build_object(
      'currency', v_quotation.currency, 'subtotalAmount', v_quotation.subtotal_amount, 'discountAmount', v_quotation.discount_amount,
      'taxAmount', v_quotation.tax_amount, 'totalAmount', v_quotation.total_amount, 'lines', v_lines
    ),
    'contract', case when v_contract.id is not null then jsonb_build_object('customerContractId', v_contract.id, 'rootContractId', v_contract.root_contract_id, 'versionNumber', v_contract.version_number, 'status', v_contract.status) else null end,
    'credit', case when v_credit_snapshot.id is not null then jsonb_build_object('outcome', v_credit_snapshot.outcome, 'checkedAt', v_credit_snapshot.checked_at) else null end,
    'acceptance', jsonb_build_object('decidedByName', v_decision.decided_by_name, 'decidedAt', v_decision.decided_at, 'decision', v_decision.decision)
  );
end;
$$;

comment on function app.build_job_order_draft_payload is
  'COM-160: deterministic snapshot assembly -- every field traces to exactly one canonical Commercial source (see this migration''s own header). Contains real, unmasked pricing (Operations needs it) -- credit deliberately carries only outcome/checked_at, never a dollar limit, so no monetary figure needing masking exists inside the credit portion at all.';

create function app.prepare_job_order_handoff(
  p_quotation_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.job_order_handoffs
language plpgsql
security definer
set search_path = app, public, extensions, pg_temp
as $$
declare
  v_quotation app.quotations;
  v_decision app.rbac_decision;
  v_conversion app.account_conversions;
  v_existing app.job_order_handoffs;
  v_payload jsonb;
  v_handoff app.job_order_handoffs;
begin
  select * into v_quotation from app.quotations where id = p_quotation_id;
  if not found then
    raise exception 'quotation_not_found: %', p_quotation_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_quotation.tenant_id, 'COM', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_quotation.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_quotation.tenant_id, v_quotation.owner_user_id, app.lead_record_scope_org_unit_ids(v_quotation.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access quotation %', p_actor_auth_user_id, p_quotation_id
      using errcode = 'insufficient_privilege';
  end if;

  -- Idempotent: an existing handoff for this exact (tenant, quotation, purpose) is
  -- returned unchanged -- never rebuilt, never duplicated (Prompt 160 §24).
  select * into v_existing from app.job_order_handoffs where tenant_id = v_quotation.tenant_id and quotation_id = p_quotation_id and purpose = 'job_order_draft';
  if found then
    if not app.has_view_selling_price(v_quotation.tenant_id, p_actor_auth_user_id) then
      v_existing.payload := null;
      v_existing.payload_hash := null;
    end if;
    return v_existing;
  end if;

  if not v_quotation.is_current then
    raise exception 'not_current_version: quotation % version % is not the current version', p_quotation_id, v_quotation.version_number using errcode = 'check_violation';
  end if;
  if v_quotation.status <> 'submitted' then
    raise exception 'quote_not_submitted: quotation % is % and cannot be handed off', p_quotation_id, v_quotation.status using errcode = 'check_violation';
  end if;
  if v_quotation.approval_status not in ('approved', 'not_required') then
    raise exception 'quote_not_approved: quotation % approval_status is %', p_quotation_id, v_quotation.approval_status using errcode = 'check_violation';
  end if;
  if v_quotation.customer_decision is distinct from 'accepted' then
    raise exception 'quote_not_accepted: quotation % has not been accepted by the customer', p_quotation_id using errcode = 'check_violation';
  end if;

  select * into v_conversion from app.account_conversions where quotation_id = p_quotation_id;
  if not found then
    raise exception 'account_not_converted: quotation % has not been converted to an account', p_quotation_id using errcode = 'check_violation';
  end if;

  v_payload := app.build_job_order_draft_payload(p_quotation_id);

  insert into app.job_order_handoffs (
    tenant_id, quotation_id, account_id, payload, payload_hash,
    prepared_by_auth_user_id, owner_user_id, org_unit_id, created_by
  ) values (
    v_quotation.tenant_id, p_quotation_id, v_conversion.account_id, v_payload, encode(digest(v_payload::text, 'sha256'), 'hex'),
    p_actor_auth_user_id, v_quotation.owner_user_id, v_quotation.org_unit_id, p_actor_label
  )
  returning * into v_handoff;

  perform app.capture_audit_event(
    v_quotation.tenant_id, p_actor_auth_user_id, p_actor_label, 'prepare_job_order_handoff',
    'app.job_order_handoffs', v_handoff.id, 'success', null, null,
    jsonb_build_object('quotation_id', p_quotation_id, 'account_id', v_conversion.account_id, 'payload_hash', v_handoff.payload_hash)
  );

  if not app.has_view_selling_price(v_quotation.tenant_id, p_actor_auth_user_id) then
    v_handoff.payload := null;
    v_handoff.payload_hash := null;
  end if;

  return v_handoff;
end;
$$;

comment on function app.prepare_job_order_handoff is
  'COM-160: the one gated entrypoint. Re-validates accepted/approved/current/converted preconditions fresh on every call (Prompt 160 §16''s "revalidate... at conversion") and is idempotent on (tenant_id, quotation_id, purpose) -- a retry after the row already exists returns it unchanged rather than re-deriving or duplicating it. Synchronous and deterministic (see this migration''s own header) -- no queued job, no separate failed-attempt state, since every precondition failure creates no row at all and is safely retryable once fixed. Masks its own returned payload/payload_hash per-caller (COM:View selling price) directly in the function body -- the same technique app.check_customer_credit (COM-157) and app.get_effective_customer_price (COM-156) already established -- since this function itself is gated only on COM:Edit, not COM:View selling price, and the row it inserts always contains the real payload for whoever is entitled to read it later via app.job_order_handoffs_directory.';

-- Field-masked wholesale projection (COM-160, mirrors app.quotations_directory's own
-- security_invoker=false-required-for-masking shape, PLT-114/COM-147 pattern). payload/
-- payload_hash are nulled out (payload_masked=true) for any caller lacking COM:View
-- selling price -- the real pricing lives only inside payload, so masking it wholesale
-- is the correct, provably-complete gate; every other column (status, timestamps,
-- account/quotation references) is never masked.
create view app.job_order_handoffs_directory
as
select
  h.id,
  h.tenant_id,
  h.quotation_id,
  h.account_id,
  h.purpose,
  h.schema_version,
  h.status,
  case when app.has_view_selling_price(h.tenant_id) then h.payload else null end as payload,
  case when app.has_view_selling_price(h.tenant_id) then h.payload_hash else null end as payload_hash,
  not app.has_view_selling_price(h.tenant_id) as payload_masked,
  h.downstream_reference,
  h.delivered_at,
  h.prepared_by_auth_user_id,
  h.owner_user_id,
  h.org_unit_id,
  h.created_by,
  h.created_at
from app.job_order_handoffs h
where app.can_access_record(auth.uid(), h.tenant_id, h.owner_user_id, app.lead_record_scope_org_unit_ids(h.org_unit_id), null);

comment on view app.job_order_handoffs_directory is
  'COM-160: field-masked projection of app.job_order_handoffs -- payload/payload_hash nulled out (payload_masked=true) for any caller lacking COM:View selling price. authenticated has no direct column-level grant on those two columns on the base table itself, forcing every read through this view -- the identical database guarantee app.quotations_directory already established.';

alter table app.job_order_handoffs enable row level security;

create policy job_order_handoffs_select_scoped on app.job_order_handoffs
  for select to authenticated
  using (app.can_access_record(auth.uid(), tenant_id, owner_user_id, app.lead_record_scope_org_unit_ids(org_unit_id), null));

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit, directly-provable revoke of
-- PostgreSQL's PUBLIC-execute default, the standing per-migration convention since
-- PLT-118, applied here before any role-specific grant.
revoke execute on all functions in schema app from public;

grant usage on schema app to authenticated;

-- The database guarantee (matches PLT-114/COM-147..160's own proven technique): a bare
-- column-level REVOKE cannot carve an exception out of a broader table-level GRANT --
-- the table-level grant must be revoked entirely and re-granted on an explicit column
-- list that omits payload/payload_hash.
grant select (
  id, tenant_id, quotation_id, account_id, purpose, schema_version, status,
  downstream_reference, delivered_at, prepared_by_auth_user_id, owner_user_id, org_unit_id, created_by, created_at
) on app.job_order_handoffs to authenticated;
grant select on app.job_order_handoffs to service_role;
grant insert, update, delete on app.job_order_handoffs to service_role;

grant select on app.job_order_handoffs_directory to authenticated, service_role;

grant execute on function app.build_job_order_draft_payload(uuid) to service_role;
grant execute on function app.prepare_job_order_handoff(uuid, uuid, text) to authenticated, service_role;
