# CargoGrid Observability Foundation

**Established by:** `CG-S5-PH0-014` (Prompt 93 — Observability Baseline)
**Status:** Active — vendor decided (`ADR-0009`), structured-log/correlation/redaction/cardinality/retention conventions fixed, vendor-neutral logger utility implemented and tested (`scripts/observability/logger.ts`). **No real export/dashboard/alert exists yet** — no Better Stack account, API key, or `instrumentation.ts` registration (no `app/` to instrument, `docs/discovery/05_ROUTE_MODULE_INVENTORY.md`; Phase 1 scope, same discipline `PH0-90`/`PH0-91`/`PH0-92` applied to components/domain factories/audience-facing docs).

This document distills `docs/architecture/11_DEVOPS_WORKSTREAM.md` §6 (already `VERIFIED`, not re-derived) plus `ADR-0009` (this checkpoint) against what is actually buildable before `app/`/`server/` exist.

## 1. Signals, dashboards, alerts (reproduced by reference, `11_*.md` §6.1)

- **5 signals:** Logs (app, API, job, webhook, auth/security), Metrics (latency, error rate, throughput, DB query duration, queue depth), Traces (request → server action/API → DB → external call), Audit (business/security change — `05_*.md` §6's append-only tables), Alerts (Sev1 errors, auth anomaly, RLS failure, job backlog, webhook failure).
- **11 dashboards:** Application health, API health, Database performance, Slow query, Queue/job health, Integration health, Tenant usage and errors, Security events, Financial posting exceptions, Storage usage, Import/export jobs. Fixed catalogue — no domain adds a twelfth without extending `11_*.md` §6.1 first.
- **8 alerts:** API p95 latency, error rate, DB CPU/connection saturation, slow query, queue backlog age, webhook failure, **cross-tenant policy test failure (immediate Sev1, no threshold delay)**, storage signed-URL anomaly.
- **Business rule restated (`11_*.md` §6, `AGENTS.md`):** logs are not audit substitutes — audit (`05_*.md` §6's five append-only log tables) has stronger retention/access semantics (§5 below) and is never satisfied by a diagnostic log line alone.

None of the above is wired yet — this checkpoint fixes the contract every dashboard/alert will bind to once `app/` exists (§7's `NOT_RUN` table).

## 2. Correlation ID contract (`08_*.md` §4.7, reproduced not re-derived)

- **Header:** `X-CargoGrid-Request-Id`, generated per request if absent.
- **Field:** `correlation_id`, written to every log/trace/audit row a request produces — the single thread a support engineer filters every one of the 11 dashboards by (§6.2's "tenant-aware diagnostics" made concrete).
- **Generation (this checkpoint, `scripts/observability/logger.ts`):** `crypto.randomUUID()` in real/production paths (Node built-in, no dependency); tests inject a fixed ID for determinism, never `crypto.randomUUID()` in an assertion (matches `tests/factories/seed.ts`'s existing "no wall-clock/non-reproducible source in a test" rule, `TESTING_STANDARDS.md` §4).
- **Propagation:** every downstream call within a request (server action → DB → external call, per §1's Traces signal) carries the same `correlation_id` — this is a Phase 1 wiring concern (needs `app/`/`server/` to propagate through); this checkpoint provides the generator/validator, not the propagation itself (§7).

## 3. Structured log event shape

Every log line `scripts/observability/logger.ts` emits is one JSON object with exactly these top-level fields — no ad hoc shape:

| Field | Type | Required | Notes |
|---|---|---|---|
| `timestamp` | ISO 8601 string | Yes | UTC |
| `severity` | `"debug"｜"info"｜"warn"｜"error"｜"critical"` | Yes | Ordered (§4) |
| `event` | string | Yes | Namespaced, e.g. `job.failed`, `auth.denied` — stable, greppable, never free text |
| `message` | string | Yes | Human-readable. **Not mechanically redacted** — free-text secret detection is unreliable (§4); never place a raw secret/PII value directly in `message`, pass it via `fields` instead, where `redact()` mechanically strips it |
| `correlation_id` | string | Yes | §2 |
| `source` | `"api"｜"job"｜"webhook"｜"db"｜"auth"｜"system"` | Yes | Which of §1's 5 signal categories this line belongs to |
| `tenant_id` | string | No | A structured **log field**, not a metrics **label** (§5 draws this exact distinction) |
| `fields` | `Record<string, JSONValue>` | No | Extra structured data — redacted (§4) before inclusion, never raw request/response bodies |

## 4. Redaction

Extends `scripts/env/redact.ts`'s existing `fingerprint()`/`describeForAudit()` pattern (`ADR-0003`'s environment-schema validation work, `PH0-86`) from environment variables to any log field. `scripts/observability/logger.ts`'s `redact()`:

- Matches key names against a fixed sensitive-key pattern list (case-insensitive): `secret`, `password`, `token`, `key`, `authorization`, `cookie`, `ssn`, `npwp` (Indonesia tax ID), `bank`, `account_number`, `salary`, `payroll` — matches `AGENTS.md`'s "Indonesia tax/payroll logic" and "Service-role credentials are server-only" rules extended to logging.
- Replaces a matched value with `fingerprint(value)` (non-reversible, length+hash only, same function `scripts/env/redact.ts` already uses for evidence-readback) — never the literal value, and never a naive `***` mask that leaks length/shape for a short secret.
- Applies **before** a value ever reaches the emitted `fields` object — `logger.ts`'s public logging functions call `redact()` internally on `fields`; there is no bypass path that logs an un-redacted `fields` object. `message` is a caller-discipline surface, not a mechanically redacted one (§3) — this is a real, disclosed limitation, not silently assumed covered.
- **Never a substitute for not collecting the value in the first place** — the correct fix for a field that should never appear in a log is to omit it upstream, not rely on redaction as the only control (defense in depth, matches `AGENTS.md`'s secrets discipline).

## 5. Cardinality (tenant-safe dimensions)

Restates `11_*.md`'s business rule (Prompt 93 §24: "Tenant identifiers use safe pseudonymous/bounded dimensions") as a concrete, enforced distinction:

- **Log/trace/audit field** (§3's `tenant_id`): unbounded cardinality is fine — one log line per request, `tenant_id` is a lookup key, not an aggregation dimension.
- **Metric label/dimension** (Phase 1, once real metrics are emitted): must come from a fixed, bounded allowlist (`source`, `severity`, `event` — all closed enums or namespaced-but-finite strings per §3). `tenant_id`, `correlation_id`, or any free-text value is **never** used as a metric label — one label value per tenant would explode cardinality across thousands of tenants, the exact failure mode `11_*.md` §6/Prompt 93 §17 warns against. `scripts/observability/logger.ts`'s `assertBoundedDimension()` enforces this today for the values this checkpoint's code can already produce (`severity`, `source`); it is the same guard Phase 1's real metrics-emission code reuses rather than re-inventing.

## 6. Retention (RPD-025, reproduced verbatim per `11_*.md` §6.3)

Finance/tax records 10 years; audit/security 7 years; operational data contract term + 90 days; backups 35 days; legal hold overrides deletion. Logs/metrics/traces fall under "operational data" **unless** they contain audit/security content (`05_*.md` §6's `audit_logs`/`support_access_logs` tables), in which case the 7-year class applies to that row, not the 35-day backup class. A vendor's own default retention setting (§1 — Better Stack's 3-day free-tier / 30-day paid-tier log retention, `ADR-0009`) is never treated as an override of this schedule; Phase 1's real export configuration must set retention consistent with RPD-025, upgrading the vendor tier if the default is shorter than the applicable class.

## 7. What is `NOT_RUN` yet (Prompt 93 §22 "Alternative flow" — named, not silently skipped)

| Item | Why not real yet | Owning future task |
|---|---|---|
| Real log/metric/trace export to Better Stack | No `instrumentation.ts`/`app/` exists to register `@vercel/otel` against | Phase 1, first `app/` slice |
| 11 dashboards / 8 alerts wired | Same — no telemetry is being exported yet | Phase 1, incrementally per `11_*.md` §11's atomic backlog |
| Health/readiness endpoints (`/api/health`, `/api/ready`) | No `app/` route exists | Phase 1 Platform Core. Contract fixed now: `/api/health` returns `{status: "ok"}` with no dependency check (liveness); `/api/ready` additionally checks DB connectivity and returns `503` with `{status: "degraded", reason: [...]}` on failure (readiness) — never a false "ok" (Prompt 93 §23 "misleading health blocks rollout") |
| Correlation-ID propagation through server action → DB → external call | No `server/` layer exists | Phase 1, shares infrastructure with `tests/factories/seed.ts` per `11_*.md` §11's atomic-backlog note |
| DB/queue/webhook metrics (latency, queue depth, DLQ age) | No database/job queue exists yet | Phase 1 Platform Core (`05_*.md` §3's `jobs` table) |

## 8. Safe-degrade rule (Prompt 93 §22, binding)

`scripts/observability/logger.ts`'s every public function wraps its actual sink call (today: `console`/`process.stderr`; Phase 1: the real OTel exporter) in a try/catch that **never rethrows** — a telemetry failure degrades to a best-effort local fallback (write to `stderr` if the primary sink throws) and never blocks, fails, or delays the caller's real request/job/transaction. This is the mechanical enforcement of "a foundation request/job failure is traceable... without losing critical audit" (§21 "Main flow") and "telemetry backend unavailable and application degrades safely" (§22) — proven by a real test that simulates a throwing sink and asserts the caller's own return value is unaffected (§9).

## 9. Test evidence this checkpoint

`scripts/observability/logger.test.ts` proves: (1) every emitted log line matches §3's required-field shape; (2) `redact()` actually redacts every sensitive-key-pattern match and never leaks the literal value, reusing `scripts/env/redact.ts`'s existing `fingerprint()` (itself exercised via `scripts/env/validate.test.ts`, which imports it) rather than a second, independently-invented redaction mechanism; (3) severity ordering is correct and total; (4) `assertBoundedDimension()` accepts an allowlisted value and rejects/warns on an out-of-allowlist one; (5) a simulated sink failure (thrown error) does not propagate to the caller — the safe-degrade rule (§8) holds under real failure injection, not merely asserted in prose.
