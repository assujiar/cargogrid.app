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
| `ADR-CAND-ARCH-002` | RLS policy family model | `06_RLS_RBAC_WORKSTREAM.md` |
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
| `ADR-CAND-ARCH-012` | `customers` extension-table vs. flat-column strategy | Phase 1 schema (Prompt 120+) | `BLOCKED` — needs Phase 1 schema slice |
| `ADR-CAND-ARCH-013` | `shipments` wide-table vs. linked-table split | Phase 3 schema (Prompt 168+) | `BLOCKED` — needs Phase 3 schema slice |
| `ADR-CAND-ARCH-014` | Rule-evaluation timeout (≈500ms) | Config engine (Phase 1 `07_*.md`) | `PROPOSED` — value signalled, ratify at build |
| `ADR-CAND-ARCH-015` | Config-engine bounded-evaluator sandbox | Config engine (Phase 1) | `PROPOSED` |
| `ADR-CAND-ARCH-017` | GraphQL depth/complexity limits + persisted-op registry | API workstream (Phase 1+) | `BLOCKED` — needs enforcement surface |
| `ADR-CAND-ARCH-018` | Webhook retry/backoff/DLQ numeric values | API workstream | `PROPOSED` |
| `ADR-CAND-ARCH-019` | Deployment ordering / API-consumer compatibility | DevOps (Phase 0 CI + release) | `PROPOSED` |
| `ADR-CAND-ARCH-020` | Component-library foundation | Phase 0 `PH0-090` (Design System) | **ACCEPTED → `ADR-0005`** (Radix UI primitives, copy-in pattern) |
| `ADR-CAND-ARCH-021` | Design-token mechanism + token file location | Phase 0 `PH0-090` | **ACCEPTED → `ADR-0006`** (CSS custom properties + Tailwind v4 `@theme`) |
| `ADR-CAND-ARCH-022` | Test-tooling/coverage-gate specifics | Phase 0 `PH0-091` (Testing) | **ACCEPTED → `ADR-0007`** (`node:test` unit/integration/component, Playwright E2E/visual-regression, `tests/factories/<domain>.ts`) |
| `ADR-CAND-ARCH-023` | DR-rehearsal cadence + automated-accessibility-checker tool | Phase 0 `PH0-091` (Testing) | **ACCEPTED → `ADR-0008`** (quarterly cadence, `@axe-core/playwright`). *Correction (`PH0-91`, `ADR-0008` "Scope discrepancy" section): this row previously read "DR-rehearsal cadence" only, reassigned to "Phase 15 (`HDN-384`)," dropping the accessibility-checker half — an unintended narrowing during this register's transcription from `docs/architecture/10_TESTING_WORKSTREAM.md` §11, not a deliberate re-scoping recorded anywhere. Both halves are resolved here, at the phase/task `10_*.md` §11 and the current `HANDOFF.md`/`TASK_LEDGER.md` always specified.* |
| `ADR-CAND-ARCH-024` | CI/CD platform + package manager | Phase 0 `PH0-085..088` | **Fully `ACCEPTED`** — package-manager component → `ADR-0002` (`PH0-085`); CI/CD-platform-product component → `ADR-0004` (`PH0-088`, GitHub Actions) |
| `ADR-CAND-ARCH-025` | Secret-manager product | Phase 0 `PH0-085..088`/`094` | `BLOCKED` — due at environment/security |
| `ADR-CAND-ARCH-026` | Observability/APM tool | Phase 0 `PH0-093` | `BLOCKED` — due at Observability |
| `ADR-CAND-ARCH-027` | Hosting/CDN platform | Phase 0 `PH0-085..088` | `BLOCKED` — due at environment |

*(Count reconciliation: `HANDOFF.md` §7's "10 resolved / 17 open" split is corrected here to **11 resolved / 16 open** — 001–010 + 016 = 11; 011–015 + 017–027 = 16; union = 27. The discrepancy was a one-item miscount, not a missing candidate; every one of the 27 is accounted for above.)*

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
