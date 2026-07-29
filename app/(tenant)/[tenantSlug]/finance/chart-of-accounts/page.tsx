import { notFound } from "next/navigation";
import Link from "next/link";
import { resolveFinanceAccessForRequest } from "../../../../../lib/portal/resolve-finance-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { listFinanceAccounts, ChartOfAccountsQueryError } from "../../../../../server/queries/chart-of-accounts.ts";
import type { FinanceAccount, FinanceAccountStatus } from "../../../../../server/contracts/chart-of-accounts/chart-of-accounts.ts";
import { DataTable, type DataTableColumn } from "../../../../../components/tables/data-table.tsx";
import { StatusBadge } from "../../../../../components/ui/status-badge.tsx";
import { FINANCE_ACCOUNT_STATUS_TONE_MAP } from "../../../../../components/domain/status-tone-map.ts";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";
import { EmptyState } from "../../../../../components/ui/empty-state.tsx";
import { createFinanceAccountDraftAction, activateFinanceAccountAction, deactivateFinanceAccountAction } from "./actions.ts";
import { CreateFinanceAccountForm, ActivateFinanceAccountForm, DeactivateFinanceAccountForm } from "./chart-of-accounts-forms.tsx";

const STATUS_FILTERS: readonly { value: FinanceAccountStatus | "all"; label: string }[] = [
  { value: "all", label: "All" },
  { value: "draft", label: "Draft" },
  { value: "active", label: "Active" },
  { value: "inactive", label: "Inactive" },
];

/**
 * Chart of Accounts workspace (FIN-192, CG-S9-FIN-003). A tenant-wide account
 * list (no pagination -- a chart of accounts is a bounded, admin-managed
 * reference set, unlike a large transactional list; still server-filtered by
 * status via `?status=...`, never a second, larger, unbounded dataset).
 * Hierarchy is rendered by indenting each row per its own parent-chain depth,
 * computed once in memory from the already-authority-gated, already-bounded
 * flat list `app.list_finance_accounts` returns -- not a second recursive
 * database query (Prompt 192 section 17's own "recursive query budgets without
 * browser-side full-tree loading" is honoured: the one query IS the bound).
 */
export default async function ChartOfAccountsPage({
  params,
  searchParams,
}: {
  params: Promise<{ tenantSlug: string }>;
  searchParams: Promise<{ status?: string }>;
}) {
  const { tenantSlug } = await params;
  const { status: rawStatus } = await searchParams;
  const access = await resolveFinanceAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const selectedStatus: FinanceAccountStatus | "all" = STATUS_FILTERS.some((f) => f.value === rawStatus) ? (rawStatus as FinanceAccountStatus | "all") : "all";

  const supabase = await createSupabaseServerClient();
  let accounts: FinanceAccount[] = [];
  let loadFailed = false;
  try {
    accounts = await listFinanceAccounts(supabase, {
      tenantId: access.tenant.id,
      companyId: null,
      status: selectedStatus === "all" ? null : selectedStatus,
      actorAuthUserId: access.authUserId,
    });
  } catch (error) {
    if (!(error instanceof ChartOfAccountsQueryError)) {
      throw error;
    }
    loadFailed = true;
  }

  const depthById = new Map<string, number>();
  const byId = new Map(accounts.map((account) => [account.id, account]));
  function depthOf(account: FinanceAccount): number {
    const cached = depthById.get(account.id);
    if (cached !== undefined) return cached;
    let depth = 0;
    let current: FinanceAccount | undefined = account;
    const seen = new Set<string>();
    while (current?.parentAccountId && !seen.has(current.id)) {
      seen.add(current.id);
      const parent = byId.get(current.parentAccountId);
      if (!parent) break;
      depth += 1;
      current = parent;
      if (depth > 10) break; // matches the database's own bounded cycle-detection depth
    }
    depthById.set(account.id, depth);
    return depth;
  }
  const sortedAccounts = [...accounts].sort((a, b) => a.code.localeCompare(b.code));

  const columns: readonly DataTableColumn<FinanceAccount>[] = [
    { key: "code", header: "Code", render: (account) => <span style={{ paddingLeft: `${depthOf(account) * 16}px` }}>{account.code}</span> },
    { key: "name", header: "Name", render: (account) => account.name },
    { key: "accountType", header: "Type", render: (account) => `${account.accountType} (${account.normalBalance})` },
    {
      key: "status",
      header: "Status",
      render: (account) => {
        const { tone, label } = FINANCE_ACCOUNT_STATUS_TONE_MAP[account.status];
        return (
          <span className="flex items-center gap-1">
            <StatusBadge tone={tone} label={label} />
            {account.isControlAccount ? <span className="text-xs text-text-secondary">(control)</span> : null}
          </span>
        );
      },
    },
    {
      key: "action",
      header: "Action",
      render: (account) =>
        account.status === "draft" ? (
          <ActivateFinanceAccountForm action={activateFinanceAccountAction.bind(null, tenantSlug, account.id, account.recordVersion)} />
        ) : account.status === "active" ? (
          <DeactivateFinanceAccountForm action={deactivateFinanceAccountAction.bind(null, tenantSlug, account.id, account.recordVersion)} />
        ) : (
          "—"
        ),
    },
  ];

  const activeAccountsForParentSelect = accounts.filter((account) => account.status !== "inactive");

  return (
    <div className="flex flex-col gap-6">
      <div>
        <h1 className="text-xl font-semibold text-text-primary">Chart of Accounts</h1>
        <p className="text-sm text-text-secondary">Canonical account master -- type, normal balance, hierarchy, and posting eligibility. Carries no balance; posting/balance capture is a later Finance capability.</p>
      </div>

      <nav aria-label="Account status filter" className="flex flex-wrap gap-1 border-b border-neutral-200">
        {STATUS_FILTERS.map((filter) => {
          const active = filter.value === selectedStatus;
          return (
            <Link
              key={filter.value}
              href={`/${tenantSlug}/finance/chart-of-accounts${filter.value === "all" ? "" : `?status=${filter.value}`}`}
              aria-current={active ? "page" : undefined}
              className={`border-b-2 px-3 py-2 text-sm font-medium ${active ? "border-primary text-primary" : "border-transparent text-text-secondary hover:text-text-primary"}`}
            >
              {filter.label}
            </Link>
          );
        })}
      </nav>

      {loadFailed ? (
        <ErrorState description="Something went wrong loading the Chart of Accounts. Please try again." />
      ) : sortedAccounts.length === 0 ? (
        <EmptyState title="No accounts yet" description="Create the first account below." />
      ) : (
        <DataTable caption="Chart of Accounts" columns={columns} rows={sortedAccounts} rowKey={(account) => account.id} emptyMessage="No accounts match this filter." />
      )}

      <CreateFinanceAccountForm action={createFinanceAccountDraftAction.bind(null, tenantSlug)} parentCandidates={activeAccountsForParentSelect} />
    </div>
  );
}
