"use client";

import { useActionState, useId } from "react";
import { Button } from "../../../../../../../components/ui/button.tsx";
import { StatusBadge, type StatusTone } from "../../../../../../../components/ui/status-badge.tsx";
import { FormField } from "../../../../../../../components/forms/form-field.tsx";
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
  children?: (describedBy: string | undefined, invalid: boolean) => React.ReactNode;
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
      {children?.(describedBy, Boolean(state.error))}
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
            {(describedBy, invalid) => (
              <div className="grid grid-cols-1 gap-2 sm:grid-cols-3">
                <FormField id="requirement-name" label={<span className="sr-only">Name</span>}>
                  <Input id="requirement-name" name="name" defaultValue={requirement.name} required invalid={invalid} aria-describedby={describedBy} />
                </FormField>
                <FormField id="requirement-document-type-code" label={<span className="sr-only">Document type code</span>}>
                  <Input id="requirement-document-type-code" name="documentTypeCode" defaultValue={requirement.documentTypeCode} required invalid={invalid} aria-describedby={describedBy} />
                </FormField>
                <FormField id="requirement-vendor-category" label={<span className="sr-only">Vendor category</span>}>
                  <Input
                    id="requirement-vendor-category"
                    name="vendorCategory"
                    defaultValue={requirement.vendorCategory ?? ""}
                    placeholder="Vendor category (blank = any)"
                    invalid={invalid}
                    aria-describedby={describedBy}
                  />
                </FormField>
                <FormField id="requirement-service-type" label={<span className="sr-only">Service type</span>}>
                  <Input
                    id="requirement-service-type"
                    name="serviceType"
                    defaultValue={requirement.serviceType ?? ""}
                    placeholder="Service type (blank = any)"
                    invalid={invalid}
                    aria-describedby={describedBy}
                  />
                </FormField>
                <FormField id="requirement-blocking-effect" label={<span className="sr-only">Blocking effect</span>}>
                  <Select id="requirement-blocking-effect" name="blockingEffect" defaultValue={requirement.blockingEffect} invalid={invalid} aria-describedby={describedBy}>
                    <option value="blocking">Blocking</option>
                    <option value="warning">Warning</option>
                  </Select>
                </FormField>
                <FormField id="requirement-reminder-offsets" label={<span className="sr-only">Reminder offsets</span>}>
                  <Input id="requirement-reminder-offsets" name="reminderOffsets" defaultValue={requirement.reminderOffsets.join(",")} invalid={invalid} aria-describedby={describedBy} />
                </FormField>
                <Checkbox id="requiresExpiry" name="requiresExpiry" defaultChecked={requirement.requiresExpiry} label="Tracks expiry" aria-describedby={describedBy} />
                <div className="sm:col-span-3">
                  <FormField id="requirement-description" label={<span className="sr-only">Description</span>}>
                    <Textarea id="requirement-description" name="description" defaultValue={requirement.description ?? ""} rows={2} invalid={invalid} aria-describedby={describedBy} />
                  </FormField>
                </div>
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
            {(describedBy, invalid) => (
              <FormField id="requirement-archive-reason" label={<span className="sr-only">Reason</span>}>
                <Input id="requirement-archive-reason" name="reason" placeholder="Reason (required)" required invalid={invalid} aria-describedby={describedBy} />
              </FormField>
            )}
          </ActionForm>
        </section>
      ) : null}
    </div>
  );
}
