/**
 * Knowledge Base read queries (HRT-289, CG-S12-HRT-017). Thin, typed
 * wrappers around every read RPC in
 * supabase/migrations/20260731130000_create_ticket_knowledge_base.sql.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseKbArticleRow,
  parseKbArticleVersionSummaryRow,
  parseKbArticleVersionRow,
  parseKbArticleSearchRow,
  parseKbArticleDetailRow,
  parseKbTicketArticleLinkRow,
  parseKbTicketArticleLinkForRequesterRow,
  type KbArticleRow,
  type KbArticleVersionSummaryRow,
  type KbArticleVersionRow,
  type KbArticleSearchRow,
  type KbArticleDetailRow,
  type KbTicketArticleLinkRow,
  type KbTicketArticleLinkForRequesterRow,
} from "../contracts/knowledge-base/knowledge-base.ts";

export type KbQueryClient = Pick<SupabaseClient, "rpc">;

export class KbQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "KbQueryError";
  }
}

function rows(data: unknown): Record<string, unknown>[] {
  return (data as Record<string, unknown>[] | null) ?? [];
}

export async function listKbArticles(client: KbQueryClient, tenantId: string, actorAuthUserId: string): Promise<KbArticleRow[]> {
  const { data, error } = await client.rpc("list_kb_articles", { p_tenant_id: tenantId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new KbQueryError(error.message);
  return rows(data).map(parseKbArticleRow);
}

export async function listKbArticleVersions(client: KbQueryClient, articleId: string, actorAuthUserId: string): Promise<KbArticleVersionSummaryRow[]> {
  const { data, error } = await client.rpc("list_kb_article_versions", { p_article_id: articleId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new KbQueryError(error.message);
  return rows(data).map(parseKbArticleVersionSummaryRow);
}

export async function getKbArticleForStaff(client: KbQueryClient, articleId: string, actorAuthUserId: string): Promise<KbArticleVersionRow | null> {
  const { data, error } = await client.rpc("get_kb_article_for_staff", { p_article_id: articleId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new KbQueryError(error.message);
  return data ? parseKbArticleVersionRow(data as Record<string, unknown>) : null;
}

// Fetches a single version's FULL row (including body) -- the authoring-UI
// complement to listKbArticleVersions's own summary-only projection.
// Visibility: published, or the caller is the author/assigned reviewer, or
// the caller holds TKT:Edit (byte-for-byte the raw-table RLS predicate).
export async function getKbArticleVersion(client: KbQueryClient, versionId: string, actorAuthUserId: string): Promise<KbArticleVersionRow | null> {
  const { data, error } = await client.rpc("get_kb_article_version", { p_version_id: versionId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new KbQueryError(error.message);
  return data ? parseKbArticleVersionRow(data as Record<string, unknown>) : null;
}

export interface SearchKnowledgeArticlesOptions {
  readonly query?: string | null;
  readonly limit?: number;
  readonly afterId?: string | null;
}

// Internal/staff search -- sees every PUBLISHED version regardless of
// audience (never draft/in_review/approved/archived). Never call this for a
// customer or helpdesk-channel caller -- use the dedicated, audience-safe
// functions below instead (the security-critical distinction this
// capability exists to prove).
export async function searchKnowledgeArticles(client: KbQueryClient, tenantId: string, actorAuthUserId: string, options?: SearchKnowledgeArticlesOptions): Promise<KbArticleSearchRow[]> {
  const { data, error } = await client.rpc("search_knowledge_articles", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_query: options?.query ?? null,
    p_limit: options?.limit ?? 20,
    p_after_id: options?.afterId ?? null,
  });
  if (error) throw new KbQueryError(error.message);
  return rows(data).map(parseKbArticleSearchRow);
}

// Customer-portal-facing search -- status=published AND audience_customer=
// true AND not expired, structurally identical to the raw-table RLS
// predicate (defense in depth). Requires a real, owned customerAccountId.
export async function searchCustomerKnowledgeArticles(client: KbQueryClient, tenantId: string, actorAuthUserId: string, customerAccountId: string, options?: SearchKnowledgeArticlesOptions): Promise<KbArticleSearchRow[]> {
  const { data, error } = await client.rpc("search_customer_knowledge_articles", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_account_id: customerAccountId,
    p_query: options?.query ?? null,
    p_limit: options?.limit ?? 20,
    p_after_id: options?.afterId ?? null,
  });
  if (error) throw new KbQueryError(error.message);
  return rows(data).map(parseKbArticleSearchRow);
}

// Tenant helpdesk-channel or CargoGrid-support-facing search --
// status=published AND audience_helpdesk=true AND not expired.
export async function searchHelpdeskKnowledgeArticles(client: KbQueryClient, tenantId: string, actorAuthUserId: string, options?: SearchKnowledgeArticlesOptions): Promise<KbArticleSearchRow[]> {
  const { data, error } = await client.rpc("search_helpdesk_knowledge_articles", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_query: options?.query ?? null,
    p_limit: options?.limit ?? 20,
    p_after_id: options?.afterId ?? null,
  });
  if (error) throw new KbQueryError(error.message);
  return rows(data).map(parseKbArticleSearchRow);
}

export async function getKbArticleForCustomer(client: KbQueryClient, articleId: string, actorAuthUserId: string, tenantId: string, customerAccountId: string): Promise<KbArticleDetailRow | null> {
  const { data, error } = await client.rpc("get_kb_article_for_customer", {
    p_article_id: articleId,
    p_actor_auth_user_id: actorAuthUserId,
    p_tenant_id: tenantId,
    p_account_id: customerAccountId,
  });
  if (error) throw new KbQueryError(error.message);
  const row = rows(data)[0];
  return row ? parseKbArticleDetailRow(row) : null;
}

export async function getKbArticleForHelpdesk(client: KbQueryClient, articleId: string, actorAuthUserId: string, tenantId: string): Promise<KbArticleDetailRow | null> {
  const { data, error } = await client.rpc("get_kb_article_for_helpdesk", {
    p_article_id: articleId,
    p_actor_auth_user_id: actorAuthUserId,
    p_tenant_id: tenantId,
  });
  if (error) throw new KbQueryError(error.message);
  const row = rows(data)[0];
  return row ? parseKbArticleDetailRow(row) : null;
}

export async function listTicketKnowledgeArticleLinks(client: KbQueryClient, ticketId: string, actorAuthUserId: string): Promise<KbTicketArticleLinkRow[]> {
  const { data, error } = await client.rpc("list_ticket_knowledge_article_links", { p_ticket_id: ticketId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new KbQueryError(error.message);
  return rows(data).map(parseKbTicketArticleLinkRow);
}

export async function listTicketKnowledgeArticleLinksForRequester(client: KbQueryClient, ticketId: string, actorAuthUserId: string): Promise<KbTicketArticleLinkForRequesterRow[]> {
  const { data, error } = await client.rpc("list_ticket_knowledge_article_links_for_requester", { p_ticket_id: ticketId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new KbQueryError(error.message);
  return rows(data).map(parseKbTicketArticleLinkForRequesterRow);
}
