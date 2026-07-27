import { notFound } from "next/navigation";
import { resolveCommercialAccessForRequest } from "../../../../../lib/portal/resolve-commercial-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { listCustomerContracts, ContractQueryError } from "../../../../../server/queries/contract.ts";
import type { CustomerContract } from "../../../../../server/contracts/contract/contract.ts";
import { DataTable, type DataTableColumn } from "../../../../../components/tables/data-table.tsx";
import { StatusBadge } from "../../../../../components/ui/status-badge.tsx";
import { CUSTOMER_CONTRACT_STATUS_TONE_MAP } from "../../../../../components/domain/status-tone-map.ts";

/**
 * Customer contract list (COM-156, CG-S7-COM-015). Tenant-wide reference data, never
 * record-scoped (mirrors app.accounts, COM-155) -- every version of every contract is
 * shown; the detail page groups versions by root_contract_id.
 */
export default async function ContractsPage({ params }: { params: Promise<{ tenantSlug: string }> }) {
  const { tenantSlug } = await params;
  const access = await resolveCommercialAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();

  let contracts: CustomerContract[];
  let loadFailed = false;
  try {
    contracts = await listCustomerContracts(supabase, access.tenant.id);
  } catch (error) {
    if (!(error instanceof ContractQueryError)) {
      throw error;
    }
    loadFailed = true;
    contracts = [];
  }

  const columns: readonly DataTableColumn<CustomerContract>[] = [
    {
      key: "version",
      header: "Version",
      render: (contract) => (
        <a href={`/${tenantSlug}/commercial/contracts/${contract.id}`} className="font-medium text-primary underline">
          v{contract.versionNumber}
        </a>
      ),
    },
    {
      key: "status",
      header: "Status",
      render: (contract) => {
        const { tone, label } = CUSTOMER_CONTRACT_STATUS_TONE_MAP[contract.status];
        return <StatusBadge tone={tone} label={label} />;
      },
    },
    { key: "effectiveFrom", header: "Effective from", render: (contract) => new Date(contract.effectiveFrom).toLocaleDateString() },
    { key: "effectiveTo", header: "Effective to", render: (contract) => (contract.effectiveTo ? new Date(contract.effectiveTo).toLocaleDateString() : "—") },
  ];

  return (
    <div className="flex flex-col gap-6">
      <h1 className="text-xl font-semibold text-neutral-900">Contracts</h1>

      {loadFailed ? (
        <div role="alert" className="flex flex-col gap-2">
          <p className="text-sm text-danger">Something went wrong loading contracts. Please try again.</p>
        </div>
      ) : (
        <DataTable
          caption="Contracts"
          columns={columns}
          rows={contracts}
          rowKey={(contract) => contract.id}
          emptyMessage="No contracts yet. Creating one from an accepted, converted quotation starts the first version."
        />
      )}
    </div>
  );
}
