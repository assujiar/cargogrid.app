import { notFound } from "next/navigation";
import { resolveTicketAccessForRequest } from "../../../../../lib/portal/resolve-ticket-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { listKbArticleVersions, getKbArticleVersion, KbQueryError } from "../../../../../server/queries/knowledge-base.ts";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";
import { KbArticlePanel } from "./kb-article-panel.tsx";
import {
  createKbArticleVersionAction,
  updateKbArticleVersionAction,
  setKbArticleExpiryAction,
  submitKbArticleVersionForReviewAction,
  reviewKbArticleVersionAction,
  publishKbArticleVersionAction,
  archiveKbArticleVersionAction,
} from "../actions.ts";

/**
 * Knowledge article version history/authoring view (HRT-289,
 * CG-S12-HRT-017). Renders app.list_kb_article_versions' own visibility
 * scoping directly -- a non-author/non-reviewer/non-TKT:Edit viewer simply
 * never receives a still-draft/in_review/approved/archived row here (the
 * query, not this component, is what makes that structurally true, mirrors
 * the internal-note discipline the ticket detail page already documents).
 */
export default async function KbArticlePage({ params }: { params: Promise<{ tenantSlug: string; articleId: string }> }) {
  const { tenantSlug, articleId } = await params;
  const access = await resolveTicketAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();
  let loadFailed = false;
  let versions: Awaited<ReturnType<typeof listKbArticleVersions>> = [];
  const fullVersionById: Record<string, Awaited<ReturnType<typeof getKbArticleVersion>>> = {};

  try {
    versions = await listKbArticleVersions(supabase, articleId, access.authUserId);
    const fullEntries = await Promise.all(versions.map(async (v) => [v.id, await getKbArticleVersion(supabase, v.id, access.authUserId)] as const));
    for (const [id, full] of fullEntries) fullVersionById[id] = full;
  } catch (error) {
    if (!(error instanceof KbQueryError)) throw error;
    loadFailed = true;
  }

  if (loadFailed) {
    return <ErrorState description="Something went wrong loading this article. Please try again." />;
  }
  // Zero versions here means EITHER the article genuinely has no version
  // yet, OR this viewer is not entitled to see any -- both render the same
  // "start a version" surface; app.create_kb_article_version's own TKT:Edit
  // gate (not this page) is the real check.

  return (
    <KbArticlePanel
      versions={versions}
      fullVersionById={fullVersionById}
      createVersionAction={createKbArticleVersionAction.bind(null, tenantSlug, articleId)}
      updateVersionAction={(versionId: string, expectedVersion: number) => updateKbArticleVersionAction.bind(null, tenantSlug, articleId, versionId, expectedVersion)}
      setExpiryAction={(versionId: string, expectedVersion: number) => setKbArticleExpiryAction.bind(null, tenantSlug, articleId, versionId, expectedVersion)}
      submitForReviewAction={(versionId: string, expectedVersion: number) => submitKbArticleVersionForReviewAction.bind(null, tenantSlug, articleId, versionId, expectedVersion)}
      reviewAction={(versionId: string, expectedVersion: number, decision) => reviewKbArticleVersionAction.bind(null, tenantSlug, articleId, versionId, expectedVersion, decision)}
      publishAction={(versionId: string, expectedVersion: number) => publishKbArticleVersionAction.bind(null, tenantSlug, articleId, versionId, expectedVersion)}
      archiveAction={(versionId: string, expectedVersion: number) => archiveKbArticleVersionAction.bind(null, tenantSlug, articleId, versionId, expectedVersion)}
    />
  );
}
