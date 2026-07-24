"use client";

import { useState, useTransition } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
import { logActivityAction, completeActivityAction, cancelActivityAction } from "./activity-actions.ts";
import type { Activity, ActivityType, RelatedType } from "../../../../../server/contracts/contact/contact.ts";

const ACTIVITY_TYPES: ActivityType[] = ["call", "email", "meeting", "visit", "follow_up", "task"];

/**
 * Unified activity timeline (COM-145, CG-S7-COM-004) -- shared by the Lead Detail
 * (COM-143) and Prospect Detail (COM-144) pages, since app.activities links
 * polymorphically to either. A Client Component so the log form and per-activity
 * complete/cancel actions render without a full page navigation.
 */
export function ActivityTimeline({
  tenantSlug,
  relatedType,
  relatedId,
  activities,
}: {
  tenantSlug: string;
  relatedType: RelatedType;
  relatedId: string;
  activities: readonly Activity[];
}) {
  const [type, setType] = useState<ActivityType>("call");
  const [subject, setSubject] = useState("");
  const [status, setStatus] = useState<"scheduled" | "completed">("completed");
  const [dueAt, setDueAt] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();

  return (
    <div className="flex flex-col gap-4 rounded-md border border-neutral-200 p-4">
      <h2 className="text-sm font-semibold text-neutral-900">Activity timeline</h2>

      {error ? (
        <p role="alert" className="text-sm text-danger">
          {error}
        </p>
      ) : null}

      <div className="flex flex-col gap-2">
        <div className="flex gap-2">
          <select value={type} onChange={(event) => setType(event.target.value as ActivityType)} className="rounded-md border border-neutral-300 px-2 py-1 text-sm">
            {ACTIVITY_TYPES.map((t) => (
              <option key={t} value={t}>
                {t}
              </option>
            ))}
          </select>
          <select value={status} onChange={(event) => setStatus(event.target.value as "scheduled" | "completed")} className="rounded-md border border-neutral-300 px-2 py-1 text-sm">
            <option value="completed">Completed now</option>
            <option value="scheduled">Scheduled</option>
          </select>
          {status === "scheduled" ? (
            <input type="datetime-local" value={dueAt} onChange={(event) => setDueAt(event.target.value)} className="rounded-md border border-neutral-300 px-2 py-1 text-sm" />
          ) : null}
        </div>
        <input
          type="text"
          placeholder="Subject"
          value={subject}
          onChange={(event) => setSubject(event.target.value)}
          className="rounded-md border border-neutral-300 px-3 py-2 text-sm"
        />
        <Button
          type="button"
          disabled={!subject.trim()}
          loading={pending}
          loadingLabel="Logging…"
          onClick={() =>
            startTransition(async () => {
              const result = await logActivityAction(tenantSlug, relatedType, relatedId, type, subject, status, status === "scheduled" && dueAt ? new Date(dueAt).toISOString() : null);
              setError(result.error);
              if (!result.error) {
                setSubject("");
              }
            })
          }
        >
          Log activity
        </Button>
      </div>

      {activities.length === 0 ? (
        <p className="text-sm text-neutral-600">No activities logged yet.</p>
      ) : (
        <ul className="flex flex-col gap-2">
          {activities.map((activity) => (
            <li key={activity.id} className="flex flex-col gap-1 border-b border-neutral-100 pb-2 text-sm">
              <div className="flex items-center justify-between">
                <span className="font-medium text-neutral-900">
                  {activity.type} — {activity.subject}
                </span>
                <span className="text-xs text-neutral-500">{activity.status}</span>
              </div>
              {activity.notes ? <p className="text-neutral-600">{activity.notes}</p> : null}
              {activity.outcome ? <p className="text-neutral-600">Outcome: {activity.outcome}</p> : null}
              {activity.status === "scheduled" ? (
                <div className="flex gap-2">
                  <Button
                    type="button"
                    variant="secondary"
                    loading={pending}
                    loadingLabel="Completing…"
                    onClick={() =>
                      startTransition(async () => {
                        const result = await completeActivityAction(tenantSlug, relatedType, relatedId, activity.id, activity.recordVersion, "");
                        setError(result.error);
                      })
                    }
                  >
                    Complete
                  </Button>
                  <Button
                    type="button"
                    variant="destructive"
                    loading={pending}
                    loadingLabel="Cancelling…"
                    onClick={() =>
                      startTransition(async () => {
                        const result = await cancelActivityAction(tenantSlug, relatedType, relatedId, activity.id, activity.recordVersion);
                        setError(result.error);
                      })
                    }
                  >
                    Cancel
                  </Button>
                </div>
              ) : null}
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
