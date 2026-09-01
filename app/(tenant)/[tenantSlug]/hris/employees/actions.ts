"use server";

/**
 * Employee Master Server Actions (HRT-274, CG-S12-HRT-002). Mirrors
 * app/(tenant)/[tenantSlug]/procurement/vendors/actions.ts's own shape: resolve
 * portal access, call the typed mutation wrapper, translate a known mutation error
 * into a plain-language message, revalidate the affected path(s).
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { resolveHrisAccessForRequest } from "../../../../../lib/portal/resolve-hris-access.server.ts";
import {
  createEmployeeDraft,
  updateEmployeeDraft,
  submitEmployeeForApproval,
  decideEmployeeApproval,
  activateEmployee,
  linkEmployeeUser,
  startEmployeeLeave,
  endEmployeeLeave,
  suspendEmployee,
  reactivateEmployee,
  terminateEmployee,
  archiveEmployeeProfile,
  transferEmployee,
  addEmployeeEmergencyContact,
  updateEmployeeEmergencyContact,
  removeEmployeeEmergencyContact,
  flagEmployeeDuplicateCandidate,
  decideEmployeeDuplicateCandidate,
  decideEmployeeChangeRequest,
  reactivateUserAfterRehire,
  initiateEmployeeDocumentUpload,
  EmployeeMutationError,
} from "../../../../../server/mutations/employee.ts";
import type { EmployeeReviewDecision, EmploymentType } from "../../../../../server/contracts/employee/employee.ts";

export interface EmployeeActionState {
  readonly error: string | null;
}

const OK: EmployeeActionState = { error: null };
const NO_ACCESS: EmployeeActionState = { error: "You don't have access to this organization's HRIS workspace." };

async function requireAccess(tenantSlug: string) {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return null;
  return access;
}

function detailPath(tenantSlug: string, masterRecordId: string): string {
  return `/${tenantSlug}/hris/employees/${masterRecordId}`;
}

export async function createEmployeeDraftAction(tenantSlug: string, _prevState: EmployeeActionState, formData: FormData): Promise<EmployeeActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const fullName = String(formData.get("fullName") ?? "").trim();
  const employmentType = String(formData.get("employmentType") ?? "") as EmploymentType;
  const workEmail = String(formData.get("workEmail") ?? "").trim() || null;
  const hireDate = String(formData.get("hireDate") ?? "").trim() || null;
  const idempotencyKey = String(formData.get("idempotencyKey") ?? "").trim() || null;

  const supabase = await createSupabaseServerClient();
  let masterRecordId: string;
  try {
    const result = await createEmployeeDraft(supabase, {
      tenantId: access.tenant.id,
      fullName,
      employmentType,
      workEmail,
      personalEmail: null,
      personalPhone: null,
      nationalIdNumber: null,
      dateOfBirth: null,
      gender: null,
      hireDate,
      companyOrgUnitId: null,
      branchOrgUnitId: null,
      departmentOrgUnitId: null,
      positionTitle: null,
      managerEmployeeId: null,
      userId: null,
      employeeNumber: null,
      intakeSource: "hr_created",
      idempotencyKey,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
    masterRecordId = result.masterRecordId;
  } catch (error) {
    if (error instanceof EmployeeMutationError) return { error: `Could not create this employee draft: ${error.message}` };
    throw error;
  }

  revalidatePath(`/${tenantSlug}/hris/employees`);
  revalidatePath(detailPath(tenantSlug, masterRecordId));
  return OK;
}

type LifecycleMutation = (client: Awaited<ReturnType<typeof createSupabaseServerClient>>, input: never) => Promise<unknown>;

async function runLifecycleAction(
  tenantSlug: string,
  masterRecordId: string,
  mutation: LifecycleMutation,
  input: Record<string, unknown>,
  failureVerb: string,
): Promise<EmployeeActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const supabase = await createSupabaseServerClient();
  try {
    await mutation(supabase, { ...input, actorAuthUserId: access.authUserId, actorLabel: access.authUserId } as never);
  } catch (error) {
    if (error instanceof EmployeeMutationError) return { error: `Could not ${failureVerb}: ${error.message}` };
    throw error;
  }

  revalidatePath(detailPath(tenantSlug, masterRecordId));
  revalidatePath(`/${tenantSlug}/hris/employees`);
  return OK;
}

export async function updateEmployeeDraftAction(
  tenantSlug: string,
  masterRecordId: string,
  expectedVersion: number,
  _prevState: EmployeeActionState,
  formData: FormData,
): Promise<EmployeeActionState> {
  const fullName = String(formData.get("fullName") ?? "").trim();
  const employmentType = String(formData.get("employmentType") ?? "") as EmploymentType;
  const workEmail = String(formData.get("workEmail") ?? "").trim() || null;
  const personalEmail = String(formData.get("personalEmail") ?? "").trim() || null;
  const personalPhone = String(formData.get("personalPhone") ?? "").trim() || null;
  const nationalIdNumber = String(formData.get("nationalIdNumber") ?? "").trim() || null;
  const dateOfBirth = String(formData.get("dateOfBirth") ?? "").trim() || null;
  const gender = String(formData.get("gender") ?? "").trim() || null;
  const hireDate = String(formData.get("hireDate") ?? "").trim() || null;
  const probationEndDate = String(formData.get("probationEndDate") ?? "").trim() || null;
  const companyOrgUnitId = String(formData.get("companyOrgUnitId") ?? "").trim() || null;
  const branchOrgUnitId = String(formData.get("branchOrgUnitId") ?? "").trim() || null;
  const departmentOrgUnitId = String(formData.get("departmentOrgUnitId") ?? "").trim() || null;
  const positionTitle = String(formData.get("positionTitle") ?? "").trim() || null;
  const managerEmployeeId = String(formData.get("managerEmployeeId") ?? "").trim() || null;

  return runLifecycleAction(
    tenantSlug,
    masterRecordId,
    updateEmployeeDraft as LifecycleMutation,
    {
      masterRecordId,
      expectedVersion,
      fullName,
      employmentType,
      workEmail,
      personalEmail,
      personalPhone,
      nationalIdNumber,
      dateOfBirth,
      gender,
      hireDate,
      probationEndDate,
      companyOrgUnitId,
      branchOrgUnitId,
      departmentOrgUnitId,
      positionTitle,
      managerEmployeeId,
    },
    "save these changes",
  );
}

export async function submitEmployeeForApprovalAction(tenantSlug: string, masterRecordId: string, expectedVersion: number, _prevState: EmployeeActionState, _formData: FormData) {
  return runLifecycleAction(tenantSlug, masterRecordId, submitEmployeeForApproval as LifecycleMutation, { masterRecordId, expectedVersion }, "submit this employee profile for approval");
}

export async function decideEmployeeApprovalAction(tenantSlug: string, masterRecordId: string, expectedVersion: number, _prevState: EmployeeActionState, formData: FormData) {
  const decision = String(formData.get("decision") ?? "") as EmployeeReviewDecision;
  const reason = String(formData.get("reason") ?? "").trim() || null;
  return runLifecycleAction(tenantSlug, masterRecordId, decideEmployeeApproval as LifecycleMutation, { masterRecordId, expectedVersion, decision, reason }, "record this approval decision");
}

export async function activateEmployeeAction(tenantSlug: string, masterRecordId: string, expectedVersion: number, _prevState: EmployeeActionState, _formData: FormData) {
  return runLifecycleAction(tenantSlug, masterRecordId, activateEmployee as LifecycleMutation, { masterRecordId, expectedVersion }, "activate this employee");
}

export async function linkEmployeeUserAction(tenantSlug: string, masterRecordId: string, expectedVersion: number, _prevState: EmployeeActionState, formData: FormData) {
  const userId = String(formData.get("userId") ?? "").trim();
  return runLifecycleAction(tenantSlug, masterRecordId, linkEmployeeUser as LifecycleMutation, { masterRecordId, expectedVersion, userId }, "link this Platform user");
}

export async function startEmployeeLeaveAction(tenantSlug: string, masterRecordId: string, expectedVersion: number, _prevState: EmployeeActionState, formData: FormData) {
  const reason = String(formData.get("reason") ?? "").trim() || null;
  return runLifecycleAction(tenantSlug, masterRecordId, startEmployeeLeave as LifecycleMutation, { masterRecordId, expectedVersion, reason }, "start leave for this employee");
}

export async function endEmployeeLeaveAction(tenantSlug: string, masterRecordId: string, expectedVersion: number, _prevState: EmployeeActionState, _formData: FormData) {
  return runLifecycleAction(tenantSlug, masterRecordId, endEmployeeLeave as LifecycleMutation, { masterRecordId, expectedVersion }, "end leave for this employee");
}

export async function suspendEmployeeAction(tenantSlug: string, masterRecordId: string, expectedVersion: number, _prevState: EmployeeActionState, formData: FormData) {
  const reason = String(formData.get("reason") ?? "").trim();
  return runLifecycleAction(tenantSlug, masterRecordId, suspendEmployee as LifecycleMutation, { masterRecordId, expectedVersion, reason }, "suspend this employee");
}

export async function reactivateEmployeeAction(tenantSlug: string, masterRecordId: string, expectedVersion: number, _prevState: EmployeeActionState, _formData: FormData) {
  return runLifecycleAction(tenantSlug, masterRecordId, reactivateEmployee as LifecycleMutation, { masterRecordId, expectedVersion }, "reactivate this employee");
}

export async function terminateEmployeeAction(tenantSlug: string, masterRecordId: string, expectedVersion: number, _prevState: EmployeeActionState, formData: FormData) {
  const reason = String(formData.get("reason") ?? "").trim();
  const employmentEndDate = String(formData.get("employmentEndDate") ?? "").trim();
  return runLifecycleAction(tenantSlug, masterRecordId, terminateEmployee as LifecycleMutation, { masterRecordId, expectedVersion, reason, employmentEndDate }, "terminate this employee");
}

/**
 * HRT-295 (ISS-2026-108 fix, Tier C review wiring): the governed
 * app.reactivate_user_after_rehire RPC (server/mutations/employee.ts) had a
 * real, tested SQL/TS wrapper but no server action or UI caller anywhere in
 * the app -- a rehired employee's Platform/ESS/MSS access was therefore still
 * practically unreachable for a real HR user, even though the database
 * mechanism itself worked. No `expectedVersion` here (unlike every sibling
 * lifecycle action above) -- the RPC targets the linked app.users row, not
 * app.employees, mirroring app.request_onboarding_access_revocation's own
 * identical shape, per this same RPC's own contract comment
 * (server/contracts/employee/employee.ts).
 */
export async function reactivateUserAfterRehireAction(tenantSlug: string, masterRecordId: string, _prevState: EmployeeActionState, formData: FormData) {
  const reason = String(formData.get("reason") ?? "").trim();
  return runLifecycleAction(tenantSlug, masterRecordId, reactivateUserAfterRehire as LifecycleMutation, { masterRecordId, reason }, "restore this employee's Platform access");
}

export async function archiveEmployeeProfileAction(tenantSlug: string, masterRecordId: string, expectedVersion: number, _prevState: EmployeeActionState, formData: FormData) {
  const reason = String(formData.get("reason") ?? "").trim() || null;
  return runLifecycleAction(tenantSlug, masterRecordId, archiveEmployeeProfile as LifecycleMutation, { masterRecordId, expectedVersion, reason }, "archive this employee profile");
}

export async function transferEmployeeAction(tenantSlug: string, masterRecordId: string, expectedVersion: number, _prevState: EmployeeActionState, formData: FormData) {
  const companyOrgUnitId = String(formData.get("companyOrgUnitId") ?? "").trim() || null;
  const branchOrgUnitId = String(formData.get("branchOrgUnitId") ?? "").trim() || null;
  const departmentOrgUnitId = String(formData.get("departmentOrgUnitId") ?? "").trim() || null;
  const positionTitle = String(formData.get("positionTitle") ?? "").trim() || null;
  const managerEmployeeId = String(formData.get("managerEmployeeId") ?? "").trim() || null;
  const reason = String(formData.get("reason") ?? "").trim() || null;
  return runLifecycleAction(
    tenantSlug,
    masterRecordId,
    transferEmployee as LifecycleMutation,
    { masterRecordId, expectedVersion, companyOrgUnitId, branchOrgUnitId, departmentOrgUnitId, positionTitle, managerEmployeeId, reason },
    "transfer this employee",
  );
}

// --- Emergency contacts ---

export async function addEmployeeEmergencyContactAction(tenantSlug: string, masterRecordId: string, _prevState: EmployeeActionState, formData: FormData) {
  const name = String(formData.get("name") ?? "").trim();
  const relationship = String(formData.get("relationship") ?? "").trim() || null;
  const phone = String(formData.get("phone") ?? "").trim() || null;
  const email = String(formData.get("email") ?? "").trim() || null;
  const isPrimary = formData.get("isPrimary") === "on";
  return runLifecycleAction(tenantSlug, masterRecordId, addEmployeeEmergencyContact as LifecycleMutation, { masterRecordId, name, relationship, phone, email, isPrimary }, "add this emergency contact");
}

export async function removeEmployeeEmergencyContactAction(tenantSlug: string, masterRecordId: string, contactId: string, expectedVersion: number, _prevState: EmployeeActionState, _formData: FormData) {
  return runLifecycleAction(tenantSlug, masterRecordId, removeEmployeeEmergencyContact as LifecycleMutation, { contactId, expectedVersion }, "remove this emergency contact");
}

export async function updateEmployeeEmergencyContactPrimaryAction(
  tenantSlug: string,
  masterRecordId: string,
  contactId: string,
  expectedVersion: number,
  name: string,
  relationship: string | null,
  phone: string | null,
  email: string | null,
  _prevState: EmployeeActionState,
  _formData: FormData,
) {
  return runLifecycleAction(
    tenantSlug,
    masterRecordId,
    updateEmployeeEmergencyContact as LifecycleMutation,
    { contactId, expectedVersion, name, relationship, phone, email, isPrimary: true },
    "set this contact as primary",
  );
}

// --- Documents (ISS-2026-064 item 2 closure) ---

/**
 * Wires the Documents tab's file picker to app.initiate_employee_document_upload --
 * unlike app/(tenant)/[tenantSlug]/procurement/compliance/vendors/actions.ts's own
 * evidence-upload actions, this goes through the ordinary RLS-scoped
 * createSupabaseServerClient(), never a service-role client: the new RPC performs its
 * own HRS:Edit check and is granted directly to `authenticated` (see the migration's
 * own header for why the raw app.initiate_file_upload primitive underneath it must
 * never be called straight from a Server Action). classification is left null so the
 * tenant's own published default for 'employee_document' applies.
 */
export async function uploadEmployeeDocumentAction(tenantSlug: string, masterRecordId: string, _prevState: EmployeeActionState, formData: FormData): Promise<EmployeeActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const file = formData.get("file");
  if (!(file instanceof File) || file.size === 0) {
    return { error: "Select a file to upload." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await initiateEmployeeDocumentUpload(supabase, {
      masterRecordId,
      originalFilename: file.name,
      mimeType: file.type || "application/octet-stream",
      sizeBytes: file.size,
      classification: null,
      idempotencyKey: null,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof EmployeeMutationError) return { error: `Could not upload this document: ${error.message}` };
    throw error;
  }

  revalidatePath(detailPath(tenantSlug, masterRecordId));
  return OK;
}

// --- Duplicate review ---

export async function flagEmployeeDuplicateCandidateAction(tenantSlug: string, masterRecordId: string, candidateMasterRecordId: string, similarityScore: number | null, _prevState: EmployeeActionState, _formData: FormData) {
  return runLifecycleAction(
    tenantSlug,
    masterRecordId,
    flagEmployeeDuplicateCandidate as LifecycleMutation,
    { sourceMasterRecordId: masterRecordId, candidateMasterRecordId, similarityBasis: "manual HR review match", similarityScore },
    "flag this duplicate candidate",
  );
}

export async function decideEmployeeDuplicateCandidateAction(
  tenantSlug: string,
  masterRecordId: string,
  candidateId: string,
  expectedVersion: number,
  _prevState: EmployeeActionState,
  formData: FormData,
) {
  const decision = String(formData.get("decision") ?? "") as "linked" | "dismissed";
  const reason = String(formData.get("reason") ?? "").trim();
  return runLifecycleAction(tenantSlug, masterRecordId, decideEmployeeDuplicateCandidate as LifecycleMutation, { candidateId, expectedVersion, decision, reason }, "record this duplicate-review decision");
}

// --- Change requests (HR review of an employee's own self-service correction request) ---

export async function decideEmployeeChangeRequestAction(
  tenantSlug: string,
  masterRecordId: string,
  requestId: string,
  expectedVersion: number,
  _prevState: EmployeeActionState,
  formData: FormData,
) {
  const decision = String(formData.get("decision") ?? "") as "approved" | "rejected";
  const decidedReason = String(formData.get("decidedReason") ?? "").trim();
  return runLifecycleAction(tenantSlug, masterRecordId, decideEmployeeChangeRequest as LifecycleMutation, { requestId, expectedVersion, decision, decidedReason }, "record this change-request decision");
}
