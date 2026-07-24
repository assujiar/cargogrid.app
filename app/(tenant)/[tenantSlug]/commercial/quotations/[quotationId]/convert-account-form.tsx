"use client";

import { useActionState } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import { convertQuotationToAccountAction, type ConvertQuotationToAccountState } from "./actions.ts";
import type { Account } from "../../../../../../server/contracts/account/account.ts";

const INITIAL_STATE: ConvertQuotationToAccountState = { error: null, accountId: null };

/** COM-155: one action, two shapes -- "create a new account" (no selection) or "link to an existing one" (radio-selected from the duplicate candidates surfaced by app.get_account_conversion_readiness), the same "one mechanism, choice narrows behavior" precedent SendAcceptanceForm (COM-154) already established. */
export function ConvertAccountForm({
  tenantSlug,
  quotationId,
  duplicateCandidates,
}: {
  tenantSlug: string;
  quotationId: string;
  duplicateCandidates: readonly Account[];
}) {
  const [state, formAction, pending] = useActionState(
    async (prevState: ConvertQuotationToAccountState, formData: FormData) => {
      const targetAccountId = String(formData.get("targetAccountId") ?? "").trim() || null;
      const parentAccountId = String(formData.get("parentAccountId") ?? "").trim() || null;
      return convertQuotationToAccountAction(tenantSlug, quotationId, targetAccountId, parentAccountId, prevState, formData);
    },
    INITIAL_STATE,
  );

  return (
    <form action={formAction} className="flex flex-col gap-3" noValidate>
      {duplicateCandidates.length > 0 ? (
        <div className="flex flex-col gap-1">
          <span className="text-sm font-medium text-neutral-700">Possible existing match</span>
          <p className="text-xs text-neutral-500">This customer&apos;s legal identity may already exist. Choose one to link instead of creating a duplicate, or leave unselected to create a new account.</p>
          <div className="flex flex-col gap-1">
            <label className="flex items-center gap-2 text-sm text-neutral-900">
              <input type="radio" name="targetAccountId" value="" defaultChecked />
              Create a new account
            </label>
            {duplicateCandidates.map((candidate) => (
              <label key={candidate.id} className="flex items-center gap-2 text-sm text-neutral-900">
                <input type="radio" name="targetAccountId" value={candidate.id} />
                {candidate.legalName}
                {candidate.taxId ? ` (${candidate.taxId})` : ""}
              </label>
            ))}
          </div>
        </div>
      ) : null}

      <div className="flex flex-col gap-1">
        <label htmlFor="parentAccountId" className="text-sm font-medium text-neutral-700">
          Parent account ID (optional)
        </label>
        <input
          id="parentAccountId"
          name="parentAccountId"
          type="text"
          placeholder="Only used when creating a new account"
          className="w-96 rounded-md border border-neutral-300 px-3 py-2 text-sm"
        />
      </div>

      {state.error ? (
        <p role="alert" className="text-sm text-danger">
          {state.error}
        </p>
      ) : null}

      <Button type="submit" loading={pending} loadingLabel="Converting…" className="w-fit">
        Convert to account
      </Button>
    </form>
  );
}
