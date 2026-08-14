"use client";

import { useActionState } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
import { StatusBadge, type StatusTone } from "../../../../../components/ui/status-badge.tsx";
import type { TicketActionState } from "../actions.ts";
import type {
  TicketDetail,
  TicketMessageRow,
  TicketWatcherRow,
  TicketEventRow,
  TicketQueueRow,
  TicketCategoryRow,
  TicketQueueMemberRow,
  TicketStatus,
} from "../../../../../server/contracts/ticketing/ticketing.ts";
import { TICKET_PRIORITIES } from "../../../../../server/contracts/ticketing/ticketing.ts";

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

// Client-side convenience mirror of app.ticket_status_transitions -- the
// SERVER is the real, enforcing source of truth (app.transition_ticket_status
// rejects anything not in that table, regardless of what this list offers);
// this only narrows which buttons render so a viewer is not routinely shown
// a control that would just come back as invalid_transition.
const NEXT_STATUSES: Record<TicketStatus, readonly TicketStatus[]> = {
  new: ["open", "cancelled"],
  open: ["pending", "on_hold", "resolved", "cancelled"],
  pending: ["open", "resolved", "on_hold", "cancelled"],
  on_hold: ["open", "cancelled"],
  resolved: ["closed", "open"],
  closed: ["open"],
  cancelled: [],
};

const REASON_REQUIRED_TARGETS = new Set<TicketStatus>(["on_hold", "resolved", "cancelled", "open"]);

type BoundAction = (prevState: TicketActionState, formData: FormData) => Promise<TicketActionState>;

function MessageBubble({
  message,
  isStaffViewer,
  redactAction,
}: {
  message: TicketMessageRow;
  isStaffViewer: boolean;
  redactAction: (messageId: string, expectedVersion: number) => BoundAction;
}) {
  const [state, formAction, pending] = useActionState(redactAction(message.id, message.recordVersion), INITIAL_STATE);
  const isInternal = message.visibility === "internal";

  return (
    <li className={`flex flex-col gap-1 rounded-md border p-3 ${isInternal ? "border-warning/40 bg-warning/5" : "border-neutral-200"}`}>
      <div className="flex flex-wrap items-center gap-2 text-xs text-neutral-500">
        <StatusBadge tone={isInternal ? "warning" : "info"} label={isInternal ? "Internal note" : "Reply"} />
        <span>{message.authorRole === "staff" ? "Staff" : "Requester"}</span>
        <span>{new Date(message.createdAt).toLocaleString()}</span>
      </div>
      <p className="whitespace-pre-wrap text-sm text-neutral-900">{message.body}</p>
      {isStaffViewer && !message.isRedacted ? (
        <form action={formAction} className="flex items-center gap-2">
          <input name="reason" required placeholder="Redaction reason (required)" className="min-w-[10rem] flex-1 rounded border border-neutral-300 p-1.5 text-xs" />
          <Button type="submit" variant="destructive" loading={pending} loadingLabel="Redacting…">
            Redact
          </Button>
        </form>
      ) : null}
      {state.error ? (
        <p role="alert" className="text-xs text-danger">
          {state.error}
        </p>
      ) : null}
    </li>
  );
}

function ReplyForm({ isStaffViewer, replyAction }: { isStaffViewer: boolean; replyAction: BoundAction }) {
  const [state, formAction, pending] = useActionState(replyAction, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
      <h3 className="text-sm font-semibold text-neutral-900">Post a message</h3>
      <textarea name="body" required minLength={1} rows={3} className="w-full rounded border border-neutral-300 p-2 text-sm" placeholder="Write a reply…" />
      {isStaffViewer ? (
        <label className="flex items-center gap-2 text-xs text-neutral-600">
          <select name="visibility" defaultValue="public" className="rounded border border-neutral-300 p-1.5 text-xs">
            <option value="public">Reply (visible to requester)</option>
            <option value="internal">Internal note (staff only)</option>
          </select>
        </label>
      ) : (
        <input type="hidden" name="visibility" value="public" />
      )}
      <div>
        <Button type="submit" variant="primary" loading={pending} loadingLabel="Posting…">
          Post
        </Button>
      </div>
      {state.error ? (
        <p role="alert" className="text-xs text-danger">
          {state.error}
        </p>
      ) : null}
    </form>
  );
}

function StatusTransitionControls({ status, transitionAction }: { status: TicketStatus; transitionAction: (toStatus: TicketStatus) => BoundAction }) {
  const options = NEXT_STATUSES[status];
  if (options.length === 0) {
    return <p className="text-xs text-neutral-500">This ticket is in a terminal state ({status.replace(/_/g, " ")}) -- no further transition is available.</p>;
  }
  return (
    <div className="flex flex-col gap-2">
      {options.map((toStatus) => (
        <TransitionForm key={toStatus} toStatus={toStatus} requiresReason={REASON_REQUIRED_TARGETS.has(toStatus)} transitionAction={transitionAction} />
      ))}
    </div>
  );
}

function TransitionForm({ toStatus, requiresReason, transitionAction }: { toStatus: TicketStatus; requiresReason: boolean; transitionAction: (toStatus: TicketStatus) => BoundAction }) {
  const [state, formAction, pending] = useActionState(transitionAction(toStatus), INITIAL_STATE);
  const label = toStatus === "open" ? "Reopen / move to Open" : `Move to ${toStatus.replace(/_/g, " ")}`;
  return (
    <form action={formAction} className="flex flex-wrap items-center gap-2">
      {requiresReason ? <input name="reason" required placeholder="Reason (required)" className="min-w-[10rem] flex-1 rounded border border-neutral-300 p-1.5 text-xs" /> : null}
      <Button type="submit" variant={toStatus === "cancelled" ? "destructive" : "secondary"} loading={pending} loadingLabel="Updating…">
        {label}
      </Button>
      {state.error ? (
        <p role="alert" className="text-xs text-danger">
          {state.error}
        </p>
      ) : null}
    </form>
  );
}

function WatcherList({ watchers, isStaffViewer, isRequesterViewer, addWatcherAction, removeWatcherAction }: { watchers: readonly TicketWatcherRow[]; isStaffViewer: boolean; isRequesterViewer: boolean; addWatcherAction: BoundAction; removeWatcherAction: (watcherId: string, expectedVersion: number) => BoundAction }) {
  const [addState, addFormAction, addPending] = useActionState(addWatcherAction, INITIAL_STATE);
  const canManage = isStaffViewer || isRequesterViewer;
  return (
    <div className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
      <h3 className="text-sm font-semibold text-neutral-900">Watchers</h3>
      {watchers.length === 0 ? (
        <p className="text-xs text-neutral-500">No watchers.</p>
      ) : (
        <ul className="flex flex-col gap-1">
          {watchers.map((w) => (
            <WatcherRow key={w.id} watcher={w} canManage={canManage} removeWatcherAction={removeWatcherAction} />
          ))}
        </ul>
      )}
      {canManage ? (
        <form action={addFormAction} className="flex items-center gap-2">
          <input name="employeeId" required placeholder="Employee UUID" className="min-w-[10rem] flex-1 rounded border border-neutral-300 p-1.5 text-xs" />
          <Button type="submit" variant="secondary" loading={addPending} loadingLabel="Adding…">
            Add watcher
          </Button>
        </form>
      ) : null}
      {addState.error ? (
        <p role="alert" className="text-xs text-danger">
          {addState.error}
        </p>
      ) : null}
    </div>
  );
}

function WatcherRow({ watcher, canManage, removeWatcherAction }: { watcher: TicketWatcherRow; canManage: boolean; removeWatcherAction: (watcherId: string, expectedVersion: number) => BoundAction }) {
  const [state, formAction, pending] = useActionState(removeWatcherAction(watcher.id, watcher.recordVersion), INITIAL_STATE);
  return (
    <li className="flex items-center justify-between gap-2 text-sm">
      <span>{watcher.employeeName}</span>
      {canManage ? (
        <form action={formAction}>
          <Button type="submit" variant="destructive" loading={pending} loadingLabel="Removing…">
            Remove
          </Button>
        </form>
      ) : null}
      {state.error ? (
        <p role="alert" className="text-xs text-danger">
          {state.error}
        </p>
      ) : null}
    </li>
  );
}

function AssignForm({ queueMembers, currentAssigneeId, assignAction }: { queueMembers: readonly TicketQueueMemberRow[]; currentAssigneeId: string | null; assignAction: BoundAction }) {
  const [state, formAction, pending] = useActionState(assignAction, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
      <h3 className="text-sm font-semibold text-neutral-900">Assignment (TKT:Assign)</h3>
      <select name="assigneeEmployeeId" defaultValue={currentAssigneeId ?? ""} className="rounded border border-neutral-300 p-1.5 text-sm">
        <option value="">Unassigned</option>
        {queueMembers.map((m) => (
          <option key={m.employeeId} value={m.employeeId}>
            {m.employeeName}
          </option>
        ))}
      </select>
      <div>
        <Button type="submit" variant="secondary" loading={pending} loadingLabel="Assigning…">
          Update assignment
        </Button>
      </div>
      {state.error ? (
        <p role="alert" className="text-xs text-danger">
          {state.error}
        </p>
      ) : null}
    </form>
  );
}

function TransferForm({ queues, currentQueueId, transferAction }: { queues: readonly TicketQueueRow[]; currentQueueId: string; transferAction: BoundAction }) {
  const [state, formAction, pending] = useActionState(transferAction, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
      <h3 className="text-sm font-semibold text-neutral-900">Transfer to another queue</h3>
      <select name="newQueueId" defaultValue={currentQueueId} className="rounded border border-neutral-300 p-1.5 text-sm">
        {queues.map((q) => (
          <option key={q.id} value={q.id}>
            {q.name}
          </option>
        ))}
      </select>
      <input name="reason" required placeholder="Reason (required)" className="rounded border border-neutral-300 p-1.5 text-sm" />
      <div>
        <Button type="submit" variant="secondary" loading={pending} loadingLabel="Transferring…">
          Transfer
        </Button>
      </div>
      {state.error ? (
        <p role="alert" className="text-xs text-danger">
          {state.error}
        </p>
      ) : null}
    </form>
  );
}

function ClassifyForm({ categories, currentCategoryId, currentPriority, classifyAction }: { categories: readonly TicketCategoryRow[]; currentCategoryId: string; currentPriority: string; classifyAction: BoundAction }) {
  const [state, formAction, pending] = useActionState(classifyAction, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
      <h3 className="text-sm font-semibold text-neutral-900">Category / priority</h3>
      <select name="categoryId" defaultValue={currentCategoryId} className="rounded border border-neutral-300 p-1.5 text-sm">
        {categories.map((c) => (
          <option key={c.id} value={c.id}>
            {c.name}
          </option>
        ))}
      </select>
      <select name="priority" defaultValue={currentPriority} className="rounded border border-neutral-300 p-1.5 text-sm">
        {TICKET_PRIORITIES.map((p) => (
          <option key={p} value={p}>
            {p}
          </option>
        ))}
      </select>
      <div>
        <Button type="submit" variant="secondary" loading={pending} loadingLabel="Updating…">
          Update classification
        </Button>
      </div>
      {state.error ? (
        <p role="alert" className="text-xs text-danger">
          {state.error}
        </p>
      ) : null}
    </form>
  );
}

export function TicketDetailPanel({
  detail,
  messages,
  watchers,
  events,
  queues,
  categories,
  queueMembers,
  replyAction,
  redactAction,
  addWatcherAction,
  removeWatcherAction,
  assignAction,
  transferAction,
  classifyAction,
  transitionAction,
}: {
  tenantSlug: string;
  detail: TicketDetail;
  messages: readonly TicketMessageRow[];
  watchers: readonly TicketWatcherRow[];
  events: readonly TicketEventRow[];
  queues: readonly TicketQueueRow[];
  categories: readonly TicketCategoryRow[];
  queueMembers: readonly TicketQueueMemberRow[];
  replyAction: BoundAction;
  redactAction: (messageId: string, expectedVersion: number) => BoundAction;
  addWatcherAction: BoundAction;
  removeWatcherAction: (watcherId: string, expectedVersion: number) => BoundAction;
  assignAction: BoundAction;
  transferAction: BoundAction;
  classifyAction: BoundAction;
  transitionAction: (toStatus: TicketStatus) => BoundAction;
}) {
  return (
    <div className="flex flex-col gap-4">
      <section className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
        <div className="flex flex-wrap items-center gap-2">
          <span className="font-mono text-xs text-neutral-500">{detail.ticketNumber}</span>
          <StatusBadge tone={detail.channel === "customer" ? "info" : "neutral"} label={detail.channel === "customer" ? "Customer" : "Internal"} />
          <StatusBadge tone={STATUS_TONE[detail.status]} label={detail.status.replace(/_/g, " ")} />
          <span className="text-xs text-neutral-500">Priority: {detail.priority}</span>
          {detail.reopenCount > 0 ? <span className="text-xs text-neutral-500">Reopened {detail.reopenCount}×</span> : null}
        </div>
        <h1 className="text-lg font-semibold text-neutral-900">{detail.subject}</h1>
        <dl className="grid grid-cols-1 gap-1 text-xs text-neutral-500 sm:grid-cols-2">
          <div>
            <dt className="inline font-medium">Category:</dt> <dd className="inline">{detail.categoryName}</dd>
          </div>
          <div>
            <dt className="inline font-medium">Queue:</dt> <dd className="inline">{detail.queueName}</dd>
          </div>
          <div>
            <dt className="inline font-medium">{detail.channel === "customer" ? "Customer account:" : "Requester:"}</dt> <dd className="inline">{detail.requesterName ?? "—"}</dd>
          </div>
          <div>
            <dt className="inline font-medium">Assignee:</dt> <dd className="inline">{detail.assigneeName ?? "Unassigned"}</dd>
          </div>
        </dl>
        {detail.resolutionSummary ? (
          <p className="rounded bg-success/10 p-2 text-sm text-neutral-900">
            <strong>Resolution:</strong> {detail.resolutionSummary}
          </p>
        ) : null}
        {detail.cancelledReason ? (
          <p className="rounded bg-neutral-100 p-2 text-sm text-neutral-900">
            <strong>Cancelled:</strong> {detail.cancelledReason}
          </p>
        ) : null}
      </section>

      <section aria-label="Conversation" className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Conversation</h2>
        <ul className="flex flex-col gap-2">
          {messages.map((m) => (
            <MessageBubble key={m.id} message={m} isStaffViewer={detail.isStaffViewer} redactAction={redactAction} />
          ))}
        </ul>
        <ReplyForm isStaffViewer={detail.isStaffViewer} replyAction={replyAction} />
      </section>

      <section aria-label="Status" className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Status</h2>
        <StatusTransitionControls status={detail.status} transitionAction={transitionAction} />
      </section>

      <WatcherList watchers={watchers} isStaffViewer={detail.isStaffViewer} isRequesterViewer={detail.isRequesterViewer} addWatcherAction={addWatcherAction} removeWatcherAction={removeWatcherAction} />

      {detail.isStaffViewer ? (
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
          <AssignForm queueMembers={queueMembers} currentAssigneeId={detail.assigneeEmployeeId} assignAction={assignAction} />
          <TransferForm queues={queues} currentQueueId={detail.queueId} transferAction={transferAction} />
          <ClassifyForm categories={categories} currentCategoryId={detail.categoryId} currentPriority={detail.priority} classifyAction={classifyAction} />
        </div>
      ) : null}

      <section aria-label="History" className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">History</h2>
        {events.length === 0 ? (
          <p className="text-xs text-neutral-500">No events recorded.</p>
        ) : (
          <ul className="flex flex-col gap-1 text-xs text-neutral-500">
            {events.map((e) => (
              <li key={e.id}>
                {new Date(e.occurredAt).toLocaleString()} — {e.eventType.replace(/_/g, " ")}
                {e.fromValue || e.toValue ? ` (${e.fromValue ?? "—"} → ${e.toValue ?? "—"})` : ""}
                {e.reason ? `: ${e.reason}` : ""}
              </li>
            ))}
          </ul>
        )}
      </section>
    </div>
  );
}
