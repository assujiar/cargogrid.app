"use client";

import { useActionState, useId } from "react";
import { Button } from "../../../../../../../components/ui/button.tsx";
import { FormField } from "../../../../../../../components/forms/form-field.tsx";
import { Input } from "../../../../../../../components/forms/input.tsx";
import { NumberInput } from "../../../../../../../components/forms/number-input.tsx";
import { Select } from "../../../../../../../components/forms/select.tsx";
import { ValidationMessage } from "../../../../../../../components/forms/validation-message.tsx";
import { StatusBadge, type StatusTone } from "../../../../../../../components/ui/status-badge.tsx";
import { Badge } from "../../../../../../../components/ui/badge.tsx";
import {
  ROUTE_PLANNING_STOP_TYPES,
  ROUTE_PLANNING_CONSTRAINT_TYPES,
  ROUTE_PLANNING_CONSTRAINT_KEYS,
  type RoutePlanningScenario,
  type RoutePlanningStop,
  type RoutePlanningConstraint,
  type RoutePlanningCandidatePlan,
  type RoutePlanningScoreComponent,
  type RoutePlanningSelectedPlan,
  type CanonicalPositionForPlanning,
} from "../../../../../../../server/contracts/route-load-planning/route-load-planning.ts";
import type { RoutePlanningFormState } from "./actions.ts";

const INITIAL_STATE: RoutePlanningFormState = { error: null };

const SCENARIO_STATUS_TONE: Record<RoutePlanningScenario["status"], StatusTone> = {
  draft: "neutral",
  validated: "info",
  executing: "info",
  ready: "info",
  selected: "success",
  cancelled: "danger",
  failed: "danger",
};

export type RoutePlanningFormAction = (prevState: RoutePlanningFormState, formData: FormData) => Promise<RoutePlanningFormState>;

export interface CandidateEntry {
  readonly candidate: RoutePlanningCandidatePlan;
  readonly scoreComponents: readonly RoutePlanningScoreComponent[];
}

/**
 * ATW-224 planner workspace. Shows the scenario's own constraints, the canonical
 * trusted position at safe granularity (tracking status/freshness/source class
 * only -- never raw coordinates, mirroring ATW-222's own dispatch-board "no raw
 * device or provider data" precedent), candidate alternatives with their own
 * explainable score breakdown, infeasibility reasons, and the human
 * select/override decision. Planning is decision support only -- nothing here
 * ever dispatches a leg.
 */
export function RoutePlanningWorkspace({
  scenario,
  stops,
  constraints,
  candidates,
  currentSelection,
  canonicalPosition,
  addStopAction,
  addConstraintAction,
  validateAction,
  executeAction,
  runPlannerAction,
  cancelAction,
  selectPlanActionFor,
  overridePlanActionFor,
  replanAction,
}: {
  scenario: RoutePlanningScenario;
  stops: readonly RoutePlanningStop[];
  constraints: readonly RoutePlanningConstraint[];
  candidates: readonly CandidateEntry[];
  currentSelection: RoutePlanningSelectedPlan | null;
  canonicalPosition: CanonicalPositionForPlanning | null;
  addStopAction: RoutePlanningFormAction;
  addConstraintAction: RoutePlanningFormAction;
  validateAction: RoutePlanningFormAction;
  executeAction: RoutePlanningFormAction;
  runPlannerAction: RoutePlanningFormAction;
  cancelAction: RoutePlanningFormAction;
  selectPlanActionFor: (candidatePlanId: string) => RoutePlanningFormAction;
  overridePlanActionFor: (candidatePlanId: string) => RoutePlanningFormAction;
  replanAction: RoutePlanningFormAction;
}) {
  const isDraft = scenario.status === "draft";
  const isValidated = scenario.status === "validated";
  const isExecuting = scenario.status === "executing";
  const hasCandidates = scenario.status === "ready" || scenario.status === "selected";
  const isCancellable = scenario.status !== "selected" && scenario.status !== "cancelled";

  return (
    <div className="flex flex-col gap-4">
      <div className="flex flex-wrap items-center gap-2">
        <StatusBadge tone={SCENARIO_STATUS_TONE[scenario.status]} label={scenario.status} />
        <span className="text-xs text-neutral-500">Scenario {scenario.id}</span>
      </div>

      <PositionSummary position={canonicalPosition} />

      <section className="flex flex-col gap-2 border-t border-neutral-100 pt-3">
        <h3 className="text-xs font-semibold uppercase tracking-wide text-neutral-500">Stops</h3>
        {stops.length > 0 ? (
          <ol className="flex flex-col gap-1 text-xs text-neutral-700">
            {stops.map((stop) => (
              <li key={stop.id}>
                {stop.stopSequence}. {stop.stopType} — {stop.locationName}
                {stop.longitude !== null && stop.latitude !== null ? ` (${stop.latitude.toFixed(4)}, ${stop.longitude.toFixed(4)})` : ""}
                {stop.timeWindowStart ? ` — window ${new Date(stop.timeWindowStart).toLocaleString()}${stop.timeWindowEnd ? ` – ${new Date(stop.timeWindowEnd).toLocaleString()}` : ""}` : ""}
              </li>
            ))}
          </ol>
        ) : (
          <p className="text-xs text-neutral-500">No stops declared yet.</p>
        )}
        {isDraft ? <AddStopForm action={addStopAction} /> : null}
      </section>

      <section className="flex flex-col gap-2 border-t border-neutral-100 pt-3">
        <h3 className="text-xs font-semibold uppercase tracking-wide text-neutral-500">Constraints</h3>
        {constraints.length > 0 ? (
          <ul className="flex flex-col gap-1 text-xs text-neutral-700">
            {constraints.map((constraint) => (
              <li key={constraint.id}>
                <StatusBadge tone={constraint.constraintType === "hard" ? "danger" : "neutral"} label={constraint.constraintType} /> {constraint.constraintKey} = {JSON.stringify(constraint.constraintValue)}
              </li>
            ))}
          </ul>
        ) : (
          <p className="text-xs text-neutral-500">No constraints declared yet.</p>
        )}
        {isDraft ? <AddConstraintForm action={addConstraintAction} /> : null}
      </section>

      <section className="flex flex-wrap items-center gap-2 border-t border-neutral-100 pt-3">
        {isDraft ? <ValidateForm action={validateAction} /> : null}
        {isValidated ? <ExecuteForm action={executeAction} /> : null}
        {isExecuting ? <RunPlannerForm action={runPlannerAction} /> : null}
        {isCancellable ? <CancelForm action={cancelAction} /> : null}
      </section>

      {hasCandidates ? (
        <section className="flex flex-col gap-3 border-t border-neutral-100 pt-3">
          <h3 className="text-xs font-semibold uppercase tracking-wide text-neutral-500">Candidate plans</h3>
          {candidates.length === 0 ? (
            <p className="text-xs text-neutral-500">The planner has not yet produced any candidate for this scenario.</p>
          ) : (
            <ol className="flex flex-col gap-3">
              {candidates.map((entry) => (
                <CandidateCard
                  key={entry.candidate.id}
                  entry={entry}
                  isCurrent={currentSelection?.candidatePlanId === entry.candidate.id && currentSelection.isCurrent}
                  selectAction={selectPlanActionFor(entry.candidate.id)}
                  overrideAction={overridePlanActionFor(entry.candidate.id)}
                />
              ))}
            </ol>
          )}
        </section>
      ) : null}

      {currentSelection ? (
        <section className="flex flex-col gap-1 border-t border-neutral-100 pt-3 text-xs text-neutral-700">
          <h3 className="text-xs font-semibold uppercase tracking-wide text-neutral-500">Current selection</h3>
          <p>
            Candidate {currentSelection.candidatePlanId} {currentSelection.isOverride ? <StatusBadge tone="warning" label="override" /> : null}
          </p>
          {currentSelection.overrideReason ? <p className="text-neutral-500">Reason: {currentSelection.overrideReason}</p> : null}
        </section>
      ) : null}

      <section className="flex flex-col gap-2 border-t border-neutral-100 pt-3">
        <h3 className="text-xs font-semibold uppercase tracking-wide text-neutral-500">Replan</h3>
        <p className="text-xs text-neutral-500">Starts a fresh draft scenario copying this one&apos;s own stops and constraints -- planning is decision support only, nothing here dispatches a leg.</p>
        <ReplanForm action={replanAction} />
      </section>
    </div>
  );
}

function PositionSummary({ position }: { position: CanonicalPositionForPlanning | null }) {
  if (!position) {
    return <p className="text-xs text-neutral-500">No canonical position could be resolved for this shipment.</p>;
  }
  return (
    <div className="flex flex-wrap items-center gap-2 rounded-md border border-neutral-200 bg-neutral-50 p-2 text-xs text-neutral-700">
      <span className="font-semibold uppercase tracking-wide text-neutral-500">Trusted position</span>
      <StatusBadge tone={position.isUsable ? "success" : "neutral"} label={position.trackingStatus.replace("_", " ")} />
      {position.freshnessStatus ? <Badge tone="neutral">{position.freshnessStatus}</Badge> : null}
      {position.authoritativeSourceType ? <Badge tone="neutral">{position.authoritativeSourceType.replace("_", " ")}</Badge> : null}
      {!position.trackingEntitled ? <span className="text-neutral-500">Not entitled</span> : null}
      {!position.isUsable ? <span className="text-neutral-500">Planning proceeds without a live position (manual mode).</span> : null}
    </div>
  );
}

function CandidateCard({
  entry,
  isCurrent,
  selectAction,
  overrideAction,
}: {
  entry: CandidateEntry;
  isCurrent: boolean;
  selectAction: RoutePlanningFormAction;
  overrideAction: RoutePlanningFormAction;
}) {
  const { candidate, scoreComponents } = entry;
  return (
    <li className="flex flex-col gap-2 rounded-md border border-neutral-200 p-3">
      <div className="flex items-center gap-2">
        <span className="text-sm font-semibold text-neutral-900">Rank {candidate.planRank}</span>
        <StatusBadge tone={candidate.feasible ? "success" : "danger"} label={candidate.feasible ? "feasible" : "infeasible"} />
        {isCurrent ? <StatusBadge tone="info" label="selected" /> : null}
      </div>

      <dl className="grid grid-cols-2 gap-x-4 gap-y-1 text-xs text-neutral-600">
        <dt>Vehicle</dt>
        <dd>{candidate.vehicleMasterId ?? "—"}</dd>
        <dt>Driver</dt>
        <dd>{candidate.driverMasterId ?? "—"}</dd>
      </dl>

      {scoreComponents.length > 0 ? (
        <ul className="flex flex-wrap gap-3 border-t border-neutral-100 pt-2 text-xs text-neutral-600">
          {scoreComponents.map((component) => (
            <li key={component.id}>
              {component.componentKey.replace(/_/g, " ")}: {component.componentValue ?? "—"}
            </li>
          ))}
        </ul>
      ) : null}

      {!candidate.feasible && candidate.infeasibilityReasons && candidate.infeasibilityReasons.length > 0 ? (
        <ul className="flex flex-wrap gap-2 border-t border-neutral-100 pt-2 text-xs text-danger">
          {candidate.infeasibilityReasons.map((reason) => (
            <li key={reason}>{reason.replace(/_/g, " ")}</li>
          ))}
        </ul>
      ) : null}

      <div className="flex flex-wrap items-center gap-2 border-t border-neutral-100 pt-2">
        {candidate.feasible ? <SelectForm action={selectAction} /> : null}
        <OverrideForm action={overrideAction} />
      </div>
    </li>
  );
}

export function PrepareScenarioForm({ action }: { action: RoutePlanningFormAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  const describedBy = state.error ? "prepare-scenario-error" : undefined;
  return (
    <form action={formAction} className="flex flex-wrap items-end gap-2 border-t border-neutral-100 pt-2" noValidate>
      <FormField id="prepare-requested-weight-kg" label="Requested weight (kg)">
        <NumberInput
          id="prepare-requested-weight-kg"
          name="requestedWeightKg"
          step="any"
          min={0}
          placeholder="Requested weight (kg)"
          className="w-40"
          invalid={Boolean(state.error)}
          aria-describedby={describedBy}
        />
      </FormField>
      <FormField id="prepare-requested-volume-cbm" label="Requested volume (cbm)">
        <NumberInput
          id="prepare-requested-volume-cbm"
          name="requestedVolumeCbm"
          step="any"
          min={0}
          placeholder="Requested volume (cbm)"
          className="w-40"
          invalid={Boolean(state.error)}
          aria-describedby={describedBy}
        />
      </FormField>
      <Button type="submit" variant="primary" loading={pending} loadingLabel="Preparing…" className="w-fit">
        Prepare new scenario
      </Button>
      {state.error ? (
        <div className="basis-full">
          <ValidationMessage id="prepare-scenario-error">{state.error}</ValidationMessage>
        </div>
      ) : null}
    </form>
  );
}

function AddStopForm({ action }: { action: RoutePlanningFormAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  const describedBy = state.error ? "planning-add-stop-error" : undefined;
  return (
    <form action={formAction} className="flex flex-wrap items-end gap-2" noValidate>
      <FormField id="planning-stop-sequence" label="Seq">
        <NumberInput id="planning-stop-sequence" name="stopSequence" min={1} required placeholder="Seq" className="w-16" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <FormField id="planning-stop-type" label="Stop type">
        <Select id="planning-stop-type" name="stopType" required defaultValue="" invalid={Boolean(state.error)} aria-describedby={describedBy}>
          <option value="" disabled>
            Stop type…
          </option>
          {ROUTE_PLANNING_STOP_TYPES.map((stopType) => (
            <option key={stopType} value={stopType}>
              {stopType}
            </option>
          ))}
        </Select>
      </FormField>
      <FormField id="planning-stop-location-name" label="Location name">
        <Input id="planning-stop-location-name" name="locationName" type="text" required placeholder="Location name" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <FormField id="planning-stop-longitude" label="Longitude">
        <NumberInput id="planning-stop-longitude" name="longitude" step="any" placeholder="Longitude" className="w-28" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <FormField id="planning-stop-latitude" label="Latitude">
        <NumberInput id="planning-stop-latitude" name="latitude" step="any" placeholder="Latitude" className="w-28" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <FormField id="planning-stop-time-window-start" label="Time window start">
        <Input id="planning-stop-time-window-start" name="timeWindowStart" type="datetime-local" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <FormField id="planning-stop-time-window-end" label="Time window end">
        <Input id="planning-stop-time-window-end" name="timeWindowEnd" type="datetime-local" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Adding…" className="w-fit">
        Add stop
      </Button>
      {state.error ? (
        <div className="basis-full">
          <ValidationMessage id="planning-add-stop-error">{state.error}</ValidationMessage>
        </div>
      ) : null}
    </form>
  );
}

function AddConstraintForm({ action }: { action: RoutePlanningFormAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  const describedBy = state.error ? "planning-add-constraint-error" : undefined;
  return (
    <form action={formAction} className="flex flex-wrap items-end gap-2" noValidate>
      <FormField id="planning-constraint-type" label="Type">
        <Select id="planning-constraint-type" name="constraintType" required defaultValue="" invalid={Boolean(state.error)} aria-describedby={describedBy}>
          <option value="" disabled>
            Type…
          </option>
          {ROUTE_PLANNING_CONSTRAINT_TYPES.map((constraintType) => (
            <option key={constraintType} value={constraintType}>
              {constraintType}
            </option>
          ))}
        </Select>
      </FormField>
      <FormField id="planning-constraint-key" label="Key">
        <Select id="planning-constraint-key" name="constraintKey" required defaultValue="" invalid={Boolean(state.error)} aria-describedby={describedBy}>
          <option value="" disabled>
            Key…
          </option>
          {ROUTE_PLANNING_CONSTRAINT_KEYS.map((constraintKey) => (
            <option key={constraintKey} value={constraintKey}>
              {constraintKey}
            </option>
          ))}
        </Select>
      </FormField>
      <FormField id="planning-constraint-value" label="Value">
        <Input
          id="planning-constraint-value"
          name="value"
          type="text"
          required
          placeholder="Value (number, UUID, or datetime)"
          className="w-56"
          invalid={Boolean(state.error)}
          aria-describedby={describedBy}
        />
      </FormField>
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Adding…" className="w-fit">
        Add constraint
      </Button>
      {state.error ? (
        <div className="basis-full">
          <ValidationMessage id="planning-add-constraint-error">{state.error}</ValidationMessage>
        </div>
      ) : null}
    </form>
  );
}

function ValidateForm({ action }: { action: RoutePlanningFormAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col items-start gap-2" noValidate>
      <Button type="submit" variant="primary" loading={pending} loadingLabel="Validating…" className="w-fit">
        Validate scenario
      </Button>
      {state.error ? <ValidationMessage id="planning-validate-error">{state.error}</ValidationMessage> : null}
    </form>
  );
}

function ExecuteForm({ action }: { action: RoutePlanningFormAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col items-start gap-2" noValidate>
      <Button type="submit" variant="primary" loading={pending} loadingLabel="Queuing…" className="w-fit">
        Execute (queue planning job)
      </Button>
      {state.error ? <ValidationMessage id="planning-execute-error">{state.error}</ValidationMessage> : null}
    </form>
  );
}

function RunPlannerForm({ action }: { action: RoutePlanningFormAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col items-start gap-2" noValidate>
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Running…" className="w-fit">
        Run planner now
      </Button>
      <p className="text-xs text-neutral-500">No live worker polls this queue yet -- this runs the queued job on demand.</p>
      {state.error ? <ValidationMessage id="planning-run-error">{state.error}</ValidationMessage> : null}
    </form>
  );
}

function CancelForm({ action }: { action: RoutePlanningFormAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-wrap items-end gap-2" noValidate>
      <FormField id="planning-cancel-reason" label="Cancellation reason">
        <Input
          id="planning-cancel-reason"
          name="reason"
          type="text"
          required
          placeholder="Cancellation reason"
          invalid={Boolean(state.error)}
          aria-describedby={state.error ? "planning-cancel-error" : undefined}
        />
      </FormField>
      <Button type="submit" variant="destructive" loading={pending} loadingLabel="Cancelling…" className="w-fit">
        Cancel scenario
      </Button>
      {state.error ? (
        <div className="basis-full">
          <ValidationMessage id="planning-cancel-error">{state.error}</ValidationMessage>
        </div>
      ) : null}
    </form>
  );
}

function SelectForm({ action }: { action: RoutePlanningFormAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  // Rendered once per candidate card, so the error id must be candidate-unique.
  const formId = useId();
  return (
    <form action={formAction} className="flex flex-col items-start gap-1" noValidate>
      <Button type="submit" variant="primary" loading={pending} loadingLabel="Selecting…" className="w-fit">
        Select this plan
      </Button>
      {state.error ? <ValidationMessage id={`${formId}-error`}>{state.error}</ValidationMessage> : null}
    </form>
  );
}

function OverrideForm({ action }: { action: RoutePlanningFormAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  // Rendered once per candidate card, so every id must be candidate-unique.
  const formId = useId();
  const errorId = `${formId}-error`;
  return (
    <form action={formAction} className="flex flex-wrap items-end gap-2" noValidate>
      <FormField id={`${formId}-override-reason`} label="Override reason">
        <Input
          id={`${formId}-override-reason`}
          name="overrideReason"
          type="text"
          required
          placeholder="Override reason"
          className="w-56"
          invalid={Boolean(state.error)}
          aria-describedby={state.error ? errorId : undefined}
        />
      </FormField>
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Overriding…" className="w-fit">
        Override select
      </Button>
      {state.error ? (
        <div className="basis-full">
          <ValidationMessage id={errorId}>{state.error}</ValidationMessage>
        </div>
      ) : null}
    </form>
  );
}

function ReplanForm({ action }: { action: RoutePlanningFormAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-wrap items-end gap-2" noValidate>
      <FormField id="planning-replan-reason" label="Replan reason">
        <Input
          id="planning-replan-reason"
          name="reason"
          type="text"
          required
          placeholder="Replan reason"
          className="w-64"
          invalid={Boolean(state.error)}
          aria-describedby={state.error ? "planning-replan-error" : undefined}
        />
      </FormField>
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Replanning…" className="w-fit">
        Replan
      </Button>
      {state.error ? (
        <div className="basis-full">
          <ValidationMessage id="planning-replan-error">{state.error}</ValidationMessage>
        </div>
      ) : null}
    </form>
  );
}
