"use client";

import { useActionState } from "react";
import { Button } from "../../../../components/ui/button.tsx";
import { StatusBadge, type StatusTone } from "../../../../components/ui/status-badge.tsx";
import { EmptyState } from "../../../../components/ui/empty-state.tsx";
import type { CustomerProfileActionState } from "./actions.ts";
import {
  readCustomerProfileProposedValue,
  CUSTOMER_PROFILE_WRITABLE_FIELD_LABELS,
  type CustomerPortalAccountProfile,
  type CustomerPortalAccountContact,
  type CustomerProfileChangeRequest,
  type CustomerProfileBillingAddress,
} from "../../../../server/contracts/customer-portal-profile/customer-portal-profile.ts";

const INITIAL_STATE: CustomerProfileActionState = { error: null };

const STATUS_TONE: Record<CustomerProfileChangeRequest["status"], StatusTone> = {
  pending: "info",
  approved: "success",
  rejected: "danger",
  withdrawn: "neutral",
};

type BoundAction = (prevState: CustomerProfileActionState, formData: FormData) => Promise<CustomerProfileActionState>;

function billingAddressText(address: Record<string, unknown>): string {
  const parts = [address.line1, address.line2, address.city, address.state, address.postalCode, address.country].filter((v): v is string => typeof v === "string" && v.length > 0);
  return parts.length > 0 ? parts.join(", ") : "Not on file";
}

/** Locked/read-only field row (design decision 3 of the migration) -- shown, never editable, with an explanation. */
function LockedField({ label, value, note }: { label: string; value: string; note: string }) {
  return (
    <div className="flex flex-col gap-1 rounded-md border border-neutral-200 bg-neutral-50 p-3">
      <div className="flex items-center gap-2">
        <span aria-hidden="true" className="text-neutral-400">
          🔒
        </span>
        <span className="text-xs font-medium text-neutral-500">{label}</span>
      </div>
      <p className="text-sm text-neutral-900">{value || "Not on file"}</p>
      <p className="text-xs text-neutral-400">{note}</p>
    </div>
  );
}

function PendingChangeBanner({ request, withdrawAction }: { request: CustomerProfileChangeRequest; withdrawAction: BoundAction }) {
  const [state, formAction, pending] = useActionState(withdrawAction, INITIAL_STATE);
  const proposed = readCustomerProfileProposedValue(request);
  const proposedText = typeof proposed === "string" ? proposed : billingAddressText(proposed);

  return (
    <div className="flex flex-col gap-2 rounded-md border border-info/30 bg-info/5 p-3 text-sm">
      <div className="flex flex-wrap items-center gap-2">
        <StatusBadge tone="info" label="Pending review" />
        <span className="text-neutral-700">
          Proposed: <span className="font-medium">{proposedText}</span>
        </span>
      </div>
      <p className="text-xs text-neutral-500">Submitted {new Date(request.createdAt).toLocaleString()}. Your team will review this before it takes effect.</p>
      <form action={formAction} className="flex items-center gap-2">
        <input type="hidden" name="requestId" value={request.id} />
        <input type="hidden" name="accountId" value={request.accountId} />
        <input type="hidden" name="expectedVersion" value={request.recordVersion} />
        <Button type="submit" variant="secondary" loading={pending} loadingLabel="Withdrawing…">
          Withdraw
        </Button>
      </form>
      {state.error ? (
        <p role="alert" className="text-xs text-danger">
          {state.error}
        </p>
      ) : null}
    </div>
  );
}

function TradeNameForm({ currentValue, submitAction }: { currentValue: string; submitAction: BoundAction }) {
  const [state, formAction, pending] = useActionState(submitAction, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col gap-2 rounded-md border border-neutral-200 p-3">
      <label className="text-xs font-medium text-neutral-500">
        Trade name
        <input name="tradeName" defaultValue={currentValue} className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" placeholder="e.g. Acme Logistics" />
      </label>
      <div>
        <Button type="submit" variant="secondary" loading={pending} loadingLabel="Submitting…">
          Propose change
        </Button>
      </div>
      <p className="text-xs text-neutral-500">This does not change your trade name immediately -- it submits a request for our team to review.</p>
      {state.error ? (
        <p role="alert" className="text-xs text-danger">
          {state.error}
        </p>
      ) : null}
    </form>
  );
}

function BillingAddressForm({ currentValue, submitAction }: { currentValue: CustomerProfileBillingAddress; submitAction: BoundAction }) {
  const [state, formAction, pending] = useActionState(submitAction, INITIAL_STATE);
  return (
    <form action={formAction} className="grid grid-cols-1 gap-2 rounded-md border border-neutral-200 p-3 sm:grid-cols-2">
      <label className="text-xs font-medium text-neutral-500 sm:col-span-2">
        Address line 1
        <input name="billingLine1" defaultValue={typeof currentValue.line1 === "string" ? currentValue.line1 : ""} className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" />
      </label>
      <label className="text-xs font-medium text-neutral-500 sm:col-span-2">
        Address line 2
        <input name="billingLine2" defaultValue={typeof currentValue.line2 === "string" ? currentValue.line2 : ""} className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" />
      </label>
      <label className="text-xs font-medium text-neutral-500">
        City
        <input name="billingCity" defaultValue={typeof currentValue.city === "string" ? currentValue.city : ""} className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" />
      </label>
      <label className="text-xs font-medium text-neutral-500">
        State/Province
        <input name="billingState" defaultValue={typeof currentValue.state === "string" ? currentValue.state : ""} className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" />
      </label>
      <label className="text-xs font-medium text-neutral-500">
        Postal code
        <input name="billingPostalCode" defaultValue={typeof currentValue.postalCode === "string" ? currentValue.postalCode : ""} className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" />
      </label>
      <label className="text-xs font-medium text-neutral-500">
        Country
        <input name="billingCountry" defaultValue={typeof currentValue.country === "string" ? currentValue.country : ""} className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" />
      </label>
      <div className="sm:col-span-2">
        <Button type="submit" variant="secondary" loading={pending} loadingLabel="Submitting…">
          Propose change
        </Button>
      </div>
      <p className="text-xs text-neutral-500 sm:col-span-2">This does not change your billing address immediately -- it submits a request for our team to review.</p>
      {state.error ? (
        <p role="alert" className="text-xs text-danger sm:col-span-2">
          {state.error}
        </p>
      ) : null}
    </form>
  );
}

function ContactsSection({ contacts }: { contacts: readonly CustomerPortalAccountContact[] }) {
  return (
    <section aria-label="Contacts" className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
      <h2 className="text-sm font-semibold text-neutral-900">Contacts</h2>
      {contacts.length === 0 ? (
        <EmptyState title="No contacts on file" description="No contacts are linked to this account yet." />
      ) : (
        <ul className="flex flex-col gap-2">
          {contacts.map((c) => (
            <li key={c.contactId} className="flex flex-wrap items-center gap-2 rounded border border-neutral-100 p-2 text-sm">
              <span className="font-medium text-neutral-900">{c.fullName}</span>
              {c.isPrimary ? <StatusBadge tone="info" label="Primary" /> : null}
              <span className="text-xs text-neutral-500">{c.title ?? "—"}</span>
              <span className="text-xs text-neutral-500">{c.email ?? "—"}</span>
              <span className="text-xs text-neutral-500">{c.phone ?? "—"}</span>
            </li>
          ))}
        </ul>
      )}
      <p className="text-xs text-neutral-400">Contacts are managed by your account team -- there is no self-service edit here yet.</p>
    </section>
  );
}

function HistorySection({ history }: { history: readonly CustomerProfileChangeRequest[] }) {
  return (
    <section aria-label="Change request history" className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
      <h2 className="text-sm font-semibold text-neutral-900">Change request history</h2>
      {history.length === 0 ? (
        <EmptyState title="No change requests yet" description="Profile change requests you or a colleague submit will appear here." />
      ) : (
        <div className="overflow-x-auto">
          <table className="w-full border-collapse">
            <thead>
              <tr className="text-left text-xs font-medium text-neutral-500">
                <th className="p-2">Field</th>
                <th className="p-2">Proposed value</th>
                <th className="p-2">Status</th>
                <th className="p-2">Reviewed</th>
                <th className="p-2">Submitted</th>
              </tr>
            </thead>
            <tbody>
              {history.map((r) => {
                const proposed = readCustomerProfileProposedValue(r);
                const proposedText = typeof proposed === "string" ? proposed : billingAddressText(proposed);
                return (
                  <tr key={r.id} className="border-t border-neutral-100">
                    <td className="p-2 text-sm">{CUSTOMER_PROFILE_WRITABLE_FIELD_LABELS[r.fieldName]}</td>
                    <td className="p-2 text-sm">{proposedText}</td>
                    <td className="p-2 text-sm">
                      <StatusBadge tone={STATUS_TONE[r.status]} label={r.status} />
                    </td>
                    <td className="p-2 text-xs text-neutral-500">{r.reviewedAt ? `${new Date(r.reviewedAt).toLocaleString()}${r.reviewReason ? ` — ${r.reviewReason}` : ""}` : "—"}</td>
                    <td className="p-2 text-xs text-neutral-500">{new Date(r.createdAt).toLocaleString()}</td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}
    </section>
  );
}

export function CustomerProfilePanel({
  profile,
  contacts,
  history,
  submitTradeNameAction,
  submitBillingAddressAction,
  withdrawAction,
}: {
  tenantSlug: string;
  profile: CustomerPortalAccountProfile;
  contacts: readonly CustomerPortalAccountContact[];
  history: readonly CustomerProfileChangeRequest[];
  submitTradeNameAction: BoundAction;
  submitBillingAddressAction: BoundAction;
  withdrawAction: BoundAction;
}) {
  const pendingTradeName = history.find((r) => r.status === "pending" && r.fieldName === "trade_name");
  const pendingBillingAddress = history.find((r) => r.status === "pending" && r.fieldName === "billing_address");

  return (
    <div className="flex flex-col gap-4">
      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        <div className="flex flex-wrap items-center gap-2">
          <h2 className="text-sm font-semibold text-neutral-900">{profile.legalName}</h2>
          <StatusBadge tone={profile.customerStatus === "active" ? "success" : "neutral"} label={profile.customerStatus} />
        </div>

        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
          <LockedField label="Legal name" value={profile.legalName} note="Legal name changes require a separate legal/tax verification process -- contact your account administrator." />
          <LockedField label="Tax ID" value={profile.taxId ?? ""} note="Tax ID changes require a separate legal/tax verification process -- contact your account administrator." />
        </div>

        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
          <div className="flex flex-col gap-2">
            <span className="text-xs font-medium text-neutral-500">Trade name</span>
            {pendingTradeName ? <PendingChangeBanner request={pendingTradeName} withdrawAction={withdrawAction} /> : <TradeNameForm currentValue={profile.tradeName ?? ""} submitAction={submitTradeNameAction} />}
          </div>
          <div className="flex flex-col gap-2">
            <span className="text-xs font-medium text-neutral-500">Billing address</span>
            {pendingBillingAddress ? (
              <PendingChangeBanner request={pendingBillingAddress} withdrawAction={withdrawAction} />
            ) : (
              <BillingAddressForm currentValue={profile.billingAddress as CustomerProfileBillingAddress} submitAction={submitBillingAddressAction} />
            )}
          </div>
        </div>
      </section>

      <ContactsSection contacts={contacts} />
      <HistorySection history={history} />
    </div>
  );
}
