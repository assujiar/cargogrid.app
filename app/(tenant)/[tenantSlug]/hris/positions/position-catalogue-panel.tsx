"use client";

import { useActionState } from "react";
import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { Button } from "../../../../../components/ui/button.tsx";
import { Input } from "../../../../../components/forms/input.tsx";
import { Select } from "../../../../../components/forms/select.tsx";
import { FormField } from "../../../../../components/forms/form-field.tsx";
import { ValidationMessage } from "../../../../../components/forms/validation-message.tsx";
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

        <form action={createGradeFormAction} className="grid grid-cols-1 gap-2 sm:grid-cols-4" noValidate>
          <label htmlFor="grade-code" className="sr-only">
            Code
          </label>
          <Input id="grade-code" name="code" placeholder="Code (e.g. GR-3)" required invalid={Boolean(createGradeState.error)} aria-describedby={createGradeState.error ? "create-grade-error" : undefined} />
          <label htmlFor="grade-name" className="sr-only">
            Name
          </label>
          <Input id="grade-name" name="name" placeholder="Name" required invalid={Boolean(createGradeState.error)} aria-describedby={createGradeState.error ? "create-grade-error" : undefined} />
          <label htmlFor="grade-rank" className="sr-only">
            Rank
          </label>
          <Input id="grade-rank" name="rank" type="number" placeholder="Rank (optional)" invalid={Boolean(createGradeState.error)} aria-describedby={createGradeState.error ? "create-grade-error" : undefined} />
          <label htmlFor="grade-description" className="sr-only">
            Description
          </label>
          <Input id="grade-description" name="description" placeholder="Description (optional)" invalid={Boolean(createGradeState.error)} aria-describedby={createGradeState.error ? "create-grade-error" : undefined} />
          {createGradeState.error ? (
            <div className="col-span-full">
              <ValidationMessage id="create-grade-error">{createGradeState.error}</ValidationMessage>
            </div>
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
            <Input
              id="position-search"
              type="search"
              defaultValue={search}
              placeholder="Code or title"
              className="py-1.5"
              onKeyDown={(event) => {
                if (event.key === "Enter") applyFilter(statusFilter ?? "", event.currentTarget.value);
              }}
            />
          </div>
          <div className="flex flex-col gap-1">
            <label htmlFor="position-status" className="text-xs font-medium text-neutral-600">
              Status
            </label>
            <Select id="position-status" defaultValue={statusFilter ?? ""} className="w-auto py-1.5" onChange={(event) => applyFilter(event.currentTarget.value, search)}>
              <option value="">All statuses</option>
              {POSITION_STATUSES.map((s) => (
                <option key={s} value={s}>
                  {s}
                </option>
              ))}
            </Select>
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

        <form action={createPosFormAction} className="grid grid-cols-1 gap-2 sm:grid-cols-3" noValidate>
          <label htmlFor="pos-code" className="sr-only">
            Code
          </label>
          <Input id="pos-code" name="code" placeholder="Code (e.g. POS-042)" required invalid={Boolean(createPosState.error)} aria-describedby={createPosState.error ? "create-position-error" : undefined} />
          <label htmlFor="pos-title" className="sr-only">
            Title
          </label>
          <Input id="pos-title" name="title" placeholder="Title" required invalid={Boolean(createPosState.error)} aria-describedby={createPosState.error ? "create-position-error" : undefined} />
          <label htmlFor="pos-org-unit" className="sr-only">
            Org unit
          </label>
          <Select id="pos-org-unit" name="orgUnitId" required defaultValue="" invalid={Boolean(createPosState.error)} aria-describedby={createPosState.error ? "create-position-error" : undefined}>
            <option value="" disabled>
              Org unit…
            </option>
            {orgUnits.map((u) => (
              <option key={u.id} value={u.id}>
                {u.name} ({u.unitType})
              </option>
            ))}
          </Select>
          <label htmlFor="pos-grade" className="sr-only">
            Grade
          </label>
          <Select id="pos-grade" name="gradeId" defaultValue="" invalid={Boolean(createPosState.error)} aria-describedby={createPosState.error ? "create-position-error" : undefined}>
            <option value="">No grade</option>
            {grades.map((g) => (
              <option key={g.id} value={g.id}>
                {g.code} — {g.name}
              </option>
            ))}
          </Select>
          <label htmlFor="pos-capacity" className="sr-only">
            Capacity
          </label>
          <Input id="pos-capacity" name="capacity" type="number" min="1" placeholder="Capacity (default 1)" invalid={Boolean(createPosState.error)} aria-describedby={createPosState.error ? "create-position-error" : undefined} />
          <label htmlFor="pos-description" className="sr-only">
            Description
          </label>
          <Input id="pos-description" name="description" placeholder="Description (optional)" invalid={Boolean(createPosState.error)} aria-describedby={createPosState.error ? "create-position-error" : undefined} />
          {createPosState.error ? (
            <div className="col-span-full">
              <ValidationMessage id="create-position-error">{createPosState.error}</ValidationMessage>
            </div>
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
          {state.error ? <ValidationMessage>{state.error}</ValidationMessage> : null}
        </form>
      </td>
    </tr>
  );
}
