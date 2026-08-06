"use server";

/**
 * Vendor Assessment Server Actions (PRC-252, CG-S11-PRC-003). Mirrors
 * app/(tenant)/[tenantSlug]/procurement/vendors/actions.ts's own shape: resolve
 * portal access, call the typed mutation wrapper, translate a known mutation error
 * into a plain-language message, revalidate the affected path(s). Authorization is
 * enforced server-side by the RPCs themselves (evaluate_permission) -- this file
 * never hides an action from an unauthorized viewer client-side only.
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { resolveProcurementAccessForRequest } from "../../../../../lib/portal/resolve-procurement-access.server.ts";
import {
  startVendorAssessment,
  recordVendorAssessmentAnswer,
  calculateVendorAssessmentScore,
  submitVendorAssessmentForReview,
  beginVendorAssessmentReview,
  decideVendorAssessmentReview,
  adjustVendorAssessmentScore,
  closeVendorAssessment,
  startVendorAssessmentReassessment,
  raiseVendorAssessmentFinding,
  decideVendorAssessmentFinding,
  createVendorAssessmentCorrectiveAction,
  updateVendorAssessmentCorrectiveActionStatus,
  VendorAssessmentMutationError,
} from "../../../../../server/mutations/vendor-assessment.ts";
import { initiateFileUpload, DocumentMutationError, type DocumentMutationRpcClient } from "../../../../../server/mutations/document.ts";
import type {
  VendorAssessmentReviewDecision,
  VendorAssessmentFindingDecision,
  VendorAssessmentFindingSeverity,
  VendorAssessmentCorrectiveActionStatus,
} from "../../../../../server/contracts/vendor-assessment/vendor-assessment.ts";

export interface AssessmentActionState {
  readonly error: string | null;
}

const OK: AssessmentActionState = { error: null };
const NO_ACCESS: AssessmentActionState = { error: "You don't have access to this organization's Procurement workspace." };

async function requireAccess(tenantSlug: string) {
  const access = await resolveProcurementAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return null;
  return access;
}

/**
 * The real Supabase client's own `rpc` overload set does not structurally satisfy
 * DocumentMutationRpcClient's narrower literal-function-name interface (a pure type-
 * level mismatch -- the real client accepts a much wider `fn: string`) -- this is the
 * first real (non-test-mock) caller of the Document/File Engine's mutation wrappers
 * from a live Server Action, so no prior call site needed this adapter.
 */
function toDocumentClient(client: Awaited<ReturnType<typeof createSupabaseServerClient>>): DocumentMutationRpcClient {
  return client as unknown as DocumentMutationRpcClient;
}

function detailPath(tenantSlug: string, assessmentId: string): string {
  return `/${tenantSlug}/procurement/assessments/${assessmentId}`;
}

type Mutation = (client: Awaited<ReturnType<typeof createSupabaseServerClient>>, input: never) => Promise<unknown>;

async function runAction(tenantSlug: string, assessmentId: string | null, mutation: Mutation, input: Record<string, unknown>, failureVerb: string): Promise<AssessmentActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const supabase = await createSupabaseServerClient();
  try {
    await mutation(supabase, { ...input, actorAuthUserId: access.authUserId, actorLabel: access.authUserId } as never);
  } catch (error) {
    if (error instanceof VendorAssessmentMutationError) return { error: `Could not ${failureVerb}: ${error.message}` };
    throw error;
  }

  if (assessmentId) revalidatePath(detailPath(tenantSlug, assessmentId));
  revalidatePath(`/${tenantSlug}/procurement/assessments`);
  return OK;
}

// --- Start / reassess ---

export async function startVendorAssessmentAction(tenantSlug: string, _prevState: AssessmentActionState, formData: FormData): Promise<AssessmentActionState> {
  const vendorMasterRecordId = String(formData.get("vendorMasterRecordId") ?? "").trim();
  const templateVersionId = String(formData.get("templateVersionId") ?? "").trim();
  const idempotencyKey = String(formData.get("idempotencyKey") ?? "").trim() || null;
  return runAction(tenantSlug, null, startVendorAssessment as Mutation, { vendorMasterRecordId, templateVersionId, reviewerAuthUserId: null, idempotencyKey }, "start this assessment");
}

export async function startVendorAssessmentReassessmentAction(tenantSlug: string, predecessorAssessmentId: string, _prevState: AssessmentActionState, formData: FormData): Promise<AssessmentActionState> {
  const templateVersionId = String(formData.get("templateVersionId") ?? "").trim();
  return runAction(
    tenantSlug,
    null,
    startVendorAssessmentReassessment as Mutation,
    { predecessorAssessmentId, templateVersionId, reviewerAuthUserId: null, idempotencyKey: null },
    "start this reassessment",
  );
}

// --- Questionnaire ---

export async function recordVendorAssessmentAnswerAction(tenantSlug: string, assessmentId: string, criterionId: string, _prevState: AssessmentActionState, formData: FormData): Promise<AssessmentActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const value = String(formData.get("value") ?? "").trim() || null;
  const scoreRaw = String(formData.get("score") ?? "").trim();
  const notes = String(formData.get("notes") ?? "").trim() || null;
  const score = scoreRaw.length === 0 ? NaN : Number(scoreRaw);
  if (!Number.isFinite(score) || score < 0 || score > 100) {
    return { error: "Score must be a number between 0 and 100." };
  }

  const evidenceFile = formData.get("evidenceFile");
  let evidenceFileId: string | null = null;
  const supabase = await createSupabaseServerClient();
  if (evidenceFile instanceof File && evidenceFile.size > 0) {
    try {
      const uploaded = await initiateFileUpload(toDocumentClient(supabase), {
        tenantId: access.tenant.id,
        documentTypeCode: "vendor_assessment_evidence",
        recordType: "vendor_assessment",
        recordId: assessmentId,
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
      if (error instanceof DocumentMutationError) return { error: `Could not attach this evidence file: ${error.message}` };
      throw error;
    }
  }

  try {
    await recordVendorAssessmentAnswer(supabase, {
      assessmentId,
      criterionId,
      value,
      score,
      evidenceFileId,
      notes,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof VendorAssessmentMutationError) return { error: `Could not record this answer: ${error.message}` };
    throw error;
  }

  revalidatePath(detailPath(tenantSlug, assessmentId));
  return OK;
}

export async function calculateVendorAssessmentScoreAction(tenantSlug: string, assessmentId: string, expectedVersion: number, _prevState: AssessmentActionState, _formData: FormData) {
  return runAction(tenantSlug, assessmentId, calculateVendorAssessmentScore as Mutation, { assessmentId, expectedVersion }, "recalculate this score");
}

export async function submitVendorAssessmentForReviewAction(tenantSlug: string, assessmentId: string, expectedVersion: number, _prevState: AssessmentActionState, _formData: FormData) {
  return runAction(tenantSlug, assessmentId, submitVendorAssessmentForReview as Mutation, { assessmentId, expectedVersion, reviewerAuthUserId: null }, "submit this assessment for review");
}

// --- Review ---

export async function beginVendorAssessmentReviewAction(tenantSlug: string, assessmentId: string, expectedVersion: number, _prevState: AssessmentActionState, _formData: FormData) {
  return runAction(tenantSlug, assessmentId, beginVendorAssessmentReview as Mutation, { assessmentId, expectedVersion }, "begin this review");
}

export async function decideVendorAssessmentReviewAction(tenantSlug: string, assessmentId: string, expectedVersion: number, _prevState: AssessmentActionState, formData: FormData) {
  const decision = String(formData.get("decision") ?? "") as VendorAssessmentReviewDecision;
  const reason = String(formData.get("reason") ?? "").trim() || null;
  return runAction(tenantSlug, assessmentId, decideVendorAssessmentReview as Mutation, { assessmentId, expectedVersion, decision, reason }, "record this review decision");
}

export async function adjustVendorAssessmentScoreAction(tenantSlug: string, assessmentId: string, expectedVersion: number, _prevState: AssessmentActionState, formData: FormData) {
  const adjustedScoreRaw = String(formData.get("adjustedScore") ?? "").trim();
  const reason = String(formData.get("reason") ?? "").trim();
  const adjustedScore = Number(adjustedScoreRaw);
  if (!Number.isFinite(adjustedScore) || adjustedScore < 0 || adjustedScore > 100) {
    return { error: "Adjusted score must be a number between 0 and 100." };
  }
  return runAction(tenantSlug, assessmentId, adjustVendorAssessmentScore as Mutation, { assessmentId, expectedVersion, adjustedScore, reason }, "adjust this score");
}

export async function closeVendorAssessmentAction(tenantSlug: string, assessmentId: string, expectedVersion: number, _prevState: AssessmentActionState, formData: FormData) {
  const overrideReason = String(formData.get("overrideReason") ?? "").trim() || null;
  return runAction(tenantSlug, assessmentId, closeVendorAssessment as Mutation, { assessmentId, expectedVersion, overrideReason }, "close this assessment");
}

// --- Findings / corrective actions ---

export async function raiseVendorAssessmentFindingAction(tenantSlug: string, assessmentId: string, _prevState: AssessmentActionState, formData: FormData) {
  const severity = String(formData.get("severity") ?? "") as VendorAssessmentFindingSeverity;
  const description = String(formData.get("description") ?? "").trim();
  return runAction(tenantSlug, assessmentId, raiseVendorAssessmentFinding as Mutation, { assessmentId, severity, description }, "raise this finding");
}

export async function decideVendorAssessmentFindingAction(tenantSlug: string, assessmentId: string, findingId: string, expectedVersion: number, _prevState: AssessmentActionState, formData: FormData) {
  const decision = String(formData.get("decision") ?? "") as VendorAssessmentFindingDecision;
  const reason = String(formData.get("reason") ?? "").trim();
  return runAction(tenantSlug, assessmentId, decideVendorAssessmentFinding as Mutation, { findingId, expectedVersion, decision, reason }, "record this finding decision");
}

export async function createVendorAssessmentCorrectiveActionAction(tenantSlug: string, assessmentId: string, findingId: string, _prevState: AssessmentActionState, formData: FormData) {
  const description = String(formData.get("description") ?? "").trim();
  const dueDate = String(formData.get("dueDate") ?? "").trim() || null;
  return runAction(tenantSlug, assessmentId, createVendorAssessmentCorrectiveAction as Mutation, { findingId, description, dueDate }, "create this corrective action");
}

export async function updateVendorAssessmentCorrectiveActionStatusAction(
  tenantSlug: string,
  assessmentId: string,
  correctiveActionId: string,
  expectedVersion: number,
  _prevState: AssessmentActionState,
  formData: FormData,
) {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const newStatus = String(formData.get("newStatus") ?? "") as VendorAssessmentCorrectiveActionStatus;
  const resolutionNotes = String(formData.get("resolutionNotes") ?? "").trim() || null;
  const evidenceFile = formData.get("evidenceFile");

  const supabase = await createSupabaseServerClient();
  let resolvedEvidenceFileId: string | null = null;
  if (evidenceFile instanceof File && evidenceFile.size > 0) {
    try {
      const uploaded = await initiateFileUpload(toDocumentClient(supabase), {
        tenantId: access.tenant.id,
        documentTypeCode: "vendor_assessment_evidence",
        recordType: "vendor_assessment",
        recordId: assessmentId,
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
      resolvedEvidenceFileId = uploaded.id;
    } catch (error) {
      if (error instanceof DocumentMutationError) return { error: `Could not attach this resolution evidence: ${error.message}` };
      throw error;
    }
  }

  try {
    await updateVendorAssessmentCorrectiveActionStatus(supabase, {
      correctiveActionId,
      expectedVersion,
      newStatus,
      resolutionNotes,
      resolvedEvidenceFileId,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof VendorAssessmentMutationError) return { error: `Could not update this corrective action: ${error.message}` };
    throw error;
  }

  revalidatePath(detailPath(tenantSlug, assessmentId));
  return OK;
}
