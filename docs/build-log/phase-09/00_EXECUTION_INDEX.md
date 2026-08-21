# Phase 9 (Intelligence, Automation and Enterprise Expansion) — Execution Index

**Prompt:** `CG-S14-IAE-001` (329, Intelligence, Automation and Enterprise WBS Runtime Kickoff)
**Runtime output of:** `329_INTELLIGENCE_ENTERPRISE_WBS_RUNTIME_KICKOFF_PROMPT.md`
**Runtime state set by this checkpoint:** `PHASE_9_IN_PROGRESS`
**Owner (every row, this build's standing convention):** Claude Code (runtime build agent)
**Short code:** `IAE` (per every Phase 9 prompt file's own self-declared ID and `00-control/05_REQUIREMENT_COVERAGE_MATRIX.md` §22 — `docs/architecture/13_FULL_WORK_BREAKDOWN_STRUCTURE.md:75`'s `IEP` label is a disclosed, non-blocking documentation defect, `ISS-2026-143`; see `ADR-0025`)

---

## 1. Checkpoint

| Field | Value |
|---|---|
| Repository root | `/home/user/cargogrid.app` |
| Branch | `claude/prompt-328-348-workflow-xtpnrm` |
| HEAD commit (before this checkpoint's own commit) | `aa667caf10cb61c44937ede06fa7da95a1801bdd` (merge of PR #60, `CG-S13-CPL-029`/`028` closure) |
| Worktree | clean at session start (`git status --short` empty before this checkpoint's own first file was written) |
| Checkpoint timestamp | 2026-08-21 |
| Package manager / runtime | `pnpm@10.33.0`, `node@v22.22.2` (`node_modules` did not exist at session start in this container — freshly `pnpm install`ed this checkpoint, 8.8s, zero errors) |
| Migrations applied (count) | 264 files under `supabase/migrations/`, latest `20260801320000_harden_customer_portal_ticket_attachment_file_privacy.sql` |
| `docs/build-log/phase-09/` | Did not exist before this checkpoint — this file is the phase's first artifact |
| Phase 0-8 status | `PHASE_0_VERIFIED` through `PHASE_8_VERIFIED` all set; `PHASE_8_VERIFIED` most recently closed 2026-08-20 at `CG-S13-CPL-029` (Prompt 327), `docs/build-log/phase-08/CUSTOMER_PORTAL_LOYALTY_CLOSURE_REPORT.md` |
| Operator authorization for Phase 9 | Explicit, fresh, separate — the operator's own message this session names the exact range "prompt 328-348" for Phase 9, satisfying `docs/runtime/HANDOFF.md`'s own standing "Step 14 dependency-clean, pending fresh, separate, explicit operator authorization before any Phase 9 work may begin" gate. **This authorization covers only Prompts 329-348** (kickoff plus the first 19 of Phase 9's 34 capabilities); Prompts 349-367 are WBS-mapped by this checkpoint per Prompt 329's own instruction but remain `BLOCKED` pending a further, separate operator authorization before any work begins on them — mirroring exactly how Phase 8's own kickoff scoped "prompt 299-327" without implying phase-wide authorization beyond that range |
| Domain code footprint for Phase 9's own subject matter | `git ls-files app/ lib/ server/ components/ supabase/migrations/ \| grep -iE 'report_engine|dashboard_builder|saved_view|materializ|scheduled_report|automation_rule|integration_hub|public_api|webhook|n8n|openai|\bai_|_ai_|provider_boundary|ocr'` → zero matches for any Phase-9-owned table/route/contract beyond the two Platform Core primitives disclosed in §3 (`app.api_keys`/`app.webhook_endpoints`, `PLT-129`) and one existing per-domain saved-view table (`app.procurement_dashboard_saved_views`, Phase 6), both out-of-Phase-9 prior art, not Phase 9 artifacts |
| Standing quality baseline (re-run fresh this checkpoint; container had no `node_modules`/running Postgres/PostGIS at session start) | `typecheck` 0 errors; `lint` 0 errors / 307 warnings; `pnpm run test` 4823/4824 passing (1 disclosed, non-defect, checkpoint-state-dependent failure — see §8); `bash scripts/db-tests/run.sh` 193/194 files `ALL PASSED` (1 file excluded and newly disclosed, not a Phase 9 defect — see §8) |

---

## 2. Runtime entry verdict — **PASS**

Prompt 329's own entry gate requires `PHASE_8_VERIFIED` at the active repository/schema/environment checkpoint, plus the executor having read the current package manifest, confirmed decision register, source matrix, conflict register, coverage matrix, and Step 13 closure evidence, or the task must stop with `PHASE_9_BLOCKED`.

- `PHASE_0_VERIFIED` … `PHASE_7_VERIFIED`: standing, established at their own respective phase closures.
- `PHASE_8_VERIFIED`: set 2026-08-20 at `CG-S13-CPL-029` (Prompt 327), `docs/build-log/phase-08/CUSTOMER_PORTAL_LOYALTY_CLOSURE_REPORT.md` — independently re-confirmed this checkpoint by reading `docs/runtime/CARGOGRID_BUILD_STATUS.md`'s own current-checkpoint line (§1 row 187) and `docs/runtime/HANDOFF.md`'s own most recent entry, both stating `PHASE_8_VERIFIED` set and Step 14 dependency-clean pending fresh authorization.
- `02_CONFIRMED_DECISION_REGISTER.md`, `04_CONFLICT_REGISTER.md`, `05_REQUIREMENT_COVERAGE_MATRIX.md`, `07_PROMPT_PACKAGE_MANIFEST.md`: read/grepped this checkpoint for every Phase-9-relevant row (`RPD-011..014/017/021/026/028/033/038/040`, `05_*.md` §22's `IAE-328..367` coverage rows, `04_*.md`'s full `CON-001..015` register — no open conflict names Phase 9).
- No unresolved `PHASE_9_BLOCKED`-triggering condition was found.
- Pre-flight collision check (`ISS-2026-002`, mandatory per `AGENTS.md` §"Required pre-flight"): `mcp__github__list_pull_requests` (state=open) on `assujiar/cargogrid.app` → zero open PRs. `mcp__github__list_branches` → 41 branches total, none other than this session's own `claude/prompt-328-348-workflow-xtpnrm` name or reference the 328-367 prompt range or `phase-09`; every branch referencing an earlier phase's prompt range is already merged into `main` (confirmed by `git log --oneline` showing the corresponding merge commits at/before `HEAD`). No parallel-session collision risk for this checkpoint.

**Verdict: entry gate PASSES.** `PHASE_9_IN_PROGRESS` is set by this checkpoint (§13 below). `PHASE_9_VERIFIED` is explicitly **not** set — only Prompt 367 may set it, and it is outside this checkpoint's own authorized range regardless.

---

## 3. Ownership/ADR map (required ownership reconciliation)

| # | Item | Verdict | Basis |
|---|---|---|---|
| 1 | Public/Customer/Vendor API foundation (337-339) vs. the already-shipped `PLT-129` API-key primitives | **RESOLVED — `ADR-0025` Part A.** Extend `app.api_keys` (hash-only storage, scope-narrowing via `app.evaluate_permission()`, overlap-window rotation); no parallel key table. The real REST `/v1` surface and rate-limit enforcement Prompt 130 left `BLOCKED` are this range's own job to complete. |
| 2 | Webhook Management (340) vs. `PLT-129`'s webhook primitives and the existing inbound GPS webhook receiver (343) | **RESOLVED — `ADR-0025` Part B.** 340 builds the real outbound delivery worker on `app.jobs`, calling `app.record_webhook_delivery_attempt()` and seeding real `app.webhook_event_types` rows; 343 keeps its own existing inbound receiver (`app/api/webhooks/third-party-gps/**`) unmerged — inbound and outbound are structurally different directions, never one table/route family. |
| 3 | Integration Hub (336) vs. `RPD-038`'s no-generic-provider-abstraction rule | **RESOLVED — `ADR-0025` Part C.** 336 is a catalog/credential/health/ownership governance layer only, per its own §3/§6 text; provider adapters (342-346) stay case-by-case, shared-code, never tenant-forked, and register into 336's catalog rather than implementing a shared protocol interface. |
| 4 | Automation Rule Engine (335) execution mechanism vs. `RPD-012`'s durable-queue decision | **RESOLVED — `ADR-0025` Part D.** 335 registers new action types into the existing single canonical job-type registry (`20260730410000_harden_job_type_single_source_of_truth.sql`) and enqueues onto `app.jobs`; no second queue/scheduler table. n8n (341) is an optional external trigger/consumer, never a replacement engine. |
| 5 | AI provider boundary (347) and first AI-assisted feature (348) | **CLEAR, genuinely greenfield.** `git ls-files app/ lib/ server/ supabase/migrations/ \| grep -iE 'openai\|\bai_\|_ai_\|provider_boundary\|ocr'` returns zero matches — no prior AI table/contract/route exists anywhere to reconcile against. `RPD-021` (OpenAI multimodal default, mandatory provider boundary, human approval before financial/legal posting) and `RPD-028` (usage-metered AI/OCR billing at provider cost +20%) are the two ratified decisions 347 must build against; both are pre-existing, unimplemented until now. |
| 6 | Reporting Engine (330) live-OLTP query pattern | **CLEAR, already ratified.** `RPD-014`: "Dashboards read transactional data directly... with read-only queries, timeouts, pagination, caching, query budgets, and read replicas when scale requires them." 330 implements this rule for the first time as a dedicated, reusable report-execution engine rather than each domain's own ad hoc dashboard query (e.g. `procurement-dashboard-reports.sql`, `finance-dashboard-reports.sql`, which pre-date this engine and are not required to migrate onto it). |
| 7 | Saved View / Configurable Report (332) vs. the existing `app.procurement_dashboard_saved_views` table | **CLEAR, no collision, disclosed prior art.** `supabase/migrations/20260730780000_create_procurement_dashboard_reports.sql:309` already ships a Procurement-domain-specific saved-view table (Phase 6). 332 builds the first cross-domain, generic saved-view/report-configuration mechanism; it does not rename, migrate, or absorb the Procurement-specific table, which remains valid, working, domain-owned prior art — the same "narrower prior art stays, broader capability is new and additive" shape `ADR-0024` Part A used for `ATW-023`/`ATW-242` versus Phase 8's own broader customer-access RPC layer. |
| 8 | Non-AI provider integrations (342-346) generic-vs-custom shape | **CLEAR, already ratified, same item as row 3.** `RPD-038` is dispositive; no new decision required beyond confirming 336 does not contradict it (row 3). |
| 9 | Enterprise IAM order (354-359, out of this checkpoint's authorized range) | **NOT APPLICABLE to Prompts 329-348.** `RPD-017` (OIDC, then SAML, then SCIM) governs 354, outside this authorization. Recorded here only so a future authorization for 349-367 does not need to re-derive it. |
| 10 | `RPD-004/011/012/013/014/017/021/026/028/033/038/040` contracts and unresolved Critical/High issues | **CLEAR on all counts.** All ten RPD contracts are pre-existing, ratified rows in `02_CONFIRMED_DECISION_REGISTER.md`. **Unresolved Critical/High issues: zero** — independently re-confirmed this checkpoint by column-aware reading of `docs/runtime/KNOWN_ISSUES.md`'s open entries: the highest-severity open items remain Medium (most recently `ISS-2026-142/143/144`), none Critical/High, none blocking. |

**ADR filed this checkpoint:** `docs/adr/ADR-0025-phase9-api-webhook-automation-and-ai-provider-boundary-foundation.md` (Status: ACCEPTED). No other item rose to a genuine, blocking ownership ambiguity requiring a new ADR within this checkpoint's authorized range — items 5-10 above are resolved by direct citation to already-existing, already-ratified repository evidence, or correctly deferred as explicitly out of range.

---

## 4. Required hierarchy — Phase → Workstream → Epic → Capability → Task

Phase 9 decomposes into 34 capabilities across 9 groups (per `00-control/05_REQUIREMENT_COVERAGE_MATRIX.md` §22's own grouping, adopted here rather than re-derived). This checkpoint's operator authorization covers only the first 19 capabilities (groups 1-6, through Prompt 348).

| Workstream (epic) | Capabilities (Prompt / `CG-S14-IAE-NNN`) | Count | In authorized range? |
|---|---|---|---|
| 1. Reporting, Dashboard and Analytics | 330 (`-002`, Reporting Engine), 331 (`-003`, Dashboard Builder), 332 (`-004`, Saved View/Configurable Report), 333 (`-005`, Analytics Materialized Views), 334 (`-006`, Scheduled Reports) | 5 | Yes — Batch 1 |
| 2. Automation and Integration Governance | 335 (`-007`, Automation Rule Engine), 336 (`-008`, Integration Hub) | 2 | Yes — Batch 2 |
| 3. API and Webhook Ecosystem | 337 (`-009`, Public API Platform), 338 (`-010`, Customer API), 339 (`-011`, Vendor API), 340 (`-012`, Webhook Management), 341 (`-013`, n8n Integration) | 5 | Yes — Batch 3 |
| 4. Provider Integrations | 342 (`-014`, Email/WhatsApp/SMS), 343 (`-015`, Maps/GPS/Telematics), 344 (`-016`, Carrier/Port/Airport/Customs), 345 (`-017`, Bank/Payment/eInvoice/Tax), 346 (`-018`, External Accounting/HR) | 5 | Yes — Batch 4 |
| 5. AI Governance and First AI-Assisted Feature | 347 (`-019`, AI Governance Provider Boundary), 348 (`-020`, AI-Assisted Quotation) | 2 | Yes — Batch 5 |
| 6. Further AI-Assisted Capabilities | 349 (`-021`, OCR), 350 (`-022`, Predictive ETA), 351 (`-023`, Optimization), 352 (`-024`, Fraud/Risk), 353 (`-025`, Forecasting/Recommendation) | 5 | **No — requires fresh authorization** |
| 7. Enterprise Security and Governance | 354-359 (`-026..031`) | 6 | **No — requires fresh authorization** |
| 8. Enterprise Deployment, Residency, Scale and DR | 360-363 (`-032..035`) | 4 | **No — requires fresh authorization** |
| 9. Verification, Hardening, Documentation and Closure | 364-367 (`-036..039`) | 4 | **No — requires fresh authorization; never batched per `AGENTS.md`** |

**Total: 34 capabilities = Prompts 330-363**, plus kickoff (329, `-001`), plus 3 non-capability checkpoints (364-366) and 1 closure (367) = 39 total WBS rows. **This checkpoint authorizes and releases only groups 1-5 (19 capabilities, Prompts 330-348)**; groups 6-9 (20 rows) are WBS-mapped per Prompt 329's own instruction but held `BLOCKED` pending separate authorization, not implied by this checkpoint.

---

## 5. Dependency graph

Every one of Prompts 330-348's own declared upstream dependencies (read in full this checkpoint) cites either `IAE-001` (this kickoff) directly, an already-`VERIFIED` Phase 1-8 domain contract, or a strictly lower-numbered `IAE-` ID — the graph is a DAG by construction.

```
IAE-001 (kickoff)
   │
   ├──► Reporting/Dashboard/Analytics track
   │    IAE-002 (330 Reporting Engine) ──► IAE-003 (331 Dashboard Builder)
   │       ├──► IAE-004 (332 Saved View/Configurable Report)
   │       ├──► IAE-005 (333 Analytics Materialized Views)
   │       └──► IAE-006 (334 Scheduled Reports, needs 330's report definitions)
   │
   ├──► Automation/Integration Governance track (needs Platform `app.jobs`, no domain dependency)
   │    IAE-007 (335 Automation Rule Engine)
   │    IAE-008 (336 Integration Hub)
   │
   ├──► API/Webhook Ecosystem track (needs the INTHUB permission-module code
   │    -- seeded by IAE-007's own migration, corrected here by Batch 3's own
   │    Tier C review after this diagram originally, inaccurately, attributed
   │    it to IAE-008 -- plus PLT-129 primitives; Batch 3 never actually
   │    touches any IAE-008/Integration Hub table or function)
   │    IAE-007 ──► IAE-009 (337 Public API Platform) ──► IAE-010 (338 Customer API)
   │                                                   └─► IAE-011 (339 Vendor API)
   │    IAE-012 (340 Webhook Management) ──► IAE-013 (341 n8n Integration)
   │
   ├──► Provider Integrations track (needs 336's catalog; each independent of the others)
   │    IAE-008 ──► IAE-014 (342), IAE-015 (343), IAE-016 (344), IAE-017 (345), IAE-018 (346)
   │
   └──► AI Governance and First AI-Assisted Feature track (needs 001 only; independent of the above)
        IAE-019 (347 AI Governance Provider Boundary) ──► IAE-020 (348 AI-Assisted Quotation,
                                                             the first real consumer of 347's
                                                             provider boundary — deliberately
                                                             held to its own batch so 347 is
                                                             fully VERIFIED, not merely
                                                             COMPLETED, before 348 begins)
```

**Practical batching implication (stated before any code is written, per `AGENTS.md` "Execution cadence"):** this checkpoint plans five implementation batches for the 19 authorized capabilities, following the coverage matrix's own natural capability grouping (§4) rather than a flat five-at-a-time split: **Batch 1** `330-334` (5, Reporting/Dashboard/Analytics); **Batch 2** `335-336` (2, Automation/Integration Governance — deliberately small: both are foundational, first-of-their-kind governance mechanisms every later batch in this range depends on, and 336 is the direct producer for every one of Batches 3-4's own consumers, so keeping this batch small bounds blast radius before 10 downstream capability prompts build on it); **Batch 3** `337-341` (5, API/Webhook Ecosystem); **Batch 4** `342-346` (5, Provider Integrations); **Batch 5** `347-348` (2, AI Governance and first AI-assisted feature — deliberately small and deliberately kept in its own batch after Batch 4 closes: `AGENTS.md` requires cutting a batch short at "a first-of-its-kind security mechanism," and AI provider-boundary governance is exactly that; 348 is included in the same batch as 347 rather than a later one specifically so the dependency graph's own producer/consumer pair is never split across a batch boundary, per the same rule). Batch size narrows adaptively (to ≤4 then ≤3) if a batch closes with a Critical/High finding, per the same standing rule.

---

## 6. Capability-to-decision traceability (Prompts 330-348)

Phase 9 does not use a `CPT-*`/`LYL-*`-style four-item anchor-family scheme — `00-control/05_REQUIREMENT_COVERAGE_MATRIX.md` §22 tracks Step 14 coverage directly by `IAE-NNN` prompt ID against mandatory template field counts, not a separate anchor code. This section maps each of the 19 authorized capabilities to the ratified decision(s) it must build against, so no capability prompt re-derives one ad hoc.

| Capability | Governing decision(s) | Disclosed gate/gap |
|---|---|---|
| 330 Reporting Engine | `RPD-014` (live OLTP, query budgets/pagination/caching) | none — first dedicated engine implementing an already-ratified rule |
| 331 Dashboard Builder | `RPD-014`, `RPD-024` (WCAG 2.2 AA) | none |
| 332 Saved View/Configurable Report | none new — additive alongside `app.procurement_dashboard_saved_views` (§3 row 7) | none |
| 333 Analytics Materialized Views | `RPD-014` (read replica/cache only after measured threshold) | materialized-view refresh cadence is this capability's own design decision, not pre-fixed |
| 334 Scheduled Reports | `RPD-012` (durable queue for async delivery), reuses 330's report definitions | none |
| 335 Automation Rule Engine | `RPD-012`, `ADR-0025` Part D | none — engine reuses `app.jobs`, not a new queue |
| 336 Integration Hub | `RPD-038`, `ADR-0025` Part C | none — governance layer only, ratified this checkpoint |
| 337 Public API Platform | `RPD-033` (REST+GraphQL together — GraphQL parity remains the same disclosed residual gap every phase since 8 has carried, `ADR-0024` Part C), `ADR-0025` Part A | REST is the real transport; GraphQL parity stays a disclosed non-blocking gap, unchanged from precedent |
| 338 Customer API | `ADR-0025` Part A, `ADR-0024` Part A (customer-layer scope narrowing precedent) | none |
| 339 Vendor API | `ADR-0025` Part A | vendor-portal actor-layer scope model does not yet exist as a ratified concept — this capability's own first job, mirroring how `ADR-0024` deferred the Phase 8 "site" scope question to its own first capability (§3 row 5 of that ADR) |
| 340 Webhook Management | `ADR-0025` Part B | none |
| 341 n8n Integration | `RPD-012` (n8n not the primary engine — optional external trigger/consumer only) | none |
| 342 Email/WhatsApp/SMS | `RPD-038`, `ADR-0025` Part C | none |
| 343 Maps/GPS/Telematics | `RPD-038`, `RPD-015` (PostGIS enabled from Platform Core) | reuses/extends the existing inbound GPS webhook receiver (§3 row 2), does not fork it |
| 344 Carrier/Port/Airport/Customs | `RPD-038` | none |
| 345 Bank/Payment/eInvoice/Tax | `RPD-038`, `RPD-016` (Indonesia-first tax, SME-evidence-gated) | any statutory tax-rule content this capability touches remains subject to `RPD-016`'s SME-evidence gate, identical to Finance/HRIS precedent — integration/sync scope only, no new posting authority |
| 346 External Accounting/HR | `RPD-038` | none |
| 347 AI Governance Provider Boundary | `RPD-021`, `RPD-028` | none — genuinely greenfield (§3 row 5) |
| 348 AI-Assisted Quotation | `RPD-021` (advisory-only, human approval before any customer-visible price commitment) | none — first real consumer of 347, held to its own batch (§5) |

No capability in this authorized range is left without a governing decision. Prompts 349-363 (out of range) are covered by the same coverage-matrix groupings (§4) and will receive their own traceability row set at their own future authorization checkpoint, not fabricated here.

---

## 7. File/migration/contract collision matrix

**Effectively clean.** `git ls-files app/ lib/ server/ components/ supabase/migrations/ | grep -iE 'report_engine|dashboard_builder|saved_view|materializ|scheduled_report|automation_rule|integration_hub|public_api|webhook|n8n|openai|\bai_|_ai_|provider_boundary|ocr'` returns zero matches for any Phase-9-owned artifact. The only related pre-existing files are the three disclosed reuse points (§3 rows 1-2, 7): `app.api_keys`/`app.webhook_endpoints`/`app.webhook_event_types` (`PLT-129`, Platform Core, to be *extended*, not duplicated), `app/api/webhooks/third-party-gps/[connectionId]/route.ts` (Advanced TMS/WMS, to be *left alone*, not merged), and `app.procurement_dashboard_saved_views` (Phase 6, to be *left alone*, not renamed/absorbed). None of these three collide with any file this checkpoint or a future Phase 9 capability writes — they are cited, not touched, by this kickoff.

The files this kickoff itself writes (`docs/adr/ADR-0025-*.md`, `docs/build-log/phase-09/00_EXECUTION_INDEX.md`, and this checkpoint's `docs/runtime/*`/`docs/adr/README.md` updates) do not collide with any existing path. Given §5's mostly-parallel-track DAG shape (Reporting/Dashboard/Analytics, Automation/Integration, API/Webhook, Provider Integrations, and AI Governance are five largely independent tracks after `IAE-001`, unlike Phase 8's single-root shape), this checkpoint's own batch plan (§5) still proceeds in strict numeric-batch order per `AGENTS.md`'s standing execution-cadence discipline, not concurrently — a future checkpoint may revisit true parallel release only if it discloses and populates a real collision matrix for two genuinely non-overlapping in-flight batches first.

---

## 8. Baseline/gate matrix

Gate commands independently re-run live at this repository this checkpoint (container had no `node_modules`, no running Postgres, and no PostGIS extension installed at session start — all three provisioned fresh this checkpoint: `pnpm install`, `service postgresql start`, `apt-get install postgresql-16-postgis-3`; the local `postgres` role additionally required a fresh password set to match `scripts/db-tests/run.sh`'s own documented `postgres:postgres@127.0.0.1:5432` convention, since this container's Postgres had none set).

| Gate category | Status | Command / mechanism / result |
|---|---|---|
| Clean install | Real, freshly run | `pnpm install` — 8.8s, zero errors |
| Typecheck | **PASS** | `pnpm run typecheck` (`tsc --noEmit`) — 0 errors |
| Lint | **PASS** | `pnpm run lint` (`eslint .`) — 0 errors, 307 warnings (pre-existing `@next/next/no-html-link-for-pages` class, unchanged from Phase 8's own baseline count, not touched by this checkpoint) |
| Unit/integration tests | **PASS with 1 disclosed, non-defect, checkpoint-state-dependent failure** | `pnpm run test` — 4823/4824 passing. The one failure (`checkWorktreeCollision — against this repository's real state`, `scripts/git/check-worktree-collision.test.ts:26`) is the same class of assertion Phase 8's own kickoff baseline disclosed: it asserts the current branch has commits ahead of `origin/main`; at the moment this baseline ran, this branch had zero new commits yet (freshly checked out). Resolves itself once this checkpoint's own first commit lands — re-run after commit to confirm (see §14). |
| Database/migration/RLS tests | **193/194 files `ALL PASSED`, 1 file excluded and newly disclosed, not a Phase 9 defect** | `bash scripts/db-tests/run.sh` halts (by design, `set -euo pipefail`) at `scripts/db-tests/procurement-vendor-performance.sql:978` — a pre-existing Phase 6 (already `PHASE_6_VERIFIED`) assertion failure (`expected New Vendor rate_validity to be computable`), unrelated to any file this checkpoint touches. Verified by ad hoc re-run excluding only this one file (session-scratchpad script, not committed): all other 193 files pass clean, `ALL PASSED`. Registered as a new, disclosed, non-blocking `KNOWN_ISSUES.md` entry this checkpoint (`ISS-2026-144`) — not fixed here, per `AGENTS.md` "fix only task-caused failures... log unrelated/pre-existing failures and create a separate recovery task"; this is Phase-6-owned capability scope, not Phase 9. |
| Build | Not run this checkpoint | Kickoff writes no `app/`, `components/`, or `"use server"` module — Tier A's `next build` trigger condition (`docs/standards/BUILD_EXECUTION_PROTOCOL.md` §2) is not met. Will run at the first Phase 9 capability prompt that touches those paths (expected: `IAE-002`/Prompt 330, the reporting engine's first UI surface, or earlier if `IAE-003`/331's dashboard shell lands first within Batch 1). |
| `git:check-paths` / `security:check` / `data-classification:check` | Not yet re-run against this checkpoint's own final diff | Will run before commit, per standing pre-commit discipline. |

---

## 9. Critical path

`IAE-001` (this kickoff) is the sole root. Unlike Phase 8's single-root DAG, Phase 9's authorized range (330-348) has five largely independent tracks after the kickoff (§5) — the critical path is therefore the longest of the five tracks, not a single chain through all 19 capabilities. The longest chain is the Reporting/Dashboard/Analytics track: `IAE-001 → IAE-002 (330) → IAE-003 (331) → IAE-004 (332)` and, in parallel from `IAE-003`, `→ IAE-005 (333)` / `→ IAE-006 (334)` — 4 sequential gates deep. The API/Webhook Ecosystem track is the second-longest at 3 gates (`IAE-001 → IAE-007 (335) → IAE-009 (337) → IAE-010 (338)`/`IAE-011 (339)`) — corrected by Batch 3's own Tier C review (§14): the track's real cross-batch dependency is IAE-007's own INTHUB permission-module seed, not IAE-008/Integration Hub, which Batch 3 never actually references. This checkpoint's own 5-batch execution grouping (§5) is a scheduling choice bounded by `AGENTS.md`'s review-cadence discipline, not a dependency requirement — the true critical-path depth within this authorized range is 4 capability-level gates, not 19.

---

## 10. Task state (39 rows; vocabulary restricted to `329_*.md`'s own set: `READY` / `BLOCKED` / `COMPLETED` / `VERIFIED`)

| Task ID | Prompt | Capability | Dependencies | Status |
|---|---|---|---|---|
| `CG-S14-IAE-001` | 329 | Intelligence, Automation and Enterprise WBS Runtime Kickoff | `PHASE_8_VERIFIED` + operator authorization | `COMPLETED` this checkpoint (sets `PHASE_9_IN_PROGRESS`; a kickoff prompt is not itself entered into the `VERIFIED` capability chain, mirroring `CG-S13-CPL-001`'s own final task-state row in `docs/build-log/phase-08/00_EXECUTION_INDEX.md` §10) |
| `CG-S14-IAE-002` | 330 | Reporting Engine | `IAE-001` `COMPLETED` | **`VERIFIED`** 2026-08-21 — Tier A/B clean at commit; Batch 1 Tier C review closed same day (1 finding fixed — see `docs/build-log/phase-09/IAE-330.md` §13). `docs/build-log/phase-09/IAE-330.md` |
| `CG-S14-IAE-003` | 331 | Dashboard Builder | `IAE-002` | **`VERIFIED`** 2026-08-21 — Tier A/B clean at commit; Batch 1 Tier C review closed same day (1 finding fixed — see `docs/build-log/phase-09/IAE-331.md` §13). `docs/build-log/phase-09/IAE-331.md` |
| `CG-S14-IAE-004` | 332 | Saved View and Configurable Report | `IAE-002`, `IAE-003` | **`VERIFIED`** 2026-08-21 — Tier A/B clean at commit; Batch 1 Tier C review closed same day (2 findings fixed — see `docs/build-log/phase-09/IAE-332.md` §13). `docs/build-log/phase-09/IAE-332.md` |
| `CG-S14-IAE-005` | 333 | Analytics Materialized Views | `IAE-002` | **`VERIFIED`** 2026-08-21 — Tier A/B clean at commit; Batch 1 Tier C review closed same day (2 findings fixed — see `docs/build-log/phase-09/IAE-333.md` §13). `docs/build-log/phase-09/IAE-333.md` |
| `CG-S14-IAE-006` | 334 | Scheduled Reports | `IAE-002` | **`VERIFIED`** 2026-08-21 — Tier A/B clean at commit; Batch 1 Tier C review closed same day (6 findings fixed, including the batch's own sole Critical — see `docs/build-log/phase-09/IAE-334.md` §13). `docs/build-log/phase-09/IAE-334.md`. Last prompt of Batch 1 |
| `CG-S14-IAE-007` | 335 | Automation Rule Engine | `IAE-001` | **`VERIFIED`** 2026-08-21 — Tier A/B clean at commit; Batch 2 Tier C review closed same day (6 findings fixed, including 2 Critical — see `docs/build-log/phase-09/IAE-335.md` §13). `docs/build-log/phase-09/IAE-335.md` |
| `CG-S14-IAE-008` | 336 | Integration Hub | `IAE-001` | **`VERIFIED`** 2026-08-21 — Tier A/B clean at commit; Batch 2 Tier C review closed same day (0 findings against this capability's own code, 1 Medium disclosed-not-fixed cross-prompt-integration finding — see `docs/build-log/phase-09/IAE-336.md` §13). `docs/build-log/phase-09/IAE-336.md`. Last prompt of Batch 2 |
| `CG-S14-IAE-009` | 337 | Public API Platform | `IAE-007` (corrected by Batch 3's own Tier C review — needs `IAE-007`'s `INTHUB` permission-module seed, not `IAE-008`/Integration Hub, which this track never references) | **`VERIFIED`** 2026-08-21 — Tier A/B clean at commit; Batch 3 Tier C review closed same day (0 findings against this capability's own code beyond a shared route-test-coverage gap and a doc-only dependency correction — see `docs/build-log/phase-09/IAE-337.md` §13). `docs/build-log/phase-09/IAE-337.md` |
| `CG-S14-IAE-010` | 338 | Customer API | `IAE-009` | **`VERIFIED`** 2026-08-21 — Tier A/B clean at commit; Batch 3 Tier C review closed same day (1 High shared-primitive finding fixed — `app.rotate_api_key` double-rotation race — see `docs/build-log/phase-09/IAE-338.md` §13). `docs/build-log/phase-09/IAE-338.md` |
| `CG-S14-IAE-011` | 339 | Vendor API | `IAE-009` | **`VERIFIED`** 2026-08-21 — Tier A/B clean at commit; Batch 3 Tier C review closed same day (2 findings fixed — a High shared-primitive `app.rotate_api_key` double-rotation race, and a doc-only dependency-graph correction — see `docs/build-log/phase-09/IAE-339.md` §13). `docs/build-log/phase-09/IAE-339.md` |
| `CG-S14-IAE-012` | 340 | Webhook Management | `IAE-001` (corrected by Batch 3's own Tier C review — this capability references no `IAE-008`/Integration Hub artifact) | **`VERIFIED`** 2026-08-21 — Tier A/B clean at commit; Batch 3 Tier C review closed same day (6 findings against this capability, 4 fixed — both of the batch's own Critical findings, a High SSRF fix, and 1 Medium; 2 Low disclosed-not-fixed — see `docs/build-log/phase-09/IAE-340.md` §13). `docs/build-log/phase-09/IAE-340.md` |
| `CG-S14-IAE-013` | 341 | n8n Integration | `IAE-012` | **`VERIFIED`** 2026-08-21 — Tier A/B clean at commit; Batch 3 Tier C review closed same day (5 findings fixed, including a High connector-rotation-orphan fix — see `docs/build-log/phase-09/IAE-341.md` §13). `docs/build-log/phase-09/IAE-341.md`. Last prompt of Batch 3 |
| `CG-S14-IAE-014` | 342 | Email, WhatsApp and SMS Integrations | `IAE-008` | `BLOCKED` (Batch 4) |
| `CG-S14-IAE-015` | 343 | Maps, GPS and Telematics Integrations | `IAE-008` | `BLOCKED` (Batch 4) |
| `CG-S14-IAE-016` | 344 | Carrier, Port, Airport and Customs Integrations | `IAE-008` | `BLOCKED` (Batch 4) |
| `CG-S14-IAE-017` | 345 | Bank, Payment, eInvoice and Tax Integrations | `IAE-008` | `BLOCKED` (Batch 4) |
| `CG-S14-IAE-018` | 346 | External Accounting and HR Integrations | `IAE-008` | `BLOCKED` (Batch 4) |
| `CG-S14-IAE-019` | 347 | AI Governance Provider Boundary | `IAE-001` | `BLOCKED` (Batch 5) |
| `CG-S14-IAE-020` | 348 | AI-Assisted Quotation | `IAE-019` | `BLOCKED` (Batch 5) |
| `CG-S14-IAE-021` | 349 | OCR Document Processing | `IAE-019` | `BLOCKED` — **outside this checkpoint's authorization; requires fresh operator authorization for 349+ before release** |
| `CG-S14-IAE-022` | 350 | Predictive ETA | `IAE-019` | `BLOCKED` — outside authorization |
| `CG-S14-IAE-023` | 351 | Optimization Assistance | `IAE-019` | `BLOCKED` — outside authorization |
| `CG-S14-IAE-024` | 352 | Fraud/Risk Assistance | `IAE-019` | `BLOCKED` — outside authorization |
| `CG-S14-IAE-025` | 353 | Forecasting/Recommendation Assistance | `IAE-019` | `BLOCKED` — outside authorization |
| `CG-S14-IAE-026` | 354 | Enterprise IAM SSO/SAML/OAuth/SCIM | `IAE-001` | `BLOCKED` — outside authorization |
| `CG-S14-IAE-027` | 355 | Enterprise MFA and Session Controls | `IAE-026` | `BLOCKED` — outside authorization |
| `CG-S14-IAE-028` | 356 | IP Restriction and Network Access | `IAE-026` | `BLOCKED` — outside authorization |
| `CG-S14-IAE-029` | 357 | Advanced Audit and Impersonation | `IAE-026` | `BLOCKED` — outside authorization |
| `CG-S14-IAE-030` | 358 | Enterprise Monitoring and Observability | `IAE-001` | `BLOCKED` — outside authorization |
| `CG-S14-IAE-031` | 359 | Data Retention and Archival | `IAE-001` | `BLOCKED` — outside authorization |
| `CG-S14-IAE-032` | 360 | Dedicated Enterprise Deployment | `IAE-001` | `BLOCKED` — outside authorization |
| `CG-S14-IAE-033` | 361 | Multi-Region and Data Residency | `IAE-032` | `BLOCKED` — outside authorization |
| `CG-S14-IAE-034` | 362 | Scale-Up Architecture | `IAE-001` | `BLOCKED` — outside authorization |
| `CG-S14-IAE-035` | 363 | Disaster Recovery and Enterprise Support | `IAE-001` | `BLOCKED` — outside authorization |
| `CG-S14-IAE-036` | 364 | Intelligence/Enterprise Integrated Verification | all of `IAE-002..035` `VERIFIED` | `BLOCKED` — outside authorization, never batched |
| `CG-S14-IAE-037` | 365 | Intelligence/Enterprise Security and AI Hardening | `IAE-036` `VERIFIED` | `BLOCKED` — outside authorization, never batched |
| `CG-S14-IAE-038` | 366 | Intelligence/Enterprise Documentation and Handoff | `IAE-037` `VERIFIED` | `BLOCKED` — outside authorization, never batched |
| `CG-S14-IAE-039` | 367 | Intelligence/Enterprise Closure Verification | `IAE-038` `VERIFIED` | `BLOCKED` — outside authorization, never batched. Sole task authorized to set `PHASE_9_VERIFIED` |

Planned batch grouping for review cadence (`AGENTS.md` "Execution cadence", stated before any code is written, per §5): **Batch 1** `IAE-002..006` (Prompts 330-334); **Batch 2** `IAE-007..008` (335-336, 2 prompts); **Batch 3** `IAE-009..013` (337-341); **Batch 4** `IAE-014..018` (342-346); **Batch 5** `IAE-019..020` (347-348, 2 prompts). Groups 6-9 (`IAE-021..039`, Prompts 349-367) are recorded for WBS completeness only and are not scheduled by this checkpoint.

---

## 11. Evidence/log path

- This file: `docs/build-log/phase-09/00_EXECUTION_INDEX.md` — living index, appended with one `## N. Update — ...` section per completed batch, mirroring `docs/build-log/phase-07/00_EXECUTION_INDEX.md`/`phase-08/00_EXECUTION_INDEX.md`'s own convention.
- Per-capability build logs: `docs/build-log/phase-09/IAE-<NNN>.md` (one per Prompt 330-348 within this authorization, created at that prompt's own checkpoint — none exist yet).
- ADR: `docs/adr/ADR-0025-phase9-api-webhook-automation-and-ai-provider-boundary-foundation.md`.
- Evidence ledgers required by `329_*.md` §5 (scaffolded this checkpoint, populated by the capability prompts that generate real evidence):
  - **Reporting/dashboard accuracy** — populated by `IAE-002`/`003` onward; each report/dashboard's own db-test proving permission-aware, field-masked, tenant-scoped output against a known fixture is the evidence unit.
  - **Analytics workload isolation** — populated by `IAE-005` (333); the evidence unit is a query-budget/timeout/read-path test proving materialized-view refresh never blocks or starves live OLTP reads, per `RPD-014`.
  - **Automation governance** — populated by `IAE-007` (335); dry-run, versioning, and no-autonomous-critical-action evidence, per `AGENTS.md`'s own automation/AI governance rules.
  - **API/webhook compatibility** — populated by `IAE-009`/`012` (337/340); version/compatibility-plan evidence extending `PLT-129`'s own already-proven idempotency/signature/retry evidence shape.
  - **Integration idempotency** — populated by `IAE-014..018` (342-346); each adapter's own retry/DLQ/idempotency-key evidence, per `AGENTS.md` "Retriable mutations and deliveries require idempotency, bounded retries, observability, and dead-letter/recovery paths."
  - **AI human governance** — populated by `IAE-019`/`020` (347/348); the evidence unit is a db-test proving zero autonomous critical-decision path exists (no AI-originated customer-visible price commitment or ledger/legal-status post without an explicit human-approval step), per `RPD-021`.
  - **Enterprise IAM, monitoring, retention, deployment, DR, support controls** — scaffolded here, populated only once a future authorization releases Prompts 349-367.
  - **Rollback** — see §12.
- `docs/runtime/KNOWN_ISSUES.md`: two new entries registered this checkpoint — `ISS-2026-143` (documentation-only `IEP`/`IAE` naming disclosure) and `ISS-2026-144` (pre-existing Phase 6 `procurement-vendor-performance.sql` assertion failure, disclosed not fixed).

---

## 12. Rollback

All work this checkpoint is additive-only and reversible: two new files (`ADR-0025`, this execution index), one appended section in `docs/adr/README.md`, and appended (never rewritten in place) sections in `docs/runtime/KNOWN_ISSUES.md`/`TASK_LEDGER.md`/`CARGOGRID_BUILD_STATUS.md`/`HANDOFF.md`, plus one project-level permission-allowlist edit (`.claude/settings.json`, requested by the operator this session, unrelated to Phase 9 product scope). No migration, no application code, no existing file's prior content was altered. Rollback, if ever required, is `git revert` of this checkpoint's own commit(s) — no database state, no applied migration, and no other phase's evidence is touched. Last known good checkpoint before this one: `aa667caf10cb61c44937ede06fa7da95a1801bdd` (Phase 8 `PHASE_8_VERIFIED` closure merge).

---

## 13. Runtime state and resume

`PHASE_9_IN_PROGRESS` is set by this checkpoint. A future agent with no access to this conversation resumes by: (1) reading `docs/runtime/HANDOFF.md`'s most recent entry, (2) reading this file in full, (3) confirming `CG-S14-IAE-002` (Prompt 330) is still the first `READY` row in §10 (or reading whichever later row is `READY` if this file has since been updated), (4) reading `docs/adr/ADR-0025-*.md` before writing any Phase 9 schema/RPC touching API keys, webhooks, automation, integrations, or AI, since it fixes four repository-wide reuse boundaries every capability prompt from 330 onward must follow without re-deriving them, (5) confirming the operator's own authorized range before starting any prompt numbered 349 or higher — this checkpoint does not authorize that work.

---

## 14. First eligible prompt

**Batch 1 Tier C review — CLOSED 2026-08-21.** All five Batch 1 capabilities (`IAE-002` Reporting Engine, `IAE-003` Dashboard Builder, `IAE-004` Saved View and Configurable Report, `IAE-005` Analytics and Materialized Views, `IAE-006` Scheduled Reports) reached `COMPLETED` 2026-08-21, then underwent Batch 1's own mandatory Tier C review the same day: 4 parallel adversarial lenses (spec-compliance; security/RLS/tenant, live-tested; correctness/concurrency, live-tested; cross-prompt integration) found 12 distinct findings (1 Critical, 5 High, 5 Medium, 1 Low, after grouping/deduping the lenses' own 14 raw findings) plus 2 propagation-sweep-only findings; all fixed in one bounded fix migration, `supabase/migrations/20260802060000_harden_intelligence_batch1_tier_c_review_fixes.sql`. Full per-capability breakdown, live regression evidence, and the fix pass's own disclosed-not-fixed items are recorded in each capability's own build log §13 (`docs/build-log/phase-09/IAE-33{0..4}.md`). The fix pass's own automated agent was interrupted mid-task (an incomplete `REP:Export` cancel regression, two un-applied TypeScript-layer disclosures, and a missing true-concurrency regression test); all three gaps were independently identified, completed, and verified by the orchestrating session before this close — never accepted on the fix agent's own self-report, per `AGENTS.md`. Independently re-run and confirmed clean by the orchestrating session: a fresh disposable-database standalone pass of all 5 Batch 1 db-test files, the full cumulative `pnpm run db:test` (194 files, including the repository-wide `rbac-enforcement.sql` sweep), `pnpm run typecheck`, `pnpm run lint` (0 errors), `pnpm run test` (4919/4919 pass), `pnpm exec next build` (clean), and all six governance checks (`docs:check`, `security:check`, `data-classification:check`, `standards:check`, `threat-model:check`, `git:check-paths`). All five capabilities are now `VERIFIED` (§10).

**`CG-S14-IAE-007`** (Prompt 335, Automation Rule Engine, Batch 2) was the first eligible prompt, released by Batch 1's own `VERIFIED` status per `AGENTS.md`'s cross-batch rule; both it and `CG-S14-IAE-008` (Prompt 336, Integration Hub) reached `COMPLETED` 2026-08-21, closing out Batch 2.

**Batch 2 Tier C review — CLOSED 2026-08-21.** Both Batch 2 capabilities (`IAE-007` Automation Rule Engine, `IAE-008` Integration Hub) reached `COMPLETED` 2026-08-21, then underwent Batch 2's own mandatory Tier C review the same day: 4 parallel adversarial lenses (spec-compliance; security/RLS/tenant, live-tested; correctness/concurrency, live-tested; cross-prompt integration) found 8 distinct findings (2 Critical, 3 High, 1 Medium cross-layer, 1 Low, 1 Medium disclosed-not-fixed), all against `IAE-007`'s own code or the shared background-job job-type registry — `IAE-008` (Integration Hub) survived every live probe against its own code with zero findings, a direct payoff of proactively applying Batch 1's own hard-won lessons (C-05 folding, `customer_user`-layer RLS exclusion, live forged-session RLS testing) from its first draft. All 7 fixable findings fixed in one bounded fix migration, `supabase/migrations/20260803030000_harden_intelligence_batch2_tier_c_review_fixes.sql`; the one disclosed-not-fixed finding (IAE-008's migration ordering dependency on IAE-007 having no fail-fast guard) is a documented, accepted risk against a migration-skip scenario this repository's own real tooling cannot produce, not a live vulnerability in the actual, only-ever-used sequential apply order. Full per-capability breakdown and live regression evidence are recorded in each capability's own build log §13 (`docs/build-log/phase-09/IAE-33{5,6}.md`). Independently re-verified by the orchestrating session before this close — never accepted on the fix agent's own self-report, per `AGENTS.md`: a full line-by-line re-read of every changed file (the fix migration's own SQL for all 6 findings against `IAE-007`, both affected TS contracts, the new db-test regression blocks, the new concurrency helper script, the UI diff, and both build logs' own §13 claims); a fresh disposable-database standalone pass via `bash scripts/db-tests/run.sh` (201 files, `ALL PASSED`, including both `automation-rule-engine.sql`'s 7 new Tier C regression blocks — the genuine 3-process concurrency proof included — and `integration-hub.sql`'s own unaffected 9 assertion groups); `pnpm run typecheck` (0 errors); `pnpm run lint` (0 errors, pre-existing warnings only); `pnpm run test` (4969/4969 pass); `pnpm exec next build` (clean); and all six governance checks (`docs:check`, `security:check`, `data-classification:check`, `standards:check`, `threat-model:check`, `git:check-paths`). Both capabilities are now `VERIFIED` (§10).

Only after this close does `CG-S14-IAE-009` (Prompt 337, Public API Platform, Batch 3) become eligible, per `AGENTS.md`'s cross-batch rule.

**`CG-S14-IAE-009`** (Prompt 337, Public API Platform, Batch 3) was the first eligible prompt, released by Batch 2's own `VERIFIED` status; it reached `COMPLETED` 2026-08-21 (Tier A/B clean; one real, self-caught `rbac-enforcement.sql` actor-identity finding fixed before commit — see `docs/build-log/phase-09/IAE-337.md` §7).

**`CG-S14-IAE-010`** (Prompt 338, Customer API, Batch 3) reached `COMPLETED` 2026-08-21 (Tier A/B clean; one real, self-caught `SECURITY DEFINER` gap fixed before commit — widening `app.revoke_api_key`/`app.rotate_api_key`'s grant to `authenticated` alone was not sufficient, since `CREATE OR REPLACE FUNCTION` does not inherit the prior definition's security mode, and both functions had been `SECURITY INVOKER`; caught live via a forged-authenticated-session db-test, not reasoned about in the abstract — see `docs/build-log/phase-09/IAE-338.md` §7).

**`CG-S14-IAE-011`** (Prompt 339, Vendor API, Batch 3) reached `COMPLETED` 2026-08-21. Live-confirmed by direct repository research before any code was written: unlike IAE-010's customer key, NO vendor `auth.users` identity exists anywhere in this repository — vendor intake is genuinely anonymous/token-based, and every existing RFQ/capacity/assignment RPC is staff-captured "on behalf of" the vendor by disclosed design. IAE-011 therefore built a DATA-scope vendor key (`vendor_master_record_id`, staff-issued only, no vendor self-service) rather than an actor-identity key, plus three new vendor-scope-authorized RPCs writing into the SAME canonical tables the staff-only functions already use. Three real, self-caught issues fixed before commit (see `docs/build-log/phase-09/IAE-339.md` §7): (1) `CREATE OR REPLACE FUNCTION` cannot append a new OUT column to an existing `RETURNS TABLE(...)` function — live-verified with a throwaway test before touching the real migration, fixed via explicit `DROP FUNCTION`/`CREATE FUNCTION` with grants re-issued; (2) an ambiguous `tenant_id` column reference inside `create_vendor_api_key` (its own `RETURNS TABLE` clause shadows the table column) — every other `RETURNS TABLE` function in the migration was then audited for the same class of bug; (3) a nonexistent `app.rfqs.title` column referenced instead of the real `rfq_number`.

**`CG-S14-IAE-012`** (Prompt 340, Webhook Management, Batch 3) reached `COMPLETED` 2026-08-21 — the real outbound delivery worker `PLT-129` explicitly disclosed as not-yet-built, built on `app.jobs`'s own existing `webhook_retry` job type per `ADR-0025` Part B, including the first outbound HTTP client anywhere in this repository (`lib/webhooks/process-webhook-delivery-job.server.ts`, proven against a real local HTTP server, never merely mocked). One real, self-caught CROSS-FILE regression fixed before commit, caught only by the full `bash scripts/db-tests/run.sh` run (never visible from a standalone run of this checkpoint's own file): giving `webhook_retry` a real producer for the first time broke `scripts/db-tests/background-job.sql`'s own pre-existing `claim_next_job` test, which had implicitly assumed exclusive control over that job type's queue state — an assumption only ever true because nothing had ever enqueued a real `webhook_retry` job before this checkpoint. Root-caused by tracing the failing row's actor id/idempotency-key convention back to `scripts/db-tests/api-key-webhook.sql`'s own fixture (an earlier-running file that calls `app.queue_webhook_delivery` for unrelated tests and now leaves a real job behind); fixed by draining leftover jobs at the start of the affected assertion block, the same remedy this checkpoint's own new db-test file already needed for an identical class of interference between its own assertion blocks (see `docs/build-log/phase-09/IAE-340.md` §7). `CG-S14-IAE-013` (Prompt 341, n8n Integration) is now the next dependency-clean prompt within Batch 3 — the final prompt before Batch 3's own Tier C review.

**`CG-S14-IAE-013`** (Prompt 341, n8n Integration, Batch 3) reached `COMPLETED` 2026-08-21 — a deliberately thin governance/labeling layer, consistent with `RPD-012`'s own framing of n8n as "not the primary engine — optional external trigger/consumer only" and the prompt's own "no tenant-specific backend code is generated for n8n" business rule: n8n calls the SAME `/api/v1` surface and receives events through the SAME webhook mechanism (IAE-009/IAE-012) as any other consumer. This checkpoint adds only a curated, Supreme-controlled safe-action allowlist (`app.n8n_action_allowlist`, seeded `OPS:View`/`PRC:View`/`TKT:View`/`TKT:Create`/`INTHUB:View` — deliberately excluding every Approve/Delete/Override/financial scope) and a named connector governance record (`app.n8n_connectors`) that composes (never forks) `app.create_api_key`/`app.revoke_api_key`, dual-gating every requested scope against BOTH the allowlist AND the creating actor's own current RBAC. One ambiguous-column-reference risk (the same class live-caught in IAE-011's `create_vendor_api_key`) was caught PROACTIVELY this time — fixed before the migration was ever applied to a scratch database, not live. One self-caught test-authoring bug fixed before commit: the "allowlisted but not held" probe scope was drafted as a scope that turned out to be not-allowlisted-at-all, producing the wrong exception; corrected to a genuinely allowlisted-but-not-held scope (see `docs/build-log/phase-09/IAE-341.md` §7). The full `bash scripts/db-tests/run.sh` suite was re-run and confirmed `ALL PASSED` with no cross-file regression, per the mandatory full-suite check established by IAE-012's own cross-file regression lesson.

**Batch 3 (Prompts 337-341) is now fully `COMPLETED`.** All five capabilities (`IAE-009` Public API Platform, `IAE-010` Customer API, `IAE-011` Vendor API, `IAE-012` Webhook Management, `IAE-013` n8n Integration) have reached `COMPLETED` status with Tier A/B self-review clean and individually gate-verified. Per `AGENTS.md`'s cross-batch rule (`CON-015`), Batch 3's own mandatory Tier C review — 4 parallel adversarial lenses (spec-compliance; security/RLS/tenant, live-tested; correctness/concurrency, live-tested; cross-prompt integration), any resulting fix pass, and an independent full gate re-run by the orchestrating session — must close, bringing all five capabilities to `VERIFIED`, before `CG-S14-IAE-014` (Prompt 342, Email/WhatsApp/SMS Integrations, Batch 4) becomes eligible.

**Batch 3 Tier C review — CLOSED 2026-08-21.** All five Batch 3 capabilities reached `COMPLETED` 2026-08-21, then underwent Batch 3's own mandatory Tier C review the same day: 4 parallel adversarial lenses (spec-compliance; security/RLS/tenant, live-tested; correctness/concurrency, live-tested; cross-prompt integration) found 17 distinct findings (2 Critical, 4 High, 6 Medium, 5 Low) — the largest concentration against `IAE-012` (Webhook Management, the first outbound HTTP client and first real `app.jobs`-backed delivery worker in the repository) and `IAE-013` (n8n Integration), plus one shared-primitive finding (`app.rotate_api_key`) affecting every capability that rotates a plain `app.api_keys` row, and one shared-UI finding (`page.tsx`) affecting all five. 12 of the 17 findings were fixed in one bounded fix migration, `supabase/migrations/20260804060000_harden_intelligence_batch3_tier_c_review_fixes.sql`, plus a new TypeScript SSRF guard (`lib/webhooks/ssrf-guard.server.ts`) and targeted UI/doc fixes; 5 findings were disclosed, not fixed (judged out of this bounded pass's own scope — see each capability's own build log §13 for the individual rationale). Full per-capability breakdown and live regression evidence are recorded in each capability's own build log §13 (`docs/build-log/phase-09/IAE-33{7,8,9}.md`, `IAE-34{0,1}.md`). Fixed (12), in order of severity:
- **2 Critical** (`IAE-012`): `app.replay_webhook_delivery` permanently broke any delivery it replayed (reset the append-only `attempts` counter, colliding with `app.webhook_delivery_attempts`' own unique constraint on the very next real attempt — 100% reproducible, no concurrency required) and had no row lock (two concurrent replays of the same `dead_letter` delivery both succeeded, double-enqueuing a job) — both live-proven against a real scratch database (including two genuinely concurrent `psql` processes for the second) and both fixed.
- **3 High** (shared `app.rotate_api_key`, `IAE-012` SSRF, `IAE-013` connector rotation): a concurrent/retried rotation of the same active key minted two independent live successor keys (live-proven under real concurrency, fixed via a new `superseded_by_key_id` guard column); the real webhook delivery worker had no runtime protection against a hostname resolving to a private/loopback/cloud-metadata address only at dispatch time (DNS rebinding — `app.validate_webhook_url`'s own migration header had explicitly disclosed this as a gap for the not-yet-built delivery worker to close; fixed in TypeScript with a new re-resolving SSRF guard plus disabling auto-redirect-following); rotating an n8n connector's key via the reused generic rotate form silently orphaned `app.n8n_connectors.api_key_id` (fixed via a new composing `app.rotate_n8n_connector`).
- **5 Medium**: `app.register_n8n_allowlisted_action` and `app.queue_webhook_delivery` (`IAE-013`/`IAE-012`) both had an unlocked check-then-insert idempotency gap, live-proven to surface a raw constraint violation to a losing concurrent caller instead of the documented idempotent no-op — both fixed via atomic `INSERT ... ON CONFLICT` upserts; `app/(tenant)/[tenantSlug]/admin/api-keys/page.tsx`'s single `Promise.all` (shared UI) blanked all nine sections across all five capabilities on any one query's failure — fixed via per-section error isolation; the dependency graph (§5, §9, doc-only) misattributed the API/Webhook Ecosystem track's cross-batch dependency to `IAE-008`/Integration Hub — the real dependency is `IAE-007`'s own `INTHUB` permission-module seed, corrected here and in `IAE-339.md`'s own §12; `IAE-013`'s console pointed a tenant admin at a non-existent internal "sample workflows" doc reference — fixed with accurate, actionable copy.
- **2 Low** (`IAE-013`): `app.create_n8n_connector` allowed linking a disabled webhook endpoint with no warning (fixed, now requires `status='active'`); `app.n8n_connectors`/`app.n8n_action_allowlist` shipped without RLS enabled (fixed as cheap defense-in-depth, zero policies needed — both were already non-exploitable, RPC-only reads).

Disclosed, not fixed (5, all judged out of this bounded pass's own scope, not live defects):
- **1 High**: zero automated test coverage for the 9 new `/api/v1` REST route handlers across `IAE-009`/`010`/`011` (`package.json`'s own `test` script glob excludes `app/**`) — the underlying RPCs are fully covered by their own db-test files; only the HTTP-layer glue is unverified. Recorded as an accepted gap for a future dedicated checkpoint.
- **1 Medium** (`IAE-013`): design decision 6's claim of per-connector execution-log filtering does not match the shipped console (neither `list_api_logs_for_tenant` nor `list_webhook_deliveries_for_tenant` accepts such a filter) — disclosed as the accurate current state; implementing the filter would need two more RPC extensions plus their own UI, deferred to a future checkpoint.
- **1 Low** (`IAE-012`): "endpoint verification" (Prompt 340 §15) was narrowed to "test send" without a distinct ownership-challenge flow — a reasonable, deliberate narrowing.
- **1 Low** (`IAE-012`): no per-event-type payload field-allowlist enforcement (Prompt 340 §24) — currently moot since no domain mutation is wired to call `queue_webhook_delivery` yet; deferred to that same future wiring task.
- **1 Low** (`IAE-009`): the documented `actor_label = 'api_key:' || key_prefix` convention was never implemented (cosmetic — the real actor UUID is still used); disclosed rather than fixed since it touches the shared gateway helper across three route-owning capabilities.

Independently re-verified by the orchestrating session before this close — never accepted on any fix's own self-report, per `AGENTS.md`: every SQL fix in the migration was live-probed against a fresh disposable database using the SAME reproduction each finding was originally caught with (including two genuinely concurrent `psql` processes for both the replay-delivery double-enqueue race and the rotate-key double-rotation race), each confirmed to now behave correctly; a fresh disposable-database standalone pass via `bash scripts/db-tests/run.sh` (`ALL PASSED`, including 4 new/modified permanent regression blocks across `webhook-management.sql`, `n8n-integration.sql`, and `api-key-webhook.sql`); `pnpm run typecheck` (0 errors); `pnpm run lint` (0 errors, pre-existing warnings only); `pnpm run test` (5034/5034 pass, including the new 22-test `ssrf-guard.server.test.ts`/`process-webhook-delivery-job.server.test.ts` coverage); `pnpm exec next build` (clean); and all six governance checks (`docs:check`, `security:check`, `data-classification:check`, `standards:check`, `threat-model:check`, `git:check-paths`). All five capabilities are now `VERIFIED` (§10).

Only after this close does `CG-S14-IAE-014` (Prompt 342, Email/WhatsApp/SMS Integrations, Batch 4) become eligible, per `AGENTS.md`'s cross-batch rule.
