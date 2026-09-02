"use client";

import { useActionState } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import { Input } from "../../../../../../components/forms/input.tsx";
import { Select } from "../../../../../../components/forms/select.tsx";
import { FormField } from "../../../../../../components/forms/form-field.tsx";
import { ValidationMessage } from "../../../../../../components/forms/validation-message.tsx";
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
            <FeedbackForm interviewId={iv.interviewId} action={submitFeedbackAction(iv.interviewId)} />
          ) : null}
        </div>
      ))}
    </div>
  );
}

function FeedbackForm({ interviewId, action }: { interviewId: string; action: Bound }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  const describedBy = state.error ? `feedback-${interviewId}-error` : undefined;
  return (
    <form action={formAction} className="mt-3 flex flex-wrap items-end gap-2" noValidate>
      <FormField id={`feedback-rating-${interviewId}`} label="Rating (1-5)">
        <Input id={`feedback-rating-${interviewId}`} name="rating" type="number" min="1" max="5" defaultValue={3} className="w-16" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <FormField id={`feedback-recommendation-${interviewId}`} label="Recommendation">
        <Select id={`feedback-recommendation-${interviewId}`} name="recommendation" invalid={Boolean(state.error)} aria-describedby={describedBy}>
          <option value="strong_yes">Strong yes</option>
          <option value="yes">Yes</option>
          <option value="no">No</option>
          <option value="strong_no">Strong no</option>
        </Select>
      </FormField>
      <label htmlFor={`feedback-notes-${interviewId}`} className="sr-only">
        Notes
      </label>
      <Input id={`feedback-notes-${interviewId}`} name="notes" placeholder="Notes" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Submitting…">
        Submit feedback
      </Button>
      {state.error ? (
        <div className="w-full">
          <ValidationMessage id={`feedback-${interviewId}-error`}>{state.error}</ValidationMessage>
        </div>
      ) : null}
    </form>
  );
}
