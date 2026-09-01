"use client";

import { useActionState } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
import { StatusBadge } from "../../../../../components/ui/status-badge.tsx";
import { EmptyState } from "../../../../../components/ui/empty-state.tsx";
import { FormField } from "../../../../../components/forms/form-field.tsx";
import { Input } from "../../../../../components/forms/input.tsx";
import { ValidationMessage } from "../../../../../components/forms/validation-message.tsx";
import { readCustomerProfileProposedValue, CUSTOMER_PROFILE_WRITABLE_FIELD_LABELS, type CustomerProfileChangeRequest } from "../../../../../server/contracts/customer-portal-profile/customer-portal-profile.ts";
import { CUSTOMER_LEGAL_IDENTITY_WRITABLE_FIELD_LABELS, type CustomerLegalIdentityChangeRequest } from "../../../../../server/contracts/customer-portal-legal-identity/customer-portal-legal-identity.ts";
import type { CustomerContactChangeRequest } from "../../../../../server/contracts/customer-portal-contact-change/customer-portal-contact-change.ts";
import type { CustomerProfileReviewActionState } from "./actions.ts";

const INITIAL_STATE: CustomerProfileReviewActionState = { error: null };

type BoundAction = (prevState: CustomerProfileReviewActionState, formData: FormData) => Promise<CustomerProfileReviewActionState>;
type DecideActionFactory = (requestId: string, expectedVersion: number, decision: "approve" | "reject") => BoundAction;

function billingAddressText(address: Record<string, unknown>): string {
  const parts = [address.line1, address.line2, address.city, address.state, address.postalCode, address.country].filter((v): v is string => typeof v === "string" && v.length > 0);
  return parts.length > 0 ? parts.join(", ") : "(empty)";
}

function DecisionForms({ requestId, expectedVersion, decideAction }: { requestId: string; expectedVersion: number; decideAction: DecideActionFactory }) {
  const approveAction = decideAction(requestId, expectedVersion, "approve");
  const rejectAction = decideAction(requestId, expectedVersion, "reject");
  const [approveState, approveFormAction, approvePending] = useActionState(approveAction, INITIAL_STATE);
  const [rejectState, rejectFormAction, rejectPending] = useActionState(rejectAction, INITIAL_STATE);

  return (
    <div className="flex flex-col gap-2">
      <div className="flex flex-wrap items-end gap-2">
        <form action={approveFormAction} className="flex flex-wrap items-end gap-2">
          <FormField id={`approve-reason-${requestId}`} label={<span className="text-xs text-neutral-500">Reason</span>}>
            <Input
              id={`approve-reason-${requestId}`}
              name="reviewReason"
              required
              placeholder="Why this decision"
              className="w-56"
              invalid={Boolean(approveState.error)}
              aria-describedby={approveState.error ? `approve-reason-${requestId}-error` : undefined}
            />
          </FormField>
          <Button type="submit" loading={approvePending} loadingLabel="Approving…">
            Approve
          </Button>
        </form>
        <form action={rejectFormAction} className="flex flex-wrap items-end gap-2">
          <FormField id={`reject-reason-${requestId}`} label={<span className="text-xs text-neutral-500">Reason</span>}>
            <Input
              id={`reject-reason-${requestId}`}
              name="reviewReason"
              required
              placeholder="Why this decision"
              className="w-56"
              invalid={Boolean(rejectState.error)}
              aria-describedby={rejectState.error ? `reject-reason-${requestId}-error` : undefined}
            />
          </FormField>
          <Button type="submit" variant="destructive" loading={rejectPending} loadingLabel="Rejecting…">
            Reject
          </Button>
        </form>
      </div>
      {approveState.error ? <ValidationMessage id={`approve-reason-${requestId}-error`}>{approveState.error}</ValidationMessage> : null}
      {rejectState.error ? <ValidationMessage id={`reject-reason-${requestId}-error`}>{rejectState.error}</ValidationMessage> : null}
    </div>
  );
}

export function ProfileChangeRequestQueue({ requests, decideAction }: { requests: readonly CustomerProfileChangeRequest[]; decideAction: DecideActionFactory }) {
  if (requests.length === 0) {
    return <EmptyState title="No pending trade name / billing address requests" description="Every submitted request has already been decided." />;
  }
  return (
    <ul className="flex flex-col gap-3">
      {requests.map((r) => {
        const proposed = readCustomerProfileProposedValue(r);
        const proposedText = typeof proposed === "string" ? proposed : billingAddressText(proposed);
        return (
          <li key={r.id} className="flex flex-col gap-2 rounded-md border border-neutral-200 p-3">
            <div className="flex flex-wrap items-center gap-2">
              <StatusBadge tone="info" label={r.status} />
              <span className="text-sm font-medium text-neutral-900">{CUSTOMER_PROFILE_WRITABLE_FIELD_LABELS[r.fieldName]}</span>
              <span className="text-xs text-neutral-500">account {r.accountId.slice(0, 8)}…</span>
            </div>
            <p className="text-sm text-neutral-900">
              Proposed: <span className="font-medium">{proposedText}</span>
            </p>
            <p className="text-xs text-neutral-500">Submitted {new Date(r.createdAt).toLocaleString()}</p>
            <DecisionForms requestId={r.id} expectedVersion={r.recordVersion} decideAction={decideAction} />
          </li>
        );
      })}
    </ul>
  );
}

export function LegalIdentityChangeRequestQueue({ requests, decideAction }: { requests: readonly CustomerLegalIdentityChangeRequest[]; decideAction: DecideActionFactory }) {
  if (requests.length === 0) {
    return <EmptyState title="No pending legal identity correction requests" description="Every submitted correction has already been decided." />;
  }
  return (
    <ul className="flex flex-col gap-3">
      {requests.map((r) => (
        <li key={r.id} className="flex flex-col gap-2 rounded-md border border-warning/40 bg-warning/5 p-3">
          <div className="flex flex-wrap items-center gap-2">
            <StatusBadge tone="warning" label={r.status} />
            <span className="text-sm font-medium text-neutral-900">{CUSTOMER_LEGAL_IDENTITY_WRITABLE_FIELD_LABELS[r.fieldName]}</span>
            <span className="text-xs text-neutral-500">account {r.accountId.slice(0, 8)}…</span>
          </div>
          <p className="text-sm text-neutral-900">
            Requested: <span className="font-medium">{typeof r.proposedValue === "string" ? r.proposedValue : ""}</span>
          </p>
          <p className="text-xs text-neutral-500">Submitted {new Date(r.createdAt).toLocaleString()}. Legal/tax identity change -- verify with the customer before approving. If this tenant requires step-up MFA for this decision, complete it first.</p>
          <DecisionForms requestId={r.id} expectedVersion={r.recordVersion} decideAction={decideAction} />
        </li>
      ))}
    </ul>
  );
}

const CHANGE_KIND_LABEL: Record<CustomerContactChangeRequest["changeKind"], string> = { add: "Add contact", update: "Update contact", remove: "Remove contact" };

export function ContactChangeRequestQueue({ requests, decideAction }: { requests: readonly CustomerContactChangeRequest[]; decideAction: DecideActionFactory }) {
  if (requests.length === 0) {
    return <EmptyState title="No pending contact requests" description="Every submitted contact add/update/remove request has already been decided." />;
  }
  return (
    <ul className="flex flex-col gap-3">
      {requests.map((r) => (
        <li key={r.id} className="flex flex-col gap-2 rounded-md border border-neutral-200 p-3">
          <div className="flex flex-wrap items-center gap-2">
            <StatusBadge tone="info" label={r.status} />
            <span className="text-sm font-medium text-neutral-900">{CHANGE_KIND_LABEL[r.changeKind]}</span>
            <span className="text-xs text-neutral-500">account {r.accountId.slice(0, 8)}…</span>
          </div>
          {r.changeKind === "add" ? (
            <p className="text-sm text-neutral-900">
              {r.fullName} {r.title ? `— ${r.title}` : ""} {r.email ? `· ${r.email}` : ""} {r.phone ? `· ${r.phone}` : ""} {r.role ? `· role: ${r.role}` : ""} {r.isPrimary ? "· primary" : ""}
            </p>
          ) : r.changeKind === "remove" ? (
            <p className="text-sm text-neutral-900">Contact {r.targetContactId?.slice(0, 8)}…</p>
          ) : (
            <p className="text-sm text-neutral-900">
              Contact {r.targetContactId?.slice(0, 8)}… — {[r.fullName && `name: ${r.fullName}`, r.title && `title: ${r.title}`, r.email && `email: ${r.email}`, r.phone && `phone: ${r.phone}`, r.role && `role: ${r.role}`, r.isPrimary !== null && `primary: ${r.isPrimary}`]
                .filter(Boolean)
                .join(", ")}
            </p>
          )}
          <p className="text-xs text-neutral-500">Submitted {new Date(r.createdAt).toLocaleString()}</p>
          <DecisionForms requestId={r.id} expectedVersion={r.recordVersion} decideAction={decideAction} />
        </li>
      ))}
    </ul>
  );
}
