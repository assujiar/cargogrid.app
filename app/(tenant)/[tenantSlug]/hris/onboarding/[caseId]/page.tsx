import { notFound } from "next/navigation";
import { resolveHrisAccessForRequest } from "../../../../../../lib/portal/resolve-hris-access.server.ts";
import { createSupabaseServerClient } from "../../../../../../lib/supabase/server.ts";
import { getOnboardingCase, listOnboardingCaseTasks, getOnboardingCaseApprovalTimeline, OnboardingQueryError } from "../../../../../../server/queries/onboarding.ts";
import { getEmployeeProfile, EmployeeQueryError } from "../../../../../../server/queries/employee.ts";
import { ErrorState } from "../../../../../../components/ui/error-state.tsx";
import { PermissionState } from "../../../../../../components/ui/permission-state.tsx";
import { CaseDetailPanel } from "./case-detail-panel.tsx";
import {
  assignOnboardingTaskAction,
  completeOnboardingTaskAction,
  waiveOnboardingTaskAction,
  reopenOnboardingTaskAction,
  requestAccessProvisioningAction,
  requestAccessRevocationAction,
  submitFinalizeApprovalAction,
  decideFinalizeApprovalAction,
  cancelOnboardingCaseAction,
  rehireEmployeeAction,
} from "./actions.ts";

/**
 * Onboarding/offboarding case workspace (HRT-277, CG-S12-HRT-005, section 15):
 * checklist/dependencies, due/blocked state, evidence, access/asset preview, and
 * approval timeline -- the role-based case workspace this whole prompt exists to
 * deliver.
 */
export default async function OnboardingCaseDetailPage({ params }: { params: Promise<{ tenantSlug: string; caseId: string }> }) {
  const { tenantSlug, caseId } = await params;
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();

  let denied = false;
  let loadFailed = false;
  let notFoundFlag = false;
  let caseDetail: Awaited<ReturnType<typeof getOnboardingCase>> | null = null;
  let tasks: Awaited<ReturnType<typeof listOnboardingCaseTasks>> = [];
  let timeline: Awaited<ReturnType<typeof getOnboardingCaseApprovalTimeline>> = [];

  try {
    [caseDetail, tasks, timeline] = await Promise.all([
      getOnboardingCase(supabase, caseId, access.authUserId),
      listOnboardingCaseTasks(supabase, caseId, access.authUserId),
      getOnboardingCaseApprovalTimeline(supabase, caseId, access.authUserId),
    ]);
  } catch (error) {
    if (!(error instanceof OnboardingQueryError)) throw error;
    if (error.message.startsWith("insufficient_authority")) denied = true;
    else if (error.message.startsWith("case_not_found")) notFoundFlag = true;
    else loadFailed = true;
  }

  if (notFoundFlag) {
    notFound();
  }
  if (denied) {
    return <PermissionState description="You don't have HR permission to view this case." />;
  }
  if (loadFailed || !caseDetail) {
    return <ErrorState description="Something went wrong loading this case. Please try again." />;
  }

  // Rehire eligibility (HRT-277 decision 2, section 22 "rehire linked to a
  // historical employee") -- only relevant for a terminated linked employee.
  // A failure loading the employee profile here degrades gracefully (the
  // rehire action is simply not offered) rather than failing the whole page.
  let employeeLifecycleStatus: string | null = null;
  let employeeRecordVersion: number | null = null;
  if (caseDetail.employeeMasterRecordId) {
    try {
      const employee = await getEmployeeProfile(supabase, caseDetail.employeeMasterRecordId, access.authUserId);
      employeeLifecycleStatus = employee.lifecycleStatus;
      employeeRecordVersion = employee.recordVersion;
    } catch (error) {
      if (!(error instanceof EmployeeQueryError)) throw error;
    }
  }

  return (
    <CaseDetailPanel
      tenantSlug={tenantSlug}
      caseDetail={caseDetail}
      tasks={tasks}
      timeline={timeline}
      employeeLifecycleStatus={employeeLifecycleStatus}
      assignTaskAction={(taskId: string, expectedVersion: number) => assignOnboardingTaskAction.bind(null, tenantSlug, caseId, taskId, expectedVersion)}
      completeTaskAction={(taskId: string, expectedVersion: number) => completeOnboardingTaskAction.bind(null, tenantSlug, caseId, taskId, expectedVersion)}
      waiveTaskAction={(taskId: string, expectedVersion: number) => waiveOnboardingTaskAction.bind(null, tenantSlug, caseId, taskId, expectedVersion)}
      reopenTaskAction={(taskId: string, expectedVersion: number) => reopenOnboardingTaskAction.bind(null, tenantSlug, caseId, taskId, expectedVersion)}
      requestProvisioningAction={(taskId: string, expectedVersion: number) => requestAccessProvisioningAction.bind(null, tenantSlug, caseId, taskId, expectedVersion)}
      requestRevocationAction={(taskId: string, expectedVersion: number) => requestAccessRevocationAction.bind(null, tenantSlug, caseId, taskId, expectedVersion)}
      submitFinalizeApprovalAction={submitFinalizeApprovalAction.bind(null, tenantSlug, caseId, caseDetail.recordVersion)}
      decideFinalizeApprovalAction={(requestStepId: string, decision: "approved" | "rejected") => decideFinalizeApprovalAction.bind(null, tenantSlug, caseId, requestStepId, decision)}
      cancelCaseAction={cancelOnboardingCaseAction.bind(null, tenantSlug, caseId, caseDetail.recordVersion)}
      rehireEmployeeAction={
        employeeRecordVersion != null && caseDetail.employeeMasterRecordId
          ? rehireEmployeeAction.bind(null, tenantSlug, caseId, caseDetail.employeeMasterRecordId, employeeRecordVersion)
          : null
      }
    />
  );
}
