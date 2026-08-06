"use server";

/**
 * Vendor Compliance document/waiver Server Actions (PRC-253, CG-S11-PRC-004).
 * Mirrors app/(tenant)/[tenantSlug]/procurement/assessments/actions.ts's own shape
 * for wiring the real Document/File Engine upload flow (app.initiate_file_upload)
 * into a compliance document submission/renewal -- no prior UI in this repository
 * uploads with record_type='vendor_compliance', so this is that first real call site
 * for this record type, following the identical pattern PRC-252's own UI already
 * established for record_type='vendor_assessment'.
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../../../lib/supabase/server.ts";
import { createSupabaseServiceRoleClient } from "../../../../../../lib/supabase/service-role.ts";
import { resolveProcurementAccessForRequest } from "../../../../../../lib/portal/resolve-procurement-access.server.ts";
import {
  submitVendorComplianceDocument,
  renewVendorComplianceDocument,
  decideVendorComplianceDocument,
  requestVendorComplianceWaiver,
  decideVendorComplianceWaiver,
  revokeVendorComplianceWaiver,
  recalculateVendorComplianceStatus,
  accessVendorComplianceDocumentEvidence,
  VendorComplianceMutationError,
} from "../../../../../../server/mutations/vendor-compliance.ts";
import { getVendorComplianceRequirement, VendorComplianceQueryError } from "../../../../../../server/queries/vendor-compliance.ts";
import { initiateFileUpload, DocumentMutationError, type DocumentMutationRpcClient } from "../../../../../../server/mutations/document.ts";
import type {
  VendorComplianceDocumentDecision,
  VendorComplianceWaiverDecision,
  VendorComplianceAccessType,
  VendorComplianceDocumentEvidenceAccess,
} from "../../../../../../server/contracts/vendor-compliance/vendor-compliance.ts";

export interface VendorComplianceActionState {
  readonly error: string | null;
}

const OK: VendorComplianceActionState = { error: null };
const NO_ACCESS: VendorComplianceActionState = { error: "You don't have access to this organization's Procurement workspace." };

async function requireAccess(tenantSlug: string) {
  const access = await resolveProcurementAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return null;
  return access;
}

/**
 * The real Supabase client's own `rpc` overload set does not structurally satisfy
 * DocumentMutationRpcClient's narrower literal-function-name interface -- identical
 * adapter shape to procurement/assessments/actions.ts's own toDocumentClient.
 *
 * Fix-pass correction: every PLT-128 mutating function (`app.initiate_file_upload`,
 * `app.authorize_file_access`, ...) is granted EXECUTE to `service_role` only, never
 * `authenticated` (see `lib/supabase/service-role.ts`'s own header: "every privileged
 * platform RPC ... is granted to service_role only ... the caller's real identity is
 * authenticated via the RLS-scoped client, then passed explicitly as a parameter to a
 * service-role RPC call"). Calling `initiate_file_upload` through the RLS-scoped
 * `createSupabaseServerClient()` client -- as this file previously did, mirroring
 * `procurement/assessments/actions.ts`'s own identical pattern -- executes as Postgres
 * role `authenticated`, which holds no EXECUTE grant on that function and would fail
 * with a permission-denied error for every real signed-in user. This adapter now
 * takes the service-role client instead; PRC-253's OWN RPCs (submit/renew/decide/...)
 * are untouched and continue to use the RLS-scoped client, since those ARE granted to
 * `authenticated` and perform their own internal app.evaluate_permission check.
 * `procurement/assessments/actions.ts` (PRC-252, already verified/committed) carries
 * the identical anon-client defect and is deliberately left untouched here -- out of
 * this checkpoint's scope, disclosed in docs/build-log/phase-06/PRC-253.md.
 */
function toDocumentClient(client: ReturnType<typeof createSupabaseServiceRoleClient>): DocumentMutationRpcClient {
  return client as unknown as DocumentMutationRpcClient;
}

function detailPath(tenantSlug: string, vendorMasterRecordId: string): string {
  return `/${tenantSlug}/procurement/compliance/vendors/${vendorMasterRecordId}`;
}

type Mutation = (client: Awaited<ReturnType<typeof createSupabaseServerClient>>, input: never) => Promise<unknown>;

async function runAction(tenantSlug: string, vendorMasterRecordId: string, mutation: Mutation, input: Record<string, unknown>, failureVerb: string): Promise<VendorComplianceActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const supabase = await createSupabaseServerClient();
  try {
    await mutation(supabase, { ...input, actorAuthUserId: access.authUserId, actorLabel: access.authUserId } as never);
  } catch (error) {
    if (error instanceof VendorComplianceMutationError) return { error: `Could not ${failureVerb}: ${error.message}` };
    throw error;
  }

  revalidatePath(detailPath(tenantSlug, vendorMasterRecordId));
  revalidatePath(`/${tenantSlug}/procurement/compliance`);
  return OK;
}

// --- Document submission / renewal (wires the real Document/File Engine upload flow) ---

export async function submitVendorComplianceDocumentAction(tenantSlug: string, vendorMasterRecordId: string, _prevState: VendorComplianceActionState, formData: FormData): Promise<VendorComplianceActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const requirementVersionId = String(formData.get("requirementVersionId") ?? "").trim();
  const issueDate = String(formData.get("issueDate") ?? "").trim() || null;
  const expiryDate = String(formData.get("expiryDate") ?? "").trim() || null;
  const evidenceFile = formData.get("evidenceFile");
  if (!(evidenceFile instanceof File) || evidenceFile.size === 0) {
    return { error: "Select an evidence file to submit." };
  }

  const supabase = await createSupabaseServerClient();

  let documentTypeCode: string;
  try {
    const requirement = await getVendorComplianceRequirement(supabase, requirementVersionId, access.authUserId);
    documentTypeCode = requirement.documentTypeCode;
  } catch (error) {
    if (error instanceof VendorComplianceQueryError) return { error: `Could not resolve the selected requirement: ${error.message}` };
    throw error;
  }

  let evidenceFileId: string;
  try {
    const uploaded = await initiateFileUpload(toDocumentClient(createSupabaseServiceRoleClient()), {
      tenantId: access.tenant.id,
      documentTypeCode,
      recordType: "vendor_compliance",
      recordId: vendorMasterRecordId,
      originalFilename: evidenceFile.name,
      mimeType: evidenceFile.type || "application/octet-stream",
      sizeBytes: evidenceFile.size,
      classification: "internal",
      legalHold: false,
      legalHoldReason: null,
      sharedOrgUnitIds: undefined,
      customerAccountRef: null,
      idempotencyKey: null,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
    evidenceFileId = uploaded.id;
  } catch (error) {
    if (error instanceof DocumentMutationError) return { error: `Could not upload this evidence file: ${error.message}` };
    throw error;
  }

  try {
    await submitVendorComplianceDocument(supabase, {
      vendorMasterRecordId,
      requirementVersionId,
      fileId: evidenceFileId,
      issueDate,
      expiryDate,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof VendorComplianceMutationError) return { error: `Could not submit this document: ${error.message}` };
    throw error;
  }

  revalidatePath(detailPath(tenantSlug, vendorMasterRecordId));
  revalidatePath(`/${tenantSlug}/procurement/compliance`);
  return OK;
}

export async function renewVendorComplianceDocumentAction(
  tenantSlug: string,
  vendorMasterRecordId: string,
  previousDocumentId: string,
  _prevState: VendorComplianceActionState,
  formData: FormData,
): Promise<VendorComplianceActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const issueDate = String(formData.get("issueDate") ?? "").trim() || null;
  const expiryDate = String(formData.get("expiryDate") ?? "").trim() || null;
  const documentTypeCode = String(formData.get("documentTypeCode") ?? "").trim();
  const evidenceFile = formData.get("evidenceFile");
  if (!(evidenceFile instanceof File) || evidenceFile.size === 0) {
    return { error: "Select a renewal evidence file." };
  }

  const supabase = await createSupabaseServerClient();

  let evidenceFileId: string;
  try {
    const uploaded = await initiateFileUpload(toDocumentClient(createSupabaseServiceRoleClient()), {
      tenantId: access.tenant.id,
      documentTypeCode,
      recordType: "vendor_compliance",
      recordId: vendorMasterRecordId,
      originalFilename: evidenceFile.name,
      mimeType: evidenceFile.type || "application/octet-stream",
      sizeBytes: evidenceFile.size,
      classification: "internal",
      legalHold: false,
      legalHoldReason: null,
      sharedOrgUnitIds: undefined,
      customerAccountRef: null,
      idempotencyKey: null,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
    evidenceFileId = uploaded.id;
  } catch (error) {
    if (error instanceof DocumentMutationError) return { error: `Could not upload this renewal evidence file: ${error.message}` };
    throw error;
  }

  return runAction(tenantSlug, vendorMasterRecordId, renewVendorComplianceDocument as Mutation, { previousDocumentId, fileId: evidenceFileId, issueDate, expiryDate }, "renew this document");
}

export async function decideVendorComplianceDocumentAction(
  tenantSlug: string,
  vendorMasterRecordId: string,
  documentId: string,
  expectedVersion: number,
  _prevState: VendorComplianceActionState,
  formData: FormData,
) {
  const decision = String(formData.get("decision") ?? "") as VendorComplianceDocumentDecision;
  const rejectionReason = String(formData.get("rejectionReason") ?? "").trim() || null;
  return runAction(tenantSlug, vendorMasterRecordId, decideVendorComplianceDocument as Mutation, { documentId, expectedVersion, decision, rejectionReason }, "record this verification decision");
}

// --- Evidence access (fix-pass addition, HIGH-severity finding, adversarial review) ---

export interface VendorComplianceEvidenceAccessState {
  readonly error: string | null;
  readonly access: VendorComplianceDocumentEvidenceAccess | null;
}

/**
 * The document/version viewer's own gated evidence-access call (Sec.15/16/18/21) --
 * calls app.access_vendor_compliance_document_evidence, which composes PRC:Download
 * authority with PLT-128's own app.authorize_file_access (malware-scan + record/
 * sensitivity gate, RPD-032). This RPC IS granted to `authenticated` (it performs its
 * own internal app.evaluate_permission check, the same shape as every other PRC-253
 * RPC) -- unlike app.initiate_file_upload above, the RLS-scoped client is correct
 * here, not the service-role client.
 */
export async function accessVendorComplianceDocumentEvidenceAction(
  tenantSlug: string,
  documentId: string,
  accessType: VendorComplianceAccessType,
  _prevState: VendorComplianceEvidenceAccessState,
  _formData: FormData,
): Promise<VendorComplianceEvidenceAccessState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return { error: NO_ACCESS.error, access: null };

  const supabase = await createSupabaseServerClient();
  try {
    const result = await accessVendorComplianceDocumentEvidence(supabase, {
      documentId,
      accessType,
      correlationId: null,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
    return { error: null, access: result };
  } catch (error) {
    if (error instanceof VendorComplianceMutationError) return { error: `Could not access this evidence file: ${error.message}`, access: null };
    throw error;
  }
}

// --- Waivers ---

export async function requestVendorComplianceWaiverAction(tenantSlug: string, vendorMasterRecordId: string, _prevState: VendorComplianceActionState, formData: FormData) {
  const requirementVersionId = String(formData.get("requirementVersionId") ?? "").trim();
  const reason = String(formData.get("reason") ?? "").trim();
  const validFrom = String(formData.get("validFrom") ?? "").trim();
  const validUntil = String(formData.get("validUntil") ?? "").trim();
  return runAction(tenantSlug, vendorMasterRecordId, requestVendorComplianceWaiver as Mutation, { requirementVersionId, vendorMasterRecordId, reason, validFrom, validUntil, idempotencyKey: null }, "request this waiver");
}

export async function decideVendorComplianceWaiverAction(tenantSlug: string, vendorMasterRecordId: string, waiverId: string, expectedVersion: number, _prevState: VendorComplianceActionState, formData: FormData) {
  const decision = String(formData.get("decision") ?? "") as VendorComplianceWaiverDecision;
  const decisionReason = String(formData.get("decisionReason") ?? "").trim() || null;
  return runAction(tenantSlug, vendorMasterRecordId, decideVendorComplianceWaiver as Mutation, { waiverId, expectedVersion, decision, decisionReason }, "record this waiver decision");
}

export async function revokeVendorComplianceWaiverAction(tenantSlug: string, vendorMasterRecordId: string, waiverId: string, expectedVersion: number, _prevState: VendorComplianceActionState, formData: FormData) {
  const reason = String(formData.get("reason") ?? "").trim();
  return runAction(tenantSlug, vendorMasterRecordId, revokeVendorComplianceWaiver as Mutation, { waiverId, expectedVersion, reason }, "revoke this waiver");
}

// --- Recalculation ---

export async function recalculateVendorComplianceStatusAction(tenantSlug: string, vendorMasterRecordId: string, _prevState: VendorComplianceActionState, _formData: FormData): Promise<VendorComplianceActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const supabase = await createSupabaseServerClient();
  try {
    await recalculateVendorComplianceStatus(supabase, { vendorMasterRecordId, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof VendorComplianceMutationError) return { error: `Could not recalculate this vendor's compliance status: ${error.message}` };
    throw error;
  }

  revalidatePath(detailPath(tenantSlug, vendorMasterRecordId));
  revalidatePath(`/${tenantSlug}/procurement/compliance`);
  return OK;
}
