"use client";

import { useActionState } from "react";
import { Button } from "../../../../../../../components/ui/button.tsx";
import { StatusBadge, type StatusTone } from "../../../../../../../components/ui/status-badge.tsx";
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
            <div className="grid grid-cols-1 gap-2 sm:grid-cols-3">
              <input name="name" defaultValue={requirement.name} required className="rounded-md border border-neutral-300 px-2 py-1 text-sm" />
              <input name="documentTypeCode" defaultValue={requirement.documentTypeCode} required className="rounded-md border border-neutral-300 px-2 py-1 text-sm" />
              <input name="vendorCategory" defaultValue={requirement.vendorCategory ?? ""} placeholder="Vendor category (blank = any)" className="rounded-md border border-neutral-300 px-2 py-1 text-sm" />
              <input name="serviceType" defaultValue={requirement.serviceType ?? ""} placeholder="Service type (blank = any)" className="rounded-md border border-neutral-300 px-2 py-1 text-sm" />
              <select name="blockingEffect" defaultValue={requirement.blockingEffect} className="rounded-md border border-neutral-300 px-2 py-1 text-sm">
                <option value="blocking">Blocking</option>
                <option value="warning">Warning</option>
              </select>
              <input name="reminderOffsets" defaultValue={requirement.reminderOffsets.join(",")} className="rounded-md border border-neutral-300 px-2 py-1 text-sm" />
              <div className="flex items-center gap-2">
                <input id="requiresExpiry" name="requiresExpiry" type="checkbox" defaultChecked={requirement.requiresExpiry} className="h-4 w-4" />
                <label htmlFor="requiresExpiry" className="text-xs font-medium text-neutral-600">
                  Tracks expiry
                </label>
              </div>
              <textarea name="description" defaultValue={requirement.description ?? ""} rows={2} className="rounded-md border border-neutral-300 px-2 py-1 text-sm sm:col-span-3" />
            </div>
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
            {currentPublished ? <input type="hidden" name="supersedesVersionId" value={currentPublished.id} /> : null}
          </ActionForm>
        </section>
      ) : null}

      {isPublished ? (
        <section className="rounded-md border border-neutral-200 p-4">
          <h2 className="mb-2 text-sm font-semibold text-neutral-900">Archive</h2>
          <p className="mb-2 text-xs text-neutral-500">Archiving removes this requirement from active enforcement without a replacement. Existing vendor compliance holds clear on the next recalculation.</p>
          <ActionForm action={archiveAction} submitLabel="Archive requirement" loadingLabel="Archiving…" variant="destructive">
            <input name="reason" placeholder="Reason (required)" required className="rounded-md border border-neutral-300 px-2 py-1 text-sm" />
          </ActionForm>
        </section>
      ) : null}
    </div>
  );
}
