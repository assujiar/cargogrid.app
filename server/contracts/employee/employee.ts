/**
 * Employee Master contract (HRT-274, CG-S12-HRT-002). Mirrors
 * supabase/migrations/20260730830000_create_hris_employee_master.sql's
 * app.employees/app.employee_emergency_contacts/app.employee_lifecycle_events/
 * app.employee_duplicate_candidates/app.employee_change_requests shapes and their
 * RPCs. Follows the exact directory convention PRC-251 established: Zod schemas
 * here, list/read projections in server/queries/employee.ts, RPC-calling mutation
 * wrappers with an enumerated error-code type in server/mutations/employee.ts.
 *
 * app.employees is a governed 1:1 extension of app.master_records where
 * master_type_code='employee' (ADR-0023 Part B; HRT-274 build log decision 1). Every
 * schema below keys off masterRecordId, never a second employee identity.
 */

import { z } from "zod";
import { ClassificationSchema } from "../document/document.ts";

export const EMPLOYMENT_TYPES = ["full_time", "part_time", "contract", "intern", "probation", "daily_worker"] as const;
export const EmploymentTypeSchema = z.enum(EMPLOYMENT_TYPES);
export type EmploymentType = z.infer<typeof EmploymentTypeSchema>;

export const EMPLOYEE_LIFECYCLE_STATUSES = ["draft", "submitted", "approved", "active", "on_leave", "suspended", "terminated", "archived"] as const;
export const EmployeeLifecycleStatusSchema = z.enum(EMPLOYEE_LIFECYCLE_STATUSES);
export type EmployeeLifecycleStatus = z.infer<typeof EmployeeLifecycleStatusSchema>;

export const EMPLOYEE_INTAKE_SOURCES = ["hr_created", "bulk_import"] as const;
export const EmployeeIntakeSourceSchema = z.enum(EMPLOYEE_INTAKE_SOURCES);
export type EmployeeIntakeSource = z.infer<typeof EmployeeIntakeSourceSchema>;

export const EMPLOYEE_REVIEW_DECISIONS = ["approve", "reject"] as const;
export const EmployeeReviewDecisionSchema = z.enum(EMPLOYEE_REVIEW_DECISIONS);
export type EmployeeReviewDecision = z.infer<typeof EmployeeReviewDecisionSchema>;

export const EMPLOYEE_DUPLICATE_DECISIONS = ["pending", "linked", "dismissed"] as const;
export const EmployeeDuplicateDecisionSchema = z.enum(EMPLOYEE_DUPLICATE_DECISIONS);
export type EmployeeDuplicateDecision = z.infer<typeof EmployeeDuplicateDecisionSchema>;

export const EMPLOYEE_CHANGE_REQUEST_FIELDS = [
  "personal_email",
  "personal_phone",
  "personal_address_street",
  "personal_address_city",
  "personal_address_province",
  "personal_address_postal_code",
  "personal_address_country",
] as const;
export const EmployeeChangeRequestFieldSchema = z.enum(EMPLOYEE_CHANGE_REQUEST_FIELDS);
export type EmployeeChangeRequestField = z.infer<typeof EmployeeChangeRequestFieldSchema>;

export const EMPLOYEE_CHANGE_REQUEST_STATUSES = ["pending", "approved", "rejected"] as const;
export const EmployeeChangeRequestStatusSchema = z.enum(EMPLOYEE_CHANGE_REQUEST_STATUSES);
export type EmployeeChangeRequestStatus = z.infer<typeof EmployeeChangeRequestStatusSchema>;

// --- Core rows ---

/** app.get_employee_profile's own projection -- sensitive columns are null when personalDataMasked=true (caller lacks HRS:View personal data AND is not reading their own linked profile). */
export const EmployeeProfileSchema = z.object({
  masterRecordId: z.string().uuid(),
  employeeNumber: z.string(),
  tenantId: z.string().uuid(),
  userId: z.string().uuid().nullable(),
  fullName: z.string(),
  employmentType: EmploymentTypeSchema,
  lifecycleStatus: EmployeeLifecycleStatusSchema,
  intakeSource: EmployeeIntakeSourceSchema,
  workEmail: z.string().nullable(),
  workPhone: z.string().nullable(),
  personalEmail: z.string().nullable(),
  personalPhone: z.string().nullable(),
  nationalIdNumber: z.string().nullable(),
  dateOfBirth: z.string().nullable(),
  gender: z.string().nullable(),
  personalAddressStreet: z.string().nullable(),
  personalAddressCity: z.string().nullable(),
  personalAddressProvince: z.string().nullable(),
  personalAddressPostalCode: z.string().nullable(),
  personalAddressCountry: z.string().nullable(),
  hireDate: z.string().nullable(),
  probationEndDate: z.string().nullable(),
  employmentEndDate: z.string().nullable(),
  companyOrgUnitId: z.string().uuid().nullable(),
  branchOrgUnitId: z.string().uuid().nullable(),
  departmentOrgUnitId: z.string().uuid().nullable(),
  positionTitle: z.string().nullable(),
  managerEmployeeId: z.string().uuid().nullable(),
  revisionReason: z.string().nullable(),
  suspendReason: z.string().nullable(),
  terminateReason: z.string().nullable(),
  archiveReason: z.string().nullable(),
  leaveReason: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
  updatedAt: z.string(),
  personalDataMasked: z.boolean(),
});
export type EmployeeProfile = z.infer<typeof EmployeeProfileSchema>;

export function parseEmployeeProfile(row: Record<string, unknown>): EmployeeProfile {
  return EmployeeProfileSchema.parse({
    masterRecordId: row.master_record_id,
    employeeNumber: row.employee_number,
    tenantId: row.tenant_id,
    userId: row.user_id ?? null,
    fullName: row.full_name,
    employmentType: row.employment_type,
    lifecycleStatus: row.lifecycle_status,
    intakeSource: row.intake_source,
    workEmail: row.work_email ?? null,
    workPhone: row.work_phone ?? null,
    personalEmail: row.personal_email ?? null,
    personalPhone: row.personal_phone ?? null,
    nationalIdNumber: row.national_id_number ?? null,
    dateOfBirth: row.date_of_birth ?? null,
    gender: row.gender ?? null,
    personalAddressStreet: row.personal_address_street ?? null,
    personalAddressCity: row.personal_address_city ?? null,
    personalAddressProvince: row.personal_address_province ?? null,
    personalAddressPostalCode: row.personal_address_postal_code ?? null,
    personalAddressCountry: row.personal_address_country ?? null,
    hireDate: row.hire_date ?? null,
    probationEndDate: row.probation_end_date ?? null,
    employmentEndDate: row.employment_end_date ?? null,
    companyOrgUnitId: row.company_org_unit_id ?? null,
    branchOrgUnitId: row.branch_org_unit_id ?? null,
    departmentOrgUnitId: row.department_org_unit_id ?? null,
    positionTitle: row.position_title ?? null,
    managerEmployeeId: row.manager_employee_id ?? null,
    revisionReason: row.revision_reason ?? null,
    suspendReason: row.suspend_reason ?? null,
    terminateReason: row.terminate_reason ?? null,
    archiveReason: row.archive_reason ?? null,
    leaveReason: row.leave_reason ?? null,
    recordVersion: row.record_version,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    personalDataMasked: row.personal_data_masked,
  });
}

/**
 * A lifecycle-transition mutation RPC (create_employee_draft, submit_..., etc.)
 * returns the raw app.employees row -- no employee_number/personal_data_masked
 * joined in. Deliberately distinct from EmployeeProfileSchema, matching
 * VendorProfileMutationResultSchema's own precedent.
 */
export const EmployeeMutationResultSchema = z.object({
  masterRecordId: z.string().uuid(),
  tenantId: z.string().uuid(),
  userId: z.string().uuid().nullable(),
  fullName: z.string(),
  employmentType: EmploymentTypeSchema,
  lifecycleStatus: EmployeeLifecycleStatusSchema,
  intakeSource: EmployeeIntakeSourceSchema,
  workEmail: z.string().nullable(),
  personalEmail: z.string().nullable(),
  personalPhone: z.string().nullable(),
  hireDate: z.string().nullable(),
  companyOrgUnitId: z.string().uuid().nullable(),
  branchOrgUnitId: z.string().uuid().nullable(),
  departmentOrgUnitId: z.string().uuid().nullable(),
  positionTitle: z.string().nullable(),
  managerEmployeeId: z.string().uuid().nullable(),
  revisionReason: z.string().nullable(),
  suspendReason: z.string().nullable(),
  terminateReason: z.string().nullable(),
  archiveReason: z.string().nullable(),
  leaveReason: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type EmployeeMutationResult = z.infer<typeof EmployeeMutationResultSchema>;

export function parseEmployeeMutationResult(row: Record<string, unknown>): EmployeeMutationResult {
  return EmployeeMutationResultSchema.parse({
    masterRecordId: row.master_record_id,
    tenantId: row.tenant_id,
    userId: row.user_id ?? null,
    fullName: row.full_name,
    employmentType: row.employment_type,
    lifecycleStatus: row.lifecycle_status,
    intakeSource: row.intake_source,
    workEmail: row.work_email ?? null,
    personalEmail: row.personal_email ?? null,
    personalPhone: row.personal_phone ?? null,
    hireDate: row.hire_date ?? null,
    companyOrgUnitId: row.company_org_unit_id ?? null,
    branchOrgUnitId: row.branch_org_unit_id ?? null,
    departmentOrgUnitId: row.department_org_unit_id ?? null,
    positionTitle: row.position_title ?? null,
    managerEmployeeId: row.manager_employee_id ?? null,
    revisionReason: row.revision_reason ?? null,
    suspendReason: row.suspend_reason ?? null,
    terminateReason: row.terminate_reason ?? null,
    archiveReason: row.archive_reason ?? null,
    leaveReason: row.leave_reason ?? null,
    recordVersion: row.record_version,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

export const EmployeeListRowSchema = z.object({
  masterRecordId: z.string().uuid(),
  employeeNumber: z.string(),
  fullName: z.string(),
  employmentType: EmploymentTypeSchema,
  lifecycleStatus: EmployeeLifecycleStatusSchema,
  departmentOrgUnitId: z.string().uuid().nullable(),
  positionTitle: z.string().nullable(),
  hireDate: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type EmployeeListRow = z.infer<typeof EmployeeListRowSchema>;

export function parseEmployeeListRow(row: Record<string, unknown>): EmployeeListRow {
  return EmployeeListRowSchema.parse({
    masterRecordId: row.master_record_id,
    employeeNumber: row.employee_number,
    fullName: row.full_name,
    employmentType: row.employment_type,
    lifecycleStatus: row.lifecycle_status,
    departmentOrgUnitId: row.department_org_unit_id ?? null,
    positionTitle: row.position_title ?? null,
    hireDate: row.hire_date ?? null,
    recordVersion: row.record_version,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

/** app.list_my_team_employees' own projection -- deliberately zero PII columns (manager-scoped view, never HR personal-data scope). */
export const MyTeamEmployeeRowSchema = z.object({
  masterRecordId: z.string().uuid(),
  employeeNumber: z.string(),
  fullName: z.string(),
  employmentType: EmploymentTypeSchema,
  lifecycleStatus: EmployeeLifecycleStatusSchema,
  positionTitle: z.string().nullable(),
  hireDate: z.string().nullable(),
});
export type MyTeamEmployeeRow = z.infer<typeof MyTeamEmployeeRowSchema>;

export function parseMyTeamEmployeeRow(row: Record<string, unknown>): MyTeamEmployeeRow {
  return MyTeamEmployeeRowSchema.parse({
    masterRecordId: row.master_record_id,
    employeeNumber: row.employee_number,
    fullName: row.full_name,
    employmentType: row.employment_type,
    lifecycleStatus: row.lifecycle_status,
    positionTitle: row.position_title ?? null,
    hireDate: row.hire_date ?? null,
  });
}

/** app.export_employees' own scoped, non-PII projection (section 14: "scoped export"). */
export const EmployeeExportRowSchema = z.object({
  employeeNumber: z.string(),
  fullName: z.string(),
  employmentType: EmploymentTypeSchema,
  lifecycleStatus: EmployeeLifecycleStatusSchema,
  hireDate: z.string().nullable(),
  departmentOrgUnitId: z.string().uuid().nullable(),
  positionTitle: z.string().nullable(),
});
export type EmployeeExportRow = z.infer<typeof EmployeeExportRowSchema>;

export function parseEmployeeExportRow(row: Record<string, unknown>): EmployeeExportRow {
  return EmployeeExportRowSchema.parse({
    employeeNumber: row.employee_number,
    fullName: row.full_name,
    employmentType: row.employment_type,
    lifecycleStatus: row.lifecycle_status,
    hireDate: row.hire_date ?? null,
    departmentOrgUnitId: row.department_org_unit_id ?? null,
    positionTitle: row.position_title ?? null,
  });
}

export const EmployeeEmergencyContactSchema = z.object({
  id: z.string().uuid(),
  masterRecordId: z.string().uuid(),
  name: z.string(),
  relationship: z.string().nullable(),
  phone: z.string().nullable(),
  email: z.string().nullable(),
  isPrimary: z.boolean(),
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
});
export type EmployeeEmergencyContact = z.infer<typeof EmployeeEmergencyContactSchema>;

/** phone/email are null when app.list_employee_emergency_contacts masked them (caller lacks HRS:View personal data) -- mirrors parseVendorContact's own disclosed masked/never-entered ambiguity. */
export function parseEmployeeEmergencyContact(row: Record<string, unknown>): EmployeeEmergencyContact {
  return EmployeeEmergencyContactSchema.parse({
    id: row.id,
    masterRecordId: row.master_record_id,
    name: row.name,
    relationship: row.relationship ?? null,
    phone: row.phone ?? null,
    email: row.email ?? null,
    isPrimary: row.is_primary,
    recordVersion: row.record_version,
    createdAt: row.created_at,
  });
}

export const EmployeeLifecycleEventSchema = z.object({
  id: z.string().uuid(),
  masterRecordId: z.string().uuid(),
  fromStatus: z.string(),
  toStatus: z.string(),
  reason: z.string().nullable(),
  metadata: z.record(z.string(), z.unknown()),
  actorLabel: z.string().nullable(),
  occurredAt: z.string(),
});
export type EmployeeLifecycleEvent = z.infer<typeof EmployeeLifecycleEventSchema>;

export function parseEmployeeLifecycleEvent(row: Record<string, unknown>): EmployeeLifecycleEvent {
  return EmployeeLifecycleEventSchema.parse({
    id: row.id,
    masterRecordId: row.master_record_id,
    fromStatus: row.from_status,
    toStatus: row.to_status,
    reason: row.reason ?? null,
    metadata: row.metadata ?? {},
    actorLabel: row.actor_label ?? null,
    occurredAt: row.occurred_at,
  });
}

// --- ISS-2026-065 closure: effective-dated lifecycle version history ---
// (supabase/migrations/20260731310000_add_hris_employee_lifecycle_effective_dating_iss2026065.sql).

export const EMPLOYEE_LIFECYCLE_VERSION_STATUSES = ["scheduled", "active", "superseded"] as const;
export const EmployeeLifecycleVersionStatusSchema = z.enum(EMPLOYEE_LIFECYCLE_VERSION_STATUSES);
export type EmployeeLifecycleVersionStatus = z.infer<typeof EmployeeLifecycleVersionStatusSchema>;

export const EMPLOYEE_LIFECYCLE_CHANGE_REASONS = ["hire", "transfer", "promotion", "demotion", "suspend", "reactivate", "terminate", "archive", "correction"] as const;
export const EmployeeLifecycleChangeReasonSchema = z.enum(EMPLOYEE_LIFECYCLE_CHANGE_REASONS);
export type EmployeeLifecycleChangeReason = z.infer<typeof EmployeeLifecycleChangeReasonSchema>;

/** app.get_employee_lifecycle_as_of's own projection -- reconstructs the genuine lifecycle state as of any date, never app.employees' own current-state columns. decidedReason is null (masked) unless the caller is self or holds HRS:View personal data. */
export const EmployeeLifecycleVersionSchema = z.object({
  id: z.string().uuid(),
  masterRecordId: z.string().uuid(),
  lifecycleStatus: EmployeeLifecycleStatusSchema,
  employmentType: EmploymentTypeSchema,
  companyOrgUnitId: z.string().uuid().nullable(),
  branchOrgUnitId: z.string().uuid().nullable(),
  departmentOrgUnitId: z.string().uuid().nullable(),
  positionTitle: z.string().nullable(),
  managerEmployeeId: z.string().uuid().nullable(),
  hireDate: z.string().nullable(),
  probationEndDate: z.string().nullable(),
  employmentEndDate: z.string().nullable(),
  effectiveStartDate: z.string(),
  effectiveEndDate: z.string().nullable(),
  status: EmployeeLifecycleVersionStatusSchema,
  changeReason: EmployeeLifecycleChangeReasonSchema,
  decidedBy: z.string().nullable(),
  decidedAt: z.string(),
  decidedReason: z.string().nullable(),
  recordVersion: z.number().int(),
});
export type EmployeeLifecycleVersion = z.infer<typeof EmployeeLifecycleVersionSchema>;

export function parseEmployeeLifecycleVersion(row: Record<string, unknown>): EmployeeLifecycleVersion {
  return EmployeeLifecycleVersionSchema.parse({
    id: row.id,
    masterRecordId: row.master_record_id,
    lifecycleStatus: row.lifecycle_status,
    employmentType: row.employment_type,
    companyOrgUnitId: row.company_org_unit_id ?? null,
    branchOrgUnitId: row.branch_org_unit_id ?? null,
    departmentOrgUnitId: row.department_org_unit_id ?? null,
    positionTitle: row.position_title ?? null,
    managerEmployeeId: row.manager_employee_id ?? null,
    hireDate: row.hire_date ?? null,
    probationEndDate: row.probation_end_date ?? null,
    employmentEndDate: row.employment_end_date ?? null,
    effectiveStartDate: row.effective_start_date,
    effectiveEndDate: row.effective_end_date ?? null,
    status: row.status,
    changeReason: row.change_reason,
    decidedBy: row.decided_by ?? null,
    decidedAt: row.decided_at,
    decidedReason: row.decided_reason ?? null,
    recordVersion: row.record_version,
  });
}

export const EmployeeDuplicateCandidateSchema = z.object({
  id: z.string().uuid(),
  sourceMasterRecordId: z.string().uuid(),
  candidateMasterRecordId: z.string().uuid(),
  similarityBasis: z.string(),
  similarityScore: z.coerce.number().nullable(),
  decision: EmployeeDuplicateDecisionSchema,
  decidedBy: z.string().nullable(),
  decidedAt: z.string().nullable(),
  decidedReason: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
});
export type EmployeeDuplicateCandidate = z.infer<typeof EmployeeDuplicateCandidateSchema>;

export function parseEmployeeDuplicateCandidate(row: Record<string, unknown>): EmployeeDuplicateCandidate {
  return EmployeeDuplicateCandidateSchema.parse({
    id: row.id,
    sourceMasterRecordId: row.source_master_record_id,
    candidateMasterRecordId: row.candidate_master_record_id,
    similarityBasis: row.similarity_basis,
    similarityScore: row.similarity_score ?? null,
    decision: row.decision,
    decidedBy: row.decided_by ?? null,
    decidedAt: row.decided_at ?? null,
    decidedReason: row.decided_reason ?? null,
    recordVersion: row.record_version,
    createdAt: row.created_at,
  });
}

export const EmployeeDuplicateSearchRowSchema = z.object({
  masterRecordId: z.string().uuid(),
  employeeNumber: z.string(),
  fullName: z.string(),
  similarityScore: z.coerce.number(),
  matchBasis: z.string(),
});
export type EmployeeDuplicateSearchRow = z.infer<typeof EmployeeDuplicateSearchRowSchema>;

export function parseEmployeeDuplicateSearchRow(row: Record<string, unknown>): EmployeeDuplicateSearchRow {
  return EmployeeDuplicateSearchRowSchema.parse({
    masterRecordId: row.master_record_id,
    employeeNumber: row.employee_number,
    fullName: row.full_name,
    similarityScore: row.similarity_score,
    matchBasis: row.match_basis,
  });
}

export const EmployeeChangeRequestSchema = z.object({
  id: z.string().uuid(),
  masterRecordId: z.string().uuid(),
  requestedByUserId: z.string().uuid(),
  fieldKey: EmployeeChangeRequestFieldSchema,
  currentValueSnapshot: z.string().nullable(),
  // Batch 291-293 Tier C fix (20260731210000, Finding 6, closes ISS-2026-092):
  // requestedValue is now nullable -- app.get_employee_change_requests (the
  // new masked read RPC) nulls it, like currentValueSnapshot/reason/
  // decidedReason, unless the caller is the employee themselves or holds
  // HRS:View personal data (it is always a classified personal_email/phone/
  // address value, per employee_change_requests_field_key_check).
  requestedValue: z.string().nullable(),
  reason: z.string().nullable(),
  status: EmployeeChangeRequestStatusSchema,
  decidedBy: z.string().nullable(),
  decidedAt: z.string().nullable(),
  decidedReason: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
});
export type EmployeeChangeRequest = z.infer<typeof EmployeeChangeRequestSchema>;

export function parseEmployeeChangeRequest(row: Record<string, unknown>): EmployeeChangeRequest {
  return EmployeeChangeRequestSchema.parse({
    id: row.id,
    masterRecordId: row.master_record_id,
    requestedByUserId: row.requested_by_user_id,
    fieldKey: row.field_key,
    currentValueSnapshot: row.current_value_snapshot ?? null,
    requestedValue: row.requested_value ?? null,
    reason: row.reason ?? null,
    status: row.status,
    decidedBy: row.decided_by ?? null,
    decidedAt: row.decided_at ?? null,
    decidedReason: row.decided_reason ?? null,
    recordVersion: row.record_version,
    createdAt: row.created_at,
  });
}

/** app.get_my_employee_profile's own projection -- always unmasked (it is always the caller's own data), never carries revision/suspend/terminate/archive/leave reason columns (own-profile self-service has no reason to see internal HR administrative notes). */
export const EmployeeOwnProfileSchema = z.object({
  masterRecordId: z.string().uuid(),
  employeeNumber: z.string(),
  tenantId: z.string().uuid(),
  userId: z.string().uuid().nullable(),
  fullName: z.string(),
  employmentType: EmploymentTypeSchema,
  lifecycleStatus: EmployeeLifecycleStatusSchema,
  intakeSource: EmployeeIntakeSourceSchema,
  workEmail: z.string().nullable(),
  workPhone: z.string().nullable(),
  personalEmail: z.string().nullable(),
  personalPhone: z.string().nullable(),
  nationalIdNumber: z.string().nullable(),
  dateOfBirth: z.string().nullable(),
  gender: z.string().nullable(),
  personalAddressStreet: z.string().nullable(),
  personalAddressCity: z.string().nullable(),
  personalAddressProvince: z.string().nullable(),
  personalAddressPostalCode: z.string().nullable(),
  personalAddressCountry: z.string().nullable(),
  hireDate: z.string().nullable(),
  probationEndDate: z.string().nullable(),
  employmentEndDate: z.string().nullable(),
  companyOrgUnitId: z.string().uuid().nullable(),
  branchOrgUnitId: z.string().uuid().nullable(),
  departmentOrgUnitId: z.string().uuid().nullable(),
  positionTitle: z.string().nullable(),
  managerEmployeeId: z.string().uuid().nullable(),
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type EmployeeOwnProfile = z.infer<typeof EmployeeOwnProfileSchema>;

export function parseEmployeeOwnProfile(row: Record<string, unknown>): EmployeeOwnProfile {
  return EmployeeOwnProfileSchema.parse({
    masterRecordId: row.master_record_id,
    employeeNumber: row.employee_number,
    tenantId: row.tenant_id,
    userId: row.user_id ?? null,
    fullName: row.full_name,
    employmentType: row.employment_type,
    lifecycleStatus: row.lifecycle_status,
    intakeSource: row.intake_source,
    workEmail: row.work_email ?? null,
    workPhone: row.work_phone ?? null,
    personalEmail: row.personal_email ?? null,
    personalPhone: row.personal_phone ?? null,
    nationalIdNumber: row.national_id_number ?? null,
    dateOfBirth: row.date_of_birth ?? null,
    gender: row.gender ?? null,
    personalAddressStreet: row.personal_address_street ?? null,
    personalAddressCity: row.personal_address_city ?? null,
    personalAddressProvince: row.personal_address_province ?? null,
    personalAddressPostalCode: row.personal_address_postal_code ?? null,
    personalAddressCountry: row.personal_address_country ?? null,
    hireDate: row.hire_date ?? null,
    probationEndDate: row.probation_end_date ?? null,
    employmentEndDate: row.employment_end_date ?? null,
    companyOrgUnitId: row.company_org_unit_id ?? null,
    branchOrgUnitId: row.branch_org_unit_id ?? null,
    departmentOrgUnitId: row.department_org_unit_id ?? null,
    positionTitle: row.position_title ?? null,
    managerEmployeeId: row.manager_employee_id ?? null,
    recordVersion: row.record_version,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

// --- Mutation input schemas ---

export const CreateEmployeeDraftInputSchema = z.object({
  tenantId: z.string().uuid(),
  fullName: z.string().min(1),
  employmentType: EmploymentTypeSchema,
  workEmail: z.string().nullable(),
  personalEmail: z.string().nullable(),
  personalPhone: z.string().nullable(),
  nationalIdNumber: z.string().nullable(),
  dateOfBirth: z.string().nullable(),
  gender: z.string().nullable(),
  hireDate: z.string().nullable(),
  companyOrgUnitId: z.string().uuid().nullable(),
  branchOrgUnitId: z.string().uuid().nullable(),
  departmentOrgUnitId: z.string().uuid().nullable(),
  positionTitle: z.string().nullable(),
  managerEmployeeId: z.string().uuid().nullable(),
  userId: z.string().uuid().nullable(),
  employeeNumber: z.string().nullable(),
  intakeSource: z.enum(["hr_created"]),
  idempotencyKey: z.string().nullable(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
  // ISS-2026-065 closure: optional, defaults to current_date server-side when
  // omitted -- fully backward-compatible for every existing caller. Always
  // materializes immediately regardless of this date (this migration's own
  // header, decision 5); backdating requires HRS:Override + a non-empty
  // backdateReason.
  effectiveDate: z.string().optional(),
  backdateReason: z.string().optional(),
});
export type CreateEmployeeDraftInput = z.input<typeof CreateEmployeeDraftInputSchema>;

const RecordActionInputBase = {
  masterRecordId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
};

export const UpdateEmployeeDraftInputSchema = z.object({
  ...RecordActionInputBase,
  fullName: z.string().min(1),
  employmentType: EmploymentTypeSchema,
  workEmail: z.string().nullable(),
  personalEmail: z.string().nullable(),
  personalPhone: z.string().nullable(),
  nationalIdNumber: z.string().nullable(),
  dateOfBirth: z.string().nullable(),
  gender: z.string().nullable(),
  hireDate: z.string().nullable(),
  probationEndDate: z.string().nullable(),
  companyOrgUnitId: z.string().uuid().nullable(),
  branchOrgUnitId: z.string().uuid().nullable(),
  departmentOrgUnitId: z.string().uuid().nullable(),
  positionTitle: z.string().nullable(),
  managerEmployeeId: z.string().uuid().nullable(),
  // ISS-2026-065 closure: see CreateEmployeeDraftInputSchema's own identical
  // fields -- same semantics (always immediate; backdating gated).
  effectiveDate: z.string().optional(),
  backdateReason: z.string().optional(),
});
export type UpdateEmployeeDraftInput = z.input<typeof UpdateEmployeeDraftInputSchema>;

export const SubmitEmployeeForApprovalInputSchema = z.object(RecordActionInputBase);
export type SubmitEmployeeForApprovalInput = z.input<typeof SubmitEmployeeForApprovalInputSchema>;

export const DecideEmployeeApprovalInputSchema = z.object({
  ...RecordActionInputBase,
  decision: EmployeeReviewDecisionSchema,
  reason: z.string().nullable(),
});
export type DecideEmployeeApprovalInput = z.input<typeof DecideEmployeeApprovalInputSchema>;

export const ActivateEmployeeInputSchema = z.object(RecordActionInputBase);
export type ActivateEmployeeInput = z.input<typeof ActivateEmployeeInputSchema>;

export const LinkEmployeeUserInputSchema = z.object({ ...RecordActionInputBase, userId: z.string().uuid() });
export type LinkEmployeeUserInput = z.input<typeof LinkEmployeeUserInputSchema>;

export const StartEmployeeLeaveInputSchema = z.object({ ...RecordActionInputBase, reason: z.string().nullable() });
export type StartEmployeeLeaveInput = z.input<typeof StartEmployeeLeaveInputSchema>;

export const EndEmployeeLeaveInputSchema = z.object(RecordActionInputBase);
export type EndEmployeeLeaveInput = z.input<typeof EndEmployeeLeaveInputSchema>;

// ISS-2026-065 closure: effectiveDate is optional on every one of the 5 real
// lifecycle-transition RPCs below -- a future date schedules the transition
// (deferred to app.activate_due_employee_lifecycle_transitions), a past date
// backdates it (gated at HRS:Override + a mandatory reason server-side; suspend/
// terminate/reactivate are already Override-gated unconditionally, so nothing
// widens for them -- see the migration's own header, decision 4).

export const SuspendEmployeeInputSchema = z.object({ ...RecordActionInputBase, reason: z.string().min(1), effectiveDate: z.string().optional() });
export type SuspendEmployeeInput = z.input<typeof SuspendEmployeeInputSchema>;

export const ReactivateEmployeeInputSchema = z.object({ ...RecordActionInputBase, effectiveDate: z.string().optional(), backdateReason: z.string().optional() });
export type ReactivateEmployeeInput = z.input<typeof ReactivateEmployeeInputSchema>;

export const TerminateEmployeeInputSchema = z.object({
  ...RecordActionInputBase,
  reason: z.string().min(1),
  employmentEndDate: z.string().min(1),
  effectiveDate: z.string().optional(),
});
export type TerminateEmployeeInput = z.input<typeof TerminateEmployeeInputSchema>;

export const ArchiveEmployeeProfileInputSchema = z.object({ ...RecordActionInputBase, reason: z.string().nullable(), effectiveDate: z.string().optional() });
export type ArchiveEmployeeProfileInput = z.input<typeof ArchiveEmployeeProfileInputSchema>;

export const TransferEmployeeInputSchema = z.object({
  ...RecordActionInputBase,
  companyOrgUnitId: z.string().uuid().nullable(),
  branchOrgUnitId: z.string().uuid().nullable(),
  departmentOrgUnitId: z.string().uuid().nullable(),
  positionTitle: z.string().nullable(),
  managerEmployeeId: z.string().uuid().nullable(),
  reason: z.string().nullable(),
  effectiveDate: z.string().optional(),
});
export type TransferEmployeeInput = z.input<typeof TransferEmployeeInputSchema>;

// --- ISS-2026-065 closure: the "as of" read and the maintenance sweep ---

export const GetEmployeeLifecycleAsOfInputSchema = z.object({
  masterRecordId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  asOf: z.string().optional(),
});
export type GetEmployeeLifecycleAsOfInput = z.input<typeof GetEmployeeLifecycleAsOfInputSchema>;

/** app.activate_due_employee_lifecycle_transitions -- HRS:Override-gated, idempotent, NOT wired to any live scheduler in this repository (disclosed NOT_RUN; callable on demand). */
export const ActivateDueEmployeeLifecycleTransitionsInputSchema = z.object({
  tenantId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type ActivateDueEmployeeLifecycleTransitionsInput = z.input<typeof ActivateDueEmployeeLifecycleTransitionsInputSchema>;

// ISS-2026-064 item 2 closure: app.initiate_employee_document_upload. classification
// is nullable (never a hardcoded literal) so the tenant's own published
// default_classification for 'employee_document' applies when the caller does not
// name one. Returns a FileSummary (server/contracts/document/document.ts) -- this RPC
// is callable directly by `authenticated`, unlike the raw storage_path-carrying
// app.initiate_file_upload primitive underneath it.
export const InitiateEmployeeDocumentUploadInputSchema = z.object({
  masterRecordId: z.string().uuid(),
  originalFilename: z.string().min(1),
  mimeType: z.string().min(1),
  sizeBytes: z.number().int().positive(),
  classification: ClassificationSchema.nullable().default(null),
  idempotencyKey: z.string().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type InitiateEmployeeDocumentUploadInput = z.input<typeof InitiateEmployeeDocumentUploadInputSchema>;

export const AddEmployeeEmergencyContactInputSchema = z.object({
  masterRecordId: z.string().uuid(),
  name: z.string().min(1),
  relationship: z.string().nullable(),
  phone: z.string().nullable(),
  email: z.string().nullable(),
  isPrimary: z.boolean(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type AddEmployeeEmergencyContactInput = z.input<typeof AddEmployeeEmergencyContactInputSchema>;

export const UpdateEmployeeEmergencyContactInputSchema = z.object({
  contactId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  name: z.string().min(1),
  relationship: z.string().nullable(),
  phone: z.string().nullable(),
  email: z.string().nullable(),
  isPrimary: z.boolean(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type UpdateEmployeeEmergencyContactInput = z.input<typeof UpdateEmployeeEmergencyContactInputSchema>;

export const RemoveEmployeeEmergencyContactInputSchema = z.object({
  contactId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type RemoveEmployeeEmergencyContactInput = z.input<typeof RemoveEmployeeEmergencyContactInputSchema>;

export const FlagEmployeeDuplicateCandidateInputSchema = z.object({
  sourceMasterRecordId: z.string().uuid(),
  candidateMasterRecordId: z.string().uuid(),
  similarityBasis: z.string().min(1),
  similarityScore: z.number().nullable(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type FlagEmployeeDuplicateCandidateInput = z.input<typeof FlagEmployeeDuplicateCandidateInputSchema>;

export const DecideEmployeeDuplicateCandidateInputSchema = z.object({
  candidateId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  decision: z.enum(["linked", "dismissed"]),
  reason: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type DecideEmployeeDuplicateCandidateInput = z.input<typeof DecideEmployeeDuplicateCandidateInputSchema>;

/** No actorLabel field -- app.request_employee_change's own signature has no p_actor_label parameter (identity-match-gated, not an HR-actor-labeled action). */
export const RequestEmployeeChangeInputSchema = z.object({
  masterRecordId: z.string().uuid(),
  fieldKey: EmployeeChangeRequestFieldSchema,
  requestedValue: z.string().min(1),
  reason: z.string().nullable(),
  actorAuthUserId: z.string().uuid(),
});
export type RequestEmployeeChangeInput = z.input<typeof RequestEmployeeChangeInputSchema>;

export const DecideEmployeeChangeRequestInputSchema = z.object({
  requestId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  decision: z.enum(["approved", "rejected"]),
  decidedReason: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type DecideEmployeeChangeRequestInput = z.input<typeof DecideEmployeeChangeRequestInputSchema>;

// --- Staged import (decision 11, PLT-131/132) ---
// Mirrors ValidateVendorRateImportRowInputSchema/CommitVendorRateImportJobInputSchema
// (server/contracts/procurement-rate/procurement-rate.ts) exactly -- the same
// generic-schema-plus-domain-adapter shape every PLT-131/132 adopter uses.

/** Server-mediated only (service_role client) -- app.validate_employee_import_row is granted to service_role only (it reaches neither app.evaluate_permission nor app.assert_actor_is_session_identity, so it is never exposed to the authenticated role directly). */
export const ValidateEmployeeImportRowInputSchema = z.object({
  stagingRowId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type ValidateEmployeeImportRowInput = z.input<typeof ValidateEmployeeImportRowInputSchema>;

export const CommitEmployeeImportJobInputSchema = z.object({
  jobId: z.string().uuid(),
  allowPartial: z.boolean().default(false),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type CommitEmployeeImportJobInput = z.input<typeof CommitEmployeeImportJobInputSchema>;

// --- Platform identity reactivation (PLT-107/110, HRT-295 / ISS-2026-108) ---
// app.reactivate_user_after_rehire has no p_expected_version -- it targets the
// linked app.users row, not app.employees, mirroring
// app.request_onboarding_access_revocation's own identical shape rather than
// RecordActionInputBase.

export const ReactivateUserAfterRehireInputSchema = z.object({
  masterRecordId: z.string().uuid(),
  reason: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type ReactivateUserAfterRehireInput = z.input<typeof ReactivateUserAfterRehireInputSchema>;
