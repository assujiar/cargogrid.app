-- Finance capability FIN-204 (Posted-Journal Integrity, CG-S9-FIN-015)
-- Protects posted journals and their lines from normal-role mutation while
-- explicitly implementing and disclosing the RPD-022 Supreme Admin
-- absolute-CRUD exception -- never a tamper-proof or universal-immutability
-- claim.
--
-- Baseline protection, already real since FIN-197 (disclosed, not rebuilt
-- here): every posted-state Finance table in this repository (finance_invoices,
-- finance_ar_open_items, finance_ap_open_items, finance_vendor_bills,
-- finance_receipts/finance_receipt_allocations,
-- finance_settlements/finance_settlement_allocations,
-- finance_subledger_batches/finance_subledger_lines, and FIN-203's own
-- finance_journals/finance_journal_lines) carries zero UPDATE/DELETE grant
-- for `authenticated` -- the repository-wide `PLT-118` convention
-- (`ERR-2026-004`). A normal-role direct-table mutation is already
-- structurally impossible; every real mutation is a `service_role`-only,
-- authority-checked function call. See `docs/standards/SECURITY_STANDARDS.md`
-- section 7 for the full protection matrix this checkpoint records.
--
-- What this migration actually adds (Prompt 204 section 4's own bounded
-- scope -- Posted-*Journal* Integrity, the named epic): a table-level
-- trigger on `app.finance_journals`/`app.finance_journal_lines` that blocks
-- *any* UPDATE/DELETE against an already-posted row -- a strictly stronger
-- guarantee than the grant-only protection every other Finance table above
-- relies on, since it also blocks a hypothetical `service_role`-level
-- direct mutation outside the vetted RPC surface (a bug in a future
-- capability, a manual support script, etc.) -- unless the acting identity
-- holds a live `supreme_admin` principal membership (`app.is_supreme_admin`,
-- read via `auth.uid()`, RPD-022's own disclosed absolute-CRUD exception,
-- reused unmodified from `PLT-113`).
--
-- RPD-022 exercised, not defeated by silence: when `app.is_supreme_admin`
-- returns true and the touched row was already posted, the trigger still
-- permits the mutation but captures a best-effort `app.capture_audit_event`
-- row disclosing the bypass -- a detective control, never a preventive
-- guarantee against a Supreme Admin who also controls the database
-- directly. No artifact in this repository claims tamper-proof or
-- universal immutability; every posted-record UI state is worded as
-- "correction uses governed reversal" (FIN-206), never "cannot be changed."
--
-- Correction path (Prompt 204 section 21/32): a normal role's only path to
-- correct a posted journal is a governed reversal/adjustment, explicitly
-- FIN-206's own scope (Reversal and Adjustment) -- not built here, the same
-- disclosed forward reference FIN-203's own header already recorded for
-- reversal.
--
-- Per `ERR-2026-004` (`docs/runtime/ERROR_LEDGER.md`): this migration
-- carries its own explicit `REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA app
-- FROM PUBLIC` statement before its final grants, the standing
-- per-migration convention since `PLT-118`.

-- Table-level guard for app.finance_journals. Fires for every UPDATE/DELETE
-- regardless of caller role (authenticated already has no grant at all;
-- this additionally blocks service_role and any other privileged role
-- unless RPD-022's own Supreme Admin exception applies).
create function app.protect_posted_finance_journal()
returns trigger
language plpgsql
as $$
declare
  v_actor uuid := auth.uid();
begin
  if TG_OP = 'DELETE' then
    if OLD.status = 'posted' and not app.is_supreme_admin(v_actor) then
      raise exception 'finance_journal_posted_immutable: normal roles cannot delete posted journal % -- use a governed reversal (FIN-206) instead', OLD.id
        using errcode = 'insufficient_privilege';
    end if;
    if OLD.status = 'posted' then
      perform app.capture_audit_event(
        OLD.tenant_id, v_actor, 'supreme_admin_absolute_crud', 'delete_posted_finance_journal',
        'app.finance_journals', OLD.id, 'success', 'RPD-022 absolute-CRUD exception invoked (best-effort evidence, not a preventive control)', to_jsonb(OLD), null
      );
    end if;
    return OLD;
  end if;

  if OLD.status = 'posted' and not app.is_supreme_admin(v_actor) then
    raise exception 'finance_journal_posted_immutable: normal roles cannot modify posted journal % -- use a governed reversal (FIN-206) instead', OLD.id
      using errcode = 'insufficient_privilege';
  end if;
  if OLD.status = 'posted' then
    perform app.capture_audit_event(
      OLD.tenant_id, v_actor, 'supreme_admin_absolute_crud', 'mutate_posted_finance_journal',
      'app.finance_journals', OLD.id, 'success', 'RPD-022 absolute-CRUD exception invoked (best-effort evidence, not a preventive control)', to_jsonb(OLD), to_jsonb(NEW)
    );
  end if;
  return NEW;
end;
$$;

comment on function app.protect_posted_finance_journal is
  'FIN-204: table-level guard, fires for every UPDATE/DELETE regardless of caller role. Blocks any mutation of an already-posted app.finance_journals row unless app.is_supreme_admin (RPD-022) -- a detective, best-effort-evidenced exception, never a tamper-proof claim.';

create trigger finance_journals_protect_posted
  before update or delete on app.finance_journals
  for each row
  execute function app.protect_posted_finance_journal();

-- Table-level guard for app.finance_journal_lines -- resolves the parent
-- journal's own status, since a line carries no status of its own.
create function app.protect_posted_finance_journal_line()
returns trigger
language plpgsql
as $$
declare
  v_journal app.finance_journals;
  v_actor uuid := auth.uid();
  v_row_id uuid := coalesce(OLD.id, NEW.id);
  v_journal_id uuid := coalesce(OLD.journal_id, NEW.journal_id);
begin
  select * into v_journal from app.finance_journals where id = v_journal_id;

  if v_journal.status = 'posted' and not app.is_supreme_admin(v_actor) then
    raise exception 'finance_journal_line_posted_immutable: normal roles cannot % a line of posted journal % -- use a governed reversal (FIN-206) instead', lower(TG_OP), v_journal.id
      using errcode = 'insufficient_privilege';
  end if;
  if v_journal.status = 'posted' then
    perform app.capture_audit_event(
      v_journal.tenant_id, v_actor, 'supreme_admin_absolute_crud', lower(TG_OP) || '_posted_finance_journal_line',
      'app.finance_journal_lines', v_row_id, 'success', 'RPD-022 absolute-CRUD exception invoked (best-effort evidence, not a preventive control)',
      to_jsonb(OLD), case when TG_OP = 'DELETE' then null else to_jsonb(NEW) end
    );
  end if;

  if TG_OP = 'DELETE' then
    return OLD;
  end if;
  return NEW;
end;
$$;

comment on function app.protect_posted_finance_journal_line is
  'FIN-204: table-level guard, fires for every UPDATE/DELETE regardless of caller role. Blocks any mutation of a line belonging to an already-posted app.finance_journals row unless app.is_supreme_admin (RPD-022).';

create trigger finance_journal_lines_protect_posted
  before update or delete on app.finance_journal_lines
  for each row
  execute function app.protect_posted_finance_journal_line();

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit, directly-provable
-- revoke of PostgreSQL's PUBLIC-execute default, the standing per-migration
-- convention since PLT-118, applied here before any role-specific grant.
revoke execute on all functions in schema app from public;

grant execute on function app.protect_posted_finance_journal() to service_role;
grant execute on function app.protect_posted_finance_journal_line() to service_role;

-- app.is_supreme_admin (PLT-113) was previously granted to `authenticated`
-- only (RLS-policy caller context); this trigger's own body calls it while
-- running under whichever role performs the direct table mutation --
-- service_role in every real deployment, since authenticated already holds
-- no UPDATE/DELETE grant on app.finance_journals at all. An additive grant
-- statement only; app.is_supreme_admin's own function body is untouched.
grant execute on function app.is_supreme_admin(uuid) to service_role;

-- This migration's own trigger functions call auth.uid() directly (to
-- capture the acting identity for RPD-022 evidence, not only to resolve
-- app.is_supreme_admin's own default argument) -- unlike every existing
-- RLS-policy caller, which only ever invokes app.is_supreme_admin()/
-- app.has_active_tenant_membership() with no explicit argument (their own
-- default-argument evaluation runs under each function's own `security
-- definer` privileges, never requiring the caller to hold schema auth
-- usage directly). A direct `auth.uid()` reference from plain plpgsql
-- code, as this migration's own triggers require, needs real USAGE on
-- schema auth for whichever role performs the table mutation --
-- service_role in every real deployment.
grant usage on schema auth to service_role;
