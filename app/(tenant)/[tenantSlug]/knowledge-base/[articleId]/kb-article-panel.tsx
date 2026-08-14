"use client";

import { useActionState } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
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
  return (
    <form action={formAction} className="flex flex-col gap-2 rounded bg-neutral-50 p-3">
      <label className="flex flex-col gap-1 text-xs text-neutral-600">
        Title
        <input name="title" required defaultValue={full.title} className="rounded border border-neutral-300 p-1.5 text-sm" />
      </label>
      <label className="flex flex-col gap-1 text-xs text-neutral-600">
        Summary
        <input name="summary" defaultValue={full.summary ?? ""} className="rounded border border-neutral-300 p-1.5 text-sm" />
      </label>
      <label className="flex flex-col gap-1 text-xs text-neutral-600">
        Body
        <textarea name="body" required rows={6} defaultValue={full.body} className="rounded border border-neutral-300 p-2 text-sm" />
      </label>
      <label className="flex flex-col gap-1 text-xs text-neutral-600">
        Tags (comma-separated)
        <input name="tags" defaultValue={full.tags.join(", ")} className="rounded border border-neutral-300 p-1.5 text-sm" />
      </label>
      <div className="flex flex-wrap gap-3 text-xs text-neutral-600">
        <label className="flex items-center gap-1">
          <input type="checkbox" name="audienceInternal" defaultChecked={full.audienceInternal} /> Internal
        </label>
        <label className="flex items-center gap-1">
          <input type="checkbox" name="audienceCustomer" defaultChecked={full.audienceCustomer} /> Customer
        </label>
        <label className="flex items-center gap-1">
          <input type="checkbox" name="audienceHelpdesk" defaultChecked={full.audienceHelpdesk} /> Helpdesk
        </label>
      </div>
      <div>
        <Button type="submit" variant="secondary" loading={pending} loadingLabel="Saving…">
          Save draft
        </Button>
      </div>
      {state.error ? (
        <p role="alert" className="text-xs text-danger">
          {state.error}
        </p>
      ) : null}
    </form>
  );
}

function SubmitForReviewForm({ versionId, expectedVersion, submitForReviewAction }: { versionId: string; expectedVersion: number; submitForReviewAction: (versionId: string, expectedVersion: number) => BoundAction }) {
  const [state, formAction, pending] = useActionState(submitForReviewAction(versionId, expectedVersion), INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-wrap items-end gap-2 rounded bg-neutral-50 p-2">
      <label className="flex flex-col gap-1 text-xs text-neutral-600">
        Reviewer (auth user id -- not the author)
        <input name="reviewerAuthUserId" required placeholder="UUID" className="min-w-[16rem] rounded border border-neutral-300 p-1.5 text-sm" />
      </label>
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Submitting…">
        Submit for review
      </Button>
      {state.error ? (
        <p role="alert" className="w-full text-xs text-danger">
          {state.error}
        </p>
      ) : null}
    </form>
  );
}

function ReviewForm({ versionId, expectedVersion, decision, label, variant, reviewAction }: { versionId: string; expectedVersion: number; decision: KbReviewDecision; label: string; variant: "primary" | "destructive"; reviewAction: (versionId: string, expectedVersion: number, decision: KbReviewDecision) => BoundAction }) {
  const [state, formAction, pending] = useActionState(reviewAction(versionId, expectedVersion, decision), INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-wrap items-end gap-2">
      <input name="notes" placeholder="Notes (optional)" className="min-w-[10rem] rounded border border-neutral-300 p-1.5 text-xs" />
      <Button type="submit" variant={variant} loading={pending} loadingLabel="Recording…">
        {label}
      </Button>
      {state.error ? (
        <p role="alert" className="text-xs text-danger">
          {state.error}
        </p>
      ) : null}
    </form>
  );
}

function SetExpiryForm({ versionId, expectedVersion, setExpiryAction }: { versionId: string; expectedVersion: number; setExpiryAction: (versionId: string, expectedVersion: number) => BoundAction }) {
  const [state, formAction, pending] = useActionState(setExpiryAction(versionId, expectedVersion), INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-wrap items-end gap-2 rounded bg-neutral-50 p-2">
      <label className="flex flex-col gap-1 text-xs text-neutral-600">
        Expires at (blank = never)
        <input name="expiresAt" type="datetime-local" className="rounded border border-neutral-300 p-1.5 text-xs" />
      </label>
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Saving…">
        Set expiry
      </Button>
      {state.error ? (
        <p role="alert" className="w-full text-xs text-danger">
          {state.error}
        </p>
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
  return (
    <form action={formAction} className="flex flex-wrap items-end gap-2">
      <input name="reason" required placeholder="Reason (required)" className="min-w-[10rem] rounded border border-neutral-300 p-1.5 text-xs" />
      <Button type="submit" variant="destructive" loading={pending} loadingLabel="Archiving…">
        Archive
      </Button>
      {state.error ? (
        <p role="alert" className="text-xs text-danger">
          {state.error}
        </p>
      ) : null}
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
  return (
    <form action={formAction} className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
      <h3 className="text-sm font-semibold text-neutral-900">New draft version</h3>
      <label className="flex flex-col gap-1 text-xs text-neutral-600">
        Title
        <input name="title" required className="rounded border border-neutral-300 p-1.5 text-sm" />
      </label>
      <label className="flex flex-col gap-1 text-xs text-neutral-600">
        Summary
        <input name="summary" className="rounded border border-neutral-300 p-1.5 text-sm" />
      </label>
      <label className="flex flex-col gap-1 text-xs text-neutral-600">
        Body
        <textarea name="body" required rows={6} className="rounded border border-neutral-300 p-2 text-sm" />
      </label>
      <label className="flex flex-col gap-1 text-xs text-neutral-600">
        Tags (comma-separated)
        <input name="tags" className="rounded border border-neutral-300 p-1.5 text-sm" />
      </label>
      <div className="flex flex-wrap gap-3 text-xs text-neutral-600">
        <label className="flex items-center gap-1">
          <input type="checkbox" name="audienceInternal" /> Internal
        </label>
        <label className="flex items-center gap-1">
          <input type="checkbox" name="audienceCustomer" /> Customer
        </label>
        <label className="flex items-center gap-1">
          <input type="checkbox" name="audienceHelpdesk" /> Helpdesk
        </label>
      </div>
      <div>
        <Button type="submit" variant="primary" loading={pending} loadingLabel="Creating…">
          Create draft version
        </Button>
      </div>
      {state.error ? (
        <p role="alert" className="text-xs text-danger">
          {state.error}
        </p>
      ) : null}
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
