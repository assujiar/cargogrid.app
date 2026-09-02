"use client";

import { useActionState } from "react";
import Link from "next/link";
import { Button } from "../../../../components/ui/button.tsx";
import { Input } from "../../../../components/forms/input.tsx";
import { Select } from "../../../../components/forms/select.tsx";
import { Textarea } from "../../../../components/forms/textarea.tsx";
import { PasswordInput } from "../../../../components/forms/password-input.tsx";
import { FormField } from "../../../../components/forms/form-field.tsx";
import { ValidationMessage } from "../../../../components/forms/validation-message.tsx";
import { StatusBadge, type StatusTone } from "../../../../components/ui/status-badge.tsx";
import { EmptyState } from "../../../../components/ui/empty-state.tsx";
import type { IntegrationHubActionState } from "./actions.ts";
import type { IntegrationAdapter, IntegrationConnection, IntegrationConnectionStatus } from "../../../../server/contracts/integration-hub/integration-hub.ts";

const INITIAL_STATE: IntegrationHubActionState = { error: null };

const STATUS_TONE: Record<IntegrationConnectionStatus, StatusTone> = {
  active: "success",
  disabled: "danger",
  testing: "warning",
};

export function IntegrationHubManagementPanel({
  tenantSlug,
  adapters,
  connections,
  createAction,
}: {
  tenantSlug: string;
  adapters: readonly IntegrationAdapter[];
  connections: readonly IntegrationConnection[];
  createAction: (prevState: IntegrationHubActionState, formData: FormData) => Promise<IntegrationHubActionState>;
}) {
  const [state, formAction, pending] = useActionState(createAction, INITIAL_STATE);
  const describedBy = state.error ? "connect-adapter-error" : undefined;

  return (
    <div className="flex flex-col gap-4">
      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Adapter catalog</h2>
        {adapters.length === 0 ? (
          <EmptyState title="No adapters registered yet" description="A Supreme Admin registers adapter types before a tenant can connect to one." />
        ) : (
          <ul className="flex flex-col gap-1 text-sm">
            {adapters.map((a) => (
              <li key={a.code} className="flex justify-between border-t border-neutral-100 py-1 first:border-t-0">
                <span>{a.name}</span>
                <span className="text-xs text-neutral-500">{a.category}</span>
              </li>
            ))}
          </ul>
        )}
      </section>

      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Your connections</h2>
        {connections.length === 0 ? (
          <EmptyState title="No connections yet" description="Connect an adapter below." />
        ) : (
          <div className="overflow-x-auto">
          <table className="w-full min-w-[560px] text-sm">
            <thead>
              <tr className="text-left text-xs text-neutral-500">
                <th className="pb-1">Name</th>
                <th className="pb-1">Adapter</th>
                <th className="pb-1">Environment</th>
                <th className="pb-1">Status</th>
                <th className="pb-1">Owner</th>
              </tr>
            </thead>
            <tbody>
              {connections.map((c) => (
                <tr key={c.id} className="border-t border-neutral-100">
                  <td className="py-1">
                    <Link href={`/${tenantSlug}/integrations/${c.id}`} className="text-primary underline">
                      {c.name}
                    </Link>
                  </td>
                  <td className="py-1">{adapters.find((a) => a.code === c.adapterCode)?.name ?? c.adapterCode}</td>
                  <td className="py-1">{c.environment}</td>
                  <td className="py-1">
                    <StatusBadge tone={STATUS_TONE[c.status]} label={c.status} />
                  </td>
                  <td className="py-1">{c.ownerTeam ?? "—"}</td>
                </tr>
              ))}
            </tbody>
          </table>
          </div>
        )}
      </section>

      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Connect an adapter</h2>
        <form action={formAction} className="grid grid-cols-1 gap-3 sm:grid-cols-2">
          <FormField id="adapterCode" label="Adapter">
            <Select id="adapterCode" name="adapterCode" required invalid={Boolean(state.error)} aria-describedby={describedBy}>
              <option value="">Select an adapter…</option>
              {adapters.map((a) => (
                <option key={a.code} value={a.code}>
                  {a.name}
                </option>
              ))}
            </Select>
          </FormField>
          <FormField id="name" label="Connection name">
            <Input id="name" name="name" type="text" required invalid={Boolean(state.error)} aria-describedby={describedBy} />
          </FormField>
          <FormField id="environment" label="Environment">
            <Select id="environment" name="environment" defaultValue="production" invalid={Boolean(state.error)} aria-describedby={describedBy}>
              <option value="production">Production</option>
              <option value="sandbox">Sandbox</option>
            </Select>
          </FormField>
          <FormField id="credentialValue" label="Credential (API key/token)">
            <PasswordInput id="credentialValue" name="credentialValue" required autoComplete="off" invalid={Boolean(state.error)} aria-describedby={describedBy} />
          </FormField>
          <FormField id="ownerTeam" label="Owner team (optional)">
            <Input id="ownerTeam" name="ownerTeam" type="text" invalid={Boolean(state.error)} aria-describedby={describedBy} />
          </FormField>
          <FormField id="ownerEmail" label="Owner email (optional)">
            <Input id="ownerEmail" name="ownerEmail" type="email" invalid={Boolean(state.error)} aria-describedby={describedBy} />
          </FormField>
          <div className="col-span-full">
            <FormField id="runbookUrl" label="Runbook URL (optional)">
              <Input id="runbookUrl" name="runbookUrl" type="url" invalid={Boolean(state.error)} aria-describedby={describedBy} />
            </FormField>
          </div>
          <div className="col-span-full">
            <FormField id="config" label="Non-secret config (JSON object, e.g. base URL, toggles)">
              <Textarea id="config" name="config" rows={2} placeholder="{}" className="font-mono" invalid={Boolean(state.error)} aria-describedby={describedBy} />
            </FormField>
          </div>

          {state.error ? (
            <div className="col-span-full">
              <ValidationMessage id="connect-adapter-error">{state.error}</ValidationMessage>
            </div>
          ) : null}

          <div className="col-span-full">
            <Button type="submit" loading={pending} loadingLabel="Connecting…">
              Connect
            </Button>
          </div>
        </form>
      </section>
    </div>
  );
}
