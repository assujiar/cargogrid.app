"use client";

import { useActionState, useState } from "react";
import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { Button } from "../../../../../components/ui/button.tsx";
import { EmptyState } from "../../../../../components/ui/empty-state.tsx";
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
}: {
  tenantSlug: string;
  vacancies: JobVacancy[];
  positions: PositionListRow[];
  statusFilter: VacancyStatus | null;
  search: string;
  createVacancyAction: (positionId: string) => (prevState: RecruitmentActionState, formData: FormData) => Promise<RecruitmentActionState>;
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
        <input
          type="search"
          defaultValue={search}
          placeholder="Search vacancy title…"
          aria-label="Search vacancies"
          onKeyDown={(e) => {
            if (e.key === "Enter") applyFilter({ q: (e.target as HTMLInputElement).value });
          }}
          className="rounded-md border border-neutral-300 px-3 py-2 text-sm"
        />
        <select aria-label="Filter by status" value={statusFilter ?? ""} onChange={(e) => applyFilter({ status: e.target.value })} className="rounded-md border border-neutral-300 px-3 py-2 text-sm">
          <option value="">All statuses</option>
          <option value="draft">Draft</option>
          <option value="open">Open</option>
          <option value="on_hold">On hold</option>
          <option value="closed">Closed</option>
          <option value="cancelled">Cancelled</option>
        </select>
        <div className="ml-auto">
          <Button type="button" variant="secondary" onClick={() => setShowCreate((v) => !v)} disabled={positions.length === 0}>
            {showCreate ? "Cancel" : "New vacancy"}
          </Button>
        </div>
      </div>

      {positions.length === 0 ? (
        <p className="text-xs text-neutral-500">No active positions exist yet -- create one under Positions &amp; grades before opening a vacancy.</p>
      ) : null}

      {showCreate ? (
        <form action={createFormAction} className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4" noValidate>
          <div className="flex flex-col gap-1">
            <label htmlFor="positionId" className="text-sm font-medium text-neutral-700">
              Position
            </label>
            <select id="positionId" name="positionId" value={positionId} onChange={(e) => setPositionId(e.target.value)} className="rounded-md border border-neutral-300 px-3 py-2 text-sm">
              {positions.map((p) => (
                <option key={p.id} value={p.id}>
                  {p.title} ({p.code})
                </option>
              ))}
            </select>
          </div>
          <div className="flex flex-col gap-1">
            <label htmlFor="title" className="text-sm font-medium text-neutral-700">
              Vacancy title
            </label>
            <input id="title" name="title" type="text" required className="rounded-md border border-neutral-300 px-3 py-2 text-sm" />
          </div>
          <div className="flex gap-3">
            <div className="flex flex-1 flex-col gap-1">
              <label htmlFor="employmentType" className="text-sm font-medium text-neutral-700">
                Employment type
              </label>
              <select id="employmentType" name="employmentType" className="rounded-md border border-neutral-300 px-3 py-2 text-sm">
                <option value="full_time">Full time</option>
                <option value="part_time">Part time</option>
                <option value="contract">Contract</option>
                <option value="internship">Internship</option>
                <option value="temporary">Temporary</option>
              </select>
            </div>
            <div className="flex w-28 flex-col gap-1">
              <label htmlFor="headcount" className="text-sm font-medium text-neutral-700">
                Headcount
              </label>
              <input id="headcount" name="headcount" type="number" min="1" defaultValue={1} className="rounded-md border border-neutral-300 px-3 py-2 text-sm" />
            </div>
          </div>
          <div className="flex flex-col gap-1">
            <label htmlFor="description" className="text-sm font-medium text-neutral-700">
              Description
            </label>
            <textarea id="description" name="description" rows={3} className="rounded-md border border-neutral-300 px-3 py-2 text-sm" />
          </div>
          <div className="flex flex-col gap-1">
            <label htmlFor="requirements" className="text-sm font-medium text-neutral-700">
              Requirements
            </label>
            <textarea id="requirements" name="requirements" rows={3} className="rounded-md border border-neutral-300 px-3 py-2 text-sm" />
          </div>
          {createState.error ? (
            <p role="alert" className="text-sm text-danger">
              {createState.error}
            </p>
          ) : null}
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
