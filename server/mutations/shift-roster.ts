/**
 * Shift, Roster and Scheduling mutation primitives (HRT-279, CG-S12-HRT-007).
 * Thin, typed wrappers around every write RPC in
 * supabase/migrations/20260730910000_create_hris_shift_roster_scheduling.sql.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  CreateShiftTemplateInputSchema,
  CreateShiftTemplateVersionInputSchema,
  PublishShiftTemplateVersionInputSchema,
  CreateRosterCycleInputSchema,
  SetRosterCycleSlotInputSchema,
  PublishRosterCycleInputSchema,
  SetRosterHolidayInputSchema,
  RemoveRosterHolidayInputSchema,
  SetScheduleCoverageRequirementInputSchema,
  AssignEmployeeScheduleInputSchema,
  CancelScheduleAssignmentInputSchema,
  PublishScheduleAssignmentsInputSchema,
  GenerateRosterScheduleAssignmentsInputSchema,
  RequestScheduleSwapInputSchema,
  DecideScheduleSwapRequestInputSchema,
  CancelScheduleSwapRequestInputSchema,
  parsePublishScheduleAssignmentsResultRow,
  parseGenerateRosterScheduleAssignmentsResult,
  type CreateShiftTemplateInput,
  type CreateShiftTemplateVersionInput,
  type PublishShiftTemplateVersionInput,
  type CreateRosterCycleInput,
  type SetRosterCycleSlotInput,
  type PublishRosterCycleInput,
  type SetRosterHolidayInput,
  type RemoveRosterHolidayInput,
  type SetScheduleCoverageRequirementInput,
  type AssignEmployeeScheduleInput,
  type CancelScheduleAssignmentInput,
  type PublishScheduleAssignmentsInput,
  type GenerateRosterScheduleAssignmentsInput,
  type RequestScheduleSwapInput,
  type DecideScheduleSwapRequestInput,
  type CancelScheduleSwapRequestInput,
  type PublishScheduleAssignmentsResultRow,
  type GenerateRosterScheduleAssignmentsResult,
} from "../contracts/shift-roster/shift-roster.ts";

export type ShiftRosterMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const SHIFT_ROSTER_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "insufficient_privilege",
  "invalid_code",
  "invalid_name",
  "org_unit_not_found",
  "shift_template_not_found",
  "shift_template_not_available",
  "shift_template_version_not_available",
  "shift_template_version_not_found",
  "invalid_transition",
  "invalid_timezone",
  "invalid_segments",
  "invalid_segment_type",
  "invalid_segment_time",
  "invalid_segment_order",
  "invalid_segment_duration",
  "invalid_segment_overlap",
  "stale_version",
  "invalid_cycle_length",
  "roster_cycle_not_found",
  "roster_cycle_not_available",
  "invalid_day_offset",
  "incomplete_roster_cycle",
  "invalid_holiday_date",
  "roster_holiday_not_found",
  "invalid_day_of_week",
  "invalid_min_headcount",
  "employee_not_found",
  "employee_not_active",
  "invalid_work_date",
  "idempotency_key_conflict",
  "reason_required",
  "schedule_assignment_not_found",
  "invalid_date_range",
  "invalid_employee_ids",
  "invalid_swap_target",
  "self_approval_not_permitted",
  "invalid_decision",
  "schedule_swap_request_not_found",
] as const;

export type KnownShiftRosterMutationErrorCode = (typeof SHIFT_ROSTER_KNOWN_MUTATION_ERROR_CODES)[number];
export type ShiftRosterMutationErrorCode = KnownShiftRosterMutationErrorCode | "mutation_failed";

export class ShiftRosterMutationError extends Error {
  readonly code: ShiftRosterMutationErrorCode;

  constructor(code: ShiftRosterMutationErrorCode, message: string) {
    super(message);
    this.name = "ShiftRosterMutationError";
    this.code = code;
  }
}

function classifyError(message: string): ShiftRosterMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (SHIFT_ROSTER_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "") ? (prefix as KnownShiftRosterMutationErrorCode) : "mutation_failed";
}

function firstRow(data: unknown): Record<string, unknown> | null {
  const row = Array.isArray(data) ? data[0] : data;
  return row && typeof row === "object" ? (row as Record<string, unknown>) : null;
}

export async function createShiftTemplate(client: ShiftRosterMutationRpcClient, input: CreateShiftTemplateInput): Promise<Record<string, unknown>> {
  const parsed = CreateShiftTemplateInputSchema.parse(input);
  const { data, error } = await client.rpc("create_shift_template", {
    p_tenant_id: parsed.tenantId,
    p_org_unit_id: parsed.orgUnitId,
    p_code: parsed.code,
    p_name: parsed.name,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new ShiftRosterMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new ShiftRosterMutationError("mutation_failed", "create_shift_template returned no row");
  return row;
}

export async function createShiftTemplateVersion(client: ShiftRosterMutationRpcClient, input: CreateShiftTemplateVersionInput): Promise<Record<string, unknown>> {
  const parsed = CreateShiftTemplateVersionInputSchema.parse(input);
  const { data, error } = await client.rpc("create_shift_template_version", {
    p_shift_template_id: parsed.shiftTemplateId,
    p_timezone: parsed.timezone,
    p_day_boundary_local_time: parsed.dayBoundaryLocalTime,
    p_shift_type: parsed.shiftType,
    p_grace_late_minutes: parsed.graceLateMinutes,
    p_grace_early_minutes: parsed.graceEarlyMinutes,
    p_effective_from: parsed.effectiveFrom,
    p_segments: parsed.segments.map((s) => ({ segment_type: s.segmentType, start_time: s.startTime, end_time: s.endTime })),
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new ShiftRosterMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new ShiftRosterMutationError("mutation_failed", "create_shift_template_version returned no row");
  return row;
}

export async function publishShiftTemplateVersion(client: ShiftRosterMutationRpcClient, input: PublishShiftTemplateVersionInput): Promise<Record<string, unknown>> {
  const parsed = PublishShiftTemplateVersionInputSchema.parse(input);
  const { data, error } = await client.rpc("publish_shift_template_version", {
    p_version_id: parsed.versionId,
    p_expected_version: parsed.expectedVersion,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new ShiftRosterMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new ShiftRosterMutationError("mutation_failed", "publish_shift_template_version returned no row");
  return row;
}

export async function createRosterCycle(client: ShiftRosterMutationRpcClient, input: CreateRosterCycleInput): Promise<Record<string, unknown>> {
  const parsed = CreateRosterCycleInputSchema.parse(input);
  const { data, error } = await client.rpc("create_roster_cycle", {
    p_tenant_id: parsed.tenantId,
    p_org_unit_id: parsed.orgUnitId,
    p_name: parsed.name,
    p_cycle_length_days: parsed.cycleLengthDays,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new ShiftRosterMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new ShiftRosterMutationError("mutation_failed", "create_roster_cycle returned no row");
  return row;
}

export async function setRosterCycleSlot(client: ShiftRosterMutationRpcClient, input: SetRosterCycleSlotInput): Promise<Record<string, unknown>> {
  const parsed = SetRosterCycleSlotInputSchema.parse(input);
  const { data, error } = await client.rpc("set_roster_cycle_slot", {
    p_roster_cycle_id: parsed.rosterCycleId,
    p_day_offset: parsed.dayOffset,
    p_shift_template_id: parsed.shiftTemplateId,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new ShiftRosterMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new ShiftRosterMutationError("mutation_failed", "set_roster_cycle_slot returned no row");
  return row;
}

export async function publishRosterCycle(client: ShiftRosterMutationRpcClient, input: PublishRosterCycleInput): Promise<Record<string, unknown>> {
  const parsed = PublishRosterCycleInputSchema.parse(input);
  const { data, error } = await client.rpc("publish_roster_cycle", {
    p_roster_cycle_id: parsed.rosterCycleId,
    p_expected_version: parsed.expectedVersion,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new ShiftRosterMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new ShiftRosterMutationError("mutation_failed", "publish_roster_cycle returned no row");
  return row;
}

export async function setRosterHoliday(client: ShiftRosterMutationRpcClient, input: SetRosterHolidayInput): Promise<Record<string, unknown>> {
  const parsed = SetRosterHolidayInputSchema.parse(input);
  const { data, error } = await client.rpc("set_roster_holiday", {
    p_tenant_id: parsed.tenantId,
    p_org_unit_id: parsed.orgUnitId,
    p_holiday_date: parsed.holidayDate,
    p_name: parsed.name,
    p_is_working_day: parsed.isWorkingDay,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new ShiftRosterMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new ShiftRosterMutationError("mutation_failed", "set_roster_holiday returned no row");
  return row;
}

export async function removeRosterHoliday(client: ShiftRosterMutationRpcClient, input: RemoveRosterHolidayInput): Promise<Record<string, unknown>> {
  const parsed = RemoveRosterHolidayInputSchema.parse(input);
  const { data, error } = await client.rpc("remove_roster_holiday", {
    p_holiday_id: parsed.holidayId,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new ShiftRosterMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new ShiftRosterMutationError("mutation_failed", "remove_roster_holiday returned no row");
  return row;
}

export async function setScheduleCoverageRequirement(client: ShiftRosterMutationRpcClient, input: SetScheduleCoverageRequirementInput): Promise<Record<string, unknown>> {
  const parsed = SetScheduleCoverageRequirementInputSchema.parse(input);
  const { data, error } = await client.rpc("set_schedule_coverage_requirement", {
    p_tenant_id: parsed.tenantId,
    p_org_unit_id: parsed.orgUnitId,
    p_shift_template_id: parsed.shiftTemplateId,
    p_day_of_week: parsed.dayOfWeek,
    p_min_headcount: parsed.minHeadcount,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new ShiftRosterMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new ShiftRosterMutationError("mutation_failed", "set_schedule_coverage_requirement returned no row");
  return row;
}

export async function assignEmployeeSchedule(client: ShiftRosterMutationRpcClient, input: AssignEmployeeScheduleInput): Promise<Record<string, unknown>> {
  const parsed = AssignEmployeeScheduleInputSchema.parse(input);
  const { data, error } = await client.rpc("assign_employee_schedule", {
    p_tenant_id: parsed.tenantId,
    p_employee_id: parsed.employeeId,
    p_shift_template_version_id: parsed.shiftTemplateVersionId,
    p_work_date: parsed.workDate,
    p_source: parsed.source,
    p_idempotency_key: parsed.idempotencyKey,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new ShiftRosterMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new ShiftRosterMutationError("mutation_failed", "assign_employee_schedule returned no row");
  return row;
}

export async function cancelScheduleAssignment(client: ShiftRosterMutationRpcClient, input: CancelScheduleAssignmentInput): Promise<Record<string, unknown>> {
  const parsed = CancelScheduleAssignmentInputSchema.parse(input);
  const { data, error } = await client.rpc("cancel_schedule_assignment", {
    p_assignment_id: parsed.assignmentId,
    p_expected_version: parsed.expectedVersion,
    p_reason: parsed.reason,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new ShiftRosterMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new ShiftRosterMutationError("mutation_failed", "cancel_schedule_assignment returned no row");
  return row;
}

export async function publishScheduleAssignments(client: ShiftRosterMutationRpcClient, input: PublishScheduleAssignmentsInput): Promise<PublishScheduleAssignmentsResultRow[]> {
  const parsed = PublishScheduleAssignmentsInputSchema.parse(input);
  const { data, error } = await client.rpc("publish_schedule_assignments", {
    p_tenant_id: parsed.tenantId,
    p_from_date: parsed.fromDate,
    p_to_date: parsed.toDate,
    p_org_unit_id: parsed.orgUnitId,
    p_employee_id: parsed.employeeId,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new ShiftRosterMutationError(classifyError(error.message), error.message);
  return ((data as Record<string, unknown>[] | null) ?? []).map(parsePublishScheduleAssignmentsResultRow);
}

export async function generateRosterScheduleAssignments(client: ShiftRosterMutationRpcClient, input: GenerateRosterScheduleAssignmentsInput): Promise<GenerateRosterScheduleAssignmentsResult> {
  const parsed = GenerateRosterScheduleAssignmentsInputSchema.parse(input);
  const { data, error } = await client.rpc("generate_roster_schedule_assignments", {
    p_tenant_id: parsed.tenantId,
    p_roster_cycle_id: parsed.rosterCycleId,
    p_employee_ids: parsed.employeeIds,
    p_from_date: parsed.fromDate,
    p_to_date: parsed.toDate,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new ShiftRosterMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new ShiftRosterMutationError("mutation_failed", "generate_roster_schedule_assignments returned no row");
  return parseGenerateRosterScheduleAssignmentsResult(row);
}

export async function requestScheduleSwap(client: ShiftRosterMutationRpcClient, input: RequestScheduleSwapInput): Promise<Record<string, unknown>> {
  const parsed = RequestScheduleSwapInputSchema.parse(input);
  const { data, error } = await client.rpc("request_schedule_swap", {
    p_assignment_id: parsed.assignmentId,
    p_target_employee_id: parsed.targetEmployeeId,
    p_target_assignment_id: parsed.targetAssignmentId,
    p_reason: parsed.reason,
    p_idempotency_key: parsed.idempotencyKey,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new ShiftRosterMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new ShiftRosterMutationError("mutation_failed", "request_schedule_swap returned no row");
  return row;
}

export async function decideScheduleSwapRequest(client: ShiftRosterMutationRpcClient, input: DecideScheduleSwapRequestInput): Promise<Record<string, unknown>> {
  const parsed = DecideScheduleSwapRequestInputSchema.parse(input);
  const { data, error } = await client.rpc("decide_schedule_swap_request", {
    p_request_id: parsed.requestId,
    p_expected_version: parsed.expectedVersion,
    p_decision: parsed.decision,
    p_decided_reason: parsed.decidedReason,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new ShiftRosterMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new ShiftRosterMutationError("mutation_failed", "decide_schedule_swap_request returned no row");
  return row;
}

export async function cancelScheduleSwapRequest(client: ShiftRosterMutationRpcClient, input: CancelScheduleSwapRequestInput): Promise<Record<string, unknown>> {
  const parsed = CancelScheduleSwapRequestInputSchema.parse(input);
  const { data, error } = await client.rpc("cancel_schedule_swap_request", {
    p_request_id: parsed.requestId,
    p_expected_version: parsed.expectedVersion,
    p_reason: parsed.reason,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new ShiftRosterMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new ShiftRosterMutationError("mutation_failed", "cancel_schedule_swap_request returned no row");
  return row;
}
