# Phase 6 → WBS Steps 12–14 Handoff Contract

**Produced by:** `CG-S11-PRC-021` (Prompt 270, Procurement/Vendor Documentation and Handoff), per Prompt 270 §20's own "Create explicit Step 12 employee, Step 13 portal and Step 14 AI/enterprise handoffs" deliverable.
**Structure:** mirrors `docs/build-log/phase-05/STEPS_11_14_HANDOFF_CONTRACT.md`'s own precedent (itself mirroring `docs/build-log/phase-02/JOB_ORDER_HANDOFF_CONTRACT.md`'s own structure) — this document explains and exemplifies the real, already-`VERIFIED` contract surfaces; it does not redefine them. If this document and a cited migration/contract file ever disagree, the migration/contract file is authoritative.
**Phase-to-step mapping** (`docs/runtime/CARGOGRID_BUILD_STATUS.md` §3, "Phase status" table, and Prompt 271 §25's own confirmation): Step 12 = Phase 7, HRIS/Ticketing; Step 13 = Phase 8, Customer Portal/Loyalty; Step 14 = Phase 9, Intelligence/Enterprise. All three phases are `NOT_STARTED` as of this checkpoint — zero HRIS/Ticketing/Customer-Portal/Loyalty/Intelligence/Enterprise domain code exists anywhere in this repository (re-confirmed below, §6).

## 1. What this contract is, and is not

Phase 6's own domain is vendor-facing, internal-tenant-staff-facing governance — a materially different shape from Phase 5's own one real, shipped, read-only Step 13 contract (Customer Inventory Access, `ATW-023`). Phase 6 ships **zero** built contract for any of Steps 12–14. This is disclosed honestly for each of the three pairings below, exactly mirroring the precedent `docs/build-log/phase-04/FINANCE_DOWNSTREAM_CONTRACTS.md` set for its own "no relationship" and "future, undesigned" cases (Finance's own §3/§4, summarized in `FINANCE_HANDOFF_PACKAGE.md` §3), and how Phase 5's own document disclosed an *undesigned* Step 12 relationship rather than inventing one. Nothing below should be read as a design proposal — every "what might a future step read" note is a disclosed plausible-future observation, not a built or committed shape.

## 2. Step 12 (Phase 7, HRIS/Ticketing) — no relationship built, disclosed rather than omitted

**Phase 6 has no direct dependency relationship with Phase 7, and no Phase 6 build log, prompt, or migration anywhere names HR, HRIS, Ticketing, or an employee/worker-shaped record distinct from `app.master_records` identity.** Confirmed by direct grep this checkpoint (§6 below returns zero matches for `hris|employee_profile|ticketing`).

### 2.1 What exists that a future HR domain might eventually care about

Read literally, this is **weaker** than Phase 5's own equivalent section (which at least had `app.driver_operational_profiles` as one real "worker" operational record). Phase 6's own actors — procurement staff, assessors, reviewers, approvers, checkers, MFA-reauthenticating deciders — are represented **exclusively** as `auth_user_id` references into the platform's own pre-existing identity/role system (`app.principal_memberships`/`app.role_assignments`, Platform Core), never as a Phase-6-owned worker record. `PRC-251`'s own maker-checker identity fields (`created_by_auth_user_id`, `reviewed_by_auth_user_id`, `approved_by_auth_user_id`, and their siblings across every one of the 25 Phase 6 migrations) are all bare UUID foreign-key-shaped references, never a Phase-6-owned "who is this person" table.

The single closest thing to a "worker as data" concept anywhere in Phase 6 is `app.vendor_assessment_corrective_actions`/`app.claim_responsibility_reviews`-style finding attribution (PRC-252) — but this attributes a *finding about a vendor*, never a finding about an internal staff member's own performance, and carries no visibility any future disciplinary/HR process reads today.

### 2.2 Explicitly forbidden mutations

- No future HR/Ticketing capability may write to `app.vendor_profiles`, `app.vendor_assessments`, or any other Phase 6 table to represent an internal employee/worker record — none of Phase 6's own tables model an internal staff identity; every actor field is a read-only reference into Platform Core's own identity system, and Phase 6's own RPCs are the only sanctioned write path for their own domain rows.
- No future HR/Ticketing capability may write to `app.role_assignments`/`app.principal_memberships` on Phase 6's own behalf to simulate a "procurement worker" role — role assignment remains entirely Platform Core's own governed surface, unmodified by any Phase 6 migration.

### 2.3 Contract surface

**None exists.** This is a disclosed future non-relationship, not a built one — the same honesty convention `FINANCE_HANDOFF_PACKAGE.md` §3/`STEPS_11_14_HANDOFF_CONTRACT.md` §3 both applied to their own respective Step 12 pairings.

### 2.4 Unresolved dependency list

1. Whether a future HR/personnel domain ever needs visibility into which internal staff identity performed a given Procurement action (assessor, approver, reviewer) — undesigned; today this is retrievable only via the generic `app.audit_logs`/`app.capture_audit_event` trail every domain already writes to, never a Phase-6-specific surface.
2. Whether "procurement staff/approver" ever becomes a formally HR-tracked role/position distinct from its current pure RBAC-permission-grant shape (`PRC:Create`/`PRC:Approve`/etc.) — undesigned, no schema exists for it.
3. Whether a future Ticketing capability ever needs to open a ticket against a Procurement governance exception (e.g. an escalated compliance waiver, an unresolved vendor dispute) — undesigned; `app.vendor_compliance_waivers`/`app.vendor_bill_match_cases`'s own exception/dispute states are Phase-6-internal today, with no outward-facing ticket-creation hook.

## 3. Step 13 (Phase 8, Customer Portal/Loyalty) — no relationship built, disclosed rather than omitted

**Phase 6's own domain is vendor-facing, not customer-facing.** No Phase 6 RPC, table, or route is reachable by, or was designed for, a `customer_user`-layer principal. Every new table's RLS `select` policy carries the hardened default-deny form (`app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id), or app.is_supreme_admin()`) — a `customer_user`-layer principal is structurally excluded from every Phase 6 table from creation, confirmed present across all 25 migrations by the same pattern every prior Phase 6 build log's own hardened-patterns section documents.

### 3.1 What is plausible-future, honestly disclosed as undesigned

A customer, in principle, could plausibly one day want to know "which vendor fulfilled my shipment" or see a vendor-performance-derived reliability signal (e.g. an on-time-delivery percentage) as part of a future Customer Portal experience — the same class of speculative future read Phase 5's own `STEPS_11_14_HANDOFF_CONTRACT.md` §4 disclosed for its own dashboard-shaped reads. **No such read is designed, built, or exposed anywhere in Phase 6.** Confirmed by direct grep this checkpoint: neither `app.lookup_public_shipment_tracking` (Operations' own public, anonymous, sanitized tracking projection, `OPS-180`, widened repeatedly through Phase 5) nor `app.evaluate_customer_inventory_access`/its 13-RPC surface (`ATW-023`, Phase 5's real, shipped Step 13 contract) references any vendor-shaped table, vendor identity, or `app.vendor_*` column — zero matches for `vendor` across either surface's own migration. A future customer-facing "fulfilled by [vendor]" or vendor-reliability signal would be an entirely new design, not an extension of anything Phase 6 built.

### 3.2 Explicitly forbidden mutations

- No future Customer Portal capability may grant a `customer_user`-layer principal any RLS exception on a Phase 6 table — every Phase 6 table's own default-deny predicate is a deliberate, structural exclusion (§3 above), not an oversight to "fix."
- No future Customer Portal capability may bypass Phase 6's own RPC layer to read vendor identity/rate/performance data directly against a Phase 6 table for a customer-facing surface — if this pairing is ever designed, it needs its own dedicated, sanitized read RPC (mirroring `app.lookup_public_shipment_tracking`'s or `ATW-023`'s own precedent), never a widened RLS policy on an internal-governance table.

### 3.3 Contract surface

**None exists.** A disclosed real future dependency, not a built one.

### 3.4 Unresolved dependency list

1. Whether a customer ever sees which vendor fulfilled their shipment at all — a real product/privacy decision (vendor identity may be considered the tenant's own competitive/operational information, not automatically customer-shareable), entirely undesigned.
2. Whether a vendor-performance-derived reliability signal (e.g. `app.vendor_kpi_scorecards.band`/`composite_score`, PRC-264) is ever surfaced to a customer, in aggregate or per-shipment form — undesigned, no sanitization/anonymization layer exists for it.
3. Whether Phase 8, if it ever needs either of the above, extends Phase 6's own existing masking conventions (`PRC:View cost`-style gates) or builds an entirely separate customer-facing projection (the `ATW-023` precedent, a dedicated read RPC layer, never a direct table grant) — undesigned; the `ATW-023` precedent is the one concretely-named seam to consider first.

## 4. Step 14 (Phase 9, Intelligence/Enterprise) — no contract designed, one named natural future input

**No Phase 6 build log, prompt, or migration anywhere names Intelligence, Enterprise, or BI.** Disclosed explicitly, mirroring `FINANCE_HANDOFF_PACKAGE.md` §4's and `STEPS_11_14_HANDOFF_CONTRACT.md` §5's own treatment of their respective phases' identical undesigned relationship with Phase 9.

### 4.1 What exists that a future analytics domain might eventually read

Phase 6's own Dashboard and Reports capability (`PRC-266`, Prompt 266) is the single most obviously analytics-adjacent surface in the whole phase — a real, already-`VERIFIED`, versioned metric-definition catalogue:

- **`app.procurement_metric_definitions`** — a root+version-collapsed, code-shipped (Supreme-registered, never tenant-authored) catalogue, 11 seeded rows, one per metric, each citing its real source tables/columns, formula, grain, freshness rule, and the exact existing PRC action gate it requires. Mirrors `app.report_types`' own registration shape (`COM-159`), extended into Procurement's own capability.
- The 10 real summary/list RPC groups it wires: vendor status/risk/compliance-expiry (`app.get_procurement_dashboard_vendor_risk_summary`, `app.list_procurement_vendor_risk_dashboard_rows`), rate validity/competitiveness, RFQ response rate/cycle time, capacity/acceptance, PO/contract, performance (reusing `app.vendor_kpi_scorecards.band`/`composite_score` verbatim, PRC-264, never a second scoring engine), and match variance/exception rate (reusing `app.get_vendor_bill_match_reconciliation_status` verbatim, PRC-265).
- **`app.enqueue_procurement_report_export`** — reuses the existing generic Background Job Framework (`PLT-132`) and shared `app.report_types`/`app.report_runs` (`COM-159`) directly, the identical shared infrastructure a future Phase 9 aggregation layer reading across Commercial/Finance/Operations/Procurement's own registered report codes would need no new Phase-6-side table to read from.

None of these were designed with a cross-tenant or aggregate-analytics consumer in mind — every one enforces per-tenant RLS and per-caller RBAC exactly as every other Phase 6 read path does, and pulling data across tenants for analytics purposes (if that is ever Phase 9's own model) is not a pattern anything in Phase 6 has been built or tested against — the identical disclosed boundary Phase 5's own `STEPS_11_14_HANDOFF_CONTRACT.md` §5.1 recorded for its own dashboard-shaped reads.

### 4.2 Explicitly forbidden mutations

None specifically designed, since no contract exists. The general rule that applies until one is designed: any future Phase 9 capability must be read-only against every Phase 6 table, and must respect the same `PRC:View cost`/`PRC:View personal data`/RLS/entitlement boundaries this document describes elsewhere (§3 above) when aggregating data that touches sensitive fields — in particular, `app.vendor_bank_accounts`/`app.vendor_tax_identities`' own encrypted columns (`PRC-254`) must never be readable by any future analytics aggregation path; only the three plaintext masked/last-4 columns and the downstream `app.get_vendor_financial_verification_status` boolean projection are ever safe to aggregate.

### 4.3 Contract surface

**None exists.** A disclosed real future dependency, not a built one.

### 4.4 Unresolved dependency list

1. Whether Phase 9 reads Phase 6's operational tables directly (requiring a new, audited cross-tenant/aggregate read path) or via a data-warehouse/ETL layer outside the live transactional schema — undesigned, no decision has been made either way, mirroring Phase 5's own identical open question.
2. Whether `app.procurement_metric_definitions`' own 11-metric catalogue becomes a literal Phase 9 ingestion source (one metric = one BI dimension) or Phase 9 builds its own independent metric taxonomy — undesigned.
3. Whether vendor-performance/rate-competitiveness signals ever feed a cross-domain risk/spend-analytics product — undesigned, no schema exists for it.
4. Whether the currency-normalization machinery this phase's own hardening pass built (`app._evaluate_procurement_currency_threshold`, `PRC-269`) is a pattern any future Phase 9 multi-currency aggregation should reuse — a real, tested precedent exists to point to, but no decision has been made that Phase 9 must use it.

## 5. A note specific to Phase 6's own real, non-hypothetical downstream contract: Phase 2/4 extension boundaries, not Step 12–14

Unlike Phase 5 (whose real Step 13 contract was genuinely new, forward-looking, shipped code), Phase 6's own real, load-bearing downstream relationships are **backward** — to already-`VERIFIED` Phase 2 (Commercial) and Phase 4 (Finance), not to any of Steps 12–14. `ADR-0020` (canonical vendor identity extends Phase 3/4's `master_type_code='vendor'`, never a new master), the `app.vendor_rate_versions` additive extension of `COM-149` (Phase 2), and the zero-write, read-only extension of `app.finance_vendor_bills` (`FIN-200`, Phase 4) are the real contract surfaces Phase 6 built against — all already documented in each capability's own build log and not restated here, since this document's own scope (per Prompt 270 §20) is Steps 12–14, forward, not the already-closed Phase 2/4 relationship backward.

## 6. Forbidden-scope confirmation (re-checked this checkpoint)

```
git ls-files app/ lib/ server/ components/ | grep -iE "hris|employee_profile|ticketing|customer_portal|loyalty|intelligence_enterprise|business_intelligence"
```

returns **zero matches** (re-run live this checkpoint, exit code 1/no output) — zero HRIS/Ticketing, Customer-Portal/Loyalty, or Intelligence/Enterprise domain concept exists anywhere in application code. A supplementary check this checkpoint also ran directly (not part of the mandated pattern above, added because §3's own claim depends on it), **corrected during this fix round after independent re-verification**: this document's own first-pass text cited `grep -n "vendor" supabase/migrations/20260730310000_create_advanced_tms_customer_inventory_access.sql supabase/migrations/2026072[7-9]*shipment_tracking*.sql` as returning "zero matches." Re-run exactly as written, that command errors instead — `grep: supabase/migrations/2026072[7-9]*shipment_tracking*.sql: No such file or directory` (exit code 2) — because the glob matches zero files in this repository: `app.lookup_public_shipment_tracking`'s original defining migration is `20260728130000_create_operations_public_tracking.sql`, whose filename contains no `shipment_tracking` substring, so the glob's own filename fragment never matches it (its `20260728` date prefix does fall inside the intended `2026072[7-9]` range, but that alone is not enough). The command as originally documented cannot have produced "zero matches"; it never ran successfully. The corrected command, re-run live this fix round — `grep -in vendor supabase/migrations/20260730310000_create_advanced_tms_customer_inventory_access.sql supabase/migrations/20260728130000_create_operations_public_tracking.sql` — returns exactly two hits, both in `20260728130000`'s own header-comment prose explicitly describing vendor/cost/internal data as *excluded* from the public tracking projection ("...vendor, cost, and sensitive contact data. Only..." / "...vendor, cost, internal exception notes, or sensitive contact data)."), never a real leak. `app.lookup_public_shipment_tracking` was in fact redefined twice more as its own projection widened through Phase 5 (`20260730100000_create_advanced_tms_fleet_control_tower.sql`, `20260730130000_create_advanced_tms_milestone_exception_telemetry.sql`); isolating all three function-body definitions specifically (not just the migration files' surrounding prose) confirms zero `vendor`-shaped reference inside any of the three bodies — the narrower, function-body-scoped sub-claim this section exists to support. §3.1's underlying conclusion (no customer-facing read anywhere in this repository today exposes vendor identity) still holds; only the originally-documented reproduction command was broken and has been corrected here.
