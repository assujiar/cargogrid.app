-- PLT-138 (Tenant/Security/Platform Hardening, CG-S6-PLT-035): closes the single
-- finding PLT-137's own integrated verification recorded (docs/build-log/phase-01/
-- PLT-137.md §5, item 1) -- purely additive, zero behavioral/schema/privilege change.
--
-- app.resolve_access_context() (PLT-108, 20260716100825_create_principal_memberships.sql)
-- has never carried a `comment on function` -- its own behavior was documented only via
-- inline `--` comments inside the function body, and PLT-137's own integration testing
-- found that a reader could plausibly (mis)read the p_tenant_id-omitted branch's own
-- "always resolves first and alone" inline comment as describing every call shape,
-- when in fact a tenant-QUALIFIED call for a Supreme Admin holding no per-tenant
-- app.tenant_user_identities row instead fails closed with `inactive_identity_link`,
-- not a silent Supreme resolution. Confirmed at PLT-137: the one real caller,
-- lib/portal/supreme-admin-guard.ts (PLT-136), always omits p_tenant_id -- so this was
-- a documentation-accuracy gap only, zero production impact, and was correctly not
-- fixed inside PLT-137 itself (a verification-only, no-repair-by-default checkpoint).
--
-- The root-cause repair: add the `comment on function` this function should have
-- carried from the start, describing both branches accurately, so a future reader
-- introspecting the schema directly (\df+, information_schema, or any tool reading
-- pg_proc.obj_description) sees the real, complete contract -- not just whichever
-- inline comment they happen to scroll past. No source line inside the original
-- migration is edited (migrations in this repository are immutable once applied,
-- 00_PLATFORM_CORE_WBS.md's own convention) -- this is purely additive schema
-- metadata, requiring no REVOKE/GRANT (COMMENT ON does not touch privileges) and no
-- rebuild of the function body itself.

comment on function app.resolve_access_context(uuid, uuid, text) is
  'PLT-108: resolves the caller''s four-layer access context. Two distinct branches, not one: '
  '(1) p_tenant_id omitted (null) -- a live Supreme Admin grant always resolves first and alone, '
  'never sharing an unqualified request with a tenant-scoped layer; absent that, the caller''s '
  'single active global-scope principal_membership resolves, or no_active_membership/'
  'ambiguous_context raises if zero/multiple exist. '
  '(2) p_tenant_id supplied -- the target tenant must itself be canonical_status=active '
  '(else inactive_tenant), AND the caller must hold its own active app.tenant_user_identities '
  '(PLT-107) row for that exact tenant (else inactive_identity_link) -- this branch has no '
  'Supreme Admin shortcut: a global-only Supreme Admin with no per-tenant identity link fails '
  'closed here exactly like any other unlinked identity would, by design (verified at PLT-137''s '
  'own integration testing, docs/build-log/phase-01/PLT-137.md §5/§6 scenario 3). The one '
  'production caller of the tenant-qualified form is app.has_active_tenant_membership()''s own '
  'RLS-facing callers; lib/portal/supreme-admin-guard.ts (PLT-136) always calls the omitted-'
  'p_tenant_id form instead, so this branch''s fail-closed behavior for Supreme Admin has no '
  'portal-facing impact.';
