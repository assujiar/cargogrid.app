"use client";

import { useActionState } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import { StatusBadge } from "../../../../../../components/ui/status-badge.tsx";
import type { ShipmentTrackingToken } from "../../../../../../server/contracts/public-tracking/public-tracking.ts";
import type { ShipmentOrderFormState, IssueTrackingTokenFormState } from "./actions.ts";

const INITIAL_ISSUE_STATE: IssueTrackingTokenFormState = { error: null, rawToken: null };
const INITIAL_REVOKE_STATE: ShipmentOrderFormState = { error: null };

/** OPS-180: issue/revoke the shipment's public tracking link. The raw token is shown exactly once, right after issuance -- it is never stored anywhere, only its hash is, so it cannot be shown again after this response. */
export function TrackingPanel({
  token,
  issueAction,
  revokeAction,
}: {
  readonly token: ShipmentTrackingToken | null;
  readonly issueAction: (prevState: IssueTrackingTokenFormState, formData: FormData) => Promise<IssueTrackingTokenFormState>;
  readonly revokeAction: (prevState: ShipmentOrderFormState, formData: FormData) => Promise<ShipmentOrderFormState>;
}) {
  const [issueState, issueFormAction, issuePending] = useActionState(issueAction, INITIAL_ISSUE_STATE);
  const [revokeState, revokeFormAction, revokePending] = useActionState(revokeAction, INITIAL_REVOKE_STATE);

  return (
    <div className="flex flex-col gap-3">
      {token ? (
        <div className="flex flex-wrap items-center gap-2">
          <StatusBadge tone="success" label="active" />
          <span className="text-sm text-neutral-700">Expires {new Date(token.expiresAt).toLocaleString()}</span>
        </div>
      ) : (
        <p className="text-sm text-neutral-500">No active tracking link for this shipment.</p>
      )}

      <form action={issueFormAction} className="flex flex-wrap items-end gap-2" noValidate>
        <label className="flex flex-col text-sm text-neutral-700">
          Validity (days)
          <input type="number" name="validityDays" required min={1} defaultValue={30} className="w-24 rounded border border-neutral-300 px-2 py-1" />
        </label>
        <Button type="submit" loading={issuePending} loadingLabel="Issuing…" className="w-fit">
          {token ? "Re-issue link (revokes the current one)" : "Issue tracking link"}
        </Button>
        {issueState.error ? (
          <p role="alert" className="mt-1 text-sm text-danger">
            {issueState.error}
          </p>
        ) : null}
      </form>

      {issueState.rawToken ? (
        <div role="status" className="flex flex-col gap-1 rounded-md border border-primary/30 bg-primary/5 p-3">
          <p className="text-sm font-medium text-neutral-900">Share this link with the customer now -- it will not be shown again.</p>
          <a href={`/tracking/${issueState.rawToken}`} target="_blank" rel="noreferrer" className="break-all text-sm text-primary underline">
            {`/tracking/${issueState.rawToken}`}
          </a>
        </div>
      ) : null}

      {token ? (
        <form action={revokeFormAction} className="flex flex-wrap items-end gap-2" noValidate>
          <label className="flex flex-col text-sm text-neutral-700">
            Reason
            <input type="text" name="reason" required className="w-64 rounded border border-neutral-300 px-2 py-1" />
          </label>
          <Button type="submit" loading={revokePending} loadingLabel="Revoking…" variant="secondary" className="w-fit">
            Revoke link
          </Button>
          {revokeState.error ? (
            <p role="alert" className="mt-1 text-sm text-danger">
              {revokeState.error}
            </p>
          ) : null}
        </form>
      ) : null}
    </div>
  );
}
