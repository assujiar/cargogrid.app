-- Self-found-and-fixed security gap in 20260902072500 (the same-day rename
-- of app.search_loyalty_finance_handoffs_pending_acknowledgement): that
-- migration's own CREATE FUNCTION statement was never followed by the
-- mandatory `revoke execute ... from public` (ERR-2026-004) before its
-- own explicit grants -- PostgreSQL grants EXECUTE on a newly created
-- function to PUBLIC by default, so this function was, briefly, callable
-- by `anon` via the implicit PUBLIC grant. Caught live, running scripts/
-- db-tests/public-api-wrapper-regression.sql's own exhaustive grant-parity
-- check while building this same fix's own wrapper functions -- that file
-- would have failed loudly the moment a public.* wrapper was added with a
-- narrower (correct) grant set than its app.* counterpart.
--
-- Every actual caller of this function already required FIN:View authority
-- internally (app.evaluate_permission), so this was never a live data leak
-- -- but the grant itself should never have existed. Fixed by explicit
-- REVOKE, restoring the identical grant set (authenticated, service_role
-- only) every other function in this same migration set already carries.

revoke execute on function app.search_loyalty_finance_handoffs_pending_acknowledgement(uuid, uuid) from public;
