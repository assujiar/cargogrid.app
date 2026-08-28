-- Track B Batch 4 (loyalty-approval-authority), ISS-2026-137
-- (docs/runtime/KNOWN_ISSUES.md): app.loyalty_account_tier_movements
-- carries the identical Supreme-Admin-override gap ISS-2026-130 already
-- closed for Phase 8's own 5 append_only_ledger-family tables
-- (supabase/migrations/20260801280000_harden_customer_portal_loyalty_
-- ledger_supreme_admin_override.sql), but was not itself included in that
-- fix -- it was named in ISS-2026-130's own ORIGINAL four-table list
-- (Batch 4, before CPL-320/CPL-321 existed) yet omitted from CPL-325's own
-- explicit 5-table remediation scope, which instead named the two newer
-- Batch-5 tables (app.loyalty_reward_stock_reservations/app.loyalty_
-- redemption_events) that postdate ISS-2026-130's own original disclosure.
--
-- Independently re-verified before drafting this fix (not accepted from
-- the issue's own text at face value): app.loyalty_account_tier_movements
-- (supabase/migrations/20260801190000_create_customer_portal_loyalty_
-- membership_tier.sql:1192) still grants only `select, insert` to
-- service_role -- zero UPDATE/DELETE to any role, staff or Supreme Admin
-- alike -- and it carries a direct tenant_id column (same CREATE TABLE
-- shape, line 288) and its own id primary key, the exact two columns
-- app.protect_loyalty_ledger_append_only() (already generic, keyed off
-- TG_TABLE_NAME/OLD.tenant_id/OLD.id, no table-specific logic) requires.
--
-- This migration is the single, bounded, well-understood follow-up
-- ISS-2026-137's own recommended fix names verbatim: extend the SAME
-- already-generic, already-tested trigger function to this one additional
-- table, plus the matching grant -- no new design, no new function body,
-- mirroring 20260801280000 exactly for this 6th table.
--
-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): this migration carries
-- its own explicit `revoke execute on all functions in schema app from
-- public` statement before its final grants, the standing per-migration
-- convention since PLT-118.

create trigger loyalty_account_tier_movements_protect_append_only
  before update or delete on app.loyalty_account_tier_movements
  for each row
  execute function app.protect_loyalty_ledger_append_only();

grant update, delete on app.loyalty_account_tier_movements to service_role;

-- Per ERR-2026-004: explicit, directly-provable revoke of PostgreSQL's
-- PUBLIC-execute default, applied before any role-specific grant below.
revoke execute on all functions in schema app from public;

grant execute on function app.protect_loyalty_ledger_append_only() to service_role;
