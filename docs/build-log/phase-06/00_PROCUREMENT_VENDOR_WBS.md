# 00 — Procurement and Vendor Management Work Breakdown Structure

**Prompt:** `CG-S11-PRC-001` (`CG-AABPP-PRC-250` v0.12.0)
**Runtime output of:** `docs/ai-agent-build-prompt-package/11-phase-06-procurement-vendor/250_PROCUREMENT_VENDOR_WBS_RUNTIME_KICKOFF_PROMPT.md`
**Status:** `PHASE_6_IN_PROGRESS` (kickoff/index only — no Phase 6 domain schema/code exists yet; this document performs no runtime source/schema change)

## 0. Scope and method

This WBS instantiates atomic Phase 6 tasks from repository evidence already produced by Phase 5's own closure (`docs/build-log/phase-05/ADVANCED_TMS_WMS_CLOSURE_REPORT.md`, `ADVANCED_TMS_WMS_HANDOFF_PACKAGE.md`) and the Phase 6 package itself (`docs/ai-agent-build-prompt-package/11-phase-06-procurement-vendor/`). It reproduces the capability catalogue and dependency order from `249_PROCUREMENT_VENDOR_README.md` §4 and each individual prompt file's own §9 "Upstream dependencies" by reference, the same "one source, not a second copy that could drift" discipline every prior phase WBS in this repository has followed.

## 1. Mandatory hierarchy

`Phase 6 → Workstream → Epic → Capability → Feature slice → Atomic implementation/verification/hardening/documentation/closure task`.

## 2. Runtime entry gate verification (`250_*.md` mandatory entry gate)

| # | Condition | Verified | Evidence |
|---:|---|---|---|
| 1 | `RUNTIME_DISCOVERY_VERIFIED` | ✔ | `docs/discovery/14_STEP2_CLOSURE_REPORT.md` — unchanged |
| 2 | `RUNTIME_ARCHITECTURE_VERIFIED` | ✔ | `docs/architecture/16_STEP3_CLOSURE_REPORT.md` — unchanged |
| 3 | `PHASE_0_VERIFIED` | ✔ | `docs/build-log/phase-00/PHASE0_CLOSURE_REPORT.md` |
| 4 | `PHASE_1_VERIFIED` | ✔ | `docs/build-log/phase-01/PLATFORM_CORE_CLOSURE_REPORT.md` |
| 5 | `PHASE_2_VERIFIED` | ✔ | `docs/build-log/phase-02/COMMERCIAL_CLOSURE_REPORT.md` |
| 6 | `PHASE_3_VERIFIED` | ✔ | `docs/build-log/phase-03/OPERATIONS_CLOSURE_REPORT.md` |
| 7 | `PHASE_4_VERIFIED` | ✔ | `docs/build-log/phase-04/FINANCE_CLOSURE_REPORT.md` |
| 8 | `PHASE_5_VERIFIED` | ✔ | `docs/build-log/phase-05/ADVANCED_TMS_WMS_CLOSURE_REPORT.md`, set at `CG-S10-ATW-029` (Prompt 248), re-confirmed clean at `ATW-030`/`031`/`032` |
| 9 | Repository/branch/HEAD/worktree ownership reconciled | ✔ | §3 below |
| 10 | Canonical vendor/service/rate; shipment/leg/resource/actual-cost/ePOD lineage; Phase 5 capacity/assignment; Finance vendor-bill/AP/posting interfaces reconciled | ✔ | §4 below |
| 11 | File, approval, notification, job, API and access primitives reconciled | ✔ | §5 below |
| 12 | Environment, baselines, unresolved ledgers reconciled | ✔ | §6/§7 below |

**Result: entry gate PASS.** `PHASE_6_BLOCKED` is not warranted.

## 3. Repository checkpoint at kickoff

| Field | Value |
|---|---|
| Repository | `assujiar/cargogrid.app` |
| Working branch | `claude/prompt-249-255-y15870` (harness-assigned; tracked to `origin/claude/prompt-249-255-y15870`) |
| HEAD at authoring time (pre-commit) | `243db46a4b831ceab598dd426e31926a4b146863` (merge of PR #44, `claude/codebase-audit-fixes-yag1ow`), which already fully contains `PHASE_5_VERIFIED` and the `ATW-030`/`031`/`032` post-closure audit repairs |
| Worktree state | Clean except this document, its sibling `PROCUREMENT_VENDOR_EXECUTION_INDEX.md`, `docs/adr/ADR-0020-*.md`, `docs/adr/README.md`, and this checkpoint's own runtime-ledger updates |
| Schema/migration state | 157 migrations applied, unchanged this checkpoint — kickoff performs zero schema change |
| Package manager/runtime | pnpm `10.33.0` + Node `>=22.11.0`; `node:test` unit suite; Playwright E2E; `db:test` (Postgres 16 + PostGIS 3, `scripts/db-tests/run.sh`, auto-discovers `scripts/db-tests/*.sql`) |
| Baseline gate results | Carried forward from `CG-S10-ATW-032`'s own fresh run (this checkpoint's own required work is planning/documentation only; §14 records this checkpoint's own re-run) |
| Authorization | Explicit user instruction "lanjut prompt 249-255" ("continue prompts 249 through 255") — a named-range authorization. Per this build's own standing discipline (`OPS-188`/`FIN-029`/`ATW-029`'s own precedent), this authorizes Prompts 250–255 as a named range; any Phase 6 capability beyond 255 requires its own fresh explicit authorization. |

## 4. Canonical Phase 2/3/4/5 root reconciliation (`250_*.md` required work items 1/2/4)

Phase 6 extends, never re-creates, the following canonical roots:

| Canonical root | Source | Extended/consumed by |
|---|---|---|
| `app.master_records` (`master_type_code='vendor'`) | `OPS-172`, `supabase/migrations/20260727130000_create_operations_resource_assignment.sql` | `PRC-251` (`app.vendor_profiles`, 1:1 governed extension — the single canonical vendor identity, per `ADR-0020`) |
| `app.master_records` (`master_type_code='vendor_rate'`) + `app.vendor_rate_versions` | `COM-149`, `supabase/migrations/20260724150000_create_commercial_rate_cost_lookup.sql`, `ADR-0015` | `PRC-255` (extends with quotation/pricelist/tiering/validity/approval; gains a new nullable `vendor_master_id` link per `ADR-0020`, never a second rate store) |
| `app.shipment_actual_cost_components.vendor_id`/`assignment_id` | `OPS-178`, `supabase/migrations/20260728110000_create_operations_actual_cost.sql` | Read-only lineage context for `PRC-264` (Vendor Performance, out of 250–255 scope); not written by 251–255 |
| `app.resource_assignments` (role=`'vendor'`) | `OPS-172` | Read-only lineage context for `PRC-263` (Vendor Assignment, out of 250–255 scope); not written by 251–255 |
| `app.finance_ap_open_items`/`finance_vendor_bills`/`finance_settlements` (`vendor_master_id`) | `FIN-199`/`200`/`201`, all `VERIFIED` | Read-only reconciliation target for `PRC-265` (Invoice Matching, out of 250–255 scope); 251–255 never write to any Finance table |
| `app.vehicle_capacity_reservations`, `app.warehouses`/`app.warehouse_zones` | `ATW-227`/`229` | Read-only context for `PRC-262`/`263` (out of 250–255 scope) |
| Document/File Engine (`app.files`/`app.document_types`/`app.authorize_file_access`) | `PLT-128`, `supabase/migrations/20260719140000_create_document_file_engine.sql` | `PRC-253` (Compliance/Document Expiry) — extended with a new `document_type_code`, no fork |
| Import/Export Job Framework (`app.jobs`/`app.create_import_export_job`/`app.commit_import_job`) | `PLT-131`/`132` | `PRC-255` (rate/pricelist import — the framework's first real domain-write adapter, closing part of `ISS-2026-013`) |
| Approval Engine, `self_approval_not_allowed`/maker-checker/`p_reauth_confirmed_at` MFA pattern | `PLT-116` (generic engine), `COM-157`/`ATW-020`/`025` (the inline-check convention) | `PRC-252` (assessor/approver separation), `PRC-254` (bank/tax maker-checker + MFA) |
| `app.evaluate_permission`/`app.assert_actor_is_session_identity`, `PRC` RBAC module (already seeded) | `PLT-111`, `supabase/migrations/20260716104519_create_rbac_evaluator.sql`, `20260730440000_harden_actor_identity_session_crosscheck.sql` | Every new Phase 6 RPC from `PRC-251` onward |

**Confirmed by direct repository inspection this checkpoint:** no `app.vendors`, `app.vendor_profiles`, `app.vendor_assessments`, `app.vendor_compliance_*`, `app.vendor_bank_accounts`, or `app.purchase_orders` table exists anywhere in the 157 already-applied migrations — Phase 6 is genuinely greenfield for full vendor lifecycle, contracting only against the roots listed above. **The one genuine reconciliation gap found and closed this checkpoint** (not a build oversight, structurally identical in shape to the Phase 5 `ATW-011A`/`016A` insertions): `app.master_records` carries two independent, previously-uncross-referenced master types both nominally about "vendor" (`vendor` — Finance/Operations identity — and `vendor_rate` — Commercial rate lookup). Resolved in `docs/adr/ADR-0020-phase6-vendor-identity-reconciliation-and-authority.md`: `vendor` is the single canonical identity Phase 6 extends; `vendor_rate` gains an additive linking column at `PRC-255`.

## 5. Platform/infrastructure foundation reconciliation (`250_*.md` required work items 1/5)

- Supabase/PostgreSQL 16, RLS/RBAC (`app.evaluate_permission`, `app.assert_actor_is_session_identity`, `app.has_active_tenant_membership`, `app.is_supreme_admin`, `app.can_access_record`, `app.lead_record_scope_org_unit_ids`) — all already established and reused, not reinvented.
- `PRC` RBAC module and five of its seven required actions already seeded (`View`/`Create`/`Edit`/`Delete`/`Approve`/`Export`/`View cost`); `Reject`/`Override`/`Download`/`Import`/`View personal data` are added once, additively, in `PRC-251`'s own migration per `ADR-0020`.
- `app.jobs`/`app.enqueue_job`/`app.claim_next_job` (`PLT-131`/`132`) — the reuse target for compliance-expiry-reminder and rate-import jobs; any new `job_type` value requires the three-place lockstep update (`app.generic_job_types()`, the `jobs_job_type_check` CHECK, the TS `GENERIC_JOB_TYPES` union) `ISS-2026-012`'s closure established.
- Document/File Engine (`PLT-128`) — real, `service_role`-only, no live malware-scan provider or signed-URL issuer wired (disclosed, unchanged); `PRC-253` is its first consumer needing expiry/renewal semantics, which the engine does not itself model (no `expires_at` column on `app.files`) — `PRC-253` adds its own compliance-document tracking table referencing `app.files.id`, not a fork of the engine.
- REST/GraphQL (RPD-033): **no REST/GraphQL adapter layer exists for any business domain yet, repository-wide** (confirmed by direct inspection — `app/api/` contains only the two GPS Gateway/webhook routes; no `app/api/v1/**`, no GraphQL resolver directory). This is an already-disclosed, standing Phase 5 boundary (`ATW-229`'s own build log: "No REST/GraphQL surface exists for this or any domain yet"), not a Phase 6 regression. `PRC-251`–`255` follow the identical precedent: one domain service layer (`server/contracts|queries|mutations/`), Next.js Server Actions as the sole consumer, with the REST/GraphQL parity gap disclosed per-capability rather than fabricated.
- No deployed environment exists yet anywhere in this repository (`preflight` fails closed by design; no live Supabase project) — unchanged by Phase 6 kickoff, not a blocker (identical disclosed condition every prior phase closed under).

## 6. Sensitive-data and masking foundation reconciliation

- Masking pattern (canonical, to reuse verbatim): `has_view_cost`-style permission gate + table-level column-restricted `GRANT` (never a bare column `REVOKE` against a broader table grant) + a `_directory`/masked read view exposing a `*_masked boolean` flag. `PRC-255` reuses `PRC:View cost` directly (already seeded, already protected).
- **No encryption/at-rest-protection primitive exists anywhere in the repository today** (confirmed: no `pgcrypto`, no existing encrypted-column pattern). `PRC-254` (Vendor Banking and Tax Security) is genuinely new ground — it must both reuse the existing visibility-masking pattern (view/grant split, `PRC:View personal data`) AND introduce the repository's first at-rest protection mechanism for a sensitive column class. This is recorded here, not discovered mid-implementation, so `PRC-254`'s own migration is not surprised by having to design both layers at once.
- MFA / privileged re-authentication: real, already proven twice (`PLT-115`'s support-session `reauth_confirmed_at`, reused verbatim by `COM-157`'s credit-approval flow) — a caller-supplied `p_reauth_confirmed_at timestamptz`, checked for ≤5-minute freshness inline. `PRC-254` reuses this exact parameter/check, not new infrastructure. Disclosed limitation carried forward unchanged: this verifies freshness of a claimed re-authentication event, not a live MFA provider integration.

## 7. Phase 6 planning gates applied (`250_*.md` "Phase 6 planning gates")

- No vendor-master task is `READY` until canonical ownership is proven — closed by `ADR-0020` (§4 above).
- No activation/eligibility task is `READY` until vendor status/assessment/compliance/service/coverage/contract/rate/capacity/override authority is explicit — `PRC-251`'s own lifecycle state machine (§9 below) is the first such explicit definition; `PRC-256`+ (sourcing/eligibility, out of 250–255 scope) remain `NOT_STARTED`.
- No tax/bank task is `READY` without field classification, masking, maker-checker/MFA, current SME/provider evidence and Finance ownership boundaries — `PRC-254` §20/§24 (RPD-016/RPD-038) explicitly bind this; no Indonesia-tax SME evidence exists in this repository (disclosed, matching every prior Finance tax capability's own disclosed boundary — `FIN-195`'s `is_example_fixture` convention), so `PRC-254` must not guess statutory behavior, only build the masked/versioned/maker-checker mechanism.
- No rate/PO/contract task is `READY` without exact currency/UOM/tax/surcharge/tiering/rounding, validity, source/config snapshots — `PRC-255` reuses `app.apply_finance_rounding`/`app.finance_currencies`/`app.calculate_finance_tax` unchanged, never reimplements rounding.
- No invoice-matching task is `READY` until Finance vendor-bill/AP and Phase 3/5 actual-cost/ePOD/service evidence are reconciled — `PRC-265` is out of 250–255 scope; this gate is recorded for the next range's own kickoff, not resolved here.
- No external vendor portal task is `READY` until identity/invitation/scope/revocation are proven without a fifth role layer — `PRC-267` is out of 250–255 scope; `PRC-251`'s own self-registration/intake stays internal-tenant-configurable only, never a public/portal identity (§9 below), consistent with `249_*.md` §5's BP-A08 boundary.
- Native/offline sync, HRIS, full Customer Portal/Loyalty and autonomous AI/enterprise automation remain outside this phase — unchanged, not touched by any of 251–255.

## 8. Capability catalogue and dependency order (reproduced by reference, `249_*.md` §4)

See `PROCUREMENT_VENDOR_EXECUTION_INDEX.md` §1 for the full 22-row table (`CG-S11-PRC-001` through `CG-S11-PRC-022`, Prompts 250–271), reproducing each prompt's own §9 "Upstream dependencies" verbatim as the single source of dependency truth. This range's own authorization covers rows `250`–`255` (`CG-S11-PRC-001..006`) only.

## 9. `PRC-251` lifecycle state machine (pre-registered here so every downstream 250–255 task cites one definition)

`draft → submitted → under_review → approved → active ⇄ suspended → archived`, plus a terminal `rejected` reachable only from `submitted`/`under_review` (returns to `draft` for revision, per `251_*.md` §22's "request revision" alternative flow — modeled as a transition back to `draft` with a revision reason, not a separate status, mirroring `app.finance_vendor_bills`' own draft-loop convention rather than inventing a `revision_requested` status the prompt does not name). `blacklisted` is reachable only from `active`/`suspended` and requires reason+evidence+approval per `249_*.md` §5. No status has an implicit self-transition; every transition is its own RPC with `record_version` optimistic concurrency, actor, reason (where the prompt requires one), and an audit row.

## 10. Only dependency-clean tasks marked `READY`

Per `250_*.md`'s own "mark only dependency-clean tasks `READY`" instruction: **`CG-S11-PRC-002` (Prompt 251) is `READY`.** `CG-S11-PRC-003`–`006` (Prompts 252–255) remain `NOT_STARTED` (dependency-correct, named in this checkpoint's own authorized range, but not yet unblocked) until their own upstream row is `VERIFIED` — matching `ADVANCED_TMS_WMS_EXECUTION_INDEX.md`'s identical precedent of not pre-marking an entire authorized range `READY` at once. Every row from `256` onward (outside this checkpoint's own authorized range) remains `NOT_STARTED`.

## 11. Atomic sizing

`PRC-251` targets 2–3 additive migrations (vendor-profile schema + child tables; the `vendor_rate_versions.vendor_master_id` link column and `PRC` permission seed rows, per `ADR-0020`) and an estimated 15–25 changed files (schema, `server/contracts|queries|mutations/procurement/`, one new `app/(tenant)/[tenantSlug]/procurement/vendors/` UI segment, tests, docs) — larger than a typical single-migration Phase 5 row because it is the first Phase 6 capability and must also stand up the `procurement/` UI segment and the five new `PRC` permission rows every later row depends on. `PRC-252`–`255` are not instantiated with exact file paths yet, the same discipline every prior phase WBS applied to not-yet-`READY` rows (paths risk staleness before the upstream row is `VERIFIED`).

## 12. Safe concurrency lanes

Single session, single branch (`claude/prompt-249-255-y15870`) — no parallel lane opened this checkpoint, matching every prior phase kickoff's one-agent-one-branch discipline (`ISS-2026-002`).

## 13. Completion statement

This document plus `PROCUREMENT_VENDOR_EXECUTION_INDEX.md` and `docs/adr/ADR-0020-*.md` satisfy `250_*.md`'s required output. `PHASE_6_IN_PROGRESS` is set this checkpoint (not `PHASE_6_VERIFIED` — only Prompt 271 may set that). `CG-S11-PRC-002` (Prompt 251, Vendor Registration and Onboarding) is the next eligible task, dependency-clean `READY`, and is within this checkpoint's own "lanjut prompt 249-255" authorization — proceeding directly, without a further per-task pause, matching the identical precedent this build established for every prior named-range authorization (`ATW-020`..`032`'s own "lanjut prompt 239-248"/"lanjut sd 248" chain).
