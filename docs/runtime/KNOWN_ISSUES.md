# KNOWN_ISSUES.md

**Instance of:** `CG-AABPP-GOV-018`
**Instance version:** `0.2.0`
**Updated:** 2026-07-14T09:58:59+07:00
**Policy:** Track unresolved, accepted, deferred, or externally constrained product/technical issues. Exact runtime failures belong in `ERROR_LEDGER.md`; issues may link errors.

## 1. Status and severity

Statuses: `OPEN`, `TRIAGED`, `PLANNED`, `IN_PROGRESS`, `MONITORING`, `ACCEPTED_RISK`, `RESOLVED`, `VERIFIED`, `SUPERSEDED`.

## 2. Standing accepted risks

These ratified risks must remain visible; they are not implementation bugs to be silently "fixed."

| Decision | Accepted condition | Required permanent handling |
|---|---|---|
| RPD-022 | Supreme Admin can mutate/delete audit, ledger, payment, and final records | No tamper-proof/absolute-immutability claim; disclose in security, finance, retention, and support material |
| RPD-034/036 | Direct GA without external pilot | Full internal UAT, penetration, performance, DR, finance, all-module, and zero-critical-defect gates |
| RPD-031/037 | Contract-silent RPO/RTO is best effort | Never imply a recovery guarantee; record actual rehearsal evidence |
| RPD-038 | Custom non-AI integrations without generic provider abstraction | Shared codebase, explicit ownership, credentials, contracts, tests, monitoring, and runbook; no tenant fork |

## 3. Issue index

| Issue ID | Title | Severity | Status | Scope/environment | Owner | Target task/release | Workaround | Release blocker | Record link |
|---|---|---|---|---|---|---|---|---|---|
| `ISS-2026-001` | Primary source documents not tracked in repository | Medium | `TRIAGED` | Repository / all environments | Product / Build agent | Before any implementation gate that must verify source fidelity | Use package control-file summaries (`00-control/`) as interim authority | Conditional — blocks source-fidelity verification, not discovery | this file |

## 4. Issue record

### ISS-2026-001 — Primary source documents not tracked in repository

| Field | Value |
|---|---|
| Reported/detected by/date | Runtime agent / 2026-07-14 |
| Severity/status/priority | Medium / `TRIAGED` / normal |
| Product module/phase/workstream | Step 2 discovery / Architecture-repository |
| Environment/tenant class | Repository (no tenant data) |
| Owner/approver | Product / Build agent |
| Source requirement/decision | Package README §3 source inventory |
| Related tasks/errors/changes | `CG-S2-DISC-001`, `CHG-2026-001` |
| Target task/release/date | Before implementation phases consume source detail |
| Release effect | Does not block discovery; must be resolved before claiming source-faithful implementation |

#### Problem statement

The CargoGrid AI Agent Build Prompt Package (`00-control/00_PACKAGE_README.md` §3) references six authoritative source documents — the Product Concept Brief and documents `01`–`05` (Charter, BPR, UX/Data, Technical, Delivery). These files are **not tracked** in this repository; only the prompt package derived from them and this runtime context are present.

Expected behavior: authoritative source documents available in-repo (or a controlled location) for verification during implementation.
Observed limitation: only package control-file summaries and prompt artifacts are available; the underlying source text cannot be independently re-verified from this repository.

#### Evidence and reproduction

- `git ls-files | grep -v '^docs/ai-agent-build-prompt-package/'` → only `README.md`.
- Package README §3 lists source filenames (e.g. `CargoGrid_Product_Concept_Brief(10).md`) that are absent from `git ls-files`.
- Reproducibility: ALWAYS.

#### Impact

| Domain | Impact | Affected users/data/contract | Severity evidence |
|---|---|---|---|
| Functional/E2E | None yet (no implementation) | — | — |
| Tenant/security/privacy | None | — | — |
| Finance/audit/retention | Potential later: statutory/finance detail must trace to a source | Finance/HR flows | Package coverage matrix |
| API/integration/job | None yet | — | — |
| Performance/accessibility/browser | None | — | — |
| Migration/deployment/recovery | None | — | — |

#### Workaround and containment

- Workaround: treat `00-control/` registers and coverage matrix as the interim authoritative summary; they encode CPD-001..023 and RPD-001..040.
- Limitations: summaries are lossy versus full source; deep functional detail (BPR is ~3,300 lines) is not fully reconstructable from summaries.
- Monitoring: revisit when any implementation prompt requires exact source-clause fidelity.
- Workaround expiry/removal trigger: first phase task that depends on unsummarized source detail.

#### Resolution plan

| Step/task | Owner | Dependency | Acceptance/test | Target | Status |
|---|---|---|---|---|---|
| Obtain and track the six source docs (or confirm the registers are the ratified authority) | Product | Repository owner input | Sources present or governance decision recorded | Before Phase 0 source-alignment prompt (81) | `PLANNED` |

## 5. Maintenance rules

1. Do not delete resolved issues; mark `VERIFIED` or `SUPERSEDED`.
2. Link reproducible failures to Error Ledger entries instead of duplicating raw logs.
3. Re-triage severity when scope, exploitability, data impact, or contracts change.
4. Reconcile release blockers with build status and go/no-go reports.
5. An ownerless or targetless non-low issue cannot be considered safely triaged.
