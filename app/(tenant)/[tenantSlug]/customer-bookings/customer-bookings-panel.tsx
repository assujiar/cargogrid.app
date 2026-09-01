"use client";

import { useActionState } from "react";
import Link from "next/link";
import { Button } from "../../../../components/ui/button.tsx";
import { StatusBadge, type StatusTone } from "../../../../components/ui/status-badge.tsx";
import { EmptyState } from "../../../../components/ui/empty-state.tsx";
import { FormField } from "../../../../components/forms/form-field.tsx";
import { Input } from "../../../../components/forms/input.tsx";
import { Select } from "../../../../components/forms/select.tsx";
import { Textarea } from "../../../../components/forms/textarea.tsx";
import { ValidationMessage } from "../../../../components/forms/validation-message.tsx";
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
  const errorId = "create-booking-error";
  const describedBy = state.error ? errorId : undefined;

  return (
    <form action={formAction} className="grid grid-cols-1 gap-2 rounded-md border border-neutral-200 p-4 sm:grid-cols-2">
      <h2 className="text-sm font-semibold text-neutral-900 sm:col-span-2">Book a shipment</h2>

      <FormField id="create-booking-account" label={<span className="text-xs text-neutral-500">Account</span>}>
        <Select id="create-booking-account" name="accountId" required defaultValue={defaultAccountId} aria-describedby={describedBy}>
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
        </Select>
      </FormField>

      <FormField id="create-booking-linked-quote" label={<span className="text-xs text-neutral-500">Originating accepted quote (optional)</span>}>
        <Select id="create-booking-linked-quote" name="linkedQuoteRequestId" defaultValue={prefill?.id ?? ""} aria-describedby={describedBy}>
          <option value="">Direct booking (no quote)</option>
          {acceptedQuoteRequests.map((q) => (
            <option key={q.id} value={q.id}>
              {q.cargoDescription || "Untitled quote"} ({q.serviceType ?? "—"})
            </option>
          ))}
        </Select>
      </FormField>

      <div className="sm:col-span-2">
        <FormField id="create-booking-cargo-description" label={<span className="text-xs text-neutral-500">Cargo description</span>}>
          <Textarea id="create-booking-cargo-description" name="cargoDescription" rows={2} defaultValue={prefill?.cargoDescription ?? ""} placeholder="What are you shipping?" aria-describedby={describedBy} />
        </FormField>
      </div>

      <fieldset className="rounded border border-neutral-100 p-2 sm:col-span-2">
        <legend className="px-1 text-xs font-medium text-neutral-500">Pickup</legend>
        <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">
          <FormField id="create-booking-pickup-label" label={<span className="text-xs text-neutral-500">Label / address</span>}>
            <Input id="create-booking-pickup-label" name="pickupLabel" defaultValue={locationDefault(prefill?.origin, "label")} aria-describedby={describedBy} />
          </FormField>
          <FormField id="create-booking-pickup-contact-name" label={<span className="text-xs text-neutral-500">Contact name</span>}>
            <Input id="create-booking-pickup-contact-name" name="pickupContactName" aria-describedby={describedBy} />
          </FormField>
          <FormField id="create-booking-pickup-contact-phone" label={<span className="text-xs text-neutral-500">Contact phone</span>}>
            <Input id="create-booking-pickup-contact-phone" name="pickupContactPhone" aria-describedby={describedBy} />
          </FormField>
          <FormField id="create-booking-pickup-at" label={<span className="text-xs text-neutral-500">Requested pickup date/time</span>}>
            <Input id="create-booking-pickup-at" type="datetime-local" name="requestedPickupAt" aria-describedby={describedBy} />
          </FormField>
        </div>
      </fieldset>

      <fieldset className="rounded border border-neutral-100 p-2 sm:col-span-2">
        <legend className="px-1 text-xs font-medium text-neutral-500">Delivery</legend>
        <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">
          <FormField id="create-booking-delivery-label" label={<span className="text-xs text-neutral-500">Label / address</span>}>
            <Input id="create-booking-delivery-label" name="deliveryLabel" defaultValue={locationDefault(prefill?.destination, "label")} aria-describedby={describedBy} />
          </FormField>
          <FormField id="create-booking-delivery-contact-name" label={<span className="text-xs text-neutral-500">Contact name</span>}>
            <Input id="create-booking-delivery-contact-name" name="deliveryContactName" aria-describedby={describedBy} />
          </FormField>
          <FormField id="create-booking-delivery-contact-phone" label={<span className="text-xs text-neutral-500">Contact phone</span>}>
            <Input id="create-booking-delivery-contact-phone" name="deliveryContactPhone" aria-describedby={describedBy} />
          </FormField>
          <FormField id="create-booking-delivery-at" label={<span className="text-xs text-neutral-500">Requested delivery date/time</span>}>
            <Input id="create-booking-delivery-at" type="datetime-local" name="requestedDeliveryAt" aria-describedby={describedBy} />
          </FormField>
        </div>
      </fieldset>

      <div className="sm:col-span-2">
        <FormField id="create-booking-special-instructions" label={<span className="text-xs text-neutral-500">Special instructions</span>}>
          <Textarea id="create-booking-special-instructions" name="specialInstructions" rows={2} aria-describedby={describedBy} />
        </FormField>
      </div>

      <div className="sm:col-span-2">
        <Button type="submit" variant="primary" loading={pending} loadingLabel="Starting…" disabled={accounts.length === 0}>
          Start draft
        </Button>
      </div>
      {accounts.length === 0 ? <p className="text-xs text-neutral-500 sm:col-span-2">No account is linked to your customer profile yet.</p> : null}
      {state.error ? (
        <div className="sm:col-span-2">
          <ValidationMessage id={errorId}>{state.error}</ValidationMessage>
        </div>
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
