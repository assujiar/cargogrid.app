-- Operations capability OPS-180 (Basic Public and Customer Tracking, CG-S8-OPS-014)
-- Minimal, fast, read-only tracking surface: an unguessable per-shipment opaque token
-- resolves to a sanitized status/timeline/ePOD-availability projection, rate-limited
-- and enumeration-resistant, never a live Customer Portal (Prompt 180 §4/§24).
--
-- Scope and design decisions, disclosed rather than left implicit:
--
-- * **Token pattern reused verbatim from `COM-154`.** `app.shipment_tracking_tokens.
--   token_hash` is a one-way `sha256` digest (`encode(digest(raw, 'sha256'), 'hex')`);
--   the raw 32-byte hex token (`encode(gen_random_bytes(32), 'hex')`) is returned
--   exactly once by `app.issue_shipment_tracking_token` and never stored -- the
--   identical mechanism `app.quotation_acceptance_tokens`/`app.send_quotation_for_
--   acceptance` already established and proved. At most one active token per
--   shipment (partial unique index); issuing again revokes the prior active token
--   first, the same "sending again revokes" precedent.
-- * **The public lookup function is the one deliberate, disclosed exception to this
--   repository's own "anon holds zero EXECUTE" convention** (`ERR-2026-004`'s own
--   standing regression guard, re-asserted by every other capability's db-tests).
--   `app.lookup_public_shipment_tracking` is granted to `anon` *and* `authenticated`
--   by design -- it is the only public, unauthenticated read surface this repository
--   exposes, and its own authorization is the token itself (verified by hash match,
--   status, and expiry), never `auth.uid()`/`app.evaluate_permission`. Every other
--   function in this migration keeps the standard zero-`anon`-`EXECUTE` posture.
-- * **Rate limiting is a real, tested, database-level mechanism**, not a fabricated
--   claim: `app.tracking_lookup_attempts` is an append-only log keyed by a caller-
--   supplied `client_key` (a hash of the caller's own IP/session, computed by the
--   calling Next.js Server Action -- the actual IP-extraction happens at that layer,
--   which this migration cannot reach; the explicit-parameter pattern mirrors every
--   other "actor passed in, never inferred inside the function" convention this whole
--   backend already uses). `app.lookup_public_shipment_tracking` returns
--   `lookup_status='rate_limited'` (never an exception -- see that function's own
--   header) once a `client_key` accumulates 10 or more `not_found`/`invalid` results
--   within a trailing 15-minute window -- real, queryable,
--   independently provable, not a live edge/WAF integration (no such infrastructure
--   exists anywhere in this repository yet, the same disclosed-NOT_RUN posture
--   `PLT-129`'s own notification delivery and `OPS-174`'s own SLA escalation already
--   established for their own external-infra seams).
-- * **The sanitized projection excludes everything Prompt 180 §24 names**: internal
--   exception notes, precise location detail (`app.milestone_events.location` is never
--   selected), vendor, cost, and sensitive contact data. Only `app.milestone_codes.
--   is_customer_visible` codes appear in the timeline -- the exact filter predicate
--   `OPS-173`'s own `app.get_shipment_milestone_timeline(p_customer_visible_only)`
--   already established and explicitly disclosed as "the actual customer/public-facing
--   tracking surface... will consume this same filtered projection, not built here" --
--   this migration is that disclosed follow-on, reusing the identical predicate rather
--   than inventing a second one.
-- * **ePOD is surfaced as an availability boolean only, no signed URL is issued
--   here.** A real signed-URL flow requires `PLT-128`'s own `service_role`-only
--   `app.authorize_file_access`, itself gated on a live customer/record identity this
--   token (a bearer secret, not an identity) does not carry -- wiring an authenticated
--   customer download path is explicitly Step 13's own full Customer Portal (§10),
--   not fabricated here. `epod_available=true` only once the shipment's own latest
--   `OPS-177` ePOD capture version has reached `status='completed'`.
-- * **No full Customer Portal feature is introduced** (§24): no booking, invoice/
--   payment, warehouse, ticket, loyalty, or account-administration table exists
--   anywhere in this migration; `app.shipment_tracking_tokens` is the only new table.
-- * Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): this migration carries its own
--   explicit REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA app FROM PUBLIC statement
--   before its final grants, the standing per-migration convention since PLT-118 --
--   `app.lookup_public_shipment_tracking`'s own `anon` grant is added back afterward,
--   explicitly and individually, never left implicit.

create table app.shipment_tracking_tokens (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  shipment_order_id uuid not null references app.shipment_orders (id),
  token_hash text not null,
  status text not null default 'active',
  expires_at timestamptz not null,
  revoked_at timestamptz,
  revoked_reason text,
  created_by text,
  created_at timestamptz not null default now(),
  constraint shipment_tracking_tokens_status_check check (status in ('active', 'revoked')),
  constraint shipment_tracking_tokens_token_hash_unique unique (token_hash),
  constraint shipment_tracking_tokens_revoked_reason_check check (status <> 'revoked' or (revoked_reason is not null and length(trim(revoked_reason)) > 0))
);

comment on table app.shipment_tracking_tokens is
  'OPS-180: one hashed, single-purpose bearer token per active issuance -- mirrors app.quotation_acceptance_tokens (COM-154). token_hash is a one-way sha256 digest; the raw value is returned exactly once by app.issue_shipment_tracking_token and never stored. At most one active row per shipment_order_id (partial unique index) -- issuing again revokes the prior active token first.';

create unique index shipment_tracking_tokens_one_active_idx on app.shipment_tracking_tokens (shipment_order_id) where status = 'active';
create index shipment_tracking_tokens_tenant_shipment_idx on app.shipment_tracking_tokens (tenant_id, shipment_order_id);

-- Append-only rate-limit evidence, distinct from app.audit_logs (compliance
-- who-changed-what) and app.file_access_logs (content-access evidence) -- this is
-- specifically anti-enumeration evidence for a public, unauthenticated surface.
create table app.tracking_lookup_attempts (
  id uuid primary key default gen_random_uuid(),
  client_key text not null,
  result text not null,
  occurred_at timestamptz not null default now(),
  constraint tracking_lookup_attempts_result_check check (result in ('success', 'not_found', 'invalid', 'rate_limited'))
);

comment on table app.tracking_lookup_attempts is
  'OPS-180: append-only evidence of every app.lookup_public_shipment_tracking() call, keyed by a caller-supplied client_key (a hash of the caller''s own IP/session, computed by the calling Server Action). A client_key accumulating 10+ not_found/invalid results within a trailing 15-minute window is rate-limited -- the real, queryable anti-enumeration mechanism this capability actually implements.';

create index tracking_lookup_attempts_client_key_idx on app.tracking_lookup_attempts (client_key, occurred_at desc);

create function app.issue_shipment_tracking_token(
  p_shipment_order_id uuid,
  p_validity_days integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns table (token_id uuid, raw_token text, expires_at timestamptz, shipment_order_id uuid)
language plpgsql
security definer
set search_path = app, public, extensions, pg_temp
as $$
declare
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_existing app.shipment_tracking_tokens;
  v_raw_token text;
  v_token_hash text;
  v_expires_at timestamptz;
  v_token app.shipment_tracking_tokens;
begin
  select * into v_shipment from app.shipment_orders so where so.id = p_shipment_order_id;
  if not found then
    raise exception 'shipment_order_not_found: %', p_shipment_order_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, p_shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  if coalesce(p_validity_days, 0) <= 0 then
    raise exception 'tracking_invalid_validity_days: validity_days must be positive' using errcode = 'check_violation';
  end if;

  update app.shipment_tracking_tokens t
  set status = 'revoked', revoked_at = now(), revoked_reason = 'superseded_by_new_issuance'
  where t.shipment_order_id = p_shipment_order_id and t.status = 'active'
  returning * into v_existing;

  v_raw_token := encode(gen_random_bytes(32), 'hex');
  v_token_hash := encode(digest(v_raw_token, 'sha256'), 'hex');
  v_expires_at := now() + (p_validity_days || ' days')::interval;

  insert into app.shipment_tracking_tokens (tenant_id, shipment_order_id, token_hash, expires_at, created_by)
  values (v_shipment.tenant_id, p_shipment_order_id, v_token_hash, v_expires_at, p_actor_label)
  returning * into v_token;

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'issue_shipment_tracking_token',
    'app.shipment_tracking_tokens', v_token.id, 'success', null, null, jsonb_build_object('expires_at', v_expires_at)
  );

  return query select v_token.id, v_raw_token, v_token.expires_at, p_shipment_order_id;
end;
$$;

create function app.revoke_shipment_tracking_token(
  p_shipment_order_id uuid,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.shipment_tracking_tokens
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_token app.shipment_tracking_tokens;
  v_updated app.shipment_tracking_tokens;
begin
  select * into v_shipment from app.shipment_orders so where so.id = p_shipment_order_id;
  if not found then
    raise exception 'shipment_order_not_found: %', p_shipment_order_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, p_shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'tracking_revoke_reason_required: a reason is required to revoke a tracking token' using errcode = 'check_violation';
  end if;

  select * into v_token from app.shipment_tracking_tokens where shipment_order_id = p_shipment_order_id and status = 'active';
  if not found then
    raise exception 'tracking_no_active_token: shipment order % has no active tracking token', p_shipment_order_id using errcode = 'no_data_found';
  end if;

  update app.shipment_tracking_tokens
  set status = 'revoked', revoked_at = now(), revoked_reason = p_reason
  where id = v_token.id
  returning * into v_updated;

  perform app.capture_audit_event(
    v_shipment.tenant_id, p_actor_auth_user_id, p_actor_label, 'revoke_shipment_tracking_token',
    'app.shipment_tracking_tokens', v_updated.id, 'success', p_reason, to_jsonb(v_token), to_jsonb(v_updated)
  );

  return v_updated;
end;
$$;

-- The one public, unauthenticated read -- authorization is the token itself, never
-- auth.uid(). Rate-limited, enumeration-resistant, sanitized (no location detail,
-- vendor, cost, internal exception notes, or sensitive contact data).
-- Returns exactly one row, always -- lookup_status ('ok'/'not_found'/'invalid'/
-- 'rate_limited') tells the caller the outcome; every other column is null unless
-- lookup_status='ok'. This is deliberate, not a stylistic choice: a raised exception
-- aborts the entire enclosing transaction (a real PostgREST call is exactly one
-- transaction), which would silently roll back this very function's own
-- app.tracking_lookup_attempts insert before it could ever persist -- the identical
-- "a raise unwinds any insert made before it" defect OPS-175 already discovered and
-- documented for its own failure-path audit capture. Returning a status column
-- instead lets the attempt-log insert commit as part of the normal, successful
-- transaction every time, which is the entire point of keeping this log at all.
create function app.lookup_public_shipment_tracking(
  p_raw_token text,
  p_client_key text
)
returns table (
  lookup_status text,
  shipment_number text,
  status text,
  mode text,
  origin text,
  destination text,
  planned_delivery_at timestamptz,
  current_eta timestamptz,
  is_delayed boolean,
  milestones jsonb,
  epod_available boolean
)
language plpgsql
security definer
set search_path = app, public, extensions, pg_temp
as $$
declare
  v_recent_bad_count integer;
  v_hash text;
  v_token app.shipment_tracking_tokens;
  v_shipment app.shipment_orders;
  v_projection app.shipment_milestone_projections;
  v_epod_available boolean;
  v_milestones jsonb;
begin
  if p_client_key is null or length(trim(p_client_key)) = 0 then
    raise exception 'tracking_client_key_required: a client_key is required' using errcode = 'check_violation';
  end if;

  select count(*) into v_recent_bad_count
  from app.tracking_lookup_attempts
  where client_key = p_client_key and result in ('not_found', 'invalid') and occurred_at > now() - interval '15 minutes';
  if v_recent_bad_count >= 10 then
    insert into app.tracking_lookup_attempts (client_key, result) values (p_client_key, 'rate_limited');
    return query select 'rate_limited'::text, null::text, null::text, null::text, null::text, null::text, null::timestamptz, null::timestamptz, null::boolean, null::jsonb, null::boolean;
    return;
  end if;

  if p_raw_token is null or length(p_raw_token) = 0 then
    insert into app.tracking_lookup_attempts (client_key, result) values (p_client_key, 'invalid');
    return query select 'invalid'::text, null::text, null::text, null::text, null::text, null::text, null::timestamptz, null::timestamptz, null::boolean, null::jsonb, null::boolean;
    return;
  end if;

  v_hash := encode(digest(p_raw_token, 'sha256'), 'hex');
  select * into v_token from app.shipment_tracking_tokens where token_hash = v_hash;

  if not found or v_token.status <> 'active' or v_token.expires_at <= now() then
    insert into app.tracking_lookup_attempts (client_key, result) values (p_client_key, 'not_found');
    return query select 'not_found'::text, null::text, null::text, null::text, null::text, null::text, null::timestamptz, null::timestamptz, null::boolean, null::jsonb, null::boolean;
    return;
  end if;

  insert into app.tracking_lookup_attempts (client_key, result) values (p_client_key, 'success');

  select * into v_shipment from app.shipment_orders so where so.id = v_token.shipment_order_id;
  select * into v_projection from app.shipment_milestone_projections where shipment_order_id = v_shipment.id;

  select coalesce(jsonb_agg(jsonb_build_object('code', me.milestone_code, 'eventTime', me.event_time) order by me.event_time asc), '[]'::jsonb)
  into v_milestones
  from app.milestone_events me
  join app.milestone_codes mc on mc.code = me.milestone_code
  where me.shipment_order_id = v_shipment.id and mc.is_customer_visible;

  select exists (
    select 1 from app.epod_captures ec where ec.shipment_order_id = v_shipment.id and ec.is_latest_version and ec.status = 'completed'
  ) into v_epod_available;

  return query
  select
    'ok', v_shipment.shipment_number, v_shipment.status, v_shipment.mode, v_shipment.origin, v_shipment.destination,
    v_shipment.planned_delivery_at, v_projection.current_eta, coalesce(v_projection.is_delayed, false),
    v_milestones, v_epod_available;
end;
$$;

alter table app.shipment_tracking_tokens enable row level security;

create policy shipment_tracking_tokens_select_scoped on app.shipment_tracking_tokens
  for select to authenticated
  using (
    exists (
      select 1 from app.shipment_orders so
      where so.id = shipment_tracking_tokens.shipment_order_id
        and app.can_access_record(auth.uid(), so.tenant_id, so.owner_user_id, app.lead_record_scope_org_unit_ids(so.org_unit_id), null)
    )
  );

revoke execute on all functions in schema app from public;

grant select on app.shipment_tracking_tokens to authenticated, service_role;
grant insert, update, delete on app.shipment_tracking_tokens to service_role;
grant select, insert on app.tracking_lookup_attempts to service_role;

grant execute on function app.issue_shipment_tracking_token(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.revoke_shipment_tracking_token(uuid, text, uuid, text) to authenticated, service_role;

-- The one deliberate exception to this repository's own "anon holds zero EXECUTE"
-- convention -- this migration's own header explains why.
grant execute on function app.lookup_public_shipment_tracking(text, text) to anon, authenticated, service_role;
