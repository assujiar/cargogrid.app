# Procurement and Vendor Management Execution Index

**Prompt:** `CG-S11-PRC-001` (`CG-AABPP-PRC-250` v0.12.0)
**Runtime output of:** `docs/ai-agent-build-prompt-package/11-phase-06-procurement-vendor/250_PROCUREMENT_VENDOR_WBS_RUNTIME_KICKOFF_PROMPT.md`
**Status:** `PHASE_6_IN_PROGRESS`. Row `250` (`CG-S11-PRC-001`, this task) is `VERIFIED`. `CG-S11-PRC-002` (Prompt 251, Vendor Registration and Onboarding) is `READY` and within this checkpoint's own "lanjut prompt 249-255" authorized range. `CG-S11-PRC-003..006` (Prompts 252–255) are `NOT_STARTED`, dependency-pending on their own upstream row, but named within this checkpoint's own authorized range. `CG-S11-PRC-007..022` (Prompts 256–271) are `NOT_STARTED`, outside this checkpoint's own authorized range.

## 0. Checkpoint

See `00_PROCUREMENT_VENDOR_WBS.md` §2/§3 for the full entry-gate verification and repository checkpoint. Summary: `PHASE_5_VERIFIED` confirmed; 157 migrations applied; zero Critical/High `OPEN` issue anywhere in `KNOWN_ISSUES.md`; `docs/adr/ADR-0020-phase6-vendor-identity-reconciliation-and-authority.md` resolves the one genuine reconciliation gap found this checkpoint (two independent `master_records` types both nominally "vendor").

## 1. Full execution index

### 1.1 Row `250` — Prompt 250, `CG-S11-PRC-001` (this task)

| Column | Value |
|---|---|
| `task_id` | `CG-S11-PRC-001` |
| `parent_prompt` | Prompt 250 (`docs/ai-agent-build-prompt-package/11-phase-06-procurement-vendor/250_PROCUREMENT_VENDOR_WBS_RUNTIME_KICKOFF_PROMPT.md`) |
| `workstream` | Governance / Phase 6 Kickoff |
| `epic` | Procurement/Vendor WBS and Runtime Kickoff |
| `capability` | Phase 6 hierarchy, dependency graph, atomic task ledger, execution index |
| `feature_slice` | n/a (kickoff is atomic) |
| `atomic_objective` | Create the repository-specific Phase 6 hierarchy/dependency graph/task ledger/execution index without implementing any capability — `250_*.md` §"Objective" |
| `source_ids` | `249_PROCUREMENT_VENDOR_README.md` §1–11; `250_*.md` full; RPD-016/022/025/032/038/040 (carried forward, unchanged) |
| `upstream` | `PHASE_5_VERIFIED` |
| `downstream` | Every row in §1.2 below (`251`–`271`, 21 task rows total) |
| `allowed_paths` | `docs/build-log/phase-06/00_PROCUREMENT_VENDOR_WBS.md`, `PROCUREMENT_VENDOR_EXECUTION_INDEX.md`, `docs/adr/ADR-0020-*.md`, `docs/adr/README.md`, `docs/runtime/*.md` |
| `forbidden_paths` | any Phase 6 domain schema/service/UI file |
| `migration_ids` | none |
| `api_contracts` | none |
| `access_controls` | none (planning only — `PRC` module/action reconciliation recorded in WBS §5, enforced starting at row `251`) |
| `vendor_rate_po_match_invariants` | none enforced yet — recorded as future obligations: single canonical vendor identity (`ADR-0020`), RPD-040 applied-version snapshot preservation, no duplicate rate/PO/match root |
| `tests` | none (docs-only task) |
| `commands` | `typecheck`; `lint`; `pnpm run test`; `docs:check`; `security:check`; `data-classification:check`; `threat-model:check`; `standards:check`; `git:check-paths`; `git:check`; `db:test`; `next build` — re-run fresh this checkpoint as baseline reconciliation before any Phase 6 file was written; results recorded in the checkpoint note this task's own commit adds to `CARGOGRID_BUILD_STATUS.md` |
| `evidence` | This document + `00_PROCUREMENT_VENDOR_WBS.md` + `docs/adr/ADR-0020-*.md` |
| `rollback` | `git revert` this commit — docs-only, no schema/data to roll back |
| `owner` | Runtime build agent |
| `status` | `VERIFIED` (this checkpoint) |
| `resume_point` | `CG-S11-PRC-002` (Prompt 251) is dependency-clean `READY` and within this checkpoint's own authorized range — proceeding directly, no further per-task pause needed within `250`–`255` |

### 1.2 Master dependency/status table — rows `251`–`271`

| `task_id` | Prompt | Workstream / Capability | `source_ids` | `upstream` | `downstream` | `status` | `resume_point` |
|---|---|---|---|---|---|---|---|
| `CG-S11-PRC-002` | 251 — Vendor Registration and Onboarding | Vendor Governance / Canonical Vendor Lifecycle | `PRC-VND-001..004`, `PRC-VND-US-001`, BP-A08 | `PRC-001` (`VERIFIED`); `ADR-0020` canonical `vendor` identity | `PRC-003..022` (every later Phase 6 row references `app.vendor_profiles`) | **`READY`** | Within this checkpoint's own "lanjut prompt 249-255" range — proceeding directly |
| `CG-S11-PRC-003` | 252 — Vendor Assessment | Vendor Governance / Qualification and Risk | `PRC-ASM-001..004` | `PRC-002` | `PRC-004`, `PRC-015` (Performance, out of range), `PRC-020` (out of range) | `NOT_STARTED` | Becomes `READY` when `PRC-002` (251) is `VERIFIED` |
| `CG-S11-PRC-004` | 253 — Compliance and Document Expiry | Vendor Governance / Compliance Control | `PRC-ASM-001..004`, `PRC-VND-001..004`, RPD-025, RPD-032 | `PRC-002..003`; verified `PLT-128` Document/File Engine | `PRC-005`, `PRC-007` (Sourcing eligibility, out of range), `PRC-014` (Assignment, out of range) | `NOT_STARTED` | Becomes `READY` when `PRC-003` (252) is `VERIFIED` |
| `CG-S11-PRC-005` | 254 — Vendor Banking and Tax Security | Vendor Governance / Sensitive Financial Master | `PRC-VND-001..004`, `PRC-ASM-001..004`, RPD-016/023/025/038 | `PRC-002..004`; verified Finance tax/payment-term contracts (`FIN-195`) | `PRC-006`, `PRC-016` (Invoice Matching, out of range) | `NOT_STARTED` | Becomes `READY` when `PRC-004` (253) is `VERIFIED` |
| `CG-S11-PRC-006` | 255 — Vendor Rate and Pricelist | Procurement Pricing / Rate Governance | `PRC-RTE-001..004` | `PRC-002..005`; verified Phase 2 `vendor_rate` ownership (`ADR-0015`), Finance currency/tax, Platform master/config | `PRC-007..022` | `NOT_STARTED` | Becomes `READY` when `PRC-005` (254) is `VERIFIED` — **last row within this checkpoint's own authorized range** |
| `CG-S11-PRC-007` | 256 — Sourcing | Sourcing / Vendor Selection Decision Support | `PRC-SRC-001..004` | `PRC-002..006` | `PRC-008..022` | `NOT_STARTED` | Outside this checkpoint's own authorized range (250–255); requires fresh explicit authorization |
| `CG-S11-PRC-008` | 257 — Procurement RFQ | Sourcing / Request for Quotation | `PRC-SRC/RTE-001..004` | `PRC-007` | `PRC-009..011` | `NOT_STARTED` | Outside authorized range |
| `CG-S11-PRC-009` | 258 — Vendor Comparison | Sourcing / Bid Evaluation | `PRC-RTE/SRC-001..004` | `PRC-008` | `PRC-010..011` | `NOT_STARTED` | Outside authorized range |
| `CG-S11-PRC-010` | 259 — Procurement Approval | Sourcing / Commitment Authorization | all `PRC` families | `PRC-007..009` | `PRC-011..012` | `NOT_STARTED` | Outside authorized range |
| `CG-S11-PRC-011` | 260 — Purchase Order | Purchasing / Commitment Instrument | `PRC-POI-001..004` | `PRC-010` | `PRC-012..016` | `NOT_STARTED` | Outside authorized range |
| `CG-S11-PRC-012` | 261 — Vendor Contract | Purchasing / Standing Agreement | `PRC-POI/VND-001..004` | `PRC-002`, `PRC-011` | `PRC-013..014` | `NOT_STARTED` | Outside authorized range |
| `CG-S11-PRC-013` | 262 — Vendor Capacity and Availability | Purchasing / Operational Eligibility | `PRC-SRC-001..004` | `PRC-002`, `PRC-004`; verified Phase 5 `app.vehicle_capacity_reservations` (`ATW-227`) | `PRC-014` | `NOT_STARTED` | Outside authorized range |
| `CG-S11-PRC-014` | 263 — Vendor Assignment | Purchasing / Operations Handoff | `PRC-SRC/POI`; OPS-TMS contract (`app.resource_assignments`, `OPS-172`) | `PRC-011..013` | `PRC-015..016` | `NOT_STARTED` | Outside authorized range |
| `CG-S11-PRC-015` | 264 — Vendor Performance | Vendor Governance / Outcome Evidence | `PRC-POI/ASM-001..004` | `PRC-003`, `PRC-014`; verified `app.shipment_actual_cost_components` (`OPS-178`) | `PRC-017` | `NOT_STARTED` | Outside authorized range |
| `CG-S11-PRC-016` | 265 — Vendor Invoice Matching | Purchasing / Finance Reconciliation | `PRC-POI-001..004`; FIN-AP contract (`app.finance_ap_open_items`/`finance_vendor_bills`, `FIN-199`/`200`) | `PRC-011`, `PRC-014`; verified Finance vendor-bill/AP interface | `PRC-017` | `NOT_STARTED` | Outside authorized range |
| `CG-S11-PRC-017` | 266 — Procurement Dashboard and Reports | Vendor Governance / Reporting | all `PRC` families | `PRC-002..016` | `PRC-019` | `NOT_STARTED` | Outside authorized range |
| `CG-S11-PRC-018` | 267 — Optional Vendor Portal | Vendor Governance / External Surface | `PRC-VND/RTE/SRC/POI`; BP-A08 | `PRC-002`, `PRC-006`; unresolved Platform membership/portal-surface ADR | `PRC-019` | `NOT_STARTED` | Outside authorized range; blocked until a Platform membership/portal-surface ADR resolves external identity ownership (`249_*.md` §5) — internal Procurement is never blocked by this |
| `CG-S11-PRC-019` | 268 — Integrated Verification | Vendor Governance / Cross-Capability Proof | all Phase 6 capabilities | `PRC-002..018` | `PRC-020` | `NOT_STARTED` | Outside authorized range |
| `CG-S11-PRC-020` | 269 — Procurement Integrity/Security/Financial Hardening | Vendor Governance / Adversarial Repair | evidence-ranked blocker repair | `PRC-019` | `PRC-021` | `NOT_STARTED` | Outside authorized range |
| `CG-S11-PRC-021` | 270 — Documentation and Handoff | Vendor Governance / Phase 7/8/9 Contracts | Phase 7/8/9 contracts | `PRC-020` | `PRC-022` | `NOT_STARTED` | Outside authorized range |
| `CG-S11-PRC-022` | 271 — Independent Closure | Vendor Governance / `PHASE_6_VERIFIED` Gate | all Phase 6 evidence | `PRC-021` | Phase 7 kickoff | `NOT_STARTED` | Outside authorized range. Only this row may set `PHASE_6_VERIFIED` |

## 2. Tally

`VERIFIED`: 1 (`250`). `READY`: 1 (`251`). `NOT_STARTED`: 20 (`252`–`271`). Total: 22.

## 3. Next eligible task

`CG-S11-PRC-002` (Prompt 251, Vendor Registration and Onboarding) — dependency-clean, within this checkpoint's own "lanjut prompt 249-255" authorized range. Proceeding directly.
