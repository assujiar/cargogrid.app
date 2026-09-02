"use client";

import { useState, useTransition } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import { approveRateVersionAction, rejectRateVersionAction, withdrawRateVersionAction } from "./actions.ts";
import type { RateVersionApprovalStatus } from "../../../../../../server/contracts/rate/rate.ts";
import { Input } from "../../../../../../components/forms/input.tsx";
import { FormField } from "../../../../../../components/forms/form-field.tsx";
import { ValidationMessage } from "../../../../../../components/forms/validation-message.tsx";

/** Approve/reject/withdraw action panel (COM-149) -- mirrors every prior Commercial capability's own `*-actions-panel.tsx` pattern (bound Server Actions called directly via `useTransition`). All three RPCs are gated by app.is_support_grant_authority, not ordinary COM RBAC -- a Commercial rep will see a real server-side denial here, which is expected. */
export function RateActionsPanel({
  tenantSlug,
  rateVersionId,
  recordVersion,
  approvalStatus,
}: {
  tenantSlug: string;
  rateVersionId: string;
  recordVersion: number;
  approvalStatus: RateVersionApprovalStatus;
}) {
  const [rejectReason, setRejectReason] = useState("");
  const [withdrawReason, setWithdrawReason] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();

  // Approve, reject and withdraw share this one `error` slot, so neither reason field can
  // honestly claim `aria-invalid`; both instead point at the shared message
  // (ISS-2026-242's own documented multi-action case).
  const describedBy = error ? "rate-actions-error" : undefined;

  const isPending = approvalStatus === "pending_approval";
  const isApproved = approvalStatus === "approved";

  return (
    <div className="flex flex-col gap-6 rounded-md border border-neutral-200 p-4">
      <h2 className="text-sm font-semibold text-neutral-900">Actions</h2>

      {error ? <ValidationMessage id="rate-actions-error">{error}</ValidationMessage> : null}

      <div className="flex flex-col gap-2">
        <h3 className="text-sm font-medium text-neutral-900">Approve</h3>
        <Button
          type="button"
          disabled={!isPending}
          loading={pending}
          loadingLabel="Approving…"
          onClick={() =>
            startTransition(async () => {
              const result = await approveRateVersionAction(tenantSlug, rateVersionId, recordVersion);
              setError(result.error);
            })
          }
        >
          Approve
        </Button>
      </div>

      <div className="flex flex-col gap-2">
        <h3 className="text-sm font-medium text-neutral-900">Reject</h3>
        <FormField id="rate-reject-reason" label={<span className="sr-only">Rejection reason</span>}>
          <Input id="rate-reject-reason" placeholder="Rejection reason" value={rejectReason} onChange={(e) => setRejectReason(e.target.value)} disabled={!isPending} aria-describedby={describedBy} />
        </FormField>
        <Button
          type="button"
          variant="destructive"
          disabled={!isPending || !rejectReason.trim()}
          loading={pending}
          loadingLabel="Rejecting…"
          onClick={() =>
            startTransition(async () => {
              const result = await rejectRateVersionAction(tenantSlug, rateVersionId, recordVersion, rejectReason.trim());
              setError(result.error);
            })
          }
        >
          Reject
        </Button>
      </div>

      <div className="flex flex-col gap-2">
        <h3 className="text-sm font-medium text-neutral-900">Withdraw</h3>
        <p className="text-xs text-neutral-500">Only an approved rate can be withdrawn.</p>
        <FormField id="rate-withdraw-reason" label={<span className="sr-only">Withdrawal reason</span>}>
          <Input id="rate-withdraw-reason" placeholder="Withdrawal reason" value={withdrawReason} onChange={(e) => setWithdrawReason(e.target.value)} disabled={!isApproved} aria-describedby={describedBy} />
        </FormField>
        <Button
          type="button"
          variant="destructive"
          disabled={!isApproved || !withdrawReason.trim()}
          loading={pending}
          loadingLabel="Withdrawing…"
          onClick={() =>
            startTransition(async () => {
              const result = await withdrawRateVersionAction(tenantSlug, rateVersionId, recordVersion, withdrawReason.trim());
              setError(result.error);
            })
          }
        >
          Withdraw
        </Button>
      </div>
    </div>
  );
}
