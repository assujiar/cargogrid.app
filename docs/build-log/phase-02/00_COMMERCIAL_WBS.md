# 00 — Commercial Work Breakdown Structure

**Prompt:** `CG-S7-COM-001` (`CG-AABPP-COM-142` v0.8.0)
**Runtime output of:** `docs/ai-agent-build-prompt-package/07-phase-02-commercial/142_COMMERCIAL_WBS_RUNTIME_KICKOFF_PROMPT.md`
**Status:** `PHASE_2_IN_PROGRESS` (kickoff/index only — no capability task `143`–`165` has executed; this document performs no runtime source/schema change)

## 0. Scope and method

This WBS instantiates atomic Commercial tasks from repository evidence already produced in Step 3 (`docs/architecture/`), Phase 1's own closure/handoff package, and the Phase 2 package itself (`docs/ai-agent-build-prompt-package/07-phase-02-commercial/`). It does not re-derive the capability catalogue or dependency order — both are reproduced by reference from `141_COMMERCIAL_README.md` §4 — the same "one source, not a second copy that could drift" discipline every prior phase kickoff/WBS document in this repository has followed (`00_PHASE0_WBS.md`, `00_PLATFORM_CORE_WBS.md`). No runtime source, schema, config, or data file is created or changed by this document except the one new ADR this checkpoint's own required task 4 mandates (`docs/adr/ADR-0015-commercial-vendor-service-rate-lookup-ownership.md`).

## 1. Mandatory hierarchy (`141_*.md` §3)

`Phase 2 → Workstream → Epic → Capability → Feature slice → Atomic implementation task → Verification task → Hardening task → Documentation task → Phase closure task`.

Every one of the 19 capability prompts (`143`–`161`) and the 4 closing prompts (`162`–`165`) fills exactly one hierarchy row below. No level is skipped; no level is invented beyond what `141_*.md` §3 already fixes.

## 2. Workstream / Epic grouping (reconciled against each capability prompt's own §3 "Workstream" line — reproduced verbatim, not re-derived)

| Workstream | Epic(s) | Capability prompts | Source requirement family |
|---|---|---|---|
| Growth and Lead | Lead Acquisition; Qualification Conversion | `143`–`144` (2) | `COM-LEAD-001..004` |
| Customer Relationship | Relationship Workspace; CRM Workspace | `145`–`146` (2) | `COM-CRM-001..004` |
| Pipeline | Revenue Opportunity | `147` (1) | `COM-OPP-001..004` (shared with Costing and Pricing) |
| Costing and Pricing | Commercial Costing (×2); Commercial Pricing | `148`–`150` (3) | `COM-OPP-001..004` |
| Quotation Lifecycle | Customer Offer (×2); Commercial Governance; Customer Commitment | `151`–`154` (4) | `COM-QTN-001..004` |
| Customer and Contract | Commercial Master Conversion; Commercial Agreement; Commercial Risk | `155`–`157` (3) | `COM-CPR-001..004` |
| Commercial Analytics | Actionable Sales Insight; Governed Reporting | `158`–`159` (2) | `COM-CPR-001..004` (shared with Customer and Contract) |
| Lineage and Data Quality | Commercial to Operations Handoff; Canonical Data Reuse | `160`–`161` (2) | `CPD-018/022`; no-reentry invariant (`01_MODULE_DEPENDENCY_MAP.md` line 127) |
| Phase Closing | Integrated Verification; Risk Hardening; Knowledge and Handoff; Closure | `162`–`165` (4) | — (cross-cutting) |

**Total: 19 capability prompts + 4 closing prompts = 23, plus this kickoff prompt (`142`) = 24 rows**, matching `COMMERCIAL_EXECUTION_INDEX.md` exactly and `docs/architecture/13_FULL_WORK_BREAKDOWN_STRUCTURE.md` §2's `COM` range (`141`–`165`, 25 files including the README, `141`).

## 3. Capability coverage — all 19 mandatory Commercial capabilities

Every row below cites its `Prompt ID` (`CG-S7-COM-NNN`), source requirement, primary dependencies (`141_COMMERCIAL_README.md` §4's dependency column reproduced verbatim, not re-derived), and allowed-scope summary extracted directly from that capability's own prompt file:

| # | Prompt | Task ID | Capability | Source requirement | Primary dependencies | Allowed scope (from prompt §11) |
|---:|---|---|---|---|---|---|
| 1 | `143` | `CG-S7-COM-002` | Lead management | `COM-LEAD-001..004` | `142` | Lead capture/dedup/scoring/assignment schema/migrations/service/contracts/tests/docs |
| 2 | `144` | `CG-S7-COM-003` | Prospect lifecycle | `COM-LEAD-001..004` | `143` | Prospect conversion schema/migrations/service/contracts/tests/docs |
| 3 | `145` | `CG-S7-COM-004` | Contact and activity management | `COM-CRM-001..004` | `143..144` | Contact/site/activity schema/migrations/service/contracts/tests/docs |
| 4 | `146` | `CG-S7-COM-005` | CRM sales plan and pipeline | `COM-CRM-001..004` | `143..145` | Sales plan/target/pipeline/forecast schema/migrations/service/contracts/tests/docs |
| 5 | `147` | `CG-S7-COM-006` | Opportunity management | `COM-OPP-001..004` | `144..146` | Opportunity/stage/probability schema/migrations/service/contracts/tests/docs |
| 6 | `148` | `CG-S7-COM-007` | RFQ and costing request | `COM-OPP-001..004` | `147` | Cost-request schema/migrations/service/contracts/tests/docs |
| 7 | `149` | `CG-S7-COM-008` | Rate and cost lookup | `COM-OPP-001..004`; `PRC-RTE-001..004` (Phase 2 slice) | `148`; **approved vendor/rate ownership ADR (`ADR-0015`, this checkpoint)** | Rate-version detail schema/migrations/service/lookup UI/tests/docs — extends `PLT-120`'s existing `master_records`/`vendor_rate` registration, never a second master |
| 8 | `150` | `CG-S7-COM-009` | Margin calculation | `COM-OPP-001..004` | `149` | Deterministic margin/markup/discount service/contracts/tests/docs — exact decimal, no floating-point money |
| 9 | `151` | `CG-S7-COM-010` | Quotation builder | `COM-QTN-001..004` | `147..150` | Quote draft/line/term schema/migrations/service/UI/contracts/tests/docs |
| 10 | `152` | `CG-S7-COM-011` | Quotation versioning | `COM-QTN-001..004` | `151` | Immutable version/supersession schema/migrations/service/tests/docs |
| 11 | `153` | `CG-S7-COM-012` | Quotation approval | `COM-QTN-001..004` | `150..152` | Threshold routing/approval schema/migrations/service/contracts/tests/docs — reuses `PLT-123` Approval Engine |
| 12 | `154` | `CG-S7-COM-013` | Customer acceptance | `COM-QTN-001..004` | `153` | Delivery/acceptance/rejection/expiry schema/migrations/service/contracts/tests/docs |
| 13 | `155` | `CG-S7-COM-014` | Customer and account conversion | `COM-CPR-001..004` | `144..146`,`154` | Customer/account/contact/site canonical conversion schema/migrations/service/contracts/tests/docs |
| 14 | `156` | `CG-S7-COM-015` | Contract and customer pricing | `COM-CPR-001..004` | `150`,`154..155` | Contract/pricelist/effective-rate schema/migrations/service/contracts/tests/docs |
| 15 | `157` | `CG-S7-COM-016` | Credit and commercial control | `COM-CPR-001..004` | `155..156` | Credit profile/hold/override snapshot schema/migrations/service/contracts/tests/docs — Finance integration boundary only, no AR/GL/payment posting |
| 16 | `158` | `CG-S7-COM-017` | Commercial dashboard | `COM-CPR-001..004` | `143..157` | Read-only live-query dashboard UI/service/tests/docs, RPD-014 budgets/pagination/caching |
| 17 | `159` | `CG-S7-COM-018` | Commercial reports | `COM-CPR-001..004` | `143..158` | Report definition/scoped query/preview/export/schedule service/UI/tests/docs |
| 18 | `160` | `CG-S7-COM-019` | Full lineage into Job Order | `COM-QTN-001..004`; `COM-CPR-001..004`; `CPD-018/022` | `143..159` | Idempotent accepted-quote→`JobOrderDraftInput` handoff contract/snapshot/lineage service/contracts/tests/docs — **no Job Order table/route**, Phase 3-owned |
| 19 | `161` | `CG-S7-COM-020` | No-reentry enforcement | `CPD-018/022`; all `COM-*` | `143..160` | Cross-flow reuse-rule/provenance/override-audit service/tests/docs |

**Schema ownership** (reconciled against `05_DATABASE_SCHEMA_WORKSTREAM.md` §3/§4, single flat `app` schema unchanged from Platform Core — no per-domain schema is created): every capability above adds tables to the same `app` schema Platform Core already established. `app.master_records`/`app.master_types` (`PLT-120`) already carry the seeded `vendor_rate` master type (`owner_module_code='PRC'`) — `149` extends it with a child detail table and read view, per `ADR-0015`; it does not create a second table family.

**API/UI boundary** (reconciled against `04_REPOSITORY_TARGET_STRUCTURE.md` §5/§8): allowed paths for this phase are `app/(tenant)/[tenantSlug]/commercial/**` (new business-domain folder — the first one created in this repository, since Phase 1 deliberately created none), `server/contracts/commercial/`, `server/{queries,mutations,actions}/commercial/`, `server/policies/commercial/`, `server/jobs/commercial/` (if any async job is needed), `components/ui/**` (extended only if a genuinely new primitive is needed, per the same folder-existence-timing convention Platform Core used), `supabase/migrations/` (first Commercial-domain migrations). No Operations/Finance/Procurement/HRIS domain folder is created in Phase 2.

**No oversized profile found**: every one of the 19 Commercial capabilities maps to exactly one bounded feature slice per its own prompt's §3/§11, within Template 53 §11's rule (normally 5–15 files, 1–3 migrations, one module boundary) — the same sizing rule Platform Core's own 32 capabilities were spot-verified against (`13_FULL_WORK_BREAKDOWN_STRUCTURE.md` §5.2). No capability prompt here exceeds it; no further splitting is required at this checkpoint.

## 4. Verification / hardening / documentation / closure tasks

| Prompt | Task ID | Purpose | Dependency | Output |
|---|---|---|---|---|
| `162` | `CG-S7-COM-021` | Integrated Commercial verification | `143`–`161` | `docs/build-log/phase-02/COM-162.md` — verification tests/scripts/fixtures/logs/docs only, default no repair |
| `163` | `CG-S7-COM-022` | Tenant/security/financial/data hardening | `162` | `docs/build-log/phase-02/COM-163.md` — exact finding-linked repair, consumes `162`'s failure matrix |
| `164` | `CG-S7-COM-023` | Documentation and handoff | `163` | `docs/build-log/phase-02/COM-164.md` — Phase 3 entry package, analogous to `docs/build-log/phase-01/PLATFORM_CORE_HANDOFF_PACKAGE.md` |
| `165` | `CG-S7-COM-024` | Phase 2 closure verification | `164` | `docs/build-log/phase-02/COMMERCIAL_CLOSURE_REPORT.md` — only this prompt may set `PHASE_2_VERIFIED` |

This is the identical 4-prompt closing pattern Phase 0 and Phase 1 already proved out (`docs/build-log/phase-00/PH0-99.md`–`PHASE0_CLOSURE_REPORT.md`; `docs/build-log/phase-01/PLT-137.md`–`PLATFORM_CORE_CLOSURE_REPORT.md`) — reused, not reinvented.

## 5. Atomic sizing

Every capability row in §3 stays within Template 53 §11's rule (normally 5–15 files, 1–3 migrations, one module boundary), per each prompt's own §11 "Allowed files/folders" and §13 "Database impact" sections (bounded, not open-ended). No child-task split is required at this checkpoint.

## 6. Safe concurrency lanes (required task 7)

The Commercial dependency chain (`141_*.md` §4) is a single, densely sequential chain far more linear than Platform Core's — every capability from `147` onward names 2–5 upstream capabilities, and the terminal analytics/lineage/closing capabilities (`158`–`165`) each depend on nearly the entire phase. This checkpoint identifies the genuinely safe parallel lanes rather than defaulting to either extreme:

| Lane | Capabilities | Rationale |
|---|---|---|
| Lane A (strictly sequential) | `143`→`144` | `144` names `143` as its sole dependency |
| Lane B (parallel to each other, both depend only on Lane A) | `145`→`146` (Customer Relationship chain) | `147` (Opportunity, depends on `144..146`, so cannot start until Lane B's own tail) | `145`/`146` and the Prospect/Lead chain do not share a table/contract/file — genuinely independent once `144` is `VERIFIED` |
| Lane C (sequential within itself, starts once `147` is `VERIFIED`) | `148`→`149`→`150` | Each explicitly depends on the prior — `149` additionally gates on `ADR-0015` (resolved this checkpoint, so no longer a blocker) |
| Lane D (sequential, depends on Lane C's tail) | `151`→`152`→`153`→`154` | Quotation Lifecycle's own internal chain — `153` needs `150..152`, `154` needs `153` |
| Lane E (sequential, depends on Lane B and Lane D tails) | `155`→`156`→`157` | `155` needs `144..146,154`; `156` needs `150,154..155`; `157` needs `155..156` |
| Lane F (parallel to each other, both depend on nearly the full phase) | `158` (needs `143..157`) | `159` (needs `143..158`, so strictly after `158`) — not actually parallel; `159` is sequential after `158` |
| Lane G (sequential, last two capability prompts, need the full phase) | `160`→`161` | `160` needs `143..159`; `161` needs `143..160` |

**Collision check (schema/contract/file/test):** no two lanes write the same table or the same `server/contracts/commercial/` file — verified by cross-referencing §3's "Allowed scope" column pairwise across every lane boundary. `149` (Lane C) is the one capability that extends Platform Core's already-seeded `app.master_records`/`vendor_rate` registration — no other Commercial capability writes to that table family, so no intra-phase collision exists either.

**This session's own operating model remains single-lane sequential** (one branch, one writer, per `ISS-2026-002`'s resolution, unchanged since Phase 0) — the lanes above describe where *safe* parallelism exists for a future multi-agent run, not an instruction to actually parallelize this session's own execution.

## 7. Integration checkpoints

| Checkpoint | After | Verifies |
|---|---|---|
| IC-1 | `146` | Lead→Prospect→Contact/Activity→CRM pipeline composes: a lead can be captured, scored, converted to a prospect, and tracked through a pipeline stage with real forecast data |
| IC-2 | `150` | Opportunity→RFQ/costing→rate lookup→margin composes: a costing request resolves against `ADR-0015`'s canonical rate source and produces a deterministic, exact-decimal margin |
| IC-3 | `154` | Quotation builder→versioning→approval→acceptance composes: an accepted quotation version is immutable, approval-gated, and carries real actor/channel/evidence |
| IC-4 | `157` | Customer/account conversion→contract pricing→credit control composes: an accepted quote can convert to a canonical customer/contract without re-typing, gated by a real credit snapshot |
| IC-5 | `161` | Lineage/no-reentry composes over the full phase: every downstream flow reuses canonical data by reference or governed snapshot, and the accepted-quote-to-Job-Order handoff contract is idempotent and lineage-complete without implementing Job Order |
| IC-6 (= Prompt `162`) | `161` | Full Commercial integrated verification — the phase-level equivalent of Phase 1's `PLT-137.md` |

## 8. Accepted-quote-to-Job-Order handoff contract (required task 6 — defined, not implemented)

Per `141_COMMERCIAL_README.md` §5 ("Job Order remains Phase 3-owned. Phase 2 owns the idempotent accepted-quote conversion contract, snapshot and lineage; it must not smuggle the Operations domain into Commercial") and `160_COMMERCIAL_JOB_ORDER_LINEAGE_PROMPT.md` §3/§4, this checkpoint fixes the contract shape Prompt 160 must implement, without implementing it here:

- **Idempotency key:** the accepted quotation version's own stable identifier (`quotation_version_id`, a UUID minted at `152`), scoped by tenant. A retried or duplicate handoff attempt with the same key must be a no-op returning the original result, never a second Job Order draft.
- **Trigger:** exactly one accepted quotation version (`154`'s customer-acceptance evidence, locked per `152`'s versioning rule) is eligible to produce exactly one `JobOrderDraftInput` payload — never zero (silent drop) and never more than one (duplicate creation).
- **Snapshot, not live reference:** the payload captures customer/contact/address/cargo/service/rate/price/acceptance/credit data **as of acceptance time** (governed snapshot, per the no-reentry binding rule) — a later edit to the live customer/rate/pricing record must never silently alter a payload already handed off, mirroring `05_DATABASE_SCHEMA_WORKSTREAM.md` §4's `record_version`-based stale-snapshot detection convention.
- **Lineage:** the full chain (lead → prospect → contact/opportunity → costing/rate/margin → quotation/version → approval → acceptance → customer/account/contract/credit → `JobOrderDraftInput`) must be queryable end-to-end from any point in the chain, satisfying `01_MODULE_DEPENDENCY_MAP.md` line 127's no-reentry invariant.
- **Phase 3 ownership boundary:** Prompt 160 defines and emits the contract (a Commercial-owned function/service and its typed payload shape under `server/contracts/commercial/`); it does **not** create a `job_orders` table, route, or UI — those are Phase 3 (`OPS-`) capabilities that consume this contract once built. This checkpoint records the boundary; Prompt 160 implements the emitting side only.
- **No-reentry enforcement (`161`):** every field in the snapshot must be traceable to its canonical source record (reference or governed snapshot) — `161`'s own job is proving zero silent re-typing occurred anywhere in the chain, with every deliberate override permissioned, reasoned, and audited.

## 9. Stale-evidence triggers

Re-verify this WBS's dependency table against `141_COMMERCIAL_README.md` §4 if any of: (1) a capability prompt file `143`–`165` is edited after this checkpoint; (2) `ADR-0015` is superseded or a Phase 6 Procurement kickoff changes the interim write-authority conclusion it records; (3) more than 5 capability prompts complete without an intervening re-read of this document (mirrors `00_PLATFORM_CORE_WBS.md` §8's own trigger cadence).

## 10. Recovery order

If a capability task fails partway: (1) do not proceed to its dependents; (2) `git revert` the failed task's own commit(s); (3) record the failure in `docs/runtime/ERROR_LEDGER.md`, update `COMMERCIAL_EXECUTION_INDEX.md`'s affected row(s) to `BLOCKED`, and generate a bounded resume prompt — never restart the phase blindly (same discipline every closing-prompt template in this package already states, re-used unchanged from Phase 0/Phase 1).

## 11. Cycle/orphan/duplicate checks (required task 7)

**Cycles:** none — `141_*.md` §4's dependency table is a strict DAG (every dependency ID is numerically lower than its dependent), re-verified this checkpoint by confirming no row cites a later-numbered prompt as its own dependency.

**Orphans:** none — every one of the 5 source requirement families (`COM-LEAD`, `COM-CRM`, `COM-OPP`, `COM-QTN`, `COM-CPR`) maps to at least one capability prompt in §3 above (per `docs/architecture/14_REQUIREMENT_PHASE_TRACEABILITY.md` lines 154–158); every capability prompt maps to exactly one primary source family; the 4 closing prompts are cross-cutting by design, not orphaned.

**Duplicates:** none — `13_FULL_WORK_BREAKDOWN_STRUCTURE.md` §12's already-verified finding ("no capability prompt ID appears in more than one phase's range") holds; within this phase, no two of the 19 capability rows in §3 claim the same table, contract file, or test path (§6's collision check). The one flagged near-duplicate risk (`149`'s vendor/rate lookup vs. Procurement's Phase-6 full lifecycle) is resolved by `ADR-0015` as a single-owner table plus a read view, not two masters.

## 12. Completion statement

All 19 mandatory Commercial capabilities plus verification/hardening/documentation/closure are represented in the hierarchy (§1–§4). Every dependency has explicit ownership (§3's "Primary dependencies" column, sourced from `141_*.md` §4). The one required ADR (vendor/service/rate lookup ownership) is resolved this checkpoint (`ADR-0015`, `ADR-CAND-ARCH-030`). The accepted-quote-to-Job-Order handoff contract is defined without implementing Job Order (§8). No cycle, orphan, or unowned collision was found (§11). `CG-S7-COM-002` (`143`, Lead management) can be instantiated from this document plus its own prompt file `143_LEAD_MANAGEMENT_PROMPT.md` — see `COMMERCIAL_EXECUTION_INDEX.md` row `002` for its `READY` determination.
