"use client";

import { useActionState } from "react";
import Link from "next/link";
import { Button } from "../../../../components/ui/button.tsx";
import { StatusBadge, type StatusTone } from "../../../../components/ui/status-badge.tsx";
import { EmptyState } from "../../../../components/ui/empty-state.tsx";
import type { CustomerTicketActionState } from "./actions.ts";
import { TICKET_PRIORITIES, type TicketStatus, type CustomerAccountRow, type CustomerTicketCategoryRow, type CustomerTicketListRow } from "../../../../server/contracts/ticketing/ticketing.ts";

const INITIAL_STATE: CustomerTicketActionState = { error: null };

const STATUS_TONE: Record<TicketStatus, StatusTone> = {
  new: "info",
  open: "info",
  pending: "warning",
  on_hold: "warning",
  resolved: "success",
  closed: "neutral",
  cancelled: "neutral",
};

function CustomerTicketRow({ tenantSlug, ticket }: { tenantSlug: string; ticket: CustomerTicketListRow }) {
  return (
    <tr className="border-t border-neutral-100">
      <td className="p-2 text-sm">
        <Link href={`/${tenantSlug}/customer-tickets/${ticket.id}`} className="text-primary underline">
          {ticket.ticketNumber}
        </Link>
      </td>
      <td className="p-2 text-sm">{ticket.subject}</td>
      <td className="p-2 text-sm">
        <StatusBadge tone={STATUS_TONE[ticket.status]} label={ticket.status.replace(/_/g, " ")} />
      </td>
      <td className="p-2 text-sm">{ticket.priority}</td>
      <td className="p-2 text-xs text-neutral-500">{ticket.categoryName}</td>
      <td className="p-2 text-xs text-neutral-500">{ticket.accountName}</td>
    </tr>
  );
}

function CreateCustomerTicketForm({
  accounts,
  categories,
  createTicketAction,
}: {
  accounts: readonly CustomerAccountRow[];
  categories: readonly CustomerTicketCategoryRow[];
  createTicketAction: (prevState: CustomerTicketActionState, formData: FormData) => Promise<CustomerTicketActionState>;
}) {
  const [state, formAction, pending] = useActionState(createTicketAction, INITIAL_STATE);
  const noCategoriesConfigured = categories.length === 0;

  return (
    <form action={formAction} className="grid grid-cols-1 gap-2 rounded-md border border-neutral-200 p-4 sm:grid-cols-2">
      <h2 className="text-sm font-semibold text-neutral-900 sm:col-span-2">Raise a new support ticket</h2>
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
              {a.legalName}
            </option>
          ))}
        </select>
      </label>
      <label className="text-xs text-neutral-500">
        Category
        <select name="categoryId" required defaultValue="" className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm">
          <option value="" disabled>
            Select a category
          </option>
          {categories.map((c) => (
            <option key={c.id} value={c.id}>
              {c.name}
            </option>
          ))}
        </select>
      </label>
      <label className="text-xs text-neutral-500">
        Priority
        <select name="priority" defaultValue="normal" className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm">
          {TICKET_PRIORITIES.map((p) => (
            <option key={p} value={p}>
              {p}
            </option>
          ))}
        </select>
      </label>
      <label className="text-xs text-neutral-500 sm:col-span-2">
        Subject
        <input name="subject" required minLength={1} className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" />
      </label>
      <label className="text-xs text-neutral-500 sm:col-span-2">
        Description
        <textarea name="body" required minLength={1} rows={4} className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" placeholder="Describe your issue or question." />
      </label>
      <div className="sm:col-span-2">
        <Button type="submit" variant="primary" loading={pending} loadingLabel="Submitting…" disabled={noCategoriesConfigured || accounts.length === 0}>
          Submit ticket
        </Button>
      </div>
      {noCategoriesConfigured ? (
        <p className="text-xs text-neutral-500 sm:col-span-2">No support categories are configured for customer intake yet -- contact your account manager.</p>
      ) : null}
      {accounts.length === 0 ? <p className="text-xs text-neutral-500 sm:col-span-2">No account is linked to your customer profile yet.</p> : null}
      {state.error ? (
        <p role="alert" className="text-xs text-danger sm:col-span-2">
          {state.error}
        </p>
      ) : null}
    </form>
  );
}

export function CustomerTicketsPanel({
  tenantSlug,
  accounts,
  categories,
  tickets,
  createTicketAction,
}: {
  tenantSlug: string;
  accounts: readonly CustomerAccountRow[];
  categories: readonly CustomerTicketCategoryRow[];
  tickets: readonly CustomerTicketListRow[];
  createTicketAction: (prevState: CustomerTicketActionState, formData: FormData) => Promise<CustomerTicketActionState>;
}) {
  return (
    <div className="flex flex-col gap-4">
      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Your tickets</h2>
        {tickets.length === 0 ? (
          <EmptyState title="No tickets yet" description="Tickets you or a colleague on your account raise will appear here." />
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full border-collapse">
              <thead>
                <tr className="text-left text-xs font-medium text-neutral-500">
                  <th className="p-2">Ticket</th>
                  <th className="p-2">Subject</th>
                  <th className="p-2">Status</th>
                  <th className="p-2">Priority</th>
                  <th className="p-2">Category</th>
                  <th className="p-2">Account</th>
                </tr>
              </thead>
              <tbody>
                {tickets.map((t) => (
                  <CustomerTicketRow key={t.id} tenantSlug={tenantSlug} ticket={t} />
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>

      <CreateCustomerTicketForm accounts={accounts} categories={categories} createTicketAction={createTicketAction} />
    </div>
  );
}
