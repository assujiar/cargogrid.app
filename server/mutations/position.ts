/**
 * Organization and Position Linkage mutation primitives (HRT-275, CG-S12-HRT-003).
 * Thin, typed wrappers around every position/grade CRUD and employee-assignment
 * propose/decide/cancel/sweep RPC in
 * supabase/migrations/20260730840000_create_hris_organization_position_linkage.sql.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  CreatePositionGradeInputSchema,
  UpdatePositionGradeInputSchema,
  SetPositionGradeStatusInputSchema,
  CreatePositionInputSchema,
  UpdatePositionInputSchema,
  SetPositionStatusInputSchema,
  ProposeEmployeePositionAssignmentInputSchema,
  DecideEmployeePositionAssignmentInputSchema,
  CancelEmployeePositionAssignmentInputSchema,
  ActivateDueEmployeePositionAssignmentsInputSchema,
  ProposeBulkEmployeePositionAssignmentInputSchema,
  parsePositionGrade,
  parsePosition,
  parseEmployeePositionAssignment,
  type CreatePositionGradeInput,
  type UpdatePositionGradeInput,
  type SetPositionGradeStatusInput,
  type CreatePositionInput,
  type UpdatePositionInput,
  type SetPositionStatusInput,
  type ProposeEmployeePositionAssignmentInput,
  type DecideEmployeePositionAssignmentInput,
  type CancelEmployeePositionAssignmentInput,
  type ActivateDueEmployeePositionAssignmentsInput,
  type ProposeBulkEmployeePositionAssignmentInput,
  type PositionGrade,
  type Position,
  type EmployeePositionAssignment,
} from "../contracts/position/position.ts";
import { resolveRequestClientIp } from "../../lib/security/client-ip.ts";

export type PositionMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const POSITION_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "insufficient_privilege",
  "invalid_position_grade",
  "position_grade_not_found",
  "position_grade_code_conflict",
  "position_grade_in_use",
  "invalid_status",
  "stale_version",
  "invalid_position",
  "position_not_found",
  "position_code_conflict",
  "position_in_use",
  "position_inactive",
  "org_unit_not_found",
  "org_unit_inactive",
  "employee_not_found",
  "employee_closed",
  "invalid_assignment_type",
  "invalid_change_reason",
  "invalid_effective_range",
  "cyclic_reporting_line",
  "invalid_decision",
  "reason_required",
  "assignment_not_found",
  "assignment_not_pending",
  "assignment_not_cancellable",
  "assignment_overlap",
  "position_over_capacity",
  "invalid_response",
  "invalid_items",
  "invalid_item",
  "too_many_items",
  "duplicate_employee",
] as const;
type KnownPositionMutationErrorCode = (typeof POSITION_KNOWN_MUTATION_ERROR_CODES)[number];
export type PositionMutationErrorCode = KnownPositionMutationErrorCode | "mutation_failed";

export class PositionMutationError extends Error {
  readonly code: PositionMutationErrorCode;

  constructor(code: PositionMutationErrorCode, message: string) {
    super(message);
    this.name = "PositionMutationError";
    this.code = code;
  }
}

function classifyError(message: string): PositionMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (POSITION_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "") ? (prefix as KnownPositionMutationErrorCode) : "mutation_failed";
}

function firstRow(data: unknown): Record<string, unknown> | null {
  const row = Array.isArray(data) ? data[0] : data;
  return row && typeof row === "object" ? (row as Record<string, unknown>) : null;
}

// --- Position grade CRUD ---

function parseGradeResponse(data: unknown, rpcName: string): PositionGrade {
  const row = firstRow(data);
  if (!row) throw new PositionMutationError("invalid_response", `${rpcName} returned no row`);
  return parsePositionGrade(row);
}

export async function createPositionGrade(client: PositionMutationRpcClient, input: CreatePositionGradeInput): Promise<PositionGrade> {
  const parsed = CreatePositionGradeInputSchema.parse(input);
  const { data, error } = await client.rpc("create_position_grade", {
    p_tenant_id: parsed.tenantId,
    p_code: parsed.code,
    p_name: parsed.name,
    p_rank: parsed.rank ?? null,
    p_description: parsed.description ?? null,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new PositionMutationError(classifyError(error.message), error.message);
  return parseGradeResponse(data, "create_position_grade");
}

export async function updatePositionGrade(client: PositionMutationRpcClient, input: UpdatePositionGradeInput): Promise<PositionGrade> {
  const parsed = UpdatePositionGradeInputSchema.parse(input);
  const { data, error } = await client.rpc("update_position_grade", {
    p_id: parsed.id,
    p_expected_version: parsed.expectedVersion,
    p_name: parsed.name,
    p_rank: parsed.rank ?? null,
    p_description: parsed.description ?? null,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new PositionMutationError(classifyError(error.message), error.message);
  return parseGradeResponse(data, "update_position_grade");
}

export async function setPositionGradeStatus(client: PositionMutationRpcClient, input: SetPositionGradeStatusInput): Promise<PositionGrade> {
  const parsed = SetPositionGradeStatusInputSchema.parse(input);
  const { data, error } = await client.rpc("set_position_grade_status", {
    p_id: parsed.id,
    p_expected_version: parsed.expectedVersion,
    p_new_status: parsed.newStatus,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new PositionMutationError(classifyError(error.message), error.message);
  return parseGradeResponse(data, "set_position_grade_status");
}

// --- Position CRUD ---

function parsePositionResponse(data: unknown, rpcName: string): Position {
  const row = firstRow(data);
  if (!row) throw new PositionMutationError("invalid_response", `${rpcName} returned no row`);
  return parsePosition(row);
}

export async function createPosition(client: PositionMutationRpcClient, input: CreatePositionInput): Promise<Position> {
  const parsed = CreatePositionInputSchema.parse(input);
  const { data, error } = await client.rpc("create_position", {
    p_tenant_id: parsed.tenantId,
    p_code: parsed.code,
    p_title: parsed.title,
    p_org_unit_id: parsed.orgUnitId,
    p_grade_id: parsed.gradeId ?? null,
    p_capacity: parsed.capacity ?? null,
    p_description: parsed.description ?? null,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new PositionMutationError(classifyError(error.message), error.message);
  return parsePositionResponse(data, "create_position");
}

export async function updatePosition(client: PositionMutationRpcClient, input: UpdatePositionInput): Promise<Position> {
  const parsed = UpdatePositionInputSchema.parse(input);
  const { data, error } = await client.rpc("update_position", {
    p_id: parsed.id,
    p_expected_version: parsed.expectedVersion,
    p_title: parsed.title,
    p_org_unit_id: parsed.orgUnitId,
    p_grade_id: parsed.gradeId ?? null,
    p_capacity: parsed.capacity ?? null,
    p_description: parsed.description ?? null,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new PositionMutationError(classifyError(error.message), error.message);
  return parsePositionResponse(data, "update_position");
}

export async function setPositionStatus(client: PositionMutationRpcClient, input: SetPositionStatusInput): Promise<Position> {
  const parsed = SetPositionStatusInputSchema.parse(input);
  const { data, error } = await client.rpc("set_position_status", {
    p_id: parsed.id,
    p_expected_version: parsed.expectedVersion,
    p_new_status: parsed.newStatus,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new PositionMutationError(classifyError(error.message), error.message);
  return parsePositionResponse(data, "set_position_status");
}

// --- Employee <-> position/grade/manager assignment workflow ---

function parseAssignmentResponse(data: unknown, rpcName: string): EmployeePositionAssignment {
  const row = firstRow(data);
  if (!row) throw new PositionMutationError("invalid_response", `${rpcName} returned no row`);
  return parseEmployeePositionAssignment(row);
}

/** Creates a status=pending_approval proposal -- never immediately effective (section 21 main flow, step 1). */
export async function proposeEmployeePositionAssignment(client: PositionMutationRpcClient, input: ProposeEmployeePositionAssignmentInput): Promise<EmployeePositionAssignment> {
  const parsed = ProposeEmployeePositionAssignmentInputSchema.parse(input);
  const { data, error } = await client.rpc("propose_employee_position_assignment", {
    p_master_record_id: parsed.masterRecordId,
    p_expected_version: parsed.expectedVersion,
    p_position_id: parsed.positionId,
    p_grade_id: parsed.gradeId ?? null,
    p_manager_employee_id: parsed.managerEmployeeId ?? null,
    p_assignment_type: parsed.assignmentType,
    p_allocation_pct: parsed.allocationPct ?? null,
    p_effective_start_date: parsed.effectiveStartDate,
    p_effective_end_date: parsed.effectiveEndDate ?? null,
    p_change_reason: parsed.changeReason,
    p_reason_note: parsed.reasonNote ?? null,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new PositionMutationError(classifyError(error.message), error.message);
  return parseAssignmentResponse(data, "propose_employee_position_assignment");
}

/** Requires HRS:Approve (section 21 main flow, step 2). Approve re-validates capacity/overlap/cycle authoritatively and syncs app.employees' cache if already effective; reject is terminal with a mandatory reason and leaves the prior active assignment untouched. */
export async function decideEmployeePositionAssignment(client: PositionMutationRpcClient, input: DecideEmployeePositionAssignmentInput): Promise<EmployeePositionAssignment> {
  const parsed = DecideEmployeePositionAssignmentInputSchema.parse(input);
  const { data, error } = await client.rpc("decide_employee_position_assignment", {
    p_assignment_id: parsed.assignmentId,
    p_expected_version: parsed.expectedVersion,
    p_decision: parsed.decision,
    p_reason: parsed.reason,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
    // ISS-2026-302: read here rather than threaded through every caller -- a security
    // control a call site can forget to pass is not a control. Null outside a request.
    p_client_ip: await resolveRequestClientIp(),
  });
  if (error) throw new PositionMutationError(classifyError(error.message), error.message);
  return parseAssignmentResponse(data, "decide_employee_position_assignment");
}

/** Only a still-pending proposal, or an approved-but-not-yet-effective (future-dated) assignment, may be cancelled -- an already-effective one may never be cancelled retroactively (section 23). */
export async function cancelEmployeePositionAssignment(client: PositionMutationRpcClient, input: CancelEmployeePositionAssignmentInput): Promise<EmployeePositionAssignment> {
  const parsed = CancelEmployeePositionAssignmentInputSchema.parse(input);
  const { data, error } = await client.rpc("cancel_employee_position_assignment", {
    p_assignment_id: parsed.assignmentId,
    p_expected_version: parsed.expectedVersion,
    p_reason: parsed.reason,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new PositionMutationError(classifyError(error.message), error.message);
  return parseAssignmentResponse(data, "cancel_employee_position_assignment");
}

/** Maintenance sweep (HRS:Override) -- syncs any approved primary assignment whose effective_start_date has arrived but whose employees.position_id cache does not yet reflect it. No live scheduler invokes this automatically in this repository yet (disclosed); callable on demand today. Returns the number of assignments activated. */
export async function activateDueEmployeePositionAssignments(client: PositionMutationRpcClient, input: ActivateDueEmployeePositionAssignmentsInput): Promise<number> {
  const parsed = ActivateDueEmployeePositionAssignmentsInputSchema.parse(input);
  const { data, error } = await client.rpc("activate_due_employee_position_assignments", {
    p_tenant_id: parsed.tenantId,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new PositionMutationError(classifyError(error.message), error.message);
  if (typeof data !== "number") throw new PositionMutationError("invalid_response", "activate_due_employee_position_assignments returned a non-numeric result");
  return data;
}

/**
 * Bulk/multi-employee reorganization (ISS-2026-066 item 1). Creates status=pending_approval
 * proposals for every item, in a list of employee/position pairs, in ONE transaction --
 * app.propose_bulk_employee_position_assignment either creates every row or none (an
 * uncaught exception on any item rolls back the whole batch). Every row lands in the SAME
 * queue a single proposeEmployeePositionAssignment call would, reviewed through the
 * existing /hris/employees/[masterRecordId]/positions wizard -- this never auto-approves.
 */
export async function proposeBulkEmployeePositionAssignment(client: PositionMutationRpcClient, input: ProposeBulkEmployeePositionAssignmentInput): Promise<EmployeePositionAssignment[]> {
  const parsed = ProposeBulkEmployeePositionAssignmentInputSchema.parse(input);
  const { data, error } = await client.rpc("propose_bulk_employee_position_assignment", {
    p_tenant_id: parsed.tenantId,
    p_items: parsed.items.map((item) => ({
      master_record_id: item.masterRecordId,
      expected_version: item.expectedVersion,
      position_id: item.positionId,
      grade_id: item.gradeId ?? null,
      manager_employee_id: item.managerEmployeeId ?? null,
      assignment_type: item.assignmentType,
    })),
    p_change_reason: parsed.changeReason,
    p_reason_note: parsed.reasonNote ?? null,
    p_effective_start_date: parsed.effectiveStartDate,
    p_effective_end_date: parsed.effectiveEndDate ?? null,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new PositionMutationError(classifyError(error.message), error.message);
  return (data as Record<string, unknown>[] | null ?? []).map(parseEmployeePositionAssignment);
}
