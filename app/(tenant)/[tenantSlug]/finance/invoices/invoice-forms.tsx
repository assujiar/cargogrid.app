"use client";

/** Customer Invoice client forms (FIN-197, CG-S9-FIN-008). Same `useActionState`/bound-action split every prior capability's own forms already use. */

import { useActionState, useId } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
import { FormField } from "../../../../../components/forms/form-field.tsx";
import { Input } from "../../../../../components/forms/input.tsx";
import { Select } from "../../../../../components/forms/select.tsx";
import { ValidationMessage } from "../../../../../components/forms/validation-message.tsx";
import type { FinanceInvoiceFormState } from "./actions.ts";

const INITIAL_STATE: FinanceInvoiceFormState = { error: null };

/**
 * CG-AUDIT-2026-09-02 B5: the seeded baseline finance_tax_codes -- a known, static, small
 * option list (the exact shape Select's own header comment calls for), never free text
 * (finance_tax_codes.tax_type distinguishes PPN's own added-tax treatment from PPH21/
 * PPH23/PPH4_2's own withheld-not-billed treatment; a typo here previously just failed
 * later with a rejected/unresolvable code).
 */
const TAX_CODE_OPTIONS = [
  { code: "PPN", label: "PPN (11% VAT, added to the invoice)" },
  { code: "PPH21", label: "PPh 21 (withholding, deducted -- employee income)" },
  { code: "PPH23", label: "PPh 23 (withholding, deducted -- services/royalties/rent)" },
  { code: "PPH4_2", label: "PPh 4(2) (final withholding, deducted)" },
] as const;

type BoundAction = (prevState: FinanceInvoiceFormState, formData: FormData) => Promise<FinanceInvoiceFormState>;

/**
 * CG-AUDIT-2026-09-02 B7 (worklist half): one instance renders per billable
 * readiness handoff row (the worklist table this session added to
 * `page.tsx`) -- `billingReadinessHandoffId` is now bound into the action
 * itself, never a hand-typed field, closing "Invoicing is driven by a
 * hand-copied UUID."
 */
export function PrepareFinanceInvoiceFromReadinessForm({ action }: { action: BoundAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  const paymentTermDaysId = `paymentTermDays-${useId()}`;
  const taxCodeId = `taxCode-${useId()}`;

  return (
    <form action={formAction} className="flex flex-wrap items-end gap-2" noValidate>
      <div className="w-24">
        <FormField id={paymentTermDaysId} label="Term (days)">
          <Input id={paymentTermDaysId} name="paymentTermDays" type="number" min="0" defaultValue={30} invalid={Boolean(state.error)} />
        </FormField>
      </div>

      <div className="w-56">
        <FormField id={taxCodeId} label="Tax code">
          <Select id={taxCodeId} name="taxCode" defaultValue="" invalid={Boolean(state.error)}>
            <option value="">No tax</option>
            {TAX_CODE_OPTIONS.map((option) => (
              <option key={option.code} value={option.code}>
                {option.label}
              </option>
            ))}
          </Select>
        </FormField>
      </div>

      <Button type="submit" loading={pending} loadingLabel="Preparing…" className="w-fit">
        Prepare invoice
      </Button>

      {state.error ? (
        <div className="w-full">
          <ValidationMessage>{state.error}</ValidationMessage>
        </div>
      ) : null}
    </form>
  );
}

export function SubmitFinanceInvoiceForApprovalForm({ action }: { action: BoundAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col gap-1" noValidate>
      {state.error ? <ValidationMessage>{state.error}</ValidationMessage> : null}
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Submitting…">
        Submit
      </Button>
    </form>
  );
}

export function DiscardFinanceInvoiceDraftForm({ action }: { action: BoundAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col gap-1" noValidate>
      <label htmlFor="discard-invoice-reason" className="sr-only">
        Reason
      </label>
      <Input id="discard-invoice-reason" name="reason" type="text" placeholder="Reason (optional)" className="w-40 text-xs" invalid={Boolean(state.error)} />
      {state.error ? <ValidationMessage>{state.error}</ValidationMessage> : null}
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Voiding…">
        Discard
      </Button>
    </form>
  );
}

export function ApproveFinanceInvoiceForm({ action }: { action: BoundAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col gap-1" noValidate>
      {state.error ? <ValidationMessage>{state.error}</ValidationMessage> : null}
      <Button type="submit" loading={pending} loadingLabel="Approving…">
        Approve
      </Button>
    </form>
  );
}

export function IssueFinanceInvoiceForm({ action }: { action: BoundAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col gap-1" noValidate>
      <label htmlFor="issue-invoice-date" className="sr-only">
        Issue date
      </label>
      <Input id="issue-invoice-date" name="issueDate" type="date" required className="w-40 text-xs" invalid={Boolean(state.error)} />
      {state.error ? <ValidationMessage>{state.error}</ValidationMessage> : null}
      <Button type="submit" loading={pending} loadingLabel="Issuing…">
        Issue (post to AR)
      </Button>
    </form>
  );
}

/** CG-AUDIT-2026-09-02 B3: one instance renders per already-issued invoice row -- reduces the customer's own AR balance by a real, negative open item, never editing the invoice itself. Mandatory reason, mirroring DiscardFinanceInvoiceDraftForm's own established shape but non-optional here (a credit note with no stated reason is a real audit gap, unlike an optional discard note). */
export function IssueFinanceCreditNoteForm({ action }: { action: BoundAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  const amountId = `credit-note-amount-${useId()}`;
  const reasonId = `credit-note-reason-${useId()}`;
  const creditDateId = `credit-note-date-${useId()}`;

  return (
    <form action={formAction} className="flex flex-col gap-1" noValidate>
      <label htmlFor={amountId} className="sr-only">
        Credit amount
      </label>
      <Input id={amountId} name="amount" type="number" min="0" step="0.01" placeholder="Amount" required className="w-32 text-xs" invalid={Boolean(state.error)} />
      <label htmlFor={reasonId} className="sr-only">
        Reason
      </label>
      <Input id={reasonId} name="reason" type="text" placeholder="Reason (required)" required className="w-40 text-xs" invalid={Boolean(state.error)} />
      <label htmlFor={creditDateId} className="sr-only">
        Credit date
      </label>
      <Input id={creditDateId} name="creditDate" type="date" required className="w-40 text-xs" invalid={Boolean(state.error)} />
      {state.error ? <ValidationMessage>{state.error}</ValidationMessage> : null}
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Issuing…">
        Issue credit note
      </Button>
    </form>
  );
}
