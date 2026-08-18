/**
 * Customer Portal Dashboard read query (CPL-301, CG-S13-CPL-003). A single,
 * thin, typed wrapper around app.get_customer_portal_dashboard_summary
 * (supabase/migrations/
 * 20260801020000_create_customer_portal_dashboard_summary.sql) -- mirrors
 * server/queries/customer-portal-scope.ts's own wrapper shape exactly.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import { parseCustomerPortalDashboardCard, type CustomerPortalDashboardCard } from "../contracts/customer-portal-dashboard/customer-portal-dashboard.ts";

export type CustomerPortalDashboardQueryClient = Pick<SupabaseClient, "rpc">;

export class CustomerPortalDashboardQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "CustomerPortalDashboardQueryError";
  }
}

/**
 * The full 9-card dashboard summary for this identity in this tenant --
 * always the same 9 card_keys, in every response, regardless of scope
 * (deny-by-default resolves to real cards carrying a genuine zero count,
 * never a missing row and never an error). One card's own degraded=true
 * never removes it from the result and never affects any other card
 * (server-side per-card isolation, migration design decision 5).
 */
export async function getCustomerPortalDashboardSummary(client: CustomerPortalDashboardQueryClient, authUserId: string, tenantId: string): Promise<CustomerPortalDashboardCard[]> {
  const { data, error } = await client.rpc("get_customer_portal_dashboard_summary", {
    p_auth_user_id: authUserId,
    p_tenant_id: tenantId,
  });
  if (error) {
    throw new CustomerPortalDashboardQueryError(error.message);
  }
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseCustomerPortalDashboardCard);
}
