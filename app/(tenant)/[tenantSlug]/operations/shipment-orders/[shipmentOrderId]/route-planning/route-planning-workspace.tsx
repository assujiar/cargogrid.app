"use client";

import { useActionState } from "react";
import { Button } from "../../../../../../../components/ui/button.tsx";
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
  return (
    <form action={formAction} className="flex flex-wrap items-end gap-2 border-t border-neutral-100 pt-2" noValidate>
      <input name="requestedWeightKg" type="number" step="any" min={0} placeholder="Requested weight (kg)" className="w-40 rounded-md border border-neutral-300 px-2 py-1.5 text-sm" />
      <input name="requestedVolumeCbm" type="number" step="any" min={0} placeholder="Requested volume (cbm)" className="w-40 rounded-md border border-neutral-300 px-2 py-1.5 text-sm" />
      <Button type="submit" variant="primary" loading={pending} loadingLabel="Preparing…" className="w-fit">
        Prepare new scenario
      </Button>
      {state.error ? (
        <p role="alert" className="basis-full text-sm text-danger">
          {state.error}
        </p>
      ) : null}
    </form>
  );
}

function AddStopForm({ action }: { action: RoutePlanningFormAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-wrap items-end gap-2" noValidate>
      <input name="stopSequence" type="number" min={1} required placeholder="Seq" className="w-16 rounded-md border border-neutral-300 px-2 py-1.5 text-sm" />
      <select name="stopType" required defaultValue="" className="rounded-md border border-neutral-300 px-2 py-1.5 text-sm">
        <option value="" disabled>
          Stop type…
        </option>
        {ROUTE_PLANNING_STOP_TYPES.map((stopType) => (
          <option key={stopType} value={stopType}>
            {stopType}
          </option>
        ))}
      </select>
      <input name="locationName" type="text" required placeholder="Location name" className="rounded-md border border-neutral-300 px-2 py-1.5 text-sm" />
      <input name="longitude" type="number" step="any" placeholder="Longitude" className="w-28 rounded-md border border-neutral-300 px-2 py-1.5 text-sm" />
      <input name="latitude" type="number" step="any" placeholder="Latitude" className="w-28 rounded-md border border-neutral-300 px-2 py-1.5 text-sm" />
      <input name="timeWindowStart" type="datetime-local" className="rounded-md border border-neutral-300 px-2 py-1.5 text-sm" />
      <input name="timeWindowEnd" type="datetime-local" className="rounded-md border border-neutral-300 px-2 py-1.5 text-sm" />
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Adding…" className="w-fit">
        Add stop
      </Button>
      {state.error ? (
        <p role="alert" className="basis-full text-sm text-danger">
          {state.error}
        </p>
      ) : null}
    </form>
  );
}

function AddConstraintForm({ action }: { action: RoutePlanningFormAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-wrap items-end gap-2" noValidate>
      <select name="constraintType" required defaultValue="" className="rounded-md border border-neutral-300 px-2 py-1.5 text-sm">
        <option value="" disabled>
          Type…
        </option>
        {ROUTE_PLANNING_CONSTRAINT_TYPES.map((constraintType) => (
          <option key={constraintType} value={constraintType}>
            {constraintType}
          </option>
        ))}
      </select>
      <select name="constraintKey" required defaultValue="" className="rounded-md border border-neutral-300 px-2 py-1.5 text-sm">
        <option value="" disabled>
          Key…
        </option>
        {ROUTE_PLANNING_CONSTRAINT_KEYS.map((constraintKey) => (
          <option key={constraintKey} value={constraintKey}>
            {constraintKey}
          </option>
        ))}
      </select>
      <input name="value" type="text" required placeholder="Value (number, UUID, or datetime)" className="w-56 rounded-md border border-neutral-300 px-2 py-1.5 text-sm" />
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Adding…" className="w-fit">
        Add constraint
      </Button>
      {state.error ? (
        <p role="alert" className="basis-full text-sm text-danger">
          {state.error}
        </p>
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
      {state.error ? (
        <p role="alert" className="text-sm text-danger">
          {state.error}
        </p>
      ) : null}
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
      {state.error ? (
        <p role="alert" className="text-sm text-danger">
          {state.error}
        </p>
      ) : null}
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
      {state.error ? (
        <p role="alert" className="text-sm text-danger">
          {state.error}
        </p>
      ) : null}
    </form>
  );
}

function CancelForm({ action }: { action: RoutePlanningFormAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-wrap items-end gap-2" noValidate>
      <input name="reason" type="text" required placeholder="Cancellation reason" className="rounded-md border border-neutral-300 px-2 py-1.5 text-sm" />
      <Button type="submit" variant="destructive" loading={pending} loadingLabel="Cancelling…" className="w-fit">
        Cancel scenario
      </Button>
      {state.error ? (
        <p role="alert" className="basis-full text-sm text-danger">
          {state.error}
        </p>
      ) : null}
    </form>
  );
}

function SelectForm({ action }: { action: RoutePlanningFormAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col items-start gap-1" noValidate>
      <Button type="submit" variant="primary" loading={pending} loadingLabel="Selecting…" className="w-fit">
        Select this plan
      </Button>
      {state.error ? (
        <p role="alert" className="text-xs text-danger">
          {state.error}
        </p>
      ) : null}
    </form>
  );
}

function OverrideForm({ action }: { action: RoutePlanningFormAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-wrap items-end gap-2" noValidate>
      <input name="overrideReason" type="text" required placeholder="Override reason" className="w-56 rounded-md border border-neutral-300 px-2 py-1.5 text-sm" />
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Overriding…" className="w-fit">
        Override select
      </Button>
      {state.error ? (
        <p role="alert" className="basis-full text-xs text-danger">
          {state.error}
        </p>
      ) : null}
    </form>
  );
}

function ReplanForm({ action }: { action: RoutePlanningFormAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-wrap items-end gap-2" noValidate>
      <input name="reason" type="text" required placeholder="Replan reason" className="w-64 rounded-md border border-neutral-300 px-2 py-1.5 text-sm" />
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Replanning…" className="w-fit">
        Replan
      </Button>
      {state.error ? (
        <p role="alert" className="basis-full text-sm text-danger">
          {state.error}
        </p>
      ) : null}
    </form>
  );
}
