import { notFound } from "next/navigation";
import { resolveHrisAccessForRequest } from "../../../../../../lib/portal/resolve-hris-access.server.ts";
import { createSupabaseServerClient } from "../../../../../../lib/supabase/server.ts";
import {
  getEmployeeProfile,
  listEmployeeEmergencyContacts,
  getEmployeeLifecycleHistory,
  listEmployeeDuplicateCandidates,
  EmployeeQueryError,
} from "../../../../../../server/queries/employee.ts";
import { parseFile, type File as HrisFile } from "../../../../../../server/contracts/document/document.ts";
import { parseEmployeeChangeRequest, type EmployeeChangeRequest } from "../../../../../../server/contracts/employee/employee.ts";
import { ErrorState } from "../../../../../../components/ui/error-state.tsx";
import { PermissionState } from "../../../../../../components/ui/permission-state.tsx";
import { EmployeeDetailPanel } from "./employee-detail-panel.tsx";
import {
  updateEmployeeDraftAction,
  submitEmployeeForApprovalAction,
  decideEmployeeApprovalAction,
  activateEmployeeAction,
  linkEmployeeUserAction,
  startEmployeeLeaveAction,
  endEmployeeLeaveAction,
  suspendEmployeeAction,
  reactivateEmployeeAction,
  terminateEmployeeAction,
  archiveEmployeeProfileAction,
  transferEmployeeAction,
  addEmployeeEmergencyContactAction,
  removeEmployeeEmergencyContactAction,
  decideEmployeeDuplicateCandidateAction,
  decideEmployeeChangeRequestAction,
} from "../actions.ts";

/**
 * Employee detail (HRT-274, CG-S12-HRT-002): personal/employment/organization/
 * documents/history tabs (section 15), lifecycle actions contextual to the current
 * status, masked sensitive fields (server-computed personalDataMasked, never a
 * client-side guess). Documents reuse app.files directly (record_type='employee') --
 * a plain Supabase read here, mirroring server/queries/document.ts's own disclosed
 * "record-scoped filtering left to the caller" shape.
 */
export default async function EmployeeDetailPage({ params }: { params: Promise<{ tenantSlug: string; masterRecordId: string }> }) {
  const { tenantSlug, masterRecordId } = await params;
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();

  let denied = false;
  let notFoundError = false;
  let loadFailed = false;
  let profile: Awaited<ReturnType<typeof getEmployeeProfile>> | null = null;
  let contacts: Awaited<ReturnType<typeof listEmployeeEmergencyContacts>> = [];
  let history: Awaited<ReturnType<typeof getEmployeeLifecycleHistory>> = [];
  let duplicates: Awaited<ReturnType<typeof listEmployeeDuplicateCandidates>> = [];
  let files: HrisFile[] = [];
  let changeRequests: EmployeeChangeRequest[] = [];
  let orgUnits: { id: string; name: string; unitType: string }[] = [];

  try {
    profile = await getEmployeeProfile(supabase, masterRecordId, access.authUserId);
    [contacts, history, duplicates] = await Promise.all([
      listEmployeeEmergencyContacts(supabase, masterRecordId, access.authUserId),
      getEmployeeLifecycleHistory(supabase, masterRecordId, access.authUserId),
      listEmployeeDuplicateCandidates(supabase, masterRecordId, access.authUserId),
    ]);
    const { data: fileRows, error: fileError } = await supabase.from("files").select("*").eq("tenant_id", access.tenant.id).eq("record_type", "employee").eq("record_id", masterRecordId);
    if (fileError) throw new EmployeeQueryError(fileError.message);
    files = (fileRows ?? []).map((row) => parseFile(row as Record<string, unknown>));

    // Direct table read (RLS-scoped, same shape as the files read above) -- no
    // dedicated read RPC exists for change requests; app.employee_change_requests'
    // own tenant-scoped RLS SELECT policy already governs this correctly.
    const { data: changeRequestRows, error: changeRequestError } = await supabase
      .from("employee_change_requests")
      .select("*")
      .eq("master_record_id", masterRecordId)
      .order("created_at", { ascending: false });
    if (changeRequestError) throw new EmployeeQueryError(changeRequestError.message);
    changeRequests = (changeRequestRows ?? []).map((row) => parseEmployeeChangeRequest(row as Record<string, unknown>));

    const { data: orgUnitRows, error: orgUnitError } = await supabase.from("org_units").select("id, name, unit_type").eq("tenant_id", access.tenant.id).eq("status", "active");
    if (orgUnitError) throw new EmployeeQueryError(orgUnitError.message);
    orgUnits = (orgUnitRows ?? []).map((row) => ({ id: String(row.id), name: String(row.name), unitType: String(row.unit_type) }));
  } catch (error) {
    if (!(error instanceof EmployeeQueryError)) throw error;
    if (error.message.startsWith("insufficient_authority")) denied = true;
    else if (error.message.startsWith("employee_not_found")) notFoundError = true;
    else loadFailed = true;
  }

  if (notFoundError) {
    notFound();
  }
  if (denied) {
    return <PermissionState description="You don't have HR permission to view this employee's profile." />;
  }
  if (loadFailed || !profile) {
    return <ErrorState description="Something went wrong loading this employee's profile. Please try again." />;
  }

  return (
    <EmployeeDetailPanel
      tenantSlug={tenantSlug}
      profile={profile}
      contacts={contacts}
      history={history}
      duplicates={duplicates}
      files={files}
      changeRequests={changeRequests}
      orgUnits={orgUnits}
      updateDraftAction={updateEmployeeDraftAction.bind(null, tenantSlug, masterRecordId, profile.recordVersion)}
      submitAction={submitEmployeeForApprovalAction.bind(null, tenantSlug, masterRecordId, profile.recordVersion)}
      decideApprovalAction={decideEmployeeApprovalAction.bind(null, tenantSlug, masterRecordId, profile.recordVersion)}
      activateAction={activateEmployeeAction.bind(null, tenantSlug, masterRecordId, profile.recordVersion)}
      linkUserAction={linkEmployeeUserAction.bind(null, tenantSlug, masterRecordId, profile.recordVersion)}
      startLeaveAction={startEmployeeLeaveAction.bind(null, tenantSlug, masterRecordId, profile.recordVersion)}
      endLeaveAction={endEmployeeLeaveAction.bind(null, tenantSlug, masterRecordId, profile.recordVersion)}
      suspendAction={suspendEmployeeAction.bind(null, tenantSlug, masterRecordId, profile.recordVersion)}
      reactivateAction={reactivateEmployeeAction.bind(null, tenantSlug, masterRecordId, profile.recordVersion)}
      terminateAction={terminateEmployeeAction.bind(null, tenantSlug, masterRecordId, profile.recordVersion)}
      archiveAction={archiveEmployeeProfileAction.bind(null, tenantSlug, masterRecordId, profile.recordVersion)}
      transferAction={transferEmployeeAction.bind(null, tenantSlug, masterRecordId, profile.recordVersion)}
      addContactAction={addEmployeeEmergencyContactAction.bind(null, tenantSlug, masterRecordId)}
      removeContactAction={(contactId: string, expectedVersion: number) => removeEmployeeEmergencyContactAction.bind(null, tenantSlug, masterRecordId, contactId, expectedVersion)}
      decideDuplicateAction={(candidateId: string, expectedVersion: number) => decideEmployeeDuplicateCandidateAction.bind(null, tenantSlug, masterRecordId, candidateId, expectedVersion)}
      decideChangeRequestAction={(requestId: string, expectedVersion: number) => decideEmployeeChangeRequestAction.bind(null, tenantSlug, masterRecordId, requestId, expectedVersion)}
    />
  );
}
