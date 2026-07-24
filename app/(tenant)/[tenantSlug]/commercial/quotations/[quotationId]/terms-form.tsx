"use client";

import { useState, useTransition } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import { updateQuotationTermsAction } from "./actions.ts";
import type { Quotation } from "../../../../../../server/contracts/quotation/quotation.ts";
import type { Contact } from "../../../../../../server/contracts/contact/contact.ts";

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

  return (
    <div className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
      <h2 className="text-sm font-semibold text-neutral-900">Terms</h2>

      <div className="flex flex-col gap-1">
        <label htmlFor="contact" className="text-sm font-medium text-neutral-700">
          Contact
        </label>
        <select id="contact" value={contactId} onChange={(e) => setContactId(e.target.value)} className="rounded-md border border-neutral-300 px-3 py-2 text-sm">
          <option value="">None selected</option>
          {contacts.map((contact) => (
            <option key={contact.id} value={contact.id}>
              {contact.fullName}
            </option>
          ))}
        </select>
      </div>

      <div className="flex gap-2">
        <input placeholder="Currency" value={currency} onChange={(e) => setCurrency(e.target.value.toUpperCase())} className="w-28 rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        <input type="datetime-local" value={validityFrom} onChange={(e) => setValidityFrom(e.target.value)} className="rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        <input type="datetime-local" value={validityTo} onChange={(e) => setValidityTo(e.target.value)} className="rounded-md border border-neutral-300 px-3 py-2 text-sm" />
      </div>

      <input placeholder="Payment terms (e.g. Net 30)" value={paymentTerms} onChange={(e) => setPaymentTerms(e.target.value)} className="rounded-md border border-neutral-300 px-3 py-2 text-sm" />
      <input placeholder="Incoterm (e.g. FOB)" value={incoterm} onChange={(e) => setIncoterm(e.target.value)} className="rounded-md border border-neutral-300 px-3 py-2 text-sm" />
      <textarea placeholder="Notes" value={notes} onChange={(e) => setNotes(e.target.value)} className="rounded-md border border-neutral-300 px-3 py-2 text-sm" rows={2} />

      {error ? (
        <p role="alert" className="text-sm text-danger">
          {error}
        </p>
      ) : null}

      <Button
        type="button"
        variant="secondary"
        disabled={quotation.status !== "draft" || !/^[A-Z]{3}$/.test(currency)}
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
