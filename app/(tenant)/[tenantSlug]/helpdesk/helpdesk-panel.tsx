"use client";

import { useActionState } from "react";
import Link from "next/link";
import { Button } from "../../../../components/ui/button.tsx";
import { StatusBadge, type StatusTone } from "../../../../components/ui/status-badge.tsx";
import { EmptyState } from "../../../../components/ui/empty-state.tsx";
import type { HelpdeskActionState } from "./actions.ts";
import { TICKET_PRIORITIES, HELPDESK_SEVERITIES, HELPDESK_ENVIRONMENTS, type TicketStatus, type HelpdeskTicketCategoryRow, type HelpdeskTicketListRow } from "../../../../server/contracts/ticketing/ticketing.ts";

const INITIAL_STATE: HelpdeskActionState = { error: null };

const STATUS_TONE: Record<TicketStatus, StatusTone> = {
  new: "info",
  open: "info",
  pending: "warning",
  on_hold: "warning",
  resolved: "success",
  closed: "neutral",
  cancelled: "neutral",
};

function HelpdeskTicketRow({ tenantSlug, ticket }: { tenantSlug: string; ticket: HelpdeskTicketListRow }) {
  return (
    <tr className="border-t border-neutral-100">
      <td className="p-2 text-sm">
        <Link href={`/${tenantSlug}/helpdesk/${ticket.id}`} className="text-primary underline">
          {ticket.ticketNumber}
        </Link>
      </td>
      <td className="p-2 text-sm">{ticket.subject}</td>
      <td className="p-2 text-sm">
        <StatusBadge tone={STATUS_TONE[ticket.status]} label={ticket.status.replace(/_/g, " ")} />
      </td>
      <td className="p-2 text-sm">{ticket.priority}</td>
      <td className="p-2 text-xs text-neutral-500">{ticket.severity ?? "—"}</td>
      <td className="p-2 text-xs text-neutral-500">{ticket.categoryName}</td>
    </tr>
  );
}

function CreateHelpdeskTicketForm({
  categories,
  createTicketAction,
}: {
  categories: readonly HelpdeskTicketCategoryRow[];
  createTicketAction: (prevState: HelpdeskActionState, formData: FormData) => Promise<HelpdeskActionState>;
}) {
  const [state, formAction, pending] = useActionState(createTicketAction, INITIAL_STATE);
  const noCategoriesConfigured = categories.length === 0;

  return (
    <form action={formAction} className="grid grid-cols-1 gap-2 rounded-md border border-neutral-200 p-4 sm:grid-cols-2">
      <h2 className="text-sm font-semibold text-neutral-900 sm:col-span-2">Open a CargoGrid support case</h2>
      <p className="text-xs text-neutral-500 sm:col-span-2">
        This opens a governed support ticket only. It never grants CargoGrid support access to your business data on its own — any diagnostic access requires a separate, reasoned, time-bound grant your organization
        approves.
      </p>
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
      <label className="text-xs text-neutral-500">
        Severity (optional)
        <select name="severity" defaultValue="" className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm">
          <option value="">Not specified</option>
          {HELPDESK_SEVERITIES.map((s) => (
            <option key={s} value={s}>
              {s}
            </option>
          ))}
        </select>
      </label>
      <label className="text-xs text-neutral-500">
        Environment (optional)
        <select name="environment" defaultValue="" className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm">
          <option value="">Not specified</option>
          {HELPDESK_ENVIRONMENTS.map((e) => (
            <option key={e} value={e}>
              {e}
            </option>
          ))}
        </select>
      </label>
      <label className="text-xs text-neutral-500">
        Product area (optional)
        <input name="productArea" className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" />
      </label>
      <label className="text-xs text-neutral-500">
        Your own reference (optional)
        <input name="externalReference" className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" />
      </label>
      <label className="text-xs text-neutral-500 sm:col-span-2">
        Subject
        <input name="subject" required minLength={1} className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" />
      </label>
      <label className="text-xs text-neutral-500 sm:col-span-2">
        Description
        <textarea name="body" required minLength={1} rows={4} className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" placeholder="Describe what you need help with." />
      </label>
      <div className="sm:col-span-2">
        <Button type="submit" variant="primary" loading={pending} loadingLabel="Submitting…" disabled={noCategoriesConfigured}>
          Submit case
        </Button>
      </div>
      {noCategoriesConfigured ? (
        <p className="text-xs text-neutral-500 sm:col-span-2">No helpdesk categories are configured for your organization yet — ask a tenant admin to enable one from the internal ticket workspace.</p>
      ) : null}
      {state.error ? (
        <p role="alert" className="text-xs text-danger sm:col-span-2">
          {state.error}
        </p>
      ) : null}
    </form>
  );
}

export function HelpdeskPanel({
  tenantSlug,
  categories,
  tickets,
  createTicketAction,
}: {
  tenantSlug: string;
  categories: readonly HelpdeskTicketCategoryRow[];
  tickets: readonly HelpdeskTicketListRow[];
  createTicketAction: (prevState: HelpdeskActionState, formData: FormData) => Promise<HelpdeskActionState>;
}) {
  return (
    <div className="flex flex-col gap-4">
      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Your organization&apos;s support cases</h2>
        {tickets.length === 0 ? (
          <EmptyState title="No support cases yet" description="Cases your organization opens with CargoGrid support will appear here." />
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full border-collapse">
              <thead>
                <tr className="text-left text-xs font-medium text-neutral-500">
                  <th className="p-2">Case</th>
                  <th className="p-2">Subject</th>
                  <th className="p-2">Status</th>
                  <th className="p-2">Priority</th>
                  <th className="p-2">Severity</th>
                  <th className="p-2">Category</th>
                </tr>
              </thead>
              <tbody>
                {tickets.map((t) => (
                  <HelpdeskTicketRow key={t.id} tenantSlug={tenantSlug} ticket={t} />
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>

      <CreateHelpdeskTicketForm categories={categories} createTicketAction={createTicketAction} />
    </div>
  );
}
