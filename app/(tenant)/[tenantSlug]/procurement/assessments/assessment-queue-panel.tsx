"use client";

import { useActionState } from "react";
import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { Button } from "../../../../../components/ui/button.tsx";
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
            <select id="assessment-status" defaultValue={statusFilter ?? ""} className="rounded-md border border-neutral-300 px-3 py-1.5 text-sm" onChange={(event) => applyFilter(event.currentTarget.value, assignedToMe)}>
              <option value="">All statuses</option>
              {VENDOR_ASSESSMENT_STATUSES.map((s) => (
                <option key={s} value={s}>
                  {s.replace(/_/g, " ")}
                </option>
              ))}
            </select>
          </div>
        </div>

        {assessments.length === 0 ? (
          <EmptyState title="No assessments match this view" description="Adjust your filters, or start a new assessment below." />
        ) : (
          <table className="w-full text-sm">
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
          <form action={formAction} className="grid grid-cols-1 gap-3 sm:grid-cols-3">
            <div className="flex flex-col gap-1">
              <label htmlFor="vendorMasterRecordId" className="text-xs font-medium text-neutral-600">
                Vendor
              </label>
              <select id="vendorMasterRecordId" name="vendorMasterRecordId" required className="rounded-md border border-neutral-300 px-3 py-1.5 text-sm">
                {vendors.map((v) => (
                  <option key={v.masterRecordId} value={v.masterRecordId}>
                    {v.vendorCode} — {v.legalName}
                  </option>
                ))}
              </select>
            </div>
            <div className="flex flex-col gap-1">
              <label htmlFor="templateVersionId" className="text-xs font-medium text-neutral-600">
                Template
              </label>
              <select id="templateVersionId" name="templateVersionId" required className="rounded-md border border-neutral-300 px-3 py-1.5 text-sm">
                {templates.map((t) => (
                  <option key={t.id} value={t.id}>
                    {t.name} ({t.assessmentType}
                    {t.vendorCategory ? `, ${t.vendorCategory}` : ""})
                  </option>
                ))}
              </select>
            </div>
            <div className="flex flex-col gap-1">
              <label htmlFor="idempotencyKey" className="text-xs font-medium text-neutral-600">
                Idempotency key (optional)
              </label>
              <input id="idempotencyKey" name="idempotencyKey" type="text" className="rounded-md border border-neutral-300 px-3 py-1.5 text-sm" />
            </div>

            {state.error ? (
              <p role="alert" className="col-span-full text-sm text-danger">
                {state.error}
              </p>
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
