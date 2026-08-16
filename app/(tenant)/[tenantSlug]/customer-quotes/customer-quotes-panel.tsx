"use client";

import { useActionState } from "react";
import Link from "next/link";
import { Button } from "../../../../components/ui/button.tsx";
import { StatusBadge, type StatusTone } from "../../../../components/ui/status-badge.tsx";
import { EmptyState } from "../../../../components/ui/empty-state.tsx";
import type { CustomerQuoteRequestActionState } from "./actions.ts";
import type { CustomerQuoteRequest, QuoteRequestStatus } from "../../../../server/contracts/customer-quote-request/customer-quote-request.ts";
import type { CustomerPortalScopeContextRow } from "../../../../server/contracts/customer-portal-scope/customer-portal-scope.ts";

const INITIAL_STATE: CustomerQuoteRequestActionState = { error: null };

const STATUS_TONE: Record<QuoteRequestStatus, StatusTone> = {
  draft: "neutral",
  submitted: "info",
  cancelled: "neutral",
  converted: "success",
};

function QuoteRequestRow({ tenantSlug, request, accountName }: { tenantSlug: string; request: CustomerQuoteRequest; accountName: string }) {
  return (
    <tr className="border-t border-neutral-100">
      <td className="p-2 text-sm">
        <Link href={`/${tenantSlug}/customer-quotes/${request.id}`} className="text-primary underline">
          {request.cargoDescription || "Untitled request"}
        </Link>
      </td>
      <td className="p-2 text-sm">
        <StatusBadge tone={STATUS_TONE[request.status]} label={request.status} />
      </td>
      <td className="p-2 text-xs text-neutral-500">{request.serviceType ?? "—"}</td>
      <td className="p-2 text-xs text-neutral-500">{accountName}</td>
      <td className="p-2 text-xs text-neutral-500">{new Date(request.updatedAt).toLocaleString()}</td>
    </tr>
  );
}

function CreateQuoteRequestForm({
  accounts,
  createAction,
}: {
  accounts: readonly CustomerPortalScopeContextRow[];
  createAction: (prevState: CustomerQuoteRequestActionState, formData: FormData) => Promise<CustomerQuoteRequestActionState>;
}) {
  const [state, formAction, pending] = useActionState(createAction, INITIAL_STATE);

  return (
    <form action={formAction} className="grid grid-cols-1 gap-2 rounded-md border border-neutral-200 p-4 sm:grid-cols-2">
      <h2 className="text-sm font-semibold text-neutral-900 sm:col-span-2">Request a quotation</h2>
      <label className="text-xs text-neutral-500">
        Account
        <select name="accountId" required defaultValue={accounts.length === 1 ? accounts[0]?.accountId : ""} className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm">
          {accounts.length !== 1 ? (
            <option value="" disabled>
              Select an account
            </option>
          ) : null}
          {accounts.map((a) => (
            <option key={a.accountId} value={a.accountId}>
              {a.accountName}
            </option>
          ))}
        </select>
      </label>
      <label className="text-xs text-neutral-500">
        Service type
        <input name="serviceType" placeholder="e.g. ocean_freight" className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" />
      </label>
      <label className="text-xs text-neutral-500 sm:col-span-2">
        Cargo description
        <textarea name="cargoDescription" rows={2} className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" placeholder="What are you shipping?" />
      </label>
      <label className="text-xs text-neutral-500">
        Origin label
        <input name="originLabel" placeholder="e.g. Jakarta warehouse" className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" />
      </label>
      <label className="text-xs text-neutral-500">
        Destination label
        <input name="destinationLabel" placeholder="e.g. Surabaya port" className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" />
      </label>
      <label className="text-xs text-neutral-500">
        Requested pickup date
        <input type="date" name="requestedPickupDate" className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" />
      </label>
      <label className="text-xs text-neutral-500">
        Requested delivery date
        <input type="date" name="requestedDeliveryDate" className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" />
      </label>
      <label className="text-xs text-neutral-500 sm:col-span-2">
        Notes
        <textarea name="notes" rows={2} className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" />
      </label>
      <div className="sm:col-span-2">
        <Button type="submit" variant="primary" loading={pending} loadingLabel="Starting…" disabled={accounts.length === 0}>
          Start draft
        </Button>
      </div>
      {accounts.length === 0 ? <p className="text-xs text-neutral-500 sm:col-span-2">No account is linked to your customer profile yet.</p> : null}
      {state.error ? (
        <p role="alert" className="text-xs text-danger sm:col-span-2">
          {state.error}
        </p>
      ) : null}
    </form>
  );
}

export function CustomerQuotesPanel({
  tenantSlug,
  accounts,
  requests,
  createAction,
}: {
  tenantSlug: string;
  accounts: readonly CustomerPortalScopeContextRow[];
  requests: readonly CustomerQuoteRequest[];
  createAction: (prevState: CustomerQuoteRequestActionState, formData: FormData) => Promise<CustomerQuoteRequestActionState>;
}) {
  const accountNameById = new Map(accounts.map((a) => [a.accountId, a.accountName]));

  return (
    <div className="flex flex-col gap-4">
      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Your quote requests</h2>
        {requests.length === 0 ? (
          <EmptyState title="No quote requests yet" description="Quote requests you or a colleague on your account submit will appear here." />
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full border-collapse">
              <thead>
                <tr className="text-left text-xs font-medium text-neutral-500">
                  <th className="p-2">Request</th>
                  <th className="p-2">Status</th>
                  <th className="p-2">Service</th>
                  <th className="p-2">Account</th>
                  <th className="p-2">Updated</th>
                </tr>
              </thead>
              <tbody>
                {requests.map((r) => (
                  <QuoteRequestRow key={r.id} tenantSlug={tenantSlug} request={r} accountName={accountNameById.get(r.accountId) ?? "—"} />
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>

      <CreateQuoteRequestForm accounts={accounts} createAction={createAction} />
    </div>
  );
}
