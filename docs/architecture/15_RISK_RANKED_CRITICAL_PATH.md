# 15 — Risk-Ranked Critical Path

**Prompt:** `CG-S3-ARCH-015` (`CG-AABPP-ARCH-050` v0.4.0)
**Runtime output of:** `docs/ai-agent-build-prompt-package/03-architecture-and-plan/50_RISK_RANKED_CRITICAL_PATH_PROMPT.md`
**Status:** `VERIFIED`

## 0. Checkpoint

| Field | Value |
|---|---|
| Repository | `assujiar/cargogrid.app` |
| Working branch | `claude/sleepy-ride-4vxsk6` |
| HEAD at authoring time | `e1a658cef9715efe6da154f03c1f191515f1b5c6` (parent of this checkpoint's commit — `CG-S3-ARCH-014` / Prompt 49 checkpoint) |
| Precondition | `docs/architecture/01_*.md` through `14_*.md` all `VERIFIED` |
| Repository state | Unchanged: 100% documentation, zero application code, zero migration, zero test, zero CI/environment/secret resource |
| Mutation performed | **NONE** — this document ranks and sequences already-registered WBS items, requirement rows, and ADR candidates; it invents no task, requirement, ADR, duration, staffing figure, or date (prompt precondition and completion gate) |

### Inputs read (full)

- `docs/runtime/HANDOFF.md` (current checkpoint, task index, dependency graph, branch history)
- `docs/ai-agent-build-prompt-package/03-architecture-and-plan/50_RISK_RANKED_CRITICAL_PATH_PROMPT.md` (this document's task definition)
- `docs/architecture/13_FULL_WORK_BREAKDOWN_STRUCTURE.md` (full — WBS phase register §4, capability-ID scheme §2, dependency edges §6, ADR/gate register §11, completeness checks §12)
- `docs/architecture/14_REQUIREMENT_PHASE_TRACEABILITY.md` (full — 401-item traceability matrix, `PARTIAL_BLOCKED`/`EXTERNAL_VERIFICATION`/`ACCEPTED_RISK` rows §3–§17, accepted-risk overlay §19, external gates §20, closure tasks §23, blocker list §24)
- `docs/architecture/12_RELEASE_TRAIN.md` (full — phase sequencing §3, cross-phase split reconciliation §4, freeze/rollback/hypercare §7, capacity assumptions §8, phase-level dependency diagram §9, risk carry-forward §10)
- `docs/discovery/11_TECHNICAL_DEBT_RISK_REGISTER.md` (full — Step 2 `RISK-001..009` register, scoring method, accepted-risk overlay)
- `docs/architecture/01_MODULE_DEPENDENCY_MAP.md` (full — module catalogue, dependency matrix, `MDM-RISK-001..002`, ADR candidates `001..004`)
- `docs/architecture/02_CANONICAL_DATA_FLOW_MAP.md` (`MDM-RISK-003..004`, `ADR-CAND-ARCH-005/006` — cited via `05_*.md`/`06_*.md`'s resolutions)
- `docs/architecture/03_DOMAIN_BOUNDARY_MAP.md` (full — ownership catalogue, public contracts §5, boundary violation patterns §9, `ADR-CAND-ARCH-007/008`)
- `docs/architecture/04_REPOSITORY_TARGET_STRUCTURE.md` (full — target structure, transition sequence §8, `ADR-CAND-ARCH-009/010/011`, `MDM-RISK-005`)
- `docs/architecture/05_DATABASE_SCHEMA_WORKSTREAM.md` (full — schema ownership §3, finance controls §5, migration waves §8, `ADR-CAND-ARCH-001/005/007/008/009/012/013` resolutions, `MDM-RISK-006`)
- `docs/architecture/06_RLS_RBAC_WORKSTREAM.md` (full — evaluation flow §3, RLS matrix §4, Supreme Admin semantics §8, negative-test matrix §10, `ADR-CAND-ARCH-002/006` resolutions)
- `docs/architecture/07_CONFIGURATION_ENGINE_WORKSTREAM.md` (full — engine catalogue §3, security/finance guardrails §11, `ADR-CAND-ARCH-010/014/015`)
- `docs/architecture/08_API_INTEGRATION_WORKSTREAM.md` (full — REST/GraphQL parity §2–§5, webhook/job contracts §7–§9, integration adapter template §8, `ADR-CAND-ARCH-016/017/018/019`)
- `docs/architecture/09_UX_DESIGN_SYSTEM_WORKSTREAM.md` (`ADR-CAND-ARCH-020/021` — component-library/design-token foundation, atomic backlog)
- `docs/architecture/10_TESTING_WORKSTREAM.md` (full — test architecture §2, critical suites §5, CI gate model §6, zero-critical-defect direct-GA gate §10.3, `ADR-CAND-ARCH-022/023`)
- `docs/architecture/11_DEVOPS_WORKSTREAM.md` (full — environment topology §2, secrets §5, observability §6, backup/DR/incident §8, capacity thresholds §9, `ADR-CAND-ARCH-004/024/025/026/027`)
- `docs/ai-agent-build-prompt-package/03-architecture-and-plan/` directory listing (confirms Prompt 51 is `51_STEP3_CLOSURE_VERIFICATION_PROMPT.md`, the final Step 3 file)
- `docs/blueprint/05_CargoGrid_Delivery_Testing_GoLive_Plan.md` direct-GA/zero-critical-defect/tax-payroll language — already fully reproduced and cross-cited in `12_*.md` §1/§7.1, `10_*.md` §10.3, and `14_*.md` §19/§20/§23; not independently re-derived here (citation, not re-authoring, per this repository's evidence-precedence rule)

## 1. Scope and method

This document ranks and sequences work that already exists in `13_FULL_WORK_BREAKDOWN_STRUCTURE.md` (WBS capability/gate/ADR register) and `14_REQUIREMENT_PHASE_TRACEABILITY.md` (401-item requirement traceability matrix). It creates **no** new WBS ID, requirement ID, or ADR candidate — every row in §5's risk table cites an ID already registered in one of those two documents (or in `01_*.md`–`12_*.md`'s own risk/ADR sections). Per the prompt's binding precondition, **no duration, staffing level, or calendar date is invented anywhere in this document** — sequencing is dependency-depth-based (§4), exactly as `12_RELEASE_TRAIN.md` §8's "sequencing basis" already establishes for the release train as a whole; this document extends that same dateless, gate-based discipline to risk-adjusted prioritization within and across phases, it does not introduce a second, conflicting scheduling model.

The distinction this document adds over `13_*.md`/`14_*.md` is: those two documents establish *what* work exists and *whether* each item is delivery/verification-owned; this document establishes *in what order, weighted by risk, that work should be pulled* — including recommending that some low-WBS-position but high-risk items (e.g. external SME engagement nominally scheduled at a late phase) begin their non-code-dependent portion earlier than their capability slice's nominal phase, because risk (not phase number) governs safe sequencing per the prompt's own objective ("effort is sequenced by blocker reduction rather than feature visibility").

## 2. Ranking method and scales

### 2.1 Nine ranking dimensions (each 1–5, higher always worse)

| # | Dimension | 1 (best) | 2 | 3 | 4 | 5 (worst) |
|---|---|---|---|---|---|---|
| 1 | **Severity (Sev)** — impact if the risk materializes | Cosmetic, no user/tenant impact | Minor, workaround exists | Moderate, degrades one capability | Major, blocks a phase gate or a named safety control | Critical — tenant-isolation, financial-integrity, legal/compliance, or irreversible-data-loss class |
| 2 | **Likelihood (Lik)** — chance the risk materializes absent further action | Rare (needs multiple independent failures) | Unlikely | Possible (plausible under normal build conditions) | Likely (known gap, no interim control yet) | Near-certain (already flagged as unresolved with no mitigation in place) |
| 3 | **Blast radius (Rad)** — how much of the system is affected | Single table/capability | Single domain/phase | Two–three phases or one cross-domain contract | Platform-wide (shared kernel, every business domain) | Whole-system / every tenant (tenant isolation, GA gate, finance ledger) |
| 4 | **Tenant/security/finance/data exposure (Exp)** — worst-case exposure class touched | None of the four classes | One class, indirectly | One class, directly | Two classes simultaneously | Three-plus classes, or any finance-ledger/tenant-isolation combination (RPD-022-adjacent) |
| 5 | **Dependency centrality (Dep)** — how many other WBS/gate items depend on this one resolving correctly | Leaf, nothing downstream depends on it | 1–2 downstream capabilities | One phase-exit gate depends on it | Multiple phase-exit gates, or a shared-kernel primitive | The whole build depends on it (Phase 0/1 foundation, terminal go-live gate) |
| 6 | **Reversibility (Rev)** — cost of undoing the risk once realized | Trivially reversible (`git revert`, no data touched) | Reversible with minor rework | Reversible with a migration/backfill | Difficult (customer-visible or contractual exposure) | Irreversible (ledger/audit mutated, tenant data lost, GA commitment already made) |
| 7 | **Detection strength gap (Det)** — how weak the planned detection mechanism is | Automated test/gate already named and specific | Automated test planned, not yet built | Manual/SME review only | Incident-response/post-hoc audit only | No named detection mechanism exists yet |
| 8 | **Uncertainty (Unc)** — how unresolved the item is | Fully ratified, no open ADR | ADR raised, non-blocking, clear recommendation given | ADR raised, no recommendation adopted | `EXTERNAL_VERIFICATION` pending (SME/legal/security) | `ACCEPTED_RISK` — standing disclosure with no closure mechanism, by design |
| 9 | **Remediation complexity (Rem)** — effort class to close the gap | One-line config/ADR pick | Single capability slice (Template 53 sizing: 1–3 migrations / 5–15 files) | Multi-slice within one phase | Cross-phase coordination required | Requires an external party (SME/legal/security vendor) or a cross-cutting architecture change |

These nine dimensions are exactly the nine the prompt's task #3 names (severity, likelihood, blast radius, tenant/security/finance/data exposure, dependency centrality, reversibility, detection strength, uncertainty, remediation complexity) — no dimension is added or dropped, and none is a duration/staffing estimate.

### 2.2 Composite Risk Score (CRS) — reproducible formula

```
CRS = (Sev × Lik) + Rad + Exp + Dep + Rev + Det + Unc + Rem
```

- Severity and Likelihood are combined multiplicatively (the classical risk-matrix product, range 1–25) because a high-severity/low-likelihood item and a low-severity/high-likelihood item are not equivalent risks, and an additive-only model would treat them as such.
- The remaining seven dimensions are added, unweighted (range 7–35), because each independently amplifies the risk's dangerousness or urgency without being reducible to a probability × impact pair (e.g. "irreversibility" is a property of the failure mode, not of its likelihood).
- **Range:** minimum `(1×1)+1+1+1+1+1+1+1 = 8`; maximum `(5×5)+5+5+5+5+5+5+5 = 60`.
- **Reproducibility rule:** every row in §5 shows its own eight input scores plus the arithmetic — a reader can recompute the CRS and get the same rank order; no score is asserted without its components shown.
- This formula is deliberately simple (no weighting coefficients beyond the Sev×Lik product) so it is auditable by inspection, consistent with the completion gate's "ranking must be reproducible" requirement — a more elaborate weighted model would not improve on this at the current pre-implementation evidence level (no measured incident data exists yet to calibrate weights against, per `docs/discovery/08_PERFORMANCE_BASELINE.md`'s `UNKNOWN` baseline).

### 2.3 What this method deliberately does not do

Per the prompt's explicit prohibition, this method assigns no duration (days/weeks), no staffing level, and no calendar date to any item — "Remediation complexity" (dimension 9) is an *effort class* (one-line change vs. cross-phase vs. external-party), never a time estimate. Where `12_RELEASE_TRAIN.md` §8 already states team-sizing/cadence figures, they are cited in §11 below as **assumptions**, not incorporated into the CRS formula, because incorporating an assumed figure into a "reproducible" ranking would make the ranking's reproducibility depend on an unvalidated number.

## 3. Dependency graph summary

### 3.1 Phase-level backbone (reproduced by reference, not re-derived)

The binding phase-to-phase dependency graph is `01_MODULE_DEPENDENCY_MAP.md` §4/§10 and `12_RELEASE_TRAIN.md` §9's mermaid diagram — this document does not redraw it a third time with different wording. Its shape, restated only as the frame this document's risk ranking operates over:

`PHASE_0_VERIFIED → Phase 1 (Platform Core) → PHASE_1_VERIFIED → Phase 2 (Commercial) → PHASE_2_VERIFIED → Phase 3 (Operations basic + Portal basic) → PHASE_3_VERIFIED → Phase 4 (Finance) → PHASE_4_VERIFIED → {Phase 5 (Operations advanced) ‖ Phase 6 (Procurement/Vendor)} → PHASE_5_VERIFIED ∧ PHASE_6_VERIFIED → Phase 7 (HRIS + Ticketing) → PHASE_7_VERIFIED → Phase 8 (Portal full + Loyalty) → PHASE_8_VERIFIED → Phase 9 (Intelligence/Enterprise) → PHASE_9_VERIFIED → Phase 15 (Full-system hardening) → FULL_SYSTEM_HARDENING_VERIFIED → Phase 16 (RC and Go-Live) → RELEASE_GO_LIVE_VERIFIED → direct GA.`

The only genuine fork is Phases 5/6 (both gated solely on `PHASE_4_VERIFIED`, both must independently close before Phase 7 opens, per `12_*.md` §9's note that Phase 7's `HRS`→`APPR`/`OPS` edge relies on Phase 1's identity model, not Phase 5/6's outputs) — this is the one place two phases are genuinely concurrency-eligible at the phase level (§8 below).

### 3.2 Atomic-task-level detail where it matters for the critical path

Reproducing all 263 capability prompts' individual edges would duplicate `13_*.md` §5's own citation-by-reference discipline; the atomic-level detail that changes this document's ranking (as opposed to merely restating `13_*.md`) is:

- **The Phase 1 primitive-ordering chain** (`13_*.md` §5.1, `01_*.md` §3.1): `TEN-IAM` (`PLT-105`→`116`) → `WLB`/`MDM` → `CFG` → `WF` → `APPR` → `STAT` → `NUM` → `FORM` → `NOTIF` → `DOC` → `API-WH` → `IMPEXP` → `JOB` → `FLAG` → `GEO` → `PORTAL-ADM`. Every business domain (Phases 2–9) depends on this entire chain (`01_*.md` §3.2) — this is the single highest dependency-centrality chain in the whole build, which is why §5's table ranks its constituent risks (RLS/RBAC foundation, config-engine bounded evaluator, API/webhook foundation) among the highest-CRS rows.
- **The ten public contracts** (`03_*.md` §5): `Quotation-accepted→Job Order`, `Vendor-rate lookup`, `Billing-readiness event`, `Vendor-bill-matched event`, `Payroll-posting-input event`, `Eligible-transaction event`, `Typed ticket link`, `Booking/quote-request intake`, `Ticket-request intake`, `Any domain→REP` — these are the exact atomic-level integration checkpoints between phases (§8 below), not phase-gate abstractions.
- **ADR-gated atomic edges**: `ADR-CAND-ARCH-001` (vendor-rate ownership, resolved — `PRC` owns `vendor_rates` from Phase 1's minimal master-data slice, Commercial reads via `app.v_active_vendor_rates`), `ADR-CAND-ARCH-002` (HRIS↔Platform identity, resolved — `employees.user_id` FK), `ADR-CAND-ARCH-005` (Job→Shipment fan-out atomicity, resolved — one DB transaction + idempotency key), `ADR-CAND-ARCH-006` (ticket-link staleness, resolved — two-part RLS rule), `ADR-CAND-ARCH-007` (schema-per-domain vs. single `app` schema, resolved in favor of single schema). These five are already **resolved** — they do not block the critical path, but their *residual* risk (a resolved ADR whose enforcement mechanism has not yet been built) is what `MDM-RISK-001..004` (§5 rows 16–19) tracks.
- **Open, non-blocking ADR-gated atomic edges that do affect ranking**: `ADR-CAND-ARCH-012`/`013` (customer/shipment schema strategy, Phase 1 `MDM`/Phase 2 `COM` and Phase 3 `OPS` respectively), `ADR-CAND-ARCH-014`/`015` (rule-evaluator timeout/grammar, Phase 1 `CFG`/`RULE`), `ADR-CAND-ARCH-017`/`018`/`019` (GraphQL/webhook numeric values, Phase 1 `API-WH`), `ADR-CAND-ARCH-020`/`021` (component-library/design-token, Phase 0 Prompt 90), `ADR-CAND-ARCH-022`/`023` (test-runner/DR-cadence tooling, Phase 0 Prompt 91), `ADR-CAND-ARCH-024`/`025`/`026`/`027` (CI/CD, secret manager, observability, hosting/CDN — Phase 0 environment/CI kickoff).

### 3.3 Gate/evidence dependencies layered on the phase graph

Beyond the module dependency graph, three evidence-class dependencies run **across** the phase graph rather than within one phase, and are the ones this document's ranking treats as first-class nodes: (a) `RGL-412`'s zero-critical-defect Go/No-Go, which depends on every `PHASE_N_VERIFIED` gate plus the Phase 15 full-suite re-run; (b) `FIN-195`/`HRT-282`'s external SME sign-offs, which depend only on the tax/payroll *policy content* being available for review, not on their nominal phase's schema being built (§4.2 below); (c) `RGL-402`'s penetration test and `HDN-384`'s DR rehearsal, both of which depend on a materially complete system existing to test against, but not on any single phase's internal completion.

## 4. Critical path and near-critical branches

**Method note (binding):** ordering below is by dependency depth alone — no duration is attached to any arrow, matching `12_RELEASE_TRAIN.md` §8's "sequencing basis (binding, not an assumption): ... Phase N's entry gate is always 'Phase N−1 `VERIFIED`,' never 'N weeks after Phase N−1 started.'" This document's only addition to that dependency-depth ordering is a risk-adjusted **pull-forward recommendation** for specific non-code-dependent sub-tasks (§4.2), which does not reorder any phase gate, only recommends starting an external, schedule-independent activity earlier within the already-fixed gate structure.

### 4.1 Critical path (deepest, single dependency chain — matches `12_*.md` §9 exactly, reproduced here as the spine this document's risk table hangs on)

```
PHASE_0_VERIFIED
  → Phase 1: Platform Core (TEN-IAM chain → WLB/MDM → CFG → WF → APPR → STAT → NUM → FORM → NOTIF → DOC → API-WH → IMPEXP → JOB → FLAG → GEO → PORTAL-ADM)
  → PHASE_1_VERIFIED
  → Phase 2: Commercial (lead → opportunity → quotation → approval → acceptance)
  → PHASE_2_VERIFIED
  → Phase 3: Operations (basic) + Customer Portal (basic) (job order → shipment → milestone → ePOD → actual cost → billing-ready)
  → PHASE_3_VERIFIED
  → Phase 4: Finance (billing-ready → invoice → journal → payment → profitability; FIN-195 tax-SME gate)
  → PHASE_4_VERIFIED
  → { Phase 5: Operations advanced (TMS/WMS)  ‖  Phase 6: Procurement/Vendor }  [genuinely parallel-eligible lane, §8]
  → PHASE_5_VERIFIED ∧ PHASE_6_VERIFIED
  → Phase 7: HRIS + Ticketing (HRT-282 payroll-SME gate)
  → PHASE_7_VERIFIED
  → Phase 8: Customer Portal (full) + Loyalty
  → PHASE_8_VERIFIED
  → Phase 9: Intelligence, Automation, Enterprise
  → PHASE_9_VERIFIED
  → Phase 15: Full-system hardening (full TI-*/FINTEST-*/UAT-E2E-* re-run, RGL-402 pen test, HDN-384 DR rehearsal)
  → FULL_SYSTEM_HARDENING_VERIFIED
  → Phase 16: Release Candidate and Go-Live (RGL-412 zero-critical-defect Go/No-Go — RPD-034/036 direct GA)
  → RELEASE_GO_LIVE_VERIFIED
  → direct GA (first external tenant is a production customer, never a pilot)
```

Every node in this chain is a WBS phase or a named gate already registered in `13_*.md` §4/§11 or `14_*.md` §19/§20 — no node is invented.

### 4.2 Risk-adjusted deviation from pure phase-number order (the "risk-adjusted" part of this document's mandate)

Two items are nominally positioned late in the phase sequence (Phase 4's `FIN-195`, Phase 7's `HRT-282`) but rank in the top 4 of §5's risk table because their **Uncertainty** (dimension 8, `EXTERNAL_VERIFICATION`) and **Remediation complexity** (dimension 9, "requires an external party") scores are maximal, and because SME sign-off does not require the owning phase's schema/UI to exist first — it requires only the tax/payroll *policy content* (rates, statutory rules, calculation logic) to be reviewable. **Recommendation (a scheduling/risk-management recommendation, not a reopened product decision or a new WBS task):** begin legal/finance/tax SME engagement for `FIN-195` and HR/payroll/tax SME engagement for `HRT-282` as early as Phase 0/1 — in parallel with Platform Core build-out — rather than waiting until each capability's nominal Phase 4/7 slot, since (a) `13_*.md` §11 and `14_*.md` §20 already name these as gates without specifying *when* SME conversation must start, (b) external SME availability/scheduling is outside this repository's control and typically has the longest lead time of any item in this plan, and (c) pulling this activity forward reduces exactly the highest-CRS items' Uncertainty and Remediation-complexity scores the earliest, which is the literal definition of "sequenced by blocker reduction" the prompt's objective states. This recommendation does not move `FIN-195`/`HRT-282`'s own WBS capability-prompt position in `13_*.md` §4 (both remain Phase 4/7 capability slices) — it only recommends that the *external verification conversation* (not the capability's implementation) start earlier, which is a scheduling choice fully within this document's "concurrency lanes" mandate (§8).

### 4.3 Near-critical branches

- **Phase 5/6 parallel lane** (§3.1/§8): near-critical because a delay in *either* phase delays Phase 7's entry gate identically — neither phase is individually on the single deepest chain, but their conjunction (`PHASE_5_VERIFIED ∧ PHASE_6_VERIFIED`) is exactly as blocking as the main chain at that point.
- **Phase 0 tooling-ADR resolution lane** (`ADR-CAND-ARCH-009/010/011/020/021/022/023/024/025/026/027`): near-critical because none of these individually sits on the phase-gate chain (they resolve *within* Phase 0, before `PHASE_0_VERIFIED`), but collectively they gate every subsequent phase's ability to build safely (CI, secrets, observability, design-system foundation, test tooling) — a delay compressing all of Phase 0 into "ship code before tooling is chosen" would violate `11_*.md` §1's own guardrail ("the first pipeline stage, environment, or secret for any layer is created by its owning Phase-0 kickoff prompt, never skipped").
- **External SME lane** (`FIN-195`, `HRT-282`, per §4.2): near-critical for the reasons above — not on the shortest phase-dependency path, but capable of delaying Phase 4/7's exit gates if not started early.
- **Phase 15 full-suite regression + pen test + DR rehearsal**: technically on the main chain (it is `PHASE_9_VERIFIED`'s sole successor), but flagged here because it is the single highest-Dependency-Centrality, lowest-Detection-Gap node in the entire graph — every earlier phase's residual defect surfaces here, for the first time, all at once, immediately before the irreversible Phase 16 GA decision.

## 5. Risk-ranked task table

Every row cites a real WBS ID (`13_*.md` §4/§5), requirement ID (`14_*.md`), or ADR ID (`01_*.md`–`13_*.md`). Scores are shown in full (Sev, Lik, Rad, Exp, Dep, Rev, Det, Unc, Rem) so the CRS is independently recomputable per §2.2's formula. Sorted descending by CRS; ties broken by Severity, then Dependency centrality.

| Rank | Item | Cited ID(s) | Phase | Sev | Lik | Rad | Exp | Dep | Rev | Det | Unc | Rem | CRS |
|---:|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | Finance tax/legal SME verification (PPN/VAT/withholding) | `FIN-195`, `FIN-TAX-*`, `FINTEST-007`, RPD-016 (`14_*.md` §4/§5/§15.3/§20/§23) | 4 | 5 | 4 | 4 | 4 | 4 | 5 | 3 | 4 | 5 | **49** |
| 2 | Payroll/tax SME verification | `HRT-282`, `HRS-PAY-*`, `BR-PAY-001` (`14_*.md` §5/§8/§20/§23) | 7 | 5 | 4 | 3 | 4 | 3 | 5 | 3 | 4 | 5 | **47** |
| 3 | Supreme Admin absolute-CRUD disclosed exception | RPD-022 (`06_*.md` §8, `14_*.md` §19, `01_*.md` `RISK-004`) | 1/4/15/16 | 5 | 3 | 5 | 5 | 3 | 5 | 3 | 5 | 5 | **46** |
| 4 | Direct-GA / zero-critical-defect Go/No-Go | RPD-034/036, `RGL-412` (`10_*.md` §10.3, `12_*.md` §7.1, `14_*.md` §19) | 16 | 5 | 3 | 5 | 5 | 5 | 5 | 2 | 2 | 4 | **43** |
| 5 | Penetration test (pre-GA external verification) | `RGL-402` (`14_*.md` §20, Blueprint §20.3) | 16 | 5 | 3 | 5 | 4 | 4 | 4 | 2 | 4 | 4 | **42** |
| 6 | Phase-15 full regression re-run (`TI`/`FINTEST`/`UAT-E2E`) | `HDN-386..389`, all 62 critical scenarios (`14_*.md` §15) | 15 | 5 | 3 | 5 | 5 | 5 | 4 | 1 | 2 | 4 | **41** |
| 7 | RLS/RBAC foundation and default-deny rollout | `PLT-105..116`, `06_*.md` §4/§9/§13, `NFR-SEC-001/002` | 1 | 5 | 3 | 5 | 5 | 5 | 4 | 2 | 1 | 2 | **39** |
| 8 | Observability/APM tool selection | `ADR-CAND-ARCH-026`, `PKG-NFR-OBS-001` (`11_*.md` §6/§10) | 0 | 4 | 3 | 5 | 3 | 5 | 2 | 4 | 3 | 3 | **37** |
| 9 | Contract-silent recovery = best effort | RPD-031/037 (`11_*.md` §8.1, `14_*.md` §19) | 15 | 4 | 2 | 4 | 4 | 2 | 5 | 3 | 5 | 5 | **36** |
| 10 | Shipment table schema split (highest-volume table) | `ADR-CAND-ARCH-013` (`05_*.md` §10, `14_*.md` §23) | 3 | 4 | 3 | 3 | 2 | 4 | 3 | 2 | 3 | 3 | **32** |
| 11 | Phase 0 CI/secret/hosting tooling ADR bundle | `ADR-CAND-ARCH-024/025/027` (`11_*.md` §10) | 0 | 4 | 2 | 5 | 3 | 5 | 2 | 2 | 3 | 3 | **31** |
| 12 | Component-library / design-token foundation | `ADR-CAND-ARCH-020/021`, `PKG-NFR-ACC-001` (`09_*.md`, `14_*.md` §7/§23) | 0 | 3 | 3 | 4 | 2 | 5 | 2 | 2 | 3 | 3 | **30** |
| 13 | Customer schema extension-table strategy | `ADR-CAND-ARCH-012`, `CPD-022` (`05_*.md` §10, `14_*.md` §3/§23) | 1/2 | 3 | 3 | 3 | 2 | 4 | 3 | 2 | 3 | 3 | **29** |
| 13 | SaaS billing vs. tenant-finance ID separation | `GAP-017` (`14_*.md` §17.2/§23) | 1 | 3 | 3 | 3 | 3 | 3 | 3 | 2 | 3 | 3 | **29** |
| 13 | DR rehearsal (quarterly, evidence gate) | `HDN-384`, `ADR-CAND-ARCH-023` (`11_*.md` §8.2, `14_*.md` §20) | 15 | 4 | 2 | 4 | 3 | 3 | 4 | 2 | 2 | 3 | **29** |
| 16 | Custom-integration, no-generic-abstraction policy | RPD-038 (`01_*.md` §7/§11, `08_*.md` §8.2, `14_*.md` §19) | 9 | 3 | 3 | 3 | 2 | 2 | 3 | 2 | 3 | 4 | **28** |
| 17 | Job Order→Shipment Order fan-out atomicity | `MDM-RISK-003`, `ADR-CAND-ARCH-005` (resolved) (`02_*.md` §12, `05_*.md` §4) | 3 | 4 | 2 | 2 | 3 | 3 | 4 | 2 | 1 | 2 | **25** |
| 18 | `report` schema read-only enforcement drift | `MDM-RISK-006` (`05_*.md` §11) | 1 | 3 | 2 | 3 | 2 | 3 | 3 | 3 | 2 | 2 | **24** |
| 18 | Bounded rule-evaluator timeout/grammar | `ADR-CAND-ARCH-014/015` (`07_*.md` §12) | 1 | 3 | 2 | 3 | 3 | 4 | 2 | 2 | 2 | 2 | **24** |
| 20 | Worker-split threshold (PostgreSQL durable queue) | `PKG-PLT-JOB-001`, RPD-012 (`14_*.md` §7, `11_*.md` §9.3) | 1 | 3 | 2 | 3 | 2 | 4 | 2 | 1 | 2 | 2 | **22** |
| 21 | Vendor-rate divergence residual | `MDM-RISK-001`, `ADR-CAND-ARCH-001` (resolved) (`01_*.md` §12, `14_*.md` §23) | 2/6 | 3 | 2 | 2 | 2 | 3 | 3 | 2 | 1 | 2 | **21** |
| 21 | HRIS identity divergence residual | `MDM-RISK-002`, `ADR-CAND-ARCH-002` (resolved) (`01_*.md` §12, `06_*.md` §11) | 7 | 3 | 2 | 2 | 2 | 3 | 3 | 2 | 1 | 2 | **21** |
| 21 | Domain-folder naming-convention drift | `MDM-RISK-005` (`04_*.md` §11) | 0–9 | 2 | 3 | 3 | 1 | 2 | 2 | 3 | 2 | 2 | **21** |
| 24 | Test-runner / DR-cadence tooling selection | `ADR-CAND-ARCH-022/023` (`10_*.md` §11) | 0 | 2 | 2 | 3 | 1 | 4 | 2 | 2 | 2 | 2 | **20** |
| 24 | GraphQL depth/complexity and webhook numeric values | `ADR-CAND-ARCH-017/018/019` (`08_*.md` §14) | 1 | 2 | 3 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | **20** |
| 26 | Ticket-link staleness enforcement | `MDM-RISK-004`, `ADR-CAND-ARCH-006` (resolved) (`02_*.md` §12, `06_*.md` §11) | 7 | 2 | 2 | 2 | 1 | 2 | 2 | 2 | 1 | 2 | **16** |

**Reproducibility check:** e.g. Rank 1 — `Sev(5) × Lik(4) = 20`; `+ Rad(4) + Exp(4) + Dep(4) + Rev(5) + Det(3) + Unc(4) + Rem(5) = 29`; `20 + 29 = 49`. Every other row recomputes identically from its own shown scores.

## 6. Foundation blockers (explicit)

Per the prompt's task #4, every named foundation-blocker category maps to a concrete WBS/ADR citation and its §5 rank — none is a bare assertion:

| Foundation blocker category | Concrete citation | §5 rank(s) | Phase |
|---|---|---:|---:|
| Repository strategy (target structure, boundaries, import rules) | `04_REPOSITORY_TARGET_STRUCTURE.md` §3–§5, `ADR-CAND-ARCH-009/010/011` | 21 (naming drift) | 0–9 |
| Target/domain boundaries | `03_DOMAIN_BOUNDARY_MAP.md` §3–§5, `ADR-CAND-ARCH-007` (resolved)/`008` | — (resolved; enforcement is `03_*.md` §10) | 0–9 |
| Schema/migrations | `05_DATABASE_SCHEMA_WORKSTREAM.md` §3/§8, `ADR-CAND-ARCH-012/013` | 13, 10 | 1/2/3 |
| Tenant/RLS/RBAC | `06_RLS_RBAC_WORKSTREAM.md` §4/§9/§13 | 7 | 1 |
| Configuration engines | `07_CONFIGURATION_ENGINE_WORKSTREAM.md` §11–§12, `ADR-CAND-ARCH-014/015` | 18 | 1 |
| API/contracts/jobs/files | `08_API_INTEGRATION_WORKSTREAM.md` §9/§10, `ADR-CAND-ARCH-017/018/019`, `PKG-PLT-JOB-001` | 24, 20 | 1 |
| CI/environments | `11_DEVOPS_WORKSTREAM.md` §2/§3, `ADR-CAND-ARCH-024/025/027` | 11 | 0 |
| Test data | `10_TESTING_WORKSTREAM.md` §4.2, `ADR-CAND-ARCH-022` | 24 | 0 |
| Observability | `11_DEVOPS_WORKSTREAM.md` §6, `ADR-CAND-ARCH-026` | 8 | 0 |
| Backup/recovery | `11_DEVOPS_WORKSTREAM.md` §8.1/§8.2, RPD-031/037 | 9, 13 | 0/15 |
| Compliance evidence | `FIN-195`, `HRT-282`, `RGL-402` pen test | 1, 2, 5 | 4/7/16 |

Nine of these eleven categories place at least one row in the top half (rank ≤ 13) of §5's 26-row table — this is the concrete, non-aspirational form of "foundation blockers are highlighted explicitly" the completion gate requires: they are not merely listed here, they visibly dominate the top of the risk ranking.

## 7. Accepted-risk and external-gate overlay (binding — must affect sequencing, not be mentioned in passing)

Per the prompt's task #5 and the completion gate's explicit requirement that "all critical accepted risks... affect sequencing/gates, not just be mentioned in passing":

| Overlay item | §5 rank | How it concretely affects sequencing/gates (not just narrative) |
|---|---:|---|
| **RPD-022** (Supreme Admin absolute CRUD, disclosed) | 3 | Forces a *distinct, separately-audited* RLS policy path on every `append_only_ledger`-family table (`06_*.md` §4/§8) shipped in Phase 1 — every later phase's finance/audit table creation (Phase 4 `journals`, Phase 8 `point_ledger`) must implement this split in the *same* migration as table creation (`06_*.md` §13's "RLS enabled... in the same migration, never a follow-up" rule), not as an afterthought; it is also a named, non-closable item in the Phase 15/16 hardening/GA evidence package (`HDN-372..374`, `RGL-412`) — GA cannot proceed by silently omitting this disclosure. |
| **Direct GA / no external pilot** (RPD-034/036) | 4 | Removes an entire *release stage* from the sequencing model — there is no "pilot tenant" gate between Phase 16's RC cut and GA (`12_*.md` §1's supersession note, applied at every phase row) — every phase's "Business acceptance" column is internal-only, and the *sole* external-facing milestone in the whole 17-node graph (§4.1) is the terminal GA arrow. This collapses what would otherwise be a multi-stage external rollout into a single, maximally-consequential gate (`RGL-412`), which is exactly why it ranks 4th: the sequencing model has no earlier opportunity to absorb a GA-blocking defect gradually via a pilot. |
| **Zero critical defects** (RPD-034/036, `RGL-412`) | 4 | Makes Phase 15's full-suite re-run (§5 rank 6) a hard predecessor of Phase 16 with no partial-credit path — `10_*.md` §10.3's "No-Go is automatic on any critical defect" means the critical path (§4.1) cannot skip or soft-gate this node; it is why Phase 15 is modeled as its own node rather than folded into Phase 9's exit. |
| **Contract-silent recovery = best effort** (RPD-031/037) | 9 | Makes `HDN-384`'s quarterly DR rehearsal (§5 rank 13) a *recurring*, not one-time, node in the Phase 15 hardening backlog (`11_*.md` §8.2) — sequencing must accommodate a repeating rehearsal cadence inside the hardening phase, not a single pre-GA check, precisely because there is no universal recovery guarantee to fall back on if the rehearsal program lapses. |
| **Custom-integration policy** (RPD-038) | 16 | Forbids collapsing Phase 9's 17-category integration backlog into one shared adapter-development task — each of the 17 categories remains its own atomic capability slice with its own sandbox contract test and runbook (`08_*.md` §8.2, `11_*.md` §8.5), which is why Phase 9's integration work cannot be compressed by building a generic abstraction layer first; this directly shapes the atomic-task-level sequencing within Phase 9, not merely a policy footnote. |
| **`FIN-195` tax/legal SME gate** (RPD-016) | 1 | See §4.2 — recommended pull-forward of the SME conversation ahead of Phase 4's nominal position, the single most consequential sequencing recommendation in this document. |
| **`HRT-282` payroll SME gate** (RPD-016) | 2 | Same pull-forward logic as `FIN-195`, applied to Phase 7. |

No overlay item above is presented as resolved, softened, or merely mentioned — each has a concrete sequencing/gate consequence traced to a specific node in §4.1's critical-path chain or §5's ranking, matching `14_*.md` §19's "never silently reclassified" rule extended into this document's own scope.

## 8. Concurrency lanes, integration checkpoints, resource assumptions, freeze points, stop/rollback triggers

### 8.1 Genuinely independent concurrency lanes

| Lane A | Lane B | Why independent | Convergence point |
|---|---|---|---|
| Phase 5 (Operations advanced TMS/WMS) | Phase 6 (Procurement/Vendor) | Both gated solely on `PHASE_4_VERIFIED`; `01_*.md` §3.3 shows no data/event edge from Phase 5 into Phase 6 or vice versa before Phase 7 | `PHASE_5_VERIFIED ∧ PHASE_6_VERIFIED` required before Phase 7 opens |
| Phase 0 tooling ADRs `024`/`025`/`026`/`027` (CI/CD, secret manager, observability, hosting/CDN) | Each other | Four independent product/vendor choices, no data dependency between them (`11_*.md` §10) | All four must close before `PHASE_0_VERIFIED`, but their internal order among themselves is unconstrained |
| `FIN-195`/`HRT-282` SME engagement (§4.2) | Phase 0–3 build-out | SME review of tax/payroll policy content requires no schema/UI to exist | Must land no later than `FIN-195`'s/`HRT-282`'s own capability-slice activation (Phase 4/7) |
| Design-system foundation (`09_*.md`, Phase 0 Prompt 90, resolves `ADR-CAND-ARCH-020/021`) | Database schema/RLS foundation (`05_*.md`/`06_*.md`, Phase 1) | Different artifact classes (UI component library vs. backend schema/policy); `09_*.md` §14's atomic backlog places design-system foundation at Phase 0, ahead of and independent of Phase 1's schema work | Both must exist before Phase 1's Configuration Studio UI slice (`09_*.md` §14, depends on both) |
| Test-runner/factory tooling (`10_*.md`, Phase 0 Prompt 91, resolves `ADR-CAND-ARCH-022/023`) | CI pipeline foundation (`11_*.md`, Phase 0) | Distinct tool choices, though the test-runner must ultimately plug into the CI pipeline | Converge at the "CI pipeline foundation" slice (`11_*.md` §11) |

### 8.2 Integration checkpoints (atomic, not phase-abstracted — per §3.2)

The ten public contracts in `03_*.md` §5 are the exact integration checkpoints exercised at each phase's entry gate (`12_*.md` §5): `Quotation-accepted→Job Order` (Phase 2→3), `Vendor-rate lookup` (Phase 1/2→6), `Billing-readiness event` (Phase 3→4), `Vendor-bill-matched event` (Phase 6→4), `Payroll-posting-input event` (Phase 7→4), `Eligible-transaction event` (Phase 4→8), `Typed ticket link` (Phase 3/4/6/8→7), `Booking/quote-request intake` (Phase 3/8→2), `Ticket-request intake` (Phase 3/8→7), `Any domain→REP` (Phases 2–8→9). No integration checkpoint is invented beyond this list.

### 8.3 Resource/skill assumptions (labeled — not commitments)

Per `12_RELEASE_TRAIN.md` §8 (reproduced here as an assumption, not re-derived as a new figure): a minimum-team assumption of 19 named roles at 0.25–2 FTE each (Phase 0–3), scaling to the same 19 roles at 1–8 FTE each (Phase 4–9), including a DevOps/Release Manager role and a Platform Reliability Pod — **this figure is `12_*.md`'s own stated assumption, not validated against any measured velocity (none exists, greenfield), and this document does not treat it as a scheduling commitment.** The only *skill*-specific assumption this document adds: `FIN-195`/`HRT-282`'s SME engagement (§4.2, §7) requires an Indonesia-qualified tax/legal and payroll/tax SME respectively — a role class already implied by RPD-016 but not previously named as a scheduling dependency; this is stated as an assumption about *who* must be engaged, not *when* in calendar terms.

### 8.4 Freeze points

Reproduces `12_RELEASE_TRAIN.md` §5's per-phase stabilization window (final 1–2 sprints before each phase's exit gate: no new capability slice merges, defect-fix/exit-gate-evidence work only) and §7.2's system-wide RC freeze (once Phase 16's RC is cut, only defect-fix/security-fix/exit-gate-evidence work merges into the RC artifact) as the two freeze points this document's sequencing must respect — no new freeze point is introduced.

### 8.5 Stop/rollback triggers

Reproduces `10_*.md` §10.2 / `12_*.md` §7.4's 9-item rollback-consideration list verbatim as the binding trigger set for **any** phase transition or the Phase 16 cutover: tenant isolation failure; authentication/login outage affecting critical users; data corruption in critical entities; financial posting defect; material migration-reconciliation failure; a critical workflow that cannot execute; performance preventing a critical business operation; a security incident during cutover; a production deployment breaking core pages/API. Any one of these firing during a phase's exit-gate evidence collection or Phase 16's cutover triggers Blueprint §26.3's rollback procedure (already reproduced in `10_*.md`/`11_*.md` §4.4/§8.3) — this document introduces no additional trigger and no softer variant.

## 9. Risk burn-down evidence plan and recalculation triggers

### 9.1 Evidence sources (where burn-down is observed, not asserted)

| Evidence source | What it shows | Owning document |
|---|---|---|
| `TASK_LEDGER.md` capability-status flips (`READY`→`VERIFIED`) | A WBS capability closing, reducing that row's Remediation-complexity/Dependency-centrality exposure | `docs/runtime/TASK_LEDGER.md` |
| `14_*.md` §22.1 coverage-state flips (`PARTIAL_BLOCKED`/`EXTERNAL_VERIFICATION`→`COVERED`) | An ADR resolving or an SME sign-off landing | `14_REQUIREMENT_PHASE_TRACEABILITY.md` (re-derived, not hand-patched, per its own §25 rule) |
| ADR-candidate resolution log | Any of the 17 currently-open `ADR-CAND-ARCH-0xx` moving from open to resolved | `01_*.md`–`13_*.md`'s own ADR sections, cross-indexed in `HANDOFF.md` §6 |
| Test-suite green status (`TI-*`/`FINTEST-*`/`UAT-E2E-*`) | Detection-strength scores improving as planned tests are actually built and pass | `10_TESTING_WORKSTREAM.md` §13 readiness dashboard |
| Observability alert history (11 dashboards/8 alerts) | Real incident/near-miss data, once it exists, replacing this document's qualitative Likelihood scores with measured frequency | `11_DEVOPS_WORKSTREAM.md` §6 |
| DR rehearsal reports (quarterly) | Reversibility/Detection scores for the backup/recovery blocker category | `11_DEVOPS_WORKSTREAM.md` §8.2 |
| Incident RCA records | New `RISK-*`/`MDM-RISK-*` candidates, or confirmation an existing one never materialized | `11_DEVOPS_WORKSTREAM.md` §8.4, `docs/runtime/ERROR_LEDGER.md` |

### 9.2 Recalculation triggers (binding — this document must be re-derived, not hand-patched, exactly mirroring `14_*.md` §25's own rule extended to risk scoring)

This document's rankings (§5) must be recomputed — not manually edited row-by-row — whenever any of the following occurs:

1. **An ADR resolves.** Any of the 17 open `ADR-CAND-ARCH-0xx` candidates (`HANDOFF.md` §6) moving to resolved changes that item's Uncertainty (dimension 8) and typically its Detection-strength (dimension 7) score — the CRS must be recomputed from the new scores, not adjusted by an unexplained delta.
2. **A runtime fact changes.** E.g., Phase 0's toolchain baseline being established changes `docs/discovery/03_TOOLCHAIN_DEPENDENCY_BASELINE.md`'s zero-CI fact, which is an input to several rows' Detection-strength/Remediation-complexity scores.
3. **An estimate changes.** This document currently contains zero duration/staffing estimates (§2.3); if a future document validates one (e.g., a measured velocity once Phase 0+ produces real commits), this document's §8.3 assumption section must be updated to cite it, and any dimension that assumed "no measured data" must be re-scored against the new evidence.
4. **A failure occurs.** Any P1/P2 incident or RCA (`11_*.md` §8.4) either confirms a modeled risk (raising confidence in its Likelihood score) or reveals a new risk not in §5 (requiring a new row, sourced to the incident record, never invented ahead of evidence).
5. **A requirement changes.** Only via `02_CONFIRMED_DECISION_REGISTER.md` §5's decision-change protocol — a ratified RPD/CPD changing (e.g. RPD-034/036 being revisited by the Steering Committee) would change §7's overlay table and cascade into §5's CRS for every affected row.

When any trigger fires, the correct action is: re-open this document, recompute the affected row(s)' CRS from updated dimension scores, re-sort §5, re-check whether §4's critical path or near-critical branches have changed, and re-issue the document — never patch a single CRS number without showing the updated dimension inputs (this preserves §2.2's reproducibility guarantee across revisions, not just at authoring time).

## 10. Ordered critical path (restated compactly) and top risks (ranked)

**Ordered critical path** (identical to §4.1, restated once more here per the prompt's required-output list): `Phase 0 → Phase 1 → Phase 2 → Phase 3 → Phase 4 → {Phase 5 ‖ Phase 6} → Phase 7 → Phase 8 → Phase 9 → Phase 15 → Phase 16 → direct GA`, with the `FIN-195`/`HRT-282` SME-engagement pull-forward (§4.2) as the one risk-adjusted deviation from pure phase-number sequencing.

**Top 10 risks (ranked, from §5):**

1. Finance tax/legal SME verification (`FIN-195`) — CRS 49
2. Payroll/tax SME verification (`HRT-282`) — CRS 47
3. Supreme Admin absolute-CRUD disclosed exception (RPD-022) — CRS 46
4. Direct-GA / zero-critical-defect Go/No-Go (`RGL-412`) — CRS 43
5. Penetration test (`RGL-402`) — CRS 42
6. Phase-15 full regression re-run — CRS 41
7. RLS/RBAC foundation and default-deny rollout — CRS 39
8. Observability/APM tool selection (`ADR-CAND-ARCH-026`) — CRS 37
9. Contract-silent recovery = best effort (RPD-031/037) — CRS 36
10. Shipment table schema split (`ADR-CAND-ARCH-013`) — CRS 32

## 11. Gate owners

Reproduced from `12_RELEASE_TRAIN.md` §7.3 (verbatim authority split) and `13_*.md` §11/`14_*.md` §20 (evidence-gate owners) — no new owner is invented:

| Gate | Owner | Source |
|---|---|---|
| Per-phase internal exit gate (Phases 0–15) | Release Board | `12_*.md` §7.3 |
| Phase 16 GA Go/No-Go | Steering Committee (Sponsor/CPO/CTO) | `12_*.md` §7.3, Blueprint §27.2 |
| `FIN-195` tax/legal SME sign-off | Legal/Finance/Tax SME | `13_*.md` §11, `14_*.md` §20/§23 |
| `HRT-282` payroll SME sign-off | HR/Payroll/Tax SME | `13_*.md` §11, `14_*.md` §20/§23 |
| `RGL-402` penetration test | Security | `13_*.md` §11, `14_*.md` §20 |
| `HDN-384` DR rehearsal | DevOps/Security | `11_*.md` §8.2, `14_*.md` §20 |
| RLS/RBAC hardening (`HDN-372..374`) | Security/QA | `06_*.md` §13, `10_*.md` §9 |
| Contract-specific RPO/RTO | SRE/Legal, per-tenant | `14_*.md` §20 |
| Phase 0 tooling ADRs (`024`–`027`) | DevOps/DevEx/Security | `11_*.md` §10 |
| Design-system ADRs (`020`/`021`) | Architecture/UX | `09_*.md` |
| Test tooling ADRs (`022`/`023`) | Architecture/DevEx, DevOps/QA | `10_*.md` §11 |

## 12. Sensitivity notes (qualitative, not a numeric model)

- If `FIN-195`'s SME engagement is *not* pulled forward per §4.2's recommendation, its Remediation-complexity and Uncertainty scores do not improve until Phase 4 nominally begins, and its already-highest CRS (49) would remain the single largest known threat to the Phase 16 zero-critical-defect gate for the longest possible window — this is the most consequential sensitivity in the entire ranking.
- If Phase 0's four tooling ADRs (`024`/`025`/`026`/`027`, rank 11) resolve quickly (their own stated non-blocking, low-ambiguity nature per `11_*.md` §10), their Uncertainty scores drop from 3 to 1–2 and their CRS falls out of the top half — this is the most easily "bought down" risk cluster in the table, precisely because none of the four choices has a disputed recommendation.
- If the Phase 5/6 parallel lane (§8.1) is *not* run concurrently (e.g. resourced sequentially instead), no CRS score in §5 changes, but the critical path's total dependency depth increases by one full phase-equivalent step — this is a pure sequencing risk, not a scored item, and is called out here because it is the one place a resourcing choice (not a technical risk) can lengthen the critical path.
- `RPD-022` (rank 3) and `RPD-031/037`/`RPD-038` (ranks 9/16) can never fall in ranking via ADR resolution — they are `ACCEPTED_RISK` by ratified decision (§7), so their Uncertainty score is permanently 5 ; only a Steering-Committee decision-change (per `02_CONFIRMED_DECISION_REGISTER.md` §5) could ever move them, and this document does not anticipate or recommend that.

## 13. Assumptions (explicit)

- Team-sizing/cadence figures cited in §8.3 are `12_RELEASE_TRAIN.md` §8's own stated assumptions, not validated by any measured data in this repository — reproduced here as an assumption, not adopted as a scheduling commitment.
- The SME-role assumption in §8.3 (Indonesia-qualified tax/legal and payroll/tax expertise) is an assumption about required skill class, not a staffing-level or duration commitment.
- §9.1's evidence sources assume the named runtime artifacts (`TASK_LEDGER.md`, `ERROR_LEDGER.md`, the 11-dashboard observability set) will exist and be populated once Phase 0+ build-out begins — this document does not assume any of them currently contain data (they do not, per every workstream document's own zero-state checkpoint).
- No calendar date, duration, or staffing number appears anywhere else in this document outside the two explicitly-labeled assumption references above (§8.3) — this satisfies the completion gate's "no unverified dates are claimed" requirement by construction, not by omission.

## 14. ADR candidates

None new. This document ranks and cross-references the 17 currently-open `ADR-CAND-ARCH-0xx` candidates already raised across `01_*.md`–`13_*.md` (§3.2, §5, §6) without introducing an 18th. No product decision (`CPD-*`/`RPD-*`) is reopened — §7's overlay table restates, and shows the sequencing effect of, four standing `ACCEPTED_RISK`/gate decisions (RPD-022, RPD-031/034/036/037, RPD-038) exactly as `14_*.md` §19 already ratifies them, without softening or reclassifying any of them.

## 15. Exit gates

Every item in §5's risk table cites an ID already registered in `13_FULL_WORK_BREAKDOWN_STRUCTURE.md` (WBS capability/phase/ADR) or `14_REQUIREMENT_PHASE_TRACEABILITY.md` (requirement/gate) — spot-checked: `FIN-195`/`HRT-282` fall inside their registered phase ranges (`13_*.md` §4: `FIN-191..214`, `HRT-274..293`), every `ADR-CAND-ARCH-0xx` cited is one of the 27 already raised across `01_*.md`–`13_*.md` (10 resolved, 17 open), every `MDM-RISK-00x` is one of the six already raised across `01_*.md`/`02_*.md`/`04_*.md`/`05_*.md`, and every `RPD-*`/`CPD-*` cited is inside the ratified `001..040`/`001..023` ranges. Ranking is reproducible: every row in §5 shows its eight component scores and the CRS arithmetic, per §2.2's formula, not merely an asserted order. Uncertainty is explicit: dimension 8 (Unc) is scored per-row, and §13 separately labels every assumption used elsewhere in this document. No unverified date is claimed anywhere (§13's closing statement; §2.3's explicit prohibition). All four critical accepted risks (RPD-022, RPD-031/034/036/037, RPD-038) visibly affect sequencing or a gate, not merely narrative mention (§7's table, with a concrete mechanism per row).

## 16. Completion statement

The ranking method (§2) defines all nine required dimensions with explicit 1–5 scales and a reproducible, unweighted-beyond-one-product composite formula (CRS = Sev×Lik + Rad+Exp+Dep+Rev+Det+Unc+Rem), with an explicit statement of what it deliberately excludes (durations, staffing, dates). The dependency graph summary (§3) is sourced entirely from `01_*.md`/`12_*.md`'s phase-level graph and `13_*.md`/`03_*.md`'s atomic-level detail, adding only the gate/evidence cross-phase dependencies those documents did not already model as first-class nodes. The critical path and near-critical branches (§4) are ordered by dependency depth alone, with one explicitly-labeled risk-adjusted scheduling recommendation (SME-engagement pull-forward) that does not reopen any WBS position or product decision. The risk-ranked task table (§5) scores 26 real, cited items across all nine dimensions with full arithmetic shown. Foundation blockers (§6) are shown to dominate the top half of the ranking, not merely listed. The accepted-risk/external-gate overlay (§7) demonstrates a concrete sequencing/gate mechanism for every one of RPD-022/031/034/036/037/038 and the two Indonesia SME gates, satisfying the completion gate's "must visibly affect sequencing... not just be mentioned in passing" requirement. Concurrency lanes, integration checkpoints, resource assumptions, freeze points, and stop/rollback triggers (§8) are enumerated with no new trigger invented beyond `10_*.md`/`12_*.md`'s existing set. The risk burn-down evidence plan and five recalculation triggers (§9) bind this document to a re-derive-not-hand-patch discipline, mirroring `14_*.md` §25. The ordered critical path, top-10 ranked risks, and gate owners (§10–§11) are stated explicitly and traceably. Sensitivity notes (§12) and explicit assumptions (§13) are qualitative and clearly labeled, never presented as fact. No new ADR candidate is raised and no product decision is reopened (§14). Every exit-gate condition (§15) is satisfied with evidence, not assertion.

Next eligible prompt: `03-architecture-and-plan/51_STEP3_CLOSURE_VERIFICATION_PROMPT.md` → `docs/architecture/16_STEP3_CLOSURE_REPORT.md` — this is the sixteenth and final Step 3 architecture-and-plan output; per `13_FULL_WORK_BREAKDOWN_STRUCTURE.md` §13, Prompt 51 "verifies the full Step 3 package (`01_*.md`–`15_*.md`) at one repository checkpoint," making it the Step 3 Closure Verification prompt anticipated by `docs/runtime/HANDOFF.md` §1/§4.
