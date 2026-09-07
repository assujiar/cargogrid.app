/**
 * Real `CustomerPortalGuardDeps` wiring (CPL-300, CG-S13-CPL-002). Mirrors
 * lib/portal/customer-ticket-guard-deps.server.ts's own wiring exactly -- uses
 * the RLS-scoped `authenticated` client only. `app.actor_holds_customer_user_
 * layer` is granted to `authenticated` directly (ATW-023 hardening,
 * 20260730311000), so no service-role client is needed here.
 *
 * `findTenantBySlug` resolves via the `public.resolve_tenant_by_slug_for_member` RPC
 * (CG-AUDIT-2026-09-02 Ø1+Ø2): schema `app` is not exposed to PostgREST so a
 * `.from("tenants")` query can never resolve (Ø1), and `app.tenants`' own RLS policy
 * excludes every `customer_user` -- the population this guard exists to admit -- by
 * construction (Ø2), so `resolve_tenant_by_slug_for_actor` (tenant-admin-only) cannot be
 * reused here either.
 */

import { createSupabaseServerClient } from "../supabase/server.ts";
import type { CustomerPortalGuardDeps, TenantLookupResult } from "./customer-portal-guard.ts";

export async function buildCustomerPortalGuardDeps(): Promise<CustomerPortalGuardDeps> {
  const supabase = await createSupabaseServerClient();

  return {
    async getCurrentUserId() {
      const { data, error } = await supabase.auth.getUser();
      if (error || !data.user) return null;
      return data.user.id;
    },

    async findTenantBySlug(slug: string, authUserId: string): Promise<TenantLookupResult | null> {
      const { data, error } = await supabase.rpc("resolve_tenant_by_slug_for_member", { p_slug: slug, p_actor_auth_user_id: authUserId });
      if (error || !data) return null;
      const row = (Array.isArray(data) ? data[0] : data) as { id: string; slug: string; canonical_status: string } | undefined;
      if (!row) return null;
      return { id: row.id, slug: row.slug, canonicalStatus: row.canonical_status };
    },

    async actorHoldsCustomerUserLayer(tenantId: string, authUserId: string): Promise<boolean> {
      const { data, error } = await supabase.rpc("actor_holds_customer_user_layer", { p_tenant_id: tenantId, p_auth_user_id: authUserId });
      if (error) return false;
      return data === true;
    },
  };
}
