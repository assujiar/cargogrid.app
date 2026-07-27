import { notFound } from "next/navigation";
import { resolveCommercialAccessForRequest } from "../../../../../lib/portal/resolve-commercial-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { listQuotationApprovalInboxForActor, QuotationApprovalQueryError } from "../../../../../server/queries/quotation-approval.ts";
import { getQuotationById } from "../../../../../server/queries/quotation.ts";
import { DataTable, type DataTableColumn } from "../../../../../components/tables/data-table.tsx";

/**
 * Quotation approval inbox (COM-153, CG-S7-COM-012, Prompt 153 §66/§15: "accessible
 * approval inbox"). Lists every currently-active step across the tenant this actor is
 * eligible to decide right now (direct role/user match or an active delegation) --
 * app.list_pending_approval_steps_for_actor (PLT-123) is entity-agnostic, so
 * listQuotationApprovalInboxForActor (server/queries/quotation-approval.ts) resolves each
 * step to its bound quotation. Deciding happens on the quotation's own detail page (the
 * approval panel there already carries the full record -- cost/margin fields projected by
 * permission, version history, comparison diff -- rather than duplicating that context
 * here); this page is a routing list, not a second decision surface.
 */
export default async function ApprovalsInboxPage({ params }: { params: Promise<{ tenantSlug: string }> }) {
  const { tenantSlug } = await params;
  const access = await resolveCommercialAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();

  let items: Awaited<ReturnType<typeof listQuotationApprovalInboxForActor>>;
  let loadFailed = false;
  try {
    items = await listQuotationApprovalInboxForActor(supabase, access.tenant.id, access.authUserId);
  } catch (error) {
    if (!(error instanceof QuotationApprovalQueryError)) {
      throw error;
    }
    loadFailed = true;
    items = [];
  }

  const quotations = await Promise.all(items.map((item) => getQuotationById(supabase, item.quotationId)));
  const rows = items.map((item, index) => ({ item, quotation: quotations[index] }));

  const columns: readonly DataTableColumn<(typeof rows)[number]>[] = [
    { key: "quotation", header: "Quotation", render: (row) => row.quotation?.quoteNumber ?? row.item.quotationId },
    { key: "step", header: "Step", render: (row) => `Step ${row.item.stepOrder}` },
    {
      key: "action",
      header: "Action",
      render: (row) => (
        <a href={`/${tenantSlug}/commercial/quotations/${row.item.quotationId}`} className="text-sm font-medium text-primary underline">
          Review
        </a>
      ),
    },
  ];

  return (
    <div className="flex flex-col gap-6">
      <h1 className="text-xl font-semibold text-neutral-900">Approvals</h1>

      {loadFailed ? (
        <div role="alert" className="flex flex-col gap-2">
          <p className="text-sm text-danger">Something went wrong loading your approval inbox. Please try again.</p>
        </div>
      ) : (
        <div className="rounded-md border border-neutral-200 p-4">
          <h2 className="text-sm font-semibold text-neutral-900">Waiting on your decision</h2>
          <div className="mt-2">
            <DataTable
              caption="Approvals waiting on your decision"
              columns={columns}
              rows={rows}
              rowKey={(row) => row.item.stepId}
              emptyMessage="Nothing is waiting on you right now."
            />
          </div>
        </div>
      )}
    </div>
  );
}
