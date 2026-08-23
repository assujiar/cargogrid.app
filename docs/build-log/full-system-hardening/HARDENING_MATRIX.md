# Step 15 — Hardening Matrix

**Produced by:** `CG-S15-HDN-001` (Prompt 369, Full-System Hardening WBS Runtime Kickoff)
**Governs:** `HDN-370` … `HDN-389`
**Companion files:** `docs/build-log/full-system-hardening/00_EXECUTION_INDEX.md` (routing),
`docs/build-log/full-system-hardening/BLOCKER_LEDGER.md` (findings)

Prompt 369 step 4 requires a matrix for each of the 16 mandatory hardening gates. Each is
seeded below with the evidence that **already exists** at this checkpoint, so no lane starts
from zero and no lane rediscovers a known item.

**Status vocabulary — used strictly.** `NOT_RUN` is never reported as a pass, and
"not triggered" is never reported as "verified".

| Status | Meaning |
|---|---|
| `NOT_RUN` | The lane has not executed. Default for every gate at this checkpoint |
| `PASS` | Executed against a real target, observed green |
| `PASS_SUBSTITUTE` | Executed against a disclosed substitute (disposable DB / migrated-but-not-running live project), with the substitution's limits stated |
| `PARTIAL` | Executed, but one or more required dimensions were not exercised. **Not a pass** |
| `FAIL` | Executed, observed red |
| `TRACKED_GAP` | Cannot be executed here. Recorded with owner, risk and the exact missing command. **Not a pass** |

---

## Gate index

| # | Gate | Lane | Status at kickoff | Seeded evidence |
|---|---|---|---|---|
| 1 | Full regression | `HDN-370` **`VERIFIED`** | **`PARTIAL`** — all local gates green; **CI red on all 3 jobs**; `test:e2e` a `TRACKED_GAP` | §1 |
| 2 | Cross-module transactional integrity | `HDN-371` | `NOT_RUN` | §2 |
| 3 | Tenant isolation | `HDN-372` | `NOT_RUN` | §3 |
| 4 | RLS / RBAC | `HDN-373` | `NOT_RUN` | §4 |
| 5 | Financial integrity | `HDN-374` | `NOT_RUN` | §5 |
| 6 | Data lineage | `HDN-375` | `NOT_RUN` | §6 |
| 7 | API compatibility | `HDN-376` | `NOT_RUN` | §7 |
| 8 | Storage / signed URL | `HDN-377` | `NOT_RUN` | §8 |
| 9 | Security hardening | `HDN-378` | `NOT_RUN` | §9 |
| 10 | Performance / scalability | `HDN-379` | `NOT_RUN` | §10 |
| 11 | Accessibility | `HDN-380` | `NOT_RUN` | §11 |
| 12 | Browser / device compatibility | `HDN-381` | `NOT_RUN` | §12 |
| 13 | Observability | `HDN-382` | `NOT_RUN` | §13 |
| 14 | Backup / restore | `HDN-383` | `NOT_RUN` | §14 |
| 15 | Disaster recovery rehearsal | `HDN-384` | `NOT_RUN` | §15 |
| 16 | Data migration rehearsal | `HDN-385` | `NOT_RUN` | §16 |
| X | **Cross-cutting: CI-mirrors-hosted** | **all lanes** | `PASS` at kickoff | §17 |

---

## 1. Full regression — `HDN-370`

> **Result, 2026-08-23 (`CG-S15-HDN-002`, Tier C `VERIFIED`): `PARTIAL` — not a pass.** This is
> the checkpoint's own final, adversarially-reviewed verdict on the gate itself — `HDN-370`
> being `VERIFIED` means its review was done correctly, not that the underlying gate is fully
> green. It is not.
> Local gates are green (`typecheck` 0, `lint` 0 errors, `test` **5394/5394**, `db-tests`
> **229/229 ALL PASSED**, `next build` **246 routes, 0 errors**, governance gates clean), and
> this lane's owned repair (`HDN-BLK-002`) is closed at the root and **proven by sweep**.
> But the gate is **not** a pass, for two reasons recorded rather than smoothed over:
> **(a)** all three CI jobs failed on the most recent push to `main` (#109, `e5da061`), with
> two further prior push-to-`main` runs also showing `failure` at the workflow level though not
> individually root-caused (`HDN-BLK-007/008/009`), so **six governance steps — including the
> secret scan and the dependency vulnerability audit — have never executed in CI on a push**
> (a further step, Protected-path check, is PR-only-gated and would be absent from a push
> regardless); **(b)** `test:e2e` could not
> be executed here and is a `TRACKED_GAP`. Full evidence: `HDN-370.md`.
>
> **`next build` is not wired into CI at all** — a Phase 0 (`PH0-88`) decision taken when the
> repository had no application code, now covering 228 page routes, 13 API routes and 136
> `"use server"` modules. It passes when run directly, so this is a coverage gap, not a live
> breakage. Owner: `HDN-387`, with the other three CI repairs.

**Objective.** Execute and reconcile the full regression suite across Platform, Commercial,
Operations, Finance, Advanced TMS/WMS, Procurement, HRIS/Ticketing, Customer Portal/Loyalty
and Intelligence/Enterprise.

| Dimension | Seeded state at kickoff | Required of `HDN-370` |
|---|---|---|
| `typecheck` | 0 errors | Re-run, exact result |
| `lint` | 0 errors / 337 warnings | Re-run; the 337 is the standing pre-existing `@next/next/no-html-link-for-pages` class — do not "fix" it inside this lane |
| `pnpm run test` | 5394 tests, 5393 pass, 1 fail — `checkWorktreeCollision`, the known checkpoint-state-dependent non-defect | Re-run; expect 5394/5394 once a commit exists |
| `bash scripts/db-tests/run.sh` | **229/229 `ALL PASSED`**, Sunday 2026-08-23, ~11:15–11:45 UTC, 306 migrations, disposable DB | Re-run; record day of week **and** UTC time of day |
| `next build` | not run — this checkpoint touches no `app/`, `components/`, `"use server"` | Run it; `HDN-370` exercises UI-adjacent regression |
| `docs:check`, `security:check`, `git:check-paths` | clean | Re-run |
| E2E / browser | No live sign-in flow exists; `e2e/` runs only against synthetic fixtures and two unauthenticated public routes | `TRACKED_GAP` with the exact missing prerequisite — never a substituted pass |

### 1.1 The day-of-week / wall-clock fixture flake class — this lane owns closing it

Four registered issues, one defect family: a `scripts/db-tests/*.sql` fixture silently
assumes something about real wall-clock time that is not always true.

| Issue | File | Trigger dimension | State |
|---|---|---|---|
| `ISS-2026-103` / `ISS-2026-115` | `scripts/db-tests/hris-overtime-timesheet.sql` | day-of-week (Sat/Sun) | **CLOSED** — fixture pinned to the most recent weekday (`cdbccc7`). **This is the pattern to reuse.** |
| `ISS-2026-077` | `scripts/db-tests/hris-leave-permit-business-trip.sql` | wall-clock **and** day-of-week | `OPEN` |
| `ISS-2026-135` | `scripts/db-tests/hris-shift-roster-scheduling.sql` | day-of-week (a coverage rule keyed to `extract(dow from current_date)` can auto-generate a real assignment, which an unconditional "always null" negative control cannot tolerate) | `OPEN` |
| `ISS-2026-154` | `scripts/db-tests/hris-attendance.sql` | **time-of-day**: a ~1-hour real-UTC window immediately after each day's 21:00 UTC (04:00 Asia/Jakarta) shift-day boundary | `OPEN` |

**Kickoff observation, stated precisely.** All four files executed and passed in this
checkpoint's full run. That is **not** proof the class is closed:

- `ISS-2026-135`'s day-of-week dimension **was genuinely in play** — the run was a Sunday —
  and did not fire.
- `ISS-2026-077`'s dimension is wall-clock *and* day-of-week; the day half was in play, the
  wall-clock half was not controlled for.
- `ISS-2026-154`'s dimension was **not exercised at all**: its trigger window is ~21:00–22:00
  UTC and this run was ~11:15–11:45 UTC, roughly ten hours outside it.

So the correct kickoff status for this class is **`PARTIAL` — one dimension exercised and
not fired, one dimension not exercised.** A green suite on one Sunday morning is not
evidence of a day-independent gate.

**Required of `HDN-370`:** make each fixture's temporal assumption explicit and pinned, then
**prove day-independence rather than observe it** — e.g. by driving the resolver's inputs
directly across all seven days and across the shift-day boundary window, not by re-running
the suite and hoping. A regression baseline green only on some days of the week is not a
release gate.

> ### Amendment, 2026-08-23 (`CG-S15-HDN-002`) — **the table above is wrong, and is kept for the record**
>
> `HDN-370` re-derived every member from live evidence instead of accepting its issue text, and
> **three of the four were misclassified.** The trigger dimensions recorded above are corrected as:
>
> | Issue | Recorded above as | **Actually** | Real exposure |
> |---|---|---|---|
> | `ISS-2026-077` | wall-clock and day-of-week | **Timezone-boundary mismatch** — `current_date` resolves in the session timezone (`Etc/UTC`), `work_date` in the tenant policy's (`Asia/Jakarta`) | **196 / 672 swept instants — 29%, exactly 7 h every day** |
> | `ISS-2026-135` | day-of-week, via a `extract(dow from current_date)` coverage rule | **A hardcoded calendar date.** That coverage rule is in a *different* file; this fixture has no wall-clock coupling at all | **1 / 30 swept dates — `2026-08-18`, a Tuesday** |
> | `ISS-2026-154` | time-of-day, 04:00 Jakarta boundary | Confirmed exactly as recorded | 84 / 2,016 swept instants — 1 h every day |
> | `ISS-2026-103`/`115` | day-of-week | Confirmed — the only genuine day-of-week member | already closed at `cdbccc7` |
>
> All three open members are **fixed at the root and proven by sweep** (0 failing instants
> after the fix, all 7 weekdays). `ISS-2026-077`/`135`/`154` → `RESOLVED`. `HDN-BLK-002` is
> closed. The correct name for this family is **temporal-frame coupling**, not day-of-week
> flakiness: in every case a date was compared across two different frames of reference —
> session vs policy timezone, shift-day vs calendar-day, literal vs wall-clock date — without
> normalizing. Full evidence: `HDN-370.md` §5, §8.

### 1.2 Other pre-existing test-suite items seeded here

| Issue | Item | Note |
|---|---|---|
| `ISS-2026-144` | `scripts/db-tests/procurement-vendor-performance.sql:978` intermittent Phase 6 assertion | Passed this checkpoint. Confirm or re-register |
| `ISS-2026-156` | `scripts/db-tests/n8n-integration.sql:204` lookup has no `ORDER BY` | Non-manifesting in real alphabetical order (position 161 vs 227 of 229). Fragility, not a live defect |
| `ISS-2026-147` | Zero test coverage for the 9 `/api/v1` REST route handlers | Medium. Relevant to `HDN-376` too |

---

## 2. Cross-module transactional integrity — `HDN-371`

> **Result, 2026-08-23 (`CG-S15-HDN-003`): the flow-level chains are reconciled against
> existing, currently-passing evidence** (below), and **one systemic finding** was made
> by a direct code-level sweep rather than by re-deriving what 118 existing sequential
> test calls already prove: `HDN-BLK-010`/`ISS-2026-162` — 7 of 19 genuine cross-module
> boundary functions (`prepare_/convert_/link_/create_from_` shape, enumerated
> exhaustively from all 306 migrations) share an identical concurrent-idempotency gap
> that a 12th sibling function, `prepare_wms_outbound_from_shipment`, already proves the
> fix for in this exact codebase (its own migration names the pattern "design note
> 9(a)"). **6 of the 7 are Finance-domain.** Bounded to **Medium**, not Critical/High, by
> direct verification: all 7 target tables carry a confirmed backing `unique`
> constraint, so no duplicate financial or handoff record can be created — the real
> consequence is a raw, uncaught `unique_violation` surfaced to a genuinely-racing
> second caller instead of the graceful "already created" response every other caller
> gets. **Deferred to `HDN-374`**, not fixed here (six of seven are Finance-domain
> functions, and `AGENTS.md` names finance-posting changes as needing their own
> dedicated treatment). Full evidence: `HDN-371.md`.

| Chain | Seeded state | Result |
|---|---|---|
| lead → quote → job | Built and `VERIFIED` across Phases 2–3 | **Reconciled** — `prepare_job_order_handoff`/`prepare_job_order` traced end to end; both idempotent on their own key (one lacks the race-safe exception handler, `HDN-BLK-010`); existing db-test coverage (`commercial-job-order-lineage.sql`, `operations-job-order.sql`) confirmed passing at `HDN-370`'s 229/229 full regression |
| shipment → ePOD → billing | Phases 3–4 | **Reconciled** — `prepare_finance_invoice_from_readiness` traced: `v_subtotal`/`v_currency` are a direct, unmutated copy of the job's own governed `revenue_snapshot`, never independently recomputed. Idempotent on `(tenant_id, billing_readiness_handoff_id)`, backed by a real unique constraint; lacks the race-safe exception handler (`HDN-BLK-010`) |
| actual cost → AP → settlement | Phase 4 | **Reconciled** — `prepare_finance_vendor_bill_from_actual_cost` and `prepare_finance_settlement` both idempotent on a real unique-constrained key; both lack the race-safe exception handler (`HDN-BLK-010`) |
| invoice → receipt → journal, reversal/correction | Phase 4 | **Reconciled.** `prepare_finance_journal_reversal`/`_adjustment` verified genuinely additive by direct code read — zero `delete from` in their migration file; both take `p_original_journal_id` and produce a new correcting record referencing it, never mutating or removing the original. Both lack the race-safe exception handler (`HDN-BLK-010`) |
| WMS inbound → outbound | Phase 5 | **Reconciled, and the source of the fix pattern.** `prepare_wms_outbound_from_shipment` has the correct, documented race-safe pattern; `prepare_wms_inbound_from_shipment` (its own earlier-created sibling) does not — same root class as `HDN-BLK-010`, folded into that one finding rather than opened separately |
| customer portal / loyalty / tickets | Phases 7–8 | **Reconciled** — `link_ticket_record`/`link_ticket_portal_record` both have the race-safe pattern; ticketing not implicated in `HDN-BLK-010` |
| Idempotent retry at every module boundary | `ISS-2026-029` closed 27 functions / 29 idempotency short-circuits at `ATW-031` | **Re-proven, and a live gap found.** Sequential idempotency (retry returns the original, ignores new params) confirmed intact and enforced at 118 existing call sites across 58 files. Concurrent-race safety was the untested half — swept directly, 7/19 gapped (`HDN-BLK-010`) |
| Concurrent submission | Phase 9 Tier C re-reproduced concurrency/CHECK-bypass fixes | **Partially re-proven.** `HDN-BLK-010` is exactly this dimension for the 19 cross-module boundary functions; a live two-process race attempt against `prepare_finance_invoice_from_readiness` did not reproduce the raw-error path within available time (see `HDN-371.md` §5.3 for why) — the finding rests on direct code verification (confirmed present/absent by reading each function body and its target table's constraints), not on an empirically forced race, and is disclosed as such rather than overclaimed |
| Source-domain ownership conflicts | None open | **None found.** `HDN-BLK-010` is a defect (an inconsistently-applied safety pattern), not an ownership conflict — no two modules claim authority over the same canonical entity |

**Hard gate:** `HDN-371` must be `VERIFIED` before `HDN-374`, `HDN-375` and `HDN-376` begin.

---

## 3. Tenant isolation — `HDN-372`

| Surface | Seeded state | Required |
|---|---|---|
| Database / RLS | 568 tables RLS-enabled, 448 policies on the live project | Cross-tenant negative tests per surface |
| PostgREST exposure | `app` is **not** in the Data API's `db_schema` (`public,graphql_public`), so no `app` table is reachable over PostgREST regardless of RLS | Confirm still true; do not treat as a substitute for RLS |
| Storage, cache, queue, reports, exports, jobs, integrations, AI context | Built across Phases 1–9 | Tenant A/B negative tests each |
| Support / impersonation | Purpose- and time-bound, logged, revocable | Test revocation propagation |
| Exception message leakage | **`ISS-2026-146`** — cross-tenant `tenant_id` disclosure via exception text, 2,087+ occurrences since Phase 6, reproduced live | Seeded here. Low, but it *is* a cross-tenant disclosure — re-assess reachability under this gate's own severity policy |
| SSO config enumeration | **`ISS-2026-149`** — `app.resolve_enterprise_idp_by_email_domain` is an unthrottled, anonymous, cross-tenant enumeration oracle | Seeded here; also relevant to `HDN-378` |

**Hard gate:** `HDN-372` must be `VERIFIED` before `HDN-373` and `HDN-378` begin.

---

## 4. RLS / RBAC — `HDN-373`

| Scope | Seeded state | Required |
|---|---|---|
| Four-layer access model | Supreme Admin, User Admin, internal hierarchy, Customer User — built at Platform Core | Positive **and** negative matrix per module/action/field/record/status/amount/scope |
| `SECURITY DEFINER` posture | 1,878 functions, **100% pinned search_path**, 0 with mutable search_path, 0 mutable + anon/auth-callable | Re-verify; this is a real, measured property, not an assumption |
| `function_search_path_mutable` advisories | 791 — **all `security invoker`**, so no privilege to escalate | Do not "fix" as a batch; confirm the invoker property still holds |
| `rls_enabled_no_policy` | 120 — INFO, default-deny by design | Confirm intent per table |
| Field masking (finance, payroll, personal, tax, bank, margin, support, AI evidence) | Built per phase | Verify |
| Supreme Admin absolute CRUD | **RPD-022 ratified accepted residual risk** | Must be **disclosed**, never weakened silently, and never described as tamper-proof or immutable-for-all |
| Maker/checker collapse | **`ISS-2026-139`** — `LYL:Edit` alone can submit **and** instantly auto-fulfill a `discount_voucher` redemption for any loyalty account in the tenant | Seeded here. Medium; re-assess under this gate |
| Supreme-Admin-override gap | **`ISS-2026-137`** — `app.loyalty_account_tier_movements` missed from `ISS-2026-130`'s fix scope | Seeded here |

---

## 5. Financial integrity — `HDN-374`

| Dimension | Seeded state | Required |
|---|---|---|
| 24 financial-integrity scenarios (or repository equivalents) | Phase 4 `VERIFIED` | Run and reconcile |
| quote → cost → job → shipment → ePOD → invoice → payment → journal → AP → settlement → loyalty liability | Built | Reconcile end to end |
| Period lock, reversal, correction, duplicate retry, concurrency, rounding | Built | Test edges |
| Idempotency reversal defect | `ISS-2026-029`: `apply_finance_ar_allocation` / `reverse_finance_ar_allocation` wrote the same table under the same unique key, so reusing a key to **reverse** silently did nothing and returned success. Closed at `ATW-031` | **Regression-prove it stays closed** |
| Loyalty liability currency scoping | **`ISS-2026-136`** item 2 still `OPEN` | Seeded here |
| RPD-016 statutory gates | Indonesia tax/payroll requires current dated SME/legal evidence, configurable | Verify gating, do not activate without evidence |
| Concurrent-idempotency gap, 6 Finance-domain boundary functions | **`HDN-BLK-010` / `ISS-2026-162`**, found and bounded to Medium at `HDN-371` — `prepare_finance_invoice_from_readiness`, `_journal_adjustment`, `_journal_reversal`, `_payroll_disbursement_handoff_from_payroll_run`, `_settlement`, `_vendor_bill_from_actual_cost` each have an idempotency short-circuit with no `unique_violation` exception handler around the subsequent `insert`. Every target table has a confirmed backing unique constraint (no duplicate-truth risk); the exposure is a raw uncaught error for a genuinely racing caller | **Owned by this lane.** Mirror `prepare_wms_outbound_from_shipment`'s proven "design note 9(a)" nested-exception shape into each function, one additive migration each, each paired with a real two-process concurrency regression test. Full evidence: `HDN-371.md` §6-7 |

**Upstream hard gate:** `HDN-371` `VERIFIED`.

---

## 6. Data lineage — `HDN-375`

| Dimension | Seeded state | Required |
|---|---|---|
| lead → payment → loyalty lineage | Built | Map canonically |
| Downstream projections reference source entity + version + refresh time | Per-phase | Verify each |
| Historical config preservation on critical transactions | Ratified: configuration is versioned/effective-dated; critical transactions retain the applied version | Verify |
| Transaction-lineage hash-chain triggers | 5 of them were among the 20 functions broken by the pgcrypto defect — now fixed | Re-prove they actually chain |
| Reports / dashboards / AI outputs / exports carry lineage metadata | Phase 9 | Inspect |
| Orphan records / projections | none known | Register as blockers |

**Upstream hard gate:** `HDN-371` `VERIFIED`.

---

## 7. API compatibility — `HDN-376`

| Dimension | Seeded state | Required |
|---|---|---|
| REST `/v1` surface | 9 route handlers exist; **`ISS-2026-147`: zero test coverage for them** (Medium) | Seeded here — this gate cannot pass while its primary surface is untested |
| GraphQL parity | Ratified as developed together with REST | Verify parity or register the gap |
| Public / customer / vendor API | Phase 9 (`IAE`), built on `PLT-129` API-key primitives (hash-only storage, scope-narrowing via `app.evaluate_permission()`) | Compatibility + deprecation tests |
| Webhooks — outbound delivery worker on `app.jobs`; inbound third-party-GPS receiver kept separate | Phase 9 / `ADR-0025` B | Signing, replay, retry, DLQ |
| Idempotency, rate limit, error shapes, pagination | Built | Test |
| Schema/migration compatibility plan | Additive / expand-and-contract only | Verify |

**Upstream hard gate:** `HDN-371` `VERIFIED`.

---

## 8. Storage / signed URL — `HDN-377`

| Dimension | Seeded state | Required |
|---|---|---|
| Private file metadata | `PLT-128` — content bytes never stored in the database; `storage_path` is the object key | Inventory every upload/download/preview/OCR/export surface |
| Malware scan gate before release to another user | Ratified mandatory (RPD-032); `malware_scan_status` must be clean before `app.authorize_file_access()` grants a signed download to anyone but the uploader | **Block release on any unscanned downloadable private file** |
| Signed URL expiry, scope, revocation, replay resistance | Designed | Test |
| Real Supabase Storage integration | **Disclosed `NOT_RUN`** — no running application exists | `TRACKED_GAP`, not a substituted pass |
| Retention / legal hold (RPD-025) | **`ISS-2026-142`** — retention/legal-hold classification unbuilt for every Phase 8 Portal/Loyalty table incl. all 6 append-only Loyalty ledgers | Seeded here |

**Upstream:** `HDN-372`.

---

## 9. Security hardening — `HDN-378`

**This lane carries the single most important carry-forward item in Step 15.**

| # | Item | Severity | Disposition required |
|---|---|---|---|
| 1 | **`ISS-2026-150` — IP restriction structurally unreachable.** RPD-023's enforcement is real and correct when called directly, but **no real client IP is threaded through the route-handler layer**, so a fully-configured `enforced`-mode allowlist gives zero real protection against a caller reaching the RPC layer directly (leaked service credential, compromised client bypassing the intended HTTP path). | **High** | **Must not be deferred again.** Phase 9's closure disclosed it as a deliberate first-of-its-kind accepted exception and **named Step 15 as the remedy**. Needs: (a) route-handler-level IP extraction and threading; (b) `assert_ip_allowed` wired into the bounded set of highest-risk SEC/IAM/INTHUB mutations; (c) an explicit ruling on service-role/background callers with no client IP (likely exempt — IP restriction is inherently an interactive-session control). A cosmetic partial wire-up is forbidden: an unenforced parameter nothing populates *looks* fixed without being fixed. |
| 2 | **`ISS-2026-151` — step-up challenge unwired** on `app.create_integration_connection` (**40+ call sites across 16 files**). 3 of 4 target functions were wired at `CG-S14-IAE-039` via migration `20260809200000`; this one was deliberately left rather than risk a rushed mass edit. | Medium | Wire it with real fixtures and a negative-path regression proving genuine enforcement, or rule on it explicitly. |
| 3 | **Move postgis, pg_trgm and btree_gist out of `public`.** Same root class as the fixed pgcrypto defect. Clears **7 of the 8 non-noise security advisories, including the only ERROR** (`rls_disabled_in_public` on PostGIS's own `spatial_ref_sys`, plus 3 `extension_in_public` and 6 `*_security_definer_function_executable` from `st_estimatedextent`). | Medium | **Its own scoped task inside this lane — never folded into another edit.** Every `geometry`/`geography`/`ST_*` caller needs `extensions` in its search_path: a far larger blast radius than pgcrypto's. Note `spatial_ref_sys` cannot have RLS enabled at all — it belongs to the extension and `postgres` is not superuser on a hosted project. |
| 4 | `ISS-2026-149` — anonymous cross-tenant SSO-config enumeration oracle | Low | Throttle or gate |
| 5 | `ISS-2026-146` — `tenant_id` disclosure via exception text | Low | Re-assess reachability |
| 6 | `auth_leaked_password_protection` advisory | Low | **Dashboard setting, not a migration.** Record as a deployment-runbook item |
| 7 | Dependency scan | — | `pnpm run security:check` / `security:audit`. Note `ISS-2026-007`'s lesson: a broken audit gate hid 20 real advisories, 11 high, for a whole phase. The gate now fails when the advisory service is unreachable — **keep that property**. **`HDN-BLK-007`/`ISS-2026-158` (High, added at `HDN-370`) means this exact gate does not run in CI on a push right now.** `HDN-378` cannot treat "the gate exists" as evidence it is enforced anywhere but a local run — it must run `security:audit` itself and record the result, the same gap this row's own note warns about one level up. Do not close this item on CI's silence being green; CI is not currently running it. |
| 8 | OWASP-style abuse: CSRF, XSS, SQLi, IDOR, SSRF, open redirect, file upload, API abuse, webhook spoofing, prompt injection | — | Test per Prompt 389 item 10 |
| 9 | Service-role / secrets server-only; logs redacted | — | Verify |
| 10 | Incident response, key rotation, privileged access audit | — | Test |

**Upstream hard gate:** `HDN-372` `VERIFIED`. Also depends on `HDN-373..377`.

---

## 10. Performance / scalability — `HDN-379`

| # | Item | Seeded state | Required |
|---|---|---|---|
| 1 | **`rbac-enforcement.sql`'s `pg_proc` catalogue scan** — walks every function in `app` calling `pg_get_functiondef()`. At ~2,900 functions it **already exceeds a remote statement timeout**, takes 15–20+ minutes standalone (`ISS-2026-145`), and grows with the schema | `OPEN` | **Scope the scan** before it bites CI. It passes locally today; that is the last thing that is true about it |
| 2 | **892 `unindexed_foreign_keys` advisories** | `OPEN`, explicitly deferred | **An owner-named decision, not a defect.** A design question needing real query patterns. **Neither drop them nor blindly index.** Record the decision and its owner |
| 3 | 982 `unused_index` advisories | noise | The database has served no queries. Not actionable until it has |
| 4 | 157 `auth_rls_initplan` warnings | **FIXED** — `auth.uid()` → `(select auth.uid())` at 228 call sites in 171 policy statements across 65 migrations | Regression-guard: a new policy using a bare `auth.uid()` reintroduces the class |
| 5 | Load/perf evidence | **`ISS-2026-141`** (Phase 8) and **`ISS-2026-148`** (Phase 9): zero load/performance-test evidence exists for any route or RPC at declared target volume | Seeded here. This gate cannot pass on assertion |
| 6 | p95, query count, payload size, job duration, queue depth, cache behavior | — | Measure or register a tracked gap |
| 7 | No `SELECT *` in transactional APIs, no browser-loaded full dataset, no unbounded export/report/import/AI workload, no unsafe cross-tenant cache | ratified | Verify |

---

## 11. Accessibility — `HDN-380`

| Dimension | Seeded state | Required |
|---|---|---|
| Harness | Real, CI-wired Playwright + `@axe-core/playwright` exists (`e2e/smoke.spec.ts`, `e2e/tenant-admin-portal.spec.ts`, `e2e/vendor-registration.spec.ts`, `e2e/supreme-admin-portal.spec.ts`) | Reuse it |
| Coverage | **It has never run against any authenticated route.** Only synthetic inline HTML fixtures and two unauthenticated public routes (`/login`, `/vendor-intake/*`) | **`ISS-2026-140`** (~30 Customer Portal + 9 admin Loyalty routes), **`ISS-2026-153`** (~9 Phase 9 admin/reporting/automation/integration routes) |
| Root cause | No live sign-in flow: every guarded route needs a real authenticated session, which needs a running auth backend | Repository-wide constraint (§10 of the execution index), not this lane's to invent around |
| CI harness itself | **`HDN-BLK-009`/`ISS-2026-160` (Medium, added at `HDN-370`): the `e2e` CI job sets no environment, so `NEXT_PUBLIC_SUPABASE_URL` is unset and every guarded route 500s before any guard logic runs.** This is a *more specific and more fixable* fact than "no live sign-in flow" — it is a missing CI environment block, and it also raises a real product question (should the guard fail safe on missing config, or do the specs encode an intent the code never had?) that this lane, not `HDN-387` alone, is positioned to answer since it owns the accessibility evidence that question blocks | **Check whether `HDN-BLK-009` is still open when this lane runs.** If it is, this lane cannot get further than `ISS-2026-140`/`153` already are without either (a) provisioning its own local `.env` for the harness (a `HDN-380`-scoped workaround, not a CI fix) or (b) formally widening its own `TRACKED_GAP` to say so explicitly, rather than silently inheriting `HDN-370`'s finding as if it were new |
| WCAG 2.2 AA | ratified target | Keyboard, focus, labels, contrast, error summaries, denied states, responsive readability |
| Source-level evidence | `role="alert"`/`role="status"`, `aria-current="page"`, `label`/`htmlFor`, status by text+icon not colour alone | **Evidence of intent, explicitly not a substitute for a run audit** |

`next build` is required from this lane onward.

---

## 12. Browser / device compatibility — `HDN-381`

| Dimension | Seeded state | Required |
|---|---|---|
| Matrix | Chrome, Edge, Safari, Firefox, tablet/mobile | Define it explicitly |
| Runtime | Chromium is available in this environment | Note which of the four can actually be driven here; the rest are tracked gaps |
| PWA posture | RPD-004: responsive **online-first**. Internal ERP desktop-first; customer/field flows mobile-friendly | **Never claim native or offline-sync behavior** |
| Auth/session, uploads/downloads, ePOD, dashboards, tables, modals, mobile forms | built | Exercise, or track the gap |

**Upstream:** `HDN-380`. Inherits `HDN-380`'s own `HDN-BLK-009` exposure — a harness that cannot reach a guarded route in `HDN-380` cannot reach one here either.

---

## 13. Observability — `HDN-382`

| Dimension | Seeded state | Required |
|---|---|---|
| Enterprise monitoring | Built at Phase 9 (`IAE-030`) | Map coverage: app, DB, queue, jobs, integrations, API, AI, storage, security events |
| Incident dedup defect | **`ISS-2026-155`** — a genuine breach of two different `job`-mapped workload types (e.g. `analytics` + `reports`) for the same tenant within the dedup window **collapses into one incident** | Seeded here. Medium — a monitoring gate that silently merges distinct incidents is an observability defect, not a cosmetic one |
| Region/service-capability matrix | **`ISS-2026-152`** — has zero run-time consequence on any data-plane function | Seeded here |
| Alerts actually firing | No deployed environment; no live alerting endpoint | Trigger or simulate; disclose which |
| Runbook links, severity workflow, alert ownership | partial | Verify |
| `docs/runbooks/gps-ingestion-database-outage.md` | Carries `NOT_YET_REHEARSED` and a now-stale "no live Supabase project exists yet" note | Refresh against the current baseline |

---

## 14. Backup / restore — `HDN-383`

| # | Constraint | Detail |
|---|---|---|
| 1 | **Teardown must batch `drop schema app cascade` per transaction** | `max_locks_per_transaction` is too low: fails with **`53200: out of shared memory` at ~1,400 objects**. The statement is atomic, so it rolls back cleanly and nothing corrupts — but any teardown must drop in batches, each in its own transaction |
| 2 | **Migrations are not idempotent** | Bare `create table`, no explicit transaction wrapper. Re-running any applied migration fails. `supabase_migrations.schema_migrations` is the **only** re-run guard — state this explicitly in the deployment runbook |
| 3 | **`auth.users` survives a schema reset** | It is Supabase's schema, untouched by dropping `app`. Any live test cycle must clear it in teardown, or **every rerun collides on `users_pkey`** |
| 4 | Scope | Database, files, configuration, secrets **references** (never secret values), jobs, deployment state |
| 5 | Evidence | An actual restore drill in a safe environment, reconciled on counts, integrity, RLS, files and jobs — plus RPO/RTO actuals versus the disclosed default |
| 6 | Target | **Never the live project's data.** State the target explicitly before executing |

**Block release if restore evidence is absent for required scope.**

---

## 15. Disaster recovery rehearsal — `HDN-384`

| Dimension | Seeded state | Required |
|---|---|---|
| Scenarios | major outage, data corruption, provider failure, security incident | Define success criteria per scenario |
| Inherited constraints | All three of §14's constraints apply verbatim to any DR teardown/rebuild | Carry them into the runbook |
| Enterprise DR controls | Built at Phase 9 (`IAE-035`) | Exercise or tabletop |
| Communication, ownership, escalation, customer impact | — | Verify |
| Recovery time / data loss | — | Measure where feasible; disclose where not |

**Upstream:** `HDN-383`.

---

## 16. Data migration rehearsal — `HDN-385`

| Dimension | Seeded state | Required |
|---|---|---|
| Real precedent | **306/306 migrations applied cleanly to a real hosted project**, ledger in sync — the strongest single piece of migration evidence this repository has | Cite it; do not re-derive it |
| Non-idempotency | §14 item 2 applies | Rollback/rerun idempotency must be tested honestly against it |
| Mapping, preview, validation, duplicate handling | Import/Export Job Framework (Phase 5) | Exercise |
| Commit + reconcile counts/totals/files/lineage | — | Rehearsal environment only |
| Do not fabricate historical data | ratified | Hard rule |

**Upstream:** `HDN-371`.

---

## 17. Cross-cutting — CI mirrors hosted, in both directions

**Status at kickoff: `PASS`.** This is the only gate already green, and it is the one most
easily broken by an unrelated edit.

| Direction | Mechanism | Regression risk |
|---|---|---|
| Extension schema | pgcrypto installed into `extensions` explicitly, schema created first, so a bare CI Postgres matches the hosted layout | A new `create extension` without an explicit schema recreates defect 1 |
| Function search_path | 39 pgcrypto callers pin `extensions`; 7 formerly-unpinned functions pinned (an unpinned function inherits the **caller's** search_path, not the session default) | A new unpinned `SECURITY DEFINER` function recreates defect 2 |
| `auth.users` column types | Stub declares `email`/`role` as `varchar(255)`, `phone` as `text` — matching real Supabase | Reverting to `text` recreates defect 3 |
| Database-level search_path | `setup-disposable-db.sh` sets `"$user", public, extensions`, mirroring what Supabase sets and stock Postgres does not | Removing it makes top-level `digest()`/`hmac()` calls fail locally while passing live |
| RLS InitPlan form | `(select auth.uid())`, not bare `auth.uid()` | A new policy with a bare call reintroduces per-row evaluation |

**Every lane's Tier B walk must check its own diff against this table.** A hardening change
that reintroduces the divergence re-blinds CI to the exact class the live migration exposed —
the one class that, by construction, no single environment can catch.
