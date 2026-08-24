-- HDN-373 (Step 15, Prompt 373, RLS and RBAC Audit, `CG-S15-HDN-005`) — closes
-- `ISS-2026-171`/`ISS-2026-173`, carried forward from `HDN-372`'s own Tier C review,
-- plus one further instance of the identical gap this checkpoint's own investigation
-- found (`app.notification_preferences`).
--
-- `app.notifications`, `app.notification_preferences` and `app.saved_report_views` each
-- carry an own-row `SELECT` policy of the shape `<owner column> = auth.uid() or
-- is_supreme_admin()` with **no tenant-membership conjunct** — unlike every other
-- own-row policy in this schema (`app.notification_contact_addresses_select_own` is the
-- established correct reference pattern, itself fixed for the identical bug at `IAE-014`,
-- `20260805070000_harden_intelligence_batch4_tier_c_review_fixes.sql`). A **revoked**
-- ex-member of a tenant therefore retains RLS-level read access to their own past rows —
-- notification inboxes, notification channel preferences, and saved report-view
-- configuration — from when they were an active member, indefinitely, unlike every other
-- table in the schema, which correctly fails closed post-revocation.
--
-- **Live-forced and confirmed** (Tier C investigation lens, `docs/build-log/full-system-
-- hardening/HDN-373.md` §6): a genuinely revoked ex-member, acting as themselves (no
-- forged actor — this is a revocation-propagation gap, not an identity-forgery one),
-- still reads their own past `app.notifications`/`app.saved_report_views` rows via
-- direct RLS. `app.notification_preferences` shares the identical policy shape and is
-- graded the identical way.
--
-- `app.saved_report_views_select_scoped`'s own original comment reasoned that "own-row
-- access is unconditional... is not the leak [the `ATW-032`/`ISS-2026-010` default-deny
-- narrowing] convention closes" — true for an ACTIVE customer_user-layer principal
-- reading their own row, but that reasoning never addressed the REVOKED case this
-- checkpoint found: once an identity is no longer a member of the tenant at all, its own
-- past application state should fail closed like everything else, not stay open because
-- the row happens to be self-authored.
--
-- **Fix**: add the same `app.has_active_tenant_membership(tenant_id)` conjunct every
-- other own-row policy in this schema already carries, to exactly the own-row branch of
-- each of the three policies (the `saved_report_views` tenant-shared branch already has
-- this conjunct and is untouched). The content, ownership and Supreme Admin exception are
-- otherwise unchanged.
--
-- **Self-caught completeness gap, fixed in the same migration rather than left for a
-- later session to trip over**: this migration's own first draft copied only half of the
-- established reference pattern (`app.notification_contact_addresses_select_own`, fixed
-- for the identical bug at `IAE-014`,
-- `20260805070000_harden_intelligence_batch4_tier_c_review_fixes.sql`) -- it carries
-- `app.has_active_tenant_membership(...)` **and** `not app.actor_holds_customer_user_layer(...)`
-- on its own-row branch, not membership alone. A customer_user-layer (portal) principal
-- holds an ordinary active `tenant_user_identities` row exactly like any staff member
-- (`ISS-2026-010`'s own default-deny premise), so membership alone does not exclude them
-- from a staff-facing table's own-row branch -- only the explicit layer check does.
-- `docs/db-tests/rbac-enforcement.sql`'s own pre-existing ATW-032/`ISS-2026-010` sweep
-- caught exactly this on `notifications`/`notification_preferences` (both policies'
-- entire predicate tested membership and nothing else); `saved_report_views`'s own-row
-- branch shares the identical gap but escaped that sweep's keyword heuristic only because
-- its TENANT-shared branch happens to already mention `actor_holds_customer_user_layer`,
-- satisfying the sweep's whole-predicate keyword match without the own-row branch itself
-- carrying the check -- fixed here for genuine correctness, not merely to satisfy the
-- sweep's own blind spot.
--
-- Full disposition: `docs/build-log/full-system-hardening/HDN-373.md` §6.

drop policy notification_preferences_select_own on app.notification_preferences;
create policy notification_preferences_select_own on app.notification_preferences
  for select to authenticated
  using (
    (
      auth_user_id = (select auth.uid())
      and app.has_active_tenant_membership(tenant_id)
      and not app.actor_holds_customer_user_layer(tenant_id)
    )
    or app.is_supreme_admin()
  );

drop policy notifications_select_own on app.notifications;
create policy notifications_select_own on app.notifications
  for select to authenticated
  using (
    (
      recipient_auth_user_id = (select auth.uid())
      and app.has_active_tenant_membership(tenant_id)
      and not app.actor_holds_customer_user_layer(tenant_id)
    )
    or app.is_supreme_admin()
  );

drop policy saved_report_views_select_scoped on app.saved_report_views;
create policy saved_report_views_select_scoped on app.saved_report_views
  for select to authenticated
  using (
    app.is_supreme_admin()
    or (
      owner_auth_user_id = (select auth.uid())
      and app.has_active_tenant_membership(tenant_id)
      and not app.actor_holds_customer_user_layer(tenant_id)
    )
    or (sharing_scope = 'tenant' and app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id))
  );
