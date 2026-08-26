/**
 * Real `RegisterLoginSessionDeps` wiring (ISS-2026-264). Mirrors
 * `lib/portal/tenant-admin-guard-deps.server.ts`'s own composition exactly: the
 * RLS-scoped `authenticated` client for the tenant-by-slug lookup, the service-role
 * client for `app.resolve_access_context` and `app.register_user_session` (both
 * `service_role`-only). Server-only -- imports `next/headers` transitively via
 * `lib/supabase/server.ts`.
 */

import { createSupabaseServerClient } from "../supabase/server.ts";
import { createSupabaseServiceRoleClient } from "../supabase/service-role.ts";
import { registerUserSession } from "../../server/mutations/enterprise-mfa.ts";
import type { RegisterLoginSessionDeps, RegisterLoginSessionTenantLookup, RegisterLoginSessionAccessContext } from "./register-login-session.ts";

export async function buildRegisterLoginSessionDeps(): Promise<RegisterLoginSessionDeps> {
  const supabase = await createSupabaseServerClient();
  const serviceRole = createSupabaseServiceRoleClient();

  return {
    async findTenantBySlug(slug: string): Promise<RegisterLoginSessionTenantLookup | null> {
      const { data, error } = await supabase.from("tenants").select("id").eq("slug", slug).maybeSingle();
      if (error || !data) return null;
      return { id: data.id as string };
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
