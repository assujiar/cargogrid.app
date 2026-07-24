import { createSupabaseServiceRoleClient } from "../../../../lib/supabase/service-role.ts";
import { getQuotationForCustomerDecision, QuotationAcceptanceQueryError } from "../../../../server/queries/quotation-acceptance.ts";
import { DecisionForm } from "./decision-form.tsx";

const TOKEN_STATUS_MESSAGE: Record<string, string> = {
  consumed: "A decision has already been recorded for this quotation.",
  revoked: "This link is no longer valid. Please contact your sales representative for a new one.",
  expired: "This link has expired. Please contact your sales representative for a new one.",
};

/**
 * Public customer decision page (COM-154, CG-S7-COM-013, Prompt 154 §15: "customer
 * decision surface with exact quote version, terms, expiry, explicit consent and
 * complete states"). Deliberately outside every tenant-authenticated portal guard
 * (`app/(public)/`, the same route group `app/(public)/login/` already established,
 * PLT-135/136) -- the customer holds no CargoGrid account. Reads via a service-role
 * client (no `auth.uid()` session exists here to key RLS off of) and the one
 * `app.get_quotation_for_customer_decision` RPC, which never raises for an
 * expired/revoked/consumed token -- only a genuinely unknown token does, rendered below
 * as "link not found" rather than a crash.
 */
export default async function QuoteDecisionPage({ params }: { params: Promise<{ token: string }> }) {
  const { token } = await params;
  const client = createSupabaseServiceRoleClient();

  let view;
  try {
    view = await getQuotationForCustomerDecision(client, { rawToken: token });
  } catch (error) {
    if (!(error instanceof QuotationAcceptanceQueryError)) {
      throw error;
    }
    return (
      <main className="mx-auto flex min-h-screen max-w-md flex-col items-center justify-center gap-3 px-4 text-center">
        <h1 className="text-xl font-semibold text-neutral-900">Link not found</h1>
        <p className="text-sm text-neutral-600">This link doesn&apos;t match any quotation. Please check the link or contact your sales representative.</p>
      </main>
    );
  }

  const statusMessage = view.tokenStatus === "active" ? null : (TOKEN_STATUS_MESSAGE[view.tokenStatus] ?? "This link is no longer valid.");

  return (
    <main className="mx-auto flex min-h-screen max-w-2xl flex-col gap-6 px-4 py-10">
      <h1 className="text-xl font-semibold text-neutral-900">Quotation {view.quoteNumber}</h1>

      <dl className="grid grid-cols-2 gap-x-6 gap-y-2 text-sm">
        <dt className="font-medium text-neutral-600">Customer</dt>
        <dd className="text-neutral-900">{typeof view.customerSnapshot.legal_name === "string" ? view.customerSnapshot.legal_name : "—"}</dd>
        <dt className="font-medium text-neutral-600">Valid until</dt>
        <dd className="text-neutral-900">{new Date(view.validityTo).toLocaleDateString()}</dd>
        <dt className="font-medium text-neutral-600">Total</dt>
        <dd className="text-neutral-900">{view.totalAmount !== null ? `${view.totalAmount} ${view.currency}` : "—"}</dd>
        {typeof view.terms.payment_terms === "string" ? (
          <>
            <dt className="font-medium text-neutral-600">Payment terms</dt>
            <dd className="text-neutral-900">{view.terms.payment_terms}</dd>
          </>
        ) : null}
        {typeof view.terms.incoterm === "string" ? (
          <>
            <dt className="font-medium text-neutral-600">Incoterm</dt>
            <dd className="text-neutral-900">{view.terms.incoterm}</dd>
          </>
        ) : null}
      </dl>

      {view.alreadyDecided ? (
        <p role="status" className="rounded-md border border-neutral-200 p-4 text-sm text-neutral-900">
          A decision has already been recorded for this quotation.
        </p>
      ) : statusMessage ? (
        <p role="alert" className="rounded-md border border-neutral-200 p-4 text-sm text-neutral-900">
          {statusMessage}
        </p>
      ) : (
        <DecisionForm rawToken={token} />
      )}
    </main>
  );
}
