/**
 * Organization hierarchy CRUD/move/lifecycle service (PLT-109, CG-S6-PLT-006). Thin,
 * typed wrappers around app.create_org_unit / app.move_org_unit / app.rename_org_unit /
 * app.set_org_unit_status (supabase/migrations/20260716101726_create_org_units.sql).
 * move/rename/setStatus all carry an `expectedVersion` -- a stale value is rejected by the
 * database as `org_unit_version_conflict`, classified below so a caller can prompt a
 * refresh rather than silently clobbering a concurrent change.
 */

import {
  CreateOrgUnitInputSchema,
  MoveOrgUnitInputSchema,
  RenameOrgUnitInputSchema,
  SetOrgUnitStatusInputSchema,
  parseOrgUnit,
  type CreateOrgUnitInput,
  type MoveOrgUnitInput,
  type OrgUnit,
  type RenameOrgUnitInput,
  type SetOrgUnitStatusInput,
} from "../contracts/org-hierarchy/org-hierarchy.ts";

export interface OrgHierarchyRpcClient {
  rpc(
    fn: "create_org_unit" | "move_org_unit" | "rename_org_unit" | "set_org_unit_status",
    args: Record<string, unknown>,
  ): Promise<{ data: unknown; error: { message: string } | null }>;
}

export const ORG_HIERARCHY_KNOWN_ERROR_CODES = [
  "org_unit_not_found",
  "org_unit_version_conflict",
  "org_unit_code_conflict",
  "org_unit_cycle",
  "org_unit_has_active_children",
  "cross_tenant_parent",
  "invalid_org_unit_parent",
] as const;
type KnownOrgHierarchyErrorCode = (typeof ORG_HIERARCHY_KNOWN_ERROR_CODES)[number];
export type OrgHierarchyMutationErrorCode = KnownOrgHierarchyErrorCode | "mutation_failed" | "invalid_response";

export class OrgHierarchyMutationError extends Error {
  readonly code: OrgHierarchyMutationErrorCode;

  constructor(code: OrgHierarchyMutationErrorCode, message: string) {
    super(message);
    this.name = "OrgHierarchyMutationError";
    this.code = code;
  }
}

function classifyError(message: string): OrgHierarchyMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (ORG_HIERARCHY_KNOWN_ERROR_CODES as readonly string[]).includes(prefix ?? "")
    ? (prefix as KnownOrgHierarchyErrorCode)
    : "mutation_failed";
}

async function callAndParse(
  client: OrgHierarchyRpcClient,
  fn: "create_org_unit" | "move_org_unit" | "rename_org_unit" | "set_org_unit_status",
  args: Record<string, unknown>,
): Promise<OrgUnit> {
  const { data, error } = await client.rpc(fn, args);

  if (error) {
    throw new OrgHierarchyMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new OrgHierarchyMutationError("invalid_response", `${fn} returned no row`);
  }
  return parseOrgUnit(data as Record<string, unknown>);
}

export async function createOrgUnit(client: OrgHierarchyRpcClient, input: CreateOrgUnitInput): Promise<OrgUnit> {
  const parsedInput = CreateOrgUnitInputSchema.parse(input);
  return callAndParse(client, "create_org_unit", {
    p_tenant_id: parsedInput.tenantId,
    p_unit_type: parsedInput.unitType,
    p_parent_id: parsedInput.parentId,
    p_code: parsedInput.code,
    p_name: parsedInput.name,
    p_requested_by: parsedInput.requestedBy,
  });
}

export async function moveOrgUnit(client: OrgHierarchyRpcClient, input: MoveOrgUnitInput): Promise<OrgUnit> {
  const parsedInput = MoveOrgUnitInputSchema.parse(input);
  return callAndParse(client, "move_org_unit", {
    p_id: parsedInput.id,
    p_new_parent_id: parsedInput.newParentId,
    p_expected_version: parsedInput.expectedVersion,
    p_requested_by: parsedInput.requestedBy,
  });
}

export async function renameOrgUnit(client: OrgHierarchyRpcClient, input: RenameOrgUnitInput): Promise<OrgUnit> {
  const parsedInput = RenameOrgUnitInputSchema.parse(input);
  return callAndParse(client, "rename_org_unit", {
    p_id: parsedInput.id,
    p_new_name: parsedInput.newName,
    p_expected_version: parsedInput.expectedVersion,
    p_requested_by: parsedInput.requestedBy,
  });
}

export async function setOrgUnitStatus(client: OrgHierarchyRpcClient, input: SetOrgUnitStatusInput): Promise<OrgUnit> {
  const parsedInput = SetOrgUnitStatusInputSchema.parse(input);
  return callAndParse(client, "set_org_unit_status", {
    p_id: parsedInput.id,
    p_new_status: parsedInput.newStatus,
    p_expected_version: parsedInput.expectedVersion,
    p_reason: parsedInput.reason,
    p_requested_by: parsedInput.requestedBy,
  });
}
