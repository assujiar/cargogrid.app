# Key and secret rotation (scheduled and emergency) — Runbook

**Template ID:** `CG-DOCS-RUNBOOK-001` (instantiated from `docs/templates/SUPPORT_RUNBOOK_TEMPLATE.md`)
**Template version:** `0.1.0`
**Audience:** Support, DevOps/on-call, Security — see `docs/standards/DOCUMENTATION_STANDARDS.md` §2
**Status:** `ACTIVE`
**Owner:** DevOps / Security
**Since:** Phase 15 (`HDN-378`, Prompt 378 Security Hardening)
**Severity class:** Routine (scheduled rotation, per key class's own recommended cadence) or Critical (emergency rotation of a suspected-compromised value — coordinate with `docs/runbooks/incident-response.md` or `docs/runbooks/secret-leak-incident-response.md` if the trigger is a leak, not a schedule). Adapted from the single-incident-shaped template: this covers a recurring operational task, not one historical incident — §7 (rehearsal history) and §1 (trigger) are read as "what starts a rotation cycle," not "what alert fires."

## 1. Symptom / trigger

**Scheduled:** a key class's own recommended rotation interval has elapsed (no fixed platform-wide cadence exists today — set one per tenant/key class based on the sensitivity of what it grants; §6 records this as an open follow-up). **Emergency:** the specific credential is suspected compromised (leaked, logged in plaintext, held by an offboarded identity, or implicated in an incident under `docs/runbooks/incident-response.md`) — treat emergency rotation as immediate, not batched with the next scheduled cycle.

## 2. Impact

Scoped to whatever the specific key/secret grants — tenant-isolation implication (`AGENTS.md`): every SQL-level primitive below is tenant-scoped by the row it rotates (an `app.api_keys`, `app.integration_connections`, `app.webhook_endpoints`, or `app.third_party_provider_connections` row each carry their own `tenant_id`), so rotating one tenant's key never touches another tenant's. `SUPABASE_SERVICE_ROLE_KEY` (§5) is the one exception — it is a single project-wide credential, not a per-tenant row, so its compromise or rotation affects every tenant simultaneously.

## 3. Diagnosis steps

1. Identify the key class (API key / integration connection credential / webhook secret / third-party provider webhook secret / the Supabase service-role key itself) — each rotates through a different primitive (§4) with a different overlap/immediacy model; do not assume one shape fits all.
2. For an emergency rotation, confirm via `app.query_audit_logs` (`docs/runbooks/incident-response.md` §3) whether the credential has already been used since the suspected compromise — this determines whether §4's rotation alone is sufficient or whether `docs/runbooks/incident-response.md`'s broader identity/session response is also needed.
3. For API keys and integration connections specifically, confirm the caller holds the required authority before attempting rotation (`app.check_api_key_manage_authority` for API keys — Supreme Admin/tenant_admin **or**, since `IAE-010`, the customer `account_admin` for their own account-scoped key; `INTHUB:Configure` for integration connections) — a failed rotation due to `insufficient_authority` is not itself a diagnosis dead-end, it means escalate to an identity that holds the grant, same as `docs/runbooks/incident-response.md` §4's rollback note.

## 4. Resolution steps (per key class)

### 4.1 API keys — `app.rotate_api_key` / `app.revoke_api_key`

`app.rotate_api_key(p_key_id uuid, p_overlap_minutes integer, p_actor_auth_user_id uuid, p_actor_label text)` (`supabase/migrations/20260809100000_harden_intelligence_iae037_security_ai_hardening.sql`, latest `CREATE OR REPLACE` — an `IAE-037` Tier C fix on top of the original `PLT-129`/`IAE-010` body). Verified behavior as of this checkpoint:

- Row-locks the source key (`FOR UPDATE`) before acting, so two concurrent/retried rotation calls against the same key cannot race.
- Requires the key's current `status = 'active'` **and** independently re-checks real-time expiry (`v_old.expires_at <= now()`) rather than trusting the stored `status` column alone — a key can read `status = 'active'` after genuinely expiring (the lazy-expiry transition elsewhere in the system rolls itself back), so this closes a defect where rotating an already-expired key used to mint a successor that was dead on arrival. **Rotating an expired key now fails outright** (`api_key_expired`) — mint a brand-new key instead, do not attempt to rotate a lapsed one.
- Guards against double-rotation via `superseded_by_key_id`, not `status` alone (a normal overlap-window rotation deliberately leaves the old key's own `status` at `'active'` during the overlap, so `status` cannot be the double-rotation guard). Attempting to rotate an already-rotated key raises `api_key_already_rotated`, naming the real successor key.
- `p_overlap_minutes` must be between `0` and `10080` (7 days). Pass `0` for immediate rotation (old key revoked instantly, `status = 'revoked'`, `revoked_reason = 'rotated'`) — use this for emergency rotation of a suspected-compromised key. Pass a non-zero value for scheduled rotation with a real overlap window (old key stays valid for that many minutes so real consumers can pick up the new value, then it stops mid-life if the tenant's own `expires_at` was already sooner than the requested overlap).
- Returns the new key's `raw_key` exactly once, in the RPC response — it is not retrievable again after this call returns; hand it to the real consumer immediately.
- Emit-once discipline: the new key inherits the old key's `name`, `scopes`, `rate_limit_per_minute`, and (whichever is sooner) `expires_at` — rotation never silently widens scope or extends an expiry past what was already set.

To revoke without rotating (emergency, no replacement needed yet): `app.revoke_api_key(p_key_id uuid, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)` (`supabase/migrations/20260804020000_create_intelligence_customer_api.sql`, latest `CREATE OR REPLACE`) — idempotent (a repeat call on an already-revoked key returns it unchanged, no error), same authority composition as rotation.

### 4.2 Integration connection credentials — `app.rotate_integration_connection_credential`

`app.rotate_integration_connection_credential(p_connection_id uuid, p_new_credential_value text, p_actor_auth_user_id uuid, p_actor_label text)` (`supabase/migrations/20260803020000_create_intelligence_integration_hub.sql`; unchanged since creation — not touched by any Tier-C pass). `INTHUB:Configure`-gated. **The caller supplies the new credential value directly** — unlike API keys or webhook secrets, this function does not generate a value, because an integration connection's credential originates at the external provider (you rotate the value there first, then call this to record the new value here). Rejects an empty value. Updates `app.integration_connection_credentials.credential_value` and `rotated_at` in place — never returns or audits the credential value itself (confirm this by checking the captured audit event's payload is `'{}'::jsonb`, not the new value).

### 4.3 Webhook secrets — `app.rotate_webhook_secret` / `app.rotate_third_party_provider_webhook_secret`

Two distinct functions for two distinct webhook shapes — do not conflate them:

- `app.rotate_webhook_secret(p_endpoint_id uuid, p_actor_auth_user_id uuid, p_actor_label text)` (`supabase/migrations/20260719150000_create_api_key_webhook_primitives.sql`; unchanged since creation) rotates an **outbound** `app.webhook_endpoints` row's own signing secret — generates a new `whsec_`-prefixed value (`gen_random_bytes(24)`), gated by `app.check_api_webhook_admin_authority`, and replaces the stored secret **immediately, with no overlap window** — the old value stops verifying signatures the instant this call returns. Returns the new `raw_secret` once, in the response.
- `app.rotate_third_party_provider_webhook_secret(p_connection_id uuid, p_actor_auth_user_id uuid, p_actor_label text)` (`supabase/migrations/20260729380000_create_advanced_tms_third_party_provider_adapter.sql`; unchanged since creation) rotates the secret CargoGrid gives an **inbound** third-party provider webhook (`app.third_party_provider_connections`, `integration_mode = 'webhook'` only — raises `not_a_webhook_connection` otherwise) — generates a new `tpws_`-prefixed value (`gen_random_bytes(32)`), `OPS:Edit`-gated, also immediate with no overlap (per the function's own code comment: a webhook secret has exactly one live consumer — the provider's own outbound webhook config — which the operator updates out-of-band at the same time as this call).

Because both are immediate with no overlap window, **rotating either one is a coordinated action**: have the new value ready to push into the counterparty's config (the outbound endpoint's own verifier for `rotate_webhook_secret`, or the third-party provider's dashboard for `rotate_third_party_provider_webhook_secret`) in the same maintenance window as the call — there is no grace period during which both old and new values verify.

### 4.4 `SUPABASE_SERVICE_ROLE_KEY` — Dashboard-only, no SQL primitive

There is no `app.rotate_*` function for the service-role key itself — it is a Supabase **project** credential (Project Settings → API), not an application-level row, so no migration or RPC can touch it. To rotate:

1. Rotate the key in the Supabase Dashboard (Project Settings → API → service role key).
2. **Every deployment environment currently holding the old value must be redeployed with the new one** — there is no in-app propagation mechanism. `lib/supabase/service-role.ts`'s own `requireEnv("SUPABASE_SERVICE_ROLE_KEY")` fails loudly (throws) rather than silently falling back to a stale or empty value if the environment variable is missing after a redeploy — treat a post-rotation failure there as a signal an environment was missed, not a bug to route around. `scripts/env/schema.ts` classifies this variable server-only (`ADR-0003`'s server-only secret convention) — confirm no client-reachable bundle or log ever carries it before and after rotation.
3. Until every environment is redeployed, the old and new keys are both technically valid at the Supabase project level for some window (Supabase's own rotation grace period, not this repository's control) — do not treat that window as a substitute for actually completing the redeploy sweep; an environment left on the old key silently keeps working until Supabase's own grace period ends, then fails closed with no advance warning from this repository's own tooling.

## 5. Communication

Scheduled rotation: no special communication required beyond the normal change log, unless a real external consumer (integration provider, webhook counterparty) needs advance notice to update their own config in step with §4.2/§4.3's coordinated-rotation requirement. Emergency rotation (suspected-compromised key): notify DevOps/Security lead immediately, same urgency as `docs/runbooks/secret-leak-incident-response.md` §5 — a live, unrotated compromised key is never a "batch it with the next cycle" item.

## 6. Post-incident / post-rotation

Record: which key class, which specific row (`app.api_keys.id` / `app.integration_connections.id` / `app.webhook_endpoints.id` / `app.third_party_provider_connections.id`, or "the project service-role key" for §4.4), whether scheduled or emergency, the overlap window chosen (API keys only) or confirmation the coordinated cutover (§4.2/§4.3) completed cleanly with no verification gap, and — for §4.4 — confirmation every environment was actually redeployed (not just that the Dashboard rotation succeeded). **Open follow-up, not resolved by this checkpoint:** no fixed, platform-wide recommended rotation cadence exists per key class today (unlike, say, a documented "rotate API keys every 90 days" policy) — until one is ratified, treat every rotation as either fully scheduled ad hoc or fully emergency-driven, and file the cadence-policy gap itself as a `docs/runtime/KNOWN_ISSUES.md` follow-up if none already exists.

## 7. Rehearsal history

| Date | Type (rehearsal/real) | Outcome | Evidence |
|---|---|---|---|
| — | — | — | Newly created (`HDN-378`) — no rehearsal has been run against this runbook yet. A disposable-database rehearsal exercising §4.1's full overlap-window-then-expire cycle (mint, rotate with a short overlap, confirm the old key still verifies until the overlap elapses, confirm it stops after) is the natural first entry, since it is the one primitive here with time-dependent behavior worth proving live rather than just reading. |

## 8. Revision history

| Date | Version | Change | Author |
|---|---|---|---|
| 2026-08-24 | 0.1.0 | Initial — instantiated from `SUPPORT_RUNBOOK_TEMPLATE.md` at `HDN-378` (Step 15 Full-System-Hardening, Security Hardening). Each SQL-level primitive's behavior verified directly against its latest `CREATE OR REPLACE FUNCTION` body at the time of writing, not assumed from its name. | Claude Code (runtime build agent) |
