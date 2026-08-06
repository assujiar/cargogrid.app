"use client";

import { useActionState } from "react";
import { Button } from "../../../../../../../components/ui/button.tsx";
import { StatusBadge, type StatusTone } from "../../../../../../../components/ui/status-badge.tsx";
import { EmptyState } from "../../../../../../../components/ui/empty-state.tsx";
import type { TemplateActionState } from "../actions.ts";
import type { VendorAssessmentTemplate, VendorAssessmentTemplateCriterion, VendorAssessmentTemplateStatus } from "../../../../../../../server/contracts/vendor-assessment/vendor-assessment.ts";

const INITIAL_STATE: TemplateActionState = { error: null };

const STATUS_TONE: Record<VendorAssessmentTemplateStatus, StatusTone> = {
  draft: "neutral",
  published: "success",
  archived: "neutral",
};

type BoundFormAction = (prevState: TemplateActionState, formData: FormData) => Promise<TemplateActionState>;

function ActionForm({
  action,
  children,
  submitLabel,
  loadingLabel,
  variant = "primary",
}: {
  action: BoundFormAction;
  children?: React.ReactNode;
  submitLabel: string;
  loadingLabel?: string;
  variant?: "primary" | "secondary" | "destructive";
}) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col gap-2">
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

export function TemplateDetailPanel({
  tenantSlug: _tenantSlug,
  template,
  criteria,
  currentPublished,
  updateDraftAction,
  addCriterionAction,
  removeCriterionActionFor,
  publishAction,
  archiveAction,
}: {
  tenantSlug: string;
  template: VendorAssessmentTemplate;
  criteria: readonly VendorAssessmentTemplateCriterion[];
  currentPublished: VendorAssessmentTemplate | null;
  updateDraftAction: BoundFormAction;
  addCriterionAction: BoundFormAction;
  removeCriterionActionFor: (criterionId: string, expectedVersion: number) => BoundFormAction;
  publishAction: BoundFormAction;
  archiveAction: BoundFormAction;
}) {
  const weightSum = criteria.reduce((sum, c) => sum + c.weight, 0);
  const weightOk = Math.abs(weightSum - template.weightTotalRequired) <= 0.01;
  const isDraft = template.status === "draft";
  const isPublished = template.status === "published";

  return (
    <div className="flex flex-col gap-6">
      <header className="flex flex-wrap items-center gap-2">
        <h1 className="text-xl font-semibold text-neutral-900">{template.name}</h1>
        <StatusBadge tone={STATUS_TONE[template.status]} label={template.status} />
      </header>
      <p className="text-xs text-neutral-500">
        {template.assessmentType} · {template.vendorCategory ?? "any category"} · validity {template.validityPeriodDays} days · pass ≥ {template.passThreshold} · conditional ≥ {template.conditionalThreshold}
      </p>

      {isDraft ? (
        <section className="rounded-md border border-neutral-200 p-4">
          <ActionForm action={updateDraftAction} submitLabel="Save changes" loadingLabel="Saving…" variant="secondary">
            <div className="grid grid-cols-1 gap-2 sm:grid-cols-3">
              <input name="name" defaultValue={template.name} required className="rounded-md border border-neutral-300 px-2 py-1 text-sm" />
              <input name="vendorCategory" defaultValue={template.vendorCategory ?? ""} placeholder="Vendor category (blank = any)" className="rounded-md border border-neutral-300 px-2 py-1 text-sm" />
              <input name="validityPeriodDays" type="number" min={1} defaultValue={template.validityPeriodDays} required className="rounded-md border border-neutral-300 px-2 py-1 text-sm" />
              <input name="passThreshold" type="number" min={0} max={100} defaultValue={template.passThreshold} required className="rounded-md border border-neutral-300 px-2 py-1 text-sm" />
              <input name="conditionalThreshold" type="number" min={0} max={100} defaultValue={template.conditionalThreshold} required className="rounded-md border border-neutral-300 px-2 py-1 text-sm" />
              <textarea name="description" defaultValue={template.description ?? ""} rows={2} className="rounded-md border border-neutral-300 px-2 py-1 text-sm sm:col-span-3" />
            </div>
          </ActionForm>
        </section>
      ) : null}

      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        <div className="flex items-center justify-between">
          <h2 className="text-sm font-semibold text-neutral-900">Criteria</h2>
          <p className={`text-xs ${weightOk ? "text-success" : "text-warning"}`}>
            Weight sum: {weightSum.toFixed(2)} / {template.weightTotalRequired.toFixed(2)} {weightOk ? "✓" : "(must match to publish)"}
          </p>
        </div>

        {criteria.length === 0 ? (
          <EmptyState title="No criteria yet" description={isDraft ? "Add at least one below before publishing." : undefined} />
        ) : (
          <ul className="flex flex-col gap-2">
            {criteria.map((c) => (
              <li key={c.id} className="flex items-center justify-between rounded-md border border-neutral-100 p-2 text-sm">
                <div>
                  <p className="font-medium text-neutral-900">{c.label}</p>
                  <p className="text-xs text-neutral-500">
                    weight {c.weight} · {c.purposeTag}
                    {c.scoringGuidance ? ` · ${c.scoringGuidance}` : ""}
                  </p>
                </div>
                {isDraft ? (
                  <ActionForm action={removeCriterionActionFor(c.id, c.recordVersion)} submitLabel="Remove" loadingLabel="Removing…" variant="destructive" />
                ) : null}
              </li>
            ))}
          </ul>
        )}

        {isDraft ? (
          <ActionForm action={addCriterionAction} submitLabel="Add criterion" loadingLabel="Adding…" variant="secondary">
            <div className="grid grid-cols-1 gap-2 sm:grid-cols-4">
              <input name="label" placeholder="Label" required className="rounded-md border border-neutral-300 px-2 py-1 text-sm sm:col-span-2" />
              <select name="purposeTag" defaultValue="operational" className="rounded-md border border-neutral-300 px-2 py-1 text-sm">
                <option value="operational">Operational</option>
                <option value="safety">Safety</option>
                <option value="financial">Financial</option>
                <option value="compliance">Compliance</option>
              </select>
              <input name="weight" type="number" min={0.01} step="0.01" placeholder="Weight" required className="rounded-md border border-neutral-300 px-2 py-1 text-sm" />
              <input name="scoringGuidance" placeholder="Scoring guidance (optional)" className="rounded-md border border-neutral-300 px-2 py-1 text-sm sm:col-span-4" />
            </div>
          </ActionForm>
        ) : null}
      </section>

      {isDraft ? (
        <section className="rounded-md border border-neutral-200 p-4">
          <h2 className="mb-2 text-sm font-semibold text-neutral-900">Publish</h2>
          {currentPublished ? <p className="mb-2 text-xs text-neutral-500">A published template already exists for this scope ({currentPublished.name}) — publishing this draft will supersede (archive) it.</p> : null}
          <ActionForm action={publishAction} submitLabel="Publish" loadingLabel="Publishing…">
            {currentPublished ? <input type="hidden" name="supersedesVersionId" value={currentPublished.id} /> : null}
          </ActionForm>
        </section>
      ) : null}

      {isPublished ? (
        <section className="rounded-md border border-neutral-200 p-4">
          <h2 className="mb-2 text-sm font-semibold text-neutral-900">Archive</h2>
          <ActionForm action={archiveAction} submitLabel="Archive template" loadingLabel="Archiving…" variant="destructive">
            <input name="reason" placeholder="Reason (required)" required className="rounded-md border border-neutral-300 px-2 py-1 text-sm" />
          </ActionForm>
        </section>
      ) : null}
    </div>
  );
}
