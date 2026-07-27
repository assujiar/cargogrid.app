import type { ResourceAssignment } from "../../../../../../server/contracts/resource-assignment/resource-assignment.ts";

/** Ordered, oldest-first, full append-oriented assignment history (OPS-172, Prompt 172 §15/§25). Read-only -- every row is a real, preserved past outcome, never rewritten. */
export function ResourceAssignmentHistory({ history }: { history: readonly ResourceAssignment[] }) {
  if (history.length === 0) {
    return <p className="text-sm text-neutral-500">No resource assignments recorded yet.</p>;
  }

  return (
    <ol className="flex flex-col gap-2">
      {history.map((assignment) => (
        <li key={assignment.id} className="flex flex-col gap-0.5 border-l-2 border-neutral-200 pl-3 text-sm">
          <span className="font-medium text-neutral-900">
            {assignment.role}: {assignment.resourceSnapshot.name} ({assignment.resourceSnapshot.code}) — {assignment.status}
            {assignment.isCurrent ? " (current)" : ""}
          </span>
          <span className="text-xs text-neutral-500">{new Date(assignment.createdAt).toLocaleString()}</span>
          {assignment.reason ? <span className="text-xs text-neutral-600">Reason: {assignment.reason}</span> : null}
          {assignment.supersededById ? <span className="text-xs text-neutral-600">Superseded by a later assignment</span> : null}
        </li>
      ))}
    </ol>
  );
}
