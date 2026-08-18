import Link from "next/link";
import { StatusBadge } from "../../../../components/ui/status-badge.tsx";
import { EmptyState } from "../../../../components/ui/empty-state.tsx";
import type { Notification } from "../../../../server/contracts/customer-shipment-alert/customer-shipment-alert.ts";

/**
 * Human label per this capability's own 6 registered notification_type_code
 * values (migration header decision 7, `'shipment_alert_' || alert_type`).
 * Any other notification_type_code this identity might otherwise have
 * (there are none today -- this capability's own read RPC already filters
 * to exactly these 6) would fall back to the raw code, never crash.
 */
const ALERT_TYPE_CODE_LABEL: Record<string, string> = {
  shipment_alert_milestone_delay: "Milestone delay",
  shipment_alert_exception: "Exception",
  shipment_alert_no_fresh_position: "Tracking signal lost",
  shipment_alert_tracking_restored: "Tracking restored",
  shipment_alert_delivery: "Delivery",
  shipment_alert_document_available: "Document available",
};

function AlertRow({ tenantSlug, alert }: { tenantSlug: string; alert: Notification }) {
  const isUnread = alert.readAt === null && alert.effectiveChannel === "in_app";
  const shipmentOrderId = typeof alert.context.shipmentOrderId === "string" ? alert.context.shipmentOrderId : null;

  return (
    <li className="flex flex-col gap-1 rounded-md border border-neutral-100 p-3">
      <div className="flex flex-wrap items-center gap-2">
        <StatusBadge tone="neutral" label={ALERT_TYPE_CODE_LABEL[alert.notificationTypeCode] ?? alert.notificationTypeCode} />
        {isUnread ? <StatusBadge tone="info" label="Unread" /> : null}
        <span className="text-xs text-neutral-400">{new Date(alert.createdAt).toLocaleString()}</span>
      </div>
      <p className="text-sm font-medium text-neutral-900">{alert.subject}</p>
      <p className="text-sm text-neutral-700">{alert.body}</p>
      {shipmentOrderId ? (
        <Link href={`/${tenantSlug}/customer-shipments/${shipmentOrderId}`} className="text-xs text-primary underline">
          View shipment
        </Link>
      ) : null}
    </li>
  );
}

export function CustomerAlertsPanel({ tenantSlug, alerts }: { tenantSlug: string; alerts: readonly Notification[] }) {
  return (
    <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
      <h2 className="text-sm font-semibold text-neutral-900">Alert history</h2>
      {alerts.length === 0 ? (
        <EmptyState title="No alerts yet" description="Alerts you're subscribed to will appear here as they happen." />
      ) : (
        <ul className="flex flex-col gap-2">
          {alerts.map((alert) => (
            <AlertRow key={alert.id} tenantSlug={tenantSlug} alert={alert} />
          ))}
        </ul>
      )}
    </section>
  );
}
