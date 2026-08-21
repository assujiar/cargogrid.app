"use client";

/**
 * Public API Platform developer console client forms (IAE-009, Prompt 337). Same
 * `useActionState`/bound-action split every prior capability's own create-form already
 * uses (e.g. `admin/loyalty/loyalty-admin-panel.tsx`).
 */

import { useActionState } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
import { StatusBadge, type StatusTone } from "../../../../../components/ui/status-badge.tsx";
import { EmptyState } from "../../../../../components/ui/empty-state.tsx";
import type { ApiKey } from "../../../../../server/contracts/api-key-webhook/api-key-webhook.ts";
import type { ApiVersion } from "../../../../../server/contracts/public-api-platform/public-api-platform.ts";
import type { WebhookEventType } from "../../../../../server/contracts/api-key-webhook/api-key-webhook.ts";
import type { ApiLog } from "../../../../../server/contracts/api/api.ts";
import { createApiKeyAction, rotateApiKeyAction, revokeApiKeyAction, type ApiKeyFormState } from "./actions.ts";

const INITIAL_STATE: ApiKeyFormState = { error: null, createdKey: null };

const API_KEY_STATUS_TONE: Record<ApiKey["status"], StatusTone> = { active: "success", revoked: "danger", expired: "neutral" };
const API_VERSION_STATUS_TONE: Record<ApiVersion["status"], StatusTone> = { active: "success", deprecated: "warning", sunset: "neutral" };

function ErrorBanner({ error }: { error: string | null }) {
  if (!error) return null;
  return (
    <p role="alert" className="text-sm text-danger">
      {error}
    </p>
  );
}

/** A raw key/secret is shown here exactly once -- app.create_api_key/app.rotate_api_key structurally never return it again, so this callout is the ONLY place a tenant admin will ever see it in full. */
function RawKeyCallout({ rawKey }: { rawKey: string }) {
  return (
    <div role="status" className="flex flex-col gap-1 rounded-md border border-warning bg-warning/10 p-3">
      <p className="text-sm font-semibold text-text-primary">Copy this key now -- it will not be shown again</p>
      <code className="break-all rounded bg-neutral-900 px-2 py-1 text-xs text-white">{rawKey}</code>
    </div>
  );
}

export function CreateApiKeyForm({ tenantSlug }: { tenantSlug: string }) {
  const [state, formAction, pending] = useActionState(createApiKeyAction.bind(null, tenantSlug), INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4" noValidate>
      <h2 className="text-sm font-semibold text-text-primary">Create an API key</h2>
      <label htmlFor="ak-name" className="text-xs font-medium text-text-secondary">
        Key name
      </label>
      <input id="ak-name" name="name" type="text" required className="w-full rounded-md border border-neutral-300 px-3 py-2 text-sm" />
      <label htmlFor="ak-scopes" className="text-xs font-medium text-text-secondary">
        Scopes (comma-separated, e.g. INTHUB:View, INTHUB:Configure) -- can only narrow your own currently-held permissions, never widen them
      </label>
      <input id="ak-scopes" name="scopes" type="text" required className="w-full rounded-md border border-neutral-300 px-3 py-2 text-sm" />
      <label htmlFor="ak-rate-limit" className="text-xs font-medium text-text-secondary">
        Rate limit per minute (optional -- blank means unlimited)
      </label>
      <input id="ak-rate-limit" name="rateLimitPerMinute" type="number" min={1} max={100000} className="w-full rounded-md border border-neutral-300 px-3 py-2 text-sm" />
      <label htmlFor="ak-expires" className="text-xs font-medium text-text-secondary">
        Expires at (optional -- blank means no expiry)
      </label>
      <input id="ak-expires" name="expiresAt" type="datetime-local" className="w-full rounded-md border border-neutral-300 px-3 py-2 text-sm" />
      <ErrorBanner error={state.error} />
      {state.createdKey ? <RawKeyCallout rawKey={state.createdKey.rawKey} /> : null}
      <Button type="submit" loading={pending} loadingLabel="Creating…" className="w-fit">
        Create key
      </Button>
    </form>
  );
}

function RotateApiKeyForm({ tenantSlug, keyId }: { tenantSlug: string; keyId: string }) {
  const [state, formAction, pending] = useActionState(rotateApiKeyAction.bind(null, tenantSlug, keyId), INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col gap-1">
      <div className="flex items-center gap-2">
        <label htmlFor={`rotate-overlap-${keyId}`} className="text-xs text-text-secondary">
          Overlap (min)
        </label>
        <input id={`rotate-overlap-${keyId}`} name="overlapMinutes" type="number" min={0} max={10080} defaultValue={0} className="w-20 rounded-md border border-neutral-300 px-2 py-1 text-xs" />
        <Button type="submit" variant="secondary" loading={pending} loadingLabel="Rotating…">
          Rotate
        </Button>
      </div>
      <ErrorBanner error={state.error} />
      {state.createdKey ? <RawKeyCallout rawKey={state.createdKey.rawKey} /> : null}
    </form>
  );
}

function RevokeApiKeyForm({ tenantSlug, keyId }: { tenantSlug: string; keyId: string }) {
  const [state, formAction, pending] = useActionState(revokeApiKeyAction.bind(null, tenantSlug, keyId), INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col gap-1">
      <div className="flex items-center gap-2">
        <input name="reason" type="text" placeholder="Reason (optional)" className="w-32 rounded-md border border-neutral-300 px-2 py-1 text-xs" />
        <Button type="submit" variant="destructive" loading={pending} loadingLabel="Revoking…">
          Revoke
        </Button>
      </div>
      <ErrorBanner error={state.error} />
    </form>
  );
}

export function ApiKeyList({ tenantSlug, keys }: { tenantSlug: string; keys: readonly ApiKey[] }) {
  if (keys.length === 0) {
    return <EmptyState title="No API keys yet" description="Create your tenant's first API key above." />;
  }
  return (
    <div className="overflow-x-auto rounded-md border border-neutral-200">
      <table className="w-full border-collapse text-sm">
        <caption className="sr-only">API keys</caption>
        <thead>
          <tr className="text-left text-xs font-medium text-text-secondary">
            <th className="p-2">Name</th>
            <th className="p-2">Prefix</th>
            <th className="p-2">Scopes</th>
            <th className="p-2">Status</th>
            <th className="p-2">Rate limit</th>
            <th className="p-2">Last used</th>
            <th className="p-2">Actions</th>
          </tr>
        </thead>
        <tbody>
          {keys.map((key) => (
            <tr key={key.id} className="border-t border-neutral-100 align-top">
              <td className="p-2 font-medium text-text-primary">{key.name}</td>
              <td className="p-2 font-mono text-xs text-text-secondary">{key.keyPrefix}…</td>
              <td className="p-2 text-xs text-text-secondary">{key.scopes.join(", ")}</td>
              <td className="p-2">
                <StatusBadge tone={API_KEY_STATUS_TONE[key.status]} label={key.status} />
              </td>
              <td className="p-2 text-xs text-text-secondary">{key.rateLimitPerMinute ?? "unlimited"}/min</td>
              <td className="p-2 text-xs text-text-secondary">{key.lastUsedAt ?? "never"}</td>
              <td className="p-2">
                {key.status === "active" ? (
                  <div className="flex flex-col gap-2">
                    <RotateApiKeyForm tenantSlug={tenantSlug} keyId={key.id} />
                    <RevokeApiKeyForm tenantSlug={tenantSlug} keyId={key.id} />
                  </div>
                ) : null}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

export function ApiVersionList({ versions }: { versions: readonly ApiVersion[] }) {
  if (versions.length === 0) {
    return <EmptyState title="No API versions registered" description="No public API version has been registered yet." />;
  }
  return (
    <div className="overflow-x-auto rounded-md border border-neutral-200">
      <table className="w-full border-collapse text-sm">
        <caption className="sr-only">API versions</caption>
        <thead>
          <tr className="text-left text-xs font-medium text-text-secondary">
            <th className="p-2">Version</th>
            <th className="p-2">Status</th>
            <th className="p-2">Sunset at</th>
            <th className="p-2">Notes</th>
          </tr>
        </thead>
        <tbody>
          {versions.map((version) => (
            <tr key={version.code} className="border-t border-neutral-100">
              <td className="p-2 font-mono text-xs text-text-primary">{version.code}</td>
              <td className="p-2">
                <StatusBadge tone={API_VERSION_STATUS_TONE[version.status]} label={version.status} />
              </td>
              <td className="p-2 text-xs text-text-secondary">{version.sunsetAt ?? "—"}</td>
              <td className="p-2 text-xs text-text-secondary">{version.notes ?? "—"}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

export function WebhookEventTypeList({ eventTypes }: { eventTypes: readonly WebhookEventType[] }) {
  if (eventTypes.length === 0) {
    return <EmptyState title="No webhook event types registered yet" description="Webhook Management (Prompt 340) seeds the first real domain event types." />;
  }
  return (
    <ul className="flex flex-col gap-1 text-sm">
      {eventTypes.map((eventType) => (
        <li key={eventType.code} className="rounded-md border border-neutral-200 p-2">
          <span className="font-mono text-xs text-text-primary">{eventType.code}</span> — <span className="text-text-secondary">{eventType.name}</span>
        </li>
      ))}
    </ul>
  );
}

export function ApiLogList({ logs }: { logs: readonly ApiLog[] }) {
  if (logs.length === 0) {
    return <EmptyState title="No API requests recorded yet" description="Requests made against your API keys will appear here." />;
  }
  return (
    <div className="overflow-x-auto rounded-md border border-neutral-200">
      <table className="w-full border-collapse text-sm">
        <caption className="sr-only">Recent API requests</caption>
        <thead>
          <tr className="text-left text-xs font-medium text-text-secondary">
            <th className="p-2">When</th>
            <th className="p-2">Method</th>
            <th className="p-2">Path</th>
            <th className="p-2">Status</th>
            <th className="p-2">Result</th>
          </tr>
        </thead>
        <tbody>
          {logs.map((log) => (
            <tr key={log.id} className="border-t border-neutral-100">
              <td className="p-2 text-xs text-text-secondary">{log.createdAt}</td>
              <td className="p-2 text-xs text-text-secondary">{log.httpMethod ?? "—"}</td>
              <td className="p-2 font-mono text-xs text-text-secondary">{log.path ?? "—"}</td>
              <td className="p-2 text-xs text-text-secondary">{log.statusCode ?? "—"}</td>
              <td className="p-2">
                <StatusBadge tone={log.result === "success" ? "success" : "danger"} label={log.result} />
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
