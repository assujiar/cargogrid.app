"use client";

import { useActionState, useState } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import { StatusBadge, type StatusTone } from "../../../../../../components/ui/status-badge.tsx";
import { EmptyState } from "../../../../../../components/ui/empty-state.tsx";
import type { AttendancePolicyRow, LocationEnforcementMode } from "../../../../../../server/contracts/attendance/attendance.ts";
import type { PolicyActionState } from "./actions.ts";

type BoundAction = (prevState: PolicyActionState, formData: FormData) => Promise<PolicyActionState>;

const INITIAL_STATE: PolicyActionState = { error: null };
const STATUS_TONE: Record<string, StatusTone> = { draft: "neutral", published: "success", archived: "neutral" };

function CreatePolicyForm({ createPolicyAction }: { createPolicyAction: BoundAction }) {
  const [state, formAction, pending] = useActionState(createPolicyAction, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-wrap items-end gap-2 rounded-md border border-neutral-200 p-4">
      <label className="text-xs text-neutral-500">
        Policy name
        <input name="name" required className="mt-1 rounded border border-neutral-300 p-2 text-sm" placeholder="e.g. Jakarta Warehouse" />
      </label>
      <label className="text-xs text-neutral-500">
        Org unit id (optional -- blank = tenant-wide)
        <input name="orgUnitId" className="mt-1 rounded border border-neutral-300 p-2 text-sm" placeholder="org_unit UUID" />
      </label>
      <Button type="submit" variant="primary" loading={pending} loadingLabel="Creating…">
        Create policy
      </Button>
      {state.error ? <p role="alert" className="text-xs text-danger">{state.error}</p> : null}
    </form>
  );
}

function CreateVersionForm({ policyId, createAndPublishVersionAction }: { policyId: string; createAndPublishVersionAction: BoundAction }) {
  const [state, formAction, pending] = useActionState(createAndPublishVersionAction, INITIAL_STATE);
  const [mode, setMode] = useState<LocationEnforcementMode>("none");

  return (
    <form action={formAction} className="mt-2 grid grid-cols-1 gap-2 rounded-md bg-neutral-50 p-3 sm:grid-cols-2">
      <label className="text-xs text-neutral-500">
        Timezone (IANA)
        <input name="timezone" required defaultValue="Asia/Jakarta" className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" />
      </label>
      <label className="text-xs text-neutral-500">
        Effective from
        <input type="date" name="effectiveFrom" required className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" />
      </label>
      <label className="text-xs text-neutral-500">
        Workday start
        <input type="time" name="workdayStartTime" defaultValue="08:00" className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" />
      </label>
      <label className="text-xs text-neutral-500">
        Workday end
        <input type="time" name="workdayEndTime" defaultValue="17:00" className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" />
      </label>
      <label className="text-xs text-neutral-500">
        Day boundary (overnight-shift cutover)
        <input type="time" name="dayBoundaryLocalTime" defaultValue="00:00" className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" />
      </label>
      <label className="text-xs text-neutral-500">
        Max session hours
        <input type="number" name="maxSessionHours" min="1" max="48" defaultValue="16" className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" />
      </label>
      <label className="text-xs text-neutral-500">
        Grace (late, minutes)
        <input type="number" name="graceLateMinutes" min="0" max="240" defaultValue="15" className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" />
      </label>
      <label className="text-xs text-neutral-500">
        Grace (early leave, minutes)
        <input type="number" name="graceEarlyMinutes" min="0" max="240" defaultValue="15" className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" />
      </label>
      <fieldset className="text-xs text-neutral-500 sm:col-span-2">
        <legend>Allowed channels</legend>
        <label className="mr-3 inline-flex items-center gap-1">
          <input type="checkbox" name="allowedChannels" value="mobile_web" defaultChecked /> Mobile web
        </label>
        <label className="mr-3 inline-flex items-center gap-1">
          <input type="checkbox" name="allowedChannels" value="kiosk" defaultChecked /> Kiosk
        </label>
        <label className="inline-flex items-center gap-1">
          <input type="checkbox" name="allowedChannels" value="device_import" /> Device import
        </label>
      </fieldset>
      <label className="text-xs text-neutral-500 sm:col-span-2">
        Location enforcement
        <select name="locationEnforcementMode" value={mode} onChange={(e) => setMode(e.target.value as LocationEnforcementMode)} className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm">
          <option value="none">None -- no geofence</option>
          <option value="advisory">Advisory -- flagged if outside, never blocked</option>
          <option value="required">Required -- rejected if outside or missing</option>
        </select>
      </label>
      {mode !== "none" ? (
        <>
          <label className="text-xs text-neutral-500">
            Geofence center latitude
            <input type="number" step="any" name="geofenceLat" required className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" />
          </label>
          <label className="text-xs text-neutral-500">
            Geofence center longitude
            <input type="number" step="any" name="geofenceLon" required className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" />
          </label>
          <label className="text-xs text-neutral-500 sm:col-span-2">
            Geofence radius (meters)
            <input type="number" name="geofenceRadiusMeters" required min="1" max="500000" className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" />
          </label>
        </>
      ) : null}
      <input type="hidden" name="policyId" value={policyId} />
      <div className="sm:col-span-2">
        <Button type="submit" variant="primary" loading={pending} loadingLabel="Creating and publishing…">
          Create and publish version
        </Button>
      </div>
      {state.error ? <p role="alert" className="text-xs text-danger sm:col-span-2">{state.error}</p> : null}
    </form>
  );
}

export function PolicyListPanel({
  policies,
  createPolicyAction,
  createAndPublishVersionAction,
}: {
  policies: AttendancePolicyRow[];
  createPolicyAction: BoundAction;
  createAndPublishVersionAction: (policyId: string) => BoundAction;
}) {
  const [expanded, setExpanded] = useState<string | null>(null);

  return (
    <div className="flex flex-col gap-4">
      <h1 className="text-xl font-semibold text-neutral-900">Attendance policies</h1>
      <CreatePolicyForm createPolicyAction={createPolicyAction} />

      {policies.length === 0 ? (
        <EmptyState title="No attendance policies yet" description="Create one above -- no employee can clock in until a published policy applies to them." />
      ) : (
        <ul className="flex flex-col gap-2">
          {policies.map((p) => (
            <li key={p.id} className="rounded-md border border-neutral-200 p-3">
              <div className="flex items-center justify-between">
                <span className="text-sm font-medium">{p.name}</span>
                <StatusBadge tone={STATUS_TONE[p.status] ?? "neutral"} label={p.status} />
              </div>
              <p className="text-xs text-neutral-500">{p.orgUnitId ? `Scoped to org unit ${p.orgUnitId}` : "Tenant-wide"} — published version: {p.publishedVersionNumber ?? "none yet"}</p>
              <Button type="button" variant="secondary" onClick={() => setExpanded(expanded === p.id ? null : p.id)} className="mt-2">
                {expanded === p.id ? "Cancel" : "Add version"}
              </Button>
              {expanded === p.id ? <CreateVersionForm policyId={p.id} createAndPublishVersionAction={createAndPublishVersionAction(p.id)} /> : null}
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
