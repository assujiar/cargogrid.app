-- Commercial capability COM-161 (No-Reentry Enforcement, CG-S7-COM-020)
-- Closes two concrete, disclosed no-reentry/canonical-reuse gaps left open by prior
-- Commercial checkpoints, rather than inventing a new generic "provenance framework" --
-- every prior capability (COM-143..160) already hand-rolls its own jsonb snapshot column
-- or duplicate-fingerprint check, each explicitly disclosed as "a snapshot, never a live
-- re-typed copy" in its own build log; this migration does not re-architect that
-- established, working pattern.
--
-- Gap 1 -- referential integrity: app.opportunities.account_ref (COM-147) was authored as
-- a disclosed "forward-compatible placeholder", a plain `text` column populated by
-- app.convert_quotation_to_account (COM-155) via a same-value string cast
-- (`v_account.id::text`) with no foreign key, no index, and no database-enforced guarantee
-- it ever stays in sync with app.accounts. That is a copy, not a reference -- exactly what
-- Prompt 161's "no re-entry" rule forbids once a canonical app.accounts row exists. This
-- migration adds a real `account_id uuid references app.accounts(id)` column, backfills it
-- from any already-populated account_ref, and re-points app.convert_quotation_to_account at
-- the canonical column going forward. account_ref itself is kept (not dropped) for
-- backward read compatibility -- this repository's immutable-migrations convention
-- forbids editing COM-147's own applied column definition, and no caller of the prior
-- column is broken by additively introducing the FK-backed one alongside it.
--
-- Gap 2 -- visibility timing: app.find_duplicate_accounts (COM-155) already answers "is
-- this legal identity already a known account," but it is only ever called at quotation
-- acceptance / account-conversion time (app.get_account_conversion_readiness). A sales rep
-- can capture a brand-new Lead, qualify it into a Prospect, build an Opportunity, run
-- costing/rate lookup/margin, and build a Quotation -- a full duplicate parallel pipeline
-- for a company that is already a paying app.accounts customer -- before any check ever
-- fires. This migration exposes the same canonical-reuse question at the two earliest
-- points where it is answerable: app.find_existing_accounts_for_lead (company-name-only,
-- the one identifying field a Lead has) and app.find_existing_accounts_for_prospect
-- (reuses app.find_duplicate_accounts' own legal_name+tax_id fingerprint match verbatim --
-- a Prospect already carries the same shape). Both are read-only, advisory, non-blocking --
-- deliberately matching app.find_duplicate_leads/app.find_duplicate_prospects' own
-- established "surface candidates, never silently block capture" discipline (COM-143 §
-- comment on app.capture_lead); the actual "treat this as the same entity" action remains
-- the existing app.link_lead_to_existing_prospect (COM-144) and
-- app.convert_quotation_to_account(p_target_account_id=...) (COM-155) mutations -- no new
-- override/audit table is introduced because those two mutations already self-capture a
-- canonical app.audit_logs entry for exactly this decision.
--
-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): this migration carries its own explicit
-- `REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA app FROM PUBLIC` statement before its final
-- grants, the standing per-migration convention since PLT-118.

alter table app.opportunities add column account_id uuid references app.accounts (id);

comment on column app.opportunities.account_id is
  'COM-161: the canonical FK-backed replacement for account_ref''s own disclosed same-value text cast (COM-147/COM-155). NULL until the opportunity''s quotation converts to an account (app.convert_quotation_to_account sets both columns from this checkpoint onward). account_ref is retained, unmodified, for backward read compatibility -- this column is additive, not a rename.';

create index opportunities_tenant_account_idx on app.opportunities (tenant_id, account_id) where account_id is not null;

-- One-time, guarded backfill of any row app.convert_quotation_to_account already populated
-- account_ref for before this checkpoint. Regex-guarded (never a blind cast) because
-- account_ref is a plain text column with no format constraint of its own -- defensive,
-- not because any known bad value exists (greenfield capability, COM-147/155 only ever
-- wrote a valid uuid's own text form into it).
update app.opportunities
set account_id = account_ref::uuid
where account_ref is not null
  and account_id is null
  and account_ref ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';

-- Re-authored verbatim from COM-155's own applied body (supabase/migrations/
-- 20260724290000_create_commercial_customer_account_conversion.sql) with exactly one
-- changed line (the account_ref update, which now also sets the new canonical account_id
-- column) -- immutable-migrations convention means the prior file itself is never edited;
-- create or replace is the sanctioned way to extend an already-applied function, the same
-- pattern COM-155 itself used on app.resolve_commercial_record_ref (COM-145/COM-147).
create or replace function app.convert_quotation_to_account(
  p_quotation_id uuid,
  p_target_account_id uuid,
  p_parent_account_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.accounts
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_quotation app.quotations;
  v_prospect app.prospects;
  v_decision app.rbac_decision;
  v_existing_conversion app.account_conversions;
  v_account app.accounts;
  v_outcome text;
  v_normalized_legal_name text;
  v_normalized_tax_id text;
  v_fingerprint text;
  v_link app.contact_links%rowtype;
begin
  select * into v_quotation from app.quotations where id = p_quotation_id;
  if not found then
    raise exception 'quotation_not_found: %', p_quotation_id using errcode = 'no_data_found';
  end if;

  select * into v_existing_conversion from app.account_conversions where quotation_id = p_quotation_id;
  if found then
    select * into v_account from app.accounts where id = v_existing_conversion.account_id;
    return v_account;
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_quotation.tenant_id, 'COM', 'Approve');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Approve (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_quotation.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_quotation.tenant_id, v_quotation.owner_user_id, app.lead_record_scope_org_unit_ids(v_quotation.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access quotation %', p_actor_auth_user_id, p_quotation_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_quotation.customer_decision is distinct from 'accepted' then
    raise exception 'quotation_not_accepted: quotation % has no accepted customer decision', p_quotation_id
      using errcode = 'check_violation';
  end if;

  select * into v_prospect from app.prospects where id = v_quotation.prospect_id;
  if v_prospect.legal_name is null or length(trim(v_prospect.legal_name)) = 0 then
    raise exception 'missing_legal_name: prospect % has no legal_name to convert', v_prospect.id
      using errcode = 'check_violation';
  end if;

  if p_target_account_id is not null then
    select * into v_account from app.accounts where id = p_target_account_id;
    if not found or v_account.tenant_id <> v_quotation.tenant_id or v_account.status = 'merged' then
      raise exception 'target_account_not_found: no active account % in tenant %', p_target_account_id, v_quotation.tenant_id
        using errcode = 'no_data_found';
    end if;
    v_outcome := 'linked_existing';
  else
    v_normalized_legal_name := app.normalize_prospect_identifier(v_prospect.legal_name);
    v_normalized_tax_id := app.normalize_prospect_identifier(v_prospect.tax_id);
    v_fingerprint := app.compute_prospect_duplicate_fingerprint(v_quotation.tenant_id, v_normalized_legal_name, v_normalized_tax_id);

    begin
      insert into app.accounts (
        tenant_id, legal_name, trade_name, tax_id, normalized_legal_name, normalized_tax_id,
        duplicate_fingerprint, billing_address, parent_account_id, source_prospect_id,
        owner_user_id, org_unit_id, created_by
      ) values (
        v_quotation.tenant_id, v_prospect.legal_name, v_prospect.trade_name, v_prospect.tax_id,
        v_normalized_legal_name, v_normalized_tax_id, v_fingerprint,
        coalesce(v_quotation.customer_snapshot -> 'billing_address', v_prospect.billing_address, '{}'::jsonb),
        p_parent_account_id, v_prospect.id, p_actor_auth_user_id, v_quotation.org_unit_id, p_actor_label
      )
      returning * into v_account;
      v_outcome := 'created';
    exception
      when unique_violation then
        select * into v_account from app.accounts where tenant_id = v_quotation.tenant_id and duplicate_fingerprint = v_fingerprint and status = 'active';
        v_outcome := 'linked_existing';
    end;
  end if;

  begin
    insert into app.account_conversions (tenant_id, quotation_id, prospect_id, account_id, outcome, converted_by)
    values (v_quotation.tenant_id, p_quotation_id, v_prospect.id, v_account.id, v_outcome, p_actor_label);
  exception
    when unique_violation then
      select * into v_existing_conversion from app.account_conversions where quotation_id = p_quotation_id;
      select * into v_account from app.accounts where id = v_existing_conversion.account_id;
      return v_account;
  end;

  -- Reuse contacts (Prompt 155 §20 task 3: "reused contacts/address/site relationships")
  -- -- every contact linked to the source prospect is also linked to the resulting
  -- account, idempotent via app.link_contact_to_record's own (contact_id, related_type,
  -- related_id, role) uniqueness.
  for v_link in select * from app.contact_links where related_type = 'prospect' and related_id = v_prospect.id loop
    perform app.link_contact_to_record(v_link.contact_id, 'account', v_account.id, v_link.role, v_link.is_primary, p_actor_auth_user_id, p_actor_label);
  end loop;

  -- COM-161: now sets both the legacy disclosed text placeholder (account_ref, COM-147)
  -- and the canonical FK-backed column (account_id, this checkpoint) from the one same
  -- value -- closing app.opportunities.account_ref's own forward-reference disclosure.
  update app.opportunities set account_ref = v_account.id::text, account_id = v_account.id where id = v_quotation.opportunity_id;

  perform app.capture_audit_event(
    v_quotation.tenant_id, p_actor_auth_user_id, p_actor_label, 'convert_quotation_to_account',
    'app.accounts', v_account.id, 'success', null,
    jsonb_build_object('quotation_id', p_quotation_id, 'prospect_id', v_prospect.id),
    jsonb_build_object('outcome', v_outcome, 'account_id', v_account.id)
  );

  return v_account;
end;
$$;

comment on function app.convert_quotation_to_account is
  'COM-155, extended COM-161: the one atomic, idempotent (unique(quotation_id) on app.account_conversions) create-or-link operation. A concurrent create-new race against the same legal identity is caught (unique_violation on accounts_tenant_fingerprint_active_unique) and re-resolved as a link to the winning row, never a duplicate account and never a hard failure on genuine concurrency (Prompt 155 §27''s own scenario). COM-161 additionally sets app.opportunities.account_id (FK-backed), closing account_ref''s own disclosed placeholder gap.';

-- Advisory, non-blocking, tenant-scoped only (fails closed on missing membership) --
-- mirrors app.find_duplicate_leads' own discipline exactly (COM-143). company_name is the
-- only identifying field a Lead carries pre-qualification; the match is therefore
-- normalized-name-only (looser than app.find_duplicate_accounts' own legal_name+tax_id
-- fingerprint match), deliberately, since a Lead has no tax_id to compare.
create function app.find_existing_accounts_for_lead(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_lead_id uuid
)
returns setof app.accounts
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_lead app.leads;
  v_normalized_name text;
begin
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % holds no active membership for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_lead from app.leads where id = p_lead_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'lead_not_found: no lead % in tenant %', p_lead_id, p_tenant_id using errcode = 'no_data_found';
  end if;

  v_normalized_name := app.normalize_prospect_identifier(v_lead.company_name);
  if v_normalized_name is null then
    return;
  end if;

  return query
    select * from app.accounts
    where tenant_id = p_tenant_id
      and status <> 'merged'
      and normalized_legal_name = v_normalized_name
    order by created_at;
end;
$$;

comment on function app.find_existing_accounts_for_lead is
  'COM-161: "is this Lead''s company already a known Account" -- advisory only, never blocks app.capture_lead, the same non-blocking discipline app.find_duplicate_leads (COM-143) already established. Tenant-scoped only, fails closed on missing membership -- structurally cannot probe another tenant''s accounts.';

-- Reuses app.find_duplicate_accounts (COM-155) directly rather than re-authoring a
-- near-duplicate fingerprint match -- a Prospect already carries the identical
-- legal_name+tax_id shape app.accounts and app.find_duplicate_accounts expect, the same
-- "generic despite the specific name, reuse rather than re-author" precedent COM-144/
-- COM-147 already established for app.lead_record_scope_org_unit_ids.
create function app.find_existing_accounts_for_prospect(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_prospect_id uuid
)
returns setof app.accounts
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_prospect app.prospects;
begin
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % holds no active membership for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_prospect from app.prospects where id = p_prospect_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'prospect_not_found: no prospect % in tenant %', p_prospect_id, p_tenant_id using errcode = 'no_data_found';
  end if;

  return query select * from app.find_duplicate_accounts(p_tenant_id, p_actor_auth_user_id, v_prospect.legal_name, v_prospect.tax_id);
end;
$$;

comment on function app.find_existing_accounts_for_prospect is
  'COM-161: exposes app.find_duplicate_accounts'' own quotation-acceptance-time check (COM-155, app.get_account_conversion_readiness) at the much earlier Prospect stage -- before Opportunity/RFQ/rate-lookup/margin/Quotation work is ever duplicated for what may turn out to be a repeat customer. Advisory only, never blocks qualification -- the actual "treat as same entity" action remains app.convert_quotation_to_account(p_target_account_id=...).';

-- Reconciliation safety net (Prompt 161 §19: "detect/reconcile brownfield duplicates").
-- security_invoker=true so app.opportunities' own opportunities_select_scoped RLS policy
-- is the real row filter -- no column here needs masking (both are plain id-shaped
-- values), the same "security_invoker=true, no hand-rolled row filter needed" choice
-- COM-146 already made over a masking-free view.
create view app.commercial_opportunity_account_ref_drift
with (security_invoker = true)
as
select o.id as opportunity_id, o.tenant_id, o.account_ref, o.account_id
from app.opportunities o
where o.account_ref is not null
  and (o.account_id is null or o.account_id::text <> o.account_ref);

comment on view app.commercial_opportunity_account_ref_drift is
  'COM-161: flags any opportunity whose legacy account_ref text placeholder (COM-147) disagrees with, or is missing, the canonical account_id FK (COM-161) -- should be structurally empty from this checkpoint onward (both columns are now set together by app.convert_quotation_to_account), retained as an ongoing brownfield-drift detector, never a mass-rewrite tool.';

revoke execute on all functions in schema app from public;

grant execute on function app.find_existing_accounts_for_lead(uuid, uuid, uuid) to authenticated, service_role;
grant execute on function app.find_existing_accounts_for_prospect(uuid, uuid, uuid) to authenticated, service_role;
grant execute on function app.convert_quotation_to_account(uuid, uuid, uuid, uuid, text) to authenticated, service_role;

grant select on app.commercial_opportunity_account_ref_drift to authenticated, service_role;
