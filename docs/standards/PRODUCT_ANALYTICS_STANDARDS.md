# CargoGrid Product Analytics Foundation

**Established by:** `CG-S5-PH0-018` (Prompt 97 — Product Analytics Baseline)
**Status:** Active — event taxonomy, consent model, prohibited-field/oversized/duplicate rejection, pseudonymization, and a vendor-neutral, tested wrapper are implemented today. **No analytics provider is integrated** — Prompt 97 §12 explicitly forbids "unapproved vendor integration," and no `docs/blueprint/**`/`docs/architecture/**` document names a specific provider or raises an `ADR-CAND-ARCH-0NN` for one (confirmed via grep, unlike `ADR-CAND-ARCH-026` for observability). Provider selection is therefore an open, disclosed `ADR_REQUIRED` item for whichever Phase 1 prompt first needs real delivery (§6), not invented here.

This document distills `docs/blueprint/01_CargoGrid_Project_Product_Charter.md` (Phase 0 deliverable "product analytics plan," risk `R-18` "Analytics workload harms transactions," risk area "Product analytics | Operating | Weak adoption insight | Instrumentation from early releases") plus `docs/standards/DATA_CLASSIFICATION_STANDARDS.md` (prohibited-field categories, reused not re-derived) and `docs/standards/OBSERVABILITY_STANDARDS.md` (the safe-degrade pattern this checkpoint's `track()` reuses).

## 1. Purpose, ownership, and the "not audit" boundary (Prompt 97 §24)

Product analytics measures adoption and workflow quality (Charter's "weak adoption insight" risk) — it is explicitly **not** a business audit or system of record (§24, restated verbatim): a fact that only exists in an analytics event and nowhere else in `docs/architecture/05_DATABASE_SCHEMA_WORKSTREAM.md`'s canonical schema is not a fact CargoGrid can rely on. Every event's purpose, owner, schema version, and retention is declared before the event ships (§4's adoption gate) — collecting "whatever might be useful later" is exactly what §24's "minimum necessary data for documented purpose/retention" rule forbids.

## 2. Event taxonomy and schema

- **Naming:** `<domain>.<action>` (lowercase, `snake_case` within each segment) — e.g. `quote.created`, `shipment.status_changed` — mirrors `scripts/observability/logger.ts`'s namespaced `event` field convention, the same pattern applied to a second signal type.
- **Required envelope fields** (`scripts/product-analytics/analytics.ts`'s `AnalyticsEvent`): `event` (name), `version` (schema version, starts at `1`), `timestamp`, `pseudonymousId`, `tenantRef`, `context` (`source`: `web`/`api`/`job`, optional `appVersion`), `consentState`, `eventId` (for dedup), and optional `properties`.
- **Versioning:** a breaking change to an event's `properties` shape increments its own event-level version tracked alongside the event definition (Phase 1, once a real event-definition registry exists per §4) — this checkpoint fixes the envelope's `version` field mechanism, not a populated per-event version table (no event is defined yet beyond this foundation's own smoke fixtures).

## 3. Consent and prohibited-field rules (Prompt 97 §16/§22, real and enforced today)

- **Consent gate:** `isConsentGranted(state)` — an event is only delivered when `consentState` is `granted` or `not_required` (a Phase-0-system event with no personal data attached, e.g. a synthetic smoke event); `denied` always short-circuits to `{ delivered: false, reasons: ["CONSENT_NOT_GRANTED"] }`, never silently dropped-but-unreported.
- **Prohibited fields:** `findProhibitedProperties()` rejects any event `properties` key matching a secret/PII/finance/payroll/tax/bank pattern — deliberately broader than `scripts/observability/logger.ts`'s redaction list (that list *redacts and still logs*; this one *rejects the whole event*, since Prompt 97 §16 says "prohibit," not "mask," and an analytics payload has no operational-debugging need `logger.ts`'s redact-and-keep design serves). Ties directly to `docs/standards/DATA_CLASSIFICATION_STANDARDS.md` §3's categories: any property whose key resembles a `pii`/`finance`/`payroll`/`security_credential` field is rejected outright, never forwarded even redacted.
- **Oversized payload:** `properties` exceeding 8 KiB (serialized) is rejected — a bounded ceiling preventing accidental large-object capture (Prompt 97 §23 "oversized ... event is rejected").
- **Pseudonymous/tenant identifiers:** `pseudonymizeId(rawId, salt)` is a real `HMAC-SHA256` (Node `node:crypto`, no dependency) — deterministic per salt (the same real user/tenant always pseudonymizes to the same value, so funnel/retention analysis still works) and non-reversible without the salt. **Disclosed limitation:** this checkpoint's own tests use a fixed development salt (`tests/factories/seed.ts`-style determinism, not a secret) — Phase 1's real wiring must source `salt` from a `secret`-classified environment variable (`ADR-0010`'s mechanism), registered in `scripts/data-classification/registry.ts`'s `PHASE_0_REGISTRY` the moment that variable is declared, per that registry's own adoption gate (`docs/standards/DATA_CLASSIFICATION_STANDARDS.md` §7) — not silently exempted from it.

## 4. Delivery: batching, dedup, safe disablement (Prompt 97 §20 task 3, §22)

- **Dedup:** `Deduplicator` (in-memory `Set`-backed, per-process) rejects a repeated `eventId` within the same process lifetime — Phase 1's real delivery layer extends this with a durable, time-windowed store once a real queue/cache exists (`NOT_RUN`, §6); the in-memory version is the correct foundation shape, not a placeholder with different semantics.
- **Safe disablement (§22, binding):** `track()`'s `enabled` flag models "consent/provider/config absent" — when `false`, every call returns `{ delivered: false, reasons: ["DISABLED"] }` immediately, with **zero** validation/sink work attempted, so a disabled/unconfigured analytics layer can never itself become a source of slowdown or error in the product flow it instruments.
- **Sink failure (§23, "provider outage ... dropped by documented policy"):** `track()`'s sink call is wrapped in `try/catch` and never rethrows — the exact safe-degrade design `scripts/observability/logger.ts`'s `emit()` already established for a different signal type, applied here to analytics delivery. A sink failure returns `{ delivered: false, reasons: ["SINK_ERROR"] }`; the caller's real request/job is never blocked or failed by an analytics-delivery problem.
- **Batching:** the real batching *transport* (buffer N events, flush on interval/size) is a Phase 1 concern once a real provider/HTTP sink exists (§6) — `track()`'s per-event, sink-injectable design is the shape that transport wraps, not re-designed by it.

## 5. Performance (Prompt 97 §17)

`track()` never performs a network call itself — the injected `sink` does, and only when `enabled=true` and validation passes. The `Deduplicator`'s `Set` lookup is O(1) amortized; `findProhibitedProperties()`/`validateEventName()` run once per event on a small object, not per-row in a loop — no measured overhead exists yet (nothing is wired to a real UI/server call), consistent with `docs/standards/TESTING_STANDARDS.md` §7's `NOT_RUN` framing for anything requiring a real application to benchmark.

## 6. What is `NOT_RUN` yet (named, not silently skipped)

| Item | Why not real yet | Owning future task |
|---|---|---|
| Analytics provider integration | No provider is approved (Prompt 97 §12 forbids unapproved vendor integration); no `ADR-CAND-ARCH-0NN` exists for this decision | Phase 1, first prompt needing real delivery — must raise and resolve the ADR first |
| Real pseudonymization salt (secret-classified) | No environment variable/secret exists yet | Phase 1, registered via `scripts/data-classification/check-registry.ts`'s adoption gate the moment it is declared |
| Durable, time-windowed dedup store | No queue/cache exists yet | Phase 1 Platform Core |
| Batching/flush transport | No real sink/HTTP client exists yet | Phase 1, together with the provider ADR |
| Per-event definition registry (owner/purpose/schema/version/trigger per `docs/standards/PRODUCT_ANALYTICS_STANDARDS.md` §2) | No real product event has been defined yet — this foundation has smoke fixtures only, not domain events | Each Phase 1+ capability prompt that instruments its own first event |
| Data-quality monitoring dashboard | No events are flowing yet | Phase 1, once the provider ADR resolves |

## 7. Test evidence this checkpoint

`scripts/product-analytics/analytics.test.ts` proves: (1) event-name/prohibited-field/oversized/consent validation each independently reject a bad input and accept a good one; (2) `pseudonymizeId` is deterministic per salt and produces different output for a different salt or a different raw ID — proven with real `HMAC-SHA256` output, not asserted in prose; (3) `Deduplicator` rejects a repeated ID and accepts a new one; (4) `track()`'s safe-disablement returns immediately with zero sink/validation work when `enabled=false`; (5) `track()`'s safe-degrade never rethrows a real sink failure, mirroring `scripts/observability/logger.ts`'s own proven failure-injection tests.
