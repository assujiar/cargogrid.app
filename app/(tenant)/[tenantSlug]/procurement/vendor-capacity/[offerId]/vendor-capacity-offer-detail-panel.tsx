"use client";

import { useActionState, useId } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import { Input } from "../../../../../../components/forms/input.tsx";
import { FormField } from "../../../../../../components/forms/form-field.tsx";
import { ValidationMessage } from "../../../../../../components/forms/validation-message.tsx";
import { StatusBadge, type StatusTone } from "../../../../../../components/ui/status-badge.tsx";
import { DataTable, type DataTableColumn } from "../../../../../../components/tables/data-table.tsx";
import type { VendorCapacityOffer, VendorCapacityBlackout, VendorCapacityReservation, VendorCapacityOfferStatus, VendorCapacityReservationStatus } from "../../../../../../server/contracts/vendor-capacity/vendor-capacity.ts";
import type { VendorCapacityActionState } from "../actions.ts";

const INITIAL_STATE: VendorCapacityActionState = { error: null };

const OFFER_STATUS_TONE: Record<VendorCapacityOfferStatus, StatusTone> = {
  draft: "neutral",
  published: "success",
  archived: "neutral",
};

const RESERVATION_STATUS_TONE: Record<VendorCapacityReservationStatus, StatusTone> = {
  held: "info",
  accepted: "success",
  declined: "danger",
  consumed: "success",
  released: "neutral",
};

type SimpleFormAction = (prevState: VendorCapacityActionState, formData: FormData) => Promise<VendorCapacityActionState>;

function ActionForm({
  action,
  children,
  submitLabel,
  loadingLabel,
  variant = "primary",
}: {
  action: SimpleFormAction;
  children?: (describedBy: string | undefined) => React.ReactNode;
  submitLabel: string;
  loadingLabel?: string;
  variant?: "primary" | "secondary" | "destructive";
}) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  const reactId = useId();
  const errorId = `${reactId}-error`;
  const describedBy = state.error ? errorId : undefined;
  return (
    <form action={formAction} className="flex flex-col gap-2">
      {children?.(describedBy)}
      {state.error ? <ValidationMessage id={errorId}>{state.error}</ValidationMessage> : null}
      <Button type="submit" variant={variant} loading={pending} loadingLabel={loadingLabel ?? "Working…"} className="w-fit">
        {submitLabel}
      </Button>
    </form>
  );
}

function NoArgActionButton({ action, label, loadingLabel, variant = "secondary" }: { action: SimpleFormAction; label: string; loadingLabel?: string; variant?: "primary" | "secondary" | "destructive" }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col gap-1">
      <Button type="submit" variant={variant} loading={pending} loadingLabel={loadingLabel ?? "Working…"}>
        {label}
      </Button>
      {state.error ? <ValidationMessage>{state.error}</ValidationMessage> : null}
    </form>
  );
}

function ConstraintRow({ label, value }: { label: string; value: string | null }) {
  return (
    <div className="flex flex-col gap-0.5">
      <dt className="text-xs font-medium text-neutral-500">{label}</dt>
      <dd className="text-sm text-neutral-900">{value ?? "—"}</dd>
    </div>
  );
}

export function VendorCapacityOfferDetailPanel({
  offer,
  blackouts,
  reservations,
  availableNow,
  updateAction,
  publishAction,
  archiveAction,
  addBlackoutAction,
  removeBlackoutAction,
  reserveAction,
  acceptReservationAction,
  declineReservationAction,
  releaseReservationAction,
  consumeReservationAction,
}: {
  offer: VendorCapacityOffer;
  blackouts: readonly VendorCapacityBlackout[];
  reservations: readonly VendorCapacityReservation[];
  availableNow: number | null;
  updateAction: SimpleFormAction;
  publishAction: SimpleFormAction;
  archiveAction: SimpleFormAction;
  addBlackoutAction: SimpleFormAction;
  removeBlackoutAction: (blackoutId: string, expectedVersion: number) => SimpleFormAction;
  reserveAction: SimpleFormAction;
  acceptReservationAction: (reservationId: string, expectedVersion: number) => SimpleFormAction;
  declineReservationAction: (reservationId: string, expectedVersion: number) => SimpleFormAction;
  releaseReservationAction: (reservationId: string, expectedVersion: number) => SimpleFormAction;
  consumeReservationAction: (reservationId: string, expectedVersion: number) => SimpleFormAction;
}) {
  const canUpdate = offer.status === "draft";
  const canPublish = offer.status === "draft";
  const canArchive = offer.status === "draft" || offer.status === "published";
  const canReserve = offer.status === "published";

  const blackoutColumns: readonly DataTableColumn<VendorCapacityBlackout>[] = [
    { key: "window", header: "Window", render: (row) => `${new Date(row.windowStart).toLocaleDateString()} → ${new Date(row.windowEnd).toLocaleDateString()}` },
    { key: "reason", header: "Reason", render: (row) => row.reason },
    { key: "remove", header: "", render: (row) => <NoArgActionButton action={removeBlackoutAction(row.id, row.recordVersion)} label="Remove" variant="destructive" loadingLabel="Removing…" /> },
  ];

  return (
    <div className="flex flex-col gap-6">
      <div>
        <h1 className="text-xl font-semibold text-neutral-900">
          {offer.serviceType} {offer.mode ? <span className="text-sm font-normal text-neutral-500">({offer.mode})</span> : null}
        </h1>
        <div className="mt-1 flex flex-wrap gap-2">
          <StatusBadge tone={OFFER_STATUS_TONE[offer.status]} label={offer.status} />
        </div>
      </div>

      <section className="rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Declaration</h2>
        <dl className="mt-2 grid grid-cols-1 gap-3 text-sm sm:grid-cols-3">
          <ConstraintRow label="Vendor" value={offer.vendorMasterId} />
          <ConstraintRow label="Lane" value={`${offer.originLane ?? "—"} → ${offer.destinationLane ?? "—"}`} />
          <ConstraintRow label="Resource type" value={offer.resourceType} />
          <ConstraintRow label="Quantity" value={`${offer.quantity.toLocaleString()} ${offer.uom}`} />
          <ConstraintRow label="Available now (full window)" value={availableNow !== null ? `${availableNow.toLocaleString()} ${offer.uom}` : "—"} />
          <ConstraintRow label="Window" value={`${new Date(offer.windowStart).toLocaleDateString()} → ${new Date(offer.windowEnd).toLocaleDateString()}`} />
          <ConstraintRow label="Governing contract" value={offer.contractId} />
        </dl>
      </section>

      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Actions</h2>

        {canUpdate ? (
          <ActionForm action={updateAction} submitLabel="Save draft terms" loadingLabel="Saving…" variant="secondary">
            {(describedBy) => (
              <>
                <FormField id="update-quantity" label="Quantity (required)">
                  <Input id="update-quantity" name="quantity" type="number" min={0.001} step="any" defaultValue={offer.quantity} required aria-describedby={describedBy} />
                </FormField>
                <FormField id="update-uom" label="UOM (required)">
                  <Input id="update-uom" name="uom" type="text" defaultValue={offer.uom} required aria-describedby={describedBy} />
                </FormField>
                <FormField id="update-windowStart" label="Window start (required)">
                  <Input id="update-windowStart" name="windowStart" type="date" defaultValue={offer.windowStart.slice(0, 10)} required aria-describedby={describedBy} />
                </FormField>
                <FormField id="update-windowEnd" label="Window end (required)">
                  <Input id="update-windowEnd" name="windowEnd" type="date" defaultValue={offer.windowEnd.slice(0, 10)} required aria-describedby={describedBy} />
                </FormField>
              </>
            )}
          </ActionForm>
        ) : null}

        {canPublish ? <ActionForm action={publishAction} submitLabel="Publish" loadingLabel="Publishing…" /> : null}
        {canArchive ? <ActionForm action={archiveAction} submitLabel="Archive" loadingLabel="Archiving…" variant="destructive" /> : null}

        {!canUpdate && !canPublish && !canArchive ? <p className="text-xs text-neutral-500">No action is currently available for this offer in its {offer.status} state.</p> : null}
      </section>

      <section className="rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Blackout windows</h2>
        <div className="mt-2">
          <DataTable caption="Blackout windows" columns={blackoutColumns} rows={blackouts} rowKey={(row) => row.id} emptyMessage="No blackout windows declared." />
        </div>
        <div className="mt-3">
          <ActionForm action={addBlackoutAction} submitLabel="Add blackout" loadingLabel="Adding…" variant="secondary">
            {(describedBy) => (
              <>
                <div className="grid grid-cols-2 gap-2">
                  <FormField id="blackout-windowStart" label="Start (required)">
                    <Input id="blackout-windowStart" name="windowStart" type="date" required aria-describedby={describedBy} />
                  </FormField>
                  <FormField id="blackout-windowEnd" label="End (required)">
                    <Input id="blackout-windowEnd" name="windowEnd" type="date" required aria-describedby={describedBy} />
                  </FormField>
                </div>
                <FormField id="blackout-reason" label="Reason (required)">
                  <Input id="blackout-reason" name="reason" type="text" required aria-describedby={describedBy} />
                </FormField>
              </>
            )}
          </ActionForm>
        </div>
      </section>

      <section className="rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Reservations</h2>
        {canReserve ? (
          <div className="mb-3">
            <ActionForm action={reserveAction} submitLabel="Reserve" loadingLabel="Reserving…" variant="secondary">
              {(describedBy) => (
                <div className="grid grid-cols-3 gap-2">
                  <FormField id="reserve-requestedQuantity" label="Quantity (required)">
                    <Input id="reserve-requestedQuantity" name="requestedQuantity" type="number" min={0.001} step="any" required aria-describedby={describedBy} />
                  </FormField>
                  <FormField id="reserve-windowStart" label="Start (required)">
                    <Input id="reserve-windowStart" name="windowStart" type="date" required aria-describedby={describedBy} />
                  </FormField>
                  <FormField id="reserve-windowEnd" label="End (required)">
                    <Input id="reserve-windowEnd" name="windowEnd" type="date" required aria-describedby={describedBy} />
                  </FormField>
                </div>
              )}
            </ActionForm>
          </div>
        ) : null}

        {reservations.length === 0 ? (
          <p className="text-xs text-neutral-500">No reservations against this offer yet.</p>
        ) : (
          <div className="flex flex-col gap-3">
            {reservations.map((r) => (
              <div key={r.id} className="rounded-md border border-neutral-200 p-3">
                <div className="flex flex-wrap items-center gap-2">
                  <StatusBadge tone={RESERVATION_STATUS_TONE[r.status]} label={r.status} />
                  <span className="text-sm text-neutral-900">
                    {r.requestedQuantity.toLocaleString()} {offer.uom}
                  </span>
                  <span className="text-xs text-neutral-500">
                    {new Date(r.windowStart).toLocaleDateString()} → {new Date(r.windowEnd).toLocaleDateString()}
                  </span>
                </div>
                {r.declineReason ? <p className="mt-1 text-xs text-neutral-500">Declined: {r.declineReason}</p> : null}
                {r.releasedReason ? <p className="mt-1 text-xs text-neutral-500">Released: {r.releasedReason}</p> : null}
                <div className="mt-2 flex flex-wrap gap-2">
                  {r.status === "held" ? (
                    <>
                      <NoArgActionButton action={acceptReservationAction(r.id, r.recordVersion)} label="Accept" loadingLabel="Accepting…" variant="primary" />
                      <ActionForm action={declineReservationAction(r.id, r.recordVersion)} submitLabel="Decline" loadingLabel="Declining…" variant="destructive">
                        {(describedBy) => (
                          <>
                            <label htmlFor={`decline-reservation-${r.id}`} className="sr-only">
                              Reason
                            </label>
                            <Input id={`decline-reservation-${r.id}`} name="reason" type="text" placeholder="Reason (required)" required aria-describedby={describedBy} />
                          </>
                        )}
                      </ActionForm>
                    </>
                  ) : null}
                  {r.status === "accepted" ? (
                    <>
                      <NoArgActionButton action={consumeReservationAction(r.id, r.recordVersion)} label="Mark consumed" loadingLabel="Marking…" variant="primary" />
                      <ActionForm action={releaseReservationAction(r.id, r.recordVersion)} submitLabel="Release" loadingLabel="Releasing…" variant="destructive">
                        {(describedBy) => (
                          <>
                            <label htmlFor={`release-reservation-${r.id}`} className="sr-only">
                              Reason
                            </label>
                            <Input id={`release-reservation-${r.id}`} name="reason" type="text" placeholder="Reason (required)" required aria-describedby={describedBy} />
                          </>
                        )}
                      </ActionForm>
                    </>
                  ) : null}
                </div>
              </div>
            ))}
          </div>
        )}
      </section>
    </div>
  );
}
