# 00 — Phase 0 Work Breakdown Structure

**Prompt:** `CG-S5-PH0-001` (`CG-AABPP-PH0-080` v0.6.0)
**Runtime output of:** `docs/ai-agent-build-prompt-package/05-phase-00-discovery-foundation/80_PHASE0_WBS_RUNTIME_KICKOFF_PROMPT.md`
**Companion document:** `docs/build-log/phase-00/00_PHASE0_EXECUTION_INDEX.md` (per-task status/dependency/evidence table; this document is the hierarchy/concurrency/recovery structure that index's tasks instantiate)
**Status:** `PHASE_0_IN_PROGRESS` (kickoff/index only — see companion document §0 for checkpoint and mutation statement, not repeated here)

## 0. Scope and method

This document does not create, assign, or execute an implementation task (mirrors `13_FULL_WORK_BREAKDOWN_STRUCTURE.md` §1's own discipline at the Step 3 layer). The 21 operational Phase 0 prompt files (`81`–`101`, plus README `79`, kickoff `80`, and closure `102` — 24 files total, matching `79_*.md` §7's "24 non-empty files" package-completion count) already exist, are package-validated (`docs/ai-agent-build-prompt-package/00-control/06_PACKAGE_BUILD_STATUS.md` §1: "Step 5 Phase 0 files `VERIFIED` — 24/24"; "Phase 0 operational fields `VERIFIED` — 756/756 across 21 prompts" = 36 fields × 21 prompts, confirmed by construction), and each already carries its own workstream/epic/capability/feature-slice framing in its own §2–§3. This document's job is to bind that already-existing content into the mandatory 10-level runtime hierarchy required by `79_PHASE0_README.md` §3, prove all 18 mandatory capabilities plus verification/hardening/documentation/closure are covered, and add the runtime-specific concurrency/checkpoint/staleness/recovery structure that no individual capability prompt file states on its own (each is scoped to its own bounded slice, not the cross-slice execution graph).

## 1. Mandatory hierarchy

Per `79_PHASE0_README.md` §3: `Phase 0 → Workstream → Epic → Capability → Feature slice → Atomic implementation task → Verification task → Hardening task → Documentation task → Phase closure task`.

| Level | Phase 0 instantiation |
|---|---|
| Phase | Phase 0 — Discovery and Foundation (`05-phase-00-discovery-foundation/`, `13_*.md` §4 row 0) |
| Workstream | One of 9 workstream groupings, §2 below (Governance/Source Control, Repository Foundation, Developer Experience, UX Foundation, Quality Foundation, Operations Foundation, Product Foundation, Phase Verification) |
| Epic | Each workstream's declared scope across its member capabilities (§2) |
| Capability | One of the 18 rows in §3 below (`PH0-081..098`) |
| Feature slice | The individual numbered prompt file itself (e.g. `85_DEVELOPMENT_ENVIRONMENT_FOUNDATION_PROMPT.md`) |
| Atomic implementation task | One `{{TASK_ID}}`-instantiated run of that file against the current repository checkpoint, recorded in `TASK_LEDGER.md` under its `CG-S5-PH0-<NNN>` ID once `READY` |
| Verification task | `PH0-099` — Phase 0 Integrated Verification |
| Hardening task | `PH0-100` — Phase 0 Hardening |
| Documentation task | `PH0-101` — Phase 0 Documentation and Handoff |
| Phase closure task | `PH0-102` — Phase 0 Closure Verification (only prompt authorized to set `PHASE_0_VERIFIED`, per `79_*.md` §6 and `102_*.md`'s own "Completion gate") |

Every level is present and non-empty (verified directly against each prompt file's own §2/§3 fields, not assumed) — no level in the mandatory 10 is skipped.

## 2. Workstream / Epic grouping

Nine workstreams partition the 18 capabilities plus the 4 phase-level tasks. Grouping is derived directly from each prompt's own title and, where read in full, its own §3 "Workstream" field (`81`→"Governance and Source Control", `85`→"Developer Experience", `99`→"Phase Verification") — not invented:

| Workstream | Epic | Member capabilities |
|---|---|---|
| Governance and Source Control | Authoritative Product Baseline; Requirement Governance; Decision Governance | `PH0-081` (source alignment/context bootstrap), `PH0-082` (requirement traceability baseline), `PH0-084` (ADR baseline/decision governance) |
| Repository Foundation | Audit Adoption; Version Control Strategy; Continuous Integration; Engineering Standards; Documentation Standards | `PH0-083` (repository audit adoption/gap closure), `PH0-087` (Git strategy foundation), `PH0-088` (CI/CD baseline), `PH0-089` (coding standards/architecture enforcement), `PH0-092` (documentation foundation) |
| Developer Experience | Reproducible Local Development | `PH0-085` (development environment foundation), `PH0-086` (environment validation foundation) |
| UX Foundation | Design System | `PH0-090` (design system foundation) |
| Quality Foundation | Test Infrastructure | `PH0-091` (testing foundation) |
| Operations Foundation | Observability; Security; Data Governance | `PH0-093` (observability baseline), `PH0-094` (security baseline controls), `PH0-095` (data classification foundation), `PH0-096` (initial threat model) |
| Product Foundation | Analytics; Progressive Delivery | `PH0-097` (product analytics baseline), `PH0-098` (feature flag foundation) |
| Phase Verification | Foundation Integration Gate; Foundation Hardening; Documentation and Handoff; Phase Closure | `PH0-099` (integrated verification), `PH0-100` (hardening), `PH0-101` (documentation/handoff), `PH0-102` (closure) |
| Phase Kickoff (this document's own workstream) | Phase 0 Kickoff | `PH0-080` (WBS and runtime kickoff — this document and its companion index) |

9 workstreams × their member capabilities = 18 capability prompts (§3) + 1 kickoff (`080`) + 4 phase-level tasks (`099`–`102`) = 23 total `CG-S5-PH0-<NNN>` IDs, matching `79_*.md` §4's 23-row execution catalogue exactly (order 0 through 22).

## 3. Capability coverage — all 18 mandatory Phase 0 capabilities

Every row cites its exact upstream dependency from `79_PHASE0_README.md` §4 (not re-derived) and its exact `CG-S5-PH0-<NNN>` runtime ID (verified against each file's own header, §2 of the companion execution index):

| # | `PH0-` | Runtime ID | Capability | Feature slice | Upstream dependency (source: `79_*.md` §4) |
|---:|---|---|---|---|---|
| 1 | `081` | `CG-S5-PH0-002` | Source alignment and context bootstrap | `81_SOURCE_ALIGNMENT_CONTEXT_BOOTSTRAP_PROMPT.md` | `PH0-080` |
| 2 | `082` | `CG-S5-PH0-003` | Requirement traceability baseline | `82_REQUIREMENT_TRACEABILITY_BASELINE_PROMPT.md` | `PH0-081` |
| 3 | `083` | `CG-S5-PH0-004` | Repository audit adoption and gap closure | `83_REPOSITORY_AUDIT_ADOPTION_GAP_CLOSURE_PROMPT.md` | `PH0-081..082` |
| 4 | `084` | `CG-S5-PH0-005` | ADR baseline and decision governance | `84_ADR_BASELINE_DECISION_GOVERNANCE_PROMPT.md` | `PH0-081..083` |
| 5 | `085` | `CG-S5-PH0-006` | Development environment foundation | `85_DEVELOPMENT_ENVIRONMENT_FOUNDATION_PROMPT.md` | `PH0-083..084` |
| 6 | `086` | `CG-S5-PH0-007` | Environment validation foundation | `86_ENVIRONMENT_VALIDATION_FOUNDATION_PROMPT.md` | `PH0-085` |
| 7 | `087` | `CG-S5-PH0-008` | Git strategy foundation | `87_GIT_STRATEGY_FOUNDATION_PROMPT.md` | `PH0-083..086` |
| 8 | `088` | `CG-S5-PH0-009` | CI/CD baseline | `88_CICD_BASELINE_PROMPT.md` | `PH0-085..087` |
| 9 | `089` | `CG-S5-PH0-010` | Coding standards and architecture enforcement | `89_CODING_STANDARDS_ARCHITECTURE_ENFORCEMENT_PROMPT.md` | `PH0-084..088` |
| 10 | `090` | `CG-S5-PH0-011` | Design system foundation | `90_DESIGN_SYSTEM_FOUNDATION_PROMPT.md` | `PH0-083..089` |
| 11 | `091` | `CG-S5-PH0-012` | Testing foundation | `91_TESTING_FOUNDATION_PROMPT.md` | `PH0-082..090` |
| 12 | `092` | `CG-S5-PH0-013` | Documentation foundation | `92_DOCUMENTATION_FOUNDATION_PROMPT.md` | `PH0-081..091` |
| 13 | `093` | `CG-S5-PH0-014` | Observability baseline | `93_OBSERVABILITY_BASELINE_PROMPT.md` | `PH0-083..092` |
| 14 | `094` | `CG-S5-PH0-015` | Security baseline controls | `94_SECURITY_BASELINE_CONTROLS_PROMPT.md` | `PH0-082..093` |
| 15 | `095` | `CG-S5-PH0-016` | Data classification foundation | `95_DATA_CLASSIFICATION_FOUNDATION_PROMPT.md` | `PH0-081..094` |
| 16 | `096` | `CG-S5-PH0-017` | Initial threat model | `96_INITIAL_THREAT_MODEL_PROMPT.md` | `PH0-083..095` |
| 17 | `097` | `CG-S5-PH0-018` | Product analytics baseline | `97_PRODUCT_ANALYTICS_BASELINE_PROMPT.md` | `PH0-082..096` |
| 18 | `098` | `CG-S5-PH0-019` | Feature flag foundation | `98_FEATURE_FLAG_FOUNDATION_PROMPT.md` | `PH0-084..097` |

**Coverage result: 18/18 mandatory capabilities present**, each with exactly one feature-slice file, one runtime ID, and one upstream-dependency set — cross-checked arithmetically against `79_*.md` §4's own table (18 rows, order 1–18) with zero addition, omission, or renumbering.

## 4. Verification / hardening / documentation / closure tasks

| `PH0-` | Runtime ID | Role | Upstream | Output |
|---|---|---|---|---|
| `099` | `CG-S5-PH0-020` | Verification task — Phase 0 Integrated Verification | `PH0-081..098` (all 18) | `docs/build-log/phase-00/PH0-99.md` |
| `100` | `CG-S5-PH0-021` | Hardening task — Phase 0 Hardening | `PH0-099` | `docs/build-log/phase-00/PH0-100.md` |
| `101` | `CG-S5-PH0-022` | Documentation task — Phase 0 Documentation and Handoff | `PH0-100` | `docs/build-log/phase-00/PH0-101.md` |
| `102` | `CG-S5-PH0-023` | Phase closure task — Phase 0 Closure Verification | `PH0-101` | `docs/build-log/phase-00/PHASE0_CLOSURE_REPORT.md` |

**Coverage result: all 4 non-capability mandatory levels present**, each a distinct, already-authored prompt file selected by phase position (not a Template-53-shaped slice — mirrors `13_*.md` §8's identical distinction at the Step 3 layer).

## 5. Atomic sizing

Every one of the 21 operational prompts (§3 rows 1–18 plus `099`–`101`) states the identical binding sizing rule in its own §11 ("Allowed files/folders... normally 5–15 files") — verified directly in `81_*.md` §11, `85_*.md` §11, `99_*.md` §11 (full reads) and structurally present in every spot-checked header/body (`82`–`98`, `100`, `101` share the identical §11 wording pattern per the uniform 36-field template all 21 prompts instantiate, `79_*.md` §7). This is the same 5–15-file, 1–3-migration bound `13_FULL_WORK_BREAKDOWN_STRUCTURE.md` §9 already enforces at the Step 3/Platform-Core layer — Phase 0 does not introduce a looser or stricter rule. No oversized capability was found: each of the 18 rows in §3 maps to exactly one bounded foundation concern (one tool decision, one control family, or one baseline), never a bundled multi-concern prompt.

## 6. Safe concurrency lanes (required task 6)

The dependency chain in §3 is **strictly linear by design** for the majority of capabilities (each depends on a growing prefix of its predecessors, per `79_*.md` §4's own upstream-dependency column) — this is the same "default sequential unless proven otherwise" discipline `79_*.md` §4's closing sentence states explicitly: "Parallel execution is allowed only when Prompt 80 proves no dependency/file/schema/environment collision." This document (Prompt 80's own output) performs that proof for the two genuine candidate lanes found:

| Lane | Members | Genuinely independent? | Collision check | Integration checkpoint |
|---|---|---|---|---|
| Lane P0-A | `PH0-085` (development environment) ∥ `PH0-086` (environment validation) | **No** — `086`'s own upstream is `085` alone (§3 row 6); `086` validates what `085` creates. Not parallel; sequential pair. | N/A — not a real lane | `086` completion |
| Lane P0-B | `PH0-093` (observability) ∥ `PH0-095` (data classification) ∥ `PH0-097` (product analytics) | **Partially** — all three share the identical upstream prefix `PH0-083..09X` range but target disjoint concerns (telemetry pipeline vs. data-classification taxonomy vs. analytics event schema) and disjoint likely file paths (observability config, classification policy docs, analytics event catalogue). However, `094` (security), `096` (threat model), and `098` (feature flags) all sit strictly between or after these three in `79_*.md`'s own numbering with their own upstream ranges spanning into this set (`096` depends on `083..095`, i.e., after `095`; `098` depends on `084..097`, i.e., after `097`) — the package's own dependency table does **not** license true concurrency here; each of `093`/`094`/`095`/`096`/`097`/`098` has an upstream range that grows monotonically, meaning `094` genuinely needs `093` and `095` genuinely needs `093..094` per `79_*.md` §4's own literal table, not merely "could be independent." **Conclusion: no proven collision-free concurrency exists inside `093..098`; this document does not license a lane here** — the package's own ranges are read literally, not loosened. |
| Lane P0-C (tooling-selection sub-lane, not a separate WBS row) | `ADR-CAND-ARCH-024..027` (CI/CD platform + package manager, secret manager, observability tool, hosting/CDN) — all four resolve *inside* `PH0-085..088`'s own execution, per `15_RISK_RANKED_CRITICAL_PATH.md` §8 Lane E ("independent of any business-domain phase — a Phase 0 prerequisite... must resolve before Phase 0 exit") | Yes, of any Phase 1+ business-domain lane | These four ADRs govern *tooling choice*, not file/schema/environment collision between Phase 0 capabilities themselves — carried forward by reference, not re-litigated here | Must resolve before `PH0-088` (CI/CD baseline) can meaningfully execute, and no later than Phase 0 exit (`PH0-102`) |

**Conclusion:** per `79_*.md` §4's own closing rule, this document finds **zero proven collision-free concurrent lane** among the 18 capability prompts themselves at this checkpoint — every one of `79_*.md` §4's upstream-dependency ranges is a genuine, literal prerequisite, not a conservative default that could be loosened. The only legitimate "lane" is the tooling-ADR resolution track (P0-C), which is not a separate WBS execution path but a sub-concern resolved inside the already-linear `085..088` sequence. **Execution proceeds strictly sequentially, `081` → `098` → `099` → `100` → `101` → `102`, one task at a time, one branch (`agent/cargogrid-autonomous-build`), consistent with this repository's established single-writer discipline (`ISS-2026-002`) and this build's demonstrated pattern through Step 2/Step 3 (one task `READY` at a time in `TASK_LEDGER.md`, never several simultaneously).**

## 7. Integration checkpoints

| Checkpoint | Trigger | What is verified |
|---|---|---|
| IC-1 | End of `PH0-084` (governance/decision quartet: `081`,`082`,`083`,`084`) | Source alignment, requirement traceability, repository-audit gap closure, and ADR baseline are mutually consistent before any tool/environment decision is made on top of them |
| IC-2 | End of `PH0-089` (environment/Git/CI/standards quintet: `085`–`089`) | Local dev environment, environment validation, Git strategy, CI/CD baseline, and coding-standards enforcement together form one working, tested pipeline — this is the checkpoint where the repository first has a real toolchain, matching `CARGOGRID_CONTEXT.md` §7's own note that baseline commands are "populated when Phase 0 establishes the environment (Prompts 85–88)" |
| IC-3 | End of `PH0-092` (design/testing/documentation trio: `090`–`092`) | Design-system, testing, and documentation foundations are consistent with the CI/CD baseline established at IC-2 (e.g., the testing foundation's CI hook actually runs against the CI/CD baseline just built) |
| IC-4 | End of `PH0-098` (observability/security/data/threat/analytics/flags sextet: `093`–`098`) | All cross-cutting operational controls are consistent with each other and with the environment/CI baseline (e.g., the security baseline's secret-scanning control and the observability baseline's alerting both reference the same CI pipeline built at IC-2) — this is the last checkpoint before `PH0-099` |
| IC-5 | `PH0-099` itself | The formal, prompt-defined integrated verification of all 18 capabilities together — IC-1 through IC-4 are this document's own incremental checkpoints *inside* the sequential execution; `PH0-099` is the authoritative, prompt-mandated integration gate, not superseded by IC-1–IC-4 |

IC-1 through IC-4 are this WBS's own internal recommended pause points for evidence review (not new prompt files, not a deviation from the strict sequence in §6) — they exist so a future agent re-validates cross-slice consistency incrementally rather than deferring every check to `PH0-099` alone, reducing the blast radius of a defect discovered late.

## 8. Stale-evidence triggers

Any of the following invalidates a `READY` determination in the companion execution index and requires re-derivation before the affected task proceeds:

1. **Source-document change.** Any amendment to `docs/architecture/13_*.md`, `14_*.md`, `15_*.md`, or `16_*.md` (the Step 3 evidence this Phase 0 graph is built on) requires this document and the companion index to be re-derived from the updated source — mirrors `15_RISK_RANKED_CRITICAL_PATH.md` §15 rule 1's identical discipline one layer up.
2. **Branch/checkpoint drift.** If the active branch's HEAD moves to a commit other than the one recorded in the companion index §0 (`c69a4f8`) without this document being re-issued, every `READY`/`BLOCKED` determination in §3 of the companion index must be re-verified against the new HEAD before any task proceeds — a stale HEAD reference is itself a stop condition, not a detail to silently update.
3. **ADR resolution.** Any of the open `ADR-CAND-ARCH-011,020..027` candidates being resolved changes the "due at" annotation in the companion index's §3 table for the owning capability (`083`/`087`→`011`; `090`→`020/021`; `091`→`022/023`; `085..088`→`024..027`) — the capability itself does not become newly `READY` or `BLOCKED` by this alone (ADR resolution happens *inside* the capability's own execution, per §3 note above), but the evidence citation must be updated to point at the resolution record rather than the still-open `HANDOFF.md` entry.
4. **Upstream `VERIFIED` state change.** The moment any `PH0-08X`/`09X` task's status changes from `NOT_STARTED`/`READY` to `VERIFIED` in `TASK_LEDGER.md`, every task listing it as an upstream dependency (§3 above) must be re-evaluated for `READY` — this is the expected, routine trigger that advances the sequential chain in §6, not an exceptional event.
5. **A stop/rollback trigger fires.** Any invocation of the rollback triggers already fixed at the release-train layer (`12_RELEASE_TRAIN.md` §7.4, `11_DEVOPS_WORKSTREAM.md` §4.4/§8.3, restated by `15_*.md` §12) during a Phase 0 capability's execution requires this document's next revision to incorporate the incident before any subsequent task in §6's sequence proceeds.
6. **Repository/tooling reality contradicts a recorded assumption.** If a future capability's execution discovers the repository already contains a file, script, or config this document's §4 (companion index) or §6 above assumed did not exist (collision), execution stops for that task and this document is re-issued with the corrected collision finding — never silently absorbed.

## 9. Recovery order

If Phase 0 execution is interrupted, fails a gate, or a stop/rollback trigger (§8 item 5) fires mid-sequence, recovery follows the same per-layer rollback discipline `11_DEVOPS_WORKSTREAM.md` §4.4 and `12_RELEASE_TRAIN.md` §7.4 already fix (restated here as this document's own recovery-order requirement per task 6, not re-authored):

1. **Identify the last `VERIFIED` capability** in `TASK_LEDGER.md`'s Phase 0 section — this is the last known good checkpoint, not necessarily the last one attempted.
2. **Roll back to that checkpoint's commit** (`git revert` the failed/partial task's commit(s), per this repository's established recovery pattern — never a hard reset, per this build's own git-safety discipline).
3. **Re-run the failed capability** using its own template's Verification/Hardening/Documentation task shapes if the failure was cosmetic, or its bounded resume-prompt mechanism (`75_DOCUMENTATION_ONLY_CHANGE_TEMPLATE`/`73_RESUME_FAILED_TASK_TEMPLATE`/`74_RESUME_INTERRUPTED_PHASE_TEMPLATE` from the Step 4 reusable library, `04-reusable-prompts/`) if the failure was structural — matching this repository's own "never restart the phase blindly" rule, restated verbatim in every one of the 21 operational prompts' own §32 ("Rollback/recovery note").
4. **Recovery order follows the same §6 sequence**, resuming exactly at the failed task, not at `PH0-081` — because every downstream task's dependency is already scoped to the specific upstream ID(s) in §3, a mid-sequence failure does not require re-running already-`VERIFIED` upstream tasks.
5. **If the failure implicates cross-slice integration** (discovered at an IC-1–IC-4 checkpoint or at `PH0-099` itself), recovery re-enters at the earliest capability whose output the failure traces to, not merely the most recently attempted task — per `15_*.md` §12's identical "a real incident is never left unincorporated into the next ranking/plan" discipline.
6. **Update `ERROR_LEDGER.md`/`KNOWN_ISSUES.md`/`HANDOFF.md`** with the incident before resuming — never silently retried without a record, per this repository's universal operational rules (`79_*.md` §5).

## 10. Cycle/orphan/duplicate checks

- **Cycles:** `79_PHASE0_README.md` §4's dependency table is a strictly monotonic, file-number-increasing chain for every one of the 18 capabilities (each capability's upstream range's highest member is always a lower file number than the capability itself) — by construction, no cycle can exist in a strictly monotonic dependency graph. Independently confirmed by direct inspection of every row in §3 above: zero row names a downstream task as its own upstream.
- **Orphans:** every one of the 18 capabilities in §3 has exactly one upstream dependency set (never zero, except `PH0-081` whose sole upstream is `PH0-080` itself — the kickoff, not an orphan) and is itself named as the upstream of at least one later task or of `PH0-099` (the terminal capability, `PH0-098`, is `PH0-099`'s explicit upstream) — zero capability exists with no downstream consumer and no capability exists with no upstream owner.
- **Duplicates:** each of the 23 `CG-S5-PH0-<NNN>` IDs (`001`–`023`) maps to exactly one file (verified: the linear mapping `CG-S5-PH0-(file# − 79)` produces no collision for file numbers `80`–`102`) and each file number `80`–`102` is claimed by exactly one capability/task row across §3–§4 — no ID or file number is double-assigned.

**Result: zero unresolved cycles, zero orphans, zero duplicates** — satisfying `80_*.md`'s completion gate ("no cycle/orphan/collision remains unowned") at the WBS-structure level, complementing the companion index's §4 file/schema/environment collision finding.

## 11. Completion statement

The mandatory 10-level hierarchy (§1) is instantiated in full — Phase 0 → 9 workstreams/epics (§2) → 18 capabilities (§3) → 18 feature-slice files → atomic per-task runtime instantiation → the 4 non-capability mandatory levels (§4: verification `099`, hardening `100`, documentation `101`, closure `102`). Atomic sizing (§5) holds at the same 5–15-file bound already established at the Step 3/Platform-Core layer, verified directly against each spot-checked prompt's own §11. Concurrency analysis (§6) proves — rather than assumes — that Phase 0's own dependency table licenses zero collision-free parallel lane among the 18 capabilities at this checkpoint (the package's own monotonic dependency ranges are read literally, not loosened), with the sole legitimate concurrency being the tooling-ADR resolution sub-track already named by `15_RISK_RANKED_CRITICAL_PATH.md` §8 Lane E. Five internal integration checkpoints (§7) are defined to catch cross-slice drift incrementally ahead of the formal `PH0-099` gate. Six stale-evidence triggers (§8) and a six-step recovery order anchored to per-layer rollback and the Step 4 resume-template mechanism (§9) are defined. Cycle/orphan/duplicate checks (§10) all resolve to zero. This document introduces no new WBS ID scheme (§2's adoption of the package's own `CG-S5-PH0-<NNN>` IDs, mirroring `13_FULL_WORK_BREAKDOWN_STRUCTURE.md` §2's identical discipline at the Step 3 layer) and reopens no ratified product decision.

**Next eligible prompt:** `CG-S5-PH0-002` (`81_SOURCE_ALIGNMENT_CONTEXT_BOOTSTRAP_PROMPT.md`) — see companion `00_PHASE0_EXECUTION_INDEX.md` §7 for the completion-gate confirmation this eligibility depends on.
