"use client";

import { useActionState } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import { Checkbox } from "../../../../../../components/forms/checkbox.tsx";
import { Select } from "../../../../../../components/forms/select.tsx";
import { FormField } from "../../../../../../components/forms/form-field.tsx";
import { ValidationMessage } from "../../../../../../components/forms/validation-message.tsx";
import { StatusBadge } from "../../../../../../components/ui/status-badge.tsx";
import { EmptyState } from "../../../../../../components/ui/empty-state.tsx";
import type { RoleActionState } from "../actions.ts";
import type { Role, RoleVersion, RoleAssignment, Permission } from "../../../../../../server/contracts/role-permission/role-permission.ts";
import type { RoleAssignmentCandidate } from "../../../../../../server/queries/role-permission.ts";

const INITIAL_STATE: RoleActionState = { error: null };
type BoundAction = (prevState: RoleActionState, formData: FormData) => Promise<RoleActionState>;

function SimpleActionButton({ action, label, pendingLabel }: { action: BoundAction; label: string; pendingLabel: string }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col gap-2">
      <Button type="submit" loading={pending} loadingLabel={pendingLabel}>
        {label}
      </Button>
      {state.error ? <ValidationMessage id={`${label}-error`}>{state.error}</ValidationMessage> : null}
    </form>
  );
}

function SetPermissionsForm({ action, allPermissions, boundPermissionIds }: { action: BoundAction; allPermissions: readonly Permission[]; boundPermissionIds: readonly string[] }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  const boundSet = new Set(boundPermissionIds);
  const byModule = new Map<string, Permission[]>();
  for (const permission of allPermissions) {
    const list = byModule.get(permission.resourceModuleCode) ?? [];
    list.push(permission);
    byModule.set(permission.resourceModuleCode, list);
  }

  return (
    <form action={formAction} className="flex flex-col gap-3">
      {[...byModule.entries()].map(([moduleCode, permissions]) => (
        <fieldset key={moduleCode} className="rounded-md border border-neutral-200 p-3">
          <legend className="px-1 text-xs font-semibold uppercase text-neutral-500">{moduleCode}</legend>
          <div className="grid grid-cols-2 gap-1 sm:grid-cols-3">
            {permissions.map((permission) => (
              <Checkbox key={permission.id} id={`perm-${permission.id}`} name="permissionId" value={permission.id} defaultChecked={boundSet.has(permission.id)} label={permission.action} />
            ))}
          </div>
        </fieldset>
      ))}
      {state.error ? <ValidationMessage id="set-permissions-error">{state.error}</ValidationMessage> : null}
      <Button type="submit" loading={pending} loadingLabel="Saving…" className="w-fit">
        Save permissions
      </Button>
    </form>
  );
}

function AssignRoleForm({ action, publishedVersions, candidates }: { action: BoundAction; publishedVersions: readonly RoleVersion[]; candidates: readonly RoleAssignmentCandidate[] }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  const describedBy = state.error ? "assign-role-error" : undefined;

  if (publishedVersions.length === 0) {
    return <EmptyState title="No published version yet" description="Publish a version of this role before assigning it to anyone." />;
  }

  return (
    <form action={formAction} className="grid grid-cols-1 gap-3 sm:grid-cols-2">
      <FormField id="roleVersionId" label="Version">
        <Select id="roleVersionId" name="roleVersionId" required invalid={Boolean(state.error)} aria-describedby={describedBy}>
          {publishedVersions.map((version) => (
            <option key={version.id} value={version.id}>
              v{version.versionNumber}
            </option>
          ))}
        </Select>
      </FormField>
      <FormField id="authUserId" label="User">
        <Select id="authUserId" name="authUserId" required invalid={Boolean(state.error)} aria-describedby={describedBy}>
          <option value="">Select a user</option>
          {candidates.map((candidate) => (
            <option key={candidate.authUserId} value={candidate.authUserId}>
              {candidate.displayName}
            </option>
          ))}
        </Select>
      </FormField>
      {state.error ? (
        <div className="col-span-full">
          <ValidationMessage id="assign-role-error">{state.error}</ValidationMessage>
        </div>
      ) : null}
      <div className="col-span-full">
        <Button type="submit" loading={pending} loadingLabel="Assigning…">
          Assign role
        </Button>
      </div>
    </form>
  );
}

function RevokeButton({ action }: { action: BoundAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  return (
    <form action={formAction} className="inline-flex flex-col gap-1">
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Revoking…">
        Revoke
      </Button>
      {state.error ? <ValidationMessage id="revoke-error">{state.error}</ValidationMessage> : null}
    </form>
  );
}

export function RoleDetailPanel({
  role,
  versions,
  draftVersion,
  draftPermissionIds,
  allPermissions,
  assignments,
  candidateNamesByAuthUserId,
  candidates,
  createVersionAction,
  setPermissionsAction,
  publishAction,
  assignAction,
  revokeActionFor,
}: {
  role: Role;
  versions: readonly RoleVersion[];
  draftVersion: RoleVersion | null;
  draftPermissionIds: readonly string[];
  allPermissions: readonly Permission[];
  assignments: readonly RoleAssignment[];
  candidateNamesByAuthUserId: ReadonlyMap<string, string>;
  candidates: readonly RoleAssignmentCandidate[];
  createVersionAction: BoundAction;
  setPermissionsAction: BoundAction | null;
  publishAction: BoundAction | null;
  assignAction: BoundAction;
  revokeActionFor: (assignmentId: string) => BoundAction;
}) {
  const publishedVersions = versions.filter((version) => version.status === "published");

  return (
    <div className="flex flex-col gap-6">
      <div>
        <h1 className="text-xl font-semibold text-neutral-900">{role.name}</h1>
        {role.description ? <p className="text-sm text-neutral-600">{role.description}</p> : null}
      </div>

      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Versions</h2>
        {versions.length === 0 ? (
          <EmptyState title="No versions yet" />
        ) : (
          <ul className="flex flex-col divide-y divide-neutral-200">
            {versions.map((version) => (
              <li key={version.id} className="flex items-center justify-between py-2 text-sm">
                <span>v{version.versionNumber}</span>
                <StatusBadge tone={version.status === "published" ? "success" : version.status === "draft" ? "warning" : "neutral"} label={version.status} />
              </li>
            ))}
          </ul>
        )}

        {draftVersion ? (
          <div className="flex flex-col gap-3">
            <h3 className="text-sm font-medium text-neutral-900">Draft v{draftVersion.versionNumber} permissions</h3>
            {setPermissionsAction ? <SetPermissionsForm action={setPermissionsAction} allPermissions={allPermissions} boundPermissionIds={draftPermissionIds} /> : null}
            {publishAction ? <SimpleActionButton action={publishAction} label="Publish this version" pendingLabel="Publishing…" /> : null}
          </div>
        ) : (
          <SimpleActionButton action={createVersionAction} label="Create new draft version" pendingLabel="Creating…" />
        )}
      </section>

      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Assignments</h2>
        {assignments.length === 0 ? (
          <EmptyState title="No one has been assigned this role yet" />
        ) : (
          <ul className="flex flex-col divide-y divide-neutral-200">
            {assignments.map((assignment) => (
              <li key={assignment.id} className="flex items-center justify-between gap-3 py-2 text-sm">
                <span>{candidateNamesByAuthUserId.get(assignment.authUserId) ?? assignment.authUserId}</span>
                <div className="flex items-center gap-3">
                  <StatusBadge tone={assignment.status === "active" ? "success" : "neutral"} label={assignment.status} />
                  {assignment.status === "active" ? <RevokeButton action={revokeActionFor(assignment.id)} /> : null}
                </div>
              </li>
            ))}
          </ul>
        )}

        <h3 className="text-sm font-medium text-neutral-900">Assign this role</h3>
        <AssignRoleForm action={assignAction} publishedVersions={publishedVersions} candidates={candidates} />
      </section>
    </div>
  );
}
