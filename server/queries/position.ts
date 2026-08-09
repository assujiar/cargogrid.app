/**
 * Organization and Position Linkage read queries (HRT-275, CG-S12-HRT-003). Thin,
 * typed wrappers around app.list_position_grades/app.list_positions/app.get_position/
 * app.export_positions/app.preview_employee_position_assignment_impact/
 * app.get_employee_position_assignment_history/
 * app.get_my_employee_position_assignment_history/app.get_employee_current_assignment/
 * app.get_employee_manager_chain/app.get_org_position_tree
 * (supabase/migrations/20260730840000_create_hris_organization_position_linkage.sql).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parsePositionGrade,
  parsePositionListRow,
  parsePositionDetail,
  parsePositionExportRow,
  parseEmployeePositionAssignment,
  parseAssignmentImpactPreview,
  parseManagerChainRow,
  parseOrgPositionTreeRow,
  type PositionGrade,
  type PositionListRow,
  type PositionDetail,
  type PositionExportRow,
  type EmployeePositionAssignment,
  type AssignmentImpactPreview,
  type ManagerChainRow,
  type OrgPositionTreeRow,
  type PositionGradeStatus,
  type PositionStatus,
} from "../contracts/position/position.ts";

export type PositionQueryClient = Pick<SupabaseClient, "rpc">;

export class PositionQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "PositionQueryError";
  }
}

function firstRow(data: unknown): Record<string, unknown> | null {
  const row = Array.isArray(data) ? data[0] : data;
  return row && typeof row === "object" ? (row as Record<string, unknown>) : null;
}

function rows(data: unknown): Record<string, unknown>[] {
  return (data as Record<string, unknown>[] | null) ?? [];
}

export async function listPositionGrades(
  client: PositionQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options?: { statusFilter?: PositionGradeStatus | null },
): Promise<PositionGrade[]> {
  const { data, error } = await client.rpc("list_position_grades", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_status_filter: options?.statusFilter ?? null,
  });
  if (error) throw new PositionQueryError(error.message);
  return rows(data).map(parsePositionGrade);
}

/** Cursor-paginated (code-keyset), server-filtered/searched catalogue -- never a client-loaded full dataset. */
export async function listPositions(
  client: PositionQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options?: { orgUnitId?: string | null; statusFilter?: PositionStatus | null; search?: string | null; limit?: number; afterCode?: string | null },
): Promise<PositionListRow[]> {
  const { data, error } = await client.rpc("list_positions", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_org_unit_id: options?.orgUnitId ?? null,
    p_status_filter: options?.statusFilter ?? null,
    p_search: options?.search ?? null,
    p_limit: options?.limit ?? 50,
    p_after_code: options?.afterCode ?? null,
  });
  if (error) throw new PositionQueryError(error.message);
  return rows(data).map(parsePositionListRow);
}

export async function getPosition(client: PositionQueryClient, id: string, actorAuthUserId: string): Promise<PositionDetail> {
  const { data, error } = await client.rpc("get_position", { p_id: id, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new PositionQueryError(error.message);
  const row = firstRow(data);
  if (!row) throw new PositionQueryError("get_position returned no row");
  return parsePositionDetail(row);
}

/** The scoped, non-compensation export projection (section 14 "scoped export"). */
export async function exportPositions(
  client: PositionQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options?: { statusFilter?: PositionStatus | null; limit?: number },
): Promise<PositionExportRow[]> {
  const { data, error } = await client.rpc("export_positions", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_status_filter: options?.statusFilter ?? null,
    p_limit: options?.limit ?? 500,
  });
  if (error) throw new PositionQueryError(error.message);
  return rows(data).map(parsePositionExportRow);
}

/** Callable standalone, before any proposal exists (decision 6) -- computes real impact signals and discloses not-yet-integrated downstream systems rather than fabricating them. */
export async function previewEmployeePositionAssignmentImpact(
  client: PositionQueryClient,
  input: { masterRecordId: string; positionId: string; managerEmployeeId: string | null; effectiveStartDate: string | null; actorAuthUserId: string },
): Promise<AssignmentImpactPreview> {
  const { data, error } = await client.rpc("preview_employee_position_assignment_impact", {
    p_master_record_id: input.masterRecordId,
    p_position_id: input.positionId,
    p_manager_employee_id: input.managerEmployeeId,
    p_effective_start_date: input.effectiveStartDate,
    p_actor_auth_user_id: input.actorAuthUserId,
  });
  if (error) throw new PositionQueryError(error.message);
  const row = firstRow(data);
  if (!row) throw new PositionQueryError("preview_employee_position_assignment_impact returned no row");
  return parseAssignmentImpactPreview(row);
}

export async function getEmployeePositionAssignmentHistory(client: PositionQueryClient, masterRecordId: string, actorAuthUserId: string): Promise<EmployeePositionAssignment[]> {
  const { data, error } = await client.rpc("get_employee_position_assignment_history", { p_master_record_id: masterRecordId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new PositionQueryError(error.message);
  return rows(data).map(parseEmployeePositionAssignment);
}

/** Self-only, identity-match-gated (never requires HRS:View) -- returns an empty array (never throws) when the caller has no linked employee profile. */
export async function getMyEmployeePositionAssignmentHistory(client: PositionQueryClient, tenantId: string, actorAuthUserId: string): Promise<EmployeePositionAssignment[]> {
  const { data, error } = await client.rpc("get_my_employee_position_assignment_history", { p_tenant_id: tenantId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new PositionQueryError(error.message);
  return rows(data).map(parseEmployeePositionAssignment);
}

/** The genuinely point-in-time-correct read (section 20 "historical queries") -- reads app.employee_position_assignments' own validity_range directly, never app.employees' convenience cache. */
export async function getEmployeeCurrentAssignment(client: PositionQueryClient, masterRecordId: string, actorAuthUserId: string, asOf?: string | null): Promise<EmployeePositionAssignment[]> {
  const { data, error } = await client.rpc("get_employee_current_assignment", { p_master_record_id: masterRecordId, p_actor_auth_user_id: actorAuthUserId, p_as_of: asOf ?? null });
  if (error) throw new PositionQueryError(error.message);
  return rows(data).map(parseEmployeePositionAssignment);
}

/** The employee's own reporting chain, direct manager first, bounded to 200 hops. */
export async function getEmployeeManagerChain(client: PositionQueryClient, masterRecordId: string, actorAuthUserId: string): Promise<ManagerChainRow[]> {
  const { data, error } = await client.rpc("get_employee_manager_chain", { p_master_record_id: masterRecordId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new PositionQueryError(error.message);
  return rows(data).map(parseManagerChainRow);
}

/** Organization-linked position tree -- one joined query, no recursive N+1 (section 17). */
export async function getOrgPositionTree(client: PositionQueryClient, tenantId: string, actorAuthUserId: string, rootOrgUnitId?: string | null): Promise<OrgPositionTreeRow[]> {
  const { data, error } = await client.rpc("get_org_position_tree", { p_tenant_id: tenantId, p_actor_auth_user_id: actorAuthUserId, p_root_org_unit_id: rootOrgUnitId ?? null });
  if (error) throw new PositionQueryError(error.message);
  return rows(data).map(parseOrgPositionTreeRow);
}
