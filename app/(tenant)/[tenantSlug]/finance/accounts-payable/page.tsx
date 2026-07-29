import { notFound } from "next/navigation";
import { resolveFinanceAccessForRequest } from "../../../../../lib/portal/resolve-finance-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { listFinanceApOpenItems, AccountsPayableQueryError } from "../../../../../server/queries/accounts-payable.ts";
import type { FinanceApOpenItem } from "../../../../../server/contracts/accounts-payable/accounts-payable.ts";
import { DataTable, type DataTableColumn } from "../../../../../components/tables/data-table.tsx";
import { StatusBadge } from "../../../../../components/ui/status-badge.tsx";
import { FINANCE_AP_OPEN_ITEM_STATUS_TONE_MAP } from "../../../../../components/domain/status-tone-map.ts";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";
import { EmptyState } from "../../../../../components/ui/empty-state.tsx";
import { placeFinanceApHoldAction, releaseFinanceApHoldAction, lookupFinanceApExposureAction } from "./actions.ts";
import { PlaceFinanceApHoldForm, ReleaseFinanceApHoldForm, FinanceApExposureLookupForm } from "./accounts-payable-forms.tsx";

/**
 * Accounts Payable workspace (FIN-199, CG-S9-FIN-010). A Finance work queue
 * over AP open items -- server-filtered by status, due-date ordered, bounded
 * to 200 rows -- the vendor-side mirror of FIN-196's own Accounts Receivable
 * workspace. Open items are created only via a controlled bill posting or an
 * approved opening balance -- no create form exists on this page (Prompt 199
 * section 24). Phase 4 uses available verified vendor references only; full
 * onboarding/PO/contract lifecycle remains Step 11.
 */
export default async function AccountsPayablePage({ params }: { params: Promise<{ tenantSlug: string }> }) {
  const { tenantSlug } = await params;
  const access = await resolveFinanceAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();
  let items: FinanceApOpenItem[] = [];
  let loadFailed = false;
  try {
    items = await listFinanceApOpenItems(supabase, { tenantId: access.tenant.id, companyId: null, vendorMasterId: null, status: null, overdueOnly: false, actorAuthUserId: access.authUserId });
  } catch (error) {
    if (!(error instanceof AccountsPayableQueryError)) {
      throw error;
    }
    loadFailed = true;
  }

  const today = new Date().toISOString().slice(0, 10);

  const columns: readonly DataTableColumn<FinanceApOpenItem>[] = [
    { key: "vendor", header: "Vendor reference", render: (item) => item.vendorMasterId },
    { key: "source", header: "Source", render: (item) => `${item.sourceDocumentType} / ${item.sourceDocumentId.slice(0, 8)}…` },
    { key: "currency", header: "Currency", render: (item) => item.currency },
    { key: "originalAmount", header: "Original", render: (item) => item.originalAmount },
    { key: "openAmount", header: "Open", render: (item) => item.openAmount },
    { key: "dueDate", header: "Due date", render: (item) => (item.status !== "settled" && item.dueDate < today ? <span className="font-semibold text-danger">{item.dueDate} (overdue)</span> : item.dueDate) },
    {
      key: "status",
      header: "Status",
      render: (item) => {
        const { tone, label } = FINANCE_AP_OPEN_ITEM_STATUS_TONE_MAP[item.status];
        return (
          <div className="flex flex-col gap-1">
            <StatusBadge tone={tone} label={label} />
            {item.isHeld ? <StatusBadge tone="danger" label="Held" /> : null}
          </div>
        );
      },
    },
    {
      key: "actions",
      header: "Actions",
      render: (item) =>
        item.isHeld ? (
          <ReleaseFinanceApHoldForm action={releaseFinanceApHoldAction.bind(null, tenantSlug, item.id, item.recordVersion)} />
        ) : (
          <PlaceFinanceApHoldForm action={placeFinanceApHoldAction.bind(null, tenantSlug, item.id, item.recordVersion)} />
        ),
    },
  ];

  return (
    <div className="flex flex-col gap-6">
      <div>
        <h1 className="text-xl font-semibold text-text-primary">Accounts Payable</h1>
        <p className="text-sm text-text-secondary">Source-linked vendor open items, due balances, and payment holds. Created only via controlled bill posting or an approved opening balance -- never ad hoc entry.</p>
      </div>

      <div>
        {loadFailed ? (
          <ErrorState description="Something went wrong loading AP open items. Please try again." />
        ) : items.length === 0 ? (
          <EmptyState title="No AP open items yet" description="Open items appear here once a vendor bill is posted or an approved opening balance is entered." />
        ) : (
          <DataTable caption="AP open items" columns={columns} rows={items} rowKey={(item) => item.id} emptyMessage="No AP open items yet." />
        )}
      </div>

      <FinanceApExposureLookupForm action={lookupFinanceApExposureAction.bind(null, tenantSlug)} />
    </div>
  );
}
