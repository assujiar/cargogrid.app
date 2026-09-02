"use client";

import { useState, useTransition } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import { updateQuotationTermsAction } from "./actions.ts";
import type { Quotation } from "../../../../../../server/contracts/quotation/quotation.ts";
import type { Contact } from "../../../../../../server/contracts/contact/contact.ts";
import { Input } from "../../../../../../components/forms/input.tsx";
import { Select } from "../../../../../../components/forms/select.tsx";
import { Textarea } from "../../../../../../components/forms/textarea.tsx";
import { FormField } from "../../../../../../components/forms/form-field.tsx";
import { ValidationMessage } from "../../../../../../components/forms/validation-message.tsx";

/** Terms/currency/validity/contact form (COM-151) -- terms keys are whitelisted server-side (payment_terms/incoterm/notes only); a currency change that would conflict with an existing sourced line's currency is rejected server-side too. */
export function TermsForm({ tenantSlug, quotation, contacts }: { tenantSlug: string; quotation: Quotation; contacts: readonly Contact[] }) {
  const [currency, setCurrency] = useState(quotation.currency);
  const [validityFrom, setValidityFrom] = useState(quotation.validityFrom.slice(0, 16));
  const [validityTo, setValidityTo] = useState(quotation.validityTo.slice(0, 16));
  const [contactId, setContactId] = useState(quotation.contactId ?? "");
  const [paymentTerms, setPaymentTerms] = useState(quotation.terms.paymentTerms ?? "");
  const [incoterm, setIncoterm] = useState(quotation.terms.incoterm ?? "");
  const [notes, setNotes] = useState(quotation.terms.notes ?? "");
  const [error, setError] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();

  const describedBy = error ? "terms-error" : undefined;
  const invalid = Boolean(error);

  return (
    <div className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
      <h2 className="text-sm font-semibold text-neutral-900">Terms</h2>

      <FormField id="contact" label="Contact">
        <Select id="contact" value={contactId} onChange={(e) => setContactId(e.target.value)} invalid={invalid} aria-describedby={describedBy}>
          <option value="">None selected</option>
          {contacts.map((contact) => (
            <option key={contact.id} value={contact.id}>
              {contact.fullName}
            </option>
          ))}
        </Select>
      </FormField>

      <div className="flex gap-2">
        <div className="w-28">
          <FormField id="terms-currency" label={<span className="sr-only">Currency</span>}>
            <Input id="terms-currency" placeholder="Currency" value={currency} onChange={(e) => setCurrency(e.target.value.toUpperCase())} invalid={invalid} aria-describedby={describedBy} />
          </FormField>
        </div>
        <FormField id="terms-validity-from" label={<span className="sr-only">Valid from</span>}>
          <Input id="terms-validity-from" type="datetime-local" value={validityFrom} onChange={(e) => setValidityFrom(e.target.value)} invalid={invalid} aria-describedby={describedBy} />
        </FormField>
        <FormField id="terms-validity-to" label={<span className="sr-only">Valid until</span>}>
          <Input id="terms-validity-to" type="datetime-local" value={validityTo} onChange={(e) => setValidityTo(e.target.value)} invalid={invalid} aria-describedby={describedBy} />
        </FormField>
      </div>

      <FormField id="terms-payment-terms" label={<span className="sr-only">Payment terms</span>}>
        <Input id="terms-payment-terms" placeholder="Payment terms (e.g. Net 30)" value={paymentTerms} onChange={(e) => setPaymentTerms(e.target.value)} invalid={invalid} aria-describedby={describedBy} />
      </FormField>
      <FormField id="terms-incoterm" label={<span className="sr-only">Incoterm</span>}>
        <Input id="terms-incoterm" placeholder="Incoterm (e.g. FOB)" value={incoterm} onChange={(e) => setIncoterm(e.target.value)} invalid={invalid} aria-describedby={describedBy} />
      </FormField>
      <FormField id="terms-notes" label={<span className="sr-only">Notes</span>}>
        <Textarea id="terms-notes" placeholder="Notes" value={notes} onChange={(e) => setNotes(e.target.value)} rows={2} invalid={invalid} aria-describedby={describedBy} />
      </FormField>

      {error ? <ValidationMessage id="terms-error">{error}</ValidationMessage> : null}

      <Button
        type="button"
        variant="secondary"
        disabled={quotation.status !== "draft" || !quotation.isCurrent || !/^[A-Z]{3}$/.test(currency)}
        loading={pending}
        loadingLabel="Saving…"
        onClick={() =>
          startTransition(async () => {
            const result = await updateQuotationTermsAction(
              tenantSlug,
              quotation.id,
              quotation.recordVersion,
              currency,
              new Date(validityFrom).toISOString(),
              new Date(validityTo).toISOString(),
              { paymentTerms: paymentTerms.trim() || undefined, incoterm: incoterm.trim() || undefined, notes: notes.trim() || undefined },
              contactId || null,
            );
            setError(result.error);
          })
        }
      >
        Save terms
      </Button>
    </div>
  );
}
