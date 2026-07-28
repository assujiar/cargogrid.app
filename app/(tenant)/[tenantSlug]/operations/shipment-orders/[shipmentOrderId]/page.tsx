import { notFound } from "next/navigation";
import { randomUUID } from "node:crypto";
import { resolveOperationsAccessForRequest } from "../../../../../../lib/portal/resolve-operations-access.server.ts";
import { createSupabaseServerClient } from "../../../../../../lib/supabase/server.ts";
import { getShipmentOrder, getJobShipmentAllocationBalance, ShipmentOrderQueryError } from "../../../../../../server/queries/shipment-order.ts";
import { getShipmentStatusHistory, ShipmentLifecycleQueryError } from "../../../../../../server/queries/shipment-lifecycle.ts";
import { getShipmentModeProfile, ShipmentModeBaselineQueryError } from "../../../../../../server/queries/shipment-mode-baseline.ts";
import { findAssignmentCandidates, getResourceAssignmentHistory, ResourceAssignmentQueryError } from "../../../../../../server/queries/resource-assignment.ts";
import { getShipmentMilestoneTimeline, getShipmentMilestoneProjection, listMilestoneCodes, MilestoneManagementQueryError } from "../../../../../../server/queries/milestone-management.ts";
import { listShipmentExceptions, ExceptionEscalationQueryError } from "../../../../../../server/queries/exception-escalation.ts";
import { getDispatchReadiness, BasicDispatchQueryError } from "../../../../../../server/queries/basic-dispatch.ts";
import { getShipmentDocumentChecklist, evaluateShipmentDocumentChecklistCompleteness, DocumentRequirementQueryError } from "../../../../../../server/queries/document-requirement.ts";
import { StatusBadge } from "../../../../../../components/ui/status-badge.tsx";
import { Badge } from "../../../../../../components/ui/badge.tsx";
import { SHIPMENT_ORDER_STATUS_TONE_MAP } from "../../../../../../components/domain/status-tone-map.ts";
import { ErrorState } from "../../../../../../components/ui/error-state.tsx";
import { ConfirmShipmentOrderForm } from "./confirm-shipment-order-form.tsx";
import { TransitionShipmentOrderForm } from "./transition-shipment-order-form.tsx";
import { StatusTimeline } from "./status-timeline.tsx";
import { ModeProfileForm } from "./mode-profile-form.tsx";
import { ChangeModeForm } from "./change-mode-form.tsx";
import { ResourceAssignmentPanel } from "./resource-assignment-panel.tsx";
import { ResourceAssignmentHistory } from "./resource-assignment-history.tsx";
import { MilestoneTimeline } from "./milestone-timeline.tsx";
import { IngestMilestoneEventForm } from "./ingest-milestone-event-form.tsx";
import { ReportExceptionForm } from "./report-exception-form.tsx";
import { ExceptionList } from "./exception-list.tsx";
import { DispatchPanel } from "./dispatch-panel.tsx";
import { DocumentChecklistPanel } from "./document-checklist-panel.tsx";
import {
  confirmShipmentOrderAction,
  transitionShipmentOrderAction,
  setShipmentModeProfileAction,
  changeShipmentModeAction,
  assignResourceAction,
  reassignResourceAction,
  holdResourceAssignmentAction,
  resumeResourceAssignmentAction,
  unassignResourceAction,
  ingestMilestoneEventAction,
  reportExceptionAction,
  manageExceptionAction,
  dispatchShipmentOrderAction,
  pinDocumentChecklistAction,
  uploadAndLinkDocumentAction,
  reviewDocumentChecklistItemAction,
  type ShipmentOrderFormState,
} from "./actions.ts";
import { permittedNextStatuses } from "./lifecycle-transitions.ts";
import type { TransitionableStatus } from "../../../../../../server/contracts/shipment-lifecycle/shipment-lifecycle.ts";
import type { ShipmentModeProfileMode } from "../../../../../../server/contracts/shipment-mode-baseline/shipment-mode-baseline.ts";
import { RESOURCE_ASSIGNMENT_ROLES } from "../../../../../../server/contracts/resource-assignment/resource-assignment.ts";

/**
 * Shipment Order detail (OPS-169, CG-S8-OPS-003, Prompt 169 §15) -- inherited fields
 * with source links (Job Order, shipper account), route/schedule, and the governed
 * allocation balance for the Job Order this Shipment Order shares with any sibling
 * splits. `getShipmentOrder` returns `null` for both "does not exist" and "exists but
 * RLS denies it," matching every prior detail page's posture.
 */
export default async function ShipmentOrderDetailPage({ params }: { params: Promise<{ tenantSlug: string; shipmentOrderId: string }> }) {
  const { tenantSlug, shipmentOrderId } = await params;
  const access = await resolveOperationsAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

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

  if (!shipment || shipment.tenantId !== access.tenant.id) {
    notFound();
  }

  let balance;
  try {
    balance = await getJobShipmentAllocationBalance(supabase, { jobOrderId: shipment.jobOrderId, actorAuthUserId: access.authUserId });
  } catch (error) {
    if (!(error instanceof ShipmentOrderQueryError)) {
      throw error;
    }
    return <ErrorState description="Something went wrong loading the allocation balance. Please try again." />;
  }

  let history;
  try {
    history = await getShipmentStatusHistory(supabase, { shipmentOrderId: shipment.id, actorAuthUserId: access.authUserId });
  } catch (error) {
    if (!(error instanceof ShipmentLifecycleQueryError)) {
      throw error;
    }
    return <ErrorState description="Something went wrong loading the status history. Please try again." />;
  }

  let modeProfile;
  try {
    modeProfile = await getShipmentModeProfile(supabase, shipment.id);
  } catch (error) {
    if (!(error instanceof ShipmentModeBaselineQueryError)) {
      throw error;
    }
    return <ErrorState description="Something went wrong loading the mode profile. Please try again." />;
  }

  let resourceHistory;
  let candidatesByRole;
  try {
    resourceHistory = await getResourceAssignmentHistory(supabase, { shipmentOrderId: shipment.id, actorAuthUserId: access.authUserId });
    candidatesByRole = Object.fromEntries(
      await Promise.all(
        RESOURCE_ASSIGNMENT_ROLES.map(async (role) => [role, await findAssignmentCandidates(supabase, { tenantId: access.tenant.id, role, actorAuthUserId: access.authUserId })] as const),
      ),
    ) as Record<(typeof RESOURCE_ASSIGNMENT_ROLES)[number], Awaited<ReturnType<typeof findAssignmentCandidates>>>;
  } catch (error) {
    if (!(error instanceof ResourceAssignmentQueryError)) {
      throw error;
    }
    return <ErrorState description="Something went wrong loading resource assignments. Please try again." />;
  }
  const currentAssignmentByRole = Object.fromEntries(
    RESOURCE_ASSIGNMENT_ROLES.map((role) => [role, resourceHistory.find((a) => a.role === role && a.isCurrent) ?? null] as const),
  ) as Record<(typeof RESOURCE_ASSIGNMENT_ROLES)[number], (typeof resourceHistory)[number] | null>;

  let milestoneEvents;
  let milestoneProjection;
  let milestoneCodes;
  try {
    milestoneEvents = await getShipmentMilestoneTimeline(supabase, { shipmentOrderId: shipment.id, actorAuthUserId: access.authUserId });
    milestoneProjection = await getShipmentMilestoneProjection(supabase, { shipmentOrderId: shipment.id, actorAuthUserId: access.authUserId });
    milestoneCodes = await listMilestoneCodes(supabase);
  } catch (error) {
    if (!(error instanceof MilestoneManagementQueryError)) {
      throw error;
    }
    return <ErrorState description="Something went wrong loading milestone events. Please try again." />;
  }

  let exceptions;
  try {
    exceptions = await listShipmentExceptions(supabase, shipment.id);
  } catch (error) {
    if (!(error instanceof ExceptionEscalationQueryError)) {
      throw error;
    }
    return <ErrorState description="Something went wrong loading exceptions. Please try again." />;
  }

  let dispatchReadiness = null;
  if (shipment.status === "assigned") {
    try {
      dispatchReadiness = await getDispatchReadiness(supabase, { shipmentOrderId: shipment.id, actorAuthUserId: access.authUserId });
    } catch (error) {
      if (!(error instanceof BasicDispatchQueryError)) {
        throw error;
      }
      return <ErrorState description="Something went wrong loading dispatch readiness. Please try again." />;
    }
  }

  let documentChecklist;
  let documentChecklistCompleteness;
  try {
    documentChecklist = await getShipmentDocumentChecklist(supabase, { shipmentOrderId: shipment.id, actorAuthUserId: access.authUserId });
    documentChecklistCompleteness = await evaluateShipmentDocumentChecklistCompleteness(supabase, { shipmentOrderId: shipment.id, actorAuthUserId: access.authUserId });
  } catch (error) {
    if (!(error instanceof DocumentRequirementQueryError)) {
      throw error;
    }
    return <ErrorState description="Something went wrong loading the document checklist. Please try again." />;
  }

  const { tone, label } = SHIPMENT_ORDER_STATUS_TONE_MAP[shipment.status];
  const consignee = shipment.consigneeSnapshot as { legal_name?: string; contact_name?: string };
  const boundConfirmAction = confirmShipmentOrderAction.bind(null, tenantSlug, shipment.id, shipment.recordVersion);
  const transitionIdempotencyKey = randomUUID();
  const boundTransitionAction = (
    toStatus: TransitionableStatus,
    reason: string,
    evidenceRef: string,
    prevState: ShipmentOrderFormState,
    formData: FormData,
  ) => transitionShipmentOrderAction(tenantSlug, shipment.id, shipment.recordVersion, transitionIdempotencyKey, toStatus, reason, evidenceRef, prevState, formData);
  const nextStatuses = permittedNextStatuses(shipment.status, shipment.heldFromStatus);
  const boundModeProfileAction = (fields: Record<string, string>, prevState: ShipmentOrderFormState, formData: FormData) =>
    setShipmentModeProfileAction(tenantSlug, shipment.id, shipment.mode as ShipmentModeProfileMode, fields, prevState, formData);
  const boundChangeModeAction = (newMode: ShipmentModeProfileMode, prevState: ShipmentOrderFormState, formData: FormData) =>
    changeShipmentModeAction(tenantSlug, shipment.id, shipment.recordVersion, newMode, prevState, formData);
  const boundAssignAction = (role: (typeof RESOURCE_ASSIGNMENT_ROLES)[number]) => assignResourceAction.bind(null, tenantSlug, shipment.id, role);
  const boundReassignAction = (role: (typeof RESOURCE_ASSIGNMENT_ROLES)[number]) => reassignResourceAction.bind(null, tenantSlug, shipment.id, role);
  const boundHoldAction = (role: (typeof RESOURCE_ASSIGNMENT_ROLES)[number]) => holdResourceAssignmentAction.bind(null, tenantSlug, shipment.id, role);
  const boundResumeAction = (role: (typeof RESOURCE_ASSIGNMENT_ROLES)[number]) => resumeResourceAssignmentAction.bind(null, tenantSlug, shipment.id, role);
  const boundUnassignAction = (role: (typeof RESOURCE_ASSIGNMENT_ROLES)[number]) => unassignResourceAction.bind(null, tenantSlug, shipment.id, role);
  const milestoneIdempotencyKey = randomUUID();
  const boundIngestMilestoneEventAction = ingestMilestoneEventAction.bind(null, tenantSlug, shipment.id, milestoneIdempotencyKey);
  const exceptionIdempotencyKey = randomUUID();
  const boundReportExceptionAction = reportExceptionAction.bind(null, tenantSlug, shipment.id, exceptionIdempotencyKey);
  const boundManageExceptionAction = (exceptionId: string, expectedVersion: number) => manageExceptionAction.bind(null, tenantSlug, shipment.id, exceptionId, expectedVersion);
  const dispatchIdempotencyKey = randomUUID();
  const boundDispatchAction = dispatchShipmentOrderAction.bind(null, tenantSlug, shipment.id, shipment.recordVersion, dispatchIdempotencyKey);
  const boundPinDocumentChecklistAction = pinDocumentChecklistAction.bind(null, tenantSlug, shipment.id);
  const boundUploadAndLinkDocumentAction = (checklistItemId: string, documentTypeCode: string) =>
    uploadAndLinkDocumentAction.bind(null, tenantSlug, shipment.id, checklistItemId, documentTypeCode, randomUUID());
  const boundReviewDocumentChecklistItemAction = (checklistItemId: string) => reviewDocumentChecklistItemAction.bind(null, tenantSlug, shipment.id, checklistItemId);

  return (
    <div className="flex flex-col gap-6">
      <div className="flex items-center gap-3">
        <h1 className="text-xl font-semibold text-neutral-900">{shipment.shipmentNumber}</h1>
        <StatusBadge tone={tone} label={label} />
        <Badge tone="neutral">{shipment.mode}</Badge>
      </div>

      <section className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Source lineage</h2>
        <dl className="grid grid-cols-2 gap-x-4 gap-y-1 text-sm">
          <dt className="text-neutral-600">Job Order</dt>
          <dd className="text-neutral-900">
            <a href={`/${tenantSlug}/operations/job-orders/${shipment.jobOrderId}`} className="text-primary underline">
              {shipment.jobOrderId}
            </a>
          </dd>
          <dt className="text-neutral-600">Shipper account</dt>
          <dd className="text-neutral-900">{shipment.shipperAccountId}</dd>
        </dl>
      </section>

      <section className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Route and schedule</h2>
        <dl className="grid grid-cols-2 gap-x-4 gap-y-1 text-sm">
          <dt className="text-neutral-600">Origin</dt>
          <dd className="text-neutral-900">{shipment.origin}</dd>
          <dt className="text-neutral-600">Destination</dt>
          <dd className="text-neutral-900">{shipment.destination}</dd>
          <dt className="text-neutral-600">Planned pickup</dt>
          <dd className="text-neutral-900">{shipment.plannedPickupAt ? new Date(shipment.plannedPickupAt).toLocaleString() : "—"}</dd>
          <dt className="text-neutral-600">Planned delivery</dt>
          <dd className="text-neutral-900">{shipment.plannedDeliveryAt ? new Date(shipment.plannedDeliveryAt).toLocaleString() : "—"}</dd>
        </dl>
      </section>

      <section className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Mode profile</h2>
        <ModeProfileForm action={boundModeProfileAction} mode={shipment.mode as ShipmentModeProfileMode} existingProfile={modeProfile} />
        {shipment.status === "draft" ? (
          <div className="mt-2 border-t border-neutral-200 pt-2">
            <ChangeModeForm action={boundChangeModeAction} currentMode={shipment.mode as ShipmentModeProfileMode} />
          </div>
        ) : null}
      </section>

      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Resource assignments</h2>
        {RESOURCE_ASSIGNMENT_ROLES.map((role) => (
          <ResourceAssignmentPanel
            key={role}
            role={role}
            current={currentAssignmentByRole[role]}
            candidates={candidatesByRole[role]}
            assignAction={boundAssignAction(role)}
            reassignAction={boundReassignAction(role)}
            holdAction={boundHoldAction(role)}
            resumeAction={boundResumeAction(role)}
            unassignAction={boundUnassignAction(role)}
          />
        ))}
        <div className="mt-2 border-t border-neutral-200 pt-2">
          <h3 className="mb-2 text-xs font-semibold uppercase tracking-wide text-neutral-500">History</h3>
          <ResourceAssignmentHistory history={resourceHistory} />
        </div>
      </section>

      <section className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Consignee</h2>
        <dl className="grid grid-cols-2 gap-x-4 gap-y-1 text-sm">
          <dt className="text-neutral-600">Legal name</dt>
          <dd className="text-neutral-900">{consignee.legal_name ?? "—"}</dd>
          <dt className="text-neutral-600">Contact</dt>
          <dd className="text-neutral-900">{consignee.contact_name ?? "—"}</dd>
        </dl>
      </section>

      <section className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Allocation</h2>
        <dl className="grid grid-cols-3 gap-x-4 gap-y-1 text-sm">
          <dt className="text-neutral-600">This shipment (qty)</dt>
          <dd className="text-neutral-900">{shipment.allocatedQuantity ?? "—"}</dd>
          <dt className="text-neutral-600">Job total (qty)</dt>
          <dd className="text-neutral-900">{balance.basisQuantity ?? "—"}</dd>
          <dt className="text-neutral-600">Job remaining (qty)</dt>
          <dd className="text-neutral-900">{balance.remainingQuantity ?? "—"}</dd>
        </dl>
        {shipment.splitReason ? <p className="text-xs text-neutral-500">Split reason: {shipment.splitReason}</p> : null}
      </section>

      {shipment.status === "draft" ? (
        <section className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
          <h2 className="text-sm font-semibold text-neutral-900">Confirm</h2>
          <ConfirmShipmentOrderForm action={boundConfirmAction} />
        </section>
      ) : null}

      {nextStatuses.length > 0 ? (
        <section className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
          <h2 className="text-sm font-semibold text-neutral-900">Transition</h2>
          {shipment.status === "closed" ? (
            <p className="text-xs text-neutral-500">Reopening a closed shipment is a Supreme Admin-only correction (RPD-022).</p>
          ) : null}
          <TransitionShipmentOrderForm action={boundTransitionAction} permittedNextStatuses={nextStatuses} />
        </section>
      ) : null}

      {dispatchReadiness ? (
        <section className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
          <h2 className="text-sm font-semibold text-neutral-900">Dispatch</h2>
          <DispatchPanel readiness={dispatchReadiness} action={boundDispatchAction} />
        </section>
      ) : null}

      <section className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Document checklist</h2>
        <DocumentChecklistPanel
          items={documentChecklist}
          completeness={documentChecklistCompleteness}
          pinAction={boundPinDocumentChecklistAction}
          uploadAction={boundUploadAndLinkDocumentAction}
          reviewAction={boundReviewDocumentChecklistItemAction}
        />
      </section>

      <section className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Status timeline</h2>
        <StatusTimeline history={history} />
      </section>

      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Milestone events</h2>
        {milestoneProjection ? (
          <dl className="grid grid-cols-3 gap-x-4 gap-y-1 text-sm">
            <dt className="text-neutral-600">Last milestone</dt>
            <dd className="text-neutral-900">{milestoneProjection.lastMilestoneCode ?? "—"}</dd>
            <dt className="text-neutral-600">Current ETA</dt>
            <dd className="text-neutral-900">{milestoneProjection.currentEta ? new Date(milestoneProjection.currentEta).toLocaleString() : "—"}</dd>
            <dt className="text-neutral-600">Delayed</dt>
            <dd className="text-neutral-900">{milestoneProjection.isDelayed ? "Yes" : "No"}</dd>
          </dl>
        ) : null}
        <IngestMilestoneEventForm action={boundIngestMilestoneEventAction} milestoneCodes={milestoneCodes} />
        <div className="mt-2 border-t border-neutral-200 pt-2">
          <h3 className="mb-2 text-xs font-semibold uppercase tracking-wide text-neutral-500">Timeline</h3>
          <MilestoneTimeline events={milestoneEvents} />
        </div>
      </section>

      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Exceptions</h2>
        <ReportExceptionForm action={boundReportExceptionAction} />
        <div className="mt-2 border-t border-neutral-200 pt-2">
          <ExceptionList exceptions={exceptions} actionFor={boundManageExceptionAction} />
        </div>
      </section>
    </div>
  );
}
