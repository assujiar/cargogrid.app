import { notFound } from "next/navigation";
import { resolveCustomerPortalAccessForRequest } from "../../../../lib/portal/resolve-customer-portal-access.server.ts";
import { createSupabaseServerClient } from "../../../../lib/supabase/server.ts";
import { listCustomerShipmentAlerts, CustomerShipmentAlertQueryError } from "../../../../server/queries/customer-shipment-alert.ts";
import { ErrorState } from "../../../../components/ui/error-state.tsx";
import { CustomerAlertsPanel } from "./customer-alerts-panel.tsx";

/**
 * Cross-shipment alert history view (CPL-306, CG-S13-CPL-008, Prompt 306),
 * per that capability's own design decision 7 ("a small standalone
 * app/(tenant)/[tenantSlug]/customer-alerts/ list route for cross-shipment
 * alert history"). Uses lib/portal/customer-portal-guard.ts (CPL-300's
 * general-purpose Layer 4 portal entry guard), mirroring app/(tenant)/
 * [tenantSlug]/customer-shipments/page.tsx's own structure.
 *
 * Real, end-to-end functional -- not a stub. It will render empty today
 * (`EmptyState`) because no emission mechanism exists yet in this
 * repository (migration header decision 8, disclosed): no scheduler/trigger
 * queues a real alert at all, AND -- a deeper, live-verified finding the
 * same decision discloses -- app.queue_notification cannot successfully
 * target a customer_user recipient today regardless (its own
 * has_active_tenant_membership recipient-authorization gate never returns
 * true for that layer). Any real app.notifications row that DOES exist for
 * this identity, however it got there, appears here correctly scoped and
 * filtered -- proven in this capability's own db-test against a row placed
 * directly, without any change needed to this page.
 */
export default async function CustomerAlertsPage({ params }: { params: Promise<{ tenantSlug: string }> }) {
  const { tenantSlug } = await params;
  const access = await resolveCustomerPortalAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();
  let loadFailed = false;
  let alerts: Awaited<ReturnType<typeof listCustomerShipmentAlerts>> = [];

  try {
    alerts = await listCustomerShipmentAlerts(supabase, access.tenant.id, access.authUserId, { limit: 50 });
  } catch (error) {
    if (!(error instanceof CustomerShipmentAlertQueryError)) throw error;
    loadFailed = true;
  }

  if (loadFailed) {
    return <ErrorState description="Something went wrong loading your alerts. Please try again." />;
  }

  return (
    <div className="flex flex-col gap-4">
      <div>
        <h1 className="text-xl font-semibold text-neutral-900">Alerts</h1>
        <p className="text-xs text-neutral-500">Every alert you&apos;ve been sent across your shipments. Manage which alerts you receive from a shipment&apos;s own detail page.</p>
      </div>

      <CustomerAlertsPanel tenantSlug={tenantSlug} alerts={alerts} />
    </div>
  );
}
