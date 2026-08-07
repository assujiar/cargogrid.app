"use server";

/**
 * Procurement Approval Server Actions (PRC-259, CG-S11-PRC-010). Mirrors
 * app/(tenant)/[tenantSlug]/procurement/vendor-comparison/actions.ts's own exact shape
 * (resolve portal access, call the typed mutation wrapper, translate a known mutation
 * error into a plain-language message, revalidate). The one dispatch this file adds
 * over that template: decideProcurementApprovalStepAction is bound per-row to the
 * correct one of the four domain sync wrapper mutations by entityType (resolved
 * server-side on the detail page before the form ever renders -- never trusted from
 * client-supplied form data), since a step's governed entity_type determines which of
 * app.decide_vendor_activation_approval_step / app.decide_rate_version_approval_step /
 * app.decide_vendor_selection_approval_step / app.decide_procurement_exception_approval_
 * step must be called.
 *
 * Idempotency-key disclosure: identical to every other PRC-25x creation form in this
 * repository -- a fresh crypto.randomUUID() is generated here, server-side, on every
 * submit, not client-persisted. The RPC-level idempotency guarantee itself is real and
 * tested (scripts/db-tests/procurement-approval.sql).
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { resolveProcurementAccessForRequest } from "../../../../../lib/portal/resolve-procurement-access.server.ts";
import {
  createProcurementApprovalPolicyVersion,
  publishProcurementApprovalPolicyVersion,
  decideVendorActivationApprovalStep,
  decideRateVersionApprovalStep,
  decideVendorSelectionApprovalStep,
  decidePurchaseOrderApprovalStep,
  decideProcurementExceptionApprovalStep,
  createProcurementExceptionRequest,
  cancelProcurementExceptionRequest,
  ProcurementApprovalMutationError,
} from "../../../../../server/mutations/procurement-approval.ts";
import type { ProcurementApprovalEntityType } from "../../../../../server/contracts/procurement-approval/procurement-approval.ts";

export interface ProcurementApprovalActionState {
  readonly error: string | null;
}

const OK: ProcurementApprovalActionState = { error: null };
const NO_ACCESS: ProcurementApprovalActionState = { error: "You don't have access to this organization's Procurement workspace." };

async function requireAccess(tenantSlug: string) {
  const access = await resolveProcurementAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return null;
  return access;
}

function inboxPath(tenantSlug: string): string {
  return `/${tenantSlug}/procurement/approvals`;
}

function detailPath(tenantSlug: string, stepId: string): string {
  return `/${tenantSlug}/procurement/approvals/${stepId}`;
}

// --- Policy actions ---------------------------------------------------------

export async function createProcurementApprovalPolicyAction(tenantSlug: string, _prevState: ProcurementApprovalActionState, formData: FormData): Promise<ProcurementApprovalActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const entityType = String(formData.get("entityType") ?? "") as ProcurementApprovalEntityType;
  const alwaysRequired = formData.get("alwaysRequired") === "on";
  const minValueAmountRaw = String(formData.get("minValueAmount") ?? "").trim();

  const supabase = await createSupabaseServerClient();
  try {
    await createProcurementApprovalPolicyVersion(supabase, {
      tenantId: access.tenant.id,
      entityType,
      minValueAmount: minValueAmountRaw.length > 0 ? Number(minValueAmountRaw) : null,
      alwaysRequired,
      actorAuthUserId: access.authUserId,
      createdBy: access.authUserId,
    });
  } catch (error) {
    if (error instanceof ProcurementApprovalMutationError) return { error: `Could not create the policy: ${error.message}` };
    throw error;
  }

  revalidatePath(inboxPath(tenantSlug));
  return OK;
}

export async function publishProcurementApprovalPolicyAction(
  tenantSlug: string,
  policyVersionId: string,
  expectedVersion: number,
  supersedesVersionId: string | null,
  _prevState: ProcurementApprovalActionState,
  _formData: FormData,
): Promise<ProcurementApprovalActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const supabase = await createSupabaseServerClient();
  try {
    await publishProcurementApprovalPolicyVersion(supabase, {
      policyVersionId,
      expectedVersion,
      supersedesVersionId,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof ProcurementApprovalMutationError) return { error: `Could not publish the policy: ${error.message}` };
    throw error;
  }

  revalidatePath(inboxPath(tenantSlug));
  return OK;
}

// --- Exception/override request actions -------------------------------------

export async function createProcurementExceptionRequestAction(tenantSlug: string, _prevState: ProcurementApprovalActionState, formData: FormData): Promise<ProcurementApprovalActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const exceptionType = String(formData.get("exceptionType") ?? "").trim();
  const reason = String(formData.get("reason") ?? "").trim();
  const relatedEntityType = String(formData.get("relatedEntityType") ?? "").trim() || null;
  const relatedEntityId = String(formData.get("relatedEntityId") ?? "").trim() || null;
  const requestedOutcome = String(formData.get("requestedOutcome") ?? "").trim() || null;
  if (!exceptionType || !reason) {
    return { error: "An exception type and a non-empty reason are required." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await createProcurementExceptionRequest(supabase, {
      tenantId: access.tenant.id,
      relatedEntityType,
      relatedEntityId,
      exceptionType,
      reason,
      requestedOutcome,
      idempotencyKey: crypto.randomUUID(),
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof ProcurementApprovalMutationError) return { error: `Could not create the exception request: ${error.message}` };
    throw error;
  }

  revalidatePath(inboxPath(tenantSlug));
  return OK;
}

export async function cancelProcurementExceptionRequestAction(
  tenantSlug: string,
  id: string,
  expectedVersion: number,
  _prevState: ProcurementApprovalActionState,
  formData: FormData,
): Promise<ProcurementApprovalActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const reason = String(formData.get("reason") ?? "").trim();
  if (!reason) {
    return { error: "A non-empty reason is required to withdraw an exception request." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await cancelProcurementExceptionRequest(supabase, { id, expectedVersion, reason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof ProcurementApprovalMutationError) return { error: `Could not withdraw: ${error.message}` };
    throw error;
  }

  revalidatePath(inboxPath(tenantSlug));
  return OK;
}

// --- Decision actions (detail page) -----------------------------------------

/** Bound to the correct one of the four domain sync wrapper mutations by entityType, resolved server-side on the detail page -- never trusted from client-supplied form data. */
export async function decideProcurementApprovalStepAction(
  tenantSlug: string,
  stepId: string,
  entityType: ProcurementApprovalEntityType,
  _prevState: ProcurementApprovalActionState,
  formData: FormData,
): Promise<ProcurementApprovalActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const decisionRaw = String(formData.get("decision") ?? "");
  if (decisionRaw !== "approved" && decisionRaw !== "rejected") {
    return { error: "Decision must be approved or rejected." };
  }
  const reason = String(formData.get("reason") ?? "").trim() || null;
  if (decisionRaw === "rejected" && !reason) {
    return { error: "A non-empty reason is required to reject." };
  }
  // Prompt 259 §16's MFA-for-privileged-approvers gate (batch 257-259 review, C-18,
  // HIGH) -- the client captures the current timestamp only once the reauth-attestation
  // checkbox is checked (approval-decision-panel.tsx); the RPC layer independently
  // re-validates freshness (<=5 minutes) on every call, so this client-supplied value is
  // never trusted blindly.
  const reauthConfirmedAt = String(formData.get("reauthConfirmedAt") ?? "").trim();
  if (!reauthConfirmedAt) {
    return { error: "Re-authentication confirmation is required for this decision." };
  }

  const input = { requestStepId: stepId, decision: decisionRaw, actorAuthUserId: access.authUserId, actorLabel: access.authUserId, reauthConfirmedAt, reason } as const;
  const supabase = await createSupabaseServerClient();
  try {
    switch (entityType) {
      case "vendor_activation":
        await decideVendorActivationApprovalStep(supabase, input);
        break;
      case "rate_version":
        await decideRateVersionApprovalStep(supabase, input);
        break;
      case "vendor_selection":
        await decideVendorSelectionApprovalStep(supabase, input);
        break;
      case "exception_override":
        await decideProcurementExceptionApprovalStep(supabase, input);
        break;
      case "purchase_order":
        // PRC-260 (Prompt 260, Purchase Order): the domain sync wrapper this capability's
        // own migration header documented as future work -- now wired.
        await decidePurchaseOrderApprovalStep(supabase, input);
        break;
      case "vendor_contract":
        // Registered as a valid policy/context entity_type dimension (see PRC-259's own
        // migration header) but no governed entity table exists yet -- no decide wrapper
        // exists to dispatch to until a future vendor-contract capability ships. A step
        // of this entity_type can never actually be created today (nothing calls
        // app.request_approval with it), so this branch is unreachable in practice, not
        // a silently swallowed real case.
        return { error: `No governed entity capability exists yet for ${entityType} -- this step should be unreachable.` };
    }
  } catch (error) {
    if (error instanceof ProcurementApprovalMutationError) return { error: `Could not record the decision: ${error.message}` };
    throw error;
  }

  revalidatePath(detailPath(tenantSlug, stepId));
  revalidatePath(inboxPath(tenantSlug));
  return OK;
}

// Deliberately no cancelProcurementApprovalRequestAction: app.cancel_approval_request
// (PLT-123) is granted service_role ONLY (the migration's own grant block) -- every
// write RPC on the generic Approval Engine except the two entity-agnostic read view
// models is service_role-only, matching server/mutations/approval.ts's own header
// ("All service_role-only"). No prior capability in this repository (including
// Commercial Quotation/Credit Approval, COM-153/157) has ever built a UI caller for
// cancel/delegate/escalate for exactly this reason -- there is no RLS-scoped session
// path to reach them from, and this checkpoint does not invent one (that would be a
// new anonymous/broadened entry point decision out of this prompt's own scope, an
// ADR-0021 batch-cut trigger on its own). Disclosed here, not silently omitted.
