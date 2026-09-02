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
  const createDescribedBy = state.error ? "create-employee-error" : undefined;

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
            <Input
              id="employee-search"
              type="search"
              defaultValue={search}
              placeholder="Name or employee number"
              className="py-1.5"
              onKeyDown={(event) => {
                if (event.key === "Enter") applyFilter(statusFilter ?? "", event.currentTarget.value);
              }}
            />
          </div>
          <div className="flex flex-col gap-1">
            <label htmlFor="employee-status" className="text-xs font-medium text-neutral-600">
              Status
            </label>
            <Select id="employee-status" defaultValue={statusFilter ?? ""} className="w-auto py-1.5" onChange={(event) => applyFilter(event.currentTarget.value, search)}>
              <option value="">All statuses</option>
              {EMPLOYEE_LIFECYCLE_STATUSES.map((s) => (
                <option key={s} value={s}>
                  {s.replace(/_/g, " ")}
                </option>
              ))}
            </Select>
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
        <form action={formAction} className="grid grid-cols-1 gap-3 sm:grid-cols-2" noValidate>
          <FormField id="fullName" label="Full name">
            <Input id="fullName" name="fullName" type="text" required invalid={Boolean(state.error)} aria-describedby={createDescribedBy} />
          </FormField>
          <FormField id="employmentType" label="Employment type">
            <Select id="employmentType" name="employmentType" required defaultValue="" invalid={Boolean(state.error)} aria-describedby={createDescribedBy}>
              <option value="" disabled>
                Select…
              </option>
              {EMPLOYMENT_TYPES.map((t) => (
                <option key={t} value={t}>
                  {t.replace(/_/g, " ")}
                </option>
              ))}
            </Select>
          </FormField>
          <FormField id="workEmail" label="Work email (optional)">
            <Input id="workEmail" name="workEmail" type="email" invalid={Boolean(state.error)} aria-describedby={createDescribedBy} />
          </FormField>
          <FormField id="hireDate" label="Hire date (optional)">
            <Input id="hireDate" name="hireDate" type="date" invalid={Boolean(state.error)} aria-describedby={createDescribedBy} />
          </FormField>

          {state.error ? (
            <div className="col-span-full">
              <ValidationMessage id="create-employee-error">{state.error}</ValidationMessage>
            </div>
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
