"use client";

/**
 * Shipment alert subscription ("notify me") sub-section (CPL-306,
 * CG-S13-CPL-008, Prompt 306). Extends the existing customer-shipments/
 * [shipmentOrderId] detail page (CPL-304/305), per the orchestrating task's
 * own design decision 7, rather than a new sibling route.
 *
 * Each of the 6 alert types is its own tiny form, mirroring
 * customer-shipment-detail-panel.tsx's RequestChangeForm shape -- one
 * useActionState per row, bound to either the subscribe or unsubscribe
 * Server Action depending on the row's own CURRENT status (an alert type
 * with no subscription row at all renders identically to an explicit
 * status='unsubscribed' row -- "not subscribed").
 *
 * Business rule (source prompt §24): "Subscription grants no shipment
 * access." This panel only ever toggles a preference row -- it never
 * affects what shipment/tracking data this identity can see, which is
 * always independently scope-checked by its own RPC (CPL-304/305).
 */

import { useActionState, useId } from "react";
import { StatusBadge } from "../../../../../components/ui/status-badge.tsx";
import { Switch } from "../../../../../components/forms/switch.tsx";
import { ValidationMessage } from "../../../../../components/forms/validation-message.tsx";
import type { CustomerShipmentOrderActionState } from "../actions.ts";
import type { CustomerShipmentAlertSubscription, CustomerShipmentAlertType } from "../../../../../server/contracts/customer-shipment-alert/customer-shipment-alert.ts";

const INITIAL_STATE: CustomerShipmentOrderActionState = { error: null };

const ALERT_TYPE_INFO: Record<CustomerShipmentAlertType, { label: string; description: string }> = {
  milestone_delay: { label: "Milestone delay", description: "A tracked milestone is running behind schedule." },
  exception: { label: "Exception", description: "An operational exception is reported for this shipment." },
  no_fresh_position: { label: "Tracking signal lost", description: "Live tracking hasn't received a fresh position recently." },
  tracking_restored: { label: "Tracking restored", description: "Live tracking has resumed after being degraded." },
  delivery: { label: "Delivery", description: "This shipment has been delivered." },
  document_available: { label: "Document available", description: "A new document (e.g. proof of delivery) is available." },
};

const ALERT_TYPES: readonly CustomerShipmentAlertType[] = ["milestone_delay", "exception", "no_fresh_position", "tracking_restored", "delivery", "document_available"];

type AlertAction = (prevState: CustomerShipmentOrderActionState, formData: FormData) => Promise<CustomerShipmentOrderActionState>;

/**
 * `ISS-2026-246`: the control here is a per-alert preference that acts the moment it is
 * flipped -- there is no Save step and nothing else in the form to submit. That is the
 * exact case `switch.tsx`'s own header reserves for `Switch` ("an immediate-effect
 * boolean toggle, distinct from Checkbox's form-submit-pending boolean"), and it was
 * hand-rolled here as a "Turn on"/"Turn off" `Button`. Nothing is dropped: the row still
 * posts through the same bound Server Action (the switch submits its own form on
 * change), the On/Off `StatusBadge` still reports the server's own state, and the
 * button's pending text survives as the pending note beside the switch. It also fixes a
 * real defect the buttons had -- six controls on one page whose entire accessible name
 * was "Turn on", with nothing saying which alert they belonged to.
 */
function AlertTypeRow({ alertType, isActive, subscribeAction, unsubscribeAction }: { alertType: CustomerShipmentAlertType; isActive: boolean; subscribeAction: AlertAction; unsubscribeAction: AlertAction }) {
  const [state, formAction, pending] = useActionState(isActive ? unsubscribeAction : subscribeAction, INITIAL_STATE);
  const info = ALERT_TYPE_INFO[alertType];
  const switchId = useId();
  // While the action is in flight the switch shows where it is going, not where it came
  // from -- a checkbox pinned to the server value would visibly snap back under the
  // user's finger. The badge stays on the server's own answer, so the two together read
  // as "asked for on, still off" until the revalidation lands (or the error below does).
  const shown = pending ? !isActive : isActive;

  return (
    <li className="flex flex-col gap-1 rounded-md border border-neutral-100 p-3">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <div>
          <p className="text-sm font-medium text-neutral-900">{info.label}</p>
          <p className="text-xs text-neutral-500">{info.description}</p>
        </div>
        <form action={formAction} className="flex items-center gap-2">
          <StatusBadge tone={isActive ? "success" : "neutral"} label={isActive ? "On" : "Off"} />
          {pending ? <span className="text-xs text-neutral-500">{isActive ? "Turning off…" : "Turning on…"}</span> : null}
          <Switch
            id={switchId}
            checked={shown}
            disabled={pending}
            aria-busy={pending || undefined}
            onChange={(event) => event.currentTarget.form?.requestSubmit()}
            label={<span className="sr-only">{`Notify me: ${info.label}`}</span>}
          />
        </form>
      </div>
      {state.error ? <ValidationMessage>{state.error}</ValidationMessage> : null}
    </li>
  );
}

export function CustomerShipmentAlertSubscriptionsPanel({
  subscriptions,
  subscribeActions,
  unsubscribeActions,
}: {
  subscriptions: readonly CustomerShipmentAlertSubscription[];
  /** One pre-bound Server Action per alert type, built in the Server Component via .bind() -- see page.tsx. A plain closure factory could not cross the server/client boundary as a prop, only an already-bound Server Action reference can (mirrors requestCustomerShipmentOrderChangeAction.bind(...) at CPL-304). */
  subscribeActions: Record<CustomerShipmentAlertType, AlertAction>;
  unsubscribeActions: Record<CustomerShipmentAlertType, AlertAction>;
}) {
  const statusByType = new Map(subscriptions.map((s) => [s.alertType, s.status]));

  return (
    <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
      <div>
        <h2 className="text-sm font-semibold text-neutral-900">Notify me</h2>
        <p className="text-xs text-neutral-500">Choose which updates you want for this shipment. Turning an alert on doesn&apos;t change what you can see -- it only controls whether we notify you.</p>
      </div>
      <ul className="flex flex-col gap-2">
        {ALERT_TYPES.map((alertType) => (
          <AlertTypeRow key={alertType} alertType={alertType} isActive={statusByType.get(alertType) === "active"} subscribeAction={subscribeActions[alertType]} unsubscribeAction={unsubscribeActions[alertType]} />
        ))}
      </ul>
    </section>
  );
}
