"use client";

import { useActionState, useId } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import { Checkbox } from "../../../../../../components/forms/checkbox.tsx";
import { FormField } from "../../../../../../components/forms/form-field.tsx";
import { Input } from "../../../../../../components/forms/input.tsx";
import { NumberInput } from "../../../../../../components/forms/number-input.tsx";
import { Select } from "../../../../../../components/forms/select.tsx";
import { ValidationMessage } from "../../../../../../components/forms/validation-message.tsx";
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

function SourceSelect({ id, name, invalid, describedBy }: { id: string; name: string; invalid: boolean; describedBy: string | undefined }) {
  return (
    <FormField id={id} label="Source">
      <Select id={id} name={name} required defaultValue="" invalid={invalid} aria-describedby={describedBy}>
        <option value="" disabled>
          Source…
        </option>
        {TRACKING_SOURCE_TYPES.map((source) => (
          <option key={source} value={source}>
            {source}
          </option>
        ))}
      </Select>
    </FormField>
  );
}

function PolicyForm({ action, existing }: { action: MileTrackingFormAction; existing: ShipmentLegTrackingPolicy | null }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  // This panel renders once per leg, so every id must be leg-unique.
  const formId = useId();
  const errorId = `${formId}-error`;
  const describedBy = state.error ? errorId : undefined;
  return (
    <form action={formAction} className="flex flex-col gap-2 border-t border-neutral-200 pt-2 text-xs" noValidate>
      <Checkbox
        id={`${formId}-tracking-required`}
        name="trackingRequired"
        defaultChecked={existing?.trackingRequired ?? false}
        label="Tracking required"
        aria-describedby={describedBy}
      />
      <fieldset>
        <legend className="text-sm font-medium text-text-primary">Allowed sources</legend>
        <div className="flex flex-wrap gap-2">
          {TRACKING_SOURCE_TYPES.map((source) => (
            <Checkbox
              key={source}
              id={`${formId}-allowed-source-${source}`}
              name="allowedSources"
              value={source}
              defaultChecked={existing?.allowedSources.includes(source) ?? false}
              label={source}
              aria-describedby={describedBy}
            />
          ))}
        </div>
      </fieldset>
      <div className="flex flex-wrap items-end gap-2">
        <FormField id={`${formId}-preferred-source`} label="Preferred source">
          <Select
            id={`${formId}-preferred-source`}
            name="preferredSource"
            defaultValue={existing?.preferredSource ?? ""}
            invalid={Boolean(state.error)}
            aria-describedby={describedBy}
          >
            <option value="">Preferred source…</option>
            {TRACKING_SOURCE_TYPES.map((source) => (
              <option key={source} value={source}>
                {source}
              </option>
            ))}
          </Select>
        </FormField>
        <FormField id={`${formId}-start-trigger`} label="Start trigger">
          <Select
            id={`${formId}-start-trigger`}
            name="startTrigger"
            defaultValue={existing?.startTrigger ?? "leg_dispatch"}
            invalid={Boolean(state.error)}
            aria-describedby={describedBy}
          >
            {TRACKING_START_TRIGGERS.map((trigger) => (
              <option key={trigger} value={trigger}>
                start: {trigger}
              </option>
            ))}
          </Select>
        </FormField>
        <FormField id={`${formId}-end-trigger`} label="End trigger">
          <Select
            id={`${formId}-end-trigger`}
            name="endTrigger"
            defaultValue={existing?.endTrigger ?? "leg_complete"}
            invalid={Boolean(state.error)}
            aria-describedby={describedBy}
          >
            {TRACKING_END_TRIGGERS.map((trigger) => (
              <option key={trigger} value={trigger}>
                end: {trigger}
              </option>
            ))}
          </Select>
        </FormField>
        <FormField id={`${formId}-no-signal-escalation-seconds`} label="No-signal escalation (s)">
          <NumberInput
            id={`${formId}-no-signal-escalation-seconds`}
            name="noSignalEscalationSeconds"
            min={1}
            placeholder="No-signal escalation (s)"
            defaultValue={existing?.noSignalEscalationSeconds ?? ""}
            className="w-48"
            invalid={Boolean(state.error)}
            aria-describedby={describedBy}
          />
        </FormField>
        <Checkbox
          id={`${formId}-customer-visible`}
          name="customerVisible"
          defaultChecked={existing?.customerVisible ?? false}
          label="Customer visible"
          aria-describedby={describedBy}
        />
      </div>
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Saving…" className="w-fit">
        {existing ? "Update policy" : "Define policy"}
      </Button>
      {state.error ? <ValidationMessage id={errorId}>{state.error}</ValidationMessage> : null}
    </form>
  );
}

function StartForm({ action }: { action: MileTrackingFormAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  // This panel renders once per leg, so every id must be leg-unique.
  const formId = useId();
  const errorId = `${formId}-error`;
  const describedBy = state.error ? errorId : undefined;
  return (
    <form action={formAction} className="flex flex-wrap items-end gap-2 text-xs" noValidate>
      <SourceSelect id={`${formId}-source-type`} name="sourceType" invalid={Boolean(state.error)} describedBy={describedBy} />
      <FormField id={`${formId}-resource-kind`} label="Resource kind">
        <Select id={`${formId}-resource-kind`} name="resourceKind" required defaultValue="" invalid={Boolean(state.error)} aria-describedby={describedBy}>
          <option value="" disabled>
            Resource kind…
          </option>
          <option value="vehicle">vehicle</option>
          <option value="driver">driver</option>
        </Select>
      </FormField>
      <FormField id={`${formId}-resource-master-id`} label="Resource master ID">
        <Input
          id={`${formId}-resource-master-id`}
          name="resourceMasterId"
          type="text"
          required
          placeholder="Resource master ID"
          invalid={Boolean(state.error)}
          aria-describedby={describedBy}
        />
      </FormField>
      <FormField id={`${formId}-device-id`} label="Device ID">
        <Input
          id={`${formId}-device-id`}
          name="deviceId"
          type="text"
          placeholder="Device ID (direct_device only)"
          invalid={Boolean(state.error)}
          aria-describedby={describedBy}
        />
      </FormField>
      <Button type="submit" variant="primary" loading={pending} loadingLabel="Starting…" className="w-fit">
        Start tracking session
      </Button>
      {state.error ? (
        <div className="basis-full">
          <ValidationMessage id={errorId}>{state.error}</ValidationMessage>
        </div>
      ) : null}
    </form>
  );
}

function HandoffForm({ action }: { action: MileTrackingFormAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  // This panel renders once per leg, so every id must be leg-unique.
  const formId = useId();
  const errorId = `${formId}-error`;
  const describedBy = state.error ? errorId : undefined;
  return (
    <form action={formAction} className="flex flex-wrap items-end gap-2 text-xs" noValidate>
      <SourceSelect id={`${formId}-source-type`} name="sourceType" invalid={Boolean(state.error)} describedBy={describedBy} />
      <FormField id={`${formId}-resource-kind`} label="Resource kind">
        <Select id={`${formId}-resource-kind`} name="resourceKind" required defaultValue="" invalid={Boolean(state.error)} aria-describedby={describedBy}>
          <option value="" disabled>
            Resource kind…
          </option>
          <option value="vehicle">vehicle</option>
          <option value="driver">driver</option>
        </Select>
      </FormField>
      <FormField id={`${formId}-resource-master-id`} label="Resource master ID">
        <Input
          id={`${formId}-resource-master-id`}
          name="resourceMasterId"
          type="text"
          required
          placeholder="Resource master ID"
          invalid={Boolean(state.error)}
          aria-describedby={describedBy}
        />
      </FormField>
      <FormField id={`${formId}-device-id`} label="Device ID">
        <Input
          id={`${formId}-device-id`}
          name="deviceId"
          type="text"
          placeholder="Device ID (direct_device only)"
          invalid={Boolean(state.error)}
          aria-describedby={describedBy}
        />
      </FormField>
      <FormField id={`${formId}-handoff-reason`} label="Handoff reason">
        <Input
          id={`${formId}-handoff-reason`}
          name="handoffReason"
          type="text"
          required
          placeholder="Handoff reason"
          invalid={Boolean(state.error)}
          aria-describedby={describedBy}
        />
      </FormField>
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Handing off…" className="w-fit">
        Hand off source
      </Button>
      {state.error ? (
        <div className="basis-full">
          <ValidationMessage id={errorId}>{state.error}</ValidationMessage>
        </div>
      ) : null}
    </form>
  );
}

function EndForm({ action }: { action: MileTrackingFormAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  // This panel renders once per leg, so every id must be leg-unique.
  const formId = useId();
  const errorId = `${formId}-error`;
  const describedBy = state.error ? errorId : undefined;
  return (
    <form action={formAction} className="flex flex-wrap items-end gap-2 text-xs" noValidate>
      <FormField id={`${formId}-end-reason`} label="End reason">
        <Select id={`${formId}-end-reason`} name="endReason" required defaultValue="leg_completed" invalid={Boolean(state.error)} aria-describedby={describedBy}>
          <option value="leg_completed">leg_completed</option>
          <option value="manual_stop">manual_stop</option>
          <option value="unauthorized_override">unauthorized_override (requires OPS:Override)</option>
        </Select>
      </FormField>
      <FormField id={`${formId}-reason-note`} label="Reason note">
        <Input
          id={`${formId}-reason-note`}
          name="reasonNote"
          type="text"
          placeholder="Reason (required for manual_stop/override)"
          invalid={Boolean(state.error)}
          aria-describedby={describedBy}
        />
      </FormField>
      <Button type="submit" variant="destructive" loading={pending} loadingLabel="Ending…" className="w-fit">
        End session
      </Button>
      {state.error ? (
        <div className="basis-full">
          <ValidationMessage id={errorId}>{state.error}</ValidationMessage>
        </div>
      ) : null}
    </form>
  );
}

function EvaluateEscalationForm({ action }: { action: MileTrackingFormAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  // This panel renders once per leg, so the error id must be leg-unique.
  const formId = useId();
  return (
    <form action={formAction} className="flex flex-col items-start gap-1 text-xs" noValidate>
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Checking…" className="w-fit">
        Check no-signal escalation
      </Button>
      <p className="text-neutral-500">No live poller runs this automatically yet -- this button is the manual stand-in.</p>
      {state.error ? <ValidationMessage id={`${formId}-error`}>{state.error}</ValidationMessage> : null}
    </form>
  );
}
