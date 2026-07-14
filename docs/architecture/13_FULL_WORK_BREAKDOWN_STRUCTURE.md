# 13 — Full Work Breakdown Structure

**Prompt:** `CG-S3-ARCH-013` (`CG-AABPP-ARCH-048` v0.4.0)
**Runtime output of:** `docs/ai-agent-build-prompt-package/03-architecture-and-plan/48_FULL_WORK_BREAKDOWN_STRUCTURE_PROMPT.md`
**Status:** `VERIFIED`

## 0. Checkpoint

| Field | Value |
|---|---|
| Repository | `assujiar/cargogrid.app` |
| Working branch | `agent/cargogrid-autonomous-build` (tracked by GitHub PR #7) |
| HEAD at authoring time | `a47a370` (parent of this checkpoint's commit on `claude/sleepy-ride-4vxsk6`; corrected 2026-07-14 per `16_STEP3_CLOSURE_REPORT.md` Finding F1 — the original citation, `56bf889`, was this same content's pre-branch-merge commit hash on `agent/cargogrid-autonomous-build`, byte-identical, not a content change) |
| Precondition | `docs/architecture/01_*.md` through `12_*.md` all `VERIFIED` |
| Repository state | Unchanged: zero code, zero task executed against this WBS (prompt precondition, verified) |
| Mutation performed | **NONE** — planning/indexing only; no implementation task was started (prompt precondition, verified) |

### Inputs read (beyond `01–12_*.md`, already fully loaded)

- `docs/ai-agent-build-prompt-package/00-control/05_REQUIREMENT_COVERAGE_MATRIX.md` (full: 194 explicit requirement IDs §2, functional-family coverage §3, 10 explicit NFR IDs §4, 13 package-generated gap-requirement IDs §5 [corrected 2026-07-14 from an earlier "14" miscount — see `14_REQUIREMENT_PHASE_TRACEABILITY.md` §1/§21 and `16_STEP3_CLOSURE_REPORT.md` §6 for the count reconciliation, independently re-verified], cross-cutting catalogue coverage §6, per-phase/step coverage conclusions §7 and §17–§25 — already-validated package-level completeness evidence, not re-derived)
- `docs/ai-agent-build-prompt-package/00-control/07_PROMPT_PACKAGE_MANIFEST.md`, `06_PACKAGE_BUILD_STATUS.md` (confirm `FINAL_PACKAGE_VALIDATED`, files 1–430 exist)
- `docs/ai-agent-build-prompt-package/04-reusable-prompts/52_STEP4_REUSABLE_PROMPTS_README.md`, `53_NEW_FEATURE_SLICE_TEMPLATE.md` (full — the 36-field atomic-task record schema this document binds), directory listing of `53`–`77` (24 further templates)
- `docs/ai-agent-build-prompt-package/05-phase-00-discovery-foundation/79_PHASE0_README.md` (full — §4 Execution catalogue with explicit per-item upstream-dependency lists)
- `docs/ai-agent-build-prompt-package/06-phase-01-platform-core/103_PLATFORM_CORE_README.md` §4 (already cited verbatim in `01_*.md` §3.1 — not re-read in full, reused by citation)
- `docs/ai-agent-build-prompt-package/09-phase-04-finance/189_FINANCE_README.md` (full — §4 Capability catalogue and dependency order, §5 Binding rules, §6 Mandatory evidence, §7 Runtime states, §8 Package completion — read as the second full worked example, confirming the per-phase README structure is uniform)
- Directory listings (file names, confirming ID ranges and per-phase file counts) for every phase directory `05-phase-00-discovery-foundation` through `17-final-validation`
- `docs/discovery/12_GREENFIELD_BROWNFIELD_DECISION.md` (confirms `GREENFIELD` — binds §9 below)

## 1. Scope and method

This document does not create, assign, or execute an implementation task (prompt precondition and completion gate). The AI Agent Build Prompt Package (`docs/ai-agent-build-prompt-package/`) already contains a complete, package-validated (`FINAL_PACKAGE_VALIDATED`, `docs/ai-agent-build-prompt-package/00-control/06_PACKAGE_BUILD_STATUS.md`) set of 430 numbered files organized as: 1 root entrypoint (`START_HERE.md`), governance/control documents (`00-control/`, `01-agent-governance/`), Step 2 discovery prompts (`02-discovery/`, already executed — `docs/discovery/**`), Step 3 architecture prompts (`03-architecture-and-plan/`, this package, files 35–51, 13/16 executed as of this checkpoint), Step 4 reusable templates (`04-reusable-prompts/`, files 52–78), and twelve phase/stage packages (`05-phase-00-discovery-foundation/` through `17-final-validation/`, files 79–430). Every phase package already follows one uniform internal structure — README → WBS runtime-kickoff prompt → N capability/atomic-task prompts in dependency order → integrated-verification prompt → hardening prompt → documentation/handoff prompt → independent-closure prompt — verified identical across the two full worked examples read for this document (Platform Core, `103_*.md`, and Finance, `189_*.md`) and structurally confirmed for every remaining phase via directory listing (file-count reconciliation, §4 below).

**This document's job is therefore not to invent ~350 new atomic tasks from nothing — it is to bind the package's already-existing, already-validated numbering into the prompt's mandatory 10-level runtime hierarchy, with runtime-specific stable IDs, dependency edges, cross-cutting workstream tags, a bound task-record schema, atomic-sizing verification, and a runtime completeness/orphan/cycle check** distinct from the package-generation-level check `00-control/05_*.md` already performed (that document checks "does every requirement have an assigned prompt"; this document checks "is the *runtime execution graph* over those prompts complete, non-duplicated, non-orphaned, and acyclic against this specific repository's Step 3 architecture"). Re-typing the full content of any of the 430 existing files would violate this repository's evidence-precedence rule (cite, don't reinvent) and the prompt's own "no implementation is performed" gate — every phase/capability reference below is a citation into an already-existing file, not a new specification.

## 2. WBS conventions and stable ID scheme

- **Stable WBS ID = the package's own numeric file ID, prefixed `CG-WBS-`.** File `105_TENANT_PROVISIONING_LIFECYCLE_PROMPT.md` is `CG-WBS-105`; no second numbering scheme is introduced, since the package's numeric IDs (1–430, sequential, gapless within each directory per §4's reconciliation) already satisfy "stable IDs... preserve traceability through later package steps" (task #1) without translation risk.
- **Phase short-codes** (already used inside each phase's own README/capability files, adopted here unchanged): `PH0` (Phase 0), `PLT` (Platform Core, Phase 1), `COM` (Commercial, Phase 2), `OPS` (Operations, Phase 3/5 basic+advanced), `FIN` (Finance, Phase 4), `ATW` (Advanced TMS/WMS, Phase 5), `PRC` (Procurement/Vendor, Phase 6), `HRT` (HRIS/Ticketing, Phase 7), `CPL` (Customer Portal/Loyalty, Phase 8), `IEP` (Intelligence/Enterprise, Phase 9), `HDN` (Full-System Hardening, Phase 15), `RGL` (Release/Go-Live, Phase 16), `FPV` (Final Package Validation, Phase 17) — a short-code plus its numeric suffix (e.g. `FIN-197`) is the human-readable form of the same `CG-WBS-197` ID, used interchangeably with the runtime ledger's own convention already established in `TASK_LEDGER.md`.
- **Hierarchy-level suffix** is positional, not a separate ID: within a phase's file range, position 1 is always the README (Epic-defining document), position 2 is always the WBS runtime-kickoff prompt (Workstream entry gate), the interior range is Capability/Feature-slice/Atomic-implementation-task prompts, and the final 3–4 positions are always Verification → Hardening → Documentation → Closure (§4's per-phase table gives the exact split).

## 3. Mandatory hierarchy mapping

| Prompt's mandatory level | Package structural equivalent | Example (Finance, Phase 4) |
|---|---|---|
| Parent phase | Phase directory (`0N-phase-...`) | `09-phase-04-finance` |
| Workstream | Phase README's declared scope (§1 of each README) | `189_FINANCE_README.md` — "controlled billing, receivables, payables, cash and double-entry accounting" |
| Epic | Phase README's capability catalogue (§4 of each README) as a whole | `189_*.md` §4's 24-capability table |
| Capability | One row of the README's §4 catalogue | Row 6: "Accounts receivable" (`FIN-196`) |
| Feature slice | The individual numbered prompt file itself | `196_ACCOUNTS_RECEIVABLE_PROMPT.md` |
| Atomic implementation task | One `{{PROMPT_ID}}`-instantiated run of that file against one repository checkpoint (Template 53 §1) | A future runtime instantiation of `196_*.md`, assigned a `TASK_LEDGER.md` entry when `READY` |
| Verification task | Phase's integrated-verification prompt | `215_FINANCE_INTEGRATED_VERIFICATION_PROMPT.md` |
| Hardening task | Phase's hardening prompt | `216_FINANCE_INTEGRITY_SECURITY_HARDENING_PROMPT.md` |
| Documentation task | Phase's documentation/handoff prompt | `217_FINANCE_DOCUMENTATION_HANDOFF_PROMPT.md` |
| Phase closure task | Phase's independent-closure prompt (the only prompt authorized to set the phase's `_VERIFIED` state) | `218_FINANCE_CLOSURE_VERIFICATION_PROMPT.md` (Finance README §7: "Only Prompt 218 may set `PHASE_4_VERIFIED`") |

Every phase in §4 below instantiates this identical 10-level mapping — the level names differ only in which file range fills "Capability/Feature slice," never in the presence of all 10 levels (verified per-phase in §4's file-count reconciliation).

## 4. Complete phase/workstream register

One row per parent phase (Phase 0 through Final Validation) plus the Step 4 cross-cutting template layer that every phase's Feature-slice/Atomic-task level draws its record schema from (§7). Capability counts are exact (file-count reconciliation: README + kickoff + capability range + verification + hardening + documentation + closure = the directory's total file count, verified for every row below):

| Parent phase | Directory | README (Epic) | Kickoff (Workstream entry) | Capability/Feature-slice range | Capability count | Verification | Hardening | Documentation | Closure | Entry gate | Exit gate |
|---:|---|---|---|---|---:|---|---|---|---|---|---|
| 0 | `05-phase-00-discovery-foundation` | `PH0-079` | `PH0-080` | `PH0-081..098` | 18 | `PH0-099` | `PH0-100` | `PH0-101` | `PH0-102` | `RUNTIME_ARCHITECTURE_VERIFIED` (this Step 3 package, `16_STEP3_CLOSURE_REPORT.md`, not yet produced) | `PHASE_0_VERIFIED` |
| 1 | `06-phase-01-platform-core` | `PLT-103` | `PLT-104` | `PLT-105..136` | 32 | `PLT-137` | `PLT-138` | `PLT-139` | `PLT-140` | `PHASE_0_VERIFIED` | `PHASE_1_VERIFIED` |
| 2 | `07-phase-02-commercial` | `COM-141` | `COM-142` | `COM-143..161` | 19 | `COM-162` | `COM-163` | `COM-164` | `COM-165` | `PHASE_1_VERIFIED` | `PHASE_2_VERIFIED` |
| 3 | `08-phase-03-operations` | `OPS-166` | `OPS-167` | `OPS-168..184` | 17 | `OPS-185` | `OPS-186` | `OPS-187` | `OPS-188` | `PHASE_2_VERIFIED` | `PHASE_3_VERIFIED` |
| 4 | `09-phase-04-finance` | `FIN-189` | `FIN-190` | `FIN-191..214` | 24 | `FIN-215` | `FIN-216` | `FIN-217` | `FIN-218` | `PHASE_3_VERIFIED` | `PHASE_4_VERIFIED` |
| 5 | `10-phase-05-advanced-tms-wms` | `ATW-219` | `ATW-220` | `ATW-221..244` | 24 | `ATW-245` | `ATW-246` | `ATW-247` | `ATW-248` | `PHASE_4_VERIFIED` | `PHASE_5_VERIFIED` |
| 6 | `11-phase-06-procurement-vendor` | `PRC-249` | `PRC-250` | `PRC-251..267` | 17 | `PRC-268` | `PRC-269` | `PRC-270` | `PRC-271` | `PHASE_5_VERIFIED` | `PHASE_6_VERIFIED` |
| 7 | `12-phase-07-hris-ticketing` | `HRT-272` | `HRT-273` | `HRT-274..293` | 20 | `HRT-294` | `HRT-295` | `HRT-296` | `HRT-297` | `PHASE_6_VERIFIED` | `PHASE_7_VERIFIED` |
| 8 | `13-phase-08-customer-portal-loyalty` | `CPL-298` | `CPL-299` | `CPL-300..323` | 24 | `CPL-324` | `CPL-325` | `CPL-326` | `CPL-327` | `PHASE_7_VERIFIED` | `PHASE_8_VERIFIED` |
| 9 | `14-phase-09-intelligence-enterprise` | `IEP-328` | `IEP-329` | `IEP-330..363` | 34 | `IEP-364` | `IEP-365` | `IEP-366` | `IEP-367` | `PHASE_8_VERIFIED` | `PHASE_9_VERIFIED` |
| 15 | `15-hardening` | `HDN-368` | `HDN-369` | `HDN-370..385` | 16 (audit/hardening capabilities) | `HDN-386` | `HDN-387` (release-blocker triage/remediation — hardening's own hardening step) | `HDN-388` | `HDN-389` | `PHASE_9_VERIFIED` | `FULL_SYSTEM_HARDENING_VERIFIED` |
| 16 | `16-release-go-live` | `RGL-390` | `RGL-391` | `RGL-392..409` | 18 | `RGL-410` | — (release has no separate hardening step; `392..409` already includes defect triage `RGL-394`) | `RGL-411` | `RGL-412` | `FULL_SYSTEM_HARDENING_VERIFIED` | `RELEASE_GO_LIVE_VERIFIED` |
| 17 | `17-final-validation` | `FPV-413` | `FPV-414` | `FPV-415..429` | 15 (package-quality audits, not runtime capabilities) | — (audits are self-verifying) | — | — | `FPV-430` | `RELEASE_GO_LIVE_VERIFIED` (runtime) / package-generation-only for `FINAL_PACKAGE_VALIDATED` | `FINAL_PACKAGE_VALIDATED` (package) — this row validates the *package*, not a runtime phase; it does not gate GA (§13) |

Total capability/feature-slice prompts across Phases 0–9, 15, 16: 18+32+19+17+24+24+17+20+24+34+16+18 = **263**. Plus 15 Step 17 audit prompts (package-quality only, not runtime capabilities) and 25 Step 4 reusable templates (§7) = **303** total non-README/kickoff/verification/hardening/documentation/closure content prompts across the runtime-relevant package. This reconciles exactly against `docs/ai-agent-build-prompt-package/00-control/05_REQUIREMENT_COVERAGE_MATRIX.md`'s per-step "N/N mandatory fields" coverage conclusions (§25 of that file: Steps 2–16 all `PROMPT_COMPLETE`, Step 17 `FINAL_FOR_STEP`) — no new count is invented, this is a reconciliation of an already-stated total.

## 5. Full capability register (worked examples + citation-by-reference)

Reproducing all 263 capability rows' full title/anchor/dependency detail here would duplicate content already authored, versioned, and package-validated in each phase's own README §4 — contrary to §1's citation discipline. Two full worked examples (confirming the pattern is genuinely followed, not merely file-count-consistent) plus the citation rule for the remaining ten phases:

### 5.1 Worked example — Phase 1 Platform Core (`PLT-105..136`, already reproduced verbatim in `01_MODULE_DEPENDENCY_MAP.md` §3.1)

`TEN-IAM` (`PLT-105` tenant → `106` entitlement → `107` Supabase Auth → `108` four-layer access context → `109` org hierarchy → `110` user lifecycle → `111` role/permission → `112` RBAC → `113` RLS → `114` field/record access → `115` support/impersonation → `116` audit) → `WLB` (`117`→`118`→`119`) and `MDM` (`120`) → `CFG` (`121`) → `WF` (`122`) → `APPR` (`123`) → `STAT` (`124`) → `NUM` (`125`) → `FORM` (`126`) → `NOTIF` (`127`) → `DOC` (`128`) → `API-WH` (`129`→`130`) → `IMPEXP` (`131`) → `JOB` (`132`) → `FLAG` (`133`) → `GEO` (`134`) → `PORTAL-ADM` (`135`→`136`) — this is `01_*.md` §3.1's dependency chain, cited by reference (not retyped a third time), and it is itself a direct reproduction of `103_PLATFORM_CORE_README.md` §4.

### 5.2 Worked example — Phase 4 Finance (`FIN-191..214`, read in full for this document)

Dependency order per `189_FINANCE_README.md` §4: Finance configuration (`191`) → Chart of accounts (`192`) → Fiscal period (`193`) → Currency/exchange rate (`194`) → Tax baseline (`195`) → Accounts receivable (`196`) → Invoice (`197`) → Receipt/payment allocation (`198`) → Accounts payable (`199`) → Vendor bill (`200`) → Settlement (`201`) → Subledger (`202`) → Double-entry journal (`203`) → Posted-journal integrity (`204`) → Draft/posted state (`205`) → Reversal/adjustment (`206`) → Period lock (`207`) → Idempotent posting (`208`) → Reconciliation (`209`) → Aging (`210`) → Cash/bank (`211`) → Job/customer/service profitability (`212`) → Finance dashboard/reports (`213`) → Financial field-level security (`214`). Every one of these 24 capabilities is source-cited to one of the six `FIN-GL/AR/AP/TAX/CLS/PRF` anchor families in `00-control/05_REQUIREMENT_COVERAGE_MATRIX.md` §3 — no capability lacks a source requirement family.

### 5.3 Citation rule for the remaining ten phases (2, 3, 5, 6, 7, 8, 9, 15, 16, 17)

Each phase's capability/feature-slice dependency order is **its own README's §4 (or §4-equivalent) table**, reproduced by reference — `07_..14_*.md` READMEs, `368_*.md`, `390_*.md`, `413_*.md` respectively — not retyped here. This is the same reproduce-by-reference discipline `01_*.md` §3.1 already established for Platform Core and this document's §5.2 just confirmed a second time for Finance; introducing a third, independently-typed copy of ~200 remaining capability rows would create exactly the drift risk `10_*.md`/`11_*.md`/`12_*.md` repeatedly warn against ("one X, not two that could silently diverge"). §4's table above is the authoritative ID-range index into every one of those tables; a future runtime agent resolves a specific capability's exact dependency by opening that phase's own README, never by consulting a stale copy in this document.

## 6. Dependency edges

- **Phase-level edges:** `01_MODULE_DEPENDENCY_MAP.md` §3 (module-to-module) and `12_RELEASE_TRAIN.md` §3.1/§9 (phase-to-phase gate sequencing) are the binding phase-level dependency graph — reproduced by reference, not restated.
- **Intra-phase edges:** each phase README's own §4 table (§5 above) — Phase 0's is the most explicit (every row lists exact upstream IDs, e.g. `PH0-087` depends on `PH0-083..086`, per `79_PHASE0_README.md` §4), and every other phase's is at minimum a strict sequential order matching README §4's row order (verified identical to file numeric order in both worked examples, §5.1/§5.2).
- **Cross-phase edges:** `01_*.md` §3.3's business-domain-to-business-domain table is the binding source — e.g. the `COM`→`OPS` edge (quote-to-job) is concretely `COM-154_CUSTOMER_ACCEPTANCE_PROMPT.md`/`COM-155_CUSTOMER_ACCOUNT_CONVERSION_PROMPT.md` (Phase 2's last two capabilities) feeding `OPS-168_JOB_ORDER_PROMPT.md` (Phase 3's first capability) — this document does not invent a new cross-phase edge, it resolves `01_*.md`'s domain-level edges down to the exact file-ID pair at each phase boundary.
- **Cross-cutting edges:** every phase's capability range also depends on the relevant slice of `05_*.md`–`11_*.md`'s atomic backlogs (§7 below) — e.g. every `FIN-*` capability depends on `05_DATABASE_SCHEMA_WORKSTREAM.md` §12's "Finance core" schema slice existing first.

## 7. Cross-cutting workstream coverage

Task #3 requires database, RLS/RBAC, configuration, API/integration/job, UX/design system, testing, performance, security, accessibility, DevOps, migration, documentation, support, and recovery work to be represented. None of this is a *fourteenth* work-item category bolted onto the WBS — it is already interleaved into every capability prompt via two existing mechanisms, both reproduced by reference:

1. **Per-phase binding rules and mandatory evidence** (verified in `189_FINANCE_README.md` §5/§6, structurally present in every phase README): every phase's own README states its RLS/RBAC, tax/SME, audit, retention, and evidence requirements inline, so every capability prompt in that phase's range already carries its cross-cutting obligations without a separate cross-cutting task ID.
2. **Step 4's 25 reusable templates** (`04-reusable-prompts/53`–`77`, the canonical shape every atomic task instantiates, §8 below) each encode one cross-cutting concern as its own template: `54_DATABASE_MIGRATION_TEMPLATE`, `55_RLS_POLICY_TEMPLATE`, `56_RBAC_PERMISSION_TEMPLATE`, `57_UI_PAGE_WORKFLOW_TEMPLATE`, `58_API_ENDPOINT_TEMPLATE`, `59_INTEGRATION_ADAPTER_TEMPLATE`, `60_BACKGROUND_JOB_TEMPLATE`, `61_IMPORT_EXPORT_TEMPLATE`, `62_REPORT_DASHBOARD_TEMPLATE`, `63_FINANCIAL_POSTING_TEMPLATE`, `67_SECURITY_REMEDIATION_TEMPLATE`, `68_PERFORMANCE_OPTIMIZATION_TEMPLATE`, `69_DATA_MIGRATION_TEMPLATE`, `70_RELEASE_PREPARATION_TEMPLATE`, `71_INCIDENT_RESPONSE_TEMPLATE`, `72_ROLLBACK_TEMPLATE`. DevOps/observability/accessibility/support work additionally draws on `11_DEVOPS_WORKSTREAM.md`'s own atomic backlog (§11 of that document) and `09_UX_DESIGN_SYSTEM_WORKSTREAM.md`'s accessibility plan (§9) as the concrete content each relevant capability prompt implements — this WBS indexes that content, it does not duplicate it.

No cross-cutting category in task #3's list lacks a delivery mechanism: database → `54`; RLS/RBAC → `55`/`56`; configuration → every `CFG`-consuming capability (`07_*.md` §7's config-type catalogue); API/integration/job → `58`/`59`/`60`/`61`; UX/design system → `57`, bound to `09_*.md`; testing → every template's own §28/§29 sections (test/regression), bound to `10_*.md`; performance → `68`, bound to `08_*.md` §12/`10_*.md` §8.1; security → `67`, bound to `06_*.md`; accessibility → `57` + `09_*.md` §9; DevOps → `11_*.md` in full; migration → `54`/`69`; documentation → every phase's own Documentation-task ID (§4) plus Template 53 §31; support → Blueprint §30, bound in `11_*.md` §8.4; recovery → `72`, bound to `11_*.md` §4.4/§8.

## 8. Task record schema

Every Feature-slice/Atomic-implementation-task in §4–§5 is instantiated at runtime as **exactly one** of the 25 Step 4 reusable templates (`52_STEP4_REUSABLE_PROMPTS_README.md`'s catalogue) — never a 26th ad hoc template invented per-task. Template 53 (New Feature Slice) is the default schema for a business-capability slice (the majority of §4's 263 capability prompts) and defines the binding 36-field record (`53_NEW_FEATURE_SLICE_TEMPLATE.md`, read in full for this document): Prompt ID, parent phase, workstream, objective, business value, source requirement, current repository context, preconditions, upstream dependencies, downstream impact, allowed files/folders, forbidden files/folders, database/API/UI/security/performance/audit/data-migration impact (7 fields), detailed implementation tasks, main/alternative/exception flow (3 fields), business/validation/access rules (3 fields), test data requirement, tests to create/update, regression tests, commands to run, documentation to update, rollback/recovery note, acceptance criteria, Definition of Done, completion report format, next eligible prompt. This is the exact field set task #4 requires ("objective, source IDs, repository boundary, owner, upstream/downstream IDs, inputs/outputs, allowed/forbidden scope, data/API/UI/security/performance/audit/migration impact, tests, commands, evidence, rollback/recovery, and completion criteria") — verified field-for-field, not approximated.

The remaining 24 templates cover every other task shape a WBS item in §4 can be: `54` migration, `55` RLS policy, `56` RBAC permission, `57` UI page/workflow, `58` API endpoint, `59` integration adapter, `60` background job, `61` import/export, `62` report/dashboard, `63` financial posting, `64` bug fix, `65` regression repair, `66` refactor, `67` security remediation, `68` performance optimization, `69` data migration, `70` release preparation, `71` incident response, `72` rollback, `73` resume-failed-task, `74` resume-interrupted-phase, `75` documentation-only change, `76` UAT-defect correction, `77` hotfix. A Verification/Hardening/Documentation/Closure task (§3's four non-capability levels) is not a Template-53-shaped slice — it is itself a distinct, already-fully-authored prompt file (e.g. `215_FINANCE_INTEGRATED_VERIFICATION_PROMPT.md`), selected by phase position, not by template.

## 9. Atomic sizing enforcement

Template 53 §11 fixes the binding sizing rule verbatim: "normally 5–15 files, one module boundary and at most 1–3 approved migrations" — identical to Step 3 README §5's architecture-task sizing rule already governing this entire Step 3 package. Every phase's capability count (§4) stays within a range (16–34 capabilities per phase) consistent with one bounded feature per prompt, not a bundled multi-feature prompt — spot-verified against the two worked examples: Platform Core's 32 capabilities each map to exactly one of `01_*.md` §2.1's 18 named primitive modules (several primitives, e.g. `TEN-IAM`, span multiple sequential capability prompts — `105`–`116` — precisely because a 12-file-spanning primitive is itself oversized for one prompt and was pre-split at package-generation time); Finance's 24 capabilities each map to exactly one of six `FIN-*` anchor families' four-anchor group or a specific named function (chart of accounts, fiscal period, etc.), never bundling two anchor families into one prompt. No oversized task was found in either worked example; the split protocol for any future discovery of an oversized task is Template 53's own precondition gate (§8 of that template: "stop on tenant, data or finance integrity conflict") escalating to a `BLOCKED` resume prompt (Template 73/74) rather than silently absorbing extra scope.

## 10. Brownfield preservation, migration, retirement

Not applicable, by evidence, not by gap: `docs/discovery/12_GREENFIELD_BROWNFIELD_DECISION.md` confirms `GREENFIELD` at High confidence (zero existing application code, routes, or schema). Task #6's brownfield-preservation instruction therefore has zero qualifying work to schedule in this WBS — every capability in §4 is a net-new build, not a preserve/migrate/retire decision. This section exists to make that absence explicit and evidenced, not silently omitted.

## 11. ADR/legal/SME/contract/evidence gates

Restates — does not reopen — every gate already raised across `01_*.md`–`12_*.md`, mapped to the WBS position where it must resolve:

| Gate | Type | Blocks | Resolve at |
|---|---|---|---|
| `ADR-CAND-ARCH-011..015,017..027` (17 open, non-blocking) | ADR | Nothing in Step 3; each names its own Phase-0/1/3/5 resolution point (`HANDOFF.md` §6) | Named phase's capability range in §4 |
| Tax/legal rate verification (`189_*.md` §5: "PPN/VAT and withholding behavior... must be verified by current legal/finance/tax SMEs before activation") | Legal/SME | `FIN-195` (Tax baseline) activation, and any tenant's Finance go-live | `FIN-195` capability + Finance Go-Live Gate (`10_*.md` §5.3) |
| Payroll/tax SME verification (`00-control/05_*.md` §3, `HRS-PAY-001..004`: `SME_RUNTIME_VERIFICATION_REQUIRED`) | Legal/SME | `HRT-282` (Payroll/benefit/reimbursement) activation | `HRT-282` capability |
| Vendor rate ownership (`ADR-CAND-ARCH-001`, resolved `05_*.md` §4) | ADR (resolved) | Was blocking `COM-149`/`PRC-255` until resolved — now clear | Closed |
| Penetration test (Blueprint §20.3, `10_*.md` §8.2) | Evidence | `RGL-402` (Penetration test evidence), Phase 16 Go/No-Go | `RGL-402` |
| DR rehearsal (`10_*.md` §7.4/§11's `ADR-CAND-ARCH-023`, quarterly cadence) | Evidence | `HDN-384` (Disaster recovery rehearsal) | `HDN-384` |
| Contract-specific RPO/RTO (RPD-031/037) | Contract | Any tenant with a contracted (non-default) recovery target — resolved per-contract, not per-phase | Tenant onboarding (outside this WBS's phase scope) |
| `docs/blueprint/tes.md` deletion | Owner approval | Nothing blocking (classified `CONFIRMED_PLACEHOLDER`, `KNOWN_ISSUES.md`) | Owner decision, any time |

No ratified product decision (RPD-001..040) is reopened by this table — every row either points to an already-resolved ADR or an evidence/SME gate whose *existence*, not resolution, is what this WBS must track.

## 12. Completeness, duplicate, orphan, cycle checks

- **Completeness:** every one of the 194 explicit requirement IDs (`00-control/05_REQUIREMENT_COVERAGE_MATRIX.md` §2) and 13 package-generated gap-requirement IDs (§5 of that document) is `SOURCE_MAPPED`/`GAP_REGISTERED` to exactly one phase and package step (§3 of that document) — cross-checked against §4's phase register above, every phase/step named in the coverage matrix has a corresponding row in §4, and no phase in §4 lacks at least one requirement family mapped to it. Zero requirement families are unmapped.
- **Duplicates:** no capability prompt ID appears in more than one phase's range (§4's ranges are contiguous and non-overlapping by construction — verified arithmetically: each phase's range starts exactly one after the prior phase's closure ID, e.g. `PLT-140` closure → `COM-141` README, no gap or overlap). No canonical master is duplicated across phases (`01_*.md` §11 R3, restated) — the one flagged near-duplicate risk (Commercial's Phase-2 vendor-rate lookup vs. Procurement's Phase-6 full lifecycle) is `ADR-CAND-ARCH-001`, already resolved as a single-owner table with a read-only view, not two masters (§11 above).
- **Orphans:** every capability prompt in §4/§5 traces to at least one requirement-family ID in the coverage matrix (verified by construction — the coverage matrix's §3 table already states each family's "Release owner: Phase N," and §4's ranges are exactly those phases) — no capability prompt exists with no source requirement, and no requirement family exists with no assigned phase/capability range.
- **Cycles:** `01_MODULE_DEPENDENCY_MAP.md` §5 already confirms "no true circular dependency (A→B→A on the same data object) was found" at the module level; this document's phase/capability-level graph (§4/§6) is a strict refinement of that module graph (every phase-to-phase edge in §6 is sourced from `01_*.md` §3.3's already-acyclic edges) and introduces no new edge type that could reintroduce a cycle — R10 of `01_*.md` §11 (phase-order-inversion detection) applies unchanged at this finer granularity, and the two known, tracked exceptions (`HRS`→`APPR`/`OPS`, `PRC`→`COM`) remain the only non-monotonic phase references, both already resolved (`ADR-CAND-ARCH-002`, `ADR-CAND-ARCH-001`).

Result: **zero unresolved duplicates, zero orphans, zero blocking cycles** — the completion gate's "cycles/orphans are zero or blocking" condition is satisfied at zero, not merely "blocking-but-tracked."

## 13. Downstream package/runtime handoff mapping

This WBS is the master index the next three Step 3 prompts and the eventual runtime phase execution both consume:

- **Prompt 49** (`03-architecture-and-plan/49_REQUIREMENT_PHASE_TRACEABILITY_PROMPT.md` → `docs/architecture/14_REQUIREMENT_PHASE_TRACEABILITY.md`) resolves each of §12's requirement-to-capability mappings into a full bidirectional traceability matrix (requirement ↔ business rule ↔ test ↔ capability ID) — this document supplies the capability-ID half of that matrix.
- **Prompt 50** (`50_RISK_RANKED_CRITICAL_PATH_PROMPT.md` → `15_RISK_RANKED_CRITICAL_PATH.md`) ranks §4's phase register and §6's dependency edges by risk, producing the critical path — this document supplies the dependency graph that prompt ranks, it does not itself rank anything.
- **Prompt 51** (`51_STEP3_CLOSURE_VERIFICATION_PROMPT.md` → `16_STEP3_CLOSURE_REPORT.md`) verifies the full Step 3 package (`01_*.md`–`15_*.md`) at one repository checkpoint — this document is one of the 16 inputs that verification checks.
- **Runtime phase execution** (Phase 0 onward, once `RUNTIME_ARCHITECTURE_VERIFIED`): a future runtime agent resolves "what is the next eligible task" by reading §4's phase register, confirming the phase's entry gate, then opening that phase's own README §4 (§5.3's citation rule) to get the exact next capability ID, instantiating it via the matching Step 4 template (§8), and recording it in `TASK_LEDGER.md` using the `CG-WBS-<n>` ID (§2) — this is the exact handoff mechanism task #8 requires ("define the exact handoff into Steps 4–16").

## 14. ADR candidates

None new. This document indexes and cross-references already-existing, already-validated package structure and already-raised architecture ADRs (§11); it introduces no additional open question of its own.

## 15. Exit gates

Every requirement/control has at least one delivery and verification owner (§12's completeness check, zero unmapped families). Every task has dependencies and completion evidence: phase-level and intra-phase dependencies are fixed (§6), and completion evidence is Template 53's own §33/§34/§35 (acceptance criteria, Definition of Done, completion report format), bound once for all 263 capability tasks rather than restated per task. Oversized work is split: §9 confirms no oversized task exists in either worked example, and the split protocol is defined for any future discovery. Cycles/orphans are zero (§12, not merely "blocking-but-tracked"). No implementation is performed (§0, confirmed against `git status`).

## 16. Completion statement

WBS conventions (§2) adopt the package's own numeric file IDs as the stable `CG-WBS-<n>` scheme, with phase short-codes already in use by the package itself — no second ID scheme is introduced. The mandatory 10-level hierarchy (§3) is mapped to the package's own uniform per-phase structure (README → kickoff → capabilities → verification → hardening → documentation → closure), verified identical across two full worked examples (Platform Core, Finance) and structurally reconciled by file-count arithmetic for the remaining ten phases (§4). The complete phase/workstream register (§4) covers Phase 0 through Final Package Validation (263 runtime capability prompts + 15 package-quality audits + 25 Step 4 templates), reconciled exactly against `00-control/05_REQUIREMENT_COVERAGE_MATRIX.md`'s own already-stated totals. Dependency edges (§6) are sourced from `01_*.md`/`12_*.md` at the phase level and each phase's own README at the intra-phase level, never independently re-derived. Cross-cutting workstream coverage (§7) is shown to already be interleaved via per-phase binding rules and the 25 Step 4 templates, not bolted on as a fifteenth category. The task record schema (§8) binds Template 53's 36 fields — verified field-for-field against the prompt's own required-field list — plus 24 sibling templates for every other task shape. Atomic sizing (§9) is enforced by Template 53 §11's rule, spot-verified against both worked examples with zero oversized findings. Brownfield work (§10) is confirmed not applicable by the `GREENFIELD` decision, not silently omitted. ADR/legal/SME/contract/evidence gates (§11) are consolidated without reopening any ratified decision. Completeness/duplicate/orphan/cycle checks (§12) all resolve to zero unresolved findings. The downstream handoff into Prompts 49–51 and eventual runtime phase execution (§13) is explicit.

Next eligible prompt: `03-architecture-and-plan/49_REQUIREMENT_PHASE_TRACEABILITY_PROMPT.md` → `docs/architecture/14_REQUIREMENT_PHASE_TRACEABILITY.md`.
