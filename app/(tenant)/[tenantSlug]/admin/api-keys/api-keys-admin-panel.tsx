"use client";

/**
 * Public API Platform developer console client forms (IAE-009, Prompt 337). Same
 * `useActionState`/bound-action split every prior capability's own create-form already
 * uses (e.g. `admin/loyalty/loyalty-admin-panel.tsx`).
 */

import { useActionState } from "react";
import Link from "next/link";
import { Button } from "../../../../../components/ui/button.tsx";
import { Input } from "../../../../../components/forms/input.tsx";
import { NumberInput } from "../../../../../components/forms/number-input.tsx";
import { FormField } from "../../../../../components/forms/form-field.tsx";
import { ValidationMessage } from "../../../../../components/forms/validation-message.tsx";
import { StatusBadge, type StatusTone } from "../../../../../components/ui/status-badge.tsx";
import { EmptyState } from "../../../../../components/ui/empty-state.tsx";
import type { ApiKey, WebhookEndpoint } from "../../../../../server/contracts/api-key-webhook/api-key-webhook.ts";
import type { ApiVersion } from "../../../../../server/contracts/public-api-platform/public-api-platform.ts";
import type { WebhookEventType } from "../../../../../server/contracts/api-key-webhook/api-key-webhook.ts";
import type { ApiLog } from "../../../../../server/contracts/api/api.ts";
import type { VendorApiKey } from "../../../../../server/contracts/vendor-api/vendor-api.ts";
import type { WebhookDelivery } from "../../../../../server/contracts/webhook-management/webhook-management.ts";
import type { N8nConnector, N8nAllowlistedAction } from "../../../../../server/contracts/n8n-integration/n8n-integration.ts";
import {
  createApiKeyAction,
  rotateApiKeyAction,
  revokeApiKeyAction,
  createVendorApiKeyAction,
  registerWebhookEndpointAction,
  rotateWebhookSecretAction,
  disableWebhookEndpointAction,
  reenableWebhookEndpointAction,
  sendTestWebhookDeliveryAction,
  replayWebhookDeliveryAction,
  createN8nConnectorAction,
  rotateN8nConnectorAction,
  type ApiKeyFormState,
  type VendorApiKeyFormState,
  type WebhookEndpointFormState,
  type WebhookDeliveryFormState,
  type N8nConnectorFormState,
} from "./actions.ts";

const INITIAL_STATE: ApiKeyFormState = { error: null, createdKey: null };
const ENDPOINT_INITIAL_STATE: WebhookEndpointFormState = { error: null, createdEndpoint: null };
const DELIVERY_INITIAL_STATE: WebhookDeliveryFormState = { error: null, delivery: null };
const N8N_INITIAL_STATE: N8nConnectorFormState = { error: null, createdConnector: null };
const WEBHOOK_ENDPOINT_STATUS_TONE: Record<WebhookEndpoint["status"], StatusTone> = { active: "success", disabled: "neutral" };
const WEBHOOK_DELIVERY_STATUS_TONE: Record<WebhookDelivery["status"], StatusTone> = { pending: "warning", delivered: "success", dead_letter: "danger" };
const VENDOR_INITIAL_STATE: VendorApiKeyFormState = { error: null, createdKey: null };

const API_KEY_STATUS_TONE: Record<ApiKey["status"], StatusTone> = { active: "success", revoked: "danger", expired: "neutral" };
const API_VERSION_STATUS_TONE: Record<ApiVersion["status"], StatusTone> = { active: "success", deprecated: "warning", sunset: "neutral" };

/** ISS-2026-242: the shared field-error renderer -- `id` is what each control's `aria-describedby` points at. */
function ErrorBanner({ id, error }: { id?: string; error: string | null }) {
  if (!error) return null;
  return <ValidationMessage id={id}>{error}</ValidationMessage>;
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
  // ISS-2026-242: the create RPC returns one error for the whole call, never per-field ones.
  const describedBy = state.error ? "ak-create-error" : undefined;
  return (
    <form action={formAction} className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4" noValidate>
      <h2 className="text-sm font-semibold text-text-primary">Create an API key</h2>
      <FormField id="ak-name" label="Key name">
        <Input id="ak-name" name="name" type="text" required invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <FormField id="ak-scopes" label="Scopes (comma-separated, e.g. INTHUB:View, INTHUB:Configure) -- can only narrow your own currently-held permissions, never widen them">
        <Input id="ak-scopes" name="scopes" type="text" required invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <FormField id="ak-rate-limit" label="Rate limit per minute (optional -- blank means unlimited)">
        <NumberInput id="ak-rate-limit" name="rateLimitPerMinute" min={1} max={100000} invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <FormField id="ak-expires" label="Expires at (optional -- blank means no expiry)">
        <Input id="ak-expires" name="expiresAt" type="datetime-local" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <ErrorBanner id="ak-create-error" error={state.error} />
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
        <NumberInput
          id={`rotate-overlap-${keyId}`}
          name="overlapMinutes"
          min={0}
          max={10080}
          defaultValue={0}
          className="w-20 text-xs"
          invalid={Boolean(state.error)}
          aria-describedby={state.error ? `rotate-${keyId}-error` : undefined}
        />
        <Button type="submit" variant="secondary" loading={pending} loadingLabel="Rotating…">
          Rotate
        </Button>
      </div>
      <ErrorBanner id={`rotate-${keyId}-error`} error={state.error} />
      {state.createdKey ? <RawKeyCallout rawKey={state.createdKey.rawKey} /> : null}
    </form>
  );
}

function RevokeApiKeyForm({ tenantSlug, keyId }: { tenantSlug: string; keyId: string }) {
  const [state, formAction, pending] = useActionState(revokeApiKeyAction.bind(null, tenantSlug, keyId), INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col gap-1">
      <div className="flex items-center gap-2">
        <label htmlFor={`revoke-reason-${keyId}`} className="sr-only">
          Revocation reason
        </label>
        <Input
          id={`revoke-reason-${keyId}`}
          name="reason"
          type="text"
          placeholder="Reason (optional)"
          className="w-32 text-xs"
          invalid={Boolean(state.error)}
          aria-describedby={state.error ? `revoke-${keyId}-error` : undefined}
        />
        <Button type="submit" variant="destructive" loading={pending} loadingLabel="Revoking…">
          Revoke
        </Button>
      </div>
      <ErrorBanner id={`revoke-${keyId}-error`} error={state.error} />
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

/** IAE-011: staff-only creation (Supreme/tenant_admin) -- there is no vendor self-service, since no vendor login/session exists anywhere in this repository. The key is handed to the vendor out-of-band, mirroring how vendor intake tokens are already issued. */
export function CreateVendorApiKeyForm({ tenantSlug }: { tenantSlug: string }) {
  const [state, formAction, pending] = useActionState(createVendorApiKeyAction.bind(null, tenantSlug), VENDOR_INITIAL_STATE);
  const describedBy = state.error ? "vak-create-error" : undefined;
  return (
    <form action={formAction} className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4" noValidate>
      <h2 className="text-sm font-semibold text-text-primary">Create a Vendor API key</h2>
      <FormField id="vak-vendor-id" label="Vendor id (app.vendor_profiles.master_record_id) -- must be an active, approved vendor">
        <Input id="vak-vendor-id" name="vendorMasterRecordId" type="text" required invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <FormField id="vak-name" label="Key name">
        <Input id="vak-name" name="name" type="text" required invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <FormField id="vak-rate-limit" label="Rate limit per minute (optional -- blank means unlimited)">
        <NumberInput id="vak-rate-limit" name="rateLimitPerMinute" min={1} max={100000} invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <FormField id="vak-expires" label="Expires at (optional -- blank means no expiry)">
        <Input id="vak-expires" name="expiresAt" type="datetime-local" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <p className="text-xs text-text-secondary">This key lets the named vendor&apos;s own systems call the CargoGrid Vendor API (RFQ responses, assignment accept/decline) scoped to exactly this vendor -- never a broader tenant scope. Hand the raw key to the vendor out-of-band; it is never shown again.</p>
      <ErrorBanner id="vak-create-error" error={state.error} />
      {state.createdKey ? <RawKeyCallout rawKey={state.createdKey.rawKey} /> : null}
      <Button type="submit" loading={pending} loadingLabel="Creating…" className="w-fit">
        Create vendor key
      </Button>
    </form>
  );
}

export function VendorApiKeyList({ tenantSlug, keys }: { tenantSlug: string; keys: readonly VendorApiKey[] }) {
  if (keys.length === 0) {
    return <EmptyState title="No Vendor API keys yet" description="Create your tenant's first vendor-scoped key above." />;
  }
  return (
    <div className="overflow-x-auto rounded-md border border-neutral-200">
      <table className="w-full border-collapse text-sm">
        <caption className="sr-only">Vendor API keys</caption>
        <thead>
          <tr className="text-left text-xs font-medium text-text-secondary">
            <th className="p-2">Name</th>
            <th className="p-2">Vendor</th>
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
              <td className="p-2 text-xs text-text-secondary">{key.vendorLegalName ?? key.vendorMasterRecordId}</td>
              <td className="p-2 font-mono text-xs text-text-secondary">{key.keyPrefix}…</td>
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

/** A raw webhook signing secret is shown here exactly once -- app.register_webhook_endpoint/app.rotate_webhook_secret structurally never return it again. */
function RawSecretCallout({ rawSecret }: { rawSecret: string }) {
  return (
    <div role="status" className="flex flex-col gap-1 rounded-md border border-warning bg-warning/10 p-3">
      <p className="text-sm font-semibold text-text-primary">Copy this signing secret now -- it will not be shown again</p>
      <code className="break-all rounded bg-neutral-900 px-2 py-1 text-xs text-white">{rawSecret}</code>
    </div>
  );
}

/** IAE-012: registers an endpoint against one or more already-seeded event types in one step (app.register_webhook_endpoint itself takes the subscription list at creation time -- there is no separate "add subscription" step to build). */
export function RegisterWebhookEndpointForm({ tenantSlug }: { tenantSlug: string }) {
  const [state, formAction, pending] = useActionState(registerWebhookEndpointAction.bind(null, tenantSlug), ENDPOINT_INITIAL_STATE);
  const describedBy = state.error ? "we-register-error" : undefined;
  return (
    <form action={formAction} className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4" noValidate>
      <h2 className="text-sm font-semibold text-text-primary">Register a webhook endpoint</h2>
      <FormField id="we-url" label="Endpoint URL (https only)">
        <Input id="we-url" name="url" type="url" required invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <FormField id="we-event-types" label="Event types (comma-separated, e.g. shipment.status_changed, ticket.created)">
        <Input id="we-event-types" name="eventTypeCodes" type="text" required invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <ErrorBanner id="we-register-error" error={state.error} />
      {state.createdEndpoint ? <RawSecretCallout rawSecret={state.createdEndpoint.rawSecret} /> : null}
      <Button type="submit" loading={pending} loadingLabel="Registering…" className="w-fit">
        Register endpoint
      </Button>
    </form>
  );
}

function RotateWebhookSecretForm({ tenantSlug, endpointId }: { tenantSlug: string; endpointId: string }) {
  const [state, formAction, pending] = useActionState(rotateWebhookSecretAction.bind(null, tenantSlug, endpointId), ENDPOINT_INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col gap-1">
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Rotating…">
        Rotate secret
      </Button>
      <ErrorBanner error={state.error} />
      {state.createdEndpoint ? <RawSecretCallout rawSecret={state.createdEndpoint.rawSecret} /> : null}
    </form>
  );
}

function DisableWebhookEndpointForm({ tenantSlug, endpointId }: { tenantSlug: string; endpointId: string }) {
  const [state, formAction, pending] = useActionState(disableWebhookEndpointAction.bind(null, tenantSlug, endpointId), ENDPOINT_INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col gap-1">
      <div className="flex items-center gap-2">
        <label htmlFor={`disable-reason-${endpointId}`} className="sr-only">
          Reason for disabling this endpoint
        </label>
        <Input
          id={`disable-reason-${endpointId}`}
          name="reason"
          type="text"
          placeholder="Reason (optional)"
          className="w-32 text-xs"
          invalid={Boolean(state.error)}
          aria-describedby={state.error ? `disable-${endpointId}-error` : undefined}
        />
        <Button type="submit" variant="destructive" loading={pending} loadingLabel="Disabling…">
          Disable
        </Button>
      </div>
      <ErrorBanner id={`disable-${endpointId}-error`} error={state.error} />
    </form>
  );
}

function ReenableWebhookEndpointForm({ tenantSlug, endpointId }: { tenantSlug: string; endpointId: string }) {
  const [state, formAction, pending] = useActionState(reenableWebhookEndpointAction.bind(null, tenantSlug, endpointId), ENDPOINT_INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col gap-1">
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Re-enabling…">
        Re-enable
      </Button>
      <ErrorBanner error={state.error} />
    </form>
  );
}

/** IAE-012: enqueues a real app.jobs job -- this genuinely exercises the real delivery worker, never a UI-only stub. */
function SendTestWebhookDeliveryForm({ tenantSlug, endpointId }: { tenantSlug: string; endpointId: string }) {
  const [state, formAction, pending] = useActionState(sendTestWebhookDeliveryAction.bind(null, tenantSlug, endpointId), DELIVERY_INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col gap-1">
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Sending…">
        Send test
      </Button>
      <ErrorBanner error={state.error} />
      {state.delivery ? <p className="text-xs text-text-secondary">Test delivery queued -- see it in the delivery log below shortly.</p> : null}
    </form>
  );
}

export function WebhookEndpointList({ tenantSlug, endpoints }: { tenantSlug: string; endpoints: readonly WebhookEndpoint[] }) {
  if (endpoints.length === 0) {
    return <EmptyState title="No webhook endpoints yet" description="Register your tenant's first webhook endpoint above." />;
  }
  return (
    <div className="overflow-x-auto rounded-md border border-neutral-200">
      <table className="w-full border-collapse text-sm">
        <caption className="sr-only">Webhook endpoints</caption>
        <thead>
          <tr className="text-left text-xs font-medium text-text-secondary">
            <th className="p-2">URL</th>
            <th className="p-2">Status</th>
            <th className="p-2">Consecutive failures</th>
            <th className="p-2">Actions</th>
          </tr>
        </thead>
        <tbody>
          {endpoints.map((endpoint) => (
            <tr key={endpoint.id} className="border-t border-neutral-100 align-top">
              <td className="p-2 font-mono text-xs text-text-primary">{endpoint.url}</td>
              <td className="p-2">
                <StatusBadge tone={WEBHOOK_ENDPOINT_STATUS_TONE[endpoint.status]} label={endpoint.status} />
                {endpoint.disabledReason ? <p className="text-xs text-text-secondary">{endpoint.disabledReason}</p> : null}
              </td>
              <td className="p-2 text-xs text-text-secondary">{endpoint.consecutiveFailureCount}</td>
              <td className="p-2">
                <div className="flex flex-col gap-2">
                  <SendTestWebhookDeliveryForm tenantSlug={tenantSlug} endpointId={endpoint.id} />
                  <RotateWebhookSecretForm tenantSlug={tenantSlug} endpointId={endpoint.id} />
                  {endpoint.status === "active" ? <DisableWebhookEndpointForm tenantSlug={tenantSlug} endpointId={endpoint.id} /> : <ReenableWebhookEndpointForm tenantSlug={tenantSlug} endpointId={endpoint.id} />}
                </div>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

/** IAE-012: valid ONLY for a dead_letter delivery (the RPC itself enforces this -- the button is still shown only for that status as a UX affordance, not the real gate). */
function ReplayWebhookDeliveryForm({ tenantSlug, deliveryId }: { tenantSlug: string; deliveryId: string }) {
  const [state, formAction, pending] = useActionState(replayWebhookDeliveryAction.bind(null, tenantSlug, deliveryId), DELIVERY_INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col gap-1">
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Replaying…">
        Replay
      </Button>
      <ErrorBanner error={state.error} />
    </form>
  );
}

export function WebhookDeliveryList({ tenantSlug, deliveries }: { tenantSlug: string; deliveries: readonly WebhookDelivery[] }) {
  if (deliveries.length === 0) {
    return <EmptyState title="No webhook deliveries yet" description="Deliveries queued via app.queue_webhook_delivery or a test send will appear here." />;
  }
  return (
    <div className="overflow-x-auto rounded-md border border-neutral-200">
      <table className="w-full border-collapse text-sm">
        <caption className="sr-only">Webhook deliveries</caption>
        <thead>
          <tr className="text-left text-xs font-medium text-text-secondary">
            <th className="p-2">Event</th>
            <th className="p-2">Endpoint</th>
            <th className="p-2">Status</th>
            <th className="p-2">Attempts</th>
            <th className="p-2">Next attempt</th>
            <th className="p-2">Actions</th>
          </tr>
        </thead>
        <tbody>
          {deliveries.map((delivery) => (
            <tr key={delivery.id} className="border-t border-neutral-100 align-top">
              <td className="p-2 font-mono text-xs text-text-primary">{delivery.eventTypeCode}</td>
              <td className="p-2 font-mono text-xs text-text-secondary">{delivery.endpointUrl}</td>
              <td className="p-2">
                <StatusBadge tone={WEBHOOK_DELIVERY_STATUS_TONE[delivery.status]} label={delivery.status} />
              </td>
              <td className="p-2 text-xs text-text-secondary">
                {delivery.attempts}/{delivery.maxAttempts}
              </td>
              <td className="p-2 text-xs text-text-secondary">{delivery.nextAttemptAt ?? "—"}</td>
              <td className="p-2">{delivery.status === "dead_letter" ? <ReplayWebhookDeliveryForm tenantSlug={tenantSlug} deliveryId={delivery.id} /> : null}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

/** IAE-013: n8n calls the SAME /api/v1 REST surface and receives events through the SAME webhook delivery mechanism every other consumer already uses -- this form only labels/scopes/links a connector. */
export function CreateN8nConnectorForm({ tenantSlug, allowlist }: { tenantSlug: string; allowlist: readonly N8nAllowlistedAction[] }) {
  const [state, formAction, pending] = useActionState(createN8nConnectorAction.bind(null, tenantSlug), N8N_INITIAL_STATE);
  const describedBy = state.error ? "n8n-create-error" : undefined;
  return (
    <form action={formAction} className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4" noValidate>
      <h2 className="text-sm font-semibold text-text-primary">Register an n8n connector</h2>
      <FormField id="n8n-name" label="Connector name">
        <Input id="n8n-name" name="name" type="text" required invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <FormField id="n8n-scopes" label="Scopes (comma-separated) -- must be on the n8n safe-action allowlist below, and cannot exceed your own currently-held permissions">
        <Input id="n8n-scopes" name="scopes" type="text" required invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <FormField id="n8n-webhook-endpoint" label="Linked webhook endpoint id (optional -- the endpoint you registered above, pointed at your n8n workflow's own webhook URL)">
        <Input id="n8n-webhook-endpoint" name="webhookEndpointId" type="text" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <FormField id="n8n-rate-limit" label="Rate limit per minute (optional -- blank means unlimited)">
        <NumberInput id="n8n-rate-limit" name="rateLimitPerMinute" min={1} max={100000} invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <p className="text-xs text-text-secondary">Safe-action allowlist: {allowlist.map((a) => a.scope).join(", ") || "none registered"}. n8n actions can never bypass domain approvals or human governance -- only read-only and low-risk scopes are ever allowlisted.</p>
      <ErrorBanner id="n8n-create-error" error={state.error} />
      {state.createdConnector ? <RawKeyCallout rawKey={state.createdConnector.rawKey} /> : null}
      <Button type="submit" loading={pending} loadingLabel="Registering…" className="w-fit">
        Register connector
      </Button>
    </form>
  );
}

/**
 * Tier C Batch 3 fix: unlike a plain API key, rotating a connector must ALSO
 * re-point app.n8n_connectors.api_key_id at the newly-minted key row --
 * reusing the generic RotateApiKeyForm here would leave the connector's own
 * governance record silently pointed at the superseded key. Revoke has no
 * such issue (it updates the SAME row in place), so RevokeApiKeyForm is
 * still reused unchanged below.
 */
function RotateN8nConnectorForm({ tenantSlug, connectorId }: { tenantSlug: string; connectorId: string }) {
  const [state, formAction, pending] = useActionState(rotateN8nConnectorAction.bind(null, tenantSlug, connectorId), N8N_INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col gap-1">
      <div className="flex items-center gap-2">
        <label htmlFor={`n8n-rotate-overlap-${connectorId}`} className="text-xs text-text-secondary">
          Overlap (min)
        </label>
        <NumberInput
          id={`n8n-rotate-overlap-${connectorId}`}
          name="overlapMinutes"
          min={0}
          max={10080}
          defaultValue={0}
          className="w-20 text-xs"
          invalid={Boolean(state.error)}
          aria-describedby={state.error ? `n8n-rotate-${connectorId}-error` : undefined}
        />
        <Button type="submit" variant="secondary" loading={pending} loadingLabel="Rotating…">
          Rotate
        </Button>
      </div>
      <ErrorBanner id={`n8n-rotate-${connectorId}-error`} error={state.error} />
      {state.createdConnector ? <RawKeyCallout rawKey={state.createdConnector.rawKey} /> : null}
    </form>
  );
}

export function N8nConnectorList({ tenantSlug, connectors }: { tenantSlug: string; connectors: readonly N8nConnector[] }) {
  if (connectors.length === 0) {
    return <EmptyState title="No n8n connectors yet" description="Register your tenant's first n8n connector above -- it reuses the SAME API key/webhook endpoint primitives every other integration already uses." />;
  }
  return (
    <div className="overflow-x-auto rounded-md border border-neutral-200">
      <table className="w-full border-collapse text-sm">
        <caption className="sr-only">n8n connectors</caption>
        <thead>
          <tr className="text-left text-xs font-medium text-text-secondary">
            <th className="p-2">Name</th>
            <th className="p-2">Scopes</th>
            <th className="p-2">Status</th>
            <th className="p-2">Linked webhook endpoint</th>
            <th className="p-2">Actions</th>
          </tr>
        </thead>
        <tbody>
          {connectors.map((connector) => (
            <tr key={connector.connectorId} className="border-t border-neutral-100 align-top">
              <td className="p-2 font-medium text-text-primary">{connector.name}</td>
              <td className="p-2 text-xs text-text-secondary">{connector.scopes.join(", ")}</td>
              <td className="p-2">
                <StatusBadge tone={API_KEY_STATUS_TONE[connector.status]} label={connector.status} />
              </td>
              <td className="p-2 font-mono text-xs text-text-secondary">{connector.webhookEndpointUrl ?? "none linked"}</td>
              <td className="p-2">
                {connector.status === "active" ? (
                  <div className="flex flex-col gap-2">
                    <RotateN8nConnectorForm tenantSlug={tenantSlug} connectorId={connector.connectorId} />
                    <RevokeApiKeyForm tenantSlug={tenantSlug} keyId={connector.apiKeyId} />
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

/**
 * ISS-2026-147 item 2: the per-connector execution-log filter. `IAE-013`'s own migration
 * comment claimed this existed; it did not, at any layer — a tenant admin running several
 * integrations saw every connector's history interleaved in one tenant-wide list, with no way
 * to isolate one.
 *
 * Rendered as links rather than a `<select>` with client-side state on purpose: the filter is
 * a server round trip either way (the predicate lives in the RPC, not in the browser), and a
 * link keeps the filtered view addressable, shareable, and back-button-correct — which a
 * client-only selection is not. `scroll={false}` keeps the reader where they are instead of
 * throwing them to the top of a long console page.
 */
export function ConnectorFilterBar({
  label,
  basePath,
  paramName,
  options,
  selectedId,
}: {
  label: string;
  basePath: string;
  paramName: string;
  options: readonly { readonly id: string; readonly label: string }[];
  selectedId: string | null;
}) {
  if (options.length === 0) {
    return null;
  }
  const hrefFor = (id: string | null) => (id === null ? basePath : `${basePath}?${paramName}=${encodeURIComponent(id)}`);
  return (
    <nav aria-label={label} className="mb-3 flex flex-wrap items-center gap-2 text-xs">
      <span className="font-medium text-text-secondary">{label}:</span>
      <Link
        href={hrefFor(null)}
        scroll={false}
        aria-current={selectedId === null ? "true" : undefined}
        className={
          selectedId === null
            ? "rounded-full border border-neutral-400 bg-neutral-100 px-2 py-0.5 font-medium text-text-primary"
            : "rounded-full border border-neutral-200 px-2 py-0.5 text-text-secondary hover:border-neutral-400"
        }
      >
        All
      </Link>
      {options.map((option) => (
        <Link
          key={option.id}
          href={hrefFor(option.id)}
          scroll={false}
          aria-current={selectedId === option.id ? "true" : undefined}
          className={
            selectedId === option.id
              ? "rounded-full border border-neutral-400 bg-neutral-100 px-2 py-0.5 font-medium text-text-primary"
              : "rounded-full border border-neutral-200 px-2 py-0.5 text-text-secondary hover:border-neutral-400"
          }
        >
          {option.label}
        </Link>
      ))}
    </nav>
  );
}
