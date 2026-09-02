"use client";

import { useActionState } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
import { Input } from "../../../../../components/forms/input.tsx";
import { Textarea } from "../../../../../components/forms/textarea.tsx";
import { PasswordInput } from "../../../../../components/forms/password-input.tsx";
import { FormField } from "../../../../../components/forms/form-field.tsx";
import { ValidationMessage } from "../../../../../components/forms/validation-message.tsx";
import { StatusBadge, type StatusTone } from "../../../../../components/ui/status-badge.tsx";
import { EmptyState } from "../../../../../components/ui/empty-state.tsx";
import type { IntegrationHubActionState } from "../actions.ts";
import type { IntegrationConnection, IntegrationHealthCheck, IntegrationConnectionStatus, IntegrationHealthStatus } from "../../../../../server/contracts/integration-hub/integration-hub.ts";

const OK: IntegrationHubActionState = { error: null };

const STATUS_TONE: Record<IntegrationConnectionStatus, StatusTone> = {
  active: "success",
  disabled: "danger",
  testing: "warning",
};

const HEALTH_TONE: Record<IntegrationHealthStatus, StatusTone> = {
  healthy: "success",
  unhealthy: "danger",
};

function ConfigEditor({ connection, updateConfigAction }: { connection: IntegrationConnection; updateConfigAction: (prevState: IntegrationHubActionState, formData: FormData) => Promise<IntegrationHubActionState> }) {
  const [state, formAction, pending] = useActionState(updateConfigAction, OK);
  const describedBy = state.error ? "integration-config-error" : undefined;

  return (
    <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
      <h2 className="text-sm font-semibold text-neutral-900">Configuration</h2>
      <form action={formAction} className="grid grid-cols-1 gap-3 sm:grid-cols-2">
        <FormField id="ownerTeam" label="Owner team">
          <Input id="ownerTeam" name="ownerTeam" type="text" defaultValue={connection.ownerTeam ?? ""} invalid={Boolean(state.error)} aria-describedby={describedBy} />
        </FormField>
        <FormField id="ownerEmail" label="Owner email">
          <Input id="ownerEmail" name="ownerEmail" type="email" defaultValue={connection.ownerEmail ?? ""} invalid={Boolean(state.error)} aria-describedby={describedBy} />
        </FormField>
        <div className="col-span-full">
          <FormField id="runbookUrl" label="Runbook URL">
            <Input id="runbookUrl" name="runbookUrl" type="url" defaultValue={connection.runbookUrl ?? ""} invalid={Boolean(state.error)} aria-describedby={describedBy} />
          </FormField>
        </div>
        <div className="col-span-full">
          <FormField id="config" label="Non-secret config (JSON object)">
            <Textarea
              id="config"
              name="config"
              rows={3}
              defaultValue={JSON.stringify(connection.config, null, 2)}
              className="font-mono"
              invalid={Boolean(state.error)}
              aria-describedby={describedBy}
            />
          </FormField>
        </div>

        {state.error ? (
          <div className="col-span-full">
            <ValidationMessage id="integration-config-error">{state.error}</ValidationMessage>
          </div>
        ) : null}

        <div className="col-span-full">
          <Button type="submit" loading={pending} loadingLabel="Saving…">
            Save
          </Button>
        </div>
      </form>
    </section>
  );
}

function CredentialRotation({ rotateCredentialAction }: { rotateCredentialAction: (prevState: IntegrationHubActionState, formData: FormData) => Promise<IntegrationHubActionState> }) {
  const [state, formAction, pending] = useActionState(rotateCredentialAction, OK);

  return (
    <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
      <h2 className="text-sm font-semibold text-neutral-900">Credential</h2>
      <p className="text-xs text-neutral-500">The current credential value is never displayed here or anywhere -- it lives in a fully isolated table no session can read directly. Rotating replaces it with a new value you supply.</p>
      <form action={formAction} className="flex flex-col gap-2">
        <FormField id="newCredentialValue" label="New credential value">
          <PasswordInput
            id="newCredentialValue"
            name="newCredentialValue"
            autoComplete="off"
            required
            invalid={Boolean(state.error)}
            aria-describedby={state.error ? "integration-credential-error" : undefined}
          />
        </FormField>

        {state.error ? <ValidationMessage id="integration-credential-error">{state.error}</ValidationMessage> : null}

        <div>
          <Button type="submit" variant="secondary" loading={pending} loadingLabel="Rotating…">
            Rotate credential
          </Button>
        </div>
      </form>
    </section>
  );
}

function HealthCheckAction({ status, recordHealthCheckActionFor }: { status: IntegrationHealthStatus; recordHealthCheckActionFor: (status: IntegrationHealthStatus) => (prevState: IntegrationHubActionState, formData: FormData) => Promise<IntegrationHubActionState> }) {
  const [state, formAction, pending] = useActionState(recordHealthCheckActionFor(status), OK);
  const detailId = `health-check-detail-${status}`;
  const errorId = `health-check-${status}-error`;

  return (
    <form action={formAction} className="flex flex-col gap-1">
      <div className="flex items-center gap-2">
        {/* Two of these forms sit side by side, so the id is status-scoped; the label is
            screen-reader-only because the inline placeholder is the visible affordance. */}
        <FormField id={detailId} label={<span className="sr-only">Detail for the {status} health check</span>}>
          <Input id={detailId} name="detail" type="text" placeholder="Detail (optional)" invalid={Boolean(state.error)} aria-describedby={state.error ? errorId : undefined} />
        </FormField>
        <Button type="submit" variant={status === "healthy" ? "primary" : "destructive"} loading={pending} loadingLabel="Recording…">
          Record {status}
        </Button>
      </div>
      {state.error ? <ValidationMessage id={errorId}>{state.error}</ValidationMessage> : null}
    </form>
  );
}

function StatusControls({ connection, setStatusActionFor }: { connection: IntegrationConnection; setStatusActionFor: (status: IntegrationConnectionStatus) => (prevState: IntegrationHubActionState, formData: FormData) => Promise<IntegrationHubActionState> }) {
  const [activeState, activeFormAction, activePending] = useActionState(setStatusActionFor("active"), OK);
  const [disabledState, disabledFormAction, disabledPending] = useActionState(setStatusActionFor("disabled"), OK);

  return (
    <section className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
      <h2 className="text-sm font-semibold text-neutral-900">Status</h2>
      <p className="text-xs text-neutral-500">Disabling stops this connection from being used while preserving every real health-check row it already has.</p>
      <div className="flex flex-wrap gap-2">
        <form action={activeFormAction}>
          <Button type="submit" loading={activePending} loadingLabel="Enabling…" disabled={connection.status === "active"}>
            Enable
          </Button>
        </form>
        <form action={disabledFormAction} className="flex items-center gap-2">
          <FormField id="integration-disable-reason" label={<span className="sr-only">Reason for disabling this connection</span>}>
            <Input
              id="integration-disable-reason"
              name="reason"
              type="text"
              placeholder="Reason (optional)"
              invalid={Boolean(disabledState.error)}
              aria-describedby={disabledState.error ? "integration-disable-error" : undefined}
            />
          </FormField>
          <Button type="submit" variant="destructive" loading={disabledPending} loadingLabel="Disabling…" disabled={connection.status === "disabled"}>
            Disable
          </Button>
        </form>
      </div>
      {activeState.error ? (
        <p role="alert" className="text-sm text-danger">
          {activeState.error}
        </p>
      ) : null}
      {disabledState.error ? <ValidationMessage id="integration-disable-error">{disabledState.error}</ValidationMessage> : null}
    </section>
  );
}

export function IntegrationConnectionDetailPanel({
  connection,
  adapterName,
  healthChecks,
  updateConfigAction,
  rotateCredentialAction,
  setStatusActionFor,
  recordHealthCheckActionFor,
}: {
  connection: IntegrationConnection;
  adapterName: string;
  healthChecks: readonly IntegrationHealthCheck[];
  updateConfigAction: (prevState: IntegrationHubActionState, formData: FormData) => Promise<IntegrationHubActionState>;
  rotateCredentialAction: (prevState: IntegrationHubActionState, formData: FormData) => Promise<IntegrationHubActionState>;
  setStatusActionFor: (status: IntegrationConnectionStatus) => (prevState: IntegrationHubActionState, formData: FormData) => Promise<IntegrationHubActionState>;
  recordHealthCheckActionFor: (status: IntegrationHealthStatus) => (prevState: IntegrationHubActionState, formData: FormData) => Promise<IntegrationHubActionState>;
}) {
  return (
    <div className="flex flex-col gap-4">
      <div className="flex items-center gap-2">
        <h1 className="text-xl font-semibold text-neutral-900">{connection.name}</h1>
        <StatusBadge tone={STATUS_TONE[connection.status]} label={connection.status} />
      </div>
      <p className="text-sm text-neutral-600">
        {adapterName} · {connection.environment}
      </p>
      {connection.autoDisabledAt ? <p className="text-xs text-danger">Auto-disabled at {connection.autoDisabledAt}: {connection.disabledReason}</p> : null}

      <ConfigEditor connection={connection} updateConfigAction={updateConfigAction} />
      <CredentialRotation rotateCredentialAction={rotateCredentialAction} />
      <StatusControls connection={connection} setStatusActionFor={setStatusActionFor} />

      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Test connection</h2>
        <div className="flex gap-4">
          <HealthCheckAction status="healthy" recordHealthCheckActionFor={recordHealthCheckActionFor} />
          <HealthCheckAction status="unhealthy" recordHealthCheckActionFor={recordHealthCheckActionFor} />
        </div>
      </section>

      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Health-check history</h2>
        {healthChecks.length === 0 ? (
          <EmptyState title="No health checks yet" description="Run a test above to record the first one." />
        ) : (
          <div className="overflow-x-auto">
          <table className="w-full min-w-[420px] text-sm">
            <thead>
              <tr className="text-left text-xs text-neutral-500">
                <th className="pb-1">Checked</th>
                <th className="pb-1">Status</th>
                <th className="pb-1">Detail</th>
              </tr>
            </thead>
            <tbody>
              {healthChecks.map((h) => (
                <tr key={h.id} className="border-t border-neutral-100">
                  <td className="py-1">{h.checkedAt}</td>
                  <td className="py-1">
                    <StatusBadge tone={HEALTH_TONE[h.status]} label={h.status} />
                  </td>
                  <td className="py-1 text-xs">{h.detail ?? "—"}</td>
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
