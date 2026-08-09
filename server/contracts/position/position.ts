/**
 * Organization and Position Linkage contract (HRT-275, CG-S12-HRT-003). Mirrors
 * supabase/migrations/20260730840000_create_hris_organization_position_linkage.sql's
 * app.position_grades/app.positions/app.employee_position_assignments shapes and
 * their RPCs. Follows the exact directory convention HRT-274/PRC-251 established:
 * Zod schemas here, list/read projections in server/queries/position.ts,
 * RPC-calling mutation wrappers with an enumerated error-code type in
 * server/mutations/position.ts.
 *
 * Position/grade are HR-governed, tenant-scoped catalogue data -- NOT routed
 * through app.master_records (unlike vendor/driver/employee), and organization
 * write itself stays Platform-governed and unchanged (this domain never creates,
 * edits, or moves an app.org_units row). app.employee_position_assignments is the
 * effective-dated source of truth for an employee's position/grade/manager history;
 * app.employees.position_id/manager_employee_id/company_org_unit_id/
 * branch_org_unit_id/department_org_unit_id/position_title are a synced
 * convenience cache (server/contracts/employee/employee.ts's own EmployeeProfile
 * shape already carries positionId -- HRT-274's own additive column).
 */

import { z } from "zod";

export const POSITION_GRADE_STATUSES = ["active", "inactive"] as const;
export const PositionGradeStatusSchema = z.enum(POSITION_GRADE_STATUSES);
export type PositionGradeStatus = z.infer<typeof PositionGradeStatusSchema>;

export const POSITION_STATUSES = ["active", "inactive"] as const;
export const PositionStatusSchema = z.enum(POSITION_STATUSES);
export type PositionStatus = z.infer<typeof PositionStatusSchema>;

export const ASSIGNMENT_TYPES = ["primary", "secondary"] as const;
export const AssignmentTypeSchema = z.enum(ASSIGNMENT_TYPES);
export type AssignmentType = z.infer<typeof AssignmentTypeSchema>;

export const ASSIGNMENT_STATUSES = ["pending_approval", "active", "rejected", "cancelled"] as const;
export const AssignmentStatusSchema = z.enum(ASSIGNMENT_STATUSES);
export type AssignmentStatus = z.infer<typeof AssignmentStatusSchema>;

export const CHANGE_REASONS = ["hire", "transfer", "promotion", "demotion", "lateral_move", "reorganization", "secondary_assignment", "correction"] as const;
export const ChangeReasonSchema = z.enum(CHANGE_REASONS);
export type ChangeReason = z.infer<typeof ChangeReasonSchema>;

export const ASSIGNMENT_DECISIONS = ["approve", "reject"] as const;
export const AssignmentDecisionSchema = z.enum(ASSIGNMENT_DECISIONS);
export type AssignmentDecision = z.infer<typeof AssignmentDecisionSchema>;

// --- Core rows ---

export const PositionGradeSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  code: z.string(),
  name: z.string(),
  rank: z.number().int(),
  status: PositionGradeStatusSchema,
  description: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type PositionGrade = z.infer<typeof PositionGradeSchema>;

export function parsePositionGrade(row: Record<string, unknown>): PositionGrade {
  return PositionGradeSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    code: row.code,
    name: row.name,
    rank: row.rank,
    status: row.status,
    description: row.description ?? null,
    recordVersion: row.record_version,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

export const PositionSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  code: z.string(),
  title: z.string(),
  orgUnitId: z.string().uuid(),
  gradeId: z.string().uuid().nullable(),
  capacity: z.number().int().positive(),
  status: PositionStatusSchema,
  description: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type Position = z.infer<typeof PositionSchema>;

export function parsePosition(row: Record<string, unknown>): Position {
  return PositionSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    code: row.code,
    title: row.title,
    orgUnitId: row.org_unit_id,
    gradeId: row.grade_id ?? null,
    capacity: row.capacity,
    status: row.status,
    description: row.description ?? null,
    recordVersion: row.record_version,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

/** app.list_positions' own projection -- includes the computed current_headcount, never a client-side count. */
export const PositionListRowSchema = z.object({
  id: z.string().uuid(),
  code: z.string(),
  title: z.string(),
  orgUnitId: z.string().uuid(),
  gradeId: z.string().uuid().nullable(),
  capacity: z.number().int().positive(),
  status: PositionStatusSchema,
  currentHeadcount: z.number().int().nonnegative(),
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type PositionListRow = z.infer<typeof PositionListRowSchema>;

export function parsePositionListRow(row: Record<string, unknown>): PositionListRow {
  return PositionListRowSchema.parse({
    id: row.id,
    code: row.code,
    title: row.title,
    orgUnitId: row.org_unit_id,
    gradeId: row.grade_id ?? null,
    capacity: row.capacity,
    status: row.status,
    currentHeadcount: row.current_headcount,
    recordVersion: row.record_version,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

/** app.get_position's own detail projection -- adds capacity_remaining alongside current_headcount. */
export const PositionDetailSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  code: z.string(),
  title: z.string(),
  orgUnitId: z.string().uuid(),
  gradeId: z.string().uuid().nullable(),
  capacity: z.number().int().positive(),
  status: PositionStatusSchema,
  description: z.string().nullable(),
  currentHeadcount: z.number().int().nonnegative(),
  capacityRemaining: z.number().int().nonnegative(),
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type PositionDetail = z.infer<typeof PositionDetailSchema>;

export function parsePositionDetail(row: Record<string, unknown>): PositionDetail {
  return PositionDetailSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    code: row.code,
    title: row.title,
    orgUnitId: row.org_unit_id,
    gradeId: row.grade_id ?? null,
    capacity: row.capacity,
    status: row.status,
    description: row.description ?? null,
    currentHeadcount: row.current_headcount,
    capacityRemaining: row.capacity_remaining,
    recordVersion: row.record_version,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

/** app.export_positions' own scoped projection (section 14 "scoped export") -- no compensation column exists to omit, but the projection is still explicit and selective. */
export const PositionExportRowSchema = z.object({
  code: z.string(),
  title: z.string(),
  orgUnitId: z.string().uuid(),
  gradeCode: z.string().nullable(),
  capacity: z.number().int().positive(),
  status: PositionStatusSchema,
});
export type PositionExportRow = z.infer<typeof PositionExportRowSchema>;

export function parsePositionExportRow(row: Record<string, unknown>): PositionExportRow {
  return PositionExportRowSchema.parse({
    code: row.code,
    title: row.title,
    orgUnitId: row.org_unit_id,
    gradeCode: row.grade_code ?? null,
    capacity: row.capacity,
    status: row.status,
  });
}

export const EmployeePositionAssignmentSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  masterRecordId: z.string().uuid(),
  positionId: z.string().uuid(),
  gradeId: z.string().uuid().nullable(),
  managerEmployeeId: z.string().uuid().nullable(),
  assignmentType: AssignmentTypeSchema,
  allocationPct: z.coerce.number(),
  effectiveStartDate: z.string(),
  effectiveEndDate: z.string().nullable(),
  status: AssignmentStatusSchema,
  changeReason: ChangeReasonSchema,
  reasonNote: z.string().nullable(),
  previousAssignmentId: z.string().uuid().nullable(),
  decidedBy: z.string().nullable(),
  decidedAt: z.string().nullable(),
  decidedReason: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type EmployeePositionAssignment = z.infer<typeof EmployeePositionAssignmentSchema>;

export function parseEmployeePositionAssignment(row: Record<string, unknown>): EmployeePositionAssignment {
  return EmployeePositionAssignmentSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    masterRecordId: row.master_record_id,
    positionId: row.position_id,
    gradeId: row.grade_id ?? null,
    managerEmployeeId: row.manager_employee_id ?? null,
    assignmentType: row.assignment_type,
    allocationPct: row.allocation_pct,
    effectiveStartDate: row.effective_start_date,
    effectiveEndDate: row.effective_end_date ?? null,
    status: row.status,
    changeReason: row.change_reason,
    reasonNote: row.reason_note ?? null,
    previousAssignmentId: row.previous_assignment_id ?? null,
    decidedBy: row.decided_by ?? null,
    decidedAt: row.decided_at ?? null,
    decidedReason: row.decided_reason ?? null,
    recordVersion: row.record_version,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

/** app.preview_employee_position_assignment_impact's own projection (decision 6) -- downstreamDisclosure is always a real, non-empty string naming the not-yet-integrated systems, never fabricated data for them. */
export const AssignmentImpactPreviewSchema = z.object({
  currentPositionId: z.string().uuid().nullable(),
  currentPositionTitle: z.string().nullable(),
  currentManagerEmployeeId: z.string().uuid().nullable(),
  proposedPositionTitle: z.string(),
  proposedGradeId: z.string().uuid().nullable(),
  proposedCompanyOrgUnitId: z.string().uuid().nullable(),
  proposedBranchOrgUnitId: z.string().uuid().nullable(),
  proposedDepartmentOrgUnitId: z.string().uuid().nullable(),
  positionCapacity: z.number().int().positive(),
  positionCurrentHeadcount: z.number().int().nonnegative(),
  positionCapacityRemaining: z.number().int().nonnegative(),
  wouldCreateManagerCycle: z.boolean(),
  targetOrgUnitActive: z.boolean(),
  directReportCount: z.number().int().nonnegative(),
  pendingChangeRequestCount: z.number().int().nonnegative(),
  pendingDuplicateCandidateCount: z.number().int().nonnegative(),
  downstreamDisclosure: z.string(),
});
export type AssignmentImpactPreview = z.infer<typeof AssignmentImpactPreviewSchema>;

export function parseAssignmentImpactPreview(row: Record<string, unknown>): AssignmentImpactPreview {
  return AssignmentImpactPreviewSchema.parse({
    currentPositionId: row.current_position_id ?? null,
    currentPositionTitle: row.current_position_title ?? null,
    currentManagerEmployeeId: row.current_manager_employee_id ?? null,
    proposedPositionTitle: row.proposed_position_title,
    proposedGradeId: row.proposed_grade_id ?? null,
    proposedCompanyOrgUnitId: row.proposed_company_org_unit_id ?? null,
    proposedBranchOrgUnitId: row.proposed_branch_org_unit_id ?? null,
    proposedDepartmentOrgUnitId: row.proposed_department_org_unit_id ?? null,
    positionCapacity: row.position_capacity,
    positionCurrentHeadcount: row.position_current_headcount,
    positionCapacityRemaining: row.position_capacity_remaining,
    wouldCreateManagerCycle: row.would_create_manager_cycle,
    targetOrgUnitActive: row.target_org_unit_active,
    directReportCount: row.direct_report_count,
    pendingChangeRequestCount: row.pending_change_request_count,
    pendingDuplicateCandidateCount: row.pending_duplicate_candidate_count,
    downstreamDisclosure: row.downstream_disclosure as string,
  });
}

/** app.get_employee_manager_chain's own projection (section 14 "hierarchy read"). */
export const ManagerChainRowSchema = z.object({
  depth: z.number().int().positive(),
  masterRecordId: z.string().uuid(),
  employeeNumber: z.string(),
  fullName: z.string(),
  positionTitle: z.string().nullable(),
});
export type ManagerChainRow = z.infer<typeof ManagerChainRowSchema>;

export function parseManagerChainRow(row: Record<string, unknown>): ManagerChainRow {
  return ManagerChainRowSchema.parse({
    depth: row.depth,
    masterRecordId: row.master_record_id,
    employeeNumber: row.employee_number,
    fullName: row.full_name,
    positionTitle: row.position_title ?? null,
  });
}

/** app.get_org_position_tree's own projection (section 15 "organization-linked position tree") -- positionId is null for an org node with no position defined yet (LEFT JOIN). */
export const OrgPositionTreeRowSchema = z.object({
  orgUnitId: z.string().uuid(),
  orgUnitCode: z.string(),
  orgUnitName: z.string(),
  unitType: z.string(),
  depth: z.number().int().nonnegative(),
  positionId: z.string().uuid().nullable(),
  positionCode: z.string().nullable(),
  positionTitle: z.string().nullable(),
  capacity: z.number().int().positive().nullable(),
  currentHeadcount: z.number().int().nonnegative().nullable(),
});
export type OrgPositionTreeRow = z.infer<typeof OrgPositionTreeRowSchema>;

export function parseOrgPositionTreeRow(row: Record<string, unknown>): OrgPositionTreeRow {
  return OrgPositionTreeRowSchema.parse({
    orgUnitId: row.org_unit_id,
    orgUnitCode: row.org_unit_code,
    orgUnitName: row.org_unit_name,
    unitType: row.unit_type,
    depth: row.depth,
    positionId: row.position_id ?? null,
    positionCode: row.position_code ?? null,
    positionTitle: row.position_title ?? null,
    capacity: row.capacity ?? null,
    currentHeadcount: row.current_headcount ?? null,
  });
}

// --- Mutation input schemas ---

export const CreatePositionGradeInputSchema = z.object({
  tenantId: z.string().uuid(),
  code: z.string().min(1),
  name: z.string().min(1),
  rank: z.number().int().nullable(),
  description: z.string().nullable(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type CreatePositionGradeInput = z.input<typeof CreatePositionGradeInputSchema>;

export const UpdatePositionGradeInputSchema = z.object({
  id: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  name: z.string().min(1),
  rank: z.number().int().nullable(),
  description: z.string().nullable(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type UpdatePositionGradeInput = z.input<typeof UpdatePositionGradeInputSchema>;

export const SetPositionGradeStatusInputSchema = z.object({
  id: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  newStatus: PositionGradeStatusSchema,
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type SetPositionGradeStatusInput = z.input<typeof SetPositionGradeStatusInputSchema>;

export const CreatePositionInputSchema = z.object({
  tenantId: z.string().uuid(),
  code: z.string().min(1),
  title: z.string().min(1),
  orgUnitId: z.string().uuid(),
  gradeId: z.string().uuid().nullable(),
  capacity: z.number().int().positive().nullable(),
  description: z.string().nullable(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type CreatePositionInput = z.input<typeof CreatePositionInputSchema>;

export const UpdatePositionInputSchema = z.object({
  id: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  title: z.string().min(1),
  orgUnitId: z.string().uuid(),
  gradeId: z.string().uuid().nullable(),
  capacity: z.number().int().positive().nullable(),
  description: z.string().nullable(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type UpdatePositionInput = z.input<typeof UpdatePositionInputSchema>;

export const SetPositionStatusInputSchema = z.object({
  id: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  newStatus: PositionStatusSchema,
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type SetPositionStatusInput = z.input<typeof SetPositionStatusInputSchema>;

export const ProposeEmployeePositionAssignmentInputSchema = z.object({
  masterRecordId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  positionId: z.string().uuid(),
  gradeId: z.string().uuid().nullable(),
  managerEmployeeId: z.string().uuid().nullable(),
  assignmentType: AssignmentTypeSchema,
  allocationPct: z.number().positive().max(100).nullable(),
  effectiveStartDate: z.string().min(1),
  effectiveEndDate: z.string().nullable(),
  changeReason: ChangeReasonSchema,
  reasonNote: z.string().nullable(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type ProposeEmployeePositionAssignmentInput = z.input<typeof ProposeEmployeePositionAssignmentInputSchema>;

export const DecideEmployeePositionAssignmentInputSchema = z.object({
  assignmentId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  decision: AssignmentDecisionSchema,
  reason: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type DecideEmployeePositionAssignmentInput = z.input<typeof DecideEmployeePositionAssignmentInputSchema>;

export const CancelEmployeePositionAssignmentInputSchema = z.object({
  assignmentId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  reason: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type CancelEmployeePositionAssignmentInput = z.input<typeof CancelEmployeePositionAssignmentInputSchema>;

export const ActivateDueEmployeePositionAssignmentsInputSchema = z.object({
  tenantId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type ActivateDueEmployeePositionAssignmentsInput = z.input<typeof ActivateDueEmployeePositionAssignmentsInputSchema>;
