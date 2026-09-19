"use client";

import { useActionState } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
import { Input } from "../../../../../components/forms/input.tsx";
import { Select } from "../../../../../components/forms/select.tsx";
import { FormField } from "../../../../../components/forms/form-field.tsx";
import { ValidationMessage } from "../../../../../components/forms/validation-message.tsx";
import { StatusBadge } from "../../../../../components/ui/status-badge.tsx";
import { EmptyState } from "../../../../../components/ui/empty-state.tsx";
import type { OrgUnitActionState } from "./actions.ts";
import type { OrgUnit, OrgUnitType } from "../../../../../server/contracts/org-hierarchy/org-hierarchy.ts";

const INITIAL_STATE: OrgUnitActionState = { error: null };
const ORG_UNIT_TYPES: readonly OrgUnitType[] = ["company", "branch", "department", "business_unit"];

type BoundAction = (prevState: OrgUnitActionState, formData: FormData) => Promise<OrgUnitActionState>;

function RenameForm({ action }: { action: BoundAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  return (
    <form action={formAction} className="flex items-center gap-1">
      <Input id="newName" name="newName" type="text" placeholder="New name" required className="w-32" />
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="…">
        Rename
      </Button>
      {state.error ? <ValidationMessage id="rename-error">{state.error}</ValidationMessage> : null}
    </form>
  );
}

function MoveForm({ action, parentOptions }: { action: BoundAction; parentOptions: readonly OrgUnit[] }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  return (
    <form action={formAction} className="flex items-center gap-1">
      <Select id="newParentId" name="newParentId" defaultValue="" className="w-32">
        <option value="">No parent (root)</option>
        {parentOptions.map((unit) => (
          <option key={unit.id} value={unit.id}>
            {unit.name}
          </option>
        ))}
      </Select>
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="…">
        Move
      </Button>
      {state.error ? <ValidationMessage id="move-error">{state.error}</ValidationMessage> : null}
    </form>
  );
}

function ToggleStatusButton({ action, nextStatus }: { action: BoundAction; nextStatus: "active" | "inactive" }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col gap-1">
      <Button type="submit" variant={nextStatus === "inactive" ? "destructive" : "secondary"} loading={pending} loadingLabel="…">
        {nextStatus === "inactive" ? "Deactivate" : "Reactivate"}
      </Button>
      {state.error ? <ValidationMessage id="status-error">{state.error}</ValidationMessage> : null}
    </form>
  );
}

function CreateOrgUnitForm({ action, parentOptions }: { action: BoundAction; parentOptions: readonly OrgUnit[] }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  const describedBy = state.error ? "create-org-unit-error" : undefined;

  return (
    <form action={formAction} className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-4">
      <FormField id="unitType" label="Type">
        <Select id="unitType" name="unitType" required invalid={Boolean(state.error)} aria-describedby={describedBy}>
          {ORG_UNIT_TYPES.map((type) => (
            <option key={type} value={type}>
              {type}
            </option>
          ))}
        </Select>
      </FormField>
      <FormField id="parentId" label="Parent (optional)">
        <Select id="parentId" name="parentId" defaultValue="" invalid={Boolean(state.error)} aria-describedby={describedBy}>
          <option value="">No parent (root)</option>
          {parentOptions.map((unit) => (
            <option key={unit.id} value={unit.id}>
              {unit.name}
            </option>
          ))}
        </Select>
      </FormField>
      <FormField id="code" label="Code">
        <Input id="code" name="code" type="text" required invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <FormField id="name" label="Name">
        <Input id="name" name="name" type="text" required invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>

      {state.error ? (
        <div className="col-span-full">
          <ValidationMessage id="create-org-unit-error">{state.error}</ValidationMessage>
        </div>
      ) : null}

      <div className="col-span-full">
        <Button type="submit" loading={pending} loadingLabel="Creating…">
          Create org unit
        </Button>
      </div>
    </form>
  );
}

export function OrgHierarchyPanel({
  orgUnits,
  createAction,
  renameActionFor,
  moveActionFor,
  setStatusActionFor,
}: {
  orgUnits: readonly OrgUnit[];
  createAction: BoundAction;
  renameActionFor: (orgUnitId: string, expectedVersion: number) => BoundAction;
  moveActionFor: (orgUnitId: string, expectedVersion: number) => BoundAction;
  setStatusActionFor: (orgUnitId: string, expectedVersion: number, nextStatus: "active" | "inactive") => BoundAction;
}) {
  const namesById = new Map(orgUnits.map((unit) => [unit.id, unit.name]));

  return (
    <div className="flex flex-col gap-6">
      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Organization structure</h2>
        {orgUnits.length === 0 ? (
          <EmptyState title="No org units yet" description="Create one below to start building this organization's structure." />
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full min-w-[720px] text-sm">
              <thead>
                <tr className="text-left text-xs text-neutral-500">
                  <th className="pb-1">Name</th>
                  <th className="pb-1">Type</th>
                  <th className="pb-1">Parent</th>
                  <th className="pb-1">Status</th>
                  <th className="pb-1">Rename</th>
                  <th className="pb-1">Move</th>
                  <th className="pb-1"></th>
                </tr>
              </thead>
              <tbody>
                {orgUnits.map((unit) => {
                  const otherUnits = orgUnits.filter((candidate) => candidate.id !== unit.id);
                  return (
                    <tr key={unit.id} className="border-t border-neutral-100">
                      <td className="py-2 pr-2">{unit.name}</td>
                      <td className="py-2 pr-2">{unit.unitType}</td>
                      <td className="py-2 pr-2">{unit.parentId ? (namesById.get(unit.parentId) ?? "—") : "—"}</td>
                      <td className="py-2 pr-2">
                        <StatusBadge tone={unit.status === "active" ? "success" : "neutral"} label={unit.status} />
                      </td>
                      <td className="py-2 pr-2">
                        <RenameForm action={renameActionFor(unit.id, unit.recordVersion)} />
                      </td>
                      <td className="py-2 pr-2">
                        <MoveForm action={moveActionFor(unit.id, unit.recordVersion)} parentOptions={otherUnits} />
                      </td>
                      <td className="py-2">
                        <ToggleStatusButton
                          action={setStatusActionFor(unit.id, unit.recordVersion, unit.status === "active" ? "inactive" : "active")}
                          nextStatus={unit.status === "active" ? "inactive" : "active"}
                        />
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </section>

      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Create a new org unit</h2>
        <CreateOrgUnitForm action={createAction} parentOptions={orgUnits} />
      </section>
    </div>
  );
}
