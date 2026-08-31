-- Closes `ISS-2026-086` by making the RBAC-model decision it has been correctly waiting for
-- across three passes. ADR-0027 Part A gives this pass the mandate.
--
-- THE FINDING
--
--   `app.is_ticket_staff` grants full ticket-content staff status -- read every internal note,
--   post replies and internal notes, transfer queue, reclassify -- to any holder of `TKT:Edit`,
--   on EVERY ticket in the tenant, regardless of queue. `20260731060000`'s own decision-5 header
--   says the opposite: "TKT:Edit is reserved for QUEUE/CATEGORY CONFIGURATION and on-behalf
--   ticket creation... not for ordinary ticket work."
--
--   The live consequence is not theoretical. A tenant that grants `TKT:Edit` to somebody purely
--   so they can administer queues and categories also, silently and inseparably, grants them the
--   contents of every ticket in the tenant -- including whatever HRS-masked personal data has
--   been quoted into a ticket body, which is `ISS-2026-111`'s own separate finding. There is no
--   way to grant the configuration half without the content half, or to revoke one without the
--   other.
--
-- THE RULING: SPLIT, WHICH IS THE OPTION THE ENTRY ITSELF NAMES
--
--   The entry frames the choice as "keep the blanket override as `redact_ticket_message` already
--   assumes, OR split into a config-only permission plus a separate, explicitly-revocable
--   service-admin grant." Split.
--
--   Keeping it was rejected on what it costs a tenant, not on principle: a permission that
--   cannot be granted for its stated purpose without also handing over every ticket's contents
--   is not a permission a careful administrator can use. The design comment has been right since
--   2026-07-31; only the implementation disagreed with it.
--
--     `TKT:Edit`        -- queue and category configuration, on-behalf ticket creation.
--                          Exactly what its own design comment always claimed. Unchanged
--                          everywhere else in the schema.
--     `TKT:Override`    -- NEW for the TKT module. Tenant-wide ticket-content staff status,
--                          independent of queue membership. Separately grantable, separately
--                          revocable.
--
--   `Override` rather than a freshly-invented action name, and that is not a cosmetic choice.
--   `app.permissions_action_check` is a FIXED 20-value enum reproduced from
--   docs/architecture/06_RLS_RBAC_WORKSTREAM.md §5.1 -- a canonical catalogue, not a list to
--   append to. The first draft of this migration seeded `TKT:Administer` and was rejected by
--   that constraint on its first run, which was the constraint doing its job. `Override` is
--   already in the catalogue, already means "act outside the normal scope" for OPS and FIN, and
--   is exactly what a queue-unscoped, tenant-wide content override is. No constraint is widened.
--
-- WHAT IS DELIBERATELY NOT MOVED, AND WHY -- `app.redact_ticket_message`
--
--   `app.redact_ticket_message` gates directly on `TKT:Edit`, not through `is_ticket_staff`, and
--   its own comment says redaction is deliberately held "to the same bar as queue/category
--   configuration". That gate is left exactly as it is.
--
--   The tempting move is to raise it to `TKT:Override` for consistency, on the reasoning that
--   somebody should not be able to destroy content they cannot read. But the separation is
--   defensible in the other direction and matches the original stated intent: redaction is how
--   leaked personal data gets removed from a ticket, and a queue administrator responding to
--   exactly that is a legitimate, non-disclosing act -- redaction destroys, it does not reveal.
--   Raising the bar would mean a tenant has to hand over every ticket's contents to somebody
--   before they may scrub a leak. That is worse than the problem this migration fixes.
--
--   So the split is precise rather than sweeping: the READ half moves, the destructive-but-
--   non-disclosing half stays where its own design comment put it.
--
-- MIGRATION SAFETY -- measured on the live project, not assumed
--
--   The live hosted project currently holds 0 tenants, 0 tickets, 0 active role assignments and
--   0 role versions carrying `TKT:Edit`, so no live actor loses access. The backfill below is
--   therefore a live no-op, and is written anyway: any OTHER environment that does carry data
--   keeps every current holder's effective access byte-for-byte, because every role version that
--   already grants `TKT:Edit` also gains `TKT:Override`. Nobody is locked out by this change;
--   what changes is that from now on the two halves can be granted and revoked apart.

insert into app.permissions (action, resource_module_code, category, protected)
values ('Override', 'TKT', 'workflow', false)
on conflict do nothing;

-- Backfill, so this is a capability split rather than a silent revocation. Idempotent, and a
-- no-op on the live project (0 matching rows there today).
insert into app.role_version_permissions (role_version_id, permission_id)
select rvp.role_version_id, (select id from app.permissions where resource_module_code = 'TKT' and action = 'Override')
from app.role_version_permissions rvp
join app.permissions p on p.id = rvp.permission_id
where p.resource_module_code = 'TKT' and p.action = 'Edit'
on conflict do nothing;

create or replace function app.is_ticket_staff(p_ticket_id uuid, p_auth_user_id uuid default auth.uid())
returns boolean
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_ticket app.tickets;
  v_self app.employees;
begin
  select * into v_ticket from app.tickets where id = p_ticket_id;
  if not found then
    return false;
  end if;
  if app.is_supreme_admin(p_auth_user_id) then
    return true;
  end if;

  -- HRT-288 (decision 3), preserved byte-for-byte: Platform-support staff status for a helpdesk
  -- case is Supreme-Admin-only. A tenant's own ticket authority -- TKT:Override now included --
  -- must NEVER grant staff status here, because on a helpdesk case the tenant is structurally the
  -- REQUESTER side, not staff. v_ticket.queue_id is always null for a helpdesk ticket
  -- (tickets_queue_shape), so the queue-membership branch below is already naturally false too;
  -- this explicit early return is belt-and-suspenders, not a reliance on that null semantics.
  if v_ticket.channel = 'helpdesk' then
    return false;
  end if;

  -- ISS-2026-086: was `check_ticket_authority('Edit', ...)`. TKT:Edit is queue/category
  -- configuration and on-behalf creation, exactly as 20260731060000's own decision 5 always
  -- said; it no longer silently carries tenant-wide ticket-content access with it.
  if app.check_ticket_authority('Override', v_ticket.tenant_id, p_auth_user_id) then
    return true;
  end if;
  v_self := app.get_self_employee(v_ticket.tenant_id, p_auth_user_id);
  if v_self.master_record_id is not null and v_self.master_record_id = v_ticket.assignee_employee_id then
    return true;
  end if;
  return app.is_ticket_queue_member(v_ticket.queue_id, p_auth_user_id);
end;
$$;

comment on function app.is_ticket_staff is
  'HRT-286/HRT-288, re-scoped by ISS-2026-086 (20260831080000). Staff status on an internal or customer-channel ticket is: Supreme Admin, OR the tenant-wide TKT:Override grant, OR being the ticket''s own assignee employee, OR membership of the ticket''s queue. A helpdesk-channel ticket returns false for every tenant-side path -- the tenant is the requester there, not staff (HRT-288 decision 3). ISS-2026-086 ruling: the tenant-wide branch was TKT:Edit and is now TKT:Override, a separately grantable and separately revocable permission, so a tenant can hand somebody queue/category configuration without also handing them the contents of every ticket in the tenant. app.redact_ticket_message is deliberately NOT moved and still gates on TKT:Edit: redaction destroys content rather than revealing it, it is how a leak gets scrubbed, and requiring full tenant-wide read access before somebody may scrub one would be worse than the problem this fixes.';

comment on function app.check_ticket_authority is
  'HRT-286: SECURITY DEFINER wrapper over app.evaluate_permission(..., ''TKT'', ...) -- mirrors app.check_training_authority (HRT-284) exactly, so RLS policies can evaluate TKT authority without granting authenticated direct access to app.permissions/app.role_version_permissions. ISS-2026-086 (20260831080000) added a TKT:Override action to the catalogue; this wrapper takes the action as a parameter and needed no change.';
