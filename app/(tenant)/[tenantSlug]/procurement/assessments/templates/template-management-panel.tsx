"use client";

import { useActionState } from "react";
import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { Button } from "../../../../../../components/ui/button.tsx";
import { Input } from "../../../../../../components/forms/input.tsx";
import { Select } from "../../../../../../components/forms/select.tsx";
import { Textarea } from "../../../../../../components/forms/textarea.tsx";
import { FormField } from "../../../../../../components/forms/form-field.tsx";
import { ValidationMessage } from "../../../../../../components/forms/validation-message.tsx";
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
  const templateErrorId = "template-create-error";
  const templateDescribedBy = state.error ? templateErrorId : undefined;

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
          <Select id="template-status" defaultValue={statusFilter ?? ""} className="w-fit py-1.5" onChange={(event) => applyFilter(event.currentTarget.value)}>
            <option value="">All statuses</option>
            {VENDOR_ASSESSMENT_TEMPLATE_STATUSES.map((s) => (
              <option key={s} value={s}>
                {s}
              </option>
            ))}
          </Select>
        </div>

        {templates.length === 0 ? (
          <EmptyState title="No templates match this view" description="Create a new draft template below." />
        ) : (
          <div className="overflow-x-auto">
          <table className="w-full min-w-[480px] text-sm">
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
          </div>
        )}
      </section>

      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Create a new template draft</h2>
        <form action={formAction} className="grid grid-cols-1 gap-3 sm:grid-cols-3" noValidate>
          <FormField id="name" label="Name">
            <Input id="name" name="name" type="text" required invalid={Boolean(state.error)} aria-describedby={templateDescribedBy} />
          </FormField>
          <FormField id="assessmentType" label="Assessment type">
            <Select id="assessmentType" name="assessmentType" required invalid={Boolean(state.error)} aria-describedby={templateDescribedBy}>
              {VENDOR_ASSESSMENT_TYPES.map((t) => (
                <option key={t} value={t}>
                  {t}
                </option>
              ))}
            </Select>
          </FormField>
          <FormField id="vendorCategory" label="Vendor category (blank = any)">
            <Input id="vendorCategory" name="vendorCategory" type="text" placeholder="trucking, warehousing…" invalid={Boolean(state.error)} aria-describedby={templateDescribedBy} />
          </FormField>
          <FormField id="validityPeriodDays" label="Validity period (days)">
            <Input id="validityPeriodDays" name="validityPeriodDays" type="number" min={1} defaultValue={180} required invalid={Boolean(state.error)} aria-describedby={templateDescribedBy} />
          </FormField>
          <FormField id="passThreshold" label="Pass threshold">
            <Input id="passThreshold" name="passThreshold" type="number" min={0} max={100} defaultValue={80} required invalid={Boolean(state.error)} aria-describedby={templateDescribedBy} />
          </FormField>
          <FormField id="conditionalThreshold" label="Conditional threshold">
            <Input id="conditionalThreshold" name="conditionalThreshold" type="number" min={0} max={100} defaultValue={60} required invalid={Boolean(state.error)} aria-describedby={templateDescribedBy} />
          </FormField>
          <div className="col-span-full">
            <FormField id="description" label="Description (optional)">
              <Textarea id="description" name="description" rows={2} invalid={Boolean(state.error)} aria-describedby={templateDescribedBy} />
            </FormField>
          </div>

          {state.error ? (
            <div className="col-span-full">
              <ValidationMessage id={templateErrorId}>{state.error}</ValidationMessage>
            </div>
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
