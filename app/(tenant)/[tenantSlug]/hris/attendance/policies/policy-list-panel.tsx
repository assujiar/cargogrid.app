"use client";

import { useActionState, useState } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import { Input } from "../../../../../../components/forms/input.tsx";
import { Select } from "../../../../../../components/forms/select.tsx";
import { Checkbox } from "../../../../../../components/forms/checkbox.tsx";
import { FormField } from "../../../../../../components/forms/form-field.tsx";
import { ValidationMessage } from "../../../../../../components/forms/validation-message.tsx";
import { StatusBadge, type StatusTone } from "../../../../../../components/ui/status-badge.tsx";
import { EmptyState } from "../../../../../../components/ui/empty-state.tsx";
import type { AttendancePolicyRow, LocationEnforcementMode } from "../../../../../../server/contracts/attendance/attendance.ts";
import type { PolicyActionState } from "./actions.ts";

type BoundAction = (prevState: PolicyActionState, formData: FormData) => Promise<PolicyActionState>;

const INITIAL_STATE: PolicyActionState = { error: null };
const STATUS_TONE: Record<string, StatusTone> = { draft: "neutral", published: "success", archived: "neutral" };

function CreatePolicyForm({ createPolicyAction }: { createPolicyAction: BoundAction }) {
  const [state, formAction, pending] = useActionState(createPolicyAction, INITIAL_STATE);
  const describedBy = state.error ? "create-attendance-policy-error" : undefined;
  return (
    <form action={formAction} className="flex flex-wrap items-end gap-2 rounded-md border border-neutral-200 p-4" noValidate>
      <FormField id="attendance-policy-name" label="Policy name">
        <Input id="attendance-policy-name" name="name" required placeholder="e.g. Jakarta Warehouse" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <FormField id="attendance-policy-org-unit" label="Org unit id (optional -- blank = tenant-wide)">
        <Input id="attendance-policy-org-unit" name="orgUnitId" placeholder="org_unit UUID" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <Button type="submit" variant="primary" loading={pending} loadingLabel="Creating…">
        Create policy
      </Button>
      {state.error ? <ValidationMessage id="create-attendance-policy-error">{state.error}</ValidationMessage> : null}
    </form>
  );
}

function CreateVersionForm({ policyId, createAndPublishVersionAction }: { policyId: string; createAndPublishVersionAction: BoundAction }) {
  const [state, formAction, pending] = useActionState(createAndPublishVersionAction, INITIAL_STATE);
  const [mode, setMode] = useState<LocationEnforcementMode>("none");
  const describedBy = state.error ? `create-attendance-version-${policyId}-error` : undefined;

  return (
    <form action={formAction} className="mt-2 grid grid-cols-1 gap-2 rounded-md bg-neutral-50 p-3 sm:grid-cols-2" noValidate>
      <FormField id={`av-timezone-${policyId}`} label="Timezone (IANA)">
        <Input id={`av-timezone-${policyId}`} name="timezone" required defaultValue="Asia/Jakarta" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <FormField id={`av-effective-from-${policyId}`} label="Effective from">
        <Input id={`av-effective-from-${policyId}`} type="date" name="effectiveFrom" required invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <FormField id={`av-workday-start-${policyId}`} label="Workday start">
        <Input id={`av-workday-start-${policyId}`} type="time" name="workdayStartTime" defaultValue="08:00" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <FormField id={`av-workday-end-${policyId}`} label="Workday end">
        <Input id={`av-workday-end-${policyId}`} type="time" name="workdayEndTime" defaultValue="17:00" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <FormField id={`av-day-boundary-${policyId}`} label="Day boundary (overnight-shift cutover)">
        <Input id={`av-day-boundary-${policyId}`} type="time" name="dayBoundaryLocalTime" defaultValue="00:00" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <FormField id={`av-max-session-${policyId}`} label="Max session hours">
        <Input id={`av-max-session-${policyId}`} type="number" name="maxSessionHours" min="1" max="48" defaultValue="16" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <FormField id={`av-grace-late-${policyId}`} label="Grace (late, minutes)">
        <Input id={`av-grace-late-${policyId}`} type="number" name="graceLateMinutes" min="0" max="240" defaultValue="15" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <FormField id={`av-grace-early-${policyId}`} label="Grace (early leave, minutes)">
        <Input id={`av-grace-early-${policyId}`} type="number" name="graceEarlyMinutes" min="0" max="240" defaultValue="15" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <fieldset className="text-xs text-neutral-500 sm:col-span-2">
        <legend>Allowed channels</legend>
        <div className="flex flex-wrap gap-3">
          <Checkbox id={`av-channel-mobile-${policyId}`} name="allowedChannels" value="mobile_web" defaultChecked label="Mobile web" aria-describedby={describedBy} />
          <Checkbox id={`av-channel-kiosk-${policyId}`} name="allowedChannels" value="kiosk" defaultChecked label="Kiosk" aria-describedby={describedBy} />
          <Checkbox id={`av-channel-device-${policyId}`} name="allowedChannels" value="device_import" label="Device import" aria-describedby={describedBy} />
        </div>
      </fieldset>
      <div className="sm:col-span-2">
        <FormField id={`av-location-mode-${policyId}`} label="Location enforcement">
          <Select id={`av-location-mode-${policyId}`} name="locationEnforcementMode" value={mode} onChange={(e) => setMode(e.target.value as LocationEnforcementMode)} invalid={Boolean(state.error)} aria-describedby={describedBy}>
            <option value="none">None -- no geofence</option>
            <option value="advisory">Advisory -- flagged if outside, never blocked</option>
            <option value="required">Required -- rejected if outside or missing</option>
          </Select>
        </FormField>
      </div>
      {mode !== "none" ? (
        <>
          <FormField id={`av-geofence-lat-${policyId}`} label="Geofence center latitude">
            <Input id={`av-geofence-lat-${policyId}`} type="number" step="any" name="geofenceLat" required invalid={Boolean(state.error)} aria-describedby={describedBy} />
          </FormField>
          <FormField id={`av-geofence-lon-${policyId}`} label="Geofence center longitude">
            <Input id={`av-geofence-lon-${policyId}`} type="number" step="any" name="geofenceLon" required invalid={Boolean(state.error)} aria-describedby={describedBy} />
          </FormField>
          <div className="sm:col-span-2">
            <FormField id={`av-geofence-radius-${policyId}`} label="Geofence radius (meters)">
              <Input id={`av-geofence-radius-${policyId}`} type="number" name="geofenceRadiusMeters" required min="1" max="500000" invalid={Boolean(state.error)} aria-describedby={describedBy} />
            </FormField>
          </div>
        </>
      ) : null}
      <input type="hidden" name="policyId" value={policyId} />
      <div className="sm:col-span-2">
        <Button type="submit" variant="primary" loading={pending} loadingLabel="Creating and publishing…">
          Create and publish version
        </Button>
      </div>
      {state.error ? (
        <div className="sm:col-span-2">
          <ValidationMessage id={`create-attendance-version-${policyId}-error`}>{state.error}</ValidationMessage>
        </div>
      ) : null}
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
