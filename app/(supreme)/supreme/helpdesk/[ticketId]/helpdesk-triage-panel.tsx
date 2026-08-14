"use client";

import { useActionState } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
import { Banner } from "../../../../../components/ui/banner.tsx";
import { StatusBadge, type StatusTone } from "../../../../../components/ui/status-badge.tsx";
import type { SupremeHelpdeskActionState } from "../actions.ts";
import {
  HELPDESK_ENVIRONMENTS,
  HELPDESK_SEVERITIES,
  TICKET_PRIORITIES,
  type PlatformHelpdeskTicketDetail,
  type SupportQueueRow,
  type TicketCategoryRow,
  type TicketMessageRow,
  type TicketStatus,
} from "../../../../../server/contracts/ticketing/ticketing.ts";

const INITIAL_STATE: SupremeHelpdeskActionState = { error: null };

const STATUS_TONE: Record<TicketStatus, StatusTone> = {
  new: "info",
  open: "info",
  pending: "warning",
  on_hold: "warning",
  resolved: "success",
  closed: "neutral",
  cancelled: "neutral",
};

function nextStaffActions(status: TicketStatus): readonly { toStatus: TicketStatus; label: string; requiresReason: boolean }[] {
  const map: Record<TicketStatus, readonly { toStatus: TicketStatus; label: string; requiresReason: boolean }[]> = {
    new: [{ toStatus: "open", label: "Open", requiresReason: false }],
    open: [
      { toStatus: "pending", label: "Mark pending", requiresReason: false },
      { toStatus: "on_hold", label: "Put on hold", requiresReason: true },
      { toStatus: "resolved", label: "Resolve", requiresReason: true },
      { toStatus: "cancelled", label: "Cancel", requiresReason: true },
    ],
    pending: [
      { toStatus: "open", label: "Reopen", requiresReason: false },
      { toStatus: "resolved", label: "Resolve", requiresReason: true },
      { toStatus: "on_hold", label: "Put on hold", requiresReason: true },
      { toStatus: "cancelled", label: "Cancel", requiresReason: true },
    ],
    on_hold: [
      { toStatus: "open", label: "Resume", requiresReason: false },
      { toStatus: "cancelled", label: "Cancel", requiresReason: true },
    ],
    resolved: [{ toStatus: "closed", label: "Close", requiresReason: false }],
    closed: [{ toStatus: "open", label: "Reopen", requiresReason: true }],
    cancelled: [],
  };
  return map[status];
}

type BoundAction = (prevState: SupremeHelpdeskActionState, formData: FormData) => Promise<SupremeHelpdeskActionState>;

function MessageBubble({ message }: { message: TicketMessageRow }) {
  return (
    <li className={`flex flex-col gap-1 rounded-md border p-3 ${message.visibility === "internal" ? "border-warning/50 bg-warning/10" : "border-neutral-200"}`}>
      <div className="flex flex-wrap items-center gap-2 text-xs text-neutral-500">
        <span>{message.authorLabel ?? message.authorRole}</span>
        <StatusBadge tone={message.visibility === "internal" ? "warning" : "neutral"} label={message.visibility === "internal" ? "Platform-internal" : "Tenant-visible"} />
        <span>{new Date(message.createdAt).toLocaleString()}</span>
      </div>
      <p className="whitespace-pre-wrap text-sm text-neutral-900">{message.isRedacted ? "[redacted]" : message.body}</p>
    </li>
  );
}

function ReplyForm({ replyAction }: { replyAction: BoundAction }) {
  const [state, formAction, pending] = useActionState(replyAction, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
      <label className="text-xs text-neutral-500">
        Message
        <textarea name="body" required minLength={1} rows={3} className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" />
      </label>
      <label className="text-xs text-neutral-500">
        Visibility
        <select name="visibility" defaultValue="public" className="mt-1 w-full max-w-xs rounded border border-neutral-300 p-2 text-sm">
          <option value="public">Tenant-visible reply</option>
          <option value="internal">Platform-internal note</option>
        </select>
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

function AssignForm({ assignAction }: { assignAction: BoundAction }) {
  const [state, formAction, pending] = useActionState(assignAction, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-wrap items-end gap-2">
      <label className="text-xs text-neutral-500">
        Assign to (Supreme Admin auth user id, blank to unassign)
        <input name="assigneeAuthUserId" className="mt-1 w-72 rounded border border-neutral-300 p-1.5 text-sm" />
      </label>
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Assigning…">
        Assign
      </Button>
      {state.error ? (
        <p role="alert" className="w-full text-xs text-danger">
          {state.error}
        </p>
      ) : null}
    </form>
  );
}

function TransferForm({ queues, transferAction }: { queues: readonly SupportQueueRow[]; transferAction: BoundAction }) {
  const [state, formAction, pending] = useActionState(transferAction, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-wrap items-end gap-2">
      <label className="text-xs text-neutral-500">
        Support queue
        <select name="supportQueueId" required defaultValue="" className="mt-1 w-48 rounded border border-neutral-300 p-2 text-sm">
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
        Reason
        <input name="reason" required minLength={1} className="mt-1 w-56 rounded border border-neutral-300 p-1.5 text-sm" />
      </label>
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Transferring…">
        Transfer
      </Button>
      {state.error ? (
        <p role="alert" className="w-full text-xs text-danger">
          {state.error}
        </p>
      ) : null}
    </form>
  );
}

function ClassificationForm({ categories, classifyAction }: { categories: readonly TicketCategoryRow[]; classifyAction: BoundAction }) {
  const [state, formAction, pending] = useActionState(classifyAction, INITIAL_STATE);
  return (
    <form action={formAction} className="grid grid-cols-1 gap-2 sm:grid-cols-4">
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
        Severity
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
        Environment
        <select name="environment" defaultValue="" className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm">
          <option value="">Not specified</option>
          {HELPDESK_ENVIRONMENTS.map((e) => (
            <option key={e} value={e}>
              {e}
            </option>
          ))}
        </select>
      </label>
      <label className="text-xs text-neutral-500 sm:col-span-3">
        Product area
        <input name="productArea" className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" />
      </label>
      <div>
        <Button type="submit" variant="secondary" loading={pending} loadingLabel="Updating…">
          Reclassify
        </Button>
      </div>
      {state.error ? (
        <p role="alert" className="text-xs text-danger sm:col-span-4">
          {state.error}
        </p>
      ) : null}
    </form>
  );
}

function SupportGrantCorrelationForm({ detail, linkAction }: { detail: PlatformHelpdeskTicketDetail; linkAction: BoundAction }) {
  const [state, formAction, pending] = useActionState(linkAction, INITIAL_STATE);
  return (
    <div className="flex flex-col gap-2">
      <Banner variant="warning">
        This correlation is display/audit only. Linking a case reference here never creates, approves, starts, or extends privileged access to this tenant&apos;s business data — that always requires a separate, reasoned,
        time-bound, MFA-protected support access grant.
      </Banner>
      {detail.supportAccessCaseRef ? (
        <p className="text-xs text-neutral-700">
          Linked support-access case: <span className="font-mono">{detail.supportAccessCaseRef}</span> — grant status:{" "}
          <StatusBadge tone={detail.supportGrantStatus === "approved" ? "success" : detail.supportGrantStatus === "revoked" ? "danger" : "neutral"} label={detail.supportGrantStatus ?? "unknown"} />
          {detail.supportGrantExpiresAt ? ` · expires ${new Date(detail.supportGrantExpiresAt).toLocaleString()}` : ""}
          {detail.supportGrantRevokedAt ? ` · revoked ${new Date(detail.supportGrantRevokedAt).toLocaleString()}` : ""}
        </p>
      ) : (
        <p className="text-xs text-neutral-500">No support-access case is currently linked to this ticket.</p>
      )}
      <form action={formAction} className="flex flex-wrap items-end gap-2">
        <label className="text-xs text-neutral-500">
          Support-access case reference (blank to unlink)
          <input name="caseRef" defaultValue={detail.supportAccessCaseRef ?? ""} className="mt-1 w-56 rounded border border-neutral-300 p-1.5 text-sm" />
        </label>
        <Button type="submit" variant="secondary" loading={pending} loadingLabel="Saving…">
          Update correlation
        </Button>
        {state.error ? (
          <p role="alert" className="w-full text-xs text-danger">
            {state.error}
          </p>
        ) : null}
      </form>
    </div>
  );
}

export function HelpdeskTriagePanel({
  detail,
  messages,
  categories,
  queues,
  replyAction,
  transitionAction,
  assignAction,
  transferAction,
  classifyAction,
  linkGrantAction,
}: {
  detail: PlatformHelpdeskTicketDetail;
  messages: readonly TicketMessageRow[];
  categories: readonly TicketCategoryRow[];
  queues: readonly SupportQueueRow[];
  replyAction: BoundAction;
  transitionAction: (toStatus: TicketStatus) => BoundAction;
  assignAction: BoundAction;
  transferAction: BoundAction;
  classifyAction: BoundAction;
  linkGrantAction: BoundAction;
}) {
  const actions = nextStaffActions(detail.status);

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
            <dt className="font-medium">Tenant</dt>
            <dd>{detail.tenantName}</dd>
          </div>
          <div>
            <dt className="font-medium">Category</dt>
            <dd>{detail.categoryName}</dd>
          </div>
          <div>
            <dt className="font-medium">Priority / Severity</dt>
            <dd>
              {detail.priority} / {detail.severity ?? "—"}
            </dd>
          </div>
          <div>
            <dt className="font-medium">Environment</dt>
            <dd>{detail.environment ?? "—"}</dd>
          </div>
          <div>
            <dt className="font-medium">Support queue</dt>
            <dd>{detail.supportQueueCode ?? "unassigned"}</dd>
          </div>
          <div>
            <dt className="font-medium">Assignee</dt>
            <dd>{detail.assigneeEmail ?? "unassigned"}</dd>
          </div>
          <div>
            <dt className="font-medium">Tenant reference</dt>
            <dd>{detail.externalReference ?? "—"}</dd>
          </div>
          <div>
            <dt className="font-medium">Updated</dt>
            <dd>{new Date(detail.updatedAt).toLocaleString()}</dd>
          </div>
        </dl>
        {actions.length > 0 ? (
          <div className="flex flex-wrap gap-2">
            {actions.map((a) => (
              <TransitionForm key={a.toStatus} toStatus={a.toStatus} label={a.label} requiresReason={a.requiresReason} transitionAction={transitionAction} />
            ))}
          </div>
        ) : null}
      </header>

      <section className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Triage</h2>
        <TransferForm queues={queues} transferAction={transferAction} />
        <AssignForm assignAction={assignAction} />
        <ClassificationForm categories={categories} classifyAction={classifyAction} />
      </section>

      <section className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Support-access correlation</h2>
        <SupportGrantCorrelationForm detail={detail} linkAction={linkGrantAction} />
      </section>

      <section className="flex flex-col gap-3">
        <h2 className="text-sm font-semibold text-neutral-900">Conversation</h2>
        <ul className="flex flex-col gap-2">
          {messages.map((m) => (
            <MessageBubble key={m.id} message={m} />
          ))}
        </ul>
        {detail.status !== "cancelled" ? <ReplyForm replyAction={replyAction} /> : <p className="text-xs text-neutral-500">This case is cancelled and can no longer receive new messages.</p>}
      </section>
    </div>
  );
}
