import { notFound } from "next/navigation";
import { resolveCommercialAccessForRequest } from "../../../../../../lib/portal/resolve-commercial-access.server.ts";
import { createSupabaseServerClient } from "../../../../../../lib/supabase/server.ts";
import {
  getCostingRequestById,
  listCostingRequestComponents,
  listCostingResponsesForRequest,
  listCostingResponseComponents,
  CostingQueryError,
} from "../../../../../../server/queries/costing.ts";
import { listActiveVendorRates, listRateSelectionsForRequest, RateQueryError } from "../../../../../../server/queries/rate.ts";
import type { RateVersion, RateSelection } from "../../../../../../server/contracts/rate/rate.ts";
import { CostingRequestActionsPanel } from "./costing-request-actions-panel.tsx";
import { SelectRateForm } from "./select-rate-form.tsx";

/**
 * Costing Request Detail (COM-148, CG-S7-COM-007). `getCostingRequestById` returns `null`
 * for both "does not exist" and "exists but RLS denies it" -- deliberately not
 * distinguished, the same posture every prior Commercial detail page uses. Responses are
 * read through `app.costing_responses_directory` (field-masked); a masked response's own
 * components are never fetched (COM:View cost gates zero-vs-full visibility identically at
 * the component-table RLS layer, so a masked caller would see an empty list regardless).
 */
export default async function CostingRequestDetailPage({ params }: { params: Promise<{ tenantSlug: string; requestId: string }> }) {
  const { tenantSlug, requestId } = await params;
  const access = await resolveCommercialAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();

  let request;
  try {
    request = await getCostingRequestById(supabase, requestId);
  } catch (error) {
    if (!(error instanceof CostingQueryError)) {
      throw error;
    }
    return (
      <div role="alert" className="flex flex-col gap-2">
        <p className="text-sm text-danger">Something went wrong loading this costing request. Please try again.</p>
      </div>
    );
  }

  if (!request || request.tenantId !== access.tenant.id) {
    notFound();
  }

  const [components, responses] = await Promise.all([
    listCostingRequestComponents(supabase, request.id),
    listCostingResponsesForRequest(supabase, request.id),
  ]);

  const responseComponentsByResponse = await Promise.all(
    responses.map(async (response) => ({
      response,
      components: response.costMasked ? [] : await listCostingResponseComponents(supabase, response.id),
    })),
  );

  let rateSelections: RateSelection[];
  let candidateRates: RateVersion[];
  try {
    [rateSelections, candidateRates] = await Promise.all([
      listRateSelectionsForRequest(supabase, request.id),
      listActiveVendorRates(supabase, access.tenant.id),
    ]);
  } catch (error) {
    if (!(error instanceof RateQueryError)) {
      throw error;
    }
    rateSelections = [];
    candidateRates = [];
  }

  return (
    <div className="flex flex-col gap-6">
      <h1 className="text-xl font-semibold text-neutral-900">Costing request</h1>

      <dl className="grid grid-cols-2 gap-x-6 gap-y-2 text-sm">
        <dt className="font-medium text-neutral-600">Status</dt>
        <dd className="text-neutral-900">{request.status}</dd>
        <dt className="font-medium text-neutral-600">Due</dt>
        <dd className="text-neutral-900">{request.dueAt ? new Date(request.dueAt).toLocaleString() : "—"}</dd>
        <dt className="font-medium text-neutral-600">Opportunity</dt>
        <dd className="text-neutral-900">
          <a href={`/${tenantSlug}/commercial/opportunities/${request.opportunityId}`} className="font-medium text-primary underline">
            View opportunity
          </a>
        </dd>
        {request.status === "cancelled" ? (
          <>
            <dt className="font-medium text-neutral-600">Cancel reason</dt>
            <dd className="text-neutral-900">{request.cancelReason}</dd>
          </>
        ) : null}
        {request.revisedFromId ? (
          <>
            <dt className="font-medium text-neutral-600">Revised from</dt>
            <dd className="text-neutral-900">
              <a href={`/${tenantSlug}/commercial/costing-requests/${request.revisedFromId}`} className="font-medium text-primary underline">
                View prior request
              </a>
            </dd>
          </>
        ) : null}
      </dl>

      <div className="rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Requested components</h2>
        {components.length === 0 ? (
          <p className="mt-2 text-sm text-neutral-600">No line items on this request.</p>
        ) : (
          <ul className="mt-2 flex flex-col gap-1 text-sm">
            {components.map((component) => (
              <li key={component.id} className="text-neutral-700">
                {component.componentCode}
                {component.description ? ` — ${component.description}` : ""}
                {component.quantity ? ` (${component.quantity} ${component.unit ?? ""})` : ""}
              </li>
            ))}
          </ul>
        )}
      </div>

      <div className="rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Responses</h2>
        {responseComponentsByResponse.length === 0 ? (
          <p className="mt-2 text-sm text-neutral-600">No responses yet.</p>
        ) : (
          <ul className="mt-2 flex flex-col gap-3 text-sm">
            {responseComponentsByResponse.map(({ response, components: itemizedComponents }) => (
              <li key={response.id} className="border-b border-neutral-100 pb-2">
                <p className="font-medium text-neutral-900">
                  {response.sourceType}
                  {response.vendorRef ? ` (${response.vendorRef})` : ""} —{" "}
                  {response.costMasked ? "Restricted" : `${response.totalAmount} ${response.currency ?? ""}`}
                  {response.isExpired ? " — expired" : ""}
                </p>
                {itemizedComponents.length > 0 ? (
                  <ul className="mt-1 flex flex-col gap-0.5 text-xs text-neutral-600">
                    {itemizedComponents.map((item) => (
                      <li key={item.id}>{item.amount}</li>
                    ))}
                  </ul>
                ) : null}
              </li>
            ))}
          </ul>
        )}
      </div>

      <div className="rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Rate selections</h2>
        {rateSelections.length === 0 ? (
          <p className="mt-2 text-sm text-neutral-600">No rate selected yet.</p>
        ) : (
          <ul className="mt-2 flex flex-col gap-1 text-sm">
            {rateSelections.map((selection) => (
              <li key={selection.id} className="text-neutral-700">
                {selection.isAdhoc ? "Ad-hoc" : "Catalog"} —{" "}
                {selection.costMasked ? "Restricted" : `${selection.amount} ${selection.currency ?? ""}`}
                {selection.overrideReason ? ` (${selection.overrideReason})` : ""}
              </li>
            ))}
          </ul>
        )}
      </div>

      <SelectRateForm tenantSlug={tenantSlug} requestId={request.id} candidateRates={candidateRates} />

      <CostingRequestActionsPanel tenantSlug={tenantSlug} requestId={request.id} recordVersion={request.recordVersion} status={request.status} requestComponents={components} />
    </div>
  );
}
