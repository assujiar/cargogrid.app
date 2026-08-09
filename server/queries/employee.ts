/**
 * Employee Master read queries (HRT-274, CG-S12-HRT-002). Thin, typed wrappers
 * around app.list_employees/app.get_employee_profile/app.get_my_employee_profile/
 * app.list_my_team_employees/app.get_employee_lifecycle_history/
 * app.list_employee_emergency_contacts/app.list_employee_duplicate_candidates/
 * app.search_employee_duplicate_candidates/app.export_employees
 * (supabase/migrations/20260730830000_create_hris_employee_master.sql).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseEmployeeListRow,
  parseEmployeeProfile,
  parseEmployeeOwnProfile,
  parseMyTeamEmployeeRow,
  parseEmployeeLifecycleEvent,
  parseEmployeeEmergencyContact,
  parseEmployeeDuplicateCandidate,
  parseEmployeeDuplicateSearchRow,
  parseEmployeeExportRow,
  type EmployeeListRow,
  type EmployeeProfile,
  type EmployeeOwnProfile,
  type MyTeamEmployeeRow,
  type EmployeeLifecycleEvent,
  type EmployeeEmergencyContact,
  type EmployeeDuplicateCandidate,
  type EmployeeDuplicateSearchRow,
  type EmployeeExportRow,
  type EmployeeLifecycleStatus,
} from "../contracts/employee/employee.ts";

export type EmployeeQueryClient = Pick<SupabaseClient, "rpc">;

export class EmployeeQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "EmployeeQueryError";
  }
}

function firstRow(data: unknown): Record<string, unknown> | null {
  const row = Array.isArray(data) ? data[0] : data;
  return row && typeof row === "object" ? (row as Record<string, unknown>) : null;
}

function rows(data: unknown): Record<string, unknown>[] {
  return (data as Record<string, unknown>[] | null) ?? [];
}

/** Cursor-paginated (employee-number keyset), server-filtered/searched directory -- never a client-loaded full dataset. */
export async function listEmployees(
  client: EmployeeQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options?: { statusFilter?: EmployeeLifecycleStatus | null; departmentOrgUnitId?: string | null; search?: string | null; limit?: number; afterEmployeeNumber?: string | null },
): Promise<EmployeeListRow[]> {
  const { data, error } = await client.rpc("list_employees", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_status_filter: options?.statusFilter ?? null,
    p_department_org_unit_id: options?.departmentOrgUnitId ?? null,
    p_search: options?.search ?? null,
    p_limit: options?.limit ?? 50,
    p_after_employee_number: options?.afterEmployeeNumber ?? null,
  });
  if (error) throw new EmployeeQueryError(error.message);
  return rows(data).map(parseEmployeeListRow);
}

export async function getEmployeeProfile(client: EmployeeQueryClient, masterRecordId: string, actorAuthUserId: string): Promise<EmployeeProfile> {
  const { data, error } = await client.rpc("get_employee_profile", { p_master_record_id: masterRecordId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new EmployeeQueryError(error.message);
  const row = firstRow(data);
  if (!row) throw new EmployeeQueryError("get_employee_profile returned no row");
  return parseEmployeeProfile(row);
}

/** Returns null (never throws) when the caller has no linked employee profile yet -- app.get_my_employee_profile itself returns zero rows rather than raising for this case. */
export async function getMyEmployeeProfile(client: EmployeeQueryClient, tenantId: string, actorAuthUserId: string): Promise<EmployeeOwnProfile | null> {
  const { data, error } = await client.rpc("get_my_employee_profile", { p_tenant_id: tenantId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new EmployeeQueryError(error.message);
  const row = firstRow(data);
  return row ? parseEmployeeOwnProfile(row) : null;
}

/** Manager-scoped, self-resolved (the caller's OWN employee row determines their team). Empty array when the caller has no linked employee profile, or is not currently anyone's manager. */
export async function listMyTeamEmployees(
  client: EmployeeQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options?: { limit?: number; afterEmployeeNumber?: string | null },
): Promise<MyTeamEmployeeRow[]> {
  const { data, error } = await client.rpc("list_my_team_employees", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_limit: options?.limit ?? 50,
    p_after_employee_number: options?.afterEmployeeNumber ?? null,
  });
  if (error) throw new EmployeeQueryError(error.message);
  return rows(data).map(parseMyTeamEmployeeRow);
}

export async function getEmployeeLifecycleHistory(client: EmployeeQueryClient, masterRecordId: string, actorAuthUserId: string): Promise<EmployeeLifecycleEvent[]> {
  const { data, error } = await client.rpc("get_employee_lifecycle_history", { p_master_record_id: masterRecordId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new EmployeeQueryError(error.message);
  return rows(data).map(parseEmployeeLifecycleEvent);
}

export async function listEmployeeEmergencyContacts(client: EmployeeQueryClient, masterRecordId: string, actorAuthUserId: string): Promise<EmployeeEmergencyContact[]> {
  const { data, error } = await client.rpc("list_employee_emergency_contacts", { p_master_record_id: masterRecordId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new EmployeeQueryError(error.message);
  return rows(data).map(parseEmployeeEmergencyContact);
}

export async function listEmployeeDuplicateCandidates(client: EmployeeQueryClient, masterRecordId: string, actorAuthUserId: string): Promise<EmployeeDuplicateCandidate[]> {
  const { data, error } = await client.rpc("list_employee_duplicate_candidates", { p_master_record_id: masterRecordId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new EmployeeQueryError(error.message);
  return rows(data).map(parseEmployeeDuplicateCandidate);
}

export async function searchEmployeeDuplicateCandidates(
  client: EmployeeQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options: { fullName?: string | null; nationalIdNumber?: string | null; workEmail?: string | null; personalEmail?: string | null; limit?: number },
): Promise<EmployeeDuplicateSearchRow[]> {
  const { data, error } = await client.rpc("search_employee_duplicate_candidates", {
    p_tenant_id: tenantId,
    p_full_name: options.fullName ?? null,
    p_national_id_number: options.nationalIdNumber ?? null,
    p_work_email: options.workEmail ?? null,
    p_personal_email: options.personalEmail ?? null,
    p_actor_auth_user_id: actorAuthUserId,
    p_limit: options.limit ?? 10,
  });
  if (error) throw new EmployeeQueryError(error.message);
  return rows(data).map(parseEmployeeDuplicateSearchRow);
}

/** The scoped, non-PII export projection (section 14 "scoped export") -- never includes personal_email/personal_phone/national_id_number/date_of_birth/gender/address. */
export async function exportEmployees(
  client: EmployeeQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options?: { statusFilter?: EmployeeLifecycleStatus | null; limit?: number },
): Promise<EmployeeExportRow[]> {
  const { data, error } = await client.rpc("export_employees", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_status_filter: options?.statusFilter ?? null,
    p_limit: options?.limit ?? 500,
  });
  if (error) throw new EmployeeQueryError(error.message);
  return rows(data).map(parseEmployeeExportRow);
}
