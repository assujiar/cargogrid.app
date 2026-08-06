"use client";

import { useActionState } from "react";
import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { Button } from "../../../../../../components/ui/button.tsx";
import { StatusBadge, type StatusTone } from "../../../../../../components/ui/status-badge.tsx";
import { EmptyState } from "../../../../../../components/ui/empty-state.tsx";
import type { TemplateActionState } from "./actions.ts";
import { VENDOR_ASSESSMENT_TEMPLATE_STATUSES, VENDOR_ASSESSMENT_TYPES, type VendorAssessmentTemplateStatus, type VendorAssessmentTemplate } from "../../../../../../server/contracts/vendor-assessment/vendor-assessment.ts";

const INITIAL_STATE: TemplateActionState = { error: null };

const STATUS_TONE: Record<VendorAssessmentTemplateStatus, StatusTone> = {
  draft: "neutral",
  published: "success",
  archived: "neutral",
};

export function TemplateManagementPanel({
  tenantSlug,
  templates,
  statusFilter,
  createAction,
}: {
  tenantSlug: string;
  templates: readonly VendorAssessmentTemplate[];
  statusFilter: VendorAssessmentTemplateStatus | null;
  createAction: (prevState: TemplateActionState, formData: FormData) => Promise<TemplateActionState>;
}) {
  const router = useRouter();
  const searchParams = useSearchParams();
  const [state, formAction, pending] = useActionState(createAction, INITIAL_STATE);

  function applyFilter(nextStatus: string) {
    const next = new URLSearchParams(searchParams.toString());
    if (nextStatus) next.set("status", nextStatus);
    else next.delete("status");
    router.push(`/${tenantSlug}/procurement/assessments/templates?${next.toString()}`);
  }

  return (
    <div className="flex flex-col gap-4">
      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        <div className="flex flex-col gap-1">
          <label htmlFor="template-status" className="text-xs font-medium text-neutral-600">
            Status
          </label>
          <select id="template-status" defaultValue={statusFilter ?? ""} className="w-fit rounded-md border border-neutral-300 px-3 py-1.5 text-sm" onChange={(event) => applyFilter(event.currentTarget.value)}>
            <option value="">All statuses</option>
            {VENDOR_ASSESSMENT_TEMPLATE_STATUSES.map((s) => (
              <option key={s} value={s}>
                {s}
              </option>
            ))}
          </select>
        </div>

        {templates.length === 0 ? (
          <EmptyState title="No templates match this view" description="Create a new draft template below." />
        ) : (
          <table className="w-full text-sm">
            <thead>
              <tr className="text-left text-xs text-neutral-500">
                <th className="pb-1">Name</th>
                <th className="pb-1">Type</th>
                <th className="pb-1">Category</th>
                <th className="pb-1">Status</th>
              </tr>
            </thead>
            <tbody>
              {templates.map((t) => (
                <tr key={t.id} className="border-t border-neutral-100">
                  <td className="py-1">
                    <Link href={`/${tenantSlug}/procurement/assessments/templates/${t.id}`} className="text-primary underline">
                      {t.name}
                    </Link>
                  </td>
                  <td className="py-1">{t.assessmentType}</td>
                  <td className="py-1">{t.vendorCategory ?? "any"}</td>
                  <td className="py-1">
                    <StatusBadge tone={STATUS_TONE[t.status]} label={t.status} />
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </section>

      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Create a new template draft</h2>
        <form action={formAction} className="grid grid-cols-1 gap-3 sm:grid-cols-3">
          <div className="flex flex-col gap-1">
            <label htmlFor="name" className="text-xs font-medium text-neutral-600">
              Name
            </label>
            <input id="name" name="name" type="text" required className="rounded-md border border-neutral-300 px-3 py-1.5 text-sm" />
          </div>
          <div className="flex flex-col gap-1">
            <label htmlFor="assessmentType" className="text-xs font-medium text-neutral-600">
              Assessment type
            </label>
            <select id="assessmentType" name="assessmentType" required className="rounded-md border border-neutral-300 px-3 py-1.5 text-sm">
              {VENDOR_ASSESSMENT_TYPES.map((t) => (
                <option key={t} value={t}>
                  {t}
                </option>
              ))}
            </select>
          </div>
          <div className="flex flex-col gap-1">
            <label htmlFor="vendorCategory" className="text-xs font-medium text-neutral-600">
              Vendor category (blank = any)
            </label>
            <input id="vendorCategory" name="vendorCategory" type="text" placeholder="trucking, warehousing…" className="rounded-md border border-neutral-300 px-3 py-1.5 text-sm" />
          </div>
          <div className="flex flex-col gap-1">
            <label htmlFor="validityPeriodDays" className="text-xs font-medium text-neutral-600">
              Validity period (days)
            </label>
            <input id="validityPeriodDays" name="validityPeriodDays" type="number" min={1} defaultValue={180} required className="rounded-md border border-neutral-300 px-3 py-1.5 text-sm" />
          </div>
          <div className="flex flex-col gap-1">
            <label htmlFor="passThreshold" className="text-xs font-medium text-neutral-600">
              Pass threshold
            </label>
            <input id="passThreshold" name="passThreshold" type="number" min={0} max={100} defaultValue={80} required className="rounded-md border border-neutral-300 px-3 py-1.5 text-sm" />
          </div>
          <div className="flex flex-col gap-1">
            <label htmlFor="conditionalThreshold" className="text-xs font-medium text-neutral-600">
              Conditional threshold
            </label>
            <input id="conditionalThreshold" name="conditionalThreshold" type="number" min={0} max={100} defaultValue={60} required className="rounded-md border border-neutral-300 px-3 py-1.5 text-sm" />
          </div>
          <div className="col-span-full flex flex-col gap-1">
            <label htmlFor="description" className="text-xs font-medium text-neutral-600">
              Description (optional)
            </label>
            <textarea id="description" name="description" rows={2} className="rounded-md border border-neutral-300 px-3 py-1.5 text-sm" />
          </div>

          {state.error ? (
            <p role="alert" className="col-span-full text-sm text-danger">
              {state.error}
            </p>
          ) : null}

          <div className="col-span-full">
            <Button type="submit" loading={pending} loadingLabel="Creating…">
              Create draft
            </Button>
          </div>
        </form>
      </section>
    </div>
  );
}
