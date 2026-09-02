"use client";

import { useActionState, useId } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import { FormField } from "../../../../../../components/forms/form-field.tsx";
import { Input } from "../../../../../../components/forms/input.tsx";
import { NumberInput } from "../../../../../../components/forms/number-input.tsx";
import { Select } from "../../../../../../components/forms/select.tsx";
import { ValidationMessage } from "../../../../../../components/forms/validation-message.tsx";
import { StatusBadge } from "../../../../../../components/ui/status-badge.tsx";
import type { ShipmentOrderFormState } from "./actions.ts";
import {
  SHIPMENT_LEG_MODES,
  SHIPMENT_LEG_STOP_TYPES,
  SHIPMENT_LEG_CUSTODY_EVENT_TYPES,
  type ShipmentLeg,
  type ShipmentLegStop,
  type ShipmentLegCargoAllocation,
  type ShipmentLegCustodyEvent,
  type LegNetworkStatus,
  type LegNetworkAggregateState,
} from "../../../../../../server/contracts/multi-leg-shipment/multi-leg-shipment.ts";
import { MileTrackingPanel, type MileTrackingFormAction } from "./mile-tracking-panel.tsx";
import type { ShipmentLegTrackingPolicy, ShipmentLegTrackingSession, ResolvedLegTrackingPolicy } from "../../../../../../server/contracts/mile-orchestration/mile-orchestration.ts";

const INITIAL_STATE: ShipmentOrderFormState = { error: null };

const LEG_STATUS_TONE: Record<ShipmentLeg["legStatus"], "success" | "warning" | "danger" | "info" | "neutral"> = {
  planned: "neutral",
  dispatched: "info",
  in_transit: "info",
  arrived: "warning",
  completed: "success",
  cancelled: "danger",
};

const AGGREGATE_STATE_TONE: Record<LegNetworkAggregateState, "success" | "warning" | "danger" | "info" | "neutral"> = {
  not_started: "neutral",
  blocked: "warning",
  in_progress: "info",
  completed: "success",
};

const NEXT_STATUS_BY_STATUS: Record<ShipmentLeg["legStatus"], readonly ShipmentLeg["legStatus"][]> = {
  planned: ["dispatched", "cancelled"],
  dispatched: ["in_transit", "cancelled"],
  in_transit: ["arrived", "cancelled"],
  arrived: ["completed", "cancelled"],
  completed: [],
  cancelled: [],
};

export interface LegNetworkEntry {
  readonly leg: ShipmentLeg;
  readonly stops: readonly ShipmentLegStop[];
  readonly cargoAllocation: ShipmentLegCargoAllocation | null;
  readonly custodyEvents: readonly ShipmentLegCustodyEvent[];
  readonly trackingPolicy: ShipmentLegTrackingPolicy | null;
  readonly resolvedTrackingPolicy: ResolvedLegTrackingPolicy | null;
  readonly currentTrackingSession: ShipmentLegTrackingSession | null;
}

export type LegNetworkFormAction = (prevState: ShipmentOrderFormState, formData: FormData) => Promise<ShipmentOrderFormState>;

/** ATW-221: the shipment's own multi-leg network -- aggregate state, per-leg planning/execution, and confirm/migrate controls. */
export function LegNetworkPanel({
  networkStatus,
  aggregateState,
  legs,
  addLegAction,
  confirmNetworkAction,
  migrateLegacyAction,
  addStopActionFor,
  allocateCargoActionFor,
  cancelLegActionFor,
  transitionLegActionFor,
  recordCustodyEventActionFor,
  upsertTrackingPolicyActionFor,
  startTrackingSessionActionFor,
  handoffTrackingSessionActionFor,
  endTrackingSessionActionFor,
  evaluateEscalationActionFor,
}: {
  networkStatus: LegNetworkStatus;
  aggregateState: LegNetworkAggregateState;
  legs: readonly LegNetworkEntry[];
  addLegAction: LegNetworkFormAction;
  confirmNetworkAction: LegNetworkFormAction;
  migrateLegacyAction: LegNetworkFormAction;
  addStopActionFor: (shipmentLegId: string) => LegNetworkFormAction;
  allocateCargoActionFor: (shipmentLegId: string) => LegNetworkFormAction;
  cancelLegActionFor: (shipmentLegId: string, expectedVersion: number) => LegNetworkFormAction;
  transitionLegActionFor: (shipmentLegId: string, expectedVersion: number) => LegNetworkFormAction;
  recordCustodyEventActionFor: (shipmentLegId: string) => LegNetworkFormAction;
  upsertTrackingPolicyActionFor: (shipmentLegId: string) => MileTrackingFormAction;
  startTrackingSessionActionFor: (shipmentLegId: string) => MileTrackingFormAction;
  handoffTrackingSessionActionFor: (shipmentLegId: string) => MileTrackingFormAction;
  endTrackingSessionActionFor: (shipmentLegId: string) => MileTrackingFormAction;
  evaluateEscalationActionFor: (shipmentLegId: string) => MileTrackingFormAction;
}) {
  return (
    <div className="flex flex-col gap-3">
      <div className="flex items-center gap-2">
        <span className="text-xs font-semibold uppercase tracking-wide text-neutral-500">Network</span>
        <StatusBadge tone="neutral" label={networkStatus ?? "not declared"} />
        <span className="text-xs font-semibold uppercase tracking-wide text-neutral-500">Aggregate</span>
        <StatusBadge tone={AGGREGATE_STATE_TONE[aggregateState]} label={aggregateState} />
      </div>

      {legs.length === 0 ? (
        <MigrateLegacyForm action={migrateLegacyAction} />
      ) : (
        <ol className="flex flex-col gap-4">
          {legs.map((entry) => (
            <LegCard
              key={entry.leg.id}
              entry={entry}
              addStopAction={addStopActionFor(entry.leg.id)}
              allocateCargoAction={allocateCargoActionFor(entry.leg.id)}
              cancelLegAction={cancelLegActionFor(entry.leg.id, entry.leg.recordVersion)}
              transitionLegAction={transitionLegActionFor(entry.leg.id, entry.leg.recordVersion)}
              recordCustodyEventAction={recordCustodyEventActionFor(entry.leg.id)}
              upsertTrackingPolicyAction={upsertTrackingPolicyActionFor(entry.leg.id)}
              startTrackingSessionAction={startTrackingSessionActionFor(entry.leg.id)}
              handoffTrackingSessionAction={handoffTrackingSessionActionFor(entry.leg.id)}
              endTrackingSessionAction={endTrackingSessionActionFor(entry.leg.id)}
              evaluateEscalationAction={evaluateEscalationActionFor(entry.leg.id)}
            />
          ))}
        </ol>
      )}

      <div className="border-t border-neutral-200 pt-3">
        <h3 className="mb-2 text-xs font-semibold uppercase tracking-wide text-neutral-500">Add leg</h3>
        <AddLegForm action={addLegAction} />
      </div>

      {legs.length > 0 && networkStatus !== "confirmed" ? (
        <div className="border-t border-neutral-200 pt-3">
          <ConfirmNetworkForm action={confirmNetworkAction} />
        </div>
      ) : null}
    </div>
  );
}

function AddLegForm({ action }: { action: LegNetworkFormAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  const describedBy = state.error ? "add-leg-error" : undefined;
  return (
    <form action={formAction} className="flex flex-wrap items-end gap-2" noValidate>
      <FormField id="add-leg-sequence-no" label="Sequence">
        <NumberInput id="add-leg-sequence-no" name="sequenceNo" min={1} required placeholder="Sequence" className="w-24" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <FormField id="add-leg-mode" label="Mode">
        <Select id="add-leg-mode" name="mode" required defaultValue="" invalid={Boolean(state.error)} aria-describedby={describedBy}>
          <option value="" disabled>
            Mode…
          </option>
          {SHIPMENT_LEG_MODES.map((mode) => (
            <option key={mode} value={mode}>
              {mode}
            </option>
          ))}
        </Select>
      </FormField>
      <FormField id="add-leg-carrier-master-id" label="Carrier master ID (optional)">
        <Input
          id="add-leg-carrier-master-id"
          name="carrierMasterId"
          type="text"
          placeholder="Carrier master ID (optional)"
          invalid={Boolean(state.error)}
          aria-describedby={describedBy}
        />
      </FormField>
      <FormField id="add-leg-planned-departure" label="Planned departure">
        <Input id="add-leg-planned-departure" name="plannedDepartureAt" type="datetime-local" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <FormField id="add-leg-planned-arrival" label="Planned arrival">
        <Input id="add-leg-planned-arrival" name="plannedArrivalAt" type="datetime-local" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Adding…" className="w-fit">
        Add leg
      </Button>
      {state.error ? (
        <div className="basis-full">
          <ValidationMessage id="add-leg-error">{state.error}</ValidationMessage>
        </div>
      ) : null}
    </form>
  );
}

function ConfirmNetworkForm({ action }: { action: LegNetworkFormAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col items-start gap-2" noValidate>
      <Button type="submit" variant="primary" loading={pending} loadingLabel="Confirming…" className="w-fit">
        Confirm leg network
      </Button>
      {state.error ? <ValidationMessage id="confirm-network-error">{state.error}</ValidationMessage> : null}
    </form>
  );
}

function MigrateLegacyForm({ action }: { action: LegNetworkFormAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col items-start gap-2" noValidate>
      <p className="text-sm text-neutral-600">This shipment has no leg network yet. Migrate it into one legacy-compatible leg, or add a leg below to start planning a multi-leg network.</p>
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Migrating…" className="w-fit">
        Migrate to single-leg network
      </Button>
      {state.error ? <ValidationMessage id="migrate-legacy-error">{state.error}</ValidationMessage> : null}
    </form>
  );
}

function LegCard({
  entry,
  addStopAction,
  allocateCargoAction,
  cancelLegAction,
  transitionLegAction,
  recordCustodyEventAction,
  upsertTrackingPolicyAction,
  startTrackingSessionAction,
  handoffTrackingSessionAction,
  endTrackingSessionAction,
  evaluateEscalationAction,
}: {
  entry: LegNetworkEntry;
  addStopAction: LegNetworkFormAction;
  allocateCargoAction: LegNetworkFormAction;
  cancelLegAction: LegNetworkFormAction;
  transitionLegAction: LegNetworkFormAction;
  recordCustodyEventAction: LegNetworkFormAction;
  upsertTrackingPolicyAction: MileTrackingFormAction;
  startTrackingSessionAction: MileTrackingFormAction;
  handoffTrackingSessionAction: MileTrackingFormAction;
  endTrackingSessionAction: MileTrackingFormAction;
  evaluateEscalationAction: MileTrackingFormAction;
}) {
  const { leg, stops, cargoAllocation, custodyEvents, trackingPolicy, resolvedTrackingPolicy, currentTrackingSession } = entry;
  const nextStatuses = NEXT_STATUS_BY_STATUS[leg.legStatus];

  return (
    <li className="flex flex-col gap-2 rounded-md border border-neutral-200 p-3">
      <div className="flex items-center gap-2">
        <span className="text-sm font-semibold text-neutral-900">
          Leg {leg.sequenceNo} — {leg.mode}
        </span>
        <StatusBadge tone={LEG_STATUS_TONE[leg.legStatus]} label={leg.legStatus} />
        {leg.isLegacyCompat ? <StatusBadge tone="neutral" label="legacy-compat" /> : null}
      </div>

      <dl className="grid grid-cols-2 gap-x-4 gap-y-1 text-xs text-neutral-600">
        <dt>Carrier</dt>
        <dd>{leg.carrierMasterId ?? "—"}</dd>
        <dt>Planned departure</dt>
        <dd>{leg.plannedDepartureAt ? new Date(leg.plannedDepartureAt).toLocaleString() : "—"}</dd>
        <dt>Planned arrival</dt>
        <dd>{leg.plannedArrivalAt ? new Date(leg.plannedArrivalAt).toLocaleString() : "—"}</dd>
        <dt>Cargo allocation</dt>
        <dd>
          {cargoAllocation
            ? `${cargoAllocation.allocatedQuantity ?? "—"} qty / ${cargoAllocation.allocatedWeightKg ?? "—"} kg / ${cargoAllocation.allocatedVolumeCbm ?? "—"} cbm`
            : "not yet allocated"}
        </dd>
      </dl>

      {stops.length > 0 ? (
        <ol className="flex flex-col gap-1 border-t border-neutral-100 pt-2 text-xs text-neutral-700">
          {stops.map((stop) => (
            <li key={stop.id}>
              {stop.stopSequence}. {stop.stopType} — {stop.locationName}
              {stop.longitude !== null && stop.latitude !== null ? ` (${stop.latitude.toFixed(4)}, ${stop.longitude.toFixed(4)})` : ""}
            </li>
          ))}
        </ol>
      ) : null}

      {custodyEvents.length > 0 ? (
        <ol className="flex flex-col gap-1 border-t border-neutral-100 pt-2 text-xs text-neutral-700">
          {custodyEvents.map((event) => (
            <li key={event.id}>
              {event.sequenceNo}. {event.eventType} — {new Date(event.occurredAt).toLocaleString()}
            </li>
          ))}
        </ol>
      ) : null}

      {leg.legStatus === "planned" ? (
        <div className="flex flex-col gap-2 border-t border-neutral-100 pt-2">
          <AddStopForm action={addStopAction} />
          <AllocateCargoForm action={allocateCargoAction} />
          <CancelLegForm action={cancelLegAction} />
        </div>
      ) : null}

      {nextStatuses.length > 0 ? (
        <div className="border-t border-neutral-100 pt-2">
          <TransitionLegForm action={transitionLegAction} nextStatuses={nextStatuses} />
        </div>
      ) : null}

      <div className="border-t border-neutral-100 pt-2">
        <MileTrackingPanel
          policy={trackingPolicy}
          resolved={resolvedTrackingPolicy}
          currentSession={currentTrackingSession}
          upsertPolicyAction={upsertTrackingPolicyAction}
          startSessionAction={startTrackingSessionAction}
          handoffSessionAction={handoffTrackingSessionAction}
          endSessionAction={endTrackingSessionAction}
          evaluateEscalationAction={evaluateEscalationAction}
        />
      </div>

      <div className="border-t border-neutral-100 pt-2">
        <RecordCustodyEventForm action={recordCustodyEventAction} />
      </div>
    </li>
  );
}

function AddStopForm({ action }: { action: LegNetworkFormAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  // Rendered once per leg card, so every id must be leg-unique.
  const formId = useId();
  const errorId = `${formId}-error`;
  const describedBy = state.error ? errorId : undefined;
  return (
    <form action={formAction} className="flex flex-wrap items-end gap-2" noValidate>
      <FormField id={`${formId}-stop-sequence`} label="Seq">
        <NumberInput id={`${formId}-stop-sequence`} name="stopSequence" min={1} required placeholder="Seq" className="w-16" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <FormField id={`${formId}-stop-type`} label="Stop type">
        <Select id={`${formId}-stop-type`} name="stopType" required defaultValue="" invalid={Boolean(state.error)} aria-describedby={describedBy}>
          <option value="" disabled>
            Stop type…
          </option>
          {SHIPMENT_LEG_STOP_TYPES.map((stopType) => (
            <option key={stopType} value={stopType}>
              {stopType}
            </option>
          ))}
        </Select>
      </FormField>
      <FormField id={`${formId}-location-name`} label="Location name">
        <Input id={`${formId}-location-name`} name="locationName" type="text" required placeholder="Location name" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <FormField id={`${formId}-longitude`} label="Longitude">
        <NumberInput id={`${formId}-longitude`} name="longitude" step="any" placeholder="Longitude" className="w-28" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <FormField id={`${formId}-latitude`} label="Latitude">
        <NumberInput id={`${formId}-latitude`} name="latitude" step="any" placeholder="Latitude" className="w-28" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <FormField id={`${formId}-planned-at`} label="Planned at">
        <Input id={`${formId}-planned-at`} name="plannedAt" type="datetime-local" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Adding…" className="w-fit">
        Add stop
      </Button>
      {state.error ? (
        <div className="basis-full">
          <ValidationMessage id={errorId}>{state.error}</ValidationMessage>
        </div>
      ) : null}
    </form>
  );
}

function AllocateCargoForm({ action }: { action: LegNetworkFormAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  // Rendered once per leg card, so every id must be leg-unique.
  const formId = useId();
  const errorId = `${formId}-error`;
  const describedBy = state.error ? errorId : undefined;
  return (
    <form action={formAction} className="flex flex-wrap items-end gap-2" noValidate>
      <FormField id={`${formId}-allocated-quantity`} label="Quantity">
        <NumberInput id={`${formId}-allocated-quantity`} name="allocatedQuantity" step="any" placeholder="Quantity" className="w-28" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <FormField id={`${formId}-allocated-weight-kg`} label="Weight (kg)">
        <NumberInput id={`${formId}-allocated-weight-kg`} name="allocatedWeightKg" step="any" placeholder="Weight (kg)" className="w-28" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <FormField id={`${formId}-allocated-volume-cbm`} label="Volume (cbm)">
        <NumberInput id={`${formId}-allocated-volume-cbm`} name="allocatedVolumeCbm" step="any" placeholder="Volume (cbm)" className="w-28" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Allocating…" className="w-fit">
        Allocate cargo
      </Button>
      {state.error ? (
        <div className="basis-full">
          <ValidationMessage id={errorId}>{state.error}</ValidationMessage>
        </div>
      ) : null}
    </form>
  );
}

function CancelLegForm({ action }: { action: LegNetworkFormAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  // Rendered once per leg card, so every id must be leg-unique.
  const formId = useId();
  const errorId = `${formId}-error`;
  return (
    <form action={formAction} className="flex flex-wrap items-end gap-2" noValidate>
      <FormField id={`${formId}-reason`} label="Cancellation reason">
        <Input
          id={`${formId}-reason`}
          name="reason"
          type="text"
          required
          placeholder="Cancellation reason"
          invalid={Boolean(state.error)}
          aria-describedby={state.error ? errorId : undefined}
        />
      </FormField>
      <Button type="submit" variant="destructive" loading={pending} loadingLabel="Cancelling…" className="w-fit">
        Cancel leg
      </Button>
      {state.error ? (
        <div className="basis-full">
          <ValidationMessage id={errorId}>{state.error}</ValidationMessage>
        </div>
      ) : null}
    </form>
  );
}

function TransitionLegForm({ action, nextStatuses }: { action: LegNetworkFormAction; nextStatuses: readonly ShipmentLeg["legStatus"][] }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  // Rendered once per leg card, so every id must be leg-unique.
  const formId = useId();
  const errorId = `${formId}-error`;
  return (
    <form action={formAction} className="flex flex-wrap items-end gap-2" noValidate>
      <FormField id={`${formId}-to-status`} label="Move leg to status">
        <Select
          id={`${formId}-to-status`}
          name="toStatus"
          required
          defaultValue=""
          invalid={Boolean(state.error)}
          aria-describedby={state.error ? errorId : undefined}
        >
          <option value="" disabled>
            Move to…
          </option>
          {nextStatuses.map((status) => (
            <option key={status} value={status}>
              {status}
            </option>
          ))}
        </Select>
      </FormField>
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Transitioning…" className="w-fit">
        Transition
      </Button>
      {state.error ? (
        <div className="basis-full">
          <ValidationMessage id={errorId}>{state.error}</ValidationMessage>
        </div>
      ) : null}
    </form>
  );
}

function RecordCustodyEventForm({ action }: { action: LegNetworkFormAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  // Rendered once per leg card, so every id must be leg-unique.
  const formId = useId();
  const errorId = `${formId}-error`;
  const describedBy = state.error ? errorId : undefined;
  return (
    <form action={formAction} className="flex flex-wrap items-end gap-2" noValidate>
      <FormField id={`${formId}-event-type`} label="Custody event">
        <Select id={`${formId}-event-type`} name="eventType" required defaultValue="" invalid={Boolean(state.error)} aria-describedby={describedBy}>
          <option value="" disabled>
            Custody event…
          </option>
          {SHIPMENT_LEG_CUSTODY_EVENT_TYPES.map((eventType) => (
            <option key={eventType} value={eventType}>
              {eventType}
            </option>
          ))}
        </Select>
      </FormField>
      <FormField id={`${formId}-from-party`} label="From party (optional)">
        <Input id={`${formId}-from-party`} name="fromParty" type="text" placeholder="From party (optional)" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <FormField id={`${formId}-to-party`} label="To party">
        <Input id={`${formId}-to-party`} name="toParty" type="text" required placeholder="To party" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <FormField id={`${formId}-occurred-at`} label="Occurred at">
        <Input id={`${formId}-occurred-at`} name="occurredAt" type="datetime-local" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Recording…" className="w-fit">
        Record custody
      </Button>
      {state.error ? (
        <div className="basis-full">
          <ValidationMessage id={errorId}>{state.error}</ValidationMessage>
        </div>
      ) : null}
    </form>
  );
}
