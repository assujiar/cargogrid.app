-- Platform Core capability PLT-129 (API Key and Webhook Primitives, CG-S6-PLT-026)
-- Tenant-scoped hashed API key lifecycle (create-once-display, rotate-with-overlap,
-- revoke, scope, expire) plus webhook endpoint/signed-delivery primitives (HMAC-SHA256
-- signing, timestamp-tolerance replay protection, retry/backoff/DLQ, consecutive-
-- failure auto-disable). Resolves `ADR-CAND-ARCH-018`'s signature/timestamp/auto-disable
-- sub-questions as `ADR-0011` (`docs/adr/ADR-0011-webhook-signature-and-auto-disable-thresholds.md`).
--
-- Scope and design decisions, disclosed rather than left implicit:
--
-- * **API key scopes can only narrow what the issuing actor's own role already holds,
--   never widen it** (`08_API_INTEGRATION_WORKSTREAM.md` line 106). A scope string is
--   shaped `<resource_module_code>:<action>` (e.g. `HRS:View personal data`), the exact
--   natural key `app.permissions` already uses (`PLT-111`) -- reused directly, not a
--   new taxonomy. `app.create_api_key()` calls `app.evaluate_permission()` (`PLT-112`)
--   for every requested scope and rejects the whole request if the actor is not
--   themself currently granted it -- composing the existing RBAC evaluator rather than
--   re-implementing a parallel authority check.
-- * **A raw API key is never stored.** Only `key_hash` (`digest(raw_key, 'sha256')`)
--   and `key_prefix` (the first 12 characters, safe to display in a list UI to help a
--   tenant identify which key is which) persist. The raw value is returned exactly once,
--   in `app.create_api_key()`/`app.rotate_api_key()`'s own return row -- structurally
--   impossible to redisplay later, since there is nothing plaintext left to redisplay.
-- * **Rotation is overlap-window-based** (`08_*.md` line 107: "Rotation = overlap
--   window"), not an instant cutover -- `app.rotate_api_key()` creates a fresh key and
--   bounds the old key's continued validity to a caller-supplied window (0 to 10080
--   minutes / 7 days; 0 means immediate revoke), never *extending* an already-sooner
--   expiry.
-- * **A webhook signing secret cannot be a one-way hash** (unlike an API key): HMAC
--   verification is symmetric, so the platform's own delivery worker needs the raw
--   secret to *compute* an outgoing signature, not merely to *compare against* a
--   presented value. `secret_value` is therefore stored directly, but the table itself
--   carries zero `authenticated` grant (`service_role` only) -- the tenant only ever
--   receives the raw value once, in `app.register_webhook_endpoint()`/
--   `app.rotate_webhook_secret()`'s own return row, the same "shown once" contract as
--   API keys, just implemented via access-control rather than one-way hashing (the
--   pragmatic reading of Prompt 129 §13's "secret refs" -- disclosed, not silently
--   assumed).
-- * **HMAC-SHA256 signing, a 5-minute timestamp tolerance, and a 10-consecutive-failure
--   auto-disable threshold** (`ADR-0011`, resolving `ADR-CAND-ARCH-018`'s signature/
--   timestamp/auto-disable sub-questions). `app.compute_webhook_signature()`/
--   `app.verify_webhook_signature()` are genuinely provable without any live HTTP call
--   -- HMAC computation is pure cryptographic computation, not network I/O -- reusing
--   `pgcrypto`'s `hmac()`/`digest()`/`gen_random_bytes()`, already unconditionally
--   enabled since `PLT-105` (`20260716075355_create_tenants.sql` line 19), zero new
--   extension dependency.
-- * **Webhook delivery itself is never real.** No live HTTP client exists anywhere in
--   this repository (disclosed `NOT_RUN`, the same class of constraint every prior
--   "no live provider" capability this session recorded). `app.record_webhook_delivery_attempt()`
--   is the real, tested, bounded adapter interface a future delivery worker would call
--   to report one HTTP attempt's outcome -- this migration never calls it against a
--   fabricated HTTP response itself.
-- * **A bounded, structural SSRF check, disclosed as partial.** `app.validate_webhook_url()`
--   requires `https://` and rejects a literal `localhost`/loopback/private/link-local
--   IPv4 or IPv6 host at *registration* time. No architecture document specifies SSRF
--   controls beyond Tech Arch's named dimension (confirmed absent from every
--   `docs/architecture/*.md` search this checkpoint performed) -- this is a reasoned,
--   disclosed construction, not a blueprint-sourced rule. It structurally cannot defend
--   against DNS-rebinding-based SSRF (a hostname that resolves to a private address only
--   *after* registration passes) since that requires a live DNS resolution at actual
--   delivery time, which belongs to the not-yet-built delivery worker, not this
--   migration's SQL-only validation.
-- * **A webhook *event type* is a Supreme-registered registry entry** (`app.webhook_event_types`),
--   the same registry-not-enum discipline `PLT-120`'s `app.register_master_type()`
--   established -- but unlike `PLT-124..128`'s definitions, it does NOT mint a
--   `app.config_types` entry, since there is no tenant-configurable *content* to version
--   here (an event type is just a subscribable code, not a definition with rules).
--   **Zero real domain event type is seeded** -- no business-domain table exists yet to
--   emit a real event from.
-- * **This entire capability is server-mediated only**, the same design `PLT-128`
--   established: every mutating function is `service_role`-only. Consequently none of
--   them needs `SECURITY DEFINER` except the two read-only listing functions
--   (`app.list_api_keys_for_tenant()`/`app.list_webhook_endpoints_for_tenant()`, granted
--   to `authenticated`), which need it to read `service_role`-only tables while
--   excluding the sensitive `key_hash`/`secret_value` columns from their result shape.
-- * **Scope boundary**: `rate_limit_per_minute` is a real, stored, bounded numeric field
--   on `app.api_keys`, but its *enforcement* against real inbound request volume is
--   disclosed `NOT_RUN` -- no live API gateway/request-rate-enforcement point exists
--   anywhere in this repository yet (Prompt 130, still `BLOCKED`). Inbound webhook
--   receiving (this platform receiving a webhook FROM an external provider,
--   `08_*.md` line 135's "Authenticate & Verify Signature → Check Idempotency" sequence)
--   is a different direction from this capability's outbound tenant-subscribed delivery
--   and is left to its own future owning task.
-- * Per `ERR-2026-004`: this migration carries its own explicit
--   `revoke execute on all functions in schema app from public;` before its final
--   grants.

create table app.api_keys (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  name text not null,
  key_prefix text not null,
  key_hash text not null,
  scopes jsonb not null,
  status text not null default 'active',
  rate_limit_per_minute integer,
  expires_at timestamptz,
  last_used_at timestamptz,
  created_by_auth_user_id uuid not null,
  revoked_at timestamptz,
  revoked_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint api_keys_status_check check (status in ('active', 'revoked', 'expired')),
  constraint api_keys_rate_limit_check check (rate_limit_per_minute is null or (rate_limit_per_minute > 0 and rate_limit_per_minute <= 100000)),
  constraint api_keys_revoked_reason_check check (status <> 'revoked' or revoked_reason is not null),
  constraint api_keys_key_hash_unique unique (key_hash)
);

comment on table app.api_keys is
  'PLT-129: tenant-scoped hashed API key metadata. key_hash is a one-way sha256 digest -- the raw key is never stored and is returned exactly once, by app.create_api_key()/app.rotate_api_key() themselves. scopes is a jsonb array of "<resource_module_code>:<action>" strings, each validated against the actor''s own currently-granted RBAC permissions at creation time (can only narrow, never widen).';

create index api_keys_tenant_id_idx on app.api_keys (tenant_id);

create function app.touch_api_keys_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger api_keys_touch_row
  before update on app.api_keys
  for each row
  execute function app.touch_api_keys_row();

-- The webhook event-type registry (kind, not rules) -- mirrors app.notification_types/
-- app.document_types in spirit, but mints no app.config_types entry (no versioned
-- definition content exists for a subscribable event code).
create table app.webhook_event_types (
  code text primary key,
  name text not null,
  owner_primitive_code text not null,
  registered_by text,
  created_at timestamptz not null default now()
);

comment on table app.webhook_event_types is
  'PLT-129: registry of subscribable webhook event codes (e.g. shipment.dispatched). Supreme-registered, idempotent. Zero real domain event type seeded -- no business-domain table exists yet in Phase 1 Platform Core to emit one from.';

create function app.register_webhook_event_type(
  p_code text,
  p_name text,
  p_owner_primitive_code text,
  p_actor_auth_user_id uuid,
  p_registered_by text
)
returns app.webhook_event_types
language plpgsql
as $$
declare
  v_existing app.webhook_event_types;
  v_type app.webhook_event_types;
begin
  if not app.is_supreme_admin(p_actor_auth_user_id) then
    raise exception 'insufficient_authority: only Supreme Admin may register a webhook event type'
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_existing from app.webhook_event_types where code = p_code;
  if found then
    return v_existing;
  end if;

  insert into app.webhook_event_types (code, name, owner_primitive_code, registered_by)
  values (p_code, p_name, p_owner_primitive_code, p_registered_by)
  returning * into v_type;

  perform app.capture_audit_event(
    null, p_actor_auth_user_id, p_registered_by, 'register_webhook_event_type',
    'app.webhook_event_types', null, 'success', null, null, to_jsonb(v_type)
  );

  return v_type;
end;
$$;

create table app.webhook_endpoints (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  url text not null,
  secret_value text not null,
  status text not null default 'active',
  consecutive_failure_count integer not null default 0,
  auto_disabled_at timestamptz,
  disabled_reason text,
  created_by_auth_user_id uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint webhook_endpoints_status_check check (status in ('active', 'disabled')),
  constraint webhook_endpoints_failure_count_check check (consecutive_failure_count >= 0)
);

comment on table app.webhook_endpoints is
  'PLT-129: a tenant-registered delivery target. secret_value is the raw HMAC-SHA256 signing secret, needed in retrievable form by the (not-yet-built) delivery worker -- unlike an API key, a signing secret cannot be a one-way hash. Zero authenticated grant on this table; the tenant receives the raw value exactly once via app.register_webhook_endpoint()/app.rotate_webhook_secret()''s own return row. Auto-disables at 10 consecutive delivery failures (ADR-0011).';

create index webhook_endpoints_tenant_id_idx on app.webhook_endpoints (tenant_id);

create function app.touch_webhook_endpoints_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger webhook_endpoints_touch_row
  before update on app.webhook_endpoints
  for each row
  execute function app.touch_webhook_endpoints_row();

create table app.webhook_subscriptions (
  id uuid primary key default gen_random_uuid(),
  webhook_endpoint_id uuid not null references app.webhook_endpoints (id),
  event_type_code text not null references app.webhook_event_types (code),
  created_at timestamptz not null default now(),
  constraint webhook_subscriptions_unique unique (webhook_endpoint_id, event_type_code)
);

create index webhook_subscriptions_event_type_idx on app.webhook_subscriptions (event_type_code);

create table app.webhook_deliveries (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  webhook_endpoint_id uuid not null references app.webhook_endpoints (id),
  event_type_code text not null,
  event_id uuid not null default gen_random_uuid(),
  payload jsonb not null,
  idempotency_key text not null,
  status text not null default 'pending',
  attempts integer not null default 0,
  max_attempts integer not null default 5,
  next_attempt_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint webhook_deliveries_status_check check (status in ('pending', 'delivered', 'dead_letter')),
  constraint webhook_deliveries_attempts_check check (attempts >= 0 and attempts <= max_attempts),
  constraint webhook_deliveries_max_attempts_check check (max_attempts > 0),
  constraint webhook_deliveries_idempotency_unique unique (tenant_id, webhook_endpoint_id, idempotency_key)
);

comment on table app.webhook_deliveries is
  'PLT-129: one row per event queued for a specific subscribed endpoint. payload is validated by app.validate_config_value() (PLT-121''s own structural/injection-safety gate, reused not reimplemented). The unique(tenant_id, webhook_endpoint_id, idempotency_key) constraint is the real "retry does not duplicate the effective consumer event" guarantee (Prompt 129 §25) -- a repeated app.queue_webhook_delivery() call for the same logical event returns the existing row.';

create index webhook_deliveries_endpoint_idx on app.webhook_deliveries (webhook_endpoint_id, created_at desc);
create index webhook_deliveries_pending_idx on app.webhook_deliveries (next_attempt_at) where status = 'pending';

create function app.touch_webhook_deliveries_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger webhook_deliveries_touch_row
  before update on app.webhook_deliveries
  for each row
  execute function app.touch_webhook_deliveries_row();

create table app.webhook_delivery_attempts (
  id uuid primary key default gen_random_uuid(),
  webhook_delivery_id uuid not null references app.webhook_deliveries (id),
  attempt_number integer not null,
  status text not null,
  http_status_code integer,
  error_message text,
  attempted_at timestamptz not null default now(),
  constraint webhook_delivery_attempts_status_check check (status in ('success', 'failed')),
  constraint webhook_delivery_attempts_unique unique (webhook_delivery_id, attempt_number)
);

comment on table app.webhook_delivery_attempts is
  'PLT-129: append-only per-attempt delivery evidence, mirroring app.notification_delivery_attempts (PLT-127)/app.file_access_logs (PLT-128)''s established "real, bounded adapter interface, never a fabricated call" pattern. http_status_code is real column shape for a real future delivery worker to populate -- always null in this migration''s own tests, since no live HTTP call is ever made here.';

-- Definition-admin-grade authority for managing keys/endpoints (Prompt 129 §26:
-- "Tenant Admin manages own allowed credentials/endpoints; Supreme controls global
-- policy") -- app.is_support_grant_authority() already composes exactly that (Supreme,
-- or the target tenant's own active tenant_admin), reused directly.
create function app.check_api_webhook_admin_authority(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns boolean
language sql
stable
as $$
  select app.is_support_grant_authority(p_actor_auth_user_id, p_tenant_id);
$$;

-- Instance-level authority for triggering a webhook delivery (any active tenant
-- member may cause an event, the same "instance-level" vs. "definition-admin" split
-- every prior engine this session established).
create function app.check_webhook_trigger_authority(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns boolean
language sql
stable
as $$
  select app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) or app.is_supreme_admin(p_actor_auth_user_id);
$$;

-- Rejects a scope shaped anything other than "<resource_module_code>:<action>", or one
-- the actor does not themself currently hold via app.evaluate_permission() (PLT-112) --
-- the "can only narrow, never widen" rule as a real, tested, database-enforced gate.
create function app.create_api_key(
  p_tenant_id uuid,
  p_name text,
  p_scopes jsonb,
  p_expires_at timestamptz,
  p_rate_limit_per_minute integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns table (
  id uuid, tenant_id uuid, name text, key_prefix text, scopes jsonb, status text,
  rate_limit_per_minute integer, expires_at timestamptz, created_at timestamptz, raw_key text
)
language plpgsql
as $$
declare
  v_scope text;
  v_colon_pos integer;
  v_module_code text;
  v_action text;
  v_decision app.rbac_decision;
  v_raw_key text;
  v_key_prefix text;
  v_key_hash text;
  v_key app.api_keys;
begin
  if not app.check_api_webhook_admin_authority(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks authority to manage API keys for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_name is null or length(trim(p_name)) = 0 then
    raise exception 'api_key_missing_name: name is required'
      using errcode = 'check_violation';
  end if;

  if p_scopes is null or jsonb_typeof(p_scopes) <> 'array' or jsonb_array_length(p_scopes) = 0 then
    raise exception 'api_key_missing_scopes: at least one scope is required'
      using errcode = 'check_violation';
  end if;

  for v_scope in select * from jsonb_array_elements_text(p_scopes) loop
    v_colon_pos := position(':' in v_scope);
    if v_colon_pos = 0 then
      raise exception 'api_key_invalid_scope_format: scope % must be shaped MODULE:action', v_scope
        using errcode = 'check_violation';
    end if;
    v_module_code := substring(v_scope from 1 for v_colon_pos - 1);
    v_action := substring(v_scope from v_colon_pos + 1);
    v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, v_module_code, v_action);
    if not (v_decision).allowed then
      raise exception 'api_key_scope_exceeds_actor_authority: actor does not currently hold % (reason %)', v_scope, (v_decision).reason
        using errcode = 'insufficient_privilege';
    end if;
  end loop;

  if p_rate_limit_per_minute is not null and (p_rate_limit_per_minute <= 0 or p_rate_limit_per_minute > 100000) then
    raise exception 'api_key_invalid_rate_limit: % must be between 1 and 100000', p_rate_limit_per_minute
      using errcode = 'check_violation';
  end if;

  if p_expires_at is not null and p_expires_at <= now() then
    raise exception 'api_key_invalid_expiry: expires_at % must be in the future', p_expires_at
      using errcode = 'check_violation';
  end if;

  v_raw_key := 'cgk_' || encode(gen_random_bytes(24), 'hex');
  v_key_prefix := substring(v_raw_key from 1 for 12);
  v_key_hash := encode(digest(v_raw_key, 'sha256'), 'hex');

  insert into app.api_keys (tenant_id, name, key_prefix, key_hash, scopes, rate_limit_per_minute, expires_at, created_by_auth_user_id)
  values (p_tenant_id, p_name, v_key_prefix, v_key_hash, p_scopes, p_rate_limit_per_minute, p_expires_at, p_actor_auth_user_id)
  returning * into v_key;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_api_key',
    'app.api_keys', v_key.id, 'success', null, null,
    jsonb_build_object('id', v_key.id, 'name', v_key.name, 'key_prefix', v_key.key_prefix, 'scopes', v_key.scopes, 'status', v_key.status)
  );

  return query select v_key.id, v_key.tenant_id, v_key.name, v_key.key_prefix, v_key.scopes, v_key.status, v_key.rate_limit_per_minute, v_key.expires_at, v_key.created_at, v_raw_key;
end;
$$;

-- Overlap-window rotation (Prompt 129 §22): the old key remains valid for at most
-- p_overlap_minutes longer (never extending an already-sooner expiry); 0 means
-- immediate revoke.
create function app.rotate_api_key(
  p_key_id uuid,
  p_overlap_minutes integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns table (
  id uuid, tenant_id uuid, name text, key_prefix text, scopes jsonb, status text,
  rate_limit_per_minute integer, expires_at timestamptz, created_at timestamptz, raw_key text
)
language plpgsql
as $$
declare
  v_old app.api_keys;
  v_new_raw_key text;
  v_new_key_prefix text;
  v_new_key_hash text;
  v_new_key app.api_keys;
  v_new_expiry timestamptz;
begin
  select * into v_old from app.api_keys where app.api_keys.id = p_key_id;
  if not found then
    raise exception 'api_key_not_found: no key %', p_key_id using errcode = 'no_data_found';
  end if;

  if not app.check_api_webhook_admin_authority(v_old.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks authority to manage API keys for tenant %', p_actor_auth_user_id, v_old.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_old.status <> 'active' then
    raise exception 'api_key_not_active: key % is %, only an active key may be rotated', p_key_id, v_old.status
      using errcode = 'check_violation';
  end if;

  if p_overlap_minutes is null or p_overlap_minutes < 0 or p_overlap_minutes > 10080 then
    raise exception 'api_key_invalid_overlap_minutes: % must be between 0 and 10080 (7 days)', p_overlap_minutes
      using errcode = 'check_violation';
  end if;

  v_new_raw_key := 'cgk_' || encode(gen_random_bytes(24), 'hex');
  v_new_key_prefix := substring(v_new_raw_key from 1 for 12);
  v_new_key_hash := encode(digest(v_new_raw_key, 'sha256'), 'hex');

  insert into app.api_keys (tenant_id, name, key_prefix, key_hash, scopes, rate_limit_per_minute, expires_at, created_by_auth_user_id)
  values (v_old.tenant_id, v_old.name, v_new_key_prefix, v_new_key_hash, v_old.scopes, v_old.rate_limit_per_minute, v_old.expires_at, p_actor_auth_user_id)
  returning * into v_new_key;

  v_new_expiry := now() + (p_overlap_minutes::text || ' minutes')::interval;

  update app.api_keys
  set status = case when p_overlap_minutes = 0 then 'revoked' else v_old.status end,
      revoked_at = case when p_overlap_minutes = 0 then now() else revoked_at end,
      revoked_reason = case when p_overlap_minutes = 0 then 'rotated' else revoked_reason end,
      expires_at = case when v_old.expires_at is not null and v_old.expires_at < v_new_expiry then v_old.expires_at else v_new_expiry end
  where app.api_keys.id = v_old.id;

  perform app.capture_audit_event(
    v_old.tenant_id, p_actor_auth_user_id, p_actor_label, 'rotate_api_key',
    'app.api_keys', v_new_key.id, 'success', null,
    jsonb_build_object('id', v_old.id, 'key_prefix', v_old.key_prefix),
    jsonb_build_object('id', v_new_key.id, 'key_prefix', v_new_key.key_prefix, 'overlap_minutes', p_overlap_minutes)
  );

  return query select v_new_key.id, v_new_key.tenant_id, v_new_key.name, v_new_key.key_prefix, v_new_key.scopes, v_new_key.status, v_new_key.rate_limit_per_minute, v_new_key.expires_at, v_new_key.created_at, v_new_raw_key;
end;
$$;

create function app.revoke_api_key(
  p_key_id uuid,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.api_keys
language plpgsql
as $$
declare
  v_key app.api_keys;
  v_updated app.api_keys;
begin
  select * into v_key from app.api_keys where id = p_key_id;
  if not found then
    raise exception 'api_key_not_found: no key %', p_key_id using errcode = 'no_data_found';
  end if;

  if not app.check_api_webhook_admin_authority(v_key.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks authority to manage API keys for tenant %', p_actor_auth_user_id, v_key.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_key.status = 'revoked' then
    return v_key;
  end if;

  update app.api_keys
  set status = 'revoked', revoked_at = now(), revoked_reason = coalesce(p_reason, 'manual revoke')
  where id = p_key_id
  returning * into v_updated;

  perform app.capture_audit_event(
    v_updated.tenant_id, p_actor_auth_user_id, p_actor_label, 'revoke_api_key',
    'app.api_keys', v_updated.id, 'success', p_reason,
    jsonb_build_object('id', v_key.id, 'status', v_key.status),
    jsonb_build_object('id', v_updated.id, 'status', v_updated.status)
  );

  return v_updated;
end;
$$;

-- The real authentication entry point a future API-gateway middleware would call
-- (disclosed NOT_RUN as a live HTTP consumer -- no such gateway exists yet, Prompt 130).
-- Lazily flips a past-expiry 'active' row to 'expired' before deciding, so status stays
-- eventually consistent rather than relying solely on a raw timestamp comparison.
create function app.authenticate_api_key(p_raw_key text)
returns table (api_key_id uuid, tenant_id uuid, scopes jsonb, rate_limit_per_minute integer)
language plpgsql
as $$
declare
  v_hash text;
  v_key app.api_keys;
begin
  if p_raw_key is null or length(p_raw_key) = 0 then
    raise exception 'api_key_not_found: no key presented' using errcode = 'no_data_found';
  end if;

  v_hash := encode(digest(p_raw_key, 'sha256'), 'hex');
  select * into v_key from app.api_keys where key_hash = v_hash;
  if not found then
    raise exception 'api_key_not_found: presented key does not match any known key' using errcode = 'no_data_found';
  end if;

  if v_key.status = 'active' and v_key.expires_at is not null and v_key.expires_at <= now() then
    update app.api_keys set status = 'expired' where id = v_key.id;
    v_key.status := 'expired';
  end if;

  if v_key.status = 'revoked' then
    raise exception 'api_key_revoked: key % has been revoked', v_key.id using errcode = 'insufficient_privilege';
  end if;
  if v_key.status = 'expired' then
    raise exception 'api_key_expired: key % has expired', v_key.id using errcode = 'insufficient_privilege';
  end if;

  update app.api_keys set last_used_at = now() where id = v_key.id;

  return query select v_key.id, v_key.tenant_id, v_key.scopes, v_key.rate_limit_per_minute;
end;
$$;

create function app.api_key_has_scope(p_api_key_id uuid, p_scope text)
returns boolean
language sql
stable
as $$
  select exists (
    select 1 from app.api_keys, jsonb_array_elements_text(scopes) as s(scope)
    where id = p_api_key_id and status = 'active' and s.scope = p_scope
  );
$$;

-- The authenticated-facing listing function -- SECURITY DEFINER since app.api_keys
-- itself carries zero authenticated grant, and excludes key_hash from its result shape
-- entirely (never selected, not merely omitted from a wider row).
create function app.list_api_keys_for_tenant(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns table (
  id uuid, tenant_id uuid, name text, key_prefix text, scopes jsonb, status text,
  rate_limit_per_minute integer, expires_at timestamptz, last_used_at timestamptz,
  created_at timestamptz, updated_at timestamptz
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
begin
  if not app.check_api_webhook_admin_authority(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks authority to view API keys for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
  select k.id, k.tenant_id, k.name, k.key_prefix, k.scopes, k.status, k.rate_limit_per_minute, k.expires_at, k.last_used_at, k.created_at, k.updated_at
  from app.api_keys k
  where k.tenant_id = p_tenant_id
  order by k.created_at desc;
end;
$$;

-- A real, bounded, structural SSRF check (this migration's own header discloses its
-- limits). Rejects non-https schemes and a literal localhost/loopback/private/
-- link-local IPv4/IPv6 host at registration time.
create function app.validate_webhook_url(p_url text)
returns boolean
language plpgsql
as $$
declare
  v_host text;
begin
  if p_url is null or p_url !~ '^https://' then
    raise exception 'webhook_invalid_url_scheme: url must start with https://'
      using errcode = 'check_violation';
  end if;

  v_host := substring(p_url from '^https://([^/:]+)');
  if v_host is null or length(v_host) = 0 or position('@' in v_host) > 0 then
    raise exception 'webhook_unsafe_url_host: url has no parseable host, or the host contains userinfo (@)'
      using errcode = 'check_violation';
  end if;

  if lower(v_host) = 'localhost'
     or v_host ~ '^127\.'
     or v_host ~ '^10\.'
     or v_host ~ '^172\.(1[6-9]|2[0-9]|3[0-1])\.'
     or v_host ~ '^192\.168\.'
     or v_host ~ '^169\.254\.'
     or v_host = '0.0.0.0'
     or v_host = '::1'
     or v_host ~* '^\[?f[cd][0-9a-f]{2}:'
  then
    raise exception 'webhook_unsafe_url_host: % resolves to a private/loopback/link-local literal, refusing to register', v_host
      using errcode = 'check_violation';
  end if;

  return true;
end;
$$;

create function app.register_webhook_endpoint(
  p_tenant_id uuid,
  p_url text,
  p_event_type_codes jsonb,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns table (
  id uuid, tenant_id uuid, url text, status text, consecutive_failure_count integer,
  created_at timestamptz, raw_secret text
)
language plpgsql
as $$
declare
  v_code text;
  v_raw_secret text;
  v_endpoint app.webhook_endpoints;
begin
  if not app.check_api_webhook_admin_authority(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks authority to manage webhook endpoints for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  perform app.validate_webhook_url(p_url);

  if p_event_type_codes is null or jsonb_typeof(p_event_type_codes) <> 'array' or jsonb_array_length(p_event_type_codes) = 0 then
    raise exception 'webhook_missing_event_types: at least one event_type_code is required'
      using errcode = 'check_violation';
  end if;
  for v_code in select * from jsonb_array_elements_text(p_event_type_codes) loop
    if not exists (select 1 from app.webhook_event_types where code = v_code) then
      raise exception 'webhook_unknown_event_type: % is not a registered event type', v_code
        using errcode = 'check_violation';
    end if;
  end loop;

  v_raw_secret := 'whsec_' || encode(gen_random_bytes(24), 'hex');

  insert into app.webhook_endpoints (tenant_id, url, secret_value, created_by_auth_user_id)
  values (p_tenant_id, p_url, v_raw_secret, p_actor_auth_user_id)
  returning * into v_endpoint;

  for v_code in select * from jsonb_array_elements_text(p_event_type_codes) loop
    insert into app.webhook_subscriptions (webhook_endpoint_id, event_type_code) values (v_endpoint.id, v_code);
  end loop;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'register_webhook_endpoint',
    'app.webhook_endpoints', v_endpoint.id, 'success', null, null,
    jsonb_build_object('id', v_endpoint.id, 'url', v_endpoint.url, 'status', v_endpoint.status, 'event_type_codes', p_event_type_codes)
  );

  return query select v_endpoint.id, v_endpoint.tenant_id, v_endpoint.url, v_endpoint.status, v_endpoint.consecutive_failure_count, v_endpoint.created_at, v_raw_secret;
end;
$$;

create function app.rotate_webhook_secret(
  p_endpoint_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns table (id uuid, tenant_id uuid, url text, status text, raw_secret text)
language plpgsql
as $$
declare
  v_endpoint app.webhook_endpoints;
  v_new_secret text;
  v_updated app.webhook_endpoints;
begin
  select * into v_endpoint from app.webhook_endpoints where app.webhook_endpoints.id = p_endpoint_id;
  if not found then
    raise exception 'webhook_endpoint_not_found: no endpoint %', p_endpoint_id using errcode = 'no_data_found';
  end if;

  if not app.check_api_webhook_admin_authority(v_endpoint.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks authority to manage webhook endpoints for tenant %', p_actor_auth_user_id, v_endpoint.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_new_secret := 'whsec_' || encode(gen_random_bytes(24), 'hex');

  update app.webhook_endpoints set secret_value = v_new_secret where app.webhook_endpoints.id = p_endpoint_id
  returning * into v_updated;

  perform app.capture_audit_event(
    v_updated.tenant_id, p_actor_auth_user_id, p_actor_label, 'rotate_webhook_secret',
    'app.webhook_endpoints', v_updated.id, 'success', null, null, jsonb_build_object('id', v_updated.id)
  );

  return query select v_updated.id, v_updated.tenant_id, v_updated.url, v_updated.status, v_new_secret;
end;
$$;

create function app.disable_webhook_endpoint(
  p_endpoint_id uuid,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.webhook_endpoints
language plpgsql
as $$
declare
  v_endpoint app.webhook_endpoints;
  v_updated app.webhook_endpoints;
begin
  select * into v_endpoint from app.webhook_endpoints where id = p_endpoint_id;
  if not found then
    raise exception 'webhook_endpoint_not_found: no endpoint %', p_endpoint_id using errcode = 'no_data_found';
  end if;

  if not app.check_api_webhook_admin_authority(v_endpoint.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks authority to manage webhook endpoints for tenant %', p_actor_auth_user_id, v_endpoint.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_endpoint.status = 'disabled' then
    return v_endpoint;
  end if;

  update app.webhook_endpoints
  set status = 'disabled', auto_disabled_at = now(), disabled_reason = coalesce(p_reason, 'manual disable')
  where id = p_endpoint_id
  returning * into v_updated;

  perform app.capture_audit_event(
    v_updated.tenant_id, p_actor_auth_user_id, p_actor_label, 'disable_webhook_endpoint',
    'app.webhook_endpoints', v_updated.id, 'success', p_reason,
    jsonb_build_object('status', v_endpoint.status), jsonb_build_object('status', v_updated.status)
  );

  return v_updated;
end;
$$;

-- Manual re-enable after a consecutive-failure auto-disable (or a manual disable) --
-- resets the failure counter, since the operator is asserting the endpoint is now
-- believed healthy.
create function app.reenable_webhook_endpoint(
  p_endpoint_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.webhook_endpoints
language plpgsql
as $$
declare
  v_endpoint app.webhook_endpoints;
  v_updated app.webhook_endpoints;
begin
  select * into v_endpoint from app.webhook_endpoints where id = p_endpoint_id;
  if not found then
    raise exception 'webhook_endpoint_not_found: no endpoint %', p_endpoint_id using errcode = 'no_data_found';
  end if;

  if not app.check_api_webhook_admin_authority(v_endpoint.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks authority to manage webhook endpoints for tenant %', p_actor_auth_user_id, v_endpoint.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  update app.webhook_endpoints
  set status = 'active', consecutive_failure_count = 0, auto_disabled_at = null, disabled_reason = null
  where id = p_endpoint_id
  returning * into v_updated;

  perform app.capture_audit_event(
    v_updated.tenant_id, p_actor_auth_user_id, p_actor_label, 'reenable_webhook_endpoint',
    'app.webhook_endpoints', v_updated.id, 'success', null,
    jsonb_build_object('status', v_endpoint.status), jsonb_build_object('status', v_updated.status)
  );

  return v_updated;
end;
$$;

create function app.list_webhook_endpoints_for_tenant(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns table (
  id uuid, tenant_id uuid, url text, status text, consecutive_failure_count integer,
  auto_disabled_at timestamptz, disabled_reason text, created_at timestamptz, updated_at timestamptz
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
begin
  if not app.check_api_webhook_admin_authority(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks authority to view webhook endpoints for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
  select e.id, e.tenant_id, e.url, e.status, e.consecutive_failure_count, e.auto_disabled_at, e.disabled_reason, e.created_at, e.updated_at
  from app.webhook_endpoints e
  where e.tenant_id = p_tenant_id
  order by e.created_at desc;
end;
$$;

-- Idempotent per (tenant, endpoint, idempotency_key) -- "retry does not duplicate the
-- effective consumer event" (§25). Publishing an event with zero subscribed endpoints
-- is normal, not an error -- returns an empty set.
create function app.queue_webhook_delivery(
  p_tenant_id uuid,
  p_event_type_code text,
  p_payload jsonb,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_triggered_by text
)
returns setof app.webhook_deliveries
language plpgsql
as $$
declare
  v_endpoint record;
  v_existing app.webhook_deliveries;
  v_delivery app.webhook_deliveries;
begin
  if not app.check_webhook_trigger_authority(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'webhook_actor_unauthorized: identity % lacks active membership in tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.validate_config_value(p_payload) then
    raise exception 'webhook_unsafe_payload: payload failed structural validation'
      using errcode = 'check_violation';
  end if;

  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'webhook_missing_idempotency_key: idempotency_key is required'
      using errcode = 'check_violation';
  end if;

  for v_endpoint in
    select we.id from app.webhook_endpoints we
    join app.webhook_subscriptions ws on ws.webhook_endpoint_id = we.id
    where we.tenant_id = p_tenant_id and we.status = 'active' and ws.event_type_code = p_event_type_code
  loop
    select * into v_existing
    from app.webhook_deliveries
    where tenant_id = p_tenant_id and webhook_endpoint_id = v_endpoint.id and idempotency_key = p_idempotency_key;

    if found then
      v_delivery := v_existing;
    else
      insert into app.webhook_deliveries (tenant_id, webhook_endpoint_id, event_type_code, payload, idempotency_key, next_attempt_at)
      values (p_tenant_id, v_endpoint.id, p_event_type_code, p_payload, p_idempotency_key, now())
      returning * into v_delivery;

      perform app.capture_audit_event(
        p_tenant_id, p_actor_auth_user_id, p_triggered_by, 'queue_webhook_delivery',
        'app.webhook_deliveries', v_delivery.id, 'success', null, null,
        jsonb_build_object('id', v_delivery.id, 'webhook_endpoint_id', v_delivery.webhook_endpoint_id, 'event_type_code', v_delivery.event_type_code)
      );
    end if;

    return next v_delivery;
  end loop;

  return;
end;
$$;

-- The bounded delivery adapter interface (this migration's own header) -- real, tested,
-- never calls a live HTTP endpoint itself. Applies the audit_logs.result 'success'/
-- 'failure' mapping proactively (the exact bug class PLT-127 found the hard way).
-- Exponential backoff on a transient failure; dead_letter once max_attempts is reached;
-- the endpoint auto-disables at 10 consecutive failures (ADR-0011), and a single
-- success resets that counter to zero.
create function app.record_webhook_delivery_attempt(
  p_delivery_id uuid,
  p_status text,
  p_http_status_code integer,
  p_error_message text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.webhook_deliveries
language plpgsql
as $$
declare
  v_delivery app.webhook_deliveries;
  v_endpoint app.webhook_endpoints;
  v_attempt_number integer;
  v_updated app.webhook_deliveries;
  v_new_failure_count integer;
begin
  select * into v_delivery from app.webhook_deliveries where id = p_delivery_id;
  if not found then
    raise exception 'webhook_delivery_not_found: no delivery %', p_delivery_id using errcode = 'no_data_found';
  end if;

  if v_delivery.status in ('delivered', 'dead_letter') then
    raise exception 'webhook_delivery_already_terminal: delivery % is already %, no further attempts may be recorded', p_delivery_id, v_delivery.status
      using errcode = 'check_violation';
  end if;

  if not (p_status = any (array['success', 'failed'])) then
    raise exception 'webhook_invalid_attempt_status: % is not one of success/failed', p_status
      using errcode = 'check_violation';
  end if;

  select * into v_endpoint from app.webhook_endpoints where id = v_delivery.webhook_endpoint_id;

  v_attempt_number := v_delivery.attempts + 1;

  insert into app.webhook_delivery_attempts (webhook_delivery_id, attempt_number, status, http_status_code, error_message)
  values (p_delivery_id, v_attempt_number, p_status, p_http_status_code, p_error_message);

  if p_status = 'success' then
    update app.webhook_deliveries
    set attempts = v_attempt_number, status = 'delivered', next_attempt_at = null
    where id = p_delivery_id
    returning * into v_updated;

    update app.webhook_endpoints set consecutive_failure_count = 0 where id = v_endpoint.id;
  else
    v_new_failure_count := v_endpoint.consecutive_failure_count + 1;

    update app.webhook_deliveries
    set attempts = v_attempt_number,
        status = case when v_attempt_number >= v_delivery.max_attempts then 'dead_letter' else v_delivery.status end,
        next_attempt_at = case when v_attempt_number >= v_delivery.max_attempts then null else now() + (power(2, v_attempt_number)::text || ' minutes')::interval end
    where id = p_delivery_id
    returning * into v_updated;

    update app.webhook_endpoints
    set consecutive_failure_count = v_new_failure_count,
        status = case when v_new_failure_count >= 10 then 'disabled' else v_endpoint.status end,
        auto_disabled_at = case when v_new_failure_count >= 10 and v_endpoint.status <> 'disabled' then now() else auto_disabled_at end,
        disabled_reason = case when v_new_failure_count >= 10 and v_endpoint.status <> 'disabled' then 'consecutive_failure_threshold_exceeded' else disabled_reason end
    where id = v_endpoint.id;
  end if;

  perform app.capture_audit_event(
    v_delivery.tenant_id, p_actor_auth_user_id, p_actor_label, 'record_webhook_delivery_attempt',
    'app.webhook_deliveries', v_updated.id,
    case when p_status = 'success' then 'success' else 'failure' end,
    p_error_message, to_jsonb(v_delivery), to_jsonb(v_updated)
  );

  return v_updated;
end;
$$;

-- ADR-0011: HMAC-SHA256 over "<unix_timestamp>.<payload>" -- genuinely provable
-- without any live HTTP call, since this is pure cryptographic computation.
create function app.compute_webhook_signature(p_endpoint_id uuid, p_payload text, p_timestamp bigint)
returns text
language plpgsql
as $$
declare
  v_secret text;
  v_signed_payload text;
begin
  select secret_value into v_secret from app.webhook_endpoints where id = p_endpoint_id;
  if v_secret is null then
    raise exception 'webhook_endpoint_not_found: no endpoint %', p_endpoint_id using errcode = 'no_data_found';
  end if;

  v_signed_payload := p_timestamp::text || '.' || p_payload;
  return encode(hmac(v_signed_payload, v_secret, 'sha256'), 'hex');
end;
$$;

-- ADR-0011: recomputes and compares, plus the 5-minute timestamp-tolerance replay
-- check. A tampered payload or a stale/future timestamp both fail closed to false,
-- never raising -- the caller (a real delivery worker, or a receiver's own reference
-- implementation) decides what a false result means for its own flow.
create function app.verify_webhook_signature(p_endpoint_id uuid, p_payload text, p_timestamp bigint, p_signature text)
returns boolean
language plpgsql
as $$
declare
  v_expected text;
begin
  if abs(extract(epoch from now()) - p_timestamp) > 300 then
    return false;
  end if;

  v_expected := app.compute_webhook_signature(p_endpoint_id, p_payload, p_timestamp);
  return v_expected = p_signature;
end;
$$;

-- RLS. app.webhook_event_types is a broadly readable registry (mirrors
-- app.document_types/app.notification_types). Every other table here carries zero
-- authenticated grant at all -- api_keys/webhook_endpoints hold credentials/secrets,
-- webhook_subscriptions/deliveries/delivery_attempts are operational data with no live
-- UI consumer yet (Prompt 129 §15: "Admin view models... later") -- so RLS is not
-- enabled on them at all, matching app.notification_delivery_attempts' (PLT-127)
-- precedent that schema-privilege absence alone is sufficient defense in depth when no
-- authenticated grant exists whatsoever.
alter table app.webhook_event_types enable row level security;

create policy webhook_event_types_select_all on app.webhook_event_types
for select to authenticated
using (true);

revoke execute on all functions in schema app from public;

grant select on app.webhook_event_types to authenticated, service_role;
grant insert, update, delete on app.webhook_event_types to service_role;

grant select, insert, update, delete on app.api_keys to service_role;
grant select, insert, update, delete on app.webhook_endpoints to service_role;
grant select, insert, update, delete on app.webhook_subscriptions to service_role;
grant select, insert, update, delete on app.webhook_deliveries to service_role;
grant select, insert, update, delete on app.webhook_delivery_attempts to service_role;

grant execute on function app.check_api_webhook_admin_authority(uuid, uuid) to service_role;
grant execute on function app.check_webhook_trigger_authority(uuid, uuid) to service_role;
grant execute on function app.create_api_key(uuid, text, jsonb, timestamptz, integer, uuid, text) to service_role;
grant execute on function app.rotate_api_key(uuid, integer, uuid, text) to service_role;
grant execute on function app.revoke_api_key(uuid, text, uuid, text) to service_role;
grant execute on function app.authenticate_api_key(text) to service_role;
grant execute on function app.api_key_has_scope(uuid, text) to service_role;
grant execute on function app.list_api_keys_for_tenant(uuid, uuid) to authenticated, service_role;
grant execute on function app.register_webhook_event_type(text, text, text, uuid, text) to service_role;
grant execute on function app.validate_webhook_url(text) to service_role;
grant execute on function app.register_webhook_endpoint(uuid, text, jsonb, uuid, text) to service_role;
grant execute on function app.rotate_webhook_secret(uuid, uuid, text) to service_role;
grant execute on function app.disable_webhook_endpoint(uuid, text, uuid, text) to service_role;
grant execute on function app.reenable_webhook_endpoint(uuid, uuid, text) to service_role;
grant execute on function app.list_webhook_endpoints_for_tenant(uuid, uuid) to authenticated, service_role;
grant execute on function app.queue_webhook_delivery(uuid, text, jsonb, text, uuid, text) to service_role;
grant execute on function app.record_webhook_delivery_attempt(uuid, text, integer, text, uuid, text) to service_role;
grant execute on function app.compute_webhook_signature(uuid, text, bigint) to service_role;
grant execute on function app.verify_webhook_signature(uuid, text, bigint, text) to service_role;
