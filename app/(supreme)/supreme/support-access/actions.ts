"use server";

/**
 * Support access console Server Actions (CG-AUDIT-2026-09-02
 * UNTRACKED-D4). `server/mutations/support-access.ts` (PLT-115) already
 * existed, fully implemented and tested, but is `service_role`-only
 * (that migration's own grants) with zero callers anywhere in the
 * product -- this closes the missing caller, not new business logic. The
 * "explicit actor, service-role execution" pattern every other
 * privileged mutation in this repository already follows (e.g.
 * `app/(tenant)/[tenantSlug]/admin/roles/actions.ts`).
 *
 * Deliberately out of scope: starting/ending a support SESSION.
 * `app.start_support_session`'s own `p_reauth_confirmed_at` is a bare
 * caller-asserted timestamp -- the RPC only checks it is recent (<=5
 * minutes old), it does not itself verify a real re-authentication
 * happened. No genuine "re-authenticate right now" UI flow exists
 * anywhere in this repository yet (grepped for every caller of
 * `server/mutations/enterprise-mfa.ts`'s own step-up challenge
 * functions -- zero). Wiring "Start session" to a synthesized
 * `new Date().toISOString()` would be a real security regression (a
 * false re-authentication claim), not a neutral UI addition, and
 * building a genuine step-up flow is a separate, deliberate capability
 * of its own. The grant lifecycle this file DOES wire up (request,
 * approve, deny, revoke, post-review) is what actually closes the
 * audit's own complaint: "an operator cannot grant, approve, or revoke
 * support access to a live tenant through the product at all."
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServiceRoleClient } from "../../../../lib/supabase/service-role.ts";
import { resolveSupremeAdminAccessForRequest } from "../../../../lib/portal/resolve-supreme-admin-access.server.ts";
import {
  requestSupportAccess,
  approveSupportAccess,
  denySupportAccess,
  revokeSupportAccess,
  completeSupportAccessPostReview,
  toSupportAccessMutationRpcClient,
  SupportAccessMutationError,
} from "../../../../server/mutations/support-access.ts";

export interface SupportAccessActionState {
  readonly error: string | null;
}

const OK: SupportAccessActionState = { error: null };
const NO_ACCESS: SupportAccessActionState = { error: "You don't have access to the support-access console." };
const PATH = "/supreme/support-access";

async function requireAccess() {
  const access = await resolveSupremeAdminAccessForRequest();
  if (access.status !== "allowed") return null;
  return access;
}

function errorMessage(prefix: string, error: unknown): SupportAccessActionState {
  if (error instanceof SupportAccessMutationError) return { error: `${prefix}: ${error.message}` };
  throw error;
}

export async function requestSupportAccessAction(_prevState: SupportAccessActionState, formData: FormData): Promise<SupportAccessActionState> {
  const access = await requireAccess();
  if (!access) return NO_ACCESS;

  const tenantId = String(formData.get("tenantId") ?? "").trim();
  const granteeAuthUserId = String(formData.get("granteeAuthUserId") ?? "").trim();
  const reason = String(formData.get("reason") ?? "").trim();
  const caseId = String(formData.get("caseId") ?? "").trim();
  const expiryMinutes = Number(formData.get("expiryMinutes") ?? "");
  const scope = String(formData.get("scope") ?? "read_only").trim();
  const emergency = formData.get("emergency") === "on";
  if (!tenantId || !granteeAuthUserId || !reason || !caseId) {
    return { error: "Tenant, grantee, reason, and case ID are all required." };
  }
  if (!Number.isFinite(expiryMinutes) || expiryMinutes <= 0) {
    return { error: "Expiry (minutes) must be a positive number." };
  }

  const client = toSupportAccessMutationRpcClient(createSupabaseServiceRoleClient());
  try {
    await requestSupportAccess(client, {
      tenantId,
      granteeAuthUserId,
      reason,
      caseId,
      expiryMinutes,
      requestedBy: access.authUserId,
      scope: scope === "read_write" ? "read_write" : "read_only",
      emergency,
      // Only meaningful when emergency=true (app.request_support_access ignores it
      // otherwise) -- the Supreme Admin filing this request is the recorded higher
      // authority, exactly what app.is_support_grant_authority requires.
      authorizedByAuthUserId: emergency ? access.authUserId : null,
    });
  } catch (error) {
    return errorMessage("Could not request support access", error);
  }

  revalidatePath(PATH);
  return OK;
}

export async function approveSupportAccessAction(grantId: string, _prevState: SupportAccessActionState, _formData: FormData): Promise<SupportAccessActionState> {
  const access = await requireAccess();
  if (!access) return NO_ACCESS;

  const client = toSupportAccessMutationRpcClient(createSupabaseServiceRoleClient());
  try {
    await approveSupportAccess(client, { grantId, approverAuthUserId: access.authUserId, approvedBy: access.authUserId, expiresAt: null });
  } catch (error) {
    return errorMessage("Could not approve this request", error);
  }

  revalidatePath(PATH);
  return OK;
}

export async function denySupportAccessAction(grantId: string, _prevState: SupportAccessActionState, formData: FormData): Promise<SupportAccessActionState> {
  const access = await requireAccess();
  if (!access) return NO_ACCESS;

  const reason = String(formData.get("reason") ?? "").trim();
  if (!reason) return { error: "A reason is required to deny a request." };

  const client = toSupportAccessMutationRpcClient(createSupabaseServiceRoleClient());
  try {
    await denySupportAccess(client, { grantId, denierAuthUserId: access.authUserId, deniedBy: access.authUserId, reason });
  } catch (error) {
    return errorMessage("Could not deny this request", error);
  }

  revalidatePath(PATH);
  return OK;
}

/** The kill switch (Prompt 115 §16/§20 task 3) -- the one control AGENTS.md itself names by name ("revocable"). */
export async function revokeSupportAccessAction(grantId: string, _prevState: SupportAccessActionState, formData: FormData): Promise<SupportAccessActionState> {
  const access = await requireAccess();
  if (!access) return NO_ACCESS;

  const reason = String(formData.get("reason") ?? "").trim();
  if (!reason) return { error: "A reason is required to revoke access." };

  const client = toSupportAccessMutationRpcClient(createSupabaseServiceRoleClient());
  try {
    await revokeSupportAccess(client, { grantId, revokerAuthUserId: access.authUserId, revokedBy: access.authUserId, reason });
  } catch (error) {
    return errorMessage("Could not revoke this grant", error);
  }

  revalidatePath(PATH);
  return OK;
}

export async function completeSupportAccessPostReviewAction(grantId: string, _prevState: SupportAccessActionState, formData: FormData): Promise<SupportAccessActionState> {
  const access = await requireAccess();
  if (!access) return NO_ACCESS;

  const note = String(formData.get("note") ?? "").trim();
  if (!note) return { error: "A post-review note is required." };

  const client = toSupportAccessMutationRpcClient(createSupabaseServiceRoleClient());
  try {
    await completeSupportAccessPostReview(client, { grantId, reviewerAuthUserId: access.authUserId, note });
  } catch (error) {
    return errorMessage("Could not complete post-review", error);
  }

  revalidatePath(PATH);
  return OK;
}
