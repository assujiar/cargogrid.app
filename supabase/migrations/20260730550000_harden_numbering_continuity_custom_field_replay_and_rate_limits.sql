-- CG-S10-ATW-032 (post-Prompt-248 audit, `ISS-2026-034`) — four verified findings across the
-- Numbering Engine, the Form/custom-field engine, driver-mobile ingestion and the audit-log
-- read RPCs. Every one was re-derived from the live post-migration catalogue
-- (`pg_get_functiondef`, `pg_constraint`, `pg_policy`, `information_schema.role_table_grants`)
-- and live-reproduced against a probe database carrying every migration through
-- `20260730530000` before being treated as a defect. Where implementing a stated fix exposed a
-- second, structurally identical entry point, that is disclosed below rather than left for the
-- next audit to re-find.
--
-- 1. **Republishing a numbering definition permanently wedged number allocation for the
--    tenant.** `numbering_counters_unique` is `UNIQUE (config_version_id, scope_key,
--    period_key)` — a counter belongs to one config VERSION. `numbering_allocations_tenant_
--    formatted_unique` is `UNIQUE (tenant_id, formatted_number)` — an issued number belongs to
--    the TENANT, across every version it ever had. Those two scopes disagree, and
--    `app.allocate_or_reserve_number` refuses any version that is not currently `published`, so
--    the archived predecessor is not available as a fallback either. Publishing v2 therefore
--    restarted every sequence at 1 while v1's numbers were still on the tenant's books: the
--    next allocation died on a raw 23505 against a number already issued, and because the
--    counter increment is part of the same failed transaction it rolled back with it — so every
--    retry regenerated the identical colliding value. Not a transient error; a permanent wedge,
--    surfacing as an unclassified constraint violation rather than a named one. There is no
--    escape route at the tenant's disposal: `config_objects_scope_shape_check` forces
--    `scope_id IS NULL` at `scope_level='tenant'`, so a tenant has exactly ONE tenant-scoped
--    `numbering` object and every edit to its format, padding or reset period is necessarily a
--    new version of that same object. Live-reproduced end to end: `INV-0001`, `INV-0002` under
--    v1; publish v2; both the next allocation and its retry fail with 23505 on
--    `numbering_allocations_tenant_formatted_unique`.
--
--    The fix carries the outgoing published version's counters forward onto the incoming one at
--    publish time, capturing the version about to be archived BEFORE `app.publish_config_
--    version` archives it. Carrying forward can only ever SKIP numbers (the incoming counter is
--    seeded at the outgoing one's current value, so the next allocation is the next unused
--    value), never reuse them, which is exactly what `20260719110000`'s own header requires of
--    this engine — "allocated numbers are never silently recycled" — and it mirrors
--    `app.bootstrap_numbering_counter`'s never-lower discipline: the carry-forward is a
--    `greatest()` upsert, so a counter already bootstrapped onto the incoming draft is raised,
--    never lowered. `docs/architecture/07_CONFIGURATION_ENGINE_WORKSTREAM.md` §10 ratifies the
--    intent verbatim — "Change numbering | New sequence scope, preserve old numbers": the new
--    version is a new sequence scope, and the old numbers are preserved precisely because the
--    new scope starts above them rather than colliding with them.
--
-- 1b. **The same wedge was reachable through `app.rollback_config_version`, and it is not
--    optional to fix.** Rolling a numbering definition back does NOT republish the archived
--    target — it clones the target into a BRAND NEW `config_versions` row (`rollback_of_
--    version_id`) and publishes that. A brand new version has zero counters, so a one-click
--    rollback wedged allocation identically. Live-reproduced in the same session: the rollback
--    minted a version with 0 counters and its first allocation failed with the same 23505.
--    Fixing only `app.publish_numbering_definition` would have left a fix that the recovery
--    path itself walks around, so the carry-forward is factored into one helper,
--    `app.carry_forward_numbering_counters`, called from both. The helper is a no-op by
--    construction for every non-`numbering` config type — those versions simply have no
--    `numbering_counters` rows to copy — so the shared, all-config-types
--    `app.rollback_config_version` gains no type-specific branch and no behavioural change for
--    the other nine engines. On rollback the counters are carried from the outgoing published
--    version AND from the rollback target, `greatest()` of the two: the live sequence lives on
--    the outgoing version, and the target is an older archived version whose counters are by
--    definition no higher.
--
--    Disclosed limitation, rather than left implicit: counters are carried per `(scope_key,
--    period_key)`. If the publish ALSO changes `reset_period`, the incoming version's period-key
--    namespace has no predecessor to carry from ('ALL' vs '2026' vs '2026-08') and continuity is
--    not carried across it. That is the same situation as an ordinary within-version period
--    rollover, which the format's own `{YYYY}`/`{MM}`/`{DD}` tokens exist to disambiguate — a
--    format that resets periodically without a period token in it already produces duplicate
--    formatted numbers inside a single version, and is a definition-level defect this migration
--    deliberately does not paper over.
--
-- 2. **`app.set_custom_field_values`: a legitimate retry of an earlier submission silently
--    destroyed newer values.** `app.custom_field_values` stores exactly one row per
--    `(tenant_id, entity_type, entity_id)` (`custom_field_values_entity_unique`, the EAV-
--    avoidance guarantee its own db-test asserts), and it carried the idempotency key ON that
--    mutable row under `unique (tenant_id, idempotency_key)`. The upsert OVERWROTE
--    `idempotency_key` with the newest request's key — so the instant a newer submission landed
--    for the same entity, the earlier request's key stopped existing anywhere in the database.
--    Its replay guard silently stopped working, and the earlier request's stale payload was
--    re-applied wholesale, with no version check, no conflict, and a `success` return.
--    Live-reproduced: submit K1/V1, submit K2/V2, then replay K1 byte-identically — V1 is
--    restored over V2 and the call reports success. The failure is symmetric and repeating: the
--    replay's own key now sits on the row, so replaying K2 flips it back again. This is a direct
--    breach of `INV-011` ("every retriable mutation, webhook, posting, and eligible ledger event
--    is idempotent"), and it is the pathology `ATW-031` was created to close, in the one shape
--    `ATW-031` could not see: not a replay lookup that is too broad, but a replay lookup whose
--    key is destroyed by ordinary forward progress.
--
--    A key that has been consumed must stay consumed for as long as the mutation is retriable,
--    which means it cannot live on a row that legitimately changes. The fix moves it to a
--    durable per-request ledger, `app.custom_field_value_idempotency_keys`, one immutable row
--    per consumed key — the same shape `app.finance_idempotency_claims` (`20260729220000`)
--    already established for the Finance postings. A recognised replay now short-circuits to a
--    true no-op that returns the entity's CURRENT row, never re-applying the stale payload.
--    Already-consumed keys are backfilled from the keys still standing on
--    `custom_field_values`, so nothing that was idempotent yesterday becomes replayable today.
--    Keys that were already overwritten in place are unrecoverable — the column that held them
--    was destroyed, not archived — and this migration does not pretend otherwise.
--
--    `custom_field_values.idempotency_key` and `custom_field_values_idempotency_unique` are
--    deliberately left in place: `server/queries/form.ts` and the contract layer read that
--    column, and dropping it would trade one defect for a breakage. It is now a denormalized
--    record of the LAST key applied to the row, and the ledger is the authority. The constraint
--    is also no longer reachable as a raw 23505 — every key it could collide on is in the
--    ledger, so the named `idempotency_key_conflict` fires first.
--
--    `ATW-031`'s target-mismatch guard is preserved, not removed — it is a different and still
--    live defect, and it now reads the ledger instead of the mutable row. One incidental
--    alignment: it compares against `coalesce(p_entity_type, 'generic')`, the same
--    canonicalization the entity lookup immediately below it has always used. Comparing the raw
--    parameter against the canonicalized stored value meant a caller who omitted `entity_type`
--    got `idempotency_key_conflict` raised against its OWN row on replay — the guard firing on
--    the exact case it exists to permit.
--
-- 3. **The anon-callable driver-mobile ingestion rate limit was bound only to a value the
--    caller chooses.** `app.ingest_driver_mobile_report` counted recent invalid attempts `where
--    client_key = p_client_key`. The HTTP route derives `client_key` from the `x-forwarded-for`
--    first hop — externally suppliable — and the function is granted to `anon`, so
--    `p_client_key` is additionally settable outright through PostgREST. Varying it per request
--    made the limiter inert and `'rate_limited'` unreachable, while every request still
--    performed an unbounded INSERT into `app.driver_mobile_ingestion_attempts`. This is the
--    identical defect `CG-S10-ATW-027` fixed one migration earlier in the sibling
--    `app.ingest_third_party_provider_webhook_event` (`20260730350000`), which widened its count
--    to `(connection_id = p_connection_id or client_key = p_client_key)` on the reasoning that
--    the caller's own attack target cannot be rotated without abandoning the attack. The
--    driver-mobile side was not swept with it.
--
--    The equivalent unrotatable discriminator here is the tracking session the function already
--    authenticates: it hashes `p_raw_token` and resolves `app.driver_mobile_tracking_sessions`
--    by `token_hash`. That session id — not the token hash — is what the attempts table now
--    carries, as a nullable FK, exactly mirroring the sibling's `connection_id` column: it is a
--    real referential handle rather than a stored derivative of a bearer credential
--    accumulating in an append-only log. The token lookup moves above the limiter so the
--    discriminator is known before the count is taken; it is a pure read and adds no side
--    effect on any path. The null case is guarded explicitly — a token that resolves to no
--    session at all yields a null discriminator, the attempt is recorded with a null FK so it
--    can never be matched by the session predicate on its own, and `client_key` remains the only
--    available signal for that caller, precisely the limitation the sibling's own inline comment
--    already discloses for a nonexistent `connection_id`. What this closes is the case that
--    matters most: a device holding a real token — expired, ended, revoked-consent or simply
--    malfunctioning — resolves to its session on EVERY attempt, so rotating `client_key` no
--    longer buys it an unlimited invalid-request budget. Every attempt row, on every branch
--    including `'success'` and `'rate_limited'`, now records both discriminators.
--
--    Not fixed here, and named rather than quietly carried: `app.driver_mobile_ingestion_
--    attempts` still has no retention sweep, and neither does `app.third_party_provider_
--    ingestion_attempts` or `app.tracking_lookup_attempts`. `20260730450000`'s
--    `app.purge_tracking_telemetry_history` covers the telemetry relations only. That is one
--    retention job across three tables of the same family, and it belongs with them, not
--    half-done inside a rate-limit correctness fix.
--
-- 4. **The two audit-log read RPCs accepted an unbounded page size.** `app.query_audit_logs` and
--    `app.export_audit_logs` ended in a bare `limit p_limit`. 48 of the 50 `p_limit`-taking
--    functions in the schema clamp (`least(greatest(coalesce(p_limit, 50), 1), 200)`, or the
--    older `least(coalesce(p_limit, …), …)` form); these two were the entire exception set.
--    `docs/architecture/05_DATABASE_SCHEMA_WORKSTREAM.md` §7 (Index and query plan) names
--    `audit_logs` as one of the relations where **keyset** pagination is mandatory — quoting
--    Tech Arch §25.4 and again §37's Scale-up exit criteria — and an unbounded page size defeats
--    the bound the cursor exists to enforce, on the one table that is by construction the largest
--    and most sensitive in the tenant. Both are `SECURITY DEFINER`, so the clamp cannot be
--    delegated to RLS. `server/contracts/audit-trail/audit-trail.ts` was already clamped to 200;
--    this is the defence-in-depth half, so a caller reaching the RPC directly cannot bypass the
--    contract. Each function keeps its OWN documented default — 50 for the interactive query,
--    500 for the bulk export — and takes the ceiling its default implies under the house
--    convention: 200 for the 50-default family, and 1000 for the 500-default family, matching
--    `app.export_customer_inventory_snapshot`, the only other 500-default export RPC in the
--    schema.
--
-- ===========================================================================
-- Objects touched
-- ===========================================================================
--
-- Six `CREATE OR REPLACE FUNCTION` on byte-identical signatures (`app.publish_numbering_
-- definition`, `app.rollback_config_version`, `app.set_custom_field_values`, `app.ingest_driver_
-- mobile_report`, `app.query_audit_logs`, `app.export_audit_logs`), each reproducing its
-- existing `LANGUAGE`/`SECURITY`/`SET search_path` attributes exactly as `pg_get_functiondef`
-- prints them. One new function (`app.carry_forward_numbering_counters`), one new table
-- (`app.custom_field_value_idempotency_keys`) with its backfill, and one new nullable column
-- plus index on `app.driver_mobile_ingestion_attempts`. No already-applied migration file is
-- edited.
--
-- Grants, and the distinction that matters: `CREATE OR REPLACE` PRESERVES an existing ACL, so
-- the six replaced functions are deliberately NOT re-granted — a blanket re-grant in a sweep
-- like this is exactly how an internal helper quietly becomes a public API, and one of the six
-- (`app.ingest_driver_mobile_report`) is granted to `anon`. Only the genuinely new objects are
-- granted, at the posture of the siblings they sit beside, verified against `pg_policy` and
-- `information_schema.role_table_grants` rather than assumed:
-- `app.custom_field_value_idempotency_keys` takes `app.custom_field_values`' own posture (RLS
-- enabled, one tenant-scoped SELECT policy for `authenticated`, `select` to `authenticated`,
-- full DML to `service_role`), and `app.carry_forward_numbering_counters` takes the
-- `service_role`-only EXECUTE every other Numbering Engine helper has. The new column on
-- `app.driver_mobile_ingestion_attempts` needs no grant at all — that table's grants are
-- table-level and already cover it.
--
-- Per `ERR-2026-004` (`docs/runtime/ERROR_LEDGER.md`): this migration carries its own explicit
-- `revoke execute on all functions in schema app from public`, placed before its own grants.

-- ===========================================================================
-- Finding 1 — numbering counter continuity across a republish
-- ===========================================================================

-- ATW-032 (ISS-2026-034). Seeds the incoming config version's counters from the outgoing one's,
-- per (scope_key, period_key). Deliberately a greatest() upsert rather than a plain insert: a
-- counter may already exist on the incoming version because app.bootstrap_numbering_counter
-- does not require its target version to be published, and that legacy bootstrap sits ABOVE the
-- verified historical maximum by construction. Lowering it would hand back numbers the legacy
-- system already issued -- the precise outcome numbering_counter_cannot_decrease exists to
-- prevent -- so the higher of the two always wins. Carrying forward can only skip values, never
-- reuse one.
--
-- A no-op by construction for every non-'numbering' config type: those versions own no
-- app.numbering_counters rows, so the insert...select finds nothing. That is what makes it safe
-- to call unconditionally from the shared app.rollback_config_version below, with no config_
-- type branch and no behavioural change for the other nine engines.
create function app.carry_forward_numbering_counters(p_from_config_version_id uuid, p_to_config_version_id uuid)
returns integer
language plpgsql
as $$
declare
  v_carried integer;
begin
  if p_from_config_version_id is null
     or p_to_config_version_id is null
     or p_from_config_version_id = p_to_config_version_id then
    return 0;
  end if;

  insert into app.numbering_counters (config_version_id, scope_key, period_key, next_seq)
  select p_to_config_version_id, c.scope_key, c.period_key, c.next_seq
  from app.numbering_counters c
  where c.config_version_id = p_from_config_version_id
  on conflict (config_version_id, scope_key, period_key)
  do update set next_seq = greatest(app.numbering_counters.next_seq, excluded.next_seq);

  get diagnostics v_carried = row_count;
  return v_carried;
end;
$$;

comment on function app.carry_forward_numbering_counters(uuid, uuid) is
  'ATW-032 (ISS-2026-034): seeds a newly-published numbering config version''s counters from the version it supersedes, per (scope_key, period_key), never lowering an existing counter. Without it a republish restarts every sequence at 1 while the tenant-wide numbering_allocations_tenant_formatted_unique constraint still holds the old numbers, wedging allocation permanently on a raw 23505. A no-op for config types that own no numbering counters.';

CREATE OR REPLACE FUNCTION app.publish_numbering_definition(p_version_id uuid, p_actor_auth_user_id uuid, p_effective_from timestamp with time zone, p_actor_label text)
 RETURNS app.config_versions
 LANGUAGE plpgsql
AS $function$
declare
  v_config_object_id uuid;
  v_prior_published_id uuid;
  v_published app.config_versions;
begin
  perform app.validate_numbering_definition(p_version_id);

  -- ATW-032 (ISS-2026-034): capture the version that is ABOUT to be archived, before
  -- app.publish_config_version archives it -- afterwards there is no 'published' sibling left
  -- to find, and the outgoing version's counters are the only record of where this tenant's
  -- sequences actually stand. numbering_counters is keyed per config VERSION while
  -- numbering_allocations is unique per TENANT, so without this the republish restarts every
  -- sequence at 1 against numbers already issued and every subsequent allocation -- and every
  -- retry of it, since the counter increment rolls back with the failed insert -- dies on the
  -- same 23505. app.allocate_or_reserve_number refuses any non-published version, so the
  -- archived predecessor is not a fallback either.
  select v.config_object_id into v_config_object_id
  from app.config_versions v
  where v.id = p_version_id;

  select v.id into v_prior_published_id
  from app.config_versions v
  where v.config_object_id = v_config_object_id
    and v.status = 'published'
    and v.id <> p_version_id
  order by v.version_number desc
  limit 1;

  v_published := app.publish_config_version(p_version_id, p_actor_auth_user_id, p_effective_from, p_actor_label);

  -- Only reached once publish_config_version has passed its own authority, draft-status and
  -- dependency-cycle gates; a failure there aborts the transaction and nothing is carried.
  perform app.carry_forward_numbering_counters(v_prior_published_id, p_version_id);

  return v_published;
end;
$function$
;

CREATE OR REPLACE FUNCTION app.rollback_config_version(p_target_version_id uuid, p_actor_auth_user_id uuid, p_reason text, p_actor_label text)
 RETURNS app.config_versions
 LANGUAGE plpgsql
AS $function$
declare
  v_target app.config_versions;
  v_object app.config_objects;
  v_next_version integer;
  v_new_version app.config_versions;
  v_prior_published app.config_versions;
  v_published app.config_versions;
begin
  select * into v_target from app.config_versions where id = p_target_version_id;
  if not found then
    raise exception 'config_version_not_found: no config version %', p_target_version_id
      using errcode = 'no_data_found';
  end if;

  if v_target.status = 'draft' then
    raise exception 'cannot_rollback_draft: version % is still a draft, nothing stable to roll back to', p_target_version_id
      using errcode = 'check_violation';
  end if;

  select * into v_object from app.config_objects where id = v_target.config_object_id;

  if not app.check_config_object_authority(v_object.scope_level, v_object.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks authority for scope % of tenant %', p_actor_auth_user_id, v_object.scope_level, v_object.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select coalesce(max(version_number), 0) + 1 into v_next_version from app.config_versions where config_object_id = v_target.config_object_id;

  insert into app.config_versions (config_object_id, version_number, cloned_from_version_id, rollback_of_version_id, created_by)
  values (v_target.config_object_id, v_next_version, p_target_version_id, p_target_version_id, p_actor_label)
  returning * into v_new_version;

  insert into app.config_items (config_version_id, key, value, canonical_ref)
  select v_new_version.id, key, value, canonical_ref from app.config_items where config_version_id = p_target_version_id;

  select * into v_prior_published from app.config_versions where config_object_id = v_target.config_object_id and status = 'published';
  if found then
    update app.config_versions
    set status = 'archived', archived_at = now(), archived_reason = 'superseded by rollback to version ' || v_target.version_number
    where id = v_prior_published.id;
  end if;

  update app.config_versions
  set status = 'published', published_by = p_actor_label, published_at = now(), effective_from = now()
  where id = v_new_version.id
  returning * into v_published;

  -- ATW-032 (ISS-2026-034), finding 1b. A rollback does NOT republish the archived target -- it
  -- clones it into a BRAND NEW config_versions row and publishes that, so for a 'numbering'
  -- object the new version owns zero counters and allocation wedges on numbering_allocations_
  -- tenant_formatted_unique exactly as an ordinary republish did (live-reproduced). Fixing only
  -- app.publish_numbering_definition would have left the recovery path walking around the fix.
  -- Carried from the outgoing published version AND from the rollback target, greatest() of the
  -- two: the live sequence stands on the outgoing version, while the target is an older
  -- archived version whose counters are by definition no higher -- but the helper takes the
  -- maximum rather than trusting that ordering. No config_type branch is needed and no other
  -- engine is affected: a version of any of the other nine config types owns no
  -- app.numbering_counters rows, so both calls copy nothing.
  perform app.carry_forward_numbering_counters(v_prior_published.id, v_published.id);
  perform app.carry_forward_numbering_counters(p_target_version_id, v_published.id);

  perform app.capture_audit_event(
    v_object.tenant_id, p_actor_auth_user_id, p_actor_label, 'rollback_config_version',
    'app.config_versions', v_published.id, 'success', p_reason, to_jsonb(v_target), to_jsonb(v_published)
  );

  return v_published;
end;
$function$
;

-- ===========================================================================
-- Finding 2 — a durable idempotency ledger for custom field submissions
-- ===========================================================================

-- ATW-032 (ISS-2026-034). One immutable row per consumed idempotency key. The key cannot live
-- on app.custom_field_values because that table holds exactly ONE row per (tenant_id,
-- entity_type, entity_id) (custom_field_values_entity_unique) and the upsert overwrites the key
-- column on every submission -- so an earlier request's key ceased to exist the moment a newer
-- submission landed for the same entity, its replay guard stopped working, and the stale
-- payload was re-applied over newer values with no version check and a 'success' return.
-- Same shape as app.finance_idempotency_claims (20260729220000): the claim outlives the row it
-- describes. Posture matches app.custom_field_values exactly (RLS enabled, one tenant-scoped
-- SELECT policy for authenticated), verified against pg_policy and role_table_grants rather
-- than assumed.
create table app.custom_field_value_idempotency_keys (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  idempotency_key text not null,
  custom_field_value_id uuid not null references app.custom_field_values (id),
  config_version_id uuid not null references app.config_versions (id),
  entity_type text not null,
  entity_id uuid not null,
  submitted_by_auth_user_id uuid references auth.users (id),
  submitted_by text,
  consumed_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  constraint custom_field_value_idempotency_keys_unique unique (tenant_id, idempotency_key)
);

comment on table app.custom_field_value_idempotency_keys is
  'ATW-032 (ISS-2026-034): durable, append-only ledger of every idempotency key consumed by app.set_custom_field_values, and the authority on whether a key has been used. app.custom_field_values.idempotency_key is a mutable, overwritten-in-place record of the LAST key applied to a row and is not usable as a replay guard -- a newer submission for the same entity erased the older request''s key, so replaying that older request re-applied its stale payload over newer values and reported success (INV-011). A key recorded here stays recorded, so a replay is recognised and becomes a true no-op.';

create index custom_field_value_idempotency_keys_entity_idx
  on app.custom_field_value_idempotency_keys (tenant_id, entity_type, entity_id, consumed_at desc);
create index custom_field_value_idempotency_keys_value_idx
  on app.custom_field_value_idempotency_keys (custom_field_value_id);

-- Backfill: every key still standing on a custom_field_values row is a key that HAS been
-- consumed, and must stay consumed -- otherwise this migration would make yesterday's
-- idempotent submissions replayable today. Keys that were already overwritten in place are
-- unrecoverable: the column that held them was destroyed rather than archived, and nothing in
-- the database or the audit trail reconstructs the mapping. Said plainly rather than implied.
insert into app.custom_field_value_idempotency_keys (
  tenant_id, idempotency_key, custom_field_value_id, config_version_id, entity_type, entity_id,
  submitted_by_auth_user_id, submitted_by, consumed_at
)
select
  v.tenant_id, v.idempotency_key, v.id, v.config_version_id, v.entity_type, v.entity_id,
  v.submitted_by_auth_user_id, v.submitted_by, v.updated_at
from app.custom_field_values v
on conflict (tenant_id, idempotency_key) do nothing;

alter table app.custom_field_value_idempotency_keys enable row level security;

create policy custom_field_value_idempotency_keys_select_scoped on app.custom_field_value_idempotency_keys
  for select
  to authenticated
  using (app.has_active_tenant_membership(tenant_id) or app.is_supreme_admin());

CREATE OR REPLACE FUNCTION app.set_custom_field_values(p_config_version_id uuid, p_tenant_id uuid, p_entity_type text, p_entity_id uuid, p_values jsonb, p_idempotency_key text, p_actor_auth_user_id uuid, p_submitted_by text)
 RETURNS app.custom_field_values
 LANGUAGE plpgsql
AS $function$
declare
  v_version app.config_versions;
  v_claim app.custom_field_value_idempotency_keys;
  v_existing_by_entity app.custom_field_values;
  v_row app.custom_field_values;
begin
  if not app.check_custom_field_authority(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % is not an active member of tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_version from app.config_versions where id = p_config_version_id;
  if not found or v_version.status <> 'published' then
    raise exception 'custom_field_definition_not_published: config version % is not a published form definition', p_config_version_id
      using errcode = 'check_violation';
  end if;

  -- ATW-032 (ISS-2026-034): the replay guard now reads the durable ledger, not the mutable row.
  -- app.custom_field_values holds ONE row per (tenant_id, entity_type, entity_id) and the
  -- upsert below overwrites its idempotency_key on every submission, so a key consumed by an
  -- earlier request simply ceased to exist as soon as a newer submission landed for the same
  -- entity -- and that earlier request, retried, sailed past this guard and re-applied its
  -- stale payload over the newer values with no version check and a 'success' return
  -- (live-reproduced: K1/V1, K2/V2, replay K1 -> V1 restored). INV-011 requires that a retriable
  -- mutation be idempotent, which a guard keyed on a value that forward progress destroys can
  -- never be.
  select * into v_claim from app.custom_field_value_idempotency_keys
    where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
  if found then
    -- ATW-031 (ISS-2026-029), preserved and still load-bearing: a key already used for a
    -- DIFFERENT target is a conflict, never a replay. Returning the earlier target's row here
    -- silently misattributed this request to it (or silently discarded it entirely). It now
    -- compares against coalesce(p_entity_type, 'generic') -- the same canonicalization the
    -- entity lookup below has always used, and the value actually stored. Comparing the raw
    -- parameter against a canonicalized stored value meant a caller who omitted entity_type had
    -- this guard raised against its OWN row on replay, firing on the exact case it exists to
    -- permit.
    if v_claim.entity_type is distinct from coalesce(p_entity_type, 'generic')
       or v_claim.entity_id is distinct from p_entity_id
       or v_claim.config_version_id is distinct from p_config_version_id then
      raise exception 'idempotency_key_conflict: idempotency key % was already used for a different custom field value set (entity % %, not % %)', p_idempotency_key, v_claim.entity_type, v_claim.entity_id, coalesce(p_entity_type, 'generic'), p_entity_id
        using errcode = 'unique_violation';
    end if;
    -- A recognised replay is a true no-op: the entity's CURRENT row is returned and the
    -- request's payload is never re-applied. Guaranteed to be found -- custom_field_value_id is
    -- a non-null FK to app.custom_field_values with no cascade, so the row cannot have been
    -- removed while this claim stands.
    select * into v_row from app.custom_field_values where id = v_claim.custom_field_value_id;
    return v_row;
  end if;

  perform app.validate_custom_field_values(p_config_version_id, p_values);

  select * into v_existing_by_entity from app.custom_field_values where tenant_id = p_tenant_id and entity_type = coalesce(p_entity_type, 'generic') and entity_id = p_entity_id;

  if found then
    update app.custom_field_values
    set config_version_id = p_config_version_id, values = p_values, idempotency_key = p_idempotency_key,
        submitted_by_auth_user_id = p_actor_auth_user_id, submitted_by = p_submitted_by
    where id = v_existing_by_entity.id
    returning * into v_row;
  else
    insert into app.custom_field_values (tenant_id, config_version_id, entity_type, entity_id, values, submitted_by_auth_user_id, submitted_by, idempotency_key)
    values (p_tenant_id, p_config_version_id, coalesce(p_entity_type, 'generic'), p_entity_id, p_values, p_actor_auth_user_id, p_submitted_by, p_idempotency_key)
    returning * into v_row;
  end if;

  -- ATW-032 (ISS-2026-034): record the consumed key durably. custom_field_values.idempotency_key
  -- is still written above -- server/queries/form.ts and the contract layer read it, and it
  -- remains a correct record of the LAST key applied to the row -- but this ledger row is what
  -- makes the key stay consumed once a later submission overwrites that column. The nested
  -- block converts a concurrent claim of the same key into the same named error every other
  -- idempotent mutation in this repository raises, rather than an unclassified 23505.
  begin
    insert into app.custom_field_value_idempotency_keys (
      tenant_id, idempotency_key, custom_field_value_id, config_version_id, entity_type, entity_id,
      submitted_by_auth_user_id, submitted_by
    ) values (
      p_tenant_id, p_idempotency_key, v_row.id, p_config_version_id, coalesce(p_entity_type, 'generic'), p_entity_id,
      p_actor_auth_user_id, p_submitted_by
    );
  exception
    when unique_violation then
      raise exception 'idempotency_key_conflict: idempotency key % was already consumed by a different, concurrent custom field submission', p_idempotency_key
        using errcode = 'unique_violation';
  end;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_submitted_by, 'set_custom_field_values',
    'app.custom_field_values', v_row.id, 'success', null, to_jsonb(v_existing_by_entity), to_jsonb(v_row)
  );

  return v_row;
end;
$function$
;

-- ===========================================================================
-- Finding 3 — bind the driver-mobile rate limit to something the caller cannot rotate
-- ===========================================================================

-- ATW-032 (ISS-2026-034). Mirrors app.third_party_provider_ingestion_attempts.connection_id
-- exactly, including its nullability: an attempt whose token resolves to no session at all must
-- record a null here rather than a fabricated value, so it can never be matched by the session
-- predicate on its own. No grant is needed -- this table's grants are table-level and already
-- cover any new column.
alter table app.driver_mobile_ingestion_attempts
  add column driver_mobile_tracking_session_id uuid references app.driver_mobile_tracking_sessions (id);

comment on column app.driver_mobile_ingestion_attempts.driver_mobile_tracking_session_id is
  'ATW-032 (ISS-2026-034): the tracking session app.ingest_driver_mobile_report authenticated this attempt against, or null when the presented token resolved to no session. The rate limit was previously bound only to client_key, which the caller controls (the HTTP route derives it from x-forwarded-for''s first hop, and the RPC is granted to anon), so varying it per request made the limiter inert. Null by design for an unresolvable token -- client_key remains the only available signal there, the same limitation the sibling third_party_provider_ingestion_attempts.connection_id column carries.';

create index driver_mobile_ingestion_attempts_session_idx
  on app.driver_mobile_ingestion_attempts (driver_mobile_tracking_session_id, occurred_at desc);

CREATE OR REPLACE FUNCTION app.ingest_driver_mobile_report(p_raw_token text, p_client_key text, p_report_type text, p_event_at timestamp with time zone, p_location jsonb, p_accuracy_meters numeric, p_battery_percent integer, p_location_permission_granted boolean, p_background_permission_granted boolean, p_raw_payload jsonb)
 RETURNS TABLE(ingest_status text, report_id uuid, session_ended boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'public', 'extensions', 'pg_temp'
AS $function$
declare
  v_recent_bad_count integer;
  v_hash text;
  v_dms app.driver_mobile_tracking_sessions;
  v_session app.shipment_leg_tracking_sessions;
  v_report app.driver_mobile_position_reports;
  v_geog geography;
  v_ended boolean := false;
  v_vehicle_master_id uuid;
  v_session_id uuid;
begin
  if p_client_key is null or length(trim(p_client_key)) = 0 then
    raise exception 'tracking_client_key_required: a client_key is required' using errcode = 'check_violation';
  end if;

  -- ATW-032 (ISS-2026-034): resolve the tracking session BEFORE the limiter counts, so the
  -- count has a discriminator the caller cannot rotate. This is the identical defect CG-S10-
  -- ATW-027 fixed in the sibling app.ingest_third_party_provider_webhook_event one migration
  -- earlier (20260730350000) and which was not swept across to this side: client_key is fully
  -- caller-controlled -- the real HTTP route derives it from x-forwarded-for's externally-
  -- suppliable first hop, and this function is granted to anon so p_client_key is settable
  -- outright through PostgREST -- so a client_key-only count is trivially defeated by varying
  -- it per request, leaving 'rate_limited' unreachable while every request still writes an
  -- attempts row. The session id is the equivalent of the sibling's connection_id: it is
  -- derived from the bearer token, so a device holding a real token (expired, ended,
  -- consent-revoked, or simply malfunctioning) presents the same one on every attempt and
  -- cannot rotate away from its own budget. The lookup is a pure read and adds no side effect
  -- on any path; only its position moved.
  if p_raw_token is not null and length(p_raw_token) > 0 then
    v_hash := encode(digest(p_raw_token, 'sha256'), 'hex');
    select * into v_dms from app.driver_mobile_tracking_sessions where token_hash = v_hash;
    v_session_id := v_dms.id;
  end if;

  -- The null case is guarded explicitly: a token that resolves to no session leaves
  -- v_session_id null, the session predicate is then skipped entirely rather than matching every
  -- other null-session attempt in the window, and client_key remains the only available signal
  -- for that caller -- exactly the limitation the sibling's own inline comment discloses for a
  -- wholly nonexistent connection_id.
  select count(*) into v_recent_bad_count
  from app.driver_mobile_ingestion_attempts
  where result = 'invalid' and occurred_at > now() - interval '15 minutes'
    and (client_key = p_client_key
         or (v_session_id is not null and driver_mobile_tracking_session_id = v_session_id));
  if v_recent_bad_count >= 10 then
    insert into app.driver_mobile_ingestion_attempts (driver_mobile_tracking_session_id, client_key, result) values (v_session_id, p_client_key, 'rate_limited');
    return query select 'rate_limited'::text, null::uuid, false;
    return;
  end if;

  if p_raw_token is null or length(p_raw_token) = 0 or p_report_type not in ('heartbeat', 'location', 'pause', 'resume', 'stop') or p_event_at is null then
    insert into app.driver_mobile_ingestion_attempts (driver_mobile_tracking_session_id, client_key, result) values (v_session_id, p_client_key, 'invalid');
    return query select 'invalid'::text, null::uuid, false;
    return;
  end if;

  -- v_dms was resolved above; v_dms.id is null exactly when the token matched no session, which
  -- is what the former "not found" of this lookup meant (the column is NOT NULL in the table).
  if v_dms.id is null or v_dms.status <> 'active' or v_dms.expires_at <= now() then
    insert into app.driver_mobile_ingestion_attempts (driver_mobile_tracking_session_id, client_key, result) values (v_session_id, p_client_key, 'invalid');
    return query select 'invalid'::text, null::uuid, false;
    return;
  end if;

  select * into v_session from app.shipment_leg_tracking_sessions where id = v_dms.shipment_leg_tracking_session_id;
  if not v_session.is_current or v_session.status <> 'active' then
    -- The dispatcher already ended/handed off this session on the ATW-225 side --
    -- real-time consistency: mobile ingestion stops the instant that happens, never a
    -- stale token still silently accepted.
    insert into app.driver_mobile_ingestion_attempts (driver_mobile_tracking_session_id, client_key, result) values (v_session_id, p_client_key, 'invalid');
    return query select 'invalid'::text, null::uuid, false;
    return;
  end if;

  -- ATW-246 finding 4: live re-check the session's own driver's CURRENT status/
  -- mobile_tracking_consent on every call, mirroring both the is_current/status live
  -- re-check immediately above AND the exact eligibility predicate app.check_leg_
  -- tracking_source_eligible already applies for driver_mobile at session-start time
  -- (ATW-225). mobile_tracking_consent was previously checked only once, at app.start_
  -- leg_tracking_session -- revoking consent mid-session via app.set_driver_mobile_
  -- tracking_consent never stopped a subsequent call here from succeeding and persisting
  -- the driver's location. v_session.resource_master_id is always this session's own
  -- driver's app.master_records.id for a source_type='driver_mobile' session (that
  -- table's own kind_source_match_check constraint) -- no extra join needed.
  if not exists (
    select 1 from app.driver_operational_profiles
    where driver_master_id = v_session.resource_master_id and status = 'active' and mobile_tracking_consent
  ) then
    insert into app.driver_mobile_ingestion_attempts (driver_mobile_tracking_session_id, client_key, result) values (v_session_id, p_client_key, 'invalid');
    return query select 'invalid'::text, null::uuid, false;
    return;
  end if;

  if p_report_type = 'location' and p_location is null then
    insert into app.driver_mobile_ingestion_attempts (driver_mobile_tracking_session_id, client_key, result) values (v_session_id, p_client_key, 'invalid');
    return query select 'invalid'::text, null::uuid, false;
    return;
  end if;

  -- ATW-246 finding 5: app.geojson_point_to_geography raises (spatial_coordinate_out_of_
  -- range / spatial_invalid_geojson_type / spatial_invalid_coordinate_count) for a
  -- malformed/out-of-bounds point -- previously uncaught here, unwinding this whole
  -- function and skipping the rate-limit bookkeeping insert below (a real, exploitable
  -- gap: repeated out-of-range coordinates cost the caller nothing toward the
  -- 10-bad-attempts/15-minute limiter, unlike every other invalid input this function
  -- handles). Caught and converted to the same clean 'invalid' result every other
  -- validation branch in this function already returns -- this RPC's own documented
  -- "never raises" contract now holds for every input shape, not just most of them.
  begin
    v_geog := case when p_location is not null then app.geojson_point_to_geography(p_location) else null end;
  exception
    when others then
      insert into app.driver_mobile_ingestion_attempts (driver_mobile_tracking_session_id, client_key, result) values (v_session_id, p_client_key, 'invalid');
      return query select 'invalid'::text, null::uuid, false;
      return;
  end;

  insert into app.driver_mobile_position_reports (
    tenant_id, driver_mobile_tracking_session_id, report_type, event_at, location,
    accuracy_meters, battery_percent, location_permission_granted, background_permission_granted, raw_payload
  ) values (
    v_dms.tenant_id, v_dms.id, p_report_type, p_event_at, v_geog,
    p_accuracy_meters, p_battery_percent, p_location_permission_granted, p_background_permission_granted, coalesce(p_raw_payload, '{}'::jsonb)
  )
  returning * into v_report;

  update app.driver_mobile_tracking_sessions set last_seen_at = now() where id = v_dms.id;

  insert into app.driver_mobile_ingestion_attempts (driver_mobile_tracking_session_id, client_key, result) values (v_session_id, p_client_key, 'success');

  -- ATW-226F: canonicalize a location/heartbeat report -- never raises, never blocks the
  -- already-committed raw insert above. Preserved verbatim from the current (ATW-226F)
  -- body -- app.arbitrate_and_project_vehicle_position's own definition is untouched here too
  -- (the "this migration" of the sentence above is 20260730360000, whose header design note 2
  -- carries the reasoning; only the attempts-table inserts in this function changed).
  if p_report_type in ('location', 'heartbeat') then
    v_vehicle_master_id := app.resolve_vehicle_for_driver_mobile_session(v_dms.id);
    if v_vehicle_master_id is not null then
      perform app.arbitrate_and_project_vehicle_position(
        v_dms.tenant_id, v_vehicle_master_id, 'driver_mobile', v_report.id, p_event_at, v_report.received_at,
        v_geog, null::numeric, null::numeric, p_accuracy_meters
      );
    end if;
  end if;

  if p_report_type = 'stop' then
    perform app.end_leg_tracking_session(
      v_session.shipment_leg_id, 'manual_stop', 'driver stopped tracking via mobile app', null, 'driver-mobile', v_dms.id
    );
    v_ended := true;
  end if;

  return query select 'ok'::text, v_report.id, v_ended;
end;
$function$
;

-- ===========================================================================
-- Finding 4 — clamp the two unbounded audit-log page sizes
-- ===========================================================================

CREATE OR REPLACE FUNCTION app.query_audit_logs(p_requester_auth_user_id uuid, p_tenant_id uuid, p_limit integer DEFAULT 50, p_before_occurred_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_before_id uuid DEFAULT NULL::uuid)
 RETURNS SETOF app.audit_logs
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
begin
  if not app.is_support_grant_authority(p_requester_auth_user_id, p_tenant_id) then
    raise exception 'insufficient_authority: identity % holds neither Supreme Admin nor tenant_admin authority for tenant %', p_requester_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  perform app.capture_audit_event(
    p_tenant_id, p_requester_auth_user_id, 'audit_query_caller', 'query_audit_logs',
    'app.audit_logs', null, 'success', null
  );

  return query
    select al.*
    from app.audit_logs al
    where al.tenant_id = p_tenant_id
      and (
        p_before_occurred_at is null
        or al.occurred_at < p_before_occurred_at
        or (al.occurred_at = p_before_occurred_at and al.id < p_before_id)
      )
    order by al.occurred_at desc, al.id desc
    -- ATW-032 (ISS-2026-034): was a bare `limit p_limit`. 48 of the 50 p_limit-taking functions
    -- in this schema clamp; this and app.export_audit_logs were the entire exception set.
    -- 05_DATABASE_SCHEMA_WORKSTREAM.md makes keyset pagination MANDATORY for audit_logs, and an
    -- unbounded page size defeats the bound the cursor exists to enforce -- on the largest and
    -- most sensitive relation in the tenant. This function is SECURITY DEFINER, so RLS cannot
    -- carry the bound for it. The default stays at this function's own documented 50 and the
    -- ceiling is the house convention's 200 for that default, matching the clamp already
    -- applied in server/contracts/audit-trail/audit-trail.ts so a direct RPC caller cannot get
    -- past it.
    limit least(greatest(coalesce(p_limit, 50), 1), 200);
end;
$function$
;

CREATE OR REPLACE FUNCTION app.export_audit_logs(p_requester_auth_user_id uuid, p_tenant_id uuid, p_limit integer DEFAULT 500, p_before_occurred_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_before_id uuid DEFAULT NULL::uuid)
 RETURNS SETOF app.audit_logs
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
begin
  if not app.is_support_grant_authority(p_requester_auth_user_id, p_tenant_id) then
    raise exception 'insufficient_authority: identity % holds neither Supreme Admin nor tenant_admin authority for tenant %', p_requester_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  perform app.capture_audit_event(
    p_tenant_id, p_requester_auth_user_id, 'audit_export_caller', 'export_audit_logs',
    'app.audit_logs', null, 'success', null
  );

  return query
    select al.*
    from app.audit_logs al
    where al.tenant_id = p_tenant_id
      and (
        p_before_occurred_at is null
        or al.occurred_at < p_before_occurred_at
        or (al.occurred_at = p_before_occurred_at and al.id < p_before_id)
      )
    order by al.occurred_at desc, al.id desc
    -- ATW-032 (ISS-2026-034): same clamp as app.query_audit_logs, deliberately at the BULK
    -- scale this function was written for rather than flattened to the interactive one. Its own
    -- documented default of 500 is preserved and the ceiling is 1000 -- the house convention's
    -- pairing for a 500-default, matching app.export_customer_inventory_snapshot, the only other
    -- 500-default export RPC in the schema. A bulk export is a real requirement; an UNBOUNDED
    -- one is not, and the keyset cursor above is how a caller reaches the rest.
    limit least(greatest(coalesce(p_limit, 500), 1), 1000);
end;
$function$
;

-- ===========================================================================
-- Revoke and grants
-- ===========================================================================
--
-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit, directly-provable revoke rather
-- than a reliance on a prior migration's, the standing per-migration convention since PLT-118,
-- applied here before any role-specific grant.
revoke execute on all functions in schema app from public;

-- Grants for NEW objects only. The six CREATE OR REPLACE'd functions above are deliberately NOT
-- re-granted: CREATE OR REPLACE preserves an existing ACL (unlike DROP + CREATE), so there is
-- nothing to restore, and a blanket re-grant in a sweep like this is exactly how an internal
-- helper quietly becomes a public API -- the stakes here are concrete, since one of the six
-- (app.ingest_driver_mobile_report) is granted to anon and another two are granted to
-- authenticated. The new column on app.driver_mobile_ingestion_attempts likewise needs no
-- grant: that table's existing grants are table-level and already cover it.
--
-- app.custom_field_value_idempotency_keys takes app.custom_field_values' own posture, read off
-- pg_policy and information_schema.role_table_grants rather than assumed: RLS enabled with one
-- tenant-scoped SELECT policy for authenticated (above), SELECT to authenticated, full DML to
-- service_role. app.carry_forward_numbering_counters takes the service_role-only EXECUTE every
-- other Numbering Engine helper in 20260719110000 has -- it is an internal engine primitive,
-- not client surface.
grant select on app.custom_field_value_idempotency_keys to authenticated, service_role;
grant insert, update, delete on app.custom_field_value_idempotency_keys to service_role;

grant execute on function app.carry_forward_numbering_counters(uuid, uuid) to service_role;
