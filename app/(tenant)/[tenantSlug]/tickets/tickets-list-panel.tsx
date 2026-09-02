"use client";

import { useActionState } from "react";
import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { Button } from "../../../../components/ui/button.tsx";
import { ButtonGroup } from "../../../../components/ui/button-group.tsx";
import { Input } from "../../../../components/forms/input.tsx";
import { Select } from "../../../../components/forms/select.tsx";
import { Textarea } from "../../../../components/forms/textarea.tsx";
import { FormField } from "../../../../components/forms/form-field.tsx";
import { ValidationMessage } from "../../../../components/forms/validation-message.tsx";
import { StatusBadge, type StatusTone } from "../../../../components/ui/status-badge.tsx";
import { EmptyState } from "../../../../components/ui/empty-state.tsx";
import type { TicketActionState } from "./actions.ts";
import { TICKET_STATUSES, TICKET_PRIORITIES, type TicketStatus, type TicketQueueRow, type TicketCategoryRow, type TicketListRow, type MyTicketListRow, type TicketQueueWorkloadRow } from "../../../../server/contracts/ticketing/ticketing.ts";

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

function TicketRow({
  tenantSlug,
  id,
  ticketNumber,
  subject,
  status,
  priority,
  categoryCode,
  queueCode,
  isCustomerChannel,
  requesterName,
}: {
  tenantSlug: string;
  id: string;
  ticketNumber: string;
  subject: string;
  status: TicketStatus;
  priority: string;
  categoryCode: string;
  queueCode: string;
  isCustomerChannel: boolean;
  requesterName: string | null;
}) {
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
      <td className="p-2 text-xs text-neutral-500">
        <StatusBadge tone={isCustomerChannel ? "info" : "neutral"} label={isCustomerChannel ? "Customer" : "Internal"} /> {requesterName ?? "—"}
      </td>
    </tr>
  );
}

function CreateTicketForm({ categories, queues, createTicketAction }: { categories: readonly TicketCategoryRow[]; queues: readonly TicketQueueRow[]; createTicketAction: (prevState: TicketActionState, formData: FormData) => Promise<TicketActionState> }) {
  const [state, formAction, pending] = useActionState(createTicketAction, INITIAL_STATE);
  const describedBy = state.error ? "create-ticket-error" : undefined;
  return (
    <form action={formAction} className="grid grid-cols-1 gap-2 rounded-md border border-neutral-200 p-4 sm:grid-cols-2">
      <h2 className="text-sm font-semibold text-neutral-900 sm:col-span-2">New ticket</h2>
      <FormField id="new-ticket-category" label="Category">
        <Select id="new-ticket-category" name="categoryId" required defaultValue="" invalid={Boolean(state.error)} aria-describedby={describedBy}>
          <option value="" disabled>
            Select a category
          </option>
          {categories.map((c) => (
            <option key={c.id} value={c.id}>
              {c.name}
            </option>
          ))}
        </Select>
      </FormField>
      <FormField id="new-ticket-queue" label="Queue (optional -- falls back to the category's default queue)">
        <Select id="new-ticket-queue" name="queueId" defaultValue="" invalid={Boolean(state.error)} aria-describedby={describedBy}>
          <option value="">Use category default</option>
          {queues.map((q) => (
            <option key={q.id} value={q.id}>
              {q.name}
            </option>
          ))}
        </Select>
      </FormField>
      <FormField id="new-ticket-priority" label="Priority">
        <Select id="new-ticket-priority" name="priority" defaultValue="normal" invalid={Boolean(state.error)} aria-describedby={describedBy}>
          {TICKET_PRIORITIES.map((p) => (
            <option key={p} value={p}>
              {p}
            </option>
          ))}
        </Select>
      </FormField>
      <div className="sm:col-span-2">
        <FormField id="new-ticket-subject" label="Subject">
          <Input id="new-ticket-subject" name="subject" required minLength={1} invalid={Boolean(state.error)} aria-describedby={describedBy} />
        </FormField>
      </div>
      <div className="sm:col-span-2">
        <FormField id="new-ticket-body" label="Description">
          <Textarea
            id="new-ticket-body"
            name="body"
            required
            minLength={1}
            rows={4}
            placeholder="Describe the issue or request."
            invalid={Boolean(state.error)}
            aria-describedby={describedBy}
          />
        </FormField>
      </div>
      <div className="sm:col-span-2">
        <Button type="submit" variant="primary" loading={pending} loadingLabel="Submitting…">
          Submit ticket
        </Button>
      </div>
      {state.error ? (
        <div className="sm:col-span-2">
          <ValidationMessage id="create-ticket-error">{state.error}</ValidationMessage>
        </div>
      ) : null}
    </form>
  );
}

function CategoryCustomerVisibilityRow({ category, setCategoryCustomerVisibilityAction }: { category: TicketCategoryRow; setCategoryCustomerVisibilityAction: (categoryId: string, customerVisible: boolean) => (prevState: TicketActionState, formData: FormData) => Promise<TicketActionState> }) {
  const [state, formAction, pending] = useActionState(setCategoryCustomerVisibilityAction(category.id, !category.customerVisible), INITIAL_STATE);
  return (
    <li className="flex flex-wrap items-center justify-between gap-2 text-xs">
      <span>
        {category.name} ({category.code})
      </span>
      <div className="flex items-center gap-2">
        <StatusBadge tone={category.customerVisible ? "success" : "neutral"} label={category.customerVisible ? "Customer-visible" : "Internal only"} />
        <form action={formAction}>
          <Button type="submit" variant="secondary" loading={pending} loadingLabel="Updating…">
            {category.customerVisible ? "Hide from customers" : "Show to customers"}
          </Button>
        </form>
      </div>
      {state.error ? (
        <p role="alert" className="w-full text-xs text-danger">
          {state.error}
        </p>
      ) : null}
    </li>
  );
}

function AdminCatalogForms({
  queues,
  categories,
  orgUnits,
  createQueueAction,
  createCategoryAction,
  addQueueMemberAction,
  setCategoryCustomerVisibilityAction,
}: {
  queues: readonly TicketQueueRow[];
  categories: readonly TicketCategoryRow[];
  orgUnits: readonly { id: string; name: string; unitType: string }[];
  createQueueAction: (prevState: TicketActionState, formData: FormData) => Promise<TicketActionState>;
  createCategoryAction: (prevState: TicketActionState, formData: FormData) => Promise<TicketActionState>;
  addQueueMemberAction: (prevState: TicketActionState, formData: FormData) => Promise<TicketActionState>;
  setCategoryCustomerVisibilityAction: (categoryId: string, customerVisible: boolean) => (prevState: TicketActionState, formData: FormData) => Promise<TicketActionState>;
}) {
  const [queueState, queueFormAction, queuePending] = useActionState(createQueueAction, INITIAL_STATE);
  const [categoryState, categoryFormAction, categoryPending] = useActionState(createCategoryAction, INITIAL_STATE);
  const [memberState, memberFormAction, memberPending] = useActionState(addQueueMemberAction, INITIAL_STATE);
  const queueDescribedBy = queueState.error ? "create-queue-error" : undefined;
  const categoryDescribedBy = categoryState.error ? "create-category-error" : undefined;
  const memberDescribedBy = memberState.error ? "add-queue-member-error" : undefined;

  return (
    <details className="rounded-md border border-neutral-200 p-4">
      <summary className="cursor-pointer text-sm font-semibold text-neutral-900">Queue and category administration (TKT:Edit)</summary>
      <div className="mt-4 flex flex-col gap-4">
        <form action={queueFormAction} className="grid grid-cols-1 gap-2 sm:grid-cols-2">
          <h3 className="text-xs font-semibold text-neutral-700 sm:col-span-2">New queue</h3>
          <FormField id="new-queue-org-unit" label="Department">
            <Select id="new-queue-org-unit" name="orgUnitId" required defaultValue="" invalid={Boolean(queueState.error)} aria-describedby={queueDescribedBy}>
              <option value="" disabled>
                Select a department
              </option>
              {orgUnits.map((o) => (
                <option key={o.id} value={o.id}>
                  {o.name}
                </option>
              ))}
            </Select>
          </FormField>
          <FormField id="new-queue-code" label="Code">
            <Input id="new-queue-code" name="code" required minLength={1} invalid={Boolean(queueState.error)} aria-describedby={queueDescribedBy} />
          </FormField>
          <div className="sm:col-span-2">
            <FormField id="new-queue-name" label="Name">
              <Input id="new-queue-name" name="name" required minLength={1} invalid={Boolean(queueState.error)} aria-describedby={queueDescribedBy} />
            </FormField>
          </div>
          <div className="sm:col-span-2">
            <FormField id="new-queue-description" label="Description">
              <Input id="new-queue-description" name="description" invalid={Boolean(queueState.error)} aria-describedby={queueDescribedBy} />
            </FormField>
          </div>
          <div className="sm:col-span-2">
            <Button type="submit" variant="secondary" loading={queuePending} loadingLabel="Creating…">
              Create queue
            </Button>
          </div>
          {queueState.error ? (
            <div className="sm:col-span-2">
              <ValidationMessage id="create-queue-error">{queueState.error}</ValidationMessage>
            </div>
          ) : null}
        </form>

        <form action={categoryFormAction} className="grid grid-cols-1 gap-2 sm:grid-cols-2">
          <h3 className="text-xs font-semibold text-neutral-700 sm:col-span-2">New category</h3>
          <FormField id="new-category-code" label="Code">
            <Input id="new-category-code" name="code" required minLength={1} invalid={Boolean(categoryState.error)} aria-describedby={categoryDescribedBy} />
          </FormField>
          <FormField id="new-category-name" label="Name">
            <Input id="new-category-name" name="name" required minLength={1} invalid={Boolean(categoryState.error)} aria-describedby={categoryDescribedBy} />
          </FormField>
          <div className="sm:col-span-2">
            <FormField id="new-category-default-queue" label="Default queue">
              <Select id="new-category-default-queue" name="defaultQueueId" defaultValue="" invalid={Boolean(categoryState.error)} aria-describedby={categoryDescribedBy}>
                <option value="">No default</option>
                {queues.map((q) => (
                  <option key={q.id} value={q.id}>
                    {q.name}
                  </option>
                ))}
              </Select>
            </FormField>
          </div>
          <div className="sm:col-span-2">
            <Button type="submit" variant="secondary" loading={categoryPending} loadingLabel="Creating…">
              Create category
            </Button>
          </div>
          {categoryState.error ? (
            <div className="sm:col-span-2">
              <ValidationMessage id="create-category-error">{categoryState.error}</ValidationMessage>
            </div>
          ) : null}
        </form>

        <form action={memberFormAction} className="grid grid-cols-1 gap-2 sm:grid-cols-2">
          <h3 className="text-xs font-semibold text-neutral-700 sm:col-span-2">Staff a queue</h3>
          <FormField id="queue-member-queue" label="Queue">
            <Select id="queue-member-queue" name="queueId" required defaultValue="" invalid={Boolean(memberState.error)} aria-describedby={memberDescribedBy}>
              <option value="" disabled>
                Select a queue
              </option>
              {queues.map((q) => (
                <option key={q.id} value={q.id}>
                  {q.name}
                </option>
              ))}
            </Select>
          </FormField>
          <FormField id="queue-member-employee" label="Employee (master record id)">
            <Input id="queue-member-employee" name="employeeId" required placeholder="employee UUID" invalid={Boolean(memberState.error)} aria-describedby={memberDescribedBy} />
          </FormField>
          <div className="sm:col-span-2">
            <Button type="submit" variant="secondary" loading={memberPending} loadingLabel="Adding…">
              Add queue member
            </Button>
          </div>
          {memberState.error ? (
            <div className="sm:col-span-2">
              <ValidationMessage id="add-queue-member-error">{memberState.error}</ValidationMessage>
            </div>
          ) : null}
        </form>

        <div className="flex flex-col gap-2">
          <h3 className="text-xs font-semibold text-neutral-700">Customer visibility (HRT-287) -- which categories a Layer 4 customer may select when raising a ticket</h3>
          {categories.length === 0 ? (
            <p className="text-xs text-neutral-500">No categories yet.</p>
          ) : (
            <ul className="flex flex-col gap-1">
              {categories.map((c) => (
                <CategoryCustomerVisibilityRow key={c.id} category={c} setCategoryCustomerVisibilityAction={setCategoryCustomerVisibilityAction} />
              ))}
            </ul>
          )}
        </div>
      </div>
    </details>
  );
}

// HRT-290 (CG-S12-HRT-018, section 17 "workload indicators"): a compact,
// read-only per-queue workload table -- only queues the caller can actually
// view workload for appear here at all (page.tsx already filtered out the
// rest, so an absent queue here means "not authorized to view", never a
// silently-empty one presented as zero).
function QueueWorkloadPanel({ queues, workloadByQueue }: { queues: readonly TicketQueueRow[]; workloadByQueue: Record<string, readonly TicketQueueWorkloadRow[]> }) {
  const visibleQueues = queues.filter((q) => workloadByQueue[q.id] !== undefined);
  if (visibleQueues.length === 0) return null;

  return (
    <details className="rounded-md border border-neutral-200 p-4">
      <summary className="cursor-pointer text-sm font-semibold text-neutral-900">Queue workload</summary>
      <div className="mt-4 flex flex-col gap-4">
        {visibleQueues.map((q) => {
          const rows = workloadByQueue[q.id] ?? [];
          return (
            <div key={q.id}>
              <h3 className="text-xs font-semibold text-neutral-700">{q.name}</h3>
              {rows.length === 0 ? (
                <p className="text-xs text-neutral-500">No active queue members.</p>
              ) : (
                <table className="mt-1 w-full border-collapse text-xs">
                  <thead>
                    <tr className="text-left text-neutral-500">
                      <th className="p-1">Employee</th>
                      <th className="p-1">Active tickets</th>
                      <th className="p-1">Eligible</th>
                    </tr>
                  </thead>
                  <tbody>
                    {rows.map((r) => (
                      <tr key={r.employeeId} className="border-t border-neutral-100">
                        <td className="p-1">{r.employeeName}</td>
                        <td className="p-1">{r.activeTicketCount}</td>
                        <td className="p-1">
                          <StatusBadge tone={r.isEligible ? "success" : "neutral"} label={r.isEligible ? "Eligible" : "Not eligible"} />
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              )}
            </div>
          );
        })}
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
  workloadByQueue,
  showQueueView,
  statusFilter,
  createTicketAction,
  createQueueAction,
  createCategoryAction,
  addQueueMemberAction,
  setCategoryCustomerVisibilityAction,
}: {
  tenantSlug: string;
  queues: readonly TicketQueueRow[];
  categories: readonly TicketCategoryRow[];
  tickets: readonly TicketListRow[];
  myTickets: readonly MyTicketListRow[];
  orgUnits: readonly { id: string; name: string; unitType: string }[];
  workloadByQueue: Record<string, readonly TicketQueueWorkloadRow[]>;
  showQueueView: boolean;
  statusFilter: TicketStatus | null;
  createTicketAction: (prevState: TicketActionState, formData: FormData) => Promise<TicketActionState>;
  createQueueAction: (prevState: TicketActionState, formData: FormData) => Promise<TicketActionState>;
  createCategoryAction: (prevState: TicketActionState, formData: FormData) => Promise<TicketActionState>;
  addQueueMemberAction: (prevState: TicketActionState, formData: FormData) => Promise<TicketActionState>;
  setCategoryCustomerVisibilityAction: (categoryId: string, customerVisible: boolean) => (prevState: TicketActionState, formData: FormData) => Promise<TicketActionState>;
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
          {/* ISS-2026-246: the shared `ButtonGroup` primitive replaces this hand-rolled wrapper.
              Both buttons keep their exact variant, `onClick` and `aria-pressed`; the only
              attribute that changes is the wrapper's role, deliberately. `role="tablist"` was
              wrong here and had been since it was written: ARIA requires a tablist's children to
              be `role="tab"` controlling `role="tabpanel"` regions, and these are plain toggle
              buttons that re-run a server query via the URL -- there is no tab or panel anywhere.
              `ButtonGroup`'s `role="group"` is the accurate semantic, and it carries the same
              "Ticket views" accessible name the tablist did. */}
          <ButtonGroup label="Ticket views">
            <Button type="button" variant={showQueueView ? "secondary" : "primary"} onClick={() => applyFilter("", statusFilter ?? "")} aria-pressed={!showQueueView}>
              My Tickets
            </Button>
            <Button type="button" variant={showQueueView ? "primary" : "secondary"} onClick={() => applyFilter("queue", statusFilter ?? "")} aria-pressed={showQueueView}>
              Queue
            </Button>
          </ButtonGroup>
          <FormField id="ticket-status" label="Status">
            <Select id="ticket-status" defaultValue={statusFilter ?? ""} onChange={(event) => applyFilter(showQueueView ? "queue" : "", event.currentTarget.value)}>
              <option value="">All statuses</option>
              {TICKET_STATUSES.map((s) => (
                <option key={s} value={s}>
                  {s.replace(/_/g, " ")}
                </option>
              ))}
            </Select>
          </FormField>
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
                  {showQueueView ? <th className="p-2">Channel / requester</th> : null}
                </tr>
              </thead>
              <tbody>
                {showQueueView
                  ? tickets.map((t) => (
                      <TicketRow
                        key={t.id}
                        tenantSlug={tenantSlug}
                        id={t.id}
                        ticketNumber={t.ticketNumber}
                        subject={t.subject}
                        status={t.status}
                        priority={t.priority}
                        categoryCode={t.categoryCode}
                        queueCode={t.queueCode}
                        isCustomerChannel={t.requesterCustomerAccountId !== null}
                        requesterName={t.requesterName}
                      />
                    ))
                  : myTickets.map((t) => (
                      <tr key={t.id} className="border-t border-neutral-100">
                        <td className="p-2 text-sm">
                          <Link href={`/${tenantSlug}/tickets/${t.id}`} className="text-primary underline">
                            {t.ticketNumber}
                          </Link>
                        </td>
                        <td className="p-2 text-sm">{t.subject}</td>
                        <td className="p-2 text-sm">
                          <StatusBadge tone={STATUS_TONE[t.status]} label={t.status.replace(/_/g, " ")} />
                        </td>
                        <td className="p-2 text-sm">{t.priority}</td>
                        <td className="p-2 text-xs text-neutral-500">{t.categoryCode}</td>
                        <td className="p-2 text-xs text-neutral-500">{t.queueCode}</td>
                      </tr>
                    ))}
              </tbody>
            </table>
          </div>
        )}
      </section>

      <CreateTicketForm categories={categories} queues={queues} createTicketAction={createTicketAction} />

      <QueueWorkloadPanel queues={queues} workloadByQueue={workloadByQueue} />

      <AdminCatalogForms
        queues={queues}
        categories={categories}
        orgUnits={orgUnits}
        createQueueAction={createQueueAction}
        createCategoryAction={createCategoryAction}
        addQueueMemberAction={addQueueMemberAction}
        setCategoryCustomerVisibilityAction={setCategoryCustomerVisibilityAction}
      />
    </div>
  );
}
