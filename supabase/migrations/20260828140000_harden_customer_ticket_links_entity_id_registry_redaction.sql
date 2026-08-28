-- ISS-2026-102 (Track B Batch 6): app.list_customer_ticket_links still
-- surfaces a real internal entity_id (and its entity_type) for a link whose
-- type is OUTSIDE the customer-safe registry (vendor/user) -- the same gap
-- HRT-295's own resolution note for the sibling ISS-2026-110 finding
-- explicitly named and deferred: "Entity_type/entity_id scope narrowing is
-- unchanged -- that is ISS-2026-102, not this finding" (comment on function
-- app.list_customer_ticket_links, 20260731300000).
--
-- ===========================================================================
-- Root cause (re-verified live against the current, post-Tier-C function
-- body, 20260731300000, not the superseded 20260731270000 draft)
-- ===========================================================================
--
-- app.list_customer_ticket_links projects `l.entity_id` (and `l.entity_type`)
-- straight off app.ticket_links with no branch on the customer-safe registry
-- at all. Staff are not type-restricted when linking (app.link_ticket_record
-- has no customer-layer check when the ACTOR is staff -- only a customer-
-- layer ACTOR is restricted to the safe registry, decision 7 of
-- 20260731170000). So an admin can link a real vendor or a real user record
-- to a customer-channel ticket; the SAME ticket's own customer requester
-- then reads it back via app.list_customer_ticket_links and receives
-- `entity_type='vendor', entity_id=<the real vendor master_record_id>` (or
-- 'user'/<real app.users.id>) verbatim. `label`/`detail` are already
-- correctly withheld for this case -- app._ticket_link_resolve_candidate
-- (20260801160000) returns no row for a customer-layer caller against
-- 'vendor' (gated on PRC:View, which no customer_user layer ever holds) or
-- 'user' (gated on `not app.actor_holds_customer_user_layer`, which is false
-- by construction for this caller) -- so `live_available=false` and
-- `status_label='unavailable'` already fire correctly. Only entity_type/
-- entity_id themselves were never masked.
--
-- ===========================================================================
-- Fix, mirroring the established "Support Team" substitution pattern for
-- created_by in this SAME function (per this entry's own resolution note)
-- ===========================================================================
--
-- entity_id is replaced with a fixed nil-UUID redaction marker
-- ('00000000-0000-0000-0000-000000000000') for any row whose entity_type is
-- NOT in app.ticket_link_customer_safe_entity_types() -- the same live
-- registry function app.link_ticket_record/app.search_ticket_link_
-- candidates already consult (20260731170000), so this stays drift-safe
-- with the actual customer-link-creation boundary rather than re-hardcoding
-- the four-value list a second time. entity_type itself is left unchanged:
-- a bare category label ("vendor" was linked here) is not "a real internal
-- record id" -- the specific disclosure this finding and its own severity
-- assessment name -- and nulling it would require widening the shared,
-- CHECK-constrained six-value TicketLinkEntityType registry (used for
-- write-side validation too) for a customer-only display concern, a wider
-- blast radius than this bounded fix warrants. The redaction marker is used
-- (not SQL NULL) because entity_id is a NOT NULL column on app.ticket_links
-- and the shared TicketLinkRowSchema (server/contracts/ticketing/
-- ticketing.ts, used by BOTH the staff and customer projections) requires a
-- non-null uuid -- widening that shared schema to accept null would also
-- affect the staff-facing app.list_ticket_links read, which must keep
-- returning the real id unconditionally. The nil UUID cannot collide with a
-- real gen_random_uuid()-issued id.
--
-- The staff-facing app.list_ticket_links (20260731170000) is NOT touched --
-- staff legitimately need the real entity_id for every link type, and this
-- finding was never about that function.
--
-- Signature and return shape are byte-identical to the current
-- app.list_customer_ticket_links (20260731300000) -- CREATE OR REPLACE,
-- existing grants (authenticated, service_role; never anon) preserved by
-- Postgres across the replace, no new GRANT/REVOKE needed (ERR-2026-004).

create or replace function app.list_customer_ticket_links(p_ticket_id uuid, p_actor_auth_user_id uuid)
returns table (
  id uuid, entity_type text, entity_id uuid, relationship text, status text,
  live_available boolean, label text, detail text, status_label text,
  linked_at timestamptz, created_by text, record_version integer
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_ticket app.tickets;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  -- Mirrors app.list_customer_ticket_messages' own defensive channel guard
  -- (20260731080000): folds "not a customer-channel ticket" into the
  -- identical empty-result shape a genuinely nonexistent id or a denied
  -- caller would produce -- no enumeration oracle on channel.
  select * into v_ticket from app.tickets t0 where t0.id = p_ticket_id and t0.channel = 'customer';
  if not found then
    return;
  end if;
  if not app.can_access_ticket(p_ticket_id, p_actor_auth_user_id) then
    return;
  end if;

  -- HRT-295 (ISS-2026-110 fix): created_by is genericized for a customer
  -- caller exactly the way app.list_customer_ticket_messages genericizes
  -- author_label -- a real staff creator shows "Support Team", never their
  -- raw internal auth_user_id. Tier C review fix (20260731300000): reads the
  -- stored l.created_by_role column rather than a live is_ticket_staff
  -- re-check on a third party's identity (see that migration's own header
  -- for why the live re-check broke this RPC for genuine customer
  -- sessions).
  --
  -- ISS-2026-102 fix (this migration): entity_id is redacted to a fixed
  -- nil-UUID marker for any row whose entity_type falls outside the
  -- customer-safe registry (today: vendor, user) -- see this migration's
  -- own header for the full rationale.
  return query
  select
    l.id, l.entity_type,
    case
      when l.entity_type = any (app.ticket_link_customer_safe_entity_types()) then l.entity_id
      else '00000000-0000-0000-0000-000000000000'::uuid
    end as entity_id,
    l.relationship, l.status,
    (c.primary_label is not null) as live_available,
    c.primary_label, c.secondary_label,
    coalesce(c.status_label, 'unavailable'),
    l.created_at,
    case when l.created_by_role = 'staff' then 'Support Team' else coalesce(l.created_by, 'You') end,
    l.record_version
  from app.ticket_links l
  left join lateral app._ticket_link_resolve_candidate(l.entity_type, v_ticket.tenant_id, p_actor_auth_user_id, l.entity_id) c on true
  where l.ticket_id = p_ticket_id and l.status = 'active'
  order by l.created_at asc;
end;
$$;

comment on function app.list_customer_ticket_links is
  'HRT-295 (ISS-2026-110 fix): the customer-safe app.list_ticket_links counterpart. created_by is genericized to "Support Team" for a staff-created link, using the STORED l.created_by_role column -- Tier C review fix (20260731300000). ISS-2026-102 fix (20260828140000): entity_id is additionally redacted to a fixed nil-UUID marker (00000000-0000-0000-0000-000000000000) for any row whose entity_type is outside app.ticket_link_customer_safe_entity_types() (today: vendor, user) -- a customer may never search/link those types, and label/detail were already correctly withheld for them (app._ticket_link_resolve_candidate returns no candidate for a customer-layer caller against either type), but the raw entity_id itself was not. entity_type is left unmasked (a bare category, not a record id, and the shared six-value CHECK-constrained registry is also used for write-side validation). The staff-facing app.list_ticket_links is unaffected -- staff legitimately need the real entity_id for every link type.';
