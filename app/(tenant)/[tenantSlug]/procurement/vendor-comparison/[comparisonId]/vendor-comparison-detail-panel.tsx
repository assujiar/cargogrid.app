"use client";

import { useActionState } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import { Input } from "../../../../../../components/forms/input.tsx";
import { StatusBadge, type StatusTone } from "../../../../../../components/ui/status-badge.tsx";
import { EmptyState } from "../../../../../../components/ui/empty-state.tsx";
import type {
  VendorComparison,
  VendorComparisonOffer,
  VendorComparisonOfferScore,
  VendorComparisonEvent,
  VendorComparisonStatus,
} from "../../../../../../server/contracts/vendor-comparison/vendor-comparison.ts";
import type { ProcurementApprovalRequirement } from "../../../../../../server/contracts/procurement-approval/procurement-approval.ts";
import type { VendorComparisonActionState } from "../actions.ts";

const INITIAL_STATE: VendorComparisonActionState = { error: null };

const COMPARISON_STATUS_TONE: Record<VendorComparisonStatus, StatusTone> = {
  draft: "neutral",
  recommended: "info",
  submitted: "success",
  cancelled: "danger",
  superseded: "neutral",
};

type SimpleFormAction = (prevState: VendorComparisonActionState, formData: FormData) => Promise<VendorComparisonActionState>;

function ActionForm({
  action,
  children,
  submitLabel,
  loadingLabel,
  variant = "primary",
  className = "flex flex-col gap-2",
}: {
  action: SimpleFormAction;
  children?: React.ReactNode;
  submitLabel: string;
  loadingLabel?: string;
  variant?: "primary" | "secondary" | "destructive";
  className?: string;
}) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  return (
    <form action={formAction} className={className}>
      {children}
      {state.error ? (
        <p role="alert" className="text-sm text-danger">
          {state.error}
        </p>
      ) : null}
      <Button type="submit" variant={variant} loading={pending} loadingLabel={loadingLabel ?? "Working…"} className="w-fit">
        {submitLabel}
      </Button>
    </form>
  );
}

function ConstraintRow({ label, value }: { label: string; value: string | null }) {
  return (
    <div className="flex flex-col gap-0.5">
      <dt className="text-xs font-medium text-neutral-500">{label}</dt>
      <dd className="text-sm text-neutral-900">{value ?? "—"}</dd>
    </div>
  );
}

function formatAmount(currency: string | null, amount: number | null): string {
  if (amount == null) return "—";
  return `${currency ?? ""} ${amount.toLocaleString()}`.trim();
}

export function VendorComparisonDetailPanel({
  comparison,
  offers,
  scoresByOfferId,
  history,
  approvalPreview,
  reviseAction,
  linkRateActionFor,
  setInclusionActionFor,
  scoreCriterionActionFor,
  recommendAction,
  submitAction,
  cancelAction,
}: {
  comparison: VendorComparison;
  offers: readonly VendorComparisonOffer[];
  scoresByOfferId: ReadonlyMap<string, VendorComparisonOfferScore[]>;
  history: readonly VendorComparisonEvent[];
  /** Batch 257-259 review (C-20, MEDIUM): app.evaluate_procurement_approval_requirement's real UI caller -- a best-effort "will this need governance approval?" preview against the currently-recommended offer, null when unavailable/not applicable (see page.tsx). */
  approvalPreview: ProcurementApprovalRequirement | null;
  reviseAction: SimpleFormAction;
  linkRateActionFor: (offerId: string, expectedVersion: number) => SimpleFormAction;
  setInclusionActionFor: (offerId: string, included: boolean, expectedVersion: number) => SimpleFormAction;
  scoreCriterionActionFor: (offerId: string) => SimpleFormAction;
  recommendAction: SimpleFormAction;
  submitAction: SimpleFormAction;
  cancelAction: SimpleFormAction;
}) {
  const isEditable = comparison.status === "draft" || comparison.status === "recommended";
  const isRecommended = comparison.status === "recommended";
  const nonPriceCriteria = comparison.criteriaSnapshot.filter((c) => c.key !== "price");
  const includedOffers = offers.filter((o) => o.included);
  const lowestAmount = includedOffers.reduce<number | null>((min, o) => (o.normalizedAmount != null && (min == null || o.normalizedAmount < min) ? o.normalizedAmount : min), null);

  return (
    <div className="flex flex-col gap-6">
      <header className="flex flex-wrap items-start justify-between gap-2">
        <div>
          <h1 className="text-xl font-semibold text-neutral-900">
            Comparison {comparison.id.slice(0, 8)} <span className="text-sm font-normal text-neutral-500">v{comparison.version}</span>
          </h1>
          <p className="text-xs text-neutral-500">
            RFQ {comparison.rfqId.slice(0, 8)} · currency {comparison.comparisonCurrency}
          </p>
        </div>
        <StatusBadge tone={COMPARISON_STATUS_TONE[comparison.status]} label={comparison.status} />
      </header>

      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Basis and criteria</h2>
        <dl className="grid grid-cols-2 gap-3 sm:grid-cols-4">
          <ConstraintRow label="Basis weight" value={comparison.basisWeight != null ? String(comparison.basisWeight) : null} />
          <ConstraintRow label="Basis volume" value={comparison.basisVolume != null ? String(comparison.basisVolume) : null} />
          <ConstraintRow label="Basis quantity" value={comparison.basisQuantity != null ? String(comparison.basisQuantity) : null} />
          <ConstraintRow label="Recommended offer" value={comparison.recommendedOfferId ? comparison.recommendedOfferId.slice(0, 8) : null} />
        </dl>
        <ul className="flex flex-wrap gap-2 text-xs text-neutral-700">
          {comparison.criteriaSnapshot.map((c) => (
            <li key={c.key} className="rounded-full bg-neutral-100 px-2 py-1">
              {c.label} ({c.weight}%)
            </li>
          ))}
        </ul>

        {isEditable ? (
          <details className="text-xs">
            <summary className="cursor-pointer text-primary">Recalculate (governed exception -- creates a new version)</summary>
            <ActionForm action={reviseAction} submitLabel="Revise comparison" loadingLabel="Revising…" variant="secondary" className="mt-2 grid grid-cols-1 gap-2 sm:grid-cols-4">
              <div className="flex flex-col gap-1">
                <label htmlFor="reviseComparisonCurrency" className="text-xs font-medium text-neutral-700">
                  New currency
                </label>
                <Input id="reviseComparisonCurrency" name="comparisonCurrency" type="text" maxLength={3} />
              </div>
              <div className="flex flex-col gap-1">
                <label htmlFor="reviseBasisWeight" className="text-xs font-medium text-neutral-700">
                  New basis weight
                </label>
                <Input id="reviseBasisWeight" name="basisWeight" type="number" min={0} />
              </div>
              <div className="flex flex-col gap-1">
                <label htmlFor="reviseBasisVolume" className="text-xs font-medium text-neutral-700">
                  New basis volume
                </label>
                <Input id="reviseBasisVolume" name="basisVolume" type="number" min={0} />
              </div>
              <div className="flex flex-col gap-1">
                <label htmlFor="reviseBasisQuantity" className="text-xs font-medium text-neutral-700">
                  New basis quantity
                </label>
                <Input id="reviseBasisQuantity" name="basisQuantity" type="number" min={0} />
              </div>
              <div className="flex flex-col gap-1 sm:col-span-4">
                <label htmlFor="reviseCriteria" className="text-xs font-medium text-neutral-700">
                  New criteria (JSON array, optional)
                </label>
                <Input id="reviseCriteria" name="criteria" type="text" />
              </div>
              <div className="flex flex-col gap-1 sm:col-span-4">
                <label htmlFor="reviseReason" className="text-xs font-medium text-neutral-700">
                  Reason (required)
                </label>
                <Input id="reviseReason" name="reason" type="text" required />
              </div>
            </ActionForm>
          </details>
        ) : null}
      </section>

      {isEditable ? (
        <section className="flex flex-wrap gap-3 rounded-md border border-neutral-200 p-4">
          <ActionForm action={cancelAction} submitLabel="Cancel comparison" loadingLabel="Cancelling…" variant="destructive" className="flex items-center gap-2">
            <Input name="reason" type="text" placeholder="Reason (required)" required className="w-64" />
          </ActionForm>
        </section>
      ) : null}

      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Normalized offers</h2>
        <p className="text-xs text-neutral-500">
          Every total is either the vendor&apos;s own quoted amount or (when a rate is linked) the rate engine&apos;s exact computed amount, converted into {comparison.comparisonCurrency} and
          rounded via the one shared rounding authority. Source amount and full conversion lineage are always preserved for drilldown.
        </p>

        {offers.length === 0 ? (
          <EmptyState title="No offers in this comparison" />
        ) : (
          <div className="overflow-x-auto rounded-md border border-neutral-200">
            <table className="w-full text-sm">
              <thead className="bg-neutral-50 text-left text-xs font-medium uppercase text-neutral-500">
                <tr>
                  <th className="px-3 py-2">Rank</th>
                  <th className="px-3 py-2">Vendor</th>
                  <th className="px-3 py-2">Source offer</th>
                  <th className="px-3 py-2">Normalized</th>
                  <th className="px-3 py-2">Price / non-price / composite</th>
                  <th className="px-3 py-2">Included</th>
                  <th className="px-3 py-2">Actions</th>
                </tr>
              </thead>
              <tbody>
                {offers.map((offer) => {
                  const scores = scoresByOfferId.get(offer.id) ?? [];
                  const isLowest = offer.included && offer.normalizedAmount != null && lowestAmount != null && offer.normalizedAmount === lowestAmount;
                  return (
                    <tr key={offer.id} className="border-t border-neutral-200 align-top">
                      <td className="px-3 py-2 text-neutral-700">{offer.rank ?? "—"}</td>
                      <td className="px-3 py-2 font-mono text-xs text-neutral-700">
                        {offer.vendorMasterId.slice(0, 8)}
                        {isLowest ? <StatusBadge tone="success" label="lowest" /> : null}
                      </td>
                      <td className="px-3 py-2 text-neutral-700">{formatAmount(offer.sourceCurrency, offer.sourceTotalAmount)}</td>
                      <td className="px-3 py-2 text-neutral-900">
                        {formatAmount(comparison.comparisonCurrency, offer.normalizedAmount)}
                        {offer.rateVersionId ? <p className="text-xs text-neutral-500">via rate {offer.rateVersionId.slice(0, 8)}</p> : null}
                        {!offer.included && offer.exclusionReason ? <p className="text-xs text-danger">{offer.exclusionReason}</p> : null}
                        {isEditable && !offer.rateVersionId ? (
                          <details className="mt-1 text-xs">
                            <summary className="cursor-pointer text-primary">Link an approved rate</summary>
                            <ActionForm action={linkRateActionFor(offer.id, offer.recordVersion)} submitLabel="Link rate" loadingLabel="Linking…" variant="secondary" className="mt-1 flex items-center gap-1">
                              <Input name="rateVersionId" type="text" placeholder="Rate version id" required className="w-40 text-xs" />
                            </ActionForm>
                          </details>
                        ) : null}
                      </td>
                      <td className="px-3 py-2 text-xs text-neutral-700">
                        <p>price {offer.priceScore ?? "—"}</p>
                        <p>non-price {offer.nonPriceScore ?? "—"}</p>
                        <p className="font-medium text-neutral-900">composite {offer.compositeScore ?? "—"}</p>
                        {isEditable && nonPriceCriteria.length > 0 ? (
                          <details className="mt-1">
                            <summary className="cursor-pointer text-primary">Score</summary>
                            <ActionForm action={scoreCriterionActionFor(offer.id)} submitLabel="Save score" loadingLabel="Saving…" variant="secondary" className="mt-1 flex flex-col gap-1">
                              <select name="criterionKey" className="rounded-md border border-neutral-300 px-2 py-1 text-xs" required>
                                {nonPriceCriteria.map((c) => (
                                  <option key={c.key} value={c.key}>
                                    {c.label}
                                  </option>
                                ))}
                              </select>
                              <Input name="score" type="number" min={0} max={100} placeholder="0-100" required className="w-24 text-xs" />
                              <Input name="notes" type="text" placeholder="Notes" className="w-40 text-xs" />
                            </ActionForm>
                            {scores.length > 0 ? (
                              <ul className="mt-1 text-xs text-neutral-500">
                                {scores.map((s) => (
                                  <li key={s.criterionKey}>
                                    {s.criterionKey}: {s.score}
                                  </li>
                                ))}
                              </ul>
                            ) : null}
                          </details>
                        ) : null}
                      </td>
                      <td className="px-3 py-2">
                        {offer.included ? (
                          <StatusBadge tone="success" label="included" />
                        ) : (
                          <StatusBadge tone="danger" label="excluded" />
                        )}
                      </td>
                      <td className="px-3 py-2">
                        {isEditable ? (
                          offer.included ? (
                            <ActionForm
                              action={setInclusionActionFor(offer.id, false, offer.recordVersion)}
                              submitLabel="Exclude"
                              loadingLabel="Excluding…"
                              variant="destructive"
                              className="flex flex-col gap-1"
                            >
                              <Input name="reason" type="text" placeholder="Reason (required)" required className="w-40 text-xs" />
                            </ActionForm>
                          ) : (
                            <ActionForm action={setInclusionActionFor(offer.id, true, offer.recordVersion)} submitLabel="Re-include" loadingLabel="Including…" variant="secondary" />
                          )
                        ) : (
                          "—"
                        )}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </section>

      {isEditable ? (
        <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
          <h2 className="text-sm font-semibold text-neutral-900">Recommendation</h2>
          <p className="text-xs text-neutral-500">Lowest price is not automatic selection -- recommending any offer other than the lowest normalized cost requires a reason.</p>
          <ActionForm action={recommendAction} submitLabel="Recommend" loadingLabel="Recording…" variant="primary" className="flex flex-col gap-2 sm:flex-row sm:items-end">
            <div className="flex flex-1 flex-col gap-1">
              <label htmlFor="recommendOfferId" className="text-xs font-medium text-neutral-700">
                Offer id
              </label>
              <select id="recommendOfferId" name="comparisonOfferId" className="rounded-md border border-neutral-300 px-2 py-1.5 text-sm" required>
                {includedOffers.map((offer) => (
                  <option key={offer.id} value={offer.id}>
                    {offer.vendorMasterId.slice(0, 8)} — {formatAmount(comparison.comparisonCurrency, offer.normalizedAmount)}
                  </option>
                ))}
              </select>
            </div>
            <div className="flex flex-1 flex-col gap-1">
              <label htmlFor="recommendReason" className="text-xs font-medium text-neutral-700">
                Reason (required if not the lowest cost)
              </label>
              <Input id="recommendReason" name="reason" type="text" />
            </div>
          </ActionForm>
        </section>
      ) : null}

      {isRecommended ? (
        <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
          <h2 className="text-sm font-semibold text-neutral-900">Submit for approval</h2>
          <p className="text-xs text-neutral-500">
            Final human selection -- terminal once submitted. Selecting an offer other than the recommended one (override) requires a reason.
          </p>
          {approvalPreview ? (
            <p className="rounded-md bg-neutral-50 px-2 py-1.5 text-xs text-neutral-700">
              {approvalPreview.required
                ? `This selection is expected to require additional governance approval (${approvalPreview.reasons.join(", ") || "policy threshold"}) based on the currently recommended offer. The real routing decision is made by the server when you submit, and applies to whichever offer you actually select below.`
                : "Based on the currently recommended offer, this selection is not expected to require additional governance approval. The real routing decision is made by the server when you submit."}
            </p>
          ) : null}
          <ActionForm action={submitAction} submitLabel="Submit for approval" loadingLabel="Submitting…" variant="primary" className="flex flex-col gap-2 sm:flex-row sm:items-end">
            <div className="flex flex-1 flex-col gap-1">
              <label htmlFor="selectedOfferId" className="text-xs font-medium text-neutral-700">
                Selected offer id
              </label>
              <select id="selectedOfferId" name="selectedOfferId" className="rounded-md border border-neutral-300 px-2 py-1.5 text-sm" required defaultValue={comparison.recommendedOfferId ?? ""}>
                {includedOffers.map((offer) => (
                  <option key={offer.id} value={offer.id}>
                    {offer.vendorMasterId.slice(0, 8)} — {formatAmount(comparison.comparisonCurrency, offer.normalizedAmount)}
                  </option>
                ))}
              </select>
            </div>
            <div className="flex flex-1 flex-col gap-1">
              <label htmlFor="selectionReason" className="text-xs font-medium text-neutral-700">
                Override reason (required if not the recommended offer)
              </label>
              <Input id="selectionReason" name="selectionReason" type="text" />
            </div>
          </ActionForm>
        </section>
      ) : null}

      {comparison.status === "submitted" ? (
        <section className="flex flex-col gap-2 rounded-md border border-success/30 bg-success/10 p-4">
          <h2 className="text-sm font-semibold text-neutral-900">Submitted for approval</h2>
          <p className="text-xs text-neutral-700">
            Selected offer {comparison.selectedOfferId?.slice(0, 8)} on {comparison.submittedAt ? new Date(comparison.submittedAt).toLocaleString() : "—"}
            {comparison.submittedBy ? ` by ${comparison.submittedBy}` : ""}. {comparison.selectionReason ? `Reason: ${comparison.selectionReason}` : ""}
          </p>
        </section>
      ) : null}

      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Lifecycle history</h2>
        {history.length === 0 ? (
          <EmptyState title="No lifecycle events yet" />
        ) : (
          <ul className="flex flex-col gap-2">
            {history.map((event) => (
              <li key={event.id} className="flex flex-col gap-0.5 border-t border-neutral-100 pt-2 text-sm first:border-t-0 first:pt-0">
                <span className="text-xs text-neutral-500">{new Date(event.occurredAt).toLocaleString()}</span>
                <span className="text-neutral-900">
                  {event.fromStatus} → {event.toStatus}
                  {event.actorLabel ? ` · ${event.actorLabel}` : ""}
                </span>
                {event.reason ? <span className="text-xs text-neutral-600">{event.reason}</span> : null}
              </li>
            ))}
          </ul>
        )}
      </section>
    </div>
  );
}
