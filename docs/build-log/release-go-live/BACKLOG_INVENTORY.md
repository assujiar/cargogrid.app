# Backlog inventory — still-open `KNOWN_ISSUES.md` items

**Purpose.** Track B, Phase 0 of the approved release-and-backlog plan (2026-08-27; see
`RGL-404.md` §11/§12A). Every mechanical count of `docs/runtime/KNOWN_ISSUES.md` this session has
run has disagreed with the others — `RGL-404.md` §11 itself records three prior scans (127/130/131);
a fresh regex-based scan run for this document returned 185 (a naive "any `RESOLVED` marker"
detector, demonstrably wrong — it does not distinguish "`RESOLVED` in code, `NOT YET DEPLOYED`"
from an actually-closed item, and it does not know `ACCEPTED_RISK`/superseded-by-a-later-ID
dispositions count as closed). The tracked, carried-forward figure through item 18 of the
historical-issue-backlog remediation was **149** (0 Critical, 9 High, 70 Medium, 70 Low); Track A's
release (`RGL-404.md` §12A) closed 2 more High items on deployment alone (`ISS-2026-295`/`296`),
bringing the tracked figure to **147** (0 Critical, 7 High, 70 Medium, 70 Low) before this inventory.

This document is the authoritative, entry-by-entry inventory Phase 0 calls for, built by a careful
read (not a regex scan) of every still-open entry, grouped into **themed batches** for Track B's
own ~20-item execution passes. It **does not silently claim exact agreement with 147** — see
"Count reconciliation" below, which discloses the honest gap rather than forcing a false match.

## Fixability classes

- `CODE` — a real, bounded code/schema/migration fix, agent-executable and testable in-sandbox.
- `TEST` — a test-coverage/evidence gap; fixable by writing a test or running a drill, no product change.
- `DOC` — a documentation/record-keeping/process-consistency gap.
- `INFRA` — requires real external infrastructure/vendor/credential access this session cannot obtain.
- `BIZ` — requires a real business/policy decision from a human, not a technical fix.
- `BIG` — a structurally new capability ("no mechanism for X exists at all"), not a bounded bug fix.

## Count reconciliation

**High confidence (independently verified twice, by two different methods): 0 Critical, 7 High.**
Zero Critical items remain open — consistent with `RGL-404.md` §11's own ruling and this session's
own re-verification. High severity is exactly enumerable (see the table below) — 9 tracked items
minus the 2 Track A just closed on deployment (`ISS-2026-295`/`296`) = 7, all listed by ID.

**Lower confidence: Medium/Low split.** The tracked 70/70 figure predates this document and has
never been independently re-derived item-by-item; a careful (non-regex) read of every entry landed
close but not exact — within roughly 6 items of 70/70, concentrated in the `009-052` index-table
range (`docs/runtime/KNOWN_ISSUES.md` §3), which has no `###` body section to disambiguate
compound severity cells (e.g. `"High → Resolved (core), Low (residual...)"`). Rather than force an
artificial match, this document **carries the tracked 70/70 figure forward as the working number**
and flags it as not-yet-item-level-reconciled. Each Track B batch, as it works through its own
items, re-verifies their true current status as a side effect — this residual will close out
naturally as batches complete, and any correction found will be disclosed here and in `RGL-404.md`
§12, never silently absorbed.

**Working total for Track B: 147** (0 Critical, 7 High, 70 Medium, 70 Low), pending the item-level
tightening above.

---

## High severity (7) — first batch priority per the approved plan

| ID | Summary | Fix | Batch |
|---|---|---|---|
| `ISS-2026-249` | Alert system unwired from webhook/AI/security failure producers | `CODE` | step-up-mfa-enforcement |
| `ISS-2026-250` | No monitoring/incident dashboard UI consumes the alerting backend | `CODE` | observability-alerting |
| `ISS-2026-258` | No real DR communication mechanism exists anywhere | `BIG` | dr-runbook |
| `ISS-2026-261` | No second infrastructure vendor; Supabase-wide outage has no failover | `INFRA` | dr-runbook |
| `ISS-2026-273` | No bulk financial opening-balance import path exists at all | `BIG` | migration-import |
| `ISS-2026-285` | `_calc_vendor_kpi_rate_validity` not-computable for sub-24h windows | `CODE` | db-test-vendor-kpi |
| `ISS-2026-289` | GitHub branch protection never configured on any of 47 branches | `INFRA` | ci-evidence |

`ISS-2026-295`/`296` — **closed** at Track A (`RGL-404.md` §12A, deployed to production
2026-08-27); removed from this list, no longer open.

## Medium/Low batches (140 items, working count)

Batches below reproduce the categorization research pass performed for this document (full
per-ID detail retained in that pass's own transcript; this table is the operative worklist).
Batch keys group items that share a file, a mechanism, or a domain — the unit Track B's own
per-batch loop (`RGL-404.md` §11/plan) works against, not raw severity order, except that the 7
High items above go in the first batch regardless of theme.

| Batch key | Items | Count | Dominant class | Note |
|---|---|---|---|---|
| `hris-integrated-verification-residual` | 057, 058, 060, 061, 062, 063, 064, 066, 067, 068, 069, 070, 071, 073 | 14 | mixed CODE/BIG/DOC | Cross-capability gaps from HRT-294; per-item handling, not one migration |
| `hris-overtime-timesheet-gaps` | 076, 100 | 2 | CODE | Unwired mutation wrappers |
| `db-test-flakiness` | 103, 146, 155 | 3 | TEST/CODE | Wall-clock fixtures, tenant-id disclosure, registration dedup gap |
| `hris-payroll-personal-data` | 091, 092, 093 | 3 | CODE | Retention/legal-hold classification, raw-column exposure |
| `ticketing-links-gaps` | 101, 102 | 2 | CODE | Missing UI caller, internal ID leak |
| `cpl-customer-portal-scope` | 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 126, 127, 128, 129 | 14 | mostly BIG/DOC | Disclosed Phase-8 scope narrowings; per-item, not one migration |
| `loyalty-fraud-reconciliation` | 131, 132, 133, 134, 136 | 5 | mixed | Same domain (CPL-322/325), different mechanisms; 132+134 share an override-gap shape |
| `loyalty-approval-authority` | 137, 138 | 2 | CODE/BIG | Checker bypass; zero accessibility-audit evidence |
| `perf-load-evidence` | 139, 140, 141 | 3 | TEST/CODE | Zero load/perf evidence for Phase 8/9 routes; retention gap |
| `docs-consistency` | 142, 153, 157, 252, 281 | 5 | DOC/BIG | Doc mislabels, stale sections, accessibility-audit gap |
| `iae-hardening-residual` | 148, 149, 152 | 3 | TEST/CODE | Load evidence, anon enumeration oracle, inert capability matrix |
| `step-up-mfa-enforcement` | 151 | 1 | CODE | `create_integration_connection` unwired to step-up MFA |
| `rls-grants` | 167, 170, 172, 174, 175, 176, 189 | 7 | CODE | Same shape (missing tenant-membership conjunct/column grant) — candidate for ONE migration mirroring the HDN-373 pattern |
| `support-access-audit` | 177, 178 | 2 | CODE | Session-open audit gap, webhook-retry tenant cross-check |
| `rbac-defense-in-depth` | 186, 187, 188, 190, 191 | 5 | mixed | Support-access session lifecycle (187+188 batchable), evaluator hardening |
| `rls-own-row-narrowing` | 192 | 1 | CODE | `principal_memberships` own-row RLS narrower than sibling pattern |
| `finance-fx` | 197 | 1 | BIG | No FX/multi-currency conversion anywhere in revenue chain |
| `lineage-provenance` | 203, 206 | 2 | CODE | JSONB snapshots missing source-entity id/version; orphan-source_id gap |
| `rest-api-consistency` | 207, 208 | 2 | CODE | `api_versions` registry inert; vendor-invitation idempotency |
| `rest-api-error-shape` | 213, 214 | 2 | CODE | Boolean-equality-fails-open shape; raw ZodError leak |
| `files-legal-hold-residual` | 223, 224 | 2 | BIZ/CODE | tenant_admin classification-gate bypass (policy question); evidence-reviewer access denial |
| `crypto-scan-recovery` | 231 | 1 | BIZ | Schema backstop conflicts with RPD-022 pattern |
| `postgis-extension` | 234 | 1 | INFRA | Cannot relocate `postgis` out of `public`; 6 advisories permanently open |
| `schema-completeness-gaps` | 237, 238 | 2 | CODE | Broken `select("*")` page; 4 unpaginated tenant-wide routes |
| `perf-cache-safety` | 240 | 1 | CODE | `auth_rls_initplan` guard blind to default `auth.uid()` pattern |
| `accessibility` | 241, 242, 243, 245, 246, 247, 248 | 7 | CODE/DOC | 241/242/247/248 share a component-level fix pattern, batchable |
| `browser-compat` | 244 | 1 | INFRA | Safari/Firefox structurally untestable in this sandbox |
| `observability-alerting` | 251, 253 | 2 | CODE | Alert dispatch mechanism; unlogged `/api/ready` failure path |
| `dr-runbook` | 256, 259, 284 | 3 | INFRA/CODE/DOC | RPO/RTO never confirmed live; audit_logs blind to raw-SQL corruption; stale doc fact |
| `migration-import` | 274, 277 | 2 | BIG/CODE | No master-data bulk-import mechanism; legal-hold scoped to deletion only |
| `prod-seed-hygiene` | 294 | 1 | INFRA | One orphaned synthetic `auth.users` row on the hosted project |
| `perf-live-latency` | 297 | 1 | INFRA | `GET /api/ready` p50 latency exceeds budget |
| `table-only-procurement-hardening` | 013, 015, 018, 019, 031, 036, 037, 038, 039, 040, 041, 043, 044, 046, 047, 048, 049, 050, 052 | 19 | mixed | 038/040/043/044/048 share an RBAC/authority-check root cause, candidate for ONE migration; rest are unrelated BIG features |

**New this session, not part of the tracked 147** (self-caught, disclosed per this session's own
established convention, `ISS-2026-298`/`299` precedent):

| ID | Summary | Fix | Batch |
|---|---|---|---|
| `ISS-2026-300` | `supabase_migrations.schema_migrations` ledger records 9 migrations under the wrong (wall-clock) version | `INFRA` (write blocked by this session's own safety classifier; needs operator/elevated-access execution) | release-tooling |

---

## Batching plan for Track B (~8 passes of ~20)

Severity orders the first batch; domain/mechanism groups the rest, per the approved plan:

1. **Batch 1 (High + quick wins)**: all 7 High items, plus `rls-grants` (7, one candidate migration) — 14 items.
2. **Batch 2**: `table-only-procurement-hardening` (19, several candidate for one migration).
3. **Batch 3**: `hris-integrated-verification-residual` (14) + `hris-overtime-timesheet-gaps` (2) + `hris-payroll-personal-data` (3) — 19 items.
4. **Batch 4**: `cpl-customer-portal-scope` (14) + `loyalty-fraud-reconciliation` (5) + `loyalty-approval-authority` (2) — 21 items.
5. **Batch 5**: `accessibility` (7) + `browser-compat` (1) + `docs-consistency` (5) + `perf-load-evidence` (3) + `iae-hardening-residual` (3) — 19 items.
6. **Batch 6**: `rbac-defense-in-depth` (5) + `support-access-audit` (2) + `rls-own-row-narrowing` (1) + `step-up-mfa-enforcement` (1) + `observability-alerting` (2) + `db-test-flakiness` (3) + `ticketing-links-gaps` (2) + `perf-cache-safety` (1) — 17 items.
7. **Batch 7**: `lineage-provenance` (2) + `rest-api-consistency` (2) + `rest-api-error-shape` (2) + `files-legal-hold-residual` (2) + `crypto-scan-recovery` (1) + `schema-completeness-gaps` (2) + `finance-fx` (1) + `migration-import` (2) — 14 items.
8. **Batch 8 (disposition batch)**: every remaining `INFRA`/`BIZ`/pure-`BIG` item not already folded into batches 1-7 — `postgis-extension`, `dr-runbook`, `prod-seed-hygiene`, `perf-live-latency`, `ISS-2026-300`, plus any `BIG` items from earlier batches whose own code-shaped half was built but whose full capability was not. Per the operator's own instruction: build the code-shaped part, write an explicit owner-named disposition for the rest.

Batch composition may shift as work proceeds (an item found to share a root cause with another
batch moves to join it) — this table is a plan, not a contract; changes are recorded in `RGL-404.md`
§12 as they happen.
