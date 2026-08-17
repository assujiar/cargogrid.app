import { redirect } from "next/navigation";
import { resolveCustomerPortalAccessForRequest } from "../../../../lib/portal/resolve-customer-portal-access.server.ts";
import { createSupabaseServerClient } from "../../../../lib/supabase/server.ts";
import { getCustomerPortalScopeContext, CustomerPortalScopeQueryError } from "../../../../server/queries/customer-portal-scope.ts";
import {
  listCustomerPortalInventoryBalances,
  listCustomerPortalWarehouseEligibility,
  CustomerPortalInventoryQueryError,
} from "../../../../server/queries/customer-portal-inventory.ts";
import { PermissionState } from "../../../../components/ui/permission-state.tsx";
import { ErrorState } from "../../../../components/ui/error-state.tsx";
import { CustomerPortalNav } from "../../../../components/domain/customer-portal-nav.tsx";
import { CustomerInventoryPanel } from "./customer-inventory-panel.tsx";

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * Warehouse Inventory Visibility (CPL-309, CG-S13-CPL-011, Prompt 309). Read
 * projection over WMS-owned app.inventory_balances -- Business rule 1 ("WMS
 * remains inventory truth; portal shows projections only"), so there is no
 * create/edit/count/move action on this page; a customer cannot adjust stock
 * from the portal (Business rule 2).
 *
 * Uses lib/portal/customer-portal-guard.ts (CPL-300's general-purpose Layer 4
 * portal entry guard) with the SAME denied/redirect shape app/(tenant)/
 * [tenantSlug]/customer-portal/page.tsx already established -- this route
 * carries `CustomerPortalNav` (CPL-301's own shared shell), unlike the later
 * standalone route families (customer-shipments/customer-documents/etc.),
 * because it is a natural sibling of the account-access/dashboard screens
 * `CustomerPortalNav` already links between.
 *
 * The RPCs this page calls (app.list_customer_portal_inventory_balances/
 * app.list_customer_portal_warehouse_eligibility) resolve scope via
 * app.resolve_customer_account_scope (CPL-300's widened resolver) rather than
 * ATW-023's own app.list_customer_inventory_balances -- the ISS-2026-117 fix:
 * an account granted only through CPL-300's new multi-account grant table is
 * visible here.
 */
export default async function CustomerInventoryPage({
  params,
  searchParams,
}: {
  params: Promise<{ tenantSlug: string }>;
  searchParams: Promise<{ warehouseId?: string }>;
}) {
  const { tenantSlug } = await params;
  const { warehouseId: rawWarehouseId } = await searchParams;
  const access = await resolveCustomerPortalAccessForRequest(tenantSlug);

  if (access.status === "unauthenticated") {
    redirect(`/login`);
  }

  if (access.status !== "allowed") {
    return (
      <PermissionState
        description={
          access.status === "tenant_suspended"
            ? "This organization's customer portal is currently unavailable."
            : "You don't have access to this organization's warehouse inventory. Contact your account administrator if you believe this is a mistake."
        }
      />
    );
  }

  // A forged/malformed warehouseId is silently ignored (never surfaced as an
  // error) -- the RPC itself is deny-by-default and would return zero rows
  // for an out-of-scope or nonexistent warehouse regardless; this check only
  // avoids sending an obviously non-uuid value to the RPC at all.
  const warehouseId = rawWarehouseId && UUID_RE.test(rawWarehouseId) ? rawWarehouseId : null;

  const supabase = await createSupabaseServerClient();
  const generatedAt = new Date().toISOString();
  let loadFailed = false;
  let accounts: Awaited<ReturnType<typeof getCustomerPortalScopeContext>> = [];
  let eligibility: Awaited<ReturnType<typeof listCustomerPortalWarehouseEligibility>> = [];
  let balances: Awaited<ReturnType<typeof listCustomerPortalInventoryBalances>> = [];

  try {
    [accounts, eligibility, balances] = await Promise.all([
      getCustomerPortalScopeContext(supabase, access.authUserId, access.tenant.id),
      listCustomerPortalWarehouseEligibility(supabase, access.tenant.id, access.authUserId),
      listCustomerPortalInventoryBalances(supabase, access.tenant.id, access.authUserId, { warehouseId, limit: 50 }),
    ]);
  } catch (error) {
    if (!(error instanceof CustomerPortalScopeQueryError) && !(error instanceof CustomerPortalInventoryQueryError)) throw error;
    loadFailed = true;
  }

  if (loadFailed) {
    return (
      <div className="flex flex-col gap-4">
        <CustomerPortalNav tenantSlug={tenantSlug} current="inventory" />
        <ErrorState description="Something went wrong loading your warehouse inventory. Please try again." />
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-4">
      <CustomerPortalNav tenantSlug={tenantSlug} current="inventory" />

      <div>
        <h1 className="text-xl font-semibold text-neutral-900">Warehouse inventory</h1>
        <p className="text-xs text-neutral-500">
          Stock WMS reports for your own accounts, in warehouses you&apos;re eligible to view. This is a read-only projection -- WMS remains the source of truth; you cannot adjust stock, count, or move
          inventory from here.
        </p>
      </div>

      <CustomerInventoryPanel tenantSlug={tenantSlug} accounts={accounts} eligibility={eligibility} balances={balances} warehouseId={warehouseId ?? ""} generatedAt={generatedAt} />
    </div>
  );
}
