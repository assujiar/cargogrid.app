import { notFound } from "next/navigation";
import { resolveProcurementAccessForRequest } from "../../../../../../lib/portal/resolve-procurement-access.server.ts";
import { createSupabaseServerClient } from "../../../../../../lib/supabase/server.ts";
import { getApprovalRequestHistory, listPendingApprovalStepsForActor } from "../../../../../../server/queries/approval.ts";
import { getProcurementApprovalContextSnapshot, ProcurementApprovalQueryError, toApprovalQueryRpcClient } from "../../../../../../server/queries/procurement-approval.ts";
import { PROCUREMENT_APPROVAL_ENTITY_TYPES, type ProcurementApprovalEntityType } from "../../../../../../server/contracts/procurement-approval/procurement-approval.ts";
import { ErrorState } from "../../../../../../components/ui/error-state.tsx";
import { ProcurementApprovalDecisionPanel } from "./approval-decision-panel.tsx";
import { decideProcurementApprovalStepAction } from "../actions.ts";

/**
 * Procurement Approval detail (PRC-259, CG-S11-PRC-010, Prompt 259 §15). Carries the
 * full immutable decision context snapshot (source/value/risk/compliance signals at
 * the moment routing began), the complete step-by-step decision history, and the
 * decision form when this actor is currently eligible to decide the active step.
 */
export default async function ProcurementApprovalStepDetailPage({ params }: { params: Promise<{ tenantSlug: string; stepId: string }> }) {
  const { tenantSlug, stepId } = await params;
  const access = await resolveProcurementAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();

  const { data: stepRow, error: stepError } = await supabase.from("approval_request_steps").select("*").eq("id", stepId).maybeSingle();
  if (stepError) {
    return <ErrorState description="Something went wrong loading this approval step. Please try again." />;
  }
  if (!stepRow) {
    notFound();
  }

  const { data: requestRow, error: requestError } = await supabase.from("approval_requests").select("*").eq("id", stepRow.request_id).maybeSingle();
  if (requestError || !requestRow) {
    return <ErrorState description="Something went wrong loading the bound approval request. Please try again." />;
  }
  if (!(PROCUREMENT_APPROVAL_ENTITY_TYPES as readonly string[]).includes(requestRow.entity_type)) {
    // Not a Procurement-governed request (e.g. a Commercial quotation approval) --
    // this detail page is not the right surface for it.
    notFound();
  }
  const entityType = requestRow.entity_type as ProcurementApprovalEntityType;

  let loadFailed = false;
  let snapshot: Awaited<ReturnType<typeof getProcurementApprovalContextSnapshot>> | null = null;
  let history: Awaited<ReturnType<typeof getApprovalRequestHistory>> = [];
  let pendingStepIds: string[] = [];
  try {
    const approvalClient = toApprovalQueryRpcClient(supabase);
    [snapshot, history] = await Promise.all([
      getProcurementApprovalContextSnapshot(supabase, { approvalRequestId: requestRow.id, actorAuthUserId: access.authUserId }),
      getApprovalRequestHistory(approvalClient, { requestId: requestRow.id, actorAuthUserId: access.authUserId }),
    ]);
    const pendingSteps = await listPendingApprovalStepsForActor(approvalClient, { tenantId: access.tenant.id, actorAuthUserId: access.authUserId });
    pendingStepIds = pendingSteps.filter((step) => step.requestId === requestRow.id).map((step) => step.id);
  } catch (error) {
    if (!(error instanceof ProcurementApprovalQueryError)) throw error;
    loadFailed = true;
  }

  if (loadFailed || !snapshot) {
    return <ErrorState description="Something went wrong loading this approval's decision context. Please try again." />;
  }

  const canDecide = stepRow.status === "active" && requestRow.status === "pending" && pendingStepIds.includes(stepId);

  return (
    <ProcurementApprovalDecisionPanel
      tenantSlug={tenantSlug}
      stepOrder={stepRow.step_order}
      stepStatus={stepRow.status}
      requestId={requestRow.id}
      requestStatus={requestRow.status}
      entityType={entityType}
      snapshot={snapshot}
      history={history}
      canDecide={canDecide}
      decideAction={decideProcurementApprovalStepAction.bind(null, tenantSlug, stepId, entityType)}
    />
  );
}
