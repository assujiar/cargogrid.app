import { notFound } from "next/navigation";
import { resolveOperationsAccessForRequest } from "../../../../../../../lib/portal/resolve-operations-access.server.ts";
import { createSupabaseServerClient } from "../../../../../../../lib/supabase/server.ts";
import { getShipmentOrder, ShipmentOrderQueryError } from "../../../../../../../server/queries/shipment-order.ts";
import {
  listRoutePlanningScenarios,
  getRoutePlanningScenario,
  listRoutePlanningStops,
  listRoutePlanningConstraints,
  listRoutePlanningCandidatePlans,
  listRoutePlanningScoreComponents,
  getCurrentRoutePlanningSelection,
  getCanonicalPositionForPlanning,
  RouteLoadPlanningQueryError,
} from "../../../../../../../server/queries/route-load-planning.ts";
import { StatusBadge, type StatusTone } from "../../../../../../../components/ui/status-badge.tsx";
import { ErrorState } from "../../../../../../../components/ui/error-state.tsx";
import type { RoutePlanningScenario } from "../../../../../../../server/contracts/route-load-planning/route-load-planning.ts";
import { RoutePlanningWorkspace, PrepareScenarioForm, type CandidateEntry } from "./route-planning-workspace.tsx";
import {
  prepareRoutePlanningScenarioAction,
  addRoutePlanningStopAction,
  addRoutePlanningConstraintAction,
  validateRoutePlanningScenarioAction,
  executeRoutePlanningScenarioAction,
  runRoutePlanningJobAction,
  cancelRoutePlanningScenarioAction,
  selectRoutePlanningPlanAction,
  overrideRoutePlanningSelectionAction,
  replanRoutePlanningScenarioAction,
  type RoutePlanningFormState,
} from "./actions.ts";
import { randomUUID } from "node:crypto";

const SCENARIO_STATUS_TONE: Record<RoutePlanningScenario["status"], StatusTone> = {
  draft: "neutral",
  validated: "info",
  executing: "info",
  ready: "info",
  selected: "success",
  cancelled: "danger",
  failed: "danger",
};

/**
 * Route and Load Planning Using Canonical Position workspace (ATW-224,
 * CG-S10-ATW-005). Planning is decision support only -- this page never
 * dispatches a leg or mutates app.shipment_legs. See the migration's own header
 * for why the canonical-position snapshot shown here is honestly not_tracked/
 * unusable until ATW-226F ships a live telemetry writer.
 */
export default async function RoutePlanningPage({
  params,
  searchParams,
}: {
  params: Promise<{ tenantSlug: string; shipmentOrderId: string }>;
  searchParams: Promise<{ scenario?: string }>;
}) {
  const { tenantSlug, shipmentOrderId } = await params;
  const access = await resolveOperationsAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const { scenario: scenarioIdParam } = await searchParams;
  const supabase = await createSupabaseServerClient();

  let shipment;
  try {
    shipment = await getShipmentOrder(supabase, shipmentOrderId);
  } catch (error) {
    if (!(error instanceof ShipmentOrderQueryError)) {
      throw error;
    }
    return <ErrorState description="Something went wrong loading this Shipment Order. Please try again." />;
  }
  if (!shipment) {
    notFound();
  }

  let scenarios: RoutePlanningScenario[];
  let activeScenario: RoutePlanningScenario | null;
  try {
    scenarios = await listRoutePlanningScenarios(supabase, shipmentOrderId);
    activeScenario = scenarioIdParam ? await getRoutePlanningScenario(supabase, scenarioIdParam) : (scenarios[0] ?? null);
  } catch (error) {
    if (!(error instanceof RouteLoadPlanningQueryError)) {
      throw error;
    }
    return <ErrorState description="Something went wrong loading the planning scenarios. Please try again." />;
  }

  let stops: Awaited<ReturnType<typeof listRoutePlanningStops>> = [];
  let constraints: Awaited<ReturnType<typeof listRoutePlanningConstraints>> = [];
  let candidateEntries: CandidateEntry[] = [];
  let currentSelection: Awaited<ReturnType<typeof getCurrentRoutePlanningSelection>> = null;
  let canonicalPosition: Awaited<ReturnType<typeof getCanonicalPositionForPlanning>> = null;
  try {
    if (activeScenario) {
      stops = await listRoutePlanningStops(supabase, activeScenario.id);
      constraints = await listRoutePlanningConstraints(supabase, activeScenario.id);
      const candidates = await listRoutePlanningCandidatePlans(supabase, activeScenario.id);
      candidateEntries = await Promise.all(candidates.map(async (candidate) => ({ candidate, scoreComponents: await listRoutePlanningScoreComponents(supabase, candidate.id) })));
      currentSelection = await getCurrentRoutePlanningSelection(supabase, activeScenario.id);
    }
    canonicalPosition = await getCanonicalPositionForPlanning(supabase, shipmentOrderId);
  } catch (error) {
    if (!(error instanceof RouteLoadPlanningQueryError)) {
      throw error;
    }
    return <ErrorState description="Something went wrong loading the planning scenario detail. Please try again." />;
  }

  const boundPrepareAction = prepareRoutePlanningScenarioAction.bind(null, tenantSlug, shipmentOrderId);
  const boundReplanAction = activeScenario ? replanRoutePlanningScenarioAction.bind(null, tenantSlug, shipmentOrderId, activeScenario.id) : null;

  let workspaceActions: {
    addStopAction: (prevState: RoutePlanningFormState, formData: FormData) => Promise<RoutePlanningFormState>;
    addConstraintAction: (prevState: RoutePlanningFormState, formData: FormData) => Promise<RoutePlanningFormState>;
    validateAction: (prevState: RoutePlanningFormState, formData: FormData) => Promise<RoutePlanningFormState>;
    executeAction: (prevState: RoutePlanningFormState, formData: FormData) => Promise<RoutePlanningFormState>;
    runPlannerAction: (prevState: RoutePlanningFormState, formData: FormData) => Promise<RoutePlanningFormState>;
    cancelAction: (prevState: RoutePlanningFormState, formData: FormData) => Promise<RoutePlanningFormState>;
    selectPlanActionFor: (candidatePlanId: string) => (prevState: RoutePlanningFormState, formData: FormData) => Promise<RoutePlanningFormState>;
    overridePlanActionFor: (candidatePlanId: string) => (prevState: RoutePlanningFormState, formData: FormData) => Promise<RoutePlanningFormState>;
  } | null = null;

  if (activeScenario) {
    const executeIdempotencyKey = randomUUID();
    workspaceActions = {
      addStopAction: addRoutePlanningStopAction.bind(null, tenantSlug, shipmentOrderId, activeScenario.id),
      addConstraintAction: addRoutePlanningConstraintAction.bind(null, tenantSlug, shipmentOrderId, activeScenario.id),
      validateAction: validateRoutePlanningScenarioAction.bind(null, tenantSlug, shipmentOrderId, activeScenario.id, activeScenario.recordVersion),
      executeAction: executeRoutePlanningScenarioAction.bind(null, tenantSlug, shipmentOrderId, activeScenario.id, activeScenario.recordVersion, executeIdempotencyKey),
      runPlannerAction: runRoutePlanningJobAction.bind(null, tenantSlug, shipmentOrderId),
      cancelAction: cancelRoutePlanningScenarioAction.bind(null, tenantSlug, shipmentOrderId, activeScenario.id, activeScenario.recordVersion),
      selectPlanActionFor: (candidatePlanId: string) => selectRoutePlanningPlanAction.bind(null, tenantSlug, shipmentOrderId, activeScenario.id, candidatePlanId, activeScenario.recordVersion),
      overridePlanActionFor: (candidatePlanId: string) => overrideRoutePlanningSelectionAction.bind(null, tenantSlug, shipmentOrderId, activeScenario.id, candidatePlanId, activeScenario.recordVersion),
    };
  }

  return (
    <div className="flex flex-col gap-6">
      <div className="flex items-center gap-3">
        <h1 className="text-xl font-semibold text-neutral-900">Route and load planning</h1>
        <a href={`/${tenantSlug}/operations/shipment-orders/${shipmentOrderId}`} className="text-sm font-medium text-primary underline">
          {shipment.shipmentNumber}
        </a>
      </div>
      <p className="text-xs text-neutral-500">
        Decision support only -- selecting or overriding a plan here never dispatches a leg. Location-dependent input is read through exactly one trusted, source-arbitrated projection; raw mobile,
        direct-device, or third-party telemetry is never read here.
      </p>

      <section className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Scenarios</h2>
        {scenarios.length > 0 ? (
          <ul className="flex flex-wrap gap-2">
            {scenarios.map((scenario) => (
              <li key={scenario.id}>
                <a
                  href={`/${tenantSlug}/operations/shipment-orders/${shipmentOrderId}/route-planning?scenario=${scenario.id}`}
                  className={`inline-flex items-center gap-1 rounded-md border px-2 py-1 text-xs ${scenario.id === activeScenario?.id ? "border-primary" : "border-neutral-200"}`}
                >
                  <StatusBadge tone={SCENARIO_STATUS_TONE[scenario.status]} label={scenario.status} />
                  {scenario.id.slice(0, 8)}
                </a>
              </li>
            ))}
          </ul>
        ) : (
          <p className="text-xs text-neutral-500">No planning scenario exists yet for this Shipment Order.</p>
        )}

        <PrepareScenarioForm action={boundPrepareAction} />
      </section>

      {activeScenario && workspaceActions ? (
        <section className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
          <h2 className="text-sm font-semibold text-neutral-900">Planner workspace</h2>
          <RoutePlanningWorkspace
            scenario={activeScenario}
            stops={stops}
            constraints={constraints}
            candidates={candidateEntries}
            currentSelection={currentSelection}
            canonicalPosition={canonicalPosition}
            addStopAction={workspaceActions.addStopAction}
            addConstraintAction={workspaceActions.addConstraintAction}
            validateAction={workspaceActions.validateAction}
            executeAction={workspaceActions.executeAction}
            runPlannerAction={workspaceActions.runPlannerAction}
            cancelAction={workspaceActions.cancelAction}
            selectPlanActionFor={workspaceActions.selectPlanActionFor}
            overridePlanActionFor={workspaceActions.overridePlanActionFor}
            replanAction={boundReplanAction!}
          />
        </section>
      ) : null}
    </div>
  );
}
