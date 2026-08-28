import { notFound } from "next/navigation";
import { resolveHrisAccessForRequest } from "../../../../../lib/portal/resolve-hris-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import {
  listPayrollPeriods,
  listPayrollComponents,
  listPayrollRuns,
  listPayrollRunEmployeeResults,
  listPayrollExceptions,
  listPayrollReimbursementRequests,
  searchPayrollFinanceHandoffsPendingAcknowledgement,
  listMyPendingPayrollApprovalSteps,
  PayrollQueryError,
} from "../../../../../server/queries/payroll.ts";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";
import { PayrollAdminPanel } from "./payroll-admin-panel.tsx";
import {
  createPayrollPeriodAction,
  freezePayrollPeriodInputsAction,
  reopenPayrollPeriodInputsAction,
  createPayrollComponentAction,
  assignPayrollComponentAction,
  decidePayrollReimbursementAction,
  issuePayrollLoanAction,
  createPayrollRunAction,
  calculatePayrollRunAction,
  resolvePayrollExceptionAction,
  waivePayrollExceptionAction,
  submitPayrollRunForFinalizationAction,
  finalizePayrollRunAction,
  cancelPayrollRunAction,
  requestPayrollRunCalculationCancellationAction,
  generateFinancePayrollHandoffAction,
  acknowledgeFinancePayrollHandoffAction,
} from "./actions.ts";

/**
 * HR/Payroll-approver workspace (HRT-282, CG-S12-HRT-010). The single most
 * sensitive and highest-scope Phase 7 capability so far -- every read here
 * is gated on HRS:View payroll specifically, never plain HRS:View and
 * never a manager-of-employee predicate (decision 5). Finalization routes
 * through PLT-123 (decision 6) -- the "my pending step for this run" cross-
 * reference below is a client-side join of two already-authorized reads
 * (this run's own approval_request_id, and this actor's own pending PLT-123
 * steps), never a new RPC.
 */
export default async function PayrollAdminPage({ params }: { params: Promise<{ tenantSlug: string }> }) {
  const { tenantSlug } = await params;
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();
  let loadFailed = false;
  let periods: Awaited<ReturnType<typeof listPayrollPeriods>> = [];
  let components: Awaited<ReturnType<typeof listPayrollComponents>> = [];
  let runs: Awaited<ReturnType<typeof listPayrollRuns>> = [];
  let pendingReimbursements: Awaited<ReturnType<typeof listPayrollReimbursementRequests>> = [];
  let pendingHandoffs: Awaited<ReturnType<typeof searchPayrollFinanceHandoffsPendingAcknowledgement>> = [];
  let myPendingSteps: Awaited<ReturnType<typeof listMyPendingPayrollApprovalSteps>> = [];

  try {
    [periods, components, runs, pendingReimbursements, myPendingSteps] = await Promise.all([
      listPayrollPeriods(supabase, access.tenant.id, access.authUserId, { limit: 50 }),
      listPayrollComponents(supabase, access.tenant.id, access.authUserId),
      listPayrollRuns(supabase, access.tenant.id, access.authUserId, {}),
      listPayrollReimbursementRequests(supabase, access.tenant.id, access.authUserId, { status: "pending_approval", limit: 50 }),
      listMyPendingPayrollApprovalSteps(supabase, access.tenant.id, access.authUserId),
    ]);
    // Finance handoff discovery is FIN:View-gated -- a Payroll-only actor
    // legitimately gets insufficient_authority here; that is not a page
    // load failure, just an empty section for this actor.
    try {
      pendingHandoffs = await searchPayrollFinanceHandoffsPendingAcknowledgement(supabase, access.tenant.id, access.authUserId);
    } catch {
      pendingHandoffs = [];
    }
  } catch (error) {
    if (!(error instanceof PayrollQueryError)) throw error;
    loadFailed = true;
  }

  if (loadFailed) {
    return <ErrorState description="Something went wrong loading the payroll workspace. Please try again." />;
  }

  const exceptionsByRun = await Promise.all(
    runs.filter((r) => r.exceptionCount > 0).map((r) => listPayrollExceptions(supabase, r.id, access.authUserId, "open")),
  );
  const openExceptions = exceptionsByRun.flat();

  const resultsByFinalizedRun = await Promise.all(
    runs.filter((r) => r.status === "finalized").map(async (r) => ({ run: r, results: await listPayrollRunEmployeeResults(supabase, r.id, access.authUserId) })),
  );

  const myStepIdByApprovalRequestId = new Map(myPendingSteps.map((s) => [s.requestId, s.id]));

  return (
    <PayrollAdminPanel
      periods={periods}
      components={components}
      runs={runs}
      openExceptions={openExceptions}
      pendingReimbursements={pendingReimbursements}
      pendingHandoffs={pendingHandoffs}
      finalizedRunTotals={resultsByFinalizedRun.map(({ run, results }) => ({
        runId: run.id,
        netPayTotal: results.reduce((sum, r) => sum + Number(r.netPay), 0),
        currency: run.currency,
      }))}
      myStepIdByApprovalRequestId={Object.fromEntries(myStepIdByApprovalRequestId)}
      createPayrollPeriodAction={createPayrollPeriodAction.bind(null, tenantSlug)}
      freezePayrollPeriodInputsAction={(periodId: string, expectedVersion: number) => freezePayrollPeriodInputsAction.bind(null, tenantSlug, periodId, expectedVersion)}
      reopenPayrollPeriodInputsAction={(periodId: string, expectedVersion: number) => reopenPayrollPeriodInputsAction.bind(null, tenantSlug, periodId, expectedVersion)}
      createPayrollComponentAction={createPayrollComponentAction.bind(null, tenantSlug)}
      assignPayrollComponentAction={assignPayrollComponentAction.bind(null, tenantSlug)}
      decidePayrollReimbursementAction={(requestId: string, expectedVersion: number, decision: "approve" | "reject") =>
        decidePayrollReimbursementAction.bind(null, tenantSlug, requestId, expectedVersion, decision)
      }
      issuePayrollLoanAction={issuePayrollLoanAction.bind(null, tenantSlug)}
      createPayrollRunAction={(periodId: string) => createPayrollRunAction.bind(null, tenantSlug, periodId)}
      calculatePayrollRunAction={(runId: string, expectedVersion: number) => calculatePayrollRunAction.bind(null, tenantSlug, runId, expectedVersion)}
      resolvePayrollExceptionAction={(exceptionId: string) => resolvePayrollExceptionAction.bind(null, tenantSlug, exceptionId)}
      waivePayrollExceptionAction={(exceptionId: string) => waivePayrollExceptionAction.bind(null, tenantSlug, exceptionId)}
      submitPayrollRunForFinalizationAction={(runId: string, expectedVersion: number) => submitPayrollRunForFinalizationAction.bind(null, tenantSlug, runId, expectedVersion)}
      finalizePayrollRunAction={(requestStepId: string, decision: "approved" | "rejected") => finalizePayrollRunAction.bind(null, tenantSlug, requestStepId, decision)}
      cancelPayrollRunAction={(runId: string, expectedVersion: number) => cancelPayrollRunAction.bind(null, tenantSlug, runId, expectedVersion)}
      requestPayrollRunCalculationCancellationAction={(runId: string) => requestPayrollRunCalculationCancellationAction.bind(null, tenantSlug, runId)}
      generateFinancePayrollHandoffAction={(runId: string) => generateFinancePayrollHandoffAction.bind(null, tenantSlug, runId)}
      acknowledgeFinancePayrollHandoffAction={(batchId: string, expectedVersion: number) => acknowledgeFinancePayrollHandoffAction.bind(null, tenantSlug, batchId, expectedVersion)}
    />
  );
}
