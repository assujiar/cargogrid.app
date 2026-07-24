"use client";

import { useActionState } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import { createContractFromQuotationAction, type CreateContractFromQuotationState } from "./actions.ts";

const INITIAL_STATE: CreateContractFromQuotationState = { error: null };

/** COM-156's own main-flow entry point on the quotation page -- mirrors SendAcceptanceForm's (COM-154) useActionState pattern. Redirects to the new contract's own detail page on success (the action itself calls redirect(), never returned as state). */
export function CreateContractForm({ tenantSlug, quotationId }: { tenantSlug: string; quotationId: string }) {
  const [state, formAction, pending] = useActionState(
    async (prevState: CreateContractFromQuotationState, formData: FormData) => {
      const effectiveFrom = String(formData.get("effectiveFrom") ?? "");
      return createContractFromQuotationAction(tenantSlug, quotationId, effectiveFrom ? new Date(effectiveFrom).toISOString() : new Date().toISOString(), prevState, formData);
    },
    INITIAL_STATE,
  );

  return (
    <form action={formAction} className="flex flex-col gap-3" noValidate>
      <div className="flex flex-col gap-1">
        <label htmlFor="effectiveFrom" className="text-sm font-medium text-neutral-700">
          Effective from
        </label>
        <input id="effectiveFrom" name="effectiveFrom" type="date" className="w-48 rounded-md border border-neutral-300 px-3 py-2 text-sm" />
      </div>

      {state.error ? (
        <p role="alert" className="text-sm text-danger">
          {state.error}
        </p>
      ) : null}

      <Button type="submit" loading={pending} loadingLabel="Creating…" className="w-fit">
        Create contract
      </Button>
    </form>
  );
}
