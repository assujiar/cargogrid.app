import { notFound } from "next/navigation";
import { resolveCommercialAccessForRequest } from "../../../../../lib/portal/resolve-commercial-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { listAccounts, AccountQueryError } from "../../../../../server/queries/account.ts";
import type { Account } from "../../../../../server/contracts/account/account.ts";

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

  return (
    <div className="flex flex-col gap-6">
      <h1 className="text-xl font-semibold text-neutral-900">Accounts</h1>

      {loadFailed ? (
        <div role="alert" className="flex flex-col gap-2">
          <p className="text-sm text-danger">Something went wrong loading accounts. Please try again.</p>
        </div>
      ) : accounts.length === 0 ? (
        <p className="text-sm text-neutral-600">No accounts yet. Converting an accepted quotation creates the first one.</p>
      ) : (
        <table className="w-full border-collapse text-sm">
          <thead>
            <tr className="border-b border-neutral-200 text-left text-neutral-600">
              <th scope="col" className="py-2 pr-4 font-medium">
                Legal name
              </th>
              <th scope="col" className="py-2 pr-4 font-medium">
                Trade name
              </th>
              <th scope="col" className="py-2 pr-4 font-medium">
                Customer status
              </th>
              <th scope="col" className="py-2 font-medium">
                Status
              </th>
            </tr>
          </thead>
          <tbody>
            {accounts.map((account) => (
              <tr key={account.id} className="border-b border-neutral-100">
                <td className="py-2 pr-4 text-neutral-900">
                  <a href={`/${tenantSlug}/commercial/accounts/${account.id}`} className="font-medium text-primary underline">
                    {account.legalName}
                  </a>
                </td>
                <td className="py-2 pr-4 text-neutral-600">{account.tradeName ?? "—"}</td>
                <td className="py-2 pr-4 text-neutral-600">{account.customerStatus}</td>
                <td className="py-2 text-neutral-600">{account.status}</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </div>
  );
}
