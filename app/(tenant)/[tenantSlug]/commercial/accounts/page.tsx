import { notFound } from "next/navigation";
import { resolveCommercialAccessForRequest } from "../../../../../lib/portal/resolve-commercial-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { listAccounts, AccountQueryError } from "../../../../../server/queries/account.ts";
import type { Account } from "../../../../../server/contracts/account/account.ts";
import { DataTable, type DataTableColumn } from "../../../../../components/tables/data-table.tsx";
import { StatusBadge } from "../../../../../components/ui/status-badge.tsx";
import { ACCOUNT_STATUS_TONE_MAP, CUSTOMER_STATUS_TONE_MAP } from "../../../../../components/domain/status-tone-map.ts";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";

/**
 * Account list (COM-155, CG-S7-COM-014). Tenant-wide reference data, never record-scoped
 * or field-masked (ADR-0018) -- `app.accounts` is read directly, not through a masking
 * view, and every active tenant member sees every account regardless of who converted it
 * or which team owns it.
 */
export default async function AccountsPage({ params }: { params: Promise<{ tenantSlug: string }> }) {
  const { tenantSlug } = await params;
  const access = await resolveCommercialAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();

  let accounts: Account[];
  let loadFailed = false;
  try {
    accounts = await listAccounts(supabase, access.tenant.id);
  } catch (error) {
    if (!(error instanceof AccountQueryError)) {
      throw error;
    }
    loadFailed = true;
    accounts = [];
  }

  const columns: readonly DataTableColumn<Account>[] = [
    {
      key: "legalName",
      header: "Legal name",
      render: (account) => (
        <a href={`/${tenantSlug}/commercial/accounts/${account.id}`} className="font-medium text-primary underline">
          {account.legalName}
        </a>
      ),
    },
    { key: "tradeName", header: "Trade name", render: (account) => account.tradeName ?? "—" },
    {
      key: "customerStatus",
      header: "Customer status",
      render: (account) => {
        const { tone, label } = CUSTOMER_STATUS_TONE_MAP[account.customerStatus];
        return <StatusBadge tone={tone} label={label} />;
      },
    },
    {
      key: "status",
      header: "Status",
      render: (account) => {
        const { tone, label } = ACCOUNT_STATUS_TONE_MAP[account.status];
        return <StatusBadge tone={tone} label={label} />;
      },
    },
  ];

  return (
    <div className="flex flex-col gap-6">
      <h1 className="text-xl font-semibold text-neutral-900">Accounts</h1>

      {loadFailed ? (
        <ErrorState description="Something went wrong loading accounts. Please try again." />
      ) : (
        <DataTable
          caption="Accounts"
          columns={columns}
          rows={accounts}
          rowKey={(account) => account.id}
          emptyMessage="No accounts yet. Converting an accepted quotation creates the first one."
        />
      )}
    </div>
  );
}
