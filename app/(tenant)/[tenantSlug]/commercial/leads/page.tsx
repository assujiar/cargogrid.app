import { notFound } from "next/navigation";
import { resolveCommercialAccessForRequest } from "../../../../../lib/portal/resolve-commercial-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { listLeads, LeadQueryError, type ListLeadsResult } from "../../../../../server/queries/lead.ts";
import type { Lead } from "../../../../../server/contracts/lead/lead.ts";
import { DataTable, type DataTableColumn } from "../../../../../components/tables/data-table.tsx";
import { Pagination } from "../../../../../components/tables/pagination.tsx";
import { captureLeadAction } from "./actions.ts";
import { CaptureLeadForm } from "./capture-lead-form.tsx";

/**
 * Lead List (COM-143, CG-S7-COM-002) -- the first business-domain page in this
 * repository. Read-only table plus the one bounded mutating action Prompt 143 §21's
 * main flow requires ("a permitted seller captures a unique lead"); assign/merge remain
 * real, tested mutation-layer capabilities without a dedicated button in this bounded
 * first slice, the same "core management, not an all-actions mega task" scoping
 * PLT-135's own Users list precedent used.
 *
 * States (`docs/standards/DESIGN_SYSTEM.md` §4): Empty and Error are both real, distinct
 * renders below; a sibling `loading.tsx` covers Loading via the Suspense boundary. Data
 * is fetched into a plain result/error value first, JSX construction kept entirely
 * outside the `try`/`catch`, mirroring `admin/users/page.tsx`'s own discipline exactly.
 *
 * Migrated onto the shared `DataTable`/`Pagination` primitives (CargoGrid UI
 * Modernization checkpoint, `docs/design-system/02_COMPONENTS.md`) -- the reference
 * Commercial consumer for both; no query/behavior change, table markup and the
 * previously-static "Page X" text (no actual prev/next control existed before this
 * checkpoint) only.
 */
export default async function CommercialLeadsPage({
  params,
  searchParams,
}: {
  params: Promise<{ tenantSlug: string }>;
  searchParams: Promise<{ page?: string }>;
}) {
  const { tenantSlug } = await params;
  const access = await resolveCommercialAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const { page: pageParam } = await searchParams;
  const page = Math.max(Number.parseInt(pageParam ?? "1", 10) || 1, 1);

  const supabase = await createSupabaseServerClient();

  let result: ListLeadsResult | null = null;
  let loadFailed = false;
  try {
    result = await listLeads(supabase, { tenantId: access.tenant.id, page });
  } catch (error) {
    if (!(error instanceof LeadQueryError)) {
      throw error;
    }
    loadFailed = true;
  }

  const boundCaptureLeadAction = captureLeadAction.bind(null, tenantSlug);

  const columns: readonly DataTableColumn<Lead>[] = [
    {
      key: "contact",
      header: "Contact",
      render: (lead) => (
        <a href={`/${tenantSlug}/commercial/leads/${lead.id}`} className="font-medium text-primary underline">
          {lead.contactName}
        </a>
      ),
    },
    { key: "company", header: "Company", render: (lead) => lead.companyName ?? "—" },
    { key: "source", header: "Source", render: (lead) => lead.source },
    { key: "status", header: "Status", render: (lead) => lead.status },
    { key: "score", header: "Score", align: "right", render: (lead) => lead.score },
  ];

  return (
    <div className="flex flex-col gap-6">
      <h1 className="text-xl font-semibold text-neutral-900">Leads</h1>

      <CaptureLeadForm action={boundCaptureLeadAction} />

      {loadFailed || !result ? (
        <div role="alert" className="flex flex-col gap-2">
          <p className="text-sm text-danger">Something went wrong loading leads. Please try again.</p>
        </div>
      ) : (
        <div className="flex flex-col gap-4">
          <DataTable
            caption="Leads"
            columns={columns}
            rows={result.leads}
            rowKey={(lead) => lead.id}
            emptyMessage="No leads found for this organization yet."
          />
          <div className="flex flex-wrap items-center justify-between gap-2">
            <p className="text-xs text-neutral-500">
              Page {result.page} — {result.totalCount} total lead{result.totalCount === 1 ? "" : "s"}
            </p>
            <Pagination
              page={result.page}
              pageSize={result.pageSize}
              totalCount={result.totalCount}
              buildHref={(targetPage) => `/${tenantSlug}/commercial/leads?page=${targetPage}`}
            />
          </div>
        </div>
      )}
    </div>
  );
}
