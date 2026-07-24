import { notFound } from "next/navigation";
import { resolveCommercialAccessForRequest } from "../../../../../../lib/portal/resolve-commercial-access.server.ts";
import { createSupabaseServerClient } from "../../../../../../lib/supabase/server.ts";
import { getCustomerContractById, listCustomerContractVersions, listCustomerContractPriceComponents, ContractQueryError } from "../../../../../../server/queries/contract.ts";
import { getAccountById } from "../../../../../../server/queries/account.ts";
import { removePriceComponentAction, publishContractAction } from "./actions.ts";
import { AddComponentForm } from "./add-component-form.tsx";
import { RenewalForm } from "./renewal-form.tsx";
import { RetireForm } from "./retire-form.tsx";

/**
 * Customer contract detail (COM-156, CG-S7-COM-015). Editing (add/remove price
 * component) is offered only while status=draft; publish is offered on a draft with
 * >=1 component; retire is offered on a published contract; renewal is offered on any
 * non-draft version (published or retired) as the alternative flow's own entry point.
 */
export default async function ContractDetailPage({ params }: { params: Promise<{ tenantSlug: string; contractId: string }> }) {
  const { tenantSlug, contractId } = await params;
  const access = await resolveCommercialAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();

  let contract;
  try {
    contract = await getCustomerContractById(supabase, contractId);
  } catch (error) {
    if (!(error instanceof ContractQueryError)) {
      throw error;
    }
    return (
      <div role="alert" className="flex flex-col gap-2">
        <p className="text-sm text-danger">Something went wrong loading this contract. Please try again.</p>
      </div>
    );
  }

  if (!contract || contract.tenantId !== access.tenant.id) {
    notFound();
  }

  const [components, versions, account] = await Promise.all([
    listCustomerContractPriceComponents(supabase, contract.id),
    listCustomerContractVersions(supabase, contract.rootContractId),
    getAccountById(supabase, contract.accountId),
  ]);

  const editable = contract.status === "draft";

  return (
    <div className="flex flex-col gap-6">
      <h1 className="text-xl font-semibold text-neutral-900">
        Contract v{contract.versionNumber} — {account?.legalName ?? "—"}
      </h1>

      <dl className="grid grid-cols-2 gap-x-6 gap-y-2 text-sm">
        <dt className="font-medium text-neutral-600">Status</dt>
        <dd className="text-neutral-900">{contract.status}</dd>
        <dt className="font-medium text-neutral-600">Account</dt>
        <dd className="text-neutral-900">
          {account ? (
            <a href={`/${tenantSlug}/commercial/accounts/${account.id}`} className="font-medium text-primary underline">
              {account.legalName}
            </a>
          ) : (
            "—"
          )}
        </dd>
        <dt className="font-medium text-neutral-600">Effective from</dt>
        <dd className="text-neutral-900">{new Date(contract.effectiveFrom).toLocaleDateString()}</dd>
        <dt className="font-medium text-neutral-600">Effective to</dt>
        <dd className="text-neutral-900">{contract.effectiveTo ? new Date(contract.effectiveTo).toLocaleDateString() : "Open-ended"}</dd>
        {contract.sourceQuotationId ? (
          <>
            <dt className="font-medium text-neutral-600">Source quotation</dt>
            <dd className="text-neutral-900">
              <a href={`/${tenantSlug}/commercial/quotations/${contract.sourceQuotationId}`} className="font-medium text-primary underline">
                View quotation
              </a>
            </dd>
          </>
        ) : null}
        {contract.amendmentReason ? (
          <>
            <dt className="font-medium text-neutral-600">Amendment reason</dt>
            <dd className="text-neutral-900">{contract.amendmentReason}</dd>
          </>
        ) : null}
        {contract.retiredReason ? (
          <>
            <dt className="font-medium text-neutral-600">Retired reason</dt>
            <dd className="text-neutral-900">{contract.retiredReason}</dd>
          </>
        ) : null}
      </dl>

      <div className="rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Price components</h2>
        {components.length === 0 ? (
          <p className="mt-2 text-sm text-neutral-600">No price components yet.</p>
        ) : (
          <table className="mt-2 w-full border-collapse text-sm">
            <thead>
              <tr className="border-b border-neutral-200 text-left text-neutral-600">
                <th scope="col" className="py-2 pr-4 font-medium">
                  Service
                </th>
                <th scope="col" className="py-2 pr-4 font-medium">
                  Lane
                </th>
                <th scope="col" className="py-2 pr-4 font-medium">
                  Base amount
                </th>
                <th scope="col" className="py-2 pr-4 font-medium">
                  Discount %
                </th>
                <th scope="col" className="py-2 font-medium">
                  Action
                </th>
              </tr>
            </thead>
            <tbody>
              {components.map((component) => (
                <tr key={component.id} className="border-b border-neutral-100">
                  <td className="py-2 pr-4 text-neutral-900">
                    {component.serviceType}
                    {component.mode ? ` (${component.mode})` : ""}
                  </td>
                  <td className="py-2 pr-4 text-neutral-600">
                    {component.originLane ?? "—"} → {component.destinationLane ?? "—"}
                  </td>
                  <td className="py-2 pr-4 text-neutral-600">{component.priceMasked ? "Restricted" : `${component.baseAmount} ${component.currency}`}</td>
                  <td className="py-2 pr-4 text-neutral-600">{component.priceMasked ? "Restricted" : (component.discountPct ?? 0)}</td>
                  <td className="py-2 text-neutral-600">
                    {editable ? (
                      <form action={removePriceComponentAction.bind(null, tenantSlug, contract.id, component.id)}>
                        <button type="submit" className="text-sm font-medium text-danger underline">
                          Remove
                        </button>
                      </form>
                    ) : (
                      "—"
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>

      {editable ? <AddComponentForm tenantSlug={tenantSlug} contractId={contract.id} /> : null}

      {editable ? (
        <form action={publishContractAction.bind(null, tenantSlug, contract.id, contract.recordVersion)}>
          <button type="submit" className="rounded-md bg-primary px-4 py-2 text-sm font-medium text-neutral-50">
            Publish
          </button>
        </form>
      ) : null}

      {contract.status === "published" ? <RetireForm tenantSlug={tenantSlug} contractId={contract.id} expectedVersion={contract.recordVersion} /> : null}

      {contract.status !== "draft" ? <RenewalForm tenantSlug={tenantSlug} sourceContractId={contract.id} /> : null}

      {versions.length > 1 ? (
        <div className="rounded-md border border-neutral-200 p-4">
          <h2 className="text-sm font-semibold text-neutral-900">Version history</h2>
          <ul className="mt-2 flex flex-col gap-1 text-sm">
            {versions.map((version) => (
              <li key={version.id}>
                <a href={`/${tenantSlug}/commercial/contracts/${version.id}`} className="font-medium text-primary underline">
                  v{version.versionNumber}
                </a>{" "}
                — {version.status} {version.id === contract.id ? "(viewing)" : ""}
              </li>
            ))}
          </ul>
        </div>
      ) : null}
    </div>
  );
}
