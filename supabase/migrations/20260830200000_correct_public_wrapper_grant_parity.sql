-- Registers and closes ISS-2026-309 (docs/runtime/KNOWN_ISSUES.md).
--
-- A CHANGE-CAUSED SECURITY DEFECT, FOUND BY THE LIVE ADVISOR SWEEP AND OWNED HERE.
--
--   Two of the public.* wrappers this session added -- public.evaluate_ip_access
--   (20260830170000) and the seven-argument public.raise_observability_alert
--   (20260830180000) -- are executable by the `anon` role on the live project. Both are
--   SECURITY DEFINER. Their app.* counterparts are service_role-only, and the wrappers were
--   written to mirror them.
--
--   The bug is one line, repeated in both files:
--
--       revoke execute on function public.evaluate_ip_access(...) from public;
--
--   `public` there is the PUBLIC pseudo-role. It is NOT the `anon` and `authenticated` roles.
--   Supabase ships an ALTER DEFAULT PRIVILEGES rule that grants EXECUTE on every new function
--   in schema public to `anon` and `authenticated` explicitly, so both wrappers acquired those
--   grants at CREATE time and the revoke above never touched them. Live proof, after applying:
--
--       public.assert_ip_allowed          postgres=X | service_role=X
--       public.evaluate_ip_access         postgres=X | anon=X | authenticated=X | service_role=X
--       public.raise_observability_alert/6  postgres=X | service_role=X
--       public.raise_observability_alert/7  postgres=X | anon=X | authenticated=X | service_role=X
--
--   The pre-existing wrapper of each pair is clean; only the two added this session are wide.
--   Every other wrapper added this session (20260830100000/120000/130000/140000/150000) used
--   `revoke ... from anon, authenticated, service_role, public` and is unaffected -- which is
--   what makes this a slip in two files rather than a misunderstanding of the convention.
--
-- WHY THIS ONE IS EXPLOITABLE AND THE OTHERS IN THE SAME SWEEP ARE NOT
--
--   Most app.* RPCs open with app.assert_actor_is_session_identity(p_actor_auth_user_id),
--   which an anon caller cannot pass -- there is no JWT subject to match. These two have no
--   actor parameter and no such guard, deliberately: app.evaluate_ip_access decides on a raw
--   (IP, scope) pair and must stay reachable from an API-key caller with no auth_user_id at
--   all, and app.raise_observability_alert is system-to-system telemetry. Their entire access
--   control IS the grant. So on the live project, before this migration, an unauthenticated
--   caller could reach both over PostgREST and:
--
--     - probe any tenant's IP allowlist, since the return value states allowed/denied, and
--       write an unbounded number of rows into app.ip_access_evaluations doing it;
--     - forge arbitrary incidents at any severity, for any tenant, via the seven-argument
--       raise_observability_alert -- including drowning a real incident in noise.
--
--   Recorded plainly because it was real, and because it was introduced by this session's own
--   work rather than inherited.
--
-- THE FOUR PRE-EXISTING WIDENINGS, KEPT SEPARATE FROM THE TWO ABOVE
--
--   The same live query found four wrappers that predate this session and are also `anon`-
--   executable while their app.* counterpart is authenticated+service_role:
--
--       public.get_customer_portal_invoice/3        public.list_customer_portal_invoices/6
--       public.get_loyalty_point_program_expiry_config/3
--       public.set_loyalty_point_program_expiry_config/5
--
--   All four DO call app.assert_actor_is_session_identity, so an anon caller is refused inside
--   the function body and no data is reachable today. They are defence-in-depth gaps, not live
--   exploits, and they are baseline rather than change-caused -- stated here so the two classes
--   are not merged. They are corrected in the same migration because the fix is identical and
--   leaving a known-wrong grant in place to preserve a tidy boundary would be the wrong call.
--
--   public.has_active_tenant_membership/2 is the one mismatch in the OTHER direction -- the
--   wrapper lacks service_role, which its app.* counterpart has. That is a functionality gap,
--   not a security one, and it is corrected here too so the parity assertion added alongside
--   this migration can be exhaustive rather than carrying an exception list.
--
-- WHY A CORRECTIVE MIGRATION RATHER THAN AN EDIT
--
--   20260830170000 and 20260830180000 are applied on the live project. ADR-0027 Part C:
--   "No applied migration may be edited. Corrective migrations only." The two files keep their
--   defect in the record and this file states what it was.
--
-- THE GATE THAT SHOULD HAVE CAUGHT IT
--
--   scripts/db-tests/public-api-wrapper-regression.sql already asserts, exhaustively, that
--   every externally-callable app.* function has a public.* wrapper with a MATCHING SECURITY
--   MODE. It caught two real defects earlier in this session. It never compared GRANTS, so a
--   wrapper with the right security mode and a wider grant set passed it cleanly -- and did.
--   That test is extended in the same commit to assert grant parity, and it fails against the
--   database as it stood before this migration.

-- ===========================================================================
-- 1. The two change-caused defects. Match the app.* counterpart: service_role only.
-- ===========================================================================

revoke execute on function public.evaluate_ip_access(uuid, text, text, text) from anon, authenticated;

revoke execute on function public.raise_observability_alert(uuid, text, text, text, text, text, text) from anon, authenticated;

-- ===========================================================================
-- 2. The four pre-existing anon widenings. Match the app.* counterpart:
--    authenticated + service_role, never anon.
-- ===========================================================================

revoke execute on function public.get_customer_portal_invoice(uuid, uuid, uuid) from anon;

revoke execute on function public.list_customer_portal_invoices(uuid, uuid, text, timestamptz, uuid, integer) from anon;

revoke execute on function public.get_loyalty_point_program_expiry_config(uuid, uuid, uuid) from anon;

revoke execute on function public.set_loyalty_point_program_expiry_config(uuid, uuid, integer, uuid, text) from anon;

-- ===========================================================================
-- 3. The one mismatch in the other direction -- a missing grant, not a wide one.
-- ===========================================================================

grant execute on function public.has_active_tenant_membership(uuid, uuid) to service_role;
