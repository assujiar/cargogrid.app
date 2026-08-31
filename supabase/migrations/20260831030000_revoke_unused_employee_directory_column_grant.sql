-- Closes `ISS-2026-189` by making the design ruling it asked for, and by correcting that
-- ruling's boundary where the original column set had drifted past "directory".
--
-- THE FINDING
--
--   `app.employees` carries a 24-column `SELECT` grant to `authenticated`, so any tenant member
--   could read those columns with no `HRS:View` check, unlike full employee reads which route
--   through RBAC-gated RPCs.
--
--   Two prior passes left it open for the same honest reason: whether this is a deliberate "org
--   directory" feature or a defect is a design question, and the fix for the "defect" reading
--   costs real test churn. Neither wanted to pick a side under time pressure. ADR-0027 Part A
--   gives this pass the mandate to decide.
--
-- THE RULING: IT IS A DIRECTORY FEATURE, AND TWO COLUMNS DID NOT BELONG IN IT
--
--   Kept, because a work-facing staff directory readable by colleagues inside the same tenant is
--   normal and expected product behaviour: full_name, work_email, work_phone, position_title, the
--   three org-unit ids, employment_type, lifecycle_status, hire_date, manager_employee_id, and
--   the plumbing columns needed to join them.
--
--   **Removed, because they are not directory data under any reading:**
--
--     probation_end_date   -- discloses that a colleague is on probation
--     employment_end_date  -- discloses that someone is leaving, before it is announced
--
--   Both are ordinary HR facts to an HR user and gossip to everyone else. Had the "accept it as a
--   documented directory feature" option been taken as written, these two would have been
--   accepted along with it, which is exactly the kind of thing a blanket ruling buries.
--
-- WHY THE FULL REVOKE WAS NOT TAKEN -- measured, not assumed
--
--   A complete revoke was written first and run against the full suite. It fails: 49 lines across
--   5 db-test files read `app.employees` directly while the role is `authenticated`
--   (hris-attendance 12, hris-overtime-timesheet 13, hris-shift-roster-scheduling 16,
--   hris-employee-master 6, hris-payroll 2). Every one is scaffolding -- resolving a fixture's
--   `master_record_id` from a `work_email` so the real assertion can run -- not a product path.
--
--   It was not taken because the exposure does not justify 43 careful test rewrites:
--
--     * No product code reads it. There is not one raw `.from("employees")` read anywhere in the
--       TypeScript codebase; every reference is an RPC parameter or a contract parser for an
--       RPC's own return shape.
--     * It is not reachable from a browser. `app` is not exposed to PostgREST -- that is the
--       entire reason this repository carries `public.*` wrappers (RGL-394 Option 2) -- and there
--       is no `public.employees` counterpart (verified: 0 such objects). The grant therefore only
--       has effect over a direct Postgres connection, which no end user holds.
--     * The real PII is already withheld and stays withheld: personal_email, personal_phone,
--       national_id_number, date_of_birth, gender, the five personal_address_* columns, and the
--       free-text revision/suspend/terminate/archive/leave reasons.
--
--   Rewriting 43 assertions' scaffolding carries a real chance of quietly changing what they
--   assert, against an exposure with no browser-reachable path. The measurement is recorded above
--   so the next person can act on it without re-deriving it.
--
-- WHAT MAKES THIS DURABLE
--
--   The accompanying regression guard in `scripts/db-tests/hris-employee-master.sql` pins the
--   exact granted column set. A column added to `app.employees` that quietly arrives with a grant
--   fails the suite, and so does either removed column coming back. The "accept it as a feature"
--   option, taken as written, would have produced no such guard -- it was a decision to keep the
--   grant and describe it.

revoke select (probation_end_date, employment_end_date) on app.employees from authenticated;

comment on column app.employees.probation_end_date is
  'ISS-2026-189: deliberately NOT part of the authenticated directory column grant. Whether a colleague is on probation is an HR fact, not directory data. Readable only through an HRS:View-gated RPC.';

comment on column app.employees.employment_end_date is
  'ISS-2026-189: deliberately NOT part of the authenticated directory column grant. A departure date discloses that someone is leaving before it is announced. Readable only through an HRS:View-gated RPC.';

comment on table app.employees is
  'HRIS employee master (HRT-274). ISS-2026-189 ruling (20260831030000): the column-level SELECT grant to `authenticated` IS a deliberate org-directory feature -- a work-facing staff directory readable by colleagues in the same tenant -- and is kept, minus probation_end_date and employment_end_date, which are HR facts rather than directory data. Real PII (personal contact, national_id_number, date_of_birth, gender, home address, and the free-text lifecycle reasons) has never been granted and still is not. The grant is not browser-reachable: `app` is not exposed to PostgREST and no public.employees counterpart exists, so it has effect only over a direct Postgres connection. scripts/db-tests/hris-employee-master.sql pins the exact granted column set, so it cannot silently grow.';
