"use client";

import { useActionState } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
import { StatusBadge, type StatusTone } from "../../../../../components/ui/status-badge.tsx";
import type { CustomerTicketActionState } from "../actions.ts";
import type { CustomerTicketDetail, CustomerTicketMessageRow, TicketStatus } from "../../../../../server/contracts/ticketing/ticketing.ts";

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

// Client-side convenience mirror of the subset of app.ticket_status_
// transitions that are requester_allowed (cancel, reopen) -- the SERVER
// (app.transition_ticket_status, via app._ticket_transition_authority) is
// the real, enforcing source of truth; this only decides which button to
// offer so a customer is not routinely shown a control that would just come
// back as insufficient_authority/invalid_transition.
function nextCustomerActions(status: TicketStatus): readonly { toStatus: TicketStatus; label: string; requiresReason: boolean }[] {
  if (status === "new" || status === "open" || status === "pending" || status === "on_hold") {
    return [{ toStatus: "cancelled", label: "Cancel ticket", requiresReason: true }];
  }
  if (status === "resolved" || status === "closed") {
    return [{ toStatus: "open", label: "Reopen ticket", requiresReason: true }];
  }
  return [];
}

type BoundAction = (prevState: CustomerTicketActionState, formData: FormData) => Promise<CustomerTicketActionState>;

function MessageBubble({ message }: { message: CustomerTicketMessageRow }) {
  return (
    <li className="flex flex-col gap-1 rounded-md border border-neutral-200 p-3">
      <div className="flex flex-wrap items-center gap-2 text-xs text-neutral-500">
        <span>{message.authorRole === "staff" ? message.authorDisplay : "You"}</span>
        <span>{new Date(message.createdAt).toLocaleString()}</span>
      </div>
      <p className="whitespace-pre-wrap text-sm text-neutral-900">{message.body}</p>
    </li>
  );
}

function ReplyForm({ replyAction }: { replyAction: BoundAction }) {
  const [state, formAction, pending] = useActionState(replyAction, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
      <label className="text-xs text-neutral-500">
        Add a reply
        <textarea name="body" required minLength={1} rows={3} className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" />
      </label>
      <div>
        <Button type="submit" variant="primary" loading={pending} loadingLabel="Sending…">
          Send
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

function TransitionForm({ toStatus, label, requiresReason, transitionAction }: { toStatus: TicketStatus; label: string; requiresReason: boolean; transitionAction: (toStatus: TicketStatus) => BoundAction }) {
  const [state, formAction, pending] = useActionState(transitionAction(toStatus), INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-wrap items-center gap-2">
      {requiresReason ? <input name="reason" required placeholder="Reason (required)" className="min-w-[10rem] flex-1 rounded border border-neutral-300 p-1.5 text-xs" /> : null}
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Updating…">
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

export function CustomerTicketDetailPanel({
  detail,
  messages,
  replyAction,
  transitionAction,
}: {
  detail: CustomerTicketDetail;
  messages: readonly CustomerTicketMessageRow[];
  replyAction: BoundAction;
  transitionAction: (toStatus: TicketStatus) => BoundAction;
}) {
  const actions = nextCustomerActions(detail.status);

  return (
    <div className="flex flex-col gap-4">
      <header className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
        <div className="flex flex-wrap items-center gap-2">
          <h1 className="text-lg font-semibold text-neutral-900">{detail.ticketNumber}</h1>
          <StatusBadge tone={STATUS_TONE[detail.status]} label={detail.status.replace(/_/g, " ")} />
        </div>
        <p className="text-sm text-neutral-700">{detail.subject}</p>
        <dl className="grid grid-cols-2 gap-2 text-xs text-neutral-500 sm:grid-cols-4">
          <div>
            <dt className="font-medium">Category</dt>
            <dd>{detail.categoryName}</dd>
          </div>
          <div>
            <dt className="font-medium">Priority</dt>
            <dd>{detail.priority}</dd>
          </div>
          <div>
            <dt className="font-medium">Account</dt>
            <dd>{detail.accountName}</dd>
          </div>
          <div>
            <dt className="font-medium">Updated</dt>
            <dd>{new Date(detail.updatedAt).toLocaleString()}</dd>
          </div>
        </dl>
        {detail.resolutionSummary ? (
          <p className="rounded bg-success/10 p-2 text-sm text-neutral-800">
            <span className="font-medium">Resolution: </span>
            {detail.resolutionSummary}
          </p>
        ) : null}
        {actions.length > 0 ? (
          <div className="flex flex-wrap gap-2">
            {actions.map((a) => (
              <TransitionForm key={a.toStatus} toStatus={a.toStatus} label={a.label} requiresReason={a.requiresReason} transitionAction={transitionAction} />
            ))}
          </div>
        ) : null}
      </header>

      <section className="flex flex-col gap-3">
        <h2 className="text-sm font-semibold text-neutral-900">Conversation</h2>
        <ul className="flex flex-col gap-2">
          {messages.map((m) => (
            <MessageBubble key={m.id} message={m} />
          ))}
        </ul>
        {detail.status !== "cancelled" ? <ReplyForm replyAction={replyAction} /> : <p className="text-xs text-neutral-500">This ticket is cancelled and can no longer receive new messages.</p>}
      </section>
    </div>
  );
}
