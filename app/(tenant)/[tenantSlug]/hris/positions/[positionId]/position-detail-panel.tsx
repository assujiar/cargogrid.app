"use client";

import { useActionState, useEffect, useRef, useState } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import { Input } from "../../../../../../components/forms/input.tsx";
import { Select } from "../../../../../../components/forms/select.tsx";
import { FormField } from "../../../../../../components/forms/form-field.tsx";
import { ValidationMessage } from "../../../../../../components/forms/validation-message.tsx";
import { StatusBadge, type StatusTone } from "../../../../../../components/ui/status-badge.tsx";
import { EmptyState } from "../../../../../../components/ui/empty-state.tsx";
import type { PositionActionState } from "../actions.ts";
import type { PositionDetail, PositionGrade, EmployeePositionAssignment, PositionStatus } from "../../../../../../server/contracts/position/position.ts";

const INITIAL_STATE: PositionActionState = { error: null };
const STATUS_TONE: Record<PositionStatus, StatusTone> = { active: "success", inactive: "neutral" };

type BoundAction = (prevState: PositionActionState, formData: FormData) => Promise<PositionActionState>;
type OrgUnit = { id: string; name: string; unitType: string };

/** Unsaved-change protection (review-round fix, section 15): the exact real
 * `beforeunload` pattern app/(tenant)/[tenantSlug]/hris/employees/[masterRecordId]/
 * employee-detail-panel.tsx's `EmployeeEditForm` already established -- a
 * browser-native "leave site?" prompt while any field has diverged from its
 * last-saved value, cleared once the save action completes without error. Generic
 * over the field-value shape so both this panel's edit form and, separately, the
 * assignment wizard can reuse the identical dirty-tracking/warning mechanics. */
function useUnsavedChangeGuard<T>(values: T, pending: boolean, error: string | null, initial: T) {
  const [savedValues, setSavedValues] = useState(initial);
  const dirty = JSON.stringify(values) !== JSON.stringify(savedValues);
  const valuesRef = useRef(values);
  const wasPendingRef = useRef(false);

  useEffect(() => {
    valuesRef.current = values;
  }, [values]);

  useEffect(() => {
    if (!dirty) return;
    const handler = (event: BeforeUnloadEvent) => {
      event.preventDefault();
    };
    window.addEventListener("beforeunload", handler);
    return () => window.removeEventListener("beforeunload", handler);
  }, [dirty]);

  useEffect(() => {
    if (wasPendingRef.current && !pending && error === null) {
      setSavedValues(valuesRef.current);
    }
    wasPendingRef.current = pending;
  }, [pending, error]);

  return dirty;
}

export function PositionDetailPanel({
  tenantSlug,
  position,
  grades,
  orgUnits,
  incumbents,
  updateAction,
  setStatusAction,
}: {
  tenantSlug: string;
  position: PositionDetail;
  grades: readonly PositionGrade[];
  orgUnits: readonly OrgUnit[];
  incumbents: readonly EmployeePositionAssignment[];
  updateAction: BoundAction;
  setStatusAction: (newStatus: PositionStatus) => BoundAction;
}) {
  const [updateState, updateFormAction, updatePending] = useActionState(updateAction, INITIAL_STATE);
  const nextStatus: PositionStatus = position.status === "active" ? "inactive" : "active";
  const [statusState, statusFormAction, statusPending] = useActionState(setStatusAction(nextStatus), INITIAL_STATE);

  const initialEditValues = {
    title: position.title,
    orgUnitId: position.orgUnitId,
    gradeId: position.gradeId ?? "",
    capacity: String(position.capacity),
    description: position.description ?? "",
  };
  const [editValues, setEditValues] = useState(initialEditValues);
  const editDirty = useUnsavedChangeGuard(editValues, updatePending, updateState.error, initialEditValues);
  function editField<K extends keyof typeof editValues>(key: K) {
    return { value: editValues[key], onChange: (e: React.ChangeEvent<HTMLInputElement | HTMLSelectElement>) => setEditValues((v) => ({ ...v, [key]: e.target.value })) };
  }

  return (
    <div className="flex flex-col gap-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h1 className="text-xl font-semibold text-neutral-900">
            {position.title} <span className="text-sm font-normal text-neutral-500">({position.code})</span>
          </h1>
          <div className="mt-1 flex items-center gap-2">
            <StatusBadge tone={STATUS_TONE[position.status]} label={position.status} />
            <span className="text-xs text-neutral-500">
              {position.currentHeadcount} / {position.capacity} capacity used ({position.capacityRemaining} remaining)
            </span>
          </div>
        </div>
        <a href={`/${tenantSlug}/hris/positions`} className="text-sm text-primary underline">
          Back to catalogue
        </a>
      </div>

      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Details</h2>
        <form action={updateFormAction} className="grid grid-cols-1 gap-2 sm:grid-cols-2" noValidate>
          {editDirty ? <p className="col-span-full text-xs text-warning">You have unsaved changes.</p> : null}
          <FormField id="position-title" label="Title">
            <Input id="position-title" name="title" required invalid={Boolean(updateState.error)} aria-describedby={updateState.error ? "position-update-error" : undefined} {...editField("title")} />
          </FormField>
          <FormField id="position-org-unit" label="Org unit">
            <Select id="position-org-unit" name="orgUnitId" required invalid={Boolean(updateState.error)} aria-describedby={updateState.error ? "position-update-error" : undefined} {...editField("orgUnitId")}>
              {orgUnits.map((u) => (
                <option key={u.id} value={u.id}>
                  {u.name} ({u.unitType})
                </option>
              ))}
            </Select>
          </FormField>
          <FormField id="position-grade" label="Grade">
            <Select id="position-grade" name="gradeId" invalid={Boolean(updateState.error)} aria-describedby={updateState.error ? "position-update-error" : undefined} {...editField("gradeId")}>
              <option value="">No grade</option>
              {grades.map((g) => (
                <option key={g.id} value={g.id}>
                  {g.code} — {g.name}
                </option>
              ))}
            </Select>
          </FormField>
          <FormField id="position-capacity" label="Capacity">
            <Input id="position-capacity" name="capacity" type="number" min="1" required invalid={Boolean(updateState.error)} aria-describedby={updateState.error ? "position-update-error" : undefined} {...editField("capacity")} />
          </FormField>
          <div className="sm:col-span-2">
            <FormField id="position-description" label="Description">
              <Input id="position-description" name="description" invalid={Boolean(updateState.error)} aria-describedby={updateState.error ? "position-update-error" : undefined} {...editField("description")} />
            </FormField>
          </div>
          {updateState.error ? (
            <div className="col-span-full">
              <ValidationMessage id="position-update-error">{updateState.error}</ValidationMessage>
            </div>
          ) : null}
          <div className="col-span-full">
            <Button type="submit" loading={updatePending} loadingLabel="Saving…">
              Save changes
            </Button>
          </div>
        </form>

        <form action={statusFormAction} className="flex flex-col gap-1 border-t border-neutral-100 pt-3">
          <p className="text-xs text-neutral-500">
            {position.status === "active" ? "Deactivating is blocked while any currently-effective assignment references this position." : "Reactivate this position to make it assignable again."}
          </p>
          <Button type="submit" variant="secondary" loading={statusPending} loadingLabel="Working…">
            Set {nextStatus}
          </Button>
          {statusState.error ? <ValidationMessage>{statusState.error}</ValidationMessage> : null}
        </form>
      </section>

      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Current incumbents</h2>
        {incumbents.length === 0 ? (
          <EmptyState title="No one currently assigned" description="This position has no active (approved and in-effect or scheduled) assignment." />
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="text-left text-xs text-neutral-500">
                  <th className="pb-1">Employee</th>
                  <th className="pb-1">Type</th>
                  <th className="pb-1">Effective from</th>
                  <th className="pb-1">Effective to</th>
                  <th className="pb-1">Change reason</th>
                </tr>
              </thead>
              <tbody>
                {incumbents.map((assignment) => (
                  <tr key={assignment.id} className="border-t border-neutral-100">
                    <td className="py-1">
                      <a href={`/${tenantSlug}/hris/employees/${assignment.masterRecordId}`} className="text-primary underline">
                        {assignment.masterRecordId}
                      </a>
                    </td>
                    <td className="py-1 text-xs">{assignment.assignmentType}</td>
                    <td className="py-1 text-xs">{assignment.effectiveStartDate}</td>
                    <td className="py-1 text-xs">{assignment.effectiveEndDate ?? "open-ended"}</td>
                    <td className="py-1 text-xs">{assignment.changeReason.replace(/_/g, " ")}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>
    </div>
  );
}
