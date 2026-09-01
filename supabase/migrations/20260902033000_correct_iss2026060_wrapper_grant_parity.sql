-- Corrective follow-up to 20260902032000 (ISS-2026-060's three new public.* wrappers).
-- Never edits an applied migration -- ADR-0027 Part C, the exact precedent
-- 20260830200000_correct_public_wrapper_grant_parity.sql already established for this
-- identical class of bug, quoted here rather than re-derived:
--
--   "`public` there is the PUBLIC pseudo-role. It is NOT the `anon` and `authenticated`
--   roles. Supabase ships an ALTER DEFAULT PRIVILEGES rule that grants EXECUTE on every
--   new function in schema public to `anon` and `authenticated` explicitly, so [the]
--   wrapper[s] acquired those grants at CREATE time and the revoke [from public] above
--   never touched them."
--
-- 20260902032000's own three `revoke execute on function public.<name>(...) from
-- public;` statements were exactly this same one-line mistake -- caught here by
-- scripts/db-tests/public-api-wrapper-regression.sql's own grant-parity assertion
-- (added by 20260830200000, extended in the same commit as that precedent), not
-- inherited: `add_vendor_rate_zone_distance_tier`, `remove_vendor_rate_zone_distance_
-- tier`, and `calculate_vendor_rate_zoned` were all three live-executable by `anon` on
-- the same live project this checkpoint applied 20260902032000 to, while their app.*
-- counterparts are authenticated+service_role only (no anon). None of the three
-- app.* functions call app.assert_actor_is_session_identity as their sole defense
-- (they gate on app.evaluate_permission/app.has_prc_view_cost against a supplied
-- actor id instead), so this is corrected immediately, not left for a future sweep.

revoke execute on function public.add_vendor_rate_zone_distance_tier(uuid, integer, text, numeric, numeric, numeric, numeric, text, uuid, text) from anon;
revoke execute on function public.remove_vendor_rate_zone_distance_tier(uuid, integer, uuid, text) from anon;
revoke execute on function public.calculate_vendor_rate_zoned(uuid, text, numeric, numeric, numeric, numeric, uuid) from anon;
