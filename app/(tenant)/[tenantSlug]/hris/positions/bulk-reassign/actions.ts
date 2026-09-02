"use server";

/**
 * Bulk/multi-employee reorganization Server Action (ISS-2026-066 item 1). Mirrors the
 * established hris Server Action shape: resolve portal access, call the typed mutation
 * wrapper, translate a known error into a plain-language message, revalidate.
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../../../lib/supabase/server.ts";
import { resolveHrisAccessForRequest } from "../../../../../../lib/portal/resolve-hris-access.server.ts";
import { proposeBulkEmployeePositionAssignment, PositionMutationError } from "../../../../../../server/mutations/position.ts";
import type { AssignmentType, ChangeReason } from "../../../../../../server/contracts/position/position.ts";

export interface BulkReassignActionState {
  readonly error: string | null;
  readonly createdCount: number | null;
}

const NO_ACCESS: BulkReassignActionState = { error: "You don't have access to this organization's HRIS workspace.", createdCount: null };

interface RawItem {
  masterRecordId: string;
  expectedVersion: number;
  positionId: string;
  gradeId: string | null;
  managerEmployeeId: string | null;
  assignmentType: AssignmentType;
}

export async function proposeBulkReassignmentAction(tenantSlug: string, _prevState: BulkReassignActionState, formData: FormData): Promise<BulkReassignActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const itemsRaw = String(formData.get("items") ?? "[]");
  const changeReason = String(formData.get("changeReason") ?? "reorganization") as ChangeReason;
  const reasonNote = String(formData.get("reasonNote") ?? "").trim() || null;
  const effectiveStartDate = String(formData.get("effectiveStartDate") ?? "").trim();
  const effectiveEndDate = String(formData.get("effectiveEndDate") ?? "").trim() || null;

  let items: RawItem[];
  try {
    const parsed = JSON.parse(itemsRaw);
    if (!Array.isArray(parsed)) throw new Error("not an array");
    items = parsed;
  } catch {
    return { error: "Could not read the selected employees. Please reselect them and try again.", createdCount: null };
  }

  if (items.length === 0) {
    return { error: "Select at least one employee to include in this batch.", createdCount: null };
  }
  if (!effectiveStartDate) {
    return { error: "An effective start date is required.", createdCount: null };
  }

  const supabase = await createSupabaseServerClient();
  try {
    const created = await proposeBulkEmployeePositionAssignment(supabase, {
      tenantId: access.tenant.id,
      items: items.map((item) => ({
        masterRecordId: item.masterRecordId,
        expectedVersion: item.expectedVersion,
        positionId: item.positionId,
        gradeId: item.gradeId ?? null,
        managerEmployeeId: item.managerEmployeeId ?? null,
        assignmentType: item.assignmentType ?? "primary",
      })),
      changeReason,
      reasonNote,
      effectiveStartDate,
      effectiveEndDate,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });

    revalidatePath(`/${tenantSlug}/hris/positions`);
    for (const item of items) revalidatePath(`/${tenantSlug}/hris/employees/${item.masterRecordId}/positions`);

    return { error: null, createdCount: created.length };
  } catch (error) {
    if (error instanceof PositionMutationError) return { error: `Could not submit this batch: ${error.message}. No proposals were created.`, createdCount: null };
    throw error;
  }
}
