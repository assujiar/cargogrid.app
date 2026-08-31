# CargoGrid Architecture Decision Records (ADR)

**Owner:** Architecture Governance workstream
**Established by:** `CG-S5-PH0-005` (Prompt 84 — ADR Baseline and Decision Governance)
**Status:** Active framework

This directory is the repository-native mechanism for recording bounded **technical** architecture decisions so they stay explainable, reviewable, and reversible. It does **not** govern product policy: the ratified `CPD-001..023` and `RPD-001..040` decisions live in `docs/ai-agent-build-prompt-package/00-control/02_CONFIRMED_DECISION_REGISTER.md` and may only change via that register's formal product-change-control protocol. An ADR may never weaken, reinterpret, or silently supersede a CPD/RPD.

## 1. What an ADR is (and is not)

- **Is:** a record of one bounded technical choice (a tool, a numeric threshold, a folder convention, a schema-shape decision) that has more than one viable option and needs a durable, cited rationale.
- **Is not:** a product decision (→ CPD/RPD change control), a re-derivation of already-`VERIFIED` architecture (→ `docs/architecture/`), or permission to write feature code (that is gated by the phase capability prompts, not by an ADR).

**Business rule (Prompt 84 §24):** *recommendation is not approval.* An architecture document may recommend an option; it becomes binding only when an ADR here reaches status `ACCEPTED` with a named approver.

## 2. Status vocabulary

| Status | Meaning |
|---|---|
| `PROPOSED` | Question and options recorded; decision not yet made (evidence or approver still pending). |
| `ACCEPTED` | Decision made, approved by an authorized approver, and propagated to dependent records. Binding. |
| `BLOCKED` | Cannot be decided yet — a specific upstream evidence artifact or capability output does not exist. Names the exact unblocking task. |
| `SUPERSEDED` | Replaced by a later ADR. The old record is retained; its header links forward. Never deleted. |
| `REJECTED` | Considered and declined, with rationale. Retained. |

Lifecycle is **append-only** (Prompt 84 §18): supersession preserves history; no silent edit of an `ACCEPTED`/`REJECTED` record.

## 3. Authority boundaries

| Decision class | Authorized approver | Mechanism |
|---|---|---|
| Bounded Phase 0 technical decision with verified runtime evidence | Runtime build agent (this process), recorded here | ADR reaches `ACCEPTED` in the same checkpoint |
| Implementation-level decision (schema shape, numeric limits, tool product) | The owning phase's capability prompt, when its evidence exists | ADR stays `PROPOSED`/`BLOCKED` until that prompt runs |
| External/SME-gated decision (tax, payroll, pen-test, DR cadence) | Named external approver (Finance/HR/Security SME) | ADR stays `BLOCKED` until sign-off |
| CPD/RPD (product policy) | **Not an ADR** — Steering Committee via `02_CONFIRMED_DECISION_REGISTER.md` §5 | Out of scope here |

**Validation rule (Prompt 84 §25):** no dependent task may be marked `READY` on the basis of an ADR that is not yet `ACCEPTED`.

## 4. ADR file template

Each ADR is `docs/adr/ADR-NNNN-<slug>.md` with:

```
# ADR-NNNN — <title>
Status: <PROPOSED|ACCEPTED|BLOCKED|SUPERSEDED|REJECTED>
Date: <YYYY-MM-DD>   Approver: <role>   Supersedes/Superseded-by: <ADR id or —>
Source candidate: <ADR-CAND-ARCH-0NN>   Owning phase/task: <id>

## Question
## Options (with trade-offs)
## Decision
## Evidence (cited runtime/architecture sources)
## Consequences (DB/API/UI/security/performance/migration/rollback + downstream impact)
## Propagation (which WBS/traceability/context records now reference this)
```

## 5. Register of architecture ADR candidates (all 27)

Reconciled from `docs/architecture/01_*.md`–`13_*.md` and `HANDOFF.md` §7. **11 resolved** in Step 3 (already decided inside an architecture workstream document and carried as `ACCEPTED`-equivalent), **16 open** (each scoped to a specific later task — none is blocking, per `13_*.md` §11). This Phase 0 baseline approves only the one open candidate that has verified evidence now (`ADR-CAND-ARCH-011` → `ADR-0001`); the rest keep their scoped status.

### 5.1 Resolved in Step 3 (11)

| Candidate | Topic | Resolved in |
|---|---|---|
| `ADR-CAND-ARCH-001` | Single `app` schema ownership | `05_DATABASE_SCHEMA_WORKSTREAM.md` |
| `ADR-CAND-ARCH-002` | RLS policy family model | `06_RLS_RBAC_WORKSTREAM.md` (its employee-vs-user identity sub-question promoted to a ratified record at `ADR-0023` Part B, Phase 7 kickoff, mirroring `ADR-0015`'s identical promotion of `ADR-CAND-ARCH-030`) |
| `ADR-CAND-ARCH-003` | Domain namespace/boundary model | `03_*.md` → `05_*.md` |
| `ADR-CAND-ARCH-004` | Live-OLTP → replica/warehouse threshold | `11_DEVOPS_WORKSTREAM.md` §9.1 |
| `ADR-CAND-ARCH-005` | Constraint/relationship plan | `05_*.md` |
| `ADR-CAND-ARCH-006` | Permission-catalogue action model | `06_*.md` |
| `ADR-CAND-ARCH-007` | Finance posting-integrity controls | `05_*.md` |
| `ADR-CAND-ARCH-008` | Migration-wave policy | `05_*.md` |
| `ADR-CAND-ARCH-009` | Audit schema approach | `05_*.md`/`06_*.md` |
| `ADR-CAND-ARCH-010` | Configuration-engine sub-engine decomposition | `07_CONFIGURATION_ENGINE_WORKSTREAM.md` |
| `ADR-CAND-ARCH-016` | REST/GraphQL shared evaluation flow | `08_API_INTEGRATION_WORKSTREAM.md` |

### 5.2 Open, scoped to a later task (16)

| Candidate | Topic | Owning task | Status here |
|---|---|---|---|
| `ADR-CAND-ARCH-011` | Empty domain-folder stubs — create eagerly or per-phase | Phase 0 (`PH0-083`/`087`) | **ACCEPTED → `ADR-0001`** (this checkpoint) |
| `ADR-CAND-ARCH-012` | `customers` extension-table vs. flat-column strategy | Phase 2 Commercial schema | **ACCEPTED → `ADR-0018`** (`CG-S7-COM-014`, Prompt 155, Customer and Account Conversion) — flat-column `app.accounts` selected, not Master Data Engine-based; resolves the account/customer distinction as one table with a `customer_status` column, not two tables |
| `ADR-CAND-ARCH-013` | `shipments` wide-table vs. linked-table split | Phase 3 schema (Prompt 168+) | `BLOCKED` — needs Phase 3 schema slice |
| `ADR-CAND-ARCH-014` | Rule-evaluation timeout (≈500ms) | Phase 2+ (bounded rule-expression evaluator, deliberately not built in Platform Core) | `PROPOSED` — value signalled, ratify at build. *Correction (`PLT-139`): previously read "Config engine (Phase 1 `07_*.md`)" — `PLT-121` (Configuration Engine, `docs/build-log/phase-01/PLT-121.md` §25) explicitly deferred the bounded rule-expression evaluator itself to "whichever Phase 2+ capability first needs to evaluate a real rule," since no business rule with real runtime semantics exists anywhere in Platform Core; this timeout question is scoped to that same not-yet-built evaluator.* |
| `ADR-CAND-ARCH-015` | Config-engine bounded-evaluator sandbox | Phase 2+ (bounded rule-expression evaluator, deliberately not built in Platform Core) | `PROPOSED` — same correction and citation as `ADR-CAND-ARCH-014` above (`PLT-121`, `docs/build-log/phase-01/PLT-121.md` §25) |
| `ADR-CAND-ARCH-017` | GraphQL depth/complexity limits + persisted-op registry | API workstream (Phase 1+) | **Partially `ACCEPTED` → `ADR-0012`** (depth/complexity numeric limits only, `CG-S6-PLT-027`/Prompt 130) — persisted-operation registration mechanism remains open, due at the future live GraphQL-server capability |
| `ADR-CAND-ARCH-018` | Webhook retry/backoff/DLQ numeric values | API workstream | **Partially `ACCEPTED` → `ADR-0011`** (signature/timestamp/auto-disable sub-questions only, `CG-S6-PLT-026`/Prompt 129) — rate-limit numeric thresholds remain `PROPOSED`, non-blocking, due at the future live API-gateway/rate-enforcement capability |
| `ADR-CAND-ARCH-019` | Deployment ordering / API-consumer compatibility | DevOps (Phase 0 CI + release) | `PROPOSED` |
| `ADR-CAND-ARCH-020` | Component-library foundation | Phase 0 `PH0-090` (Design System) | **ACCEPTED → `ADR-0005`** (Radix UI primitives, copy-in pattern) |
| `ADR-CAND-ARCH-021` | Design-token mechanism + token file location | Phase 0 `PH0-090` | **ACCEPTED → `ADR-0006`** (CSS custom properties + Tailwind v4 `@theme`) |
| `ADR-CAND-ARCH-022` | Test-tooling/coverage-gate specifics | Phase 0 `PH0-091` (Testing) | **ACCEPTED → `ADR-0007`** (`node:test` unit/integration/component, Playwright E2E/visual-regression, `tests/factories/<domain>.ts`) |
| `ADR-CAND-ARCH-023` | DR-rehearsal cadence + automated-accessibility-checker tool | Phase 0 `PH0-091` (Testing) | **ACCEPTED → `ADR-0008`** (quarterly cadence, `@axe-core/playwright`). *Correction (`PH0-91`, `ADR-0008` "Scope discrepancy" section): this row previously read "DR-rehearsal cadence" only, reassigned to "Phase 15 (`HDN-384`)," dropping the accessibility-checker half — an unintended narrowing during this register's transcription from `docs/architecture/10_TESTING_WORKSTREAM.md` §11, not a deliberate re-scoping recorded anywhere. Both halves are resolved here, at the phase/task `10_*.md` §11 and the current `HANDOFF.md`/`TASK_LEDGER.md` always specified.* |
| `ADR-CAND-ARCH-024` | CI/CD platform + package manager | Phase 0 `PH0-085..088` | **Fully `ACCEPTED`** — package-manager component → `ADR-0002` (`PH0-085`); CI/CD-platform-product component → `ADR-0004` (`PH0-088`, GitHub Actions) |
| `ADR-CAND-ARCH-025` | Secret-manager product | Phase 0 `PH0-085..088`/`094` | **ACCEPTED → `ADR-0010`** (Vercel Environment Variables + Supabase project secrets — native platform mechanism, no dedicated secret-manager service at MVP) |
| `ADR-CAND-ARCH-026` | Observability/APM tool | Phase 0 `PH0-093` | **ACCEPTED → `ADR-0009`** (Better Stack — logs/metrics/traces/alerting/incident-management in one product, OpenTelemetry-native) |
| `ADR-CAND-ARCH-027` | Hosting/CDN platform | Phase 0 `PH0-085..088` | `BLOCKED` — due at environment |
| `ADR-CAND-ARCH-028` | Job queue backoff formula, worker lease duration, DLQ numeric defaults | API and Jobs (Phase 1, `CG-S6-PLT-029`/Prompt 132) | **ACCEPTED → `ADR-0013`** (this checkpoint) — newly minted, not part of the original 27; this checkpoint's own research confirmed no prior candidate covered this dimension (`08_API_INTEGRATION_WORKSTREAM.md`/`04_REPOSITORY_TARGET_STRUCTURE.md` name the adjacent "worker separation" threshold as `ADR_REQUIRED` with no number either, deliberately left open — see `ADR-0013`'s own Consequences) |
| `ADR-CAND-ARCH-029` | PostGIS extension version, spatial column type (`geography` vs. `geometry`)/SRID, bounded-radius query cap | Progressive Delivery and Spatial (Phase 1, `CG-S6-PLT-031`/Prompt 134) | **ACCEPTED → `ADR-0014`** (this checkpoint) — newly minted, not part of the original 27 or `ADR-CAND-ARCH-028`; this checkpoint's own research confirmed no prior candidate covered PostGIS version/SRID/query-radius numeric thresholds (`05_DATABASE_SCHEMA_WORKSTREAM.md` line 108 already resolved the `geography`-vs-`geometry` type choice qualitatively — this ADR restates it as the SRID number that choice structurally implies, proven by direct testing, and resolves the two genuinely open numeric questions: version pin and bounded-radius cap) |
| `ADR-CAND-ARCH-030` | Canonical vendor/service/rate lookup ownership across Commercial's Phase-2 interim lookup and Procurement's Phase-6 full lifecycle; interim write authority before Procurement ships | Commercial (Phase 2, `CG-S7-COM-001`/Prompt 142 kickoff, resolved ahead of `CG-S7-COM-008`/Prompt 149) | **ACCEPTED → `ADR-0015`** (Phase 2 kickoff checkpoint) — formalizes a decision `05_DATABASE_SCHEMA_WORKSTREAM.md` line 93 already reached qualitatively ("Option (a)": Procurement-owned from Phase 1's master-data foundation, Commercial reads via a view) but never before promoted to a binding `docs/adr/ADR-NNNN` record; resolves the one genuinely open sub-question (interim write authority before Phase 6) by confirming the existing tenant-admin/support-grant chain (`app.is_support_grant_authority`, `PLT-115`) already covers it, no new authority model needed. **Numbering note:** this candidate is a *distinct* question from the "`ADR-CAND-ARCH-001`" both `01_MODULE_DEPENDENCY_MAP.md` §9 and `05_DATABASE_SCHEMA_WORKSTREAM.md` §11 use as their own **local** citation for this exact vendor-rate topic — a pre-existing local/master numbering divergence (the master register's own `ADR-CAND-ARCH-001`, §5.1 above, is "Single `app` schema ownership," unrelated), the same class of divergence already disclosed once before for `ADR-CAND-ARCH-010` (`server/contracts/` folder-timing vs. config-engine sub-engine decomposition, `00_PLATFORM_CORE_WBS.md` §3). Neither architecture document is edited to renumber its own internal citation (both are closed, `VERIFIED` Step 3 artifacts) — this row is the real master-register entry, numbered fresh rather than silently overloading `001` a third time. |
| `ADR-CAND-ARCH-031` | Canonical item/SKU and UOM master identity shape and ownership — `app.master_records` extension vs. flat-column strategy, structurally identical question to `ADR-CAND-ARCH-012` for a new entity | Phase 5 (`CG-S10-ATW-011A`, inserted between the `VERIFIED` Prompt 230 and Prompt 231 by explicit operator authorization following a comprehensive gap audit) | **ACCEPTED → `ADR-0019`** (this checkpoint) — newly minted; no prior candidate in this register covers item/SKU or UOM identity. Resolves a package-level gap: no prompt in `docs/ai-agent-build-prompt-package/` (79-430) ever creates an item/SKU/product master or a UOM master, yet Prompt 231 §9 and Prompt 234 §9 both require one already `VERIFIED` |

| `ADR-CAND-ARCH-032` | Phase 6 canonical vendor identity reconciliation between the pre-existing `master_type_code='vendor_rate'` (Phase 2 rate lookup) and `master_type_code='vendor'` (Phase 3/4 identity/AP) master types, plus interim `PRC`-specific write authority | Phase 6 (`CG-S11-PRC-001`, Prompt 250, Procurement/Vendor WBS and Runtime Kickoff) | **ACCEPTED → `ADR-0020`** (this checkpoint) — newly minted; resolves a gap `ADR-0015` explicitly deferred to Phase 6's own kickoff, sharpened by this checkpoint's own direct-inspection finding that a second, independent, already-`VERIFIED`-Phase-3 master type (`vendor`) already exists and is already the live FK target for Finance's entire AP/vendor-bill/settlement chain — the two master types were never cross-referenced against each other before this checkpoint |

| `ADR-CAND-ARCH-033` | Build-process execution cadence — how often the adversarial review-and-fix round runs relative to capability prompts, and what compensating controls make any deferral safe | Phase 6 (out-of-band process change, 2026-08-07, on explicit operator instruction; applies from Prompt 257 onward) | **ACCEPTED → `ADR-0021`** (this checkpoint) — newly minted; no prior candidate in this register covers build cadence or review scheduling. The per-prompt review convention used for Prompts 220–256 was never itself an ADR — it existed only as practice recorded retrospectively in build logs, which is precisely why changing it needed a real decision record rather than a silent practice change |

| `ADR-CAND-ARCH-034` | `app.org_units.unit_type` has no `team` value while Phase 7's own Organization and Position Linkage capability (Prompt 275) names company/branch/department/team as the four canonical Platform org node types position/grade must reference, at binding-rule level, in two of its own sections | Phase 7 (`CG-S12-HRT-001`, Prompt 273, HRIS/Ticketing WBS Runtime Kickoff) | **ACCEPTED → `ADR-0023`** Part A (this checkpoint) — newly minted; no prior candidate in this register covers the org_units type set. Resolves a genuine, load-bearing gap between the live schema (four values only) and a downstream capability prompt's binding text, the same class of decision `ADR-0015`/`ADR-0020` required a ratified ADR for at their own respective kickoffs |

| `ADR-CAND-ARCH-035` | Repository-wide customer-facing (Layer 4) read access shape, customer write access shape, REST/GraphQL transport scope for Phase 8, and loyalty ledger/Finance-liability-handoff shape — four questions common to nearly all 24 Phase 8 capability prompts, none previously answered by a ratified decision | Phase 8 (`CG-S13-CPL-001`, Prompt 299, Customer Portal and Loyalty WBS Runtime Kickoff) | **ACCEPTED → `ADR-0024`** (this checkpoint) — newly minted; no prior candidate in this register covers a repository-wide customer-facing access pattern. Ratifies and generalizes the already-shipped, already-adversarially-reviewed `ATW-023`/`ATW-032` pattern (Part A/B) so no capability prompt from 300 onward re-derives it independently; narrows `ADR-CAND-ARCH-017`'s open live-GraphQL-server question for Phase 8's own scope only, without resolving that candidate itself (Part C); fixes the loyalty ledger/handoff shape against the two closest proven precedents in the repository, the inventory ledger and the HRT-282 Finance-payroll-handoff pattern (Part D) |

| `ADR-CAND-ARCH-036` | Phase 9 Public/Customer/Vendor API and Webhook Management reuse boundary against the already-shipped `PLT-129` API-key/webhook primitives, Integration Hub vs. `RPD-038`'s no-generic-provider-abstraction rule, and Automation Rule Engine execution mechanism against the existing `app.jobs` durable queue — four questions common to the first 19 Phase 9 capability prompts (330-348), none previously answered by a ratified Phase 9-scoped decision | Phase 9 (`CG-S14-IAE-001`, Prompt 329, Intelligence, Automation and Enterprise WBS Runtime Kickoff) | **ACCEPTED → `ADR-0025`** (this checkpoint) — newly minted; no prior candidate in this register covers Phase 9's own API/webhook/automation/AI foundation. Ratifies extension of `PLT-129`'s already-shipped API-key/webhook primitives (Part A/B) rather than a parallel table; ratifies Prompt 336's own already-stated governance-layer framing against `RPD-038` (Part C); ratifies extension of the existing `app.jobs`/job-type registry (Part D) per `RPD-012` |

*(Count reconciliation: `HANDOFF.md` §7's "10 resolved / 17 open" split is corrected here to **11 resolved / 16 open** — 001–010 + 016 = 11; 011–015 + 017–027 = 16; union = 27. The discrepancy was a one-item miscount, not a missing candidate; every one of the 27 is accounted for above. `ADR-CAND-ARCH-028`, `ADR-CAND-ARCH-029`, and `ADR-CAND-ARCH-030` are a 28th, 29th, and 30th candidate, each minted and resolved in its own checkpoint (`CG-S6-PLT-029`/Prompt 132, `CG-S6-PLT-031`/Prompt 134, and `CG-S7-COM-001`/Prompt 142 respectively) — none part of that original 27-item reconciliation. Updated at `CG-S7-COM-014` (Prompt 155): `ADR-CAND-ARCH-012` (one of the original 27, previously counted in the 16 open) resolved `ACCEPTED → ADR-0018` — the original-27 split is now **12 resolved / 15 open**; total resolved across all 30 candidates is 15. Updated at `CG-S10-ATW-011A` (Phase 5, inserted between Prompt 230 and Prompt 231): `ADR-CAND-ARCH-031` is a 31st candidate, newly minted and resolved in the same checkpoint (`ACCEPTED → ADR-0019`) — not part of the original 27; total resolved across all 31 candidates is 16. Updated at `CG-S11-PRC-001` (Phase 6 kickoff, Prompt 250): `ADR-CAND-ARCH-032` is a 32nd candidate, newly minted and resolved in the same checkpoint (`ACCEPTED → ADR-0020`) — not part of the original 27; total resolved across all 32 candidates is 17. Updated 2026-08-07 (out-of-band process change, post-Prompt-256): `ADR-CAND-ARCH-033` is a 33rd candidate, newly minted and resolved in the same checkpoint (`ACCEPTED → ADR-0021`) — not part of the original 27, and the first candidate in this register about the build *process* rather than the product's architecture; total resolved across all 33 candidates is 18. Updated 2026-08-09 (Phase 7 kickoff, `CG-S12-HRT-001`/Prompt 273): `ADR-CAND-ARCH-034` is a 34th candidate, newly minted and resolved in the same checkpoint (`ACCEPTED → ADR-0023` Part A) — not part of the original 27; total resolved across all 34 candidates is 19. The same checkpoint also promoted the already-Step-3-resolved `ADR-CAND-ARCH-002` (§5.1) to a ratified record for the first time (`ADR-0023` Part B, mirroring `ADR-0015`'s identical promotion of `ADR-CAND-ARCH-030`) — `ADR-CAND-ARCH-002` was already counted among the 11 resolved-in-Step-3 candidates and is not double-counted here. Updated 2026-08-16 (Phase 8 kickoff, `CG-S13-CPL-001`/Prompt 299): `ADR-CAND-ARCH-035` is a 35th candidate, newly minted and resolved in the same checkpoint (`ACCEPTED → ADR-0024`) — not part of the original 27; total resolved across all 35 candidates is 20. Updated 2026-08-21 (Phase 9 kickoff, `CG-S14-IAE-001`/Prompt 329): `ADR-CAND-ARCH-036` is a 36th candidate, newly minted and resolved in the same checkpoint (`ACCEPTED → ADR-0025`) — not part of the original 27; total resolved across all 36 candidates is 21.)*

## 6. Index of accepted/active ADRs

| ADR | Title | Status | Source candidate |
|---|---|---|---|
| `ADR-0001` | No empty domain-folder stubs | `ACCEPTED` (2026-07-15) | `ADR-CAND-ARCH-011` |
| `ADR-0002` | Package manager and initial toolchain version pins | `ACCEPTED` (2026-07-15) | `ADR-CAND-ARCH-024` (package-manager component only) |
| `ADR-0003` | Runtime validation library for the environment schema | `ACCEPTED` (2026-07-15) | None (new, operationalizes the existing "Zod-or-equivalent" pattern from `04_*.md`/`08_*.md`) |
| `ADR-0004` | CI/CD platform | `ACCEPTED` (2026-07-15) | `ADR-CAND-ARCH-024` (CI/CD-platform-product component — fully closes this candidate together with `ADR-0002`) |
| `ADR-0005` | Component library foundation | `ACCEPTED` (2026-07-15) | `ADR-CAND-ARCH-020` |
| `ADR-0006` | Design-token mechanism | `ACCEPTED` (2026-07-15) | `ADR-CAND-ARCH-021` |
| `ADR-0007` | Test-runner and framework stack | `ACCEPTED` (2026-07-15) | `ADR-CAND-ARCH-022` |
| `ADR-0008` | DR-rehearsal cadence and automated-accessibility-checker tool | `ACCEPTED` (2026-07-15) | `ADR-CAND-ARCH-023` |
| `ADR-0009` | Observability platform | `ACCEPTED` (2026-07-15) | `ADR-CAND-ARCH-026` |
| `ADR-0010` | Secret-manager mechanism | `ACCEPTED` (2026-07-15) | `ADR-CAND-ARCH-025` |
| `ADR-0011` | Webhook signature scheme, timestamp tolerance, and auto-disable threshold | `ACCEPTED` (2026-07-19) | `ADR-CAND-ARCH-018` (partial) |
| `ADR-0012` | GraphQL depth and complexity limit values | `ACCEPTED` (2026-07-19) | `ADR-CAND-ARCH-017` (partial) |
| `ADR-0013` | Job queue backoff formula, worker lease duration, and DLQ numeric defaults | `ACCEPTED` (2026-07-19) | `ADR-CAND-ARCH-028` (newly minted) |
| `ADR-0014` | PostGIS extension version, spatial column type, and bounded-radius query cap | `ACCEPTED` (2026-07-22) | `ADR-CAND-ARCH-029` (newly minted) |
| `ADR-0015` | Commercial vendor/service/rate lookup ownership (Phase 2 vs. Phase 6) | `ACCEPTED` (2026-07-23) | `ADR-CAND-ARCH-030` (newly minted; formalizes `05_DATABASE_SCHEMA_WORKSTREAM.md` line 93's qualitative Step 3 resolution) |
| `ADR-0016` | CargoGrid default brand identity (color, typography) | `ACCEPTED` (2026-07-24) | None (new; resolves `docs/standards/DESIGN_SYSTEM.md` §3's disclosed open item, out-of-band Design System Expansion task) |
| `ADR-0017` | CargoGrid Adaptive Industrial UI design language and white-label governance boundary | `ACCEPTED` (2026-07-24) | None (new; formalizes `RPD-019` at implementation precision, out-of-band Design System Expansion task) |
| `ADR-0018` | Canonical Account/Customer entity shape and ownership (flat-column `app.accounts`, not Master Data Engine-based) | `ACCEPTED` (2026-07-24) | `ADR-CAND-ARCH-012` |
| `ADR-0019` | Canonical Item/SKU and UOM master identity and ownership (flat-column `app.item_masters`/`app.uoms`, not Master Data Engine-based) | `ACCEPTED` (2026-08-03) | `ADR-CAND-ARCH-031` (newly minted) |
| `ADR-0020` | Phase 6 canonical vendor identity reconciliation (`vendor` vs. `vendor_rate` master types) and `PRC` write authority | `ACCEPTED` (2026-08-05) | `ADR-CAND-ARCH-032` (newly minted) |
| `ADR-0021` | Batched adversarial review-and-fix execution cadence (≤ 5 prompts per review round), with per-prompt automated gates and a mandatory defect-taxonomy self-check as compensating controls | `ACCEPTED` (2026-08-07) | `ADR-CAND-ARCH-033` (newly minted) |
| `ADR-0022` | Phase 6 Integrated Verification proceeds over internally-scoped capabilities while the Optional Vendor Portal stays ADR-blocked | `ACCEPTED` (2026-08-08) | None prior (newly identified literal-text tension, same character as `ADR-0021`'s own out-of-band process reconciliation). **This row closes a previously-disclosed registry gap**: `ADR-0022` existed as a file but was never indexed here — first found and disclosed (not fixed) at `CG-S11-PRC-021` (Prompt 270); closed by this checkpoint (`CG-S12-HRT-001`, Prompt 273) while adding `ADR-0023` below |
| `ADR-0023` | Phase 7 `org_units` `team` node type (Part A, newly minted), and ratification of employee-versus-user identity ownership (Part B, promotes the already-Step-3-resolved `ADR-CAND-ARCH-002` to a ratified record for the first time) | `ACCEPTED` (2026-08-09) | Part A: `ADR-CAND-ARCH-034` (newly minted). Part B: `ADR-CAND-ARCH-002` (§5.1, promoted) |
| `ADR-0024` | Phase 8 customer-portal read/write access pattern (Part A/B, ratifies and generalizes the already-shipped `ATW-023`/`ATW-032` pattern), REST/GraphQL transport scope (Part C, defers the live-GraphQL-server question), and loyalty ledger/Finance-liability-handoff shape (Part D, mirrors the inventory ledger and HRT-282 payroll-handoff patterns) | `ACCEPTED` (2026-08-16) | `ADR-CAND-ARCH-035` (newly minted) |
| `ADR-0025` | Phase 9 Public/Customer/Vendor API and Webhook Management reuse of `PLT-129`'s API-key/webhook primitives (Part A/B), Integration Hub as a governance layer under `RPD-038` (Part C), and Automation Rule Engine reuse of the existing `app.jobs` durable queue/job-type registry (Part D) | `ACCEPTED` (2026-08-21) | `ADR-CAND-ARCH-036` (newly minted) |
| `ADR-0026` | Step 17 package-metadata correction authority — narrows `GIT_STRATEGY.md` §4's blanket `docs/ai-agent-build-prompt-package/**` FORBIDDEN rule to `CAUTION` for exactly four derived-metadata files (`05_REQUIREMENT_COVERAGE_MATRIX.md`, `06_PACKAGE_BUILD_STATUS.md`, `07_PROMPT_PACKAGE_MANIFEST.md`, `START_HERE.md`), mechanical source-safe corrections only; all 324 prompt files and 18 step READMEs stay FORBIDDEN | `ACCEPTED` (2026-08-29) | `ADR-CAND-ARCH-037` (newly minted) |
| `ADR-0027` | Owner-authorized remediation scope and launch-gate risk acceptance. **Part A** lifts `AGENTS.md`'s per-task size cap and inverts "fix only task-caused failures" for a declared backlog-remediation task, unblocking the 82 issues that were scope-blocked rather than impossible; expires when that backlog reaches zero. **Part B** records the human-only launch gates (UAT, penetration test, GitHub branch protection, statutory tax confirmation) as `ACCEPTED_RISK (OWNER_OVERRIDE)` — dated, risk stated in plain language, **accepted and never labelled passed** — and satisfies `GO_NO_GO_REPORT.md` §7 item 6. **Part C** names every integrity rule that does not move. | `ACCEPTED` (2026-08-30) | `ADR-CAND-ARCH-038` (newly minted) |
| `ADR-0028` | Package revision `0.19.0`: authority to close Step 17's own eight open findings — extends `ADR-0026`'s narrow, source-safe metadata-correction authority to the revision that closes them. **This row closes the same registry gap `ADR-0022` once had**: `ADR-0028` existed as a file from 2026-08-30 but was never indexed here; found and closed by this checkpoint while adding `ADR-0029` below | `ACCEPTED` (2026-08-30) | None (extends `ADR-0026`) |
| `ADR-0029` | Vendor-bill match-exception approval stays a domain-owned maker-checker rather than migrating onto the canonical `PLT-123` engine — closes `ISS-2026-061` by taking that entry's own second named outcome. Ruled on evidence, not preference: the canonical procurement on-ramp returns `required = false` when a tenant has published no policy row, which would convert an unconditional accounts-payable control into an opt-in one; it would also introduce `approval_definition_not_configured` as a new unavailability, and would make invoice matching the fifth domain sharing the single tenant-wide approval routing definition `ISS-2026-069` already flags as overloaded. Conditional, not permanent — revisit once `ISS-2026-069` permits per-domain routing | `ACCEPTED` (2026-08-31) | None (resolves `ISS-2026-061`; blocked-on `ISS-2026-069`) |
