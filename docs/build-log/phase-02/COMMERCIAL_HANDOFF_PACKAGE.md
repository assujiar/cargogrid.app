# Phase 2 (Commercial) → Phase 3 (Operations) Entry Package

**Produced by:** `CG-S7-COM-023` (Prompt 164 — Commercial Documentation and Handoff)
**Audience:** an independent Phase 3 agent with **zero prior context** from this build session — every fact below is either directly cited to a `VERIFIED` document or explicitly marked as this checkpoint's own reconciliation.
**Status of this package itself:** complete pending one external precondition — `CG-S7-COM-024` (Prompt 165, Phase 2 Closure Verification) has not yet run. **Nothing in this document should be read as `PHASE_2_VERIFIED` being set** — only Prompt 165 may set that.

This is a **new, self-contained artifact**, distinct from `docs/runtime/HANDOFF.md` (the intra-Phase-2, checkpoint-to-checkpoint runtime handoff). This package exists specifically for the "fresh Phase 3 agent reconstructs Commercial and starts the exact eligible Phase 3 task safely" flow, mirroring `docs/build-log/phase-01/PLATFORM_CORE_HANDOFF_PACKAGE.md`'s own precedent one phase up.

## 1. Verified dependencies (what Phase 3 may rely on as fact)

| Closure | Status | Evidence |
|---|---|---|
| Phase 0 — Discovery and Foundation | `PHASE_0_VERIFIED` | `docs/build-log/phase-00/PHASE0_CLOSURE_REPORT.md` |
| Phase 1 — Platform Core | `PHASE_1_VERIFIED` | `docs/build-log/phase-01/PLATFORM_CORE_CLOSURE_REPORT.md` |
| Commercial kickoff (`142`, `CG-S7-COM-001`) | `VERIFIED` | `docs/build-log/phase-02/00_COMMERCIAL_WBS.md`, `COMMERCIAL_EXECUTION_INDEX.md` row `001` |
| 19 Commercial capability tasks (`143`–`161`, `CG-S7-COM-002..020`) | All `VERIFIED` | `docs/runtime/TASK_LEDGER.md`; individual build logs `docs/build-log/phase-02/COM-143.md`–`COM-161.md` |
| Integrated Commercial Verification (`162`, `CG-S7-COM-021`) | `VERIFIED` | `docs/build-log/phase-02/COM-162.md` |
| Tenant/Security/Financial/Data Hardening (`163`, `CG-S7-COM-022`) | `VERIFIED` | `docs/build-log/phase-02/COM-163.md` |
| Commercial Documentation and Handoff (`164`, `CG-S7-COM-023`, this checkpoint) | `IN_PROGRESS` → `VERIFIED` on this checkpoint's own close | This document + `docs/build-log/phase-02/COM-164.md` |
| Phase 2 Closure Verification (`165`, `CG-S7-COM-024`) | `NOT_STARTED` — the one remaining gate before `PHASE_2_VERIFIED` | `165_COMMERCIAL_CLOSURE_VERIFICATION_PROMPT.md` |

**Domain-code status:** zero Operations/Finance/Procurement (or any later-phase) business code exists anywhere in this repository. Everything listed in §2 below is Commercial-domain evidence — Commercial's own scope ends at the Job Order *handoff record* (§3); no Job Order table, route, or domain logic exists anywhere (re-confirmed §8).

## 2. Preserved assets (what already exists — do not recreate)

### 2.1 Database (20 Commercial migrations of 52 total, `supabase/migrations/`)

Every migration lives under `app` schema ownership, RLS enabled on every tenant-scoped table, and the `ERR-2026-004` per-migration convention (`revoke execute on all functions in schema app from public;`) present in every migration since `PLT-118` and independently re-confirmed across all 52 migrations at `COM-162`'s own traceability audit.

| Capability | Migration | Key tables/functions |
|---|---|---|
| Commercial WBS/Kickoff (`142`) | — (planning only, zero schema) | `docs/build-log/phase-02/00_COMMERCIAL_WBS.md` |
| Lead Management (`143`) | `20260723090000_create_commercial_lead_management.sql` | `app.leads`, `capture_lead`, `find_duplicate_leads`, `merge_leads` |
| Prospect Lifecycle (`144`) | `20260723120000_create_commercial_prospect_lifecycle.sql` | `app.prospects`, `convert_lead_to_prospect`, `link_lead_to_existing_prospect` |
| Contact and Activity Management (`145`) | `20260723150000_create_commercial_contact_activity_management.sql` | `app.contacts`, `app.contact_links`, `app.activities`, `resolve_commercial_record_ref` |
| CRM Sales Plan and Pipeline (`146`) | `20260723180000_create_commercial_sales_pipeline.sql` | `app.sales_plans`/`sales_targets`/`forecast_snapshots`/`win_loss_reasons`/`pipeline_outcomes` |
| Opportunity Management (`147`) | `20260723210000_create_commercial_opportunity_management.sql` | `app.opportunities`, `app.opportunity_stage_history`, `opportunities_directory` |
| RFQ and Costing Request (`148`) | `20260724090000_create_commercial_costing_request.sql` | `app.costing_requests`/`costing_request_components`/`costing_responses` |
| Rate and Cost Lookup (`149`) | `20260724150000_create_commercial_rate_cost_lookup.sql` | `app.vendor_rate_versions`, `app.rate_selections` (`ADR-0015`) |
| Margin Calculation (`150`) | `20260724180000_create_commercial_margin_calculation.sql` | `app.margin_rule_versions`, `app.margin_calculations`, `calculate_margin`/`override_margin_threshold` |
| Quotation Builder (`151`) | `20260724210000_create_commercial_quotation_builder.sql` | `app.quotations`, `app.quotation_lines`, `create_quotation_draft`/`submit_quotation` |
| Quotation Versioning (`152`) | `20260724240000_create_commercial_quotation_versioning.sql` | widens `app.quotations` (`root_quotation_id`/`version_number`/`is_current`), `create_quotation_revision` |
| Quotation Approval (`153`) | `20260724270000_create_commercial_quotation_approval.sql` | `app.quotation_approval_rules`, `evaluate_quotation_approval_requirement` (hardened `COM-163`), `decide_quotation_approval_step` |
| Customer Acceptance (`154`) | `20260724280000_create_commercial_quotation_customer_acceptance.sql` | `app.quotation_acceptance_tokens`, `app.quotation_customer_decisions`, first public route `/quote-decision/[token]` |
| Customer and Account Conversion (`155`) | `20260724290000_create_commercial_customer_account_conversion.sql` | `app.accounts` (`ADR-0018`), `app.account_conversions`, `convert_quotation_to_account` (hardened `COM-161`'s `account_id`) |
| Contract and Customer Pricing (`156`) | `20260724300000_create_commercial_customer_contract_pricing.sql` | `app.customer_contracts`, `app.customer_contract_price_components`, `get_effective_customer_price` |
| Credit and Commercial Control (`157`) | `20260724310000_create_commercial_credit_commercial_control.sql` | `app.credit_profiles`/`credit_profile_overrides`/`credit_check_snapshots`, `check_customer_credit` |
| Commercial Dashboard (`158`) | `20260724320000_create_commercial_dashboard.sql` | 7 `app.get_dashboard_*` read functions, zero new table |
| Commercial Reports (`159`) | `20260724330000_create_commercial_reports.sql` | `app.report_types`/`report_runs`, `enqueue_report_export` (queues only, no live worker) |
| Full Lineage into Job Order (`160`) | `20260724340000_create_commercial_job_order_lineage.sql` | `app.job_order_handoffs`, `prepare_job_order_handoff` — **the Phase 3 handoff contract, §3** |
| No-Reentry Enforcement (`161`) | `20260725090000_create_commercial_no_reentry_enforcement.sql` | `app.opportunities.account_id` (FK), `find_existing_accounts_for_lead`/`for_prospect`, `commercial_opportunity_account_ref_drift` |
| Tenant/Security/Financial/Data Hardening (`163`) | `20260726090000_create_commercial_hardening.sql` | widens `evaluate_quotation_approval_requirement` with actor/access-check (High finding closed, `COM-163`) |

**Integrated Commercial Verification (`162`) introduces zero migration** — verification-only, per its own mandate.

### 2.2 Application code (`app/`, `server/` — Commercial's own additions on top of Platform Core's Phase 1 foundation)

- **`server/contracts/<domain>/`** — Zod schemas for every one of the 19 Commercial capabilities' own public shape, including `server/contracts/job-order-lineage/job-order-lineage.ts` — **the exact `JobOrderDraftInput` contract Phase 3 must consume, §3**.
- **`server/queries/`/`server/mutations/`** — typed client wrappers per capability, same two-client architecture (`authenticated` RLS-scoped vs. `service_role`) Platform Core established.
- **`app/(tenant)/[tenantSlug]/commercial/`** — the full Commercial portal: `leads/`, `prospects/`, `contacts/`, `pipeline/`, `opportunities/`, `costing-requests/`, `rates/`, `margin-rules/`, `quotations/`, `approval-rules/`, `approvals/`, `accounts/`, `contracts/`, `credit-approvals/`, `dashboard/`, `reports/`. Shared `_shared/` folder: `activity-timeline.tsx` (polymorphic, `COM-145`), `account-reentry-panel.tsx` (`COM-161`).
- **`app/(public)/quote-decision/[token]/`** — the second public, unauthenticated route this repository adds (after `/login`) — customer-facing accept/reject decision surface (`COM-154`).
- **`lib/portal/commercial-guard.ts`** — the Commercial portal-entry guard, accepting `tenant_admin`+`org_user` layers (distinct from the Tenant Admin portal's own `tenant_admin`-only guard).

**No REST/GraphQL live HTTP route exists anywhere** — unchanged since Platform Core (`PLT-130` remains a contract/logging foundation only).

### 2.3 Verification and hardening evidence (`scripts/db-tests/`, 53 files)

51 individual-capability db-test files (Platform Core's 32 plus Commercial's 19, one per capability, each independently exhaustive for its own scope) plus two Commercial cross-cutting files: `commercial-integrated-verification.sql` (`COM-162`, 6 scenario groups composing 13 capabilities through a two-tenant golden path) and `commercial-hardening.sql` (`COM-163`, 5 scenario groups, the one High finding's own regression evidence). All passing together against one disposable, sequentially-migrated database in a single `pnpm run db:test` invocation.

### 2.4 ADRs (18 ratified, `docs/adr/`)

`ADR-0001`–`ADR-0014` from Phase 0/Platform Core; `ADR-0015` (vendor/service rate lookup ownership, `142`/`149`), `ADR-0016` (CargoGrid default brand identity), `ADR-0017` (adaptive industrial UI + white-label boundary), `ADR-0018` (canonical Account entity shape and ownership, `155`) from Commercial. See `docs/adr/README.md` §6 for the full index.

## 3. The Phase 3 Job Order handoff contract (Prompt 164 §20 task 3 — the primary deliverable of this checkpoint)

See the dedicated companion document: **`docs/build-log/phase-02/JOB_ORDER_HANDOFF_CONTRACT.md`** — the exact `JobOrderDraftInput` schema (field-by-field, with a full synthetic example payload), the `app.prepare_job_order_handoff`/`app.job_order_handoffs_directory` API shape, compatibility notes (schema versioning, masking, idempotency), and the unresolved-dependency list Phase 3 must resolve before it can consume this contract for real (no live Job Order table/route/worker exists anywhere yet — Commercial's own scope stops at producing this one immutable snapshot).

## 4. Known issues carried into Phase 3 (from `docs/runtime/KNOWN_ISSUES.md`, current state — unchanged since the Phase 1→2 handoff)

| ID | Status | Carries into Phase 3 as |
|---|---|---|
| `ISS-2026-005` | `OPEN`, Low | A documentation-completeness gap in `CHANGE_MANIFEST.md` (Prompts 83–90 entries never backfilled, Phase 0-scoped) — does not affect Commercial or any later code/schema/decision; owner DevEx, pick up opportunistically |
| `ISS-2026-007` | `OPEN`, Medium | No working automated dependency/supply-chain audit gate (`pnpm audit` calls a retired npm endpoint at pnpm `10.33.0`) — `pnpm install --frozen-lockfile` remains the real, working deterministic-install control in the interim |
| `ISS-2026-006` | `ACCEPTED_RISK`, Low | 4 historical citations to deleted plural build-log paths, excused via a named allowlist — no action needed |
| All others (`ISS-2026-001..004`, `008`) | `RESOLVED` | No action needed |

**Zero new issue was opened anywhere across the entire Commercial phase** (`COM-142`–`163`, 22 checkpoints). **No Critical or unresolved High-severity issue exists** — the one High finding found (`COM-163`, cross-tenant approval-threshold disclosure) is fully closed, not open. Neither open issue blocks any Phase 3 gate or decision.

**Errors:** `ERR-2026-001..003` (Phase 0) all `RECOVERED`/`SUPERSEDED`. `ERR-2026-004` (repository-wide `PUBLIC` EXECUTE grant) is `RECOVERED`, with its per-migration convention independently re-confirmed intact across all 52 migrations at `COM-162`'s own traceability audit. **Zero `OPEN` error.**

## 5. Environment commands (verified working, this checkpoint)

```
pnpm install --frozen-lockfile   # deterministic install
pnpm run typecheck               # tsc --noEmit
pnpm run lint                    # eslint .
pnpm run test                    # node:test, scripts/**|server/**|lib/**|tests/**/*.test.ts
pnpm run test:e2e                # Playwright + axe-core (sandbox chrome-headless-shell gap, unchanged since PLT-117)
pnpm run db:test                 # bash scripts/db-tests/run.sh -- 52 migrations + 53 test files, disposable DB
pnpm run docs:check              # scripts/docs/check-doc-links.ts
pnpm run security:check          # scripts/security/check-secrets.ts
pnpm run data-classification:check
pnpm run threat-model:check
pnpm run standards:check         # scripts/standards/check-suppressions.ts
pnpm run git:check-paths         # scripts/git/check-protected-paths.ts (known false positive on any new migration file, see §6)
```

`db:test` requires a reachable Postgres with PostGIS available (`postgresql-<major>-postgis-3` locally; CI uses `postgis/postgis:17-3.4`). **This checkpoint's own sandbox had neither pre-installed** — both were provisioned fresh at `COM-161` and remain installed for the rest of this session; a genuinely fresh sandbox must repeat that provisioning step before `db:test` can run past the PostGIS migration. All gate results as of this checkpoint: see `docs/build-log/phase-02/COM-164.md` §6 (live gate run) — do not treat any specific `node:test`/`db:test` count in this document as durable; read the live gate output.

## 6. Residual risks Phase 3 should be aware of (not blocking, all already-disclosed across COM-143..163's own build logs)

- **No standalone canonical address/site master exists** — `billing_address` is a jsonb snapshot duplicated by design across `app.prospects`, `app.accounts`, and `app.quotations.customer_snapshot` (`COM-145`'s own disclosed deferral, re-disclosed at `COM-155`). Phase 3 (or a later Commercial capability) should build one durable, reusable site/address master when a real multi-site requirement first appears — not before.
- **No FX/multi-currency conversion anywhere in Commercial** — `app.calculate_margin` fails closed (`mixed_currency`) unless selling currency exactly matches the pinned cost snapshot's own currency (`COM-150`'s own disclosed boundary). A future capability needing real currency conversion must design it from scratch.
- **Quotation line editing is add/remove, not in-place edit** (`COM-151`'s own disclosed boundary) — unchanged through `163`.
- **The Configurable Numbering Engine (`PLT-125`) was never adopted for Commercial** — `app.next_quotation_number()` is a bounded, tenant-scoped monotonic counter instead, a disclosed alternative (`COM-151`).
- **The bounded rule-expression evaluator was never built** (`PLT-121` §25, `ADR-CAND-ARCH-014`/`015`) — every Commercial threshold/rule (margin minimums, quotation-approval thresholds, credit limits) is bespoke `plpgsql`, not a generic evaluated expression. The first capability needing real dynamic business-rule authoring must design this from scratch.
- **Commercial Reports' export path is queue-only** — `app.enqueue_report_export` reaches `status=queued` and stops there; no live worker processes the `report_generation` job type anywhere in this repository (the same disclosed `NOT_RUN` condition every Platform Core job type carries since `PLT-132`). Of the ten report subjects Prompt 159 §4 names, only the seven `COM-158`'s dashboard already computes are implemented — conversion/costing/pricing reports are a disclosed gap.
- **No live Configuration-Engine-authored approval-routing UI exists** — Quotation Approval (`COM-153`) and Credit (`COM-157`) both reuse `PLT-121`/`123`'s generic RPCs directly with zero dedicated Commercial authoring screen, the same "ships with zero authoring UI" precedent `PLT-123` itself set.
- **`app.job_order_handoffs.downstream_reference`/`delivered_at` are real, structurally-ready columns, currently always null** — no Phase 3 Job Order consumer exists yet to populate them (§3).
- **RPD-022** (Supreme Admin absolute CRUD) — unchanged from Platform Core; no tamper-proof/immutability claim may ever be made anywhere in Commercial either.
- **No live Supabase project exists anywhere** — unchanged from Platform Core; a real sign-in flow, real RLS-against-a-live-database session, and real deploy pipeline all remain `NOT_RUN`.
- **`pnpm run test:e2e` has the same persistent, disclosed sandbox condition** since `PLT-117` — `chrome-headless-shell` executable missing. Every Commercial E2E-relevant spec (none currently exist — no `test:e2e` spec was added anywhere in Commercial; disclosed, not an oversight) would hit the identical gap.
- **`git:check-paths` false-positives on any brand-new migration file** — reproduces identically at every Commercial checkpoint that added one (`COM-151..163`); not a real protected-path violation, disclosed at each occurrence.

## 7. Corrections made this checkpoint (disclosed, not hidden)

None found. Unlike the Phase 1→2 handoff (which corrected 3 stale `ADR-CAND-ARCH-*` citations), this checkpoint's read-back of `docs/adr/README.md` §5.2/§6, `docs/runtime/KNOWN_ISSUES.md`, and every Commercial build log found no stale citation, no missing evidence link, and no orphaned reference — `COM-162`'s own traceability audit (§4 of that build log) already confirmed zero orphan immediately before this checkpoint, and nothing changed in the interim beyond `COM-163`'s own bounded fix.

## 8. Forbidden-scope confirmation (Prompt 164 §12/§24, re-checked this checkpoint)

`git ls-files app/ lib/ server/ components/ | grep -iE "job_order|jobs_order|shipment|invoice|payment|procurement|vendor_bill|purchase_order|hris|payroll"` returns **zero matches** (re-run directly this checkpoint) — zero Operations/Finance/Procurement (or any later-phase) domain concept exists anywhere in application code; even Commercial's own `job-order-lineage` service files (hyphenated, `server/contracts|queries|mutations/job-order-lineage.ts`) fall outside this underscore-based pattern, confirming no literal "Job Order domain" naming exists in code at all — only the disclosed handoff *record* (`app.job_order_handoffs`, database-side, cited in §2/§3) exists, never a Job Order table/route/domain module (`COM-160`'s own explicit forbidden-scope confirmation, re-verified unchanged through `163`).

## 9. Fresh-context reconstruction check (Prompt 164 §21/§28, rehearsed this checkpoint)

Reading only this document plus its cited paths (no other session context), an agent can determine: what phase the repository is in (Phase 2, pending Prompt 165 closure), what exists on disk (§2), the exact contract Phase 3 must consume and how (§3, companion document), what is decided vs. still open (§2.4, §6), what commands verify the current state (§5), what the exact next prompt is once Phase 2 formally closes (Prompt 165, `CG-S7-COM-024` — already dependency-`READY` and authorized under this session's "Commercial WBS through phase closure" range), and what residual risks/design boundaries to respect rather than "fix" without re-reading history first (§6). This satisfies Prompt 164 §21's "fresh Phase 3 agent reconstructs Commercial and safely starts exact next task."
