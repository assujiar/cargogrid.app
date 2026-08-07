import { notFound } from "next/navigation";
import { resolveProcurementAccessForRequest } from "../../../../../lib/portal/resolve-procurement-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { listProcurementApprovalInboxForActor, ProcurementApprovalQueryError, listProcurementApprovalPolicyVersions, listProcurementExceptionRequests } from "../../../../../server/queries/procurement-approval.ts";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";
import { ProcurementApprovalsQueuePanel } from "./approvals-queue-panel.tsx";
import { createProcurementApprovalPolicyAction, publishProcurementApprovalPolicyAction, createProcurementExceptionRequestAction, cancelProcurementExceptionRequestAction } from "./actions.ts";

/**
 * Unified Procurement Approval inbox (PRC-259, CG-S11-PRC-010, Prompt 259 §15:
 * "Unified procurement approval inbox/detail"). Lists every currently-active step
 * across the tenant this actor is eligible to decide right now, filtered to this
 * capability's own 6 governed entity_type values -- app.list_pending_approval_steps_
 * for_actor (PLT-123) is entity-agnostic (the SAME shared engine Commercial's
 * quotation/credit approvals already use, this capability's own migration header) --
 * plus the tenant's governed policy set and its exception/override requests. Deciding
 * happens on the step's own detail page (/[stepId]), which carries the full immutable
 * decision context snapshot.
 */
export default async function ProcurementApprovalsPage({ params }: { params: Promise<{ tenantSlug: string }> }) {
  const { tenantSlug } = await params;
  const access = await resolveProcurementAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();

  let loadFailed = false;
  let inbox: Awaited<ReturnType<typeof listProcurementApprovalInboxForActor>> = [];
  let policies: Awaited<ReturnType<typeof listProcurementApprovalPolicyVersions>> = [];
  let exceptions: Awaited<ReturnType<typeof listProcurementExceptionRequests>> = [];
  try {
    [inbox, policies, exceptions] = await Promise.all([
      listProcurementApprovalInboxForActor(supabase, access.tenant.id, access.authUserId),
      listProcurementApprovalPolicyVersions(supabase, access.tenant.id),
      listProcurementExceptionRequests(supabase, { tenantId: access.tenant.id, actorAuthUserId: access.authUserId, statusFilter: null, limit: 100 }),
    ]);
  } catch (error) {
    if (!(error instanceof ProcurementApprovalQueryError)) throw error;
    loadFailed = true;
  }

  if (loadFailed) {
    return <ErrorState description="Something went wrong loading the procurement approvals workspace. Please try again." />;
  }

  return (
    <div className="flex flex-col gap-6">
      <div>
        <h1 className="text-xl font-semibold text-neutral-900">Procurement Approvals</h1>
        <p className="text-xs text-neutral-500">
          One canonical approval engine (Platform Approval Engine, PLT-123) governs vendor activation, rate approval, vendor selection, and exception/override decisions across
          Procurement -- Procurement stores bindings and immutable decision context here, never a second workflow engine.
        </p>
      </div>

      <ProcurementApprovalsQueuePanel
        tenantSlug={tenantSlug}
        inbox={inbox}
        policies={policies}
        exceptions={exceptions}
        createPolicyAction={createProcurementApprovalPolicyAction.bind(null, tenantSlug)}
        publishPolicyAction={publishProcurementApprovalPolicyAction.bind(null, tenantSlug)}
        createExceptionAction={createProcurementExceptionRequestAction.bind(null, tenantSlug)}
        cancelExceptionAction={cancelProcurementExceptionRequestAction.bind(null, tenantSlug)}
      />
    </div>
  );
}
