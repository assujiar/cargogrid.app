"use client";

import { useActionState } from "react";
import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { Button } from "../../../../../components/ui/button.tsx";
import { Input } from "../../../../../components/forms/input.tsx";
import { Select } from "../../../../../components/forms/select.tsx";
import { FormField } from "../../../../../components/forms/form-field.tsx";
import { ValidationMessage } from "../../../../../components/forms/validation-message.tsx";
import { StatusBadge, type StatusTone } from "../../../../../components/ui/status-badge.tsx";
import { EmptyState } from "../../../../../components/ui/empty-state.tsx";
import type { AssessmentActionState } from "./actions.ts";
import { VENDOR_ASSESSMENT_STATUSES, type VendorAssessmentStatus, type VendorAssessmentMutationResult, type VendorAssessmentTemplate } from "../../../../../server/contracts/vendor-assessment/vendor-assessment.ts";
import type { VendorProfileListRow } from "../../../../../server/contracts/vendor-profile/vendor-profile.ts";

const INITIAL_STATE: AssessmentActionState = { error: null };

const STATUS_TONE: Record<VendorAssessmentStatus, StatusTone> = {
  draft: "neutral",
  in_progress: "info",
  submitted: "info",
  under_review: "info",
  approved: "success",
  rejected: "danger",
  closed: "neutral",
};

export function AssessmentQueuePanel({
  tenantSlug,
  assessments,
  vendors,
  templates,
  statusFilter,
  assignedToMe,
  startAction,
}: {
  tenantSlug: string;
  assessments: readonly VendorAssessmentMutationResult[];
  vendors: readonly VendorProfileListRow[];
  templates: readonly VendorAssessmentTemplate[];
  statusFilter: VendorAssessmentStatus | null;
  assignedToMe: boolean;
  startAction: (prevState: AssessmentActionState, formData: FormData) => Promise<AssessmentActionState>;
}) {
  const router = useRouter();
  const searchParams = useSearchParams();
  const [state, formAction, pending] = useActionState(startAction, INITIAL_STATE);
  const startErrorId = "assessment-start-error";
  const startDescribedBy = state.error ? startErrorId : undefined;

  function applyFilter(nextStatus: string, nextMine: boolean) {
    const next = new URLSearchParams(searchParams.toString());
    if (nextStatus) next.set("status", nextStatus);
    else next.delete("status");
    if (nextMine) next.set("mine", "1");
    else next.delete("mine");
    next.delete("after");
    router.push(`/${tenantSlug}/procurement/assessments?${next.toString()}`);
  }

  return (
    <div className="flex flex-col gap-4">
      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        <div className="flex flex-wrap items-end gap-3">
          <div className="flex gap-1 rounded-md border border-neutral-300 p-1 text-sm">
            <button type="button" onClick={() => applyFilter(statusFilter ?? "", true)} className={`rounded px-3 py-1 ${assignedToMe ? "bg-primary text-neutral-50" : ""}`}>
              Assigned to me
            </button>
            <button type="button" onClick={() => applyFilter(statusFilter ?? "", false)} className={`rounded px-3 py-1 ${!assignedToMe ? "bg-primary text-neutral-50" : ""}`}>
              All
            </button>
          </div>
          <div className="flex flex-col gap-1">
            <label htmlFor="assessment-status" className="text-xs font-medium text-neutral-600">
              Status
            </label>
            <Select id="assessment-status" defaultValue={statusFilter ?? ""} className="w-auto py-1.5" onChange={(event) => applyFilter(event.currentTarget.value, assignedToMe)}>
              <option value="">All statuses</option>
              {VENDOR_ASSESSMENT_STATUSES.map((s) => (
                <option key={s} value={s}>
                  {s.replace(/_/g, " ")}
                </option>
              ))}
            </Select>
          </div>
        </div>

        {assessments.length === 0 ? (
          <EmptyState title="No assessments match this view" description="Adjust your filters, or start a new assessment below." />
        ) : (
          <div className="overflow-x-auto">
          <table className="w-full min-w-[560px] text-sm">
            <thead>
              <tr className="text-left text-xs text-neutral-500">
                <th className="pb-1">Type</th>
                <th className="pb-1">Status</th>
                <th className="pb-1">Score</th>
                <th className="pb-1">Band</th>
                <th className="pb-1">Expiry</th>
              </tr>
            </thead>
            <tbody>
              {assessments.map((assessment) => (
                <tr key={assessment.id} className="border-t border-neutral-100">
                  <td className="py-1">
                    <Link href={`/${tenantSlug}/procurement/assessments/${assessment.id}`} className="text-primary underline">
                      {assessment.assessmentType.replace(/_/g, " ")}
                    </Link>
                  </td>
                  <td className="py-1">
                    <StatusBadge tone={STATUS_TONE[assessment.status]} label={assessment.status.replace(/_/g, " ")} />
                  </td>
                  <td className="py-1">{assessment.adjustedScore ?? assessment.calculatedScore ?? "—"}</td>
                  <td className="py-1">{assessment.scoreBand ?? "—"}</td>
                  <td className="py-1 text-xs">{assessment.expiryDate ?? "—"}</td>
                </tr>
              ))}
            </tbody>
          </table>
          </div>
        )}
      </section>

      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Start a new assessment</h2>
        {vendors.length === 0 || templates.length === 0 ? (
          <p className="text-sm text-neutral-500">
            {vendors.length === 0 ? "No vendors are registered yet. " : ""}
            {templates.length === 0 ? "No published assessment template exists yet -- publish one from Manage templates first." : ""}
          </p>
        ) : (
          <form action={formAction} className="grid grid-cols-1 gap-3 sm:grid-cols-3" noValidate>
            <FormField id="vendorMasterRecordId" label="Vendor">
              <Select id="vendorMasterRecordId" name="vendorMasterRecordId" required invalid={Boolean(state.error)} aria-describedby={startDescribedBy}>
                {vendors.map((v) => (
                  <option key={v.masterRecordId} value={v.masterRecordId}>
                    {v.vendorCode} — {v.legalName}
                  </option>
                ))}
              </Select>
            </FormField>
            <FormField id="templateVersionId" label="Template">
              <Select id="templateVersionId" name="templateVersionId" required invalid={Boolean(state.error)} aria-describedby={startDescribedBy}>
                {templates.map((t) => (
                  <option key={t.id} value={t.id}>
                    {t.name} ({t.assessmentType}
                    {t.vendorCategory ? `, ${t.vendorCategory}` : ""})
                  </option>
                ))}
              </Select>
            </FormField>
            <FormField id="idempotencyKey" label="Idempotency key (optional)">
              <Input id="idempotencyKey" name="idempotencyKey" type="text" invalid={Boolean(state.error)} aria-describedby={startDescribedBy} />
            </FormField>

            {state.error ? (
              <div className="col-span-full">
                <ValidationMessage id={startErrorId}>{state.error}</ValidationMessage>
              </div>
            ) : null}

            <div className="col-span-full">
              <Button type="submit" loading={pending} loadingLabel="Starting…">
                Start assessment
              </Button>
            </div>
          </form>
        )}
      </section>
    </div>
  );
}
