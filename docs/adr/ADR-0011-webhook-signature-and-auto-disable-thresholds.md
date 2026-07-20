# ADR-0011 — Webhook signature scheme, timestamp tolerance, and auto-disable threshold

Status: ACCEPTED
Date: 2026-07-19   Approver: Runtime build agent (Phase 1 governance authority, per `docs/adr/README.md` §3)   Supersedes/Superseded-by: —
Source candidate: `ADR-CAND-ARCH-018` (partial — the signature/timestamp/auto-disable sub-question only; the rate-limit-numeric-threshold sub-question remains open, see Consequences)   Owning phase/task: Phase 1 (`CG-S6-PLT-026`, Prompt 129, API Key and Webhook Primitives)

## Question

`docs/architecture/08_API_INTEGRATION_WORKSTREAM.md` §14 (`ADR-CAND-ARCH-018`) asks: what HMAC algorithm and timestamp-tolerance window should outbound webhook signing use (§7.3), and at what consecutive-failure count should a webhook endpoint auto-disable (§7.4)? Tech Arch §25.7/§25.8/§26 name the dimensions and requirement but no numeric values anywhere in the blueprint.

## Options

1. **HMAC-SHA256 signing, 5-minute timestamp tolerance, 10-consecutive-failure auto-disable (SELECTED — the candidate's own recommendation, `08_*.md` line 234).**
   - Trade-off: HMAC-SHA256 is the industry-standard webhook signing algorithm (Stripe, GitHub, Shopify all use it) — well-understood by any tenant/vendor integrator, natively available via PostgreSQL's already-enabled `pgcrypto` extension (`hmac(data, key, 'sha256')`, no new dependency — `pgcrypto` was enabled unconditionally at `PLT-105`). A 5-minute tolerance window is wide enough to absorb realistic clock skew and network latency between signing and verification, narrow enough to make a captured-signature replay attack impractical without also compromising the raw payload within that window. A 10-consecutive-failure threshold gives a struggling receiver several realistic retry cycles (with exponential backoff, so 10 consecutive failures spans a meaningful elapsed time, not 10 rapid-fire attempts) before the platform stops wasting delivery attempts against a permanently broken endpoint — auto-disable is reversible (`app.reenable_webhook_endpoint()`), so the cost of a wrong threshold is low.
   - Trade-off against: these are still judgment calls, not values derived from CargoGrid's own measured traffic (none exists yet, this repository is still Phase 1 Platform Core with no live tenant traffic). Explicitly disclosed as the same class of reasoned default `ADR-0002`/`ADR-0004` already used for CI/CD/package-manager choices absent blueprint-mandated numbers.
2. **A different/weaker signing scheme (e.g. HMAC-SHA1, plain shared-secret comparison with no HMAC) or no timestamp tolerance / auto-disable at all.**
   - Trade-off: HMAC-SHA1 is deprecated for new designs (collision resistance concerns, no meaningful benefit over SHA-256 which is equally available); no timestamp tolerance makes every legitimate delivery attempt with any clock skew fail closed unpredictably; no auto-disable threshold means a permanently broken endpoint would receive retries indefinitely, wasting delivery-worker capacity forever. Rejected — strictly worse on every axis with no offsetting benefit.

## Decision

**HMAC-SHA256** signing of `"<unix_timestamp>.<payload>"` (the timestamp-prefixed payload pattern preventing a captured signature from being replayed against a different payload), a **5-minute (300 second)** timestamp tolerance window, and a **10-consecutive-failure** auto-disable threshold for webhook endpoints. Implemented as real, tested database functions in `supabase/migrations/20260719150000_create_api_key_webhook_primitives.sql`: `app.compute_webhook_signature()`/`app.verify_webhook_signature()` (the signing/verification pair — genuinely provable without a live HTTP call, since HMAC computation is pure cryptographic computation, not network I/O) and `app.record_webhook_delivery_attempt()`'s auto-disable branch (increments `app.webhook_endpoints.consecutive_failure_count` on failure, disables at the threshold, resets to zero on the next success).

## Evidence

- `docs/architecture/08_API_INTEGRATION_WORKSTREAM.md` §7.3/§7.4 (dimensions named, no numeric value) and §14 (`ADR-CAND-ARCH-018`'s exact question and recommendation, line 234: "Adopt HMAC-SHA256 signing with a 5-minute timestamp tolerance ..., a 10-consecutive-failure auto-disable threshold").
- `supabase/migrations/20260716075355_create_tenants.sql:19` — `create extension if not exists pgcrypto;` — confirms `hmac()`/`digest()`/`gen_random_bytes()` are already available with zero new extension dependency.
- `docs/build-log/phase-01/00_PLATFORM_CORE_EXECUTION_INDEX.md` row `026` — this task (`CG-S6-PLT-026`) is the named owning task ("resolve at Phase 1 `API-WH` implementation").

## Consequences

- **DB/API:** `app.webhook_endpoints.consecutive_failure_count`/`auto_disabled_at`/`disabled_reason` are the physical auto-disable mechanism; `app.compute_webhook_signature()`/`app.verify_webhook_signature()` are the physical signing mechanism, both proven directly in `scripts/db-tests/api-key-webhook.sql` (a tampered payload fails verification; a stale timestamp outside the 5-minute window fails verification; 10 consecutive `record_webhook_delivery_attempt(status='failed')` calls auto-disable the endpoint; the next success resets the counter).
- **Security:** the timestamp-prefixed signed payload is the concrete answer to replay-attack resistance this ADR's window closes; the raw webhook secret is stored server-side only (`service_role`-only table access, never exposed to `authenticated` after the one-time create/rotate response) — this ADR fixes the algorithm, not the storage model (already fixed by this same migration's own design, disclosed in `docs/build-log/phase-01/PLT-129.md`).
- **Performance:** none — HMAC-SHA256 over a typical webhook payload is sub-millisecond; no measurable cost versus a weaker scheme.
- **Migration/rollback:** additive — no prior webhook signing mechanism exists anywhere in this repository to migrate away from.
- **Downstream impact / what remains open:** `ADR-CAND-ARCH-018`'s rate-limit-numeric-threshold sub-question (per-`06_*.md`-§6-dimension request-rate values) is **not** resolved by this ADR — no live API gateway/request-rate-enforcement point exists yet anywhere in this repository (Prompt 130, REST/GraphQL Platform API Foundation, is still `BLOCKED`); `app.api_keys.rate_limit_per_minute` is a real, stored, validated numeric field this migration adds, but its *enforcement* against real inbound request volume is disclosed `NOT_RUN` until that future capability exists. `ADR-CAND-ARCH-018`'s batch-operation-size-limit sub-question (§4.9) belongs to the bulk import/export job framework (Prompt 131), not this capability, and is left untouched here.

## Propagation

Referenced by: `docs/build-log/phase-01/PLT-129.md`; `docs/adr/README.md` §5.2 (marks `ADR-CAND-ARCH-018` partially `ACCEPTED` — signature/timestamp/auto-disable sub-questions only) and §6 (index). Does not alter any CPD/RPD or any other `docs/architecture/**` decision.
