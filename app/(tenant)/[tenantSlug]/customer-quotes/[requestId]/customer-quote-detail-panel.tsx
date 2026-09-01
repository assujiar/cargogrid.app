"use client";

import { useActionState, useState } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
import { StatusBadge, type StatusTone } from "../../../../../components/ui/status-badge.tsx";
import { FormField } from "../../../../../components/forms/form-field.tsx";
import { Input } from "../../../../../components/forms/input.tsx";
import { Textarea } from "../../../../../components/forms/textarea.tsx";
import { ValidationMessage } from "../../../../../components/forms/validation-message.tsx";
import type { CustomerQuoteRequestActionState } from "../actions.ts";
import type { CustomerQuoteRequest, CustomerQuoteRequestFile, QuoteRequestStatus } from "../../../../../server/contracts/customer-quote-request/customer-quote-request.ts";

const INITIAL_STATE: CustomerQuoteRequestActionState = { error: null };

const STATUS_TONE: Record<QuoteRequestStatus, StatusTone> = {
  draft: "neutral",
  submitted: "info",
  cancelled: "neutral",
  converted: "success",
};

type BoundAction = (prevState: CustomerQuoteRequestActionState, formData: FormData) => Promise<CustomerQuoteRequestActionState>;

function locationText(location: Record<string, unknown>): string {
  const parts = [location.label, location.addressLine, location.city, location.country].filter((v): v is string => typeof v === "string" && v.length > 0);
  return parts.length > 0 ? parts.join(", ") : "Not specified";
}

/** Chronological status timeline (source prompt §15's own "status timeline" requirement) -- built from the row's own real timestamps, never a synthetic event log. */
function StatusTimeline({ detail }: { detail: CustomerQuoteRequest }) {
  const steps: { label: string; at: string | null; done: boolean }[] = [
    { label: "Draft created", at: detail.createdAt, done: true },
    { label: "Submitted to Commercial", at: detail.submittedAt, done: detail.status === "submitted" || detail.status === "converted" || (detail.status === "cancelled" && !!detail.submittedAt) },
    { label: "Converted to quotation", at: detail.status === "converted" ? detail.updatedAt : null, done: detail.status === "converted" },
  ];
  if (detail.status === "cancelled") {
    steps.push({ label: "Cancelled", at: detail.cancelledAt, done: true });
  }

  return (
    <ol className="flex flex-col gap-1 text-xs text-neutral-600">
      {steps.map((s) => (
        <li key={s.label} className="flex items-center gap-2">
          <span className={`h-2 w-2 rounded-full ${s.done ? "bg-success" : "bg-neutral-300"}`} aria-hidden="true" />
          <span className={s.done ? "font-medium text-neutral-900" : ""}>{s.label}</span>
          {s.at ? <span className="text-neutral-400">— {new Date(s.at).toLocaleString()}</span> : null}
        </li>
      ))}
    </ol>
  );
}

function EditDraftForm({ detail, updateAction }: { detail: CustomerQuoteRequest; updateAction: BoundAction }) {
  const [state, formAction, pending] = useActionState(updateAction, INITIAL_STATE);
  const errorId = "edit-draft-error";
  const describedBy = state.error ? errorId : undefined;
  return (
    <form action={formAction} className="grid grid-cols-1 gap-2 rounded-md border border-neutral-200 p-4 sm:grid-cols-2">
      <h2 className="text-sm font-semibold text-neutral-900 sm:col-span-2">Edit draft</h2>
      <FormField id="edit-service-type" label={<span className="text-xs text-neutral-500">Service type</span>}>
        <Input id="edit-service-type" name="serviceType" defaultValue={detail.serviceType ?? ""} aria-describedby={describedBy} />
      </FormField>
      <div />
      <div className="sm:col-span-2">
        <FormField id="edit-cargo-description" label={<span className="text-xs text-neutral-500">Cargo description</span>}>
          <Textarea id="edit-cargo-description" name="cargoDescription" defaultValue={detail.cargoDescription ?? ""} rows={2} aria-describedby={describedBy} />
        </FormField>
      </div>
      <FormField id="edit-origin-label" label={<span className="text-xs text-neutral-500">Origin label</span>}>
        <Input id="edit-origin-label" name="originLabel" defaultValue={typeof detail.origin.label === "string" ? detail.origin.label : ""} aria-describedby={describedBy} />
      </FormField>
      <FormField id="edit-destination-label" label={<span className="text-xs text-neutral-500">Destination label</span>}>
        <Input id="edit-destination-label" name="destinationLabel" defaultValue={typeof detail.destination.label === "string" ? detail.destination.label : ""} aria-describedby={describedBy} />
      </FormField>
      <FormField id="edit-pickup-date" label={<span className="text-xs text-neutral-500">Requested pickup date</span>}>
        <Input id="edit-pickup-date" type="date" name="requestedPickupDate" defaultValue={detail.requestedPickupDate ?? ""} aria-describedby={describedBy} />
      </FormField>
      <FormField id="edit-delivery-date" label={<span className="text-xs text-neutral-500">Requested delivery date</span>}>
        <Input id="edit-delivery-date" type="date" name="requestedDeliveryDate" defaultValue={detail.requestedDeliveryDate ?? ""} aria-describedby={describedBy} />
      </FormField>
      <div className="sm:col-span-2">
        <FormField id="edit-notes" label={<span className="text-xs text-neutral-500">Notes</span>}>
          <Textarea id="edit-notes" name="notes" defaultValue={detail.notes ?? ""} rows={2} aria-describedby={describedBy} />
        </FormField>
      </div>
      <div className="sm:col-span-2">
        <Button type="submit" variant="secondary" loading={pending} loadingLabel="Saving…">
          Save changes
        </Button>
      </div>
      {state.error ? (
        <div className="sm:col-span-2">
          <ValidationMessage id={errorId}>{state.error}</ValidationMessage>
        </div>
      ) : null}
    </form>
  );
}

function SubmitForm({ submitAction }: { submitAction: BoundAction }) {
  const [state, formAction, pending] = useActionState(submitAction, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col gap-2">
      <Button type="submit" variant="primary" loading={pending} loadingLabel="Submitting…">
        Submit to Commercial
      </Button>
      {state.error ? <ValidationMessage>{state.error}</ValidationMessage> : null}
    </form>
  );
}

function CancelForm({ cancelAction }: { cancelAction: BoundAction }) {
  const [state, formAction, pending] = useActionState(cancelAction, INITIAL_STATE);
  const errorId = "cancel-request-error";
  return (
    <form action={formAction} className="flex flex-wrap items-center gap-2">
      <label htmlFor="cancel-request-reason" className="sr-only">
        Cancellation reason
      </label>
      <Input
        id="cancel-request-reason"
        name="reason"
        required
        placeholder="Cancellation reason (required)"
        className="min-w-[12rem] flex-1 text-xs"
        invalid={Boolean(state.error)}
        aria-describedby={state.error ? errorId : undefined}
      />
      <Button type="submit" variant="destructive" loading={pending} loadingLabel="Cancelling…">
        Cancel request
      </Button>
      {state.error ? (
        <div className="w-full">
          <ValidationMessage id={errorId}>{state.error}</ValidationMessage>
        </div>
      ) : null}
    </form>
  );
}

function AttachmentsSection({
  files,
  uploadAction,
  canUpload,
}: {
  files: readonly CustomerQuoteRequestFile[];
  uploadAction: (prevState: CustomerQuoteRequestActionState, formData: FormData) => Promise<CustomerQuoteRequestActionState>;
  canUpload: boolean;
}) {
  const [state, formAction, pending] = useActionState(uploadAction, INITIAL_STATE);
  const [selected, setSelected] = useState<File | null>(null);

  const SCAN_TONE: Record<string, StatusTone> = { pending: "warning", clean: "success", infected: "danger", error: "danger" };

  return (
    <section aria-label="Attachments" className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
      <h2 className="text-sm font-semibold text-neutral-900">Attachments</h2>
      {files.length === 0 ? (
        <p className="text-xs text-neutral-500">No files attached yet.</p>
      ) : (
        <ul className="flex flex-col gap-1">
          {files.map((f) => (
            <li key={f.id} className="flex flex-wrap items-center gap-2 rounded border border-neutral-100 p-2 text-xs">
              <span className="font-medium text-neutral-900">{f.originalFilename}</span>
              <span className="text-neutral-400">{(f.sizeBytes / 1024).toFixed(0)} KB</span>
              <StatusBadge tone={SCAN_TONE[f.malwareScanStatus] ?? "neutral"} label={f.malwareScanStatus === "pending" ? "Scanning" : f.malwareScanStatus} />
            </li>
          ))}
        </ul>
      )}
      {canUpload ? (
        <>
          <form
            action={formAction}
            className="flex flex-wrap items-center gap-2"
            onSubmit={(event) => {
              if (!selected) event.preventDefault();
            }}
          >
            <label htmlFor="quote-attachment-file" className="sr-only">
              Attachment file
            </label>
            <input id="quote-attachment-file" type="file" required onChange={(event) => setSelected(event.currentTarget.files?.[0] ?? null)} className="text-xs" />
            <input type="hidden" name="originalFilename" value={selected?.name ?? ""} />
            <input type="hidden" name="mimeType" value={selected?.type || "application/octet-stream"} />
            <input type="hidden" name="sizeBytes" value={selected?.size ?? 0} />
            <Button type="submit" variant="secondary" loading={pending} loadingLabel="Attaching…" disabled={!selected}>
              Attach file
            </Button>
          </form>
          <p className="text-xs text-neutral-500">Files remain private and are scanned before being shared with anyone other than the uploader.</p>
          {state.error ? <ValidationMessage>{state.error}</ValidationMessage> : null}
        </>
      ) : (
        <p className="text-xs text-neutral-500">Attachments can only be added while this request is still a draft.</p>
      )}
    </section>
  );
}

export function CustomerQuoteDetailPanel({
  detail,
  files,
  updateAction,
  submitAction,
  cancelAction,
  uploadAction,
}: {
  detail: CustomerQuoteRequest;
  files: readonly CustomerQuoteRequestFile[];
  updateAction: BoundAction;
  submitAction: BoundAction;
  cancelAction: BoundAction;
  uploadAction: (prevState: CustomerQuoteRequestActionState, formData: FormData) => Promise<CustomerQuoteRequestActionState>;
}) {
  const isDraft = detail.status === "draft";
  const isCancellable = detail.status === "draft" || detail.status === "submitted";

  return (
    <div className="flex flex-col gap-4">
      <header className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
        <div className="flex flex-wrap items-center gap-2">
          <h1 className="text-lg font-semibold text-neutral-900">{detail.cargoDescription || "Untitled quote request"}</h1>
          <StatusBadge tone={STATUS_TONE[detail.status]} label={detail.status} />
        </div>
        <dl className="grid grid-cols-2 gap-2 text-xs text-neutral-500 sm:grid-cols-4">
          <div>
            <dt className="font-medium">Service</dt>
            <dd>{detail.serviceType ?? "—"}</dd>
          </div>
          <div>
            <dt className="font-medium">Origin</dt>
            <dd>{locationText(detail.origin)}</dd>
          </div>
          <div>
            <dt className="font-medium">Destination</dt>
            <dd>{locationText(detail.destination)}</dd>
          </div>
          <div>
            <dt className="font-medium">Updated</dt>
            <dd>{new Date(detail.updatedAt).toLocaleString()}</dd>
          </div>
        </dl>
        {detail.status === "converted" ? (
          <p className="rounded bg-success/10 p-2 text-sm text-neutral-800">
            This request has been converted into a formal quotation by Commercial. Pricing and next steps will be shared separately -- this request itself was never a price commitment.
          </p>
        ) : null}
        {detail.status === "cancelled" && detail.cancelledReason ? (
          <p className="rounded bg-neutral-100 p-2 text-sm text-neutral-800">
            <span className="font-medium">Cancelled: </span>
            {detail.cancelledReason}
          </p>
        ) : null}
        <StatusTimeline detail={detail} />
        <div className="flex flex-wrap gap-2">
          {isDraft ? <SubmitForm submitAction={submitAction} /> : null}
          {isCancellable ? <CancelForm cancelAction={cancelAction} /> : null}
        </div>
      </header>

      {isDraft ? <EditDraftForm detail={detail} updateAction={updateAction} /> : null}

      <AttachmentsSection files={files} uploadAction={uploadAction} canUpload={isDraft} />
    </div>
  );
}
