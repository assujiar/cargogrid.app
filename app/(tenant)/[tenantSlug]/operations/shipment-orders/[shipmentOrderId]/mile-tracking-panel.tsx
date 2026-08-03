"use client";

import { useActionState } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import { StatusBadge, type StatusTone } from "../../../../../../components/ui/status-badge.tsx";
import { Badge } from "../../../../../../components/ui/badge.tsx";
import {
  TRACKING_SOURCE_TYPES,
  TRACKING_START_TRIGGERS,
  TRACKING_END_TRIGGERS,
  type ShipmentLegTrackingPolicy,
  type ShipmentLegTrackingSession,
  type ResolvedLegTrackingPolicy,
} from "../../../../../../server/contracts/mile-orchestration/mile-orchestration.ts";
import type { ShipmentOrderFormState } from "./actions.ts";

const INITIAL_STATE: ShipmentOrderFormState = { error: null };

const SESSION_STATUS_TONE: Record<ShipmentLegTrackingSession["status"], StatusTone> = {
  active: "success",
  ended: "neutral",
};

export type MileTrackingFormAction = (prevState: ShipmentOrderFormState, formData: FormData) => Promise<ShipmentOrderFormState>;

/**
 * ATW-225: the control-tower stage view for one leg -- expected tracking mode
 * (policy), active source (current session), freshness/eligibility
 * resolution, handoff, and no-signal readiness. Tracking entitlement is
 * disclosed, never hidden, alongside eligibility -- see the migration's own
 * header for why it does not gate this panel's own controls.
 */
export function MileTrackingPanel({
  policy,
  resolved,
  currentSession,
  upsertPolicyAction,
  startSessionAction,
  handoffSessionAction,
  endSessionAction,
  evaluateEscalationAction,
}: {
  policy: ShipmentLegTrackingPolicy | null;
  resolved: ResolvedLegTrackingPolicy | null;
  currentSession: ShipmentLegTrackingSession | null;
  upsertPolicyAction: MileTrackingFormAction;
  startSessionAction: MileTrackingFormAction;
  handoffSessionAction: MileTrackingFormAction;
  endSessionAction: MileTrackingFormAction;
  evaluateEscalationAction: MileTrackingFormAction;
}) {
  return (
    <div className="flex flex-col gap-2 rounded-md border border-neutral-100 bg-neutral-50 p-2">
      <div className="flex flex-wrap items-center gap-2">
        <span className="text-xs font-semibold uppercase tracking-wide text-neutral-500">Tracking</span>
        {policy ? (
          <StatusBadge tone={policy.trackingRequired ? "info" : "neutral"} label={policy.trackingRequired ? "required" : "not required"} />
        ) : (
          <span className="text-xs text-neutral-500">No policy defined yet</span>
        )}
        {resolved && !resolved.trackingEntitled ? <span className="text-xs text-neutral-500">Not entitled</span> : null}
      </div>

      {policy ? (
        <dl className="grid grid-cols-2 gap-x-4 gap-y-1 text-xs text-neutral-600">
          <dt>Allowed sources</dt>
          <dd>{policy.allowedSources.length > 0 ? policy.allowedSources.join(", ") : "—"}</dd>
          <dt>Fallback order</dt>
          <dd>{policy.fallbackOrder.length > 0 ? policy.fallbackOrder.join(" → ") : "—"}</dd>
          <dt>No-signal escalation</dt>
          <dd>{policy.noSignalEscalationSeconds ? `${policy.noSignalEscalationSeconds}s` : "—"}</dd>
        </dl>
      ) : null}

      {resolved && policy?.trackingRequired ? (
        <div className="flex flex-wrap items-center gap-2 text-xs text-neutral-600">
          <span>Eligible: {resolved.eligibleSources.length > 0 ? resolved.eligibleSources.join(", ") : "none"}</span>
          {resolved.resolvedSource ? <Badge tone="primary">resolves to {resolved.resolvedSource}</Badge> : null}
          {resolved.blockedReason ? <span className="text-danger">{resolved.blockedReason.replace(/_/g, " ")}</span> : null}
        </div>
      ) : null}

      {currentSession ? (
        <div className="flex flex-wrap items-center gap-2 text-xs text-neutral-700">
          <span className="font-semibold">Active source</span>
          <StatusBadge tone={SESSION_STATUS_TONE[currentSession.status]} label={currentSession.sourceType.replace(/_/g, " ")} />
          <span>since {new Date(currentSession.startedAt).toLocaleString()}</span>
        </div>
      ) : null}

      <PolicyForm action={upsertPolicyAction} existing={policy} />

      {policy?.trackingRequired ? (
        <div className="flex flex-col gap-2 border-t border-neutral-200 pt-2">
          {currentSession ? (
            <>
              <HandoffForm action={handoffSessionAction} />
              <EndForm action={endSessionAction} />
              <EvaluateEscalationForm action={evaluateEscalationAction} />
            </>
          ) : (
            <StartForm action={startSessionAction} />
          )}
        </div>
      ) : null}
    </div>
  );
}

function SourceSelect({ name }: { name: string }) {
  return (
    <select name={name} required defaultValue="" className="rounded-md border border-neutral-300 px-2 py-1.5 text-sm">
      <option value="" disabled>
        Source…
      </option>
      {TRACKING_SOURCE_TYPES.map((source) => (
        <option key={source} value={source}>
          {source}
        </option>
      ))}
    </select>
  );
}

function PolicyForm({ action, existing }: { action: MileTrackingFormAction; existing: ShipmentLegTrackingPolicy | null }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col gap-2 border-t border-neutral-200 pt-2 text-xs" noValidate>
      <label className="flex items-center gap-1">
        <input type="checkbox" name="trackingRequired" defaultChecked={existing?.trackingRequired ?? false} /> Tracking required
      </label>
      <div className="flex flex-wrap gap-2">
        {TRACKING_SOURCE_TYPES.map((source) => (
          <label key={source} className="flex items-center gap-1">
            <input type="checkbox" name="allowedSources" value={source} defaultChecked={existing?.allowedSources.includes(source) ?? false} /> {source}
          </label>
        ))}
      </div>
      <div className="flex flex-wrap items-end gap-2">
        <select name="preferredSource" defaultValue={existing?.preferredSource ?? ""} className="rounded-md border border-neutral-300 px-2 py-1.5 text-sm">
          <option value="">Preferred source…</option>
          {TRACKING_SOURCE_TYPES.map((source) => (
            <option key={source} value={source}>
              {source}
            </option>
          ))}
        </select>
        <select name="startTrigger" defaultValue={existing?.startTrigger ?? "leg_dispatch"} className="rounded-md border border-neutral-300 px-2 py-1.5 text-sm">
          {TRACKING_START_TRIGGERS.map((trigger) => (
            <option key={trigger} value={trigger}>
              start: {trigger}
            </option>
          ))}
        </select>
        <select name="endTrigger" defaultValue={existing?.endTrigger ?? "leg_complete"} className="rounded-md border border-neutral-300 px-2 py-1.5 text-sm">
          {TRACKING_END_TRIGGERS.map((trigger) => (
            <option key={trigger} value={trigger}>
              end: {trigger}
            </option>
          ))}
        </select>
        <input
          name="noSignalEscalationSeconds"
          type="number"
          min={1}
          placeholder="No-signal escalation (s)"
          defaultValue={existing?.noSignalEscalationSeconds ?? ""}
          className="w-48 rounded-md border border-neutral-300 px-2 py-1.5 text-sm"
        />
        <label className="flex items-center gap-1">
          <input type="checkbox" name="customerVisible" defaultChecked={existing?.customerVisible ?? false} /> Customer visible
        </label>
      </div>
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Saving…" className="w-fit">
        {existing ? "Update policy" : "Define policy"}
      </Button>
      {state.error ? (
        <p role="alert" className="text-danger">
          {state.error}
        </p>
      ) : null}
    </form>
  );
}

function StartForm({ action }: { action: MileTrackingFormAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-wrap items-end gap-2 text-xs" noValidate>
      <SourceSelect name="sourceType" />
      <select name="resourceKind" required defaultValue="" className="rounded-md border border-neutral-300 px-2 py-1.5 text-sm">
        <option value="" disabled>
          Resource kind…
        </option>
        <option value="vehicle">vehicle</option>
        <option value="driver">driver</option>
      </select>
      <input name="resourceMasterId" type="text" required placeholder="Resource master ID" className="rounded-md border border-neutral-300 px-2 py-1.5 text-sm" />
      <input name="deviceId" type="text" placeholder="Device ID (direct_device only)" className="rounded-md border border-neutral-300 px-2 py-1.5 text-sm" />
      <Button type="submit" variant="primary" loading={pending} loadingLabel="Starting…" className="w-fit">
        Start tracking session
      </Button>
      {state.error ? (
        <p role="alert" className="basis-full text-danger">
          {state.error}
        </p>
      ) : null}
    </form>
  );
}

function HandoffForm({ action }: { action: MileTrackingFormAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-wrap items-end gap-2 text-xs" noValidate>
      <SourceSelect name="sourceType" />
      <select name="resourceKind" required defaultValue="" className="rounded-md border border-neutral-300 px-2 py-1.5 text-sm">
        <option value="" disabled>
          Resource kind…
        </option>
        <option value="vehicle">vehicle</option>
        <option value="driver">driver</option>
      </select>
      <input name="resourceMasterId" type="text" required placeholder="Resource master ID" className="rounded-md border border-neutral-300 px-2 py-1.5 text-sm" />
      <input name="deviceId" type="text" placeholder="Device ID (direct_device only)" className="rounded-md border border-neutral-300 px-2 py-1.5 text-sm" />
      <input name="handoffReason" type="text" required placeholder="Handoff reason" className="rounded-md border border-neutral-300 px-2 py-1.5 text-sm" />
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Handing off…" className="w-fit">
        Hand off source
      </Button>
      {state.error ? (
        <p role="alert" className="basis-full text-danger">
          {state.error}
        </p>
      ) : null}
    </form>
  );
}

function EndForm({ action }: { action: MileTrackingFormAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-wrap items-end gap-2 text-xs" noValidate>
      <select name="endReason" required defaultValue="leg_completed" className="rounded-md border border-neutral-300 px-2 py-1.5 text-sm">
        <option value="leg_completed">leg_completed</option>
        <option value="manual_stop">manual_stop</option>
        <option value="unauthorized_override">unauthorized_override (requires OPS:Override)</option>
      </select>
      <input name="reasonNote" type="text" placeholder="Reason (required for manual_stop/override)" className="rounded-md border border-neutral-300 px-2 py-1.5 text-sm" />
      <Button type="submit" variant="destructive" loading={pending} loadingLabel="Ending…" className="w-fit">
        End session
      </Button>
      {state.error ? (
        <p role="alert" className="basis-full text-danger">
          {state.error}
        </p>
      ) : null}
    </form>
  );
}

function EvaluateEscalationForm({ action }: { action: MileTrackingFormAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col items-start gap-1 text-xs" noValidate>
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Checking…" className="w-fit">
        Check no-signal escalation
      </Button>
      <p className="text-neutral-500">No live poller runs this automatically yet -- this button is the manual stand-in.</p>
      {state.error ? (
        <p role="alert" className="text-danger">
          {state.error}
        </p>
      ) : null}
    </form>
  );
}
