"use client";

/**
 * Customer API key self-service client forms (IAE-010, Prompt 338). Mirrors
 * app/(tenant)/[tenantSlug]/admin/api-keys/api-keys-admin-panel.tsx's own
 * shape, scoped to one account instead of the whole tenant.
 */

import { useActionState } from "react";
import { Button } from "../../../../components/ui/button.tsx";
import { StatusBadge, type StatusTone } from "../../../../components/ui/status-badge.tsx";
import { EmptyState } from "../../../../components/ui/empty-state.tsx";
import type { CustomerApiKey } from "../../../../server/contracts/customer-api/customer-api.ts";
import { createCustomerApiKeyAction, rotateCustomerApiKeyAction, revokeCustomerApiKeyAction, type CustomerApiKeyActionState } from "./actions.ts";

const INITIAL_STATE: CustomerApiKeyActionState = { error: null, createdKey: null };

const STATUS_TONE: Record<CustomerApiKey["status"], StatusTone> = { active: "success", revoked: "danger", expired: "neutral" };

function ErrorBanner({ error }: { error: string | null }) {
  if (!error) return null;
  return (
    <p role="alert" className="text-sm text-danger">
      {error}
    </p>
  );
}

/** A raw key is shown here exactly once -- app.create_customer_api_key/app.rotate_api_key structurally never return it again. */
function RawKeyCallout({ rawKey }: { rawKey: string }) {
  return (
    <div role="status" className="flex flex-col gap-1 rounded-md border border-warning bg-warning/10 p-3">
      <p className="text-sm font-semibold text-text-primary">Copy this key now -- it will not be shown again</p>
      <code className="break-all rounded bg-neutral-900 px-2 py-1 text-xs text-white">{rawKey}</code>
    </div>
  );
}

export function CreateCustomerApiKeyForm({ tenantSlug, accountId }: { tenantSlug: string; accountId: string }) {
  const [state, formAction, pending] = useActionState(createCustomerApiKeyAction.bind(null, tenantSlug, accountId), INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4" noValidate>
      <h2 className="text-sm font-semibold text-text-primary">Create an API key for this account</h2>
      <label htmlFor="cak-name" className="text-xs font-medium text-text-secondary">
        Key name
      </label>
      <input id="cak-name" name="name" type="text" required className="w-full rounded-md border border-neutral-300 px-3 py-2 text-sm" />
      <label htmlFor="cak-rate-limit" className="text-xs font-medium text-text-secondary">
        Rate limit per minute (optional -- blank means unlimited)
      </label>
      <input id="cak-rate-limit" name="rateLimitPerMinute" type="number" min={1} max={100000} className="w-full rounded-md border border-neutral-300 px-3 py-2 text-sm" />
      <p className="text-xs text-text-secondary">This key lets your own systems call the CargoGrid Customer API (tracking, bookings) on this account&apos;s own behalf -- never a broader tenant scope.</p>
      <ErrorBanner error={state.error} />
      {state.createdKey ? <RawKeyCallout rawKey={state.createdKey.rawKey} /> : null}
      <Button type="submit" loading={pending} loadingLabel="Creating…" className="w-fit">
        Create key
      </Button>
    </form>
  );
}

function RotateCustomerApiKeyForm({ tenantSlug, accountId, keyId }: { tenantSlug: string; accountId: string; keyId: string }) {
  const [state, formAction, pending] = useActionState(rotateCustomerApiKeyAction.bind(null, tenantSlug, accountId, keyId), INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col gap-1">
      <div className="flex items-center gap-2">
        <label htmlFor={`c-rotate-overlap-${keyId}`} className="text-xs text-text-secondary">
          Overlap (min)
        </label>
        <input id={`c-rotate-overlap-${keyId}`} name="overlapMinutes" type="number" min={0} max={10080} defaultValue={0} className="w-20 rounded-md border border-neutral-300 px-2 py-1 text-xs" />
        <Button type="submit" variant="secondary" loading={pending} loadingLabel="Rotating…">
          Rotate
        </Button>
      </div>
      <ErrorBanner error={state.error} />
      {state.createdKey ? <RawKeyCallout rawKey={state.createdKey.rawKey} /> : null}
    </form>
  );
}

function RevokeCustomerApiKeyForm({ tenantSlug, accountId, keyId }: { tenantSlug: string; accountId: string; keyId: string }) {
  const [state, formAction, pending] = useActionState(revokeCustomerApiKeyAction.bind(null, tenantSlug, accountId, keyId), INITIAL_STATE);
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

export function CustomerApiKeyList({ tenantSlug, accountId, keys }: { tenantSlug: string; accountId: string; keys: readonly CustomerApiKey[] }) {
  if (keys.length === 0) {
    return <EmptyState title="No API keys yet" description="Create this account's first API key above." />;
  }
  return (
    <div className="overflow-x-auto rounded-md border border-neutral-200">
      <table className="w-full border-collapse text-sm">
        <caption className="sr-only">API keys for this account</caption>
        <thead>
          <tr className="text-left text-xs font-medium text-text-secondary">
            <th className="p-2">Name</th>
            <th className="p-2">Prefix</th>
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
              <td className="p-2">
                <StatusBadge tone={STATUS_TONE[key.status]} label={key.status} />
              </td>
              <td className="p-2 text-xs text-text-secondary">{key.rateLimitPerMinute ?? "unlimited"}/min</td>
              <td className="p-2 text-xs text-text-secondary">{key.lastUsedAt ?? "never"}</td>
              <td className="p-2">
                {key.status === "active" ? (
                  <div className="flex flex-col gap-2">
                    <RotateCustomerApiKeyForm tenantSlug={tenantSlug} accountId={accountId} keyId={key.id} />
                    <RevokeCustomerApiKeyForm tenantSlug={tenantSlug} accountId={accountId} keyId={key.id} />
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
