"use client";

import { useActionState } from "react";
import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { Button } from "../../../../components/ui/button.tsx";
import { StatusBadge, type StatusTone } from "../../../../components/ui/status-badge.tsx";
import { EmptyState } from "../../../../components/ui/empty-state.tsx";
import type { TicketActionState } from "./actions.ts";
import { TICKET_STATUSES, TICKET_PRIORITIES, type TicketStatus, type TicketQueueRow, type TicketCategoryRow, type TicketListRow, type MyTicketListRow } from "../../../../server/contracts/ticketing/ticketing.ts";

const INITIAL_STATE: TicketActionState = { error: null };

const STATUS_TONE: Record<TicketStatus, StatusTone> = {
  new: "info",
  open: "info",
  pending: "warning",
  on_hold: "warning",
  resolved: "success",
  closed: "neutral",
  cancelled: "neutral",
};

function TicketRow({ tenantSlug, id, ticketNumber, subject, status, priority, categoryCode, queueCode }: { tenantSlug: string; id: string; ticketNumber: string; subject: string; status: TicketStatus; priority: string; categoryCode: string; queueCode: string }) {
  return (
    <tr className="border-t border-neutral-100">
      <td className="p-2 text-sm">
        <Link href={`/${tenantSlug}/tickets/${id}`} className="text-primary underline">
          {ticketNumber}
        </Link>
      </td>
      <td className="p-2 text-sm">{subject}</td>
      <td className="p-2 text-sm">
        <StatusBadge tone={STATUS_TONE[status]} label={status.replace(/_/g, " ")} />
      </td>
      <td className="p-2 text-sm">{priority}</td>
      <td className="p-2 text-xs text-neutral-500">{categoryCode}</td>
      <td className="p-2 text-xs text-neutral-500">{queueCode}</td>
    </tr>
  );
}

function CreateTicketForm({ categories, queues, createTicketAction }: { categories: readonly TicketCategoryRow[]; queues: readonly TicketQueueRow[]; createTicketAction: (prevState: TicketActionState, formData: FormData) => Promise<TicketActionState> }) {
  const [state, formAction, pending] = useActionState(createTicketAction, INITIAL_STATE);
  return (
    <form action={formAction} className="grid grid-cols-1 gap-2 rounded-md border border-neutral-200 p-4 sm:grid-cols-2">
      <h2 className="text-sm font-semibold text-neutral-900 sm:col-span-2">New ticket</h2>
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
        Queue (optional -- falls back to the category&apos;s default queue)
        <select name="queueId" defaultValue="" className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm">
          <option value="">Use category default</option>
          {queues.map((q) => (
            <option key={q.id} value={q.id}>
              {q.name}
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
        <textarea name="body" required minLength={1} rows={4} className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" placeholder="Describe the issue or request." />
      </label>
      <div className="sm:col-span-2">
        <Button type="submit" variant="primary" loading={pending} loadingLabel="Submitting…">
          Submit ticket
        </Button>
      </div>
      {state.error ? (
        <p role="alert" className="text-xs text-danger sm:col-span-2">
          {state.error}
        </p>
      ) : null}
    </form>
  );
}

function AdminCatalogForms({
  queues,
  orgUnits,
  createQueueAction,
  createCategoryAction,
  addQueueMemberAction,
}: {
  queues: readonly TicketQueueRow[];
  orgUnits: readonly { id: string; name: string; unitType: string }[];
  createQueueAction: (prevState: TicketActionState, formData: FormData) => Promise<TicketActionState>;
  createCategoryAction: (prevState: TicketActionState, formData: FormData) => Promise<TicketActionState>;
  addQueueMemberAction: (prevState: TicketActionState, formData: FormData) => Promise<TicketActionState>;
}) {
  const [queueState, queueFormAction, queuePending] = useActionState(createQueueAction, INITIAL_STATE);
  const [categoryState, categoryFormAction, categoryPending] = useActionState(createCategoryAction, INITIAL_STATE);
  const [memberState, memberFormAction, memberPending] = useActionState(addQueueMemberAction, INITIAL_STATE);

  return (
    <details className="rounded-md border border-neutral-200 p-4">
      <summary className="cursor-pointer text-sm font-semibold text-neutral-900">Queue and category administration (TKT:Edit)</summary>
      <div className="mt-4 flex flex-col gap-4">
        <form action={queueFormAction} className="grid grid-cols-1 gap-2 sm:grid-cols-2">
          <h3 className="text-xs font-semibold text-neutral-700 sm:col-span-2">New queue</h3>
          <label className="text-xs text-neutral-500">
            Department
            <select name="orgUnitId" required defaultValue="" className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm">
              <option value="" disabled>
                Select a department
              </option>
              {orgUnits.map((o) => (
                <option key={o.id} value={o.id}>
                  {o.name}
                </option>
              ))}
            </select>
          </label>
          <label className="text-xs text-neutral-500">
            Code
            <input name="code" required minLength={1} className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" />
          </label>
          <label className="text-xs text-neutral-500 sm:col-span-2">
            Name
            <input name="name" required minLength={1} className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" />
          </label>
          <label className="text-xs text-neutral-500 sm:col-span-2">
            Description
            <input name="description" className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" />
          </label>
          <div className="sm:col-span-2">
            <Button type="submit" variant="secondary" loading={queuePending} loadingLabel="Creating…">
              Create queue
            </Button>
          </div>
          {queueState.error ? (
            <p role="alert" className="text-xs text-danger sm:col-span-2">
              {queueState.error}
            </p>
          ) : null}
        </form>

        <form action={categoryFormAction} className="grid grid-cols-1 gap-2 sm:grid-cols-2">
          <h3 className="text-xs font-semibold text-neutral-700 sm:col-span-2">New category</h3>
          <label className="text-xs text-neutral-500">
            Code
            <input name="code" required minLength={1} className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" />
          </label>
          <label className="text-xs text-neutral-500">
            Name
            <input name="name" required minLength={1} className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" />
          </label>
          <label className="text-xs text-neutral-500 sm:col-span-2">
            Default queue
            <select name="defaultQueueId" defaultValue="" className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm">
              <option value="">No default</option>
              {queues.map((q) => (
                <option key={q.id} value={q.id}>
                  {q.name}
                </option>
              ))}
            </select>
          </label>
          <div className="sm:col-span-2">
            <Button type="submit" variant="secondary" loading={categoryPending} loadingLabel="Creating…">
              Create category
            </Button>
          </div>
          {categoryState.error ? (
            <p role="alert" className="text-xs text-danger sm:col-span-2">
              {categoryState.error}
            </p>
          ) : null}
        </form>

        <form action={memberFormAction} className="grid grid-cols-1 gap-2 sm:grid-cols-2">
          <h3 className="text-xs font-semibold text-neutral-700 sm:col-span-2">Staff a queue</h3>
          <label className="text-xs text-neutral-500">
            Queue
            <select name="queueId" required defaultValue="" className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm">
              <option value="" disabled>
                Select a queue
              </option>
              {queues.map((q) => (
                <option key={q.id} value={q.id}>
                  {q.name}
                </option>
              ))}
            </select>
          </label>
          <label className="text-xs text-neutral-500">
            Employee (master record id)
            <input name="employeeId" required className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" placeholder="employee UUID" />
          </label>
          <div className="sm:col-span-2">
            <Button type="submit" variant="secondary" loading={memberPending} loadingLabel="Adding…">
              Add queue member
            </Button>
          </div>
          {memberState.error ? (
            <p role="alert" className="text-xs text-danger sm:col-span-2">
              {memberState.error}
            </p>
          ) : null}
        </form>
      </div>
    </details>
  );
}

export function TicketsListPanel({
  tenantSlug,
  queues,
  categories,
  tickets,
  myTickets,
  orgUnits,
  showQueueView,
  statusFilter,
  createTicketAction,
  createQueueAction,
  createCategoryAction,
  addQueueMemberAction,
}: {
  tenantSlug: string;
  queues: readonly TicketQueueRow[];
  categories: readonly TicketCategoryRow[];
  tickets: readonly TicketListRow[];
  myTickets: readonly MyTicketListRow[];
  orgUnits: readonly { id: string; name: string; unitType: string }[];
  showQueueView: boolean;
  statusFilter: TicketStatus | null;
  createTicketAction: (prevState: TicketActionState, formData: FormData) => Promise<TicketActionState>;
  createQueueAction: (prevState: TicketActionState, formData: FormData) => Promise<TicketActionState>;
  createCategoryAction: (prevState: TicketActionState, formData: FormData) => Promise<TicketActionState>;
  addQueueMemberAction: (prevState: TicketActionState, formData: FormData) => Promise<TicketActionState>;
}) {
  const router = useRouter();
  const searchParams = useSearchParams();

  function applyFilter(nextView: string, nextStatus: string) {
    const next = new URLSearchParams(searchParams.toString());
    if (nextView) next.set("view", nextView);
    else next.delete("view");
    if (nextStatus) next.set("status", nextStatus);
    else next.delete("status");
    router.push(`/${tenantSlug}/tickets?${next.toString()}`);
  }

  const rows = showQueueView ? tickets : myTickets;

  return (
    <div className="flex flex-col gap-4">
      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        <div className="flex flex-wrap items-end gap-3">
          <div className="flex gap-1" role="tablist" aria-label="Ticket views">
            <Button type="button" variant={showQueueView ? "secondary" : "primary"} onClick={() => applyFilter("", statusFilter ?? "")} aria-pressed={!showQueueView}>
              My Tickets
            </Button>
            <Button type="button" variant={showQueueView ? "primary" : "secondary"} onClick={() => applyFilter("queue", statusFilter ?? "")} aria-pressed={showQueueView}>
              Queue
            </Button>
          </div>
          <div className="flex flex-col gap-1">
            <label htmlFor="ticket-status" className="text-xs font-medium text-neutral-600">
              Status
            </label>
            <select id="ticket-status" defaultValue={statusFilter ?? ""} className="rounded-md border border-neutral-300 px-3 py-1.5 text-sm" onChange={(event) => applyFilter(showQueueView ? "queue" : "", event.currentTarget.value)}>
              <option value="">All statuses</option>
              {TICKET_STATUSES.map((s) => (
                <option key={s} value={s}>
                  {s.replace(/_/g, " ")}
                </option>
              ))}
            </select>
          </div>
        </div>

        {rows.length === 0 ? (
          <EmptyState title="No tickets" description={showQueueView ? "No tickets are visible to you in this queue view yet." : "You have not filed or been added to any ticket yet."} />
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
                  <th className="p-2">Queue</th>
                </tr>
              </thead>
              <tbody>
                {rows.map((t) => (
                  <TicketRow key={t.id} tenantSlug={tenantSlug} id={t.id} ticketNumber={t.ticketNumber} subject={t.subject} status={t.status} priority={t.priority} categoryCode={t.categoryCode} queueCode={t.queueCode} />
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>

      <CreateTicketForm categories={categories} queues={queues} createTicketAction={createTicketAction} />

      <AdminCatalogForms queues={queues} orgUnits={orgUnits} createQueueAction={createQueueAction} createCategoryAction={createCategoryAction} addQueueMemberAction={addQueueMemberAction} />
    </div>
  );
}
