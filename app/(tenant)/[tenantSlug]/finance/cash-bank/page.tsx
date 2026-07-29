import { notFound } from "next/navigation";
import Link from "next/link";
import { resolveFinanceAccessForRequest } from "../../../../../lib/portal/resolve-finance-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { listFinanceBankAccounts, listFinanceBankTransactions, getFinanceCashPosition, CashBankQueryError } from "../../../../../server/queries/cash-bank.ts";
import type { FinanceBankAccount, FinanceBankTransaction, FinanceCashPosition } from "../../../../../server/contracts/cash-bank/cash-bank.ts";
import { DataTable, type DataTableColumn } from "../../../../../components/tables/data-table.tsx";
import { StatusBadge } from "../../../../../components/ui/status-badge.tsx";
import { FINANCE_BANK_TRANSACTION_MATCH_STATUS_TONE_MAP } from "../../../../../components/domain/status-tone-map.ts";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";
import { EmptyState } from "../../../../../components/ui/empty-state.tsx";
import {
  createFinanceBankAccountAction,
  importFinanceBankStatementAction,
  matchFinanceBankTransactionAction,
  unmatchFinanceBankTransactionAction,
} from "./actions.ts";
import { CreateFinanceBankAccountForm, ImportFinanceBankStatementForm, MatchFinanceBankTransactionForm, UnmatchFinanceBankTransactionForm } from "./cash-bank-forms.tsx";

/**
 * Cash and Bank Baseline workspace (FIN-211, CG-S9-FIN-022). Bank/cash
 * account management (masked account numbers only), a staged statement
 * import form (no live bank-provider connection), a governed match/unmatch
 * transaction queue, and a reconciled cash position against the account's
 * own GL (cash_default-mapped) balance.
 */
export default async function CashBankPage({
  params,
  searchParams,
}: {
  params: Promise<{ tenantSlug: string }>;
  searchParams: Promise<{ bankAccountId?: string; asOfDate?: string }>;
}) {
  const { tenantSlug } = await params;
  const { bankAccountId, asOfDate: rawAsOfDate } = await searchParams;
  const access = await resolveFinanceAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const asOfDate = rawAsOfDate ?? new Date().toISOString().slice(0, 10);
  const supabase = await createSupabaseServerClient();
  let accounts: FinanceBankAccount[] = [];
  let transactions: FinanceBankTransaction[] = [];
  let position: FinanceCashPosition | null = null;
  let loadFailed = false;
  try {
    accounts = await listFinanceBankAccounts(supabase, { tenantId: access.tenant.id, companyId: null, actorAuthUserId: access.authUserId });
    if (bankAccountId) {
      transactions = await listFinanceBankTransactions(supabase, { tenantId: access.tenant.id, bankAccountId, matchStatus: null, actorAuthUserId: access.authUserId });
      position = await getFinanceCashPosition(supabase, { tenantId: access.tenant.id, bankAccountId, asOfDate, actorAuthUserId: access.authUserId });
    }
  } catch (error) {
    if (!(error instanceof CashBankQueryError)) {
      throw error;
    }
    loadFailed = true;
  }

  const accountColumns: readonly DataTableColumn<FinanceBankAccount>[] = [
    { key: "name", header: "Account", render: (account) => <Link href={`?bankAccountId=${account.id}`}>{account.accountName}</Link> },
    { key: "bank", header: "Bank", render: (account) => account.bankName },
    { key: "last4", header: "Ending in", render: (account) => `••••${account.accountNumberLast4}` },
    { key: "currency", header: "Currency", render: (account) => account.currency },
    { key: "status", header: "Status", render: (account) => account.status },
  ];

  const transactionColumns: readonly DataTableColumn<FinanceBankTransaction>[] = [
    { key: "date", header: "Date", render: (transaction) => transaction.transactionDate },
    { key: "direction", header: "Direction", render: (transaction) => transaction.direction },
    { key: "amount", header: "Amount", render: (transaction) => transaction.amount },
    { key: "reference", header: "Reference", render: (transaction) => transaction.reference ?? "—" },
    {
      key: "status",
      header: "Status",
      render: (transaction) => {
        const { tone, label } = FINANCE_BANK_TRANSACTION_MATCH_STATUS_TONE_MAP[transaction.matchStatus];
        return <StatusBadge tone={tone} label={label} />;
      },
    },
    {
      key: "actions",
      header: "Actions",
      render: (transaction) => {
        if (transaction.matchStatus === "unmatched") {
          return <MatchFinanceBankTransactionForm action={matchFinanceBankTransactionAction.bind(null, tenantSlug, transaction.id, transaction.recordVersion)} />;
        }
        return <UnmatchFinanceBankTransactionForm action={unmatchFinanceBankTransactionAction.bind(null, tenantSlug, transaction.id, transaction.recordVersion)} />;
      },
    },
  ];

  return (
    <div className="flex flex-col gap-6">
      <div>
        <h1 className="text-xl font-semibold text-text-primary">Cash and Bank</h1>
        <p className="text-sm text-text-secondary">
          Bank/cash account control with masked account numbers only, staged statement import (no live bank-provider connection), governed
          transaction matching, and a cash position reconciled against the account&apos;s own GL balance.
        </p>
      </div>

      <div>
        {loadFailed ? (
          <ErrorState description="Something went wrong loading cash and bank data. Please try again." />
        ) : accounts.length === 0 ? (
          <EmptyState title="No bank accounts yet" description="Add a bank/cash account below to begin." />
        ) : (
          <DataTable caption="Bank accounts" columns={accountColumns} rows={accounts} rowKey={(account) => account.id} emptyMessage="No bank accounts yet." />
        )}
      </div>

      {bankAccountId && position ? (
        <div className="rounded-md border border-neutral-200 p-4">
          <h2 className="text-sm font-semibold text-text-primary">Cash position as of {asOfDate}</h2>
          <p className="text-sm text-text-secondary">
            Statement balance: {position.statementBalance} {position.currency} · GL balance: {position.glBalance} {position.currency} · Variance:{" "}
            {position.varianceAmount} {position.currency}
          </p>
        </div>
      ) : null}

      {bankAccountId ? (
        <div>
          <h2 className="text-sm font-semibold text-text-primary">Transactions</h2>
          <DataTable caption="Bank transactions" columns={transactionColumns} rows={transactions} rowKey={(transaction) => transaction.id} emptyMessage="No transactions yet." />
        </div>
      ) : null}

      <div className="flex flex-col gap-4 md:flex-row">
        <CreateFinanceBankAccountForm action={createFinanceBankAccountAction.bind(null, tenantSlug)} />
        <ImportFinanceBankStatementForm action={importFinanceBankStatementAction.bind(null, tenantSlug)} />
      </div>
    </div>
  );
}
