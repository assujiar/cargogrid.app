import { notFound } from "next/navigation";
import { resolveHrisAccessForRequest } from "../../../../../../lib/portal/resolve-hris-access.server.ts";
import { createSupabaseServerClient } from "../../../../../../lib/supabase/server.ts";
import { listMyPayslips, listMyPayrollReimbursementRequests, listMyPayrollLoans, PayrollQueryError } from "../../../../../../server/queries/payroll.ts";
import { ErrorState } from "../../../../../../components/ui/error-state.tsx";
import { MyPayrollPanel } from "./my-payroll-panel.tsx";
import { createMyReimbursementRequestAction, submitMyReimbursementRequestAction, cancelMyReimbursementRequestAction } from "./actions.ts";

/**
 * Self-service payslip and benefit view (HRT-282, CG-S12-HRT-010). Every
 * read here resolves the caller's own employee_id server-side via the RPC's
 * own app.get_self_employee call -- no employee-id parameter exists on any
 * of the my_* RPCs this page calls, structurally impossible to spoof.
 */
export default async function MyPayrollPage({ params }: { params: Promise<{ tenantSlug: string }> }) {
  const { tenantSlug } = await params;
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();
  let loadFailed = false;
  let payslips: Awaited<ReturnType<typeof listMyPayslips>> = [];
  let reimbursements: Awaited<ReturnType<typeof listMyPayrollReimbursementRequests>> = [];
  let loans: Awaited<ReturnType<typeof listMyPayrollLoans>> = [];
  try {
    [payslips, reimbursements, loans] = await Promise.all([
      listMyPayslips(supabase, access.tenant.id, access.authUserId),
      listMyPayrollReimbursementRequests(supabase, access.tenant.id, access.authUserId),
      listMyPayrollLoans(supabase, access.tenant.id, access.authUserId),
    ]);
  } catch (error) {
    if (!(error instanceof PayrollQueryError)) throw error;
    loadFailed = true;
  }

  if (loadFailed) {
    return <ErrorState description="Something went wrong loading your payroll information. Please try again." />;
  }

  return (
    <MyPayrollPanel
      payslips={payslips}
      reimbursements={reimbursements}
      loans={loans}
      createMyReimbursementRequestAction={createMyReimbursementRequestAction.bind(null, tenantSlug)}
      submitMyReimbursementRequestAction={(requestId: string, expectedVersion: number) => submitMyReimbursementRequestAction.bind(null, tenantSlug, requestId, expectedVersion)}
      cancelMyReimbursementRequestAction={(requestId: string, expectedVersion: number) => cancelMyReimbursementRequestAction.bind(null, tenantSlug, requestId, expectedVersion)}
    />
  );
}
