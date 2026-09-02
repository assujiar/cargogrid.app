"use client";

import { useActionState, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { Button } from "../../../../../../components/ui/button.tsx";
import { Input } from "../../../../../../components/forms/input.tsx";
import { Select } from "../../../../../../components/forms/select.tsx";
import { DateInput } from "../../../../../../components/forms/date-input.tsx";
import { FormField } from "../../../../../../components/forms/form-field.tsx";
import { ValidationMessage } from "../../../../../../components/forms/validation-message.tsx";
import { EmptyState } from "../../../../../../components/ui/empty-state.tsx";
import type { BulkReassignActionState } from "./actions.ts";
import { ASSIGNMENT_TYPES, CHANGE_REASONS, type AssignmentType, type ChangeReason, type PositionGrade, type PositionListRow } from "../../../../../../server/contracts/position/position.ts";
import type { EmployeeListRow } from "../../../../../../server/contracts/employee/employee.ts";

const INITIAL_STATE: BulkReassignActionState = { error: null, createdCount: null };

interface RowState {
  positionId: string;
  gradeId: string;
  managerEmployeeId: string;
  assignmentType: AssignmentType;
}

type SubmitAction = (prevState: BulkReassignActionState, formData: FormData) => Promise<BulkReassignActionState>;

export function BulkReassignPanel({
  tenantSlug,
  departments,
  selectedDepartmentId,
  employees,
  positions,
  grades,
  submitAction,
}: {
  tenantSlug: string;
  departments: readonly { id: string; name: string }[];
  selectedDepartmentId: string | null;
  employees: readonly EmployeeListRow[];
  positions: readonly PositionListRow[];
  grades: readonly PositionGrade[];
  submitAction: SubmitAction;
}) {
  const router = useRouter();
  const [state, formAction, pending] = useActionState(submitAction, INITIAL_STATE);
  const [selected, setSelected] = useState<Record<string, boolean>>({});
  const [rows, setRows] = useState<Record<string, RowState>>({});
  const [bulkPositionId, setBulkPositionId] = useState("");
  const [changeReason, setChangeReason] = useState<ChangeReason>("reorganization");
  const [reasonNote, setReasonNote] = useState("");
  const [effectiveStartDate, setEffectiveStartDate] = useState("");
  const [effectiveEndDate, setEffectiveEndDate] = useState("");

  function rowFor(masterRecordId: string): RowState {
    return rows[masterRecordId] ?? { positionId: "", gradeId: "", managerEmployeeId: "", assignmentType: "primary" };
  }

  function updateRow(masterRecordId: string, patch: Partial<RowState>) {
    setRows((prev) => ({ ...prev, [masterRecordId]: { ...rowFor(masterRecordId), ...patch } }));
  }

  function applyPositionToSelected() {
    if (!bulkPositionId) return;
    setRows((prev) => {
      const next = { ...prev };
      for (const employee of employees) {
        if (!selected[employee.masterRecordId]) continue;
        next[employee.masterRecordId] = { ...rowFor(employee.masterRecordId), positionId: bulkPositionId };
      }
      return next;
    });
  }

  const selectedEmployees = useMemo(() => employees.filter((e) => selected[e.masterRecordId]), [employees, selected]);
  const readyItems = useMemo(
    () =>
      selectedEmployees
        .filter((e) => rowFor(e.masterRecordId).positionId)
        .map((e) => ({
          masterRecordId: e.masterRecordId,
          expectedVersion: e.recordVersion,
          positionId: rowFor(e.masterRecordId).positionId,
          gradeId: rowFor(e.masterRecordId).gradeId || null,
          managerEmployeeId: rowFor(e.masterRecordId).managerEmployeeId || null,
          assignmentType: rowFor(e.masterRecordId).assignmentType,
        })),
    // eslint-disable-next-line react-hooks/exhaustive-deps -- SUPPRESS(owner=hris, reason=rowFor already reads the listed rows dependency, expires=NONE, adr=NONE)
    [selectedEmployees, rows],
  );
  const missingPositionCount = selectedEmployees.length - readyItems.length;
  const canSubmit = readyItems.length > 0 && effectiveStartDate.length > 0 && !pending;
  // One server-action error covers the whole batch, so every batch-detail field points at it
  // rather than fabricating a per-field attribution the action does not return.
  const describedBy = state.error ? "bulk-reassign-error" : undefined;

  function onDepartmentChange(id: string) {
    setSelected({});
    setRows({});
    const next = new URLSearchParams();
    if (id) next.set("department", id);
    router.push(`/${tenantSlug}/hris/positions/bulk-reassign?${next.toString()}`);
  }

  return (
    <div className="flex flex-col gap-6">
      <section className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
        {/* ISS-2026-242: the "Department" text used to be a <label htmlFor="department-select">
            rendered even in the no-departments branch, where no such control exists -- a label
            pointing at nothing. It is only a real label when there is a real control. */}
        {departments.length === 0 ? (
          <>
            <p className="text-xs font-medium text-neutral-600">Department</p>
            <p className="text-xs text-neutral-500">No active departments exist yet in the organization tree.</p>
          </>
        ) : (
          <FormField id="department-select" label="Department">
            <Select id="department-select" defaultValue={selectedDepartmentId ?? ""} className="sm:max-w-sm" onChange={(e) => onDepartmentChange(e.currentTarget.value)}>
              <option value="">Select a department…</option>
              {departments.map((d) => (
                <option key={d.id} value={d.id}>
                  {d.name}
                </option>
              ))}
            </Select>
          </FormField>
        )}
      </section>

      {!selectedDepartmentId ? (
        <EmptyState title="Choose a department to begin" description="Pick a department above to list its active employees and select which ones to move." />
      ) : employees.length === 0 ? (
        <EmptyState title="No active employees in this department" description="Choose a different department, or use the single-employee wizard from an employee's own profile." />
      ) : (
        <form action={formAction} className="flex flex-col gap-4">
          <input type="hidden" name="items" value={JSON.stringify(readyItems)} />
          <input type="hidden" name="changeReason" value={changeReason} />
          <input type="hidden" name="reasonNote" value={reasonNote} />
          <input type="hidden" name="effectiveStartDate" value={effectiveStartDate} />
          <input type="hidden" name="effectiveEndDate" value={effectiveEndDate} />

          <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
            <h2 className="text-sm font-semibold text-neutral-900">Apply to all selected</h2>
            <div className="flex flex-wrap items-end gap-2">
              <FormField id="bulk-target-position" label="Target position">
                <Select id="bulk-target-position" value={bulkPositionId} onChange={(e) => setBulkPositionId(e.currentTarget.value)}>
                  <option value="">Select…</option>
                  {positions.map((p) => (
                    <option key={p.id} value={p.id}>
                      {p.code} — {p.title} ({p.currentHeadcount}/{p.capacity})
                    </option>
                  ))}
                </Select>
              </FormField>
              <Button type="button" variant="secondary" onClick={applyPositionToSelected} disabled={!bulkPositionId}>
                Apply to selected rows
              </Button>
            </div>
          </section>

          <section className="rounded-md border border-neutral-200 p-4">
            <h2 className="mb-3 text-sm font-semibold text-neutral-900">
              Employees in this department ({employees.length})
            </h2>
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead>
                  <tr className="text-left text-xs text-neutral-500">
                    <th className="pb-1">
                      <input
                        type="checkbox"
                        aria-label="Select all"
                        checked={employees.length > 0 && employees.every((e) => selected[e.masterRecordId])}
                        onChange={(e) => {
                          const checked = e.currentTarget.checked;
                          setSelected(Object.fromEntries(employees.map((emp) => [emp.masterRecordId, checked])));
                        }}
                      />
                    </th>
                    <th className="pb-1">Employee</th>
                    <th className="pb-1">Current position</th>
                    <th className="pb-1">Target position</th>
                    <th className="pb-1">Grade (optional)</th>
                    <th className="pb-1">Manager (optional)</th>
                    <th className="pb-1">Type</th>
                  </tr>
                </thead>
                <tbody>
                  {employees.map((employee) => {
                    const isSelected = !!selected[employee.masterRecordId];
                    const row = rowFor(employee.masterRecordId);
                    return (
                      <tr key={employee.masterRecordId} className="border-t border-neutral-100 align-top">
                        <td className="py-1">
                          <input
                            type="checkbox"
                            checked={isSelected}
                            aria-label={`Select ${employee.fullName}`}
                            onChange={(e) => setSelected((prev) => ({ ...prev, [employee.masterRecordId]: e.currentTarget.checked }))}
                          />
                        </td>
                        <td className="py-1 text-xs">
                          {employee.fullName} <span className="text-neutral-400">({employee.employeeNumber})</span>
                        </td>
                        <td className="py-1 text-xs">{employee.positionTitle ?? "—"}</td>
                        <td className="py-1">
                          {/* One row per employee, so every id is row-scoped -- a static id here
                              would repeat across every row. The visible column header carries the
                              field name, so each row's own label is screen-reader-only and names
                              the employee it belongs to. */}
                          <FormField id={`row-position-${employee.masterRecordId}`} label={<span className="sr-only">Target position for {employee.fullName}</span>}>
                            <Select
                              id={`row-position-${employee.masterRecordId}`}
                              disabled={!isSelected}
                              value={row.positionId}
                              onChange={(e) => updateRow(employee.masterRecordId, { positionId: e.currentTarget.value })}
                            >
                              <option value="">Select…</option>
                              {positions.map((p) => (
                                <option key={p.id} value={p.id}>
                                  {p.code} — {p.title}
                                </option>
                              ))}
                            </Select>
                          </FormField>
                        </td>
                        <td className="py-1">
                          <FormField id={`row-grade-${employee.masterRecordId}`} label={<span className="sr-only">Grade for {employee.fullName}</span>}>
                            <Select
                              id={`row-grade-${employee.masterRecordId}`}
                              disabled={!isSelected}
                              value={row.gradeId}
                              onChange={(e) => updateRow(employee.masterRecordId, { gradeId: e.currentTarget.value })}
                            >
                              <option value="">Position default</option>
                              {grades.map((g) => (
                                <option key={g.id} value={g.id}>
                                  {g.code}
                                </option>
                              ))}
                            </Select>
                          </FormField>
                        </td>
                        <td className="py-1">
                          <FormField id={`row-manager-${employee.masterRecordId}`} label={<span className="sr-only">Manager for {employee.fullName}</span>}>
                            <Input
                              id={`row-manager-${employee.masterRecordId}`}
                              type="text"
                              disabled={!isSelected}
                              value={row.managerEmployeeId}
                              onChange={(e) => updateRow(employee.masterRecordId, { managerEmployeeId: e.currentTarget.value })}
                              placeholder="uuid, optional"
                              className="w-32"
                            />
                          </FormField>
                        </td>
                        <td className="py-1">
                          <FormField id={`row-assignment-type-${employee.masterRecordId}`} label={<span className="sr-only">Assignment type for {employee.fullName}</span>}>
                            <Select
                              id={`row-assignment-type-${employee.masterRecordId}`}
                              disabled={!isSelected}
                              value={row.assignmentType}
                              onChange={(e) => updateRow(employee.masterRecordId, { assignmentType: e.currentTarget.value as AssignmentType })}
                            >
                              {ASSIGNMENT_TYPES.map((t) => (
                                <option key={t} value={t}>
                                  {t}
                                </option>
                              ))}
                            </Select>
                          </FormField>
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          </section>

          <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
            <h2 className="text-sm font-semibold text-neutral-900">Batch details</h2>
            <div className="grid grid-cols-1 gap-2 sm:grid-cols-3">
              <FormField id="batch-change-reason" label="Change reason">
                <Select
                  id="batch-change-reason"
                  value={changeReason}
                  onChange={(e) => setChangeReason(e.currentTarget.value as ChangeReason)}
                  invalid={Boolean(state.error)}
                  aria-describedby={describedBy}
                >
                  {CHANGE_REASONS.map((r) => (
                    <option key={r} value={r}>
                      {r.replace(/_/g, " ")}
                    </option>
                  ))}
                </Select>
              </FormField>
              <FormField id="batch-effective-start-date" label="Effective start date">
                <DateInput
                  id="batch-effective-start-date"
                  required
                  value={effectiveStartDate}
                  onChange={(e) => setEffectiveStartDate(e.currentTarget.value)}
                  invalid={Boolean(state.error)}
                  aria-describedby={describedBy}
                />
              </FormField>
              <FormField id="batch-effective-end-date" label="Effective end date (optional)">
                <DateInput
                  id="batch-effective-end-date"
                  value={effectiveEndDate}
                  onChange={(e) => setEffectiveEndDate(e.currentTarget.value)}
                  invalid={Boolean(state.error)}
                  aria-describedby={describedBy}
                />
              </FormField>
              <div className="sm:col-span-3">
                <FormField id="batch-reason-note" label="Reason note (optional)">
                  <Input
                    id="batch-reason-note"
                    type="text"
                    value={reasonNote}
                    onChange={(e) => setReasonNote(e.currentTarget.value)}
                    invalid={Boolean(state.error)}
                    aria-describedby={describedBy}
                  />
                </FormField>
              </div>
            </div>

            <p className="text-xs text-neutral-500">
              {selectedEmployees.length} employee(s) selected, {readyItems.length} with a target position chosen
              {missingPositionCount > 0 ? ` (${missingPositionCount} still need one before they can be included)` : ""}.
            </p>
            <p className="text-xs text-neutral-500">This creates a status=pending approval proposal for each employee, in one transaction -- either every proposal is created, or (on any error) none is. A separate HRS:Approve-holding reviewer must still decide each one.</p>

            <div>
              <Button type="submit" loading={pending} loadingLabel="Submitting…" disabled={!canSubmit}>
                Submit batch ({readyItems.length})
              </Button>
            </div>

            {state.error ? <ValidationMessage id="bulk-reassign-error">{state.error}</ValidationMessage> : null}
            {state.createdCount !== null ? (
              <p role="status" className="text-sm text-success">
                {state.createdCount} pending-approval proposal(s) created. Review and decide each from the affected employee&apos;s own position page.
              </p>
            ) : null}
          </section>
        </form>
      )}
    </div>
  );
}
