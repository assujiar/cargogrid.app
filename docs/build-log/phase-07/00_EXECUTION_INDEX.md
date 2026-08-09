# Phase 7 (HRIS and Ticketing) — Execution Index

**Prompt:** `CG-S12-HRT-001` (273, HRIS and Ticketing WBS Runtime Kickoff)
**Runtime output of:** `273_HRIS_TICKETING_WBS_RUNTIME_KICKOFF_PROMPT.md`
**Runtime state set by this checkpoint:** `PHASE_7_IN_PROGRESS`
**Runtime state NOT set by this checkpoint:** `PHASE_7_VERIFIED` — reserved exclusively for Prompt 297 (`CG-S12-HRT-025`, Closure Verification), per `273_*.md` §"Required output" and `272_HRIS_TICKETING_README.md` §10.
**Owner (every row, this build's standing convention):** Claude Code (runtime build agent)

---

## 1. Checkpoint

| Field | Value |
|---|---|
| Repository root | `/home/user/cargogrid.app` |
| Branch | `claude/lanjut-271-275-f4mz9a` |
| HEAD commit | `408b741c59acf16f3df15dc44e53f60018f2740d` (2026-08-09 06:32:19 +0000) |
| Worktree | clean at time of this checkpoint's own read pass (no uncommitted changes observed to any tracked source file) |
| Checkpoint timestamp | 2026-08-09T07:08:47Z |
| Migrations applied (count) | 182 files under `supabase/migrations/`, latest `20260730820000_harden_procurement_c05_tenant_disclosure_sweep_batch5.sql` |
| `docs/build-log/phase-07/` | Did not exist before this checkpoint (`ls` confirmed `ENOENT`) — this file is the phase's first artifact |
| Phase 0–6 status | `PHASE_0_VERIFIED` through `PHASE_6_VERIFIED` all set; `PHASE_6_VERIFIED` most recently closed this session (`docs/build-log/phase-06/PROCUREMENT_VENDOR_CLOSURE_REPORT.md`) |
| Standing quality baseline (cited, not re-run this checkpoint per orchestrating instruction) | typecheck 0 errors; lint 0 errors / 175 warnings; `pnpm run test` 3428/3428 passing; `next build` clean; `pnpm run db:test` ALL PASSED across 150 files; `security:audit` PASS; `standards:check`/`docs:check`/`data-classification:check`/`security:check` all PASS |
| Domain code footprint for Phase 7's own subject matter | `git ls-files app/ lib/ server/ components/ supabase/migrations/ | grep -iE 'hris|employee|ticketing|ticket'` → **zero matches**, independently re-run this checkpoint. Phase 7 is genuinely greenfield. |

---

## 2. Runtime entry verdict — **PASS**

Prompt 273's mandatory entry gate requires `RUNTIME_DISCOVERY_VERIFIED`, `RUNTIME_ARCHITECTURE_VERIFIED`, and `PHASE_0_VERIFIED` through `PHASE_6_VERIFIED` at the same checkpoint, or the task must stop and write `PHASE_7_BLOCKED`.

- `PHASE_0_VERIFIED` … `PHASE_5_VERIFIED`: standing, established at their own respective phase closures (Phases 0–5 all closed prior to this session).
- `PHASE_6_VERIFIED`: set this session (`docs/build-log/phase-06/PROCUREMENT_VENDOR_CLOSURE_REPORT.md`), independently re-confirmed as the most recent phase closure before this kickoff ran.
- `RUNTIME_DISCOVERY_VERIFIED` / `RUNTIME_ARCHITECTURE_VERIFIED`: standing from Step 3 (Prompts 40–41) closure, re-affirmed by every intervening phase's own entry gate (Phases 1–6 each required and passed the identical check before proceeding).
- No unresolved `PHASE_7_BLOCKED`-triggering condition was found.

**Verdict: entry gate PASSES.** `PHASE_7_IN_PROGRESS` is set by this checkpoint (§13 below). `PHASE_7_VERIFIED` is explicitly **not** set — only Prompt 297 may set it.

---

## 3. Ownership/ADR map (10 required reconciliation items, `273_*.md` §"Required ownership reconciliation")

| # | Item | Verdict | Basis |
|---|---|---|---|
| 1 | Platform identity vs. HR employee profile ownership; tenant/company/branch/department/team/position/reporting-line scope | **RESOLVED — ADR-0023 Part A (team) + Part B (employee identity)** | `docs/adr/ADR-0023-phase7-hris-organization-team-and-employee-identity-reconciliation.md`. Part A: `app.org_units.unit_type` gains an additive fifth value, `team` — a genuine, load-bearing gap between the live schema (`supabase/migrations/20260716101726_create_org_units.sql:33-34`, four values only) and Prompt 275's own binding text (§13, §24) naming `team` as canonical. Part B: employee identity is ratified as a required, non-duplicating extension of `app.users` (formalizing the already-unanimous, 9-document architecture record at `ADR-CAND-ARCH-002`, never before promoted to a ratified ADR file). The narrower question of whether Employee *also* registers a `master_type_code='employee'` row (mirroring `driver`/`vendor`) is deliberately left open for Prompt 274's own checkpoint — recommended, not forced. |
| 2 | Effective-dated employment/organization/position/manager links without duplicating Platform organization truth | **RESOLVED by ADR-0023 Part A** — Prompt 275's own migration widens `org_units`/`enforce_org_unit_parent_shape` additively; position/grade/assignment tables reference `app.org_units` and `app.master_records`(employee) directly, no second hierarchy table. |
| 3 | Candidate/recruitment identity, document and user-account conversion ownership | **CLEAR, no ADR needed.** `276_RECRUITMENT_ATS_PROMPT.md:60,108` already binds candidate/application identity as purpose-bound and separate from Platform user/employee identity until an explicit, governed onboarding conversion (Prompt 277). Candidate data never touches `org_units`, position, or `master_records` before conversion. |
| 4 | Operations fleet/driver/vendor/assignment identities vs. workforce references | **CLEAR, no conflict.** `app.driver_operational_profiles` (`supabase/migrations/20260729310000_create_advanced_tms_fleet_driver_device.sql:93-111`, read in full) is a pure operational layer over `driver_master_id → app.master_records(id)`, no employee/user FK exists or is implied. A future employee-as-driver linkage is fully additive (a link table or a nullable column later); not designed here, correctly out of this kickoff's scope. |
| 5 | Finance ownership of journal/period/bank-cash/payment/settlement/reconciliation vs. HR payroll calculation/handoff | **CLEAR, established boundary.** `docs/build-log/phase-04/FINANCE_HANDOFF_PACKAGE.md` §2.1/§3 documents Finance's complete, `VERIFIED` posting/journal/AP/AR/settlement ownership and the "approved handoff, never direct posting" pattern (e.g. `app.prepare_finance_vendor_bill_from_actual_cost`). `272_HRIS_TICKETING_README.md:73` states the identical rule for HRIS verbatim. Prompt 282 (Payroll) must follow the same `prepare_finance_*_from_*` handoff shape, never invent a new one. |
| 6 | Canonical customer/shipment/invoice/warehouse/vendor/user records for typed ticket links | **CLEAR, all six exist and VERIFIED.** `app.shipment_orders` (`20260727100000_create_operations_shipment_order.sql`); `app.finance_invoices` (`20260729110000_create_finance_invoice.sql`); `app.warehouses` (`20260730140000_create_advanced_tms_warehouse_zone.sql:82`); `app.vendor_profiles` (`20260730580000_create_procurement_vendor_registration.sql`); `app.users` (`20260716102620_create_users.sql`); `app.master_records` (`20260717120000_create_master_data.sql`). Prompt 292's typed ticket-link table may reference all six directly. |
| 7 | Four principal/access layers for employee, customer, CargoGrid support sessions; no fifth layer | **CLEAR, confirmed closed.** `app.principal_memberships.layer` CHECK (`supabase/migrations/20260716100825_create_principal_memberships.sql:36-37`) is closed at exactly `supreme_admin`/`tenant_admin`/`org_user`/`customer_user`; header comment states "deliberately closed." CargoGrid support access is a separate, time-bound grant mechanism (`app.support_access_grants`, `20260716111315_create_support_access.sql`), not a fifth layer. HRIS employees are `org_user` (Layer 3) principals, per ADR-0023 Part B. |
| 8 | Shared workflow/approval/numbering/config-version/notification/file-scan/audit/import-export/job primitives — confirm reusable, not rebuilt | **CLEAR, all confirmed live and reused, not rebuilt.** PLT-123 Approval Engine (`20260719090000_create_approval_engine.sql`); PLT-128 File/Document Engine (`20260719140000_create_document_file_engine.sql`); PLT-131 Import/Export (`20260719170000_create_import_export_job_framework.sql`); PLT-132 Background Job Framework (`20260719180000_create_background_job_framework.sql`); RPD-040 config-version pattern (`00-control/03_ASSUMPTION_REGISTER.md:10`, `04_CONFLICT_REGISTER.md:23`). 40+ later migrations already cite these by name rather than rebuilding parallel primitives. |
| 9 | Current dated Indonesia payroll/statutory SME activation evidence under RPD-016 | **CONFIRMED ABSENT — correctly deferred, not blocking.** No dated sign-off artifact exists anywhere (`docs/build-log/phase-07/` did not exist before this checkpoint; repository-wide search for SME/statutory-activation evidence found only forward-looking disclaimers). RPD-016 (`00-control/02_CONFIRMED_DECISION_REGISTER.md:92`) gates *activation* of specific statutory rules at Prompt 282 (Payroll), not schema-foundation work at 274/275. Not a blocker for this kickoff or for Prompts 274/275. |
| 10 | RPD-022/023/025/032/033/040 contracts and unresolved critical/high issues | **CLEAR on both halves.** All six RPD contracts are pre-existing, ratified rows in `00-control/02_CONFIRMED_DECISION_REGISTER.md` (lines 92–109) and `04_CONFLICT_REGISTER.md:23`, already reused verbatim across Phases 1–6. **Unresolved critical/high issues: zero**, independently re-verified this checkpoint by column-aware parsing of `docs/runtime/KNOWN_ISSUES.md`'s Severity/Status fields (not a bare substring grep, which produces false positives against this file's narrative prose — see §8 below for the exact method and result). |

**ADR filed this checkpoint:** `docs/adr/ADR-0023-phase7-hris-organization-team-and-employee-identity-reconciliation.md` (Status: ACCEPTED). No other item rose to a genuine, blocking ownership ambiguity requiring a new ADR — items 3–10 above are resolved by direct citation to already-existing, already-ratified repository evidence.

---

## 4. Required hierarchy — Phase → Workstream → Epic → Capability → Task

Phase 7 decomposes into the 10 workstreams `273_*.md` §"Required workstreams" names at minimum, each containing one or more of Prompts 274–297 as its capability-level epics. No capability appears in more than one workstream; no workstream is empty.

| Workstream (epic) | Capabilities (Prompt / `CG-S12-HRT-NNN`) | Count |
|---|---|---|
| 1. Workforce Master and Lifecycle | 274 (`-002`, Employee master), 275 (`-003`, Organization and position linkage) | 2 |
| 2. Recruitment and Workforce Entry/Exit | 276 (`-004`, Recruitment/ATS), 277 (`-005`, Onboarding/offboarding) | 2 |
| 3. Time, Attendance and Scheduling | 278 (`-006`, Attendance), 279 (`-007`, Shift/roster), 280 (`-008`, Leave/permit/business trip), 281 (`-009`, Overtime/timesheet) | 4 |
| 4. Payroll, Benefit and Reimbursement | 282 (`-010`, Payroll foundation/benefit/reimbursement) | 1 |
| 5. Performance, Learning and Talent | 283 (`-011`, KPI/performance), 284 (`-012`, Training/talent) | 2 |
| 6. Employee and Manager Self-Service | 285 (`-013`, ESS/MSS) | 1 |
| 7. Ticket Channels and Conversation | 286 (`-014`, Internal ticket), 287 (`-015`, Customer ticket), 288 (`-016`, CargoGrid helpdesk) | 3 |
| 8. SLA, Assignment, Escalation and Knowledge | 289 (`-017`, SLA/KB), 290 (`-018`, Assignment), 291 (`-019`, Escalation), 292 (`-020`, Typed linked records) | 4 |
| 9. HR/Ticket Privacy, Files, API and Jobs | 293 (`-021`, Sensitive personal/payroll data controls) | 1 |
| 10. Integrated Verification, Hardening, Documentation and Closure | 294 (`-022`), 295 (`-023`), 296 (`-024`), 297 (`-025`) | 4 |

**Total: 24 capabilities = exactly Prompts 274–297**, zero overlap, zero unassigned. Prompt 273 (this kickoff) sits above all 10 workstreams as the WBS root that creates them and is not itself a member of any workstream.

Each of the 24 capability prompts is, per `273_*.md` §"Required hierarchy and task contract", to be instantiated as one or more **atomic tasks** carrying unique WBS/task/prompt IDs, exact source anchors, exact prerequisite IDs, exact allowed/forbidden paths, normally 5–15 changed files and at most 1–3 additive migrations, and a runtime log path under `docs/build-log/phase-07/`. **No atomic task has been instantiated yet** — this kickoff creates the WBS structure and releases the first eligible prompt; the atomic-task-level split (e.g. whether Prompt 282's Payroll capability splits into "payroll calculation engine" / "benefit" / "reimbursement" sub-tasks) is each capability's own job at its own checkpoint, per Prompt 273 §"Required hierarchy": *"Split a capability prompt into smaller atomic tasks when file, migration, risk, approval or independent-test boundaries require it."*

---

## 5. Dependency graph

The declared "Upstream dependencies" (§9) of every one of Prompts 274–297 cite only strictly lower-numbered `HRT-` IDs — the graph is a DAG by construction, no cycle is possible. It is **not one single linear chain**, despite the README's order-table numbering (1–24) implying one. It is **two independent linear sub-chains that reconverge at HRT-293**:

```
HRT-273 (kickoff)
   │
   ├──► Workforce/HR track (12 capabilities, strictly sequential)
   │    HRT-274 → 275 → 276 → 277 → 278 → 279 → 280 → 281 → 282 → 283 → 284 → 285
   │
   └──► Ticket track (7 capabilities, strictly sequential, independent of the HR track)
        HRT-286 → 287 → 288 → 289 → 290 → 291 → 292
                                                    │
        HR track (…285) ───────────────────────────┤
                                                    ▼
                                          HRT-293 (Sensitive HR/Payroll Data
                                          Controls — upstream = "HRT-274..292",
                                          the sole convergence point)
                                                    │
                                                    ▼
                              HRT-294 → 295 → 296 → 297 (closure track, serial)
```

`HRT-286`'s own §9 reads "HRT-273; Platform user/org/workflow/file/notification/job foundations and verified canonical linked records" — it does **not** cite HRT-274 or any HR-track prompt. This matches `272_HRIS_TICKETING_README.md` §7's own architecture note that internal ticket assignees resolve through Platform Layer-3 user identity, not the not-yet-built Employee Master table.

**Practical implication, disclosed but not acted on by this checkpoint:** `HRT-286` is structurally dependency-clean on the same terms as `HRT-274` (both have upstream = `HRT-273` only, now `COMPLETED`, plus already-`VERIFIED` Platform/canonical-record primitives). Per `273_*.md` §"Execution-index rules" ("Independent tasks may run concurrently only when their file, migration, contract, data and evidence surfaces do not overlap"), `HRT-286` is a **candidate for concurrent release** alongside `HRT-274` at a future checkpoint. This index does not release it now (see §10, task state) because no concrete allowed-file path list exists yet for either track to check for overlap — no atomic task has run to produce one. §7 (collision matrix) records this as a re-evaluation trigger, not a current blocker in substance.

**Minor open item, disclosed:** `290_TICKET_ASSIGNMENT_PROMPT.md` §9 prose reads "HRT-286..289; effective user/employee/team/queue and SLA contracts" — the word "employee" appears even though its declared upstream ID range (286–289) never cites HRT-274. Cross-checked against `272_*.md` §7 ("Assignment uses eligible queue/team/user scope... without duplicating employee, user, vendor or customer identity"), this reads as generic prose, not a real hidden dependency on the Employee Master table — flagged here for the future HRT-290 checkpoint to confirm explicitly rather than assume.

---

## 6. 20-capability × 40-anchor traceability

All 24 anchors in the six HRS families and all 16 anchors in the four TKT families have at least one owning capability assigned in the WBS below. **"Covered" here means every anchor has a named owning capability prompt in this WBS — it does not mean built or verified; Phase 7 is greenfield (§1).** Cross-verified two ways that agree: the `272_*.md` §4 order table, and the independently-authored `docs/architecture/14_REQUIREMENT_PHASE_TRACEABILITY.md` §5.6–5.7.

| Anchor family | Owning capability(ies) | WBS status | Disclosed gate/gap |
|---|---|---|---|
| `HRS-EMP-001..004` | HRT-274, 275 | WBS-assigned | ADR-0023 (both Parts) now removes the ownership ambiguity blocking design |
| `HRS-REC-001..004` | HRT-276, 277 | WBS-assigned | none |
| `HRS-ATT-001..004` | HRT-278, 279, 280, 281 | WBS-assigned | none |
| `HRS-PAY-001..004` | HRT-282 | WBS-assigned | **EXTERNAL_VERIFICATION pending** — RPD-016 dated Indonesia payroll SME sign-off (item 9 above); HRT-282 itself must gate activation of statutory rules on this evidence when it runs. Not a blocker for 274/275. |
| `HRS-KPI-001..004` | HRT-283, 284 | WBS-assigned | none |
| `HRS-ESS-001..004` | HRT-285 (secondary touch at HRT-277 for offboarding access revocation) | WBS-assigned | none |
| `TKT-INT-001..004` | HRT-286 | WBS-assigned | none |
| `TKT-CUS-001..004` | HRT-286..288 (domain/API core) | WBS-assigned | full Customer Portal account-management/dashboard depth is Step 13 (`CPL-311..315`), explicitly out of Phase 7 scope per `273_*.md` §"Preserve these boundaries" |
| `TKT-HLP-001..004` | HRT-286..288 (domain) | WBS-assigned | **PARTIAL_BLOCKED for one release-depth item** — Phase-16 release-support-documentation depth (`RGL-411`) is out of Phase 7 scope; the Phase-7 domain/API surface itself is not blocked |
| `TKT-SLA-001..004` | HRT-289, 290, 291, 292 | WBS-assigned | none |

No anchor family is `NOT_COVERED`. The two disclosed gates (`HRS-PAY` external-verification, `TKT-HLP` partial-block) are both pre-existing, named in the source package itself, and non-blocking for every task this index releases or holds at this checkpoint.

---

## 7. File/migration/contract collision matrix

**Trivially clean — greenfield.** Independently re-confirmed this checkpoint: `git ls-files app/ lib/ server/ components/ supabase/migrations/ | grep -iE 'hris|employee|ticketing|ticket'` returns **zero matches**. No Phase 7 file, migration, table, RPC, or REST/GraphQL contract exists anywhere in the repository to collide with. The two files this kickoff itself writes (`docs/adr/ADR-0023-*.md`, `docs/build-log/phase-07/00_EXECUTION_INDEX.md`) do not collide with any existing path.

No collision matrix entry is therefore populated with a real conflict at this checkpoint. The matrix becomes load-bearing starting at whichever capability(ies) this index next releases into an atomic task with concrete allowed-file paths (§10) — that task's own build-log entry must populate this matrix for real before any second, concurrently-running task is released, per §5's disclosed HR/Ticket-track concurrency candidacy.

---

## 8. Baseline/gate matrix

Gate commands independently verified live at this repository (not assumed) unless marked otherwise. Standing baseline figures (typecheck/lint/test/db:test/build/security:audit/standards/docs/data-classification/security-check) are cited per the orchestrating instruction as already fresh this session, not re-run.

| Gate category | Status | Command / mechanism |
|---|---|---|
| Clean install | Real | `pnpm install --frozen-lockfile` (`.github/workflows/ci.yml:79-80,190-191`) |
| Phase 6→7 upgrade | Real, indirect | No dedicated snapshot-upgrade rehearsal exists. `scripts/db-tests/run.sh` applies all 182 migrations to a fresh disposable database in one sequential pass — the closest real analogue; Phase 7 inherits it automatically once its own migrations exist. |
| Generated types | **GAP — no repository precedent.** | Repo-wide grep for `supabase gen types` / `database.types.ts` / `gen:types`: zero hits. This codebase uses hand-written Zod contracts (`server/contracts/<domain>/`) instead of DB-generated types. Disclosed as a genuine absence, not assumed handled. |
| typecheck | Real | `pnpm run typecheck` → `tsc --noEmit` |
| lint | Real | `pnpm run lint` → `eslint .` |
| unit/integration | Real | `pnpm run test` → `node --experimental-strip-types --test` over `scripts/**/*.test.ts server/**/*.test.ts lib/**/*.test.ts tests/**/*.test.ts` |
| database | Real | `pnpm run db:test` → `scripts/db-tests/run.sh`, fresh disposable Postgres, all migrations + all `*.sql` RLS/RBAC tests |
| build | Real, unscripted | `next build` run directly — confirmed no `build` script exists in `package.json`; build-status log entries phrase it identically ("next build clean, N routes present") |
| API/contract (REST/GraphQL parity, RPD-033) | Real pattern | `server/contracts/<domain>/<domain>.ts` shared Zod modules consumed by both REST (`app/api/`) and GraphQL. Phase 7 should add `server/contracts/employee/`, `server/contracts/ticket/`, etc. in the same shape. |
| Browser/accessibility | Real, beyond smoke | `pnpm run test:e2e` (Playwright + `@axe-core/playwright`) — `e2e/smoke.spec.ts` plus three real-page specs (`vendor-registration`, `tenant-admin-portal`, `supreme-admin-portal`). No Phase-7-specific spec exists yet (correctly `NOT_RUN` until a real UI ships at Prompt 285/286+); the one-spec-per-first-real-page pattern is proven twice and should be followed. |
| Target-volume performance | Real, but manual/uncoupled from CI | `scripts/load-tests/run.sh` (`CG-S10-ATW-024`) — pgbench scenarios + a Node GPS-load scenario + `pagination-explain.sh`; not wired into `package.json`/CI. Phase 7 should add its own scenarios here (e.g. ticket-assignment-claim, payroll-run volume) rather than build a second harness. |
| Tenant/company/branch/department isolation | Real, universal | Every `scripts/db-tests/*.sql` file follows the mandatory "two tenants, prove cross-tenant isolation" shape (`docs/standards/TESTING_STANDARDS.md` §8). Phase 7's own db-test files must follow the identical convention. |
| Employee/customer/support isolation (four-layer model) | **GAP for employee/support specifically.** | Zero HRIS code exists (§1). The four-layer model itself is real (`app.principal_memberships`, `app.support_access_grants`) but has no employee- or ticket-specific enforcement code yet to gate. |
| Field-level isolation/masking (payroll, bank, tax, personal) | Real, extendable precedent | `scripts/data-classification/registry.ts`'s `FINANCE_REGISTRY` (FIN-214) + `pnpm run data-classification:check`. Explicitly designed to be extended per-domain — Phase 7 should add an `HRS_REGISTRY` following the identical shape. |
| Effective-date/lifecycle concurrency | Real, hardened precedent — adopt the fixed shape from day one | `record_version` + `BEFORE UPDATE` trigger, **row-locked** (`SELECT ... FOR UPDATE`) per `supabase/migrations/20260730480000_harden_optimistic_concurrency_row_lock.sql`, which fixed a genuine lost-update race across 64 paths repository-wide. Phase 7 must not repeat the original defective (unlocked) shape. |
| Ticket channel/requester/watcher/assignee/note/file/link isolation | **GAP — no precedent, correctly future work.** | Zero ticketing schema/RLS anywhere. Prompts 286–292 must each add their own `db-tests/*.sql` isolation proofs. |
| Payroll decimals/config-formula snapshots/correction-finalization/Finance-handoff reconciliation | Real, analogous Finance precedent to generalize (not literally reusable) | FIN-208 idempotency-claim-ledger (`20260729220000_create_finance_idempotent_posting.sql`) + FIN-209 tolerance/exception/certification reconciliation pattern. Also disclose: `app.enqueue_job`'s (PLT-132) idempotency replay matches the key but never verifies the target tuple (`ISS-2026-053`, OPEN, Low) — Phase 7 inherits this the moment it uses `app.enqueue_job` for payroll-run jobs. |
| Deterministic timezone/workday/shift/leave/overtime calculations | No literal Phase 5 precedent (Phase 5 is dispatch/warehouse timing, not workforce scheduling) — closest lesson is a Phase 6 defect | `ISS-2026-059` (OPEN, Low): `app._calc_vendor_kpi_rate_validity` (PRC-264) silently collapses a calendar-day window to zero rows when its own date arithmetic crosses a UTC day boundary in the 00:00–03:59 UTC band. Direct, load-bearing lesson for `HRS-ATT-US-001`: test day-boundary math across UTC midnight, not only convenient wall-clock hours. |
| SLA clock/pause/calendar/version, assignment/escalation retry, notification idempotency | **GAP — no ticket-specific precedent.** | `app.notification_engine` (PLT-128... correction: Phase 1, `20260719130000_create_notification_engine.sql`) exists as the reusable send mechanism; the FIN-208 claim-ledger shape is the pattern to generalize. No SLA-clock/escalation-specific idempotency exists yet — explicitly Prompts 289/291's own gate to add. |
| Upload malware scan, quarantine, signed URL, access log | Real, exact, proven-reusable | `app.files`/`app.file_access_logs` (PLT-128, `20260719140000_create_document_file_engine.sql`); `malware_scan_status` CHECK + `app.authorize_file_access()` true quarantine (RPD-032). Already extended (never forked) by PRC-253 for vendor documents. Phase 7 must extend the same table for employee/candidate documents, ticket attachments, and payslips. |
| Import/payroll/report/SLA job retry, cancellation, DLQ, reconciliation | Real, exact, proven-reusable, four prior adopters | PLT-131 (`20260719170000_create_import_export_job_framework.sql`) + PLT-132 (`20260719180000_create_background_job_framework.sql`), already reused verbatim by Commercial/Finance/Operations/Procurement. Phase 7 must be the fifth adopter. The `app.enqueue_job` idempotency gap noted above applies here too. |
| RPD-022 residual-risk disclosure / later-phase scope audit | Real, standing discipline + a repeatable command | `AGENTS.md` / `docs/standards/SECURITY_STANDARDS.md` §6 restate RPD-022 at every closure. The scope-audit command (`grep -rniE "hris|employee_profile|ticketing" app server supabase/migrations`) was run at Phase 6 closure (3 hits, all pre-existing Phase-1 labels) and independently re-run this checkpoint (0 hits under a slightly broader glob, §1) — Phase 7's own closure (Prompt 297) must run the mirror-image command for Step 13/14 terms. |
| Unresolved critical/high issues (item 10) | **Zero**, verified by column-aware parsing | A bare `grep -n "OPEN" ... | grep -iE "critical|high"` over `docs/runtime/KNOWN_ISSUES.md` produces false positives (the file's narrative prose contains phrases like "still `OPEN`" and "High → Medium" inside otherwise-`RESOLVED` rows). This checkpoint instead parsed the Severity/Status *table columns* directly (`awk -F'|'`) across all 63 issue records (`ISS-2026-001` through `063`, spanning both the §3 index table and the §4 prose records): **zero rows have Status exactly `` `OPEN` `` combined with a Critical/High severity.** All currently-`OPEN` rows are Medium, Low-Medium, or Low; every High-severity row found is `RESOLVED`. |

---

## 9. Critical path

The HR track (12 capabilities, `HRT-274..285`) is longer than the Ticket track (7 capabilities, `HRT-286..292`); both must complete before the sole convergence point, `HRT-293`. The critical path is therefore:

```
273 → 274 → 275 → 276 → 277 → 278 → 279 → 280 → 281 → 282 → 283 → 284 → 285 → 293 → 294 → 295 → 296 → 297
```

18 nodes (kickoff + 12 HR-track capabilities + convergence + 4 closure capabilities). The Ticket track (286–292) is not on the critical path in isolation, but `293` cannot start until **both** tracks reach `VERIFIED` — so a delay on either track delays `293` equally; only the HR track's greater length makes it the nominal "critical" path under normal (non-delayed) conditions.

---

## 10. Task state (all 25 rows; vocabulary restricted to `273_*.md`'s own set)

| Prompt | ID | Capability | State | Basis / blocked-on |
|---|---|---|---|---|
| 273 | `CG-S12-HRT-001` | HRIS/Ticketing WBS Runtime Kickoff (this task) | **VERIFIED** | Entry gate passed (§2); required ownership reconciliation performed (§3); ADR-0023 filed; this execution index is the required runtime output; `PHASE_7_IN_PROGRESS` set (§13). Self-closes on writing this index, per this build's standing convention (mirrors `CG-S11-PRC-001`/Prompt 250's own `VERIFIED` closure) — independently re-verified by the orchestrating session (`docs:check` clean, ADR file read in full and confirmed well-formed) before commit. |
| 274 | `CG-S12-HRT-002` | Employee master | **VERIFIED** | Implementation complete: `app.employees` (governed 1:1 extension of `app.master_records`, `master_type_code='employee'`, ADR-0023 Part B), a full lifecycle state machine (`draft→submitted→approved→active↔on_leave↔suspended→terminated→archived`, reject-to-draft -- point-in-time only, NOT effective-dated at the employee/HR-event level, see `ISS-2026-065`), RLS/RBAC, field masking (RLS-row-scoped AND column-privilege-scoped, see the review-round fix below), staged import (fifth-plus PLT-131/132 domain-write adapter, RPC + service layer, no UI yet), own-profile change-request flow, contracts/queries/mutations, UI (directory/detail/own-profile), `scripts/db-tests/hris-employee-master.sql` (27 assertion blocks). A subsequent same-checkpoint adversarial review round (3 lenses) found and this checkpoint fixed 2 CRITICAL, 1 MEDIUM, 3 HIGH, and 2 LOW defects (raw-table PII exposure bypassing RPC masking; unmasked PII copied into `app.audit_logs`; version-before-authority disclosure ordering on emergency-contact writes; idempotency-key replay comparing only `full_name`; missing org-unit-status enforcement; missing staged-import TS service wrapper; friendly duplicate-employee-number error; `reactivate_employee` losing `on_leave` state) -- full detail in `docs/build-log/phase-07/HRT-274.md` §11. All gates re-run and green (`typecheck`/`lint`/`test` 3473/3473/`db:test` ALL PASSED (150 files)/`next build`/`standards`/`docs`/`security:check`/`security:audit`/`threat-model:check`/`data-classification:check`). See `docs/build-log/phase-07/HRT-274.md`. Residual gaps disclosed as `ISS-2026-064` (Low) and `ISS-2026-065` (High, effective-dating). **`VERIFIED` set by the orchestrating session**: independently re-ran the full fresh gate suite (typecheck/lint/test/db:test/next build/security:audit/standards/docs/data-classification/security:check), every number matching the fix agent's own claim exactly; directly read the migration's grants section and confirmed the column-restricted `grant select (...) on app.employees/employee_emergency_contacts/employee_change_requests to authenticated` genuinely excludes every classified PII column; directly confirmed `app.employee_audit_projection(v_employee)` (not raw `to_jsonb`) is what every `capture_audit_event` call site actually passes. |
| 275 | `CG-S12-HRT-003` | Organization and position linkage | **VERIFIED** | Implementation complete: ADR-0023 Part A implemented exactly as decided (`org_units.unit_type` widened to add `team`, `enforce_org_unit_parent_shape()` widened with the leaf-type guard); `app.position_grades`/`app.positions` (HR-governed, tenant-scoped catalogue, deliberately not routed through `app.master_records`); `app.employee_position_assignments` (effective-dated, two real `btree_gist` EXCLUDE constraints for overlap, position-scoped advisory-locked capacity enforcement at approval time); `app.employees.position_id` (additive current-pointer column, `position_title` unchanged); a two-step propose (HRS:Edit)/decide (HRS:Approve) assignment workflow with zero new `app.permissions` rows; a real, non-fabricated impact-preview RPC; hierarchy reads reusing `app.assert_no_employee_manager_cycle` unchanged (HRT-274's own disclosed placeholder, formalized without a materialized closure table, reasoning in `HRT-275.md` §3.7); contracts/queries/mutations, UI (position/grade catalogue, organization-linked position tree, assignment timeline + transfer/promotion/reorg wizard with impact preview), `scripts/db-tests/hris-organization-position-linkage.sql` (17 assertion blocks). 2 real defects found and fixed during this checkpoint's own db-testing (a capacity double-count on same-position corrections; a bare-column-reference ambiguity bug in `get_employee_manager_chain`, the same class HRT-274 already found in three other functions) — full detail `docs/build-log/phase-07/HRT-275.md` §6. All gates re-run and green (`typecheck`/`lint` 0 errors, 185 warnings (185 vs. 180 baseline is pre-existing `no-html-link-for-pages` noise scaling with new route count, zero findings in this checkpoint's own files, independently confirmed)/`test` 3509/3509/`db:test` ALL PASSED (151 files)/`next build` (4 new routes)/`standards`/`docs`/`security:check`/`security:audit`/`threat-model:check`/`data-classification:check`). See `docs/build-log/phase-07/HRT-275.md`. Residual gaps disclosed as `ISS-2026-066` (Low) and an update note on `ISS-2026-065` (HRT-274's own gap, unaffected by this checkpoint — see `HRT-275.md` §3.10). |
| 276 | `CG-S12-HRT-004` | Recruitment, job portal and ATS | **READY** | Upstream: `HRT-275`, now `VERIFIED` (see row above). No additional ownership/security/privacy conflict disclosed against this row's own stated scope. |
| 277 | `CG-S12-HRT-005` | Onboarding and offboarding | **BLOCKED** | Upstream: `HRT-274..276`, not all `VERIFIED`. |
| 278 | `CG-S12-HRT-006` | Attendance | **BLOCKED** | Upstream: `HRT-274..277`, not all `VERIFIED`. |
| 279 | `CG-S12-HRT-007` | Shift, roster and scheduling | **BLOCKED** | Upstream: `HRT-274..278`, not all `VERIFIED`. |
| 280 | `CG-S12-HRT-008` | Leave, permit and business trip | **BLOCKED** | Upstream: `HRT-274..279`, not all `VERIFIED`. |
| 281 | `CG-S12-HRT-009` | Overtime and timesheet | **BLOCKED** | Upstream: `HRT-274..280`, not all `VERIFIED`. |
| 282 | `CG-S12-HRT-010` | Payroll foundation, benefit and reimbursement | **BLOCKED** | Upstream: `HRT-274..281` + verified Finance posting/period/payment contracts (Finance side already `VERIFIED`; HR-track side is not). Also gated at its own future checkpoint by RPD-016 dated SME evidence (§3 item 9, §6 `HRS-PAY`) before statutory rules may activate. |
| 283 | `CG-S12-HRT-011` | KPI and performance | **BLOCKED** | Upstream: `HRT-274..282`, not all `VERIFIED`. |
| 284 | `CG-S12-HRT-012` | Training and talent | **BLOCKED** | Upstream: `HRT-274..283`, not all `VERIFIED`. |
| 285 | `CG-S12-HRT-013` | ESS and MSS | **BLOCKED** | Upstream: `HRT-274..284`, not all `VERIFIED`. |
| 286 | `CG-S12-HRT-014` | Internal and interdepartmental ticket | **BLOCKED** | Own stated upstream (`HRT-273` + Platform primitives + verified canonical linked records) is fully satisfied already (§5). Held `BLOCKED` by this index as a deliberate, disclosed conservative choice pending a real file/migration/contract collision check against the concurrently-releasable HR track (§5, §7) — not yet performable because no atomic task has produced a concrete allowed-file path list to check. **Re-evaluation candidate**, not a genuine prerequisite gap. |
| 287 | `CG-S12-HRT-015` | Customer-to-tenant ticket | **BLOCKED** | Upstream: `HRT-286`, not `VERIFIED`. |
| 288 | `CG-S12-HRT-016` | Tenant-to-CargoGrid helpdesk | **BLOCKED** | Upstream: `HRT-286..287`, not all `VERIFIED`. |
| 289 | `CG-S12-HRT-017` | SLA and knowledge base | **BLOCKED** | Upstream: `HRT-286..288`, not all `VERIFIED`. |
| 290 | `CG-S12-HRT-018` | Ticket assignment | **BLOCKED** | Upstream: `HRT-286..289`, not all `VERIFIED`. |
| 291 | `CG-S12-HRT-019` | Ticket escalation | **BLOCKED** | Upstream: `HRT-289..290`, not all `VERIFIED`. |
| 292 | `CG-S12-HRT-020` | Typed ticket-linked records | **BLOCKED** | Upstream: `HRT-286..291`, not all `VERIFIED`. |
| 293 | `CG-S12-HRT-021` | Sensitive personal and payroll data controls | **BLOCKED** | Upstream: `HRT-274..292` (union of both tracks), the sole convergence point — far from satisfied. |
| 294 | `CG-S12-HRT-022` | Integrated verification | **BLOCKED** | Upstream: `HRT-274..293` all `VERIFIED`. |
| 295 | `CG-S12-HRT-023` | Privacy/integrity hardening | **BLOCKED** | Upstream: `HRT-294` `VERIFIED` with finding register. |
| 296 | `CG-S12-HRT-024` | Documentation and handoff | **BLOCKED** | Upstream: `HRT-295` `VERIFIED`. |
| 297 | `CG-S12-HRT-025` | Closure verification | **BLOCKED** | Upstream: `HRT-296` `VERIFIED`. Only this prompt may set `PHASE_7_VERIFIED`. |

**Summary: 3 VERIFIED (273, 274, 275), 1 READY (276), 21 BLOCKED (277–297).**

---

## 11. Evidence/log path

Every future Phase 7 task's own runtime log, atomic-task record, db-test file, and closure report is written under `docs/build-log/phase-07/`, mirroring the `docs/build-log/phase-0{0..6}/` convention every prior phase used. This checkpoint's own two writes:

- `docs/adr/ADR-0023-phase7-hris-organization-team-and-employee-identity-reconciliation.md`
- `docs/build-log/phase-07/00_EXECUTION_INDEX.md` (this file)

---

## 12. Rollback

Phase 7 is a fresh phase with zero prior state — there is nothing pre-existing to roll back to except these two new files. Rollback of this checkpoint specifically means: delete `docs/build-log/phase-07/00_EXECUTION_INDEX.md` and `docs/adr/ADR-0023-*.md`, and revert `PHASE_7_IN_PROGRESS` to `PHASE_7_NOT_STARTED`. No schema, service, UI, or test file was touched (per this kickoff's own binding constraint — planning-only), so no migration rollback is needed or possible at this checkpoint.

---

## 13. Runtime state and resume

`PHASE_7_IN_PROGRESS` is **set** by this checkpoint. `PHASE_7_VERIFIED` is **not** set and must not be set by any task before Prompt 297.

**Resume instruction:** the next runtime checkpoint should pick up `CG-S12-HRT-002` (Prompt 274, Employee Master) as the first eligible task — it is the only row in §10 marked `READY`. Before releasing `HRT-286` concurrently (§5, §10), a future checkpoint must first perform the file/migration/contract collision check this index could not yet perform (no concrete allowed-file paths exist for either track yet).

## 14. First eligible prompt

**Prompt 274 (`CG-S12-HRT-002`, Employee Master)** — dependency-clean, all prerequisites `VERIFIED`, ownership ADR filed (ADR-0023 Part B), no critical ownership/security/privacy/Finance/ticket-link conflict. Ready to begin its own atomic-task decomposition and schema design, including its own disclosed decision on whether to additionally register `master_type_code='employee'` in `app.master_records` (ADR-0023 Part B, left open).

---

## 15. Update — HRT-274 (Prompt 274, Employee Master) implementation complete

Recorded here rather than rewritten into §10/§13/§14 above (preserving those sections as this kickoff's own point-in-time record, matching this repository's append-only evidence discipline — see `ISS-2026-005`/`006`'s own precedent for "evidence, once committed, is not revised to look retroactively correct").

`CG-S12-HRT-002` is now **COMPLETED** (§10, row updated in place since that table is this index's own live task-state ledger, not a point-in-time narrative). Full evidence: `docs/build-log/phase-07/HRT-274.md`. `master_type_code='employee'` **was** registered (§10 row 274's own original open question, now resolved and documented). `HRT-275` (`CG-S12-HRT-003`, Organization and Position Linkage) is now the sole `READY` row — its own upstream (`HRT-274`) is satisfied, and `ADR-0023` Part A already resolves its `team`-node-type design question in advance. `PHASE_7_VERIFIED` remains unset (reserved for Prompt 297, unchanged from §13).

---

## 16. Update — HRT-275 (Prompt 275, Organization and Position Linkage) implementation complete

Recorded here rather than rewritten into §13/§14 above, per the same append-only evidence discipline §15 already establishes for this file. §10's row 275 (and row 276) are updated in place, matching §15's own precedent that the task-state table is a live ledger, not frozen narrative.

`CG-S12-HRT-003` is now **VERIFIED** (§10). Full evidence: `docs/build-log/phase-07/HRT-275.md`. ADR-0023 Part A is implemented exactly as decided — this checkpoint's own chartered migration, not a re-litigation. HRT-274's own build log §10 recommendation (additive `app.employees.position_id`, formalize or disclose the manager-cycle-prevention decision) is fully addressed: `position_id` is real and additive; the cycle-prevention decision is to keep the existing bounded chain walk unchanged, with recorded reasoning (`HRT-275.md` §3.7), not a materialized closure table. `HRT-276` (`CG-S12-HRT-004`, Recruitment, job portal and ATS) is now the sole `READY` row — its own upstream (`HRT-275`) is satisfied and no additional ownership/security/privacy conflict is disclosed against its own stated scope. `PHASE_7_VERIFIED` remains unset (reserved for Prompt 297, unchanged from §13).
