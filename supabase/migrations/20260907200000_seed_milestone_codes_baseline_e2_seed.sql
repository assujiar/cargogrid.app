-- CG-AUDIT-2026-09-02 E2-seed remediation (bundled sub-finding of E2, tracked separately in
-- the remediation backlog's own Housekeeping section). `app.milestone_codes` (OPS-173,
-- 20260727140000) is the permanent, platform-wide canonical milestone code registry --
-- Supreme-Admin-only to write, idempotent on `code` -- but ships with ZERO seeded rows on a
-- fresh install: `ingest-milestone-event-form.tsx`'s own milestone-code dropdown is a live,
-- reproducible dead end for a brand-new tenant until SOME Supreme Admin registers a first
-- code by hand.
--
-- A prior attempt at this seed (recorded in the backlog's own execution log) was reverted
-- after it silently broke a real test: `app.register_milestone_code` returns the FIRST-ever
-- registered row for a given `code` and never updates it again (its own header comment:
-- "idempotent... a repeated call with an existing code returns that row, never raises"), so
-- a migration-time seed's own is_customer_visible/affects_eta/is_terminal choice for a code
-- permanently pre-empts every later scripts/db-tests/*.sql fixture that registers the SAME
-- code with a DIFFERENT expectation -- confirmed live at the time:
-- operations-milestone-management.sql's own internal-only `customs_hold` regressed to
-- customer-visible because the reverted seed had guessed the wrong flags for that code.
--
-- This attempt is built the way the reverted one was not: from a full audit of every one of
-- the 33 real `app.register_milestone_code(...)` call sites across all 11 db-test files that
-- use this registry (`grep -rn register_milestone_code scripts/db-tests/*.sql`), grouped by
-- `code`, before writing a single `insert`. Two REAL, independent cross-file disagreements
-- were found this time (not the earlier attempt's own wrong guess -- these are two different
-- test files genuinely expecting two different things for the SAME code):
--   - `delivery_arrival`: advanced-tms-geofence-route-deviation-signals.sql expects
--     (affects_eta=false, is_terminal=false); advanced-tms-wms-integrated-verification.sql
--     expects (affects_eta=true, is_terminal=true) for the identical code.
--   - `delivered`: operations-integrated-verification.sql and operations-milestone-
--     management.sql both expect affects_eta=true; operations-public-tracking.sql expects
--     affects_eta=false for the identical code.
-- Both are deliberately EXCLUDED from this seed -- there is no value this migration could
-- choose that would not silently break one of those two files' own current, passing
-- assertions, exactly the failure mode that sank the earlier attempt. They remain registered
-- dynamically, on demand, precisely as today (zero behavior change for either).
--
-- Every OTHER code below was confirmed byte-for-byte identical (same name/category/
-- is_customer_visible/affects_eta/is_terminal) across every one of its own real call sites --
-- `picked_up` alone appears identically in 4 separate files (operations-dashboard.sql,
-- operations-integrated-verification.sql, operations-milestone-management.sql,
-- operations-public-tracking.sql). Seeding these does not change what any of those
-- call sites already observed (register_milestone_code was already idempotently returning
-- exactly these values, whichever file happened to register first); it only means a fresh
-- tenant with NO db-test fixtures ever run against it sees a real, usable set instead of an
-- empty dropdown. File-prefixed, obviously test-only codes (`customer_tracking_*`,
-- `iaeeta_*`, `vperf_*`, `iss146b_*`) are excluded on purpose -- they are synthetic fixture
-- identifiers, not a real production baseline, and none of them collides with a seeded code
-- here (registered fresh by their own file, exactly as before).
--
-- Plain `insert`, no `on conflict` clause needed: this migration runs exactly once, against
-- a table that starts empty, mirroring `20260729090000_create_finance_tax_baseline.sql`'s own
-- `app.finance_tax_codes` platform-catalog seed precedent (labels-only, `registered_by` =
-- 'platform-foundation' mirroring that migration's own 'finance-foundation' label).

insert into app.milestone_codes (code, name, category, is_customer_visible, affects_eta, is_terminal, registered_by) values
  ('pickup_arrival', 'Pickup Arrival', 'pickup', true, false, false, 'platform-foundation'),
  ('pickup_departure', 'Pickup Departure', 'pickup', true, false, false, 'platform-foundation'),
  ('picked_up', 'Picked Up', 'pickup', true, false, false, 'platform-foundation'),
  ('departed_origin', 'Departed Origin', 'in_transit', true, false, false, 'platform-foundation'),
  ('in_transit', 'In Transit', 'in_transit', true, true, false, 'platform-foundation'),
  ('customs_hold', 'Customs Hold', 'exception', false, false, false, 'platform-foundation'),
  ('out_for_delivery', 'Out for Delivery', 'delivery', true, true, false, 'platform-foundation'),
  ('delivery_departure', 'Delivery Departure', 'delivery', true, false, true, 'platform-foundation');
