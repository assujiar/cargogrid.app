"use server";

/**
 * Vendor Registration and Onboarding Server Actions (PRC-251, CG-S11-PRC-002). Mirrors
 * app/(tenant)/[tenantSlug]/operations/fleet/actions.ts's own shape: resolve portal
 * access, call the typed mutation wrapper, translate a known mutation error into a
 * plain-language message, revalidate the affected path(s).
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { resolveProcurementAccessForRequest } from "../../../../../lib/portal/resolve-procurement-access.server.ts";
import {
  createVendorProfileDraft,
  submitVendorProfileForReview,
  beginVendorProfileReview,
  decideVendorProfileReview,
  activateVendorProfile,
  suspendVendorProfile,
  reactivateVendorProfile,
  archiveVendorProfile,
  blacklistVendorProfile,
  addVendorContact,
  updateVendorContact,
  removeVendorContact,
  addVendorAddress,
  updateVendorAddress,
  removeVendorAddress,
  addVendorService,
  removeVendorService,
  addVendorCoverage,
  removeVendorCoverage,
  flagVendorDuplicateCandidate,
  decideVendorDuplicateCandidate,
  createVendorIntakeToken,
  revokeVendorIntakeToken,
  VendorProfileMutationError,
} from "../../../../../server/mutations/vendor-profile.ts";
import type { VendorAddressType, VendorReviewDecision } from "../../../../../server/contracts/vendor-profile/vendor-profile.ts";

export interface VendorActionState {
  readonly error: string | null;
}

const OK: VendorActionState = { error: null };

async function requireAccess(tenantSlug: string) {
  const access = await resolveProcurementAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return null;
  }
  return access;
}

function detailPath(tenantSlug: string, masterRecordId: string): string {
  return `/${tenantSlug}/procurement/vendors/${masterRecordId}`;
}

export async function createVendorProfileDraftAction(tenantSlug: string, _prevState: VendorActionState, formData: FormData): Promise<VendorActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return { error: "You don't have access to this organization's Procurement workspace." };

  const legalName = String(formData.get("legalName") ?? "").trim();
  const tradeName = String(formData.get("tradeName") ?? "").trim() || null;
  const legalEntityType = String(formData.get("legalEntityType") ?? "").trim() || null;
  const businessRegistrationNumber = String(formData.get("businessRegistrationNumber") ?? "").trim() || null;
  const vendorCategory = String(formData.get("vendorCategory") ?? "").trim() || null;
  const paymentTermDaysRaw = String(formData.get("paymentTermDays") ?? "").trim();
  const idempotencyKey = String(formData.get("idempotencyKey") ?? "").trim() || null;

  const supabase = await createSupabaseServerClient();
  try {
    await createVendorProfileDraft(supabase, {
      tenantId: access.tenant.id,
      legalName,
      tradeName,
      legalEntityType,
      businessRegistrationNumber,
      vendorCategory,
      paymentTermDays: paymentTermDaysRaw.length === 0 ? null : Number(paymentTermDaysRaw),
      intakeSource: "staff_created",
      idempotencyKey,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof VendorProfileMutationError) return { error: `Could not create this vendor draft: ${error.message}` };
    throw error;
  }

  revalidatePath(`/${tenantSlug}/procurement/vendors`);
  return OK;
}

type LifecycleMutation = (client: Awaited<ReturnType<typeof createSupabaseServerClient>>, input: never) => Promise<unknown>;

async function runLifecycleAction(
  tenantSlug: string,
  masterRecordId: string,
  mutation: LifecycleMutation,
  input: Record<string, unknown>,
  failureVerb: string,
): Promise<VendorActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return { error: "You don't have access to this organization's Procurement workspace." };

  const supabase = await createSupabaseServerClient();
  try {
    await mutation(supabase, { ...input, actorAuthUserId: access.authUserId, actorLabel: access.authUserId } as never);
  } catch (error) {
    if (error instanceof VendorProfileMutationError) return { error: `Could not ${failureVerb}: ${error.message}` };
    throw error;
  }

  revalidatePath(detailPath(tenantSlug, masterRecordId));
  revalidatePath(`/${tenantSlug}/procurement/vendors`);
  return OK;
}

export async function submitVendorProfileAction(tenantSlug: string, masterRecordId: string, expectedVersion: number, _prevState: VendorActionState, _formData: FormData) {
  return runLifecycleAction(tenantSlug, masterRecordId, submitVendorProfileForReview as LifecycleMutation, { masterRecordId, expectedVersion }, "submit this vendor profile for review");
}

export async function beginVendorProfileReviewAction(tenantSlug: string, masterRecordId: string, expectedVersion: number, _prevState: VendorActionState, _formData: FormData) {
  return runLifecycleAction(tenantSlug, masterRecordId, beginVendorProfileReview as LifecycleMutation, { masterRecordId, expectedVersion }, "begin review");
}

export async function decideVendorProfileReviewAction(tenantSlug: string, masterRecordId: string, expectedVersion: number, _prevState: VendorActionState, formData: FormData) {
  const decision = String(formData.get("decision") ?? "") as VendorReviewDecision;
  const reason = String(formData.get("reason") ?? "").trim() || null;
  return runLifecycleAction(tenantSlug, masterRecordId, decideVendorProfileReview as LifecycleMutation, { masterRecordId, expectedVersion, decision, reason }, "record this review decision");
}

export async function activateVendorProfileAction(tenantSlug: string, masterRecordId: string, expectedVersion: number, _prevState: VendorActionState, _formData: FormData) {
  return runLifecycleAction(tenantSlug, masterRecordId, activateVendorProfile as LifecycleMutation, { masterRecordId, expectedVersion }, "activate this vendor");
}

export async function suspendVendorProfileAction(tenantSlug: string, masterRecordId: string, expectedVersion: number, _prevState: VendorActionState, formData: FormData) {
  const reason = String(formData.get("reason") ?? "").trim();
  return runLifecycleAction(tenantSlug, masterRecordId, suspendVendorProfile as LifecycleMutation, { masterRecordId, expectedVersion, reason }, "suspend this vendor");
}

export async function reactivateVendorProfileAction(tenantSlug: string, masterRecordId: string, expectedVersion: number, _prevState: VendorActionState, _formData: FormData) {
  return runLifecycleAction(tenantSlug, masterRecordId, reactivateVendorProfile as LifecycleMutation, { masterRecordId, expectedVersion }, "reactivate this vendor");
}

export async function archiveVendorProfileAction(tenantSlug: string, masterRecordId: string, expectedVersion: number, _prevState: VendorActionState, formData: FormData) {
  const reason = String(formData.get("reason") ?? "").trim() || null;
  return runLifecycleAction(tenantSlug, masterRecordId, archiveVendorProfile as LifecycleMutation, { masterRecordId, expectedVersion, reason }, "archive this vendor");
}

export async function blacklistVendorProfileAction(tenantSlug: string, masterRecordId: string, expectedVersion: number, _prevState: VendorActionState, formData: FormData) {
  const reason = String(formData.get("reason") ?? "").trim();
  const evidenceRef = String(formData.get("evidenceRef") ?? "").trim();
  return runLifecycleAction(tenantSlug, masterRecordId, blacklistVendorProfile as LifecycleMutation, { masterRecordId, expectedVersion, reason, evidenceRef }, "blacklist this vendor");
}

// --- Child records ---

export async function addVendorContactAction(tenantSlug: string, masterRecordId: string, _prevState: VendorActionState, formData: FormData) {
  const name = String(formData.get("name") ?? "").trim();
  const title = String(formData.get("title") ?? "").trim() || null;
  const email = String(formData.get("email") ?? "").trim() || null;
  const phone = String(formData.get("phone") ?? "").trim() || null;
  const isPrimary = formData.get("isPrimary") === "on";
  return runLifecycleAction(tenantSlug, masterRecordId, addVendorContact as LifecycleMutation, { masterRecordId, name, title, email, phone, isPrimary }, "add this contact");
}

export async function removeVendorContactAction(tenantSlug: string, masterRecordId: string, contactId: string, expectedVersion: number, _prevState: VendorActionState, _formData: FormData) {
  return runLifecycleAction(tenantSlug, masterRecordId, removeVendorContact as LifecycleMutation, { contactId, expectedVersion }, "remove this contact");
}

export async function updateVendorContactPrimaryAction(
  tenantSlug: string,
  masterRecordId: string,
  contactId: string,
  expectedVersion: number,
  name: string,
  title: string | null,
  email: string | null,
  phone: string | null,
  _prevState: VendorActionState,
  _formData: FormData,
) {
  return runLifecycleAction(tenantSlug, masterRecordId, updateVendorContact as LifecycleMutation, { contactId, expectedVersion, name, title, email, phone, isPrimary: true }, "set this contact as primary");
}

export async function addVendorAddressAction(tenantSlug: string, masterRecordId: string, _prevState: VendorActionState, formData: FormData) {
  const addressType = String(formData.get("addressType") ?? "") as VendorAddressType;
  const street = String(formData.get("street") ?? "").trim();
  const city = String(formData.get("city") ?? "").trim();
  const province = String(formData.get("province") ?? "").trim() || null;
  const postalCode = String(formData.get("postalCode") ?? "").trim() || null;
  const country = String(formData.get("country") ?? "").trim();
  return runLifecycleAction(
    tenantSlug,
    masterRecordId,
    addVendorAddress as LifecycleMutation,
    { masterRecordId, addressType, street, city, province, postalCode, country },
    "add this address",
  );
}

export async function removeVendorAddressAction(tenantSlug: string, masterRecordId: string, addressId: string, expectedVersion: number, _prevState: VendorActionState, _formData: FormData) {
  return runLifecycleAction(tenantSlug, masterRecordId, removeVendorAddress as LifecycleMutation, { addressId, expectedVersion }, "remove this address");
}

export async function addVendorServiceAction(tenantSlug: string, masterRecordId: string, _prevState: VendorActionState, formData: FormData) {
  const serviceType = String(formData.get("serviceType") ?? "").trim();
  return runLifecycleAction(tenantSlug, masterRecordId, addVendorService as LifecycleMutation, { masterRecordId, serviceType }, "add this service");
}

export async function removeVendorServiceAction(tenantSlug: string, masterRecordId: string, serviceId: string, expectedVersion: number, _prevState: VendorActionState, _formData: FormData) {
  return runLifecycleAction(tenantSlug, masterRecordId, removeVendorService as LifecycleMutation, { serviceId, expectedVersion }, "remove this service");
}

export async function addVendorCoverageAction(tenantSlug: string, masterRecordId: string, _prevState: VendorActionState, formData: FormData) {
  const originLane = String(formData.get("originLane") ?? "").trim();
  const destinationLane = String(formData.get("destinationLane") ?? "").trim() || null;
  return runLifecycleAction(tenantSlug, masterRecordId, addVendorCoverage as LifecycleMutation, { masterRecordId, originLane, destinationLane }, "add this coverage lane");
}

export async function removeVendorCoverageAction(tenantSlug: string, masterRecordId: string, coverageId: string, expectedVersion: number, _prevState: VendorActionState, _formData: FormData) {
  return runLifecycleAction(tenantSlug, masterRecordId, removeVendorCoverage as LifecycleMutation, { coverageId, expectedVersion }, "remove this coverage lane");
}

// --- Duplicate review ---

export async function flagVendorDuplicateCandidateAction(tenantSlug: string, masterRecordId: string, candidateMasterRecordId: string, similarityScore: number | null, _prevState: VendorActionState, _formData: FormData) {
  return runLifecycleAction(
    tenantSlug,
    masterRecordId,
    flagVendorDuplicateCandidate as LifecycleMutation,
    { sourceMasterRecordId: masterRecordId, candidateMasterRecordId, similarityBasis: "trigram legal_name/trade_name similarity", similarityScore },
    "flag this duplicate candidate",
  );
}

export async function decideVendorDuplicateCandidateAction(
  tenantSlug: string,
  masterRecordId: string,
  candidateId: string,
  expectedVersion: number,
  _prevState: VendorActionState,
  formData: FormData,
) {
  const decision = String(formData.get("decision") ?? "") as "linked" | "dismissed";
  const reason = String(formData.get("reason") ?? "").trim();
  return runLifecycleAction(tenantSlug, masterRecordId, decideVendorDuplicateCandidate as LifecycleMutation, { candidateId, expectedVersion, decision, reason }, "record this duplicate-review decision");
}

// --- Intake ---

export interface IssueTokenActionState {
  readonly error: string | null;
  /** The raw bearer token, present only immediately after a true first issuance -- app.create_vendor_intake_token never stores it, so this is the only moment the UI can ever show it. */
  readonly rawToken: string | null;
  readonly intendedEmail: string | null;
}

const ISSUE_TOKEN_INITIAL: IssueTokenActionState = { error: null, rawToken: null, intendedEmail: null };

export async function createVendorIntakeTokenAction(tenantSlug: string, _prevState: IssueTokenActionState, formData: FormData): Promise<IssueTokenActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return { ...ISSUE_TOKEN_INITIAL, error: "You don't have access to this organization's Procurement workspace." };

  const intendedEmail = String(formData.get("intendedEmail") ?? "").trim();
  const validityDaysRaw = String(formData.get("validityDays") ?? "7").trim();

  const supabase = await createSupabaseServerClient();
  let result: Awaited<ReturnType<typeof createVendorIntakeToken>>;
  try {
    result = await createVendorIntakeToken(supabase, {
      tenantId: access.tenant.id,
      intendedEmail,
      validityDays: Number(validityDaysRaw) || 7,
      idempotencyKey: null,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof VendorProfileMutationError) return { ...ISSUE_TOKEN_INITIAL, error: `Could not issue this invitation: ${error.message}` };
    throw error;
  }

  revalidatePath(`/${tenantSlug}/procurement/vendors/intake`);
  return { error: null, rawToken: result.rawToken, intendedEmail: result.intendedEmail };
}

export async function revokeVendorIntakeTokenAction(tenantSlug: string, tokenId: string, _prevState: VendorActionState, formData: FormData): Promise<VendorActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return { error: "You don't have access to this organization's Procurement workspace." };

  const reason = String(formData.get("reason") ?? "").trim();
  const supabase = await createSupabaseServerClient();
  try {
    await revokeVendorIntakeToken(supabase, { tokenId, reason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof VendorProfileMutationError) return { error: `Could not revoke this invitation: ${error.message}` };
    throw error;
  }

  revalidatePath(`/${tenantSlug}/procurement/vendors/intake`);
  return OK;
}
