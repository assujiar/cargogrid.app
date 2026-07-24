import { notFound } from "next/navigation";
import { resolveCommercialAccessForRequest } from "../../../../../../lib/portal/resolve-commercial-access.server.ts";
import { createSupabaseServerClient } from "../../../../../../lib/supabase/server.ts";
import { getQuotationById, listQuotationVersions, listQuotationLines, getQuotationSubmissionReadiness, QuotationQueryError } from "../../../../../../server/queries/quotation.ts";
import { listCostingRequestsForOpportunity } from "../../../../../../server/queries/costing.ts";
import { listMarginCalculationsForRequest } from "../../../../../../server/queries/margin.ts";
import { listContacts } from "../../../../../../server/queries/contact.ts";
import { getQuotationApprovalOverview } from "../../../../../../server/queries/quotation-approval.ts";
import { listQuotationAcceptanceTokens } from "../../../../../../server/queries/quotation-acceptance.ts";
import { diffQuotationVersions } from "../../../../../../server/contracts/quotation/quotation-diff.ts";
import { removeQuotationLineAction } from "./actions.ts";
import { AddLineForm } from "./add-line-form.tsx";
import { TermsForm } from "./terms-form.tsx";
import { SubmitAndCloneActions } from "./submit-and-clone-actions.tsx";
import { VersionHistory } from "./version-history.tsx";
import { RevisionForm } from "./revision-form.tsx";
import { ComparisonPanel } from "./comparison-panel.tsx";
import { ApprovalPanel } from "./approval-panel.tsx";
import { CustomerAcceptancePanel } from "./customer-acceptance-panel.tsx";
import type { MarginCalculation } from "../../../../../../server/contracts/margin/margin.ts";

/**
 * Quotation Builder detail page (COM-151/152/153, CG-S7-COM-010/011/012).
 * `getQuotationById` returns `null` for both "does not exist" and "exists but RLS denies
 * it," matching every prior Commercial detail page's posture. Available sourcing margin
 * calculations are gathered across every costing request under the quotation's own
 * opportunity (there is no direct quotation-to-margin-calculation link table --
 * app.quotation_lines.margin_calculation_id is set per line at add time), filtered to
 * isCurrent so a stale/superseded calculation is never offered as a new line's source.
 *
 * COM-152: this page renders any version of a root, current or historical -- line/term
 * editing is only offered when `quotation.status === "draft" && quotation.isCurrent`
 * (the exact same lock condition the underlying RPCs enforce server-side, restated here
 * only for UI affordance -- a direct RPC call against a locked version is still denied
 * regardless of what this page renders). `?compareWith=<versionId>` renders a computed
 * diff against another version of the same root.
 *
 * COM-153: `getQuotationApprovalOverview` composes the Approval Engine's own
 * history/pending-inbox view models for this quotation's bound request (null when
 * approvalStatus is not_required, i.e. never routed) -- rendered by ApprovalPanel.
 */
export default async function QuotationDetailPage({
  params,
  searchParams,
}: {
  params: Promise<{ tenantSlug: string; quotationId: string }>;
  searchParams: Promise<{ compareWith?: string }>;
}) {
  const { tenantSlug, quotationId } = await params;
  const { compareWith } = await searchParams;
  const access = await resolveCommercialAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();

  let quotation;
  try {
    quotation = await getQuotationById(supabase, quotationId);
  } catch (error) {
    if (!(error instanceof QuotationQueryError)) {
      throw error;
    }
    return (
      <div role="alert" className="flex flex-col gap-2">
        <p className="text-sm text-danger">Something went wrong loading this quotation. Please try again.</p>
      </div>
    );
  }

  if (!quotation || quotation.tenantId !== access.tenant.id) {
    notFound();
  }

  const [lines, readiness, costingRequests, contacts, versions, approvalOverview, acceptanceTokens] = await Promise.all([
    listQuotationLines(supabase, quotation.id),
    getQuotationSubmissionReadiness(supabase, quotation.id, access.authUserId),
    listCostingRequestsForOpportunity(supabase, quotation.opportunityId),
    listContacts(supabase, { tenantId: access.tenant.id, page: 1, pageSize: 50 }),
    listQuotationVersions(supabase, quotation.rootQuotationId),
    getQuotationApprovalOverview(supabase, quotation, access.authUserId),
    listQuotationAcceptanceTokens(supabase, quotation.id),
  ]);

  const calculationsByRequest = await Promise.all(costingRequests.map((request) => listMarginCalculationsForRequest(supabase, request.id)));
  const availableCalculations: MarginCalculation[] = calculationsByRequest.flat().filter((calc) => calc.isCurrent);

  const editable = quotation.status === "draft" && quotation.isCurrent;

  let comparisonPanel = null;
  if (compareWith) {
    const otherQuotation = await getQuotationById(supabase, compareWith);
    if (otherQuotation && otherQuotation.rootQuotationId === quotation.rootQuotationId) {
      const otherLines = await listQuotationLines(supabase, otherQuotation.id);
      const diff = diffQuotationVersions({ quotation: otherQuotation, lines: otherLines }, { quotation, lines });
      comparisonPanel = <ComparisonPanel diff={diff} otherVersionNumber={otherQuotation.versionNumber} />;
    }
  }

  return (
    <div className="flex flex-col gap-6">
      <h1 className="text-xl font-semibold text-neutral-900">{quotation.quoteNumber}</h1>

      <dl className="grid grid-cols-2 gap-x-6 gap-y-2 text-sm">
        <dt className="font-medium text-neutral-600">Version</dt>
        <dd className="text-neutral-900">
          v{quotation.versionNumber} — {quotation.isCurrent ? "Current" : "Superseded (read-only)"}
        </dd>
        <dt className="font-medium text-neutral-600">Status</dt>
        <dd className="text-neutral-900">{quotation.status}</dd>
        {quotation.approvalStatus !== "not_required" ? (
          <>
            <dt className="font-medium text-neutral-600">Approval</dt>
            <dd className="text-neutral-900">{quotation.approvalStatus}</dd>
          </>
        ) : null}
        <dt className="font-medium text-neutral-600">Customer</dt>
        <dd className="text-neutral-900">{quotation.customerSnapshot.legalName ?? "—"}</dd>
        <dt className="font-medium text-neutral-600">Currency</dt>
        <dd className="text-neutral-900">{quotation.currency}</dd>
        <dt className="font-medium text-neutral-600">Validity</dt>
        <dd className="text-neutral-900">
          {new Date(quotation.validityFrom).toLocaleDateString()} – {new Date(quotation.validityTo).toLocaleDateString()}
        </dd>
        <dt className="font-medium text-neutral-600">Total</dt>
        <dd className="text-neutral-900">{quotation.sellMasked ? "Restricted" : quotation.totalAmount !== null ? `${quotation.totalAmount} ${quotation.currency}` : "—"}</dd>
        <dt className="font-medium text-neutral-600">Source opportunity</dt>
        <dd className="text-neutral-900">
          <a href={`/${tenantSlug}/commercial/opportunities/${quotation.opportunityId}`} className="font-medium text-primary underline">
            View opportunity
          </a>
        </dd>
        {quotation.clonedFromId ? (
          <>
            <dt className="font-medium text-neutral-600">Cloned from</dt>
            <dd className="text-neutral-900">
              <a href={`/${tenantSlug}/commercial/quotations/${quotation.clonedFromId}`} className="font-medium text-primary underline">
                View source quotation
              </a>
            </dd>
          </>
        ) : null}
      </dl>

      <div className="rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Lines</h2>
        {lines.length === 0 ? (
          <p className="mt-2 text-sm text-neutral-600">No lines yet.</p>
        ) : (
          <table className="mt-2 w-full border-collapse text-sm">
            <thead>
              <tr className="border-b border-neutral-200 text-left text-neutral-600">
                <th scope="col" className="py-2 pr-4 font-medium">
                  Description
                </th>
                <th scope="col" className="py-2 pr-4 font-medium">
                  Type
                </th>
                <th scope="col" className="py-2 pr-4 font-medium">
                  Qty
                </th>
                <th scope="col" className="py-2 pr-4 font-medium">
                  Unit price
                </th>
                <th scope="col" className="py-2 pr-4 font-medium">
                  Line total
                </th>
                <th scope="col" className="py-2 pr-4 font-medium">
                  Cost (internal)
                </th>
                <th scope="col" className="py-2 font-medium">
                  Action
                </th>
              </tr>
            </thead>
            <tbody>
              {lines.map((line) => (
                <tr key={line.id} className="border-b border-neutral-100">
                  <td className="py-2 pr-4 text-neutral-900">{line.description}</td>
                  <td className="py-2 pr-4 text-neutral-600">{line.lineType}</td>
                  <td className="py-2 pr-4 text-neutral-600">{line.quantity}</td>
                  <td className="py-2 pr-4 text-neutral-600">{line.sellMasked ? "Restricted" : (line.unitPrice ?? "—")}</td>
                  <td className="py-2 pr-4 text-neutral-600">{line.sellMasked ? "Restricted" : (line.lineTotal ?? "—")}</td>
                  <td className="py-2 pr-4 text-neutral-600">
                    {line.costMasked ? "Restricted" : (line.costAmountSnapshot ?? "—")}
                    {!line.costMasked && line.marginPctSnapshot !== null ? ` (${line.marginPctSnapshot}% margin)` : ""}
                  </td>
                  <td className="py-2 text-neutral-600">
                    {editable ? (
                      <form action={removeQuotationLineAction.bind(null, tenantSlug, quotation.id, quotation.recordVersion, line.id)}>
                        <button type="submit" className="text-sm font-medium text-danger underline">
                          Remove
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
        )}
      </div>

      {editable ? <AddLineForm tenantSlug={tenantSlug} quotationId={quotation.id} recordVersion={quotation.recordVersion} availableCalculations={availableCalculations} /> : null}

      <TermsForm tenantSlug={tenantSlug} quotation={quotation} contacts={contacts.contacts} />

      {quotation.isCurrent ? <SubmitAndCloneActions tenantSlug={tenantSlug} quotationId={quotation.id} recordVersion={quotation.recordVersion} status={quotation.status} readiness={readiness} /> : null}

      <ApprovalPanel tenantSlug={tenantSlug} quotationId={quotation.id} approvalStatus={quotation.approvalStatus} approvalRequiredReasons={quotation.approvalRequiredReasons} overview={approvalOverview} />

      <CustomerAcceptancePanel tenantSlug={tenantSlug} quotation={quotation} tokens={acceptanceTokens} contacts={contacts.contacts} />

      <RevisionForm tenantSlug={tenantSlug} sourceQuotationId={quotation.id} isCurrent={quotation.isCurrent} />

      <VersionHistory tenantSlug={tenantSlug} versions={versions} currentViewedId={quotation.id} />

      {comparisonPanel}
    </div>
  );
}
