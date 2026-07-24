-- Commercial capability COM-154 (Customer Acceptance, CG-S7-COM-013)
-- Secure delivery of an approved quotation to a customer who holds no CargoGrid account
-- (no Customer Portal exists yet, `COM-155` Customer and Account Conversion has not run),
-- and an explicit, evidence-locked accept/reject decision bound to one exact quotation
-- version -- Prompt 154 §24: "delivery/read is not acceptance," "one final customer
-- decision binds one exact approved version."
--
-- Reuses, not reinvents: the hashed-bearer-secret shape is `PLT-129`'s own
-- `app.api_keys`/`app.authenticate_api_key` (raw value returned exactly once,
-- `sha256` digest stored, lazy expiry-flip-on-read) -- the closest existing precedent in
-- this repository for "validate a caller with no `auth.users` row via a presented secret."
-- The public consumption route reuses `PLT-135`'s own `createSupabaseServiceRoleClient()`
-- (`lib/supabase/service-role.ts`) -- already an established, already-used factory, not a
-- new privileged-client pattern invented here.
--
-- Scope boundaries (disclosed, not silently narrowed, matching every prior checkpoint's
-- discipline):
--
-- * **"Send"/"resend" are one function, not two.** Calling `app.send_quotation_for_
--   acceptance` again while an active token already exists revokes it
--   (`superseded_by_resend`) and mints a fresh one -- safe to retry, never accumulates a
--   second live token (the partial unique index `quotation_acceptance_tokens_quotation_
--   active_unique` makes this database-enforced, not merely a convention). It is
--   deliberately **not** idempotent on a literal shared secret the way `app.request_
--   approval`'s `p_idempotency_key` is -- `PLT-129`'s own `app.api_keys` precedent already
--   established that a raw secret is returned exactly once and never replayed on a second
--   call; the alternative (storing the raw token so a retry could return the identical
--   value) would be a real credential-storage regression, not a convenience.
-- * **Token expiry is bound to the quotation's own `validity_to`**, never a separately
--   invented policy -- a token can never outlive the quote it grants a decision over.
--   Lazily flipped `active`→`expired` on read/decide, the exact mechanism `app.
--   authenticate_api_key` already established, not rediscovered.
-- * **No scheduled expiry/reminder job is dispatched.** `PLT-132`'s own Background Job
--   Framework has no live worker consuming `app.jobs` anywhere in this repository yet
--   (that migration's own disclosed boundary) -- lazy expiry-on-read is the real,
--   sufficient mechanism for this bounded slice, the same choice `PLT-129` already made
--   for API key expiry.
-- * **No email/SMTP delivery is dispatched.** No real notification provider is wired
--   anywhere in this repository (`PLT-130`'s own disclosed boundary: `app.notifications`
--   itself requires a real `auth.users` recipient, which a customer with no account does
--   not have). `app.send_quotation_for_acceptance` mints and returns the real, secure,
--   hashed-and-validated token/link; the seller is expected to relay it through their own
--   real-world channel (email/WhatsApp/etc.) until a real provider capability exists to
--   automate that -- disclosed, not silently faked.
-- * **No rate limiting / IP throttling on the public decision route.** No live deployment
--   or edge/gateway infrastructure exists yet anywhere in this repository (the same
--   disclosed boundary `PLT-129`'s own API-gateway-dependent `app.authenticate_api_key`
--   already carries) -- replay protection instead comes from the token's own atomic
--   single-use consumption (`update ... where status = 'active'`, the same "stale record
--   fails safely" pattern `PLT-123`'s own `app.decide_approval_step` already established),
--   which is real and proven, not a placeholder.
-- * **Customer identity is bearer-token possession, not a verified account.** No customer
--   login/account exists yet (`COM-155`). `decided_by_name`/`decided_by_title`/
--   `decided_by_email` are the customer's own typed attestation, captured as evidence
--   alongside `ip_address`/`user_agent` where the caller supplies them (best-effort,
--   lawful-basis-dependent, never fabricated) -- the same disclosed limitation every
--   magic-link-style flow carries until a real identity-verification step exists.
-- * Per `ERR-2026-004` (`docs/runtime/ERROR_LEDGER.md`): this migration carries its own
--   explicit `REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA app FROM PUBLIC` statement before
--   its final grants, the standing per-migration convention since `PLT-118`.
-- * **`search_path` on the two `SECURITY DEFINER` functions that call pgcrypto
--   (`app.send_quotation_for_acceptance`/`app.record_quotation_customer_decision`) is
--   `app, public, pg_temp`, not the usual bare `app, pg_temp`.** `pgcrypto` (`create
--   extension pgcrypto`, `PLT-105`) installs `gen_random_bytes()`/`digest()` into
--   `public`, and every table/function reference in this migration's own bodies is
--   already fully schema-qualified (`app.quotations`, etc.) -- so this is a real,
--   narrower-than-`PLT-129`'s-own-precedent restriction (`app.create_api_key` sets no
--   `search_path` override at all), not a regression of the `ERR-2026-004` discipline.



create table app.quotation_acceptance_tokens (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  quotation_id uuid not null references app.quotations (id),
  token_hash text not null,
  status text not null default 'active',
  channel text not null default 'email',
  recipient_contact_id uuid references app.contacts (id),
  recipient_email text,
  expires_at timestamptz not null,
  sent_at timestamptz not null default now(),
  sent_by text,
  revoked_at timestamptz,
  revoked_reason text,
  consumed_at timestamptz,
  created_by text,
  created_at timestamptz not null default now(),
  constraint quotation_acceptance_tokens_status_check check (status in ('active', 'consumed', 'revoked', 'expired')),
  constraint quotation_acceptance_tokens_channel_check check (channel in ('email', 'manual_link')),
  constraint quotation_acceptance_tokens_token_hash_unique unique (token_hash),
  constraint quotation_acceptance_tokens_revoked_reason_check check (status <> 'revoked' or revoked_reason is not null)
);

comment on table app.quotation_acceptance_tokens is
  'COM-154: one hashed, single-purpose bearer token per active send -- mirrors app.api_keys (PLT-129): token_hash is a one-way sha256 digest, the raw value is returned exactly once by app.send_quotation_for_acceptance() and never stored. At most one active row per quotation_id (quotation_acceptance_tokens_quotation_active_unique) -- sending again revokes the prior active token first.';

create unique index quotation_acceptance_tokens_quotation_active_unique on app.quotation_acceptance_tokens (quotation_id) where status = 'active';
create index quotation_acceptance_tokens_tenant_idx on app.quotation_acceptance_tokens (tenant_id);
create index quotation_acceptance_tokens_quotation_idx on app.quotation_acceptance_tokens (quotation_id);

-- Append-only decision evidence (Prompt 154 §24: "acceptance evidence cannot be
-- overwritten" for a normal role -- no update/delete RPC exists over this table for
-- `authenticated`, only service_role can touch it at all beyond the one insert path
-- below). unique(quotation_id) is the real "one final decision per exact version" gate
-- (Prompt 154 §13 "quote-version uniqueness constraint") -- a later revision
-- (`app.create_quotation_revision`, COM-152) is a brand-new quotation row/id, so it is
-- structurally a fresh decision opportunity, never a second decision on the same version.
create table app.quotation_customer_decisions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  quotation_id uuid not null references app.quotations (id),
  token_id uuid not null references app.quotation_acceptance_tokens (id),
  decision text not null,
  decided_by_name text not null,
  decided_by_title text,
  decided_by_email text,
  reason text,
  ip_address text,
  user_agent text,
  decided_at timestamptz not null default now(),
  constraint quotation_customer_decisions_decision_check check (decision in ('accepted', 'rejected')),
  constraint quotation_customer_decisions_reason_check check (decision <> 'rejected' or (reason is not null and length(trim(reason)) > 0)),
  constraint quotation_customer_decisions_name_check check (length(trim(decided_by_name)) > 0),
  constraint quotation_customer_decisions_quotation_unique unique (quotation_id)
);

comment on table app.quotation_customer_decisions is
  'COM-154: append-only, one row per quotation (version) -- the customer''s explicit accept/reject evidence. decided_by_name/title/email are the customer''s own typed attestation (bearer-token possession is the only authority in this bounded slice, no verified customer account exists yet); ip_address/user_agent are best-effort, supplied by the calling route where lawfully available, never fabricated.';

create index quotation_customer_decisions_tenant_idx on app.quotation_customer_decisions (tenant_id);

-- Second axis on the quotation header, independent of approval_status (COM-153) and
-- status (COM-151) -- the final customer outcome for this exact version.
alter table app.quotations
  add column customer_decision text,
  add column customer_decision_at timestamptz;

alter table app.quotations
  add constraint quotations_customer_decision_check check (customer_decision is null or customer_decision in ('accepted', 'rejected'));

comment on column app.quotations.customer_decision is
  'COM-154: synced by app.record_quotation_customer_decision once a decision is recorded -- app.quotation_customer_decisions remains the authoritative evidence row; this column is a denormalized read convenience for gating conversion eligibility (COM-155+).';

-- Authority mirrors app.submit_quotation''s own gate (COM:Edit + record access) -- sending
-- is an ordinary Commercial action on a record the actor can already reach, not a
-- separately-permissioned governance action.
create function app.check_quotation_send_authority(p_quotation app.quotations, p_actor_auth_user_id uuid)
returns boolean
language plpgsql
stable
as $$
declare
  v_decision app.rbac_decision;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_quotation.tenant_id, 'COM', 'Edit');
  if not (v_decision).allowed then
    return false;
  end if;
  return app.can_access_record(p_actor_auth_user_id, p_quotation.tenant_id, p_quotation.owner_user_id, app.lead_record_scope_org_unit_ids(p_quotation.org_unit_id), null);
end;
$$;

-- send/resend, one function (this migration''s own header). Requires status='submitted',
-- approval_status='approved' (or 'not_required'), is_current=true, and no customer
-- decision already recorded -- an already-decided quotation can never be re-sent for a
-- second decision on the same version.
create function app.send_quotation_for_acceptance(
  p_quotation_id uuid,
  p_recipient_contact_id uuid,
  p_channel text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns table (token_id uuid, raw_token text, expires_at timestamptz, quotation_id uuid)
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_quotation app.quotations;
  v_contact app.contacts;
  v_raw_token text;
  v_token_hash text;
  v_token app.quotation_acceptance_tokens;
  v_existing_active app.quotation_acceptance_tokens;
begin
  select * into v_quotation from app.quotations where id = p_quotation_id;
  if not found then
    raise exception 'quotation_not_found: %', p_quotation_id using errcode = 'no_data_found';
  end if;

  if not app.check_quotation_send_authority(v_quotation, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % cannot send quotation %', p_actor_auth_user_id, p_quotation_id
      using errcode = 'insufficient_privilege';
  end if;

  if not v_quotation.is_current then
    raise exception 'not_current_version: quotation % is a superseded version and cannot be sent', p_quotation_id
      using errcode = 'check_violation';
  end if;
  if v_quotation.status <> 'submitted' then
    raise exception 'quotation_not_acceptance_eligible: quotation % is % (must be submitted)', p_quotation_id, v_quotation.status
      using errcode = 'check_violation';
  end if;
  if v_quotation.approval_status not in ('approved', 'not_required') then
    raise exception 'quotation_not_acceptance_eligible: quotation % approval_status is % (must be approved or not_required)', p_quotation_id, v_quotation.approval_status
      using errcode = 'check_violation';
  end if;
  if exists (select 1 from app.quotation_customer_decisions d where d.quotation_id = p_quotation_id) then
    raise exception 'decision_already_recorded: quotation % already carries a final customer decision', p_quotation_id
      using errcode = 'check_violation';
  end if;
  if v_quotation.validity_to <= now() then
    raise exception 'quotation_validity_expired: quotation % validity_to % has already passed', p_quotation_id, v_quotation.validity_to
      using errcode = 'check_violation';
  end if;

  if p_recipient_contact_id is not null then
    select * into v_contact from app.contacts where id = p_recipient_contact_id;
    if not found or v_contact.tenant_id <> v_quotation.tenant_id then
      raise exception 'recipient_not_found: no contact % in tenant %', p_recipient_contact_id, v_quotation.tenant_id
        using errcode = 'no_data_found';
    end if;
  end if;

  if coalesce(p_channel, 'email') not in ('email', 'manual_link') then
    raise exception 'invalid_channel: % is not one of email/manual_link', p_channel using errcode = 'check_violation';
  end if;

  -- "Resend" is this same call again -- revoke the prior active token first (this
  -- migration's own header), never accumulating a second live token.
  select * into v_existing_active from app.quotation_acceptance_tokens t where t.quotation_id = p_quotation_id and t.status = 'active';
  if found then
    update app.quotation_acceptance_tokens set status = 'revoked', revoked_at = now(), revoked_reason = 'superseded_by_resend' where id = v_existing_active.id;
  end if;

  v_raw_token := encode(gen_random_bytes(32), 'hex');
  v_token_hash := encode(digest(v_raw_token, 'sha256'), 'hex');

  insert into app.quotation_acceptance_tokens (
    tenant_id, quotation_id, token_hash, channel, recipient_contact_id, recipient_email, expires_at, sent_by, created_by
  ) values (
    v_quotation.tenant_id, p_quotation_id, v_token_hash, coalesce(p_channel, 'email'), p_recipient_contact_id, v_contact.email, v_quotation.validity_to, p_actor_label, p_actor_label
  )
  returning * into v_token;

  perform app.capture_audit_event(
    v_quotation.tenant_id, p_actor_auth_user_id, p_actor_label, 'send_quotation_for_acceptance',
    'app.quotation_acceptance_tokens', v_token.id, 'success', null, null,
    jsonb_build_object('quotation_id', p_quotation_id, 'channel', v_token.channel, 'recipient_contact_id', p_recipient_contact_id, 'expires_at', v_token.expires_at)
  );

  return query select v_token.id, v_raw_token, v_token.expires_at, p_quotation_id;
end;
$$;

comment on function app.send_quotation_for_acceptance is
  'COM-154: mints (or re-mints, revoking any prior active token) a hashed single-use acceptance token for one submitted+approved+undecided quotation version. Returns the raw token exactly once -- app.api_keys'' own precedent (PLT-129), never stored or replayable.';

create function app.revoke_quotation_acceptance_token(
  p_token_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  p_reason text
)
returns app.quotation_acceptance_tokens
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_token app.quotation_acceptance_tokens;
  v_quotation app.quotations;
  v_updated app.quotation_acceptance_tokens;
begin
  select * into v_token from app.quotation_acceptance_tokens where id = p_token_id;
  if not found then
    raise exception 'token_not_found: no quotation acceptance token %', p_token_id using errcode = 'no_data_found';
  end if;
  select * into v_quotation from app.quotations where id = v_token.quotation_id;

  if not app.check_quotation_send_authority(v_quotation, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % cannot revoke a token for quotation %', p_actor_auth_user_id, v_token.quotation_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_token.status <> 'active' then
    raise exception 'token_not_active: token % is %, only an active token can be revoked', p_token_id, v_token.status
      using errcode = 'check_violation';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a revoke reason is required' using errcode = 'not_null_violation';
  end if;

  update app.quotation_acceptance_tokens set status = 'revoked', revoked_at = now(), revoked_reason = p_reason
  where id = p_token_id
  returning * into v_updated;

  perform app.capture_audit_event(
    v_quotation.tenant_id, p_actor_auth_user_id, p_actor_label, 'revoke_quotation_acceptance_token',
    'app.quotation_acceptance_tokens', v_updated.id, 'success', p_reason, to_jsonb(v_token), to_jsonb(v_updated)
  );

  return v_updated;
end;
$$;

-- The public, unauthenticated read path (Prompt 154 §15: "customer decision surface with
-- exact quote version, terms, expiry"). service_role-only (no auth.uid() exists for this
-- caller) -- lazily flips a past-expiry 'active' token to 'expired' before deciding,
-- mirroring app.authenticate_api_key exactly. Returns customer-safe fields only: never
-- cost_amount_snapshot/margin_pct_snapshot (Prompt 154 §26: "cost/margin never appears in
-- customer projection").
create function app.get_quotation_for_customer_decision(p_raw_token text)
returns table (
  token_status text,
  quotation_id uuid,
  quote_number text,
  customer_snapshot jsonb,
  currency text,
  validity_to timestamptz,
  terms jsonb,
  subtotal_amount numeric,
  discount_amount numeric,
  tax_amount numeric,
  total_amount numeric,
  already_decided boolean
)
language plpgsql
as $$
declare
  v_hash text;
  v_token app.quotation_acceptance_tokens;
  v_quotation app.quotations;
begin
  if p_raw_token is null or length(p_raw_token) = 0 then
    raise exception 'token_not_found: no token presented' using errcode = 'no_data_found';
  end if;

  v_hash := encode(digest(p_raw_token, 'sha256'), 'hex');
  select * into v_token from app.quotation_acceptance_tokens where token_hash = v_hash;
  if not found then
    raise exception 'token_not_found: presented token does not match any known token' using errcode = 'no_data_found';
  end if;

  if v_token.status = 'active' and v_token.expires_at <= now() then
    update app.quotation_acceptance_tokens set status = 'expired' where id = v_token.id;
    v_token.status := 'expired';
  end if;

  select * into v_quotation from app.quotations where id = v_token.quotation_id;

  return query
    select
      v_token.status,
      v_quotation.id,
      v_quotation.quote_number,
      v_quotation.customer_snapshot,
      v_quotation.currency,
      v_quotation.validity_to,
      v_quotation.terms,
      v_quotation.subtotal_amount,
      v_quotation.discount_amount,
      v_quotation.tax_amount,
      v_quotation.total_amount,
      exists (select 1 from app.quotation_customer_decisions d where d.quotation_id = v_quotation.id);
end;
$$;

comment on function app.get_quotation_for_customer_decision is
  'COM-154: the public token-consumption read. Never raises for an expired/revoked/consumed token (the caller renders the returned token_status as a real UI state, Prompt 154 §23 "expired/revoked/wrong version ... rejected safely") -- only a genuinely unknown token raises token_not_found.';

-- The public decision write (Prompt 154 §14: "scoped customer accept/reject operations").
-- Atomic single-use consumption (`update ... where status = 'active'`) is the real replay
-- guard -- a second concurrent decision attempt with the same token finds zero matching
-- rows and fails closed, the exact "stale record fails safely" pattern app.decide_
-- approval_step (PLT-123) already established.
create function app.record_quotation_customer_decision(
  p_raw_token text,
  p_decision text,
  p_decided_by_name text,
  p_decided_by_title text,
  p_decided_by_email text,
  p_reason text,
  p_ip_address text,
  p_user_agent text
)
returns app.quotations
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_hash text;
  v_token app.quotation_acceptance_tokens;
  v_quotation app.quotations;
  v_decision_row app.quotation_customer_decisions;
begin
  if p_decision not in ('accepted', 'rejected') then
    raise exception 'invalid_decision: % must be accepted or rejected', p_decision using errcode = 'check_violation';
  end if;
  if p_decided_by_name is null or length(trim(p_decided_by_name)) = 0 then
    raise exception 'decided_by_name_required: a name is required' using errcode = 'not_null_violation';
  end if;
  if p_decision = 'rejected' and (p_reason is null or length(trim(p_reason)) = 0) then
    raise exception 'reason_required: a reason is required to reject' using errcode = 'not_null_violation';
  end if;

  v_hash := encode(digest(coalesce(p_raw_token, ''), 'sha256'), 'hex');
  select * into v_token from app.quotation_acceptance_tokens where token_hash = v_hash;
  if not found then
    raise exception 'token_not_found: presented token does not match any known token' using errcode = 'no_data_found';
  end if;

  if v_token.status = 'active' and v_token.expires_at <= now() then
    update app.quotation_acceptance_tokens set status = 'expired' where id = v_token.id;
    v_token.status := 'expired';
  end if;
  if v_token.status = 'expired' then
    raise exception 'token_expired: token % has expired', v_token.id using errcode = 'check_violation';
  end if;
  if v_token.status = 'revoked' then
    raise exception 'token_revoked: token % has been revoked', v_token.id using errcode = 'check_violation';
  end if;
  if v_token.status = 'consumed' then
    raise exception 'token_already_consumed: token % has already recorded a decision', v_token.id using errcode = 'check_violation';
  end if;

  update app.quotation_acceptance_tokens set status = 'consumed', consumed_at = now()
  where id = v_token.id and status = 'active';
  if not found then
    raise exception 'token_not_active: token % changed concurrently, no longer active', v_token.id using errcode = 'check_violation';
  end if;

  select * into v_quotation from app.quotations where id = v_token.quotation_id;

  begin
    insert into app.quotation_customer_decisions (
      tenant_id, quotation_id, token_id, decision, decided_by_name, decided_by_title, decided_by_email, reason, ip_address, user_agent
    ) values (
      v_quotation.tenant_id, v_quotation.id, v_token.id, p_decision, p_decided_by_name, p_decided_by_title, p_decided_by_email, p_reason, p_ip_address, p_user_agent
    )
    returning * into v_decision_row;
  exception
    when unique_violation then
      raise exception 'decision_already_recorded: quotation % already carries a final customer decision', v_quotation.id
        using errcode = 'unique_violation';
  end;

  update app.quotations
  set customer_decision = p_decision, customer_decision_at = v_decision_row.decided_at, updated_at = now(), record_version = record_version + 1
  where id = v_quotation.id
  returning * into v_quotation;

  perform app.capture_audit_event(
    v_quotation.tenant_id, null, coalesce(p_decided_by_email, p_decided_by_name), 'record_quotation_customer_decision',
    'app.quotations', v_quotation.id, 'success', p_reason, null, jsonb_build_object('decision', p_decision, 'token_id', v_token.id)
  );

  return v_quotation;
end;
$$;

comment on function app.record_quotation_customer_decision is
  'COM-154: the one customer-facing decision write. actor_auth_user_id is null in its own audit event (this migration''s own header: bearer-token possession, no auth.users identity exists for a customer). Normal-role acceptance evidence is never overwritten -- app.quotation_customer_decisions carries no update/delete path for authenticated at all; RPD-022 (Supreme Admin absolute CRUD via service_role) remains disclosed, not newly implemented.';

-- Widens COM-153's app.quotations_directory -- appends the two new columns at the end.
-- Reason/status-like, never a dollar figure, visible to any record-scoped viewer
-- regardless of COM:View cost/selling price (the same established masking-independent
-- precedent).
create or replace view app.quotations_directory
as
select
  q.id,
  q.tenant_id,
  q.quote_number,
  q.opportunity_id,
  q.source_opportunity_version,
  q.prospect_id,
  q.contact_id,
  q.customer_snapshot,
  q.currency,
  q.validity_from,
  q.validity_to,
  q.terms,
  case when app.has_view_selling_price(q.tenant_id) then q.subtotal_amount else null end as subtotal_amount,
  case when app.has_view_selling_price(q.tenant_id) then q.discount_amount else null end as discount_amount,
  case when app.has_view_selling_price(q.tenant_id) then q.tax_amount else null end as tax_amount,
  case when app.has_view_selling_price(q.tenant_id) then q.total_amount else null end as total_amount,
  not app.has_view_selling_price(q.tenant_id) as sell_masked,
  q.status,
  q.cancel_reason,
  q.cloned_from_id,
  q.document_ref,
  q.submitted_at,
  q.submitted_by,
  q.owner_user_id,
  q.org_unit_id,
  q.record_version,
  q.created_by,
  q.created_at,
  q.updated_at,
  q.root_quotation_id,
  q.version_number,
  q.is_current,
  q.superseded_by_id,
  q.revision_reason,
  q.approval_status,
  q.approval_request_id,
  q.approval_rule_version_id,
  q.approval_required_reasons,
  q.customer_decision,
  q.customer_decision_at
from app.quotations q
where app.can_access_record(auth.uid(), q.tenant_id, q.owner_user_id, app.lead_record_scope_org_unit_ids(q.org_unit_id), null);

alter table app.quotation_acceptance_tokens enable row level security;
alter table app.quotation_customer_decisions enable row level security;

-- Normal tenant business data, direct RLS-scoped select for authenticated (mirrors
-- app.approval_requests, PLT-123) -- record-scoped through the owning quotation, since
-- neither table itself carries owner_user_id/org_unit_id.
create policy quotation_acceptance_tokens_select_scoped on app.quotation_acceptance_tokens
  for select to authenticated
  using (exists (
    select 1 from app.quotations q
    where q.id = quotation_acceptance_tokens.quotation_id
      and app.can_access_record(auth.uid(), q.tenant_id, q.owner_user_id, app.lead_record_scope_org_unit_ids(q.org_unit_id), null)
  ));

create policy quotation_customer_decisions_select_scoped on app.quotation_customer_decisions
  for select to authenticated
  using (exists (
    select 1 from app.quotations q
    where q.id = quotation_customer_decisions.quotation_id
      and app.can_access_record(auth.uid(), q.tenant_id, q.owner_user_id, app.lead_record_scope_org_unit_ids(q.org_unit_id), null)
  ));

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit, directly-provable revoke of
-- PostgreSQL's PUBLIC-execute default, the standing per-migration convention since
-- PLT-118, applied here before any role-specific grant.
revoke execute on all functions in schema app from public;

-- token_hash is never granted -- authenticated may see every other column of its own
-- tenant's tokens (status/expiry/channel/recipient), never the hash itself.
grant select (id, tenant_id, quotation_id, status, channel, recipient_contact_id, recipient_email, expires_at, sent_at, sent_by, revoked_at, revoked_reason, consumed_at, created_by, created_at) on app.quotation_acceptance_tokens to authenticated;
grant select, insert, update, delete on app.quotation_acceptance_tokens to service_role;
grant select on app.quotation_customer_decisions to authenticated, service_role;
grant insert, update, delete on app.quotation_customer_decisions to service_role;

grant execute on function app.check_quotation_send_authority(app.quotations, uuid) to service_role;
grant execute on function app.send_quotation_for_acceptance(uuid, uuid, text, uuid, text) to authenticated, service_role;
grant execute on function app.revoke_quotation_acceptance_token(uuid, uuid, text, text) to authenticated, service_role;
grant execute on function app.get_quotation_for_customer_decision(text) to service_role;
grant execute on function app.record_quotation_customer_decision(text, text, text, text, text, text, text, text) to service_role;
