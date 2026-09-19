"use server";

/**
 * Org-unit master-data Server Actions (audit remediation A2's own §41 MVP
 * scope item, "master-data entry" -- tenant provisioning, user invitation,
 * role/permission configuration, and org-unit structure are the same
 * `docs/blueprint/01_CargoGrid_Project_Product_Charter.md` §41 checklist).
 * `server/mutations/org-hierarchy.ts` (PLT-109) already existed, fully
 * implemented and tested, but is `service_role`-only (this file's own
 * migration's grants) -- every call below uses the service-role client, the
 * "explicit actor, service-role execution" pattern every other privileged
 * mutation in this repository already follows.
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServiceRoleClient } from "../../../../../lib/supabase/service-role.ts";
import { resolveTenantAdminAccessForRequest } from "../../../../../lib/portal/resolve-tenant-admin-access.server.ts";
import {
  createOrgUnit,
  moveOrgUnit,
  renameOrgUnit,
  setOrgUnitStatus,
  setOrgUnitTaxId,
  toOrgHierarchyMutationRpcClient,
  OrgHierarchyMutationError,
} from "../../../../../server/mutations/org-hierarchy.ts";
import type { OrgUnitType, OrgUnitStatus } from "../../../../../server/contracts/org-hierarchy/org-hierarchy.ts";

export interface OrgUnitActionState {
  readonly error: string | null;
}

const OK: OrgUnitActionState = { error: null };
const NO_ACCESS: OrgUnitActionState = { error: "You don't have access to manage this organization's structure." };

async function requireAccess(tenantSlug: string) {
  const access = await resolveTenantAdminAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return null;
  return access;
}

export async function createOrgUnitAction(tenantSlug: string, _prevState: OrgUnitActionState, formData: FormData): Promise<OrgUnitActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const unitType = String(formData.get("unitType") ?? "") as OrgUnitType;
  const parentId = String(formData.get("parentId") ?? "").trim() || null;
  const code = String(formData.get("code") ?? "").trim();
  const name = String(formData.get("name") ?? "").trim();

  const client = toOrgHierarchyMutationRpcClient(createSupabaseServiceRoleClient());
  try {
    await createOrgUnit(client, { tenantId: access.tenant.id, unitType, parentId, code, name, requestedBy: access.authUserId });
  } catch (error) {
    if (error instanceof OrgHierarchyMutationError) return { error: `Could not create this org unit: ${error.message}` };
    throw error;
  }

  revalidatePath(`/${tenantSlug}/admin/organization`);
  return OK;
}

export async function renameOrgUnitAction(tenantSlug: string, orgUnitId: string, expectedVersion: number, _prevState: OrgUnitActionState, formData: FormData): Promise<OrgUnitActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const newName = String(formData.get("newName") ?? "").trim();

  const client = toOrgHierarchyMutationRpcClient(createSupabaseServiceRoleClient());
  try {
    await renameOrgUnit(client, { id: orgUnitId, newName, expectedVersion, requestedBy: access.authUserId });
  } catch (error) {
    if (error instanceof OrgHierarchyMutationError) return { error: `Could not rename this org unit: ${error.message}` };
    throw error;
  }

  revalidatePath(`/${tenantSlug}/admin/organization`);
  return OK;
}

/** CG-AUDIT-2026-09-02 C1: an empty submitted value clears a previously-set tax_id (null), not an empty string. */
export async function setOrgUnitTaxIdAction(tenantSlug: string, orgUnitId: string, expectedVersion: number, _prevState: OrgUnitActionState, formData: FormData): Promise<OrgUnitActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const rawTaxId = String(formData.get("newTaxId") ?? "").trim();
  const newTaxId = rawTaxId.length > 0 ? rawTaxId : null;

  const client = toOrgHierarchyMutationRpcClient(createSupabaseServiceRoleClient());
  try {
    await setOrgUnitTaxId(client, { id: orgUnitId, newTaxId, expectedVersion, requestedBy: access.authUserId });
  } catch (error) {
    if (error instanceof OrgHierarchyMutationError) return { error: `Could not set this org unit's tax ID: ${error.message}` };
    throw error;
  }

  revalidatePath(`/${tenantSlug}/admin/organization`);
  return OK;
}

export async function moveOrgUnitAction(tenantSlug: string, orgUnitId: string, expectedVersion: number, _prevState: OrgUnitActionState, formData: FormData): Promise<OrgUnitActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const newParentId = String(formData.get("newParentId") ?? "").trim() || null;

  const client = toOrgHierarchyMutationRpcClient(createSupabaseServiceRoleClient());
  try {
    await moveOrgUnit(client, { id: orgUnitId, newParentId, expectedVersion, requestedBy: access.authUserId });
  } catch (error) {
    if (error instanceof OrgHierarchyMutationError) return { error: `Could not move this org unit: ${error.message}` };
    throw error;
  }

  revalidatePath(`/${tenantSlug}/admin/organization`);
  return OK;
}

export async function setOrgUnitStatusAction(
  tenantSlug: string,
  orgUnitId: string,
  expectedVersion: number,
  newStatus: OrgUnitStatus,
  _prevState: OrgUnitActionState,
  _formData: FormData,
): Promise<OrgUnitActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const client = toOrgHierarchyMutationRpcClient(createSupabaseServiceRoleClient());
  try {
    await setOrgUnitStatus(client, { id: orgUnitId, newStatus, expectedVersion, reason: `set to ${newStatus} from admin/organization`, requestedBy: access.authUserId });
  } catch (error) {
    if (error instanceof OrgHierarchyMutationError) return { error: `Could not change this org unit's status: ${error.message}` };
    throw error;
  }

  revalidatePath(`/${tenantSlug}/admin/organization`);
  return OK;
}
