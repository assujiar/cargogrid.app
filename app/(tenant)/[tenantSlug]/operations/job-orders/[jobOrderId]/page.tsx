import { notFound } from "next/navigation";
import { resolveOperationsAccessForRequest } from "../../../../../../lib/portal/resolve-operations-access.server.ts";
import { createSupabaseServerClient } from "../../../../../../lib/supabase/server.ts";
import { getJobOrder, JobOrderQueryError } from "../../../../../../server/queries/job-order.ts";
import { getJobProfitability, JobProfitabilityQueryError } from "../../../../../../server/queries/job-profitability.ts";
import { getCurrentBillingReadinessEvaluation, listBillingReadinessHandoffs, BillingReadinessQueryError } from "../../../../../../server/queries/billing-readiness.ts";
import { StatusBadge } from "../../../../../../components/ui/status-badge.tsx";
import { JOB_ORDER_STATUS_TONE_MAP } from "../../../../../../components/domain/status-tone-map.ts";
import { ErrorState } from "../../../../../../components/ui/error-state.tsx";
import { ConfirmJobOrderForm } from "./confirm-job-order-form.tsx";
import { OverrideJobOrderForm } from "./override-job-order-form.tsx";
import { JobProfitabilityPanel } from "./job-profitability-panel.tsx";
import { BillingReadinessPanel } from "./billing-readiness-panel.tsx";
import {
  confirmJobOrderAction,
  overrideJobOrderFieldAction,
  calculateJobProfitabilityAction,
  evaluateBillingReadinessAction,
  overrideBillingReadinessAction,
  revokeBillingReadinessOverrideAction,
  handoffBillingReadinessAction,
  type JobOrderFormState,
} from "./actions.ts";
import type { OverridableSnapshotColumn } from "../../../../../../server/contracts/job-order/job-order.ts";
import { randomUUID } from "node:crypto";

/**
 * Job Order detail (OPS-168, CG-S8-OPS-002, Prompt 168 §15) -- every inherited field
 * traces to its Commercial source (`sourceHandoffId`/`quotationId`/`accountId` are
 * live links, not copies), with revenue/credit masked per COM:View selling price/
 * COM:View cost the same way Commercial's own quotation detail page already masks
 * its own totals. `getJobOrder` returns `null` for both "does not exist" and "exists
 * but RLS denies it," matching every prior detail page's posture.
 */
export default async function JobOrderDetailPage({ params }: { params: Promise<{ tenantSlug: string; jobOrderId: string }> }) {
  const { tenantSlug, jobOrderId } = await params;
  const access = await resolveOperationsAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();

  let jobOrder;
  try {
    jobOrder = await getJobOrder(supabase, jobOrderId);
  } catch (error) {
    if (!(error instanceof JobOrderQueryError)) {
      throw error;
    }
    return <ErrorState description="Something went wrong loading this Job Order. Please try again." />;
  }

  if (!jobOrder || jobOrder.tenantId !== access.tenant.id) {
    notFound();
  }

  let profitabilitySnapshot;
  try {
    profitabilitySnapshot = await getJobProfitability(supabase, jobOrder.id);
  } catch (error) {
    if (!(error instanceof JobProfitabilityQueryError)) {
      throw error;
    }
    return <ErrorState description="Something went wrong loading job profitability. Please try again." />;
  }

  let billingReadinessEvaluation;
  let billingReadinessHandoffs;
  try {
    billingReadinessEvaluation = await getCurrentBillingReadinessEvaluation(supabase, jobOrder.id);
    billingReadinessHandoffs = await listBillingReadinessHandoffs(supabase, jobOrder.id);
  } catch (error) {
    if (!(error instanceof BillingReadinessQueryError)) {
      throw error;
    }
    return <ErrorState description="Something went wrong loading billing readiness. Please try again." />;
  }

  const boundCalculateProfitabilityAction = calculateJobProfitabilityAction.bind(null, tenantSlug, jobOrder.id);
  const boundEvaluateBillingReadinessAction = evaluateBillingReadinessAction.bind(null, tenantSlug, jobOrder.id);
  const boundOverrideBillingReadinessAction = overrideBillingReadinessAction.bind(null, tenantSlug, jobOrder.id, billingReadinessEvaluation?.recordVersion ?? 0);
  const boundRevokeBillingReadinessOverrideAction = revokeBillingReadinessOverrideAction.bind(null, tenantSlug, jobOrder.id, billingReadinessEvaluation?.recordVersion ?? 0);
  const boundHandoffBillingReadinessAction = handoffBillingReadinessAction.bind(null, tenantSlug, jobOrder.id, randomUUID());
  const { tone, label } = JOB_ORDER_STATUS_TONE_MAP[jobOrder.status];
  const customerSnapshot = jobOrder.customerSnapshot as { customerSnapshot?: { legal_name?: string }; contactName?: string; contactEmail?: string; contactPhone?: string };
  const boundConfirmAction = confirmJobOrderAction.bind(null, tenantSlug, jobOrder.id, jobOrder.recordVersion);
  const boundOverrideAction = (
    snapshotColumn: OverridableSnapshotColumn,
    fieldPath: string,
    newValue: string,
    reason: string,
    prevState: JobOrderFormState,
    formData: FormData,
  ) => overrideJobOrderFieldAction(tenantSlug, jobOrder.id, jobOrder.recordVersion, snapshotColumn, fieldPath, newValue, reason, prevState, formData);

  return (
    <div className="flex flex-col gap-6">
      <div className="flex items-center gap-3">
        <h1 className="text-xl font-semibold text-neutral-900">{jobOrder.jobNumber}</h1>
        <StatusBadge tone={tone} label={label} />
      </div>

      <section className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Source lineage</h2>
        <dl className="grid grid-cols-2 gap-x-4 gap-y-1 text-sm">
          <dt className="text-neutral-600">Source handoff</dt>
          <dd className="text-neutral-900">{jobOrder.sourceHandoffId}</dd>
          <dt className="text-neutral-600">Source quotation</dt>
          <dd className="text-neutral-900">{jobOrder.quotationId}</dd>
          <dt className="text-neutral-600">Account</dt>
          <dd className="text-neutral-900">{jobOrder.accountId}</dd>
        </dl>
      </section>

      <section className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Customer</h2>
        <dl className="grid grid-cols-2 gap-x-4 gap-y-1 text-sm">
          <dt className="text-neutral-600">Legal name</dt>
          <dd className="text-neutral-900">{customerSnapshot.customerSnapshot?.legal_name ?? "—"}</dd>
          <dt className="text-neutral-600">Contact</dt>
          <dd className="text-neutral-900">{customerSnapshot.contactName ?? "—"}</dd>
          <dt className="text-neutral-600">Email</dt>
          <dd className="text-neutral-900">{customerSnapshot.contactEmail ?? "—"}</dd>
          <dt className="text-neutral-600">Phone</dt>
          <dd className="text-neutral-900">{customerSnapshot.contactPhone ?? "—"}</dd>
        </dl>
      </section>

      <section className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Revenue</h2>
        {jobOrder.revenueMasked || !jobOrder.revenueSnapshot ? (
          <p className="text-sm text-neutral-500">Restricted -- COM:View selling price is required to see this Job Order&apos;s revenue.</p>
        ) : (
          <dl className="grid grid-cols-2 gap-x-4 gap-y-1 text-sm">
            <dt className="text-neutral-600">Currency</dt>
            <dd className="text-neutral-900">{(jobOrder.revenueSnapshot as { currency?: string }).currency ?? "—"}</dd>
            <dt className="text-neutral-600">Total amount</dt>
            <dd className="text-neutral-900">{((jobOrder.revenueSnapshot as { totalAmount?: number }).totalAmount ?? 0).toLocaleString("en-US")}</dd>
          </dl>
        )}
      </section>

      {jobOrder.status === "draft" ? (
        <section className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
          <h2 className="text-sm font-semibold text-neutral-900">Confirm</h2>
          <p className="text-xs text-neutral-500">Confirming makes this Job Order eligible for Shipment Order creation.</p>
          <ConfirmJobOrderForm action={boundConfirmAction} />
        </section>
      ) : null}

      {jobOrder.status !== "cancelled" ? (
        <section className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
          <h2 className="text-sm font-semibold text-neutral-900">Override a field</h2>
          <p className="text-xs text-neutral-500">Bounded, reasoned, audited -- restricted to customer and cargo/service fields. Revenue, contract, credit and acceptance are never editable here.</p>
          <OverrideJobOrderForm action={boundOverrideAction} />
        </section>
      ) : null}

      {jobOrder.status === "confirmed" ? (
        <section className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
          <h2 className="text-sm font-semibold text-neutral-900">Shipment Orders</h2>
          <a href={`/${tenantSlug}/operations/shipment-orders/create?jobOrderId=${jobOrder.id}`} className="w-fit text-sm font-medium text-primary underline">
            Create a Shipment Order from this Job Order
          </a>
        </section>
      ) : null}

      <section className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Profitability</h2>
        <JobProfitabilityPanel snapshot={profitabilitySnapshot} action={boundCalculateProfitabilityAction} />
      </section>

      <section className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Billing readiness</h2>
        <BillingReadinessPanel
          evaluation={billingReadinessEvaluation}
          handoffs={billingReadinessHandoffs}
          evaluateAction={boundEvaluateBillingReadinessAction}
          overrideAction={boundOverrideBillingReadinessAction}
          revokeOverrideAction={boundRevokeBillingReadinessOverrideAction}
          handoffAction={boundHandoffBillingReadinessAction}
        />
      </section>
    </div>
  );
}
