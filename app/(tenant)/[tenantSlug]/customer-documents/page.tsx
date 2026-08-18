import { notFound } from "next/navigation";
import { resolveCustomerPortalAccessForRequest } from "../../../../lib/portal/resolve-customer-portal-access.server.ts";
import { createSupabaseServerClient } from "../../../../lib/supabase/server.ts";
import { getCustomerPortalScopeContext, CustomerPortalScopeQueryError } from "../../../../server/queries/customer-portal-scope.ts";
import { listCustomerDocuments, CustomerDocumentQueryError } from "../../../../server/queries/customer-document.ts";
import { CUSTOMER_DOCUMENT_SOURCE_MODULES, type CustomerDocumentSourceModule } from "../../../../server/contracts/customer-document/customer-document.ts";
import { ErrorState } from "../../../../components/ui/error-state.tsx";
import { CustomerDocumentsPanel } from "./customer-documents-panel.tsx";
import { downloadCustomerDocumentAction } from "./actions.ts";

/**
 * Customer Document Center (CPL-308, CG-S13-CPL-010, Prompt 308). Uses
 * lib/portal/customer-portal-guard.ts (CPL-300's general-purpose Layer 4
 * portal entry guard), mirroring app/(tenant)/[tenantSlug]/customer-
 * shipments/page.tsx's own structure. A standalone route, per the
 * orchestrating task's own instruction (migration design decision 13) --
 * never a sub-route of an existing capability. A live, cross-source
 * composition (quote-request attachments + ePOD evidence today; invoice/
 * ticket filters are recognized but honestly empty until Prompts 311/313
 * ship) -- never a duplicate file store, never a new upload path.
 */
export default async function CustomerDocumentsPage({
  params,
  searchParams,
}: {
  params: Promise<{ tenantSlug: string }>;
  searchParams: Promise<{ sourceModule?: string; accountId?: string; dateFrom?: string; dateTo?: string }>;
}) {
  const { tenantSlug } = await params;
  const { sourceModule: rawSourceModule, accountId: rawAccountId, dateFrom: rawDateFrom, dateTo: rawDateTo } = await searchParams;
  const access = await resolveCustomerPortalAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const sourceModule = rawSourceModule && (CUSTOMER_DOCUMENT_SOURCE_MODULES as readonly string[]).includes(rawSourceModule) ? (rawSourceModule as CustomerDocumentSourceModule) : null;
  const accountId = rawAccountId && rawAccountId.length > 0 ? rawAccountId : null;
  // A plain <input type="date"> submits "YYYY-MM-DD" -- widened to a real
  // inclusive calendar-day range (start of day / end of day, both UTC) before
  // reaching the RPC's own timestamptz parameters, never sent as a bare date
  // string.
  const dateFrom = rawDateFrom ? new Date(`${rawDateFrom}T00:00:00.000Z`).toISOString() : null;
  const dateTo = rawDateTo ? new Date(`${rawDateTo}T23:59:59.999Z`).toISOString() : null;

  const supabase = await createSupabaseServerClient();
  let loadFailed = false;
  let accounts: Awaited<ReturnType<typeof getCustomerPortalScopeContext>> = [];
  let documents: Awaited<ReturnType<typeof listCustomerDocuments>> = [];

  try {
    [accounts, documents] = await Promise.all([
      getCustomerPortalScopeContext(supabase, access.authUserId, access.tenant.id),
      listCustomerDocuments(supabase, access.tenant.id, access.authUserId, { accountId, sourceModule, dateFrom, dateTo, limit: 50 }),
    ]);
  } catch (error) {
    if (!(error instanceof CustomerPortalScopeQueryError) && !(error instanceof CustomerDocumentQueryError)) throw error;
    loadFailed = true;
  }

  if (loadFailed) {
    return <ErrorState description="Something went wrong loading your documents. Please try again." />;
  }

  return (
    <div className="flex flex-col gap-4">
      <div>
        <h1 className="text-xl font-semibold text-neutral-900">Documents</h1>
        <p className="text-xs text-neutral-500">
          Every document you&apos;re entitled to across your quote requests and delivery evidence, in one place. Invoice and ticket documents will appear here once those capabilities ship. A document link
          never grants access to its own source record or any other linked document -- file bytes remain Platform-owned.
        </p>
      </div>

      <CustomerDocumentsPanel
        tenantSlug={tenantSlug}
        accounts={accounts}
        documents={documents}
        filters={{ sourceModule: rawSourceModule ?? "", accountId: rawAccountId ?? "", dateFrom: rawDateFrom ?? "", dateTo: rawDateTo ?? "" }}
        downloadAction={downloadCustomerDocumentAction.bind(null, tenantSlug)}
      />
    </div>
  );
}
