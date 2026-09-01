-- Corrective migration for ISS-2026-309-class defect in 20260902075000
-- (this same session's own public.* wrapper batch for ISS-2026-122/129/
-- 132/134's new app.* functions) -- caught live, running scripts/db-tests/
-- public-api-wrapper-regression.sql's own exhaustive grant-parity
-- assertion (added by 20260830200000, the ORIGINAL registration of this
-- exact defect class) against a fresh disposable database.
--
-- The bug, verbatim repeat of ISS-2026-309: every `revoke execute on
-- function public.X(...) from public;` statement in 20260902075000 revokes
-- only the PUBLIC pseudo-role. Supabase's own `ALTER DEFAULT PRIVILEGES IN
-- SCHEMA public GRANT EXECUTE ON FUNCTIONS TO anon, authenticated,
-- service_role` (mirrored in scripts/db-tests/lib/setup-disposable-db.sh
-- and real on every live project) grants EXECUTE to `anon` explicitly and
-- separately at CREATE FUNCTION time -- a revoke of the PUBLIC pseudo-role
-- never touches it. All ten wrappers 20260902075000 created therefore
-- shipped `anon`-executable, live-verified via pg_proc.proacl on the
-- hosted project before writing this fix (not merely reasoned about):
--
--   public.staff_document_ticket_link_access_ok:  anon=X (app.* counterpart: service_role only)
--   the other nine:                                anon=X (app.* counterpart: authenticated + service_role)
--
-- Exploitability, stated plainly per this repository's own ISS-2026-309
-- disclosure discipline: every one of these ten app.* functions calls
-- app.assert_actor_is_session_identity(p_actor_auth_user_id) as its own
-- first statement (or, for staff_document_ticket_link_access_ok, is called
-- only from within another SECURITY DEFINER function that already did) --
-- an anon caller supplies no real session subject, so every real call
-- still fails closed inside the function body today. This is the
-- "defence-in-depth gap, not a live exploit" class ISS-2026-309's own text
-- names for its four pre-existing widenings, not the "no actor parameter,
-- the grant IS the access control" class its own two change-caused
-- defects were -- still corrected in full, per that same entry's own
-- "leaving a known-wrong grant in place... would be the wrong call."
--
-- ADR-0027 Part C: 20260902075000 is already applied live -- a corrective
-- migration, never an edit in place. Convention followed exactly:
-- `revoke ... from anon, authenticated, service_role, public;` then
-- re-grant only the roles the app.* counterpart actually holds.

revoke execute on function public.staff_document_ticket_link_access_ok(uuid, uuid, uuid, uuid[], text, text) from anon, authenticated, service_role, public;
grant execute on function public.staff_document_ticket_link_access_ok(uuid, uuid, uuid, uuid[], text, text) to service_role;

revoke execute on function public.set_loyalty_reward_voucher_value_config(uuid, uuid, integer, text, numeric, numeric, numeric, uuid, text) from anon, authenticated, service_role, public;
grant execute on function public.set_loyalty_reward_voucher_value_config(uuid, uuid, integer, text, numeric, numeric, numeric, uuid, text) to authenticated, service_role;

revoke execute on function public.set_loyalty_reward_auto_approve_customer_redemption(uuid, uuid, integer, boolean, uuid, text) from anon, authenticated, service_role, public;
grant execute on function public.set_loyalty_reward_auto_approve_customer_redemption(uuid, uuid, integer, boolean, uuid, text) to authenticated, service_role;

revoke execute on function public.set_loyalty_redemption_auto_approval_principal(uuid, uuid, text, uuid, text) from anon, authenticated, service_role, public;
grant execute on function public.set_loyalty_redemption_auto_approval_principal(uuid, uuid, text, uuid, text) to authenticated, service_role;

revoke execute on function public.get_loyalty_redemption_auto_approval_principal(uuid, uuid) from anon, authenticated, service_role, public;
grant execute on function public.get_loyalty_redemption_auto_approval_principal(uuid, uuid) to authenticated, service_role;

revoke execute on function public.clear_loyalty_redemption_auto_approval_principal(uuid, uuid, text) from anon, authenticated, service_role, public;
grant execute on function public.clear_loyalty_redemption_auto_approval_principal(uuid, uuid, text) to authenticated, service_role;

revoke execute on function public.prepare_finance_liability_handoff_from_loyalty_liability(uuid, uuid, uuid, text) from anon, authenticated, service_role, public;
grant execute on function public.prepare_finance_liability_handoff_from_loyalty_liability(uuid, uuid, uuid, text) to authenticated, service_role;

revoke execute on function public.search_loyalty_finance_handoffs_pending_acknowledgement(uuid, uuid) from anon, authenticated, service_role, public;
grant execute on function public.search_loyalty_finance_handoffs_pending_acknowledgement(uuid, uuid) to authenticated, service_role;

revoke execute on function public.acknowledge_loyalty_finance_liability_handoff(uuid, integer, uuid, text) from anon, authenticated, service_role, public;
grant execute on function public.acknowledge_loyalty_finance_liability_handoff(uuid, integer, uuid, text) to authenticated, service_role;

revoke execute on function public.get_loyalty_finance_liability_handoff(uuid, uuid) from anon, authenticated, service_role, public;
grant execute on function public.get_loyalty_finance_liability_handoff(uuid, uuid) to authenticated, service_role;
