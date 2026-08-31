/**
 * Release-candidate freeze enforcement — Step 16, `CG-S16-RGL-003` (Prompt 393,
 * No-New-Feature Rule), enforcing the freeze recorded by `CG-S16-RGL-002`
 * (Prompt 392) in docs/build-log/release-go-live/RGL-392.md §1-§4.
 *
 * A freeze that only exists as prose is not a control. This turns
 * `RC_FROZEN` into a mechanical check: it recomputes the digests Prompt 392
 * froze and fails closed if the candidate's shippable content has drifted.
 *
 * What it guards, and why each one:
 *
 *   - migrations   Schema is the least reversible thing a release can change,
 *                  and "never edit an applied migration" is an AGENTS.md rule
 *                  with real incident history behind it (ERR-2026-001..003).
 *   - db-tests     The evidence that the migrations are correct. Freezing the
 *                  schema while leaving its test suite mutable would let the
 *                  candidate's proof change under it.
 *   - lockfile     The resolved dependency set. Prompt 392 §2 anchors the
 *                  dependency freeze here rather than on package.json, because
 *                  six manifest entries are caret-ranged and only the lockfile
 *                  pins them.
 *
 * Deliberately NOT guarded: docs/**, which every Step 16 lane must write to by
 * charter. A freeze that forbade its own evidence trail would be unusable.
 *
 * This is a local/CI gate over repository content. It cannot police a direct
 * push to an unprotected `main` — see RGL-393.md §3 for the ingress paths that
 * remain open. Do not read a pass here as "the candidate is sealed".
 *
 * CORRECTED 2026-08-30: this comment, and the console line below, previously
 * also named the Vercel `main` -> production auto-deploy as an open ingress.
 * That was true when written and is no longer: `RGL-BLK-001` was closed by
 * mechanism (`vercel.json` sets `git.deploymentEnabled.main = false` and routes
 * every build through `scripts/release/check-go-decision.ts`, which fails
 * closed unless a recorded go decision matches the exact commit SHA). Branch
 * protection remains genuinely open, so that half of the caveat stands.
 *
 * CLI: node --experimental-strip-types scripts/release/check-release-freeze.ts
 */

import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";

/**
 * The frozen digests, from docs/build-log/release-go-live/RGL-392.md §2-§3.
 * Changing a value here is amending the freeze and requires a release-authority
 * ruling recorded in that build log — never a quiet edit to make a gate pass.
 *
 * AMENDED 2026-08-25 (first pass), migrationSetSha256 and dbTestSetSha256 only
 * (lockfile untouched). Ruling: docs/build-log/release-go-live/RGL-BLK-002-OPTION2-REMEDIATION.md.
 * Direct, explicit operator authority ("benerin pake opsi 2 sampe tuntas dan tidak
 * tersisa tanpa membuat error regression") to fix RGL-BLK-002 (app schema unreachable
 * via PostgREST -- every server-side RPC call in the deployed application failed)
 * before Step 16's own RGL-394/395 formally run. This is not a silent edit to make
 * the gate pass: the prior digests are preserved below as history, the new migration
 * (20260826000000_create_public_api_data_wrappers.sql, 2367 wrapper functions) and
 * its own exhaustive regression test (scripts/db-tests/public-api-wrapper-regression.sql)
 * are both committed and reviewable, and the full 231-file db-test suite plus the
 * full Tier A gate suite were re-run clean against this exact amended state before
 * this file was changed.
 *
 * AMENDED 2026-08-25 (second pass), migrationSetSha256 only. Same ruling
 * document, same operator authority -- this is that authority's own Tier C
 * self-correction, not a new instruction. The first-pass migration, once
 * applied live, was found (by direct live catalog comparison, not a sample) to
 * carry two live-forced defects of its own: 140 of 2367 wrappers hardcoded
 * `security definer` against an `invoker` app.* counterpart (RLS-bypass class,
 * ISS-2026-291), and 2359 of 2367 wrappers carried an unintended anon/
 * authenticated EXECUTE grant from this Supabase project's own platform-level
 * default privileges on schema public, which the migration's `revoke ... from
 * public` cleanup does not reach (ISS-2026-292). Both are fixed, additively,
 * by supabase/migrations/20260826010000_harden_public_api_data_wrappers_tierc_fixes.sql
 * (335 files total) -- the already-applied 20260826000000 file is not edited.
 * Re-verified exhaustively live (both mismatch counts to 0) and via a fresh
 * full local db-test suite run (335 migrations, 231 files, ALL PASSED,
 * including public-api-wrapper-regression.sql's own security-mode and
 * grant-parity assertions) before this digest was changed.
 *
 * AMENDED 2026-08-25 (third pass), migrationSetSha256 and dbTestSetSha256.
 * Ruling: docs/build-log/release-go-live/RGL-394.md (CG-S16-RGL-004, Defect
 * Triage) -- this task's own charter is to fix RGL-BLK-004 directly (`_calc_
 * vendor_kpi_rate_validity`'s days-in-window arithmetic collapsed to an empty
 * series for any sub-24-hour or otherwise day-unaligned window, contradicting
 * its own documented guarantee, and failing db:test for 3 of every 24 hours).
 * Fixed additively by supabase/migrations/20260826020000_harden_vendor_kpi_
 * rate_validity_window_calc.sql (336 files total) -- the already-applied
 * 20260730740000 file is not edited. scripts/db-tests/procurement-vendor-
 * performance.sql gained a new, hardcoded (not now()-relative) regression
 * assertion pinning the exact previously-collapsing window shape, so this
 * class of defect is now caught at every hour, not only inside the historical
 * 01:00-03:59 dead band (232 files total -- no new file, the existing one
 * widened). Re-verified via a fresh full local db-test suite run (336
 * migrations, 231 runner files, ALL PASSED) before this digest was changed,
 * and applied to the live hosted project only after that local run passed.
 *
 * AMENDED 2026-08-25 (fourth pass), dbTestSetSha256 only. Ruling:
 * docs/build-log/release-go-live/RGL-395.md (CG-S16-RGL-005, CI/CD Gate
 * Validation) -- this task's own charter is the CI gate-enforcement gap that
 * produced RGL-BLK-005 (reclassified High at RGL-394): `pg_read_file()` is a
 * Postgres SERVER-side function reading the SERVER's filesystem, but the
 * concurrency-race helper scripts write their output files on the psql
 * CLIENT's filesystem. Locally client and server share a host so this
 * happened to work; in CI Postgres runs as a separate `postgis/postgis:
 * 17-3.4` Docker service container with its own filesystem, so the file
 * genuinely does not exist server-side. Fixed, structurally not
 * coincidentally, in all 6 affected files (advanced-tms-wms-outbound.sql,
 * advanced-tms-wms-packing.sql, advanced-tms-wms-picking.sql,
 * automation-rule-engine.sql, procurement-vendor-contract.sql, public-api-
 * platform.sql) by capturing each race-output file's CONTENT client-side via
 * psql's `` \set var `cat "$RACE_OUT_A" ...` `` backtick-subshell syntax
 * (which inherits psql's own process environment) instead of asking the
 * server to read a client-local path with `pg_read_file()`; bridged into
 * `do $$...$$` blocks via the pre-existing `set_config`/`current_setting`
 * GUC pattern where required. No file added or removed (232 files
 * unchanged); only these 6 files' content changed. Re-verified via a fresh
 * full local db-test suite run (336 migrations, 231 runner files, ALL
 * PASSED) before this digest was changed. See RGL-395.md for the CI-run
 * evidence obtained separately from this local run, per RGL-392's standing
 * constraint that no lane may report a CI gate as passing on the strength of
 * a local run alone.
 *
 * AMENDED 2026-08-25 (fifth pass), migrationSetSha256 and dbTestSetSha256.
 * Ruling: docs/build-log/release-go-live/RGL-404.md §9 (fix pass following an
 * explicit operator instruction, after the RGL-014/CG-S16-RGL-014 Go/No-Go
 * Report reached NO_GO, to fix every blocker fixable with this session's
 * tooling) and docs/build-log/release-go-live/BLOCKER_LEDGER.md's
 * `RGL-BLK-009` entry -- a Critical financial mis-posting defect: the
 * settlement-reversal governed action (`app.request_finance_settlement_
 * reversal`) reversed the AP side of a posted settlement but never posted an
 * offsetting GL correction journal, so the general ledger silently diverged
 * from the subledger on every reversal. Fixed additively by
 * supabase/migrations/20260826030000_harden_finance_settlement_reversal_gl_
 * journal_and_reachability.sql (337 files total) -- the already-applied
 * 20260810700000 and 20260811200000 files are not edited. The same migration
 * also fixes a second, previously undiscovered live defect it uncovered:
 * 20260811200000 (a same-day HDN-374 Tier C fix) recreated this function via
 * `CREATE OR REPLACE FUNCTION` without restating `SECURITY DEFINER`, silently
 * reverting it to the Postgres default (`SECURITY INVOKER`) and breaking
 * reachability for real `authenticated`/`service_role` callers -- undetected
 * until this pass live-queried `pg_proc.prosecdef` directly. Restoring
 * `SECURITY DEFINER` also required a matching fix to the pre-existing
 * `public.*` wrapper (still `SECURITY INVOKER`, matching the function's OLD
 * broken state), caught by this repo's own
 * scripts/db-tests/public-api-wrapper-regression.sql zero-tolerance guard.
 * scripts/db-tests/finance-settlement.sql gained a new regression block
 * asserting EXECUTE reachability, a full settlement-reversal lifecycle, GL/
 * subledger consistency after reversal, and exact line-level correction
 * matching (232 files unchanged -- no new file, the existing one widened);
 * its pre-existing "HDN-374 Tier C regression: locked period" assertion was
 * also widened to accept the more accurate `finance_period_locked` error now
 * correctly raised by the properly-hardened posting path this fix reaches,
 * alongside the original `finance_settlement_reversal_period_not_open`
 * (a second, independent latent defect this pass discovered but did not need
 * to fix: `app.lock_finance_period`-based locks were never reflected by this
 * function's own pre-existing `posting_eligible` check; only the real
 * enforcement path, `app.assert_finance_period_open_for_posting`, catches
 * them, and that path is what this fix's callees now reach). Re-verified via
 * a fresh full local db-test suite run (337 migrations, 232 runner files, ALL
 * PASSED) before this digest was changed, and applied to the live hosted
 * project across three `apply_migration` calls (initial fix, a settlement-
 * date-not-`current_date` correction, and the wrapper security-mode fix)
 * before this local run.
 *
 * AMENDED 2026-08-25 (sixth pass), migrationSetSha256 and dbTestSetSha256.
 * Ruling: docs/build-log/release-go-live/RGL-404.md's historical-issue-backlog
 * remediation section and docs/runtime/KNOWN_ISSUES.md's `ISS-2026-267`/
 * `ISS-2026-072` entries -- following the operator's explicit "seluruh issue
 * ... harus solved semua tanpa terkecuali" instruction (every issue, all
 * severities, resolved without exception) after `RGL-BLK-001` and the three
 * tracked go-live gaps were accepted by operator override. First two items
 * from the resulting ~168-entry open-issue inventory (0 Critical / 16 High /
 * 78 Medium / 74 Low), both High:
 *
 * `ISS-2026-267`/`HDN-BLK-036` (no mutual-exclusion mechanism for the composed
 * in-place restore procedure) -- fixed via a documented, mandatory
 * `pg_try_advisory_lock(872314, 1)`/`pg_advisory_unlock` step added to
 * `docs/runbooks/database-restore.md` §4 item 4 (no new schema object, so
 * nothing is lost when the procedure's own step (a) drops the `app` schema;
 * auto-releases on a crashed/disconnected session, so no stale-lock cleanup
 * logic is needed). New regression file
 * `scripts/db-tests/database-restore-lock.sql` (233 files total: +1) proves
 * genuine mutual exclusion between two real, independent concurrent `psql`
 * processes using this repository's own existing two-process concurrency-race
 * helper (`scripts/db-tests/wms-picking-concurrency-helper.sh`), not a
 * single-session simulation.
 *
 * `ISS-2026-072` (the still-open `app.users.status` half of a two-part
 * finding; the `role_assignments`-cascade half was already fixed at HRT-295,
 * the tenant-membership half at HDN-373/20260810300000) -- fixed additively
 * by supabase/migrations/20260826040000_harden_rbac_evaluator_platform_
 * user_status_check.sql (338 files total: +1) -- the already-applied
 * 20260810300000 file is not edited. One new defense-in-depth branch in
 * `app.evaluate_permission`'s body, placed after the Supreme Admin exception
 * (a Supreme Admin can hold zero `app.users` rows in a tenant they still
 * legitimately act in -- live-verified this placement is correct, not merely
 * argued, via a new regression assertion). No call-site changes anywhere:
 * confirmed a single-signature, never-overloaded function, so all ~1,124
 * transitive callers are syntactically untouched; the real risk this pass had
 * to rule out was behavioral (a false-deny), not textual, ruled out both by a
 * lockout-safety analysis (`app.assign_role` already hard-requires
 * `app.users.status='active'` at grant time, so no legitimate actor's
 * `role_assignments` row can exist while their `app.users.status` is not
 * `'active'` except via exactly the out-of-band drift this fix targets) and
 * empirically (full local `db-tests` suite `ALL PASSED` across all 233 files,
 * every domain's own regression suite included, not merely a dedicated new
 * assertion). `scripts/db-tests/rbac-enforcement.sql` widened, not replaced
 * (233 files unchanged in count from the file above -- content changed only).
 * Re-verified via a fresh full local db-test suite run (338 migrations, 233
 * runner files, ALL PASSED) before this digest was changed, and applied to
 * the live hosted project via `apply_migration` before this local run,
 * live-reconfirmed present via a direct `pg_get_functiondef`/`pg_proc.
 * prosecdef` query against the hosted project afterward.
 *
 * AMENDED 2026-08-25 (seventh pass), migrationSetSha256 and dbTestSetSha256.
 * Ruling: docs/build-log/release-go-live/RGL-404.md's historical-issue-backlog
 * remediation section, item 3: `ISS-2026-257` -- a full database backup
 * (`pg_dump`/`pg_restore`) captured 3 plaintext secret columns verbatim, no
 * encryption-at-rest (`app.integration_connection_credentials.
 * credential_value`, `app.third_party_provider_connections.
 * webhook_secret_value`, `app.webhook_endpoints.secret_value`), contradicting
 * this repository's own documented "references, never values" export
 * discipline. Fixed additively by
 * supabase/migrations/20260826050000_harden_integration_secrets_encryption_
 * at_rest.sql (339 files total) -- no already-applied migration is edited.
 * Mirrors the already-established, already-proven vendor-financial encryption
 * pattern (`pgp_sym_encrypt`/`pgp_sym_decrypt` via `pgcrypto`): a fail-closed
 * GUC-keyed symmetric key shared by all 3 columns, 2 private encrypt/decrypt
 * helpers, and a rename-the-plaintext-column-out-in-one-migration technique
 * (never a second plaintext column, never a backfill-then-drop-later
 * straddle). 6 writer and 11 reader functions across 5 other, already-applied
 * migration files redefined via `CREATE OR REPLACE` on their identical
 * existing signatures -- zero call-site changes anywhere, zero `public.*`
 * wrapper or TypeScript changes needed (confirmed no wrapper exposes any of
 * the 3 raw column names, and the writer RPCs' own one-time-reveal return
 * shapes are unchanged). Self-caught before shipping (the identical class of
 * gap HDN-373's own migration self-caught for
 * `app.has_active_tenant_membership`): this domain's callers are a MIX of
 * `SECURITY DEFINER` and `SECURITY INVOKER` (unlike vendor-financial's
 * uniformly-DEFINER callers), so the private encrypt/decrypt helpers are
 * explicitly granted to `service_role` rather than left ungranted. While
 * verifying, this pass's own schema change (an `ALTER TABLE` row rewrite on
 * `app.webhook_endpoints`) incidentally surfaced a second, independent,
 * already-tracked defect -- `ISS-2026-156` (a webhook-endpoint lookup in
 * `scripts/db-tests/n8n-integration.sql` with no `ORDER BY`/status filter,
 * latent nondeterminism that had previously happened to pick the right row) --
 * fixed in the same pass by filtering on `status = 'active'`, the
 * semantically correct fix matching that test's own intent. Re-verified via a
 * fresh full local db-test suite run (339 migrations, 233 runner files, ALL
 * PASSED) before this digest was changed, and applied to the live hosted
 * project via `apply_migration` (zero existing rows in any of the 3 tables,
 * confirmed live before applying, so the backfill `UPDATE` statements were
 * no-ops), live-reconfirmed via `information_schema.columns` afterward.
 *
 * AMENDED 2026-08-25 (eighth pass), migrationSetSha256 and dbTestSetSha256.
 * Ruling: docs/build-log/release-go-live/RGL-404.md's historical-issue-backlog
 * remediation section, item 5: `ISS-2026-265`/`HDN-BLK-034` -- the composed
 * in-place restore procedure's own `TRUNCATE` step never fires `FOR EACH ROW`
 * triggers at all (standard, documented Postgres behavior, independent of
 * `pg_restore`'s own `--disable-triggers` flag), silently bypassing 9
 * security/integrity row-level triggers with zero row left in
 * `app.audit_logs` documenting the restore happened. Fixed additively by
 * supabase/migrations/20260826060000_harden_database_restore_audit_trail.sql
 * (340 files total) -- closes only the genuinely closable "zero audit trail"
 * half: a new mandatory step (j), `app.record_database_restore_event(...)`,
 * writes one explicit, structured `app.audit_logs` row (`tenant_id = null`,
 * the established platform-level-event convention) recording who ran the
 * restore, its scope, and how many tables were truncated. Does NOT and
 * cannot re-verify any individual table's own security invariant (a legal
 * hold, a posted-journal balance) that the bypassed triggers would have
 * protected -- disclosed inline in the recorded event's own payload and in
 * the runbook, not silently claimed as fully closed; that remaining half
 * needs a structurally different mechanism (a pre-restore manifest to diff
 * against post-restore state), left open. Also ships the function's own
 * `public.*` Option 2 wrapper (security-mode-matched, `SECURITY DEFINER`) --
 * missed in the first draft and caught immediately by this repo's own
 * `scripts/db-tests/public-api-wrapper-regression.sql` zero-tolerance guard
 * before this digest was ever changed, not after. New regression in
 * `scripts/db-tests/database-restore-lock.sql`: a real, persisted
 * `app.audit_logs` row with the exact scope/table-count supplied, plus 3
 * negative-input rejection assertions (233 files unchanged in count -- the
 * existing file widened, no new file). Re-verified via a fresh full local
 * db-test suite run (340 migrations, 233 runner files, ALL PASSED) before
 * this digest was changed, and applied to the live hosted project via
 * `apply_migration` before this local run.
 *
 * AMENDED 2026-08-25 (ninth pass), migrationSetSha256 only (dbTestSetSha256
 * unchanged -- an existing file widened, no file added or removed). Ruling:
 * docs/build-log/release-go-live/RGL-404.md's historical-issue-backlog
 * remediation section, item 6: `ISS-2026-269` -- an auto-generated-employee-
 * number import row has zero duplicate detection against an existing
 * employee sharing the same identity, live-reproduced at `HDN-385` (a fresh
 * re-import of an identical un-keyed row silently creates a second,
 * genuinely duplicate employee -- distinct from, and unfixed by, `HDN-385`'s
 * own `20260817000000` fix, which only catches a collision on an EXPLICIT
 * employee_number). Fixed additively by
 * supabase/migrations/20260826070000_harden_employee_import_duplicate_
 * detection.sql (341 files total) -- `app.commit_employee_import_job`
 * (already `CREATE OR REPLACE`d once at `20260817000000`) redefined again on
 * its identical signature, never editing either already-applied file.
 * Matching heuristic: exact case-insensitive `work_email` match OR exact
 * `full_name` match against any existing tenant employee -- the same
 * definition of "duplicate" `HDN-385`'s own live reproduction used, not an
 * invented fuzzier heuristic (Levenshtein/phonetic matching), which this
 * finding's own text explicitly flagged as needing further HR-domain design
 * input beyond a bounded fix. Deliberately a review flag into the
 * already-established `app.employee_duplicate_candidates` mechanism, never a
 * hard block -- the import still succeeds. Deliberately NOT routed through
 * the existing `app.flag_employee_duplicate_candidate` RPC, which re-checks
 * `HRS:Edit` authority independent of the `HRS:Import` authority the commit
 * function already verified once -- composing it would have silently
 * required every importer to also hold `HRS:Edit`, a real authority
 * regression this fix avoids by inserting directly into the review table
 * from within the already-authority-checked commit function. New regression
 * in `scripts/db-tests/hris-employee-master.sql`: a genuine re-import
 * reproduces `HDN-385`'s own scenario and is now flagged (import still
 * succeeds); a genuinely distinct new employee (no shared `work_email`/
 * `full_name`) is confirmed NOT flagged, proving this is a real match, not
 * an unconditional flag-everything rule. Re-verified via a fresh full local
 * db-test suite run (341 migrations, 233 runner files, ALL PASSED) before
 * this digest was changed (the first attempt surfaced a `min(uuid)` bug in
 * this pass's own new test, fixed before the digest was touched), and
 * applied to the live hosted project via `apply_migration` before this local
 * run (zero existing rows in `app.employees`/`app.import_staging_rows`,
 * confirmed live before applying).
 *
 * AMENDED 2026-08-25 (tenth pass), migrationSetSha256 and dbTestSetSha256.
 * Ruling: docs/build-log/release-go-live/RGL-404.md's historical-issue-
 * backlog remediation section, item 7: `ISS-2026-254` (partial, disclosed as
 * voluntary) plus two self-caught security regressions in this same
 * checkpoint's own prior work, registered as `ISS-2026-298` and
 * `ISS-2026-299`. Three migrations added (344 files total):
 * `20260826080000_harden_restore_security_state_reconciliation.sql` creates
 * `app.capture_security_state_snapshot`/`app.detect_reverted_security_state`
 * plus `public.security_state_snapshots` and their matching Option 2
 * wrappers -- a voluntary pre/post-restore compensating control for
 * `ISS-2026-254`, explicitly disclosed as not closing the "snapshot never
 * taken" case (no mechanism forces the snapshot step, since the actual
 * restore procedure runs entirely outside any RPC this schema controls).
 * `20260826081000_harden_record_database_restore_event_wrapper_grant_leak.sql`
 * is a repository-side record of a fix already applied live via a direct
 * `apply_migration` call, before this file was written: the prior
 * `20260826060000` migration's own `public.record_database_restore_event`
 * wrapper had used a bare `revoke ... from public`, missing the amended,
 * explicitly-named-roles form (`revoke ... from anon, authenticated,
 * service_role, public`) the `20260826010000` Tier C fix's own convention
 * requires -- live-confirmed exploitable (`anon`/`authenticated` could call
 * this `SECURITY DEFINER` audit-writing function directly) before the fix,
 * live-reconfirmed closed after. `20260826090000_harden_security_state_
 * snapshots_table_privilege_leak.sql` is a second, worse self-caught
 * regression, found while live-verifying `20260826080000`'s own security
 * posture: `public.security_state_snapshots` is the first table this
 * repository has ever created directly in `public` schema, and it shipped
 * without RLS or a revoke of Supabase's own default table-privilege
 * bootstrap -- live-confirmed `anon`/`authenticated` held direct
 * SELECT/INSERT on it (the identical bootstrap-grant class `ISS-2026-298`
 * found for functions, reproduced here for a table), fixed live via a
 * direct `apply_migration` call before this file was written, applying this
 * repository's own standard `app.*`-table security pattern (RLS enabled,
 * fail-closed with zero policies; `anon`/`authenticated` explicitly
 * revoked). Neither `20260826060000` nor `20260826080000` is edited, per
 * this repository's own "never edit an applied migration" rule.
 * dbTestSetSha256 changed (an existing file widened, no file added or
 * removed): `scripts/db-tests/database-restore-lock.sql` gained 2 new
 * regression blocks -- one proving `capture_security_state_snapshot`
 * correctly captures an active legal hold/revoked API key/disabled webhook
 * endpoint/suspended user/suspended membership, that
 * `detect_reverted_security_state` correctly reports all 5 by category
 * after each is directly reverted under `session_replication_role =
 * replica` (matching pg_restore --disable-triggers, since app.principal_
 * memberships' own transition-enforcement trigger would otherwise reject a
 * raw revoked-to-active UPDATE a real restore's data load never routes
 * through triggers to begin with), that a same-point-in-time snapshot
 * reports nothing, and that an unknown snapshot id is rejected; a second
 * proving `public.security_state_snapshots` carries RLS enabled and zero
 * anon/authenticated table privilege. Re-verified via a fresh full local
 * db-test suite run (344 migrations, 233 runner files, ALL PASSED) before
 * this digest was changed (earlier attempts surfaced and fixed, before the
 * digest was touched: a stale `secret_value` column reference this new
 * test's own webhook_endpoints insert had missed after `ISS-2026-257`'s
 * rename to `secret_value_encrypted`; a missing `app.integration_secrets_
 * encryption_key` test GUC this file had never needed before; and the
 * principal_memberships transition-trigger rejection above). All 3
 * migrations' live security posture was independently verified after
 * applying (`has_function_privilege` for the 3 function wrappers,
 * `has_table_privilege`/`pg_class.relrowsecurity` for the table) before
 * this digest was changed -- the mitigation practice `ISS-2026-298`
 * established, now applied to both functions and tables.
 *
 * AMENDED 2026-08-25 (eleventh pass), migrationSetSha256 and dbTestSetSha256.
 * Ruling: docs/build-log/release-go-live/RGL-404.md's historical-issue-
 * backlog remediation section, item 8: `ISS-2026-263` --
 * `app.transition_user_status`'s own `event_type` `CASE` mapping had an
 * `else` fallback assigning the raw target-status value (e.g. `'suspended'`)
 * as the history `event_type`, instead of a verb-form value
 * `app.user_lifecycle_history_event_type_check` actually accepts -- any
 * transition outside 5 explicit pairs, including a true no-op, deterministically
 * failed with a spurious `CHECK`-constraint violation rather than a clear
 * error. One migration added (345 files: +1,
 * `20260826100000_harden_user_status_transition_invalid_event_type.sql`) --
 * `CREATE OR REPLACE` on the identical existing signature, changing the
 * `else` branch to `null` and adding an explicit `invalid_status_transition`
 * rejection before the history insert, mirroring this repository's own
 * established convention for this exact error shape (see
 * `advanced-tms-label-barcode-operations.sql`'s own `invalid_status_transition`
 * regression). No new `public.*` object created (function body only, grant
 * set untouched), so the `ISS-2026-298`/`ISS-2026-299` live-verification
 * mitigation does not apply here; `pg_get_functiondef` re-confirmed the live
 * fix took effect instead, the same pattern used for `ISS-2026-072`.
 * dbTestSetSha256 changed (an existing file widened, no file added or
 * removed): `scripts/db-tests/user-lifecycle.sql` gained a new regression
 * block proving all 5 real transitions still succeed with the correct
 * `event_type` (including a full round-trip through every history row), and
 * that 3 no-op/unrecognized calls (`invited->invited`, `active->active`,
 * `suspended->suspended` -- the exact scenario `HDN-384` originally
 * reproduced) are now rejected with the new, clear error. Re-verified via a
 * fresh full local db-test suite run (345 migrations, 233 runner files, ALL
 * PASSED, first attempt clean) before this digest was changed, and applied
 * to the live hosted project via `apply_migration` before this local run.
 *
 * AMENDED 2026-08-25 (twelfth pass), migrationSetSha256 and dbTestSetSha256.
 * Ruling: docs/build-log/release-go-live/RGL-404.md's historical-issue-
 * backlog remediation section, item 9: `ISS-2026-264` --
 * `app.revoke_all_actor_sessions`'s own session-status flip in
 * `app.user_sessions` was never consulted by any RLS policy, RPC, or
 * `app.evaluate_permission`, so session revocation had zero real enforcement
 * effect anywhere. Root-caused further during this fix:
 * `app.register_user_session` (the only function that ever creates an
 * `app.user_sessions` row) was never called from anywhere in the real
 * application either -- not even the real sign-in path
 * (`app/(public)/login/actions.ts`) -- so a database-only fix would have
 * been a structural no-op in production. One migration added (346 files:
 * +1, `20260826110000_harden_evaluate_permission_session_revocation_
 * enforcement.sql`) -- `CREATE OR REPLACE` on the identical existing
 * signature, adding one new, deliberately narrow check: deny only when an
 * actor has at least one tracked session for the tenant AND every one of
 * them is revoked, never when zero sessions are tracked (so no login
 * predating this fix, and no future login path that never registers a
 * session, is ever universally denied). Paired with an application-code
 * change (`lib/auth/register-login-session.ts`, wired into the sign-in
 * Server Action) that makes session registration actually happen on every
 * real tenant-scoped sign-in going forward -- without it, the new database
 * check alone could never fire against real traffic. No new `public.*`
 * object created (function body only, grant set untouched), so the
 * `ISS-2026-298`/`ISS-2026-299` live-verification mitigation does not apply
 * here; `pg_get_functiondef` re-confirmed the live fix took effect instead,
 * the same pattern used for `ISS-2026-072`/`ISS-2026-263`.
 * dbTestSetSha256 changed (an existing file widened, no file added or
 * removed): `scripts/db-tests/rbac-enforcement.sql` gained a new regression
 * block proving an untracked actor is completely unaffected, an actor with
 * an active tracked session remains allowed, an actor whose every tracked
 * session is revoked (via a real `app.revoke_all_actor_sessions` call) is
 * denied `all_sessions_revoked`, a fresh session immediately restores
 * authority, and Supreme Admin remains unaffected. Re-verified via a fresh
 * full local db-test suite run (346 migrations, 233 runner files, ALL
 * PASSED, first attempt clean once the local disposable Postgres cluster --
 * found stopped, unrelated to this change -- was restarted) before this
 * digest was changed, and applied to the live hosted project via
 * `apply_migration` before this local run.
 *
 * AMENDED 2026-08-25 (thirteenth pass), migrationSetSha256 and
 * dbTestSetSha256. Ruling: docs/build-log/release-go-live/RGL-404.md's
 * historical-issue-backlog remediation section, item 10: `ISS-2026-266` --
 * the composed in-place restore procedure's own required step (h) was a
 * raw, per-view-name `REFRESH MATERIALIZED VIEW CONCURRENTLY` an operator
 * had to remember to repeat for every registered view, bypassing this
 * repository's own already-existing governed refresh mechanism
 * (`app.refresh_analytics_view`, IAE-005) entirely -- this entry's own text
 * named exactly this gap ("a more permanent fix... rather than a manual
 * runbook step") as its remaining owner item. One migration added (347
 * files: +1, `20260826120000_harden_restore_materialized_view_refresh_
 * completeness.sql`) -- `app.refresh_all_registered_analytics_views(p_actor_
 * auth_user_id, p_actor_label)` delegates to the existing
 * `app.refresh_analytics_view` for every `active` row in
 * `app.analytics_view_registry`, inheriting its authority check (Supreme
 * Admin only) and `app.analytics_refresh_runs` ledger entry per view, and
 * automatically covering any view registered after this function shipped.
 * Ships with a matching Option 2 `public.*` wrapper, correctly using the
 * amended `revoke ... from anon, authenticated, service_role, public`
 * form from first principles (not discovered as a live bug this time) --
 * live-verified via `has_function_privilege` immediately after applying,
 * per the `ISS-2026-298` mitigation practice: `anon` denied,
 * `authenticated`/`service_role` allowed, matching
 * `app.refresh_analytics_view`'s own existing grant set exactly.
 * `docs/runbooks/database-restore.md`'s own step (h) instruction updated to
 * call this function instead of the raw per-view SQL. dbTestSetSha256
 * changed (an existing file widened, no file added or removed):
 * `scripts/db-tests/analytics-materialized-views.sql` gained a new
 * regression block proving the new function is Supreme-only, refreshes
 * every active registered view (including surfacing a real per-view
 * `'failed'` run for a view whose underlying materialized view no longer
 * exists, without aborting the batch), and produces the identical
 * persisted ledger rows an individual `app.refresh_analytics_view` call
 * would. Re-verified via a fresh full local db-test suite run (347
 * migrations, 233 runner files, ALL PASSED, first attempt clean) before
 * this digest was changed, and applied to the live hosted project via
 * `apply_migration` before this local run.
 *
 * AMENDED 2026-08-25 (fourteenth pass), migrationSetSha256 and
 * dbTestSetSha256. Ruling: docs/build-log/release-go-live/RGL-404.md's
 * historical-issue-backlog remediation section, item 11: `ISS-2026-270` --
 * no safe import/registration path existed for migration-seeded reference
 * tables (`app.finance_currencies`, `app.uoms`): a raw insert collision
 * raised an unclassified duplicate-key error, and a multi-row batch insert
 * with one colliding row rolled back the entire batch, including
 * genuinely-new rows in the same statement. Confirmed live: zero writer
 * RPCs existed anywhere for either table before this fix. One migration
 * added (348 files: +1, `20260826130000_create_reference_data_import_
 * registration.sql`) -- `app.import_reference_currency`/
 * `app.import_reference_uom`, mirroring this repository's own established
 * "return the existing row if found" idempotent-registration pattern
 * (`app.invite_user`, `app.provision_tenant`) rather than the entry's own
 * cited `INSERT ... ON CONFLICT DO NOTHING`, which would silently accept a
 * same-code row with different values. Supreme Admin only, matching
 * `app.register_analytics_view`'s own convention for the other
 * platform-wide registry this codebase has. Ships with matching Option 2
 * `public.*` wrappers, correctly using the amended revoke form from first
 * principles; live-verified via `has_function_privilege` immediately after
 * applying: `anon`/`authenticated` denied, `service_role` allowed, for
 * both. dbTestSetSha256 changed (one NEW file added, 233 -> 234): new
 * `scripts/db-tests/reference-data-import.sql` proves both functions are
 * Supreme-only, idempotently return the existing row on a collision
 * (the exact scenario this entry live-reproduced), a genuinely-new code
 * inserts cleanly and survives being called alongside a colliding sibling
 * (proving no multi-row-batch-style rollback), the underlying table's own
 * CHECK constraint still rejects invalid input, and a real audit event
 * records each genuinely-new import. Re-verified via a fresh full local
 * db-test suite run (348 migrations, 234 runner files, ALL PASSED, first
 * attempt clean once the local disposable Postgres cluster -- found
 * stopped again, unrelated to this change -- was restarted) before this
 * digest was changed, and applied to the live hosted project via
 * `apply_migration` before this local run.
 *
 * AMENDED 2026-08-25 (fifteenth pass), migrationSetSha256 and
 * dbTestSetSha256. Ruling: docs/build-log/release-go-live/RGL-404.md's
 * historical-issue-backlog remediation section, item 12: `ISS-2026-272` --
 * no mechanism tracked "migration rehearsals completed" for enterprise
 * tenants, the identical structural pattern already found for DR
 * communication (`ISS-2026-258`) and `app.dr_restore_tests`' own
 * `component_scope` enum (`ISS-2026-260`). One migration added (349 files:
 * +1, `20260826140000_create_migration_rehearsal_tracking.sql`) -- a real
 * evidence table (`app.migration_rehearsal_tests`) and recording RPC
 * (`app.record_migration_rehearsal_test`) mirroring `app.dr_restore_tests`/
 * `app.record_dr_restore_test`'s own honesty discipline verbatim, plus a
 * 7th checklist item (`migration_rehearsal_verified`) on
 * `app.verify_onboarding_checklist_item` (`CREATE OR REPLACE` on the
 * identical existing signature, diffed against the prior definition to
 * confirm the only changes are the widened item allow-list, the new
 * computation branch, and the 2 new `UPDATE ... SET` columns). Confirmed
 * with the operator via `AskUserQuestion` before implementing: the
 * business rule this traces to is "at least two rehearsals **where
 * contracted**", and no "is migration rehearsal contracted" flag exists
 * anywhere in this schema -- so the new item is deliberately NOT added to
 * the existing `status='ready_for_production'` composite gate the other 6
 * items form (confirmed unchanged by direct diff), which would otherwise
 * have newly required every tenant, contracted or not, to complete 2
 * rehearsals to reach that status -- a real behavior change to existing
 * tenant onboarding gating this fix deliberately avoids. Ships with a
 * matching Option 2 `public.*` wrapper for the new RPC (the existing
 * `verify_onboarding_checklist_item` wrapper needs no change, same
 * signature); live-verified via `has_function_privilege` immediately after
 * applying: `anon` denied, `authenticated`/`service_role` allowed,
 * matching `app.record_dr_restore_test`'s own grant set; `pg_get_
 * functiondef` re-confirmed the `verify_onboarding_checklist_item` fix
 * took effect. dbTestSetSha256 changed (an existing file widened, no file
 * added or removed): `scripts/db-tests/disaster-recovery-enterprise-
 * support.sql` gained a new regression block proving the new RPC is
 * `SUP:Configure`-gated with real failure-evidence discipline mirroring
 * `app.record_dr_restore_test`, `migration_rehearsal_verified` correctly
 * requires >=2 passed rehearsals and recomputes live, and -- the central
 * point of this fix -- flipping it from `false` to `true` never changes
 * `status`, proving directly (not merely asserting) that it is not part of
 * the `ready_for_production` gate; the file's own pre-existing anon-grant
 * defense-in-depth check was widened to cover the new function too.
 * Re-verified via a fresh full local db-test suite run (349 migrations,
 * 234 runner files, ALL PASSED, first attempt clean) before this digest
 * was changed, and applied to the live hosted project via `apply_migration`
 * before this local run.
 *
 * AMENDED 2026-08-25 (sixteenth pass), migrationSetSha256 and
 * dbTestSetSha256. Ruling: docs/build-log/release-go-live/RGL-404.md's
 * historical-issue-backlog remediation section, item 13: `ISS-2026-271` --
 * no `rollback_import_job`/`undo_import_job`/`revert_import_job` RPC
 * existed anywhere; a manual, FK-ordered raw-SQL delete live-proved to work
 * but left 2 residues (a dangling `app.audit_logs` reference to a deleted
 * job row; an untouched employee-number counter) and left the entry's own
 * flagged downstream-reference risk unexercised. One migration added (350
 * files: +1, `20260826150000_create_employee_import_rollback.sql`) --
 * `app.rollback_employee_import_job`, deliberately shaped differently from
 * the manual drill in exactly the ways that close both residues: the job
 * row is never deleted (status moves to a new `'rolled_back'` value,
 * `jobs_status_check` widened, confirmed via direct `grep` that no other
 * migration had ever touched that constraint before this one), so every
 * existing `audit_logs` reference to it stays resolvable, and the rollback
 * itself is captured as one new audit event; `app.employee_number_counters`
 * is deliberately left untouched, per that table's own already-documented
 * "Never reused" design intent (decrementing it would risk a future import
 * reusing a number a different, concurrent import already consumed). The
 * downstream-reference risk is handled by Postgres's own default
 * (`RESTRICT`) foreign-key behavior on every `app.employees` reference in
 * this schema (confirmed by direct migration read -- no `ON DELETE CASCADE`
 * exists anywhere), caught as `foreign_key_violation` and re-raised as a
 * clear, named error -- correct and complete by construction against the
 * database's own authoritative FK catalog, not a hand-maintained table
 * list that could drift. The set of records a job created is resolved via
 * `app.employee_lifecycle_events.metadata->>'job_id'`, the exact linkage
 * `app.commit_employee_import_job`'s own creation-event insert already
 * writes -- not a new mechanism invented for this fix. Ships with a
 * matching Option 2 `public.*` wrapper, correctly using the amended revoke
 * form from first principles; live-verified via `has_function_privilege`
 * immediately after applying: `anon` denied, `authenticated`/`service_role`
 * allowed. dbTestSetSha256 changed (an existing file widened, no file
 * added or removed): `scripts/db-tests/hris-employee-master.sql` gained a
 * new regression block proving the RPC is `HRS:Import`-gated, refuses a
 * non-completed job/blank reason/second rollback attempt, and -- the
 * central point of this fix -- refuses atomically (never partially,
 * confirmed by checking both fixture employees survive intact) when a
 * real downstream reference exists (a minimal `app.employee_duplicate_
 * candidates` row referencing one of the job's own created employees),
 * then succeeds cleanly once that reference is cleared, leaving the job
 * row (`status='rolled_back'`) and the employee-number counter completely
 * untouched with a real audit event recorded. Re-verified via a fresh full
 * local db-test suite run (350 migrations, 234 runner files, ALL PASSED,
 * first attempt clean once the local disposable Postgres cluster -- found
 * stopped again, unrelated to this change -- was restarted) before this
 * digest was changed, and applied to the live hosted project via
 * `apply_migration` before this local run.
 *
 * AMENDED 2026-08-27 (seventeenth pass), migrationSetSha256 and
 * dbTestSetSha256. Ruling: docs/build-log/release-go-live/RGL-404.md's
 * historical-issue-backlog remediation section, item 14: `ISS-2026-275`/
 * `ISS-2026-276` -- `app.finance_journals_protect_posted` never fires on
 * `INSERT` (only `UPDATE`/`DELETE`), so a direct bulk insert of an
 * already-posted journal was neither blocked by that trigger nor checked
 * for a balanced debit=credit total (`app.validate_finance_journal_line_
 * balance` is only ever invoked from inside the RPC functions, never at
 * the table layer), and no legitimate `source_type` existed to record its
 * true provenance -- `'migration'` did not exist in `app.finance_journals`'
 * own `source_type` vocabulary, the identical root gap `ISS-2026-276`
 * registered separately. Confirmed with the operator (AskUserQuestion)
 * before implementing that widening the existing `UPDATE`/`DELETE`
 * immutability trigger to also guard `INSERT` was the wrong fix (it would
 * make it impossible to ever load real historical already-posted data, since
 * the trigger has no way to distinguish a legitimate migration insert from
 * an illegitimate one) -- a dedicated migration-insert RPC replicating the
 * RPC-layer validation is correct instead. One migration added (351 files:
 * +1, `20260826160000_create_finance_journal_historical_import.sql`) --
 * `app.import_historical_finance_journal`, modeled directly on the existing
 * `app.create_and_post_finance_system_journal` (posts immediately, skipping
 * draft/submitted/approved) but differing in exactly the ways that close
 * both entries' own gaps: it requires real `FIN:Approve` authority itself
 * (its own template deliberately has none, trusting its caller to have
 * already checked; this new RPC is the directly-called entry point), it
 * re-validates debit=credit balance via the existing shared rule before
 * ever writing a row, and it requires a real non-null `source_id` and a
 * real non-empty reason -- `'migration'` is added to both
 * `finance_journals_source_type_check` and `finance_journals_source_check`
 * (preserving the existing `'correction'` source type, FIN-206's own
 * retrofit, byte-for-byte -- an additive replacement, confirmed by direct
 * read of the currently-applied constraint text before writing the new
 * one, never a narrowing). Matches the finance domain's own current
 * security posture: `security definer` with the established `search_path
 * to 'app', 'pg_temp'` clause (confirmed by direct read that
 * `20260810700000_harden_finance_authority_chain_security_definer.sql`
 * converted the whole domain, including this fix's own direct template,
 * from its original security-invoker shape -- matching that, not the
 * template's now-superseded original definition, is correct). The one real
 * design decision this fix makes, confirmed with the operator before
 * implementing: unlike the live system-journal path, this RPC does NOT
 * require the resolved fiscal period to be `posting_eligible` (open) -- a
 * real historical migration by definition targets periods that are already
 * closed today; requiring an open period would make this fix useless for
 * its own stated purpose. A period covering the date must still exist
 * (`app.resolve_finance_period_for_date` returns zero rows otherwise,
 * raised as a clear error) -- this only relaxes the open/closed check,
 * never the date-to-period resolution itself. Idempotent on `(tenant_id,
 * source_type='migration', source_id)`, mirroring the template's own
 * idempotency shape. Ships with a matching Option 2 `public.*` wrapper,
 * correctly using the amended revoke form from first principles;
 * live-verified via `has_function_privilege` immediately after applying:
 * `anon` denied, `authenticated`/`service_role` allowed. dbTestSetSha256
 * changed (an existing file widened, no file added or removed):
 * `scripts/db-tests/finance-journal.sql` gained a new regression block
 * proving a non-`FIN:Approve` actor is denied, a null `source_id` and a
 * blank reason are each rejected with a distinct named exception, an
 * unbalanced line set is rejected by the shared balance rule, a real
 * balanced journal dated inside an already-CLOSED historical fiscal period
 * (a brand-new, isolated calendar generated and then directly closed via
 * raw SQL, never disturbing the file's own shared open `2026-03` period)
 * still posts successfully -- the central point of this fix -- a repeated
 * call with the same `source_id` returns the existing journal idempotently,
 * a real audit event is recorded, and (defense in depth) the underlying
 * `finance_journals_source_check` constraint independently rejects a
 * sourceless `'migration'` row at the table layer, plus a schema-privilege
 * defense-in-depth block proving `anon` holds zero EXECUTE on the new
 * function. Re-verified via a fresh full local db-test suite run (351
 * migrations, 234 runner files, ALL PASSED, clean after four authoring
 * mistakes were caught and fixed across successive local runs -- an
 * insufficient-lines vs. unbalanced mismatch in the negative test, the
 * historical journal date not falling inside the single generated period, a
 * mis-declared composite-typed account-id variable, the wrong
 * `app.audit_logs` column names, and (caught by
 * `public-api-wrapper-regression.sql`'s own exhaustive check) the new
 * `public.*` wrapper's security mode not matching its `app.*` counterpart
 * -- and the local disposable Postgres cluster found stopped again,
 * unrelated to this change, was restarted twice during authoring) before
 * this digest was changed, and applied to the live hosted project via
 * `apply_migration` before this local run.
 *
 * AMENDED 2026-08-27 (eighteenth pass), migrationSetSha256 and
 * dbTestSetSha256. Ruling: docs/build-log/release-go-live/RGL-404.md's
 * historical-issue-backlog remediation section, item 15: `ISS-2026-279` --
 * `app.employee_number` uniqueness on an explicit staged value is
 * case/whitespace-sensitive (`master_records_tenant_code_unique` is a
 * plain case-sensitive `btree` unique index, no `lower()`/`trim()`
 * normalization), letting `EMP-001`, `emp-001`, and `EMP-001 ` (trailing
 * space) all commit as 3 distinct employees in one job. This entry's own
 * text names the fix as a genuine design decision left open between a
 * hard functional unique index and a soft validation-time/commit-time
 * flag, "best made alongside `ISS-2026-269`'s own broader un-keyed-
 * duplicate-detection fix" (already resolved, an earlier item in this
 * same running log). A hard functional unique index was deliberately NOT
 * chosen -- `app.master_records` is shared across every
 * `master_type_code`, and a live hosted project may already carry real
 * case-varying rows that predate this fix, so a retroactive hard
 * constraint risks failing migration application outright or silently
 * rejecting a legitimate future record with no human review. Widened
 * `app.commit_employee_import_job` a third time (351 -> 352 files: +1,
 * `20260826170000_harden_employee_import_number_normalization_detection.sql`)
 * with the symmetric, already-shipped-and-approved answer `ISS-2026-269`
 * established for the identical risk class on this same function: an
 * explicitly-numbered row whose `employee_number` normalizes (`lower` +
 * `trim`) to an existing employee's own number, without being byte-
 * identical (an exact match already raises `employee_import_duplicate_
 * employee_number` via the unique index, unchanged), is flagged into the
 * existing `app.employee_duplicate_candidates` table for human review --
 * never a hard block, mirroring `ISS-2026-269`'s own disclosed rationale
 * that a trivial keystroke variation must not itself become a false-
 * positive import failure. `CREATE OR REPLACE` diffed against the
 * currently-applied function body before writing the new one, confirming
 * only the new `else` branch (paired with the existing `if
 * v_was_auto_numbered`) and the updated comment changed -- nothing else
 * drifted. dbTestSetSha256 changed (an existing file widened, no file
 * added or removed): `scripts/db-tests/hris-employee-master.sql` gained a
 * new regression block proving the exact 3-variant scenario this entry's
 * own live reproduction named (`EMP-CASE-001`/`emp-case-001`/`'EMP-CASE-001 '`)
 * all still commit successfully and are flagged pairwise for human
 * review, and that a genuinely unrelated explicit `employee_number` is
 * never flagged. Re-verified via a fresh full local db-test suite run
 * (352 migrations, 234 runner files, ALL PASSED, clean on the first
 * attempt) before this digest was changed, and applied to the live hosted
 * project via `apply_migration` before this local run.
 *
 * AMENDED 2026-08-27 (nineteenth pass), migrationSetSha256 and
 * dbTestSetSha256. Ruling: docs/build-log/release-go-live/RGL-404.md's
 * historical-issue-backlog remediation section, item 16: `ISS-2026-260` --
 * `app.dr_restore_tests.component_scope` (IAE-035) is CHECK-constrained to
 * a component/mechanism taxonomy (`database`, `secrets`, `backup`,
 * `observability`, `jobs_integrations`), not the 4 DR scenarios (data
 * corruption, security incident, provider failure, major outage) Prompt
 * 384's own DR rehearsal charter names -- 3 of the 4 scenarios have no
 * natural component slot. Confirmed with the operator (`AskUserQuestion`)
 * before implementing: add a NEW, parallel, nullable `dr_scenario` column
 * alongside the existing `component_scope`, rather than widening
 * `component_scope`'s own CHECK constraint to also accept scenario
 * values -- mixing a mechanism taxonomy and a scenario taxonomy into one
 * enum would make every future query against `component_scope`
 * ambiguous about which taxonomy a given row's value belongs to. One
 * migration added (352 -> 353 files: +1,
 * `20260826180000_create_dr_restore_scenario_taxonomy.sql`) adding the
 * column plus its own CHECK constraint, and widening
 * `app.record_dr_restore_test` (and its matching Option 2 `public.*`
 * wrapper) with one new, trailing, DEFAULT-valued `p_dr_scenario`
 * parameter. **A real defect self-caught and fixed during this same
 * migration's authoring**: `CREATE OR REPLACE FUNCTION` cannot be used to
 * append a new parameter to an existing function -- Postgres identifies a
 * function by its name PLUS its full parameter type list, so appending
 * one (even with a default) creates a SECOND, DISTINCT overload alongside
 * the original rather than truly replacing it, making every pre-existing
 * call site genuinely ambiguous (`function ... is not unique`) --
 * verified directly against a real disposable Postgres instance before
 * settling on the fix. Corrected by explicitly `DROP FUNCTION`-ing the
 * original 13-argument signature (both `app.*` and `public.*`) before
 * creating the new 14-argument one, confirmed by direct read to be the
 * exact, already-established convention this repository's own FIN-206
 * migration used for the identical `p_lock_scope` append onto `app.
 * create_and_post_finance_system_journal` (a `drop function if exists`
 * line was already present there) -- not a new pattern invented for this
 * fix, and not a live defect in that earlier migration either, once
 * actually read in full. dbTestSetSha256 changed (an existing file
 * widened, no file added or removed):
 * `scripts/db-tests/disaster-recovery-enterprise-support.sql` gained a
 * new regression block proving all 4 named scenarios can now be recorded
 * alongside `component_scope`, an invalid scenario is rejected at both
 * the RPC and table-CHECK-constraint layer, and every pre-existing
 * 13-argument call site keeps working completely unchanged. Re-verified
 * via a fresh full local db-test suite run (353 migrations, 234 runner
 * files, ALL PASSED, clean after the ambiguous-overload defect above was
 * caught and fixed by this same local run) before this digest was
 * changed, and applied to the live hosted project via `apply_migration`
 * before this local run.
 *
 * AMENDED 2026-08-27 (twentieth pass), migrationSetSha256 only
 * (dbTestSetSha256 also changed -- see below, listed separately per this
 * digest's own established convention when the two land in the same
 * pass). Ruling: docs/build-log/release-go-live/RGL-404.md's
 * historical-issue-backlog remediation section, item 18: `ISS-2026-278`
 * -- no MFA/step-up/elevated-authorization gate existed on any
 * import-commit RPC (`app.commit_import_job` and every domain adapter's
 * own `app.commit_*_import_job`), unlike the 4 "platform-default
 * high-risk target functions" HDN-378/ISS-2026-150 already hardened with
 * an IP-allowlist + MFA-step-up composition. Confirmed with the operator
 * (`AskUserQuestion`) before implementing: IP-allowlist gating only, no
 * mandatory MFA step-up, scoped to the 5 real `commit_*_import_job`
 * functions -- this entry's own text already flags the real risk of
 * forcing step-up on every bulk import commit, including routine,
 * non-financial ones (e.g. `attendance_device_import`), without a
 * dedicated UX review this checkpoint has no standing to perform. One
 * migration added (353 -> 354 files: +1,
 * `20260826190000_harden_import_commit_ip_allowlist_gating.sql`) widening
 * `app.commit_import_job`, `app.commit_employee_import_job`, `app.
 * commit_attendance_device_import_job`, `app.commit_timesheet_import_job`,
 * and `app.commit_vendor_rate_import_job` (plus each one's own Option 2
 * `public.*` wrapper) with one new, trailing, DEFAULT-valued
 * `p_client_ip` parameter each -- the identical composition and
 * non-interactive-caller exemption (`app.assert_ip_allowed` +
 * `app.has_active_ip_allowlist_bypass`) HDN-378's own 4 functions already
 * established. Every one of the 10 functions (5 `app.*` + 5 `public.*`)
 * widened via an explicit `DROP FUNCTION` (old signature) + `CREATE
 * FUNCTION` (new signature), never a bare `CREATE OR REPLACE` across a
 * changed argument list -- `ISS-2026-260`'s own self-caught
 * ambiguous-overload finding applied correctly from the first draft this
 * time, not rediscovered. Each widened function's body diffed against its
 * currently-applied definition before writing the new one, confirming
 * only the intended trailing parameter and IP-check block (placed
 * immediately after the function's own last authority check, before its
 * first business-state validation -- the identical "after authority is
 * otherwise established, before the mutating action" ordering discipline
 * HDN-378 used) changed in each case. dbTestSetSha256 changed (5 existing
 * files widened, no file added or removed):
 * `scripts/db-tests/import-export.sql` gained a full 4-scenario
 * regression block for `app.commit_import_job` (out-of-range IP denied
 * under enforced mode, in-range IP allowed, omitted IP allowed regardless
 * of enforcement, active bypass grant exempts an out-of-range IP);
 * `scripts/db-tests/hris-employee-master.sql`,
 * `scripts/db-tests/hris-attendance.sql`,
 * `scripts/db-tests/hris-overtime-timesheet.sql`, and
 * `scripts/db-tests/procurement-vendor-rate-tiers.sql` each gained a
 * lighter 3-scenario proof (deny/allow-in-range/allow-omitted) for their
 * own domain adapter, confirming the composition is correctly wired in
 * every one of the 5 functions, not only the generic framework one.
 * Re-verified via a fresh full local db-test suite run (354 migrations,
 * 234 runner files, ALL PASSED, clean on the first attempt for both the
 * migration and every one of the 5 new regression blocks) before this
 * digest was changed, and applied to the live hosted project via
 * `apply_migration` before this local run.
 *
 * AMENDED 2026-08-27 (twenty-first pass), migrationSetSha256 and
 * dbTestSetSha256. Ruling: docs/build-log/release-go-live/RGL-404.md §12,
 * items 22-26 (Track B, Batch 1 of the operator-directed full-backlog
 * remediation). Three migrations added (354 -> 357 files: +3):
 * `20260827000000_wire_observability_alert_producers.sql` (closes part of
 * ISS-2026-249: `app.record_webhook_delivery_attempt`,
 * `app.record_integration_health_check`, and
 * `app.record_ai_governed_request_outcome` now each call
 * `app.raise_observability_alert` on their own terminal-failure branch,
 * so a dead-lettered webhook, an auto-disabled integration connection,
 * and a failed AI-governed action each produce a real `app.incidents`
 * row instead of a silent gap; a fourth producer,
 * `app.assert_ip_allowed`, was drafted and then withdrawn from this same
 * migration after this batch's own new db-test assertion caught a
 * caught-exception implicit-savepoint rollback that would have
 * discarded the function's own alert insert whenever its caller wraps
 * the call in `BEGIN ... EXCEPTION WHEN ... END` -- documented in
 * `KNOWN_ISSUES.md` under ISS-2026-249 rather than forced through);
 * `20260827010000_harden_cross_tenant_error_disclosure_representative.sql`
 * (closes part of ISS-2026-167: `app.create_quotation_draft` collapses
 * to one generic `opportunity_not_found` error for both a genuinely
 * cross-tenant and a fully nonexistent opportunity id, and
 * `app.revoke_api_key`/`app.rotate_api_key` gained an
 * `app.has_active_tenant_membership` pre-check so a genuine stranger to
 * the key's tenant gets the same generic not-found while a same-tenant
 * actor who merely lacks manage authority still gets their own specific
 * `insufficient_authority` error -- the first-draft version of this fix
 * collapsed both cases unconditionally and broke the legitimate
 * same-tenant case, caught by this batch's own db-tests run and
 * corrected before this digest was changed); and
 * `20260827030000_harden_analytics_refresh_runs_grant.sql` (closes
 * ISS-2026-176: narrows the `authenticated` grant on
 * `app.analytics_refresh_runs` from whole-table `SELECT` to an explicit
 * column list, removing incidental exposure of internal refresh-run
 * detail columns). dbTestSetSha256 changed (234 files unchanged in
 * count -- 9 existing files widened, no file added or removed):
 * `scripts/db-tests/webhook-management.sql`,
 * `scripts/db-tests/integration-hub.sql`, and
 * `scripts/db-tests/ai-governance-provider-boundary.sql` each gained a
 * new assertion proving a real `app.incidents` row now exists at their
 * producer's own terminal-failure moment;
 * `scripts/db-tests/commercial-quotation-builder.sql` gained a block
 * proving a cross-tenant and a nonexistent opportunity id raise the
 * byte-identical error shape; `scripts/db-tests/api-key-webhook.sql`
 * gained a block proving cross-tenant `revoke_api_key`/`rotate_api_key`
 * calls never leak the foreign tenant's UUID;
 * `scripts/db-tests/vendor-api.sql` had one pre-existing test corrected
 * to expect the new (correct) `no_data_found`/`api_key_not_found` error
 * for a genuinely cross-tenant caller, replacing its old expectation of
 * `insufficient_privilege`; `scripts/db-tests/rbac-enforcement.sql`
 * gained a regression guard enumerating the 35 `app`-schema views
 * deliberately granted to `authenticated` without `security_invoker`
 * (closes ISS-2026-174/175); and
 * `scripts/db-tests/hris-shift-roster-scheduling.sql` and
 * `scripts/db-tests/analytics-materialized-views.sql` each received a
 * small defensive/doc-correction change carried over from this batch's
 * investigation of ISS-2026-189 and ISS-2026-285 respectively (both
 * dispositioned, not code-fixed, in `KNOWN_ISSUES.md`). Re-verified via
 * a fresh full local db-test suite run (357 migrations, 234 runner
 * files, ALL PASSED) before this digest was changed, and applied to the
 * live hosted project via `apply_migration` immediately after this local
 * run passed.
 *
 * AMENDED 2026-08-27 (twenty-second pass), migrationSetSha256 and
 * dbTestSetSha256. Ruling: docs/build-log/release-go-live/RGL-404.md §12,
 * items 27-31 (Track B, Batch 2 -- `table-only-procurement-hardening`).
 * Two migrations added (357 -> 359 files: +2):
 * `20260827110000_harden_request_approval_unique_violation_handler.sql`
 * (closes ISS-2026-044: `app.request_approval`'s own INSERT is now
 * wrapped in a `unique_violation` handler, returning the winning
 * concurrent caller's own row instead of propagating a raw
 * constraint-violation error -- drafted against the correct LATEST body,
 * `20260730390000`'s own `idempotency_key_conflict` widening, after an
 * earlier draft based on the stale original migration was caught by an
 * exhaustive, case-insensitive re-grep before being applied anywhere)
 * and
 * `20260827130000_harden_tenant_disclosure_representative_extension_batch2.sql`
 * (extends ISS-2026-043/048's own established
 * `has_active_tenant_membership`-folded-into-not-found pattern to 6 more
 * representative, cross-domain sites --
 * `app.get_sourcing_request`/`app.select_vendor_rate`/
 * `app.get_wms_inbound_order`/`app.reveal_vendor_bank_account_number`
 * (reads) and `app.cancel_approval_request`/`app.approve_finance_invoice`
 * (writes) -- plus `app.decide_approval_step`, closing ISS-2026-049's own
 * second half at the shared Platform Approval Engine's single choke
 * point. `app.approve_finance_invoice` was drafted a second time after
 * this batch's own db-tests wrapper-security-mode regression check
 * caught the first draft silently dropping a later migration's own
 * `SECURITY DEFINER`/`SET search_path`/`FOR UPDATE` hardening -- a bare
 * `CREATE OR REPLACE FUNCTION` with unspecified `SECURITY` resets to
 * `INVOKER`, the Postgres default, not the prior function's own value).
 * Two migrations were also drafted for this batch and then withdrawn
 * before being applied anywhere, after a repo-wide check found each
 * one's true blast radius far exceeded its own originating entry's
 * bounded-fix assessment: ISS-2026-038 (self-approval gate on
 * `app.create_rate_version`/`app.approve_rate_version` -- these two
 * functions turned out to be used as a generic same-actor
 * create-then-approve fixture-seeding shortcut across ~75 unrelated
 * `scripts/db-tests/*.sql` files, 117 total `approve_rate_version` call
 * sites) and ISS-2026-040 (an RPC-level `app.evaluate_permission` deny
 * for any `customer_user`-layer principal -- at least 8 domain test
 * files deliberately grant such a principal a narrow staff role for
 * real, working owner-scoped portal read access, with ownership-scoping,
 * not the RPC-level role gate, providing the actual isolation; a blanket
 * deny would have broken this real capability). dbTestSetSha256 changed
 * (234 files unchanged in count -- 6 existing files widened, no file
 * added or removed): `scripts/db-tests/approval.sql` gained blocks
 * proving `app.request_approval`'s wrapped INSERT still succeeds
 * cleanly on the non-colliding path (the literal concurrent-race branch
 * needs genuine concurrent sessions this harness cannot create -- the
 * same limitation `scripts/db-tests/batch4-tier-c-review-fixes.sql`'s
 * own Fix 13 already accepted for the identical function), and that a
 * cross-tenant stranger now gets a generic not-found error from both
 * `app.cancel_approval_request` and `app.decide_approval_step`, never a
 * tenant-echoing `insufficient_authority`;
 * `scripts/db-tests/procurement-sourcing.sql`,
 * `scripts/db-tests/procurement-vendor-rate-tiers.sql`,
 * `scripts/db-tests/procurement-vendor-financial-security.sql`, and
 * `scripts/db-tests/finance-invoice.sql` each gained or corrected a
 * cross-tenant assertion for their own newly-fixed function;
 * `scripts/db-tests/advanced-tms-wms-inbound.sql` had one pre-existing
 * test corrected from its pre-fix `insufficient_authority` expectation
 * to the corrected `inbound_order_not_found`. Re-verified via a fresh
 * full local db-test suite run (359 migrations, 234 runner files, ALL
 * PASSED) before this digest was changed, and applied to the live
 * hosted project via `apply_migration` immediately after this local run
 * passed.
 *
 * AMENDED 2026-08-27 (twenty-third pass), dbTestSetSha256 only
 * (migrationSetSha256 unchanged -- no migration this batch). Ruling:
 * docs/build-log/release-go-live/RGL-404.md §12, items 32-33 (Track B,
 * Batch 3 -- `hris-integrated-verification-residual` +
 * `hris-overtime-timesheet-gaps` + `hris-payroll-personal-data`). No
 * schema change: `ISS-2026-092` was doc-only (closed by a later entry,
 * `ISS-2026-099`, never applied here); `ISS-2026-063` is test-coverage
 * only. dbTestSetSha256 changed (234 files unchanged in count -- 1
 * existing file widened, no file added or removed):
 * `scripts/db-tests/procurement-vendor-invoice-matching.sql` gained one
 * new block exercising `match_mode='non_po'` (vendor2, which carries no
 * active vendor contract, created with no PO attached) with both
 * `is_partial_invoice=true`/`is_consolidated_invoice=true` on the same
 * case -- three previously-dispatchable-but-never-exercised code paths
 * in `app.create_vendor_bill_match_case`, none of which any existing
 * test in this file reached (every prior successful case-creation call
 * passed `false,false` for both flags). A separate new file,
 * `server/queries/procurement-dashboard.test.ts` (31 tests), is a
 * TypeScript unit test outside this digest's own tracked
 * `scripts/db-tests/` set and does not affect it. An earlier draft of
 * the new db-test block used a vendor1 case for `is_consolidated_invoice`
 * instead, which broke this file's own `invoice_accuracy` KPI aggregate
 * assertion (a fixed 2-case denominator over vendor1's own decided
 * cases) -- caught by the local db-tests suite before this digest was
 * changed, corrected by moving both flags onto a single vendor2 case.
 * Re-verified via a fresh full local db-test suite run (359 migrations,
 * 234 runner files, ALL PASSED) before this digest was changed. No live
 * database write this batch -- nothing to apply via `apply_migration`.
 *
 * AMENDED 2026-08-28 (twenty-fourth pass), migrationSetSha256 and
 * dbTestSetSha256. Ruling: docs/build-log/release-go-live/RGL-404.md §12,
 * items 34-41 (Track B, Batch 4 -- `cpl-customer-portal-scope` +
 * `loyalty-fraud-reconciliation` + `loyalty-approval-authority`). Seven
 * migrations added (359 -> 366 files: +7):
 * `20260827140000_harden_customer_portal_invoice_account_id_projection_
 * iss2026124.sql` (ISS-2026-124: adds `customer_account_id` to
 * `app.get_customer_portal_invoice`/`app.list_customer_portal_invoices`
 * and their `public.*` wrappers, `DROP`+`CREATE` required for the
 * `RETURNS TABLE` widening);
 * `20260828000000_create_loyalty_point_program_expiry_config.sql`
 * (ISS-2026-128 item 2: new `app.loyalty_point_program_configs` table +
 * `set_`/`get_` RPCs + their `public.*` wrappers, `app.post_loyalty_
 * points_earned` widened via `CREATE OR REPLACE` with an identical
 * signature -- self-caught mid-drafting: an ordering bug validated
 * `p_expiry_days` only inside the idempotency short-circuit, silently
 * skipping it on replay, corrected before this digest changed; a missing
 * `public.*` wrapper pair was also self-caught by `public-api-wrapper-
 * regression.sql` and added);
 * `20260828030000_harden_customer_portal_membership_anti_enumeration.sql`
 * (ISS-2026-116: collapses `app.accept_customer_portal_invite`/`app.set_
 * customer_portal_account_membership_status`'s own distinguishable
 * wrong-actor error into the identical not-found shape);
 * `20260828040000_harden_advanced_tms_customer_inventory_access_actor_
 * identity.sql` (ISS-2026-117: all 10 actor-taking functions in ATW-023's
 * customer-inventory-access migration now call `app.assert_actor_is_
 * session_identity` first -- escalated in severity during verification,
 * since `20260826000000`'s own `public.*` wrappers made the gap directly
 * reachable by any authenticated session, not merely theoretical);
 * `20260828050000_harden_customer_portal_loyalty_fraud_review_case_self_
 * approval.sql` (ISS-2026-133 item 1: a new `opened_by_auth_user_id`
 * column plus the established `self_approval_not_allowed` convention on
 * `app.open_loyalty_fraud_review_case`/`app.decide_loyalty_fraud_review_
 * case`);
 * `20260828060000_harden_customer_portal_loyalty_tier_movements_supreme_
 * admin_override.sql` (ISS-2026-137: extends the already-generic
 * `app.protect_loyalty_ledger_append_only()` trigger to a 6th table); and
 * `20260828070000_harden_customer_portal_loyalty_liability_reward_
 * internal_cost_missing_exception.sql` (ISS-2026-134 item 3: a third
 * exception type, `reward_internal_cost_missing`, on `app.execute_
 * loyalty_liability_reconciliation_run` -- self-caught mid-drafting: an
 * early version was accidentally based on a stale pre-CPL-325-atomicity
 * body, live-reproduced breaking that file's own snapshot-atomicity
 * regression, rebuilt on the current body before finalizing).
 * dbTestSetSha256 changed (234 files unchanged in count -- 8 existing
 * files widened, no file added or removed): `advanced-tms-customer-
 * inventory-access.sql`, `customer-invoice-billing-visibility.sql`,
 * `customer-loyalty-expiry-fraud-prevention.sql`, `customer-loyalty-
 * liability-reconciliation.sql`, `customer-loyalty-membership-tier.sql`
 * (a pre-existing fixture that directly `UPDATE`d `app.loyalty_account_
 * tier_movements` corrected to use a genuine Supreme Admin actor, now
 * that the new trigger blocks a raw update), `customer-loyalty-points-
 * ledger.sql`, `customer-portal-loyalty-ledger-supreme-admin-override.
 * sql`, and `customer-portal-scope.sql`. Re-verified via a fresh full
 * local db-test suite run (366 migrations, 234 runner files, ALL PASSED)
 * before this digest was changed, and applied to the live hosted project
 * via `apply_migration` immediately after this local run passed; every
 * new/changed grant and function body live-verified correct.
 *
 * AMENDED 2026-08-28 (twenty-fifth pass), migrationSetSha256 and
 * dbTestSetSha256. Ruling: docs/build-log/release-go-live/RGL-404.md §12,
 * items 42-47 (Track B, Batch 5 -- `perf-load-evidence` +
 * `docs-consistency` + `iae-hardening-residual` + `accessibility` +
 * `browser-compat`). Two migrations added (366 -> 368 files: +2):
 * `20260828090000_harden_ai_governed_action_region_capability_consult.sql`
 * (ISS-2026-152: `app.request_ai_governed_action` now consults the
 * region/service-capability matrix at dispatch time, same signature, zero
 * behavior change for the default `apac` case) and
 * `20260828100000_harden_enterprise_idp_domain_lookup_rate_limit.sql`
 * (ISS-2026-149: `app.resolve_enterprise_idp_by_email_domain`, escalated
 * in severity during verification since RGL-394's own `public.*` wrapper
 * layer made it a real, live, anon-reachable endpoint after this entry
 * was written, gains a `client_key`-scoped rate limiter mirroring
 * `app.lookup_public_shipment_tracking`'s own established shape --
 * `DROP`+`CREATE`, never a bare `CREATE OR REPLACE` with an added
 * parameter, taxonomy class C-29). A third draft
 * (`retention_class`/`legal_hold` columns on 6 Loyalty ledger tables,
 * ISS-2026-142) was deleted before being applied anywhere after this
 * batch's own integration pass found the true scope (registry.ts entries
 * + an enforcement mechanism + db-test coverage, none of which the draft
 * itself had) exceeds the entry's own bounded-fix assessment -- its own
 * timestamp slot (`20260828080000`, which briefly collided with a
 * sibling draft from the same research pass) was freed by the deletion,
 * not reused. dbTestSetSha256 changed (234 files unchanged in count -- 2
 * existing files widened, no file added or removed):
 * `scripts/db-tests/ai-governance-provider-boundary.sql` gained a new
 * block proving the default-region case is unaffected, an
 * unsupported-with-no-exception dispatch is refused, and an
 * unsupported-with-a-real-exception dispatch succeeds and is
 * audit-tagged; `scripts/db-tests/enterprise-iam-sso-scim.sql` gained a
 * new block proving the client_key-scoped rate limit (10 not-found
 * lookups rate-limit the 11th for one client_key, a distinct client_key
 * unaffected) plus updated its 3 pre-existing call sites and its own
 * schema-privilege regression to the new 2-parameter signature.
 * `scripts/load-tests/pagination-explain.sh`/`pgbench/claim-next-job.sql`
 * and 19 accessibility component files under `app/(tenant)/[tenantSlug]/`
 * are also part of this batch but fall outside either tracked set (load
 * scripts are not `scripts/db-tests/`; component files are not
 * migrations or db-tests) and so do not affect either digest. Re-verified
 * via a fresh full local db-test suite run (368 migrations, 234 runner
 * files, ALL PASSED) before this digest was changed, and applied to the
 * live hosted project via `apply_migration` immediately after this local
 * run passed; every new/changed grant and function body live-verified
 * correct.
 *
 * AMENDED 2026-08-28 (twenty-sixth pass), migrationSetSha256 and
 * dbTestSetSha256. Ruling: docs/build-log/release-go-live/RGL-404.md §12,
 * items 48-59 (Track B, Batch 6 -- `rbac-defense-in-depth` +
 * `support-access-audit` + `rls-own-row-narrowing` +
 * `step-up-mfa-enforcement` + `observability-alerting` +
 * `db-test-flakiness` + `ticketing-links-gaps` + `perf-cache-safety`).
 * Four migrations added (368 -> 372 files: +4):
 * `20260828110000_harden_support_session_gates_active_grant.sql`
 * (ISS-2026-187+188: `app.has_active_support_grant` now also requires a
 * live, open `support_access_sessions` row for the grant, closing both
 * the reauth-bypass and the end-session-is-a-no-op gaps with one fix);
 * `20260828111000_harden_support_session_open_audit_trail.sql`
 * (ISS-2026-177: `app.start_support_session` now also writes a canonical
 * `app.audit_logs` entry on a genuine new session);
 * `20260828121000_harden_shared_record_scope_primitives_actor_identity.sql`
 * (ISS-2026-186 partial: 3 of the ~14 candidates re-derived as genuinely
 * self-referential-only gain the established assert-first pattern; 6
 * remain genuinely open); and
 * `20260828140000_harden_customer_ticket_links_entity_id_registry_
 * redaction.sql` (ISS-2026-102: `app.list_customer_ticket_links` redacts
 * `entity_id` to a fixed nil-UUID marker for any row whose `entity_type`
 * falls outside the customer-safe registry). Two self-caught regressions
 * found and fixed during this batch's own db-tests run before anything
 * was applied live -- a hardcoded row-count assertion that didn't account
 * for a function being called twice in the same fixture, and a
 * wiring-check regex anchored on a dollar-quote tag `pg_get_functiondef()`
 * never actually produces (it renders `$function$`, not `$$`) -- both
 * fixed in the db-test files themselves, not the migrations.
 * dbTestSetSha256 changed (234 files unchanged in count -- 5 existing
 * files widened, no file added or removed): `scripts/db-tests/support-
 * access.sql` (section 8 updated for the new session-gate semantics),
 * `audit-trail.sql` (new session-open audit-event proof),
 * `rbac-enforcement.sql` (position-aware wiring check + live two-session
 * forced-spoof proof for the 3 newly-fixed primitives), `hris-kpi-
 * performance.sql` (new RLS contrast proof for ISS-2026-190, a stale
 * finding requiring no code fix), and `ticketing-linked-records.sql`
 * (new section 20 proving the entity_id redaction). `.github/workflows/
 * ci.yml` and `package.json` also changed (new `security:check-rls-
 * initplan` CI step, closing ISS-2026-240's finding that no such guard
 * existed as committed tooling) but fall outside either tracked set.
 * Re-verified via a fresh full local db-test suite run (372 migrations,
 * 234 runner files, ALL PASSED, third attempt after the two self-caught
 * fixes above) before this digest was changed, and applied to the live
 * hosted project via `apply_migration` immediately after this local run
 * passed; every new/changed grant and function body live-verified
 * correct.
 *
 * AMENDED 2026-08-28 (twenty-seventh pass), migrationSetSha256 and
 * dbTestSetSha256. Ruling: docs/build-log/release-go-live/RGL-404.md §12,
 * items 60-73 (Track B, Batch 7 -- `lineage-provenance` +
 * `rest-api-consistency` + `rest-api-error-shape` +
 * `files-legal-hold-residual` + `crypto-scan-recovery` +
 * `schema-completeness-gaps` + `finance-fx` + `migration-import`). Five
 * migrations added (372 -> 377 files: +5):
 * `20260828150000_harden_job_order_snapshot_source_lineage.sql`
 * (ISS-2026-203: `app.prepare_job_order` merges quotation id/version into
 * 4 of 5 snapshot columns; rewritten mid-draft after a stale-base-body
 * regression was caught against a pre-existing test);
 * `20260828151000_harden_inventory_movement_reservation_source_lineage.sql`
 * (ISS-2026-206 partial: 2 new validation triggers on `app.inventory_
 * movements`/`app.inventory_reservations`; the other 2 named tables
 * re-confirmed to break established `finance-subledger.sql` fixtures,
 * left open);
 * `20260828160000_harden_self_approval_null_actor_fail_open.sql`
 * (ISS-2026-213: 6 self-approval functions widened to
 * `coalesce(<nullable actor column> = p_actor_auth_user_id, true)`; a
 * second stale-base-body regression on `app.approve_warehouse_billing_
 * event` caught and fixed before ever applying);
 * `20260828171000_harden_vendor_evidence_reviewer_record_scope.sql`
 * (ISS-2026-224: new narrow sibling `app.authorize_vendor_evidence_file_
 * access()` unblocks the vendor-evidence second-reviewer workflow; a
 * live-only grant leak on its `public.*` wrapper, from this hosted
 * project's own platform default-privilege bootstrap, found and fixed
 * both live and in this file after local db-tests had already passed);
 * and `20260828173000_harden_files_malware_scan_raw_correction_audit.sql`
 * (ISS-2026-231 partial, audit-visibility only: new `AFTER UPDATE` trigger
 * records an audit_logs entry for a raw malware-scan-status correction; a
 * blocking schema backstop was investigated and correctly NOT added,
 * confirmed to conflict with an established, already-tested repository
 * pattern used in 4 other domains). By far the most difficult batch to
 * date: 10 full local db-tests runs and 9 further self-caught issues
 * before a clean local pass (2 fixture-quantity bugs, 1
 * fixture-isolation/shared-balance conflict, 1 data-modifying-CTE-in-
 * EXISTS PostgreSQL syntax error, 1 missing `auth.users` seed row, 1
 * new-trigger `auth.uid()` robustness gap, 1 missing required `public.*`
 * wrapper, plus the 2 stale-base-body regressions named above).
 * dbTestSetSha256 changed (234 files unchanged in count -- 10 existing
 * files widened, no file added or removed):
 * `scripts/db-tests/operations-job-order.sql`, `advanced-tms-inventory-
 * ledger.sql`, `advanced-tms-cycle-count-adjustment.sql`, `advanced-tms-
 * warehouse-billing-events.sql`, `procurement-vendor-compliance.sql`,
 * `procurement-vendor-financial-security.sql`, `document-file.sql`,
 * `approval.sql`, `dedicated-enterprise-deployment.sql`, `multi-region-
 * data-residency.sql`. `app/api/v1/vendor/assignments/[invitationId]/
 * accept/route.ts`, `.../decline/route.ts`, `app/api/v1/vendor/rfqs/
 * [rfqInvitationId]/response/route.ts`, `app/api/v1/customer/bookings/
 * [bookingRequestId]/submit/route.ts`, `server/contracts/api/api.ts`,
 * `server/queries/automation-rule.ts`(`.test.ts`), and 4
 * `tests/api/v1/*.test.ts` files (ISS-2026-214/237, TypeScript-only) also
 * changed but fall outside either tracked set. Re-verified via a fresh
 * full local db-test suite run (377 migrations, 234 runner files, ALL
 * PASSED, tenth attempt after the self-caught fixes above) before this
 * digest was changed, and applied to the live hosted project via
 * `apply_migration` immediately after this local run passed; every
 * new/changed grant and function body live-verified correct, including a
 * live-only grant-leak correction found via mandatory post-apply grant
 * introspection.
 *
 * AMENDED 2026-08-28 (twenty-eighth pass), migrationSetSha256 and
 * dbTestSetSha256. Ruling: docs/build-log/release-go-live/RGL-404.md §12,
 * items 74-99 (Track B, Batch 8 -- the final "sweep up everything"
 * disposition batch, a 26-item independent re-derivation against
 * docs/runtime/KNOWN_ISSUES.md rather than the plan's own 5 named groups
 * alone). Two migrations added (377 -> 379 files: +2):
 * `20260828193000_harden_customer_portal_last_account_admin_status_guard.sql`
 * (ISS-2026-125 item 3: `app.set_customer_portal_account_membership_
 * status` gains the identical last-admin guard `app.update_customer_
 * portal_account_membership_role` already applies -- the sole active
 * account_admin on an account may no longer suspend/revoke themselves or
 * the account's only other admin); and
 * `20260828200000_create_raw_mutation_tripwire.sql` (ISS-2026-259: a new
 * statement-level tripwire trigger + `xact_id` correlation column + `app.
 * list_untracked_table_mutations()` read RPC, attached to `app.leads` and
 * `app.audit_logs`, detecting -- never blocking -- a raw DELETE/UPDATE/
 * TRUNCATE with no corresponding same-transaction audit-log entry;
 * deliberately bounded to 2 tables, honestly disclosed as narrowing, not
 * closing, the general repo-wide audit blindness). A third migration
 * (`20260828190000_harden_enqueue_job_payload_target_mismatch.sql`,
 * ISS-2026-053) was drafted, applied to a local disposable database, and
 * then WITHDRAWN before ever being applied live -- the full local
 * db-tests suite (not its own isolated regression, which had passed
 * clean) surfaced a real regression: `app.run_loyalty_expiry_sweep`'s own
 * deliberate idempotent-replay design legitimately embeds a
 * `clock_timestamp()`-derived, microsecond-varying value in its payload
 * while its idempotency key correctly scopes only to the calendar day --
 * mirrors the `ISS-2026-038`/`040` withdrawal precedent exactly. Also
 * found and corrected in this same batch: a real inventory omission
 * (`ISS-2026-255`, High, `TRACKED_GAP`, never tracked in `BACKLOG_
 * INVENTORY.md`'s own High-severity table at all -- disclosed and
 * corrected, not silently absorbed) and a false-positive research finding
 * (a first-pass agent's claim that 13 `table-only-procurement-hardening`
 * items were "never actually written back" was independently re-checked
 * and found to be a regex miss against this file's own pipe-table row
 * format, not a real gap -- caught before any action was taken on it).
 * dbTestSetSha256 changed (234 -> 235 files: +1,
 * `scripts/db-tests/raw-mutation-tripwire.sql` -- 6 new regression cases
 * for ISS-2026-259). `scripts/db-tests/ticketing-sla.sql` (new test 13,
 * ISS-2026-090), `customer-user-management.sql` (new block, ISS-2026-125
 * item 3), `customer-portal-dashboard.sql`/`customer-shipment-alerts.sql`
 * (fixture repairs, each self-mutation given a second admin first, direct
 * consequence of the ISS-2026-125 fix), and `scripts/db-tests/lib/setup-
 * disposable-db.sh` (`set -euo pipefail` added internally, ISS-2026-161)
 * all also changed but fall outside the tracked set (widened existing
 * files, not a net-new file, except the one counted above).
 * `app/(tenant)/[tenantSlug]/hris/payroll/actions.ts`/`page.tsx`/
 * `payroll-admin-panel.tsx` (ISS-2026-080, TypeScript-only UI wiring)
 * also changed but is neither a migration nor a db-test file. Re-verified
 * via a fresh full local db-test suite run (379 migrations, 235 runner
 * files, ALL PASSED, second attempt after the ISS-2026-053 migration was
 * withdrawn following the first attempt's real regression) before this
 * digest was changed, and applied to the live hosted project via
 * `apply_migration` immediately after this local run passed; every
 * new/changed grant and function body live-verified correct on first
 * application, no live-only leak this time (the platform default-
 * privilege bootstrap revoke was baked into the new migration from the
 * start, per the precedent Batch 7 established).
 *
 * AMENDED 2026-08-30 (twenty-ninth pass), migrationSetSha256 and
 * dbTestSetSha256. Ruling: docs/adr/ADR-0027-owner-authorized-remediation-and-
 * launch.md Part A (owner-authorized remediation scope), which lifts the
 * per-task size cap and inverts AGENTS.md's "fix only task-caused failures"
 * for declared remediation tasks until the backlog reaches zero. This is the
 * first schema-touching item worked under that ruling; subsequent amendments
 * in this remediation phase share it rather than each minting a new one.
 *
 * `ISS-2026-057` (PRC-251 §22 "Bulk-import staged vendors" -- a named
 * alternative flow in the source prompt that was never built; the only trace
 * of it in the repository was the `bulk_import` value in the
 * `vendor_profiles_intake_source_check` constraint and the matching
 * TypeScript enum). Re-verified live as still-open before any code was
 * written. Closed additively by one new migration (379 -> 380 files: +1,
 * `20260830100000_create_vendor_import_adapter.sql`) -- no already-applied
 * migration is edited. It registers the `vendor_import` PLT-131 schema kind
 * and its config type, adds `app.vendor_profiles.source_import_staging_row_id`
 * with a partial unique index as the adapter's own idempotency guard, and adds
 * `app.validate_vendor_import_row` + `app.commit_vendor_import_job` (plus their
 * two `public.*` wrappers), at the fidelity of the entry's own cited precedent,
 * PRC-255's `vendor_rate_import`.
 *
 * Three properties worth naming here because each is a defect class this
 * repository has already paid for: (1) authority is strictly additive --
 * BOTH `app.is_support_grant_authority` AND `PRC:Import`, with
 * `create_vendor_profile_draft`'s own unchanged `PRC:Create` still enforced per
 * row (the regression live-proves these are independent: `tenant_admin` does
 * not confer `PRC:Import`); (2) `unique_violation` is discriminated by
 * constraint name, and the shape here deliberately differs from both
 * precedents -- no `unique_violation` escaping `create_vendor_profile_draft` is
 * ever a safe replay, so it is left unhandled there, and the single handler
 * sits on the provenance-stamping UPDATE accepting exactly one constraint
 * name; (3) the duplicate-candidate detector PRC-251 already built, which had
 * no bulk caller, is wired in with two sweeps (trigram name similarity, and an
 * exact punctuation/case-normalized `business_registration_number` match) that
 * flag rather than block -- the import lands and the flagged vendor cannot be
 * submitted for review until a human decides. `ISS-2026-278`'s trailing
 * `p_client_ip` IP-allowlist shape is carried at birth.
 *
 * dbTestSetSha256 changed (235 files unchanged in count --
 * `scripts/db-tests/procurement-vendor-registration.sql` widened with six new
 * regression blocks, no file added or removed). One defect in this fix was
 * caught by an existing gate rather than by its author and is recorded rather
 * than quietly corrected: the first version's
 * `public.validate_vendor_import_row` wrapper was `security definer` over an
 * `invoker` `app.*` function -- an RLS-bypass-class mismatch --
 * and `scripts/db-tests/public-api-wrapper-regression.sql`'s exhaustive
 * mode-parity check failed the run; fixed to `invoker` before commit.
 * Re-verified via a fresh full local db-test suite run (380 migrations, 235
 * runner files, ALL PASSED) before this digest was changed. NOT yet applied to
 * the live hosted project -- live application is Part 5 of this phase's own
 * plan, and this amendment does not claim it.
 *
 * AMENDED 2026-08-30 (thirtieth pass), migrationSetSha256 and dbTestSetSha256.
 * Same ruling as the twenty-ninth pass: ADR-0027 Part A.
 *
 * `ISS-2026-236` (High, `HDN-BLK-024`/`HDN-BLK-040`) -- 3 of
 * `app.is_high_risk_action`'s own 7 platform-default high-risk tuples
 * (`SEC:Configure`, `FIN:Approve`, `HRS:Approve`, covering 61 real,
 * reachable, `authenticated`-executable functions) were classified
 * high-risk and enforced nothing, across the entire IAE-037 -> IAE-039 ->
 * HDN-378 lineage. Step-up half closed additively by one new migration
 * (380 -> 381 files: +1,
 * `20260830110000_harden_evaluate_permission_step_up_enforcement.sql`) --
 * a single unchanged-signature CREATE OR REPLACE of
 * `app.evaluate_permission`, carrying forward every branch 20260810300000,
 * 20260826040000 and 20260826110000 added, verbatim and in order, plus one
 * new branch. Not 61 function-body rewrites: that shape is what every prior
 * checkpoint correctly declined (61 verbatim body restatements, one slip
 * inside `approve_finance_invoice` being worse than the gap), and IAE-037
 * live-proved the second cost when wiring 4 of them unconditionally broke
 * 17 already-VERIFIED fixtures and was reverted. All 61 pass through
 * `evaluate_permission`, and this repository already established the
 * chokepoint precedent at `20260826110000` (ISS-2026-264, session-
 * revocation enforcement in that same function).
 *
 * `app.is_high_risk_action` is deliberately NOT changed -- narrowing its
 * platform-default tuple list would have made every fixture pass trivially
 * and would have been a weakening of a declared security classification
 * dressed up as a fix. The blast radius is bounded instead on a real,
 * tenant-owned, already-shipped switch (`mfa_tenant_policies.
 * tenant_wide_required`), so a tenant with MFA off reaches an identical
 * decision to before. Measured across the whole suite, that radius was one
 * file.
 *
 * dbTestSetSha256 changed (235 files unchanged in count --
 * `scripts/db-tests/enterprise-mfa-session-controls.sql` widened, no file
 * added or removed): a new regression block for the branch itself
 * (denial with the exact reason, a real verified challenge restoring
 * `role_grant`, tuple-scoping, time-scoping, a Supreme Admin subject to the
 * gate and able to clear it, and an MFA-off tenant unaffected while
 * `is_high_risk_action` still reports the tuple high-risk), plus two
 * existing `SEC:Configure` call sites adapted the way IAE-039 adapted its
 * own -- by requesting and verifying a real challenge, never by relaxing an
 * assertion. The negative (`viewer1`) case was given a challenge too,
 * deliberately, so its rejection still fires on the SEC:Configure role gap
 * it was written for rather than passing for the wrong reason.
 *
 * The IP-restriction half of ISS-2026-236 is NOT closed and is carried
 * forward as `ISS-2026-302` (Medium) -- `app.assert_ip_allowed` needs the
 * caller's own IP, which `evaluate_permission` has no parameter for, so the
 * chokepoint cannot serve it. A half-fix is not allowed to retire a
 * two-part finding.
 *
 * Re-verified via a fresh full local db-test suite run (381 migrations, 235
 * runner files, ALL PASSED) before this digest was changed. NOT yet applied
 * to the live hosted project.
 *
 * AMENDED 2026-08-30 (thirty-first pass), migrationSetSha256 and
 * dbTestSetSha256. Same ruling: ADR-0027 Part A.
 *
 * `ISS-2026-274` (Medium) -- no master-data (customer/vendor/item) bulk-import
 * mechanism existed anywhere. The vendor third was closed by the
 * twenty-ninth pass; the customer and item thirds are closed here, so the
 * entry retires rather than staying partially annotated. One new migration
 * (381 -> 382 files: +1,
 * `20260830120000_create_customer_and_item_import_adapters.sql`).
 *
 * That migration also fixes a prerequisite the issue's own text got wrong. It
 * names `app.create_master_record` as the primitive a customer adapter should
 * compose; a customer is not a `master_records` row (no `customer` master type
 * is seeded anywhere) but an `app.accounts` row -- and
 * `app.convert_quotation_to_account` was the ONLY function in the entire
 * repository that had ever inserted into `app.accounts`. A tenant migrating an
 * existing customer book at cutover therefore had no path that did not involve
 * inventing a quotation. `app.create_customer_account_direct` is added as a
 * real second creation path at the SAME COM:Approve authority, computing
 * normalization and the duplicate fingerprint through the SAME functions the
 * quotation path uses, so it cannot slip a duplicate past a control that path
 * enforces.
 *
 * dbTestSetSha256 changed (235 -> 236 files: +1,
 * `scripts/db-tests/master-data-import.sql`, new). `scripts/db-tests/
 * advanced-tms-item-uom-master.sql` also changed but is a corrected comment,
 * not a new file: it asserted the CRM pipeline was "the only real path to
 * app.accounts -- no shortcut function exists anywhere in this repository",
 * which was true when written and is no longer. That fixture deliberately
 * keeps using the conversion pipeline, since exercising the original path is
 * what makes it a regression guard for it.
 *
 * Re-verified via a fresh full local db-test suite run (382 migrations, 236
 * runner files, ALL PASSED) before this digest was changed. NOT yet applied to
 * the live hosted project.
 *
 * AMENDED 2026-08-30 (thirty-second pass), migrationSetSha256 and
 * dbTestSetSha256. Same ruling: ADR-0027 Part A.
 *
 * `ISS-2026-273` (High) -- two coupled gaps: no bulk opening-balance import
 * path existed at all, and opening balances never reached the general ledger
 * (FIN-202 disclosed the second and named it a live constraint on any future
 * opening-balance import; this migration builds that import). Closed together
 * in one new migration (382 -> 383 files: +1,
 * `20260830130000_create_finance_opening_balance_import_and_gl_posting.sql`),
 * because closing either alone would leave the other making the first untrue.
 *
 * The GL entry posts against a NEW `opening_balance_equity` finance_posting_map
 * key rather than a hardcoded account: an unconfigured tenant fails closed with
 * finance_subledger_missing_mapping instead of having an equity account guessed
 * for it. `app.get_finance_subledger_reconciliation_summary` is corrected, not
 * merely widened -- its old invoice-only filter would have made a correctly
 * migrated tenant read UNRECONCILED once opening balances started emitting
 * batches, while including all of them would have hidden a real difference; it
 * now counts posted opening balances in the total, reports unposted ones
 * explicitly, and carries an openingBalancesFullyPostedToGl boolean.
 *
 * TWO defects in this migration were caught by existing gates rather than by
 * its author, and are recorded rather than quietly corrected: (1) the
 * CREATE OR REPLACE of get_finance_subledger_reconciliation_summary was written
 * from the ORIGINAL 20260729160000 definition and silently dropped the
 * SECURITY DEFINER that 20260810900000 had added -- the exact defect
 * 20260811200000 introduced on request_finance_settlement_reversal and RGL-404
 * later had to find; public-api-wrapper-regression.sql's mode-parity check
 * failed the run. (2) The CHECK constraint on
 * finance_subledger_batches.source_type is not the only gate --
 * app.post_finance_subledger_batch carries its own `not in (...)` list, and
 * widening one without the other left opening balances rejected outright. That
 * function's ~140-line body is now a SCRIPT-EXTRACTED, mechanically patched
 * copy of 20260811000000's definition with exactly one line changed, its
 * security definer and search_path clauses carried along -- nothing retyped,
 * because restating that much balanced-posting and journal-emission logic by
 * hand is the transcription risk the thirtieth pass argued against.
 *
 * The Inventory and HRIS instances of the same non-bulk opening-balance pattern
 * are NOT closed and are carried forward as `ISS-2026-303` (Medium) -- ordinary
 * PLT-131 adapter work with no double-entry coupling, and not the same change.
 *
 * dbTestSetSha256 changed (236 files unchanged in count --
 * `scripts/db-tests/finance-subledger.sql` widened, no file added or removed):
 * an opening-balance setup block and a 10-row import scenario covering every
 * validator branch, both halves posting in one transaction, the equity
 * counter-account carrying a net 850.00 credit in the right direction on both
 * sides, reconciliation staying exact (the case that would have read
 * UNRECONCILED under the old filter), GL-post idempotency, and refusal to post
 * an invoice-sourced item. The file's pre-existing assertion about an un-posted
 * opening balance was STRENGTHENED rather than adjusted -- it now also asserts
 * the item is reported rather than filtered away.
 *
 * Re-verified via a fresh full local db-test suite run (383 migrations, 236
 * runner files, ALL PASSED) before this digest was changed. NOT yet applied to
 * the live hosted project.
 *
 * AMENDED 2026-08-30 (thirty-third pass), migrationSetSha256 and
 * dbTestSetSha256. Same ruling: ADR-0027 Part A.
 *
 * `ISS-2026-258` (High) -- no DR/incident communication mechanism existed
 * anywhere: no channel, no template, no notification order, no customer-impact
 * record. All twenty runbooks' Communication sections were a bare "notify
 * DevOps". One new migration (383 -> 384 files: +1,
 * `20260830140000_create_incident_communication.sql`).
 *
 * A load-bearing claim in that entry was stale and changed the shape of the
 * fix: it (and its 2026-08-27 disposition) stated no dispatch integration
 * existed anywhere and concluded an external product build was required.
 * PLT-127's Notification Engine is real and complete, IAE-034 added contact
 * addresses on top of it, and IAE-035 carries email/WhatsApp/SMS adapters. The
 * channel existed; what did not was everything between an incident and it. This
 * migration adds an ordered audience registry (data, not runbook prose), a
 * durable record of what was said to whom, a registered notification type so
 * templates are ordinary config, and a broadcast action that COMPOSES
 * app.queue_notification rather than building dispatch a second time -- the
 * caution ISS-2026-251 raises, taken literally.
 *
 * dbTestSetSha256 changed (236 files unchanged in count --
 * `scripts/db-tests/enterprise-monitoring-observability.sql` widened, no file
 * added or removed): four regression blocks covering the dispatch order and its
 * uniqueness constraint, the full authority matrix (including a DIFFERENT
 * tenant's tenant_admin refused), verbatim body storage, recipient records
 * matching the recorded count, the timeline event, idempotent retry and the
 * different-words conflict, platform-scoped Supreme-Admin-only, tenant-audience
 * refusal on a platform incident, the zero-recipient case recorded as zero
 * rather than reported as sent, and RLS plus the anon/authenticated grant
 * matrix.
 *
 * Also in this pass, outside the frozen sets: a new
 * `docs/runbooks/incident-communication.md`, and three runbooks corrected in
 * place because this fix made their text false -- disaster-recovery.md §5
 * (which asserted no such mechanism existed anywhere),
 * data-migration-rehearsal.md §5 (which repeated it), and
 * incident-response.md §5. Superseded text is quoted rather than quietly
 * deleted.
 *
 * The public status page is NOT built and is carried forward as `ISS-2026-304`
 * (Medium): a status page hosted inside the system it reports on is useless
 * during the outage it exists to report, which makes it a hosting decision
 * rather than a migration.
 *
 * Re-verified via a fresh full local db-test suite run (384 migrations, 236
 * runner files, ALL PASSED) before this digest was changed. NOT yet applied to
 * the live hosted project.
 *
 * AMENDED 2026-08-30 (thirty-fourth pass), migrationSetSha256 and
 * dbTestSetSha256. Same ruling: ADR-0027 Part A.
 *
 * `ISS-2026-251` (Medium) -- alert routes carried real owner metadata that
 * nothing ever dispatched to, and no automatic escalation existed, so an
 * unacknowledged incident never paged anyone. The dispatch half closed in the
 * thirty-third pass (ISS-2026-258); the escalation half closes here. One new
 * migration (384 -> 385 files: +1,
 * `20260830150000_create_incident_escalation_sweep.sql`).
 *
 * app.run_incident_escalation_sweep COMPOSES
 * app.broadcast_incident_communication rather than building a second dispatch
 * path -- the precise caution ISS-2026-251 raises. Thresholds are per-severity
 * policy with tenant-nullable platform defaults, anchored to
 * 11_DEVOPS_WORKSTREAM.md §8.4's own P1-P4 targets rather than invented, and a
 * regression pins the critical=15-minute figure so a change to that
 * architecture target fails loudly instead of drifting.
 *
 * A REAL BUG in this fix was caught by its own regression rather than by
 * review, and is recorded rather than quietly corrected: the first version
 * treated the two escalation levels as independent flags, escalating an
 * incident at 'unresolved' on one sweep and then the SAME incident again at
 * 'unacknowledged' on the next, because that row did not exist yet. On a
 * five-minute timer that is a double-page. They are a ladder.
 *
 * FIVE places had to move in lockstep for the new job type, not the four the
 * drift gate names: jobs_job_type_check, app.generic_job_types(), the
 * TypeScript GENERIC_JOB_TYPES contract and its test, the db-test mirror, and
 * IMPORT_EXPORT_JOB_TYPES in server/contracts/import-export/import-export.ts.
 * ATW-031's gate caught the first four and named each; the fifth was caught by
 * ATW-032's own separate assertion, which exists precisely because an earlier
 * remediation widened GENERIC_JOB_TYPES and missed this array.
 * app.all_job_types() needed no change -- it is derived rather than a sixth
 * literal. A first draft had also copied 20260805050000's job-type list
 * instead of 20260807500000's -- the latest -- silently dropping 'audit_export'
 * and 'retention_archive'; caught on the first run by
 * advanced-audit-impersonation.sql. The correct list was then extracted
 * programmatically rather than retyped.
 *
 * dbTestSetSha256 changed (236 files unchanged in count --
 * `enterprise-monitoring-observability.sql` widened with three regression
 * blocks, and `background-job.sql`'s TS-mirror literal updated; no file added
 * or removed). `server/contracts/background-job/background-job.ts` and its test
 * also changed but are neither migrations nor db-tests.
 *
 * NOT closed, and named as an operational step rather than implied: nothing
 * invokes the sweep on a timer. No batch in this repository has a scheduler --
 * run_ticket_sla_evaluation_batch, run_leave_accrual_batch and
 * run_loyalty_expiry_sweep all sit in the same position. That is one deployment
 * task for all of them, not one per feature.
 *
 * Re-verified via a fresh full local db-test suite run (385 migrations, 236
 * runner files, ALL PASSED) before this digest was changed. NOT yet applied to
 * the live hosted project.
 *
 * AMENDED 2026-08-30 (thirty-fifth pass), migrationSetSha256 and
 * dbTestSetSha256. Same ruling: ADR-0027 Part A.
 *
 * `ISS-2026-093` (Medium, C-24) -- `app.cancel_approval_request`, a shared
 * PLT-123 primitive, duplicated its caller-supplied reason into
 * app.audit_logs.reason, readable by any plain tenant_admin with zero domain
 * permission. One new migration (385 -> 386 files: +1,
 * `20260830160000_harden_approval_engine_audit_reason_redaction.sql`).
 *
 * Two corrections to that entry's own premise, both from checking rather than
 * assuming. (1) It is TWO functions: app.decide_approval_step passes p_reason
 * raw in the same shape and is the more frequently called of the two.
 * (2) They are not equally severe, and the entry's reasoning fits the one it
 * does not name -- app.approval_decisions carries NO authenticated grant, so
 * the audit log genuinely was the only path to a rejection reason; whereas
 * app.approval_requests grants select on the whole table to authenticated with
 * an any-active-member policy, so ended_reason was ALREADY readable by a
 * broader audience than tenant_admins. The cancel half is recorded as
 * defence-in-depth rather than dressed up as a narrowing it is not.
 *
 * A second leak vector the obvious fix would have missed:
 * app.redact_audit_payload matches by KEY NAME and 'ended_reason' matches none
 * of its patterns, so to_jsonb(v_updated) carried the reason verbatim into
 * after_value. Passing null for the scalar alone would have closed one vector
 * and left the other -- a fix that reads as complete and is not. Hence
 * app._approval_request_audit_projection, mirroring
 * app.leave_request_audit_projection (HRT-280/293).
 *
 * The genuinely wider exposure -- the table grant itself -- is NOT changed here
 * and is registered as `ISS-2026-305` (Medium). app.approval_requests is read
 * directly by Finance, Commercial, Procurement and HR; narrowing that grant
 * needs every one of those read paths re-verified, and doing it quietly inside
 * a fix for a different finding would be exactly the unreviewed blast radius
 * ISS-2026-093's own disposition was right to refuse.
 *
 * Both function bodies are MECHANICALLY EXTRACTED copies of their current
 * definitions with only the capture_audit_event call changed -- between them
 * they carry the C-21 lock-ordering fix, ISS-2026-048/049's tenant-disclosure
 * fixes and ISS-2026-213's null-actor self-approval guard.
 *
 * dbTestSetSha256 changed (236 files unchanged in count -- `approval.sql`
 * widened with two regression blocks, no file added or removed). The first
 * plants canary strings in a real rejection and cancellation reason and asserts
 * neither appears anywhere in app.audit_logs -- scalar column AND both jsonb
 * payloads, searched as text, because checking only the reason column is what
 * let the jsonb vector survive the first time this defect class was fixed
 * elsewhere -- while asserting both reasons are still durably stored and both
 * audit events still exist. The second pins that redact_audit_payload does NOT
 * cover ended_reason, so a later assumption that it does fails loudly.
 *
 * Re-verified via a fresh full local db-test suite run (386 migrations, 236
 * runner files, ALL PASSED) before this digest was changed. NOT yet applied to
 * the live hosted project.
 *
 * AMENDED 2026-08-30 (thirty-sixth pass), migrationSetSha256 and
 * dbTestSetSha256. Same ruling: ADR-0027 Part A.
 *
 * `ISS-2026-307` (Medium, found while closing `ISS-2026-249`) --
 * `app.ip_access_evaluations`, the IP allowlist's own audit trail, can never
 * contain a `denied` row. `app.assert_ip_allowed` was its only writer; on a
 * denial it INSERTs the row and then raises `ip_not_allowed` to deny the
 * caller, and that exception aborts the transaction and takes the INSERT with
 * it. So the table holds exactly the accesses the control let through and none
 * it blocked -- the harder the control works, the emptier its evidence gets.
 * One new migration (386 -> 387 files: +1,
 * `20260830170000_create_durable_ip_access_evaluation.sql`).
 *
 * Live-reproduced on a disposable database BEFORE the fix was written, with a
 * control case in the same run: denied 203.0.113.9 left the table at 0 -> 0
 * rows; allowed 10.1.2.3 left it at 0 -> 1. Without the control this would
 * read as "the table is empty", not "the table cannot record denials".
 *
 * This was drafted once before, as Part D of
 * `20260827000000_wire_observability_alert_producers.sql`, and WITHDRAWN before
 * applying -- the local db-tests suite caught the rollback and that migration's
 * header recorded the root cause honestly. But it framed the loss as being
 * about the alert it was adding. The evaluation row one line above it, which
 * predates the alert idea entirely, was already being lost the same way. A
 * withdrawn fix with a correct diagnosis is a good outcome; the miss was not
 * re-reading what else lived in the branch about to be abandoned.
 *
 * The shape that works is the one that note itself named -- move the recording
 * out of the raising function. `app.evaluate_ip_access` makes the same decision
 * and RETURNS it, so its evaluation row and its new security alert both
 * survive; `app.assert_ip_allowed` keeps its signature and behaviour and now
 * composes the evaluator, so there is exactly one copy of the decision logic
 * and the two cannot drift about what counts as allowed. This also closes the
 * IP-restriction slice of `ISS-2026-249` (security denials produced zero
 * incident); its other two slices stay open, unchanged, for the architectural
 * reasons already recorded there.
 *
 * The residual is stated in the migration header rather than left implicit: a
 * denial raised INSIDE a business transaction still loses its own row, because
 * that transaction still aborts. Closing that needs an autonomous transaction
 * (a real new dependency) or a breaking contract change to every import-commit
 * RPC. What changed is that a durable path now EXISTS, which it did not before.
 *
 * `public.evaluate_ip_access` was missing on this migration's first run and
 * `public-api-wrapper-regression.sql` failed it -- the parity gate catching a
 * real omission, recorded rather than quietly fixed.
 *
 * dbTestSetSha256 changed (236 files unchanged in count --
 * `ip-restriction-network-access.sql` widened, no file added or removed). Its
 * new block asserts the DEFECT as a property first (assert_ip_allowed's denial
 * row is still rolled back, with a message saying that if this ever starts
 * persisting the assertion should be inverted, not deleted), then the fix: the
 * evaluator's row survives, carries the right subject and address, and opens
 * exactly ONE deduplicated security incident.
 *
 * Re-verified via a fresh full local db-test suite run (387 migrations, 236
 * runner files, ALL PASSED) before this digest was changed. NOT yet applied to
 * the live hosted project.
 *
 * AMENDED 2026-08-30 (thirty-seventh pass), dbTestSetSha256 ONLY -- no
 * migration added or changed. Same ruling: ADR-0027 Part A.
 *
 * `ISS-2026-151` (Medium) -- `app.create_integration_connection`
 * (`INTHUB:Configure`) was the last of four platform-default high-risk actions
 * with no step-up enforcement. Its own worklist said the fix required wiring
 * the function AND adapting 52 call sites across 17 files in one change,
 * "never one without the other". That worklist was right about the shape of
 * fix it assumed: an unconditional `assert_current_step_up_authorization` in
 * the body, which `CG-S14-IAE-037` live-proved breaks every fixture that does
 * not model a challenge, and reverted.
 *
 * The enforcement already shipped, at the thirtieth pass. 20260830110000's
 * chokepoint branch gates any high-risk (module, action) on the tenant's own
 * `tenant_wide_required` switch, and `('INTHUB','Configure')` is one of the
 * seven platform defaults. Condition (b) is the transition path the reverted
 * attempt lacked, which is why none of the 52 call sites needed adapting:
 * none of the 17 files turns tenant-wide MFA on.
 *
 * So this pass adds NO code. It adds the proof, because "it should be covered
 * by the chokepoint" is a claim about a call graph, not evidence.
 * `integration-hub.sql` now asserts four properties: the call succeeds with no
 * step-up by default (the fixture-compatibility property IAE-037 failed); the
 * same call by the same INTHUB:Configure holder is denied `mfa_step_up_required`
 * once the tenant turns MFA on; a genuine request/verify challenge lets that
 * actor through, so the gate is passable rather than a lockout; and turning the
 * policy back OFF requires a step-up even for the Supreme Admin, since
 * `SEC:Configure` is itself high-risk and the branch sits deliberately before
 * the Supreme Admin exception. That last assertion fails if the ordering is
 * ever lost.
 *
 * Also recorded rather than left as a surprise: turning tenant-wide MFA ON
 * succeeds without a step-up, because condition (b) is not true yet. Gating it
 * would make the control unadoptable.
 *
 * Re-verified via a fresh full local db-test suite run (387 migrations, 236
 * runner files, ALL PASSED) before this digest was changed. NOT yet applied to
 * the live hosted project.
 *
 * AMENDED 2026-08-30 (thirty-eighth pass), migrationSetSha256 and
 * dbTestSetSha256. Same ruling: ADR-0027 Part A.
 *
 * `ISS-2026-155` (Medium) -- `app.raise_observability_alert` deduplicates on
 * (tenant_id, source_type, signal_type), and `app.evaluate_workload_budget`
 * maps seven workload types onto four source types, so `analytics` and
 * `reports` both arrive as 'job'. A tenant breaching both inside the dedup
 * window opened ONE incident; the second was filed as a duplicate_signal and
 * its workload was never named anywhere. One new migration (387 -> 388 files:
 * +1, 20260830180000_add_observability_alert_dedupe_discriminator.sql).
 *
 * Three earlier passes reached the same two options and rejected both,
 * correctly: widen the shared CHECK enums, or let IAE-034 raise outside the
 * dedup mechanism. The third shape none considered is an OPTIONAL extra
 * dimension -- a nullable column, a seventh parameter defaulting to null, one
 * caller that passes something. Same additive-optional-parameter move as
 * `p_effective_date` (20260731310000) and `p_client_ip` (20260826190000), for
 * the same reason: a parameter a caller does not know about cannot regress it.
 *
 * Overloaded rather than DROP+CREATE: CREATE OR REPLACE cannot add a
 * parameter, and dropping the 6-argument form would mean dropping its public.*
 * wrapper and recreating both. The 7-argument form carries the body; the
 * 6-argument form delegates with null. One implementation, no dependency churn.
 *
 * `v_source_type` stays coarse deliberately -- it routes the incident to an
 * owner team via app.alert_routes, and re-pointing it would have silently
 * re-routed every workload alert while appearing to fix the symptom.
 *
 * Two things that would each have been a silent regression, both caught while
 * writing rather than by a test: the lookup needs `is not distinct from`, since
 * `=` would stop all seven null-discriminator producers deduplicating; and the
 * advisory lock key needs the discriminator too, keyed on exactly what the
 * lookup filters, or the check-then-act race the lock closes reopens.
 *
 * dbTestSetSha256 changed (236 files unchanged in count --
 * scale-up-architecture.sql widened, no file added or removed). It asserts the
 * two workloads now separate, that each incident carries its workload while
 * source_type stays 'job', that a repeat breach of the SAME workload still
 * reuses its incident with exactly one duplicate_signal, and that two
 * null-discriminator signals still collapse. The strongest non-regression proof
 * was already in the tree and is untouched: background-job.sql still asserts
 * two distinct job_types dead-lettering for one tenant collapse into one
 * incident -- that producer passes no discriminator.
 *
 * Re-verified via a fresh full local db-test suite run (388 migrations, 236
 * runner files, ALL PASSED) before this digest was changed. NOT yet applied to
 * the live hosted project.
 *
 * AMENDED 2026-08-30 (thirty-ninth pass), migrationSetSha256 and
 * dbTestSetSha256. Same ruling: ADR-0027 Part A.
 *
 * `ISS-2026-053` (Low) -- app.enqueue_job's idempotency replay compared the key
 * and job_type but not the payload, so reusing a key for the same job type with
 * different work silently returned the first job and reported success. One new
 * migration (388 -> 389 files: +1,
 * 20260830190000_harden_enqueue_job_idempotency_payload_tuple.sql).
 *
 * Two things this fix discovered, both recorded rather than absorbed:
 *
 * 1. The obvious fix is wrong. Comparing app.jobs.payload failed the suite on
 *    app.run_loyalty_expiry_sweep's own "same day does NOT double-expire" test,
 *    because payload is a request AND result store -- the sweep appends its
 *    counts to it after the job runs, so a stored payload can never equal the
 *    request that created it. Hence app.jobs.request_payload: written once at
 *    insert, never updated, null on pre-existing rows (and null skips the
 *    comparison, so the guard is never retroactive).
 *
 * 2. Registered as ISS-2026-308: the sweep keyed idempotency per run_label (a
 *    date) while putting clock_timestamp() in its request payload. Key said
 *    "once per label", payload said "every call differs". Its request payload
 *    now carries run_label alone; the resolved instant and the caller's own
 *    p_as_of moved to the completion update, on the result side.
 *
 * A third thing, and the one worth remembering. The first draft copied both
 * function bodies from the newest migration a GREP for the name surfaced. Both
 * were stale -- 20260810700000 had since made enqueue_job SECURITY DEFINER with
 * a pinned search_path -- so the draft silently reverted a security hardening.
 * public-api-wrapper-regression.sql caught it: public.enqueue_job (definer) no
 * longer matched its app.* counterpart (now invoker). Both bodies were rebuilt
 * from pg_get_functiondef against a fully-migrated database, each edit asserted
 * to apply exactly once and the security attributes asserted present after
 * patching. The live catalog is the source of truth for a function body, not
 * the newest file a grep finds.
 *
 * dbTestSetSha256 changed (236 files unchanged in count). background-job.sql
 * gained the request-tuple proof; data-retention-archival.sql's
 * "ZERO retention_archive jobs" assertion was scoped to its own tenant, having
 * counted globally and so depended on no other file in the shared disposable
 * database ever enqueueing one.
 *
 * Re-verified via a fresh full local db-test suite run (389 migrations, 236
 * runner files, ALL PASSED) before this digest was changed. NOT yet applied to
 * the live hosted project.
 *
 * AMENDED 2026-08-31 (fortieth pass), migrationSetSha256 ONLY. Same ruling:
 * ADR-0027 Part A.
 *
 * FIRST: the ten migrations of the thirty-first through thirty-ninth passes ARE
 * NOW APPLIED to the live hosted project (awdlicmwzdxquopwtcfd), in timestamp
 * order, each verified by querying pg_proc/information_schema for the objects it
 * creates rather than by trusting the migration ledger's own names -- deliberate,
 * because ISS-2026-300 is precisely about that ledger's naming drift. All 37
 * expected objects present.
 *
 * `ISS-2026-309` (High, CHANGE-CAUSED, mine) -- and this pass exists because
 * applying them is what exposed it. The post-apply get_advisors(security) sweep
 * returned anon_security_definer_function_executable for two functions this
 * session had just created: public.evaluate_ip_access (20260830170000) and the
 * 7-arg public.raise_observability_alert (20260830180000). Both SECURITY
 * DEFINER, both live-reachable by the anon role. One new migration
 * (389 -> 390 files: +1,
 * 20260830200000_correct_public_wrapper_grant_parity.sql).
 *
 * The cause is one line, repeated in two files:
 * `revoke execute on function public.<f>(...) from public`. `public` there is
 * the PUBLIC pseudo-role, NOT the anon and authenticated roles. Supabase ships
 * an ALTER DEFAULT PRIVILEGES rule granting EXECUTE on new public-schema
 * functions to both, explicitly, at CREATE time; the revoke never touched it.
 * Every other wrapper added this session wrote
 * `revoke ... from anon, authenticated, service_role, public` and is unaffected.
 *
 * These two were genuinely exploitable where most would not have been: they
 * carry no actor parameter and no app.assert_actor_is_session_identity guard, by
 * design, so the grant IS their access control. An unauthenticated caller could
 * probe any tenant's IP allowlist and forge incidents at any severity.
 *
 * The gate was not at fault, and this is the part worth remembering.
 * public-api-wrapper-regression.sql already asserts exhaustive, zero-tolerance
 * grant parity between every public.* wrapper and its app.* counterpart. It
 * passed because the ENVIRONMENT it runs in could not host the defect:
 * setup-disposable-db.sh created the three Supabase roles but never installed
 * Supabase's ALTER DEFAULT PRIVILEGES rule, so locally a new public.* function
 * received no anon/authenticated grant at all and parity genuinely held. A green
 * suite was telling the truth about the database it ran against, and nothing at
 * all about the one that mattered.
 *
 * setup-disposable-db.sh now mirrors the live pg_default_acl rows verbatim
 * (functions, tables and sequences on schema public, granted by postgres).
 * Guard-the-guards, run rather than asserted: with that in place and
 * 20260830200000 held aside, the suite FAILS with "7 public.* wrapper(s) have a
 * grant set that does not exactly match their app.* counterpart" -- naming
 * exactly the seven the live advisor found. Restoring the migration returns it
 * to green.
 *
 * Four of those seven are PRE-EXISTING anon widenings (the two customer-portal
 * invoice reads, the two loyalty expiry-config functions), kept separate from
 * the two change-caused ones. All four do call
 * app.assert_actor_is_session_identity, so no data was reachable; they are
 * defence-in-depth gaps, corrected in the same migration because the fix is
 * identical. The seventh is a missing service_role grant, not a wide one.
 *
 * dbTestSetSha256 deliberately UNCHANGED, and that is itself a finding worth
 * recording: scripts/db-tests/lib/setup-disposable-db.sh is not covered by that
 * digest, which spans the runner's *.sql files only. The harness that decides
 * what the frozen db-test set can even observe therefore sits outside the
 * freeze. Not widened here -- changing what the digest spans is a release-
 * authority decision, not a side effect of a security fix -- but disclosed.
 *
 * Re-verified via a fresh full local db-test suite run (390 migrations, 236
 * runner files, ALL PASSED), plus typecheck, lint and the 5,646-test unit suite,
 * before this digest was changed. 20260830200000 IS applied to the live hosted
 * project, and the live query that found the defect now returns zero wrappers
 * wider than their app.* counterpart.
 *
 * AMENDED 2026-08-31 (forty-first pass), migrationSetSha256 and dbTestSetSha256.
 * Same ruling: ADR-0027 Part A.
 *
 * `ISS-2026-186` (Medium) -- the last 6 of the RBAC boolean-oracle family, carried
 * open across three prior checkpoints. Six SECURITY DEFINER primitives granted to
 * `authenticated` (`is_supreme_admin`, `has_active_tenant_membership`,
 * `actor_holds_customer_user_layer`, `has_active_support_grant`,
 * `can_access_record`, `resolve_locale_context`) would answer a question about ANY
 * claimed identity, not just the caller's own. One new migration (390 -> 391
 * files: +1, 20260831010000_close_rbac_oracle_on_public_wrappers.sql). Closing it
 * also closed `ISS-2026-179` and `HDN-BLK-014`.
 *
 * The reason it stayed open for three checkpoints, and the reason it can be closed
 * now, are the same fact seen from opposite ends.
 *
 * Those entries concluded that the blind `assert_actor_is_session_identity`
 * pattern -- which closed the other 19 members of this family -- could not be used
 * here, because these functions ARE called with genuinely third-party actor
 * arguments (`p_owner_user_id`, `p_recipient_auth_user_id`,
 * `p_assignee_auth_user_id`) inside other definer functions. That conclusion was
 * correct, and two further facts establish it harder than the entries did:
 *
 *   1. `auth.uid()` reads the session's JWT claim and SECURITY DEFINER changes only
 *      the ROLE, so it does not go null in a nested definer call -- the assert
 *      really would fire on those legitimate uses.
 *   2. These are RLS PREDICATES. Live counts: 304 policies reference
 *      app.is_supreme_admin, 276 actor_holds_customer_user_layer, 266
 *      has_active_tenant_membership, 72 can_access_record. A policy is evaluated as
 *      the querying role, so revoking `authenticated` -- the other obvious fix --
 *      breaks ~918 policy evaluations, i.e. every protected read in the product. And
 *      a `raise` inside a policy aborts the statement rather than filtering rows.
 *
 * What all three passes missed is that none of those call sites is the attack
 * surface. Every one of them invokes the `app.*` function directly -- verified
 * exhaustively, 266 of 266 and 304 of 304 policy expressions are `app.`-prefixed,
 * zero bare references -- and `app` is not exposed to PostgREST. The oracle is
 * reachable from a browser only through the thin `public.*` wrapper. Guarding the
 * wrapper closes it and touches nothing else.
 *
 * dbTestSetSha256 changed (236 files unchanged in count): rbac-enforcement.sql
 * gained a four-property proof -- each wrapper refuses a forged actor; own-identity
 * calls still answer; anonymous pre-login locale resolution still works; and, the
 * one that matters most, the `app.*` layer must STILL answer about a third party.
 * That last assertion fails if anyone ever "tidies up" by pushing the assert down
 * into `app.*`, which would silently convert row-level denials into aborted queries
 * across the product. Guard-the-guards run rather than argued: with the migration
 * held aside the suite fails on the first property.
 *
 * Re-verified via a fresh full local db-test suite run (391 migrations, 236 runner
 * files, ALL PASSED), plus typecheck and lint, before these digests were changed.
 * 20260831010000 IS applied to the live hosted project; re-verified there that all
 * six wrappers carry the guard, the app.* layer carries none, and grants are
 * byte-identical to before.
 *
 * AMENDED 2026-08-31 (forty-second pass), migrationSetSha256 and dbTestSetSha256.
 * Same ruling: ADR-0027 Part A.
 *
 * `ISS-2026-223` (Low by its own grading, and the grading undersold it) -- five
 * file-domain call sites gated their "elevated override" on
 * app.is_support_grant_authority, whose name says "holds a live support session"
 * and whose body means "Supreme Admin OR this tenant's own tenant_admin". One new
 * migration (391 -> 392 files: +1,
 * 20260831020000_harden_file_legal_hold_provenance.sql).
 *
 * Two prior checkpoints declined to fix it, correctly: the same predicate is used
 * the same way across ~35 other migrations, and a committed db-test deliberately
 * asserts the tenant_admin-has-override behaviour. Fixing 5 of ~40 sites would have
 * produced an inconsistent model rather than a safer one.
 *
 * The ruling made here is that BOTH framings were partly right, applied to
 * different parts of the problem. The convention itself is correct and the NAME is
 * the defect: tenant_admin is the top authority inside its own tenant, while
 * support access is a separate axis for CargoGrid staff reaching into a tenant.
 * Narrowing all ~40 sites would stop a customer's own administrator from
 * administering their own files without CargoGrid opening a support session against
 * them. So ~35 call sites are untouched and the function is re-documented, not
 * renamed.
 *
 * Legal hold is the one genuine exception, because it is the one control whose
 * purpose can be to constrain the tenant itself -- and set_file_legal_hold had no
 * ordinary path at all, so the override WAS the only gate. It could not be fixed by
 * swapping predicates because the system never recorded who placed a hold, and so
 * could not tell "the tenant lifting their own litigation hold" (legitimate, and
 * exercised by the committed test) from "the tenant lifting the platform's hold on
 * them". app.files now records the placing tier and identity, and lifting requires
 * equal-or-higher authority. Unrecorded provenance ranks as supreme_admin: "someone
 * forgot to stamp it" must not become the cheapest hold to clear.
 *
 * Safe by inspection: app.files holds 0 rows and 0 held rows live, so no existing
 * hold changed meaning.
 *
 * dbTestSetSha256 changed (236 files unchanged in count): document-file.sql gained a
 * six-property proof, and the pre-existing block asserting a tenant admin placing
 * AND lifting their own hold still passes untouched, because that is equal rank --
 * which is exactly the evidence that this is a narrowing and not a lockout.
 *
 * The wrapper-parity gate caught the first draft naming its two helpers without the
 * app._* internal prefix. Re-verified via a fresh full local db-test run (392
 * migrations, 236 runner files, ALL PASSED). 20260831020000 IS applied live.
 *
 * AMENDED 2026-08-31 (forty-third pass), migrationSetSha256 and dbTestSetSha256.
 * Same ruling: ADR-0027 Part A.
 *
 * `ISS-2026-189` (Low) -- app.employees carried a 24-column SELECT grant to
 * `authenticated`, readable with no HRS:View check. Two prior passes left it open
 * because whether that is a deliberate org-directory feature or a defect is a
 * design question neither had the mandate to settle. One new migration (392 -> 393
 * files: +1, 20260831030000_revoke_unused_employee_directory_column_grant.sql).
 *
 * Ruled: it IS a directory feature and is kept -- but two of the 24 columns were
 * never directory data. probation_end_date discloses that a colleague is on
 * probation; employment_end_date discloses an unannounced departure. Taking the
 * entry's own "accept as a documented feature" option as written would have
 * accepted both along with it, which is what a blanket ruling buries.
 *
 * The full revoke was written, run against the suite, and deliberately not taken.
 * It fails on 49 lines across 5 db-test files that read app.employees while the
 * role is authenticated -- every one scaffolding that resolves a fixture id, none a
 * product path. Not taken because no product code reads the grant (zero raw
 * .from("employees") reads exist anywhere in the TypeScript), and it is not
 * browser-reachable at all: app is not exposed to PostgREST and no public.employees
 * counterpart exists. Rewriting 43 assertions' scaffolding risks quietly changing
 * what they assert, against an exposure with no browser-reachable path. The
 * measurement is recorded in the entry so a later pass can act on it without
 * re-deriving it.
 *
 * dbTestSetSha256 changed (236 files unchanged in count): hris-employee-master.sql
 * now PINS the exact 22-column granted set in both directions, plus a
 * guard-the-guard that service_role retains access -- a revoke-from-everyone "fix"
 * would otherwise satisfy every other assertion while breaking every employee RPC.
 * That guard is the part the accept-as-written option would never have produced.
 *
 * Re-verified via a fresh full local db-test run (393 migrations, 236 runner files,
 * ALL PASSED). 20260831030000 IS applied live.
 *
 * AMENDED 2026-08-31 (forty-fourth pass), migrationSetSha256 and dbTestSetSha256.
 * Same ruling: ADR-0027 Part A.
 *
 * `ISS-2026-172(b)` (Medium) -- a direct RLS read of app.files writes nothing to
 * app.file_access_logs, so "every file read is logged" was not true. One new
 * migration (393 -> 394 files: +1,
 * 20260831040000_create_logged_file_metadata_listing.sql).
 *
 * Three of that entry's own claims did not survive contact with the live schema:
 * there is no TABLE-level grant (a 26-of-29 COLUMN grant), listFilesForTenant() has
 * only test callers rather than being "real, live and exercised", and the path is
 * not browser-reachable at all (no public.files, app not exposed to PostgREST).
 *
 * Its proposed fix -- "revoke direct table SELECT entirely" -- was the wrong half,
 * and taking it would have made the product less safe. Unlike ISS-2026-189's grant,
 * this one is not vestigial: it backs files_select_scoped, and 12 db-test assertions
 * exercise that policy as `authenticated`. Revoking would make the policy dead code,
 * since nothing else reads the table as authenticated and every RPC bypasses RLS by
 * running as definer.
 *
 * What genuinely cannot be fixed is stated rather than engineered around:
 * PostgreSQL has no SELECT trigger, so a plain select cannot write an audit row by
 * any available mechanism. The schema now carries the narrower true claim -- every
 * read THROUGH THE FILE API is logged -- instead of the false general one.
 *
 * Built instead: app.list_files_for_tenant composes app.authorize_file_access per
 * row with metadata_view, so the listing is authority-checked and logged through the
 * existing decision rather than a second divergent one. An unauthorized row is
 * skipped, not raised -- aborting would be unusable and would disclose the row's
 * existence through the error. server/queries/document.ts is rewired onto it in the
 * same commit, and its client interface now speaks RPC, so a regression back to
 * .from("files") fails to type-check as well as failing tests.
 *
 * dbTestSetSha256 changed (236 files unchanged in count): document-file.sql proves
 * exactly one metadata_view log entry per returned row (count-checked, not merely
 * "wrote something"), the skip behaviour, the non-member refusal, and -- guard the
 * guard -- that the direct grant STILL exists and storage_path is STILL withheld, so
 * a later "tidy up" that revokes it fails loudly instead of quietly killing
 * files_select_scoped.
 *
 * Re-verified via a fresh full local db-test run (394 migrations, 236 runner files,
 * ALL PASSED). 20260831040000 IS applied live.
 *
 * AMENDED 2026-08-31 (forty-fifth pass), dbTestSetSha256 ONLY -- no migration was
 * added, and that is the finding. Same ruling: ADR-0027 Part A.
 *
 * `ISS-2026-170` (Low) -- app.initiate_file_upload's p_record_id was validated
 * against the tenant at neither layer. The entry scoped the fix as "enumerate every
 * record_type, verify each backing table, then write a tenant-ownership dispatch".
 * The enumeration was done and produced the OPPOSITE conclusion: the dispatch must
 * not be written.
 *
 * A BEFORE INSERT trigger on app.files was written and run against the full suite in
 * three successive designs -- tenant-enforcing, existence-only, and
 * existence-with-tenant-recorded. All three failed, always for the same reason: SEVEN
 * db-tests deliberately construct a wrongly-scoped or cross-tenant file precisely to
 * prove the CONSUMER's guard rejects it (hris-onboarding-offboarding:572,
 * hris-training-talent:451, operations-document-requirement:326,
 * procurement-vendor-assessment:797 and :946, procurement-vendor-compliance:343,
 * procurement-vendor-financial-security:674). A trigger on app.files makes every one
 * of those unconstructible -- it would remove seven real defence-in-depth assertions
 * to add one redundant with them. Strictly worse, and it would have looked like a fix.
 *
 * Two other things the enumeration turned up: `shipment` has no backing table at all
 * (there is no app.shipments; shipment_order is the entity, and production code passes
 * `shipment` anyway), and `loyalty_reward`/`employee` look like foreign keys but are
 * not -- the file is created first and the reward then stores THAT FILE's id, so
 * record_type is a category label there. Registering them failed the suite at
 * customer-loyalty-reward-catalogue.sql:819.
 *
 * What exists instead: 14 consumer-side record-scope guards. document-file.sql now
 * PINS that set, so a consumer silently losing its check fails the suite -- the
 * durable protection, since nothing on app.files backstops them.
 *
 * Residual registered separately as ISS-2026-312 rather than buried in a closed
 * entry: 3 of the 14 (contract_evidence_file_mismatch, dispute_evidence_file_mismatch,
 * document_checklist_record_mismatch) have no test proving they FIRE. Pinning proves
 * they exist, not that they work.
 *
 * Re-verified via a fresh full local db-test run (394 migrations, 236 runner files,
 * ALL PASSED).
 *
 * AMENDED 2026-08-31 (forty-sixth pass), migrationSetSha256 and dbTestSetSha256.
 * Same ruling: ADR-0027 Part A. One migration, three findings -- because they are the
 * same defect in different clothes: the data model names an owner or an approver, and
 * the authorization layer never reads it.
 * 20260831060000_close_hris_authority_shape_rulings.sql.
 *
 * `ISS-2026-068` (Medium) -- app.job_vacancies.hiring_manager_employee_id was written
 * and validated at draft time, never read back by any read RPC, so a hiring manager
 * could only see their own vacancy by holding tenant-wide HRS:View, which also shows
 * every other vacancy, candidate, application and offer. app.list_my_hiring_manager_
 * vacancies is the §26 half that was missing, built to the shape §26's OTHER half
 * already had (app.get_my_assigned_interviews): session-identity assert, explicit
 * membership gate, employee resolution, silent empty return on either miss.
 *
 * app.list_job_vacancies is deliberately NOT narrowed. The entry frames the wide read
 * as the defect; a genuine HRS:View recruiter is supposed to see the whole pipeline.
 * What was missing was the narrow path, and adding it lets a tenant grant a hiring
 * manager NO HRS permission at all instead of HRS:View -- a real reduction in what
 * tenants are forced to grant, achieved additively.
 *
 * `ISS-2026-071` (Medium) -- app.onboarding_case_tasks.owner_auth_user_id was written,
 * displayed, never checked. Two fixes pointed opposite ways. TIGHTEN (require an
 * HRS:Edit holder to also match the owner) was rejected on evidence: HRS:Edit is a
 * permission a tenant grants deliberately, an HR coordinator closing an IT-owned task
 * is ordinary correct work, every act is already audited, and there is no cross-tenant
 * or unauthenticated exposure to close. WIDEN was taken: the named owner may complete
 * their own task without HRS:Edit -- which REDUCES what a tenant must grant, since
 * today that owner needs blanket HRS:Edit to touch their own task.
 *
 * Scoped to completion alone. Not assign, reopen, waive, cancel, or the two access
 * RPCs. The shared app.resolve_onboarding_case_task_for_write preamble is unmodified,
 * so no other caller's authority moved.
 *
 * Two ways it could have gone wrong. owner_auth_user_id is nullable, so a bare
 * equality yields null on an unassigned task and `not null` is null -- the guard would
 * silently PASS. It is wrapped in coalesce(..., false), and the regression proves the
 * unassigned case is rejected. And a path whose only credential is "this row names
 * you" must prove the caller is that session: it does, because app.evaluate_permission
 * itself calls app.assert_actor_is_session_identity (ATW-031) and runs unconditionally
 * BEFORE the owner comparison. A duplicate call there would have looked more careful
 * and been less true.
 *
 * `ISS-2026-073` (Medium) -- Prompt 277 §21/§25 name an "approved direct hire"
 * precondition that no field, table or approval call implemented. §21 reads like a
 * start-time gate; §25 is explicit -- "before completion/finalization" -- so the gate
 * is at finalization, which also matches what job_offer-sourced cases already got
 * implicitly from HRT-276's offer-approval routing.
 *
 * app.record_direct_hire_approval is gated on HRS:Approve, deliberately not HRS:Edit:
 * the finding IS that starting and approving were the same permission, so an HRS:Edit
 * gate would have closed the entry while changing nothing.
 *
 * Enforcement is a table CHECK constraint, not a branch in the finalize RPC. The
 * constraint holds for every path into pending_finalize_approval/finalized -- a future
 * RPC, a service_role script, a raw UPDATE -- not only the function someone remembered
 * to edit, and it mirrors this table's own onboarding_offboarding_cases_exit_reason_
 * check shape. Added NOT VALID then VALIDATEd separately, so validation reports
 * honestly whether an already-finalized direct_hire case predates the rule instead of
 * grandfathering one. It validated clean live.
 *
 * Not enforced and stated rather than implied: segregation of duties between initiator
 * and approver. app.onboarding_offboarding_cases records its initiator as a text label,
 * not an identity, so that check cannot be made reliably; the function comment says so.
 *
 * dbTestSetSha256 changed (236 files unchanged in count): hris-recruitment-ats.sql
 * proves the assigned slice on the fixture's genuinely zero-permission hiring manager
 * (asserted, not assumed), through a forged session, with cross-tenant silence and an
 * identity-mismatch rejection. hris-onboarding-offboarding.sql proves the owner path
 * end to end (denied assigning, allowed completing their own, denied on an UNASSIGNED
 * task, denied reopening, HRS:Edit still completes anyone's) and proves the direct-hire
 * constraint AROUND the RPC layer entirely, by raw UPDATE.
 *
 * Re-verified via a fresh full local db-test run (395 migrations, 236 runner files,
 * ALL PASSED). 20260831060000 IS applied live; the constraint is convalidated.
 *
 * AMENDED 2026-08-31 (forty-seventh pass), migrationSetSha256 and dbTestSetSha256.
 * Same ruling: ADR-0027 Part A. `ISS-2026-147`, both items.
 * 20260831070000_add_connector_scoped_execution_log_filters.sql.
 *
 * Item 1 ("zero test coverage for the 9 /api/v1 REST route handlers") is closed on
 * re-derived evidence rather than on a claim: there are 9 handlers under app/api/v1/ and
 * 9 matching files under tests/api/v1/, one per handler, each confirmed to correspond.
 * Work that had already closed it never updated the entry.
 *
 * Item 2 was the real one. IAE-013's own migration comment claimed per-connector
 * execution-log filtering; the 2026-08-28 re-verification sharpened the finding correctly
 * -- this was never "under-evidenced", the capability did not exist at any layer. Neither
 * app.list_api_logs_for_tenant nor app.list_webhook_deliveries_for_tenant accepted any
 * connector-identifying filter, so a tenant admin running several integrations saw every
 * connector's history interleaved with no way to isolate one.
 *
 * Each function gains one optional trailing filter -- p_api_key_id on the REST/GraphQL
 * half (an integration authenticates with its own key) and p_webhook_endpoint_id on the
 * webhook half (one integration, one endpoint URL). Both via DROP + CREATE, never
 * CREATE OR REPLACE: appending even a defaulted parameter produces a SECOND overload and
 * makes every existing call site ambiguous, the defect ISS-2026-260 found the hard way.
 *
 * The filter is validated, not silently ignored. A key or endpoint id belonging to another
 * tenant would otherwise return an empty list -- a usable oracle, since "empty" would mean
 * "not mine" and a caller could walk ids to learn what exists elsewhere. Both raise a
 * not-found that is byte-identical for a foreign id and for one that exists nowhere.
 *
 * Caught during this pass and worth recording rather than quietly fixing: the first draft
 * wrote `revoke execute ... from public` on the two new public.* wrappers and
 * public-api-wrapper-regression.sql failed them as privilege-widening. `revoke ... from
 * public` removes only the PUBLIC pseudo-role, while Supabase's ALTER DEFAULT PRIVILEGES
 * grants `anon` EXECUTE explicitly at CREATE time -- an explicit grant a PUBLIC revoke does
 * not touch. That is precisely how ISS-2026-309 shipped two anon-executable SECURITY
 * DEFINER wrappers. The gate caught it here on the first run, which is the gate working.
 *
 * The UI half is wired too, so the capability is reachable rather than merely present:
 * the api-keys admin console reads a UUID-shape-checked search param and renders a link
 * filter bar per section. Links, not client-side selection, so a filtered view stays
 * addressable and back-button-correct. Ownership is deliberately NOT re-checked in the
 * page -- the RPC owns that rule, and a second copy would drift.
 *
 * dbTestSetSha256 changed (236 files unchanged in count): public-api-platform.sql proves
 * a second real key's history is isolated, composes with the existing cursor, leaves the
 * unfiltered default intact, and refuses a foreign key id; webhook-management.sql proves
 * the same shape per endpoint, including that not one returned row belongs to the other
 * endpoint (stronger than counting) and that the endpoint and status filters both apply.
 * Both foreign-id controls are created by the block itself rather than picked out of
 * whatever another test file left in the shared database first.
 *
 * Re-verified via a fresh full local db-test run (396 migrations, 236 runner files,
 * ALL PASSED).
 *
 * AMENDED 2026-08-31 (forty-eighth pass), migrationSetSha256 and dbTestSetSha256.
 * Same ruling: ADR-0027 Part A. `ISS-2026-086`, the RBAC-model decision three passes
 * correctly declined to make under a bounded mandate.
 * 20260831080000_split_ticket_admin_content_override_permission.sql.
 *
 * app.is_ticket_staff granted full ticket-content staff status -- every internal note,
 * replies, queue transfer, reclassify -- to any TKT:Edit holder, on EVERY ticket in the
 * tenant, unscoped by queue. 20260731060000's own decision-5 comment says the opposite:
 * TKT:Edit is "reserved for QUEUE/CATEGORY CONFIGURATION ... not for ordinary ticket work."
 * A tenant granting TKT:Edit for queue administration silently and inseparably handed over
 * every ticket's contents, ISS-2026-111's HRS-masked-data-quoted-into-a-ticket case
 * included, with no way to revoke one half without the other.
 *
 * The ruling is the split this entry itself names. TKT:Edit keeps configuration and
 * on-behalf creation; the tenant-wide content override moves to TKT:Override, separately
 * grantable and separately revocable. Keeping the blanket form was rejected on what it
 * costs a tenant: a permission that cannot be granted for its stated purpose without also
 * handing over every ticket's contents is not one a careful administrator can use.
 *
 * `Override`, not a freshly-invented action name, and that is not cosmetic. The first draft
 * seeded TKT:Administer and was rejected on its first run by app.permissions_action_check --
 * a FIXED 20-value enum reproduced from docs/architecture/06_RLS_RBAC_WORKSTREAM.md §5.1, a
 * canonical catalogue rather than a list to append to. The constraint was doing its job.
 * `Override` is already in it, already means "act outside the normal scope" for OPS and FIN,
 * and is exactly what a queue-unscoped tenant-wide content override is.
 *
 * One function changed, not twenty-five. TKT:Edit gates ~25 configuration RPCs across
 * queues, categories, SLA and the knowledge base; moving all of them would have been the
 * shared-schema redesign this entry rightly warned a bounded pass away from. Adding the
 * override grant achieves the same separation by touching app.is_ticket_staff alone.
 *
 * app.redact_ticket_message is deliberately NOT moved and still gates on TKT:Edit. Raising
 * it for consistency would mean a tenant has to hand somebody every ticket's contents before
 * they may scrub a leaked-PII message -- worse than the problem being fixed. Redaction
 * destroys, it does not reveal.
 *
 * Migration safety measured, not assumed: the live project holds 0 tenants, 0 tickets, 0
 * active role assignments and 0 role versions carrying TKT:Edit, so nobody lost access. The
 * backfill is written anyway and is a live no-op -- every role version already granting
 * TKT:Edit also gains TKT:Override, so any environment WITH data keeps every holder's
 * effective access byte-for-byte.
 *
 * dbTestSetSha256 changed (236 files unchanged in count): ticketing-internal.sql proves a
 * TKT:Edit-only identity is NOT staff on a queue it does not belong to, that adding
 * TKT:Override makes it staff, and -- the half the finding is about -- that revoking
 * TKT:Override alone removes content access while leaving TKT:Edit configuration authority
 * intact. The fixture this entry named as the blocker (ticketing-internal.sql:593, staff1
 * replying after a queue transfer) was updated rather than worked around: it now grants
 * TKT:Override explicitly, which is the point. Eight further service-desk-admin fixtures
 * were updated the same way; ticketing-escalation.sql failed first and revealed the set.
 *
 * Re-verified via a fresh full local db-test run (397 migrations, 236 runner files,
 * ALL PASSED).
 *
 * AMENDED 2026-08-31 (forty-ninth pass), migrationSetSha256 and dbTestSetSha256.
 * Same ruling: ADR-0027 Part A. The automatic task scheduler.
 * 20260831090000_create_tenant_configurable_task_scheduler.sql, plus the first new
 * db-test runner file this freeze has taken (task-scheduler.sql, 236 -> 237).
 *
 * Eleven backlog entries shared one sentence -- some form of "on-demand/staff-triggered
 * only; no automatic job wires this up". The sweeps all existed and all worked; nothing
 * ever called them on a timer.
 *
 * Why that was not a cron entry: every sweep takes p_actor_auth_user_id and most are
 * evaluate_permission-gated, and a cron job has no identity. Minting a second top-privilege
 * platform identity for the scheduler was put to the project owner and REJECTED. The owner's
 * own direction shaped what was built instead -- CargoGrid is configurable by Supreme Admin,
 * per tenant, with access delegable to a tenant's own admin -- so: Supreme Admin owns a
 * catalogue of schedulable tasks and a per-task delegation switch, and a scheduled run
 * executes AS THE REAL PERSON who authorized the schedule, their authority re-checked every
 * run. Nothing is minted and nothing runs as "the system".
 *
 * The consequences are deliberate: an authority failure is a distinct outcome from any other
 * error, three consecutive ones auto-disable the schedule with the reason recorded, and
 * re-authorizing means somebody with current authority reconfigures it, which re-stamps the
 * identity as theirs. A departed employee's stale schedule becomes a visible dead row rather
 * than permanent nightly noise.
 *
 * Two gates caught real defects in the first draft, both worth recording rather than quietly
 * fixing. public-api-wrapper-regression.sql failed two functions with no public.* wrapper --
 * fixed by app._ prefixing the internal predicate (a helper with no independent meaning should
 * not become a REST endpoint) and giving the runner a service_role-only wrapper. And
 * scripts/security/check-rls-initplan.ts failed both new RLS policies for a bare auth.uid(),
 * which is re-evaluated per row; both now use (select auth.uid()).
 *
 * Honest scope, recorded in the entries themselves rather than claimed here: this closes the
 * scheduler ITEM in ISS-2026-066 and the expiry half of ISS-2026-129. It does NOT close
 * ISS-2026-070, 126, 127 or 132, because those need sweep functions that do not exist
 * (an onboarding-overdue sweep, a tenant-wide tier recalculation) or an event trigger rather
 * than a timer. A scheduler can only run sweeps that exist.
 *
 * Nothing is scheduled on the live project: pg_cron remains uninstalled, and attaching a
 * trigger to app.run_due_scheduled_tasks is a deliberate operator step.
 *
 * ISS-2026-313 registered by this same pass: enumerating pg_proc afterwards found four more
 * tenant-wide sweeps of exactly the right shape that the catalogue does not carry, because it
 * was seeded from what the backlog complained about rather than from what the schema offers.
 *
 * Re-verified via a fresh full local db-test run (398 migrations, 237 runner files,
 * ALL PASSED). 20260831090000 IS applied live and object-verified.
 *
 * AMENDED 2026-08-31 (fiftieth pass), migrationSetSha256 and dbTestSetSha256.
 * Same ruling: ADR-0027 Part A. ISS-2026-249 (High, both remaining producers) and
 * ISS-2026-313, in one migration:
 * 20260831100000_close_authority_denial_alerting_and_scheduler_catalogue_gap.sql.
 *
 * ISS-2026-249's own diagnosis was right and understated the obstacle by one step, which is
 * why three passes could not close it. The blocker was never volatility: a database function
 * that RAISES cannot durably record the denial it raises on, because the INSERT and the RAISE
 * share a transaction. Making app.assert_current_step_up_authorization volatile would have let
 * it insert and still recorded nothing. 20260827000000 was already working around exactly this
 * when it placed every alert call "before that branch's own normal return, never before a raise
 * exception" -- the entry just never named it.
 *
 * Two problems, two answers. DURABILITY: app.authority_denials is written from OUTSIDE the
 * refused transaction, by the boundary that catches the error (server/policies/
 * authority-denial-recorder.ts), in a fresh statement after the rollback -- the only point in
 * the stack where "this call was refused" both exists and can be written down. THE FLOOD, which
 * is the half that actually mattered: app.run_authority_denial_anomaly_sweep alerts on a BURST,
 * not per denial. One refusal raises nothing; an identity crossing the threshold inside a window
 * raises exactly one incident, deduplicated on that identity, escalating to high when the
 * refusals span more than two modules (breadth reads as probing; one module usually means a role
 * that needs granting).
 *
 * The step-up producer closes as a consequence rather than needing its own machinery -- a better
 * outcome than the new log table plus volatility change the entry proposed. app.evaluate_
 * permission RETURNS mfa_step_up_required as a reason rather than raising (ISS-2026-236), so a
 * step-up refusal arrives as an ordinary insufficient_authority error carrying that reason and is
 * classified apart by classifyDenial. The unit tests pin that classification, so a change folding
 * step-up back into plain rbac fails rather than silently re-opening the producer.
 *
 * The recorder never throws: a failed observability write must not turn a clean "you may not do
 * that" into a 500. It also stays silent for stale_version and other non-refusals, so ordinary
 * optimistic-concurrency retries never reach the burst detector.
 *
 * ISS-2026-313 closes in the same migration: the four sweeps the scheduler catalogue was seeded
 * without, plus this pass's own denial sweep, take it from 11 tasks to 16, each with an explicit
 * dispatch branch. task-scheduler.sql's catalogue walk exercises all 16 and fails on any row
 * without a branch.
 *
 * ISS-2026-314 registered by this pass rather than dismissed: scheduled-reports.sql's two-OS-
 * process concurrency assertion failed once mid-batch and passed on the runs either side of it,
 * with no related change. Its message names a real correctness property (a double-advance skips a
 * due occurrence), and the evidence available cannot distinguish "the product races" from "the
 * test's process synchronisation is fragile". Calling it a flake would assume the second without
 * evidence. The suite is green on the committed state, and that is stated rather than implied.
 *
 * Re-verified via a fresh full local db-test run (399 migrations, 237 runner files,
 * ALL PASSED). 20260831100000 IS applied live and object-verified: 16 catalogue tasks, the
 * denial ledger present with one RLS policy, zero anon EXECUTE on either new function.
 *
 * AMENDED 2026-08-31 (fifty-first pass), migrationSetSha256 and dbTestSetSha256.
 * Same ruling: ADR-0027 Part A. ISS-2026-207.
 * 20260831110000_give_api_version_registry_live_effect.sql.
 *
 * app.api_versions was a real, audited, Supreme-only state machine, wired into the admin
 * console and covered by passing db-tests -- and completely inert. Live-forced at HDN-008:
 * mark v1 deprecated, then sunset with a real future date, then call the gateway with an
 * otherwise valid key, and it still returned outcome=ok.
 *
 * The decision deliberately did NOT go into app.authenticate_and_authorize_api_request.
 * Version state is not an authentication fact: RFC 8594 says a deprecated endpoint still
 * answers normally and carries Deprecation/Sunset headers, so folding it into the auth outcome
 * would force a choice between denying a request that should succeed and returning ok while
 * losing the signal. The registry needs three answers; an auth outcome has room for two.
 *
 * The judgement call, recorded because it is one: a version marked sunset with a FUTURE
 * sunset_at is still served. set_api_version_status requires a real date precisely so clients
 * are warned before the date; refusing when the status flips would turn the announcement into
 * the outage it exists to prevent.
 *
 * TWO DRAFT DEFECTS, both caught before shipping and both worth recording.
 *
 * First, the query wrapper originally failed CLOSED, returning gone on an unreadable registry.
 * Wrong direction: 410 means PERMANENTLY gone, so emitting it because a SELECT blipped would
 * tell every integrator the endpoint had been withdrawn and well-behaved clients would stop
 * calling -- a transient error becoming a sticky outage across every integration at once. It
 * now fails open, which costs nothing real because authentication reads the same database and
 * fails honestly on its own. An unknown code is still refused: the SQL returns a real gone row
 * for it rather than an error.
 *
 * Second, the function was granted to authenticated as well as service_role, and
 * rbac-enforcement.sql's ISS-2026-033 sweep failed it -- a SECURITY DEFINER function reachable
 * by authenticated with no authority check in its call graph. The gate offers two exits (add a
 * check, or justify it on the reviewed list); a third was better, since the only caller is the
 * gateway running as service_role. The narrower grant removes the question instead of answering
 * it, and the db-test now pins authenticated at zero as well as anon.
 *
 * Also fixed, because it would have made the new tests lie: the route-test harness 404s an
 * unregistered RPC and the new query fails open, so all nine existing route tests would have
 * passed while silently exercising the failure path instead of the registry. The stub now
 * defaults evaluate_api_version_request to an active v1.
 *
 * dbTestSetSha256 changed (237 files unchanged in count): public-api-platform.sql proves all
 * five registry states drive the right decision, that the fixture never disturbs v1, and that
 * the evaluator is service_role-only on both schemas.
 *
 * Re-verified via a fresh full local db-test run (400 migrations, 237 runner files,
 * ALL PASSED). 20260831110000 IS applied live and verified: v1 -> ok, unknown -> gone, zero
 * anon or authenticated EXECUTE on either schema.
 *
 * AMENDED 2026-08-31 (fifty-second pass), migrationSetSha256 and dbTestSetSha256.
 * Same ruling: ADR-0027 Part A. ISS-2026-091 and ISS-2026-142 together.
 * 20260831120000_create_data_retention_and_legal_hold_registry.sql, plus a new runner file
 * (data-retention-legal-hold.sql, 237 -> 238).
 *
 * Both entries say RPD-025 retention/legal-hold classification is unbuilt, and both propose
 * retention_class/legal_hold columns on every affected table. That was MEASURED and rejected:
 * the live schema carries 615 tables in app. A column-per-table fix would leave ~500 silently
 * ungoverned, make adding a table to governance a migration rather than a policy decision, and
 * -- decisively -- be structurally unable to express the most common real hold, since a per-row
 * boolean can only speak about a row that already exists while a hold usually arrives as
 * "preserve everything about this customer" before anybody knows which rows that means.
 *
 * So classification is a registry keyed by table, and a hold is a RECORD WITH A SCOPE whose
 * nulls widen it: a record, a table, a tenant, the platform. app.is_record_under_legal_hold is
 * the predicate any future purge must consult, and it answers correctly for a record that did
 * not exist when the hold was placed.
 *
 * review_status is the load-bearing field and exists because of ISS-2026-091's own warning
 * against a copy-paste default. No migration can answer that warning -- the mapping is a legal
 * judgement about a particular business in a particular jurisdiction -- so all 112 seeded rows
 * are provisional, and a table CHECK constraint makes a confirmed row impossible without a named
 * reviewer, so not even a service_role UPDATE can manufacture the assurance. Changing a class
 * resets the review.
 *
 * It deliberately deletes nothing. A generic sweeper deleting across 615 tables driven by a
 * config table would be the most dangerous thing in this repository. Classification, holds, the
 * predicate and a coverage report ship; destruction stays a human-reviewed act per table.
 *
 * The coverage report keeps provisional and confirmed apart rather than reporting one
 * "classified" number, because collapsing them would let a wall of unreviewed defaults read as
 * compliance -- the precise failure both entries warn about.
 *
 * Wrapper parity caught two functions with no public.* wrapper, resolved differently on purpose:
 * the unclassified-table lister is an internal helper of the coverage report and was renamed
 * app._list_unclassified_tables (the underscore exempts it, correctly -- it should not become a
 * REST endpoint), while the hold predicate is a real API any purge must call and got a
 * service_role-only wrapper instead.
 *
 * Re-verified via a fresh full local db-test run (401 migrations, 238 runner files,
 * ALL PASSED). 20260831120000 IS applied live and verified: 112 tables classified (23
 * HR/payroll-family, 12 Loyalty-ledger) of 618, 0 confirmed, 0 anon EXECUTE.
 *
 * AMENDED 2026-08-31 (fifty-third pass), migrationSetSha256 and dbTestSetSha256.
 * Same ruling: ADR-0027 Part A. ISS-2026-231.
 * 20260831130000_backstop_malware_scan_resolution_invariant.sql.
 *
 * app.record_file_scan_result enforces document_scan_already_resolved; nothing else did, so a
 * raw service_role UPDATE could silently un-quarantine an infected file. A BEFORE UPDATE trigger
 * with an is_supreme_admin(auth.uid()) bypass had been drafted and correctly abandoned: it broke
 * five deliberately-designed tests whose raw re-flags run with NO session actor at all.
 *
 * The entry concluded this needed "reconciling two incompatible models of who may perform an
 * out-of-band RPD-022 correction". That framing is what kept it stuck. They do not need
 * reconciling -- they need DISTINGUISHING, and no actor inspection can do it, because at the
 * moment of the UPDATE a legitimate service-level correction and a hostile raw write are
 * byte-identical: the legitimate one has no actor by definition, and so does an attacker who has
 * reached service_role.
 *
 * So intent is DECLARED, not inferred: `set local app.scan_correction_reason = '<why>'`.
 * Undeclared, the transition is refused. Declared, it is allowed AND recorded in
 * app.file_scan_corrections by the trigger itself -- which turns the honest-but-invisible thing
 * RPD-022 already permitted into an honest and visible one. A transaction-scoped GUC is the right
 * carrier: an ordinary authenticated session cannot set one through PostgREST, and `set local`
 * cannot leak past its own transaction to bless a later, unrelated write.
 *
 * The five tests were not broken, they were made to say what they already meant -- their intent
 * was documented in prose at every call site and was indistinguishable TO THE DATABASE from an
 * unauthorized write. (The entry names four; there are five. document-file.sql was not listed.)
 *
 * Two cases deliberately left alone, because widening the guard would turn a security fix into
 * an outage: pending -> resolved (the normal path) and a no-op same-value update. Both are
 * asserted, so a later tightening cannot break ordinary writes unnoticed.
 *
 * Re-verified via a fresh full local db-test run (402 migrations, 238 runner files,
 * ALL PASSED). 20260831130000 IS applied live: trigger and ledger table both confirmed present.
 *
 * AMENDED 2026-08-31 (fifty-fourth pass), migrationSetSha256 only -- dbTestSetSha256 is
 * unchanged, because ISS-2026-238's evidence is TypeScript-side (the caps are asserted in unit
 * tests against recorded .range()/p_limit values, where a dropped cap actually shows up).
 * Same ruling: ADR-0027 Part A. 20260831140000_bound_logged_file_listing.sql.
 *
 * Four production routes fetched an entire tenant-wide dataset into the browser with no cap.
 * server/queries/bounded-list.ts is the convention in one place, at 200 -- the same number the
 * RPC layer already uses, because two caps in one product is a difference a reader must learn
 * for no benefit.
 *
 * The functions return a BoundedList rather than an array, and that type change IS the fix. A
 * silently capped list is worse than an unbounded one: unbounded is slow, silently capped is
 * WRONG, because the reader believes they are seeing everything. Changing the type forced every
 * caller to decide what to say about it.
 *
 * A correctness bug this nearly introduced, caught before it shipped: the account DETAIL page
 * resolved an account's parent and subsidiaries by filtering the full tenant list in memory.
 * Capping that would have made the page silently wrong rather than truncated -- a parent outside
 * the newest 200 rendering as "no parent". It now uses two targeted queries, which was always
 * the right shape; the cap is what made that obvious.
 *
 * The fourth route needed a different truncation detector, and the reason is worth recording.
 * app.list_files_for_tenant writes an app.file_access_logs row PER ROW RETURNED, so the usual
 * fetch-one-past-the-cap trick would leave a log entry claiming somebody viewed a file they were
 * never shown. toBoundedListByCapReached infers truncation from reaching the cap instead --
 * conservative by one row, never dishonest about who saw what. The migration clamps rather than
 * rejects an over-large limit (failing a page is a worse answer than serving 200, especially
 * when the alternative is writing 100,000 audit rows) and counts rows RETURNED, exiting before
 * the next authorize call so a skipped unauthorized row costs nothing.
 *
 * The ~10 lower-severity siblings are deliberately NOT capped: each reads a config/rule/rate/
 * directory-shaped table naturally bounded by business cardinality, as the entry itself says.
 * Capping them would add a truncation notice to lists that never truncate, and a warning nobody
 * can act on teaches people to ignore warnings.
 *
 * Re-verified via a fresh full local db-test run (403 migrations, 238 runner files,
 * ALL PASSED). 20260831140000 IS applied live: 2 functions, zero anon EXECUTE.
 *
 * Also corrected in the same pass, outside the digests: the four migrations applied
 * live on 2026-08-31 via apply_migration had been recorded in
 * supabase_migrations.schema_migrations under the MCP tool's own wall-clock version
 * (e.g. 20260831032450) rather than their repo filename version, silently
 * re-introducing the ledger drift the 84-row reconciliation had just closed. All four,
 * plus this pass's own, were remapped to their filename versions under an
 * in-transaction assertion requiring exactly 5 remapped rows; ledger and repo now agree
 * again, so `supabase db push` cannot re-run any of them.
 */
export interface FrozenCandidate {
  readonly id: string;
  readonly migrationSetSha256: string;
  readonly dbTestSetSha256: string;
  readonly lockfileSha256: string;
}

export const FROZEN_CANDIDATE: FrozenCandidate = {
  id: "RC-2026.08.25-1",
  // History: 15f6e7049105f751c6226bef49520bf035e32fad9418d2247ba2c968172a59ac
  // (333 files, RGL-392's original freeze). Superseded 2026-08-25 by the
  // RGL-BLK-002 remediation's new migration (334 files: +1,
  // 20260826000000_create_public_api_data_wrappers.sql, 2367 public.* wrapper
  // functions).
  // History: a9c11bdb1f266f90c29d3697fc3e05526b47379bf95491d1ca27f34a882b0b29
  // (334 files, first-pass amendment above). Superseded 2026-08-25 (second
  // pass) by the same remediation's own Tier C self-correction (335 files: +1,
  // 20260826010000_harden_public_api_data_wrappers_tierc_fixes.sql, closing
  // ISS-2026-291/ISS-2026-292).
  // History: be34c20ff211d741ca043414ffb4bf8d7cd7a6b17fd6d1e525ce39663cd82a4b
  // (335 files, second-pass amendment above). Superseded 2026-08-25 (third
  // pass) by RGL-394's own RGL-BLK-004 fix (336 files: +1,
  // 20260826020000_harden_vendor_kpi_rate_validity_window_calc.sql). See the
  // class-level doc comment above.
  // History: 5fc5907adfa0b06061b9ebd31b8019272ebecdaee2d00e9c92faf48a79726378
  // (336 files, third-pass amendment above). Superseded 2026-08-25 (fifth
  // pass) by RGL-404's own RGL-BLK-009 fix (337 files: +1,
  // 20260826030000_harden_finance_settlement_reversal_gl_journal_and_
  // reachability.sql). See the class-level doc comment above.
  // History: 9c4f956ebc7b29c6f1dcfe2bcc31f20676ba20ccb7718f7cc2c74f785e8df78e
  // (337 files, fifth-pass amendment above). Superseded 2026-08-25 (sixth
  // pass) by the historical-issue-backlog remediation's ISS-2026-072 fix
  // (338 files: +1, 20260826040000_harden_rbac_evaluator_platform_user_
  // status_check.sql). See the class-level doc comment above.
  // History: 07611ff2691d0e1e48937062a1d84e3a3bb4fe26ff019dd49e325a516c32d703
  // (338 files, sixth-pass amendment above). Superseded 2026-08-25 (seventh
  // pass) by the historical-issue-backlog remediation's ISS-2026-257 fix
  // (339 files: +1, 20260826050000_harden_integration_secrets_encryption_
  // at_rest.sql). See the class-level doc comment above.
  // History: bfa32177ec2cd98323484c900e32c94175d102a7aaf378854061f56c2d684408
  // (339 files, seventh-pass amendment above). Superseded 2026-08-25 (eighth
  // pass) by the historical-issue-backlog remediation's ISS-2026-265 fix (340
  // files: +1, 20260826060000_harden_database_restore_audit_trail.sql). See
  // the class-level doc comment above.
  // History: 9ed06519551ea6bad34bcbd4cb0084b3b5a4c9df2e83bcd4cca1dad96f1271ba
  // (340 files, eighth-pass amendment above). Superseded 2026-08-25 (ninth
  // pass) by the historical-issue-backlog remediation's ISS-2026-269 fix (341
  // files: +1, 20260826070000_harden_employee_import_duplicate_detection.sql).
  // See the class-level doc comment above.
  // History: 129a7340fe49515b3c11aa34a604cc79446f4848c82eece13772124b85fc2c4a
  // (341 files, ninth-pass amendment above). Superseded 2026-08-25 (tenth
  // pass) by the historical-issue-backlog remediation's ISS-2026-254/
  // ISS-2026-298/ISS-2026-299 fix (344 files: +3, 20260826080000_harden_
  // restore_security_state_reconciliation.sql, 20260826081000_harden_record_
  // database_restore_event_wrapper_grant_leak.sql, and 20260826090000_harden_
  // security_state_snapshots_table_privilege_leak.sql). See the class-level
  // doc comment above.
  // History: 15c04e9af0c803e83ed66f188f1d16109275afc97476776e44720b73916f5a16
  // (344 files, tenth-pass amendment above). Superseded 2026-08-25 (eleventh
  // pass) by the historical-issue-backlog remediation's ISS-2026-263 fix (345
  // files: +1, 20260826100000_harden_user_status_transition_invalid_event_
  // type.sql). See the class-level doc comment above.
  // History: 0593e6a0e53ee7abdb92c0bf0838b423f15f20c16a28c44d2cb072457d16a33f
  // (345 files, eleventh-pass amendment above). Superseded 2026-08-25
  // (twelfth pass) by the historical-issue-backlog remediation's
  // ISS-2026-264 fix (346 files: +1,
  // 20260826110000_harden_evaluate_permission_session_revocation_
  // enforcement.sql). See the class-level doc comment above.
  // History: 578757a56b8dd35e88216a2c7df91b0937d9678129131ef7068f54b23ca486e1
  // (346 files, twelfth-pass amendment above). Superseded 2026-08-25
  // (thirteenth pass) by the historical-issue-backlog remediation's
  // ISS-2026-266 fix (347 files: +1,
  // 20260826120000_harden_restore_materialized_view_refresh_completeness.sql).
  // See the class-level doc comment above.
  // History: 6bf6ec92c95de4e62a618acd9979f8349ffc3096d42faf9bd6d79d43de0a1dd5
  // (347 files, thirteenth-pass amendment above). Superseded 2026-08-25
  // (fourteenth pass) by the historical-issue-backlog remediation's
  // ISS-2026-270 fix (348 files: +1,
  // 20260826130000_create_reference_data_import_registration.sql). See the
  // class-level doc comment above.
  // History: cfb96c5e91cc5ca6018f0a5096cd9c17cc1d77f07168f84865414c06e17ef4c6
  // (348 files, fourteenth-pass amendment above). Superseded 2026-08-25
  // (fifteenth pass) by the historical-issue-backlog remediation's
  // ISS-2026-272 fix (349 files: +1,
  // 20260826140000_create_migration_rehearsal_tracking.sql). See the
  // class-level doc comment above.
  // History: 76faad22b3899f5ed7f96a09fe83a3863ee0737a3ca0c6234910e6bb9c276358
  // (349 files, fifteenth-pass amendment above). Superseded 2026-08-25
  // (sixteenth pass) by the historical-issue-backlog remediation's
  // ISS-2026-271 fix (350 files: +1,
  // 20260826150000_create_employee_import_rollback.sql). See the
  // class-level doc comment above.
  // History: 855f12fb61bcd39b8d160f9038cb4682d4c6f214b5e6d9cf8d15829b0768db73
  // (350 files, sixteenth-pass amendment above). Superseded 2026-08-27
  // (seventeenth pass) by the historical-issue-backlog remediation's
  // ISS-2026-275/ISS-2026-276 fix (351 files: +1,
  // 20260826160000_create_finance_journal_historical_import.sql). See the
  // class-level doc comment above.
  // History: 6ac79f37937d6011fc19c49341dbd9d3c9c3958523aaf7eeb4e3cf0aad9a4820
  // (351 files, seventeenth-pass amendment above). Superseded 2026-08-27
  // (eighteenth pass) by the historical-issue-backlog remediation's
  // ISS-2026-279 fix (352 files: +1,
  // 20260826170000_harden_employee_import_number_normalization_detection.sql).
  // See the class-level doc comment above.
  // History: c91908161eb1fd75911be833555d5ce29cd144e2993ee7b31d99f8a2cc11b780
  // (352 files, eighteenth-pass amendment above). Superseded 2026-08-27
  // (nineteenth pass) by the historical-issue-backlog remediation's
  // ISS-2026-260 fix (353 files: +1,
  // 20260826180000_create_dr_restore_scenario_taxonomy.sql). See the
  // class-level doc comment above.
  // History: 6fac78cbabdd98b6780cc815e8d9e0a952895741f4d2da14b8170d2161c42ed4
  // (353 files, nineteenth-pass amendment above). Superseded 2026-08-27
  // (twentieth pass) by the historical-issue-backlog remediation's
  // ISS-2026-278 fix (354 files: +1,
  // 20260826190000_harden_import_commit_ip_allowlist_gating.sql). See the
  // class-level doc comment above.
  // History: cc91b1907804884cba268a6911e6cb02d82124eceecdc5ce3bfc335a1488f47d
  // (354 files, twentieth-pass amendment above). Superseded 2026-08-27
  // (twenty-first pass) by Track B Batch 1's ISS-2026-249/167/176 fixes
  // (357 files: +3, 20260827000000_wire_observability_alert_producers.sql,
  // 20260827010000_harden_cross_tenant_error_disclosure_representative.sql,
  // 20260827030000_harden_analytics_refresh_runs_grant.sql). See the
  // class-level doc comment above.
  // History: 38f3969a786380bbbd4a5645cc81667f0da7c96633192400c079ad418ed067fa
  // (357 files, twenty-first-pass amendment above). Superseded 2026-08-27
  // (twenty-second pass) by Track B Batch 2's ISS-2026-044/043/048/049
  // fixes (359 files: +2,
  // 20260827110000_harden_request_approval_unique_violation_handler.sql,
  // 20260827130000_harden_tenant_disclosure_representative_extension_batch2.sql).
  // History: 8a5b26a13dad1db0db102030e4d4da13b0bf0bc4c4e2681b0486d65b0728b989
  // (359 files, twenty-second-pass amendment above). Superseded 2026-08-28
  // (twenty-fourth pass) by Track B Batch 4's ISS-2026-116/117/124/128/133/
  // 134/137 fixes (366 files: +7, 20260827140000, 20260828000000,
  // 20260828030000, 20260828040000, 20260828050000, 20260828060000,
  // 20260828070000).
  // History: 9a1fecf2af2f4ab64f64b67a10d4773b3979ab0711c457dcab3587dba09541c9
  // (366 files, twenty-fourth-pass amendment above). Superseded 2026-08-28
  // (twenty-fifth pass) by Track B Batch 5's ISS-2026-149/152 fixes
  // (368 files: +2, 20260828090000, 20260828100000). See the class-level
  // doc comment above.
  // History: afbf205da403b240c532b861aac219391f790024aa56254fbc751f3e1b0553e3
  // (368 files, twenty-fifth-pass amendment above). Superseded 2026-08-28
  // (twenty-sixth pass) by Track B Batch 6's ISS-2026-187/188/177/186/102
  // fixes (372 files: +4, 20260828110000_harden_support_session_gates_
  // active_grant.sql, 20260828111000_harden_support_session_open_audit_
  // trail.sql, 20260828121000_harden_shared_record_scope_primitives_actor_
  // identity.sql, 20260828140000_harden_customer_ticket_links_entity_id_
  // registry_redaction.sql).
  // History: ac5fba0df49a0777dc05745dbf00ab2b706ce3cd8040cdddaf7a72cc70cd5ef0
  // (372 files, twenty-sixth-pass amendment above). Superseded 2026-08-28
  // (twenty-seventh pass) by Track B Batch 7's ISS-2026-203/206/213/224/231
  // fixes (377 files: +5, 20260828150000_harden_job_order_snapshot_source_
  // lineage.sql, 20260828151000_harden_inventory_movement_reservation_
  // source_lineage.sql, 20260828160000_harden_self_approval_null_actor_
  // fail_open.sql, 20260828171000_harden_vendor_evidence_reviewer_record_
  // scope.sql, 20260828173000_harden_files_malware_scan_raw_correction_
  // audit.sql).
  // History: 2f8b8c272e6b00db9132dc954786f0e2337b7e8a7386b0e15db16f7d57106d18
  // (377 files, twenty-seventh-pass amendment above). Superseded 2026-08-28
  // (twenty-eighth pass) by Track B Batch 8's ISS-2026-125/259 fixes (379
  // files: +2, 20260828193000_harden_customer_portal_last_account_admin_
  // status_guard.sql, 20260828200000_create_raw_mutation_tripwire.sql).
  // History: c2caf7cec32d7dc08535ee11f477e01f3c3ed7a2c0ec14b26a746a1ca4707d26
  // (379 files, twenty-eighth-pass amendment above). Superseded 2026-08-30
  // (twenty-ninth pass) by ISS-2026-057's vendor bulk-import adapter (380
  // files: +1, 20260830100000_create_vendor_import_adapter.sql).
  // History: 0430b50b46eadaaf5d0c45c28e68c2a15c79c1784d5e84c132d991050d36defd
  // (380 files, twenty-ninth-pass amendment above). Superseded 2026-08-30
  // (thirtieth pass) by ISS-2026-236's step-up enforcement (381 files: +1,
  // 20260830110000_harden_evaluate_permission_step_up_enforcement.sql).
  // History: e626706010a913a8e59c0b7241e2434fada7ecd0d5f5915c83f362f3feeae09b
  // (381 files, thirtieth-pass amendment above). Superseded 2026-08-30
  // (thirty-first pass) by ISS-2026-274's customer/item import adapters (382
  // files: +1, 20260830120000_create_customer_and_item_import_adapters.sql).
  // History: eebd52b277bc7674ba8870c65949343319fe602eefc8d0071ea34eaf1ffa447e
  // (382 files, thirty-first-pass amendment above). Superseded 2026-08-30
  // (thirty-second pass) by ISS-2026-273's opening-balance import and GL
  // posting (383 files: +1, 20260830130000_create_finance_opening_balance_
  // import_and_gl_posting.sql).
  // History: b5d845458ed0e16e687446511fa19132ee8f89ecf9a161e302face6769cd444c
  // (383 files, thirty-second-pass amendment above). Superseded 2026-08-30
  // (thirty-third pass) by ISS-2026-258's incident-communication capability
  // (384 files: +1, 20260830140000_create_incident_communication.sql).
  // History: ef8fe38708c2d672934527015279bce7a065a5c3b90600a42b3d52326c441a21
  // (384 files, thirty-third-pass amendment above). Superseded 2026-08-30
  // (thirty-fourth pass) by ISS-2026-251's escalation sweep (385 files: +1,
  // 20260830150000_create_incident_escalation_sweep.sql).
  // History: 301d42ffd8a27a6c1c3a5821433f516200c1516fadb534c03a6793dbafbf9a56
  // (385 files, thirty-fourth-pass amendment above). Superseded 2026-08-30
  // (thirty-fifth pass) by ISS-2026-093 (386 files: +1, 20260830160000_harden_
  // approval_engine_audit_reason_redaction.sql). See the class-level doc
  // comment above.
  // History: 30b093fea9ee698b13918049b8b32f5637bcd63e0ffe140cf66bb83db8d64f69
  // (386 files, thirty-fifth-pass amendment above). Superseded 2026-08-30
  // (thirty-sixth pass) by ISS-2026-307's durable IP-access evaluation (387
  // files: +1, 20260830170000_create_durable_ip_access_evaluation.sql). See
  // the class-level doc comment above.
  // History: 9eaff92625219ddc8619c01e5012667089ca339789733cc97afe71af38974bc3
  // (387 files, thirty-sixth-pass amendment above). Superseded 2026-08-30
  // (thirty-eighth pass) by ISS-2026-155's alert dedup discriminator (388
  // files: +1, 20260830180000_add_observability_alert_dedupe_discriminator.sql).
  // See the class-level doc comment above.
  // History: d594538bf46479d34d1cb77dae790869ce87b7f37dfb033f63a5e05aa5467827
  // (388 files, thirty-eighth-pass amendment above). Superseded 2026-08-30
  // (thirty-ninth pass) by ISS-2026-053/ISS-2026-308 (389 files: +1,
  // 20260830190000_harden_enqueue_job_idempotency_payload_tuple.sql). See the
  // class-level doc comment above.
  // History: f4f470c48da0be14c4209b69cfad8d1ed86aaf4011b410819f48de96751df4f9
  // (389 files, thirty-ninth-pass amendment above). Superseded 2026-08-31
  // (fortieth pass) by ISS-2026-309, a change-caused security defect found by
  // the live advisor sweep (390 files: +1,
  // 20260830200000_correct_public_wrapper_grant_parity.sql). See the
  // class-level doc comment above.
  // History: fe1ca6c9607ec26a16acb2141d0ba4b4e1447c469a372fa35ee453684c173218
  // (390 files, fortieth-pass amendment above). Superseded 2026-08-31 (forty-first
  // pass) by ISS-2026-186/ISS-2026-179/HDN-BLK-014 (391 files: +1,
  // 20260831010000_close_rbac_oracle_on_public_wrappers.sql). See the class-level doc
  // comment above.
  // History: b5386269e2d4c9e802f0e013ad24d2a6f3dcd926515cad5653f7db8eaab63660
  // (391 files, forty-first-pass amendment above). Superseded 2026-08-31 (forty-second
  // pass) by ISS-2026-223 (392 files: +1,
  // 20260831020000_harden_file_legal_hold_provenance.sql). See the class-level doc comment.
  // History: fc88d7f379d609c70b1221b570253cc68c809e8474ddb8398823932594d7e478
  // (392 files, forty-second-pass amendment above). Superseded 2026-08-31 (forty-third
  // pass) by ISS-2026-189 (393 files: +1,
  // 20260831030000_revoke_unused_employee_directory_column_grant.sql).
  // History: e07f4ff308432f3c5077ad3ed4e396a65011a0a9e0363f9f1becff03eb870232
  // (393 files, forty-third-pass amendment above). Superseded 2026-08-31 (forty-fourth
  // pass) by ISS-2026-172(b) (394 files: +1,
  // 20260831040000_create_logged_file_metadata_listing.sql).
  // History: 29e80b0443bda98ddd95d0d61a49fc53fa34b156efdf37728503c1bdce50f4c8
  // (394 files, forty-fourth-pass amendment above). Superseded 2026-08-31 (forty-sixth
  // pass) by ISS-2026-068/071/073 (395 files: +1,
  // 20260831060000_close_hris_authority_shape_rulings.sql). The forty-fifth pass moved
  // dbTestSetSha256 only -- ISS-2026-170's own enumeration concluded no migration should
  // be written -- so this digest skips from the forty-fourth pass to the forty-sixth.
  // History: c10632fead489aa251ea5b2c2c01f6a522558961b9cc859e8514fcaf106c7bcd
  // (395 files, forty-sixth-pass amendment above). Superseded 2026-08-31 (forty-seventh
  // pass) by ISS-2026-147 (396 files: +1,
  // 20260831070000_add_connector_scoped_execution_log_filters.sql).
  // History: 49e3ca8b14376b9b9a8569d1d4c6b620838b209f5c2dcb011b8b3e56f229be19
  // (396 files, forty-seventh-pass amendment above). Superseded 2026-08-31 (forty-eighth
  // pass) by ISS-2026-086 (397 files: +1,
  // 20260831080000_split_ticket_admin_content_override_permission.sql).
  // History: ce7ae92e77046ffb102cefc61da453c00b86593e6064c6d33e06373c9f5b244a
  // (397 files, forty-eighth-pass amendment above). Superseded 2026-08-31 (forty-ninth
  // pass) by the task scheduler (398 files: +1,
  // 20260831090000_create_tenant_configurable_task_scheduler.sql).
  // History: 42161bc6d1fe31e12a6f7fd25f890ae7ea865653a67b9fc82ad4ff5f07d619de
  // (398 files, forty-ninth-pass amendment above). Superseded 2026-08-31 (fiftieth pass) by
  // ISS-2026-249 + ISS-2026-313 (399 files: +1,
  // 20260831100000_close_authority_denial_alerting_and_scheduler_catalogue_gap.sql).
  // History: 04367e3b842f68f719216c613f55046857e1cd3b05b8bbf12aa46af94c719802
  // (399 files, fiftieth-pass amendment above). Superseded 2026-08-31 (fifty-first pass) by
  // ISS-2026-207 (400 files: +1,
  // 20260831110000_give_api_version_registry_live_effect.sql).
  // History: 84203764b0d28bd824209e2b5725963ad8f81e56a0f9a03e6dddb4afd3976ffd
  // (400 files, fifty-first-pass amendment above). Superseded 2026-08-31 (fifty-second pass) by
  // ISS-2026-091 + ISS-2026-142 (401 files: +1,
  // 20260831120000_create_data_retention_and_legal_hold_registry.sql).
  // History: e9c37fd7c4bf21bccd704d62a51bd7b1e0d2e74f414f49333c476e6144247f46
  // (401 files, fifty-second-pass amendment above). Superseded 2026-08-31 (fifty-third pass)
  // by ISS-2026-231 (402 files: +1,
  // 20260831130000_backstop_malware_scan_resolution_invariant.sql).
  // History: 8b7d0585b8b415d905ebedf923f2985232f6f60e829a9732318ac0d53350a26a
  // (402 files, fifty-third-pass amendment above). Superseded 2026-08-31 (fifty-fourth pass) by
  // ISS-2026-238 (403 files: +1, 20260831140000_bound_logged_file_listing.sql).
  // History: 2819e35ab8fe49aebfc65d7e1cbe628ceaa4da84dd9f5f6752362ec78765a005
  // (403 files, fifty-fourth-pass amendment above). Superseded 2026-08-31 (fifty-fifth pass) by
  // ISS-2026-058 (404 files: +1,
  // 20260831150000_add_vendor_capacity_manual_confirmation_evidence.sql).
  // History: 0c97fd28555b491731a36af023748cc3b8084fad03d9c76d3a65f8a23189d6fc
  // (404 files, fifty-fifth-pass amendment above). Superseded 2026-08-31 (fifty-seventh pass) by
  // ISS-2026-315 (405 files: +1,
  // 20260831160000_expose_timesheet_entry_break_and_notes_in_list.sql). The fifty-sixth pass,
  // ISS-2026-061 / ADR-0029, touched no migration, which is why this history skips a number.
  // History: d01233074429077c68e6d9196764132cc353d9576fd7c0d16615a9aabe47868b
  // (405 files, fifty-seventh-pass amendment above). Superseded 2026-08-31 (fifty-eighth pass) by
  // ISS-2026-206's third table (406 files: +1,
  // 20260831170000_harden_finance_bank_transaction_match_source_lineage.sql).
  // History: 9008a90551ddc9d091db33518412a879630d9d2371b91ab1964357fc6d2ca581
  // (406 files, fifty-eighth-pass amendment above). Superseded 2026-08-31 (fifty-ninth pass) by
  // ISS-2026-208 (407 files: +1,
  // 20260831180000_make_vendor_api_invitation_response_replay_safe.sql).
  // History: 1690f2f36fb5d469880bedbc6651cea124e91c4298e872943a82a64404dff8b6
  // (407 files, fifty-ninth-pass amendment above). Superseded 2026-08-31 (sixty-first pass) by
  // ISS-2026-083 (408 files: +1,
  // 20260831190000_add_training_provider_evidence_attachment.sql). The sixtieth pass,
  // ISS-2026-312, touched no migration, which is why this history skips a number.
  // History: 6c63e9d375fa35962da5a27ef6c22acd31e342d50e2ff15bc917d2bb3b7e4010
  // (408 files, sixty-first-pass amendment above). Superseded 2026-08-31 (sixty-second pass) by
  // ISS-2026-314 (409 files: +1,
  // 20260831200000_stop_early_scheduled_report_trigger_skipping_a_due_occurrence.sql).
  // History: ce3f785b26728689c0e042efd4c5366053fc9e281f044dfd678d49590d9b94db
  // (409 files, sixty-second-pass amendment above). Superseded 2026-08-31 (sixty-third pass) by
  // ISS-2026-118 (410 files: +1,
  // 20260831210000_wire_customer_dashboard_bookings_shipments_invoices_payments.sql).
  // History: 5b403a1c326197650266a23bc955f8b2a62be46d4615eddf6cdab7eb211e7f99
  // (410 files, sixty-third-pass amendment above). Superseded 2026-08-31 (sixty-fifth pass) by
  // ISS-2026-120 (411 files: +1,
  // 20260831220000_add_customer_portal_inbound_order_visibility.sql). The sixty-fourth pass,
  // ISS-2026-119, touched no migration, which is why this history skips a number rather than
  // losing one. Ruling: ADR-0027 Part A.
  //
  // CPL-310 shipped the outbound half of customer warehouse-order visibility and disclosed, in
  // its own design decision 11, that no customer-facing inbound RPC existed anywhere in this
  // repository. That was a budget disclosure, not a defect, and it stayed true for two weeks.
  // This migration builds the inbound half exactly as ISS-2026-120's own recommended fix
  // specified: three RPCs mirroring the outbound three, reusing
  // app.evaluate_customer_portal_inventory_access and app.resolve_customer_account_scope
  // unmodified, plus their three public.* wrappers.
  //
  // The part that was not in the recommended fix, and is the reason this migration is more than
  // a mirror: 20260730311000 narrowed seven tables' raw SELECT policy to deny a
  // customer_user-layer actor outright, and the inbound pair was not among them -- correctly, at
  // the time, since no customer-facing inbound path existed to harden against. This migration is
  // the thing that creates that path, so it is the migration that owes the matching denial. One
  // added conjunct per policy, the rest byte-identical; it can only remove rows, and only for
  // actors whose sanctioned read path is the SECURITY DEFINER layer.
  // History: e6d734bfb302d7c77f96881d72464a2464b8d50f33d3224a19f13453bcb0a805
  // (411 files, sixty-fifth-pass amendment above). Superseded 2026-08-31 (sixty-seventh pass)
  // by ISS-2026-126 / ISS-2026-127 item 1 / ISS-2026-128 item 1 (412 files: +1,
  // 20260831230000_add_loyalty_earning_tier_and_points_posting_sweeps.sql). The sixty-sixth
  // pass, ISS-2026-075, touched no migration, which is why this history skips a number.
  // Ruling: ADR-0027 Part A.
  //
  // Three entries filed separately that were always one gap: loyalty earning evaluation, tier
  // recalculation and points posting are each a real, correct, idempotent RPC reachable only by
  // a staff member clicking a button one record at a time. Each disclosed the same reason --
  // scheduled-job wiring was capability-sized work beyond its own prompt -- and that stopped
  // being true when 20260831090000 shipped the scheduler.
  //
  // What was still missing was not a catalogue entry. All three RPCs are PER-RECORD, and a
  // schedule has no record: this migration adds the sweeps that find the work, and nothing
  // else. No earning computation, tier evaluation or lot posting is reimplemented.
  //
  // The design decision that matters: a skipped record is not a failed sweep. Each per-record
  // call runs in its own subtransaction, so an ineligible record is a counted skip with its own
  // reason rather than a raise that would stop every eligible record behind it.
  //
  // Two near-misses, both caught by this repository's own gates rather than by care. The
  // dispatcher replacement was first drafted from the migration that CREATED it (eleven
  // branches) when a later migration had already extended it to sixteen -- task-scheduler.sql's
  // "every catalogue task reaches a real dispatch branch" assertion failed loudly. And the job
  // type had to be added in four places, not one: the CHECK constraint, app.generic_job_types(),
  // GENERIC_JOB_TYPES and IMPORT_EXPORT_JOB_TYPES -- each guarded by its own parity assertion,
  // each of which fired in turn.
  migrationSetSha256: "797fc4af0660d4d5d64c0cffbde908480faca60efcd01ca6b933f9534f6c2ddb",
  // History: 4df2ae90f01f1b67ee708efc9919d48de2bb78a76e8d1a52cf14788d508488dd
  // (231 files, RGL-393's widened freeze). Superseded 2026-08-25 by the same
  // remediation's new permanent regression test (232 files: +1,
  // public-api-wrapper-regression.sql).
  // History: 576c4aa0693173d361293df78b79f12f79ed72f5bdd502210f272d54a8a9f438
  // (232 files, prior amendment above). Superseded 2026-08-25 (third pass) by
  // RGL-394's own new regression assertion widening the existing
  // procurement-vendor-performance.sql (still 232 files -- content changed,
  // not file count).
  //
  // 232 tracked .sql files under scripts/db-tests/: the 231 the runner executes,
  // plus fixtures/auth-schema-stub.sql, which it loads into every disposable
  // database before any test runs. RGL-392 §3 originally recorded 2c3389a8...,
  // covering only the 230 top-level files; this gate's own first run caught the
  // omission and RGL-393 widened the freeze to include the fixture. See
  // RGL-393.md §4. The fixture is not incidental — HDN-369 had to correct a
  // stale, load-bearing claim inside it, and its content changes what every
  // db-test runs against.
  // History: 746030c4f93ef1f16da79f87154547cb78e9cad0c8020efadc78a184f4c7aa05
  // (232 files, prior amendment above). Superseded 2026-08-25 (fourth pass) by
  // RGL-395's own RGL-BLK-005 fix: 6 files' content changed (no file added or
  // removed, still 232 files). See the class-level doc comment above.
  // History: e531723a2160096d28c778784f53723f07afe36ff9529623964998ad4c4ca07a
  // (232 files, fourth-pass amendment above). Superseded 2026-08-25 (fifth
  // pass) by RGL-404's own RGL-BLK-009 fix: scripts/db-tests/finance-
  // settlement.sql widened (still 232 files -- content changed, not file
  // count). See the class-level doc comment above.
  // History: 1b4103c220a5ce06c5587def356cc0c6091d6538afd8367c4f00f0e320a65438
  // (232 files, fifth-pass amendment above). Superseded 2026-08-25 (sixth
  // pass) by the historical-issue-backlog remediation (233 files: +1,
  // database-restore-lock.sql; rbac-enforcement.sql also widened). See the
  // class-level doc comment above.
  // History: f00bfda7738cb225dd77ec978d3752332f2e9865546987599574130c257b6cd7
  // (233 files, sixth-pass amendment above). Superseded 2026-08-25 (seventh
  // pass) by the historical-issue-backlog remediation's ISS-2026-257 fix (233
  // files unchanged in count -- 26 files widened with the new encryption-key
  // GUC/decrypt fixes, plus the ISS-2026-156 fix, no file added or removed).
  // See the class-level doc comment above.
  // History: e54ed5a03d8f13dcdfaedd41da3c8837480e0032b92e6e743649dc7f3c7a6d19
  // (233 files, seventh-pass amendment above). Superseded 2026-08-25 (eighth
  // pass) by the historical-issue-backlog remediation's ISS-2026-265 fix (233
  // files unchanged in count -- database-restore-lock.sql widened, no file
  // added or removed). See the class-level doc comment above.
  // History: 83e37b49ef1dbde855586a3a3899466b4894f458861f0c8dfb4adecf0bb256fa
  // (233 files, eighth-pass amendment above). Superseded 2026-08-25 (ninth
  // pass) by the historical-issue-backlog remediation's ISS-2026-269 fix (233
  // files unchanged in count -- hris-employee-master.sql widened). See the
  // class-level doc comment above.
  // History: e135017ae8d8ce9d6a0fa9782cca9143fe1c24a7534372b2b5a2be8714d75d65
  // (233 files, ninth-pass amendment above). Superseded 2026-08-25 (tenth
  // pass) by the historical-issue-backlog remediation's ISS-2026-254/
  // ISS-2026-299 fix (233 files unchanged in count --
  // database-restore-lock.sql widened twice, no file added or removed). See
  // the class-level doc comment above.
  // History: 44f48a6bd042c6304810db54d8bd24157fb46a0a94d82a79530337c75ca6d26b
  // (233 files, tenth-pass amendment above). Superseded 2026-08-25 (eleventh
  // pass) by the historical-issue-backlog remediation's ISS-2026-263 fix (233
  // files unchanged in count -- user-lifecycle.sql widened, no file added or
  // removed). See the class-level doc comment above.
  // History: f573d9f0df1a5652a658aac531b690217f380678bf933051cc1c93d4dfa0da3a
  // (233 files, eleventh-pass amendment above). Superseded 2026-08-25
  // (twelfth pass) by the historical-issue-backlog remediation's
  // ISS-2026-264 fix (233 files unchanged in count -- rbac-enforcement.sql
  // widened, no file added or removed). See the class-level doc comment
  // above.
  // History: bf17db612e08fc505d510ad871a16b1c026a0f40f7d8dec5e82212f782b3b0bf
  // (233 files, twelfth-pass amendment above). Superseded 2026-08-25
  // (thirteenth pass) by the historical-issue-backlog remediation's
  // ISS-2026-266 fix (233 files unchanged in count --
  // analytics-materialized-views.sql widened, no file added or removed).
  // See the class-level doc comment above.
  // History: cdb12fdd4aaaa26aa4f6ebe9e57e4d1a4690e380832e2d272b0c28c36c71c6c4
  // (233 files, thirteenth-pass amendment above). Superseded 2026-08-25
  // (fourteenth pass) by the historical-issue-backlog remediation's
  // ISS-2026-270 fix (234 files: +1, new scripts/db-tests/reference-
  // data-import.sql). See the class-level doc comment above.
  // History: 9a0a5dbc71315f18ba3d4598e9fa849aacacdb051527cc1a7d878df89566245a
  // (234 files, fourteenth-pass amendment above). Superseded 2026-08-25
  // (fifteenth pass) by the historical-issue-backlog remediation's
  // ISS-2026-272 fix (234 files unchanged in count -- disaster-recovery-
  // enterprise-support.sql widened, no file added or removed). See the
  // class-level doc comment above.
  // History: f3c257c8dde475150aa07c97e4a93798ccc7d5ef21d3a980beddbbcf99a894bc
  // (234 files, fifteenth-pass amendment above). Superseded 2026-08-25
  // (sixteenth pass) by the historical-issue-backlog remediation's
  // ISS-2026-271 fix (234 files unchanged in count --
  // hris-employee-master.sql widened, no file added or removed). See the
  // class-level doc comment above.
  // History: 47b945d51ad5f749c7018f3b96b063468bb984173598db437846f2eedf9ffee9
  // (234 files, sixteenth-pass amendment above). Superseded 2026-08-27
  // (seventeenth pass) by the historical-issue-backlog remediation's
  // ISS-2026-275/ISS-2026-276 fix (234 files unchanged in count --
  // finance-journal.sql widened, no file added or removed). See the
  // class-level doc comment above.
  // History: 329cfdf96f8296255f45891f7da0ffd66efb033fc0dc2256102de9c6758ce4c7
  // (234 files, seventeenth-pass amendment above). Superseded 2026-08-27
  // (eighteenth pass) by the historical-issue-backlog remediation's
  // ISS-2026-279 fix (234 files unchanged in count --
  // hris-employee-master.sql widened, no file added or removed). See the
  // class-level doc comment above.
  // History: b1e8c3f83d0c0e62258bb8086e60a1e6120945718db67ddfbcb62039f89e38fc
  // (234 files, eighteenth-pass amendment above). Superseded 2026-08-27
  // (nineteenth pass) by the historical-issue-backlog remediation's
  // ISS-2026-260 fix (234 files unchanged in count --
  // disaster-recovery-enterprise-support.sql widened, no file added or
  // removed). See the class-level doc comment above.
  // History: dafb20eb1d719bae7251a199b5d11733e4a015876108e7b7098fb840e530b2cd
  // (234 files, nineteenth-pass amendment above). Superseded 2026-08-27
  // (twentieth pass) by the historical-issue-backlog remediation's
  // ISS-2026-278 fix (234 files unchanged in count -- import-export.sql,
  // hris-employee-master.sql, hris-attendance.sql,
  // hris-overtime-timesheet.sql, and procurement-vendor-rate-tiers.sql
  // all widened, no file added or removed). See the class-level doc
  // comment above.
  // History: e6a7a317c8a6c28a7f4e6a3bcae6f59c2b61dacdef78ce92cce491c0530d589a
  // (234 files, twentieth-pass amendment above). Superseded 2026-08-27
  // (twenty-first pass) by Track B Batch 1 (234 files unchanged in count --
  // webhook-management.sql, integration-hub.sql,
  // ai-governance-provider-boundary.sql, commercial-quotation-builder.sql,
  // api-key-webhook.sql, vendor-api.sql, rbac-enforcement.sql,
  // hris-shift-roster-scheduling.sql, and analytics-materialized-views.sql
  // all widened, no file added or removed). See the class-level doc
  // comment above.
  // History: 69d5f99356271c3fb246f210a497bf3f9f5f904d62c7fbffba9fe1608b9200cc
  // (234 files, twenty-first-pass amendment above). Superseded 2026-08-27
  // (twenty-second pass) by Track B Batch 2 (234 files unchanged in count --
  // approval.sql, procurement-sourcing.sql, procurement-vendor-rate-tiers.sql,
  // procurement-vendor-financial-security.sql, finance-invoice.sql, and
  // advanced-tms-wms-inbound.sql all widened, no file added or removed).
  // History: 2361bc6950e59dbe9ac8d029cc0a7d45a8cd296080b7e8de30cf7f2269b33003
  // (234 files, twenty-second-pass amendment above). Superseded 2026-08-27
  // (twenty-third pass) by Track B Batch 3 (234 files unchanged in count --
  // procurement-vendor-invoice-matching.sql widened, no file added or
  // removed).
  // History: 834154f63adbc87e9e732601ec836ac9a4239835dda75300c892dc3625179fbb
  // (234 files, twenty-third-pass amendment above). Superseded 2026-08-28
  // (twenty-fourth pass) by Track B Batch 4 (234 files unchanged in count --
  // advanced-tms-customer-inventory-access.sql, customer-invoice-billing-
  // visibility.sql, customer-loyalty-expiry-fraud-prevention.sql,
  // customer-loyalty-liability-reconciliation.sql, customer-loyalty-
  // membership-tier.sql, customer-loyalty-points-ledger.sql, customer-
  // portal-loyalty-ledger-supreme-admin-override.sql, and customer-portal-
  // scope.sql all widened, no file added or removed).
  // History: 3e48578beba727ba14b0bae623f3da0abf258d5ed528377537438f7900bed688
  // (234 files, twenty-fourth-pass amendment above). Superseded 2026-08-28
  // (twenty-fifth pass) by Track B Batch 5 (234 files unchanged in count --
  // ai-governance-provider-boundary.sql and enterprise-iam-sso-scim.sql
  // both widened, no file added or removed). See the class-level doc
  // comment above.
  // History: a71e939f07a16879b52d744324231cbab3436a8529ec2a07d80ae14ac827528b
  // (234 files, twenty-fifth-pass amendment above). Superseded 2026-08-28
  // (twenty-sixth pass) by Track B Batch 6 (234 files unchanged in count --
  // support-access.sql, audit-trail.sql, rbac-enforcement.sql,
  // hris-kpi-performance.sql, and ticketing-linked-records.sql all
  // widened, no file added or removed).
  // History: 9c6faf9a551c36165bd90836eab1e9a84ddafac8be8397b958d9be9c260cec3e
  // (234 files, twenty-sixth-pass amendment above). Superseded 2026-08-28
  // (twenty-seventh pass) by Track B Batch 7 (234 files unchanged in count
  // -- operations-job-order.sql, advanced-tms-inventory-ledger.sql,
  // advanced-tms-cycle-count-adjustment.sql, advanced-tms-warehouse-
  // billing-events.sql, procurement-vendor-compliance.sql, procurement-
  // vendor-financial-security.sql, document-file.sql, approval.sql,
  // dedicated-enterprise-deployment.sql, and multi-region-data-
  // residency.sql all widened, no file added or removed).
  // History: 6128cd424ad1aa108a22c013cf8c790aa1feff99449724ea972cd345accfdb90
  // (234 files, twenty-seventh-pass amendment above). Superseded 2026-08-28
  // (twenty-eighth pass) by Track B Batch 8 (235 files: +1, scripts/db-
  // tests/raw-mutation-tripwire.sql, new -- ticketing-sla.sql, customer-
  // user-management.sql, customer-portal-dashboard.sql, and customer-
  // shipment-alerts.sql all also widened).
  // History: e425cdf978802940d2c205edc44a566f641cb811fed7b1924c2d3994beba036b
  // (235 files, twenty-eighth-pass amendment above). Superseded 2026-08-30
  // (twenty-ninth pass) by ISS-2026-057 (235 files unchanged in count --
  // procurement-vendor-registration.sql widened with six new regression
  // blocks, no file added or removed).
  // History: 9d123c8162ed7342874245b03c757bed4c355ee7deb6239565b0c0904af32d0c
  // (235 files, twenty-ninth-pass amendment above). Superseded 2026-08-30
  // (thirtieth pass) by ISS-2026-236 (235 files unchanged in count --
  // enterprise-mfa-session-controls.sql widened, no file added or removed).
  // History: 312ceebcbdcb65023606c9e912b3475c9f77b58873f3967692b32aeb0a2e21b4
  // (235 files, thirtieth-pass amendment above). Superseded 2026-08-30
  // (thirty-first pass) by ISS-2026-274 (236 files: +1, scripts/db-tests/
  // master-data-import.sql, new -- advanced-tms-item-uom-master.sql also
  // changed, a corrected comment rather than a new file).
  // History: 2c74593b6c4df816cc476824fd656e97bc153b3d0b5ac5b177d06c4a47ea6572
  // (236 files, thirty-first-pass amendment above). Superseded 2026-08-30
  // (thirty-second pass) by ISS-2026-273 (236 files unchanged in count --
  // finance-subledger.sql widened, no file added or removed).
  // History: 748ede7ef8b7a48e15084ea67a964610b1edaaa1aa5810ae43bbc2f402ab4c4b
  // (236 files, thirty-second-pass amendment above). Superseded 2026-08-30
  // (thirty-third pass) by ISS-2026-258 (236 files unchanged in count --
  // enterprise-monitoring-observability.sql widened).
  // History: 80822f8742653226f49c39f1bb69150b4bf101b768a31205fffb732a6e99bbd1
  // (236 files, thirty-third-pass amendment above). Superseded 2026-08-30
  // (thirty-fourth pass) by ISS-2026-251 (236 files unchanged in count --
  // enterprise-monitoring-observability.sql widened again, background-job.sql's
  // TS-mirror literal updated).
  // History: 65044b3c407abb5e8d269f66f3635ce4e83e5c3b68400a512357fb8e384d5d1c
  // (236 files, thirty-fourth-pass amendment above). Superseded 2026-08-30
  // (thirty-fifth pass) by ISS-2026-093 (236 files unchanged in count --
  // approval.sql widened). See the class-level doc comment above.
  // History: d94aad5edcf1ba3cf303d564246be6331b28df5de8ed60380838b5823e9b626b
  // (236 files, thirty-fifth-pass amendment above). Superseded 2026-08-30
  // (thirty-sixth pass) by ISS-2026-307 (236 files unchanged in count --
  // ip-restriction-network-access.sql widened with the durable-denial
  // regression block). See the class-level doc comment above.
  // History: b9fee1d89db1815841a392a1ffdf4fbc7e98d4fc1c04e738228d163abfe957f9
  // (236 files, thirty-sixth-pass amendment above). Superseded 2026-08-30
  // (thirty-seventh pass) by ISS-2026-151 (236 files unchanged in count --
  // integration-hub.sql widened with the INTHUB:Configure step-up proof, no
  // migration added: the enforcement already shipped at 20260830110000). See
  // the class-level doc comment above.
  // History: acbf2f047e9dc181408457c4d4401a2d18d6d0c4a609d228d76317364bc63f78
  // (236 files, thirty-seventh-pass amendment above). Superseded 2026-08-30
  // (thirty-eighth pass) by ISS-2026-155 (236 files unchanged in count --
  // scale-up-architecture.sql widened with the dedup-discriminator proof). See
  // the class-level doc comment above.
  // History: 33b21176ca55a840895858d839c6f7c0670c63d4c77a699ff9e231ed86cb6b2f
  // (236 files, thirty-eighth-pass amendment above). Superseded 2026-08-30
  // (thirty-ninth pass) by ISS-2026-053 (236 files unchanged in count --
  // background-job.sql widened with the request-tuple proof, and
  // data-retention-archival.sql's global job count scoped to its own tenant).
  // See the class-level doc comment above.
  // History: 32857b68d97f5ccef86af1a1645699260cbd3218f7281178deeff6f33fdd2306
  // (236 files, fortieth-pass state). Superseded 2026-08-31 (forty-first pass) by
  // ISS-2026-186 (236 files unchanged in count -- rbac-enforcement.sql widened with the
  // four-property wrapper-oracle proof). See the class-level doc comment above.
  // History: d8b60f1c4516d63b1cd3d5e972b8b72b86e5703d0f10bcf10ea457af20a57ff4
  // (236 files, forty-first-pass state). Superseded 2026-08-31 (forty-second pass) by
  // ISS-2026-223 (236 files unchanged in count -- document-file.sql widened with the
  // six-property legal-hold provenance proof). See the class-level doc comment.
  // History: c2f1876cfab99546cf288a67262971440ddf4e8df9a91f3813d612c42f1cf535
  // (236 files, forty-second-pass state). Superseded 2026-08-31 (forty-third pass) by
  // ISS-2026-189 (236 files unchanged in count -- hris-employee-master.sql gained the
  // column-set pinning guard).
  // History: 4250d75c426c64b364557b14a38a6ac8f85291c7866c8ac98aa9c8b361043e13
  // (236 files, forty-third-pass state). Superseded 2026-08-31 (forty-fourth pass) by
  // ISS-2026-172(b) (236 files unchanged -- document-file.sql gained the logged-listing proof).
  // History: 2acefedb71b9e0d083959408545dfc2381baf340cdef0a0489b3d4f335202a5a
  // (236 files, forty-fourth-pass state). Superseded 2026-08-31 (forty-fifth pass) by
  // ISS-2026-170 (236 files unchanged -- document-file.sql gained the 14-guard set pin).
  // History: 5f2aa52037f5c42d6b0cfd4f17219c64bc89ee1e305fa1bdbd3964fd1abd7b84
  // (236 files, forty-fifth-pass state). Superseded 2026-08-31 (forty-sixth pass) by
  // ISS-2026-068/071/073 (236 files unchanged in count -- hris-recruitment-ats.sql gained
  // the hiring-manager assigned-slice proof, hris-onboarding-offboarding.sql gained the
  // task-owner authority proof and both direct-hire approval proofs).
  // History: 81eb9c86c069e4ed31105135a29326cd82947dfe4ff4b4e9b28db3e2bc0e41bc
  // (236 files, forty-sixth-pass state). Superseded 2026-08-31 (forty-seventh pass) by
  // ISS-2026-147 (236 files unchanged in count -- public-api-platform.sql and
  // webhook-management.sql each gained a per-connector filter proof).
  // History: 24117ef8f4cc859bc79e452a36353e939c428efd9333d8e24e281c9943dd37fd
  // (236 files, forty-seventh-pass state). Superseded 2026-08-31 (forty-eighth pass) by
  // ISS-2026-086 (236 files unchanged in count -- ticketing-internal.sql gained the
  // TKT:Edit/TKT:Override separation proof, and nine service-desk-admin fixtures across the
  // ticketing files now grant TKT:Override explicitly).
  // History: 1689689c82d2975899730849e307e47f106e93b5e3ef93674340564480738435
  // (236 files, forty-eighth-pass state). Superseded 2026-08-31 (forty-ninth pass) by the
  // task scheduler (237 files: +1, task-scheduler.sql -- the first NEW runner file in this
  // freeze's history, every prior amendment having only widened existing ones).
  // History: d7a3a3184533bf28d6e4584eeb23c2477de6ebcc032d3a0f5686dfb4641dc4b4
  // (237 files, forty-ninth-pass state). Superseded 2026-08-31 (fiftieth pass) by
  // ISS-2026-249 + ISS-2026-313 (237 files unchanged in count -- task-scheduler.sql gained the
  // burst-detector, step-up-recorder and denial-ledger-privilege proofs, and its catalogue
  // walk went from 11 tasks to 16).
  // History: dc64811eb99224c485871cf2e282caa51a9945dcafec1823a1f768516efdfb1b
  // (237 files, fiftieth-pass state). Superseded 2026-08-31 (fifty-first pass) by ISS-2026-207
  // (237 files unchanged in count -- public-api-platform.sql gained the five-state registry
  // decision proof and a service_role-only grant pin).
  // History: 9e26bcb23ea399ec040ce3e0487be2c625ddcab134bc3df5e1415f336a94c7e0
  // (237 files, fifty-first-pass state). Superseded 2026-08-31 (fifty-second pass) by
  // ISS-2026-091 + ISS-2026-142 (238 files: +1, data-retention-legal-hold.sql).
  // History: c16d4c44787b61fcaab715381fbfb855a78bccacffd34dc40c137db968ac06eb
  // (238 files, fifty-second-pass state). Superseded 2026-08-31 (fifty-third pass) by
  // ISS-2026-231 (238 files unchanged in count -- document-file.sql gained the backstop proof,
  // and five files' own raw RPD-022 re-flags now declare themselves).
  // History: b8a19b3c014bbb1452cd7b4b1b5e725f912225461d5aeac5c5a48b0854decd77
  // (238 files, fifty-third-pass state; the fifty-fourth pass, ISS-2026-238, touched no
  // db-test file, which is why this history skips a number rather than losing one).
  // Superseded 2026-08-31 (fifty-fifth pass) by ISS-2026-058 (238 files unchanged in count --
  // procurement-vendor-capacity.sql gained the Prompt 262 §22 manual-confirmation-with-evidence
  // block: the six refusal modes, the legitimate path, the in-system accept's own
  // system_accept stamp, and the raw-UPDATE case only the CHECK constraint can police).
  // History: e47ee3cb537cb0b0d74c7a93e3896cfe323910d319dbaeeb6845144f6d23361a
  // (238 files, fifty-fifth-pass state). Superseded 2026-08-31 (fifty-sixth pass) by
  // ISS-2026-061 / ADR-0029 (238 files unchanged in count --
  // procurement-vendor-invoice-matching.sql gained the block that makes ADR-0029's ruling
  // executable: the canonical on-ramp's own conditionality, the domain path's
  // unconditionality with no policy or routing definition configured, and the no-FK pin that
  // stops the two approval mechanisms drifting into a half-bound hybrid).
  // History: 52bda850cb9c8921fdf4ad24af45bff4ace36a0a60b4609ef202f5f38d701e7e
  // (238 files, fifty-sixth-pass state). Superseded 2026-08-31 (fifty-seventh pass) by
  // ISS-2026-315 (238 files unchanged in count -- hris-overtime-timesheet.sql gained the
  // pg_get_function_result pin that sits ON the SQL/TypeScript join, the one place from which
  // the defect was visible: both halves were internally consistent, only the contract between
  // them was wrong).
  // History: fd7e7747deedfe9f26fde33078f6b2a39e2a1cd146957fdaaf231e5f9d3ddbd9
  // (238 files, fifty-seventh-pass state). Superseded 2026-08-31 (fifty-eighth pass) by
  // ISS-2026-206's third table (238 files unchanged in count -- finance-cash-bank.sql swapped a
  // gen_random_uuid() match for a REAL captured receipt, which was testing the very orphan the
  // new guard rejects, and gained direct-INSERT/direct-UPDATE proofs plus the null-id boundary).
  // History: 2c4cd1f6fa5864b48d93faab4e7b6916f0ab25efe8003f394cca81f760db4f64
  // (238 files, fifty-eighth-pass state). Superseded 2026-08-31 (fifty-ninth pass) by
  // ISS-2026-208 (238 files unchanged in count -- vendor-api.sql gained the lost-response-retry
  // proof and, more importantly, the two boundaries the narrow replay signature exists to hold:
  // a decline retry with a DIFFERENT reason, and a client stale by more than their own write,
  // both still refused).
  // History: be5e42c586cd13e104dff131a0c5156038e3dda3283326363155bf0f2a524058
  // (238 files, fifty-ninth-pass state). Superseded 2026-08-31 (sixtieth pass) by ISS-2026-312
  // (238 files unchanged in count -- operations-document-requirement.sql,
  // procurement-vendor-contract.sql and procurement-vendor-invoice-matching.sql each gained the
  // wrongly-scoped-file fixture that proves their record-scope guard FIRES, closing the last
  // three of the 14 guards ISS-2026-170 pinned as a set but could only prove existed).
  // History: 3a36cd5d637e07f28318f3fdd19759e53d0b509156d45d9a98e16023d2aa411b
  // (238 files, sixtieth-pass state). Superseded 2026-08-31 (sixty-first pass) by ISS-2026-083
  // (238 files unchanged in count -- hris-training-talent.sql gained the provider-evidence block,
  // proving the new path refuses infected, unscanned, wrong-scope, unauthorized and stale-version
  // attempts under the identical PLT-128 discipline the certificate path already established).
  // History: 46d6bf80aeaa996c56044dd16d5d7a3bfaa194cab4c9d537aae2f9d9a56da84e
  // (238 files, sixty-first-pass state). Superseded 2026-08-31 (sixty-second pass) by
  // ISS-2026-314 (238 files unchanged in count -- scheduled-reports.sql's own assertion that an
  // early trigger ADVANCES next_run_at was asserting the defect, and is replaced by the two
  // assertions that actually separate the cases; the race block now forces the occurrence due
  // before racing it, which is the property it always claimed to test).
  // History: a665ddc29a51b89b85714dff3040e9cde3c6b8c2bf8bb347622d5f8ee490f076
  // (238 files, sixty-second-pass state). Superseded 2026-08-31 (sixty-third pass) by
  // ISS-2026-118 (238 files unchanged in count -- customer-portal-dashboard.sql's stub-card
  // assertion is split, since four of the six stopped being stubs, and a new block pins each
  // composed card's route and summary key plus the absence of a cross-currency summed amount).
  // History: 655cc713cbfb922a36cf665edd5589554904f33484a982ecde6a1bad7cd5c7df
  // (238 files, sixty-third-pass state). Superseded 2026-08-31 (sixty-fourth pass) by
  // ISS-2026-119 (238 files unchanged in count -- customer-portal-scope.sql gained the probe that
  // proves the widened and legacy customer-scope resolvers agree across invited/active/revoked,
  // which is what makes keeping two of them a consistency gap rather than a grant difference).
  // History: 86ffcc1e0f16293b3b2398bfc872504e37af4c4c576e4cfa7efb67c41fd32cef
  // (238 files, sixty-fourth-pass state). Superseded 2026-08-31 (sixty-fifth pass) by
  // ISS-2026-120 (238 files unchanged in count -- customer-warehouse-order-visibility.sql gained
  // seven inbound fixtures and seven assertion blocks, deliberately inside the file that already
  // owns the outbound half rather than in a new one. The reason is the point: the two halves run
  // against the SAME accounts, warehouses, eligibility grants and customer identities, so any
  // divergence in scope resolution, eligibility, anti-enumeration or identity handling between
  // them fails here instead of becoming a quiet asymmetry nobody reads. The inbound block is
  // ordered AFTER the existing revocation block on purpose, which lets it prove the inbound list
  // reads live eligibility rather than a snapshot -- the revoked-warehouse order must already be
  // gone by the time it counts.).
  // History: b7980d9c7091d563b2acd20aed5312d0f476c3484dcdef3f122e95bc192bd7be
  // (238 files, sixty-fifth-pass state). Superseded 2026-08-31 (sixty-sixth pass) by
  // ISS-2026-075 (239 files: +1, hris-export-projection.sql -- the migration set is
  // UNCHANGED, because this pass adds no migration: all four export RPCs have been live
  // and SQL-tested since HRT-278..281; what was missing was any TypeScript caller).
  // Ruling: ADR-0027 Part A.
  //
  // The new file deliberately asserts SHAPES rather than rows. Re-running the four
  // capabilities' own row-level assertions would prove nothing new; what just started
  // existing is a TypeScript parser reading specific column names and types out of these
  // projections, and that join is exactly where ISS-2026-315 was found -- both halves
  // internally consistent, only the contract between them wrong, invisible to either
  // half's own tests. It pins app.* and public.* alike, since PostgREST is what the
  // application actually calls (the ISS-2026-124 lesson), freezes the one real
  // inconsistency in the set (export_leave_requests says employee_code/employee_name
  // where its three siblings say employee_number/employee_full_name, absorbed in one
  // place in TypeScript), pins the audit capture, and pins the leave export's
  // reason/destination/evidence minimisation against a future column addition.
  // History: 2be50cd62631c33667f8f9ea463f201d90eece88cb6c4fd568eddf9890c7a4d1
  // (239 files, sixty-sixth-pass state). Superseded 2026-08-31 (sixty-seventh pass) by
  // ISS-2026-126 / 127 / 128 (239 files unchanged in count -- five existing files widened).
  // customer-loyalty-program-earning.sql, customer-loyalty-membership-tier.sql and
  // customer-loyalty-points-ledger.sql each gained their own sweep block, deliberately placed
  // where that capability's fixtures already live rather than in one new file: a sweep is only
  // meaningfully testable against real eligible AND ineligible records, and those fixtures
  // already exist there. Each block asserts the property that makes a sweep trustworthy -- every
  // candidate is accounted for as processed or skipped, the run completes rather than aborting
  // on the first ineligible record, nothing eligible is left behind, the tenant boundary holds,
  // and re-running under the same label is the same job. The earning block also pins that skip
  // reasons carry the bare error code and never the interpolated message, which for several of
  // these RPCs contains a tenant id (ISS-2026-146 class).
  //
  // task-scheduler.sql's catalogue counts move 16 -> 19, and background-job.sql's job-type
  // mirror gains the three new sweep types. One correction outside this change's own scope,
  // made because it was hiding evidence: audit-trail.sql line 498's \echo carried an unescaped
  // apostrophe, so psql reported "unterminated quoted string" and truncated the description of
  // what that block proves. The assertions themselves always ran; only their label was lost.
  dbTestSetSha256: "913c0bd799b47ae2d8be903cc9e6e0536b90ffcafe8a5383ee3d736940cdace4",
  lockfileSha256: "feafbf67d7d3b98f1612b770c42775dd41b4aa2943f8849f19a2d3e2b450ade7",
};

export type DriftKind = "MIGRATION_SET" | "DB_TEST_SET" | "LOCKFILE";

export interface FreezeDrift {
  readonly kind: DriftKind;
  readonly expected: string;
  readonly actual: string;
  readonly detail: string;
}

function sha256(buffers: readonly Buffer[]): string {
  const hash = createHash("sha256");
  for (const b of buffers) hash.update(b);
  return hash.digest("hex");
}

/**
 * Tracked files under `dir` with the given extension, in the sorted order the
 * freeze digest was computed in. `git ls-files` is used rather than a directory
 * read so an untracked scratch file cannot silently change the digest — and so
 * a *deleted* tracked file does.
 */
export function listTrackedFiles(dir: string, extension: string): string[] {
  const output = execFileSync("git", ["ls-files", "--", `${dir}/*${extension}`], { encoding: "utf8" });
  return output
    .split("\n")
    .map((l) => l.trim())
    .filter(Boolean)
    .sort();
}

export function digestOfFileSet(files: readonly string[]): string {
  return sha256(files.map((f) => readFileSync(f)));
}

export function checkFreeze(frozen: FrozenCandidate = FROZEN_CANDIDATE): FreezeDrift[] {
  const drift: FreezeDrift[] = [];

  const migrations = listTrackedFiles("supabase/migrations", ".sql");
  const migrationDigest = digestOfFileSet(migrations);
  if (migrationDigest !== frozen.migrationSetSha256) {
    drift.push({
      kind: "MIGRATION_SET",
      expected: frozen.migrationSetSha256,
      actual: migrationDigest,
      detail: `${migrations.length} tracked migration file(s) under supabase/migrations/ no longer match the frozen set`,
    });
  }

  const dbTests = listTrackedFiles("scripts/db-tests", ".sql");
  const dbTestDigest = digestOfFileSet(dbTests);
  if (dbTestDigest !== frozen.dbTestSetSha256) {
    drift.push({
      kind: "DB_TEST_SET",
      expected: frozen.dbTestSetSha256,
      actual: dbTestDigest,
      detail: `${dbTests.length} tracked test file(s) under scripts/db-tests/ no longer match the frozen set`,
    });
  }

  const lockfileDigest = digestOfFileSet(["pnpm-lock.yaml"]);
  if (lockfileDigest !== frozen.lockfileSha256) {
    drift.push({
      kind: "LOCKFILE",
      expected: frozen.lockfileSha256,
      actual: lockfileDigest,
      detail: "pnpm-lock.yaml no longer matches the frozen resolved dependency set",
    });
  }

  return drift;
}

function main(): void {
  const drift = checkFreeze();

  if (drift.length === 0) {
    console.log(`✔ release candidate ${FROZEN_CANDIDATE.id} matches its frozen migration, db-test and lockfile digests.`);
    console.log("  (Content gate only — it does not seal direct pushes to main. Production deploys are separately gated by vercel.json + scripts/release/check-go-decision.ts.)");
    return;
  }

  for (const d of drift) {
    console.error(`✖ [${d.kind}] ${d.detail}`);
    console.error(`    expected ${d.expected}`);
    console.error(`    actual   ${d.actual}`);
  }
  console.error(
    `\n${drift.length} freeze violation(s) against ${FROZEN_CANDIDATE.id}. ` +
      "A change here is a change to the release candidate: it needs a release-authority ruling recorded in " +
      "docs/build-log/release-go-live/, not an edit to the expected digests.",
  );
  process.exit(1);
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main();
}
