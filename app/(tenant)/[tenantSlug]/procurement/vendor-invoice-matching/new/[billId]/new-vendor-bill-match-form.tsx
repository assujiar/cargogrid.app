"use client";

import { useActionState } from "react";
import { Button } from "../../../../../../../components/ui/button.tsx";
import { Input } from "../../../../../../../components/forms/input.tsx";
import { FormField } from "../../../../../../../components/forms/form-field.tsx";
import { Checkbox } from "../../../../../../../components/forms/checkbox.tsx";
import { ValidationMessage } from "../../../../../../../components/forms/validation-message.tsx";
import type { FinanceVendorBillLine } from "../../../../../../../server/contracts/vendor-bill/vendor-bill.ts";
import type { NewVendorBillMatchActionState } from "./actions.ts";

const INITIAL_STATE: NewVendorBillMatchActionState = { error: null };

export function NewVendorBillMatchForm({
  lines,
  action,
}: {
  lines: readonly FinanceVendorBillLine[];
  action: (prevState: NewVendorBillMatchActionState, formData: FormData) => Promise<NewVendorBillMatchActionState>;
}) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);

  return (
    <form action={formAction} className="flex flex-col gap-4" noValidate>
      <div className="grid grid-cols-1 gap-2 sm:grid-cols-3">
        <FormField id="purchaseOrderId" label={<span className="text-xs font-medium text-neutral-700">Purchase order id (optional -- three-way match)</span>}>
          <Input id="purchaseOrderId" name="purchaseOrderId" placeholder="Leave blank for non-PO / contract-based match" />
        </FormField>
        <Checkbox id="isPartialInvoice" name="isPartialInvoice" label="Partial invoice" />
        <Checkbox id="isConsolidatedInvoice" name="isConsolidatedInvoice" label="Consolidated invoice" />
      </div>

      <div className="overflow-x-auto rounded-md border border-neutral-200">
        <table className="w-full text-sm">
          <thead className="bg-neutral-50 text-left text-xs font-medium uppercase text-neutral-500">
            <tr>
              <th className="px-3 py-2">Line</th>
              <th className="px-3 py-2">Type</th>
              <th className="px-3 py-2">Description</th>
              <th className="px-3 py-2">Vendor qty</th>
              <th className="px-3 py-2">Vendor UOM</th>
              <th className="px-3 py-2">Vendor rate</th>
              <th className="px-3 py-2">Vendor amount (required)</th>
            </tr>
          </thead>
          <tbody>
            {lines.map((line) => (
              <tr key={line.id} className="border-t border-neutral-200">
                <td className="px-3 py-2 text-neutral-700">{line.lineNumber}</td>
                <td className="px-3 py-2 text-neutral-700">{line.lineType}</td>
                <td className="px-3 py-2 text-neutral-700">{line.description}</td>
                <td className="px-3 py-2">
                  <Input name={`quantity_${line.id}`} type="number" step="0.0001" className="w-24" />
                </td>
                <td className="px-3 py-2">
                  <Input name={`uom_${line.id}`} className="w-20" />
                </td>
                <td className="px-3 py-2">
                  <Input name={`rate_${line.id}`} type="number" step="0.0001" className="w-24" />
                </td>
                <td className="px-3 py-2">
                  <Input name={`amount_${line.id}`} type="number" step="0.01" required className="w-28" />
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {state.error ? <ValidationMessage>{state.error}</ValidationMessage> : null}

      <Button type="submit" loading={pending} loadingLabel="Evaluating…" className="w-fit">
        Create match case
      </Button>
    </form>
  );
}
