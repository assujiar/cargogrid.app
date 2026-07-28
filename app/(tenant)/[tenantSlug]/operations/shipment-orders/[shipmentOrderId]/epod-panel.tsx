"use client";

import { useActionState } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import { StatusBadge } from "../../../../../../components/ui/status-badge.tsx";
import type { EpodCapture } from "../../../../../../server/contracts/epod-capture-review/epod-capture-review.ts";
import type { ShipmentOrderFormState } from "./actions.ts";

const INITIAL_STATE: ShipmentOrderFormState = { error: null };

const STATUS_TONE: Record<EpodCapture["status"], "success" | "warning" | "danger" | "neutral"> = {
  draft: "neutral",
  submitted: "warning",
  approved: "success",
  revision_requested: "danger",
  completed: "success",
};

/** OPS-177: online-first ePOD capture/review -- history (every version preserved), an evidence form for the latest draft/revision_requested version, a reviewer decision form for a submitted version, and a Complete action once approved. Native mobile/offline capture is explicitly out of scope (RPD-004). */
export function EpodPanel({
  shipmentDelivered,
  history,
  startAction,
  evidenceAction,
  submitAction,
  reviewAction,
  reviseAction,
  completeAction,
}: {
  readonly shipmentDelivered: boolean;
  readonly history: readonly EpodCapture[];
  readonly startAction: (prevState: ShipmentOrderFormState, formData: FormData) => Promise<ShipmentOrderFormState>;
  readonly evidenceAction: (captureId: string) => (prevState: ShipmentOrderFormState, formData: FormData) => Promise<ShipmentOrderFormState>;
  readonly submitAction: (captureId: string, expectedVersion: number) => (prevState: ShipmentOrderFormState, formData: FormData) => Promise<ShipmentOrderFormState>;
  readonly reviewAction: (captureId: string, expectedVersion: number) => (prevState: ShipmentOrderFormState, formData: FormData) => Promise<ShipmentOrderFormState>;
  readonly reviseAction: (captureId: string) => (prevState: ShipmentOrderFormState, formData: FormData) => Promise<ShipmentOrderFormState>;
  readonly completeAction: (captureId: string, expectedVersion: number) => (prevState: ShipmentOrderFormState, formData: FormData) => Promise<ShipmentOrderFormState>;
}) {
  const [startState, startFormAction, startPending] = useActionState(startAction, INITIAL_STATE);
  const latest = history.find((c) => c.isLatestVersion) ?? null;

  return (
    <div className="flex flex-col gap-3">
      {history.length === 0 ? (
        shipmentDelivered ? (
          <form action={startFormAction}>
            <Button type="submit" loading={startPending} loadingLabel="Starting…" className="w-fit">
              Start ePOD capture
            </Button>
            {startState.error ? (
              <p role="alert" className="mt-1 text-sm text-danger">
                {startState.error}
              </p>
            ) : null}
          </form>
        ) : (
          <p className="text-sm text-neutral-500">ePOD capture can begin once this shipment reaches delivered.</p>
        )
      ) : (
        <ul className="flex flex-col gap-3">
          {[...history].reverse().map((capture) => (
            <li key={capture.id} className="rounded-md border border-neutral-200 p-3">
              <div className="flex flex-wrap items-center gap-2">
                <span className="text-xs uppercase tracking-wide text-neutral-500">v{capture.versionNumber}</span>
                <StatusBadge tone={STATUS_TONE[capture.status]} label={capture.status.replace("_", " ")} />
                {capture.receiverName ? <span className="text-sm text-neutral-700">Receiver: {capture.receiverName}</span> : null}
              </div>
              {capture.reviewNotes ? <p className="mt-1 text-sm text-neutral-600">Notes: {capture.reviewNotes}</p> : null}
              {capture.isLatestVersion ? (
                <EpodCaptureActions
                  capture={capture}
                  evidenceAction={evidenceAction(capture.id)}
                  submitAction={submitAction(capture.id, capture.recordVersion)}
                  reviewAction={reviewAction(capture.id, capture.recordVersion)}
                  reviseAction={reviseAction(capture.id)}
                  completeAction={completeAction(capture.id, capture.recordVersion)}
                />
              ) : null}
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}

function EpodCaptureActions({
  capture,
  evidenceAction,
  submitAction,
  reviewAction,
  reviseAction,
  completeAction,
}: {
  readonly capture: EpodCapture;
  readonly evidenceAction: (prevState: ShipmentOrderFormState, formData: FormData) => Promise<ShipmentOrderFormState>;
  readonly submitAction: (prevState: ShipmentOrderFormState, formData: FormData) => Promise<ShipmentOrderFormState>;
  readonly reviewAction: (prevState: ShipmentOrderFormState, formData: FormData) => Promise<ShipmentOrderFormState>;
  readonly reviseAction: (prevState: ShipmentOrderFormState, formData: FormData) => Promise<ShipmentOrderFormState>;
  readonly completeAction: (prevState: ShipmentOrderFormState, formData: FormData) => Promise<ShipmentOrderFormState>;
}) {
  const [evidenceState, evidenceFormAction, evidencePending] = useActionState(evidenceAction, INITIAL_STATE);
  const [submitState, submitFormAction, submitPending] = useActionState(submitAction, INITIAL_STATE);
  const [reviewState, reviewFormAction, reviewPending] = useActionState(reviewAction, INITIAL_STATE);
  const [reviseState, reviseFormAction, revisePending] = useActionState(reviseAction, INITIAL_STATE);
  const [completeState, completeFormAction, completePending] = useActionState(completeAction, INITIAL_STATE);

  if (capture.status === "revision_requested") {
    return (
      <form action={reviseFormAction} className="mt-2">
        <Button type="submit" loading={revisePending} loadingLabel="Starting revision…" variant="secondary">
          Start revision (new version)
        </Button>
        {reviseState.error ? (
          <p role="alert" className="mt-1 text-sm text-danger">
            {reviseState.error}
          </p>
        ) : null}
      </form>
    );
  }

  if (capture.status === "draft") {
    return (
      <>
        <form action={evidenceFormAction} className="mt-2 flex flex-col gap-2" noValidate>
          <div className="flex flex-wrap gap-2">
            <label className="flex flex-col text-sm text-neutral-700">
              Receiver name
              <input type="text" name="receiverName" required defaultValue={capture.receiverName ?? ""} className="rounded border border-neutral-300 px-2 py-1" />
            </label>
            <label className="flex flex-col text-sm text-neutral-700">
              Receiver position
              <input type="text" name="receiverPosition" defaultValue={capture.receiverPosition ?? ""} className="rounded border border-neutral-300 px-2 py-1" />
            </label>
          </div>
          <div className="flex flex-wrap items-end gap-2">
            <label className="flex flex-col text-sm text-neutral-700">
              Signature filename
              <input type="text" name="signatureFilename" placeholder="signature.png" className="rounded border border-neutral-300 px-2 py-1" />
            </label>
            <label className="flex flex-col text-sm text-neutral-700">
              Photo filename
              <input type="text" name="photoFilename" placeholder="delivery-photo.jpg" className="rounded border border-neutral-300 px-2 py-1" />
            </label>
          </div>
          <div className="flex flex-wrap items-end gap-2">
            <label className="flex flex-col text-sm text-neutral-700">
              Latitude
              <input type="number" name="latitude" step="any" min={-90} max={90} className="w-28 rounded border border-neutral-300 px-2 py-1" />
            </label>
            <label className="flex flex-col text-sm text-neutral-700">
              Longitude
              <input type="number" name="longitude" step="any" min={-180} max={180} className="w-28 rounded border border-neutral-300 px-2 py-1" />
            </label>
            <label className="flex flex-col text-sm text-neutral-700">
              Captured at
              <input type="datetime-local" name="capturedAt" className="rounded border border-neutral-300 px-2 py-1" />
            </label>
          </div>
          <Button type="submit" loading={evidencePending} loadingLabel="Saving…" variant="secondary" className="w-fit">
            Save evidence
          </Button>
        </form>
        {evidenceState.error ? (
          <p role="alert" className="mt-1 text-sm text-danger">
            {evidenceState.error}
          </p>
        ) : null}

        <form action={submitFormAction} className="mt-2">
          <Button type="submit" loading={submitPending} loadingLabel="Submitting…" className="w-fit">
            Submit for review
          </Button>
          {submitState.error ? (
            <p role="alert" className="mt-1 text-sm text-danger">
              {submitState.error}
            </p>
          ) : null}
        </form>
      </>
    );
  }

  if (capture.status === "submitted") {
    return (
      <form action={reviewFormAction} className="mt-2 flex flex-wrap items-end gap-2" noValidate>
        <label className="flex flex-col text-sm text-neutral-700">
          Notes
          <input type="text" name="notes" className="rounded border border-neutral-300 px-2 py-1" />
        </label>
        <Button type="submit" name="decision" value="approved" loading={reviewPending} loadingLabel="Saving…">
          Approve
        </Button>
        <Button type="submit" name="decision" value="revision_requested" loading={reviewPending} loadingLabel="Saving…" variant="secondary">
          Request revision
        </Button>
        {reviewState.error ? (
          <p role="alert" className="mt-1 text-sm text-danger">
            {reviewState.error}
          </p>
        ) : null}
      </form>
    );
  }

  if (capture.status === "approved") {
    return (
      <form action={completeFormAction} className="mt-2">
        <Button type="submit" loading={completePending} loadingLabel="Completing…">
          Complete ePOD
        </Button>
        {completeState.error ? (
          <p role="alert" className="mt-1 text-sm text-danger">
            {completeState.error}
          </p>
        ) : null}
      </form>
    );
  }

  return null;
}
