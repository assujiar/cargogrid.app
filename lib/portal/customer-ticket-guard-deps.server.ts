/**
 * Real `CustomerTicketGuardDeps` wiring (HRT-287, CG-S12-HRT-015). Uses the
 * RLS-scoped `authenticated` client only -- `app.actor_holds_customer_user_
 * layer` is granted to `authenticated` directly (ATW-023 hardening,
 * 20260730311000), so no service-role client is needed here, unlike
 * `tenant-admin-guard-deps.server.ts`'s own `resolve_access_context` call.
 */

import { createSupabaseServerClient } from "../supabase/server.ts";
import type { CustomerTicketGuardDeps, TenantLookupResult } from "./customer-ticket-guard.ts";

export async function buildCustomerTicketGuardDeps(): Promise<CustomerTicketGuardDeps> {
  const supabase = await createSupabaseServerClient();

  return {
    async getCurrentUserId() {
      const { data, error } = await supabase.auth.getUser();
      if (error || !data.user) return null;
      return data.user.id;
    },

    async findTenantBySlug(slug: string): Promise<TenantLookupResult | null> {
      const { data, error } = await supabase.from("tenants").select("id, slug, canonical_status").eq("slug", slug).maybeSingle();
      if (error || !data) return null;
      return { id: data.id as string, slug: data.slug as string, canonicalStatus: data.canonical_status as string };
    },

    async actorHoldsCustomerUserLayer(tenantId: string, authUserId: string): Promise<boolean> {
      const { data, error } = await supabase.rpc("actor_holds_customer_user_layer", { p_tenant_id: tenantId, p_auth_user_id: authUserId });
      if (error) return false;
      return data === true;
    },
  };
}
