import { notFound } from "next/navigation";
import Link from "next/link";
import { resolveFinanceAccessForRequest } from "../../../../../../../lib/portal/resolve-finance-access.server.ts";
import { createSupabaseServerClient } from "../../../../../../../lib/supabase/server.ts";
import { listFinanceAccounts, ChartOfAccountsQueryError } from "../../../../../../../server/queries/chart-of-accounts.ts";
import { getFinanceAccountLedger, FinanceAccountLedgerQueryError } from "../../../../../../../server/queries/finance-account-ledger.ts";
import type { FinanceAccountLedgerEntry } from "../../../../../../../server/contracts/finance-account-ledger/finance-account-ledger.ts";
import { DataTable, type DataTableColumn } from "../../../../../../../components/tables/data-table.tsx";
import { ErrorState } from "../../../../../../../components/ui/error-state.tsx";
import { EmptyState } from "../../../../../../../components/ui/empty-state.tsx";
import { FormField } from "../../../../../../../components/forms/form-field.tsx";
import { DateInput } from "../../../../../../../components/forms/date-input.tsx";

function firstOfMonth(): string {
  const now = new Date();
  return new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1)).toISOString().slice(0, 10);
}

/**
 * Account Ledger detail report (CG-AUDIT-2026-09-02 B2, GL detail-report
 * half). One account's own posted transaction history for a date range --
 * a per-currency opening balance (never blended, mirroring app.get_
 * finance_trial_balance's own disclosed convention) and a running balance
 * through every posted line, closing the audit's own "GL is write-only"
 * complaint: previously only a whole-journal browse (finance/journals) or
 * a trial-balance TOTAL existed, never this account's own detail.
 */
export default async function FinanceAccountLedgerPage({
  params,
  searchParams,
}: {
  params: Promise<{ tenantSlug: string; accountId: string }>;
  searchParams: Promise<{ dateFrom?: string; dateTo?: string }>;
}) {
  const { tenantSlug, accountId } = await params;
  const { dateFrom: rawDateFrom, dateTo: rawDateTo } = await searchParams;
  const access = await resolveFinanceAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const dateFrom = rawDateFrom ?? firstOfMonth();
  const dateTo = rawDateTo ?? new Date().toISOString().slice(0, 10);

  const supabase = await createSupabaseServerClient();
  let entries: FinanceAccountLedgerEntry[] = [];
  let accountLabel = accountId;
  let loadFailed = false;
  try {
    const accounts = await listFinanceAccounts(supabase, { tenantId: access.tenant.id, companyId: null, status: null, actorAuthUserId: access.authUserId });
    const account = accounts.find((a) => a.id === accountId);
    if (!account) {
      notFound();
    }
    accountLabel = `${account.code} -- ${account.name}`;
    entries = await getFinanceAccountLedger(supabase, { tenantId: access.tenant.id, companyId: null, accountId, dateFrom, dateTo, actorAuthUserId: access.authUserId });
  } catch (error) {
    if (!(error instanceof ChartOfAccountsQueryError) && !(error instanceof FinanceAccountLedgerQueryError)) {
      throw error;
    }
    loadFailed = true;
  }

  const columns: readonly DataTableColumn<FinanceAccountLedgerEntry>[] = [
    { key: "date", header: "Date", render: (entry) => entry.entryDate },
    { key: "journal", header: "Journal #", render: (entry) => (entry.journalNumber ? <Link href={`/${tenantSlug}/finance/journals?journalId=${entry.journalId}`} className="text-primary underline">{entry.journalNumber}</Link> : "—") },
    { key: "source", header: "Source", render: (entry) => entry.sourceType ?? "—" },
    { key: "description", header: "Description", render: (entry) => entry.description ?? "—" },
    { key: "debit", header: "Debit", render: (entry) => (entry.direction === "debit" ? entry.amount : "—") },
    { key: "credit", header: "Credit", render: (entry) => (entry.direction === "credit" ? entry.amount : "—") },
    { key: "runningBalance", header: "Running balance", render: (entry) => entry.runningBalance },
    { key: "currency", header: "Currency", render: (entry) => entry.currency },
  ];

  return (
    <div className="flex flex-col gap-6">
      <div>
        <h1 className="text-xl font-semibold text-text-primary">Account Ledger -- {accountLabel}</h1>
        <p className="text-sm text-text-secondary">
          Every posted journal line against this account for the selected date range, with a per-currency opening balance and running total -- never a
          blended cross-currency sum. A draft/submitted/approved-but-not-posted journal never appears.
        </p>
        <Link href={`/${tenantSlug}/finance/chart-of-accounts`} className="text-sm text-primary underline">
          Back to Chart of Accounts
        </Link>
      </div>

      <form method="get" className="flex flex-wrap items-end gap-3 rounded-md border border-neutral-200 p-4">
        <FormField id="ledger-filter-dateFrom" label="From">
          <DateInput id="ledger-filter-dateFrom" name="dateFrom" defaultValue={dateFrom} className="w-40" />
        </FormField>
        <FormField id="ledger-filter-dateTo" label="To">
          <DateInput id="ledger-filter-dateTo" name="dateTo" defaultValue={dateTo} className="w-40" />
        </FormField>
        <button type="submit" className="rounded-md border border-neutral-300 px-3 py-2 text-sm font-medium">
          Apply
        </button>
      </form>

      {loadFailed ? (
        <ErrorState description="Something went wrong loading the account ledger. Please try again." />
      ) : entries.length === 0 ? (
        <EmptyState title="No activity" description="No posted activity against this account for the selected date range." />
      ) : (
        <DataTable caption="Account ledger" columns={columns} rows={entries} rowKey={(entry) => entry.journalId ?? `opening-${entry.currency}`} emptyMessage="No posted activity." />
      )}
    </div>
  );
}
