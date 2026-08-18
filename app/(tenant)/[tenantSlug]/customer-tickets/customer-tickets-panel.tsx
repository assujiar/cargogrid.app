"use client";

import { useActionState, useState } from "react";
import Link from "next/link";
import { Button } from "../../../../components/ui/button.tsx";
import { StatusBadge, type StatusTone } from "../../../../components/ui/status-badge.tsx";
import { EmptyState } from "../../../../components/ui/empty-state.tsx";
import type { CustomerTicketActionState, CustomerTicketPrecreateLinkSearchActionState } from "./actions.ts";
import {
  TICKET_PRIORITIES,
  TICKET_LINK_RELATIONSHIPS,
  type TicketStatus,
  type TicketLinkRelationship,
  type TicketPortalLinkCandidateRow,
  type TicketPrecreateLinkEntityType,
  type CustomerAccountRow,
  type CustomerTicketCategoryRow,
  type CustomerTicketListRow,
} from "../../../../server/contracts/ticketing/ticketing.ts";

const INITIAL_STATE: CustomerTicketActionState = { error: null };

const PRECREATE_LINK_ENTITY_TYPE_LABELS: Record<TicketPrecreateLinkEntityType, string> = {
  shipment: "Shipment",
  warehouse_order: "Warehouse order",
  invoice: "Invoice",
  document: "Document",
};

const PRECREATE_LINK_RELATIONSHIP_LABELS: Record<TicketLinkRelationship, string> = {
  primary_subject: "Primary subject",
  related: "Related",
  affected: "Affected",
  context: "Context",
};

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

/** CPL-311 (Invoice and Billing Visibility): pre-fill payload for the "dispute this invoice" deep link from the customer invoice detail page -- see ./page.tsx's own header comment. */
export interface CustomerTicketDisputePrefill {
  readonly invoiceId: string;
  readonly invoiceNumber: string;
}

/** CPL-313 (Complaint and Ticket): a customer's selection from the generic LinkRecordPicker below -- lifted state, submitted as hidden fields on CreateCustomerTicketForm's own single top-level form (search happens on a SEPARATE, sibling form/action; nested <form> is invalid HTML). */
export interface SelectedLinkCandidate {
  readonly entityType: TicketPrecreateLinkEntityType;
  readonly entityId: string;
  readonly relationship: TicketLinkRelationship;
  readonly label: string;
}

// A SEPARATE, sibling form from CreateCustomerTicketForm (a ticket does not
// exist yet, so "linking" here only stores the caller's selection locally
// via onSelect -- the ACTUAL link happens server-side, after ticket
// creation, inside createCustomerTicketAction, exactly like the existing
// CPL-311 disputeInvoiceId auto-link above). Every candidate this renders
// is already independently reauthorized server-side (C-05, app.search_
// customer_ticket_link_candidates_precreate) -- and reauthorized AGAIN at
// actual link time (app.link_ticket_record/app.link_ticket_portal_record),
// so a stale/no-longer-eligible selection between search and submit simply
// fails the post-create link as a safe, disclosed best-effort no-op (mirrors
// the dispute flow's own established convention).
function LinkRecordPicker({
  searchAction,
  selected,
  onSelect,
  onClear,
}: {
  searchAction: (prevState: CustomerTicketPrecreateLinkSearchActionState, formData: FormData) => Promise<CustomerTicketPrecreateLinkSearchActionState>;
  selected: SelectedLinkCandidate | null;
  onSelect: (candidate: SelectedLinkCandidate) => void;
  onClear: () => void;
}) {
  const [searchState, searchFormAction, searchPending] = useActionState(searchAction, { error: null, entityType: null, relationship: "related", results: [] } as CustomerTicketPrecreateLinkSearchActionState);

  if (selected) {
    return (
      <div className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Linked record</h2>
        <div className="flex flex-wrap items-center justify-between gap-2 rounded bg-neutral-50 p-2 text-sm">
          <span>
            <span className="font-medium text-neutral-900">{PRECREATE_LINK_ENTITY_TYPE_LABELS[selected.entityType]}</span> — {selected.label}
          </span>
          <Button type="button" variant="secondary" onClick={onClear}>
            Remove
          </Button>
        </div>
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
      <h2 className="text-sm font-semibold text-neutral-900">Link a record (optional)</h2>
      <p className="text-xs text-neutral-500">Link this ticket to your own shipment, warehouse order, invoice, or document. Every result is already scoped to your account -- a record you cannot access never appears here.</p>
      <form action={searchFormAction} className="flex flex-col gap-2 rounded bg-neutral-50 p-2">
        <div className="flex flex-wrap items-end gap-2">
          <label className="flex flex-col gap-1 text-xs text-neutral-600">
            Record type
            <select name="entityType" required defaultValue={searchState.entityType ?? ""} className="rounded border border-neutral-300 p-1.5 text-xs">
              <option value="" disabled>
                Select…
              </option>
              {(Object.keys(PRECREATE_LINK_ENTITY_TYPE_LABELS) as TicketPrecreateLinkEntityType[]).map((t) => (
                <option key={t} value={t}>
                  {PRECREATE_LINK_ENTITY_TYPE_LABELS[t]}
                </option>
              ))}
            </select>
          </label>
          <label className="flex flex-col gap-1 text-xs text-neutral-600">
            Relationship
            <select name="relationship" defaultValue={searchState.relationship} className="rounded border border-neutral-300 p-1.5 text-xs">
              {TICKET_LINK_RELATIONSHIPS.map((r) => (
                <option key={r} value={r}>
                  {PRECREATE_LINK_RELATIONSHIP_LABELS[r]}
                </option>
              ))}
            </select>
          </label>
          <input name="searchText" placeholder="Search by number/name…" className="min-w-[12rem] flex-1 rounded border border-neutral-300 p-1.5 text-xs" />
          <Button type="submit" variant="secondary" loading={searchPending} loadingLabel="Searching…">
            Search
          </Button>
        </div>
        {searchState.error ? (
          <p role="alert" className="text-xs text-danger">
            {searchState.error}
          </p>
        ) : null}
        {searchState.entityType ? (
          searchState.results.length === 0 ? (
            <p className="text-xs text-neutral-500">No matching records found on your account.</p>
          ) : (
            <ul className="flex flex-col gap-1">
              {searchState.results.map((c: TicketPortalLinkCandidateRow) => (
                <li key={c.entityId} className="flex flex-wrap items-center justify-between gap-2 rounded bg-white p-1.5 text-xs">
                  <div>
                    <span className="font-medium text-neutral-900">{c.primaryLabel}</span>
                    {c.secondaryLabel ? <span className="text-neutral-500"> — {c.secondaryLabel}</span> : null}
                  </div>
                  <Button
                    type="button"
                    variant="secondary"
                    onClick={() =>
                      onSelect({
                        entityType: searchState.entityType as TicketPrecreateLinkEntityType,
                        entityId: c.entityId,
                        relationship: searchState.relationship,
                        label: c.primaryLabel,
                      })
                    }
                  >
                    Select
                  </Button>
                </li>
              ))}
            </ul>
          )
        ) : null}
      </form>
    </div>
  );
}

function CreateCustomerTicketForm({
  accounts,
  categories,
  createTicketAction,
  initialDispute,
  linked,
}: {
  accounts: readonly CustomerAccountRow[];
  categories: readonly CustomerTicketCategoryRow[];
  createTicketAction: (prevState: CustomerTicketActionState, formData: FormData) => Promise<CustomerTicketActionState>;
  initialDispute?: CustomerTicketDisputePrefill | null;
  linked?: SelectedLinkCandidate | null;
}) {
  const [state, formAction, pending] = useActionState(createTicketAction, INITIAL_STATE);
  const noCategoriesConfigured = categories.length === 0;

  return (
    <form action={formAction} className="grid grid-cols-1 gap-2 rounded-md border border-neutral-200 p-4 sm:grid-cols-2">
      <h2 className="text-sm font-semibold text-neutral-900 sm:col-span-2">{initialDispute ? "Dispute an invoice" : "Raise a new support ticket"}</h2>
      {initialDispute ? (
        <>
          <p className="text-xs text-neutral-500 sm:col-span-2">This ticket will be linked to invoice {initialDispute.invoiceNumber}.</p>
          <input type="hidden" name="disputeInvoiceId" value={initialDispute.invoiceId} />
        </>
      ) : linked ? (
        <>
          <input type="hidden" name="linkEntityType" value={linked.entityType} />
          <input type="hidden" name="linkEntityId" value={linked.entityId} />
          <input type="hidden" name="linkRelationship" value={linked.relationship} />
        </>
      ) : null}
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
        <input name="subject" required minLength={1} defaultValue={initialDispute ? `Invoice dispute -- ${initialDispute.invoiceNumber}` : undefined} className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" />
      </label>
      <label className="text-xs text-neutral-500 sm:col-span-2">
        Description
        <textarea
          name="body"
          required
          minLength={1}
          rows={4}
          defaultValue={initialDispute ? `I'd like to dispute invoice ${initialDispute.invoiceNumber}.\n\nDetails: ` : undefined}
          className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm"
          placeholder="Describe your issue or question."
        />
      </label>
      <div className="sm:col-span-2">
        <Button type="submit" variant="primary" loading={pending} loadingLabel="Submitting…" disabled={noCategoriesConfigured || accounts.length === 0}>
          {initialDispute ? "Submit dispute" : "Submit ticket"}
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
  searchLinkCandidatesAction,
  initialDispute,
}: {
  tenantSlug: string;
  accounts: readonly CustomerAccountRow[];
  categories: readonly CustomerTicketCategoryRow[];
  tickets: readonly CustomerTicketListRow[];
  createTicketAction: (prevState: CustomerTicketActionState, formData: FormData) => Promise<CustomerTicketActionState>;
  searchLinkCandidatesAction: (prevState: CustomerTicketPrecreateLinkSearchActionState, formData: FormData) => Promise<CustomerTicketPrecreateLinkSearchActionState>;
  initialDispute?: CustomerTicketDisputePrefill | null;
}) {
  // Lifted, client-only selection state (design note on LinkRecordPicker
  // above: search is a SEPARATE sibling form/action from the actual ticket
  // creation form; the link itself happens server-side, after ticket
  // creation, inside createCustomerTicketAction).
  const [linked, setLinked] = useState<SelectedLinkCandidate | null>(null);

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

      {initialDispute ? null : <LinkRecordPicker searchAction={searchLinkCandidatesAction} selected={linked} onSelect={setLinked} onClear={() => setLinked(null)} />}

      <CreateCustomerTicketForm accounts={accounts} categories={categories} createTicketAction={createTicketAction} initialDispute={initialDispute} linked={linked} />
    </div>
  );
}
