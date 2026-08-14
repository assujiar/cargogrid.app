/**
 * Knowledge Base mutation primitives (HRT-289, CG-S12-HRT-017). Thin, typed
 * wrappers around every write RPC in
 * supabase/migrations/20260731130000_create_ticket_knowledge_base.sql.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  CreateKbArticleInputSchema,
  CreateKbArticleVersionInputSchema,
  UpdateKbArticleVersionInputSchema,
  SetKbArticleExpiryInputSchema,
  SubmitKbArticleVersionForReviewInputSchema,
  ReviewKbArticleVersionInputSchema,
  PublishKbArticleVersionInputSchema,
  ArchiveKbArticleVersionInputSchema,
  ExpireKbArticleVersionsBatchInputSchema,
  LinkTicketKnowledgeArticleInputSchema,
  UnlinkTicketKnowledgeArticleInputSchema,
  type CreateKbArticleInput,
  type CreateKbArticleVersionInput,
  type UpdateKbArticleVersionInput,
  type SetKbArticleExpiryInput,
  type SubmitKbArticleVersionForReviewInput,
  type ReviewKbArticleVersionInput,
  type PublishKbArticleVersionInput,
  type ArchiveKbArticleVersionInput,
  type ExpireKbArticleVersionsBatchInput,
  type LinkTicketKnowledgeArticleInput,
  type UnlinkTicketKnowledgeArticleInput,
} from "../contracts/knowledge-base/knowledge-base.ts";

export type KbMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const KB_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "insufficient_privilege",
  "code_required",
  "title_required",
  "body_required",
  "reason_required",
  "reviewer_required",
  "self_review_forbidden",
  "reviewer_not_eligible",
  "invalid_decision",
  "invalid_visibility",
  "invalid_state",
  "audience_required",
  "kb_article_not_found",
  "kb_article_version_not_found",
  "kb_article_not_published",
  "kb_article_already_linked",
  "kb_ticket_article_link_not_found",
  "article_not_audience_permitted",
  "invalid_period",
  "stale_version",
  "ticket_not_found",
] as const;

export type KnownKbMutationErrorCode = (typeof KB_KNOWN_MUTATION_ERROR_CODES)[number];
export type KbMutationErrorCode = KnownKbMutationErrorCode | "mutation_failed";

export class KbMutationError extends Error {
  readonly code: KbMutationErrorCode;

  constructor(code: KbMutationErrorCode, message: string) {
    super(message);
    this.name = "KbMutationError";
    this.code = code;
  }
}

function classifyError(message: string): KbMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  if (prefix && (KB_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix)) {
    return prefix as KnownKbMutationErrorCode;
  }
  return "mutation_failed";
}

async function callRpc<T>(client: KbMutationRpcClient, fn: string, args: Record<string, unknown>): Promise<T> {
  const { data, error } = await client.rpc(fn, args);
  if (error) throw new KbMutationError(classifyError(error.message), error.message);
  return data as T;
}

export async function createKbArticle(client: KbMutationRpcClient, input: CreateKbArticleInput) {
  const v = CreateKbArticleInputSchema.parse(input);
  return callRpc(client, "create_kb_article", {
    p_tenant_id: v.tenantId,
    p_code: v.code,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}

export async function createKbArticleVersion(client: KbMutationRpcClient, input: CreateKbArticleVersionInput) {
  const v = CreateKbArticleVersionInputSchema.parse(input);
  return callRpc(client, "create_kb_article_version", {
    p_article_id: v.articleId,
    p_title: v.title,
    p_summary: v.summary,
    p_body: v.body,
    p_tags: v.tags,
    p_audience_internal: v.audienceInternal,
    p_audience_customer: v.audienceCustomer,
    p_audience_helpdesk: v.audienceHelpdesk,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}

export async function updateKbArticleVersion(client: KbMutationRpcClient, input: UpdateKbArticleVersionInput) {
  const v = UpdateKbArticleVersionInputSchema.parse(input);
  return callRpc(client, "update_kb_article_version", {
    p_version_id: v.versionId,
    p_expected_version: v.expectedVersion,
    p_title: v.title,
    p_summary: v.summary,
    p_body: v.body,
    p_tags: v.tags,
    p_audience_internal: v.audienceInternal,
    p_audience_customer: v.audienceCustomer,
    p_audience_helpdesk: v.audienceHelpdesk,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}

export async function setKbArticleExpiry(client: KbMutationRpcClient, input: SetKbArticleExpiryInput) {
  const v = SetKbArticleExpiryInputSchema.parse(input);
  return callRpc(client, "set_kb_article_expiry", {
    p_version_id: v.versionId,
    p_expected_version: v.expectedVersion,
    p_expires_at: v.expiresAt,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}

export async function submitKbArticleVersionForReview(client: KbMutationRpcClient, input: SubmitKbArticleVersionForReviewInput) {
  const v = SubmitKbArticleVersionForReviewInputSchema.parse(input);
  return callRpc(client, "submit_kb_article_version_for_review", {
    p_version_id: v.versionId,
    p_expected_version: v.expectedVersion,
    p_reviewer_auth_user_id: v.reviewerAuthUserId,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}

export async function reviewKbArticleVersion(client: KbMutationRpcClient, input: ReviewKbArticleVersionInput) {
  const v = ReviewKbArticleVersionInputSchema.parse(input);
  return callRpc(client, "review_kb_article_version", {
    p_version_id: v.versionId,
    p_expected_version: v.expectedVersion,
    p_decision: v.decision,
    p_notes: v.notes,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}

export async function publishKbArticleVersion(client: KbMutationRpcClient, input: PublishKbArticleVersionInput) {
  const v = PublishKbArticleVersionInputSchema.parse(input);
  return callRpc(client, "publish_kb_article_version", {
    p_version_id: v.versionId,
    p_expected_version: v.expectedVersion,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}

export async function archiveKbArticleVersion(client: KbMutationRpcClient, input: ArchiveKbArticleVersionInput) {
  const v = ArchiveKbArticleVersionInputSchema.parse(input);
  return callRpc(client, "archive_kb_article_version", {
    p_version_id: v.versionId,
    p_expected_version: v.expectedVersion,
    p_reason: v.reason,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}

export async function expireKbArticleVersionsBatch(client: KbMutationRpcClient, input: ExpireKbArticleVersionsBatchInput) {
  const v = ExpireKbArticleVersionsBatchInputSchema.parse(input);
  return callRpc(client, "expire_kb_article_versions_batch", {
    p_tenant_id: v.tenantId,
    p_as_of: v.asOf,
    p_period_label: v.periodLabel,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}

export async function linkTicketKnowledgeArticle(client: KbMutationRpcClient, input: LinkTicketKnowledgeArticleInput) {
  const v = LinkTicketKnowledgeArticleInputSchema.parse(input);
  return callRpc(client, "link_ticket_knowledge_article", {
    p_ticket_id: v.ticketId,
    p_article_id: v.articleId,
    p_visibility: v.visibility,
    p_note: v.note,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}

export async function unlinkTicketKnowledgeArticle(client: KbMutationRpcClient, input: UnlinkTicketKnowledgeArticleInput) {
  const v = UnlinkTicketKnowledgeArticleInputSchema.parse(input);
  return callRpc(client, "unlink_ticket_knowledge_article", {
    p_link_id: v.linkId,
    p_expected_version: v.expectedVersion,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}
