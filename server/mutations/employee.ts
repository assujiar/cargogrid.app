/**
 * Employee Master mutation primitives (HRT-274, CG-S12-HRT-002). Thin, typed
 * wrappers around every lifecycle/transfer/emergency-contact/duplicate-review/
 * change-request RPC in
 * supabase/migrations/20260730830000_create_hris_employee_master.sql.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  CreateEmployeeDraftInputSchema,
  UpdateEmployeeDraftInputSchema,
  SubmitEmployeeForApprovalInputSchema,
  DecideEmployeeApprovalInputSchema,
  ActivateEmployeeInputSchema,
  LinkEmployeeUserInputSchema,
  StartEmployeeLeaveInputSchema,
  EndEmployeeLeaveInputSchema,
  SuspendEmployeeInputSchema,
  ReactivateEmployeeInputSchema,
  TerminateEmployeeInputSchema,
  ArchiveEmployeeProfileInputSchema,
  TransferEmployeeInputSchema,
  AddEmployeeEmergencyContactInputSchema,
  UpdateEmployeeEmergencyContactInputSchema,
  RemoveEmployeeEmergencyContactInputSchema,
  FlagEmployeeDuplicateCandidateInputSchema,
  DecideEmployeeDuplicateCandidateInputSchema,
  RequestEmployeeChangeInputSchema,
  DecideEmployeeChangeRequestInputSchema,
  ValidateEmployeeImportRowInputSchema,
  CommitEmployeeImportJobInputSchema,
  parseEmployeeMutationResult,
  parseEmployeeEmergencyContact,
  parseEmployeeDuplicateCandidate,
  parseEmployeeChangeRequest,
  type CreateEmployeeDraftInput,
  type UpdateEmployeeDraftInput,
  type SubmitEmployeeForApprovalInput,
  type DecideEmployeeApprovalInput,
  type ActivateEmployeeInput,
  type LinkEmployeeUserInput,
  type StartEmployeeLeaveInput,
  type EndEmployeeLeaveInput,
  type SuspendEmployeeInput,
  type ReactivateEmployeeInput,
  type TerminateEmployeeInput,
  type ArchiveEmployeeProfileInput,
  type TransferEmployeeInput,
  type AddEmployeeEmergencyContactInput,
  type UpdateEmployeeEmergencyContactInput,
  type RemoveEmployeeEmergencyContactInput,
  type FlagEmployeeDuplicateCandidateInput,
  type DecideEmployeeDuplicateCandidateInput,
  type RequestEmployeeChangeInput,
  type DecideEmployeeChangeRequestInput,
  type ValidateEmployeeImportRowInput,
  type CommitEmployeeImportJobInput,
  type EmployeeMutationResult,
  type EmployeeEmergencyContact,
  type EmployeeDuplicateCandidate,
  type EmployeeChangeRequest,
} from "../contracts/employee/employee.ts";

export type EmployeeMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const EMPLOYEE_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "insufficient_privilege",
  "invalid_full_name",
  "invalid_employment_type",
  "invalid_intake_source",
  "employee_not_found",
  "user_not_found",
  "idempotency_key_conflict",
  "stale_version",
  "employee_not_draft",
  "invalid_transition",
  "missing_required_field",
  "missing_required_contact",
  "unresolved_duplicate_candidates",
  "invalid_decision",
  "reason_required",
  "user_already_linked",
  "employment_end_date_required",
  "employee_closed",
  "invalid_contact",
  "contact_not_found",
  "invalid_similarity_basis",
  "duplicate_candidate_not_found",
  "duplicate_candidate_already_decided",
  "not_own_profile",
  "invalid_field_key",
  "invalid_requested_value",
  "change_request_not_found",
  "change_request_already_decided",
  "cyclic_reporting_line",
  "governed_position_exists",
  "org_unit_not_found",
  "invalid_org_unit_type",
  "org_unit_ancestor_mismatch",
  "org_unit_inactive",
  "employee_number_conflict",
  "import_export_job_not_found",
  "import_export_wrong_schema",
  "job_actor_unauthorized",
  "import_export_job_not_committable",
  "import_export_job_not_fully_validated",
  "import_export_job_has_invalid_rows",
  "invalid_response",
] as const;
type KnownEmployeeMutationErrorCode = (typeof EMPLOYEE_KNOWN_MUTATION_ERROR_CODES)[number];
export type EmployeeMutationErrorCode = KnownEmployeeMutationErrorCode | "mutation_failed";

export class EmployeeMutationError extends Error {
  readonly code: EmployeeMutationErrorCode;

  constructor(code: EmployeeMutationErrorCode, message: string) {
    super(message);
    this.name = "EmployeeMutationError";
    this.code = code;
  }
}

function classifyError(message: string): EmployeeMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (EMPLOYEE_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "") ? (prefix as KnownEmployeeMutationErrorCode) : "mutation_failed";
}

function firstRow(data: unknown): Record<string, unknown> | null {
  const row = Array.isArray(data) ? data[0] : data;
  return row && typeof row === "object" ? (row as Record<string, unknown>) : null;
}

function parseEmployeeResponse(data: unknown, rpcName: string): EmployeeMutationResult {
  const row = firstRow(data);
  if (!row) throw new EmployeeMutationError("invalid_response", `${rpcName} returned no row`);
  return parseEmployeeMutationResult(row);
}

// --- Lifecycle ---

export async function createEmployeeDraft(client: EmployeeMutationRpcClient, input: CreateEmployeeDraftInput): Promise<EmployeeMutationResult> {
  const parsed = CreateEmployeeDraftInputSchema.parse(input);
  const { data, error } = await client.rpc("create_employee_draft", {
    p_tenant_id: parsed.tenantId,
    p_full_name: parsed.fullName,
    p_employment_type: parsed.employmentType,
    p_work_email: parsed.workEmail ?? null,
    p_personal_email: parsed.personalEmail ?? null,
    p_personal_phone: parsed.personalPhone ?? null,
    p_national_id_number: parsed.nationalIdNumber ?? null,
    p_date_of_birth: parsed.dateOfBirth ?? null,
    p_gender: parsed.gender ?? null,
    p_hire_date: parsed.hireDate ?? null,
    p_company_org_unit_id: parsed.companyOrgUnitId ?? null,
    p_branch_org_unit_id: parsed.branchOrgUnitId ?? null,
    p_department_org_unit_id: parsed.departmentOrgUnitId ?? null,
    p_position_title: parsed.positionTitle ?? null,
    p_manager_employee_id: parsed.managerEmployeeId ?? null,
    p_user_id: parsed.userId ?? null,
    p_employee_number: parsed.employeeNumber ?? null,
    p_intake_source: parsed.intakeSource,
    p_idempotency_key: parsed.idempotencyKey ?? null,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new EmployeeMutationError(classifyError(error.message), error.message);
  return parseEmployeeResponse(data, "create_employee_draft");
}

export async function updateEmployeeDraft(client: EmployeeMutationRpcClient, input: UpdateEmployeeDraftInput): Promise<EmployeeMutationResult> {
  const parsed = UpdateEmployeeDraftInputSchema.parse(input);
  const { data, error } = await client.rpc("update_employee_draft", {
    p_master_record_id: parsed.masterRecordId,
    p_expected_version: parsed.expectedVersion,
    p_full_name: parsed.fullName,
    p_employment_type: parsed.employmentType,
    p_work_email: parsed.workEmail ?? null,
    p_personal_email: parsed.personalEmail ?? null,
    p_personal_phone: parsed.personalPhone ?? null,
    p_national_id_number: parsed.nationalIdNumber ?? null,
    p_date_of_birth: parsed.dateOfBirth ?? null,
    p_gender: parsed.gender ?? null,
    p_hire_date: parsed.hireDate ?? null,
    p_probation_end_date: parsed.probationEndDate ?? null,
    p_company_org_unit_id: parsed.companyOrgUnitId ?? null,
    p_branch_org_unit_id: parsed.branchOrgUnitId ?? null,
    p_department_org_unit_id: parsed.departmentOrgUnitId ?? null,
    p_position_title: parsed.positionTitle ?? null,
    p_manager_employee_id: parsed.managerEmployeeId ?? null,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new EmployeeMutationError(classifyError(error.message), error.message);
  return parseEmployeeResponse(data, "update_employee_draft");
}

export async function submitEmployeeForApproval(client: EmployeeMutationRpcClient, input: SubmitEmployeeForApprovalInput): Promise<EmployeeMutationResult> {
  const parsed = SubmitEmployeeForApprovalInputSchema.parse(input);
  const { data, error } = await client.rpc("submit_employee_for_approval", {
    p_master_record_id: parsed.masterRecordId,
    p_expected_version: parsed.expectedVersion,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new EmployeeMutationError(classifyError(error.message), error.message);
  return parseEmployeeResponse(data, "submit_employee_for_approval");
}

export async function decideEmployeeApproval(client: EmployeeMutationRpcClient, input: DecideEmployeeApprovalInput): Promise<EmployeeMutationResult> {
  const parsed = DecideEmployeeApprovalInputSchema.parse(input);
  const { data, error } = await client.rpc("decide_employee_approval", {
    p_master_record_id: parsed.masterRecordId,
    p_expected_version: parsed.expectedVersion,
    p_decision: parsed.decision,
    p_reason: parsed.reason ?? null,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new EmployeeMutationError(classifyError(error.message), error.message);
  return parseEmployeeResponse(data, "decide_employee_approval");
}

export async function activateEmployee(client: EmployeeMutationRpcClient, input: ActivateEmployeeInput): Promise<EmployeeMutationResult> {
  const parsed = ActivateEmployeeInputSchema.parse(input);
  const { data, error } = await client.rpc("activate_employee", {
    p_master_record_id: parsed.masterRecordId,
    p_expected_version: parsed.expectedVersion,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new EmployeeMutationError(classifyError(error.message), error.message);
  return parseEmployeeResponse(data, "activate_employee");
}

export async function linkEmployeeUser(client: EmployeeMutationRpcClient, input: LinkEmployeeUserInput): Promise<EmployeeMutationResult> {
  const parsed = LinkEmployeeUserInputSchema.parse(input);
  const { data, error } = await client.rpc("link_employee_user", {
    p_master_record_id: parsed.masterRecordId,
    p_expected_version: parsed.expectedVersion,
    p_user_id: parsed.userId,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new EmployeeMutationError(classifyError(error.message), error.message);
  return parseEmployeeResponse(data, "link_employee_user");
}

export async function startEmployeeLeave(client: EmployeeMutationRpcClient, input: StartEmployeeLeaveInput): Promise<EmployeeMutationResult> {
  const parsed = StartEmployeeLeaveInputSchema.parse(input);
  const { data, error } = await client.rpc("start_employee_leave", {
    p_master_record_id: parsed.masterRecordId,
    p_expected_version: parsed.expectedVersion,
    p_reason: parsed.reason ?? null,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new EmployeeMutationError(classifyError(error.message), error.message);
  return parseEmployeeResponse(data, "start_employee_leave");
}

export async function endEmployeeLeave(client: EmployeeMutationRpcClient, input: EndEmployeeLeaveInput): Promise<EmployeeMutationResult> {
  const parsed = EndEmployeeLeaveInputSchema.parse(input);
  const { data, error } = await client.rpc("end_employee_leave", {
    p_master_record_id: parsed.masterRecordId,
    p_expected_version: parsed.expectedVersion,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new EmployeeMutationError(classifyError(error.message), error.message);
  return parseEmployeeResponse(data, "end_employee_leave");
}

export async function suspendEmployee(client: EmployeeMutationRpcClient, input: SuspendEmployeeInput): Promise<EmployeeMutationResult> {
  const parsed = SuspendEmployeeInputSchema.parse(input);
  const { data, error } = await client.rpc("suspend_employee", {
    p_master_record_id: parsed.masterRecordId,
    p_expected_version: parsed.expectedVersion,
    p_reason: parsed.reason,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new EmployeeMutationError(classifyError(error.message), error.message);
  return parseEmployeeResponse(data, "suspend_employee");
}

export async function reactivateEmployee(client: EmployeeMutationRpcClient, input: ReactivateEmployeeInput): Promise<EmployeeMutationResult> {
  const parsed = ReactivateEmployeeInputSchema.parse(input);
  const { data, error } = await client.rpc("reactivate_employee", {
    p_master_record_id: parsed.masterRecordId,
    p_expected_version: parsed.expectedVersion,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new EmployeeMutationError(classifyError(error.message), error.message);
  return parseEmployeeResponse(data, "reactivate_employee");
}

export async function terminateEmployee(client: EmployeeMutationRpcClient, input: TerminateEmployeeInput): Promise<EmployeeMutationResult> {
  const parsed = TerminateEmployeeInputSchema.parse(input);
  const { data, error } = await client.rpc("terminate_employee", {
    p_master_record_id: parsed.masterRecordId,
    p_expected_version: parsed.expectedVersion,
    p_reason: parsed.reason,
    p_employment_end_date: parsed.employmentEndDate,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new EmployeeMutationError(classifyError(error.message), error.message);
  return parseEmployeeResponse(data, "terminate_employee");
}

export async function archiveEmployeeProfile(client: EmployeeMutationRpcClient, input: ArchiveEmployeeProfileInput): Promise<EmployeeMutationResult> {
  const parsed = ArchiveEmployeeProfileInputSchema.parse(input);
  const { data, error } = await client.rpc("archive_employee_profile", {
    p_master_record_id: parsed.masterRecordId,
    p_expected_version: parsed.expectedVersion,
    p_reason: parsed.reason ?? null,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new EmployeeMutationError(classifyError(error.message), error.message);
  return parseEmployeeResponse(data, "archive_employee_profile");
}

export async function transferEmployee(client: EmployeeMutationRpcClient, input: TransferEmployeeInput): Promise<EmployeeMutationResult> {
  const parsed = TransferEmployeeInputSchema.parse(input);
  const { data, error } = await client.rpc("transfer_employee", {
    p_master_record_id: parsed.masterRecordId,
    p_expected_version: parsed.expectedVersion,
    p_company_org_unit_id: parsed.companyOrgUnitId ?? null,
    p_branch_org_unit_id: parsed.branchOrgUnitId ?? null,
    p_department_org_unit_id: parsed.departmentOrgUnitId ?? null,
    p_position_title: parsed.positionTitle ?? null,
    p_manager_employee_id: parsed.managerEmployeeId ?? null,
    p_reason: parsed.reason ?? null,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new EmployeeMutationError(classifyError(error.message), error.message);
  return parseEmployeeResponse(data, "transfer_employee");
}

// --- Emergency contacts ---

function parseContactResponse(data: unknown, rpcName: string): EmployeeEmergencyContact {
  const row = firstRow(data);
  if (!row) throw new EmployeeMutationError("invalid_response", `${rpcName} returned no row`);
  return parseEmployeeEmergencyContact(row);
}

export async function addEmployeeEmergencyContact(client: EmployeeMutationRpcClient, input: AddEmployeeEmergencyContactInput): Promise<EmployeeEmergencyContact> {
  const parsed = AddEmployeeEmergencyContactInputSchema.parse(input);
  const { data, error } = await client.rpc("add_employee_emergency_contact", {
    p_master_record_id: parsed.masterRecordId,
    p_name: parsed.name,
    p_relationship: parsed.relationship ?? null,
    p_phone: parsed.phone ?? null,
    p_email: parsed.email ?? null,
    p_is_primary: parsed.isPrimary,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new EmployeeMutationError(classifyError(error.message), error.message);
  return parseContactResponse(data, "add_employee_emergency_contact");
}

export async function updateEmployeeEmergencyContact(client: EmployeeMutationRpcClient, input: UpdateEmployeeEmergencyContactInput): Promise<EmployeeEmergencyContact> {
  const parsed = UpdateEmployeeEmergencyContactInputSchema.parse(input);
  const { data, error } = await client.rpc("update_employee_emergency_contact", {
    p_contact_id: parsed.contactId,
    p_expected_version: parsed.expectedVersion,
    p_name: parsed.name,
    p_relationship: parsed.relationship ?? null,
    p_phone: parsed.phone ?? null,
    p_email: parsed.email ?? null,
    p_is_primary: parsed.isPrimary,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new EmployeeMutationError(classifyError(error.message), error.message);
  return parseContactResponse(data, "update_employee_emergency_contact");
}

export async function removeEmployeeEmergencyContact(client: EmployeeMutationRpcClient, input: RemoveEmployeeEmergencyContactInput): Promise<EmployeeEmergencyContact> {
  const parsed = RemoveEmployeeEmergencyContactInputSchema.parse(input);
  const { data, error } = await client.rpc("remove_employee_emergency_contact", {
    p_contact_id: parsed.contactId,
    p_expected_version: parsed.expectedVersion,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new EmployeeMutationError(classifyError(error.message), error.message);
  return parseContactResponse(data, "remove_employee_emergency_contact");
}

// --- Duplicate review ---

function parseDuplicateCandidateResponse(data: unknown, rpcName: string): EmployeeDuplicateCandidate {
  const row = firstRow(data);
  if (!row) throw new EmployeeMutationError("invalid_response", `${rpcName} returned no row`);
  return parseEmployeeDuplicateCandidate(row);
}

export async function flagEmployeeDuplicateCandidate(client: EmployeeMutationRpcClient, input: FlagEmployeeDuplicateCandidateInput): Promise<EmployeeDuplicateCandidate> {
  const parsed = FlagEmployeeDuplicateCandidateInputSchema.parse(input);
  const { data, error } = await client.rpc("flag_employee_duplicate_candidate", {
    p_source_master_record_id: parsed.sourceMasterRecordId,
    p_candidate_master_record_id: parsed.candidateMasterRecordId,
    p_similarity_basis: parsed.similarityBasis,
    p_similarity_score: parsed.similarityScore ?? null,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new EmployeeMutationError(classifyError(error.message), error.message);
  return parseDuplicateCandidateResponse(data, "flag_employee_duplicate_candidate");
}

export async function decideEmployeeDuplicateCandidate(client: EmployeeMutationRpcClient, input: DecideEmployeeDuplicateCandidateInput): Promise<EmployeeDuplicateCandidate> {
  const parsed = DecideEmployeeDuplicateCandidateInputSchema.parse(input);
  const { data, error } = await client.rpc("decide_employee_duplicate_candidate", {
    p_candidate_id: parsed.candidateId,
    p_expected_version: parsed.expectedVersion,
    p_decision: parsed.decision,
    p_reason: parsed.reason,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new EmployeeMutationError(classifyError(error.message), error.message);
  return parseDuplicateCandidateResponse(data, "decide_employee_duplicate_candidate");
}

// --- Own-profile change requests ---

function parseChangeRequestResponse(data: unknown, rpcName: string): EmployeeChangeRequest {
  const row = firstRow(data);
  if (!row) throw new EmployeeMutationError("invalid_response", `${rpcName} returned no row`);
  return parseEmployeeChangeRequest(row);
}

export async function requestEmployeeChange(client: EmployeeMutationRpcClient, input: RequestEmployeeChangeInput): Promise<EmployeeChangeRequest> {
  const parsed = RequestEmployeeChangeInputSchema.parse(input);
  const { data, error } = await client.rpc("request_employee_change", {
    p_master_record_id: parsed.masterRecordId,
    p_field_key: parsed.fieldKey,
    p_requested_value: parsed.requestedValue,
    p_reason: parsed.reason ?? null,
    p_actor_auth_user_id: parsed.actorAuthUserId,
  });
  if (error) throw new EmployeeMutationError(classifyError(error.message), error.message);
  return parseChangeRequestResponse(data, "request_employee_change");
}

export async function decideEmployeeChangeRequest(client: EmployeeMutationRpcClient, input: DecideEmployeeChangeRequestInput): Promise<EmployeeChangeRequest> {
  const parsed = DecideEmployeeChangeRequestInputSchema.parse(input);
  const { data, error } = await client.rpc("decide_employee_change_request", {
    p_request_id: parsed.requestId,
    p_expected_version: parsed.expectedVersion,
    p_decision: parsed.decision,
    p_decided_reason: parsed.decidedReason,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new EmployeeMutationError(classifyError(error.message), error.message);
  return parseChangeRequestResponse(data, "decide_employee_change_request");
}

// --- Staged import (decision 11, PLT-131/132) ---
// Mirrors validateVendorRateImportRow/commitVendorRateImportJob
// (server/mutations/procurement-rate.ts) exactly -- the fifth-plus real domain-write
// adapter after PRC-255. Previously missing at this service layer entirely (the RPCs
// existed and were exercised only by raw SQL in scripts/db-tests/hris-employee-master.sql
// -- this checkpoint's own review round found and closed that gap).

/** Server-mediated only (service_role client) -- validates one staged employee_import row, rejecting (never silently stripping) any formula/spreadsheet-injection-shaped text field plus org-unit-code resolution (app.validate_employee_import_row). */
export async function validateEmployeeImportRow(client: EmployeeMutationRpcClient, input: ValidateEmployeeImportRowInput): Promise<Record<string, unknown>> {
  const parsed = ValidateEmployeeImportRowInputSchema.parse(input);
  const { data, error } = await client.rpc("validate_employee_import_row", {
    p_staging_row_id: parsed.stagingRowId,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new EmployeeMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new EmployeeMutationError("invalid_response", "validate_employee_import_row returned no row");
  return row;
}

/** Requires HRS:Import. Idempotent per staging row (source_import_staging_row_id unique-when-set on app.employees) and job-scoped-advisory-lock serialized -- safe to retry (app.commit_employee_import_job). */
export async function commitEmployeeImportJob(client: EmployeeMutationRpcClient, input: CommitEmployeeImportJobInput): Promise<Record<string, unknown>> {
  const parsed = CommitEmployeeImportJobInputSchema.parse(input);
  const { data, error } = await client.rpc("commit_employee_import_job", {
    p_job_id: parsed.jobId,
    p_allow_partial: parsed.allowPartial,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new EmployeeMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new EmployeeMutationError("invalid_response", "commit_employee_import_job returned no row");
  return row;
}
