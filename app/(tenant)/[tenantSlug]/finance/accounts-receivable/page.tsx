import { notFound } from "next/navigation";
import { resolveFinanceAccessForRequest } from "../../../../../lib/portal/resolve-finance-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { listFinanceArOpenItems, AccountsReceivableQueryError } from "../../../../../server/queries/accounts-receivable.ts";
import type { FinanceArOpenItem } from "../../../../../server/contracts/accounts-receivable/accounts-receivable.ts";
import { DataTable, type DataTableColumn } from "../../../../../components/tables/data-table.tsx";
import { StatusBadge } from "../../../../../components/ui/status-badge.tsx";
import { FINANCE_AR_OPEN_ITEM_STATUS_TONE_MAP } from "../../../../../components/domain/status-tone-map.ts";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";
import { EmptyState } from "../../../../../components/ui/empty-state.tsx";
import { placeFinanceArHoldAction, releaseFinanceArHoldAction, lookupFinanceArExposureAction } from "./actions.ts";
import { PlaceFinanceArHoldForm, ReleaseFinanceArHoldForm, FinanceArExposureLookupForm } from "./accounts-receivable-forms.tsx";

/**
 * Accounts Receivable workspace (FIN-196, CG-S9-FIN-007). A Finance work
 * queue over AR open items -- server-filtered by status, due-date ordered,
 * bounded to 200 rows (Prompt 196 section 17's own "cursor paginate open
 * items" requirement; a bounded first page mirrors every prior Finance
 * capability's own MVP list-size decision, full cursor pagination deferred).
 * Open items are created only via a balanced source posting -- no create
 * form exists on this page (Prompt 196 section 24).
 */
export default async function AccountsReceivablePage({ params }: { params: Promise<{ tenantSlug: string }> }) {
  const { tenantSlug } = await params;
  const access = await resolveFinanceAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();
  let items: FinanceArOpenItem[] = [];
  let loadFailed = false;
  try {
    items = await listFinanceArOpenItems(supabase, { tenantId: access.tenant.id, companyId: null, customerAccountId: null, status: null, overdueOnly: false, actorAuthUserId: access.authUserId });
  } catch (error) {
    if (!(error instanceof AccountsReceivableQueryError)) {
      throw error;
    }
    loadFailed = true;
  }

  const today = new Date().toISOString().slice(0, 10);

  const columns: readonly DataTableColumn<FinanceArOpenItem>[] = [
    { key: "customer", header: "Customer account", render: (item) => item.customerAccountId },
    { key: "source", header: "Source", render: (item) => `${item.sourceDocumentType} / ${item.sourceDocumentId.slice(0, 8)}…` },
    { key: "currency", header: "Currency", render: (item) => item.currency },
    { key: "originalAmount", header: "Original", render: (item) => item.originalAmount },
    { key: "openAmount", header: "Open", render: (item) => item.openAmount },
    { key: "dueDate", header: "Due date", render: (item) => (item.status !== "paid" && item.dueDate < today ? <span className="font-semibold text-danger">{item.dueDate} (overdue)</span> : item.dueDate) },
    {
      key: "status",
      header: "Status",
      render: (item) => {
        const { tone, label } = FINANCE_AR_OPEN_ITEM_STATUS_TONE_MAP[item.status];
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
          <ReleaseFinanceArHoldForm action={releaseFinanceArHoldAction.bind(null, tenantSlug, item.id, item.recordVersion)} />
        ) : (
          <PlaceFinanceArHoldForm action={placeFinanceArHoldAction.bind(null, tenantSlug, item.id, item.recordVersion)} />
        ),
    },
  ];

  return (
    <div className="flex flex-col gap-6">
      <div>
        <h1 className="text-xl font-semibold text-text-primary">Accounts Receivable</h1>
        <p className="text-sm text-text-secondary">Source-linked customer open items, due balances, and collection holds. Created only via a balanced source posting (invoice issue or an approved opening balance) -- never ad hoc entry.</p>
      </div>

      <div>
        {loadFailed ? (
          <ErrorState description="Something went wrong loading AR open items. Please try again." />
        ) : items.length === 0 ? (
          <EmptyState title="No AR open items yet" description="Open items appear here once an invoice is issued or an approved opening balance is posted." />
        ) : (
          <DataTable caption="AR open items" columns={columns} rows={items} rowKey={(item) => item.id} emptyMessage="No AR open items yet." />
        )}
      </div>

      <FinanceArExposureLookupForm action={lookupFinanceArExposureAction.bind(null, tenantSlug)} />
    </div>
  );
}
