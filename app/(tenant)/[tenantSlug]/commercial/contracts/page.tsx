import { notFound } from "next/navigation";
import { resolveCommercialAccessForRequest } from "../../../../../lib/portal/resolve-commercial-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { listCustomerContracts, ContractQueryError } from "../../../../../server/queries/contract.ts";
import type { CustomerContract } from "../../../../../server/contracts/contract/contract.ts";

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

  return (
    <div className="flex flex-col gap-6">
      <h1 className="text-xl font-semibold text-neutral-900">Contracts</h1>

      {loadFailed ? (
        <div role="alert" className="flex flex-col gap-2">
          <p className="text-sm text-danger">Something went wrong loading contracts. Please try again.</p>
        </div>
      ) : contracts.length === 0 ? (
        <p className="text-sm text-neutral-600">No contracts yet. Creating one from an accepted, converted quotation starts the first version.</p>
      ) : (
        <table className="w-full border-collapse text-sm">
          <thead>
            <tr className="border-b border-neutral-200 text-left text-neutral-600">
              <th scope="col" className="py-2 pr-4 font-medium">
                Version
              </th>
              <th scope="col" className="py-2 pr-4 font-medium">
                Status
              </th>
              <th scope="col" className="py-2 pr-4 font-medium">
                Effective from
              </th>
              <th scope="col" className="py-2 font-medium">
                Effective to
              </th>
            </tr>
          </thead>
          <tbody>
            {contracts.map((contract) => (
              <tr key={contract.id} className="border-b border-neutral-100">
                <td className="py-2 pr-4 text-neutral-900">
                  <a href={`/${tenantSlug}/commercial/contracts/${contract.id}`} className="font-medium text-primary underline">
                    v{contract.versionNumber}
                  </a>
                </td>
                <td className="py-2 pr-4 text-neutral-600">{contract.status}</td>
                <td className="py-2 pr-4 text-neutral-600">{new Date(contract.effectiveFrom).toLocaleDateString()}</td>
                <td className="py-2 text-neutral-600">{contract.effectiveTo ? new Date(contract.effectiveTo).toLocaleDateString() : "—"}</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </div>
  );
}
