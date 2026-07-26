import { notFound } from "next/navigation";
import { resolveCommercialAccessForRequest } from "../../../../../lib/portal/resolve-commercial-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { listCreditProfileApprovalInboxForActor, getCreditProfileById, CreditQueryError } from "../../../../../server/queries/credit.ts";
import { getAccountById } from "../../../../../server/queries/account.ts";

/**
 * Credit profile approval inbox (COM-157, CG-S7-COM-016, Prompt 157 §16/§26). Mirrors the
 * Quotation Approval inbox (COM-153, commercial/approvals/) exactly, filtered to
 * entity_type=credit_profile requests instead -- a routing list, not a second decision
 * surface. Deciding happens on the Account Detail page's own CreditPanel, where the
 * reauth-freshness gate this capability's own privileged-approver actions require lives.
 */
export default async function CreditApprovalsInboxPage({ params }: { params: Promise<{ tenantSlug: string }> }) {
  const { tenantSlug } = await params;
  const access = await resolveCommercialAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();

  let items: Awaited<ReturnType<typeof listCreditProfileApprovalInboxForActor>>;
  let loadFailed = false;
  try {
    items = await listCreditProfileApprovalInboxForActor(supabase, access.tenant.id, access.authUserId);
  } catch (error) {
    if (!(error instanceof CreditQueryError)) {
      throw error;
    }
    loadFailed = true;
    items = [];
  }

  const profiles = await Promise.all(items.map((item) => getCreditProfileById(supabase, item.creditProfileId)));
  const accounts = await Promise.all(profiles.map((profile) => (profile ? getAccountById(supabase, profile.accountId) : null)));

  return (
    <div className="flex flex-col gap-6">
      <h1 className="text-xl font-semibold text-neutral-900">Credit Approvals</h1>

      {loadFailed ? (
        <div role="alert" className="flex flex-col gap-2">
          <p className="text-sm text-danger">Something went wrong loading your credit approval inbox. Please try again.</p>
        </div>
      ) : (
        <div className="rounded-md border border-neutral-200 p-4">
          <h2 className="text-sm font-semibold text-neutral-900">Waiting on your decision</h2>
          {items.length === 0 ? (
            <p className="mt-2 text-sm text-neutral-600">Nothing is waiting on you right now.</p>
          ) : (
            <table className="mt-2 w-full border-collapse text-sm">
              <thead>
                <tr className="border-b border-neutral-200 text-left text-neutral-600">
                  <th scope="col" className="py-2 pr-4 font-medium">
                    Account
                  </th>
                  <th scope="col" className="py-2 pr-4 font-medium">
                    Step
                  </th>
                  <th scope="col" className="py-2 font-medium">
                    Action
                  </th>
                </tr>
              </thead>
              <tbody>
                {items.map((item, index) => {
                  const account = accounts[index];
                  return (
                    <tr key={item.stepId} className="border-b border-neutral-100">
                      <td className="py-2 pr-4 text-neutral-900">{account?.legalName ?? item.creditProfileId}</td>
                      <td className="py-2 pr-4 text-neutral-600">Step {item.stepOrder}</td>
                      <td className="py-2 text-neutral-600">
                        {account ? (
                          <a href={`/${tenantSlug}/commercial/accounts/${account.id}`} className="text-sm font-medium text-primary underline">
                            Review
                          </a>
                        ) : (
                          "—"
                        )}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          )}
        </div>
      )}
    </div>
  );
}
