"use client";

import { useActionState } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
import { StatusBadge, type StatusTone } from "../../../../../components/ui/status-badge.tsx";
import type { TicketActionState } from "../actions.ts";
import type { KbActionState } from "../../knowledge-base/actions.ts";
import type { KbTicketArticleLinkRow, KbTicketArticleLinkForRequesterRow } from "../../../../../server/contracts/knowledge-base/knowledge-base.ts";
import type {
  TicketDetail,
  TicketMessageRow,
  TicketWatcherRow,
  TicketEventRow,
  TicketQueueRow,
  TicketCategoryRow,
  TicketQueueMemberRow,
  TicketStatus,
  TicketSlaClockRow,
  TicketSlaStatusForRequesterRow,
  SlaPhaseStatus,
  TicketAssignmentCandidateRow,
  TicketAssignmentEventRow,
  TicketEscalationRow,
  TicketEscalationStatusForRequesterRow,
  TicketEscalationEventRow,
  TicketEscalationSuppressionRow,
} from "../../../../../server/contracts/ticketing/ticketing.ts";
import { TICKET_PRIORITIES, SLA_PAUSE_REASON_CODES } from "../../../../../server/contracts/ticketing/ticketing.ts";

const INITIAL_STATE: TicketActionState = { error: null };

const SLA_PHASE_TONE: Record<SlaPhaseStatus, StatusTone> = {
  pending: "info",
  met: "success",
  breached: "danger",
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
      <h3 className="text-sm font-semibold text-neutral-900">Manual assignment (TKT:Assign)</h3>
      <select name="assigneeEmployeeId" defaultValue={currentAssigneeId ?? ""} className="rounded border border-neutral-300 p-1.5 text-sm">
        <option value="">Unassigned</option>
        {queueMembers.map((m) => (
          <option key={m.employeeId} value={m.employeeId}>
            {m.employeeName}
          </option>
        ))}
      </select>
      <input name="reason" placeholder="Reason (optional)" className="rounded border border-neutral-300 p-1.5 text-sm" />
      <label className="flex items-center gap-2 text-xs text-neutral-600">
        <input type="checkbox" name="overrideWorkloadLimit" />
        Override this employee&apos;s workload cap, if one is configured
      </label>
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

// HRT-290 (CG-S12-HRT-018, section 15 "assignment drawer with explainable
// eligibility"): claim (self-service, any active queue member), accept/
// decline (assignee-only -- the RPC itself is the real gate; a non-assignee
// submitting either sees a clear insufficient_authority error rather than a
// hidden control, mirroring this file's own established "always rendered,
// RPC-enforced" pattern for the SLA/catalog admin forms below), auto-route
// (apply the published routing rule), and the live candidate/eligibility
// list. Rendered only for internal/customer tickets (queues/actions.ts binds
// nothing for a helpdesk ticket, and app.list_ticket_assignment_candidates
// itself refuses one -- decision 2, no eligibility model exists for
// helpdesk).
function AssignmentDrawer({
  currentAssigneeName,
  candidates,
  assignmentEvents,
  claimAction,
  acceptAssignmentAction,
  declineAssignmentAction,
  autoRouteAction,
}: {
  currentAssigneeName: string | null;
  candidates: readonly TicketAssignmentCandidateRow[];
  assignmentEvents: readonly TicketAssignmentEventRow[];
  claimAction: BoundAction;
  acceptAssignmentAction: BoundAction;
  declineAssignmentAction: BoundAction;
  autoRouteAction: BoundAction;
}) {
  const [claimState, claimFormAction, claimPending] = useActionState(claimAction, INITIAL_STATE);
  const [acceptState, acceptFormAction, acceptPending] = useActionState(acceptAssignmentAction, INITIAL_STATE);
  const [declineState, declineFormAction, declinePending] = useActionState(declineAssignmentAction, INITIAL_STATE);
  const [routeState, routeFormAction, routePending] = useActionState(autoRouteAction, INITIAL_STATE);

  return (
    <div className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
      <h3 className="text-sm font-semibold text-neutral-900">Claim / accept / decline / auto-route</h3>
      <div className="flex flex-wrap gap-2">
        <form action={claimFormAction}>
          <Button type="submit" variant="secondary" loading={claimPending} loadingLabel="Claiming…">
            Claim for myself
          </Button>
        </form>
        <form action={acceptFormAction}>
          <Button type="submit" variant="secondary" loading={acceptPending} loadingLabel="Confirming…" disabled={!currentAssigneeName}>
            Accept assignment
          </Button>
        </form>
        <form action={routeFormAction}>
          <Button type="submit" variant="secondary" loading={routePending} loadingLabel="Auto-routing…">
            Auto-route (apply routing rule)
          </Button>
        </form>
      </div>
      {claimState.error ? (
        <p role="alert" className="text-xs text-danger">
          {claimState.error}
        </p>
      ) : null}
      {acceptState.error ? (
        <p role="alert" className="text-xs text-danger">
          {acceptState.error}
        </p>
      ) : null}
      {routeState.error ? (
        <p role="alert" className="text-xs text-danger">
          {routeState.error}
        </p>
      ) : null}

      <form action={declineFormAction} className="flex flex-wrap items-center gap-2">
        <input name="reason" required placeholder="Decline reason (required)" className="min-w-[12rem] flex-1 rounded border border-neutral-300 p-1.5 text-sm" />
        <Button type="submit" variant="secondary" loading={declinePending} loadingLabel="Declining…" disabled={!currentAssigneeName}>
          Decline (return to backlog)
        </Button>
      </form>
      {declineState.error ? (
        <p role="alert" className="text-xs text-danger">
          {declineState.error}
        </p>
      ) : null}

      <div>
        <h4 className="text-xs font-semibold text-neutral-700">Eligible candidates (this queue)</h4>
        {candidates.length === 0 ? (
          <p className="text-xs text-neutral-500">No active queue members.</p>
        ) : (
          <table className="mt-1 w-full border-collapse text-xs">
            <thead>
              <tr className="text-left text-neutral-500">
                <th className="p-1">Employee</th>
                <th className="p-1">Eligible</th>
                <th className="p-1">Active tickets</th>
                <th className="p-1">Reason</th>
              </tr>
            </thead>
            <tbody>
              {candidates.map((c) => (
                <tr key={c.employeeId} className="border-t border-neutral-100">
                  <td className="p-1">{c.employeeName}</td>
                  <td className="p-1">
                    <StatusBadge tone={c.isEligible ? "success" : "neutral"} label={c.isEligible ? "Eligible" : "Not eligible"} />
                  </td>
                  <td className="p-1">{c.activeTicketCount}</td>
                  <td className="p-1 text-neutral-500">{c.ineligibleReason ?? "—"}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>

      <div>
        <h4 className="text-xs font-semibold text-neutral-700">Assignment history</h4>
        {assignmentEvents.length === 0 ? (
          <p className="text-xs text-neutral-500">No assignment events recorded yet.</p>
        ) : (
          <ul className="mt-1 flex flex-col gap-1 text-xs text-neutral-500">
            {assignmentEvents.map((e) => (
              <li key={e.id}>
                {new Date(e.occurredAt).toLocaleString()} — {e.eventType.replace(/_/g, " ")} ({e.source})
                {e.toAssigneeName ? ` → ${e.toAssigneeName}` : e.eventType === "unassign" || e.eventType === "decline" ? " → unassigned" : ""}
                {e.reason ? `: ${e.reason}` : ""}
              </li>
            ))}
          </ul>
        )}
      </div>
    </div>
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

// HRT-289 (CG-S12-HRT-017): SLA status/controls -- a distinct section, never
// woven into the lifecycle Status section above, matching the underlying
// RPCs' own "explicit, separate action" discipline (decision 1). Staff sees
// the full projection (calendar/policy identity implied by target minutes)
// plus pause/resume/start controls; a requester sees ONLY the narrower
// target/status projection with no controls at all -- the component never
// receives the staff-only fields for a requester viewer in the first place
// (page.tsx fetches the two projections from two DIFFERENT RPCs), so there
// is no client-side field to accidentally leak.
function SlaSection({
  isStaffViewer,
  slaClock,
  slaStatusForRequester,
  startSlaClockAction,
  pauseSlaClockAction,
  resumeSlaClockAction,
}: {
  isStaffViewer: boolean;
  slaClock: TicketSlaClockRow | null;
  slaStatusForRequester: TicketSlaStatusForRequesterRow | null;
  startSlaClockAction: BoundAction;
  pauseSlaClockAction: (expectedVersion: number) => BoundAction;
  resumeSlaClockAction: (expectedVersion: number) => BoundAction;
}) {
  const [startState, startFormAction, startPending] = useActionState(startSlaClockAction, INITIAL_STATE);

  if (!isStaffViewer) {
    if (!slaStatusForRequester) return null;
    return (
      <section aria-label="Service level" className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Service level</h2>
        <div className="flex flex-wrap items-center gap-2 text-xs">
          <span>Response:</span>
          <StatusBadge tone={SLA_PHASE_TONE[slaStatusForRequester.responseStatus]} label={slaStatusForRequester.responseStatus} />
          <span>Resolution:</span>
          <StatusBadge tone={SLA_PHASE_TONE[slaStatusForRequester.resolutionStatus]} label={slaStatusForRequester.resolutionStatus} />
        </div>
      </section>
    );
  }

  return (
    <section aria-label="Service level" className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
      <h2 className="text-sm font-semibold text-neutral-900">Service level (SLA)</h2>
      {!slaClock ? (
        <form action={startFormAction} className="flex flex-col gap-2">
          <p className="text-xs text-neutral-500">No SLA clock has been started for this ticket yet.</p>
          <div>
            <Button type="submit" variant="secondary" loading={startPending} loadingLabel="Starting…">
              Start SLA clock
            </Button>
          </div>
          {startState.error ? (
            <p role="alert" className="text-xs text-danger">
              {startState.error}
            </p>
          ) : null}
        </form>
      ) : (
        <>
          <div className="flex flex-wrap items-center gap-2 text-xs">
            <StatusBadge tone={slaClock.status === "running" ? "info" : slaClock.status === "paused" ? "warning" : "neutral"} label={slaClock.status.replace(/_/g, " ")} />
            <span>Response ({slaClock.responseTargetMinutes}m):</span>
            <StatusBadge tone={SLA_PHASE_TONE[slaClock.responseStatus]} label={slaClock.responseStatus} />
            <span>Resolution ({slaClock.resolutionTargetMinutes}m):</span>
            <StatusBadge tone={SLA_PHASE_TONE[slaClock.resolutionStatus]} label={slaClock.resolutionStatus} />
          </div>
          {slaClock.status === "running" ? (
            <PauseClockForm expectedVersion={slaClock.recordVersion} pauseSlaClockAction={pauseSlaClockAction} />
          ) : slaClock.status === "paused" ? (
            <ResumeClockForm expectedVersion={slaClock.recordVersion} resumeSlaClockAction={resumeSlaClockAction} />
          ) : null}
        </>
      )}
    </section>
  );
}

function PauseClockForm({ expectedVersion, pauseSlaClockAction }: { expectedVersion: number; pauseSlaClockAction: (expectedVersion: number) => BoundAction }) {
  const [state, formAction, pending] = useActionState(pauseSlaClockAction(expectedVersion), INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-wrap items-center gap-2">
      <select name="pauseReasonCode" required defaultValue="" className="rounded border border-neutral-300 p-1.5 text-xs">
        <option value="" disabled>
          Pause reason…
        </option>
        {SLA_PAUSE_REASON_CODES.map((code) => (
          <option key={code} value={code}>
            {code.replace(/_/g, " ")}
          </option>
        ))}
      </select>
      <input name="reason" placeholder="Note (optional)" className="min-w-[8rem] flex-1 rounded border border-neutral-300 p-1.5 text-xs" />
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Pausing…">
        Pause clock
      </Button>
      {state.error ? (
        <p role="alert" className="text-xs text-danger">
          {state.error}
        </p>
      ) : null}
    </form>
  );
}

function ResumeClockForm({ expectedVersion, resumeSlaClockAction }: { expectedVersion: number; resumeSlaClockAction: (expectedVersion: number) => BoundAction }) {
  const [state, formAction, pending] = useActionState(resumeSlaClockAction(expectedVersion), INITIAL_STATE);
  return (
    <form action={formAction} className="flex items-center gap-2">
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Resuming…">
        Resume clock
      </Button>
      {state.error ? (
        <p role="alert" className="text-xs text-danger">
          {state.error}
        </p>
      ) : null}
    </form>
  );
}

// HRT-289 (CG-S12-HRT-017): knowledge-article linking reuses the SAME
// public/internal visibility discipline app.ticket_messages already
// established (this capability's own decision 7) -- staff choose the
// visibility explicitly when linking; the requester's own list only ever
// includes public-visibility links, structurally (a distinct RPC/query, not
// a client-side filter).
function KnowledgeBaseSection({
  isStaffViewer,
  kbLinks,
  kbLinksForRequester,
  linkArticleAction,
  unlinkArticleAction,
}: {
  isStaffViewer: boolean;
  kbLinks: readonly KbTicketArticleLinkRow[];
  kbLinksForRequester: readonly KbTicketArticleLinkForRequesterRow[];
  linkArticleAction: BoundAction;
  unlinkArticleAction: (linkId: string, expectedVersion: number) => BoundAction;
}) {
  if (!isStaffViewer) {
    if (kbLinksForRequester.length === 0) return null;
    return (
      <section aria-label="Related knowledge articles" className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Related articles</h2>
        <ul className="flex flex-col gap-1 text-sm">
          {kbLinksForRequester.map((l) => (
            <li key={l.id}>
              <span className="font-medium text-neutral-900">{l.articleTitle}</span>
              {l.articleSummary ? <p className="text-xs text-neutral-500">{l.articleSummary}</p> : null}
            </li>
          ))}
        </ul>
      </section>
    );
  }

  return (
    <section aria-label="Related knowledge articles" className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
      <h2 className="text-sm font-semibold text-neutral-900">Knowledge base</h2>
      {kbLinks.length === 0 ? (
        <p className="text-xs text-neutral-500">No articles linked yet.</p>
      ) : (
        <ul className="flex flex-col gap-1">
          {kbLinks.map((l) => (
            <KbLinkRow key={l.id} link={l} unlinkArticleAction={unlinkArticleAction} />
          ))}
        </ul>
      )}
      <LinkArticleForm linkArticleAction={linkArticleAction} />
    </section>
  );
}

function KbLinkRow({ link, unlinkArticleAction }: { link: KbTicketArticleLinkRow; unlinkArticleAction: (linkId: string, expectedVersion: number) => BoundAction }) {
  const [state, formAction, pending] = useActionState(unlinkArticleAction(link.id, link.recordVersion), INITIAL_STATE);
  return (
    <li className="flex flex-wrap items-center gap-2 text-sm">
      <StatusBadge tone={link.visibility === "public" ? "info" : "warning"} label={link.visibility} />
      <span className="font-medium text-neutral-900">{link.articleTitle}</span>
      {link.note ? <span className="text-xs text-neutral-500">— {link.note}</span> : null}
      <form action={formAction}>
        <Button type="submit" variant="destructive" loading={pending} loadingLabel="Unlinking…">
          Unlink
        </Button>
      </form>
      {state.error ? (
        <p role="alert" className="w-full text-xs text-danger">
          {state.error}
        </p>
      ) : null}
    </li>
  );
}

function LinkArticleForm({ linkArticleAction }: { linkArticleAction: BoundAction }) {
  const [state, formAction, pending] = useActionState(linkArticleAction, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-wrap items-end gap-2 rounded bg-neutral-50 p-2">
      <label className="flex flex-col gap-1 text-xs text-neutral-600">
        Article id
        <input name="articleId" required placeholder="UUID" className="min-w-[16rem] rounded border border-neutral-300 p-1.5 text-xs" />
      </label>
      <label className="flex flex-col gap-1 text-xs text-neutral-600">
        Visibility
        <select name="visibility" defaultValue="internal" className="rounded border border-neutral-300 p-1.5 text-xs">
          <option value="internal">Internal (staff-only reference)</option>
          <option value="public">Public (visible to requester)</option>
        </select>
      </label>
      <input name="note" placeholder="Note (optional)" className="min-w-[10rem] flex-1 rounded border border-neutral-300 p-1.5 text-xs" />
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Linking…">
        Link article
      </Button>
      {state.error ? (
        <p role="alert" className="w-full text-xs text-danger">
          {state.error}
        </p>
      ) : null}
    </form>
  );
}

// HRT-291 (CG-S12-HRT-019): escalation timeline/level/acknowledge/suppress
// section. Staff sees the full projection (current level, trigger, target
// history, active suppressions) plus every control; a requester/customer
// sees ONLY a single is_escalated badge -- the component never receives the
// staff-only fields for a requester viewer in the first place (page.tsx
// fetches the two projections from two DIFFERENT RPCs, mirroring the SLA
// section's own established split), so there is no client-side field to
// accidentally leak. Bounded to internal/customer channels (decision 1) --
// rendered only when detail.channel !== "helpdesk", matching the assignment
// drawer's own established guard.
function EscalationSection({
  isStaffViewer,
  escalation,
  escalationStatusForRequester,
  escalationEvents,
  suppressions,
  queues,
  escalateAction,
  acknowledgeAction,
  resolveAction,
  suppressAction,
  revokeSuppressionAction,
}: {
  isStaffViewer: boolean;
  escalation: TicketEscalationRow | null;
  escalationStatusForRequester: TicketEscalationStatusForRequesterRow | null;
  escalationEvents: readonly TicketEscalationEventRow[];
  suppressions: readonly TicketEscalationSuppressionRow[];
  queues: readonly TicketQueueRow[];
  escalateAction: BoundAction;
  acknowledgeAction: (expectedVersion: number) => BoundAction;
  resolveAction: (expectedVersion: number) => BoundAction;
  suppressAction: BoundAction;
  revokeSuppressionAction: (suppressionId: string, expectedVersion: number) => BoundAction;
}) {
  const [escalateState, escalateFormAction, escalatePending] = useActionState(escalateAction, INITIAL_STATE);
  const [suppressState, suppressFormAction, suppressPending] = useActionState(suppressAction, INITIAL_STATE);

  if (!isStaffViewer) {
    if (!escalationStatusForRequester) return null;
    return (
      <section aria-label="Escalation status" className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Escalation status</h2>
        <StatusBadge
          tone={escalationStatusForRequester.isEscalated ? "warning" : "neutral"}
          label={escalationStatusForRequester.isEscalated ? "Escalated for priority handling" : "Normal handling"}
        />
      </section>
    );
  }

  const activeSuppression = suppressions.find((s) => s.revokedAt === null) ?? null;

  return (
    <section aria-label="Escalation" className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
      <h2 className="text-sm font-semibold text-neutral-900">Escalation</h2>

      {escalation ? (
        <div className="flex flex-wrap items-center gap-2 text-xs">
          <StatusBadge tone={escalation.status === "resolved" ? "neutral" : escalation.status === "acknowledged" ? "info" : "warning"} label={`Level ${escalation.currentLevel} — ${escalation.status.replace(/_/g, " ")}`} />
          <span>Trigger: {escalation.lastTriggerType.replace(/_/g, " ")}</span>
          <span>Last triggered: {new Date(escalation.lastTriggeredAt).toLocaleString()}</span>
          {escalation.acknowledgedAt ? <span>Acknowledged by {escalation.acknowledgedBy} at {new Date(escalation.acknowledgedAt).toLocaleString()}</span> : null}
        </div>
      ) : (
        <p className="text-xs text-neutral-500">This ticket has not been escalated.</p>
      )}

      {escalation && escalation.status !== "resolved" ? (
        <div className="flex flex-wrap gap-2">
          {escalation.status === "active" ? (
            <AcknowledgeButton expectedVersion={escalation.recordVersion} acknowledgeAction={acknowledgeAction} />
          ) : null}
          <ResolveEscalationForm expectedVersion={escalation.recordVersion} resolveAction={resolveAction} />
        </div>
      ) : null}

      <form action={escalateFormAction} className="flex flex-col gap-2 rounded bg-neutral-50 p-2">
        <h3 className="text-xs font-semibold text-neutral-700">Manually escalate</h3>
        <div className="flex flex-wrap items-end gap-2">
          <label className="flex flex-col gap-1 text-xs text-neutral-600">
            Target type
            <select name="targetType" required defaultValue="employee" className="rounded border border-neutral-300 p-1.5 text-xs">
              <option value="employee">Employee</option>
              <option value="queue">Queue</option>
            </select>
          </label>
          <label className="flex flex-col gap-1 text-xs text-neutral-600">
            Target queue (if target type = queue)
            <select name="targetQueueId" defaultValue="" className="rounded border border-neutral-300 p-1.5 text-xs">
              <option value="">Select…</option>
              {queues.map((q) => (
                <option key={q.id} value={q.id}>
                  {q.name}
                </option>
              ))}
            </select>
          </label>
          <label className="flex flex-col gap-1 text-xs text-neutral-600">
            Target employee id (if target type = employee)
            <input name="targetEmployeeId" placeholder="employee UUID" className="min-w-[14rem] rounded border border-neutral-300 p-1.5 text-xs" />
          </label>
          <label className="flex items-center gap-2 text-xs text-neutral-600">
            <input type="checkbox" name="reassign" />
            Also reassign to this employee
          </label>
        </div>
        <input name="reason" required placeholder="Reason (required)" className="rounded border border-neutral-300 p-1.5 text-xs" />
        <div>
          <Button type="submit" variant="secondary" loading={escalatePending} loadingLabel="Escalating…">
            Escalate
          </Button>
        </div>
        {escalateState.error ? (
          <p role="alert" className="text-xs text-danger">
            {escalateState.error}
          </p>
        ) : null}
      </form>

      <div className="flex flex-col gap-2">
        <h3 className="text-xs font-semibold text-neutral-700">Suppression</h3>
        {activeSuppression ? (
          <div className="flex flex-wrap items-center gap-2 text-xs">
            <StatusBadge tone="warning" label={`Suppressed until ${new Date(activeSuppression.expiresAt).toLocaleString()}`} />
            <span className="text-neutral-500">{activeSuppression.reason}</span>
            <RevokeSuppressionForm suppressionId={activeSuppression.id} expectedVersion={activeSuppression.recordVersion} revokeSuppressionAction={revokeSuppressionAction} />
          </div>
        ) : (
          <form action={suppressFormAction} className="flex flex-wrap items-end gap-2">
            <input name="reason" required placeholder="Suppression reason (required)" className="min-w-[12rem] flex-1 rounded border border-neutral-300 p-1.5 text-xs" />
            <label className="flex flex-col gap-1 text-xs text-neutral-600">
              Suppress until
              <input name="expiresAt" type="datetime-local" required className="rounded border border-neutral-300 p-1.5 text-xs" />
            </label>
            <Button type="submit" variant="secondary" loading={suppressPending} loadingLabel="Suppressing…">
              Suppress escalation
            </Button>
          </form>
        )}
        {suppressState.error ? (
          <p role="alert" className="text-xs text-danger">
            {suppressState.error}
          </p>
        ) : null}
      </div>

      <div>
        <h3 className="text-xs font-semibold text-neutral-700">Escalation history</h3>
        {escalationEvents.length === 0 ? (
          <p className="text-xs text-neutral-500">No escalation events recorded yet.</p>
        ) : (
          <ul className="mt-1 flex flex-col gap-1 text-xs text-neutral-500">
            {escalationEvents.map((e) => (
              <li key={e.id}>
                {new Date(e.occurredAt).toLocaleString()} — level {e.levelNumber} {e.eventType.replace(/_/g, " ")} ({e.triggerType.replace(/_/g, " ")})
                {e.targetEmployeeName ? ` → ${e.targetEmployeeName}` : e.targetQueueCode ? ` → ${e.targetQueueCode}` : ""}
                {e.reason ? `: ${e.reason}` : ""}
              </li>
            ))}
          </ul>
        )}
      </div>
    </section>
  );
}

function AcknowledgeButton({ expectedVersion, acknowledgeAction }: { expectedVersion: number; acknowledgeAction: (expectedVersion: number) => BoundAction }) {
  const [state, formAction, pending] = useActionState(acknowledgeAction(expectedVersion), INITIAL_STATE);
  return (
    <form action={formAction}>
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Acknowledging…">
        Acknowledge
      </Button>
      {state.error ? (
        <p role="alert" className="text-xs text-danger">
          {state.error}
        </p>
      ) : null}
    </form>
  );
}

function ResolveEscalationForm({ expectedVersion, resolveAction }: { expectedVersion: number; resolveAction: (expectedVersion: number) => BoundAction }) {
  const [state, formAction, pending] = useActionState(resolveAction(expectedVersion), INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-wrap items-center gap-2">
      <input name="reason" placeholder="Note (optional)" className="min-w-[8rem] rounded border border-neutral-300 p-1.5 text-xs" />
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Resolving…">
        Resolve / de-escalate
      </Button>
      {state.error ? (
        <p role="alert" className="text-xs text-danger">
          {state.error}
        </p>
      ) : null}
    </form>
  );
}

function RevokeSuppressionForm({ suppressionId, expectedVersion, revokeSuppressionAction }: { suppressionId: string; expectedVersion: number; revokeSuppressionAction: (suppressionId: string, expectedVersion: number) => BoundAction }) {
  const [state, formAction, pending] = useActionState(revokeSuppressionAction(suppressionId, expectedVersion), INITIAL_STATE);
  return (
    <form action={formAction} className="flex items-center gap-2">
      <Button type="submit" variant="destructive" loading={pending} loadingLabel="Revoking…">
        Revoke suppression
      </Button>
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
  slaClock,
  slaStatusForRequester,
  kbLinks,
  kbLinksForRequester,
  replyAction,
  redactAction,
  addWatcherAction,
  removeWatcherAction,
  assignAction,
  transferAction,
  classifyAction,
  transitionAction,
  startSlaClockAction,
  pauseSlaClockAction,
  resumeSlaClockAction,
  linkArticleAction,
  unlinkArticleAction,
  assignmentCandidates,
  assignmentEvents,
  claimAction,
  acceptAssignmentAction,
  declineAssignmentAction,
  autoRouteAction,
  escalation,
  escalationStatusForRequester,
  escalationEvents,
  suppressions,
  escalateAction,
  acknowledgeEscalationAction,
  resolveEscalationAction,
  suppressEscalationAction,
  revokeEscalationSuppressionAction,
}: {
  tenantSlug: string;
  detail: TicketDetail;
  messages: readonly TicketMessageRow[];
  watchers: readonly TicketWatcherRow[];
  events: readonly TicketEventRow[];
  queues: readonly TicketQueueRow[];
  categories: readonly TicketCategoryRow[];
  queueMembers: readonly TicketQueueMemberRow[];
  slaClock: TicketSlaClockRow | null;
  slaStatusForRequester: TicketSlaStatusForRequesterRow | null;
  kbLinks: readonly KbTicketArticleLinkRow[];
  kbLinksForRequester: readonly KbTicketArticleLinkForRequesterRow[];
  replyAction: BoundAction;
  redactAction: (messageId: string, expectedVersion: number) => BoundAction;
  addWatcherAction: BoundAction;
  removeWatcherAction: (watcherId: string, expectedVersion: number) => BoundAction;
  assignAction: BoundAction;
  transferAction: BoundAction;
  classifyAction: BoundAction;
  transitionAction: (toStatus: TicketStatus) => BoundAction;
  startSlaClockAction: BoundAction;
  pauseSlaClockAction: (expectedVersion: number) => BoundAction;
  resumeSlaClockAction: (expectedVersion: number) => BoundAction;
  linkArticleAction: BoundAction;
  unlinkArticleAction: (linkId: string, expectedVersion: number) => BoundAction;
  assignmentCandidates: readonly TicketAssignmentCandidateRow[];
  assignmentEvents: readonly TicketAssignmentEventRow[];
  claimAction: BoundAction;
  acceptAssignmentAction: BoundAction;
  declineAssignmentAction: BoundAction;
  autoRouteAction: BoundAction;
  escalation: TicketEscalationRow | null;
  escalationStatusForRequester: TicketEscalationStatusForRequesterRow | null;
  escalationEvents: readonly TicketEscalationEventRow[];
  suppressions: readonly TicketEscalationSuppressionRow[];
  escalateAction: BoundAction;
  acknowledgeEscalationAction: (expectedVersion: number) => BoundAction;
  resolveEscalationAction: (expectedVersion: number) => BoundAction;
  suppressEscalationAction: BoundAction;
  revokeEscalationSuppressionAction: (suppressionId: string, expectedVersion: number) => BoundAction;
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

      <SlaSection
        isStaffViewer={detail.isStaffViewer}
        slaClock={slaClock}
        slaStatusForRequester={slaStatusForRequester}
        startSlaClockAction={startSlaClockAction}
        pauseSlaClockAction={pauseSlaClockAction}
        resumeSlaClockAction={resumeSlaClockAction}
      />

      <KnowledgeBaseSection
        isStaffViewer={detail.isStaffViewer}
        kbLinks={kbLinks}
        kbLinksForRequester={kbLinksForRequester}
        linkArticleAction={linkArticleAction}
        unlinkArticleAction={unlinkArticleAction}
      />

      <WatcherList watchers={watchers} isStaffViewer={detail.isStaffViewer} isRequesterViewer={detail.isRequesterViewer} addWatcherAction={addWatcherAction} removeWatcherAction={removeWatcherAction} />

      {detail.isStaffViewer ? (
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
          <AssignForm queueMembers={queueMembers} currentAssigneeId={detail.assigneeEmployeeId} assignAction={assignAction} />
          <TransferForm queues={queues} currentQueueId={detail.queueId} transferAction={transferAction} />
          <ClassifyForm categories={categories} currentCategoryId={detail.categoryId} currentPriority={detail.priority} classifyAction={classifyAction} />
        </div>
      ) : null}

      {/* HRT-290 (CG-S12-HRT-018): claim/accept/decline/auto-route and the
          explainable-eligibility candidate/history views -- internal/customer
          channels only (decision 2), matching every new RPC's own reject of
          a helpdesk-channel ticket. */}
      {detail.isStaffViewer && detail.channel !== "helpdesk" ? (
        <AssignmentDrawer
          currentAssigneeName={detail.assigneeName}
          candidates={assignmentCandidates}
          assignmentEvents={assignmentEvents}
          claimAction={claimAction}
          acceptAssignmentAction={acceptAssignmentAction}
          declineAssignmentAction={declineAssignmentAction}
          autoRouteAction={autoRouteAction}
        />
      ) : null}

      {/* HRT-291 (CG-S12-HRT-019): escalation timeline/level/acknowledge/
          suppress -- internal/customer channels only (decision 1), matching
          every new RPC's own reject of a helpdesk-channel ticket. A
          requester/customer viewer still sees the minimal, structurally
          separate is_escalated badge (EscalationSection's own non-staff
          branch) -- rendered unconditionally on channel for that viewer,
          since app.get_ticket_escalation_status_for_requester itself is not
          channel-restricted the way the staff-side RPCs are. */}
      {detail.channel !== "helpdesk" ? (
        <EscalationSection
          isStaffViewer={detail.isStaffViewer}
          escalation={escalation}
          escalationStatusForRequester={escalationStatusForRequester}
          escalationEvents={escalationEvents}
          suppressions={suppressions}
          queues={queues}
          escalateAction={escalateAction}
          acknowledgeAction={acknowledgeEscalationAction}
          resolveAction={resolveEscalationAction}
          suppressAction={suppressEscalationAction}
          revokeSuppressionAction={revokeEscalationSuppressionAction}
        />
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
