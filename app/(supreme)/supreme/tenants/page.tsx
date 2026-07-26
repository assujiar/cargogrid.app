import { notFound } from "next/navigation";
import { resolveSupremeAdminAccessForRequest } from "../../../../lib/portal/resolve-supreme-admin-access.server.ts";
import { createSupabaseServerClient } from "../../../../lib/supabase/server.ts";
import { listSupremeTenants, SupremeTenantsQueryError, type ListSupremeTenantsResult, type SupremeTenant } from "../../../../server/queries/supreme-tenants.ts";
import { DataTable, type DataTableColumn } from "../../../../components/tables/data-table.tsx";
import { Pagination } from "../../../../components/tables/pagination.tsx";

const PAGE_SIZE = 20;

/**
 * Global tenant list (PLT-136, CG-S6-PLT-033) -- the one bounded workflow this
 * checkpoint ships (Prompt 136 §11/§12: "bounded workflows," never an unreviewed
 * destructive bulk action or domain feature admin). Read-only: tenant lifecycle
 * mutations (`app.transition_tenant_status()` and friends, `PLT-105`) already exist as
 * real backend capability, but their own high-risk UI (re-authentication, impact
 * preview, confirmation -- Prompt 136 §16/§20 task 2) is deliberately deferred to a
 * later, separately-scoped slice: building that machinery now, with no real mutating
 * action to gate yet, would be exactly the kind of unresolved placeholder this
 * checkpoint's own governance forbids.
 *
 * States (`docs/standards/DESIGN_SYSTEM.md` §4): Empty and Error are both real,
 * distinct renders below; data is fetched into a plain result/error value first, with
 * JSX construction kept entirely outside the `try`/`catch`
 * (`react-hooks/error-boundaries`, the same defect class `PLT-135`'s own users list
 * page fixed).
 *
 * Migrated onto the shared `DataTable`/`Pagination` primitives (CargoGrid UI
 * Modernization checkpoint, `docs/design-system/02_COMPONENTS.md`) -- the second real
 * consumer validating both against a screen outside Commercial; no query/behavior
 * change, table markup and the previously-static "Page X" text (no actual prev/next
 * control existed before this checkpoint) only.
 */
export default async function SupremeTenantsPage({ searchParams }: { searchParams: Promise<{ page?: string }> }) {
  const access = await resolveSupremeAdminAccessForRequest();
  if (access.status !== "allowed") {
    notFound();
  }

  const { page: pageParam } = await searchParams;
  const page = Math.max(Number.parseInt(pageParam ?? "1", 10) || 1, 1);

  const supabase = await createSupabaseServerClient();

  let result: ListSupremeTenantsResult | null = null;
  let loadFailed = false;
  try {
    result = await listSupremeTenants(supabase, { page, pageSize: PAGE_SIZE });
  } catch (error) {
    if (!(error instanceof SupremeTenantsQueryError)) {
      throw error;
    }
    loadFailed = true;
  }

  if (loadFailed || !result) {
    return (
      <div className="flex flex-col gap-2" role="alert">
        <h1 className="text-xl font-semibold text-neutral-900">Tenants</h1>
        <p className="text-sm text-danger">Something went wrong loading tenants. Please try again.</p>
      </div>
    );
  }

  const columns: readonly DataTableColumn<SupremeTenant>[] = [
    { key: "name", header: "Name", render: (tenant) => tenant.name },
    { key: "slug", header: "Slug", render: (tenant) => tenant.slug },
    { key: "status", header: "Status", render: (tenant) => tenant.canonicalStatus },
  ];

  return (
    <div className="flex flex-col gap-4">
      <h1 className="text-xl font-semibold text-neutral-900">Tenants</h1>
      <DataTable
        caption="Tenants"
        columns={columns}
        rows={result.tenants}
        rowKey={(tenant) => tenant.id}
        emptyMessage="No tenants have been provisioned yet."
      />
      <div className="flex flex-wrap items-center justify-between gap-2">
        <p className="text-xs text-neutral-500">
          Page {result.page} — {result.totalCount} total tenant{result.totalCount === 1 ? "" : "s"}
        </p>
        <Pagination
          page={result.page}
          pageSize={PAGE_SIZE}
          totalCount={result.totalCount}
          buildHref={(targetPage) => `/supreme/tenants?page=${targetPage}`}
        />
      </div>
    </div>
  );
}
