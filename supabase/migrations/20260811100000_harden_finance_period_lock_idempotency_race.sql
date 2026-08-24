-- HDN-374 Tier C (Financial Integrity Audit, `CG-S15-HDN-006`) -- an independent adversarial
-- review lens re-ran this checkpoint's own concurrent-idempotency sweep (`HDN-BLK-010`/
-- `ISS-2026-162`, closed for 10 Finance functions at `20260811000000_harden_financial_
-- integrity_invoicing_and_idempotency.sql`) and found one more: `app.lock_finance_period`
-- shares the exact same shape -- a plain `select` idempotency pre-check (no `for update`)
-- followed by a plain `insert` with no `unique_violation` exception handler, backed by a real
-- unique index (`finance_period_locks_scope_unique`, `tenant_id, company_id, period_id,
-- lock_scope`). Two concurrent FIRST-TIME lock calls for the same tenant/period/scope both
-- pass the pre-check (`not found`), both attempt the `insert`, and the loser gets a raw
-- `duplicate key value violates unique constraint` instead of the graceful outcome every other
-- function in this checkpoint's own sweep now gives.
--
-- This function's own shape is not a pure idempotent-replay (create-once, always return the
-- same row) like the other 10 -- it is closer to an upsert: a not-found row is inserted and
-- locked; a found-but-not-locked row (e.g. `reopened`/`reopen_requested`) is updated to
-- locked; a found-and-already-locked row is returned unchanged (a genuine no-op replay). The
-- race only threatens the not-found/insert branch (two racers can both see not-found); the
-- fix therefore wraps only that insert, and on `unique_violation` re-selects the now-existing
-- row and applies the SAME locked-transition logic the ordinary "found" branch already uses
-- (already-locked -> return unchanged; otherwise -> update to locked), rather than silently
-- discarding the loser's own genuine lock intent.
--
-- Live-forced: a genuine two-process race (two concurrent first-time `lock_finance_period`
-- calls for the same tenant/period/scope) reproduced the raw `duplicate key value violates
-- unique constraint "finance_period_locks_scope_unique"` on the losing process before this
-- fix; both processes now return the identical, correctly `locked` row. Regression test:
-- `scripts/db-tests/finance-period-lock.sql`'s own new HDN-374 Tier C block.

create or replace function app.lock_finance_period(
  p_tenant_id uuid,
  p_company_id uuid,
  p_period_id uuid,
  p_lock_scope text,
  p_reason text,
  p_evidence_ref text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.finance_period_locks
language plpgsql
as $$
declare
  v_lock app.finance_period_locks;
  v_period app.finance_fiscal_periods;
begin
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % holds no active membership for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.check_finance_period_lock_authority('Approve', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'finance_period_lock_reason_required: a non-empty reason is required' using errcode = 'check_violation';
  end if;
  if p_lock_scope not in ('all', 'gl', 'ar', 'ap', 'tax') then
    raise exception 'finance_period_lock_invalid_scope: % is not a supported lock scope', p_lock_scope using errcode = 'check_violation';
  end if;

  select * into v_period from app.finance_fiscal_periods where id = p_period_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'finance_period_not_found: % is not a known fiscal period for tenant %', p_period_id, p_tenant_id
      using errcode = 'no_data_found';
  end if;

  select * into v_lock from app.finance_period_locks
    where tenant_id = p_tenant_id and period_id = p_period_id and lock_scope = p_lock_scope
      and coalesce(company_id, '00000000-0000-0000-0000-000000000000'::uuid) = coalesce(p_company_id, '00000000-0000-0000-0000-000000000000'::uuid);

  if found and v_lock.status = 'locked' then
    return v_lock;
  end if;

  if found then
    update app.finance_period_locks
      set status = 'locked', lock_reason = p_reason, evidence_ref = p_evidence_ref, locked_by = p_actor_label, locked_at = now(),
          relocked_by = p_actor_label, relocked_at = now()
      where id = v_lock.id
      returning * into v_lock;
  else
    -- HDN-374 Tier C fix: a genuine race between the not-found check above and this insert
    -- (two concurrent first-time lock calls for the same tenant/period/scope) is resolved by
    -- re-selecting the now-existing row and applying the same locked-transition logic the
    -- ordinary "found" branch above already uses, rather than surfacing a raw unique_violation
    -- or silently discarding the loser's own genuine lock intent.
    begin
      insert into app.finance_period_locks (tenant_id, company_id, period_id, lock_scope, lock_reason, evidence_ref, locked_by, created_by)
      values (p_tenant_id, p_company_id, p_period_id, p_lock_scope, p_reason, p_evidence_ref, p_actor_label, p_actor_label)
      returning * into v_lock;
    exception
      when unique_violation then
        select * into v_lock from app.finance_period_locks
          where tenant_id = p_tenant_id and period_id = p_period_id and lock_scope = p_lock_scope
            and coalesce(company_id, '00000000-0000-0000-0000-000000000000'::uuid) = coalesce(p_company_id, '00000000-0000-0000-0000-000000000000'::uuid);
        if not found then
          raise;
        end if;
        if v_lock.status = 'locked' then
          return v_lock;
        end if;
        update app.finance_period_locks
          set status = 'locked', lock_reason = p_reason, evidence_ref = p_evidence_ref, locked_by = p_actor_label, locked_at = now(),
              relocked_by = p_actor_label, relocked_at = now()
          where id = v_lock.id
          returning * into v_lock;
    end;
  end if;

  insert into app.finance_period_lock_events (lock_id, tenant_id, action, reason, actor_label) values (v_lock.id, p_tenant_id, 'locked', p_reason, p_actor_label);

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'lock_finance_period',
    'app.finance_period_locks', v_lock.id, 'success', p_reason, null, to_jsonb(v_lock)
  );

  return v_lock;
end;
$$;

revoke execute on all functions in schema app from public;
