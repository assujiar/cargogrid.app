/**
 * Real `TenantAdminGuardDeps` wiring (PLT-135, CG-S6-PLT-032) -- bridges the pure
 * `lib/portal/tenant-admin-guard.ts` logic to the two real Supabase clients this
 * portal needs: the RLS-scoped `authenticated` client (session identity and tenant lookup,
 * the latter via the `public.resolve_tenant_by_slug_for_actor` RPC -- CG-AUDIT-2026-09-02 Ø1,
 * schema `app` is not exposed to PostgREST so a `.from("tenants")` query can never resolve)
 * and the service-role client (`app.resolve_access_context`, `service_role`-only -- see
 * `lib/supabase/service-role.ts`'s own header). Server-only -- imports `next/headers`
 * transitively via `lib/supabase/server.ts`.
 */

import { createSupabaseServerClient } from "../supabase/server.ts";
import { createSupabaseServiceRoleClient } from "../supabase/service-role.ts";
import type { TenantAdminGuardDeps, TenantLookupResult, ResolvedAccessContextResult } from "./tenant-admin-guard.ts";

export async function buildTenantAdminGuardDeps(): Promise<TenantAdminGuardDeps> {
  const supabase = await createSupabaseServerClient();
  const serviceRole = createSupabaseServiceRoleClient();

  return {
    async getCurrentUserId() {
      const { data, error } = await supabase.auth.getUser();
      if (error || !data.user) return null;
      return data.user.id;
    },

    async findTenantBySlug(slug: string, authUserId: string): Promise<TenantLookupResult | null> {
      const { data, error } = await supabase.rpc("resolve_tenant_by_slug_for_actor", { p_slug: slug, p_actor_auth_user_id: authUserId });
      if (error || !data) return null;
      const row = (Array.isArray(data) ? data[0] : data) as { id: string; slug: string; canonical_status: string } | undefined;
      if (!row) return null;
      return { id: row.id, slug: row.slug, canonicalStatus: row.canonical_status };
    },

    async resolveAccessContext(authUserId: string, tenantId: string): Promise<ResolvedAccessContextResult | null> {
      const { data, error } = await serviceRole.rpc("resolve_access_context", { p_auth_user_id: authUserId, p_tenant_id: tenantId });
      if (error || !data) return null;
      const row = data as { layer: string; tenant_id: string | null };
      return { layer: row.layer, tenantId: row.tenant_id };
    },
  };
}
