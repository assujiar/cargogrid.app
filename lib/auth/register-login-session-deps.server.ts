/**
 * Real `RegisterLoginSessionDeps` wiring (ISS-2026-264). Mirrors
 * `lib/portal/tenant-admin-guard-deps.server.ts`'s own composition exactly: the
 * RLS-scoped `authenticated` client for the tenant-by-slug lookup, the service-role
 * client for `app.resolve_access_context` and `app.register_user_session` (both
 * `service_role`-only). Server-only -- imports `next/headers` transitively via
 * `lib/supabase/server.ts`.
 *
 * `findTenantBySlug` resolves via the `public.resolve_tenant_by_slug_for_member` RPC
 * (CG-AUDIT-2026-09-02 Ø1+Ø2): schema `app` is not exposed to PostgREST so a
 * `.from("tenants")` query can never resolve (Ø1). This call fires from the one shared
 * `app/(public)/login/` route for EVERY principal layer, tenant-admin and customer_user
 * alike -- `resolve_tenant_by_slug_for_actor` (tenant-admin-only, deliberately excludes
 * customer_user) would silently skip session registration for every customer sign-in
 * (Ø2's own lockout mechanism), so `resolve_tenant_by_slug_for_member` (admits any
 * active member, either layer) is used instead. Best-effort either way -- the caller
 * already treats a null return as "nothing to register a session against" and never
 * blocks sign-in on it, per this file's own pure-logic module's documented contract.
 */

import { createSupabaseServerClient } from "../supabase/server.ts";
import { createSupabaseServiceRoleClient } from "../supabase/service-role.ts";
import { registerUserSession } from "../../server/mutations/enterprise-mfa.ts";
import type { RegisterLoginSessionDeps, RegisterLoginSessionTenantLookup, RegisterLoginSessionAccessContext } from "./register-login-session.ts";

export async function buildRegisterLoginSessionDeps(): Promise<RegisterLoginSessionDeps> {
  const supabase = await createSupabaseServerClient();
  const serviceRole = createSupabaseServiceRoleClient();

  return {
    async findTenantBySlug(slug: string, authUserId: string): Promise<RegisterLoginSessionTenantLookup | null> {
      const { data, error } = await supabase.rpc("resolve_tenant_by_slug_for_member", { p_slug: slug, p_actor_auth_user_id: authUserId });
      if (error || !data) return null;
      const row = (Array.isArray(data) ? data[0] : data) as { id: string } | undefined;
      if (!row) return null;
      return { id: row.id };
    },

    async resolveAccessContext(authUserId: string, tenantId: string): Promise<RegisterLoginSessionAccessContext | null> {
      const { data, error } = await serviceRole.rpc("resolve_access_context", { p_auth_user_id: authUserId, p_tenant_id: tenantId });
      if (error || !data) return null;
      const row = data as { layer: string };
      return { layer: row.layer };
    },

    async registerSession(tenantId: string, authUserId: string, actorLabel: string): Promise<void> {
      await registerUserSession(serviceRole, {
        tenantId,
        deviceLabel: null,
        ipAddress: null,
        actorAuthUserId: authUserId,
        actorLabel,
      });
    },
  };
}
