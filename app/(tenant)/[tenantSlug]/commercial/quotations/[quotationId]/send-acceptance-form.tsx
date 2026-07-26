"use client";

import { useActionState } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import { sendQuotationForAcceptanceAction, type SendQuotationForAcceptanceState } from "./actions.ts";

const INITIAL_STATE: SendQuotationForAcceptanceState = { error: null, rawToken: null };

/** COM-154: send/resend, one action (server/mutations/quotation-acceptance.ts's own header) -- the label switches depending on whether an active token already exists, the same "one mechanism, label switches by state" precedent RevisionForm (COM-152) already established. The raw link is shown exactly once, right here, immediately after a successful send -- it is never retrievable again (not stored anywhere, only its hash is). */
export function SendAcceptanceForm({
  tenantSlug,
  quotationId,
  hasActiveToken,
  contacts,
}: {
  tenantSlug: string;
  quotationId: string;
  hasActiveToken: boolean;
  contacts: readonly { id: string; fullName: string; email: string | null }[];
}) {
  const [state, formAction, pending] = useActionState(
    async (prevState: SendQuotationForAcceptanceState, formData: FormData) => {
      const recipientContactId = String(formData.get("recipientContactId") ?? "").trim() || null;
      const channel = (String(formData.get("channel") ?? "email").trim() || "email") as "email" | "manual_link";
      return sendQuotationForAcceptanceAction(tenantSlug, quotationId, recipientContactId, channel, prevState, formData);
    },
    INITIAL_STATE,
  );

  return (
    <div className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
      <h2 className="text-sm font-semibold text-neutral-900">{hasActiveToken ? "Resend for acceptance" : "Send for acceptance"}</h2>
      <p className="text-xs text-neutral-500">Generates a secure, single-use link the customer can use to accept or reject this exact quotation version -- no customer login required.</p>

      <form action={formAction} className="flex flex-col gap-3" noValidate>
        <div className="flex flex-col gap-1">
          <label htmlFor="recipientContactId" className="text-sm font-medium text-neutral-700">
            Recipient contact (optional)
          </label>
          <select id="recipientContactId" name="recipientContactId" defaultValue="" className="w-64 rounded-md border border-neutral-300 px-3 py-2 text-sm">
            <option value="">— None —</option>
            {contacts.map((contact) => (
              <option key={contact.id} value={contact.id}>
                {contact.fullName}
                {contact.email ? ` (${contact.email})` : ""}
              </option>
            ))}
          </select>
        </div>

        <div className="flex flex-col gap-1">
          <label htmlFor="channel" className="text-sm font-medium text-neutral-700">
            Channel
          </label>
          <select id="channel" name="channel" defaultValue="email" className="w-48 rounded-md border border-neutral-300 px-3 py-2 text-sm">
            <option value="email">Email</option>
            <option value="manual_link">Manual link</option>
          </select>
        </div>

        {state.error ? (
          <p role="alert" className="text-sm text-danger">
            {state.error}
          </p>
        ) : null}

        <Button type="submit" loading={pending} loadingLabel="Sending…">
          {hasActiveToken ? "Resend (revokes the current link)" : "Send"}
        </Button>
      </form>

      {state.rawToken ? (
        <div role="status" className="flex flex-col gap-1 rounded-md border border-primary/30 bg-primary/5 p-3">
          <p className="text-sm font-medium text-neutral-900">Share this link with the customer now -- it will not be shown again.</p>
          <a href={`/quote-decision/${state.rawToken}`} target="_blank" rel="noreferrer" className="break-all text-sm text-primary underline">
            {`/quote-decision/${state.rawToken}`}
          </a>
        </div>
      ) : null}
    </div>
  );
}
