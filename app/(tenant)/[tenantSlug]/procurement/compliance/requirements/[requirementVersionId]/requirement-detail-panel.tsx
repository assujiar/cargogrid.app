"use client";

import { useActionState, useId } from "react";
import { Button } from "../../../../../../../components/ui/button.tsx";
import { StatusBadge, type StatusTone } from "../../../../../../../components/ui/status-badge.tsx";
import { Input } from "../../../../../../../components/forms/input.tsx";
import { Select } from "../../../../../../../components/forms/select.tsx";
import { Textarea } from "../../../../../../../components/forms/textarea.tsx";
import { Checkbox } from "../../../../../../../components/forms/checkbox.tsx";
import { ValidationMessage } from "../../../../../../../components/forms/validation-message.tsx";
import type { ComplianceActionState } from "../../actions.ts";
import type { VendorComplianceRequirement, VendorComplianceRequirementStatus } from "../../../../../../../server/contracts/vendor-compliance/vendor-compliance.ts";

const INITIAL_STATE: ComplianceActionState = { error: null };

const STATUS_TONE: Record<VendorComplianceRequirementStatus, StatusTone> = {
  draft: "neutral",
  published: "success",
  archived: "neutral",
};

type BoundFormAction = (prevState: ComplianceActionState, formData: FormData) => Promise<ComplianceActionState>;

function ActionForm({
  action,
  children,
  submitLabel,
  loadingLabel,
  variant = "primary",
}: {
  action: BoundFormAction;
  children?: (describedBy: string | undefined) => React.ReactNode;
  submitLabel: string;
  loadingLabel?: string;
  variant?: "primary" | "secondary" | "destructive";
}) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  const reactId = useId();
  const errorId = `${reactId}-error`;
  const describedBy = state.error ? errorId : undefined;
  return (
    <form action={formAction} className="flex flex-col gap-2">
      {children?.(describedBy)}
      {state.error ? <ValidationMessage id={errorId}>{state.error}</ValidationMessage> : null}
      <Button type="submit" variant={variant} loading={pending} loadingLabel={loadingLabel ?? "Working…"} className="w-fit">
        {submitLabel}
      </Button>
    </form>
  );
}

export function RequirementDetailPanel({
  requirement,
  currentPublished,
  updateDraftAction,
  publishAction,
  archiveAction,
}: {
  requirement: VendorComplianceRequirement;
  currentPublished: VendorComplianceRequirement | null;
  updateDraftAction: BoundFormAction;
  publishAction: BoundFormAction;
  archiveAction: BoundFormAction;
}) {
  const isDraft = requirement.status === "draft";
  const isPublished = requirement.status === "published";

  return (
    <div className="flex flex-col gap-6">
      <header className="flex flex-wrap items-center gap-2">
        <h1 className="text-xl font-semibold text-neutral-900">{requirement.name}</h1>
        <StatusBadge tone={STATUS_TONE[requirement.status]} label={requirement.status} />
        <StatusBadge tone={requirement.blockingEffect === "blocking" ? "danger" : "neutral"} label={requirement.blockingEffect} />
      </header>
      <p className="text-xs text-neutral-500">
        {requirement.vendorCategory ?? "any category"} / {requirement.serviceType ?? "any service"} · document type {requirement.documentTypeCode} ·{" "}
        {requirement.requiresExpiry ? `reminders at ${requirement.reminderOffsets.join(", ") || "none"} day(s) before expiry` : "does not track expiry"}
      </p>
      {requirement.description ? <p className="text-sm text-neutral-700">{requirement.description}</p> : null}

      {isDraft ? (
        <section className="rounded-md border border-neutral-200 p-4">
          <h2 className="mb-2 text-sm font-semibold text-neutral-900">Edit draft</h2>
          <ActionForm action={updateDraftAction} submitLabel="Save changes" loadingLabel="Saving…" variant="secondary">
            {(describedBy) => (
              <div className="grid grid-cols-1 gap-2 sm:grid-cols-3">
                <label htmlFor="requirement-name" className="sr-only">
                  Name
                </label>
                <Input id="requirement-name" name="name" defaultValue={requirement.name} required aria-describedby={describedBy} />
                <label htmlFor="requirement-document-type-code" className="sr-only">
                  Document type code
                </label>
                <Input id="requirement-document-type-code" name="documentTypeCode" defaultValue={requirement.documentTypeCode} required aria-describedby={describedBy} />
                <label htmlFor="requirement-vendor-category" className="sr-only">
                  Vendor category
                </label>
                <Input id="requirement-vendor-category" name="vendorCategory" defaultValue={requirement.vendorCategory ?? ""} placeholder="Vendor category (blank = any)" aria-describedby={describedBy} />
                <label htmlFor="requirement-service-type" className="sr-only">
                  Service type
                </label>
                <Input id="requirement-service-type" name="serviceType" defaultValue={requirement.serviceType ?? ""} placeholder="Service type (blank = any)" aria-describedby={describedBy} />
                <label htmlFor="requirement-blocking-effect" className="sr-only">
                  Blocking effect
                </label>
                <Select id="requirement-blocking-effect" name="blockingEffect" defaultValue={requirement.blockingEffect} aria-describedby={describedBy}>
                  <option value="blocking">Blocking</option>
                  <option value="warning">Warning</option>
                </Select>
                <label htmlFor="requirement-reminder-offsets" className="sr-only">
                  Reminder offsets
                </label>
                <Input id="requirement-reminder-offsets" name="reminderOffsets" defaultValue={requirement.reminderOffsets.join(",")} aria-describedby={describedBy} />
                <Checkbox id="requiresExpiry" name="requiresExpiry" defaultChecked={requirement.requiresExpiry} label="Tracks expiry" aria-describedby={describedBy} />
                <label htmlFor="requirement-description" className="sr-only">
                  Description
                </label>
                <Textarea id="requirement-description" name="description" defaultValue={requirement.description ?? ""} rows={2} className="sm:col-span-3" aria-describedby={describedBy} />
              </div>
            )}
          </ActionForm>
        </section>
      ) : null}

      {isDraft ? (
        <section className="rounded-md border border-neutral-200 p-4">
          <h2 className="mb-2 text-sm font-semibold text-neutral-900">Publish</h2>
          {currentPublished ? (
            <p className="mb-2 text-xs text-neutral-500">A published requirement already exists for this scope ({currentPublished.name}) — publishing this draft will supersede (archive) it, carrying its own compliance history forward.</p>
          ) : null}
          <ActionForm action={publishAction} submitLabel="Publish" loadingLabel="Publishing…">
            {() => (currentPublished ? <input type="hidden" name="supersedesVersionId" value={currentPublished.id} /> : null)}
          </ActionForm>
        </section>
      ) : null}

      {isPublished ? (
        <section className="rounded-md border border-neutral-200 p-4">
          <h2 className="mb-2 text-sm font-semibold text-neutral-900">Archive</h2>
          <p className="mb-2 text-xs text-neutral-500">Archiving removes this requirement from active enforcement without a replacement. Existing vendor compliance holds clear on the next recalculation.</p>
          <ActionForm action={archiveAction} submitLabel="Archive requirement" loadingLabel="Archiving…" variant="destructive">
            {(describedBy) => (
              <>
                <label htmlFor="requirement-archive-reason" className="sr-only">
                  Reason
                </label>
                <Input id="requirement-archive-reason" name="reason" placeholder="Reason (required)" required aria-describedby={describedBy} />
              </>
            )}
          </ActionForm>
        </section>
      ) : null}
    </div>
  );
}
