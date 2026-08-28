"use client";

import { useActionState } from "react";
import Link from "next/link";
import { Button } from "../../../../components/ui/button.tsx";
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
          <div className="flex flex-col gap-1">
            <label htmlFor="adapterCode" className="text-xs font-medium text-neutral-600">
              Adapter
            </label>
            <select id="adapterCode" name="adapterCode" required className="rounded-md border border-neutral-300 px-3 py-1.5 text-sm">
              <option value="">Select an adapter…</option>
              {adapters.map((a) => (
                <option key={a.code} value={a.code}>
                  {a.name}
                </option>
              ))}
            </select>
          </div>
          <div className="flex flex-col gap-1">
            <label htmlFor="name" className="text-xs font-medium text-neutral-600">
              Connection name
            </label>
            <input id="name" name="name" type="text" required className="rounded-md border border-neutral-300 px-3 py-1.5 text-sm" />
          </div>
          <div className="flex flex-col gap-1">
            <label htmlFor="environment" className="text-xs font-medium text-neutral-600">
              Environment
            </label>
            <select id="environment" name="environment" defaultValue="production" className="rounded-md border border-neutral-300 px-3 py-1.5 text-sm">
              <option value="production">Production</option>
              <option value="sandbox">Sandbox</option>
            </select>
          </div>
          <div className="flex flex-col gap-1">
            <label htmlFor="credentialValue" className="text-xs font-medium text-neutral-600">
              Credential (API key/token)
            </label>
            <input id="credentialValue" name="credentialValue" type="password" required autoComplete="off" className="rounded-md border border-neutral-300 px-3 py-1.5 text-sm" />
          </div>
          <div className="flex flex-col gap-1">
            <label htmlFor="ownerTeam" className="text-xs font-medium text-neutral-600">
              Owner team (optional)
            </label>
            <input id="ownerTeam" name="ownerTeam" type="text" className="rounded-md border border-neutral-300 px-3 py-1.5 text-sm" />
          </div>
          <div className="flex flex-col gap-1">
            <label htmlFor="ownerEmail" className="text-xs font-medium text-neutral-600">
              Owner email (optional)
            </label>
            <input id="ownerEmail" name="ownerEmail" type="email" className="rounded-md border border-neutral-300 px-3 py-1.5 text-sm" />
          </div>
          <div className="col-span-full flex flex-col gap-1">
            <label htmlFor="runbookUrl" className="text-xs font-medium text-neutral-600">
              Runbook URL (optional)
            </label>
            <input id="runbookUrl" name="runbookUrl" type="url" className="rounded-md border border-neutral-300 px-3 py-1.5 text-sm" />
          </div>
          <div className="col-span-full flex flex-col gap-1">
            <label htmlFor="config" className="text-xs font-medium text-neutral-600">
              Non-secret config (JSON object, e.g. base URL, toggles)
            </label>
            <textarea id="config" name="config" rows={2} placeholder="{}" className="rounded-md border border-neutral-300 px-3 py-1.5 font-mono text-sm" />
          </div>

          {state.error ? (
            <p role="alert" className="col-span-full text-sm text-danger">
              {state.error}
            </p>
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
