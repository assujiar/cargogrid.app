"use client";

import { useActionState } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import { StatusBadge } from "../../../../../../components/ui/status-badge.tsx";
import type { ChecklistItemView, ChecklistCompleteness } from "../../../../../../server/contracts/document-requirement/document-requirement.ts";
import type { ShipmentOrderFormState } from "./actions.ts";

const INITIAL_STATE: ShipmentOrderFormState = { error: null };

const EFFECTIVE_STATUS_TONE: Record<ChecklistItemView["effectiveStatus"], "success" | "warning" | "danger" | "neutral"> = {
  approved: "success",
  pending_review: "warning",
  missing: "neutral",
  rejected: "danger",
  expired: "danger",
};

/** OPS-176: the pinned checklist plus a per-item upload/link form (filename/mime/size metadata only -- no live storage integration exists in this sandbox, PLT-128's own disclosed constraint) and a reviewer approve/reject form. effective_status is always the live app.get_shipment_document_checklist value, never cached client state. */
export function DocumentChecklistPanel({
  items,
  completeness,
  pinAction,
  uploadAction,
  reviewAction,
}: {
  readonly items: readonly ChecklistItemView[];
  readonly completeness: ChecklistCompleteness;
  readonly pinAction: (prevState: ShipmentOrderFormState, formData: FormData) => Promise<ShipmentOrderFormState>;
  readonly uploadAction: (checklistItemId: string, documentTypeCode: string) => (prevState: ShipmentOrderFormState, formData: FormData) => Promise<ShipmentOrderFormState>;
  readonly reviewAction: (checklistItemId: string) => (prevState: ShipmentOrderFormState, formData: FormData) => Promise<ShipmentOrderFormState>;
}) {
  const [pinState, pinFormAction, pinPending] = useActionState(pinAction, INITIAL_STATE);

  return (
    <div className="flex flex-col gap-3">
      <div className="flex items-center gap-2">
        <StatusBadge tone={completeness.isComplete ? "success" : "warning"} label={completeness.isComplete ? "Complete" : "Incomplete"} />
        {!completeness.isComplete && completeness.missingMandatory.length > 0 ? (
          <span className="text-sm text-neutral-600">{completeness.missingMandatory.length} mandatory item(s) outstanding</span>
        ) : null}
      </div>

      <form action={pinFormAction}>
        <Button type="submit" loading={pinPending} loadingLabel="Syncing…" variant="secondary" className="w-fit">
          Sync checklist
        </Button>
        {pinState.error ? (
          <p role="alert" className="mt-1 text-sm text-danger">
            {pinState.error}
          </p>
        ) : null}
      </form>

      {items.length === 0 ? (
        <p className="text-sm text-neutral-500">No requirements pinned yet. Sync the checklist once a document requirement has been published.</p>
      ) : (
        <ul className="flex flex-col gap-3">
          {items.map((item) => (
            <ChecklistItemRow key={item.id} item={item} uploadAction={uploadAction(item.id, item.documentTypeCode)} reviewAction={reviewAction(item.id)} />
          ))}
        </ul>
      )}
    </div>
  );
}

function ChecklistItemRow({
  item,
  uploadAction,
  reviewAction,
}: {
  readonly item: ChecklistItemView;
  readonly uploadAction: (prevState: ShipmentOrderFormState, formData: FormData) => Promise<ShipmentOrderFormState>;
  readonly reviewAction: (prevState: ShipmentOrderFormState, formData: FormData) => Promise<ShipmentOrderFormState>;
}) {
  const [uploadState, uploadFormAction, uploadPending] = useActionState(uploadAction, INITIAL_STATE);
  const [reviewState, reviewFormAction, reviewPending] = useActionState(reviewAction, INITIAL_STATE);

  return (
    <li className="rounded-md border border-neutral-200 p-3">
      <div className="flex flex-wrap items-center gap-2">
        <span className="font-medium text-neutral-900">{item.documentTypeCode}</span>
        <span className="text-xs uppercase tracking-wide text-neutral-500">{item.party}</span>
        <span className="text-xs uppercase tracking-wide text-neutral-500">{item.criticality}</span>
        <StatusBadge tone={EFFECTIVE_STATUS_TONE[item.effectiveStatus]} label={item.effectiveStatus.replace("_", " ")} />
      </div>
      {item.reviewNotes ? <p className="mt-1 text-sm text-neutral-600">Notes: {item.reviewNotes}</p> : null}

      <form action={uploadFormAction} className="mt-2 flex flex-wrap items-end gap-2" noValidate>
        <label className="flex flex-col text-sm text-neutral-700">
          Filename
          <input type="text" name="originalFilename" required className="rounded border border-neutral-300 px-2 py-1" placeholder="pod.pdf" />
        </label>
        <label className="flex flex-col text-sm text-neutral-700">
          MIME type
          <select name="mimeType" required defaultValue="application/pdf" className="rounded border border-neutral-300 px-2 py-1">
            <option value="application/pdf">application/pdf</option>
            <option value="image/jpeg">image/jpeg</option>
            <option value="image/png">image/png</option>
          </select>
        </label>
        <label className="flex flex-col text-sm text-neutral-700">
          Size (bytes)
          <input type="number" name="sizeBytes" required min={1} defaultValue={102400} className="w-28 rounded border border-neutral-300 px-2 py-1" />
        </label>
        <Button type="submit" loading={uploadPending} loadingLabel="Uploading…" variant="secondary">
          Upload &amp; link
        </Button>
      </form>
      {uploadState.error ? (
        <p role="alert" className="mt-1 text-sm text-danger">
          {uploadState.error}
        </p>
      ) : null}

      {item.fileId ? (
        <form action={reviewFormAction} className="mt-2 flex flex-wrap items-end gap-2" noValidate>
          <label className="flex flex-col text-sm text-neutral-700">
            Notes
            <input type="text" name="notes" className="rounded border border-neutral-300 px-2 py-1" />
          </label>
          <label className="flex flex-col text-sm text-neutral-700">
            Expires at (approve only)
            <input type="datetime-local" name="expiresAt" className="rounded border border-neutral-300 px-2 py-1" />
          </label>
          <Button type="submit" name="decision" value="approved" loading={reviewPending} loadingLabel="Saving…" disabled={item.malwareScanStatus !== "clean"}>
            Approve
          </Button>
          <Button type="submit" name="decision" value="rejected" loading={reviewPending} loadingLabel="Saving…" variant="secondary">
            Reject
          </Button>
        </form>
      ) : null}
      {item.fileId && item.malwareScanStatus !== "clean" ? <p className="mt-1 text-xs text-neutral-500">Scan status: {item.malwareScanStatus} — approval is blocked until the file scans clean.</p> : null}
      {reviewState.error ? (
        <p role="alert" className="mt-1 text-sm text-danger">
          {reviewState.error}
        </p>
      ) : null}
    </li>
  );
}
