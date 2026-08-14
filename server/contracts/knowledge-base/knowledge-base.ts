/**
 * Knowledge Base contract (HRT-289, CG-S12-HRT-017). Mirrors
 * supabase/migrations/20260731130000_create_ticket_knowledge_base.sql's
 * tables/RPCs. A standalone sibling module rather than an extension of
 * server/contracts/ticketing/ticketing.ts -- documented design decision: an
 * article has no REQUIRED ticket relationship (ticket linking is one
 * optional feature of the capability, not its own identity), unlike SLA
 * where every clock is 1:1 with a ticket. Follows the exact directory
 * convention every prior HRT checkpoint established: Zod schemas here,
 * list/read projections in server/queries/knowledge-base.ts, RPC-calling
 * mutation wrappers with an enumerated error-code type in
 * server/mutations/knowledge-base.ts.
 */

import { z } from "zod";

export const KB_ARTICLE_STATUSES = ["draft", "in_review", "approved", "published", "archived"] as const;
export const KbArticleStatusSchema = z.enum(KB_ARTICLE_STATUSES);
export type KbArticleStatus = z.infer<typeof KbArticleStatusSchema>;

export const KB_REVIEW_DECISIONS = ["approved", "changes_requested"] as const;
export const KbReviewDecisionSchema = z.enum(KB_REVIEW_DECISIONS);
export type KbReviewDecision = z.infer<typeof KbReviewDecisionSchema>;

export const KB_LINK_VISIBILITIES = ["public", "internal"] as const;
export const KbLinkVisibilitySchema = z.enum(KB_LINK_VISIBILITIES);
export type KbLinkVisibility = z.infer<typeof KbLinkVisibilitySchema>;

// --- Core rows ---

export const KbArticleRowSchema = z.object({
  id: z.string().uuid(),
  code: z.string(),
  currentStatus: KbArticleStatusSchema.nullable(),
  currentVersionId: z.string().uuid().nullable(),
  currentVersionNumber: z.number().int().positive().nullable(),
  title: z.string().nullable(),
});
export type KbArticleRow = z.infer<typeof KbArticleRowSchema>;

export function parseKbArticleRow(row: Record<string, unknown>): KbArticleRow {
  return KbArticleRowSchema.parse({
    id: row.id,
    code: row.code,
    currentStatus: row.current_status ?? null,
    currentVersionId: row.current_version_id ?? null,
    currentVersionNumber: row.current_version_number ?? null,
    title: row.title ?? null,
  });
}

export const KbArticleVersionSummaryRowSchema = z.object({
  id: z.string().uuid(),
  versionNumber: z.number().int().positive(),
  status: KbArticleStatusSchema,
  title: z.string(),
  audienceInternal: z.boolean(),
  audienceCustomer: z.boolean(),
  audienceHelpdesk: z.boolean(),
  reviewerLabel: z.string().nullable(),
  reviewDecision: KbReviewDecisionSchema.nullable(),
  publishedAt: z.string().nullable(),
  expiresAt: z.string().nullable(),
  recordVersion: z.number().int().positive(),
});
export type KbArticleVersionSummaryRow = z.infer<typeof KbArticleVersionSummaryRowSchema>;

export function parseKbArticleVersionSummaryRow(row: Record<string, unknown>): KbArticleVersionSummaryRow {
  return KbArticleVersionSummaryRowSchema.parse({
    id: row.id,
    versionNumber: row.version_number,
    status: row.status,
    title: row.title,
    audienceInternal: row.audience_internal,
    audienceCustomer: row.audience_customer,
    audienceHelpdesk: row.audience_helpdesk,
    reviewerLabel: row.reviewer_label ?? null,
    reviewDecision: row.review_decision ?? null,
    publishedAt: row.published_at ?? null,
    expiresAt: row.expires_at ?? null,
    recordVersion: row.record_version,
  });
}

// The full authoring-side version row (returned by create/update/submit/
// review/publish/archive) -- includes body, unlike the search/list
// projections below, which are deliberately narrower.
export const KbArticleVersionRowSchema = z.object({
  id: z.string().uuid(),
  articleId: z.string().uuid(),
  versionNumber: z.number().int().positive(),
  status: KbArticleStatusSchema,
  title: z.string(),
  summary: z.string().nullable(),
  body: z.string(),
  tags: z.array(z.string()),
  audienceInternal: z.boolean(),
  audienceCustomer: z.boolean(),
  audienceHelpdesk: z.boolean(),
  reviewerLabel: z.string().nullable(),
  reviewDecision: KbReviewDecisionSchema.nullable(),
  reviewNotes: z.string().nullable(),
  publishedAt: z.string().nullable(),
  expiresAt: z.string().nullable(),
  archivedReason: z.string().nullable(),
  recordVersion: z.number().int().positive(),
});
export type KbArticleVersionRow = z.infer<typeof KbArticleVersionRowSchema>;

export function parseKbArticleVersionRow(row: Record<string, unknown>): KbArticleVersionRow {
  return KbArticleVersionRowSchema.parse({
    id: row.id,
    articleId: row.article_id,
    versionNumber: row.version_number,
    status: row.status,
    title: row.title,
    summary: row.summary ?? null,
    body: row.body,
    tags: row.tags ?? [],
    audienceInternal: row.audience_internal,
    audienceCustomer: row.audience_customer,
    audienceHelpdesk: row.audience_helpdesk,
    reviewerLabel: row.reviewer_label ?? null,
    reviewDecision: row.review_decision ?? null,
    reviewNotes: row.review_notes ?? null,
    publishedAt: row.published_at ?? null,
    expiresAt: row.expires_at ?? null,
    archivedReason: row.archived_reason ?? null,
    recordVersion: row.record_version,
  });
}

// Search-result / audience-safe projection -- no reviewer/review_notes/
// archived_reason, matching every search/get RPC's own deliberately narrow
// column list (security impact: audience-safe search is the security-
// critical half of this sub-capability).
export const KbArticleSearchRowSchema = z.object({
  id: z.string().uuid(),
  articleId: z.string().uuid(),
  versionNumber: z.number().int().positive(),
  title: z.string(),
  summary: z.string().nullable(),
  tags: z.array(z.string()),
  publishedAt: z.string().nullable(),
});
export type KbArticleSearchRow = z.infer<typeof KbArticleSearchRowSchema>;

export function parseKbArticleSearchRow(row: Record<string, unknown>): KbArticleSearchRow {
  return KbArticleSearchRowSchema.parse({
    id: row.id,
    articleId: row.article_id,
    versionNumber: row.version_number,
    title: row.title,
    summary: row.summary ?? null,
    tags: row.tags ?? [],
    publishedAt: row.published_at ?? null,
  });
}

export const KbArticleDetailRowSchema = KbArticleSearchRowSchema.extend({
  body: z.string(),
});
export type KbArticleDetailRow = z.infer<typeof KbArticleDetailRowSchema>;

export function parseKbArticleDetailRow(row: Record<string, unknown>): KbArticleDetailRow {
  return KbArticleDetailRowSchema.parse({
    id: row.id,
    articleId: row.article_id,
    versionNumber: row.version_number,
    title: row.title,
    summary: row.summary ?? null,
    tags: row.tags ?? [],
    publishedAt: row.published_at ?? null,
    body: row.body,
  });
}

export const KbTicketArticleLinkRowSchema = z.object({
  id: z.string().uuid(),
  articleId: z.string().uuid(),
  articleVersionId: z.string().uuid(),
  articleTitle: z.string(),
  visibility: KbLinkVisibilitySchema,
  note: z.string().nullable(),
  linkedBy: z.string().nullable(),
  linkedAt: z.string(),
  recordVersion: z.number().int().positive(),
});
export type KbTicketArticleLinkRow = z.infer<typeof KbTicketArticleLinkRowSchema>;

export function parseKbTicketArticleLinkRow(row: Record<string, unknown>): KbTicketArticleLinkRow {
  return KbTicketArticleLinkRowSchema.parse({
    id: row.id,
    articleId: row.article_id,
    articleVersionId: row.article_version_id,
    articleTitle: row.article_title,
    visibility: row.visibility,
    note: row.note ?? null,
    linkedBy: row.linked_by ?? null,
    linkedAt: row.linked_at,
    recordVersion: row.record_version,
  });
}

// Requester-safe link projection -- public-visibility links only, no note
// (staff-authored context), matching app.list_ticket_knowledge_article_
// links_for_requester's own deliberately narrow column list.
export const KbTicketArticleLinkForRequesterRowSchema = z.object({
  id: z.string().uuid(),
  articleId: z.string().uuid(),
  articleVersionId: z.string().uuid(),
  articleTitle: z.string(),
  articleSummary: z.string().nullable(),
  linkedAt: z.string(),
});
export type KbTicketArticleLinkForRequesterRow = z.infer<typeof KbTicketArticleLinkForRequesterRowSchema>;

export function parseKbTicketArticleLinkForRequesterRow(row: Record<string, unknown>): KbTicketArticleLinkForRequesterRow {
  return KbTicketArticleLinkForRequesterRowSchema.parse({
    id: row.id,
    articleId: row.article_id,
    articleVersionId: row.article_version_id,
    articleTitle: row.article_title,
    articleSummary: row.article_summary ?? null,
    linkedAt: row.linked_at,
  });
}

// --- Mutation inputs ---

export const CreateKbArticleInputSchema = z.object({
  tenantId: z.string().uuid(),
  code: z.string().regex(/^[a-z0-9-]{2,80}$/),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type CreateKbArticleInput = z.infer<typeof CreateKbArticleInputSchema>;

export const CreateKbArticleVersionInputSchema = z.object({
  articleId: z.string().uuid(),
  title: z.string().min(1),
  summary: z.string().nullable(),
  body: z.string().min(1),
  tags: z.array(z.string()),
  audienceInternal: z.boolean(),
  audienceCustomer: z.boolean(),
  audienceHelpdesk: z.boolean(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type CreateKbArticleVersionInput = z.infer<typeof CreateKbArticleVersionInputSchema>;

export const UpdateKbArticleVersionInputSchema = CreateKbArticleVersionInputSchema.omit({ articleId: true }).extend({
  versionId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
});
export type UpdateKbArticleVersionInput = z.infer<typeof UpdateKbArticleVersionInputSchema>;

export const SetKbArticleExpiryInputSchema = z.object({
  versionId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  expiresAt: z.string().nullable(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type SetKbArticleExpiryInput = z.infer<typeof SetKbArticleExpiryInputSchema>;

export const SubmitKbArticleVersionForReviewInputSchema = z.object({
  versionId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  reviewerAuthUserId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type SubmitKbArticleVersionForReviewInput = z.infer<typeof SubmitKbArticleVersionForReviewInputSchema>;

export const ReviewKbArticleVersionInputSchema = z.object({
  versionId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  decision: KbReviewDecisionSchema,
  notes: z.string().nullable(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type ReviewKbArticleVersionInput = z.infer<typeof ReviewKbArticleVersionInputSchema>;

export const PublishKbArticleVersionInputSchema = z.object({
  versionId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type PublishKbArticleVersionInput = z.infer<typeof PublishKbArticleVersionInputSchema>;

export const ArchiveKbArticleVersionInputSchema = z.object({
  versionId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  reason: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type ArchiveKbArticleVersionInput = z.infer<typeof ArchiveKbArticleVersionInputSchema>;

export const ExpireKbArticleVersionsBatchInputSchema = z.object({
  tenantId: z.string().uuid(),
  asOf: z.string().nullable(),
  periodLabel: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type ExpireKbArticleVersionsBatchInput = z.infer<typeof ExpireKbArticleVersionsBatchInputSchema>;

export const LinkTicketKnowledgeArticleInputSchema = z.object({
  ticketId: z.string().uuid(),
  articleId: z.string().uuid(),
  visibility: KbLinkVisibilitySchema,
  note: z.string().nullable(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type LinkTicketKnowledgeArticleInput = z.infer<typeof LinkTicketKnowledgeArticleInputSchema>;

export const UnlinkTicketKnowledgeArticleInputSchema = z.object({
  linkId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type UnlinkTicketKnowledgeArticleInput = z.infer<typeof UnlinkTicketKnowledgeArticleInputSchema>;
