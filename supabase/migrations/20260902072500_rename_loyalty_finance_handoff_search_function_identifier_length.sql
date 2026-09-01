-- Self-found-and-fixed quality gap in 20260902072000 (ISS-2026-134 item
-- 5): app.search_loyalty_finance_liability_handoffs_pending_acknowledgement
-- is 65 characters, over Postgres' 63-byte NAMEDATALEN-1 identifier limit
-- -- silently, consistently truncated by Postgres itself to
-- search_loyalty_finance_liability_handoffs_pending_acknowledgeme (63
-- chars) at both CREATE and CALL time, so it was never actually broken,
-- but it is not the name this repository's own db-test evidence (and any
-- future caller) should have to spell out or risk colliding against.
-- Caught live, running this same fix's own db-test evidence, before this
-- entry was ever reported closed.
--
-- Renamed by DROP + CREATE (a rename, not merely a body replace) to app.
-- search_loyalty_finance_handoffs_pending_acknowledgement (55 chars,
-- comfortably under the limit) -- drops "_liability" only from this ONE
-- function's own name (the table, and the other three functions in this
-- same family, are all comfortably under the limit already and are
-- unchanged). Behavior, signature, grants, and RLS posture are otherwise
-- byte-identical to 20260902072000's own original.

drop function if exists app.search_loyalty_finance_liability_handoffs_pending_acknowledgeme(uuid, uuid);

create function app.search_loyalty_finance_handoffs_pending_acknowledgement(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns setof app.loyalty_finance_liability_handoff_batches
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if not (app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'FIN', 'View')).allowed then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  return query select * from app.loyalty_finance_liability_handoff_batches
    where tenant_id = p_tenant_id and status = 'pending_acknowledgement'
    order by generated_at asc
    limit 200;
end;
$$;

comment on function app.search_loyalty_finance_handoffs_pending_acknowledgement is
  'ISS-2026-134 item 5 (renamed 2026-09-02, same day as creation -- see this migration''s own header): mirrors app.search_payroll_finance_handoffs_pending_acknowledgement (HRT-282) exactly -- how Finance discovers what Loyalty has prepared, gated on FIN:View, without Loyalty ever reaching into a Finance table.';

grant execute on function app.search_loyalty_finance_handoffs_pending_acknowledgement(uuid, uuid) to authenticated, service_role;
