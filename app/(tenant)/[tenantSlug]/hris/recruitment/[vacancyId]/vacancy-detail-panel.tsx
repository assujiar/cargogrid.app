"use client";

import { useActionState, useState } from "react";
import Link from "next/link";
import { Button } from "../../../../../../components/ui/button.tsx";
import { Input } from "../../../../../../components/forms/input.tsx";
import { Select } from "../../../../../../components/forms/select.tsx";
import { FormField } from "../../../../../../components/forms/form-field.tsx";
import { ValidationMessage } from "../../../../../../components/forms/validation-message.tsx";
import { EmptyState } from "../../../../../../components/ui/empty-state.tsx";
import { RecruitmentExportForm, type RecruitmentExportActionState } from "../../../../../../components/domain/recruitment-export-form.tsx";
import type { JobVacancyDetail, ApplicationPipelineRow, ApplicationStage } from "../../../../../../server/contracts/recruitment/recruitment.ts";
import type { RecruitmentActionState } from "../actions.ts";

const INITIAL_STATE: RecruitmentActionState = { error: null };

const STAGE_LABEL: Record<ApplicationStage, string> = {
  new: "New",
  screening: "Screening",
  assessment: "Assessment",
  interview: "Interview",
  offer: "Offer",
  offer_accepted: "Offer accepted",
  rejected: "Rejected",
  withdrawn: "Withdrawn",
};

type BoundAction = (prevState: RecruitmentActionState, formData: FormData) => Promise<RecruitmentActionState>;

export function VacancyDetailPanel({
  tenantSlug,
  detail,
  applications,
  updateAction,
  publishAction,
  holdAction,
  reopenAction,
  closeAction,
  cancelAction,
  addCandidateAction,
  exportApplicationsAction,
}: {
  tenantSlug: string;
  detail: JobVacancyDetail;
  applications: ApplicationPipelineRow[];
  updateAction: BoundAction;
  publishAction: BoundAction;
  holdAction: BoundAction;
  reopenAction: BoundAction;
  closeAction: BoundAction;
  cancelAction: BoundAction;
  addCandidateAction: BoundAction;
  exportApplicationsAction: (prevState: RecruitmentExportActionState, formData: FormData) => Promise<RecruitmentExportActionState>;
}) {
  const { vacancy } = detail;
  const [publishState, publishFormAction, publishPending] = useActionState(publishAction, INITIAL_STATE);
  const [holdState, holdFormAction, holdPending] = useActionState(holdAction, INITIAL_STATE);
  const [reopenState, reopenFormAction, reopenPending] = useActionState(reopenAction, INITIAL_STATE);
  const [closeState, closeFormAction, closePending] = useActionState(closeAction, INITIAL_STATE);
  const [cancelState, cancelFormAction, cancelPending] = useActionState(cancelAction, INITIAL_STATE);
  const [addState, addFormAction, addPending] = useActionState(addCandidateAction, INITIAL_STATE);
  const [showAdd, setShowAdd] = useState(false);

  const lastAnyError = publishState.error ?? holdState.error ?? reopenState.error ?? closeState.error ?? cancelState.error;

  return (
    <div className="flex flex-col gap-4">
      <div>
        <h1 className="text-xl font-semibold text-neutral-900">{vacancy.title}</h1>
        <div className="mt-1 flex flex-wrap items-center gap-2 text-xs text-neutral-500">
          <span className="rounded-full bg-neutral-100 px-2 py-0.5 font-medium text-neutral-700">{vacancy.status.replace("_", " ")}</span>
          <span>{vacancy.employmentType.replace("_", " ")}</span>
          <span>{detail.currentOpenHeadcount} active applications</span>
          {detail.activePostingExpiresAt ? <span>Public link active until {new Date(detail.activePostingExpiresAt).toLocaleDateString()}</span> : null}
        </div>
      </div>

      {vacancy.description ? <p className="text-sm text-neutral-700">{vacancy.description}</p> : null}

      {lastAnyError ? <ValidationMessage>{lastAnyError}</ValidationMessage> : null}

      <div className="flex flex-wrap gap-2">
        {vacancy.status === "draft" ? (
          <>
            <form action={publishFormAction} className="flex items-center gap-2">
              <label className="sr-only" htmlFor="validityDays">
                Public link validity (days)
              </label>
              <Input id="validityDays" name="validityDays" type="number" min="1" defaultValue={30} className="w-20" invalid={Boolean(publishState.error)} />
              <Button type="submit" loading={publishPending} loadingLabel="Publishing…">
                Publish
              </Button>
            </form>
            <form action={cancelFormAction} className="flex items-center gap-2">
              <input type="hidden" name="reason" value="Cancelled before publishing" />
              <Button type="submit" variant="secondary" loading={cancelPending} loadingLabel="Cancelling…">
                Cancel draft
              </Button>
            </form>
          </>
        ) : null}
        {vacancy.status === "open" ? (
          <>
            <form action={holdFormAction} className="flex items-center gap-2">
              <input type="hidden" name="reason" value="Paused by recruiter" />
              <Button type="submit" variant="secondary" loading={holdPending} loadingLabel="Pausing…">
                Place on hold
              </Button>
            </form>
            <form action={closeFormAction} className="flex items-center gap-2">
              <input type="hidden" name="reason" value="Closed by recruiter" />
              <Button type="submit" variant="destructive" loading={closePending} loadingLabel="Closing…">
                Close vacancy
              </Button>
            </form>
          </>
        ) : null}
        {vacancy.status === "on_hold" ? (
          <>
            <form action={reopenFormAction}>
              <Button type="submit" loading={reopenPending} loadingLabel="Reopening…">
                Reopen
              </Button>
            </form>
            <form action={closeFormAction} className="flex items-center gap-2">
              <input type="hidden" name="reason" value="Closed by recruiter" />
              <Button type="submit" variant="destructive" loading={closePending} loadingLabel="Closing…">
                Close vacancy
              </Button>
            </form>
          </>
        ) : null}
      </div>

      <div className="flex items-center justify-between">
        <h2 className="text-sm font-semibold text-neutral-900">Pipeline</h2>
        {vacancy.status === "open" ? (
          <Button type="button" variant="secondary" onClick={() => setShowAdd((v) => !v)}>
            {showAdd ? "Cancel" : "Add candidate"}
          </Button>
        ) : null}
      </div>

      {showAdd ? (
        <form action={addFormAction} className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4" noValidate>
          <div className="flex gap-3">
            <div className="flex-1">
              <FormField id="fullName" label="Full name">
                <Input id="fullName" name="fullName" type="text" required invalid={Boolean(addState.error)} aria-describedby={addState.error ? "add-candidate-error" : undefined} />
              </FormField>
            </div>
            <div className="flex-1">
              <FormField id="email" label="Email">
                <Input id="email" name="email" type="email" required invalid={Boolean(addState.error)} aria-describedby={addState.error ? "add-candidate-error" : undefined} />
              </FormField>
            </div>
          </div>
          <div className="flex gap-3">
            <div className="flex-1">
              <FormField id="phone" label="Phone (optional)">
                <Input id="phone" name="phone" type="tel" invalid={Boolean(addState.error)} aria-describedby={addState.error ? "add-candidate-error" : undefined} />
              </FormField>
            </div>
            <div className="flex-1">
              <FormField id="source" label="Source">
                <Select id="source" name="source" invalid={Boolean(addState.error)} aria-describedby={addState.error ? "add-candidate-error" : undefined}>
                  <option value="staff_created">Staff-entered</option>
                  <option value="agency">Agency</option>
                  <option value="talent_pool">Talent pool</option>
                </Select>
              </FormField>
            </div>
          </div>
          {addState.error ? <ValidationMessage id="add-candidate-error">{addState.error}</ValidationMessage> : null}
          <Button type="submit" loading={addPending} loadingLabel="Adding…">
            Add and apply
          </Button>
        </form>
      ) : null}

      <RecruitmentExportForm label="Export applications" description="Downloads every application against this vacancy." action={exportApplicationsAction} />

      {applications.length === 0 ? (
        <EmptyState title="No applications yet" description={vacancy.status === "open" ? "Add a candidate above, or share the public application link once published." : "This vacancy has no applications."} />
      ) : (
        <div className="overflow-x-auto rounded-md border border-neutral-200">
          <table className="w-full text-left text-sm">
            <thead className="bg-neutral-50 text-xs uppercase text-neutral-500">
              <tr>
                <th scope="col" className="px-3 py-2">
                  Candidate
                </th>
                <th scope="col" className="px-3 py-2">
                  Stage
                </th>
                <th scope="col" className="px-3 py-2">
                  Source
                </th>
                <th scope="col" className="px-3 py-2">
                  Applied
                </th>
              </tr>
            </thead>
            <tbody>
              {applications.map((a) => (
                <tr key={a.id} className="border-t border-neutral-100 hover:bg-neutral-50">
                  <td className="px-3 py-2">
                    <Link href={`/${tenantSlug}/hris/recruitment/applications/${a.id}`} className="font-medium text-primary underline">
                      {a.candidateFullName}
                    </Link>
                  </td>
                  <td className="px-3 py-2">{STAGE_LABEL[a.stage]}</td>
                  <td className="px-3 py-2">{a.source.replace("_", " ")}</td>
                  <td className="px-3 py-2">{new Date(a.appliedAt).toLocaleDateString()}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
