import { notFound } from "next/navigation";
import { resolveCommercialAccessForRequest } from "../../../../../../lib/portal/resolve-commercial-access.server.ts";
import { createSupabaseServerClient } from "../../../../../../lib/supabase/server.ts";
import { getAccountById, listAccounts, AccountQueryError } from "../../../../../../server/queries/account.ts";

/**
 * Account detail (COM-155, CG-S7-COM-014). Read-only in this bounded slice -- no
 * account-editing RPC exists yet beyond `app.convert_quotation_to_account` itself (which
 * only creates or links, never edits an existing account's own fields). Shows the
 * parent/subsidiary link both directions (this account's own parent, and any accounts
 * that name this one as their parent).
 */
export default async function AccountDetailPage({ params }: { params: Promise<{ tenantSlug: string; accountId: string }> }) {
  const { tenantSlug, accountId } = await params;
  const access = await resolveCommercialAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();

  let account;
  try {
    account = await getAccountById(supabase, accountId);
  } catch (error) {
    if (!(error instanceof AccountQueryError)) {
      throw error;
    }
    return (
      <div role="alert" className="flex flex-col gap-2">
        <p className="text-sm text-danger">Something went wrong loading this account. Please try again.</p>
      </div>
    );
  }

  if (!account || account.tenantId !== access.tenant.id) {
    notFound();
  }

  const allAccounts = await listAccounts(supabase, access.tenant.id);
  const parent = account.parentAccountId ? (allAccounts.find((candidate) => candidate.id === account.parentAccountId) ?? null) : null;
  const subsidiaries = allAccounts.filter((candidate) => candidate.parentAccountId === account.id);

  return (
    <div className="flex flex-col gap-6">
      <h1 className="text-xl font-semibold text-neutral-900">{account.legalName}</h1>

      <dl className="grid grid-cols-2 gap-x-6 gap-y-2 text-sm">
        <dt className="font-medium text-neutral-600">Trade name</dt>
        <dd className="text-neutral-900">{account.tradeName ?? "—"}</dd>
        <dt className="font-medium text-neutral-600">Tax ID</dt>
        <dd className="text-neutral-900">{account.taxId ?? "—"}</dd>
        <dt className="font-medium text-neutral-600">Customer status</dt>
        <dd className="text-neutral-900">{account.customerStatus}</dd>
        <dt className="font-medium text-neutral-600">Status</dt>
        <dd className="text-neutral-900">{account.status}</dd>
        {typeof account.billingAddress.city === "string" ? (
          <>
            <dt className="font-medium text-neutral-600">Billing city</dt>
            <dd className="text-neutral-900">{account.billingAddress.city}</dd>
          </>
        ) : null}
        {parent ? (
          <>
            <dt className="font-medium text-neutral-600">Parent account</dt>
            <dd className="text-neutral-900">
              <a href={`/${tenantSlug}/commercial/accounts/${parent.id}`} className="font-medium text-primary underline">
                {parent.legalName}
              </a>
            </dd>
          </>
        ) : null}
      </dl>

      {subsidiaries.length > 0 ? (
        <div className="rounded-md border border-neutral-200 p-4">
          <h2 className="text-sm font-semibold text-neutral-900">Subsidiaries</h2>
          <ul className="mt-2 flex flex-col gap-1 text-sm">
            {subsidiaries.map((subsidiary) => (
              <li key={subsidiary.id}>
                <a href={`/${tenantSlug}/commercial/accounts/${subsidiary.id}`} className="font-medium text-primary underline">
                  {subsidiary.legalName}
                </a>
              </li>
            ))}
          </ul>
        </div>
      ) : null}
    </div>
  );
}
