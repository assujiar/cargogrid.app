"use server";

/** Own-profile self-service Server Actions (HRT-274, CG-S12-HRT-002). */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../../../lib/supabase/server.ts";
import { resolveHrisAccessForRequest } from "../../../../../../lib/portal/resolve-hris-access.server.ts";
import { requestEmployeeChange, EmployeeMutationError } from "../../../../../../server/mutations/employee.ts";
import type { EmployeeChangeRequestField } from "../../../../../../server/contracts/employee/employee.ts";

export interface MyProfileActionState {
  readonly error: string | null;
  readonly success: boolean;
}

const OK: MyProfileActionState = { error: null, success: true };

export async function requestMyProfileChangeAction(tenantSlug: string, masterRecordId: string, _prevState: MyProfileActionState, formData: FormData): Promise<MyProfileActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return { error: "You don't have access to this organization's HRIS workspace.", success: false };

  const fieldKey = String(formData.get("fieldKey") ?? "") as EmployeeChangeRequestField;
  const requestedValue = String(formData.get("requestedValue") ?? "").trim();
  const reason = String(formData.get("reason") ?? "").trim() || null;

  const supabase = await createSupabaseServerClient();
  try {
    await requestEmployeeChange(supabase, { masterRecordId, fieldKey, requestedValue, reason, actorAuthUserId: access.authUserId });
  } catch (error) {
    if (error instanceof EmployeeMutationError) return { error: `Could not submit this correction request: ${error.message}`, success: false };
    throw error;
  }

  revalidatePath(`/${tenantSlug}/hris/my/profile`);
  return OK;
}
