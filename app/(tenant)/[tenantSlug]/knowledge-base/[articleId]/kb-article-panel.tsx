"use client";

import { useActionState } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
import { Input } from "../../../../../components/forms/input.tsx";
import { Textarea } from "../../../../../components/forms/textarea.tsx";
import { Checkbox } from "../../../../../components/forms/checkbox.tsx";
import { FormField } from "../../../../../components/forms/form-field.tsx";
import { ValidationMessage } from "../../../../../components/forms/validation-message.tsx";
import { StatusBadge, type StatusTone } from "../../../../../components/ui/status-badge.tsx";
import type { KbActionState } from "../actions.ts";
import type { KbArticleVersionSummaryRow, KbArticleVersionRow, KbArticleStatus, KbReviewDecision } from "../../../../../server/contracts/knowledge-base/knowledge-base.ts";

const INITIAL_STATE: KbActionState = { error: null };

const STATUS_TONE: Record<KbArticleStatus, StatusTone> = {
  draft: "neutral",
  in_review: "warning",
  approved: "info",
  published: "success",
  archived: "neutral",
};

type BoundAction = (prevState: KbActionState, formData: FormData) => Promise<KbActionState>;

function VersionEditor({ full, updateVersionAction }: { full: KbArticleVersionRow; updateVersionAction: (versionId: string, expectedVersion: number) => BoundAction }) {
  const [state, formAction, pending] = useActionState(updateVersionAction(full.id, full.recordVersion), INITIAL_STATE);
  // One editor per version card, all on the same page -- every id is version-scoped.
  const errorId = `kb-version-editor-${full.id}-error`;
  const describedBy = state.error ? errorId : undefined;
  return (
    <form action={formAction} className="flex flex-col gap-2 rounded bg-neutral-50 p-3">
      <FormField id={`kb-edit-title-${full.id}`} label="Title">
        <Input id={`kb-edit-title-${full.id}`} name="title" required defaultValue={full.title} invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <FormField id={`kb-edit-summary-${full.id}`} label="Summary">
        <Input id={`kb-edit-summary-${full.id}`} name="summary" defaultValue={full.summary ?? ""} invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <FormField id={`kb-edit-body-${full.id}`} label="Body">
        <Textarea id={`kb-edit-body-${full.id}`} name="body" required rows={6} defaultValue={full.body} invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <FormField id={`kb-edit-tags-${full.id}`} label="Tags (comma-separated)">
        <Input id={`kb-edit-tags-${full.id}`} name="tags" defaultValue={full.tags.join(", ")} invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <div className="flex flex-wrap gap-3 text-xs text-neutral-600">
        <Checkbox id={`kb-edit-audience-internal-${full.id}`} name="audienceInternal" defaultChecked={full.audienceInternal} label="Internal" aria-describedby={describedBy} />
        <Checkbox id={`kb-edit-audience-customer-${full.id}`} name="audienceCustomer" defaultChecked={full.audienceCustomer} label="Customer" aria-describedby={describedBy} />
        <Checkbox id={`kb-edit-audience-helpdesk-${full.id}`} name="audienceHelpdesk" defaultChecked={full.audienceHelpdesk} label="Helpdesk" aria-describedby={describedBy} />
      </div>
      <div>
        <Button type="submit" variant="secondary" loading={pending} loadingLabel="Saving…">
          Save draft
        </Button>
      </div>
      {state.error ? <ValidationMessage id={errorId}>{state.error}</ValidationMessage> : null}
    </form>
  );
}

function SubmitForReviewForm({ versionId, expectedVersion, submitForReviewAction }: { versionId: string; expectedVersion: number; submitForReviewAction: (versionId: string, expectedVersion: number) => BoundAction }) {
  const [state, formAction, pending] = useActionState(submitForReviewAction(versionId, expectedVersion), INITIAL_STATE);
  const fieldId = `kb-reviewer-${versionId}`;
  const errorId = `kb-submit-review-${versionId}-error`;
  return (
    <form action={formAction} className="flex flex-wrap items-end gap-2 rounded bg-neutral-50 p-2">
      <FormField id={fieldId} label="Reviewer (auth user id -- not the author)">
        <Input
          id={fieldId}
          name="reviewerAuthUserId"
          required
          placeholder="UUID"
          className="min-w-[16rem]"
          invalid={Boolean(state.error)}
          aria-describedby={state.error ? errorId : undefined}
        />
      </FormField>
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Submitting…">
        Submit for review
      </Button>
      {state.error ? (
        <div className="w-full">
          <ValidationMessage id={errorId}>{state.error}</ValidationMessage>
        </div>
      ) : null}
    </form>
  );
}

function ReviewForm({ versionId, expectedVersion, decision, label, variant, reviewAction }: { versionId: string; expectedVersion: number; decision: KbReviewDecision; label: string; variant: "primary" | "destructive"; reviewAction: (versionId: string, expectedVersion: number, decision: KbReviewDecision) => BoundAction }) {
  const [state, formAction, pending] = useActionState(reviewAction(versionId, expectedVersion, decision), INITIAL_STATE);
  // Two review forms per in-review version, so the id carries both the version and the decision.
  const fieldId = `kb-review-notes-${versionId}-${decision}`;
  const errorId = `kb-review-${versionId}-${decision}-error`;
  return (
    <form action={formAction} className="flex flex-wrap items-end gap-2">
      <FormField id={fieldId} label={<span className="sr-only">Notes for &ldquo;{label}&rdquo;</span>}>
        <Input
          id={fieldId}
          name="notes"
          placeholder="Notes (optional)"
          className="min-w-[10rem]"
          invalid={Boolean(state.error)}
          aria-describedby={state.error ? errorId : undefined}
        />
      </FormField>
      <Button type="submit" variant={variant} loading={pending} loadingLabel="Recording…">
        {label}
      </Button>
      {state.error ? <ValidationMessage id={errorId}>{state.error}</ValidationMessage> : null}
    </form>
  );
}

function SetExpiryForm({ versionId, expectedVersion, setExpiryAction }: { versionId: string; expectedVersion: number; setExpiryAction: (versionId: string, expectedVersion: number) => BoundAction }) {
  const [state, formAction, pending] = useActionState(setExpiryAction(versionId, expectedVersion), INITIAL_STATE);
  const fieldId = `kb-expires-at-${versionId}`;
  const errorId = `kb-set-expiry-${versionId}-error`;
  return (
    <form action={formAction} className="flex flex-wrap items-end gap-2 rounded bg-neutral-50 p-2">
      {/* `datetime-local`, not `date` -- an expiry is a real instant, so `DateInput`
          (which pins `type="date"`) would drop the time half of this value. */}
      <FormField id={fieldId} label="Expires at (blank = never)">
        <Input id={fieldId} name="expiresAt" type="datetime-local" invalid={Boolean(state.error)} aria-describedby={state.error ? errorId : undefined} />
      </FormField>
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Saving…">
        Set expiry
      </Button>
      {state.error ? (
        <div className="w-full">
          <ValidationMessage id={errorId}>{state.error}</ValidationMessage>
        </div>
      ) : null}
    </form>
  );
}

function PublishForm({ versionId, expectedVersion, publishAction }: { versionId: string; expectedVersion: number; publishAction: (versionId: string, expectedVersion: number) => BoundAction }) {
  const [state, formAction, pending] = useActionState(publishAction(versionId, expectedVersion), INITIAL_STATE);
  return (
    <form action={formAction}>
      <Button type="submit" variant="primary" loading={pending} loadingLabel="Publishing…">
        Publish
      </Button>
      {state.error ? (
        <p role="alert" className="text-xs text-danger">
          {state.error}
        </p>
      ) : null}
    </form>
  );
}

function ArchiveForm({ versionId, expectedVersion, archiveAction }: { versionId: string; expectedVersion: number; archiveAction: (versionId: string, expectedVersion: number) => BoundAction }) {
  const [state, formAction, pending] = useActionState(archiveAction(versionId, expectedVersion), INITIAL_STATE);
  const fieldId = `kb-archive-reason-${versionId}`;
  const errorId = `kb-archive-${versionId}-error`;
  return (
    <form action={formAction} className="flex flex-wrap items-end gap-2">
      <FormField id={fieldId} label={<span className="sr-only">Reason for archiving this version</span>}>
        <Input
          id={fieldId}
          name="reason"
          required
          placeholder="Reason (required)"
          className="min-w-[10rem]"
          invalid={Boolean(state.error)}
          aria-describedby={state.error ? errorId : undefined}
        />
      </FormField>
      <Button type="submit" variant="destructive" loading={pending} loadingLabel="Archiving…">
        Archive
      </Button>
      {state.error ? <ValidationMessage id={errorId}>{state.error}</ValidationMessage> : null}
    </form>
  );
}

function VersionCard({
  summary,
  full,
  updateVersionAction,
  submitForReviewAction,
  reviewAction,
  publishAction,
  archiveAction,
  setExpiryAction,
}: {
  summary: KbArticleVersionSummaryRow;
  full: KbArticleVersionRow | null;
  updateVersionAction: (versionId: string, expectedVersion: number) => BoundAction;
  submitForReviewAction: (versionId: string, expectedVersion: number) => BoundAction;
  reviewAction: (versionId: string, expectedVersion: number, decision: KbReviewDecision) => BoundAction;
  publishAction: (versionId: string, expectedVersion: number) => BoundAction;
  archiveAction: (versionId: string, expectedVersion: number) => BoundAction;
  setExpiryAction: (versionId: string, expectedVersion: number) => BoundAction;
}) {
  return (
    <div className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
      <div className="flex flex-wrap items-center gap-2">
        <StatusBadge tone={STATUS_TONE[summary.status]} label={summary.status.replace(/_/g, " ")} />
        <h3 className="text-sm font-semibold text-neutral-900">v{summary.versionNumber}: {summary.title}</h3>
      </div>
      <div className="flex flex-wrap gap-2 text-xs text-neutral-500">
        {summary.audienceInternal ? <StatusBadge tone="neutral" label="internal" /> : null}
        {summary.audienceCustomer ? <StatusBadge tone="neutral" label="customer" /> : null}
        {summary.audienceHelpdesk ? <StatusBadge tone="neutral" label="helpdesk" /> : null}
        {summary.reviewerLabel ? <span>Reviewer: {summary.reviewerLabel}</span> : null}
        {summary.reviewDecision ? <span>Decision: {summary.reviewDecision.replace(/_/g, " ")}</span> : null}
      </div>

      {summary.status === "draft" && full ? (
        <>
          <VersionEditor full={full} updateVersionAction={updateVersionAction} />
          <SubmitForReviewForm versionId={summary.id} expectedVersion={summary.recordVersion} submitForReviewAction={submitForReviewAction} />
        </>
      ) : null}

      {summary.status === "in_review" ? (
        <div className="flex flex-wrap gap-3">
          <ReviewForm versionId={summary.id} expectedVersion={summary.recordVersion} decision="approved" label="Approve" variant="primary" reviewAction={reviewAction} />
          <ReviewForm versionId={summary.id} expectedVersion={summary.recordVersion} decision="changes_requested" label="Request changes" variant="destructive" reviewAction={reviewAction} />
        </div>
      ) : null}

      {summary.status === "approved" ? <PublishForm versionId={summary.id} expectedVersion={summary.recordVersion} publishAction={publishAction} /> : null}

      {summary.status === "published" ? <SetExpiryForm versionId={summary.id} expectedVersion={summary.recordVersion} setExpiryAction={setExpiryAction} /> : null}

      {summary.status !== "archived" ? <ArchiveForm versionId={summary.id} expectedVersion={summary.recordVersion} archiveAction={archiveAction} /> : null}

      {full && (summary.status === "published" || summary.status === "approved" || summary.status === "in_review") ? (
        <div className="rounded bg-neutral-50 p-3 text-sm">
          {full.summary ? <p className="text-neutral-600">{full.summary}</p> : null}
          <p className="whitespace-pre-wrap text-neutral-900">{full.body}</p>
        </div>
      ) : null}
    </div>
  );
}

function NewVersionForm({ createVersionAction }: { createVersionAction: BoundAction }) {
  const [state, formAction, pending] = useActionState(createVersionAction, INITIAL_STATE);
  const describedBy = state.error ? "kb-new-version-error" : undefined;
  return (
    <form action={formAction} className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
      <h3 className="text-sm font-semibold text-neutral-900">New draft version</h3>
      <FormField id="kb-new-title" label="Title">
        <Input id="kb-new-title" name="title" required invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <FormField id="kb-new-summary" label="Summary">
        <Input id="kb-new-summary" name="summary" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <FormField id="kb-new-body" label="Body">
        <Textarea id="kb-new-body" name="body" required rows={6} invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <FormField id="kb-new-tags" label="Tags (comma-separated)">
        <Input id="kb-new-tags" name="tags" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <div className="flex flex-wrap gap-3 text-xs text-neutral-600">
        <Checkbox id="kb-new-audience-internal" name="audienceInternal" label="Internal" aria-describedby={describedBy} />
        <Checkbox id="kb-new-audience-customer" name="audienceCustomer" label="Customer" aria-describedby={describedBy} />
        <Checkbox id="kb-new-audience-helpdesk" name="audienceHelpdesk" label="Helpdesk" aria-describedby={describedBy} />
      </div>
      <div>
        <Button type="submit" variant="primary" loading={pending} loadingLabel="Creating…">
          Create draft version
        </Button>
      </div>
      {state.error ? <ValidationMessage id="kb-new-version-error">{state.error}</ValidationMessage> : null}
    </form>
  );
}

export function KbArticlePanel({
  versions,
  fullVersionById,
  createVersionAction,
  updateVersionAction,
  submitForReviewAction,
  reviewAction,
  publishAction,
  archiveAction,
  setExpiryAction,
}: {
  versions: readonly KbArticleVersionSummaryRow[];
  fullVersionById: Record<string, KbArticleVersionRow | null>;
  createVersionAction: BoundAction;
  updateVersionAction: (versionId: string, expectedVersion: number) => BoundAction;
  submitForReviewAction: (versionId: string, expectedVersion: number) => BoundAction;
  reviewAction: (versionId: string, expectedVersion: number, decision: KbReviewDecision) => BoundAction;
  publishAction: (versionId: string, expectedVersion: number) => BoundAction;
  archiveAction: (versionId: string, expectedVersion: number) => BoundAction;
  setExpiryAction: (versionId: string, expectedVersion: number) => BoundAction;
}) {
  const hasOpenDraft = versions.some((v) => v.status === "draft" || v.status === "in_review" || v.status === "approved");

  return (
    <div className="flex flex-col gap-4">
      <h1 className="text-xl font-semibold text-neutral-900">Article versions</h1>

      {versions.length === 0 ? <p className="text-xs text-neutral-500">No versions yet, or you are not entitled to see any.</p> : null}

      <div className="flex flex-col gap-3">
        {versions.map((v) => (
          <VersionCard
            key={v.id}
            summary={v}
            full={fullVersionById[v.id] ?? null}
            updateVersionAction={updateVersionAction}
            submitForReviewAction={submitForReviewAction}
            reviewAction={reviewAction}
            publishAction={publishAction}
            archiveAction={archiveAction}
            setExpiryAction={setExpiryAction}
          />
        ))}
      </div>

      {!hasOpenDraft ? <NewVersionForm createVersionAction={createVersionAction} /> : null}
    </div>
  );
}
