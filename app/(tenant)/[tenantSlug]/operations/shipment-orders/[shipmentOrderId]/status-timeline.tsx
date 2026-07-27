import type { ShipmentStatusTransition } from "../../../../../../server/contracts/shipment-lifecycle/shipment-lifecycle.ts";

/** Ordered, oldest-first status timeline (OPS-170, Prompt 170 §15). Read-only -- history is append-only and never rewritten by a normal user. */
export function StatusTimeline({ history }: { history: readonly ShipmentStatusTransition[] }) {
  if (history.length === 0) {
    return <p className="text-sm text-neutral-500">No transitions recorded yet.</p>;
  }

  return (
    <ol className="flex flex-col gap-2">
      {history.map((transition) => (
        <li key={transition.id} className="flex flex-col gap-0.5 border-l-2 border-neutral-200 pl-3 text-sm">
          <span className="font-medium text-neutral-900">
            {transition.fromStatus} → {transition.toStatus}
          </span>
          <span className="text-xs text-neutral-500">{new Date(transition.occurredAt).toLocaleString()}</span>
          {transition.reason ? <span className="text-xs text-neutral-600">Reason: {transition.reason}</span> : null}
          {transition.evidenceRef ? <span className="text-xs text-neutral-600">Evidence: {transition.evidenceRef}</span> : null}
        </li>
      ))}
    </ol>
  );
}
