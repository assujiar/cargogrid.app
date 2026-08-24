-- HDN-376 (Step 15, Prompt 376, API Compatibility Audit, `CG-S15-HDN-008`) -- four
-- independent parallel investigation lenses (REST/GraphQL contract parity; webhook
-- signing/retry/replay/DLQ and idempotency; schema/migration compatibility and
-- cross-cutting idempotency/rate-limit/error-shape/pagination consistency; public/
-- customer/vendor API and deprecation), each required to live-force its own findings
-- on disposable databases rather than accept a code read as proof.
--
-- ===========================================================================
-- Finding 1 -- `app.verify_third_party_provider_webhook_signature` returns SQL NULL,
-- not false, when `p_signature` is null, so `if not app.verify_...(...)` silently
-- treats an entirely UNSIGNED inbound GPS webhook as verified (Critical, live-forced
-- exploit, `anon`-reachable directly via PostgREST)
-- ===========================================================================
--
-- **Live-forced**: `return v_expected = p_signature;` (ATW-226E,
-- `20260729380000_create_advanced_tms_third_party_provider_adapter.sql`) evaluates to
-- SQL NULL, not `false`, whenever `p_signature` is null -- and PL/pgSQL's `if not
-- app.verify_...(...) then <reject> end if;` (the caller, `app.ingest_third_party_
-- provider_webhook_event`) treats a NULL condition as false, so the reject branch is
-- silently skipped. A direct call with `p_signature => null` -- no HMAC secret known
-- at all -- inserted a real `app.third_party_telemetry_reports` row attributed to a
-- real, mapped vehicle, `ingest_status = 'ok'`. `app.ingest_third_party_provider_
-- webhook_event` is granted to `anon`, so this is directly reachable via Supabase
-- PostgREST (`/rest/v1/rpc/ingest_third_party_provider_webhook_event`) with the public
-- anon key, entirely bypassing `app/api/webhooks/third-party-gps/[connectionId]/
-- route.ts`'s own app-layer signature-presence check -- the database function is the
-- actual authoritative boundary here, and it fails open on this one input. Directly
-- violates Prompt 376 §24: "Webhook spoofing and unsigned callbacks fail."
--
-- This exact defect class was already found and fixed twice, in two structurally
-- identical, LATER-built capabilities, and never backported to this older function:
-- `app.verify_logistics_partner_webhook_signature` (`20260805030000_create_operations_
-- customs_integrations.sql`) and `app.verify_finance_payment_webhook_signature`
-- (`20260805040000_create_intelligence_tax_integrations.sql`) both already carry an
-- explicit `if p_signature is null or length(trim(p_signature)) = 0 then return false;
-- end if;` guard this function lacks. Neither `advanced-tms-third-party-provider-
-- adapter.sql` nor `api-key-webhook.sql` had a NULL-signature negative-case test --
-- the coverage gap that let this ship and let the later fix fail to get backported.
--
-- **Fix**: mirror the two sibling functions' own proven guard exactly, plus their own
-- `v_expected is null` defense-in-depth check (a computed-signature failure should
-- also fail closed, not merely rely on `= NULL` evaluating falsy). `p_timestamp is
-- null` is already guarded by this function's own existing first check (unchanged).
--
-- ===========================================================================
-- Finding 2 -- `app.verify_webhook_signature` (PLT-129, the outbound-direction sibling
-- ATW-226E's own comment says this function was "reused verbatim" from) carries the
-- identical latent defect, plus does not guard a null `p_timestamp` either (High,
-- registered-and-fixed together with Finding 1 -- not currently live-exploitable:
-- `service_role`-only grant, zero live caller anywhere in this codebase today, but
-- fixed for consistency and to close the class permanently before anything is ever
-- wired to call it as a live inbound gate)
-- ===========================================================================
--
-- **Fix**: the same two guards (`p_timestamp is null`, `p_signature is null or empty`,
-- `v_expected is null`) added to this function too, mirroring Finding 1's own fix.
--
-- Full disposition: `docs/build-log/full-system-hardening/HDN-376.md` §6.

create or replace function app.verify_third_party_provider_webhook_signature(p_connection_id uuid, p_payload text, p_timestamp bigint, p_signature text)
returns boolean
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_expected text;
begin
  if p_timestamp is null or abs(extract(epoch from now()) - p_timestamp) > 300 then
    return false;
  end if;
  if p_signature is null or length(trim(p_signature)) = 0 then
    return false;
  end if;

  begin
    v_expected := app.compute_third_party_provider_webhook_signature(p_connection_id, p_payload, p_timestamp);
  exception
    when others then
      return false;
  end;
  if v_expected is null then
    return false;
  end if;

  return v_expected = p_signature;
end;
$$;

comment on function app.verify_third_party_provider_webhook_signature is
  'ATW-226E: ADR-0011''s own HMAC-SHA256-over-"<timestamp>.<payload>" scheme plus 5-minute timestamp-tolerance replay window. Fails closed to false for every reason (stale/null timestamp, null/empty signature, unknown/non-webhook connection, mismatched signature) -- never raises, so a caller-distinguishable error class/timing never leaks to an unauthenticated provider. HDN-376 (Data Lineage/API Compatibility Audit): a null p_signature previously evaluated `v_expected = null` to SQL NULL, which `if not verify_...()` silently treats as verified rather than rejected -- live-forced, fixed by an explicit null/empty guard mirroring app.verify_logistics_partner_webhook_signature/app.verify_finance_payment_webhook_signature''s own already-proven pattern.';

create or replace function app.verify_webhook_signature(p_endpoint_id uuid, p_payload text, p_timestamp bigint, p_signature text)
returns boolean
language plpgsql
as $$
declare
  v_expected text;
begin
  if p_timestamp is null or abs(extract(epoch from now()) - p_timestamp) > 300 then
    return false;
  end if;
  if p_signature is null or length(trim(p_signature)) = 0 then
    return false;
  end if;

  v_expected := app.compute_webhook_signature(p_endpoint_id, p_payload, p_timestamp);
  if v_expected is null then
    return false;
  end if;

  return v_expected = p_signature;
end;
$$;

comment on function app.verify_webhook_signature is
  'PLT-129 outbound-direction HMAC verification helper. HDN-376: carried the identical NULL-signature/NULL-timestamp fail-open defect as app.verify_third_party_provider_webhook_signature (ATW-226E, this function''s own documented source) -- not currently live-exploitable (service_role-only grant, zero live caller in this codebase today), fixed here for consistency and to close the defect class before any future caller wires this in as a live inbound gate.';

revoke execute on all functions in schema app from public;
