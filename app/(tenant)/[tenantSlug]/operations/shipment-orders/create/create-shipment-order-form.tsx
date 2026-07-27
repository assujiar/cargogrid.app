"use client";

import { useActionState } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import type { CreateShipmentOrderState } from "./actions.ts";
import { SHIPMENT_MODES, type ShipmentMode } from "../../../../../../server/contracts/shipment-order/shipment-order.ts";

const INITIAL_STATE: CreateShipmentOrderState = { error: null };

/**
 * The one atomic, idempotent creation action (OPS-169). basisQuantity/basisWeightKg/
 * basisVolumeCbm are only meaningful -- and only shown -- on the first Shipment Order
 * for a Job Order (`isFirstShipment`); a split shipment shows a required reason field
 * instead, matching the split-reason-required rule the database itself enforces.
 */
export function CreateShipmentOrderForm({
  action,
  isFirstShipment,
}: {
  action: (
    serviceType: string,
    mode: ShipmentMode,
    origin: string,
    destination: string,
    plannedPickupAt: string,
    plannedDeliveryAt: string,
    allocatedQuantity: string,
    allocatedWeightKg: string,
    allocatedVolumeCbm: string,
    basisQuantity: string,
    basisWeightKg: string,
    basisVolumeCbm: string,
    splitReason: string,
    prevState: CreateShipmentOrderState,
    formData: FormData,
  ) => Promise<CreateShipmentOrderState>;
  isFirstShipment: boolean;
}) {
  const [state, formAction, pending] = useActionState(
    async (prevState: CreateShipmentOrderState, formData: FormData) => {
      const field = (name: string) => String(formData.get(name) ?? "");
      return action(
        field("serviceType"),
        field("mode") as ShipmentMode,
        field("origin"),
        field("destination"),
        field("plannedPickupAt"),
        field("plannedDeliveryAt"),
        field("allocatedQuantity"),
        field("allocatedWeightKg"),
        field("allocatedVolumeCbm"),
        field("basisQuantity"),
        field("basisWeightKg"),
        field("basisVolumeCbm"),
        field("splitReason"),
        prevState,
        formData,
      );
    },
    INITIAL_STATE,
  );

  return (
    <form action={formAction} className="flex flex-col gap-3" noValidate>
      <div className="grid grid-cols-2 gap-3">
        <div className="flex flex-col gap-1">
          <label htmlFor="serviceType" className="text-sm font-medium text-neutral-700">
            Service type
          </label>
          <input id="serviceType" name="serviceType" type="text" required defaultValue="ocean_freight" className="rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        </div>
        <div className="flex flex-col gap-1">
          <label htmlFor="mode" className="text-sm font-medium text-neutral-700">
            Mode
          </label>
          <select id="mode" name="mode" className="rounded-md border border-neutral-300 px-3 py-2 text-sm" defaultValue={SHIPMENT_MODES[2]}>
            {SHIPMENT_MODES.map((mode) => (
              <option key={mode} value={mode}>
                {mode}
              </option>
            ))}
          </select>
        </div>
        <div className="flex flex-col gap-1">
          <label htmlFor="origin" className="text-sm font-medium text-neutral-700">
            Origin
          </label>
          <input id="origin" name="origin" type="text" required className="rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        </div>
        <div className="flex flex-col gap-1">
          <label htmlFor="destination" className="text-sm font-medium text-neutral-700">
            Destination
          </label>
          <input id="destination" name="destination" type="text" required className="rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        </div>
        <div className="flex flex-col gap-1">
          <label htmlFor="plannedPickupAt" className="text-sm font-medium text-neutral-700">
            Planned pickup
          </label>
          <input id="plannedPickupAt" name="plannedPickupAt" type="datetime-local" className="rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        </div>
        <div className="flex flex-col gap-1">
          <label htmlFor="plannedDeliveryAt" className="text-sm font-medium text-neutral-700">
            Planned delivery
          </label>
          <input id="plannedDeliveryAt" name="plannedDeliveryAt" type="datetime-local" className="rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        </div>
        <div className="flex flex-col gap-1">
          <label htmlFor="allocatedQuantity" className="text-sm font-medium text-neutral-700">
            Allocated quantity
          </label>
          <input id="allocatedQuantity" name="allocatedQuantity" type="number" step="any" className="rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        </div>
        <div className="flex flex-col gap-1">
          <label htmlFor="allocatedWeightKg" className="text-sm font-medium text-neutral-700">
            Allocated weight (kg)
          </label>
          <input id="allocatedWeightKg" name="allocatedWeightKg" type="number" step="any" className="rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        </div>
        <div className="flex flex-col gap-1">
          <label htmlFor="allocatedVolumeCbm" className="text-sm font-medium text-neutral-700">
            Allocated volume (cbm)
          </label>
          <input id="allocatedVolumeCbm" name="allocatedVolumeCbm" type="number" step="any" className="rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        </div>
      </div>

      {isFirstShipment ? (
        <div className="flex flex-col gap-2 rounded-md border border-neutral-200 p-3">
          <p className="text-xs text-neutral-500">
            This is the first Shipment Order for this Job Order -- the totals below declare the Job Order&apos;s own governed allocation basis for every future split. Leave a dimension blank to leave it advisory-only (never enforced).
          </p>
          <div className="grid grid-cols-3 gap-3">
            <div className="flex flex-col gap-1">
              <label htmlFor="basisQuantity" className="text-sm font-medium text-neutral-700">
                Total quantity
              </label>
              <input id="basisQuantity" name="basisQuantity" type="number" step="any" className="rounded-md border border-neutral-300 px-3 py-2 text-sm" />
            </div>
            <div className="flex flex-col gap-1">
              <label htmlFor="basisWeightKg" className="text-sm font-medium text-neutral-700">
                Total weight (kg)
              </label>
              <input id="basisWeightKg" name="basisWeightKg" type="number" step="any" className="rounded-md border border-neutral-300 px-3 py-2 text-sm" />
            </div>
            <div className="flex flex-col gap-1">
              <label htmlFor="basisVolumeCbm" className="text-sm font-medium text-neutral-700">
                Total volume (cbm)
              </label>
              <input id="basisVolumeCbm" name="basisVolumeCbm" type="number" step="any" className="rounded-md border border-neutral-300 px-3 py-2 text-sm" />
            </div>
          </div>
        </div>
      ) : (
        <div className="flex flex-col gap-1">
          <label htmlFor="splitReason" className="text-sm font-medium text-neutral-700">
            Split reason (required)
          </label>
          <input id="splitReason" name="splitReason" type="text" required minLength={1} className="rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        </div>
      )}

      {state.error ? (
        <p role="alert" className="text-sm text-danger">
          {state.error}
        </p>
      ) : null}

      <Button type="submit" loading={pending} loadingLabel="Creating…" className="w-fit">
        Create Shipment Order
      </Button>
    </form>
  );
}
