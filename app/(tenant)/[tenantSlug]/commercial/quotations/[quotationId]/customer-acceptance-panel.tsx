import type { Quotation } from "../../../../../../server/contracts/quotation/quotation.ts";
import type { QuotationAcceptanceToken } from "../../../../../../server/contracts/quotation/quotation-acceptance.ts";
import { SendAcceptanceForm } from "./send-acceptance-form.tsx";
import { revokeQuotationAcceptanceTokenAction } from "./actions.ts";

/**
 * Customer Acceptance panel (COM-154, CG-S7-COM-013, Prompt 154 §15: "send confirmation/
 * status"). Renders only for an acceptance-eligible quotation (status=submitted,
 * approvalStatus approved/not_required, isCurrent) or one that already carries send/
 * decision history -- a draft or superseded version has nothing to show here. The
 * customer's own decision surface is the separate public `/quote-decision/[token]` route
 * (app/(public)/), never rendered inside this authenticated portal.
 */
export function CustomerAcceptancePanel({
  tenantSlug,
  quotation,
  tokens,
  contacts,
}: {
  tenantSlug: string;
  quotation: Quotation;
  tokens: QuotationAcceptanceToken[];
  contacts: readonly { id: string; fullName: string; email: string | null }[];
}) {
  const eligible = quotation.status === "submitted" && quotation.isCurrent && (quotation.approvalStatus === "approved" || quotation.approvalStatus === "not_required") && quotation.customerDecision === null;

  if (!eligible && tokens.length === 0 && quotation.customerDecision === null) {
    return null;
  }

  const activeToken = tokens.find((token) => token.status === "active") ?? null;

  return (
    <div className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
      <h2 className="text-sm font-semibold text-neutral-900">Customer acceptance</h2>

      {quotation.customerDecision ? (
        <p className="text-sm text-neutral-900">
          Customer decision: <span className="font-medium">{quotation.customerDecision}</span>
          {quotation.customerDecisionAt ? ` on ${new Date(quotation.customerDecisionAt).toLocaleString()}` : ""}
        </p>
      ) : null}

      {tokens.length > 0 ? (
        <div className="flex flex-col gap-1">
          <h3 className="text-xs font-semibold uppercase tracking-wide text-neutral-500">Send history</h3>
          <table className="w-full border-collapse text-sm">
            <thead>
              <tr className="border-b border-neutral-200 text-left text-neutral-600">
                <th scope="col" className="py-2 pr-4 font-medium">
                  Sent
                </th>
                <th scope="col" className="py-2 pr-4 font-medium">
                  Channel
                </th>
                <th scope="col" className="py-2 pr-4 font-medium">
                  Status
                </th>
                <th scope="col" className="py-2 pr-4 font-medium">
                  Expires
                </th>
                <th scope="col" className="py-2 font-medium">
                  Action
                </th>
              </tr>
            </thead>
            <tbody>
              {tokens.map((token) => (
                <tr key={token.id} className="border-b border-neutral-100">
                  <td className="py-2 pr-4 text-neutral-900">{new Date(token.sentAt).toLocaleString()}</td>
                  <td className="py-2 pr-4 text-neutral-600">{token.channel}</td>
                  <td className="py-2 pr-4 text-neutral-600">{token.status}</td>
                  <td className="py-2 pr-4 text-neutral-600">{new Date(token.expiresAt).toLocaleString()}</td>
                  <td className="py-2 text-neutral-600">
                    {token.status === "active" ? (
                      <form action={revokeQuotationAcceptanceTokenAction.bind(null, tenantSlug, quotation.id, token.id, "Revoked by sender")}>
                        <button type="submit" className="text-sm font-medium text-danger underline">
                          Revoke
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
        </div>
      ) : null}

      {eligible ? <SendAcceptanceForm tenantSlug={tenantSlug} quotationId={quotation.id} hasActiveToken={activeToken !== null} contacts={contacts} /> : null}
    </div>
  );
}
