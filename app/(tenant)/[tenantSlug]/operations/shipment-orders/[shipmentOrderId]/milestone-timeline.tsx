import type { MilestoneEvent } from "../../../../../../server/contracts/milestone-management/milestone-management.ts";

/** Ordered, oldest-first milestone event timeline (OPS-173, Prompt 173 §15). Read-only -- events are append-only; a correction appears as its own later row, never a rewrite of the one it corrects. */
export function MilestoneTimeline({ events }: { events: readonly MilestoneEvent[] }) {
  if (events.length === 0) {
    return <p className="text-sm text-neutral-500">No milestone events recorded yet.</p>;
  }

  return (
    <ol className="flex flex-col gap-2">
      {events.map((event) => (
        <li key={event.id} className="flex flex-col gap-0.5 border-l-2 border-neutral-200 pl-3 text-sm">
          <span className="font-medium text-neutral-900">{event.milestoneCode}</span>
          <span className="text-xs text-neutral-500">
            Occurred {new Date(event.eventTime).toLocaleString()} — received {new Date(event.receivedTime).toLocaleString()}
          </span>
          {event.location?.label ? <span className="text-xs text-neutral-600">Location: {event.location.label}</span> : null}
          <span className="text-xs text-neutral-500">Source: {event.source}</span>
          {event.correctsEventId ? <span className="text-xs text-neutral-600">Correction of a prior event{event.reason ? ` — ${event.reason}` : ""}</span> : null}
        </li>
      ))}
    </ol>
  );
}
