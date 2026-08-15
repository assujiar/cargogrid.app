-- HRT-293 (Sensitive Personal and Payroll Data Controls, CG-S12-HRT-021) --
-- self-found sibling of Finding A, discovered while drafting this
-- checkpoint's own HR_PAYROLL_FIELD_POLICY_MATRIX.md (§2 "Database"
-- dimension) and verified live against a fully-migrated database (not
-- assumed): `has_table_privilege('authenticated', 'app.<table>', 'select')`
-- returned `true` (whole-table, not merely some-columns) for five further
-- Phase 7 HR tables carrying the identical shape Finding A named for
-- app.employees -- a free-text reason/decision column, populated from a
-- caller-supplied narrative parameter, included in a table-wide grant to
-- `authenticated` with no column restriction at all, admitted by RLS to any
-- active tenant member (zero HRS permission required):
--
--   * app.job_applications.rejection_reason / .withdrawal_reason (HRT-276)
--   * app.interviews.cancel_reason (HRT-276)
--   * app.candidate_duplicate_candidates.decided_reason (HRT-276)
--   * app.employee_duplicate_candidates.decided_reason (HRT-274)
--   * app.employee_position_assignments.reason_note / .decided_reason (HRT-275)
--
-- Verified before fixing, not assumed: no read RPC in any of these
-- capabilities' own migrations returns any of these columns (a
-- repository-wide grep for each column name outside its own owning
-- table-definition/constraint/write-site turned up zero SELECT-shaped
-- projections) -- these six columns have NO legitimate read path through
-- this application's own RPC layer at all today, so restricting them is a
-- pure closure of an unused, unintended raw-table bypass, not a narrowing of
-- any real caller's existing functionality (Tier B taxonomy class C-08,
-- re-verified clean).
--
-- A genuine self-found implementation defect corrected before this file was
-- ever applied anywhere real: an earlier draft of this migration issued a
-- bare `revoke select (<col>) on app.<table> from authenticated`, mirroring
-- Finding A's OWN column-level revoke shape verbatim -- but Finding A's own
-- five app.employees columns were removed from an ALREADY column-restricted
-- grant (`grant select (col_a, col_b, ...) ...`), whereas all five tables
-- here were originally granted a PLAIN, whole-table `grant select on
-- app.<table> to authenticated`. PostgreSQL's column-level and table-level
-- ACLs are tracked independently (`pg_class.relacl` vs `pg_attribute.attacl`)
-- -- a column-level REVOKE against a role that holds access only via a
-- TABLE-level GRANT is a genuine no-op (there is no column-level ACL entry
-- to remove), confirmed live: `has_column_privilege('authenticated',
-- 'app.job_applications', 'rejection_reason', 'select')` still returned
-- `true` after the bare `revoke select (rejection_reason) ...` ran with no
-- error at all. Corrected to the SAME two-statement `revoke select on
-- app.<table> from authenticated` (whole table) + `grant select (<every
-- OTHER column, explicit list>) on app.<table> to authenticated` shape
-- app.employee_lifecycle_events' own fix (20260731180000, part 2) already
-- uses correctly for exactly this same "originally a whole-table grant"
-- starting condition -- re-verified live via `information_schema.
-- column_privileges` (not `has_table_privilege`, which returns `true` for
-- ANY column-or-table-level select and would not have caught this) after
-- the fix: zero rows for any of the six restricted columns, non-zero for
-- every sibling column on each table.
--
-- One of the five tables, app.employee_position_assignments, IS read via a
-- raw `.select("*")` in this application's own code
-- (app/(tenant)/[tenantSlug]/hris/positions/[positionId]/page.tsx, per that
-- file's own header comment: "no dedicated 'list assignments by position'
-- RPC exists yet, and RLS already scopes this correctly" -- the exact
-- "RLS scopes rows, never columns" mistake Finding A's own audit text
-- diagnoses). Confirmed live: `reason_note`/`decided_reason` are fetched by
-- that page today but never rendered anywhere in
-- position-detail-panel.tsx (grep-confirmed, zero references) -- so
-- excluding them from that page's own select list is a pure no-op for the
-- UI, not a feature removal. That file is edited in the SAME commit as
-- this migration (not a separate follow-up), since a raw `select("*")`
-- against a column-restricted table would otherwise be rejected outright by
-- Postgres (a `SELECT *` fails if the caller lacks column-level privilege
-- on any column the wildcard would expand to) -- confirmed the explicit
-- column list the page now uses still resolves cleanly post-fix.

revoke select on app.job_applications from authenticated;
grant select (
  id, tenant_id, vacancy_id, candidate_id, stage, source, applied_at, stage_since,
  idempotency_key, record_version, created_by, created_at, updated_at
) on app.job_applications to authenticated;

revoke select on app.interviews from authenticated;
grant select (
  id, tenant_id, application_id, round, mode, scheduled_at, duration_minutes, location_or_link, status,
  record_version, created_by, created_at, updated_at
) on app.interviews to authenticated;

revoke select on app.candidate_duplicate_candidates from authenticated;
grant select (
  id, tenant_id, source_candidate_id, candidate_id, similarity_basis, similarity_score, decision, decided_by, decided_at,
  record_version, created_by, created_at
) on app.candidate_duplicate_candidates to authenticated;

revoke select on app.employee_duplicate_candidates from authenticated;
grant select (
  id, tenant_id, source_master_record_id, candidate_master_record_id, similarity_basis, similarity_score, decision, decided_by, decided_at,
  record_version, created_by, created_at
) on app.employee_duplicate_candidates to authenticated;

revoke select on app.employee_position_assignments from authenticated;
grant select (
  id, tenant_id, master_record_id, position_id, grade_id, manager_employee_id, assignment_type, allocation_pct,
  effective_start_date, effective_end_date, validity_range, status, change_reason, previous_assignment_id,
  source_config_version_id, decided_by, decided_at, record_version, created_by, created_at, updated_at
) on app.employee_position_assignments to authenticated;
