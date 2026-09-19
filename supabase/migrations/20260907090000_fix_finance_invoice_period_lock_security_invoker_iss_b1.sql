-- CG-AUDIT-2026-09-02 B1 remediation.
--
-- The independent launch-readiness audit (docs/audit/2026-09-02-independent-launch-readiness-audit.md
-- §4 B1) reproduced live: `select app.issue_finance_invoice(...)` as `authenticated` fails with
-- `permission denied for table finance_invoices`. `app.issue_finance_invoice` and
-- `app.lock_finance_period` are the only two *writers* in this schema left `SECURITY INVOKER`
-- among 99 invoker functions granted to `authenticated`, in a database where `authenticated`
-- holds no table privileges by design (every write goes through a `SECURITY DEFINER` RPC that
-- asserts its own authority -- see docs/audit's §5 "Authorization lives in the database,
-- deliberately"). Both functions already perform their own complete, self-contained authority
-- checks before touching any row (`has_active_tenant_membership`, `check_finance_invoice_
-- authority`/`check_finance_period_lock_authority` -- both of which reach
-- `app.assert_actor_is_session_identity` transitively via `app.evaluate_permission`, so the
-- impersonation-closure property this schema maintains elsewhere is already intact here too).
-- The only defect is the privilege mode itself.
--
-- Unlike every other `SECURITY DEFINER` function in this schema (2,148 of 2,148 per the audit),
-- neither function pins `search_path` at all today -- because neither was ever `SECURITY
-- DEFINER`, pinning was never required. This migration adds the pin in the same statement that
-- flips the security mode, so the count becomes 2,150 of 2,150, never a temporary gap.
--
-- Their `public.*` Option-2 wrappers (20260826000000_create_public_api_data_wrappers.sql) already
-- exist and are the actual call path from `server/mutations/invoice.ts` / `period-lock.ts` (both
-- use the RLS-scoped `authenticated` client, per the audit). Those wrappers already pin
-- `search_path = pg_catalog, pg_temp` correctly -- untouched here -- but were generated with
-- `security invoker` to mirror their `app.*` counterpart's (then-correct) mode, per
-- 20260826000000's own "identical grant set, never a reimplementation" convention. They must
-- flip in lockstep with the `app.*` originals, exactly as
-- `20260826010000_harden_public_api_data_wrappers_tierc_fixes.sql` Finding 1 already established
-- for the 140 wrappers found mismatched the other way. `ALTER FUNCTION ... SECURITY {DEFINER|
-- INVOKER}` does not touch `search_path` (search_path is not a security-mode property) or any
-- grant, so the wrappers' existing grants (`service_role`, `authenticated`) are unaffected and
-- remain in parity with their `app.*` counterparts, keeping
-- `scripts/db-tests/public-api-wrapper-regression.sql`'s exhaustive grant/security-mode-parity
-- check green.

alter function app.issue_finance_invoice(uuid, integer, date, uuid, text, text)
  security definer
  set search_path = app, pg_temp;

alter function app.lock_finance_period(uuid, uuid, uuid, text, text, text, uuid, text, text)
  security definer
  set search_path = app, pg_temp;

alter function public.issue_finance_invoice(uuid, integer, date, uuid, text, text)
  security definer;

alter function public.lock_finance_period(uuid, uuid, uuid, text, text, text, uuid, text, text)
  security definer;
