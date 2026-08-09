"use client";

import { useActionState } from "react";
import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { Button } from "../../../../../components/ui/button.tsx";
import { StatusBadge, type StatusTone } from "../../../../../components/ui/status-badge.tsx";
import { EmptyState } from "../../../../../components/ui/empty-state.tsx";
import type { PositionActionState } from "./actions.ts";
import { POSITION_STATUSES, type PositionGrade, type PositionListRow, type PositionGradeStatus, type PositionStatus } from "../../../../../server/contracts/position/position.ts";

const INITIAL_STATE: PositionActionState = { error: null };

const STATUS_TONE: Record<PositionStatus, StatusTone> = { active: "success", inactive: "neutral" };

type OrgUnit = { id: string; name: string; unitType: string };
type BoundAction = (prevState: PositionActionState, formData: FormData) => Promise<PositionActionState>;

export function PositionCataloguePanel({
  tenantSlug,
  positions,
  grades,
  orgUnits,
  statusFilter,
  search,
  createGradeAction,
  setGradeStatusAction,
  createPositionAction,
  setPositionStatusAction,
}: {
  tenantSlug: string;
  positions: readonly PositionListRow[];
  grades: readonly PositionGrade[];
  orgUnits: readonly OrgUnit[];
  statusFilter: PositionStatus | null;
  search: string;
  createGradeAction: BoundAction;
  setGradeStatusAction: (id: string, expectedVersion: number, newStatus: PositionGradeStatus) => BoundAction;
  createPositionAction: BoundAction;
  setPositionStatusAction: (id: string, expectedVersion: number, newStatus: PositionStatus) => BoundAction;
}) {
  const router = useRouter();
  const searchParams = useSearchParams();
  const [createPosState, createPosFormAction, createPosPending] = useActionState(createPositionAction, INITIAL_STATE);
  const [createGradeState, createGradeFormAction, createGradePending] = useActionState(createGradeAction, INITIAL_STATE);

  function applyFilter(nextStatus: string, nextSearch: string) {
    const next = new URLSearchParams(searchParams.toString());
    if (nextStatus) next.set("status", nextStatus);
    else next.delete("status");
    if (nextSearch) next.set("q", nextSearch);
    else next.delete("q");
    next.delete("after");
    router.push(`/${tenantSlug}/hris/positions?${next.toString()}`);
  }

  const orgUnitName = (id: string) => orgUnits.find((u) => u.id === id)?.name ?? id;
  const gradeCode = (id: string | null) => (id ? grades.find((g) => g.id === id)?.code ?? id : "—");

  return (
    <div className="flex flex-col gap-6">
      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Position grades</h2>
        {grades.length === 0 ? (
          <EmptyState title="No grades yet" description="Create a grade below to start building the position ladder." />
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="text-left text-xs text-neutral-500">
                  <th className="pb-1">Code</th>
                  <th className="pb-1">Name</th>
                  <th className="pb-1">Rank</th>
                  <th className="pb-1">Status</th>
                  <th className="pb-1">Action</th>
                </tr>
              </thead>
              <tbody>
                {grades.map((grade) => (
                  <GradeRow key={grade.id} grade={grade} action={setGradeStatusAction} />
                ))}
              </tbody>
            </table>
          </div>
        )}

        <form action={createGradeFormAction} className="grid grid-cols-1 gap-2 sm:grid-cols-4">
          <input name="code" placeholder="Code (e.g. GR-3)" required className="rounded-md border border-neutral-300 px-2 py-1 text-sm" />
          <input name="name" placeholder="Name" required className="rounded-md border border-neutral-300 px-2 py-1 text-sm" />
          <input name="rank" type="number" placeholder="Rank (optional)" className="rounded-md border border-neutral-300 px-2 py-1 text-sm" />
          <input name="description" placeholder="Description (optional)" className="rounded-md border border-neutral-300 px-2 py-1 text-sm" />
          {createGradeState.error ? (
            <p role="alert" className="col-span-full text-xs text-danger">
              {createGradeState.error}
            </p>
          ) : null}
          <div className="col-span-full">
            <Button type="submit" variant="secondary" loading={createGradePending} loadingLabel="Creating…">
              Add grade
            </Button>
          </div>
        </form>
      </section>

      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        <div className="flex flex-wrap items-end gap-3">
          <div className="flex flex-col gap-1">
            <label htmlFor="position-search" className="text-xs font-medium text-neutral-600">
              Search
            </label>
            <input
              id="position-search"
              type="search"
              defaultValue={search}
              placeholder="Code or title"
              className="rounded-md border border-neutral-300 px-3 py-1.5 text-sm"
              onKeyDown={(event) => {
                if (event.key === "Enter") applyFilter(statusFilter ?? "", event.currentTarget.value);
              }}
            />
          </div>
          <div className="flex flex-col gap-1">
            <label htmlFor="position-status" className="text-xs font-medium text-neutral-600">
              Status
            </label>
            <select id="position-status" defaultValue={statusFilter ?? ""} className="rounded-md border border-neutral-300 px-3 py-1.5 text-sm" onChange={(event) => applyFilter(event.currentTarget.value, search)}>
              <option value="">All statuses</option>
              {POSITION_STATUSES.map((s) => (
                <option key={s} value={s}>
                  {s}
                </option>
              ))}
            </select>
          </div>
        </div>

        {positions.length === 0 ? (
          <EmptyState title="No positions match this view" description="Adjust your search/status filter, or create a new position below." />
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="text-left text-xs text-neutral-500">
                  <th className="pb-1">Code</th>
                  <th className="pb-1">Title</th>
                  <th className="pb-1">Org unit</th>
                  <th className="pb-1">Grade</th>
                  <th className="pb-1">Headcount</th>
                  <th className="pb-1">Status</th>
                </tr>
              </thead>
              <tbody>
                {positions.map((position) => (
                  <tr key={position.id} className="border-t border-neutral-100">
                    <td className="py-1">
                      <Link href={`/${tenantSlug}/hris/positions/${position.id}`} className="text-primary underline">
                        {position.code}
                      </Link>
                    </td>
                    <td className="py-1">{position.title}</td>
                    <td className="py-1 text-xs">{orgUnitName(position.orgUnitId)}</td>
                    <td className="py-1 text-xs">{gradeCode(position.gradeId)}</td>
                    <td className="py-1 text-xs">
                      {position.currentHeadcount} / {position.capacity}
                    </td>
                    <td className="py-1">
                      <StatusBadge tone={STATUS_TONE[position.status]} label={position.status} />
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}

        <form action={createPosFormAction} className="grid grid-cols-1 gap-2 sm:grid-cols-3">
          <input name="code" placeholder="Code (e.g. POS-042)" required className="rounded-md border border-neutral-300 px-2 py-1 text-sm" />
          <input name="title" placeholder="Title" required className="rounded-md border border-neutral-300 px-2 py-1 text-sm" />
          <select name="orgUnitId" required defaultValue="" className="rounded-md border border-neutral-300 px-2 py-1 text-sm">
            <option value="" disabled>
              Org unit…
            </option>
            {orgUnits.map((u) => (
              <option key={u.id} value={u.id}>
                {u.name} ({u.unitType})
              </option>
            ))}
          </select>
          <select name="gradeId" defaultValue="" className="rounded-md border border-neutral-300 px-2 py-1 text-sm">
            <option value="">No grade</option>
            {grades.map((g) => (
              <option key={g.id} value={g.id}>
                {g.code} — {g.name}
              </option>
            ))}
          </select>
          <input name="capacity" type="number" min="1" placeholder="Capacity (default 1)" className="rounded-md border border-neutral-300 px-2 py-1 text-sm" />
          <input name="description" placeholder="Description (optional)" className="rounded-md border border-neutral-300 px-2 py-1 text-sm" />
          {createPosState.error ? (
            <p role="alert" className="col-span-full text-xs text-danger">
              {createPosState.error}
            </p>
          ) : null}
          <div className="col-span-full">
            <Button type="submit" loading={createPosPending} loadingLabel="Creating…">
              Add position
            </Button>
          </div>
        </form>
      </section>
    </div>
  );
}

function GradeRow({ grade, action }: { grade: PositionGrade; action: (id: string, expectedVersion: number, newStatus: PositionGradeStatus) => BoundAction }) {
  const nextStatus: PositionGradeStatus = grade.status === "active" ? "inactive" : "active";
  const boundAction = action(grade.id, grade.recordVersion, nextStatus);
  const [state, formAction, pending] = useActionState(boundAction, INITIAL_STATE);
  return (
    <tr className="border-t border-neutral-100 align-top">
      <td className="py-1">{grade.code}</td>
      <td className="py-1">{grade.name}</td>
      <td className="py-1">{grade.rank}</td>
      <td className="py-1">
        <StatusBadge tone={grade.status === "active" ? "success" : "neutral"} label={grade.status} />
      </td>
      <td className="py-1">
        <form action={formAction} className="flex flex-col gap-1">
          <Button type="submit" variant="secondary" loading={pending} loadingLabel="Working…">
            Set {nextStatus}
          </Button>
          {state.error ? (
            <p role="alert" className="text-xs text-danger">
              {state.error}
            </p>
          ) : null}
        </form>
      </td>
    </tr>
  );
}
