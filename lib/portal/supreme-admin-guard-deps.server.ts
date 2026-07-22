/**
 * Real `SupremeAdminGuardDeps` wiring (PLT-136, CG-S6-PLT-033) -- mirrors
 * `tenant-admin-guard-deps.server.ts`'s own split (RLS-scoped client for the current
 * user, service-role client for the `service_role`-only `app.resolve_access_context`
 * RPC). `p_tenant_id` is omitted (defaults to `null`) -- the global, tenant-independent
 * resolution path.
 */

import { createSupabaseServerClient } from "../supabase/server.ts";
import { createSupabaseServiceRoleClient } from "../supabase/service-role.ts";
import type { SupremeAdminGuardDeps, ResolvedSupremeContextResult } from "./supreme-admin-guard.ts";

export async function buildSupremeAdminGuardDeps(): Promise<SupremeAdminGuardDeps> {
  const supabase = await createSupabaseServerClient();
  const serviceRole = createSupabaseServiceRoleClient();

  return {
    async getCurrentUserId() {
      const { data, error } = await supabase.auth.getUser();
      if (error || !data.user) return null;
      return data.user.id;
    },

    async resolveGlobalAccessContext(authUserId: string): Promise<ResolvedSupremeContextResult | null> {
      const { data, error } = await serviceRole.rpc("resolve_access_context", { p_auth_user_id: authUserId });
      if (error || !data) return null;
      const row = data as { layer: string };
      return { layer: row.layer };
    },
  };
}
