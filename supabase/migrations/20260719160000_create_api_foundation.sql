-- Platform Core capability PLT-130 (REST and GraphQL Platform API Foundation, CG-S6-PLT-027)
-- The shared foundation both REST and GraphQL interfaces sit on top of: a canonical
-- per-request observability record (`app.api_logs`), and (in `server/policies/` --
-- see that directory's own files) the composed 8-stage access-evaluation pipeline,
-- pagination bounds, and GraphQL depth/complexity limiter (`ADR-0012`, resolving
-- `ADR-CAND-ARCH-017`'s numeric-limit sub-question) neither interface may bypass.
--
-- Scope and design decisions, disclosed rather than left implicit:
--
-- * **No live HTTP route or GraphQL server exists anywhere in this repository.**
--   `08_API_INTEGRATION_WORKSTREAM.md` line 11 states this outright: "zero API route,
--   zero GraphQL schema." Per that same document's own atomic backlog (§15, line
--   242-245), the actual `app/api/v1/**` route scaffold and the actual schema-first
--   GraphQL server are two SEPARATE, LATER atomic slices ("REST v1 root..." and
--   "GraphQL foundation..." respectively) that both explicitly depend on THIS
--   checkpoint's own slice ("API/webhook/job foundation"). Building live routes here
--   would therefore be scope creep beyond what this specific prompt owns, not merely
--   an environment limitation -- this checkpoint's own deliverable is the shared
--   context/error/pagination/idempotency/correlation contract layer plus the
--   depth/complexity scoring algorithm, both real and fully tested without any live
--   server, the same "algorithm real, live wiring disclosed NOT_RUN" pattern
--   `ADR-0011`'s HMAC signing established.
-- * **`app.api_logs` is the canonical per-request observability record** -- one of the
--   five distinct append-only tables `05_DATABASE_SCHEMA_WORKSTREAM.md` §6 names
--   (`audit_logs`, `event_logs`, `api_logs`, `file_access_logs`, `support_access_logs`),
--   the only one of the five not yet built before this checkpoint (`audit_logs` at
--   `PLT-116`, `file_access_logs` at `PLT-128`, `support_access_events` at `PLT-115`;
--   `event_logs` remains deliberately deferred -- it serves the outbox-pattern role for
--   async job/webhook dispatch per that same section, which belongs to the not-yet-built
--   Background Job Framework, Prompt 132, not to per-request API observability). It does
--   NOT also write to `app.audit_logs` for the same event -- the five-table split exists
--   precisely so each event class has one canonical home, not several competing ones.
-- * **`actor_type`/`api_key_id` map all four principal layers plus API-key/service
--   identities onto one row shape** (Prompt 130 §26: "All four layers/API keys/service
--   identities mapped per operation"), composing `PLT-129`'s own `app.api_keys` via a
--   plain FK rather than duplicating key metadata.
-- * **No read/list function is built for `app.api_logs` this checkpoint** -- Prompt 130
--   §15 itself scopes UI/UX to "typed clients/contracts only... no feature pages," and
--   no admin-observability surface exists yet to consume one; deferred to whichever
--   future capability builds that surface, disclosed rather than built speculatively.
-- * Per `ERR-2026-004`: this migration carries its own explicit
--   `revoke execute on all functions in schema app from public;` before its final
--   grants.

create table app.api_logs (
  id uuid primary key default gen_random_uuid(),
  correlation_id uuid not null,
  tenant_id uuid references app.tenants (id),
  actor_auth_user_id uuid references auth.users (id),
  actor_type text not null,
  api_key_id uuid references app.api_keys (id),
  interface text not null,
  operation text not null,
  http_method text,
  path text,
  graphql_operation_name text,
  status_code integer,
  result text not null,
  error_code text,
  idempotency_key text,
  duration_ms integer,
  created_at timestamptz not null default now(),
  constraint api_logs_actor_type_check check (actor_type in ('user', 'api_key', 'service_role', 'anon')),
  constraint api_logs_interface_check check (interface in ('rest', 'graphql')),
  constraint api_logs_result_check check (result in ('success', 'failure')),
  constraint api_logs_actor_shape_check check (
    (actor_type = 'api_key' and api_key_id is not null)
    or (actor_type = 'user' and actor_auth_user_id is not null)
    or (actor_type in ('service_role', 'anon'))
  ),
  constraint api_logs_interface_fields_check check (
    (interface = 'rest' and graphql_operation_name is null)
    or (interface = 'graphql' and http_method is null and path is null)
  )
);

comment on table app.api_logs is
  'PLT-130: the canonical per-request API observability record -- one of the five distinct append-only tables 05_DATABASE_SCHEMA_WORKSTREAM.md §6 names. correlation_id is the same value a request''s X-CargoGrid-Request-Id header carries (08_API_INTEGRATION_WORKSTREAM.md §9) and that this repository''s other capabilities'' app.capture_audit_event() calls thread through as their own p_correlation_id, so one request''s full downstream effect is traceable across tables. No live HTTP/GraphQL server exists yet to populate this table for real (disclosed NOT_RUN) -- app.record_api_request() is the real, tested adapter interface a future request-handling middleware would call exactly once per request.';

create index api_logs_correlation_id_idx on app.api_logs (correlation_id);
create index api_logs_tenant_created_idx on app.api_logs (tenant_id, created_at desc);

-- The bounded adapter interface (this migration's own header) -- real, tested, never
-- called against a fabricated live request itself.
create function app.record_api_request(
  p_correlation_id uuid,
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_type text,
  p_api_key_id uuid,
  p_interface text,
  p_operation text,
  p_http_method text,
  p_path text,
  p_graphql_operation_name text,
  p_status_code integer,
  p_result text,
  p_error_code text,
  p_idempotency_key text,
  p_duration_ms integer
)
returns app.api_logs
language plpgsql
as $$
declare
  v_log app.api_logs;
begin
  if not (p_actor_type = any (array['user', 'api_key', 'service_role', 'anon'])) then
    raise exception 'api_log_invalid_actor_type: % is not one of user/api_key/service_role/anon', p_actor_type
      using errcode = 'check_violation';
  end if;

  if not (p_interface = any (array['rest', 'graphql'])) then
    raise exception 'api_log_invalid_interface: % is not one of rest/graphql', p_interface
      using errcode = 'check_violation';
  end if;

  if not (p_result = any (array['success', 'failure'])) then
    raise exception 'api_log_invalid_result: % is not one of success/failure', p_result
      using errcode = 'check_violation';
  end if;

  insert into app.api_logs (
    correlation_id, tenant_id, actor_auth_user_id, actor_type, api_key_id, interface,
    operation, http_method, path, graphql_operation_name, status_code, result,
    error_code, idempotency_key, duration_ms
  ) values (
    p_correlation_id, p_tenant_id, p_actor_auth_user_id, p_actor_type, p_api_key_id, p_interface,
    p_operation, p_http_method, p_path, p_graphql_operation_name, p_status_code, p_result,
    p_error_code, p_idempotency_key, p_duration_ms
  )
  returning * into v_log;

  return v_log;
end;
$$;

revoke execute on all functions in schema app from public;

grant select, insert, update, delete on app.api_logs to service_role;
grant execute on function app.record_api_request(uuid, uuid, uuid, text, uuid, text, text, text, text, text, integer, text, text, text, integer) to service_role;
