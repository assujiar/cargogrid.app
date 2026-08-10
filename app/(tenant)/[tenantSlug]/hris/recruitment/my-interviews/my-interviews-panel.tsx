"use client";

import { useActionState } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import type { MyAssignedInterview } from "../../../../../../server/contracts/recruitment/recruitment.ts";
import type { MyInterviewsActionState } from "./actions.ts";

const INITIAL_STATE: MyInterviewsActionState = { error: null };

type Bound = (prevState: MyInterviewsActionState, formData: FormData) => Promise<MyInterviewsActionState>;

export function MyInterviewsPanel({ interviews, submitFeedbackAction }: { interviews: MyAssignedInterview[]; submitFeedbackAction: (interviewId: string) => Bound }) {
  return (
    <div className="flex flex-col gap-3">
      {interviews.map((iv) => (
        <div key={iv.interviewId} className="rounded-md border border-neutral-200 p-4">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm font-medium text-neutral-900">{iv.candidateFullName}</p>
              <p className="text-xs text-neutral-500">
                {iv.vacancyTitle} &middot; {new Date(iv.scheduledAt).toLocaleString()}
              </p>
            </div>
            <span className="rounded-full bg-neutral-100 px-2 py-0.5 text-xs">{iv.status}</span>
          </div>
          {iv.myFeedbackSubmitted ? (
            <p className="mt-2 text-xs text-success">You have submitted your feedback for this interview.</p>
          ) : iv.status === "scheduled" || iv.status === "completed" ? (
            <FeedbackForm action={submitFeedbackAction(iv.interviewId)} />
          ) : null}
        </div>
      ))}
    </div>
  );
}

function FeedbackForm({ action }: { action: Bound }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  return (
    <form action={formAction} className="mt-3 flex flex-wrap items-end gap-2" noValidate>
      <div className="flex flex-col gap-1">
        <label className="text-xs font-medium text-neutral-700">Rating (1-5)</label>
        <input name="rating" type="number" min="1" max="5" defaultValue={3} className="w-16 rounded-md border border-neutral-300 px-2 py-1 text-sm" />
      </div>
      <div className="flex flex-col gap-1">
        <label className="text-xs font-medium text-neutral-700">Recommendation</label>
        <select name="recommendation" className="rounded-md border border-neutral-300 px-2 py-1 text-sm">
          <option value="strong_yes">Strong yes</option>
          <option value="yes">Yes</option>
          <option value="no">No</option>
          <option value="strong_no">Strong no</option>
        </select>
      </div>
      <input name="notes" placeholder="Notes" className="rounded-md border border-neutral-300 px-2 py-1 text-sm" />
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Submitting…">
        Submit feedback
      </Button>
      {state.error ? (
        <p role="alert" className="w-full text-xs text-danger">
          {state.error}
        </p>
      ) : null}
    </form>
  );
}
