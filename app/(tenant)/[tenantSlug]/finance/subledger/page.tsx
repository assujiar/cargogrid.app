import { notFound } from "next/navigation";
import Link from "next/link";
import { resolveFinanceAccessForRequest } from "../../../../../lib/portal/resolve-finance-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import {
  listFinanceSubledgerBatches,
  getFinanceSubledgerLines,
  getFinanceSubledgerReconciliationSummary,
  SubledgerQueryError,
} from "../../../../../server/queries/subledger.ts";
import type { FinanceSubledgerBatch, FinanceSubledgerLine, FinanceSubledgerReconciliationSummary } from "../../../../../server/contracts/subledger/subledger.ts";
import { DataTable, type DataTableColumn } from "../../../../../components/tables/data-table.tsx";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";
import { EmptyState } from "../../../../../components/ui/empty-state.tsx";

/**
 * Subledger explorer (FIN-202, CG-S9-FIN-013). Read-only: a subledger batch
 * is only ever emitted by an already-authority-checked source posting
 * (invoice issue, receipt allocation, vendor bill post, settlement post) --
 * there is no create/edit surface here, per Prompt 202 section 24's own
 * "Normal users cannot create arbitrary source events or edit posted
 * lines." Shows a bounded (200-row) batch list filterable by source type,
 * a per-batch debit/credit line drill-down, and the AR/AP control-account
 * reconciliation summary.
 */
export default async function SubledgerPage({
  params,
  searchParams,
}: {
  params: Promise<{ tenantSlug: string }>;
  searchParams: Promise<{ sourceType?: string; batchId?: string }>;
}) {
  const { tenantSlug } = await params;
  const { sourceType, batchId } = await searchParams;
  const access = await resolveFinanceAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();
  let batches: FinanceSubledgerBatch[] = [];
  let lines: FinanceSubledgerLine[] = [];
  let reconciliation: FinanceSubledgerReconciliationSummary | null = null;
  let loadFailed = false;
  try {
    batches = await listFinanceSubledgerBatches(supabase, { tenantId: access.tenant.id, companyId: null, sourceType: sourceType ?? null, actorAuthUserId: access.authUserId });
    if (batchId) {
      lines = await getFinanceSubledgerLines(supabase, { batchId, actorAuthUserId: access.authUserId });
    }
    reconciliation = await getFinanceSubledgerReconciliationSummary(supabase, { tenantId: access.tenant.id, actorAuthUserId: access.authUserId });
  } catch (error) {
    if (!(error instanceof SubledgerQueryError)) {
      throw error;
    }
    loadFailed = true;
  }

  const batchColumns: readonly DataTableColumn<FinanceSubledgerBatch>[] = [
    { key: "sourceType", header: "Source type", render: (batch) => batch.sourceType },
    { key: "sourceId", header: "Source ID", render: (batch) => batch.sourceId },
    { key: "currency", header: "Currency", render: (batch) => batch.currency },
    { key: "total", header: "Total", render: (batch) => batch.totalAmount },
    { key: "status", header: "Status", render: (batch) => batch.status },
    { key: "glJournal", header: "GL journal", render: (batch) => batch.glJournalId ?? "(not yet linked -- FIN-203)" },
    { key: "postedAt", header: "Posted at", render: (batch) => batch.postedAt },
    { key: "view", header: "Lines", render: (batch) => <Link href={`?batchId=${batch.id}`}>View lines</Link> },
  ];

  const lineColumns: readonly DataTableColumn<FinanceSubledgerLine>[] = [
    { key: "lineNumber", header: "#", render: (line) => line.lineNumber },
    { key: "direction", header: "Direction", render: (line) => line.direction },
    { key: "amount", header: "Amount", render: (line) => line.amount },
    { key: "accountId", header: "Account", render: (line) => line.accountId },
    { key: "postingMapKey", header: "Posting map key", render: (line) => line.postingMapKey ?? "(direct account reference)" },
    { key: "openItem", header: "Open item", render: (line) => (line.openItemId ? `${line.openItemType}: ${line.openItemId}` : "—") },
  ];

  return (
    <div className="flex flex-col gap-6">
      <div>
        <h1 className="text-xl font-semibold text-text-primary">Subledger</h1>
        <p className="text-sm text-text-secondary">
          Read-only canonical accounting events translating invoice, receipt-allocation, vendor-bill and settlement postings into balanced debit/credit
          lines. A subledger batch is only ever emitted by an already-authorized source posting -- there is no manual create/edit action here.
        </p>
      </div>

      {reconciliation ? (
        <div className="grid grid-cols-1 gap-4 rounded-md border border-neutral-200 p-4 sm:grid-cols-2">
          <div>
            <h2 className="text-sm font-semibold text-text-primary">AR control reconciliation ({reconciliation.arControlAccountCode})</h2>
            <p className="text-sm text-text-secondary">
              Subledger balance {reconciliation.arControlSubledgerBalance} vs. AR open-item total {reconciliation.arOpenItemTotal} --{" "}
              {reconciliation.arReconciled ? "reconciled" : "NOT reconciled"}
            </p>
          </div>
          <div>
            <h2 className="text-sm font-semibold text-text-primary">AP control reconciliation ({reconciliation.apControlAccountCode})</h2>
            <p className="text-sm text-text-secondary">
              Subledger balance {reconciliation.apControlSubledgerBalance} vs. AP open-item total {reconciliation.apOpenItemTotal} --{" "}
              {reconciliation.apReconciled ? "reconciled" : "NOT reconciled"}
            </p>
          </div>
        </div>
      ) : null}

      <div>
        {loadFailed ? (
          <ErrorState description="Something went wrong loading the subledger. Please try again." />
        ) : batches.length === 0 ? (
          <EmptyState title="No subledger batches yet" description="Batches are emitted automatically when an invoice is issued, a receipt is allocated, a vendor bill is posted, or a settlement is posted." />
        ) : (
          <DataTable caption="Subledger batches" columns={batchColumns} rows={batches} rowKey={(batch) => batch.id} emptyMessage="No subledger batches yet." />
        )}
      </div>

      {batchId ? (
        <div>
          <h2 className="text-sm font-semibold text-text-primary">Lines for batch {batchId}</h2>
          <DataTable caption="Subledger lines" columns={lineColumns} rows={lines} rowKey={(line) => line.id} emptyMessage="No lines found." />
        </div>
      ) : null}
    </div>
  );
}
