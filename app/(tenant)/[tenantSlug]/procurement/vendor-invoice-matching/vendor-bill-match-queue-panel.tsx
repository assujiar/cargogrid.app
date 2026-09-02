"use client";

import { useActionState } from "react";
import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { Button } from "../../../../../components/ui/button.tsx";
import { Input } from "../../../../../components/forms/input.tsx";
import { Select } from "../../../../../components/forms/select.tsx";
import { Checkbox } from "../../../../../components/forms/checkbox.tsx";
import { FormField } from "../../../../../components/forms/form-field.tsx";
import { ValidationMessage } from "../../../../../components/forms/validation-message.tsx";
import { StatusBadge, type StatusTone } from "../../../../../components/ui/status-badge.tsx";
import { EmptyState } from "../../../../../components/ui/empty-state.tsx";
import {
  VENDOR_BILL_MATCH_CASE_STATUSES,
  type VendorBillMatchCase,
  type VendorBillMatchCaseStatus,
  type VendorBillMatchReconciliationRow,
  type VendorBillMatchTolerancePolicy,
} from "../../../../../server/contracts/vendor-invoice-matching/vendor-invoice-matching.ts";
import type { VendorBillMatchQueueActionState } from "./actions.ts";

const INITIAL_STATE: VendorBillMatchQueueActionState = { error: null };

const STATUS_TONE: Record<VendorBillMatchCaseStatus, StatusTone> = {
  pending: "neutral",
  matched: "success",
  exception: "warning",
  disputed: "danger",
  blocked: "danger",
  cancelled: "neutral",
};

type BoundFormAction = (prevState: VendorBillMatchQueueActionState, formData: FormData) => Promise<VendorBillMatchQueueActionState>;

function ActivatePolicyForm({ policy, activatePolicyAction }: { policy: VendorBillMatchTolerancePolicy; activatePolicyAction: BoundFormAction }) {
  const [state, formAction, pending] = useActionState(activatePolicyAction, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col items-start gap-1">
      <input type="hidden" name="policyId" value={policy.id} />
      <input type="hidden" name="expectedVersion" value={policy.recordVersion} />
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Activating…" className="text-xs">
        Activate
      </Button>
      {state.error ? <ValidationMessage>{state.error}</ValidationMessage> : null}
    </form>
  );
}

function EditPolicyDraftForm({ policy, updatePolicyAction }: { policy: VendorBillMatchTolerancePolicy; updatePolicyAction: BoundFormAction }) {
  const [state, formAction, pending] = useActionState(updatePolicyAction, INITIAL_STATE);
  const errorId = `edit-policy-${policy.id}-error`;
  const describedBy = state.error ? errorId : undefined;
  return (
    <details className="w-full text-xs">
      <summary className="cursor-pointer font-medium text-neutral-700">Edit draft</summary>
      <form action={formAction} className="mt-2 grid grid-cols-2 gap-2 sm:grid-cols-4">
        <input type="hidden" name="policyId" value={policy.id} />
        <input type="hidden" name="expectedVersion" value={policy.recordVersion} />
        <label htmlFor={`edit-policy-name-${policy.id}`} className="sr-only">
          Policy name
        </label>
        <Input id={`edit-policy-name-${policy.id}`} name="name" placeholder="Policy name" required defaultValue={policy.name} className="col-span-2" invalid={Boolean(state.error)} aria-describedby={describedBy} />
        <label htmlFor={`edit-policy-qty-${policy.id}`} className="sr-only">
          Quantity tolerance percent
        </label>
        <Input id={`edit-policy-qty-${policy.id}`} name="quantityTolerancePct" type="number" min={0} max={100} step="0.1" placeholder="Qty %" defaultValue={policy.quantityTolerancePct} invalid={Boolean(state.error)} aria-describedby={describedBy} />
        <label htmlFor={`edit-policy-rate-${policy.id}`} className="sr-only">
          Rate tolerance percent
        </label>
        <Input id={`edit-policy-rate-${policy.id}`} name="rateTolerancePct" type="number" min={0} max={100} step="0.1" placeholder="Rate %" defaultValue={policy.rateTolerancePct} invalid={Boolean(state.error)} aria-describedby={describedBy} />
        <label htmlFor={`edit-policy-tax-${policy.id}`} className="sr-only">
          Tax tolerance percent
        </label>
        <Input id={`edit-policy-tax-${policy.id}`} name="taxTolerancePct" type="number" min={0} max={100} step="0.1" placeholder="Tax %" defaultValue={policy.taxTolerancePct} invalid={Boolean(state.error)} aria-describedby={describedBy} />
        <label htmlFor={`edit-policy-abs-${policy.id}`} className="sr-only">
          Absolute tolerance buffer
        </label>
        <Input id={`edit-policy-abs-${policy.id}`} name="lineAmountToleranceAbs" type="number" min={0} step="0.01" placeholder="Abs buffer" defaultValue={policy.lineAmountToleranceAbs} invalid={Boolean(state.error)} aria-describedby={describedBy} />
        <label htmlFor={`edit-policy-window-${policy.id}`} className="sr-only">
          Duplicate window (days)
        </label>
        <Input id={`edit-policy-window-${policy.id}`} name="duplicateWindowDays" type="number" min={1} placeholder="Duplicate window (days)" defaultValue={policy.duplicateWindowDays} invalid={Boolean(state.error)} aria-describedby={describedBy} />
        <Checkbox id={`edit-policy-autoclear-${policy.id}`} name="autoClearEnabled" defaultChecked={policy.autoClearEnabled} label="Auto-clear enabled" aria-describedby={describedBy} />
        <Button type="submit" variant="secondary" loading={pending} loadingLabel="Saving…" className="col-span-2 w-fit">
          Save draft
        </Button>
      </form>
      {state.error ? <ValidationMessage id={errorId}>{state.error}</ValidationMessage> : null}
    </details>
  );
}

export function VendorBillMatchQueuePanel({
  tenantSlug,
  cases,
  policies,
  reconciliation,
  statusFilter,
  startMatchAction,
  createPolicyAction,
  updatePolicyAction,
  activatePolicyAction,
}: {
  tenantSlug: string;
  cases: readonly VendorBillMatchCase[];
  policies: readonly VendorBillMatchTolerancePolicy[];
  reconciliation: readonly VendorBillMatchReconciliationRow[];
  statusFilter: VendorBillMatchCaseStatus | null;
  startMatchAction: BoundFormAction;
  createPolicyAction: BoundFormAction;
  updatePolicyAction: BoundFormAction;
  activatePolicyAction: BoundFormAction;
}) {
  const router = useRouter();
  const searchParams = useSearchParams();
  const [startState, startFormAction, startPending] = useActionState(startMatchAction, INITIAL_STATE);
  const [createPolicyState, createPolicyFormAction, createPolicyPending] = useActionState(createPolicyAction, INITIAL_STATE);
  const createPolicyErrorId = "create-policy-error";
  const createPolicyDescribedBy = createPolicyState.error ? createPolicyErrorId : undefined;

  const activePolicy = policies.find((p) => p.status === "active") ?? null;
  const draftPolicies = policies.filter((p) => p.status === "draft");

  function applyStatusFilter(nextStatus: string) {
    const next = new URLSearchParams(searchParams.toString());
    if (nextStatus) next.set("overallStatus", nextStatus);
    else next.delete("overallStatus");
    router.push(`/${tenantSlug}/procurement/vendor-invoice-matching?${next.toString()}`);
  }

  return (
    <div className="flex flex-col gap-6">
      <section className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Start matching a bill</h2>
        <p className="text-xs text-neutral-500">
          Paste the canonical Finance vendor bill id (from the Finance vendor-bill workspace). Matching a bill requires FIN:View in addition to your Procurement role, since it
          reads real Finance evidence.
        </p>
        <form action={startFormAction} className="flex flex-wrap items-end gap-2" noValidate>
          <FormField id="billId" label="Vendor bill id" error={startState.error ?? undefined}>
            <Input id="billId" name="billId" required className="w-80" placeholder="00000000-0000-0000-0000-000000000000" invalid={Boolean(startState.error)} aria-describedby={startState.error ? "billId-error" : undefined} />
          </FormField>
          <Button type="submit" loading={startPending} loadingLabel="Loading bill…">
            Continue
          </Button>
        </form>
      </section>

      <section className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Tolerance policy</h2>
        {activePolicy ? (
          <p className="text-xs text-neutral-700">
            Active: <span className="font-medium">{activePolicy.name}</span> -- qty ±{activePolicy.quantityTolerancePct}%, rate ±{activePolicy.rateTolerancePct}%, tax ±
            {activePolicy.taxTolerancePct}%, abs buffer {activePolicy.lineAmountToleranceAbs}, auto-clear {activePolicy.autoClearEnabled ? "ON" : "OFF"}, duplicate window{" "}
            {activePolicy.duplicateWindowDays} days.
          </p>
        ) : (
          <p className="text-xs text-warning">No active tolerance policy -- every case will require an exception approval, since nothing auto-clears without one.</p>
        )}
        {draftPolicies.length > 0 ? (
          <div className="flex flex-col gap-2">
            <h3 className="text-xs font-medium text-neutral-700">Draft policies awaiting activation</h3>
            {draftPolicies.map((p) => (
              <div key={p.id} className="flex flex-col gap-2 rounded border border-neutral-200 p-2 text-xs sm:flex-row sm:items-start sm:justify-between">
                <span>
                  {p.name} -- qty ±{p.quantityTolerancePct}%, rate ±{p.rateTolerancePct}%, auto-clear {p.autoClearEnabled ? "ON" : "OFF"}
                </span>
                <div className="flex flex-col items-start gap-2 sm:flex-row sm:items-center">
                  <EditPolicyDraftForm policy={p} updatePolicyAction={updatePolicyAction} />
                  <ActivatePolicyForm policy={p} activatePolicyAction={activatePolicyAction} />
                </div>
              </div>
            ))}
          </div>
        ) : null}
        <details className="text-xs">
          <summary className="cursor-pointer font-medium text-neutral-700">Create a new tolerance policy draft</summary>
          <form action={createPolicyFormAction} className="mt-2 grid grid-cols-2 gap-2 sm:grid-cols-4">
            <label htmlFor="create-policy-name" className="sr-only">
              Policy name
            </label>
            <Input id="create-policy-name" name="name" placeholder="Policy name" required className="col-span-2" invalid={Boolean(createPolicyState.error)} aria-describedby={createPolicyDescribedBy} />
            <label htmlFor="create-policy-qty" className="sr-only">
              Quantity tolerance percent
            </label>
            <Input id="create-policy-qty" name="quantityTolerancePct" type="number" min={0} max={100} step="0.1" placeholder="Qty %" defaultValue={0} invalid={Boolean(createPolicyState.error)} aria-describedby={createPolicyDescribedBy} />
            <label htmlFor="create-policy-rate" className="sr-only">
              Rate tolerance percent
            </label>
            <Input id="create-policy-rate" name="rateTolerancePct" type="number" min={0} max={100} step="0.1" placeholder="Rate %" defaultValue={0} invalid={Boolean(createPolicyState.error)} aria-describedby={createPolicyDescribedBy} />
            <label htmlFor="create-policy-tax" className="sr-only">
              Tax tolerance percent
            </label>
            <Input id="create-policy-tax" name="taxTolerancePct" type="number" min={0} max={100} step="0.1" placeholder="Tax %" defaultValue={0} invalid={Boolean(createPolicyState.error)} aria-describedby={createPolicyDescribedBy} />
            <label htmlFor="create-policy-abs" className="sr-only">
              Absolute tolerance buffer
            </label>
            <Input id="create-policy-abs" name="lineAmountToleranceAbs" type="number" min={0} step="0.01" placeholder="Abs buffer" defaultValue={0} invalid={Boolean(createPolicyState.error)} aria-describedby={createPolicyDescribedBy} />
            <label htmlFor="create-policy-window" className="sr-only">
              Duplicate window (days)
            </label>
            <Input id="create-policy-window" name="duplicateWindowDays" type="number" min={1} placeholder="Duplicate window (days)" defaultValue={30} invalid={Boolean(createPolicyState.error)} aria-describedby={createPolicyDescribedBy} />
            <Checkbox id="create-policy-autoclear" name="autoClearEnabled" label="Auto-clear enabled" aria-describedby={createPolicyDescribedBy} />
            <Button type="submit" loading={createPolicyPending} loadingLabel="Creating…" className="col-span-2 w-fit">
              Create draft
            </Button>
          </form>
          {createPolicyState.error ? <ValidationMessage id={createPolicyErrorId}>{createPolicyState.error}</ValidationMessage> : null}
        </details>
      </section>

      {reconciliation.length > 0 ? (
        <section className="flex flex-col gap-2">
          <h2 className="text-sm font-semibold text-neutral-900">Reconciliation status</h2>
          <div className="overflow-x-auto rounded-md border border-neutral-200">
            <table className="w-full text-xs">
              <thead className="bg-neutral-50 text-left uppercase text-neutral-500">
                <tr>
                  <th className="px-3 py-2">Status</th>
                  <th className="px-3 py-2">Readiness</th>
                  <th className="px-3 py-2">Cases</th>
                  <th className="px-3 py-2">Total variance</th>
                </tr>
              </thead>
              <tbody>
                {reconciliation.map((r, i) => (
                  <tr key={i} className="border-t border-neutral-200">
                    <td className="px-3 py-2">
                      <StatusBadge tone={STATUS_TONE[r.overallStatus]} label={r.overallStatus} />
                    </td>
                    <td className="px-3 py-2 text-neutral-700">{r.readinessStatus}</td>
                    <td className="px-3 py-2 text-neutral-700">{r.caseCount}</td>
                    <td className="px-3 py-2 text-neutral-700">{r.totalVarianceAmount === null ? "masked" : r.totalVarianceAmount}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </section>
      ) : null}

      <section className="flex flex-col gap-2">
        <div className="flex items-center gap-2">
          <label htmlFor="vbm-status" className="text-xs font-medium text-neutral-600">
            Status
          </label>
          <Select
            id="vbm-status"
            defaultValue={statusFilter ?? ""}
            className="w-auto py-1.5"
            onChange={(event) => applyStatusFilter(event.currentTarget.value)}
          >
            <option value="">All</option>
            {VENDOR_BILL_MATCH_CASE_STATUSES.map((s) => (
              <option key={s} value={s}>
                {s}
              </option>
            ))}
          </Select>
        </div>

        {cases.length === 0 ? (
          <EmptyState title="No match cases match this view" description="Start matching a bill above." />
        ) : (
          <div className="overflow-x-auto rounded-md border border-neutral-200">
            <table className="w-full text-sm">
              <thead className="bg-neutral-50 text-left text-xs font-medium uppercase text-neutral-500">
                <tr>
                  <th className="px-3 py-2">Bill</th>
                  <th className="px-3 py-2">Mode</th>
                  <th className="px-3 py-2">Status</th>
                  <th className="px-3 py-2">Readiness</th>
                  <th className="px-3 py-2">Duplicate</th>
                  <th className="px-3 py-2">Variance %</th>
                </tr>
              </thead>
              <tbody>
                {cases.map((c) => (
                  <tr key={c.id} className="border-t border-neutral-200">
                    <td className="px-3 py-2">
                      <Link href={`/${tenantSlug}/procurement/vendor-invoice-matching/${c.id}`} className="font-medium text-primary hover:underline">
                        {c.billId}
                      </Link>
                      <span className="ml-1 text-xs text-neutral-500">v{c.versionNo}</span>
                    </td>
                    <td className="px-3 py-2 text-neutral-700">{c.matchMode}</td>
                    <td className="px-3 py-2">
                      <StatusBadge tone={STATUS_TONE[c.overallStatus]} label={c.overallStatus} />
                    </td>
                    <td className="px-3 py-2 text-neutral-700">{c.readinessStatus}</td>
                    <td className="px-3 py-2 text-neutral-700">{c.isDuplicateFlagged ? "flagged" : "-"}</td>
                    <td className="px-3 py-2 text-neutral-700">{c.totalVariancePct === null ? "masked" : `${c.totalVariancePct}%`}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>
    </div>
  );
}
