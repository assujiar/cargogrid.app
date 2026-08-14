"use server";

/**
 * MSS team workspace server actions (HRT-285, CG-S12-HRT-013). Every action
 * below is a thin wrapper around the single composed
 * `decideManagerApprovalQueueItem` dispatcher (`server/mutations/self-
 * service.ts`), which itself calls the OWNING capability's own canonical
 * `decide*` RPC unchanged -- this file performs no authority check, no
 * validation beyond binding form fields to the right shape, and writes no
 * audit row of its own.
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { resolveHrisAccessForRequest } from "../../../../../lib/portal/resolve-hris-access.server.ts";
import { decideManagerApprovalQueueItem, SelfServiceMutationError } from "../../../../../server/mutations/self-service.ts";

export interface MssActionState {
  readonly error: string | null;
}

const OK: MssActionState = { error: null };
const NO_ACCESS: MssActionState = { error: "You don't have access to this organization's HRIS workspace." };

function path(tenantSlug: string): string {
  return `/${tenantSlug}/hris/team`;
}

export async function decideLeaveQueueItemAction(
  tenantSlug: string,
  requestStepId: string,
  _prevState: MssActionState,
  formData: FormData,
): Promise<MssActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const decision = String(formData.get("decision") ?? "");
  const reason = String(formData.get("reason") ?? "").trim();
  const overrideCoverage = formData.get("overrideCoverage") === "on";
  if (decision !== "approved" && decision !== "rejected") return { error: "Choose a decision." };
  if (!reason) return { error: "A reason is required." };

  const supabase = await createSupabaseServerClient();
  try {
    await decideManagerApprovalQueueItem(supabase, {
      kind: "leave", requestStepId, decision, reason, overrideCoverage, actorAuthUserId: access.authUserId, actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof SelfServiceMutationError) return { error: `Could not decide this leave request: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function decideOvertimeQueueItemAction(
  tenantSlug: string,
  requestId: string,
  expectedVersion: number,
  _prevState: MssActionState,
  formData: FormData,
): Promise<MssActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const decision = String(formData.get("decision") ?? "");
  const decidedReason = String(formData.get("decidedReason") ?? "").trim();
  const approvedMinutesOverrideRaw = String(formData.get("approvedMinutesOverride") ?? "").trim();
  if (decision !== "approve" && decision !== "reject") return { error: "Choose a decision." };
  if (!decidedReason) return { error: "A reason is required." };

  const supabase = await createSupabaseServerClient();
  try {
    await decideManagerApprovalQueueItem(supabase, {
      kind: "overtime",
      requestId,
      expectedVersion,
      decision,
      decidedReason,
      approvedMinutesOverride: approvedMinutesOverrideRaw ? Number(approvedMinutesOverrideRaw) : null,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof SelfServiceMutationError) return { error: `Could not decide this overtime request: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function decideTimesheetQueueItemAction(
  tenantSlug: string,
  entryId: string,
  expectedVersion: number,
  _prevState: MssActionState,
  formData: FormData,
): Promise<MssActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const decision = String(formData.get("decision") ?? "");
  const decidedReason = String(formData.get("decidedReason") ?? "").trim();
  const approvedMinutesOverrideRaw = String(formData.get("approvedMinutesOverride") ?? "").trim();
  if (decision !== "approve" && decision !== "reject") return { error: "Choose a decision." };
  if (!decidedReason) return { error: "A reason is required." };

  const supabase = await createSupabaseServerClient();
  try {
    await decideManagerApprovalQueueItem(supabase, {
      kind: "timesheet_entry",
      entryId,
      expectedVersion,
      decision,
      decidedReason,
      approvedMinutesOverride: approvedMinutesOverrideRaw ? Number(approvedMinutesOverrideRaw) : null,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof SelfServiceMutationError) return { error: `Could not decide this timesheet entry: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function decideTrainingQueueItemAction(
  tenantSlug: string,
  enrollmentId: string,
  expectedVersion: number,
  _prevState: MssActionState,
  formData: FormData,
): Promise<MssActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const decision = String(formData.get("decision") ?? "");
  const decisionReason = String(formData.get("decisionReason") ?? "").trim();
  if (decision !== "approve" && decision !== "reject") return { error: "Choose a decision." };

  const supabase = await createSupabaseServerClient();
  try {
    await decideManagerApprovalQueueItem(supabase, {
      kind: "training_enrollment",
      enrollmentId,
      expectedVersion,
      decision,
      decisionReason: decisionReason || null,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof SelfServiceMutationError) return { error: `Could not decide this training enrollment: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}
