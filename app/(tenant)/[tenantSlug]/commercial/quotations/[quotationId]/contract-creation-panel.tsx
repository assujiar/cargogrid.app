import type { CustomerContract } from "../../../../../../server/contracts/contract/contract.ts";
import type { AccountConversionRecord } from "../../../../../../server/queries/account.ts";
import { CreateContractForm } from "./create-contract-form.tsx";

/**
 * Contract creation panel (COM-156, CG-S7-COM-015). Renders only once this quotation has
 * both an accepted customer decision and an existing account conversion (COM-155) -- the
 * main flow's own two preconditions (app.create_customer_contract_draft's own
 * quotation_not_accepted / quotation_not_converted checks, restated here for UI
 * affordance). Once a contract has already been sourced from this quotation, shows a
 * link instead of the form again -- one contract root per source quotation, ever.
 */
export function ContractCreationPanel({
  tenantSlug,
  quotationId,
  isAccepted,
  existingConversion,
  existingContract,
}: {
  tenantSlug: string;
  quotationId: string;
  isAccepted: boolean;
  existingConversion: AccountConversionRecord | null;
  existingContract: CustomerContract | null;
}) {
  if (!isAccepted || !existingConversion) {
    return null;
  }

  return (
    <div className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
      <h2 className="text-sm font-semibold text-neutral-900">Customer contract</h2>

      {existingContract ? (
        <p className="text-sm text-neutral-900">
          A contract was already created from this quotation:{" "}
          <a href={`/${tenantSlug}/commercial/contracts/${existingContract.id}`} className="font-medium text-primary underline">
            View contract
          </a>
        </p>
      ) : (
        <CreateContractForm tenantSlug={tenantSlug} quotationId={quotationId} />
      )}
    </div>
  );
}
