-- HDN-387 (Step 15, Prompt 387, Release Blocker Triage and Remediation) -- bounded
-- repairs selected from `docs/build-log/full-system-hardening/BLOCKER_LEDGER.md`'s own
-- open backlog after full triage. Per this checkpoint's own charter: "select bounded
-- critical/high repairs... implement with regression tests... escalate unresolved
-- blockers with exact no-go rationale." Everything fixed below is bounded, mechanical,
-- and reuses an already-proven pattern already live in this codebase. The much larger
-- design-decision items (`HDN-BLK-003/004/016/017/018/024/`, the ~35-table remainder of
-- `HDN-BLK-022`, and the ~70-table remainder of `HDN-BLK-018`) remain deliberately
-- untouched and registered, per the identical mechanical-fix-vs-genuine-design-decision
-- judgment this session has applied throughout Step 15.

-- ===========================================================================
-- Part 1: `HDN-BLK-023` (Critical) -- `app.set_integration_connection_status`
-- independently bypasses the SSO-specific wrapper's own IP-restriction/lockout/step-up-
-- MFA protections via a direct call. The ONLY Critical-severity finding open anywhere in
-- Step 15; per `00_EXECUTION_INDEX.md` §8.2 condition 1, a Critical can never be an
-- accepted exception -- it must be fixed or remain an active Step 16 blocker.
--
-- Two prior checkpoints (`HDN-386`'s own first round and Tier C review) investigated
-- and declined to fix this, judging the required audit ("does any OTHER connection type
-- have an equivalent specialized wrapper this same generic function also bypasses?")
-- open-ended. This checkpoint re-ran that exact audit: grepped every integration
-- migration for a call to `app.set_integration_connection_status` and, separately, for
-- the step-up-MFA/IP-restriction/lockout-guard pattern in every non-SSO integration
-- file. Zero hits outside the SSO-specific files
-- (`20260807000000_create_intelligence_enterprise_iam_sso.sql`,
-- `20260809200000_harden_intelligence_iae039_closure_step_up_wiring.sql`,
-- `20260815000000_harden_ip_restriction_iss150_closure_wiring.sql`).
-- `app.activate_enterprise_idp_connection` is the ONLY specialized activation wrapper
-- that exists anywhere in this schema -- the "audit every other type" scope that made
-- this look unbounded was actually a closed, single-item list all along.
--
-- Fix mirrors an already-proven precedent in this exact codebase:
-- `app.request_gps_device_status_transition`
-- (`20260730420000_harden_gps_device_installation_evidence_gate.sql`, ATW-031,
-- `ISS-2026-028`) -- "a flag is only as strong as the caller's inability to set it; a
-- revoked grant is enforced by Postgres itself." `app.set_integration_connection_status`
-- keeps its full, unmodified status machine and becomes a shared INTERNAL core: its
-- `authenticated`/`service_role` EXECUTE grants are revoked. A new entry point,
-- `app.request_integration_connection_status_change`, carries the grant instead, and
-- refuses `p_status='active'` for either SSO adapter code outright, directing the
-- caller to the specialized wrapper. `app.activate_enterprise_idp_connection` is
-- `SECURITY DEFINER`, owned by the same role as the core, so it is completely
-- unaffected by the grant revocation and continues calling the core directly, unchanged.
--
-- Contract note: `server/mutations/integration-hub.ts`'s `setIntegrationConnectionStatus`
-- is repointed to the new entry point in this same checkpoint. `app.set_integration_
-- connection_status` itself is NOT dropped and its signature is NOT changed -- additive,
-- expand-and-contract-safe, not a breaking rename.
-- ===========================================================================

create or replace function app.request_integration_connection_status_change(
  p_connection_id uuid,
  p_status text,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.integration_connections
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_adapter_code text;
begin
  select adapter_code into v_adapter_code from app.integration_connections where id = p_connection_id;
  if not found then
    raise exception 'integration_connection_not_found: %', p_connection_id using errcode = 'no_data_found';
  end if;

  -- HDN-387 (ISS-2026-235, HDN-BLK-023): the ONE transition this generic entry point
  -- must never perform for these two adapter codes. Reactivating an enterprise SSO
  -- connection is IP-restriction/lockout-guard/step-up-MFA-mandatory and belongs
  -- exclusively to app.activate_enterprise_idp_connection (IAE-026, CG-S14-IAE-039,
  -- HDN-378). Before this gate, any caller holding only INTHUB:Configure could reach
  -- 'active' for an SSO connection with none of that -- live-forced at HDN-378's own
  -- Tier C attack-surface adversarial testing lens.
  if p_status = 'active' and v_adapter_code in ('enterprise_sso_oidc', 'enterprise_sso_saml') then
    raise exception 'enterprise_sso_activation_requires_specialized_wrapper: connection % (adapter %) cannot be activated through the generic status-change entry point -- use app.activate_enterprise_idp_connection, which enforces the lockout guard, step-up-MFA and IP-restriction this connection type requires', p_connection_id, v_adapter_code
      using errcode = 'insufficient_privilege';
  end if;

  return app.set_integration_connection_status(p_connection_id, p_status, p_reason, p_actor_auth_user_id, p_actor_label);
end;
$$;

comment on function app.request_integration_connection_status_change is
  'HDN-387 (Release Blocker Triage and Remediation, closing HDN-BLK-023, Critical): the ONLY integration-connection status-change entry point granted to authenticated. Refuses p_status=''active'' for enterprise_sso_oidc/enterprise_sso_saml adapter codes (enterprise_sso_activation_requires_specialized_wrapper) -- that transition is protection-mandatory (IP-restriction, lockout guard, step-up-MFA) and belongs exclusively to app.activate_enterprise_idp_connection. Every other transition, and every other adapter type, delegates to app.set_integration_connection_status (IAE-008) unchanged. Mirrors app.request_gps_device_status_transition''s own already-proven pattern (ATW-031, ISS-2026-028) exactly.';

comment on function app.set_integration_connection_status is
  'IAE-008: INTHUB:Configure-gated. Manual disable/re-enable/test-mode. auto_disabled_at is cleared and the failure counter reset only on an explicit re-activation to active (never implicitly by moving to testing) -- "disabling stops new jobs while preserving evidence/history" (Prompt 336 §24): the connection row and every app.integration_health_checks row are never deleted, only the status changes. HDN-387 (ISS-2026-235, HDN-BLK-023): re-scoped to a shared INTERNAL core -- no longer granted to authenticated or service_role. Clients go through app.request_integration_connection_status_change, which refuses to activate an enterprise SSO connection through this generic path. Still called directly, unchanged, by app.activate_enterprise_idp_connection (SECURITY DEFINER, same owner, so unaffected by the grant revocation), which is what makes that RPC the only route to activating an SSO connection.';

revoke execute on function app.set_integration_connection_status(uuid, text, text, uuid, text) from authenticated;
revoke execute on function app.set_integration_connection_status(uuid, text, text, uuid, text) from service_role;

grant execute on function app.request_integration_connection_status_change(uuid, text, text, uuid, text) to authenticated, service_role;

-- ===========================================================================
-- Part 2: `HDN-BLK-013` (High) -- 7 TS Server Action call sites and 1 API route pass a
-- client-supplied resource ID straight to a tenant-scoped RPC after confirming the
-- CALLER's own tenant admin authority, but never confirm the TARGET record actually
-- belongs to that same tenant. The database-layer RPCs themselves are correctly
-- tenant-scoped (a cross-tenant ID resolves to `not_found`, never leaks data) -- this is
-- defense-in-depth at the app layer, matching the already-established idiom at
-- `app/(tenant)/[tenantSlug]/commercial/accounts/[accountId]/page.tsx:37`
-- (`if (!account || account.tenantId !== access.tenant.id) { notFound(); }`).
-- This part is TypeScript-only; see the accompanying diff to
-- `app/(tenant)/[tenantSlug]/admin/api-keys/actions.ts` and
-- `app/api/v1/customer/bookings/[bookingRequestId]/submit/route.ts` in this same commit.
-- No migration needed for Part 2 -- noted here only to keep this file's own numbering
-- legible against the build log.
-- ===========================================================================

-- ===========================================================================
-- Part 3: `HDN-BLK-019` (High) -- `app.file_access_logs` carries zero triggers and
-- `service_role` holds live UPDATE/DELETE on the table, so even a file under an active
-- legal hold has its own access-log evidence rows freely mutable/deletable. Bundled
-- with `HDN-BLK-018`'s own much larger ~70-table append-only-guard rollout by that
-- entry's original text -- but the worst part (a legally-held file's own evidence trail
-- being destructible) is separable and narrowly boundable, mirroring `HDN-386`'s own
-- just-proven legal-hold-bridge-plus-trigger pattern for `app.audit_logs`/`app.tenants`.
-- Deliberately does NOT attempt `HDN-BLK-018`'s own full ~70-table rollout -- ordinary
-- (non-held) `app.file_access_logs` rows remain `service_role`-UPDATE/DELETE-able,
-- exactly as `app.audit_logs` itself remains for non-held rows after HDN-386's fix. This
-- asymmetry is honest and intentional, not an oversight.
--
-- `app.file_access_logs` has no native `legal_hold` column of its own (unlike
-- `app.files`/`app.audit_logs`/`app.tenants`) -- its hold-state is entirely inherited
-- via `file_id -> app.files.id`, so the guard joins out to the parent file rather than
-- reading a local column.
-- ===========================================================================

create function app.protect_file_access_logs_legal_hold_from_mutation()
returns trigger
language plpgsql
as $$
declare
  v_actor uuid;
  v_held boolean;
  v_tenant_id uuid;
begin
  select f.tenant_id, (f.legal_hold or app._is_under_legal_hold(f.tenant_id, 'operational', 'app.files', f.id))
    into v_tenant_id, v_held
    from app.files f where f.id = OLD.file_id;

  if v_tenant_id is null or not v_held then
    if TG_OP = 'DELETE' then
      return OLD;
    end if;
    return NEW;
  end if;

  -- Computed lazily, after confirming the parent file is actually held -- mirrors
  -- app.protect_audit_logs_legal_hold_from_deletion's own HDN-386 Tier C discipline
  -- (auth.uid() raises on a session with no JWT claims set, which the overwhelming
  -- majority of ordinary, unheld-file access-log writes are).
  v_actor := auth.uid();
  if not app.is_supreme_admin(v_actor) then
    if TG_OP = 'DELETE' then
      raise exception 'file_access_log_legal_hold_blocks_deletion: access-log row % for a legally-held file cannot be physically deleted -- this is the schema-level backstop for a direct DELETE against evidence tied to an active hold', OLD.id
        using errcode = 'insufficient_privilege';
    else
      raise exception 'file_access_log_legal_hold_blocks_deletion: access-log row % for a legally-held file cannot be updated -- this is the schema-level backstop for a direct UPDATE against evidence tied to an active hold', OLD.id
        using errcode = 'insufficient_privilege';
    end if;
  end if;

  perform app.capture_audit_event(
    v_tenant_id, v_actor, 'supreme_admin_absolute_crud',
    case when TG_OP = 'DELETE' then 'delete_legally_held_file_access_log' else 'update_legally_held_file_access_log' end,
    'app.file_access_logs', OLD.id, 'success',
    'RPD-022 absolute-CRUD exception invoked (best-effort evidence, not a preventive control) -- app.file_access_logs is otherwise blocked from mutation while the referenced file is under legal hold, native or generic (app.legal_holds)',
    to_jsonb(OLD), case when TG_OP = 'DELETE' then null else to_jsonb(NEW) end
  );

  if TG_OP = 'DELETE' then
    return OLD;
  end if;
  return NEW;
end;
$$;

comment on function app.protect_file_access_logs_legal_hold_from_mutation is
  'HDN-387 (Release Blocker Triage and Remediation, closing the worst part of HDN-BLK-019, High): BEFORE UPDATE OR DELETE guard for app.file_access_logs. Inherits hold-state from the parent app.files row (file_access_logs carries no native legal_hold column of its own) -- checks BOTH the PLT-128-native app.files.legal_hold flag AND the bridged generic (IAE-031) app._is_under_legal_hold(), mirroring app.protect_audit_logs_legal_hold_from_deletion (HDN-386) exactly. Deliberately narrow: only rows whose parent file is under an active hold are protected -- ordinary access-log rows remain mutable, matching HDN-BLK-018''s own still-open, much larger append-only-guard scope, not attempting it here.';

create trigger file_access_logs_protect_legal_hold
  before update or delete on app.file_access_logs
  for each row
  execute function app.protect_file_access_logs_legal_hold_from_mutation();

-- ===========================================================================
-- Part 4: `HDN-BLK-022` (High) -- the coarse-tenant-membership-RLS-plus-fine-RPC-gate
-- bypass shape (already fixed once for 2 Procurement tables at `HDN-377`,
-- `ISS-2026-220`) recurs across ~35 more Procurement/HR tables. Closing the full
-- ~35-table sweep is explicitly out of this checkpoint's own bounded-repair budget (each
-- table needs its own individual action-code verification against its own RPC layer,
-- even though the fix pattern itself is identical) -- but the 2 tables `HDN-377`'s own
-- Tier C live-forced as genuinely exploitable are closed now as a first increment,
-- exactly matching the already-proven `app.check_procurement_authority`/`ISS-2026-220`
-- fix shape. The remaining ~33-table sweep stays registered, owner `HDN-378`, unchanged.
--
-- `app.check_hris_authority` is a direct structural copy of `app.check_procurement_
-- authority` (itself already the third instance of this exact wrapper shape, alongside
-- `app.check_payroll_authority`) -- one string changed (module code 'HRS' in place of
-- 'PRC'), not a new design.
-- ===========================================================================

create function app.check_hris_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = app, pg_temp
as $$
  select (app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'HRS', p_action)).allowed;
$$;

comment on function app.check_hris_authority is
  'HDN-387 (Release Blocker Triage and Remediation, closing part of HDN-BLK-022, High): RLS-callable HRS-module authority check, mirroring app.check_procurement_authority (HDN-377, ISS-2026-220) and app.check_payroll_authority exactly -- the third instance of this identical wrapper shape, not a new design. Used as a defense-in-depth RLS policy predicate alongside bare tenant-membership, closing the gap where a zero-HRS-role tenant member could direct-SELECT a table''s own real data despite the RPC layer correctly denying the same actor.';

-- HDN-387 Tier-A-live-run fix: an RLS policy predicate is evaluated AS the querying
-- role (authenticated), so this function needs its own explicit EXECUTE grant --
-- mirroring app.check_procurement_authority's own grant
-- (20260814000000_harden_storage_signed_url_audit_findings.sql:415) exactly. Missing
-- this caused a live "permission denied for function check_hris_authority" the moment
-- this file's own closing `revoke execute on all functions in schema app from public`
-- ran without a matching re-grant -- caught by a live db-tests re-run
-- (hris-organization-position-linkage.sql).
grant execute on function app.check_hris_authority(text, uuid, uuid) to authenticated, service_role;

-- HDN-387 Tier-A-live-run fix: the pre-existing policy on both tables is actually
-- named `*_select_scoped` (matching the established HDN-377 precedent's own exact
-- naming -- `vendor_compliance_documents_select_scoped` /
-- `rfq_response_attachments_select_scoped`,
-- 20260814000000_harden_storage_signed_url_audit_findings.sql:417-439), NOT
-- `*_tenant_read` as first assumed here. Since Postgres OR-combines multiple
-- permissive policies for the same command/role, the original `drop policy if exists
-- ..._tenant_read` was a silent no-op and the new, differently-named policy below was
-- simply ADDED alongside the still-live, unrestricted `*_select_scoped` policy -- a
-- zero-HRS-role tenant member could still read the table through the OLD policy,
-- completely nullifying this fix. Caught live: a probe actor holding only a bare
-- `org_user` role (no HRS grant at all) could still SELECT the fixture row. Fixed by
-- dropping and replacing the SAME, correctly-named `*_select_scoped` policy in place,
-- exactly mirroring the HDN-377 precedent.
drop policy position_grades_select_scoped on app.position_grades;
create policy position_grades_select_scoped on app.position_grades
  for select to authenticated
  using (
    app.is_supreme_admin()
    or (
      app.has_active_tenant_membership(tenant_id)
      and not app.actor_holds_customer_user_layer(tenant_id)
      and app.check_hris_authority('View', tenant_id, (select auth.uid()))
    )
  );

drop policy vendor_kpi_scorecards_select_scoped on app.vendor_kpi_scorecards;
create policy vendor_kpi_scorecards_select_scoped on app.vendor_kpi_scorecards
  for select to authenticated
  using (
    app.is_supreme_admin()
    or (
      app.has_active_tenant_membership(tenant_id)
      and not app.actor_holds_customer_user_layer(tenant_id)
      and app.check_procurement_authority('View', tenant_id, (select auth.uid()))
    )
  );

-- ===========================================================================
-- Part 5: `HDN-BLK-027` (High) -- alerting is unwired from most real failure producers;
-- `app.record_job_failure`'s own dead-letter branch is the only one that raises a real
-- alert (HDN-382). This checkpoint closes one concrete, narrow slice: the 3 inbound
-- webhook INGESTION functions' own `signature_verification_failed` branch (NOT the
-- pure, `stable`-declared `verify_*_webhook_signature` functions themselves, which
-- correctly stay side-effect-free) -- the real, non-`stable` failure-recording point,
-- the identical shape as `record_job_failure`'s own dead-letter branch. The remaining
-- producers this entry names (replay-divergence, IAE-008 health-check auto-disable,
-- AI-governance rejection, security-denial paths) span more domains and stay
-- registered under the still-open `ISS-2026-249`, not attempted here.
-- ===========================================================================

-- HDN-387 Tier-A-live-run fix: the first draft of this Part 5 based each function's
-- "verbatim reproduction" on its ORIGINAL create-table migration, silently reverting
-- every later hardening pass on all 3 functions (advisory-lock rate-limit scoping,
-- ATW-226F's own canonical-telemetry-arbitration call, ATW-226I's auto-disable
-- wiring, ATW-027's widened exception boundary) -- caught by a live db-tests run
-- (advanced-tms-canonical-telemetry-arbitration.sql's own "switch_suppressed" case
-- failed once the arbitration call silently vanished). Rewritten below from each
-- function's true LATEST body (grep-verified: 20260805070000_harden_intelligence_
-- batch4_tier_c_review_fixes.sql for the 2 IAE functions,
-- 20260730350000_harden_advanced_tms_third_party_hybrid_tracking.sql for ATW-226) --
-- the ONLY change from that latest body in all 3 is the one added
-- app.raise_observability_alert(...) call in the signature_verification_failed
-- branch, re-verified via a full db-tests re-run.

create or replace function app.ingest_finance_payment_gateway_webhook_event(
  p_connection_id uuid,
  p_client_key text,
  p_raw_payload text,
  p_timestamp bigint,
  p_signature text
)
returns table (ingest_status text, event_id uuid)
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_recent_bad_count integer;
  v_conn app.integration_connections;
  v_payload jsonb;
  v_provider_event_id text;
  v_event_type text;
  v_external_reference text;
  v_match_count integer := 0;
  v_bank_transaction_id uuid := null;
  v_match_status text := 'unmatched';
  v_row app.finance_payment_gateway_events;
begin
  if p_client_key is null or length(trim(p_client_key)) = 0 then
    raise exception 'finance_payment_client_key_required: a client_key is required' using errcode = 'check_violation';
  end if;

  -- Tier C fix: identical shape to app.ingest_logistics_partner_webhook_
  -- event's own fix -- see that function's own comment for the live
  -- reproduction this closes.
  perform pg_advisory_xact_lock(hashtext('finance_payment_gateway_rate:' || p_connection_id::text || ':' || p_client_key)::bigint);

  select count(*) into v_recent_bad_count
  from app.finance_payment_gateway_ingestion_attempts
  where connection_id = p_connection_id and client_key = p_client_key and result = 'invalid' and occurred_at > now() - interval '15 minutes';
  if v_recent_bad_count >= 10 then
    insert into app.finance_payment_gateway_ingestion_attempts (connection_id, client_key, result, reason) values (p_connection_id, p_client_key, 'rate_limited', 'rate_limited');
    return query select 'rate_limited'::text, null::uuid;
    return;
  end if;

  select * into v_conn from app.integration_connections where id = p_connection_id;
  if not found or v_conn.status <> 'active' or v_conn.adapter_code <> 'payment_gateway' then
    insert into app.finance_payment_gateway_ingestion_attempts (connection_id, client_key, result, reason) values (v_conn.id, p_client_key, 'invalid', 'connection_not_active');
    return query select 'invalid'::text, null::uuid;
    return;
  end if;

  if not app.verify_finance_payment_webhook_signature(p_connection_id, p_raw_payload, p_timestamp, p_signature) then
    insert into app.finance_payment_gateway_ingestion_attempts (connection_id, client_key, result, reason) values (p_connection_id, p_client_key, 'invalid', 'signature_verification_failed');
    -- HDN-387 (HDN-BLK-027): mirrors app.record_job_failure's own dead-letter alert
    -- pattern (HDN-382) -- previously a real invalid-signature attempt produced zero
    -- incident, zero alert, zero owner notification.
    perform app.raise_observability_alert(
      v_conn.tenant_id, 'webhook', 'error',
      format('webhook signature verification failed: connection %s (finance_payment_gateway)', p_connection_id),
      'high', format('connection_id=%s client_key=%s', p_connection_id, p_client_key)
    );
    return query select 'invalid'::text, null::uuid;
    return;
  end if;

  begin
    v_payload := p_raw_payload::jsonb;
  exception
    when others then
      insert into app.finance_payment_gateway_ingestion_attempts (connection_id, client_key, result, reason) values (p_connection_id, p_client_key, 'invalid', 'malformed_json');
      return query select 'invalid'::text, null::uuid;
      return;
  end;

  v_provider_event_id := v_payload ->> 'event_id';
  v_event_type := v_payload ->> 'event_type';
  v_external_reference := v_payload ->> 'external_reference';

  if v_provider_event_id is null or v_event_type not in ('payment_confirmed', 'payment_failed', 'refund_issued', 'chargeback') then
    insert into app.finance_payment_gateway_ingestion_attempts (connection_id, client_key, result, reason, raw_payload) values (p_connection_id, p_client_key, 'invalid', 'schema_validation_failed', v_payload);
    return query select 'invalid'::text, null::uuid;
    return;
  end if;

  select count(*) into v_match_count from app.match_finance_payment_gateway_event_to_transaction(v_conn.tenant_id, v_external_reference);
  if v_match_count = 1 then
    select m.bank_transaction_id into v_bank_transaction_id from app.match_finance_payment_gateway_event_to_transaction(v_conn.tenant_id, v_external_reference) m;
    v_match_status := 'matched';
  elsif v_match_count > 1 then
    v_match_status := 'ambiguous';
  end if;

  insert into app.finance_payment_gateway_events (
    tenant_id, connection_id, provider_event_id, event_type, external_reference, bank_transaction_id, match_status, raw_payload
  ) values (
    v_conn.tenant_id, v_conn.id, v_provider_event_id, v_event_type, v_external_reference, v_bank_transaction_id, v_match_status, v_payload
  )
  on conflict (connection_id, provider_event_id) do nothing
  returning * into v_row;

  if v_row.id is null then
    insert into app.finance_payment_gateway_ingestion_attempts (connection_id, client_key, result, reason) values (p_connection_id, p_client_key, 'duplicate', 'provider_event_id_already_ingested');
    return query select 'duplicate'::text, null::uuid;
    return;
  end if;

  insert into app.finance_payment_gateway_ingestion_attempts (connection_id, client_key, result) values (p_connection_id, p_client_key, 'success');

  return query select 'ok'::text, v_row.id;
end;
$$;

comment on function app.ingest_finance_payment_gateway_webhook_event is
  'IAE-017: the sole anon-granted entrypoint for inbound payment-gateway events. Atomic insert-on-conflict-do-nothing-returning dedup (never a two-step exists-check), mirrors app.ingest_logistics_partner_webhook_event (IAE-016) exactly. Never raises for a caller-facing failure mode. Rate-limit dedup keyed on (connection_id, client_key), advisory-lock-serialized (Tier C fix). HDN-387 (HDN-BLK-027): a signature-verification failure now also raises a real observability alert, mirroring app.record_job_failure''s own dead-letter alert pattern (HDN-382).';

create or replace function app.ingest_logistics_partner_webhook_event(
  p_connection_id uuid,
  p_client_key text,
  p_raw_payload text,
  p_timestamp bigint,
  p_signature text
)
returns table (ingest_status text, event_id uuid)
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_recent_bad_count integer;
  v_conn app.integration_connections;
  v_payload jsonb;
  v_provider_event_id text;
  v_event_type text;
  v_external_reference text;
  v_match_count integer := 0;
  v_shipment_order_id uuid := null;
  v_match_status text := 'unmatched';
  v_row app.logistics_partner_events;
begin
  if p_client_key is null or length(trim(p_client_key)) = 0 then
    raise exception 'logistics_partner_client_key_required: a client_key is required' using errcode = 'check_violation';
  end if;

  -- Tier C fix: serialize the check-then-act for THIS (connection, client)
  -- pair -- live-reproduced without the lock, 40 concurrent bad-signature
  -- deliveries blew through the documented 10-per-15-minute budget (36
  -- admitted). Scoping the count by connection_id (not client_key alone)
  -- closes the live-reproduced cross-tenant blast radius: an attacker
  -- spoofing X-Forwarded-For to match a genuine provider's own client_key
  -- could previously throttle a DIFFERENT tenant's connection entirely.
  perform pg_advisory_xact_lock(hashtext('logistics_partner_rate:' || p_connection_id::text || ':' || p_client_key)::bigint);

  select count(*) into v_recent_bad_count
  from app.logistics_partner_ingestion_attempts
  where connection_id = p_connection_id and client_key = p_client_key and result = 'invalid' and occurred_at > now() - interval '15 minutes';
  if v_recent_bad_count >= 10 then
    insert into app.logistics_partner_ingestion_attempts (connection_id, client_key, result, reason) values (p_connection_id, p_client_key, 'rate_limited', 'rate_limited');
    return query select 'rate_limited'::text, null::uuid;
    return;
  end if;

  select * into v_conn from app.integration_connections where id = p_connection_id;
  if not found or v_conn.status <> 'active' or not (v_conn.adapter_code = any (app.logistics_partner_adapter_codes())) then
    insert into app.logistics_partner_ingestion_attempts (connection_id, client_key, result, reason) values (v_conn.id, p_client_key, 'invalid', 'connection_not_active');
    return query select 'invalid'::text, null::uuid;
    return;
  end if;

  if not app.verify_logistics_partner_webhook_signature(p_connection_id, p_raw_payload, p_timestamp, p_signature) then
    insert into app.logistics_partner_ingestion_attempts (connection_id, client_key, result, reason) values (p_connection_id, p_client_key, 'invalid', 'signature_verification_failed');
    -- HDN-387 (HDN-BLK-027): mirrors app.record_job_failure's own dead-letter alert
    -- pattern (HDN-382).
    perform app.raise_observability_alert(
      v_conn.tenant_id, 'webhook', 'error',
      format('webhook signature verification failed: connection %s (logistics_partner)', p_connection_id),
      'high', format('connection_id=%s client_key=%s', p_connection_id, p_client_key)
    );
    return query select 'invalid'::text, null::uuid;
    return;
  end if;

  begin
    v_payload := p_raw_payload::jsonb;
  exception
    when others then
      insert into app.logistics_partner_ingestion_attempts (connection_id, client_key, result, reason) values (p_connection_id, p_client_key, 'invalid', 'malformed_json');
      return query select 'invalid'::text, null::uuid;
      return;
  end;

  v_provider_event_id := v_payload ->> 'event_id';
  v_event_type := v_payload ->> 'event_type';
  v_external_reference := v_payload ->> 'external_reference';

  if v_provider_event_id is null or v_event_type not in ('status_update', 'milestone', 'document_available', 'customs_clearance') then
    insert into app.logistics_partner_ingestion_attempts (connection_id, client_key, result, reason, raw_payload) values (p_connection_id, p_client_key, 'invalid', 'schema_validation_failed', v_payload);
    return query select 'invalid'::text, null::uuid;
    return;
  end if;

  select count(*) into v_match_count from app.match_logistics_partner_event_to_shipment(v_conn.tenant_id, v_external_reference);
  if v_match_count = 1 then
    select m.shipment_order_id into v_shipment_order_id from app.match_logistics_partner_event_to_shipment(v_conn.tenant_id, v_external_reference) m;
    v_match_status := 'matched';
  elsif v_match_count > 1 then
    v_match_status := 'ambiguous';
  end if;

  insert into app.logistics_partner_events (
    tenant_id, connection_id, provider_event_id, event_type, external_reference, shipment_order_id, match_status, raw_payload
  ) values (
    v_conn.tenant_id, v_conn.id, v_provider_event_id, v_event_type, v_external_reference, v_shipment_order_id, v_match_status, v_payload
  )
  on conflict (connection_id, provider_event_id) do nothing
  returning * into v_row;

  if v_row.id is null then
    insert into app.logistics_partner_ingestion_attempts (connection_id, client_key, result, reason) values (p_connection_id, p_client_key, 'duplicate', 'provider_event_id_already_ingested');
    return query select 'duplicate'::text, null::uuid;
    return;
  end if;

  insert into app.logistics_partner_ingestion_attempts (connection_id, client_key, result) values (p_connection_id, p_client_key, 'success');

  return query select 'ok'::text, v_row.id;
end;
$$;

comment on function app.ingest_logistics_partner_webhook_event is
  'IAE-016: the sole anon-granted entrypoint for inbound carrier/port/airport/customs provider events, mirrors app.ingest_third_party_provider_webhook_event (ATW-226E) exactly in shape. Never raises for a caller-facing failure mode -- every branch returns a row. Rate-limit dedup keyed on (connection_id, client_key), advisory-lock-serialized (Tier C fix). HDN-387 (HDN-BLK-027): a signature-verification failure now also raises a real observability alert, mirroring app.record_job_failure''s own dead-letter alert pattern (HDN-382).';

create or replace function app.ingest_third_party_provider_webhook_event(
  p_connection_id uuid,
  p_client_key text,
  p_raw_payload text,
  p_timestamp bigint,
  p_signature text
)
returns table (ingest_status text, report_id uuid)
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_recent_bad_count integer;
  v_conn app.third_party_provider_connections;
  v_payload jsonb;
  v_event_id text;
  v_vehicle_external_id text;
  v_report_type text;
  v_event_at timestamptz;
  v_lat numeric;
  v_lon numeric;
  v_speed numeric;
  v_heading numeric;
  v_mapping app.provider_vehicle_mappings;
  v_geojson jsonb;
  v_geog geography;
  v_report app.third_party_telemetry_reports;
  v_new_failure_count integer;
begin
  -- ATW-226I widens ATW-226F's own already-widened body below (this function was
  -- CREATE OR REPLACE'd a second time at 226F to add the app.arbitrate_and_project_
  -- vehicle_position() call near the end -- that call is preserved unchanged here,
  -- only the signature-failure branch immediately below gains the auto-disable logic).
  if p_client_key is null or length(trim(p_client_key)) = 0 then
    raise exception 'tracking_client_key_required: a client_key is required' using errcode = 'check_violation';
  end if;

  -- CG-S10-ATW-027 fix-pass addition (adversarial review, Finding 4, MEDIUM): widened
  -- from client_key-only to (connection_id OR client_key) -- client_key is fully
  -- caller-controlled (the real HTTP route derives it from x-forwarded-for's own
  -- externally-suppliable first hop), so a client_key-only count is trivially bypassed
  -- by varying it per request (live-reproduced: 30 distinct client_keys against the
  -- same connection, 0/30 ever tripped rate_limited). connection_id is the caller's
  -- own chosen attack target and cannot be rotated without abandoning the attack, so it
  -- is now the primary, unavoidable bound; client_key is kept as a secondary signal --
  -- still the only signal available for a wholly nonexistent connection_id, which the
  -- "invalid: connection_not_active" branch below deliberately records with a null
  -- connection_id FK (see that branch's own inline comment), so it can never be matched
  -- by the connection_id predicate on its own.
  select count(*) into v_recent_bad_count
  from app.third_party_provider_ingestion_attempts
  where result = 'invalid' and occurred_at > now() - interval '15 minutes'
    and (connection_id = p_connection_id or client_key = p_client_key);
  if v_recent_bad_count >= 10 then
    insert into app.third_party_provider_ingestion_attempts (connection_id, client_key, result, reason) values (p_connection_id, p_client_key, 'rate_limited', 'rate_limited');
    return query select 'rate_limited'::text, null::uuid;
    return;
  end if;

  select * into v_conn from app.third_party_provider_connections where id = p_connection_id;
  if not found or v_conn.integration_mode <> 'webhook' or v_conn.status <> 'active' then
    -- v_conn.id, not p_connection_id -- a caller-supplied connection_id that does not
    -- exist at all must not be inserted as the FK value (v_conn.id is null in that
    -- case, the FK column's own nullable design intent for exactly this outcome).
    insert into app.third_party_provider_ingestion_attempts (connection_id, client_key, result, reason) values (v_conn.id, p_client_key, 'invalid', 'connection_not_active');
    return query select 'invalid'::text, null::uuid;
    return;
  end if;

  if not app.verify_third_party_provider_webhook_signature(p_connection_id, p_raw_payload, p_timestamp, p_signature) then
    -- ATW-226I (design note 1): a genuine security/outage signal about this
    -- connection's own health, unlike a locally-invalid payload below -- mirrors
    -- app.record_webhook_delivery_attempt's own failure branch exactly (ADR-0011).
    v_new_failure_count := v_conn.consecutive_failure_count + 1;
    update app.third_party_provider_connections
    set consecutive_failure_count = v_new_failure_count,
        status = case when v_new_failure_count >= 10 then 'disabled' else status end,
        auto_disabled_at = case when v_new_failure_count >= 10 and status <> 'disabled' then now() else auto_disabled_at end,
        disabled_reason = case when v_new_failure_count >= 10 and status <> 'disabled' then 'consecutive_failure_threshold_exceeded' else disabled_reason end
    where id = v_conn.id;

    insert into app.third_party_provider_ingestion_attempts (connection_id, client_key, result, reason) values (p_connection_id, p_client_key, 'invalid', 'signature_verification_failed');
    -- HDN-387 (HDN-BLK-027): mirrors app.record_job_failure's own dead-letter alert
    -- pattern (HDN-382).
    perform app.raise_observability_alert(
      v_conn.tenant_id, 'webhook', 'error',
      format('webhook signature verification failed: connection %s (third_party_provider)', p_connection_id),
      'high', format('connection_id=%s client_key=%s', p_connection_id, p_client_key)
    );
    return query select 'invalid'::text, null::uuid;
    return;
  end if;

  begin
    v_payload := p_raw_payload::jsonb;
  exception
    when others then
      insert into app.third_party_provider_ingestion_attempts (connection_id, client_key, result, reason) values (p_connection_id, p_client_key, 'invalid', 'malformed_json');
      return query select 'invalid'::text, null::uuid;
      return;
  end;

  -- CG-S10-ATW-027 fix-pass addition (adversarial review, Finding 3, MEDIUM): widens
  -- the exception boundary from "JSON-parse only" to cover every field
  -- extraction/cast below AND the final INSERT's own CHECK constraints -- a
  -- validly-signed-but-malformed payload (non-numeric/out-of-range latitude,
  -- longitude, speed_kmh, heading_degrees, or a non-timestamp `timestamp` string) was
  -- live-reproduced raising an uncaught exception instead of this function's own
  -- documented "never raises" contract, and because the failure was uncaught, zero
  -- row landed in third_party_provider_ingestion_attempts -- invisible to both the
  -- rate limiter above and ATW-226I's own auto-disable counter. This begin/exception
  -- block is an implicit savepoint: every already-clean early RETURN inside it
  -- (schema_validation_failed/duplicate/quarantined/location_report_missing_
  -- coordinates) is normal control flow, not an exception, and is entirely
  -- unaffected -- only a genuine uncaught error (a bad cast, or
  -- app.geojson_point_to_geography's own explicit spatial_coordinate_out_of_range
  -- raise, or a table CHECK violation on the final INSERT) is now caught here.
  begin
    v_event_id := v_payload ->> 'event_id';
    v_vehicle_external_id := v_payload ->> 'vehicle_id';
    v_report_type := v_payload ->> 'event_type';
    v_event_at := (v_payload ->> 'timestamp')::timestamptz;

    if v_event_id is null or v_vehicle_external_id is null or v_report_type not in ('location', 'heartbeat') or v_event_at is null then
      insert into app.third_party_provider_ingestion_attempts (connection_id, client_key, result, reason, raw_payload) values (p_connection_id, p_client_key, 'invalid', 'schema_validation_failed', v_payload);
      return query select 'invalid'::text, null::uuid;
      return;
    end if;

    if exists (select 1 from app.third_party_telemetry_reports where connection_id = p_connection_id and provider_event_id = v_event_id) then
      insert into app.third_party_provider_ingestion_attempts (connection_id, client_key, result, reason) values (p_connection_id, p_client_key, 'duplicate', 'provider_event_id_already_ingested');
      return query select 'duplicate'::text, null::uuid;
      return;
    end if;

    select * into v_mapping
    from app.provider_vehicle_mappings
    where tenant_id = v_conn.tenant_id and provider_code = v_conn.provider_code and external_vehicle_id = v_vehicle_external_id and status = 'active';
    if not found then
      insert into app.third_party_provider_ingestion_attempts (connection_id, client_key, result, reason, raw_payload) values (p_connection_id, p_client_key, 'quarantined', 'unmapped_external_vehicle_id', v_payload);
      return query select 'quarantined'::text, null::uuid;
      return;
    end if;

    v_lat := (v_payload ->> 'latitude')::numeric;
    v_lon := (v_payload ->> 'longitude')::numeric;
    v_speed := (v_payload ->> 'speed_kmh')::numeric;
    v_heading := (v_payload ->> 'heading_degrees')::numeric;

    if v_report_type = 'location' and (v_lat is null or v_lon is null) then
      insert into app.third_party_provider_ingestion_attempts (connection_id, client_key, result, reason, raw_payload) values (p_connection_id, p_client_key, 'invalid', 'location_report_missing_coordinates', v_payload);
      return query select 'invalid'::text, null::uuid;
      return;
    end if;

    v_geog := null;
    if v_report_type = 'location' then
      v_geojson := jsonb_build_object('type', 'Point', 'coordinates', jsonb_build_array(v_lon, v_lat));
      v_geog := app.geojson_point_to_geography(v_geojson);
    end if;

    insert into app.third_party_telemetry_reports (
      tenant_id, connection_id, vehicle_master_id, provider_event_id, report_type, event_at, location, speed_kmh, heading_degrees, raw_fields
    ) values (
      v_conn.tenant_id, v_conn.id, v_mapping.vehicle_master_id, v_event_id, v_report_type, v_event_at, v_geog, v_speed, v_heading, v_payload
    )
    returning * into v_report;
  exception
    when others then
      insert into app.third_party_provider_ingestion_attempts (connection_id, client_key, result, reason, raw_payload) values (p_connection_id, p_client_key, 'invalid', 'malformed_field_value', v_payload);
      return query select 'invalid'::text, null::uuid;
      return;
  end;

  update app.third_party_provider_connections set last_successful_ingest_at = now(), consecutive_failure_count = 0 where id = v_conn.id;

  insert into app.third_party_provider_ingestion_attempts (connection_id, client_key, result) values (p_connection_id, p_client_key, 'success');

  -- ATW-226F: canonicalize -- never raises, never blocks the already-committed raw insert above.
  perform app.arbitrate_and_project_vehicle_position(
    v_conn.tenant_id, v_mapping.vehicle_master_id, 'third_party_platform', v_report.id, v_event_at, v_report.received_at,
    v_geog, v_speed, v_heading, null::numeric
  );

  return query select 'ok'::text, v_report.id;
end;
$$;

comment on function app.ingest_third_party_provider_webhook_event is
  'ATW-226E: the one anon-callable HTTPS webhook ingestion entry point (design note 2 above). Validates the reference JSON contract (design note 3), quarantines an unmapped external_vehicle_id rather than dropping it (design note 4), and treats a replayed provider_event_id as a distinct duplicate outcome, never an error (design note 5). Raw storage only -- canonicalizes via app.arbitrate_and_project_vehicle_position (ATW-226F). Auto-disables after 10 consecutive signature failures (ATW-226I); the exception boundary covers every field extraction/cast and the final INSERT''s own CHECK constraints, never just JSON-parse (CG-S10-ATW-027). HDN-387 (HDN-BLK-027): a signature-verification failure now also raises a real observability alert, mirroring app.record_job_failure''s own dead-letter alert pattern (HDN-382).';

-- ===========================================================================
-- Part 6: `HDN-BLK-010` (narrowed remainder, High) -- the Finance/HRIS-Payroll portion
-- of this class was already closed at `HDN-374` (`ISS-2026-162`); this checkpoint closes
-- the remaining 3 non-Finance check-then-insert functions with the SAME already-proven
-- "design note 9(a)" nested begin/exception unique_violation recovery shape
-- (`app.prepare_wms_outbound_from_shipment`,
-- `20260730230000_create_advanced_tms_wms_outbound_order.sql:343`) -- a genuine race
-- between the SELECT-for-idempotency-replay and the INSERT (two concurrent callers
-- both prepare from the same source row) previously surfaced as a raised
-- `unique_violation` instead of the correct idempotent-replay return. `app.link_auth_
-- identity` (PLT-107) is the same shape one level earlier in the product (auth
-- identity linkage, not a Commercial/TMS domain object), included here because it is
-- the exact same defect class, not a new one.
--
-- Also closes `ISS-2026-163` in the same session, same function family, per that
-- issue's own registered owner (`HDN-374`, handed forward to `HDN-387`):
-- `app.prepare_job_order`'s own nested exception handler is a DEFECTIVE instance of
-- this same pattern (missing `if found`/`raise;`), not a missing one -- it can
-- silently return an all-NULL row on an UNRELATED unique_violation (the table's own
-- separate `job_orders_tenant_number_unique` constraint), rather than the correct
-- idempotent-replay row or a raised error. Fixed by adding the missing guard, not by
-- adding a new begin/exception block.
-- ===========================================================================

create or replace function app.prepare_job_order_handoff(
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

  -- HDN-387 (HDN-BLK-010): design note 9(a) nested begin/exception unique_violation
  -- recovery -- a genuine race between the SELECT above and this INSERT (two
  -- concurrent callers both preparing a handoff from the same quotation) is resolved
  -- by re-selecting and returning the winner, never a raised error on a legitimate
  -- concurrent retry. Mirrors app.prepare_wms_outbound_from_shipment exactly.
  begin
    insert into app.job_order_handoffs (
      tenant_id, quotation_id, account_id, payload, payload_hash,
      prepared_by_auth_user_id, owner_user_id, org_unit_id, created_by
    ) values (
      v_quotation.tenant_id, p_quotation_id, v_conversion.account_id, v_payload, encode(digest(v_payload::text, 'sha256'), 'hex'),
      p_actor_auth_user_id, v_quotation.owner_user_id, v_quotation.org_unit_id, p_actor_label
    )
    returning * into v_handoff;
  exception
    when unique_violation then
      select * into v_existing from app.job_order_handoffs where tenant_id = v_quotation.tenant_id and quotation_id = p_quotation_id and purpose = 'job_order_draft';
      if found then
        if not app.has_view_selling_price(v_quotation.tenant_id, p_actor_auth_user_id) then
          v_existing.payload := null;
          v_existing.payload_hash := null;
        end if;
        return v_existing;
      end if;
      raise;
  end;

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
  'HDN-387 (HDN-BLK-010): idempotent on (tenant_id, quotation_id, purpose=job_order_draft), including under a genuine concurrent-insert race (design note 9a) -- mirrors app.prepare_wms_outbound_from_shipment exactly. An existing handoff for this key is always returned unchanged, whether found by the initial SELECT or recovered after a concurrent-insert unique_violation. Selling-price fields are masked for an actor lacking view-selling-price authority on every return path.';

create or replace function app.prepare_wms_inbound_from_shipment(
  p_tenant_id uuid,
  p_shipment_order_id uuid,
  p_warehouse_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.wms_inbound_orders
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_shipment app.shipment_orders;
  v_warehouse app.warehouses;
  v_existing app.wms_inbound_orders;
  v_order app.wms_inbound_orders;
  v_number text;
begin
  select * into v_shipment from app.shipment_orders where id = p_shipment_order_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'shipment_order_not_found: % is not a shipment order of tenant %', p_shipment_order_id, p_tenant_id using errcode = 'no_data_found';
  end if;
  if v_shipment.status = 'cancelled' then
    raise exception 'stale_source: shipment order % is cancelled', p_shipment_order_id using errcode = 'check_violation';
  end if;

  select * into v_warehouse from app.warehouses where id = p_warehouse_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'warehouse_not_found: % is not a warehouse of tenant %', p_warehouse_id, p_tenant_id using errcode = 'no_data_found';
  end if;
  if v_warehouse.status <> 'active' then
    raise exception 'warehouse_not_active: warehouse % is not active', p_warehouse_id using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'OPS', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, p_tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot create an inbound order under warehouse %', p_actor_auth_user_id, p_warehouse_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_existing from app.wms_inbound_orders
    where tenant_id = p_tenant_id and source_type = 'shipment_order' and source_shipment_order_id = p_shipment_order_id and status <> 'cancelled';
  if found then
    return v_existing;
  end if;

  v_number := app.next_wms_inbound_order_number(p_tenant_id);

  -- HDN-387 (HDN-BLK-010): design note 9(a) nested begin/exception unique_violation
  -- recovery, mirroring app.prepare_wms_outbound_from_shipment exactly -- the sibling
  -- inbound-side function of the same source-shipment-fanout shape, guarded by the
  -- identical partial unique index shape (wms_inbound_orders_source_shipment_unique).
  begin
    insert into app.wms_inbound_orders (
      tenant_id, warehouse_id, owner_account_id, inbound_number, source_type, source_shipment_order_id, created_by
    ) values (
      p_tenant_id, p_warehouse_id, v_shipment.shipper_account_id, v_number, 'shipment_order', p_shipment_order_id, p_actor_label
    )
    returning * into v_order;
  exception
    when unique_violation then
      select * into v_existing from app.wms_inbound_orders
        where tenant_id = p_tenant_id and source_type = 'shipment_order' and source_shipment_order_id = p_shipment_order_id and status <> 'cancelled';
      if found then
        return v_existing;
      end if;
      raise;
  end;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'prepare_wms_inbound_from_shipment',
    'app.wms_inbound_orders', v_order.id, 'success', null, null,
    jsonb_build_object('source_shipment_order_id', p_shipment_order_id, 'warehouse_id', p_warehouse_id, 'inbound_number', v_number)
  );

  return v_order;
end;
$$;

comment on function app.prepare_wms_inbound_from_shipment is
  'ATW-012, HDN-387 (HDN-BLK-010) hardened: idempotent on (tenant_id, source_shipment_order_id) among non-cancelled rows, including under a genuine concurrent-insert race (design note 9a) -- mirrors app.prepare_wms_outbound_from_shipment exactly. owner_account_id is inherited from the shipment order''s own shipper_account_id, never re-entered.';

create or replace function app.link_auth_identity(
  p_auth_user_id uuid,
  p_tenant_id uuid,
  p_invited_by text,
  p_status text default 'invited'
)
returns app.tenant_user_identities
language plpgsql
as $$
declare
  v_existing app.tenant_user_identities;
  v_link app.tenant_user_identities;
begin
  select * into v_existing
  from app.tenant_user_identities
  where auth_user_id = p_auth_user_id and tenant_id = p_tenant_id;

  if found then
    return v_existing;
  end if;

  -- HDN-387 (HDN-BLK-010): design note 9(a) nested begin/exception unique_violation
  -- recovery -- a genuine race between the SELECT above and this INSERT (two
  -- concurrent invite/link calls for the same auth_user_id/tenant_id pair) is resolved
  -- by re-selecting and returning the winner, never a raised error on a legitimate
  -- concurrent retry. The history row below is only ever reached on this function's own
  -- successful INSERT, so it cannot itself double-write on the exception-recovery path.
  begin
    insert into app.tenant_user_identities (auth_user_id, tenant_id, status, invited_by, activated_at)
    values (p_auth_user_id, p_tenant_id, p_status, p_invited_by, case when p_status = 'active' then now() else null end)
    returning * into v_link;
  exception
    when unique_violation then
      select * into v_existing
      from app.tenant_user_identities
      where auth_user_id = p_auth_user_id and tenant_id = p_tenant_id;
      if found then
        return v_existing;
      end if;
      raise;
  end;

  insert into app.tenant_user_identity_history (auth_user_id, tenant_id, from_status, to_status, reason, requested_by)
  values (p_auth_user_id, p_tenant_id, null, p_status, 'identity linked', p_invited_by);

  return v_link;
end;
$$;

comment on function app.link_auth_identity is
  'PLT-107, HDN-387 (HDN-BLK-010) hardened: idempotent invitation/linkage on (auth_user_id, tenant_id) -- Prompt 107 §25 ("No account enumeration or orphan/duplicate membership") -- including under a genuine concurrent-insert race (design note 9a), mirroring app.prepare_wms_outbound_from_shipment exactly.';

create or replace function app.prepare_job_order(
  p_source_handoff_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.job_orders
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_handoff app.job_order_handoffs;
  v_decision app.rbac_decision;
  v_existing app.job_orders;
  v_job_order app.job_orders;
  v_number text;
begin
  select * into v_handoff from app.job_order_handoffs where id = p_source_handoff_id;
  if not found then
    raise exception 'handoff_not_found: %', p_source_handoff_id using errcode = 'no_data_found';
  end if;

  select * into v_existing from app.job_orders where tenant_id = v_handoff.tenant_id and source_handoff_id = p_source_handoff_id;
  if found then
    return v_existing;
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_handoff.tenant_id, 'OPS', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_handoff.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_handoff.tenant_id, v_handoff.owner_user_id, app.lead_record_scope_org_unit_ids(v_handoff.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access job order handoff %', p_actor_auth_user_id, p_source_handoff_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_handoff.payload is null then
    raise exception 'handoff_payload_unavailable: handoff % carries no payload to convert', p_source_handoff_id
      using errcode = 'check_violation';
  end if;

  v_number := app.next_job_order_number(v_handoff.tenant_id);

  begin
    insert into app.job_orders (
      tenant_id, job_number, source_handoff_id, quotation_id, account_id,
      customer_snapshot, cargo_service_snapshot, revenue_snapshot, contract_snapshot, credit_snapshot, acceptance_snapshot,
      owner_user_id, created_by
    ) values (
      v_handoff.tenant_id, v_number, v_handoff.id, v_handoff.quotation_id, v_handoff.account_id,
      v_handoff.payload -> 'customer', v_handoff.payload -> 'cargoService', v_handoff.payload -> 'pricing',
      v_handoff.payload -> 'contract', v_handoff.payload -> 'credit', v_handoff.payload -> 'acceptance',
      p_actor_auth_user_id, p_actor_label
    )
    returning * into v_job_order;
  exception
    when unique_violation then
      -- HDN-387 (ISS-2026-163 fix): this handler was previously missing the `if
      -- found`/`raise;` guard every other instance of this pattern in this codebase
      -- carries -- a unique_violation raised by the table's OWN SEPARATE
      -- job_orders_tenant_number_unique constraint (or a re-select genuinely finding
      -- no row) was silently converted into a `return` of an all-NULL app.job_orders
      -- composite instead of a raised error. Re-selecting on the correct idempotency
      -- key (tenant_id, source_handoff_id) and requiring `found` before returning,
      -- else re-raising, closes that silent-data-fabrication shape.
      select * into v_job_order from app.job_orders where tenant_id = v_handoff.tenant_id and source_handoff_id = p_source_handoff_id;
      if found then
        return v_job_order;
      end if;
      raise;
  end;

  perform app.capture_audit_event(
    v_handoff.tenant_id, p_actor_auth_user_id, p_actor_label, 'prepare_job_order',
    'app.job_orders', v_job_order.id, 'success', null, null,
    jsonb_build_object('source_handoff_id', p_source_handoff_id, 'job_number', v_number)
  );

  return v_job_order;
end;
$$;

comment on function app.prepare_job_order is
  'OPS-168/OPS-186-hardened, HDN-387 (ISS-2026-163 fix): idempotent on (tenant_id, source_handoff_id) -- a repeated call, including under a concurrent-insert race, returns the exact same Job Order row, never a duplicate, and now correctly re-raises (rather than silently returning an all-NULL row) when the unique_violation is not the idempotency key''s own constraint. Every snapshot column is copied verbatim from the handoff''s own already-canonical payload. Record-scope-checked against the source handoff (OPS-186).';

revoke execute on all functions in schema app from public;
