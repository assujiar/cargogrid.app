# ADR-0009 — Observability platform

Status: ACCEPTED
Date: 2026-07-15   Approver: Runtime build agent (Phase 0 governance authority, per `docs/adr/README.md` §3)   Supersedes/Superseded-by: —
Source candidate: `ADR-CAND-ARCH-026` (`docs/architecture/11_DEVOPS_WORKSTREAM.md` §6/§10)   Owning phase/task: Phase 0 (`CG-S5-PH0-014`, Prompt 93, Observability Baseline)

## Question

`ADR-CAND-ARCH-026` calls for "a single integrated observability platform (logs+metrics+traces+alerting in one product to avoid a four-tool correlation problem) at Phase 0, sized to the MVP tier first ... and upgraded to the Scale-up tier's 'Full dashboard/alert' capability without a tool migration if the chosen product supports both tiers," able to support all 11 `11_*.md` §6.1 dashboards and 8 named alerts with `tenant_id`/`correlation_id` filtering. Which product?

## Options

1. **Better Stack (SELECTED).**
   - Trade-off: single product covering logs, metrics, traces, alerting, on-call/incident management, and uptime monitoring — directly satisfies the "avoid a four-tool correlation problem" criterion without composing separate vendors for each signal. Explicitly "OpenTelemetry-native" (verified this checkpoint via `betterstack.com/logs`, not assumed) — integrates via the vendor-neutral standard rather than a proprietary SDK, so the application-side integration point is Next.js's own official `@vercel/otel`/`instrumentation.ts` mechanism (verified this checkpoint via `nextjs.org/docs/app/guides/open-telemetry` and `vercel.com/docs/tracing/instrumentation`), not a Better-Stack-specific library — avoids vendor lock-in at the code layer even though the backend is a single vendor. Free tier confirmed real and usable for MVP-tier local/CI verification (`betterstack.com/pricing`, this checkpoint): 3 GB logs (3-day retention), 30 GB metrics, 3 GB traces (3-day retention), 10 monitors, Slack/email alerts, 100k tracked exceptions/month — sufficient to stand up and verify the foundation without a paid commitment. Paid tiers (Nano $25–30/mo through Tera $500+/mo, 30-day retention, verified this checkpoint) scale the *same product* to the "Scale-up tier's Full dashboard/alert capability" the candidate requires without a tool migration — directly satisfies that specific requirement.
   - Trade-off against: newer/smaller vendor than Datadog/Grafana Labs; SQL/PromQL query surface (verified) is less universally known than some alternatives' proprietary query languages, but this cuts the other way for a small team (SQL is the more broadly known skill, not a new one to learn).
2. **Grafana Cloud (Loki + Prometheus + Tempo + Alerting).**
   - Trade-off: also single-vendor, also supports all 4 signal types, and is more established. Rejected because — per comparison evidence gathered this checkpoint — its investigation flow requires navigating between separate Explore/APM/infrastructure views per signal (alert → Explore for logs → switch to APM for traces → link to infra panel for metrics), the composed-tool-correlation friction `ADR-CAND-ARCH-026` explicitly wants to avoid, even though it is nominally "one product." Pricing (~$0.50/GB ingested, roughly 2x Better Stack's bundled rate per the same evidence) is also less favorable at MVP-tier volumes.
3. **Axiom.**
   - Trade-off: excellent, verified first-class Vercel/Next.js marketplace integration (zero-config serverless/build/edge log forwarding) and native OpenTelemetry support. Rejected because it is evidenced as strongest specifically as a **log store** and "doesn't integrate deeply with the rest of the observability stack" (metrics/traces/alerting) per the comparison evidence gathered this checkpoint — would still risk the four-tool composition problem for the metrics/alerting/incident-management signals `11_*.md` §6.1 requires (11 dashboards, 8 alerts), several of which are not log-only (DB CPU/connection saturation, queue backlog age, storage signed-URL anomaly volume).
4. **Datadog.**
   - Trade-off: comprehensive, single-vendor, industry-standard. Rejected on cost at MVP-tier sizing — evidenced this checkpoint (via the Better Stack comparison source) as "30x" the cost of the selected option for equivalent ingestion, with no offsetting capability gap `11_*.md` §6's fixed 11-dashboard/8-alert catalogue actually requires at Phase 0/1 scale.
5. **Compose Sentry (errors/traces) + a separate metrics/dashboard product + a separate alerting/on-call tool.**
   - Trade-off: this is precisely the "four-tool correlation problem" `ADR-CAND-ARCH-026`'s own text names and asks to avoid — rejected on that stated criterion alone, not re-litigated further.

## Decision

**Better Stack**, integrated via Next.js's official OpenTelemetry mechanism (`@vercel/otel` + `instrumentation.ts`) once `app/` exists (Phase 1 — no application to instrument yet, `docs/discovery/05_ROUTE_MODULE_INVENTORY.md`). This checkpoint implements the vendor-neutral foundation (`docs/standards/OBSERVABILITY_STANDARDS.md`, `scripts/observability/logger.ts`) that Phase 1's real instrumentation wires into; it does not create a Better Stack account, API key, or export configuration (no secret exists yet to protect, and `AGENTS.md`/§12 forbid "production alert/service mutation" at this checkpoint).

## Evidence

- `docs/architecture/11_DEVOPS_WORKSTREAM.md` §6.1/§6.2 (the exact 5-signal/11-dashboard/8-alert/correlation-ID catalogue this product must support) and §10 (`ADR-CAND-ARCH-026`'s exact question/recommendation/blocking-state).
- `betterstack.com/logs` (fetched this checkpoint): "logs, metrics, and traces," "Incident management & on-call is built-in," "OpenTelemetry-native observability," SQL/PromQL query support.
- `betterstack.com/pricing` (fetched this checkpoint): free-tier limits (3 GB logs/3-day retention, 30 GB metrics, 3 GB traces/3-day retention, 10 monitors, Slack/email alerts, 100k exceptions/month) and paid Nano→Tera bundle pricing (30-day retention).
- Web comparison evidence (fetched this checkpoint, multiple sources) on Grafana Cloud's cross-view investigation friction, Axiom's log-store-first strength/shallow cross-signal integration, and Datadog's relative cost — used only for the specific, attributable claims cited in §Options above, not as an unverified blanket endorsement.
- `nextjs.org/docs/app/guides/open-telemetry` and `vercel.com/docs/tracing/instrumentation` (fetched this checkpoint): confirms `@vercel/otel` + root `instrumentation.ts` is the official, vendor-neutral Next.js integration point — the reason this ADR's *product* choice does not force a proprietary SDK into application code.

## Consequences

- **DB/API/UI (§13/§14/§15):** none — no schema, no endpoint, no UI created; this ADR fixes the vendor decision and the code-side integration *mechanism* (`@vercel/otel`, standard, not Better-Stack-specific) for Phase 1 to use.
- **Security (§16):** no credential exists yet — no Better Stack API key/ingestion token is created or stored this checkpoint; when Phase 1 wires real export, the key is server-only environment configuration per `scripts/env/schema.ts`'s existing classification pattern (`ADR-0003`), never a client-bundled value. `docs/standards/OBSERVABILITY_STANDARDS.md` §4's redaction rules apply before any line reaches this or any other vendor.
- **Performance (§17):** OpenTelemetry's SDK overhead is a Phase-1, real-application concern (nothing to benchmark against yet); `scripts/observability/logger.ts`'s safe-degrade design (§ below) ensures a future exporter outage cannot block a request/job, independent of which vendor is behind it.
- **Migration/rollback:** trivial at this checkpoint — no infrastructure resource exists; reverting this ADR removes only documentation and the vendor-neutral logger utility, with zero coupling to a specific vendor SDK to unwind.
- **Downstream impact:** Phase 1's `instrumentation.ts` (once `app/` exists) registers `@vercel/otel` pointed at Better Stack's OTel ingestion endpoint; `docs/standards/OBSERVABILITY_STANDARDS.md`'s structured-log-field contract and `scripts/observability/logger.ts`'s redaction/correlation helpers are consumed unchanged by that future instrumentation, not re-decided.

## Propagation

Referenced by: `docs/build-log/phase-00/PH0-93.md`; `docs/adr/README.md` §5.2 (marks `ADR-CAND-ARCH-026` `ACCEPTED`) and §6 (index); `docs/standards/OBSERVABILITY_STANDARDS.md` (this checkpoint, full signal/field/redaction/retention convention built on this ADR's vendor choice); `scripts/observability/logger.ts` (vendor-neutral foundation code). Does not alter any CPD/RPD or any `docs/architecture/**` decision.
