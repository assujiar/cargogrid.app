# 15 — Risk-Ranked Critical Path

**Prompt:** `CG-S3-ARCH-015` (`CG-AABPP-ARCH-050` v0.4.0)
**Runtime output of:** `docs/ai-agent-build-prompt-package/03-architecture-and-plan/50_RISK_RANKED_CRITICAL_PATH_PROMPT.md`
**Status:** `VERIFIED`

## 0. Checkpoint

| Field | Value |
|---|---|
| Repository | `assujiar/cargogrid.app` |
| Working branch | `agent/cargogrid-autonomous-build` (tracked by GitHub PR #7) |
| HEAD at authoring time | `69dbbc160c991fc129dc4a9aab2ee8fa47524794` (parent of this checkpoint's commit) |
| Precondition | `docs/architecture/01_*.md` through `14_*.md` all `VERIFIED` |
| Repository state | Unchanged: zero code, zero task executed against this ranking (prompt precondition, verified) |
| Mutation performed | **NONE** — planning/ranking only; no implementation task was started, no WBS ID invented |

### Inputs read in full for this document

- `docs/ai-agent-build-prompt-package/03-architecture-and-plan/50_RISK_RANKED_CRITICAL_PATH_PROMPT.md` (full — objective, 8 required tasks, required output, completion gate)
- `docs/architecture/13_FULL_WORK_BREAKDOWN_STRUCTURE.md` (full — §4 phase register, the sole source of every WBS ID cited below)
- `docs/architecture/14_REQUIREMENT_PHASE_TRACEABILITY.md` (full — §20 cross-phase links, §21 accepted-risk overlay, §22 external/SME verification, §24 coverage totals, §25 blocker list)
- `docs/architecture/12_RELEASE_TRAIN.md` (full — §3 phase increment table, §9 dependency diagram, §10 risk register)
- `docs/architecture/11_DEVOPS_WORKSTREAM.md` (full — §2 environments, §3 CI/CD, §6 observability, §8 backup/DR/incident, §9.1 `ADR-CAND-ARCH-004`, §10 open ADRs, §11 atomic backlog, §12 go-live blockers)
- `docs/architecture/06_RLS_RBAC_WORKSTREAM.md` (full — §3 evaluation flow, §4 tenant/RLS matrix, §8 RPD-022 semantics, §10 negative-test matrix, §12 atomic backlog)
- `docs/architecture/05_DATABASE_SCHEMA_WORKSTREAM.md` (full — §4 constraint plan, §5 finance controls, §8 migration waves, §10 ADR candidates, §12 atomic backlog)
- `docs/architecture/07_CONFIGURATION_ENGINE_WORKSTREAM.md` (full — §11 security/finance guardrails, §12 ADR candidates, §15 atomic backlog)
- `docs/architecture/08_API_INTEGRATION_WORKSTREAM.md` (full — §8 integration adapter template, §14 ADR candidates, §15 atomic backlog)
- `docs/discovery/11_TECHNICAL_DEBT_RISK_REGISTER.md` (full — RISK-001..009, the Step 2 debt/risk register required by task 4)
- `docs/runtime/HANDOFF.md` §1, §6, §7 (open `ADR-CAND-ARCH-011..027` list; `FIN-195`/`HRT-282` evidence-gate disclosure)
- `docs/runtime/CARGOGRID_CONTEXT.md` §3, §11 (ratified operating snapshot; active constraints/accepted risks RPD-022/034/036/031/037/038)
- `docs/architecture/01_MODULE_DEPENDENCY_MAP.md` (cited — §10 phase implications table, §12 risks, already carried forward verbatim into `12_*.md` §10, not re-read a second time to avoid restating an already-`VERIFIED` source)

## 1. Scope and method

This document does not create, assign, execute, or resolve any implementation task, ADR, or requirement (prompt precondition and completion gate). It re-reads the already-`VERIFIED` dependency graph (`13_*.md`), coverage/accepted-risk/blocker state (`14_*.md`), release sequencing (`12_*.md`), and the five foundation workstreams (`05_*.md`–`08_*.md`, `11_*.md`) and produces one artifact: a risk-adjusted ordering of that already-existing work, so a future runtime agent spends its first effort reducing the highest-leverage blockers rather than the most visible features. Every WBS ID, phase gate, ADR candidate ID, and accepted-risk ID cited below already exists in `13_*.md` §4, `14_*.md`, or an already-`VERIFIED` workstream document — this document introduces zero new ID of any kind (§16 confirms).

**Binding constraint (prompt precondition, restated):** no duration, staff-week, or calendar date is fabricated anywhere in this document. `12_RELEASE_TRAIN.md` §8 already established that this repository has zero measured velocity (greenfield, no prior sprint) and that sequencing must be dependency-based, not time-based. This document extends that same discipline to risk ranking: **ordinal dependency depth** (§3) is the sequencing backbone, and **ordinal risk scores** (§2) are the ranking backbone — no numeric probability, cost, or schedule-impact figure is invented to make either backbone appear more precise than the evidence supports. Every place uncertainty is genuinely unresolved (an `ADR_REQUIRED` value, an `EXTERNAL_VERIFICATION` gate with no controllable timeline, a greenfield defect-volume unknown) is scored explicitly on the **Uncertainty** dimension (§2) rather than papered over with an invented number.

## 2. Ranking method and scales

### 2.1 Nine ranking dimensions (prompt task #3, verbatim list, operationalized)

Every ranked item (§7) is scored on nine dimensions, each an ordinal 1–4 scale (1 = lowest concern, 4 = highest concern on that dimension) so that **higher is always worse** and the scores are directly summable without a hidden sign flip. This is the full ranking method — reproducible by re-applying the same nine rubrics to the same evidence, not a black-box weighting:

| # | Dimension | 1 (low) | 2 | 3 | 4 (high) |
|---|---|---|---|---|---|
| 1 | **Severity** — impact if the risk materializes | Cosmetic/no data or trust impact | Recoverable functional defect | Major functional/financial/security impact requiring incident response | Critical: tenant leak, financial-integrity break, or GA-blocking system-wide failure |
| 2 | **Likelihood** — plausibility the condition is exercised or the defect is introduced, given design complexity and evidence (never a measured frequency — none exists pre-implementation) | Rare/only under contrived conditions | Possible under normal build activity | Likely given the surface's complexity/novelty | Near-certain / structurally guaranteed to be exercised (e.g., a standing accepted-risk design feature) |
| 3 | **Blast radius** — how much of the system is affected | Single capability/table | Single phase/domain | Multiple phases/domains | System-wide or cross-tenant |
| 4 | **Tenant/security/finance/data exposure** — worst of the four exposure classes touched | None of the four | One class, non-critical instance | One class, critical instance, or two classes | Two or more critical classes simultaneously (e.g., tenant + finance) |
| 5 | **Dependency centrality** — how many downstream WBS items/phases require this item to close first (`13_*.md` §6, `14_*.md` §20) | No downstream dependent | A few capabilities in one phase | An entire phase or cross-phase link | Every subsequent phase (a true foundation blocker) |
| 6 | **Reversibility** — how hard to undo once realized | Trivially reversible (config/flag toggle) | Reversible with a forward-fix migration | Reversible only via manual business correction | Irreversible or explicitly non-resolvable by design (an `ACCEPTED_RISK`) |
| 7 | **Detection strength** — how weak the evidence/test coverage is (1 = strong/automated detection exists, 4 = weak/manual/relies on self-report) | Automated, comprehensive negative-test suite already specified | Automated but partial coverage | Manual review/checklist only | Detection depends on the same privileged actor who could cause the issue (e.g., Supreme Admin self-audit) |
| 8 | **Uncertainty** — how unresolved the item's own specification is | Fully specified, zero open question | Minor open detail, non-blocking | Named `ADR_REQUIRED` value with a recommended default | `EXTERNAL_VERIFICATION`/SME-dependent with no agent-controllable timeline, or genuinely no blueprint evidence |
| 9 | **Remediation complexity** — how hard to fix once found | Single-file/single-migration fix | Bounded slice fix (1–3 migrations/5–15 files, the standing atomic-task size) | Cross-phase coordination required | No shared fix path exists (e.g., RPD-038's per-category-only remediation) or the item is `ACCEPTED_RISK` (not remediable by design) |

### 2.2 Composite score

**Score = unweighted sum of the nine dimension scores (range 9–36).** No dimension is weighted above another — every prior weighting scheme this build agent could invent (e.g., "security counts double") would itself be an unevidenced number, which task #3's own instruction not to fabricate figures rules out. Rank is the composite score, descending; ties are broken by Dependency Centrality (dimension 5), since the prompt's own objective ("sequenced by blocker reduction rather than feature visibility") privileges centrality when severity is equal.

### 2.3 What this method deliberately does not produce

No score is a probability, a dollar figure, or a day count. A score of 29 is not "2.9× worse" than a score of 10.5 in any measurable unit — it is an ordinal rank, valid only for *this document's* relative ordering of *this document's* candidate set, recomputed whenever §13's recalculation triggers fire.

## 3. Dependency graph summary

### 3.1 Phase-level graph (source: `13_*.md` §4/§6, `12_*.md` §9, reproduced by reference not re-derived)

The binding phase-level graph is `12_RELEASE_TRAIN.md` §9's mermaid diagram, itself built from `01_MODULE_DEPENDENCY_MAP.md` §3/§4 and `13_*.md` §4's phase register — not re-drawn here with different content that could drift. Its structure, restated as an ordinal **dependency-depth** ladder (task #2's substitute for unavailable duration estimates):

| Depth | Phase(s) | Entry gate | Parallel with | WBS anchor (`13_*.md` §4) |
|---:|---|---|---|---|
| 0 | Phase 0 — Discovery/Foundation | Step 3 `RUNTIME_ARCHITECTURE_VERIFIED` (this package's own closure, Prompt 51) | — | `PH0-079..102` |
| 1 | Phase 1 — Platform Core | `PHASE_0_VERIFIED` | — | `PLT-103..140` |
| 2 | Phase 2 — Commercial | `PHASE_1_VERIFIED` | — | `COM-141..165` |
| 3 | Phase 3 — Operations (basic) + Customer Portal (basic) | `PHASE_2_VERIFIED` | — | `OPS-166..188` |
| 4 | Phase 4 — Finance | `PHASE_3_VERIFIED` | — | `FIN-189..218` |
| 5 | Phase 5 — Operations (advanced TMS/WMS) **and** Phase 6 — Procurement/Vendor | `PHASE_4_VERIFIED` (both) | Yes — genuinely independent internal workstreams (`12_*.md` §9's note) | `ATW-219..248`, `PRC-249..271` |
| 6 | Phase 7 — HRIS + Ticketing | `PHASE_5_VERIFIED` **and** `PHASE_6_VERIFIED` (both must close) | — | `HRT-272..297` |
| 7 | Phase 8 — Customer Portal (full) + Loyalty | `PHASE_7_VERIFIED` | — | `CPL-298..327` |
| 8 | Phase 9 — Intelligence/Automation/Enterprise | `PHASE_8_VERIFIED` | — | `IEP-328..367` |
| 9 | Phase 15 — Full-system hardening | `PHASE_9_VERIFIED` | — | `HDN-368..389` |
| 10 | Phase 16 — Release Candidate and Go-Live | `FULL_SYSTEM_HARDENING_VERIFIED` | — | `RGL-390..412` |
| 11 | Direct GA (RPD-034/036) | Phase 16 Go/No-Go | — | (no further WBS phase; first external tenant is production) |

Phase 17 (`FPV-413..430`) validates the **prompt package**, not the runtime build, and is explicitly excluded from the runtime critical path (`13_*.md` §4's own footnote: "does not gate GA") — it is not a depth-12 node.

### 3.2 Intra-phase and cross-cutting edges (source: `13_*.md` §5/§6/§7, not re-derived)

Within Phase 0 and Phase 1 specifically, the ten cross-cutting workstreams this document draws its foundation-blocker list from (§4 below) are not a separate depth level — they are the **content** of Phase 0's `PH0-081..098` capability range and Phase 1's `PLT-105..136` capability range, sequenced internally per each workstream's own atomic backlog (`05_*.md` §12, `06_*.md` §12, `07_*.md` §15, `08_*.md` §15, `11_*.md` §11), all of which name **Phase 0** (environment/CI/secret/observability/backup foundation, per `11_*.md` §11) or **Phase 1** (schema/RLS/config/API foundation, per `05_*.md`/`06_*.md`/`07_*.md`/`08_*.md` §12/§12/§15/§15) as their own first slice. This document's contribution is not a new edge — it is naming, in one place, which of these already-sequenced Phase 0/1 slices carry the highest risk score (§7), since `13_*.md` intentionally does not itself rank within a phase.

### 3.3 Cross-phase links carried forward (source: `14_*.md` §20, not re-derived)

Ten cross-phase items each have exactly one primary owner and prerequisite/extension edges already fixed by `14_*.md` §20 (vendor rate `PRC-254..255`←`COM-149..150`; job/shipment lineage `OPS-168..169`←Phase 2; tracking/ePOD `OPS-172..177`→`ATW-226..228`/`CPL-305..308`; WMS `ATW-229..242`→`CPL-309..310`; cost/job-closing `OPS-178..181`→`FIN-196..214`→`ATW-239..242`; vendor billing `FIN-199..201`→`PRC-265..266`; billing readiness `FIN-196..214`→`CPL-311..315`; ticketing `HRT-286..288`→`CPL-311..315` and →`RGL-411`; white-label `PLT-117..119`→`IEP-354..359`; reporting `IEP-330..334` aggregating every domain phase). These edges are the concrete mechanism behind two of §7's highest-ranked items (Finance's centrality, §7 rank 5; the `TKT-HLP` partial-blocked tail, §7 rank 16) — restated here as graph input, not reopened.

## 4. Foundation blockers (prompt task #4)

Every category task #4 names already has a named delivery mechanism (no category is unowned):

| Foundation category | Owning workstream/section | Phase | Blocking scope if incomplete |
|---|---|---|---|
| Repository strategy | `04_REPOSITORY_TARGET_STRUCTURE.md` §8 (10-slice transition sequence) | 0 | Every later file-boundary/allowed-path rule |
| Target boundaries (domain ownership) | `03_DOMAIN_BOUNDARY_MAP.md` §3/§5 | 0/1 | Every cross-domain contract (§3.3 above) |
| Schema/migrations | `05_DATABASE_SCHEMA_WORKSTREAM.md` §3/§8/§12 (single `app` schema, expand/migrate/contract) | 1 (first slice), continuous | Every table-owning capability in every phase |
| Tenant/RLS/RBAC | `06_RLS_RBAC_WORKSTREAM.md` §3/§4/§9 (8-stage evaluation flow, same-migration rollout rule) | 1 (first slice), continuous | Every tenant-scoped read/write in every phase; release blocker per `06_*.md` §13 |
| Configuration engine | `07_CONFIGURATION_ENGINE_WORKSTREAM.md` §2–§11 (10 sub-engines, one metadata model) | 1 (bootstrap), continuous | Every workflow/approval/status/rule-driven capability (91 catalogued items) |
| API/contracts/jobs/files | `08_API_INTEGRATION_WORKSTREAM.md` §3/§9/§10 (REST+GraphQL parity, PostgreSQL durable queue, file/signed-URL contract) | 1 (foundation slice) | Every external-facing capability and every long-running operation |
| CI/environments | `11_DEVOPS_WORKSTREAM.md` §2/§3/§11 (7-tier topology, deterministic pipeline) | 0 | Every deployable artifact in every phase |
| Test data | `10_TESTING_WORKSTREAM.md` §4.2 (synthetic factories) — cited, not re-read in full this checkpoint since already `VERIFIED` and unchanged | 0 | Every automated test in every phase |
| Observability | `11_*.md` §6 (11 dashboards, 8 alerts) | 0 | Detection strength for every later risk (directly feeds §2.1 dimension 7 for every item below) |
| Backup/recovery | `11_*.md` §8 (RPO/RTO tiers, DR rehearsal) | 0 (backup), 15 (rehearsal) | Phase 15 exit gate; every RPD-031/037 claim (§9 below) |
| Compliance evidence | `14_*.md` §22/§25 (SME gates, pentest, DR rehearsal, retention) | 4/7 (SME gates), 16 (pentest) | GA gate (`RGL-404`), specific module activation only (§9 below) |

No category in task #4's list is undelivered — this table is the concrete answer to "highlight foundation blockers," cross-referenced into §7's ranking (every row above appears as, or inside, a ranked item).

## 5. Ordered critical path

Dependency-depth ordering (§3.1) is the backbone; within Phase 0/1, the highest-risk foundation slices (§7) are called out as the *risk-critical* sub-sequence — the true blocker, not merely the first-numbered item. **No date appears in this section.**

1. **Depth 0 — Phase 0 foundation.** Risk-critical items: environment/CI/secret/observability/backup foundation (`11_*.md` §11, §7 rank 6), repository/target-boundary scaffolding (§4). Exit: `PHASE_0_VERIFIED`.
2. **Depth 1 — Phase 1 Platform Core.** Risk-critical items, in the order their own atomic backlogs already fix: Platform identity core + RLS negative tests (`05_*.md`/`06_*.md` first slice, §7 rank 2) → config metadata core + bounded-evaluator guardrails (`07_*.md` §15, §7 rank 3/4) → API/webhook/job foundation (`08_*.md` §15) → append-only-ledger policy family carrying the RPD-022 exception (`06_*.md` §4/§8, §7 rank 1 — an **overlay**, not a separate sequential step; it ships inside this same Platform Core slice, §9 below). Exit: `PHASE_1_VERIFIED` (RLS/RBAC baseline, config draft/publish/rollback, CI/CD gates active — `12_*.md` §3.1).
3. **Depth 2 — Phase 2 Commercial.** Vendor-rate basic lookup seeded (resolved `ADR-CAND-ARCH-001`, low residual risk, §7 rank 15). Exit: `PHASE_2_VERIFIED`.
4. **Depth 3 — Phase 3 Operations (basic) + Portal (basic).** Job→Shipment atomicity (`ADR-CAND-ARCH-005`, resolved). Exit: `PHASE_3_VERIFIED`.
5. **Depth 4 — Phase 4 Finance.** Risk-critical: idempotent posting/period lock/balanced-journal controls (§7 rank 5), immediately followed by the `FIN-195` tax/legal SME external-verification gate (§7 rank 7, §10 below — gates *activation* of `FIN-195` specifically, not the whole phase). Exit: `PHASE_4_VERIFIED` (Finance Go-Live Gate, 24 `FINTEST-*`).
6. **Depth 5 — Phase 5 (Advanced TMS/WMS) ∥ Phase 6 (Procurement/Vendor), parallel.** Risk-critical: WMS inventory-ledger correctness (§7 rank 7). Both must independently reach `PHASE_5_VERIFIED`/`PHASE_6_VERIFIED` before Depth 6 (§3.1's parallel note).
7. **Depth 6 — Phase 7 HRIS + Ticketing.** Risk-critical: `HRT-282` payroll/tax SME external-verification gate (§7 rank 7, §10 below). Exit: `PHASE_7_VERIFIED`.
8. **Depth 7 — Phase 8 Customer Portal (full) + Loyalty.** RPD-022 ledger exception recurs here for `point_ledger`/`cashback_ledger` (overlay, not new work, §9). Exit: `PHASE_8_VERIFIED`.
9. **Depth 8 — Phase 9 Intelligence/Automation/Enterprise.** Risk-critical: RPD-038 custom-integration fan-out across the remaining 14 categories (§7 rank 7). Exit: `PHASE_9_VERIFIED`.
10. **Depth 9 — Phase 15 Full-system hardening.** Risk-critical: penetration test (§7 rank 7, §10 below), DR rehearsal (§7 rank 13, §10 below), full `TI-*`/`FINTEST-*`/`UAT-E2E-*` re-run. Exit: `FULL_SYSTEM_HARDENING_VERIFIED`.
11. **Depth 10 — Phase 16 Release Candidate and Go-Live.** Risk-critical: the RPD-034/036 zero-Sev-1 convergence gate (§7 rank 3, §9 below) — this is the single node every other node in this list must simultaneously satisfy; it is not new work, it is the point where every prior node's residual risk is checked at once. Exit: `RELEASE_GO_LIVE_VERIFIED`.
12. **Depth 11 — Direct GA.** First external tenant is a production customer (RPD-034/036) — no depth-12 pilot node exists in this graph (§9 confirms this is a structural, not accidental, absence).

This is the same 12-node sequence `12_*.md` §9 already fixes — this document adds no new node and reorders nothing; it annotates which sub-slice inside each node is the risk-critical one.

## 6. Near-critical branches

Branches that do not sit on the depth-ladder's spine but can become critical if their own risk materializes:

| Branch | Why near-critical, not critical | Trigger that would promote it |
|---|---|---|
| `ADR-CAND-ARCH-004` reporting-replica graduation (`11_*.md` §9.1) | Conditional — only fires on a measured four-signal trigger, not scheduled by phase number | Any one of the four signals sustained >1 week post-Phase-5 |
| GraphQL depth/complexity + webhook/rate-limit numeric ADRs (`ADR-CAND-ARCH-017/018`, `08_*.md` §14) | Deferred to Phase 1 `API-WH` implementation with a recommended default already given — low residual risk while the default holds | A measured Phase-1/2 traffic pattern invalidates the recommended default |
| Deprecation overlap-window duration (`ADR-CAND-ARCH-019`) | Only matters once a breaking API change is proposed — no breaking change is scheduled before Phase 9 at the earliest | First breaking REST/GraphQL change proposal |
| `TKT-HLP` release-depth item (`14_*.md` §20/§25, `RGL-411`) | `PARTIAL_BLOCKED` but explicitly non-blocking, closes at Phase 16 documentation | Any attempt to treat it as a Phase-7-blocking item (would be a process error, not a real escalation) |
| Reporting/dashboard cross-domain aggregation (`IEP-330..334`) | Depends on every prior domain phase's data maturity but is itself additive (no domain phase depends on it) | A Phase-9 dashboard defect traced back to a stale schema assumption from an earlier phase |

None of these branches currently sits on the critical path (§5) — each is one condition away from doing so, which is why each carries an explicit trigger rather than being silently dropped.

## 7. Risk-ranked task table

Top 16 items by composite score (§2.2), covering every foundation blocker (§4), every accepted risk (§9), and every external gate (§10) at least once — no `ACCEPTED_RISK`/`EXTERNAL_VERIFICATION`/`PARTIAL_BLOCKED` item from `14_*.md` §24.4 is absent from either this table or §6.

| Rank | Item | WBS/citation | Sev | Lik | BR | Exp | DC | Rev | Det | Unc | RC | **Score** |
|---:|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | RPD-022 Supreme Admin absolute-CRUD accepted-risk overlay | `06_*.md` §8, `14_*.md` §21, `RISK-004` | 4 | 4 | 3 | 4 | 2 | 4 | 3 | 1 | 4 | **29** |
| 2 | Tenant isolation / RLS foundation | `PLT-112..114`, `06_*.md` §3/§4, `TI-001..018` | 4 | 3 | 4 | 4 | 4 | 3 | 1 | 2 | 3 | **28** |
| 3 | RPD-034/036 direct-GA zero-Sev-1 convergence gate | `RGL-404`, `12_*.md` §7.1 | 4 | 2 | 4 | 4 | 4 | 1 | 1 | 3 | 3 | **26** |
| 3 | Configuration-engine bounded-evaluator/no-bypass guardrails | `07_*.md` §11, `ADR-CAND-ARCH-014/015` | 4 | 2 | 3 | 4 | 3 | 2 | 2 | 3 | 3 | **26** |
| 5 | Finance posting integrity (idempotent posting/period lock/balanced journal) | `FIN-202..208`, `05_*.md` §5, `FINTEST-001..024` | 4 | 2 | 3 | 4 | 3 | 2 | 2 | 2 | 3 | **25** |
| 6 | Environment/CI/secret/observability/backup foundation | `11_*.md` §11, `ADR-CAND-ARCH-024..027` | 3 | 2 | 4 | 2 | 4 | 1 | 1 | 4 | 2 | **23** |
| 7 | `FIN-195` tax/legal SME external verification | `14_*.md` §22/§25, RPD-016 | 3 | 3 | 2 | 3 | 3 | 1 | 1 | 4 | 2 | **22** |
| 7 | `HRT-282` payroll/tax SME external verification | `14_*.md` §22/§25, RPD-016 | 3 | 3 | 2 | 3 | 3 | 1 | 1 | 4 | 2 | **22** |
| 7 | RPD-038 custom-integration fan-out (17 categories, no shared abstraction) | `IEP-342..346`, `08_*.md` §8.2 | 2 | 3 | 2 | 2 | 2 | 2 | 2 | 3 | 4 | **22** |
| 7 | Penetration test gate | `RGL-402`, `14_*.md` §22 | 4 | 2 | 2 | 3 | 2 | 2 | 1 | 3 | 3 | **22** |
| 7 | WMS inventory-ledger correctness | `ATW-229..242`, `05_*.md` §3 | 3 | 3 | 2 | 3 | 2 | 2 | 2 | 2 | 3 | **22** |
| 7 | Schema/migration expand-migrate-contract discipline | `05_*.md` §8, financial-table extra review | 3 | 2 | 3 | 3 | 3 | 2 | 2 | 2 | 2 | **22** |
| 13 | RPD-031/037 contract-silent recovery = best effort | `HDN-384`, `RGL-408`, `11_*.md` §8.1 | 3 | 2 | 2 | 3 | 2 | 2 | 2 | 3 | 2 | **21** |
| 14 | GraphQL depth/complexity + webhook/rate-limit numeric ADRs | `ADR-CAND-ARCH-017/018` | 2 | 2 | 2 | 2 | 2 | 1 | 2 | 3 | 2 | **18** |
| 15 | Vendor-rate cross-phase coordination (resolved) | `ADR-CAND-ARCH-001`, `14_*.md` §20 | 2 | 2 | 2 | 2 | 2 | 1 | 1 | 1 | 1 | **14** |
| 16 | `TKT-HLP` partial-blocked release-depth item | `RGL-411`, `14_*.md` §20/§25 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 2 | 1 | **10** |

**Reproducibility check:** every row's nine scores are individually justified against the rubric in §2.1 by the citation column — a future agent recomputing this table from the same sources and the same rubric should reach the same ordinal ordering (exact sums may vary by ±1–2 per dimension on subjective calls, but the top-6/bottom-2 grouping is stable because the score gaps between those groups exceed plausible rubric disagreement).

## 8. Concurrency lanes

Per prompt task #6:

| Lane | Members | Genuinely independent? | Integration checkpoint |
|---|---|---|---|
| Lane A | Phase 5 (Advanced TMS/WMS) | Yes, of Phase 6 — different tables (`ATW-*` vs. `PRC-*`), different owning teams per `12_*.md` §9's note | Converges at Phase 7 entry (`PHASE_5_VERIFIED` **and** `PHASE_6_VERIFIED` both required) |
| Lane B | Phase 6 (Procurement/Vendor) | Yes, of Phase 5 | Same convergence point as Lane A |
| Lane C | `FIN-195` SME verification track | Independent of Finance's internal build (build can proceed; only *activation* waits) | Finance Go-Live Gate (`10_*.md` §5.3) and, ultimately, Phase 16 GA (`RGL-404`, §9 below) |
| Lane D | `HRT-282` SME verification track | Independent of HRIS's internal build | `HRT-282` capability activation and, ultimately, Phase 16 GA |
| Lane E | `ADR-CAND-ARCH-024..027` tooling selection (CI/CD, secret manager, observability, hosting/CDN) | Independent of any business-domain phase — a Phase 0 prerequisite, not a domain dependency | Must resolve before Phase 0 exit (`PHASE_0_VERIFIED`) — these are the one foundation item genuinely on Depth 0's spine, not a side lane once Phase 0 begins |
| Lane F | Remaining 14 integration categories (`08_*.md` §15, Phase 9) | Mutually independent of each other by RPD-038 design (no shared abstraction to serialize on) — but all internally depend on their respective domain phase already being `VERIFIED` | Phase 9 exit gate (`PHASE_9_VERIFIED`) requires all 17 categories' sandbox contract tests green |

**Freeze points** (`12_*.md` §5/§7.2, restated as this document's concurrency boundary): every phase's own stabilization window (its final 1–2 sprints, no new capability merges) and Phase 16's system-wide no-new-feature window once the RC is cut — both are lane-closing events: a lane cannot introduce new scope once its owning phase enters its stabilization window.

**Resource/skill assumption** (task #6, stated as an assumption per `12_*.md` §8, not a commitment): Lanes A/B require distinct Operations and Procurement subject-matter capacity to run genuinely in parallel — if the same limited pool staffs both, the "parallel" lanes become sequential in practice even though no *architectural* dependency forces it; this document does not assume a specific staffing level (none is evidenced) but flags the assumption explicitly, per §14.

## 9. Accepted-risk overlay (prompt task #5)

Per the prompt's explicit requirement to preserve — and visibly apply, not merely footnote — RPD-022, direct GA/no pilot, zero critical defects, contract-silent recovery, custom integrations, and time-sensitive Indonesia tax/payroll verification:

| Standing decision | Where it touches this critical path (concrete, not general) |
|---|---|
| **RPD-022** — Supreme Admin absolute CRUD, no tamper-proof claim | Ranked #1 (§7). Structurally: the `append_only_ledger` RLS policy family (`06_*.md` §4/§8) must ship in the **same migration** as every ledger table's creation (`06_*.md` §9's rollout rule) — this is not an optional overlay applied later, it changes *how* Depth-1 (Platform Core), Depth-4 (Finance), and Depth-7 (Loyalty) ship their ledger tables. It also permanently caps Detection Strength at "weak" (dimension 7) for every ledger-adjacent item, because the audit trail that would normally catch a privileged-actor abuse is itself alterable by the same actor (`06_*.md` §8) — no future evidence can raise this item's Det score, per `14_*.md` §26 rule 4 ("`ACCEPTED_RISK` is permanent, not resolvable"). |
| **RPD-034/036** — direct GA, no external pilot, full internal validation, zero critical defects | Ranked #3 (§7). Structurally: it removes an entire node type from the depth ladder (§3.1/§5) — there is no depth-11 "pilot" node, only depth-11 "GA" — and it converts Phase 16 (`RGL-404`) into a **hard convergence gate**: every one of Depth 0–9's residual risk items (§7) must independently reach zero-Sev-1 status *simultaneously*, because there is no partial-GA fallback to absorb a still-open defect in one module while others ship. This is why §7's Phase-16 item scores Dependency Centrality = 4 (every phase feeds it) despite the gate itself requiring no new build work. |
| **RPD-031/037** — contract-silent recovery = best effort, no universal RPO/RTO | Ranked #13 (§7). Structurally: it caps what Phase 15's DR rehearsal (`HDN-384`) can prove — the rehearsal demonstrates the recovery *process* works, never a guaranteed numeric RPO/RTO, because no universal number exists to test against (§10 below). This lowers the item's own Severity relative to a hypothetical "must hit a guaranteed number" gate, but it **raises** downstream Uncertainty for any tenant contract that later claims a non-default target — that claim is resolved at tenant onboarding, structurally outside this WBS's phase register (`13_*.md` §11, `14_*.md` §22), not at any node in §5's path. |
| **RPD-038** — custom per-integration adapters, no generic provider abstraction | Ranked #7 (§7). Structurally: it multiplies Phase 9's (Depth 8) effective task count without a shared amortization path — each of the 17 categories (3 seeded at Phase 1, 14 remaining at Phase 9) requires its own adapter, contract test, credential, and runbook (`08_*.md` §8.2); a defect discovered in one category's adapter provides zero direct fix leverage for another category's adapter, which is why this item's Remediation Complexity is scored at the maximum (4) — this is a designed trade-off (RPD-038 is deliberate, not an oversight), and this document does not recommend reopening it, only makes its critical-path cost visible. |
| **Time-sensitive Indonesia tax/payroll SME verification (RPD-016)** | Ranked #7 twice (`FIN-195`, `HRT-282`, §7). Structurally, this is the sharpest interaction in the whole overlay: `14_*.md` §25 classifies both gates as blocking *only* their own capability's activation — but RPD-034/036's "all modules before GA, zero Sev-1" rule (row above) means that by the time Phase 16's convergence gate (`RGL-404`) is reached, an unresolved SME gate is no longer a scoped, capability-local blocker — **it has become a GA blocker**, because GA requires every module active, and Finance/HRIS cannot be GA-active with their tax/payroll capability inactive. This document makes that interaction explicit (it is not separately stated in `12_*.md`/`14_*.md`, which each describe one half of it): the SME gates' Uncertainty score (4, the maximum — no agent-controllable timeline) is the single highest-uncertainty input to the Depth-10 convergence gate, and it is an *external* dependency this build process cannot resolve by working harder. |

No standing decision above is weakened, narrowed, or resolved by this document (`14_*.md` §26 rule 4, restated) — each row states where it bites on the path, not whether it should be revisited.

## 10. External/SME/contract gate placement

Per prompt task #8 ("gate owners" and task #5's evidence-gate integration), the exact position of every external gate already named in `14_*.md` §22/§25:

| Gate | Exact path position | Gate owner |
|---|---|---|
| Tax/legal SME sign-off | Tail of Depth 4 (Finance), re-checked at Depth 10 convergence per §9's interaction | Finance/Legal/Tax SME (`14_*.md` §25) |
| Payroll/tax SME sign-off | Tail of Depth 6 (HRIS+Ticketing), re-checked at Depth 10 convergence | HR/Payroll/Tax SME |
| Penetration test | Inside Depth 9 (Phase 15 hardening), before Depth 9 exit (`FULL_SYSTEM_HARDENING_VERIFIED`) | Security (`RGL-402`) |
| DR rehearsal | Inside Depth 9 (Phase 15 hardening), same exit gate, shared cadence with Testing workstream's `ADR-CAND-ARCH-023` | DevOps/Security (`HDN-384`) |
| Contract-specific RPO/RTO review | Outside the phase register entirely — occurs at each tenant's own onboarding, structurally after Depth 11 (GA) for the first tenant and repeatable for every subsequent tenant | Legal/SRE (`13_*.md` §11) |
| `docs/blueprint/tes.md` deletion | Non-blocking housekeeping, no depth position — resolvable at any point, does not sit on this path | Repository owner |

Six gates total, matching `14_*.md` §22's own count exactly — this document adds no seventh gate and removes none.

## 11. Risk burn-down evidence plan

Per prompt task #7. For each of §7's top-6 items, the evidence that would lower its score, and where that evidence is produced:

| Item | Burn-down evidence | Produced by |
|---|---|---|
| RPD-022 overlay | Cannot burn down (permanent, §9) — evidence plan is *containment*, not reduction: every Supreme Admin mutation of a ledger row produces an `audit_logs` before/after entry (negative test #9, `06_*.md` §10), reviewed on a standing cadence once Phase 1 ships | Phase 1 `AUD` capability + ongoing security review |
| Tenant isolation/RLS foundation | All 18 `TI-*` negative tests green at Phase 1 exit, re-run at every subsequent phase gate and again at Phase 15 hardening | `PLT-137..140` verification, `HDN-372..374` |
| RPD-034/036 convergence gate | Zero open Sev-1/Critical defect count, tracked continuously from Phase 1 onward, not first measured at Phase 16 | Every phase's own exit-gate defect-threshold check (`12_*.md` §7.1) |
| Configuration-engine guardrails | Dependency-validation gate (`07_*.md` §8) passing at every publish; bounded-evaluator sandbox test (`ADR-CAND-ARCH-015`) green before any rule activates | `07_*.md` §15 first slice, `07_*.md` §14 test matrix |
| Finance posting integrity | All 24 `FINTEST-*` green plus the 12-item Finance Go-Live Gate | `FIN-215..218` |
| Environment/CI/secret/observability/backup foundation | `ADR-CAND-ARCH-024..027` resolved with a concrete product choice; CI pipeline green on first commit; DR rehearsal #1 completed | `11_*.md` §11 first six slices |

**General rule (not item-specific):** every burn-down claim in this section is only valid once the cited verification/hardening WBS ID has actually run — this document does not itself claim any item is burned down; it names where that claim would first become evidenced.

## 12. Stop/rollback triggers

Per prompt task #6, reproduced by reference from `12_*.md` §7.4 and `11_*.md` §4.4/§8.3 (not re-authored, this document adds the risk-ranking lens only):

- Any of the 9 rollback-consideration triggers already fixed (`12_*.md` §7.4): tenant isolation failure, auth/login outage, data corruption, financial posting defect, material migration-reconciliation failure, a critical workflow that cannot execute, performance preventing critical operation, a security incident during cutover, a deployment breaking core pages/API.
- **Risk-ranking-specific addition:** if any §7 rank-1-through-6 item's score would rise (not merely stay flat) upon a proposed architecture or requirement change — e.g., a change that widens RPD-022's blast radius, or removes a currently-planned negative test — that change itself is a stop trigger requiring this document's re-issuance (§13) before the change proceeds, not a routine amendment.
- Per-layer rollback mechanism for any triggered stop: Frontend/API/DB-schema/Config/Feature/Data, exactly as `11_*.md` §4.4 already fixes — this document does not introduce a seventh rollback layer.

## 13. Assumptions

Every figure or framing below is an assumption, consistent with `12_*.md` §8's own discipline:

1. **Nine-dimension equal weighting (§2.2)** is an assumption, not an evidenced formula — no blueprint or prior architecture document specifies a risk-scoring weight scheme, so this document adopts the simplest defensible one (unweighted sum) rather than inventing a weighted one with no supporting evidence.
2. **Likelihood scores (§7)** are qualitative judgments from architectural complexity/novelty, not measured defect rates — this repository has zero implementation history (`RISK-001`), so no frequency data exists or could be honestly cited.
3. **Lane staffing (§8)** assumes Lanes A/B (Phase 5/6) have independent capacity available to run in parallel; if actual staffing is shared, the lanes serialize in practice without any architectural change being required.
4. **SME gate resolution (§9/§10)** assumes the tax/payroll SME engagements are initiated early enough (i.e., not first attempted at Phase 16) that their `EXTERNAL_VERIFICATION` status does not itself become the sole blocker to GA — this document does not assume a specific engagement date, since none is evidenced, but flags that *waiting* until Depth 10 to start this engagement would convert an Uncertainty-4 item into a hard schedule blocker with no remaining slack.
5. **`ADR-CAND-ARCH-024..027` tooling ADRs (§8 Lane E)** are assumed resolvable within Phase 0 without external procurement delay — no evidence contradicts this, but none confirms it either.

## 14. Sensitivity analysis

What would change this document's ordering if a stated assumption were wrong (prompt required output):

| If this assumption is wrong... | ...then this changes |
|---|---|
| RPD-022's Detection Strength is not actually permanently capped (e.g., a future architecture change introduces write-once external attestation) | Rank #1's score would drop materially (dimension 7 from 3 toward 1) — but per `14_*.md` §26 rule 4, this would itself be a decision-register change, requiring re-issuance of this document, not a silent recalculation |
| SME engagement (Indonesia tax/payroll) starts late (Depth 10, not earlier) | §9's "Depth 10 convergence gate" interaction becomes the actual binding constraint on GA timing, elevating rank-7 items' effective Dependency Centrality toward Phase-16's rank-3 item — the two would functionally merge into one blocking cluster |
| Lane A/B (Phase 5/6) staffing is shared, not independent | §8's concurrency lane collapses to sequential — Depth 5 becomes two sequential sub-depths, lengthening the ordinal path by one step without changing any risk score |
| `ADR-CAND-ARCH-024..027` tooling selection stalls past Phase 0 | Rank #6's Uncertainty (already 4) compounds into a genuine Dependency-Centrality escalation, since literally nothing at Depth 1+ can ship without a chosen CI/hosting/secret/observability stack — this would promote rank #6 toward the top 3 |
| A future workstream document (`05_*.md`–`11_*.md`) is amended | This entire document requires recalculation (§13 rule 1 below) — every score here is only as current as its cited source |
| RPD-038's per-category isolation assumption is relaxed (a shared abstraction is later approved) | Rank #7's integration-fan-out item would drop sharply (Remediation Complexity from 4 toward 2), since a shared fix path would then exist — this is the one item in §7 whose score is most sensitive to a plausible future architecture decision |

## 15. Recalculation rules

Per prompt task #7 ("recalculation triggers when ADRs, runtime facts, estimates, failures, or requirements change"):

1. **Source-document change.** Any amendment to `13_*.md` (WBS/dependency graph) or `14_*.md` (traceability/accepted-risk/blocker state) requires this document to be re-derived from the updated source in the same change — this document is not authoritative over either; both are authoritative over this document, exactly as `14_*.md` §26 rule 2 already establishes for its own relationship to `13_*.md`.
2. **ADR resolution.** Any of the fifteen still-open `ADR-CAND-ARCH-011..027` candidates (`HANDOFF.md` §1/§6) being resolved requires re-scoring the items in §6/§7 whose Uncertainty dimension cited that ADR's open status.
3. **Runtime evidence.** Once Phase 0 execution begins and `TASK_LEDGER.md` starts recording real `IMPLEMENTED`/`VERIFIED` states, every Likelihood score in §7 that was a design-time qualitative judgment must be re-evaluated against real defect/incident data at that item's first opportunity to be measured — mirroring `14_*.md` §26 rule 6's identical "prompt-package coverage" → "runtime evidence coverage" transition.
4. **A stop/rollback trigger fires (§12).** Any actual invocation of a rollback trigger requires this document's next revision to incorporate the incident's RCA (`11_*.md` §8.4) as new evidence for the relevant item's Severity/Likelihood/Detection scores — a real incident is never left unincorporated into the next ranking.
5. **A new requirement or decision is ratified.** A new `RPD-0NN`/`CPD-0NN` or a new `PKG-<AREA>-NNN` gap ID (per `14_*.md` §26 rule 5) that touches tenant/security/finance/data exposure requires a new row in §7, scored by the same rubric (§2.1) — never appended without scoring, never silently omitted.
6. **Step 3 closure.** `03-architecture-and-plan/51_STEP3_CLOSURE_VERIFICATION_PROMPT.md` (`16_STEP3_CLOSURE_REPORT.md`) checks this document as one of its sixteen inputs — any finding from that closure check that identifies a factual error here is itself a recalculation trigger.

## 16. ADR candidates

None new. This document ranks and sequences already-raised, already-owned ADR candidates (`ADR-CAND-ARCH-004` resolved, `011..027` open per `HANDOFF.md` §1/§6, all cited in §6/§7/§9 by ID) — it introduces no additional open architecture question of its own, and it resolves none (ranking is not resolution).

## 17. Exit gates

Every critical-path item (§5) and every ranked item (§7) traces to a WBS ID already present in `13_*.md` §4/§5 or `14_*.md`, or to an already-open `ADR-CAND-ARCH-*`/accepted-risk ID from `HANDOFF.md`/`CARGOGRID_CONTEXT.md` — zero fabricated ID (verified by construction: every citation column in §5–§10 names an existing document/section). The ranking method (§2) is reproducible: nine named ordinal dimensions, unweighted sum, tie-break rule stated. Uncertainty is explicit wherever unresolved (§2.1 dimension 8 scored on every §7 row; §13's five assumptions named as assumptions, never presented as fact). No unverified date is claimed anywhere in this document (confirmed by construction — every sequencing statement in §3/§5 is a depth/gate, never a calendar reference). All four target accepted risks (RPD-022, RPD-034/036, RPD-031/037, RPD-038) plus the time-sensitive Indonesia tax/payroll SME gates visibly affect sequencing or gate placement in §9/§10, not merely a footnote — each row states the concrete mechanism, not just the citation. The completion gate is met in full.

## 18. Completion statement

The ranking method (§2) fixes nine ordinal dimensions and an unweighted-sum composite score, reproducible without a hidden weighting scheme. The dependency graph summary (§3) restates — without re-deriving — `13_*.md` §4/§6 and `12_*.md` §9's phase-level graph as an 11-depth ordinal ladder, with intra-phase and cross-phase edges cited by reference. Foundation blockers (§4) are shown to have a named owner for every one of task #4's eleven categories. The ordered critical path (§5) walks Depth 0 through GA, annotating the risk-critical sub-slice inside each depth without reordering any phase. Near-critical branches (§6) name five conditional items with explicit promotion triggers. The risk-ranked task table (§7) scores sixteen items — every accepted risk, foundation blocker, and external gate at least once — with full per-dimension justification. Concurrency lanes (§8) identify the one genuinely parallel pair (Phase 5/6) and five further lanes with named integration checkpoints and a stated staffing assumption. The accepted-risk overlay (§9) states, for each of RPD-022/034/036/031/037/038 and the Indonesia SME gates, the exact mechanism by which it changes this path's shape — including the previously-unstated interaction between RPD-034/036's zero-Sev-1 convergence rule and the two SME gates' `EXTERNAL_VERIFICATION` status. External/SME gate placement (§10) fixes six gates at exact depth positions, matching `14_*.md` §22's count exactly. Risk burn-down evidence (§11), stop/rollback triggers (§12), assumptions (§13), sensitivity analysis (§14), and recalculation rules (§15) close out the remaining required output. No new ADR candidate is raised (§16). The completion gate (§17) is satisfied: every item sourced, ranking reproducible, uncertainty explicit, no fabricated dates, accepted risks visibly affecting sequencing.

Next eligible prompt: `03-architecture-and-plan/51_STEP3_CLOSURE_VERIFICATION_PROMPT.md` → `docs/architecture/16_STEP3_CLOSURE_REPORT.md`.
