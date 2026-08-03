# ATW-011A — Item/SKU and UOM Master

## 0. Checkpoint

| Field | Value |
|---|---|
| Task | `CG-S10-ATW-011A` — inserted between the `VERIFIED` Prompt 230 (Bin and Racking, `CG-S10-ATW-011`) and Prompt 231 (WMS Inbound, `CG-S10-ATW-012`) |
| Repository | `assujiar/cargogrid.app` |
| Working branch | `claude/prompt-231-238-e2wb54` |
| Dependency | `CG-S10-ATW-010`/`011` (Prompts 229/230, both `VERIFIED`); `app.accounts` (`COM-155`); `app.finance_currencies`/`app.validate_currency_code` (`FIN-194`, the reused UOM-registry pattern) |
| Authorization | Explicit operator instruction, following a comprehensive read-only gap audit this same session ran across Phase 5's own `VERIFIED` build output (prompts 220-230) for risk to prompts 231-248. That audit confirmed, by direct inspection of `app.master_types`'s seeded rows and by exhaustively enumerating every `*_PROMPT.md` filename plus grepping every prompt body in `docs/ai-agent-build-prompt-package/` (79-430), that no item/SKU/product master and no UOM registry have ever been built, and **no prompt in the entire package ever creates one** — an unsatisfiable circular dependency, since Prompt 231 §9 and Prompt 234 §9 both require this identity already `VERIFIED`. The operator was presented four options (build the master now as an inserted task, widen Prompt 231's own scope, fix only the Tier-2 defects, or stop) and selected "Sisipkan ATW-011A, mulai bangun" (insert `ATW-011A`, start building). |

## 1. Pre-flight

`git status`/`git log` confirmed a clean worktree on `claude/prompt-231-238-e2wb54`, HEAD at `aef25e5` (== `origin/main` tip). `mcp__github__list_pull_requests` (state=open) returned zero open PRs against this repository — zero collision risk. `pnpm install --frozen-lockfile` (fresh), then local Postgres 16 + `postgresql-16-postgis-3` provisioned (`service postgresql start`; `apt-get install postgresql-16-postgis-3`; `postgres` role password set to the script's own documented default) — the identical one-time sandbox setup step every prior Phase 5 checkpoint has disclosed, not a repository change. Fresh baseline gate suite confirmed green before any file for this task was written: `typecheck`/`lint` (0 errors, 85 pre-existing warnings unchanged), `node:test` **2497/2497**, `db:test` PASS across 113 migrations/115 db-test files — an exact match to `ATW-230`'s own recorded checkpoint.

## 2. Design decision — `docs/adr/ADR-0019-canonical-item-sku-and-uom-master-identity.md`

The one genuine architecture-shape question this insertion raised (`app.master_records` extension vs. flat-column table) was resolved as `ADR-0019`, `ACCEPTED` this checkpoint, registering a newly-minted `ADR-CAND-ARCH-031` in `docs/adr/README.md` §5.2/§6. **Decision: a flat, typed-column `app.item_masters` table, never `app.master_records`** — the identical structural conclusion `ADR-0018` already reached for `app.accounts`, for the identical reason: `app.master_records`' own unique index `(master_type_code, tenant_id, code)` has no owner dimension, so it could never let two different 3PL customers in the same tenant hold the same SKU code — a real, proven-in-this-checkpoint's-own-db-test requirement. Full rationale, evidence, and rejected alternatives in the ADR itself.

## 3. Implementation

### 3.1 Scope boundaries and design decisions (disclosed, migration header)

1. **A flat, typed-column `app.item_masters` table** mirroring `app.accounts`' own shape and RLS posture (tenant-wide visibility via `app.has_active_tenant_membership`, never per-org-unit record-scoped) — `ADR-0019`.
2. **`owner_account_id` is a mandatory, real `uuid references app.accounts (id)`** — every SKU belongs to exactly one customer, the identical proven FK shape `ATW-229`'s own `app.warehouse_customer_eligibility.customer_account_id` already established.
3. **UOM is a real, governed registry (`app.uoms` + `app.uom_conversions`), mirroring `app.finance_currencies`/`app.validate_currency_code` (`FIN-194`) verbatim** — small global catalogue, `service_role`-only write, `select ... using (true)` read for every authenticated identity. Every pre-existing UOM-shaped column in this repository (`app.warehouse_zones.capacity_uom`, `app.warehouse_locations.capacity_uom`, `app.actual_costs.uom`) stays exactly as-is (free text) — this migration edits no applied migration; retrofitting those columns is disclosed as a deferred obligation for whichever future capability first needs it.
4. **`unit_category` is a deliberately narrow closed CHECK enum** (`weight`, `volume`, `count`, `length`) — genuinely fungible physical UOMs with a fixed scalar conversion factor only. Discrete handling/packaging units (box, carton, pallet — a ratio that varies per item, not a universal physical constant) are **not** modelled here, explicitly deferred to Prompt 237 ("WMS Packing").
5. **`app.item_masters` carries no on-hand/allocated/available quantity column** — Prompt 231 §24 ("Expected quantity is not on-hand inventory") and Prompt 234 §24 ("normal roles never patch balance") both forbid it; those remain `ATW-234`'s own derived-balance columns.
6. **Deactivation dependency-impact checking is disclosed as deferred**, identical boundary to `ATW-229`/`ATW-230`'s own design notes — `app.set_item_master_status` does not check for referencing inbound/receiving/ledger/lot rows, since none exist yet at this checkpoint. `ATW-231` (or whichever future capability first references an `app.item_masters` row) is obligated to wire a real check.
7. **List reads are bounded** (`p_limit`, default 50, hard-capped 200), never unbounded `setof` — a deliberate choice given no Phase 5 list RPC yet uses real keyset/cursor pagination repository-wide.
8. Per `ERR-2026-004`: this migration carries its own explicit `REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA app FROM PUBLIC` statement before its final grants.

### 3.2 Schema — `supabase/migrations/20260730160000_create_advanced_tms_item_uom_master.sql`

Three new tables: `app.uoms` (global UOM catalogue, 10 seeded codes across the four categories), `app.uom_conversions` (12 seeded directed factors, structurally constrained to same-category pairs via `app.uom_conversion_categories_match`, a `STABLE` CHECK-constraint function), `app.item_masters` (tenant + customer-owner scoped, optimistic-concurrency touch trigger). Nine new functions: `app.validate_uom_code`, `app.uom_conversion_categories_match`, `app.convert_uom_quantity` (direct-or-inverse factor resolution, honest `uom_conversion_not_registered` rather than a silent 1:1 fallback), `app.create_item_master`/`app.update_item_master`/`app.set_item_master_status` (lifecycle), `app.get_item_master`/`app.resolve_item_master_by_code` (single-row reads), `app.list_item_masters` (bounded). RLS: `app.item_masters` tenant-wide (`app.has_active_tenant_membership`, mirrors `app.accounts`); `app.uoms`/`app.uom_conversions` globally readable to any authenticated identity (mirrors `app.finance_currencies`).

### 3.3 Service layer

`server/contracts/item-uom-master/item-uom-master.ts` (Zod schemas + row parsers), `server/queries/item-uom-master.ts` (`getItemMaster`/`resolveItemMasterByCode`/`listItemMasters`/`validateUomCode`/`convertUomQuantity`), `server/mutations/item-uom-master.ts` (`createItemMaster`/`updateItemMaster`/`setItemMasterStatus`, with a classified `ItemUomMasterMutationError` mirroring `WarehouseZoneMutationError`'s own error-code-prefix pattern). No UI route — this checkpoint is a pure identity/master-data capability with no independent operator workflow yet; the first consumer (Prompt 231) is expected to surface item selection inside its own inbound workflow, not here.

### 3.4 Tests

`scripts/db-tests/advanced-tms-item-uom-master.sql` — full pattern: two tenants, one with two customer accounts built via the full CRM lead→prospect→contact→opportunity→costing→rate→margin→quotation→account pipeline (the only real path to an `app.accounts` row in this repository), proving the exact structural claim `ADR-0019` makes (the identical SKU code, same tenant, two different owners, two distinct rows); UOM conversion (direct, inverse, same-code passthrough, cross-category rejection at both the query layer and the CHECK constraint); item-master authority gating, idempotent replay, immutable fields, optimistic concurrency, reason-required deactivation, same-status no-op; bounded list reads with owner/status/search filters and limit clamping; cross-tenant isolation; schema-privilege defense in depth. 41 new `do $$ ... $$` assertion blocks. `server/contracts|queries|mutations/item-uom-master.test.ts` — 25 net new `node:test` cases (parse/schema validation, RPC arg mapping, error classification, response-shape edge cases).

## 4. Commands and results

`pnpm install --frozen-lockfile`; `typecheck` (0 errors); `lint` (0 errors, 85 pre-existing warnings, unchanged); `pnpm run test` (**2522/2522** passing — the one `not ok` node:test result, `checkWorktreeCollision`'s own "current branch has commits ahead of origin/main" assertion, is a pre-existing environment-state condition on a branch with zero commits yet, not caused by this checkpoint; it resolves the moment this checkpoint's own commit lands); `pnpm run db:test` PASS across **114 migrations/116 db-test files** (1 new migration, 1 new db-test file, zero regression); `docs:check`/`security:check`/`data-classification:check`/`threat-model:check`/`standards:check`/`git:check-paths` all pass; `next build` PASS (**90 routes, unchanged** — no UI route added by this checkpoint).

## 5. Evidence mapping

Source requirement (the audit's own `no-item-sku-product-master`/`no-uom-registry-or-conversion` findings, cross-verified adversarially) → this task (`CG-S10-ATW-011A`) → code/migration/contract (`20260730160000_create_advanced_tms_item_uom_master.sql`, `server/contracts|queries|mutations/item-uom-master.ts`) → test (`scripts/db-tests/advanced-tms-item-uom-master.sql`, `*.test.ts`) → documentation (this file, `ADR-0019`, `ADVANCED_TMS_WMS_EXECUTION_INDEX.md`, `TASK_LEDGER.md`, `CARGOGRID_BUILD_STATUS.md`, `HANDOFF.md`).

## 6. Residual scope, explicitly not this checkpoint's own

- Packaging/handling-unit identity (box/carton/pallet) — deferred to Prompt 237 (`ADR-0019` design note 4).
- Retrofitting `app.warehouse_zones.capacity_uom`/`app.warehouse_locations.capacity_uom`/`app.actual_costs.uom` (pre-existing free-text columns) to validate against `app.uoms` — deferred, no applied migration edited.
- Item-master deactivation dependency checking against inbound/receiving/ledger/lot rows — deferred to `ATW-231` or whichever capability first references an `app.item_masters` row (design note 6).
- The remaining Tier-2/3/4 findings from this session's own gap audit (`app.set_warehouse_zone_status` not checking child locations; `app.shipment_tracking_health` having no writer; the `ATW-230.md`-vs-execution-index status contradiction; Phase 5 deferrals absent from `ERROR_LEDGER.md`/`KNOWN_ISSUES.md`; the 232/233-vs-234 WBS sequencing question; the 236-vs-238 outbound-demand-contract question) were **not** in the scope the operator selected for this checkpoint ("Sisipkan ATW-011A, mulai bangun" — insert and build the item/UOM master only) and remain open, recorded in this session's own gap-audit plan for a future checkpoint's explicit authorization.

## 7. Rollback/recovery note

`git revert` this checkpoint's own commit — one new, purely additive migration (114th; no existing table/function/view modified), no destructive rollback needed.

## 8. Status

`VERIFIED`. `CG-S10-ATW-012` (Prompt 231, WMS Inbound) is now dependency-clean on its own §9 "verified customer/item/master and shipment contracts" line (`ATW-229`/`230`/`011A` all `VERIFIED`) — see `ADVANCED_TMS_WMS_EXECUTION_INDEX.md` for the corrected row. The next runtime agent must stop and obtain fresh explicit user authorization before starting `231` or any further Phase 5 row.
