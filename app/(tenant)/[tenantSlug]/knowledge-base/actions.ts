"use server";

/**
 * Knowledge Base Server Actions (HRT-289, CG-S12-HRT-017). Mirrors
 * app/(tenant)/[tenantSlug]/tickets/actions.ts's own shape exactly: resolve
 * portal access (the same ticketing guard -- KB authoring gates on TKT:Edit
 * at the RPC layer, so a ticketing-workspace member is the right audience),
 * call the typed mutation wrapper, translate a known mutation error into a
 * plain-language message, revalidate the affected path(s).
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../lib/supabase/server.ts";
import { resolveTicketAccessForRequest } from "../../../../lib/portal/resolve-ticket-access.server.ts";
import {
  createKbArticle,
  createKbArticleVersion,
  updateKbArticleVersion,
  setKbArticleExpiry,
  submitKbArticleVersionForReview,
  reviewKbArticleVersion,
  publishKbArticleVersion,
  archiveKbArticleVersion,
  linkTicketKnowledgeArticle,
  unlinkTicketKnowledgeArticle,
  KbMutationError,
} from "../../../../server/mutations/knowledge-base.ts";
import type { KbReviewDecision, KbLinkVisibility } from "../../../../server/contracts/knowledge-base/knowledge-base.ts";

export interface KbActionState {
  readonly error: string | null;
}

const OK: KbActionState = { error: null };
const NO_ACCESS: KbActionState = { error: "You don't have access to this organization's ticketing workspace." };

async function requireAccess(tenantSlug: string) {
  const access = await resolveTicketAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return null;
  return access;
}

function listPath(tenantSlug: string): string {
  return `/${tenantSlug}/knowledge-base`;
}

function articlePath(tenantSlug: string, articleId: string): string {
  return `/${tenantSlug}/knowledge-base/${articleId}`;
}

function errorMessage(prefix: string, error: unknown): KbActionState {
  if (error instanceof KbMutationError) return { error: `${prefix}: ${error.message}` };
  throw error;
}

function readTags(formData: FormData): string[] {
  const raw = String(formData.get("tags") ?? "").trim();
  if (!raw) return [];
  return raw
    .split(",")
    .map((t) => t.trim())
    .filter((t) => t.length > 0);
}

export async function createKbArticleAction(tenantSlug: string, _prevState: KbActionState, formData: FormData): Promise<KbActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const code = String(formData.get("code") ?? "").trim();
  if (!code) return { error: "A code (lowercase-with-dashes) is required." };

  const supabase = await createSupabaseServerClient();
  try {
    const article = await createKbArticle(supabase, { tenantId: access.tenant.id, code, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
    revalidatePath(listPath(tenantSlug));
    const created = article as { id?: string };
    if (created.id) revalidatePath(articlePath(tenantSlug, created.id));
  } catch (error) {
    return errorMessage("Could not create this article", error);
  }
  return OK;
}

export async function createKbArticleVersionAction(tenantSlug: string, articleId: string, _prevState: KbActionState, formData: FormData): Promise<KbActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const title = String(formData.get("title") ?? "").trim();
  const summary = String(formData.get("summary") ?? "").trim() || null;
  const body = String(formData.get("body") ?? "").trim();
  const tags = readTags(formData);
  const audienceInternal = formData.get("audienceInternal") === "on";
  const audienceCustomer = formData.get("audienceCustomer") === "on";
  const audienceHelpdesk = formData.get("audienceHelpdesk") === "on";
  if (!title || !body) return { error: "Title and body are both required." };

  const supabase = await createSupabaseServerClient();
  try {
    await createKbArticleVersion(supabase, { articleId, title, summary, body, tags, audienceInternal, audienceCustomer, audienceHelpdesk, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    return errorMessage("Could not create this article version", error);
  }
  revalidatePath(articlePath(tenantSlug, articleId));
  return OK;
}

export async function updateKbArticleVersionAction(tenantSlug: string, articleId: string, versionId: string, expectedVersion: number, _prevState: KbActionState, formData: FormData): Promise<KbActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const title = String(formData.get("title") ?? "").trim();
  const summary = String(formData.get("summary") ?? "").trim() || null;
  const body = String(formData.get("body") ?? "").trim();
  const tags = readTags(formData);
  const audienceInternal = formData.get("audienceInternal") === "on";
  const audienceCustomer = formData.get("audienceCustomer") === "on";
  const audienceHelpdesk = formData.get("audienceHelpdesk") === "on";
  if (!title || !body) return { error: "Title and body are both required." };

  const supabase = await createSupabaseServerClient();
  try {
    await updateKbArticleVersion(supabase, { versionId, expectedVersion, title, summary, body, tags, audienceInternal, audienceCustomer, audienceHelpdesk, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    return errorMessage("Could not update this draft", error);
  }
  revalidatePath(articlePath(tenantSlug, articleId));
  return OK;
}

export async function setKbArticleExpiryAction(tenantSlug: string, articleId: string, versionId: string, expectedVersion: number, _prevState: KbActionState, formData: FormData): Promise<KbActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const expiresAtRaw = String(formData.get("expiresAt") ?? "").trim();
  const expiresAt = expiresAtRaw ? new Date(expiresAtRaw).toISOString() : null;

  const supabase = await createSupabaseServerClient();
  try {
    await setKbArticleExpiry(supabase, { versionId, expectedVersion, expiresAt, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    return errorMessage("Could not set expiry", error);
  }
  revalidatePath(articlePath(tenantSlug, articleId));
  return OK;
}

export async function submitKbArticleVersionForReviewAction(tenantSlug: string, articleId: string, versionId: string, expectedVersion: number, _prevState: KbActionState, formData: FormData): Promise<KbActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const reviewerAuthUserId = String(formData.get("reviewerAuthUserId") ?? "").trim();
  if (!reviewerAuthUserId) return { error: "A reviewer (auth user id) is required." };

  const supabase = await createSupabaseServerClient();
  try {
    await submitKbArticleVersionForReview(supabase, { versionId, expectedVersion, reviewerAuthUserId, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    return errorMessage("Could not submit this version for review", error);
  }
  revalidatePath(articlePath(tenantSlug, articleId));
  return OK;
}

export async function reviewKbArticleVersionAction(tenantSlug: string, articleId: string, versionId: string, expectedVersion: number, decision: KbReviewDecision, _prevState: KbActionState, formData: FormData): Promise<KbActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const notes = String(formData.get("notes") ?? "").trim() || null;

  const supabase = await createSupabaseServerClient();
  try {
    await reviewKbArticleVersion(supabase, { versionId, expectedVersion, decision, notes, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    return errorMessage("Could not record this review decision", error);
  }
  revalidatePath(articlePath(tenantSlug, articleId));
  return OK;
}

export async function publishKbArticleVersionAction(tenantSlug: string, articleId: string, versionId: string, expectedVersion: number, _prevState: KbActionState, _formData: FormData): Promise<KbActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const supabase = await createSupabaseServerClient();
  try {
    await publishKbArticleVersion(supabase, { versionId, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    return errorMessage("Could not publish this version", error);
  }
  revalidatePath(articlePath(tenantSlug, articleId));
  revalidatePath(listPath(tenantSlug));
  return OK;
}

export async function archiveKbArticleVersionAction(tenantSlug: string, articleId: string, versionId: string, expectedVersion: number, _prevState: KbActionState, formData: FormData): Promise<KbActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const reason = String(formData.get("reason") ?? "").trim();
  if (!reason) return { error: "A reason is required to archive an article version." };

  const supabase = await createSupabaseServerClient();
  try {
    await archiveKbArticleVersion(supabase, { versionId, expectedVersion, reason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    return errorMessage("Could not archive this version", error);
  }
  revalidatePath(articlePath(tenantSlug, articleId));
  revalidatePath(listPath(tenantSlug));
  return OK;
}

// --- Ticket-article linking (called from the tickets detail page too). ---

export async function linkTicketKnowledgeArticleAction(tenantSlug: string, ticketId: string, _prevState: KbActionState, formData: FormData): Promise<KbActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const articleId = String(formData.get("articleId") ?? "").trim();
  const visibility = String(formData.get("visibility") ?? "") as KbLinkVisibility;
  const note = String(formData.get("note") ?? "").trim() || null;
  if (!articleId || !visibility) return { error: "An article id and visibility are both required." };

  const supabase = await createSupabaseServerClient();
  try {
    await linkTicketKnowledgeArticle(supabase, { ticketId, articleId, visibility, note, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    return errorMessage("Could not link this article", error);
  }
  revalidatePath(`/${tenantSlug}/tickets/${ticketId}`);
  return OK;
}

export async function unlinkTicketKnowledgeArticleAction(tenantSlug: string, ticketId: string, linkId: string, expectedVersion: number, _prevState: KbActionState, _formData: FormData): Promise<KbActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const supabase = await createSupabaseServerClient();
  try {
    await unlinkTicketKnowledgeArticle(supabase, { linkId, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    return errorMessage("Could not unlink this article", error);
  }
  revalidatePath(`/${tenantSlug}/tickets/${ticketId}`);
  return OK;
}
