"use client";

import { useActionState } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
import { StatusBadge, type StatusTone } from "../../../../../components/ui/status-badge.tsx";
import type { CustomerBookingRequestActionState } from "../actions.ts";
import type { BookingRequestStatus, CustomerBookingRequest } from "../../../../../server/contracts/customer-booking-request/customer-booking-request.ts";

const INITIAL_STATE: CustomerBookingRequestActionState = { error: null };

const STATUS_TONE: Record<BookingRequestStatus, StatusTone> = {
  draft: "neutral",
  submitted: "info",
  reschedule_requested: "warning",
  cancel_requested: "warning",
  cancelled: "neutral",
  converted: "success",
};

const STATUS_LABEL: Record<BookingRequestStatus, string> = {
  draft: "draft",
  submitted: "submitted",
  reschedule_requested: "reschedule requested",
  cancel_requested: "cancellation requested",
  cancelled: "cancelled",
  converted: "converted",
};

type BoundAction = (prevState: CustomerBookingRequestActionState, formData: FormData) => Promise<CustomerBookingRequestActionState>;

function locationText(location: Record<string, unknown>): string {
  const parts = [location.label, location.addressLine, location.city, location.country].filter((v): v is string => typeof v === "string" && v.length > 0);
  const contact = [location.contactName, location.contactPhone].filter((v): v is string => typeof v === "string" && v.length > 0);
  const addressText = parts.length > 0 ? parts.join(", ") : "Not specified";
  return contact.length > 0 ? `${addressText} — ${contact.join(", ")}` : addressText;
}

function toDatetimeLocalValue(iso: string | null): string {
  if (!iso) return "";
  const date = new Date(iso);
  if (Number.isNaN(date.getTime())) return "";
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}`;
}

/** Chronological status timeline built from the row's own real timestamps, never a synthetic event log -- mirrors app/(tenant)/[tenantSlug]/customer-quotes/[requestId]/customer-quote-detail-panel.tsx's own StatusTimeline exactly. */
function StatusTimeline({ detail }: { detail: CustomerBookingRequest }) {
  const steps: { label: string; at: string | null; done: boolean }[] = [
    { label: "Draft created", at: detail.createdAt, done: true },
    { label: "Submitted to Operations", at: detail.submittedAt, done: !!detail.submittedAt },
    { label: "Converted to job/shipment order", at: detail.status === "converted" ? detail.updatedAt : null, done: detail.status === "converted" },
  ];
  if (detail.status === "reschedule_requested") {
    steps.push({ label: "Reschedule requested", at: detail.rescheduleRequestedAt, done: true });
  }
  if (detail.status === "cancel_requested" || detail.status === "cancelled") {
    steps.push({ label: detail.status === "cancelled" ? "Cancelled" : "Cancellation requested", at: detail.cancelledAt, done: true });
  }

  return (
    <ol className="flex flex-col gap-1 text-xs text-neutral-600">
      {steps.map((s) => (
        <li key={s.label} className="flex items-center gap-2">
          <span className={`h-2 w-2 rounded-full ${s.done ? "bg-success" : "bg-neutral-300"}`} aria-hidden="true" />
          <span className={s.done ? "font-medium text-neutral-900" : ""}>{s.label}</span>
          {s.at ? <span className="text-neutral-400">— {new Date(s.at).toLocaleString()}</span> : null}
        </li>
      ))}
    </ol>
  );
}

function EditDraftForm({ detail, updateAction }: { detail: CustomerBookingRequest; updateAction: BoundAction }) {
  const [state, formAction, pending] = useActionState(updateAction, INITIAL_STATE);
  return (
    <form action={formAction} className="grid grid-cols-1 gap-2 rounded-md border border-neutral-200 p-4 sm:grid-cols-2">
      <h2 className="text-sm font-semibold text-neutral-900 sm:col-span-2">Edit draft</h2>
      <label className="text-xs text-neutral-500 sm:col-span-2">
        Cargo description
        <textarea name="cargoDescription" defaultValue={detail.cargoDescription ?? ""} rows={2} className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" />
      </label>
      <label className="text-xs text-neutral-500">
        Pickup label / address
        <input name="pickupLabel" defaultValue={typeof detail.pickup.label === "string" ? detail.pickup.label : ""} className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" />
      </label>
      <label className="text-xs text-neutral-500">
        Delivery label / address
        <input name="deliveryLabel" defaultValue={typeof detail.delivery.label === "string" ? detail.delivery.label : ""} className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" />
      </label>
      <label className="text-xs text-neutral-500">
        Requested pickup date/time
        <input type="datetime-local" name="requestedPickupAt" defaultValue={toDatetimeLocalValue(detail.requestedPickupAt)} className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" />
      </label>
      <label className="text-xs text-neutral-500">
        Requested delivery date/time
        <input type="datetime-local" name="requestedDeliveryAt" defaultValue={toDatetimeLocalValue(detail.requestedDeliveryAt)} className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" />
      </label>
      <label className="text-xs text-neutral-500 sm:col-span-2">
        Special instructions
        <textarea name="specialInstructions" defaultValue={detail.specialInstructions ?? ""} rows={2} className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" />
      </label>
      <div className="sm:col-span-2">
        <Button type="submit" variant="secondary" loading={pending} loadingLabel="Saving…">
          Save changes
        </Button>
      </div>
      {state.error ? (
        <p role="alert" className="text-xs text-danger sm:col-span-2">
          {state.error}
        </p>
      ) : null}
    </form>
  );
}

function SubmitForm({ submitAction }: { submitAction: BoundAction }) {
  const [state, formAction, pending] = useActionState(submitAction, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col gap-2">
      <Button type="submit" variant="primary" loading={pending} loadingLabel="Submitting…">
        Submit to Operations
      </Button>
      {state.error ? (
        <p role="alert" className="text-xs text-danger">
          {state.error}
        </p>
      ) : null}
    </form>
  );
}

function RescheduleForm({ rescheduleAction }: { rescheduleAction: BoundAction }) {
  const [state, formAction, pending] = useActionState(rescheduleAction, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
      <h2 className="text-sm font-semibold text-neutral-900">Request a reschedule</h2>
      <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">
        <label className="text-xs text-neutral-500">
          New requested pickup date/time
          <input type="datetime-local" name="requestedPickupAt" className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" />
        </label>
        <label className="text-xs text-neutral-500">
          New requested delivery date/time
          <input type="datetime-local" name="requestedDeliveryAt" className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" />
        </label>
      </div>
      <label className="text-xs text-neutral-500">
        Reason (required)
        <input name="reason" required placeholder="Why do you need to reschedule?" className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" />
      </label>
      <div>
        <Button type="submit" variant="secondary" loading={pending} loadingLabel="Requesting…">
          Request reschedule
        </Button>
      </div>
      <p className="text-xs text-neutral-500">This is a request only -- Operations reviews and confirms any schedule change; your current requested dates are not changed automatically.</p>
      {state.error ? (
        <p role="alert" className="text-xs text-danger">
          {state.error}
        </p>
      ) : null}
    </form>
  );
}

function CancelForm({ cancelAction, requiresOperationsReview }: { cancelAction: BoundAction; requiresOperationsReview: boolean }) {
  const [state, formAction, pending] = useActionState(cancelAction, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-wrap items-center gap-2">
      <input name="reason" required placeholder="Cancellation reason (required)" className="min-w-[12rem] flex-1 rounded border border-neutral-300 p-1.5 text-xs" />
      <Button type="submit" variant="destructive" loading={pending} loadingLabel="Cancelling…">
        {requiresOperationsReview ? "Request cancellation" : "Cancel booking"}
      </Button>
      {state.error ? (
        <p role="alert" className="w-full text-xs text-danger">
          {state.error}
        </p>
      ) : null}
    </form>
  );
}

export function CustomerBookingDetailPanel({
  detail,
  updateAction,
  submitAction,
  rescheduleAction,
  cancelAction,
}: {
  detail: CustomerBookingRequest;
  updateAction: BoundAction;
  submitAction: BoundAction;
  rescheduleAction: BoundAction;
  cancelAction: BoundAction;
}) {
  const isDraft = detail.status === "draft";
  const isReschedulable = detail.status === "submitted" || detail.status === "converted";
  const isCancellable = detail.status === "draft" || detail.status === "submitted" || detail.status === "converted";

  return (
    <div className="flex flex-col gap-4">
      <header className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
        <div className="flex flex-wrap items-center gap-2">
          <h1 className="text-lg font-semibold text-neutral-900">{detail.cargoDescription || "Untitled booking"}</h1>
          <StatusBadge tone={STATUS_TONE[detail.status]} label={STATUS_LABEL[detail.status]} />
        </div>
        <dl className="grid grid-cols-2 gap-2 text-xs text-neutral-500 sm:grid-cols-4">
          <div>
            <dt className="font-medium">Pickup</dt>
            <dd>{locationText(detail.pickup)}</dd>
          </div>
          <div>
            <dt className="font-medium">Delivery</dt>
            <dd>{locationText(detail.delivery)}</dd>
          </div>
          <div>
            <dt className="font-medium">Requested pickup</dt>
            <dd>{detail.requestedPickupAt ? new Date(detail.requestedPickupAt).toLocaleString() : "—"}</dd>
          </div>
          <div>
            <dt className="font-medium">Requested delivery</dt>
            <dd>{detail.requestedDeliveryAt ? new Date(detail.requestedDeliveryAt).toLocaleString() : "—"}</dd>
          </div>
        </dl>
        {detail.specialInstructions ? (
          <p className="text-xs text-neutral-500">
            <span className="font-medium">Instructions: </span>
            {detail.specialInstructions}
          </p>
        ) : null}
        {detail.status === "converted" ? (
          <p className="rounded bg-success/10 p-2 text-sm text-neutral-800">
            This booking has been confirmed as an operational shipment by Operations. Job order and shipment order references are attached to your account -- your account team can share tracking details
            separately.
          </p>
        ) : null}
        {detail.status === "reschedule_requested" ? (
          <p className="rounded bg-warning/10 p-2 text-sm text-neutral-800">
            <span className="font-medium">Reschedule requested: </span>
            {detail.rescheduleReason}
            {detail.rescheduleRequestedPickupAt ? ` — new pickup: ${new Date(detail.rescheduleRequestedPickupAt).toLocaleString()}` : ""}
            {detail.rescheduleRequestedDeliveryAt ? ` — new delivery: ${new Date(detail.rescheduleRequestedDeliveryAt).toLocaleString()}` : ""} Operations will confirm this change.
          </p>
        ) : null}
        {(detail.status === "cancel_requested" || detail.status === "cancelled") && detail.cancelledReason ? (
          <p className="rounded bg-neutral-100 p-2 text-sm text-neutral-800">
            <span className="font-medium">{detail.status === "cancelled" ? "Cancelled: " : "Cancellation requested: "}</span>
            {detail.cancelledReason}
          </p>
        ) : null}
        <StatusTimeline detail={detail} />
        <div className="flex flex-wrap gap-2">
          {isDraft ? <SubmitForm submitAction={submitAction} /> : null}
          {isCancellable ? <CancelForm cancelAction={cancelAction} requiresOperationsReview={detail.status === "converted"} /> : null}
        </div>
      </header>

      {isDraft ? <EditDraftForm detail={detail} updateAction={updateAction} /> : null}
      {isReschedulable ? <RescheduleForm rescheduleAction={rescheduleAction} /> : null}
    </div>
  );
}
