import type { Quotation } from "../../../../../../server/contracts/quotation/quotation.ts";
import type { Account, AccountConversionReadiness } from "../../../../../../server/contracts/account/account.ts";
import type { AccountConversionRecord } from "../../../../../../server/queries/account.ts";
import { ConvertAccountForm } from "./convert-account-form.tsx";

/**
 * Customer and Account Conversion panel (COM-155, CG-S7-COM-014). Renders only for a
 * quotation the customer has accepted -- before that, conversion is not offered at all
 * (matching `app.get_account_conversion_readiness`'s own `quotation_not_accepted` reason,
 * restated here only for UI affordance). Once converted, shows the resulting account
 * (created or linked) with a direct link -- the conversion form never reappears for an
 * already-converted quotation, matching `app.convert_quotation_to_account`'s own
 * idempotent-on-quotationId posture.
 */
export function AccountConversionPanel({
  tenantSlug,
  quotation,
  existingConversion,
  readiness,
  duplicateCandidates,
}: {
  tenantSlug: string;
  quotation: Quotation;
  existingConversion: AccountConversionRecord | null;
  readiness: AccountConversionReadiness | null;
  duplicateCandidates: readonly Account[];
}) {
  if (quotation.customerDecision !== "accepted") {
    return null;
  }

  return (
    <div className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
      <h2 className="text-sm font-semibold text-neutral-900">Customer and account conversion</h2>

      {existingConversion ? (
        <p className="text-sm text-neutral-900">
          {existingConversion.outcome === "created" ? "A new account was created from this quotation: " : "This quotation was linked to an existing account: "}
          <a href={`/${tenantSlug}/commercial/accounts/${existingConversion.accountId}`} className="font-medium text-primary underline">
            View account
          </a>
        </p>
      ) : readiness && !readiness.ready ? (
        <p className="text-sm text-neutral-600">Not ready to convert: {readiness.blockingReasons.join(", ")}</p>
      ) : (
        <ConvertAccountForm tenantSlug={tenantSlug} quotationId={quotation.id} duplicateCandidates={duplicateCandidates} />
      )}
    </div>
  );
}
