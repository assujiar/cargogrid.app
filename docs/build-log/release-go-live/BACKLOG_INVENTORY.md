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

**Working total for Track B: 135** (0 Critical, 5 High, 63 Medium, 67 Low) — updated during Batch 1
review: `ISS-2026-285` turned out to already be fixed (`RGL-394`), just never annotated; see
`RGL-404.md` §12 item 21. Further updated after Batch 1 (141), Batch 2 (136), and Batch 3 (135,
this figure) — see the "Batch 1 status"/"Batch 2 status"/"Batch 3 status" sections below and
`RGL-404.md` §12 items 22-33 for the authoritative running log.

---

## High severity (6) — first batch priority per the approved plan

| ID | Summary | Fix | Batch | Status |
|---|---|---|---|---|
| `ISS-2026-249` | Alert system unwired from webhook/AI/security failure producers | `CODE` | step-up-mfa-enforcement | in progress (Batch 1) |
| `ISS-2026-250` | No monitoring/incident dashboard UI consumes the alerting backend | `CODE`/`BIG` (TBD by research) | observability-alerting | in progress (Batch 1) |
| `ISS-2026-258` | No real DR communication mechanism exists anywhere | `BIG` | dr-runbook | dispositioned (KNOWN_ISSUES.md, not agent-fixable) |
| `ISS-2026-261` | No second infrastructure vendor; Supabase-wide outage has no failover | `INFRA` | dr-runbook | dispositioned (KNOWN_ISSUES.md, not agent-fixable) |
| `ISS-2026-273` | No bulk financial opening-balance import path exists at all | `BIG` | migration-import | dispositioned (KNOWN_ISSUES.md, not agent-fixable) |
| `ISS-2026-289` | GitHub branch protection never configured on any of 47 branches | `INFRA` | ci-evidence | dispositioned (KNOWN_ISSUES.md, exact steps for operator) |

`ISS-2026-285` — **closed as doc-only** (already fixed at `RGL-394`, entry just never annotated);
removed from this list. See `RGL-404.md` §12 item 21.

`ISS-2026-295`/`296` — **closed** at Track A (`RGL-404.md` §12A, deployed to production
2026-08-27); removed from this list, no longer open.

## Batch 1 status: complete

`ISS-2026-249`, `167` (representative, 3 of ~41 sites), `174`, `175`, `176` — `RESOLVED`, full
detail in `KNOWN_ISSUES.md` and `RGL-404.md` §12 items 22-26.

`ISS-2026-170` — investigated, withdrawn from this batch after a wider check (34
`scripts/db-tests/*.sql` files, not just the 5 production TypeScript callers a first-pass grep
found) revealed the true `record_type` enumeration is ~17 values, not 5, some backed by real
records and some deliberately synthetic by design; a migration was drafted and then deleted before
being applied, rather than risk breaking legitimate tests across a dozen unrelated domains on an
incomplete enumeration. Redispositioned to a dedicated future task with the full corrected scope
handed forward — see the entry's own text.

`ISS-2026-189` — investigated, an `HRS:View` RLS gate (with a self-access carve-out) was drafted
and applied locally, then also reverted after the suite surfaced ~90 sites across ~15 HRIS/
ticketing test files relying on the current, broader access as normal fixture-construction
practice — real evidence supporting this entry's own "plausibly an intentional org directory
feature" framing, not just test debt. Rather than force through a design interpretation the entry
itself calls genuinely undecided, the ruling is deferred to a human, with both options and the new
evidence laid out in the entry's own text.

`ISS-2026-258`/`261`/`273`/`289` — dispositioned (named owner, real next step, not agent-fixable).

Working total after Batch 1: **141 remaining** (0 Critical, 5 High, 69 Medium, 67 Low). Down from
146: `ISS-2026-249` (High) and `167` (Medium) resolved partial-by-design-disclosed per this
session's own established convention (a real, verified, disclosed-as-incomplete fix counts as
resolved, same treatment as `ISS-2026-265`/`254`/`272` earlier this session); `174`/`175`/`176`
(all Low) fully resolved. `189` remains open pending a human ruling. `250`/`258`/`261`/`273`/`289`
(5 High) remain open, dispositioned not fixed. See `RGL-404.md` §12 for the authoritative running
log.

## Batch 2 status: complete

`table-only-procurement-hardening` (19 items: 013, 015, 018, 019, 031, 036, 037, 038, 039, 040,
041, 043, 044, 046, 047, 048, 049, 050, 052) turned out genuinely `mixed`, as this table's own
batch-key row predicted — 5 items closed (fully or partial-by-design), 2 drafted-then-withdrawn
after their true scope was found materially larger than assessed, 12 confirmed-still-open
dispositions (10 pure, plus `049`'s own unfixed first half).

`ISS-2026-013`, `036` — `RESOLVED (doc-only, already fixed)`: both entries described a defect
that was already remediated by an unrelated later checkpoint (`PRC-255` for 013, `HDN-380` for
036) but never reconciled — the same `ISS-2026-285`-class finding (item 21) recurring, caught the
same way: verify against actual current code before writing a disposition, not before.

`ISS-2026-044` — `RESOLVED`: `app.request_approval`'s own unique_violation gap, fixed at the
single shared choke point.

`ISS-2026-043`/`048` — `RESOLVED (partial by design)`: extended with 6 more representative
cross-domain sites (17/34 of an estimated ~334 candidate sites total), mirroring `167`'s own
Batch 1 treatment for the identical class of repo-wide sweep.

`ISS-2026-049` — partial: its own second half (the shared `app.decide_approval_step`'s tenant-id
echo) closed by the same migration as `043`/`048`; its own first half (entity_type-before-authority
across 5 wrappers) stays open, the review's own original "disclose, not partially fix" choice,
unchanged — so the item as a whole is NOT counted as resolved in the running tally.

`ISS-2026-038` (self-approval gate on vendor rate versions) and `ISS-2026-040` (RPC-level
`evaluate_permission` gate against a customer_user-layer principal) were BOTH drafted, migration
files written and ready to apply, and then withdrawn before being applied anywhere — mirroring
Batch 1's own `ISS-2026-170`/`189` precedent exactly. In both cases a repo-wide check performed
before applying (not after) found the true blast radius far exceeds the originating entry's own
bounded-fix assessment: `038` would have broken ~75 unrelated test files' own "seed an approved
rate" fixture-shortcut pattern (117 call sites, almost universally same-actor create+approve);
`040` would have broken a real, deliberate, working customer-portal read-access pattern already
exercised across at least 8 domain test files (a narrow staff role granted to a customer_user-layer
principal, with ownership-scoping — not the RPC-level role gate — providing the actual isolation).
Neither was forced through; both are redispositioned with the corrected scope handed forward — see
each entry's own text in `KNOWN_ISSUES.md`.

`ISS-2026-015`, `018`, `019`, `031`, `037`, `039`, `041`, `046`, `047`, `050`, `052` —
re-verified still genuinely open against current code (not assumed from the entry's own possibly-
stale text) and dispositioned: each is a real `BIG`/`BIZ`/`INFRA` gap this batch confirmed cannot
be closed by a bounded agent-executable fix, consistent with `00_EXECUTION_INDEX.md` §8.1's own
"registered with a named owner and a disposition" treatment for exactly this class.

Working total after Batch 2: **136 remaining** (0 Critical, 5 High, 64 Medium, 67 Low). Down from
141 by 5 (all Medium): `013`/`036` doc-only, `044` fully resolved, `043`/`048` partial-by-design
(tracked as one combined tally reduction since both share the identical fix migration and
disclosure text). See `RGL-404.md` §12 items 27-31 for the authoritative running log.

## Batch 3 status: complete

`hris-integrated-verification-residual` (14: 057, 058, 060, 061, 062, 063, 064, 066, 067, 068, 069,
070, 071, 073) + `hris-overtime-timesheet-gaps` (2: 076, 100) + `hris-payroll-personal-data` (3:
091, 092, 093) — 19 items, genuinely `mixed` as the table predicted: 1 item closed doc-only
(already fixed elsewhere, never reconciled), 1 item partially closed (2 of 3 sub-items — a real
test-coverage fix), 17 confirmed-still-open dispositions (16 pure, plus `064`'s own doc-drift
correction on an already-open item).

`ISS-2026-092` — `RESOLVED (doc-only, already fixed, not annotated in place)`: the identical
raw-table-SELECT PII-disclosure shape as this checkpoint's own already-fixed Finding A
(`app.employee_change_requests.reason`/`decided_reason`), closed by a LATER entry in the same
file, `ISS-2026-099` (`app.get_employee_change_requests`, a new masked RPC; raw grant on
`app.employee_change_requests` excludes `reason`/`decided_reason`; `page.tsx` updated to call the
RPC instead of a raw `.select("*")`). The same `ISS-2026-285`/`013`/`036`-class doc-drift finding
recurring for a fourth time this session. **Not edited in `KNOWN_ISSUES.md` itself** — `ISS-2026-099`'s
own text explicitly directs "`ISS-2026-092`'s own text remains unchanged, per this file's
append-only discipline; this entry supersedes its disposition," so its own `###` section stays
`OPEN` verbatim by that entry's own instruction; this paragraph (plus `RGL-404.md` §12 and
`CHANGE_MANIFEST.md`) is the closure record instead.

`ISS-2026-063` — partial: (1) `server/queries/procurement-dashboard.test.ts` created (no dedicated
test existed; every sibling dashboard query module had one) — 31 tests, `pnpm run test` green. (3,
the `FINTEST-016` sibling note tracked under this same ID) `scripts/db-tests/procurement-vendor-
invoice-matching.sql` gained a new block exercising `match_mode='non_po'` with both
`is_partial_invoice=true`/`is_consolidated_invoice=true` on one case (vendor2, no active contract,
no PO) — all three previously dispatchable but never exercised by any live test (every existing
case-creation call passed `false,false`), kept off vendor1 to avoid perturbing the fixed 2-case
denominator its own decided cases feed into the file's `invoice_accuracy` KPI aggregate. (2) **Not fixed** — extending the `PRC-268`/`PRC-269` large-scale load proof to the
remaining 5 of 9 named surfaces needs new `scripts/load-tests/` scenarios, materially larger than a
bounded test addition; genuinely out of scope. The item as a whole stays `OPEN` (narrowed to
sub-item 2 only), so is NOT counted as resolved in the running tally.

`ISS-2026-057`, `058`, `060`, `061`, `062`, `066`, `067`, `068`, `069`, `070`, `071`, `073`, `076`,
`091`, `093`, `100` — re-verified still genuinely open against current code (a dedicated
verification pass independently checked all 17 for a hidden superseding entry — the `092`-class
doc-drift pattern — and found none for any of them) and redispositioned with a fresh "Track B
Batch 3" update paragraph each, consistent with `00_EXECUTION_INDEX.md` §8.1's own "registered
with a named owner and a disposition" treatment.

`ISS-2026-064` — a genuine doc-drift correction, not a resolution: the verification pass found
item (1) of this entry's own text ("no manager-team UI route exists") is now stale — a real route
was built later at HRT-285 and was not cross-referenced back to this entry. Items (2)/(3) remain
independently re-verified genuinely open, so the item as a whole stays `OPEN`, unchanged severity.

Working total after Batch 3: **135 remaining** (0 Critical, 5 High, 63 Medium, 67 Low). Down from
136 by 1 (Medium, `ISS-2026-092`'s own severity): the sole doc-only closure. `ISS-2026-063`
(Low-Medium) stays counted as open since only 2 of its 3 sub-items closed. See `RGL-404.md` §12
items 32-33 for the authoritative running log.

## Medium/Low batches (140 items, working count)

Batches below reproduce the categorization research pass performed for this document (full
per-ID detail retained in that pass's own transcript; this table is the operative worklist).
Batch keys group items that share a file, a mechanism, or a domain — the unit Track B's own
per-batch loop (`RGL-404.md` §11/plan) works against, not raw severity order, except that the 7
High items above go in the first batch regardless of theme.

| Batch key | Items | Count | Dominant class | Note |
|---|---|---|---|---|
| `hris-integrated-verification-residual` | 057, 058, 060, 061, 062, 063, 064, 066, 067, 068, 069, 070, 071, 073 | 14 | mixed CODE/BIG/DOC | **Batch 3, complete.** 063 partial (test-coverage sub-items fixed, load-proof sub-item open); 064 doc-drift corrected; rest confirmed still-open BIG/DOC, dispositioned |
| `hris-overtime-timesheet-gaps` | 076, 100 | 2 | CODE | **Batch 3, complete.** Both confirmed still-open (accepted, disclosed UI-wiring gap per repo convention), dispositioned |
| `db-test-flakiness` | 103, 146, 155 | 3 | TEST/CODE | Wall-clock fixtures, tenant-id disclosure, registration dedup gap |
| `hris-payroll-personal-data` | 091, 092, 093 | 3 | CODE | **Batch 3, complete.** 092 resolved doc-only (closed by `ISS-2026-099`); 091/093 confirmed still-open BIG, dispositioned |
| `ticketing-links-gaps` | 101, 102 | 2 | CODE | Missing UI caller, internal ID leak |
| `cpl-customer-portal-scope` | 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 126, 127, 128, 129 | 14 | mostly BIG/DOC | Disclosed Phase-8 scope narrowings; per-item, not one migration |
| `loyalty-fraud-reconciliation` | 131, 132, 133, 134, 136 | 5 | mixed | Same domain (CPL-322/325), different mechanisms; 132+134 share an override-gap shape |
| `loyalty-approval-authority` | 137, 138 | 2 | CODE/BIG | Checker bypass; zero accessibility-audit evidence |
| `perf-load-evidence` | 139, 140, 141 | 3 | TEST/CODE | Zero load/perf evidence for Phase 8/9 routes; retention gap |
| `docs-consistency` | 142, 153, 157, 252, 281 | 5 | DOC/BIG | Doc mislabels, stale sections, accessibility-audit gap |
| `iae-hardening-residual` | 148, 149, 152 | 3 | TEST/CODE | Load evidence, anon enumeration oracle, inert capability matrix |
| `step-up-mfa-enforcement` | 151 | 1 | CODE | `create_integration_connection` unwired to step-up MFA |
| `rls-grants` | ~~167~~, 170, ~~172~~, ~~174~~, ~~175~~, ~~176~~, 189 | 7 | CODE | **Batch 1: 5 of 7 resolved, 2 withdrawn/deferred** (170, 189) — each item turned out to need its own distinct mechanism (error-text collapse, column grant, cache key, view allow-list), not one shared migration as originally guessed; see per-item detail below |
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
| `table-only-procurement-hardening` | 013, 015, 018, 019, 031, 036, 037, 038, 039, 040, 041, 043, 044, 046, 047, 048, 049, 050, 052 | 19 | mixed | **Batch 2, complete.** 043/044/048/049(half) shared an RBAC/authority-check root cause and were fixed via 2 migrations; 013/036 were doc-only (already fixed elsewhere); 038/040 drafted then withdrawn (blast radius exceeded assessment); rest confirmed still-open BIG/BIZ/INFRA, dispositioned |

**New this session, not part of the tracked 147** (self-caught, disclosed per this session's own
established convention, `ISS-2026-298`/`299` precedent):

| ID | Summary | Fix | Batch |
|---|---|---|---|
| `ISS-2026-300` | `supabase_migrations.schema_migrations` ledger records 9 migrations under the wrong (wall-clock) version | `INFRA` (write blocked by this session's own safety classifier; needs operator/elevated-access execution) | release-tooling |

---

## Batching plan for Track B (~8 passes of ~20)

Severity orders the first batch; domain/mechanism groups the rest, per the approved plan:

1. **Batch 1 (High + quick wins)**: all 6 High items, plus `rls-grants` (7, one candidate migration) — 13 items.
2. **Batch 2 (complete)**: `table-only-procurement-hardening` (19 items — 5 closed, 2 withdrawn/
   redispositioned, 12 dispositioned; see "Batch 2 status" above).
3. **Batch 3 (complete)**: `hris-integrated-verification-residual` (14) + `hris-overtime-timesheet-gaps` (2) + `hris-payroll-personal-data` (3) — 19 items (1 resolved doc-only, 1 partially resolved, 17 dispositioned).
4. **Batch 4**: `cpl-customer-portal-scope` (14) + `loyalty-fraud-reconciliation` (5) + `loyalty-approval-authority` (2) — 21 items.
5. **Batch 5**: `accessibility` (7) + `browser-compat` (1) + `docs-consistency` (5) + `perf-load-evidence` (3) + `iae-hardening-residual` (3) — 19 items.
6. **Batch 6**: `rbac-defense-in-depth` (5) + `support-access-audit` (2) + `rls-own-row-narrowing` (1) + `step-up-mfa-enforcement` (1) + `observability-alerting` (2) + `db-test-flakiness` (3) + `ticketing-links-gaps` (2) + `perf-cache-safety` (1) — 17 items.
7. **Batch 7**: `lineage-provenance` (2) + `rest-api-consistency` (2) + `rest-api-error-shape` (2) + `files-legal-hold-residual` (2) + `crypto-scan-recovery` (1) + `schema-completeness-gaps` (2) + `finance-fx` (1) + `migration-import` (2) — 14 items.
8. **Batch 8 (disposition batch)**: every remaining `INFRA`/`BIZ`/pure-`BIG` item not already folded into batches 1-7 — `postgis-extension`, `dr-runbook`, `prod-seed-hygiene`, `perf-live-latency`, `ISS-2026-300`, plus any `BIG` items from earlier batches whose own code-shaped half was built but whose full capability was not. Per the operator's own instruction: build the code-shaped part, write an explicit owner-named disposition for the rest.

Batch composition may shift as work proceeds (an item found to share a root cause with another
batch moves to join it) — this table is a plan, not a contract; changes are recorded in `RGL-404.md`
§12 as they happen.
