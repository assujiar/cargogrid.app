"use client";

import { useActionState } from "react";
import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { Button } from "../../../../../components/ui/button.tsx";
import { StatusBadge, type StatusTone } from "../../../../../components/ui/status-badge.tsx";
import { EmptyState } from "../../../../../components/ui/empty-state.tsx";
import type { EmployeeActionState } from "./actions.ts";
import { EMPLOYEE_LIFECYCLE_STATUSES, EMPLOYMENT_TYPES, type EmployeeLifecycleStatus, type EmployeeListRow } from "../../../../../server/contracts/employee/employee.ts";

const INITIAL_STATE: EmployeeActionState = { error: null };

const STATUS_TONE: Record<EmployeeLifecycleStatus, StatusTone> = {
  draft: "neutral",
  submitted: "info",
  approved: "info",
  active: "success",
  on_leave: "warning",
  suspended: "warning",
  terminated: "danger",
  archived: "neutral",
};

export function EmployeeDirectoryPanel({
  tenantSlug,
  employees,
  statusFilter,
  search,
  createAction,
}: {
  tenantSlug: string;
  employees: readonly EmployeeListRow[];
  statusFilter: EmployeeLifecycleStatus | null;
  search: string;
  createAction: (prevState: EmployeeActionState, formData: FormData) => Promise<EmployeeActionState>;
}) {
  const router = useRouter();
  const searchParams = useSearchParams();
  const [state, formAction, pending] = useActionState(createAction, INITIAL_STATE);

  function applyFilter(nextStatus: string, nextSearch: string) {
    const next = new URLSearchParams(searchParams.toString());
    if (nextStatus) next.set("status", nextStatus);
    else next.delete("status");
    if (nextSearch) next.set("q", nextSearch);
    else next.delete("q");
    next.delete("after");
    router.push(`/${tenantSlug}/hris/employees?${next.toString()}`);
  }

  return (
    <div className="flex flex-col gap-4">
      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        <div className="flex flex-wrap items-end gap-3">
          <div className="flex flex-col gap-1">
            <label htmlFor="employee-search" className="text-xs font-medium text-neutral-600">
              Search
            </label>
            <input
              id="employee-search"
              type="search"
              defaultValue={search}
              placeholder="Name or employee number"
              className="rounded-md border border-neutral-300 px-3 py-1.5 text-sm"
              onKeyDown={(event) => {
                if (event.key === "Enter") applyFilter(statusFilter ?? "", event.currentTarget.value);
              }}
            />
          </div>
          <div className="flex flex-col gap-1">
            <label htmlFor="employee-status" className="text-xs font-medium text-neutral-600">
              Status
            </label>
            <select id="employee-status" defaultValue={statusFilter ?? ""} className="rounded-md border border-neutral-300 px-3 py-1.5 text-sm" onChange={(event) => applyFilter(event.currentTarget.value, search)}>
              <option value="">All statuses</option>
              {EMPLOYEE_LIFECYCLE_STATUSES.map((s) => (
                <option key={s} value={s}>
                  {s.replace(/_/g, " ")}
                </option>
              ))}
            </select>
          </div>
        </div>

        {employees.length === 0 ? (
          <EmptyState title="No employees match this view" description="Adjust your search/status filter, or create a new employee draft below." />
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="text-left text-xs text-neutral-500">
                  <th className="pb-1">Employee number</th>
                  <th className="pb-1">Full name</th>
                  <th className="pb-1">Employment type</th>
                  <th className="pb-1">Position</th>
                  <th className="pb-1">Hire date</th>
                  <th className="pb-1">Status</th>
                </tr>
              </thead>
              <tbody>
                {employees.map((employee) => (
                  <tr key={employee.masterRecordId} className="border-t border-neutral-100">
                    <td className="py-1">
                      <Link href={`/${tenantSlug}/hris/employees/${employee.masterRecordId}`} className="text-primary underline">
                        {employee.employeeNumber}
                      </Link>
                    </td>
                    <td className="py-1">{employee.fullName}</td>
                    <td className="py-1 text-xs">{employee.employmentType.replace(/_/g, " ")}</td>
                    <td className="py-1">{employee.positionTitle ?? "—"}</td>
                    <td className="py-1">{employee.hireDate ?? "—"}</td>
                    <td className="py-1">
                      <StatusBadge tone={STATUS_TONE[employee.lifecycleStatus]} label={employee.lifecycleStatus.replace(/_/g, " ")} />
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>

      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Create a new employee draft</h2>
        <form action={formAction} className="grid grid-cols-1 gap-3 sm:grid-cols-2">
          <div className="flex flex-col gap-1">
            <label htmlFor="fullName" className="text-xs font-medium text-neutral-600">
              Full name
            </label>
            <input id="fullName" name="fullName" type="text" required className="rounded-md border border-neutral-300 px-3 py-1.5 text-sm" />
          </div>
          <div className="flex flex-col gap-1">
            <label htmlFor="employmentType" className="text-xs font-medium text-neutral-600">
              Employment type
            </label>
            <select id="employmentType" name="employmentType" required defaultValue="" className="rounded-md border border-neutral-300 px-3 py-1.5 text-sm">
              <option value="" disabled>
                Select…
              </option>
              {EMPLOYMENT_TYPES.map((t) => (
                <option key={t} value={t}>
                  {t.replace(/_/g, " ")}
                </option>
              ))}
            </select>
          </div>
          <div className="flex flex-col gap-1">
            <label htmlFor="workEmail" className="text-xs font-medium text-neutral-600">
              Work email (optional)
            </label>
            <input id="workEmail" name="workEmail" type="email" className="rounded-md border border-neutral-300 px-3 py-1.5 text-sm" />
          </div>
          <div className="flex flex-col gap-1">
            <label htmlFor="hireDate" className="text-xs font-medium text-neutral-600">
              Hire date (optional)
            </label>
            <input id="hireDate" name="hireDate" type="date" className="rounded-md border border-neutral-300 px-3 py-1.5 text-sm" />
          </div>

          {state.error ? (
            <p role="alert" className="col-span-full text-sm text-danger">
              {state.error}
            </p>
          ) : null}

          <div className="col-span-full">
            <Button type="submit" loading={pending} loadingLabel="Creating…">
              Create draft
            </Button>
          </div>
        </form>
      </section>
    </div>
  );
}
