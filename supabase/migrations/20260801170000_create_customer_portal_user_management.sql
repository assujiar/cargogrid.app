-- Phase 8 capability CPL-315 (CG-S13-CPL-017, Prompt 315, "Customer User
-- Management"). First prompt of Batch 4. Overwhelmingly an ADDITIVE EXTENSION
-- of CPL-300's own already-VERIFIED invite/accept/status-management machinery
-- (supabase/migrations/20260801010000_create_customer_portal_account_scope.sql,
-- DO NOT EDIT, read in full before this migration was written). CPL-300 already
-- ships: app.resolve_customer_account_scope, app.actor_is_active_customer_
-- portal_account_admin, app.get_customer_portal_scope_context, app.invite_
-- customer_portal_user, app.accept_customer_portal_invite, app.set_customer_
-- portal_account_membership_status (active/suspended/revoked), app.list_
-- customer_portal_account_memberships, app.grant_initial_customer_portal_
-- account_admin. This migration closes the two real, confirmed gaps CPL-300's
-- own build log (§9) named as this prompt's own chartered scope, plus the
-- access-review surface the source prompt's own §20/§28 requires.
--
-- ===========================================================================
-- Design decisions (cited, not re-derived)
-- ===========================================================================
--
-- 1. **Gap 1 -- role update.** No "update role/scope for an existing active
--    membership" RPC existed before this migration -- only invite (creates a
--    NEW row) and set_status (active/suspended/revoked, never touches role)
--    did. `app.update_customer_portal_account_membership_role` mirrors app.
--    set_customer_portal_account_membership_status's own shape exactly: same
--    admin-authority check (app.actor_is_active_customer_portal_account_admin,
--    the one shared Layer-4 authority primitive, never re-derived), same
--    optimistic-concurrency shape (select ... for update, then compare
--    record_version), same audit write into the existing app.customer_portal_
--    account_membership_history table (from_status/to_status both carry the
--    row's own unchanged status; the human-readable "role changed from X to Y"
--    goes in that table's own free-text reason column -- there is no
--    dedicated role-history table in the given schema, and adding one would be
--    a second, independently-evolving audit trail for the same table this
--    migration deliberately avoids).
-- 2. **Role-hierarchy finding (disclosed, per this task's own explicit
--    instruction to check before deciding).** `app.customer_portal_account_
--    memberships`'s own `cpam_role_check` CHECK constraint (CPL-300, read
--    directly from the applied migration before writing this one) admits
--    EXACTLY two values: `account_admin`, `member` -- a flat, two-level model,
--    not a ranked hierarchy of three or more roles. Every write RPC in this
--    whole capability (CPL-300's own invite/set_status, and this migration's
--    own update_role/record_access_review) is already gated on the caller
--    holding an ACTIVE `account_admin` row -- the higher of the two values --
--    so a caller who reaches this function's own authority check by
--    construction already holds the maximum authority this role model has.
--    Granting either `account_admin` or `member` to a target membership is
--    therefore never an escalation past the caller's OWN already-maximal
--    authority -- there is no THIRD, higher role to escalate into. This
--    mirrors app.invite_customer_portal_user's own already-shipped, already-
--    accepted behavior of letting an account_admin invite a brand-new member
--    at EITHER role value. No additional "may not grant a role higher than
--    my own" check is added because the role model this repository actually
--    built has no such gradient to guard against -- adding one would be
--    defending against a case this schema cannot construct.
-- 3. **A genuine, disclosed hardening beyond the literal mirror: the
--    "last active account_admin" guard.** Live reasoning (not merely
--    mirroring) surfaced a real gap CPL-300's own set_status function ALSO
--    has (see design decision 8 below, since that migration is applied and
--    may not be edited here): nothing stops the SOLE active account_admin on
--    an account from demoting themselves to `member`, after which the account
--    has no self-service path back -- app.grant_initial_customer_portal_
--    account_admin (CPL-300) is a no-op once ANY row already exists for that
--    identity+account (it returns the existing row unchanged, it does not
--    promote it), so a demoted sole admin cannot even re-bootstrap themselves
--    through the one staff-facing escape hatch that exists. This migration's
--    OWN new `app.update_customer_portal_account_membership_role` therefore
--    rejects (`last_account_admin`) a demotion that would leave an account
--    with zero remaining active account_admin rows. Race-safety: rather than
--    a bare `count(*)` after the target row's own `for update` lock (which
--    would leave a genuine TOCTOU window -- two concurrent demotions of two
--    DIFFERENT admins on a 2-admin account could each read "1 other admin
--    remains" before either commits, and both succeed, leaving zero), the
--    demotion branch additionally locks EVERY currently-active account_admin
--    row for the same account (`for update`) before counting, serializing any
--    concurrent demotion attempt against the same account's own admin set.
--    Reasoned about and structurally relies on Postgres's own row-lock
--    guarantee (mirrors ISS-2026-014's own established disclosure convention
--    for this class of claim) -- this checkpoint's own db-test proves the
--    guard's SEQUENTIAL correctness (a lone admin cannot demote themselves; a
--    non-last admin can be demoted; the true last cannot), not a genuine
--    multi-process concurrent-race harness (that infrastructure is scripts/
--    load-tests/'s own dedicated job, ATW-024, not an ordinary capability
--    db-test's).
-- 4. **Gap 2 -- access review.** A NEW, SEPARATE, additive table, app.
--    customer_portal_account_membership_access_reviews (membership_id,
--    reviewed_by_actor_auth_user_id, review_outcome, note, reviewed_at, plus
--    tenant_id/account_id denormalized copies mirroring app.customer_portal_
--    account_membership_history's own established denormalization, an
--    idempotency_key, and reviewed_by_label mirroring the suspended_by/
--    revoked_by text-label convention already used on the parent table) --
--    NOT a nullable last_reviewed_at/last_reviewed_by/last_review_note ADD
--    COLUMN on CPL-300's own already-applied app.customer_portal_account_
--    memberships. A new, additive table is strictly safer than altering an
--    applied table's own column set even where this repository's convention
--    permits a nullable ADD COLUMN -- it carries zero risk of colliding with
--    that table's own already-`VERIFIED` shape, its own status-transition
--    trigger, or any already-shipped caller's own row-shape assumption
--    (e.g. a `select m.*` caller that would otherwise silently start
--    receiving three new columns it never asked for). The review record is
--    also naturally APPEND-ONLY evidence (each review event is its own row,
--    never overwritten) -- the exact shape a bolt-on "last_*" column set
--    could not represent (it can only ever show the MOST RECENT review, never
--    the full history), so the new-table shape is not merely safer, it is
--    also the more correct model for "record a review action" read literally.
-- 5. **Access-review outcome is a closed, two-value enum**
--    (`confirmed_appropriate`, `flagged_for_follow_up`) -- an access review is
--    an ATTESTATION ("is this person's access still appropriate"), not itself
--    a corrective action. A reviewer who concludes a role/status change is
--    warranted performs that change through the existing, unmodified
--    app.update_customer_portal_account_membership_role / app.set_customer_
--    portal_account_membership_status RPCs (this migration composes neither
--    of those INTO the review RPC -- keeping "record what I observed" and
--    "change what I'm granting" as two independent, separately-audited
--    actions, never one RPC silently doing both).
-- 6. **Idempotency (this batch's own mandatory pattern, applied to BOTH new
--    mutating RPCs).** `app.update_customer_portal_account_membership_role`
--    is idempotent by construction on its own natural key -- a repeated call
--    with the identical target role for a membership already at that role is
--    a genuine no-op (returns the unchanged row, no touch-row bump, no
--    spurious history entry) -- mirroring how a role either already IS the
--    requested value or it is not, with no separate synthetic key needed.
--    `app.record_customer_portal_account_membership_access_review` is a
--    genuine append-only EVENT (two reviews of the same membership on two
--    different occasions are two real, distinct rows, never collapsed), so it
--    needs a REAL caller-supplied idempotency key exactly like every ledger-
--    posting RPC in this repository: a real `unique (tenant_id,
--    idempotency_key)` constraint (NOT NULL, NOT a nullable/partial index --
--    mirroring app.inventory_movements'/app.inventory_reservations' own
--    ledger-shaped, always-required key, since this batch's own mandate reads
--    every new RPC in the batch as ledger-posting-grade), the scope/authority
--    check running BEFORE the idempotent short-circuit SELECT, and a real
--    `exception when unique_violation` handler around the INSERT (never a
--    pre-check-only pattern) -- mirrors app.submit_customer_profile_change_
--    request's (CPL-314) own established shape exactly, including verifying
--    the FULL target tuple (membership_id) on the short-circuit match, not
--    only the key (C-01).
-- 7. **Every actor-taking function in this migration calls app.assert_actor_
--    is_session_identity as its OWN literal first statement** -- this batch's
--    own single most emphasized mandatory pattern, applied from the first
--    draft to all four new functions (two mutations, two reads -- the two
--    reads carry an identity-scoping p_actor_auth_user_id exactly like CPL-
--    300's own Finding-1 Tier C fix required for that migration's own reads).
-- 8. **Disclosed, NOT fixed here (forbidden -- applied migration, DO NOT
--    EDIT): the identical "last active account_admin" gap this migration's
--    own design decision 3 closes for update_role ALSO exists, unfixed, in
--    CPL-300's own already-VERIFIED app.set_customer_portal_account_
--    membership_status** -- an account_admin can suspend/revoke themselves,
--    or the account's only other account_admin, leaving the account with zero
--    active account_admin rows and no self-service recovery path (app.grant_
--    initial_customer_portal_account_admin no-ops once any row already exists
--    for that identity+account). Registered as a new, additive KNOWN_ISSUES.md
--    entry (this migration's own companion doc edit) rather than silently
--    left undisclosed -- recommended fix for whichever future checkpoint owns
--    it: a dedicated additive hardening migration mirroring this one's own
--    design decision 3 guard, applied to that function via its own new
--    migration (never an edit to the applied 20260801010000 file).
-- 9. **Anti-enumeration (C-05), disclosed continuation of an already-accepted
--    precedent, not a new regression.** Both new mutation-by-id RPCs
--    (update_role, record_access_review) fetch their target membership row
--    (to learn its own tenant_id/account_id, required to run the authority
--    check at all) BEFORE the authority check, raising a distinguishable
--    `customer_portal_membership_not_found` vs. `insufficient_authority` --
--    the IDENTICAL shape CPL-300's own set_customer_portal_account_
--    membership_status/accept_customer_portal_invite already have, already
--    live-reviewed and accepted as `ISS-2026-116` (Low, OPEN): `p_membership_
--    id` is a random, non-guessable UUID a caller can only ever have via
--    legitimate visibility (their own invite, or app.list_customer_portal_
--    account_memberships/this migration's own app.list_customer_portal_
--    account_memberships_for_access_review, both already identity-checked) --
--    no practical enumeration path exists. Deliberately mirrored rather than
--    "fixed" here to keep this whole capability's own error shape uniform;
--    fixing the class repository-wide (if ever warranted) belongs to
--    ISS-2026-116's own future owner, not a one-off divergence introduced by
--    this migration alone.
-- 10. **Two new read RPCs, both composing app.actor_is_active_customer_
--     portal_account_admin directly in their own body (deny-by-default, empty
--     result for a non-admin caller, never an error) -- automatically covered
--     by scripts/db-tests/rbac-enforcement.sql's own ATW-032 base-regex
--     closure sweep with ZERO edit to that shared file required** (verified
--     live in this checkpoint's own scratch-database run, not merely
--     assumed) -- mirrors CPL-314's own identical "no edit required" outcome.
--     `app.list_customer_portal_account_membership_access_reviews` (raw
--     review history, optionally filtered to one membership) and app.list_
--     customer_portal_account_memberships_for_access_review (the "admin-
--     facing view of active memberships in scope" the source prompt's own
--     access-review requirement names, pre-joined with each membership's own
--     MOST RECENT review via a LATERAL join so the UI needs exactly one call
--     for the review screen's own table, never an N+1).
-- 11. **No REST/GraphQL HTTP route, no MFA/step-up-auth mechanism added** --
--     both standing, repository-wide, not-CPL-315-specific gaps, identical in
--     kind to every disclosure CPL-300/CPL-314 already made for the SAME two
--     gaps. See this migration's own companion KNOWN_ISSUES.md entry and
--     docs/build-log/phase-08/CPL-315.md for the full, literal disclosure
--     text this task's own instructions require verbatim.
-- 12. Per `ERR-2026-004`: this migration carries its own explicit `revoke
--     execute on all functions in schema app from public` statement before
--     its final grants.
-- 13. **Tier C review fix (Batch 4 close): `app.update_customer_portal_
--     account_membership_role`'s optimistic-concurrency check now rejects a
--     NULL `p_expected_version` instead of silently letting it through.**
--     `record_version <> NULL` evaluates to SQL NULL, which `if ... then
--     raise` treats as false -- a caller supplying no expected version was
--     applying its write completely unchecked. Fixed by additionally
--     repeating `and record_version = p_expected_version` on the UPDATE
--     itself (so a NULL never matches any row, falling through to the same
--     `stale_version` error) -- this repository's own TS contract layer
--     already requires a positive integer here, so the app's own callers
--     were never exposed, but the RPC itself is meant to be self-defending,
--     not merely protected by the app layer above it.

-- ===========================================================================
-- 1. app.customer_portal_account_membership_access_reviews -- append-only
-- ===========================================================================

create table app.customer_portal_account_membership_access_reviews (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  account_id uuid not null references app.accounts (id),
  membership_id uuid not null references app.customer_portal_account_memberships (id),
  reviewed_by_actor_auth_user_id uuid not null references auth.users (id),
  reviewed_by_label text,
  review_outcome text not null,
  note text,
  idempotency_key text not null,
  -- clock_timestamp(), not now(): now() is frozen at transaction start, so
  -- two reviews recorded for the same membership inside one transaction
  -- (the exact shape scripts/db-tests/customer-user-management.sql's own
  -- fixture exercises) would get a byte-identical reviewed_at, leaving
  -- app.list_customer_portal_account_memberships_for_access_review's own
  -- "most recent review" resolution (order by reviewed_at desc, id desc)
  -- to tie-break on id -- a random gen_random_uuid(), not an insertion-order
  -- signal -- making "most recent" a coin flip. clock_timestamp() advances
  -- on every call regardless of transaction boundaries, so two reviews
  -- always get distinct, correctly-ordered timestamps. Self-found via live
  -- re-run of this migration's own db-test (2 of 3 fresh runs failed at an
  -- assertion expecting the second review to be the one returned).
  reviewed_at timestamptz not null default clock_timestamp(),
  created_at timestamptz not null default now(),
  constraint cpamar_review_outcome_check check (review_outcome in ('confirmed_appropriate', 'flagged_for_follow_up')),
  constraint cpamar_tenant_idempotency_unique unique (tenant_id, idempotency_key)
);

comment on table app.customer_portal_account_membership_access_reviews is
  'CPL-315: append-only access-review attestation events, one row per review action -- never updated or deleted, and never itself a corrective action (design decision 5). A new, additive table (design decision 4), never an ALTER TABLE on CPL-300''s own applied app.customer_portal_account_memberships. RLS enabled, authenticated holds zero direct grant -- the RPCs below are the only sanctioned access path, mirroring every other table in this whole capability.';

create index cpamar_membership_reviewed_at_idx
  on app.customer_portal_account_membership_access_reviews (tenant_id, membership_id, reviewed_at desc, id desc);
create index cpamar_account_reviewed_at_idx
  on app.customer_portal_account_membership_access_reviews (tenant_id, account_id, reviewed_at desc, id desc);

-- ===========================================================================
-- 2. app.update_customer_portal_account_membership_role -- Gap 1
-- ===========================================================================

create function app.update_customer_portal_account_membership_role(
  p_membership_id uuid,
  p_expected_version integer,
  p_new_role text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.customer_portal_account_memberships
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_membership app.customer_portal_account_memberships;
  v_updated app.customer_portal_account_memberships;
  v_remaining_admins integer;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if p_new_role not in ('account_admin', 'member') then
    raise exception 'invalid_role: % is not a recognized customer portal role', p_new_role using errcode = 'check_violation';
  end if;

  select * into v_membership from app.customer_portal_account_memberships where id = p_membership_id for update;
  if not found then
    raise exception 'customer_portal_membership_not_found: %', p_membership_id using errcode = 'no_data_found';
  end if;

  -- Design decision 9: fetching the target row before the authority check
  -- (to learn its own tenant_id/account_id, required to evaluate authority at
  -- all) deliberately mirrors CPL-300's own already-accepted ISS-2026-116
  -- error shape -- not a new disclosure.
  if not app.actor_is_active_customer_portal_account_admin(v_membership.tenant_id, v_membership.account_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % is not an active account_admin on account %', p_actor_auth_user_id, v_membership.account_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_membership.status <> 'active' then
    raise exception 'invalid_transition: customer portal membership % is %, only an active membership''s role may be changed', p_membership_id, v_membership.status
      using errcode = 'check_violation';
  end if;

  -- Tier C review fix: p_expected_version IS NULL must not silently bypass
  -- this check -- `record_version <> NULL` evaluates to SQL NULL, which a
  -- bare `if ... then raise` treats as false. This early check stays (it
  -- gives the common "wrong version supplied" case a clear message), and
  -- the UPDATE below ALSO repeats `and record_version = p_expected_version`
  -- so a NULL (or any other value that reaches this far some other way)
  -- matches zero rows and falls through to the same stale_version error --
  -- defense in depth, never a single point of failure for this guard.
  if v_membership.record_version <> p_expected_version then
    raise exception 'stale_version: customer portal membership % expected version % but found %', p_membership_id, p_expected_version, v_membership.record_version
      using errcode = 'serialization_failure';
  end if;

  -- Idempotent no-op (design decision 6): the identical role is already in
  -- effect -- return unchanged, no spurious touch-row bump / history entry.
  if v_membership.role = p_new_role then
    return v_membership;
  end if;

  -- Last-account_admin guard (design decision 3). Row-lock the FULL active
  -- account_admin set for this account (not merely v_membership's own row,
  -- already locked above) before deciding, closing the TOCTOU window a bare
  -- count() after only-this-row's-own-lock would leave open.
  if v_membership.role = 'account_admin' and p_new_role = 'member' then
    perform 1 from app.customer_portal_account_memberships
    where tenant_id = v_membership.tenant_id
      and account_id = v_membership.account_id
      and role = 'account_admin'
      and status = 'active'
    for update;

    select count(*) into v_remaining_admins
    from app.customer_portal_account_memberships
    where tenant_id = v_membership.tenant_id
      and account_id = v_membership.account_id
      and role = 'account_admin'
      and status = 'active'
      and id <> v_membership.id;

    if v_remaining_admins = 0 then
      raise exception 'last_account_admin: account % must retain at least one active account_admin', v_membership.account_id
        using errcode = 'check_violation';
    end if;
  end if;

  update app.customer_portal_account_memberships
  set role = p_new_role
  where id = p_membership_id and record_version = p_expected_version
  returning * into v_updated;
  if not found then
    raise exception 'stale_version: customer portal membership % was concurrently modified (expected version %)', p_membership_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  insert into app.customer_portal_account_membership_history
    (membership_id, auth_user_id, tenant_id, account_id, from_status, to_status, reason, requested_by)
  values
    (v_updated.id, v_updated.auth_user_id, v_updated.tenant_id, v_updated.account_id, v_updated.status, v_updated.status,
     format('role changed from %s to %s', v_membership.role, p_new_role), p_actor_label);

  return v_updated;
end;
$$;

comment on function app.update_customer_portal_account_membership_role is
  'CPL-315: change role (account_admin <-> member) for an existing ACTIVE membership. Caller-gated by app.actor_is_active_customer_portal_account_admin on the SAME account_id (design decision 5 of CPL-300, composed here unchanged). Mirrors app.set_customer_portal_account_membership_status''s own shape exactly (optimistic concurrency, audit write into app.customer_portal_account_membership_history). Flat two-role model (design decision 2) -- no role escalation is possible beyond the caller''s own already-maximal account_admin authority. Rejects (last_account_admin) a demotion that would leave the account with zero active account_admin rows (design decision 3) -- a genuine, disclosed hardening beyond the literal mirror; the identical gap remains OPEN, unfixed, in CPL-300''s own applied set_customer_portal_account_membership_status (cannot edit that migration; see this migration''s own companion KNOWN_ISSUES.md entry).';

-- ===========================================================================
-- 3. app.record_customer_portal_account_membership_access_review -- Gap 3 (access review)
-- ===========================================================================

create function app.record_customer_portal_account_membership_access_review(
  p_membership_id uuid,
  p_review_outcome text,
  p_note text,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.customer_portal_account_membership_access_reviews
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_membership app.customer_portal_account_memberships;
  v_existing app.customer_portal_account_membership_access_reviews;
  v_review app.customer_portal_account_membership_access_reviews;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if p_review_outcome not in ('confirmed_appropriate', 'flagged_for_follow_up') then
    raise exception 'invalid_review_outcome: % is not a recognized access review outcome', p_review_outcome using errcode = 'check_violation';
  end if;
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'invalid_idempotency_key: an idempotency key is required' using errcode = 'check_violation';
  end if;

  select * into v_membership from app.customer_portal_account_memberships where id = p_membership_id;
  if not found then
    raise exception 'customer_portal_membership_not_found: %', p_membership_id using errcode = 'no_data_found';
  end if;

  -- Scope/authority check BEFORE the idempotent short-circuit (design
  -- decision 6, this batch's own mandatory pattern).
  if not app.actor_is_active_customer_portal_account_admin(v_membership.tenant_id, v_membership.account_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % is not an active account_admin on account %', p_actor_auth_user_id, v_membership.account_id
      using errcode = 'insufficient_privilege';
  end if;

  -- Access reviews answer "is this person's access still appropriate" --
  -- only meaningful against a currently active membership, never a pending
  -- invite, suspended, or revoked row.
  if v_membership.status <> 'active' then
    raise exception 'invalid_review_target: customer portal membership % is %, only an active membership may be access-reviewed', p_membership_id, v_membership.status
      using errcode = 'check_violation';
  end if;

  select * into v_existing from app.customer_portal_account_membership_access_reviews
  where tenant_id = v_membership.tenant_id and idempotency_key = p_idempotency_key;
  if found then
    if v_existing.membership_id = p_membership_id then
      return v_existing;
    end if;
    raise exception 'idempotency_key_conflict: key % was already used for a different membership''s access review %', p_idempotency_key, v_existing.id
      using errcode = 'unique_violation';
  end if;

  -- Real exception handler, not merely a pre-check (design decision 6) -- a
  -- genuine concurrent double-submit under the identical key converges on one
  -- row, mirroring app.submit_customer_profile_change_request (CPL-314).
  begin
    insert into app.customer_portal_account_membership_access_reviews (
      tenant_id, account_id, membership_id, reviewed_by_actor_auth_user_id, reviewed_by_label, review_outcome, note, idempotency_key
    ) values (
      v_membership.tenant_id, v_membership.account_id, p_membership_id, p_actor_auth_user_id, p_actor_label, p_review_outcome, p_note, p_idempotency_key
    )
    returning * into v_review;
  exception
    when unique_violation then
      select * into v_review from app.customer_portal_account_membership_access_reviews
      where tenant_id = v_membership.tenant_id and idempotency_key = p_idempotency_key;
      if not found or v_review.membership_id <> p_membership_id then
        raise;
      end if;
      return v_review;
  end;

  return v_review;
end;
$$;

comment on function app.record_customer_portal_account_membership_access_review is
  'CPL-315: records an access-review attestation for an ACTIVE membership -- an observation, never itself a role/status change (design decision 5; a reviewer who concludes a change is warranted performs it through app.update_customer_portal_account_membership_role / app.set_customer_portal_account_membership_status separately). Caller-gated by app.actor_is_active_customer_portal_account_admin. Idempotent on (tenant_id, idempotency_key), a real NOT NULL unique constraint (design decision 6, ledger-grade -- never a nullable/partial key); the scope/authority check runs BEFORE the idempotent short-circuit SELECT, and the INSERT carries a real exception when unique_violation handler, verifying the full target tuple (membership_id) on a key match, not only the key itself (C-01).';

-- ===========================================================================
-- 4. app.list_customer_portal_account_membership_access_reviews -- read
-- ===========================================================================

create function app.list_customer_portal_account_membership_access_reviews(
  p_tenant_id uuid,
  p_account_id uuid,
  p_actor_auth_user_id uuid,
  p_membership_id uuid default null,
  p_cursor_reviewed_at timestamptz default null,
  p_cursor_id uuid default null,
  p_limit integer default 50
)
returns setof app.customer_portal_account_membership_access_reviews
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_limit integer;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if p_cursor_id is not null and p_cursor_reviewed_at is null then
    raise exception 'invalid_cursor: p_cursor_reviewed_at is required when p_cursor_id is supplied' using errcode = 'invalid_parameter_value';
  end if;

  -- account_admin-only; deny-by-default, empty set (never an error) for a
  -- non-admin caller, mirroring app.list_customer_portal_account_memberships.
  if not app.actor_is_active_customer_portal_account_admin(p_tenant_id, p_account_id, p_actor_auth_user_id) then
    return;
  end if;

  v_limit := least(greatest(coalesce(p_limit, 50), 1), 200);

  return query
  select r.*
  from app.customer_portal_account_membership_access_reviews r
  where r.tenant_id = p_tenant_id
    and r.account_id = p_account_id
    and (p_membership_id is null or r.membership_id = p_membership_id)
    and (p_cursor_id is null or (r.reviewed_at, r.id) < (p_cursor_reviewed_at, p_cursor_id))
  order by r.reviewed_at desc, r.id desc
  limit v_limit;
end;
$$;

comment on function app.list_customer_portal_account_membership_access_reviews is
  'CPL-315: account_admin-only access-review history for one account, optionally filtered to one membership. Keyset-paginated on (reviewed_at desc, id desc), never OFFSET, hard-capped at 200.';

-- ===========================================================================
-- 5. app.list_customer_portal_account_memberships_for_access_review -- read
-- ===========================================================================

create function app.list_customer_portal_account_memberships_for_access_review(
  p_tenant_id uuid,
  p_account_id uuid,
  p_actor_auth_user_id uuid,
  p_cursor_updated_at timestamptz default null,
  p_cursor_id uuid default null,
  p_limit integer default 50
)
returns table (
  membership_id uuid,
  auth_user_id uuid,
  role text,
  status text,
  granted_at timestamptz,
  updated_at timestamptz,
  record_version integer,
  last_reviewed_at timestamptz,
  last_reviewed_by_label text,
  last_review_outcome text,
  last_review_note text
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_limit integer;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if p_cursor_id is not null and p_cursor_updated_at is null then
    raise exception 'invalid_cursor: p_cursor_updated_at is required when p_cursor_id is supplied' using errcode = 'invalid_parameter_value';
  end if;

  -- The "admin-facing view of active memberships in scope" the source
  -- prompt's own access-review requirement names -- deny-by-default, empty
  -- set (never an error) for a non-admin caller.
  if not app.actor_is_active_customer_portal_account_admin(p_tenant_id, p_account_id, p_actor_auth_user_id) then
    return;
  end if;

  v_limit := least(greatest(coalesce(p_limit, 50), 1), 200);

  return query
  select
    m.id as membership_id,
    m.auth_user_id,
    m.role,
    m.status,
    m.granted_at,
    m.updated_at,
    m.record_version,
    r.reviewed_at as last_reviewed_at,
    r.reviewed_by_label as last_reviewed_by_label,
    r.review_outcome as last_review_outcome,
    r.note as last_review_note
  from app.customer_portal_account_memberships m
  left join lateral (
    select rr.reviewed_at, rr.reviewed_by_label, rr.review_outcome, rr.note
    from app.customer_portal_account_membership_access_reviews rr
    where rr.membership_id = m.id
    order by rr.reviewed_at desc, rr.id desc
    limit 1
  ) r on true
  where m.tenant_id = p_tenant_id
    and m.account_id = p_account_id
    and m.status = 'active'
    and (p_cursor_id is null or (m.updated_at, m.id) < (p_cursor_updated_at, p_cursor_id))
  order by m.updated_at desc, m.id desc
  limit v_limit;
end;
$$;

comment on function app.list_customer_portal_account_memberships_for_access_review is
  'CPL-315: active-only membership roster for one account, pre-joined (LATERAL, one row max per membership) with each membership''s own MOST RECENT access review, if any -- one call for the whole review screen, never an N+1. account_admin-only, deny-by-default. Keyset-paginated on (updated_at desc, id desc), never OFFSET, hard-capped at 200.';

-- ===========================================================================
-- 6. RLS -- enable, grant service_role only, mirrors every table in this
-- whole capability (design decision 4/CPL-300 design decision 3)
-- ===========================================================================

alter table app.customer_portal_account_membership_access_reviews enable row level security;

grant select, insert, update, delete
  on app.customer_portal_account_membership_access_reviews
  to service_role;

-- Per ERR-2026-004: explicit, directly-provable revoke of PostgreSQL's
-- PUBLIC-execute default, the standing per-migration convention since
-- PLT-118, applied here before any role-specific grant.
revoke execute on all functions in schema app from public;

grant execute on function app.update_customer_portal_account_membership_role(uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.record_customer_portal_account_membership_access_review(uuid, text, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.list_customer_portal_account_membership_access_reviews(uuid, uuid, uuid, uuid, timestamptz, uuid, integer) to authenticated, service_role;
grant execute on function app.list_customer_portal_account_memberships_for_access_review(uuid, uuid, uuid, timestamptz, uuid, integer) to authenticated, service_role;
