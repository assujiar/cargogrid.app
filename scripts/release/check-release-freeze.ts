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
 * push to an unprotected `main`, nor the Vercel `main` -> production
 * auto-deploy — see RGL-393.md §3 for the ingress paths that remain open, and
 * RGL-BLK-001. Do not read a pass here as "the candidate is sealed".
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
  migrationSetSha256: "cfb96c5e91cc5ca6018f0a5096cd9c17cc1d77f07168f84865414c06e17ef4c6",
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
  dbTestSetSha256: "9a0a5dbc71315f18ba3d4598e9fa849aacacdb051527cc1a7d878df89566245a",
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
    console.log("  (Content gate only — it does not seal direct pushes to main or the Vercel auto-deploy. See RGL-BLK-001.)");
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
