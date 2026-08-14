import { notFound } from "next/navigation";
import { resolveTicketAccessForRequest } from "../../../../lib/portal/resolve-ticket-access.server.ts";
import { createSupabaseServerClient } from "../../../../lib/supabase/server.ts";
import { listKbArticles, searchKnowledgeArticles, KbQueryError } from "../../../../server/queries/knowledge-base.ts";
import { ErrorState } from "../../../../components/ui/error-state.tsx";
import { KbListPanel } from "./kb-list-panel.tsx";
import { createKbArticleAction } from "./actions.ts";

/**
 * Knowledge Base workspace (HRT-289, CG-S12-HRT-017) -- its own top-level
 * route family, deliberately NOT nested under `tickets/` (decision, this
 * capability's own contract-file header): an article has no required ticket
 * relationship. Internal/staff-facing only in this checkpoint -- a full
 * Customer Portal article projection remains Step 13 scope
 * (272_HRIS_TICKETING_README.md section 7's own explicit boundary), so this
 * page always calls app.search_knowledge_articles (the staff/internal
 * search, sees every published article regardless of audience), never the
 * customer- or helpdesk-scoped RPCs -- those are exercised from the
 * server/queries/mutations layer and this checkpoint's own db-test file, not
 * from a live customer-facing page.
 */
export default async function KnowledgeBaseListPage({ params, searchParams }: { params: Promise<{ tenantSlug: string }>; searchParams: Promise<{ q?: string }> }) {
  const { tenantSlug } = await params;
  const { q } = await searchParams;
  const access = await resolveTicketAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();
  let loadFailed = false;
  let articles: Awaited<ReturnType<typeof listKbArticles>> = [];
  let searchResults: Awaited<ReturnType<typeof searchKnowledgeArticles>> = [];

  try {
    articles = await listKbArticles(supabase, access.tenant.id, access.authUserId);
    if (q && q.trim().length > 0) {
      searchResults = await searchKnowledgeArticles(supabase, access.tenant.id, access.authUserId, { query: q.trim(), limit: 50 });
    }
  } catch (error) {
    if (!(error instanceof KbQueryError)) throw error;
    loadFailed = true;
  }

  if (loadFailed) {
    return <ErrorState description="Something went wrong loading the knowledge base. Please try again." />;
  }

  return (
    <div className="flex flex-col gap-4">
      <div>
        <h1 className="text-xl font-semibold text-neutral-900">Knowledge base</h1>
        <p className="text-xs text-neutral-500">Draft, review, and publish support articles -- audience (internal/customer/helpdesk) controls exactly who a published article reaches.</p>
      </div>

      <KbListPanel tenantSlug={tenantSlug} articles={articles} query={q ?? ""} searchResults={searchResults} createArticleAction={createKbArticleAction.bind(null, tenantSlug)} />
    </div>
  );
}
