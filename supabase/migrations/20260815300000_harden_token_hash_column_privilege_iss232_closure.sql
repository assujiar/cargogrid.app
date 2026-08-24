-- ISS-2026-232 closure (docs/runtime/KNOWN_ISSUES.md) -- three tables each store a
-- bearer-token `token_hash` (a one-way SHA-256 digest, never the raw token) but grant
-- `authenticated` a blanket `select on app.<table>`, which under Postgres's additive
-- table/column ACL model exposes `token_hash` to any tenant member with SELECT on the
-- table -- exactly the gap `app.quotation_acceptance_tokens` (the documented precedent
-- these three tables' own comments claim to mirror) was already correctly built to
-- avoid, and exactly the fix pattern `ISS-2026-216` already established at `HDN-377`:
-- revoke the table-level grant entirely, re-grant SELECT on an explicit column list
-- omitting `token_hash`. No RLS/policy change -- this is a column-privilege gap only,
-- additive to whatever row-level scoping each table's own policies already apply.
--
-- No already-applied migration is edited. Column lists below were read directly from
-- each table's live `information_schema.columns`, not assumed from memory.

-- ===========================================================================
-- 1. app.vendor_intake_tokens (PRC-251)
-- ===========================================================================

revoke select on app.vendor_intake_tokens from authenticated;
grant select (
  id, tenant_id, status, intended_email, expires_at, idempotency_key,
  created_by_auth_user_id, created_by, created_at, redeemed_at,
  redeemed_master_record_id, revoked_at, revoked_reason, record_version
) on app.vendor_intake_tokens to authenticated;

-- ===========================================================================
-- 2. app.driver_mobile_tracking_sessions (ATW-226C)
-- ===========================================================================

revoke select on app.driver_mobile_tracking_sessions from authenticated;
grant select (
  id, tenant_id, shipment_leg_tracking_session_id, status, issued_at,
  expires_at, last_seen_at, revoked_at, revoked_reason, created_by, created_at
) on app.driver_mobile_tracking_sessions to authenticated;

-- ===========================================================================
-- 3. app.shipment_tracking_tokens (OPS-180)
-- ===========================================================================

revoke select on app.shipment_tracking_tokens from authenticated;
grant select (
  id, tenant_id, shipment_order_id, status, expires_at, revoked_at,
  revoked_reason, created_by, created_at
) on app.shipment_tracking_tokens to authenticated;
