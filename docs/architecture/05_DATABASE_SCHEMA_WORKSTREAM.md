# 05 — Database Schema Workstream

**Prompt:** `CG-S3-ARCH-005` (`CG-AABPP-ARCH-040` v0.4.0)
**Runtime output of:** `docs/ai-agent-build-prompt-package/03-architecture-and-plan/40_DATABASE_SCHEMA_WORKSTREAM_PROMPT.md`
**Status:** `VERIFIED`

## 0. Checkpoint

| Field | Value |
|---|---|
| Repository | `assujiar/cargogrid.app` |
| Working branch | `agent/cargogrid-autonomous-build` |
| HEAD at authoring time | `a159ad7d77b876a13ef8759c5efacfee7ea88890` (parent of this checkpoint's commit) |
| Precondition | `docs/architecture/01_*.md` through `04_*.md` all `VERIFIED` |
| Repository state | Unchanged: zero database, zero migration, zero schema (`docs/discovery/04_DATABASE_MIGRATION_BASELINE.md`) |
| Mutation performed | **NONE** — this is a planning document only; no migration was created or applied (prompt precondition, verified) |

### Inputs read (beyond `01–04_*.md`, already fully loaded)

- Tech Arch §9 (Database Architecture, full: schema strategy, core tenant columns, domain boundaries, FKs, soft delete, temporal data, event/audit log)
- Tech Arch §11 (RLS, full: principles, helper functions, **example policy on `app.shipments`**, testing)
- Tech Arch §24 (Financial Integrity, full: double-entry, draft/posted states, subledger/GL, multi-currency, idempotent posting key)
- Tech Arch §32.6 (Index Strategy, full — **concrete example indexes on `app.shipments`, `app.shipment_milestones`, `app.invoices`, `app.audit_logs`, `app.vendor_rates`**), §32.7 (query plan review), §25.4 (pagination)
- `docs/discovery/04_DATABASE_MIGRATION_BASELINE.md` (confirms zero existing schema/migration)

## 1. Scope and method — and one correction to a prior recommendation

No table, column, or migration is created by this document (prompt precondition). Every entity below is already named in `02_CANONICAL_DATA_FLOW_MAP.md` §2's canonical entity register or its §14 data-dictionary sources; this document adds only the schema-level design layer (keys, constraints, indexes, migration sequencing) around what 01–04 already established.

**Correction:** `03_DOMAIN_BOUNDARY_MAP.md` §3's "Table/schema namespace" column (`commercial.*`, `operations.*`, `finance.*`, ...) and its `ADR-CAND-ARCH-007` (§11) recommended PostgreSQL schema-per-domain, marked `ADR_REQUIRED`. Direct evidence gathered for **this** prompt contradicts that recommendation: Tech Arch §11.3's example RLS policy and §32.6's example indexes both consistently use a **single flat `app` schema** with unprefixed, business-meaningful table names (`app.shipments`, `app.shipment_milestones`, `app.invoices`, `app.vendor_rates`, `app.audit_logs`), not per-domain schemas. Per this repository's evidence-precedence rule, concrete SQL evidence in the blueprint outranks an earlier speculative recommendation this build agent made in Prompt 38. §3 below formally resolves `ADR-CAND-ARCH-007` in favor of the evidenced single-schema convention, and `04_REPOSITORY_TARGET_STRUCTURE.md`'s `server/` folder layout (organized by domain at the *application* layer, not the database layer) is unaffected — only `03_*.md`'s namespace column is superseded, via a short amendment note (see this checkpoint's change entry) rather than a full rewrite of that already-`VERIFIED` document.

## 2. Schema principles

Reproduced from Tech Arch §9.2 (Core Tenant Columns, verbatim) — every tenant-owned table carries these columns unless explicitly exempted:

| Column | Purpose | Required in |
|---|---|---|
| `tenant_id` | Primary tenant isolation | All tenant-owned tables |
| `company_id` | Multi-company scope | Customer, shipment, finance, HR, warehouse, vendor tables |
| `branch_id` | Branch-level operation | Shipment, warehouse, employee, finance dimension |
| `department_id` | Department-level access/workflow | Approval, task, ticket, HR |
| `business_unit_id` | BU scope | Commercial, finance, reporting |
| `customer_account_id` | Customer portal boundary | Shipment, invoice, warehouse order, ticket |
| `owner_user_id` | Ownership rule | Lead, opportunity, quote, task |
| `created_by`, `updated_by` | Audit base | All mutable transactional tables |
| `record_version` | Optimistic concurrency | High-impact mutable records |
| `deleted_at` | Soft delete | Most master/transaction tables except immutable ledger |
| `status_code`, `canonical_status` | Tenant label + reporting consistency | All lifecycle entities |

Temporal fields (Tech Arch §9.6, verbatim): `effective_from`, `effective_to`, `published_at`, `activated_at`, `deactivated_at`, `valid_from`, `valid_until`, `posted_at`, `period_id`, `locked_at` — used for rate, contract, service config, workflow config, approval matrix, pricing, tax, exchange rate, employee contract, membership tier (matches the entities so tagged in `02_*.md` §2/§3).

Data classification (restates `02_*.md` §10, applied at column-design time, not just query-time): cost/margin fields, finance fields, payroll fields, PII fields, and security fields (API key/webhook secret) each get a `_masked`-aware column comment or a dedicated projection view at Prompt 41, not a schema-level split — masking is enforced in the access layer, not by physically separating sensitive columns into another table (that would fragment the canonical entity and violate `02_*.md` §4's no-re-entry/no-duplication rule).

## 3. Entity/schema ownership

**Resolved convention (supersedes `04_*.md` §3's schema-per-domain recommendation, per §1 above):** one PostgreSQL schema, `app`, holds every tenant-owned business table, plus Supabase-managed `auth` (identity) and `storage` (files) schemas used as-is. Domain **ownership** — which module's `server/queries/*` file is the sole legitimate writer — is enforced at the application/RLS layer (`03_*.md` §5/§9, `04_*.md` §5), documented here and in `03_*.md` §3, not by physical schema boundary. This matches the blueprint's own SQL evidence exactly and avoids inventing a namespace pattern with zero supporting example.

Reporting is the one deliberate exception: materialized views and reporting tables (Tech Arch §18.1, ADR-007 "materialized views/reporting tables" already accepted per Tech Arch §35) live in a second schema, `report`, so that "never write to a source-of-truth table" (`03_*.md` §9 violation pattern 5) has a physical backstop, not just a code-review rule — this resolves `ADR-CAND-ARCH-008` (§10 below).

Table naming: `snake_case`, plural, business-meaningful, no domain prefix (matches `shipments`/`invoices`/`vendor_rates` exactly) — ownership is looked up in the table below or in `03_*.md` §3, not inferred from the name.

| Domain owner (from `03_*.md` §3) | Core tables (from `02_*.md` §2 canonical entity register + §14 data dictionaries) | Phase |
|---|---|---|
| Platform (`TEN-IAM`) | `tenants`, `companies`, `branches`, `departments`, `business_units`, `users`, `roles`, `permissions`, `user_tenant_memberships` | 1 |
| Platform (`CFG`/`WF`/`APPR`/`STAT`/`NUM`/`FORM`) | `config_objects`, `config_versions`, `workflow_definitions`, `workflow_instances`, `approval_matrices`, `approval_instances`, `statuses`, `numbering_schemes`, `form_definitions`, `custom_field_definitions` | 1 |
| Platform (`NOTIF`) | `notifications`, `notification_templates`, `notification_deliveries` | 1 |
| Platform (`DOC`) | `files`, `file_access_logs` | 1 |
| Platform (`AUD`) | `audit_logs`, `event_logs`, `api_logs`, `file_access_logs` (shared with `DOC`), `support_access_logs` | 1 |
| Platform (`API-WH`) | `api_keys`, `webhook_subscriptions`, `webhook_deliveries` | 1 |
| Platform (`JOB`/`IMPEXP`) | `jobs`, `import_export_jobs` | 1 |
| Platform (`GEO`) | spatial columns/indexes added to owning-domain tables (no standalone table; PostGIS extension enabled tenant-wide) | 1 |
| Commercial (`COM`) | `leads`, `prospects`, `customers` (legal/tax/billing/hierarchy sub-groups as columns or 1:1 extension tables per §14.1's 8 field groups), `customer_contacts`, `opportunities`, `quotations`, `quotation_versions`, `contracts`, `pricelists` | 2 |
| Operations (`OPS`) | `job_orders`, `shipments`, `shipment_legs`, `dispatch_assignments`, `shipment_milestones`, `epods`, `claims_incidents`, `actual_costs`, `warehouses`, `warehouse_zones`, `warehouse_bins`, `skus`, `inventory_ledger`, `warehouse_orders` | 3 (basic), 5 (advanced) |
| Finance (`FIN`) | `chart_of_accounts`, `journals`, `journal_lines`, `subledgers`, `invoices`, `invoice_lines`, `payments`, `payment_allocations`, `vendor_bills`, `vendor_bill_lines`, `settlements`, `tax_codes`, `exchange_rates`, `fiscal_periods`, `profitability_snapshots` | 4 |
| Procurement/Vendor (`PRC`) | `vendors`, `vendor_contacts`, `vendor_assessments`, `vendor_rates`, `rfqs`, `purchase_orders`, `vendor_contracts`, `vendor_performance_scores` | 6 |
| HRIS (`HRS`) | `employees`, `employee_positions`, `attendance_records`, `leave_requests`, `payroll_runs`, `payroll_lines`, `kpi_records` | 7 |
| Ticketing (`TKT`) | `tickets`, `ticket_comments`, `ticket_links` (typed reference table, Tech Arch §9.4), `sla_policies`, `sla_breaches` | 7 |
| Loyalty (`LYL`) | `loyalty_programs`, `membership_tiers`, `point_ledger`, `cashback_ledger`, `rewards`, `redemptions` | 8 |
| Reporting (`REP`), schema `report` | `report.shipment_performance_mv`, `report.ar_aging_mv`, `report.job_profitability_mv`, `report.vendor_performance_mv`, `report.sales_pipeline_mv`, `report.warehouse_inventory_aging_mv`, `report.ticket_sla_summary_mv` (names drawn directly from Tech Arch §32.12's materialized-view list) | 1 (basic per-domain), 9 (full) |

Customer Portal (`CPT`) owns **no table** — confirmed by `03_*.md` §3 and restated here for schema completeness: no `cpt_*` table exists in this catalogue, by design.

## 4. Relationship and constraint plan

- **Foreign keys** (Tech Arch §9.4): stable canonical relationships get real FKs — `tenants→companies→branches`, `customers→shipments`, `shipments→shipment_milestones`, `invoices→payments`. Polymorphic links (`ticket_links`) use a typed reference table (`linked_entity_type`, `linked_entity_id`) with application-level validation, never a bare untyped FK — this is `ticket_links`' physical form and directly resolves how `ADR-CAND-ARCH-006` (ticket-link staleness) should be enforced: the typed-link validation function checks the target's `canonical_status`/`deleted_at` at link-creation time and re-checks at read time (per `272_*.md`'s "every read... rechecks both ticket and linked-record authorization," already quoted in `02_*.md`).
- **Uniqueness**: `(tenant_id, <natural_key>)` composite unique constraints throughout — e.g. `(tenant_id, customer_code)`, `(tenant_id, shipment_number)`, `(tenant_id, invoice_number)` — never a bare global-unique natural key, since natural keys are tenant-scoped by definition (Tech Arch §10 multi-tenancy).
- **Referential integrity**: `ON DELETE RESTRICT` as the default for master-data FKs referenced by transactions (Tech Arch §9.5: "prevent delete if referenced"); soft-delete (`deleted_at`) is the only sanctioned "removal" path for master data.
- **State transitions**: every status-lifecycle table (`02_*.md` §3's per-entity lifecycle strings) gets a `canonical_status` column constrained by a `CHECK` against that entity's fixed lifecycle enum, plus a separate tenant-facing `status_label` the tenant may rename (Tech Arch §9.2's dual-column pattern) — the enum values themselves are never tenant-configurable, only the label.
- **Soft delete / retention / legal hold**: `deleted_at` on master/transaction-draft tables; **no delete column at all** on `journals`, `journal_lines`, `point_ledger`, `inventory_ledger`, `audit_logs` (Tech Arch §9.5 — reversal/adjustment-entry only); a `legal_hold` boolean + `legal_hold_reason` column added to every table in RPD-025's Finance/Audit/Operational retention classes, checked by any future purge job before physical deletion.
- **Idempotency**: general-purpose `idempotency_key` column (unique per `tenant_id`) on every table reachable from an API/webhook/job entry point (Tech Arch §19.2's "Check Idempotency" step); Finance posting uses the specific formula from Tech Arch §24.5: `tenant_id + source_entity_type + source_entity_id + posting_type + posting_version`, stored as a generated/unique column on `journals`.
- **Optimistic concurrency**: `record_version integer not null default 1`, incremented on every update, checked via `WHERE record_version = :expected` on high-impact mutable tables (quotations, shipments, invoices, journals, vendor rates) — this is the concrete mechanism `02_*.md`'s stale-snapshot concern (Commercial revenue read by Operations) and `ADR-CAND-ARCH-001`'s vendor-rate read both rely on: a reader captures the `record_version` it read, so any downstream process can detect if the source has since changed.
- **Immutable-for-normal-role, RPD-022 exception**: enforced by RLS policy (no `UPDATE`/`DELETE` grant to normal roles on `journals`/`point_ledger`/`inventory_ledger`/`audit_logs` after `posted_at`/`created_at` is set), with a separate, heavily audited Supreme-Admin-only policy path that **does** permit it — the RLS policy split itself is the physical form of RPD-022's disclosed exception; it must never be implemented as "no RLS restriction at all," only as a distinct, logged, Supreme-Admin-scoped policy.
- **`ADR-CAND-ARCH-001` resolved**: `vendor_rates` is owned by `PRC` (Procurement) from Phase 1's master-data foundation onward — the table is created in Phase 1's `MDM` slice (empty, no Procurement UI yet) with `PRC` as the documented sole writer once Phase 6 ships; Commercial's Phase 2 costing reads it via a view (`app.v_active_vendor_rates`, matching the partial-index pattern in §6) rather than copying rows — this is Option (a) from `01_*.md` `ADR-CAND-ARCH-001`, now ratified with a concrete table/view design.
- **`ADR-CAND-ARCH-005` resolved**: Job Order → Shipment Order fan-out (`02_*.md` §12 `MDM-RISK-003`) is one DB transaction, guarded by an `idempotency_key` on the Job Order confirmation action — a retried confirmation returns the existing Shipment Order set rather than creating a duplicate/partial fan-out, mirroring the Finance idempotent-posting pattern exactly.

## 5. Finance controls (Tech Arch §24, applied to §3's finance tables)

- **Balanced postings**: `journals` requires `sum(journal_lines.debit) = sum(journal_lines.credit)` enforced by a `CHECK`/trigger at commit time, not application-only validation (Tech Arch §24.1).
- **Draft/post/reversal**: `journals.canonical_status` enum = `draft → submitted → approved → posted → reversed`; `posted` rows are immutable for normal roles (§4 above); a reversal creates a new linked `journals` row (`reversal_of_journal_id` FK), never mutates the original (Tech Arch §24.2).
- **Period locks**: `fiscal_periods.locked_at` gates every posting — a posting attempt against a locked period fails at the DB constraint level (`CHECK` referencing the period's lock state via a function, not just application logic), matching Tech Arch §28.2's "financial table migration requires extra review" caution.
- **Allocation/reconciliation**: `payment_allocations` links `payments` to one or more `invoices`/`vendor_bills` (many-to-many with amounts); this table is the physical backing for `02_*.md` §8's reconciliation points R2 (AR aging), R4 (AP three-way match), R5 (bank reconciliation) — each reconciliation point becomes a read-only report query against `payment_allocations` + the source ledgers, never a separate write path.
- **Snapshots/lineage**: `profitability_snapshots` stores point-in-time revenue/cost/margin per job, generated by a scheduled job (not a live view) so historical profitability reporting survives later cost corrections — each snapshot row references the `record_version` of the source `actual_costs`/`invoices` rows it was computed from, giving exact lineage.
- **Duplicate prevention**: the Finance idempotency-key formula (§4) is the single mechanism preventing duplicate journal creation from a retried posting call, matching `02_*.md` §5.4's citation of Tech Arch §24.5 verbatim.
- **Multi-currency** (Tech Arch §24.4): `journals`/`invoices`/`vendor_bills` carry `transaction_currency`, `functional_currency`, `exchange_rate`, `exchange_rate_source`, `rate_date`; exchange-rate changes never mutate a historical posted row — a new `exchange_rates` row with a new `rate_date` is the only sanctioned update path.

## 6. Spatial, file, job, config, audit, event, staging, and reporting schema needs

- **PostGIS/spatial** (RPD-015, `GEO` primitive): PostGIS extension enabled tenant-wide from Phase 1; spatial columns (`geography(Point)`/`geography(LineString)`) added directly to `shipments`/`shipment_milestones`/`warehouses` rather than a separate geo table, since location is an attribute of those entities, not a new canonical entity (matches Tech Arch §32.6's "GiST/SP-GiST for geospatial if PostGIS is introduced").
- **File metadata/quarantine** (RPD-032, `DOC` primitive): `files` table carries `tenant_id`, `record_type`, `record_id`, `classification`, `storage_path`, `malware_scan_status` (`pending|clean|infected|error`), `malware_scan_completed_at` — a file's `malware_scan_status` must equal `clean` before any signed URL is issued to a consumer other than the uploader (Tech Arch §17.3, RPD-032, already established in `02_*.md` §6/§9).
- **Job queue/retry/DLQ** (RPD-012, `JOB` primitive): `jobs` table matches the exact field list from Tech Arch §32.11 verbatim: `job_id, tenant_id, job_type, status, priority, payload, attempts, max_attempts, locked_by, locked_until, error, result_url, created_by, created_at, completed_at`; a job whose `attempts` reaches `max_attempts` transitions to a `dead_letter` status (the DLQ state, Tech Arch §32.17) and requires a Supreme-Admin/authorized-admin action to requeue (the "manual replay" step).
- **Configuration versions** (`CFG` primitive): `config_versions` table with `effective_from`/`effective_to`/`published_at` (Tech Arch §9.6) and a `config_version_id` FK column added to every transaction table affected by configuration (ADR-012, RPD-040's default: active transactions retain their applied version).
- **Audit events / event log** (Tech Arch §9.7, §22): `audit_logs` (compliance, who-changed-what), `event_logs` (business event stream), `api_logs`, `file_access_logs`, `support_access_logs` are five distinct append-only tables, not one merged table — matching Tech Arch §9.7's table exactly, correlated by a shared `correlation_id` column (§22.3) present on all five. `event_logs` also serves the outbox-pattern role for async job/webhook dispatch (Tech Arch §19.2's `WRITE → OUT[Outbound Webhook/Event]` step reads from `event_logs`, not a separate outbox table — no such separate table is evidenced anywhere in the source material, so none is invented).
- **Import staging**: `import_export_jobs` (a specialization row-type of `jobs`, sharing the same table with `job_type = 'import'|'export'`) plus a per-domain staging pattern — large imports land in a `import_staging_rows` table (`tenant_id`, `job_id`, `row_number`, `raw_payload jsonb`, `validation_status`, `error`) before being validated and inserted into the canonical table row-by-row or in validated batches, so a partially-invalid file never corrupts canonical data (Tech Arch §32.11's "bulk import" job type, applied concretely).
- **Reporting/read-model** (§3 above, `report` schema): materialized views refreshed per Tech Arch §32.12's strategy (scheduled refresh, event-triggered for small scope, incremental reporting table for high volume, never synchronous refresh on user request).

## 7. Index and query plan

Adopts Tech Arch §32.6's example indexes as-is (already domain-general, no per-domain reinterpretation needed) plus the same pattern applied to every other high-volume table in §3:

- Tenant-leading composite indexes: `(tenant_id, canonical_status, updated_at desc)` on every high-volume transactional table (`shipments`, `invoices`, `vendor_bills`, `tickets`, `quotations`).
- Tenant + scope composite: `(tenant_id, customer_account_id, updated_at desc)` on every customer-portal-visible table.
- Time-ordered child tables: `(tenant_id, <parent>_id, occurred_at desc)` on `shipment_milestones`, `audit_logs`, `event_logs`, `point_ledger`, `inventory_ledger`.
- Partial indexes for active-only filters: mirrors Tech Arch's `idx_active_vendor_rates` example exactly, applied to `vendor_rates`, `quotations` (active/pending), `config_versions` (published).
- GIN for JSONB config search and full-text search (`jobs.payload`, `config_versions.value`); trigram for fuzzy customer/vendor/location search **only if enabled** per RPD-039 (PostgreSQL-first, external search only after measured threshold).
- Pagination (Tech Arch §25.4): offset for small stable master lists (`chart_of_accounts`, `warehouses`); cursor for large changing lists (`quotations`, `vendor_rates`); **keyset** mandatory for `shipment_milestones`/`audit_logs`/`event_logs`/`inventory_ledger`/`tickets` (explicitly named in Tech Arch §25.4 and again in §37's Scale-up TMS/WMS exit criteria "keyset pagination... mandatory"); async export for large full extractions.
- No speculative index proliferation: every index above is directly evidenced by an existing blueprint example or a table this document introduces for a documented query pattern (reconciliation reports, portal scoping) — no index is added "in case it's useful" (prompt instruction #6, `GAP-015`'s "derive measurable thresholds in the performance workstream" applies to any further index beyond this evidenced set).

## 8. Migration waves

Since the repository is greenfield (zero existing schema), "expand/migrate/contract" applies only prospectively, once Phase 1 ships and later phases must evolve it without breaking Phase 1's shape. Documented here as the standing policy for every future migration, not as a plan for migrating existing data (none exists):

| Wave | Meaning | Applies when |
|---|---|---|
| Expand | Add new nullable column/table, deploy, backfill | Any additive schema change |
| Migrate | Dual-write or backfill job populates the new shape while the old shape still serves reads | Changing a column's meaning/type, not just adding one |
| Contract | Remove the old column/table only after all readers/writers are confirmed migrated | Final cleanup step, requires an explicit verification gate before applying |

Rules (Tech Arch §28.2/§28.3, applied): every migration is versioned (per `ADR-CAND-ARCH-009`, resolved below); backward-compatible where possible; no destructive migration without backup and approval; large backfills run as a background job (`jobs` table, `job_type = 'backfill'`), never a synchronous migration statement; RLS policy migrations get their own negative-test pass before merge (Tech Arch §11.4); financial-table migrations get mandatory extra review (Tech Arch §28.2); rollback strategy is forward-fix preferred, down-migration only if safe (Tech Arch §28.3) — a destructive down-migration on a table already holding tenant data is never acceptable once Phase 1 has shipped to any environment beyond local/dev.

Seed/reference data: chart-of-accounts templates, default role/permission sets, default numbering schemes, default status/workflow templates ship as versioned seed migrations (idempotent — safe to re-run), scoped to a `system`/template tenant or applied at tenant-provisioning time (`TEN-IAM`'s tenant lifecycle), never hardcoded into application code (Tech Arch §8 Backend Rules: "Backend tidak boleh membuat tenant-specific branch logic hardcoded").

Clean rebuild / upgrade path: not applicable pre-Phase-1 (no prior schema to upgrade from); this section becomes relevant starting with the first Phase-2+ migration wave, and this document's wave policy above is what that future migration must follow.

## 9. Test matrix

Maps Tech Arch §27.3's Test Pyramid onto this document's schema:

| Test type | Applied to |
|---|---|
| Unit | Constraint/trigger logic (balanced-journal check, idempotency-key uniqueness, status-transition CHECK) |
| Integration | Server action/query layer against a real Postgres instance — one per table in §3 |
| RLS | Negative test per table per Tech Arch §11.4's 7-item minimal list, applied to every table in §3, not just `shipments` |
| Migration | Up/down (or forward-fix) verified per wave in §8 |
| Financial | Posting, reversal, period lock, reconciliation — one test per control in §5 |
| Performance | `EXPLAIN ANALYZE` review per Tech Arch §32.7 threshold (500ms common API / 2s complex report) on every index in §7 |
| Security | File malware-scan gate, API-key/webhook-secret masking, support-access expiry |

## 10. ADR candidates

Three prior candidates resolved directly in this document (§1/§3/§4 above): `ADR-CAND-ARCH-001` (vendor-rate ownership — resolved), `ADR-CAND-ARCH-005` (Job→Shipment atomicity — resolved), `ADR-CAND-ARCH-007` (schema-per-domain — resolved, corrected to single `app` schema). `ADR-CAND-ARCH-008` (Reporting schema timing) resolved in §3: `report` schema created from Phase 1 for early per-domain dashboards, not deferred to Phase 9. New candidates from this document:

| ID | Question | Constraint | Recommendation | Owner | Blocking state |
|---|---|---|---|---|---|
| `ADR-CAND-ARCH-009` (resolved) | Migration file naming convention | Must work with Supabase CLI | `supabase/migrations/<YYYYMMDDHHMMSS>_<snake_case_description>.sql` — the Supabase CLI's own default | Data/DevEx | Resolved |
| `ADR-CAND-ARCH-012` | Exact extension-table vs. flat-column strategy for `customers`' 8 field groups (§14.1: legal/tax/billing/hierarchy/contact/service-requirement/contract-pricelist/portal-user) — one wide table or 1:1 extension tables? | Wide tables risk column sprawl (60+ columns); extension tables risk join overhead on every customer read | 1:1 extension tables for `Contact/PIC` (one customer has many contacts, genuinely 1:N) and `Contract/Pricelist` (genuinely 1:N, temporal); flat columns for Legal/Tax/Billing/Hierarchy/Portal-user groups (genuinely 1:1 per customer) — avoids both extremes | Data/Architecture | `ADR_REQUIRED`, non-blocking — resolve at Phase 1 `MDM`/Phase 2 `COM` schema implementation (Prompts 120, 143+) |
| `ADR-CAND-ARCH-013` | Does `shipments`' 13 field groups (§14.2) follow the same wide-table pattern, or split `Financial`/`Document-ePOD`/`Risk-claim`/`Audit` into linked tables given `shipments` is the highest-volume table in the schema? | Tech Arch §33.1 already names `shipments` as needing partitioning/keyset pagination at scale | Keep `Identifiers`/`Parties`/`Service-mode`/`Location`/`Structure`/`Commodity`/`Asset-resource`/`Schedule`/`Milestone-status` as flat columns on `shipments`; extract `Financial` onto `shipments` still (needed for every list-view query) but move `Document/ePOD` to the existing `files`/`epods` linkage and `Risk/claim` to the existing `claims_incidents` table (already separate in §3) | Data/Architecture | `ADR_REQUIRED`, non-blocking — resolve at Phase 3 Operations schema implementation (Prompt 168+) |

## 11. Risks

| ID | Description | Category | Severity | Recommended handling |
|---|---|---|---|---|
| `MDM-RISK-006` | The `report` schema (§3) is a deliberate divergence from the single-`app`-schema convention; if this distinction isn't documented in code (e.g. a lint rule forbidding writes to `report.*` from anywhere but the scheduled refresh job), a future domain could accidentally treat it as just another writable schema, defeating its purpose as `03_*.md` §9 violation-pattern-5's physical backstop. | Enforcement-drift risk | Low | Encode the `report.*`-is-read-only rule in the same architecture-test suite as `03_*.md` §10's other enforcement gates, at Phase 1 kickoff. |

Carried forward unchanged: `MDM-RISK-002..004` (identity reconciliation, non-atomic handoff — now resolved as `ADR-CAND-ARCH-005`, ticket-link staleness), `RISK-004..007` (standing accepted RPD risks).

## 12. Atomic workstream backlog

Each row is sized to 1–3 migrations / 5–15 changed files, per the standing architecture-task constraint (Step 3 README §5), sequenced to match `04_REPOSITORY_TARGET_STRUCTURE.md` §8's phase order:

| Slice | Phase | Migrations | Depends on | Test evidence required |
|---|---|---|---|---|
| Platform identity core | 1 | `tenants`, `companies`, `branches`, `users`, `roles`, `permissions`, `user_tenant_memberships` (1 migration, foundational) | none | RLS negative tests for tenant isolation before any other table ships |
| Platform config/workflow/approval core | 1 | `config_objects`, `config_versions`, `workflow_definitions`, `approval_matrices`, `statuses`, `numbering_schemes` (2 migrations: definitions, then instances) | Platform identity core | Config-version-stamping test |
| Platform notification/document/audit core | 1 | `notifications`, `files`, `audit_logs`, `event_logs`, `api_logs`, `file_access_logs`, `support_access_logs` (2 migrations) | Platform identity core | Malware-scan-gate test, correlation-ID propagation test |
| Platform API/job/flag/spatial core | 1 | `api_keys`, `webhook_subscriptions`, `jobs`, `feature_flags`; PostGIS extension enable (2 migrations) | Platform notification/document/audit core | Idempotency-key uniqueness test, job DLQ transition test |
| Commercial core | 2 | `leads`, `prospects`, `customers` (+ extension tables per `ADR-CAND-ARCH-012`), `opportunities`, `quotations`, `contracts` (3 migrations) | Platform config/workflow/approval core | No-duplicate-customer test, quotation-versioning test |
| Operations core (basic) | 3 | `job_orders`, `shipments` (+ split per `ADR-CAND-ARCH-013`), `shipment_milestones`, `epods`, `claims_incidents`, `actual_costs` (3 migrations) | Commercial core | Job→Shipment atomicity test (`ADR-CAND-ARCH-005`), keyset-pagination test on `shipment_milestones` |
| Finance core | 4 | `chart_of_accounts`, `journals`, `journal_lines`, `invoices`, `vendor_bills`, `payments`, `payment_allocations`, `fiscal_periods` (3 migrations: COA/periods, journals/subledger, AR/AP) | Operations core (basic) | Balanced-posting test, period-lock test, idempotent-posting test |
| Operations advanced (WMS/TMS) | 5 | `warehouses`, `warehouse_zones`, `warehouse_bins`, `skus`, `inventory_ledger`, `warehouse_orders`, `shipment_legs`, `dispatch_assignments` (3 migrations) | Operations core (basic), Finance core (for costing) | Inventory-ledger-no-direct-mutation test |
| Procurement core | 6 | `vendors`, `vendor_assessments`, `vendor_rates` (already seeded empty in Platform master-data slice per §4), `rfqs`, `purchase_orders`, `vendor_performance_scores` (3 migrations) | Finance core, Operations advanced | Vendor-rate-single-owner test (`ADR-CAND-ARCH-001`), three-way-match test |
| HRIS core | 7 | `employees` (FK to `users` per `ADR-CAND-ARCH-002`), `employee_positions`, `attendance_records`, `payroll_runs`, `payroll_lines`, `kpi_records` (3 migrations) | Platform identity core, Finance core (payroll posting) | Employee-not-duplicate-identity test (`ADR-CAND-ARCH-002`) |
| Ticketing core | 7 | `tickets`, `ticket_comments`, `ticket_links`, `sla_policies` (2 migrations) | Platform config/workflow/approval core | Ticket-link-staleness test (`ADR-CAND-ARCH-006`) |
| Loyalty core | 8 | `loyalty_programs`, `membership_tiers`, `point_ledger`, `cashback_ledger`, `rewards`, `redemptions` (2 migrations) | Finance core | Idempotent-earning test, no-direct-balance-mutation test |
| Reporting core (basic) | 1 (early) | `report` schema creation + first materialized view (`report.shipment_performance_mv` deferred until Operations core ships; schema itself created at Phase 1) | Platform core | Report-schema-read-only test |
| Reporting full | 9 | Remaining materialized views from Tech Arch §32.12's list (2–3 migrations) | All prior domain cores | Scheduled-refresh test |

## 13. Exit gates

Complete only when (restating the prompt's completion gate, verified against this document): every canonical entity in `02_*.md` §2 has exactly one owner and phase in §3 above (verified — 14 entity groups, all rows populated); tenant integrity is designed (§2's mandatory tenant-column set, §4's RLS-backed immutability); finance integrity is designed (§5, matching Tech Arch §24 in full); no code/database mutation occurred (§0, confirmed); every migration task in §12 is sized to 1–3 migrations (verified per row); and this document, combined with `01_*.md`–`04_*.md`, gives Prompt 41 (RLS/RBAC Workstream) a complete table list to write policies against without inventing one.

Next eligible prompt: `03-architecture-and-plan/41_RLS_RBAC_WORKSTREAM_PROMPT.md` → `docs/architecture/06_RLS_RBAC_WORKSTREAM.md`.
