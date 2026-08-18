"use client";

import { useActionState } from "react";
import Link from "next/link";
import { Button } from "../../../../components/ui/button.tsx";
import { StatusBadge, type StatusTone } from "../../../../components/ui/status-badge.tsx";
import { EmptyState } from "../../../../components/ui/empty-state.tsx";
import type { CustomerBookingRequestActionState } from "./actions.ts";
import type { BookingRequestStatus, CustomerBookingRequest } from "../../../../server/contracts/customer-booking-request/customer-booking-request.ts";
import type { CustomerQuoteRequest } from "../../../../server/contracts/customer-quote-request/customer-quote-request.ts";
import type { CustomerPortalScopeContextRow } from "../../../../server/contracts/customer-portal-scope/customer-portal-scope.ts";

const INITIAL_STATE: CustomerBookingRequestActionState = { error: null };

const STATUS_TONE: Record<BookingRequestStatus, StatusTone> = {
  draft: "neutral",
  submitted: "info",
  reschedule_requested: "warning",
  cancel_requested: "warning",
  cancelled: "neutral",
  converted: "success",
};

const STATUS_LABEL: Record<BookingRequestStatus, string> = {
  draft: "draft",
  submitted: "submitted",
  reschedule_requested: "reschedule requested",
  cancel_requested: "cancellation requested",
  cancelled: "cancelled",
  converted: "converted",
};

function BookingRow({ tenantSlug, booking, accountName }: { tenantSlug: string; booking: CustomerBookingRequest; accountName: string }) {
  return (
    <tr className="border-t border-neutral-100">
      <td className="p-2 text-sm">
        <Link href={`/${tenantSlug}/customer-bookings/${booking.id}`} className="text-primary underline">
          {booking.cargoDescription || "Untitled booking"}
        </Link>
      </td>
      <td className="p-2 text-sm">
        <StatusBadge tone={STATUS_TONE[booking.status]} label={STATUS_LABEL[booking.status]} />
      </td>
      <td className="p-2 text-xs text-neutral-500">{accountName}</td>
      <td className="p-2 text-xs text-neutral-500">{booking.requestedPickupAt ? new Date(booking.requestedPickupAt).toLocaleString() : "—"}</td>
      <td className="p-2 text-xs text-neutral-500">{new Date(booking.updatedAt).toLocaleString()}</td>
    </tr>
  );
}

function locationDefault(location: Record<string, unknown> | undefined, key: string): string {
  const value = location?.[key];
  return typeof value === "string" ? value : "";
}

function CreateBookingForm({
  accounts,
  acceptedQuoteRequests,
  prefill,
  createAction,
}: {
  accounts: readonly CustomerPortalScopeContextRow[];
  acceptedQuoteRequests: readonly CustomerQuoteRequest[];
  prefill: CustomerQuoteRequest | null;
  createAction: (prevState: CustomerBookingRequestActionState, formData: FormData) => Promise<CustomerBookingRequestActionState>;
}) {
  const [state, formAction, pending] = useActionState(createAction, INITIAL_STATE);
  const defaultAccountId = prefill?.accountId ?? (accounts.length === 1 ? accounts[0]?.accountId : "");

  return (
    <form action={formAction} className="grid grid-cols-1 gap-2 rounded-md border border-neutral-200 p-4 sm:grid-cols-2">
      <h2 className="text-sm font-semibold text-neutral-900 sm:col-span-2">Book a shipment</h2>

      <label className="text-xs text-neutral-500">
        Account
        <select name="accountId" required defaultValue={defaultAccountId} className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm">
          {accounts.length !== 1 || defaultAccountId === "" ? (
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
        Originating accepted quote (optional)
        <select name="linkedQuoteRequestId" defaultValue={prefill?.id ?? ""} className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm">
          <option value="">Direct booking (no quote)</option>
          {acceptedQuoteRequests.map((q) => (
            <option key={q.id} value={q.id}>
              {q.cargoDescription || "Untitled quote"} ({q.serviceType ?? "—"})
            </option>
          ))}
        </select>
      </label>

      <label className="text-xs text-neutral-500 sm:col-span-2">
        Cargo description
        <textarea name="cargoDescription" rows={2} defaultValue={prefill?.cargoDescription ?? ""} className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" placeholder="What are you shipping?" />
      </label>

      <fieldset className="rounded border border-neutral-100 p-2 sm:col-span-2">
        <legend className="px-1 text-xs font-medium text-neutral-500">Pickup</legend>
        <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">
          <label className="text-xs text-neutral-500">
            Label / address
            <input name="pickupLabel" defaultValue={locationDefault(prefill?.origin, "label")} className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" />
          </label>
          <label className="text-xs text-neutral-500">
            Contact name
            <input name="pickupContactName" className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" />
          </label>
          <label className="text-xs text-neutral-500">
            Contact phone
            <input name="pickupContactPhone" className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" />
          </label>
          <label className="text-xs text-neutral-500">
            Requested pickup date/time
            <input type="datetime-local" name="requestedPickupAt" className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" />
          </label>
        </div>
      </fieldset>

      <fieldset className="rounded border border-neutral-100 p-2 sm:col-span-2">
        <legend className="px-1 text-xs font-medium text-neutral-500">Delivery</legend>
        <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">
          <label className="text-xs text-neutral-500">
            Label / address
            <input name="deliveryLabel" defaultValue={locationDefault(prefill?.destination, "label")} className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" />
          </label>
          <label className="text-xs text-neutral-500">
            Contact name
            <input name="deliveryContactName" className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" />
          </label>
          <label className="text-xs text-neutral-500">
            Contact phone
            <input name="deliveryContactPhone" className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" />
          </label>
          <label className="text-xs text-neutral-500">
            Requested delivery date/time
            <input type="datetime-local" name="requestedDeliveryAt" className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" />
          </label>
        </div>
      </fieldset>

      <label className="text-xs text-neutral-500 sm:col-span-2">
        Special instructions
        <textarea name="specialInstructions" rows={2} className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" />
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

export function CustomerBookingsPanel({
  tenantSlug,
  accounts,
  bookings,
  acceptedQuoteRequests,
  prefill,
  createAction,
}: {
  tenantSlug: string;
  accounts: readonly CustomerPortalScopeContextRow[];
  bookings: readonly CustomerBookingRequest[];
  acceptedQuoteRequests: readonly CustomerQuoteRequest[];
  prefill: CustomerQuoteRequest | null;
  createAction: (prevState: CustomerBookingRequestActionState, formData: FormData) => Promise<CustomerBookingRequestActionState>;
}) {
  const accountNameById = new Map(accounts.map((a) => [a.accountId, a.accountName]));

  return (
    <div className="flex flex-col gap-4">
      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Your bookings</h2>
        {bookings.length === 0 ? (
          <EmptyState title="No bookings yet" description="Bookings you or a colleague on your account submit will appear here." />
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full border-collapse">
              <thead>
                <tr className="text-left text-xs font-medium text-neutral-500">
                  <th className="p-2">Booking</th>
                  <th className="p-2">Status</th>
                  <th className="p-2">Account</th>
                  <th className="p-2">Requested pickup</th>
                  <th className="p-2">Updated</th>
                </tr>
              </thead>
              <tbody>
                {bookings.map((b) => (
                  <BookingRow key={b.id} tenantSlug={tenantSlug} booking={b} accountName={accountNameById.get(b.accountId) ?? "—"} />
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>

      <CreateBookingForm accounts={accounts} acceptedQuoteRequests={acceptedQuoteRequests} prefill={prefill} createAction={createAction} />
    </div>
  );
}
