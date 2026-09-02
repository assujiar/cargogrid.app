"use client";

import { useActionState, useState } from "react";
import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { Button } from "../../../../../components/ui/button.tsx";
import { Input } from "../../../../../components/forms/input.tsx";
import { Select } from "../../../../../components/forms/select.tsx";
import { Textarea } from "../../../../../components/forms/textarea.tsx";
import { FormField } from "../../../../../components/forms/form-field.tsx";
import { ValidationMessage } from "../../../../../components/forms/validation-message.tsx";
import { EmptyState } from "../../../../../components/ui/empty-state.tsx";
import { RecruitmentExportForm, type RecruitmentExportActionState } from "../../../../../components/domain/recruitment-export-form.tsx";
import type { JobVacancy, VacancyStatus } from "../../../../../server/contracts/recruitment/recruitment.ts";
import type { PositionListRow } from "../../../../../server/contracts/position/position.ts";
import type { RecruitmentActionState } from "./actions.ts";

const STATUS_TONE: Record<VacancyStatus, string> = {
  draft: "bg-neutral-100 text-neutral-700",
  open: "bg-success/10 text-success",
  on_hold: "bg-warning/10 text-warning",
  closed: "bg-neutral-200 text-neutral-600",
  cancelled: "bg-danger/10 text-danger",
};

const INITIAL_STATE: RecruitmentActionState = { error: null };

export function RecruitmentPanel({
  tenantSlug,
  vacancies,
  positions,
  statusFilter,
  search,
  createVacancyAction,
  exportAction,
}: {
  tenantSlug: string;
  vacancies: JobVacancy[];
  positions: PositionListRow[];
  statusFilter: VacancyStatus | null;
  search: string;
  createVacancyAction: (positionId: string) => (prevState: RecruitmentActionState, formData: FormData) => Promise<RecruitmentActionState>;
  exportAction: (prevState: RecruitmentExportActionState, formData: FormData) => Promise<RecruitmentExportActionState>;
}) {
  const router = useRouter();
  const searchParams = useSearchParams();
  const [showCreate, setShowCreate] = useState(false);
  const [positionId, setPositionId] = useState(positions[0]?.id ?? "");
  const boundCreate = createVacancyAction(positionId);
  const [createState, createFormAction, createPending] = useActionState(boundCreate, INITIAL_STATE);

  function applyFilter(next: { status?: string; q?: string }) {
    const params = new URLSearchParams(searchParams.toString());
    if (next.status !== undefined) {
      if (next.status) params.set("status", next.status);
      else params.delete("status");
    }
    if (next.q !== undefined) {
      if (next.q) params.set("q", next.q);
      else params.delete("q");
    }
    params.delete("after");
    router.push(`/${tenantSlug}/hris/recruitment?${params.toString()}`);
  }

  return (
    <div className="flex flex-col gap-4">
      <div className="flex flex-wrap items-center gap-2">
        <Input
          type="search"
          defaultValue={search}
          placeholder="Search vacancy title…"
          aria-label="Search vacancies"
          onKeyDown={(e) => {
            if (e.key === "Enter") applyFilter({ q: (e.target as HTMLInputElement).value });
          }}
        />
        <Select aria-label="Filter by status" value={statusFilter ?? ""} onChange={(e) => applyFilter({ status: e.target.value })} className="w-auto">
          <option value="">All statuses</option>
          <option value="draft">Draft</option>
          <option value="open">Open</option>
          <option value="on_hold">On hold</option>
          <option value="closed">Closed</option>
          <option value="cancelled">Cancelled</option>
        </Select>
        <div className="ml-auto">
          <Button type="button" variant="secondary" onClick={() => setShowCreate((v) => !v)} disabled={positions.length === 0}>
            {showCreate ? "Cancel" : "New vacancy"}
          </Button>
        </div>
      </div>

      <RecruitmentExportForm label="Export vacancies" description="Downloads the vacancy list, respecting the status filter above." action={exportAction} />

      {positions.length === 0 ? (
        <p className="text-xs text-neutral-500">No active positions exist yet -- create one under Positions &amp; grades before opening a vacancy.</p>
      ) : null}

      {showCreate ? (
        <form action={createFormAction} className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4" noValidate>
          <FormField id="positionId" label="Position">
            <Select id="positionId" name="positionId" value={positionId} onChange={(e) => setPositionId(e.target.value)} invalid={Boolean(createState.error)} aria-describedby={createState.error ? "create-vacancy-error" : undefined}>
              {positions.map((p) => (
                <option key={p.id} value={p.id}>
                  {p.title} ({p.code})
                </option>
              ))}
            </Select>
          </FormField>
          <FormField id="title" label="Vacancy title">
            <Input id="title" name="title" type="text" required invalid={Boolean(createState.error)} aria-describedby={createState.error ? "create-vacancy-error" : undefined} />
          </FormField>
          <div className="flex gap-3">
            <div className="flex-1">
              <FormField id="employmentType" label="Employment type">
                <Select id="employmentType" name="employmentType" invalid={Boolean(createState.error)} aria-describedby={createState.error ? "create-vacancy-error" : undefined}>
                  <option value="full_time">Full time</option>
                  <option value="part_time">Part time</option>
                  <option value="contract">Contract</option>
                  <option value="internship">Internship</option>
                  <option value="temporary">Temporary</option>
                </Select>
              </FormField>
            </div>
            <div className="w-28">
              <FormField id="headcount" label="Headcount">
                <Input id="headcount" name="headcount" type="number" min="1" defaultValue={1} invalid={Boolean(createState.error)} aria-describedby={createState.error ? "create-vacancy-error" : undefined} />
              </FormField>
            </div>
          </div>
          <FormField id="description" label="Description">
            <Textarea id="description" name="description" rows={3} invalid={Boolean(createState.error)} aria-describedby={createState.error ? "create-vacancy-error" : undefined} />
          </FormField>
          <FormField id="requirements" label="Requirements">
            <Textarea id="requirements" name="requirements" rows={3} invalid={Boolean(createState.error)} aria-describedby={createState.error ? "create-vacancy-error" : undefined} />
          </FormField>
          {createState.error ? <ValidationMessage id="create-vacancy-error">{createState.error}</ValidationMessage> : null}
          <Button type="submit" loading={createPending} loadingLabel="Creating…">
            Create draft
          </Button>
        </form>
      ) : null}

      {vacancies.length === 0 ? (
        <EmptyState title="No vacancies yet" description="Create a draft vacancy above to start building a pipeline." />
      ) : (
        <div className="overflow-x-auto rounded-md border border-neutral-200">
          <table className="w-full text-left text-sm">
            <thead className="bg-neutral-50 text-xs uppercase text-neutral-500">
              <tr>
                <th scope="col" className="px-3 py-2">
                  Title
                </th>
                <th scope="col" className="px-3 py-2">
                  Employment type
                </th>
                <th scope="col" className="px-3 py-2">
                  Headcount
                </th>
                <th scope="col" className="px-3 py-2">
                  Status
                </th>
              </tr>
            </thead>
            <tbody>
              {vacancies.map((v) => (
                <tr key={v.id} className="border-t border-neutral-100 hover:bg-neutral-50">
                  <td className="px-3 py-2">
                    <Link href={`/${tenantSlug}/hris/recruitment/${v.id}`} className="font-medium text-primary underline">
                      {v.title}
                    </Link>
                  </td>
                  <td className="px-3 py-2">{v.employmentType.replace("_", " ")}</td>
                  <td className="px-3 py-2">{v.headcount}</td>
                  <td className="px-3 py-2">
                    <span className={`rounded-full px-2 py-0.5 text-xs font-medium ${STATUS_TONE[v.status]}`}>{v.status.replace("_", " ")}</span>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
