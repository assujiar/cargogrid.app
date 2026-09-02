"use client";

/**
 * Membership Tier admin client forms (CPL-317, CG-S13-CPL-019). Same
 * `useActionState`/bound-action split every prior capability's own
 * create-form already uses (e.g. `admin/loyalty/loyalty-admin-panel.tsx`).
 */

import { useActionState } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
import { Input } from "../../../../../components/forms/input.tsx";
import { Select } from "../../../../../components/forms/select.tsx";
import { Textarea } from "../../../../../components/forms/textarea.tsx";
import { NumberInput } from "../../../../../components/forms/number-input.tsx";
import { FormField } from "../../../../../components/forms/form-field.tsx";
import { ValidationMessage } from "../../../../../components/forms/validation-message.tsx";
import { StatusBadge } from "../../../../../components/ui/status-badge.tsx";
import type { LoyaltyTierDefinition, LoyaltyAccountTierState, LoyaltyProgramTierReadiness } from "../../../../../server/contracts/customer-portal-loyalty-tier/customer-portal-loyalty-tier.ts";
import type { LoyaltyAccount } from "../../../../../server/contracts/customer-portal-loyalty-program/customer-portal-loyalty-program.ts";
import {
  createLoyaltyTierDefinitionAction,
  updateLoyaltyTierDefinitionDraftAction,
  publishLoyaltyTierDefinitionAction,
  recalculateCustomerLoyaltyTierAction,
  holdLoyaltyAccountTierBenefitsAction,
  releaseLoyaltyAccountTierBenefitsAction,
  type LoyaltyTierAdminFormState,
} from "./actions.ts";

const INITIAL_STATE: LoyaltyTierAdminFormState = { error: null };

const TIER_STATUS_TONE = { draft: "neutral", published: "success", superseded: "neutral" } as const;

/** ISS-2026-242: the shared field-error renderer -- `id` is what each control's `aria-describedby` points at. */
function ErrorBanner({ id, error }: { id?: string; error: string | null }) {
  if (!error) return null;
  return <ValidationMessage id={id}>{error}</ValidationMessage>;
}

export function CreateTierDefinitionForm({ tenantSlug, programId }: { tenantSlug: string; programId: string }) {
  const [state, formAction, pending] = useActionState(createLoyaltyTierDefinitionAction.bind(null, tenantSlug, programId), INITIAL_STATE);
  // ISS-2026-242: the create RPC returns one error for the whole tier, never per-field ones.
  const describedBy = state.error ? "td-create-error" : undefined;
  return (
    <form action={formAction} className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4" noValidate>
      <h3 className="text-sm font-semibold text-text-primary">Add a tier</h3>
      <FormField id="td-name" label="Tier name">
        <Input id="td-name" name="tierName" type="text" required placeholder="e.g. Gold" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <FormField id="td-rank" label="Tier rank (higher = more prestigious)">
        <NumberInput id="td-rank" name="tierRank" step="1" min="1" required invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <FormField id="td-dimension" label="Threshold dimension">
        <Select id="td-dimension" name="thresholdDimension" defaultValue="earning_amount_ytd" invalid={Boolean(state.error)} aria-describedby={describedBy}>
          <option value="earning_amount_ytd">Year-to-date earning amount (implemented)</option>
        </Select>
      </FormField>
      <FormField id="td-threshold" label="Threshold value (customer qualifies once earning reaches this amount)">
        <NumberInput id="td-threshold" name="thresholdValue" step="0.01" min="0" required invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <FormField id="td-review" label="Review period (days a customer keeps this tier before a downgrade can apply; 0 = immediate)">
        <NumberInput id="td-review" name="reviewPeriodDays" step="1" min="0" defaultValue={0} invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <FormField id="td-benefits" label="Benefits (JSON object, optional)">
        <Textarea id="td-benefits" name="benefits" rows={2} placeholder='{"free_shipping": true}' className="font-mono text-xs" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <ErrorBanner id="td-create-error" error={state.error} />
      <Button type="submit" loading={pending} loadingLabel="Creating…" className="w-fit">
        Add tier
      </Button>
    </form>
  );
}

export function EditTierDefinitionDraftForm({ tenantSlug, programId, version }: { tenantSlug: string; programId: string; version: LoyaltyTierDefinition }) {
  const [state, formAction, pending] = useActionState(updateLoyaltyTierDefinitionDraftAction.bind(null, tenantSlug, programId, version.id, version.recordVersion), INITIAL_STATE);
  const [publishState, publishAction, publishPending] = useActionState(publishLoyaltyTierDefinitionAction.bind(null, tenantSlug, programId, version.id, version.recordVersion), INITIAL_STATE);
  // ISS-2026-242: the update RPC returns one error for the whole draft, never per-field ones.
  const describedBy = state.error ? `td-edit-${version.id}-error` : undefined;
  return (
    <div className="mt-2 flex flex-col gap-3 rounded-md border border-info/30 bg-info/5 p-3">
      <StatusBadge tone="neutral" label={`Draft v${version.versionNumber}`} />
      <form action={formAction} className="flex flex-col gap-2" noValidate>
        <input type="hidden" name="tierName" value={version.tierName} />
        <FormField id={`td-edit-rank-${version.id}`} label="Tier rank">
          <NumberInput id={`td-edit-rank-${version.id}`} name="tierRank" step="1" min="1" defaultValue={version.tierRank} required invalid={Boolean(state.error)} aria-describedby={describedBy} />
        </FormField>
        <FormField id={`td-edit-dimension-${version.id}`} label="Threshold dimension">
          <Select id={`td-edit-dimension-${version.id}`} name="thresholdDimension" defaultValue={version.thresholdDimension} invalid={Boolean(state.error)} aria-describedby={describedBy}>
            <option value="earning_amount_ytd">Year-to-date earning amount (implemented)</option>
          </Select>
        </FormField>
        <FormField id={`td-edit-threshold-${version.id}`} label="Threshold value">
          <NumberInput
            id={`td-edit-threshold-${version.id}`}
            name="thresholdValue"
            step="0.01"
            min="0"
            defaultValue={version.thresholdValue}
            required
            invalid={Boolean(state.error)}
            aria-describedby={describedBy}
          />
        </FormField>
        <FormField id={`td-edit-review-${version.id}`} label="Review period (days)">
          <NumberInput
            id={`td-edit-review-${version.id}`}
            name="reviewPeriodDays"
            step="1"
            min="0"
            defaultValue={version.reviewPeriodDays}
            invalid={Boolean(state.error)}
            aria-describedby={describedBy}
          />
        </FormField>
        <FormField id={`td-edit-benefits-${version.id}`} label="Benefits (JSON object)">
          <Textarea
            id={`td-edit-benefits-${version.id}`}
            name="benefits"
            rows={2}
            defaultValue={JSON.stringify(version.benefits)}
            className="font-mono text-xs"
            invalid={Boolean(state.error)}
            aria-describedby={describedBy}
          />
        </FormField>
        <ErrorBanner id={`td-edit-${version.id}-error`} error={state.error} />
        <Button type="submit" variant="secondary" loading={pending} loadingLabel="Saving…" className="w-fit">
          Save draft
        </Button>
      </form>
      <form action={publishAction} noValidate>
        <p className="text-xs text-text-secondary">Publishing locks this version forever and supersedes this tier&apos;s own current published version, if any -- historical tier movements already recorded keep the version they were evaluated under.</p>
        <ErrorBanner error={publishState.error} />
        <Button type="submit" loading={publishPending} loadingLabel="Publishing…" className="mt-2 w-fit">
          Publish this version
        </Button>
      </form>
    </div>
  );
}

/**
 * ISS-2026-127 item 2: advisory-only warning banner for a programme the
 * nightly tier-recalculation sweep (app.run_loyalty_tier_recalculation_
 * sweep) will silently skip accounts under. Reuses StatusBadge's own
 * `warning` tone (already imported above for the fraud-hold badge) rather
 * than introducing a new component -- never renders anything that blocks an
 * action on this page; `readiness === null` (fetch failed or tolerated
 * error) or `readiness.ready === true` both render nothing.
 */
export function TierReadinessBanner({ readiness }: { readiness: LoyaltyProgramTierReadiness | null }) {
  if (!readiness || readiness.ready) return null;

  const reasons: string[] = [];
  if (!readiness.hasBaseTier) {
    reasons.push("no published tier has a threshold of 0, so a newly enrolled account never resolves to a starting tier");
  }
  if (readiness.unsupportedDimensionTierCount > 0) {
    reasons.push(`${readiness.unsupportedDimensionTierCount} published tier${readiness.unsupportedDimensionTierCount === 1 ? "" : "s"} use${readiness.unsupportedDimensionTierCount === 1 ? "s" : ""} a threshold dimension this system does not compute`);
  }
  if (readiness.untieredActiveAccountCount > 0) {
    reasons.push(`${readiness.untieredActiveAccountCount} active account${readiness.untieredActiveAccountCount === 1 ? "" : "s"} currently ha${readiness.untieredActiveAccountCount === 1 ? "s" : "ve"} no tier assigned`);
  }

  return (
    <div role="status" className="flex flex-col gap-2 rounded-md border border-warning/30 bg-warning/10 p-3">
      <div className="flex items-center gap-2">
        <StatusBadge tone="warning" label="Tier ladder not ready" />
        <p className="text-sm font-medium text-text-primary">The nightly recalculation sweep will silently skip some accounts in this programme.</p>
      </div>
      <ul className="ml-4 list-disc text-xs text-text-secondary">
        {reasons.map((reason) => (
          <li key={reason}>{reason}</li>
        ))}
      </ul>
      <p className="text-xs text-text-secondary">This is advisory only -- no action on this page is blocked. Publish a base (threshold 0) tier, or review the accounts above, to resolve it.</p>
    </div>
  );
}

export function TierDefinitionHistory({ versions }: { versions: readonly LoyaltyTierDefinition[] }) {
  const historical = versions.filter((version) => version.status !== "draft");
  if (historical.length === 0) {
    return <p className="text-xs text-text-secondary">No published tier version yet.</p>;
  }
  return (
    <div className="overflow-x-auto rounded-md border border-neutral-200">
      <table className="w-full border-collapse text-sm">
        <caption className="sr-only">Published and superseded tier definitions</caption>
        <thead>
          <tr className="text-left text-xs font-medium text-text-secondary">
            <th className="p-2">Tier</th>
            <th className="p-2">Version</th>
            <th className="p-2">Status</th>
            <th className="p-2 text-right">Rank</th>
            <th className="p-2 text-right">Threshold</th>
            <th className="p-2">Effective from</th>
            <th className="p-2">Effective to</th>
          </tr>
        </thead>
        <tbody>
          {historical.map((version) => (
            <tr key={version.id} className="border-t border-neutral-100">
              <td className="p-2">{version.tierName}</td>
              <td className="p-2">v{version.versionNumber}</td>
              <td className="p-2">
                <StatusBadge tone={TIER_STATUS_TONE[version.status] ?? "neutral"} label={version.status} />
              </td>
              <td className="p-2 text-right tabular-nums">{version.tierRank}</td>
              <td className="p-2 text-right tabular-nums">{version.thresholdValue}</td>
              <td className="p-2 text-xs text-text-secondary">{version.effectiveFrom ? new Date(version.effectiveFrom).toLocaleString() : "—"}</td>
              <td className="p-2 text-xs text-text-secondary">{version.effectiveTo ? new Date(version.effectiveTo).toLocaleString() : "—"}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

export function AccountTierRow({ tenantSlug, programId, account, state }: { tenantSlug: string; programId: string; account: LoyaltyAccount; state: LoyaltyAccountTierState | null }) {
  const [recalcState, recalcAction, recalcPending] = useActionState(recalculateCustomerLoyaltyTierAction.bind(null, tenantSlug, programId, account.id), INITIAL_STATE);
  const [holdState, holdAction, holdPending] = useActionState(holdLoyaltyAccountTierBenefitsAction.bind(null, tenantSlug, programId, account.id), INITIAL_STATE);
  const [releaseState, releaseAction, releasePending] = useActionState(releaseLoyaltyAccountTierBenefitsAction.bind(null, tenantSlug, programId, account.id), INITIAL_STATE);
  const isHeld = state?.isHeld ?? false;

  return (
    <div className="flex flex-col gap-2 rounded-md border border-neutral-200 p-3">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <div>
          <p className="font-mono text-xs text-text-secondary">{account.customerAccountId}</p>
          <p className="text-sm font-medium text-text-primary">{state?.currentTierName ?? "Not yet evaluated"}</p>
        </div>
        <div className="flex items-center gap-2">
          {isHeld ? <StatusBadge tone="warning" label="Benefits held" /> : null}
          {state?.nextReviewAt ? <span className="text-xs text-text-secondary">Next review {new Date(state.nextReviewAt).toLocaleDateString()}</span> : null}
        </div>
      </div>

      <div className="flex flex-wrap items-end gap-3">
        <form action={recalcAction} noValidate>
          <ErrorBanner error={recalcState.error} />
          <Button type="submit" variant="secondary" loading={recalcPending} loadingLabel="Recalculating…" className="w-fit">
            Recalculate tier
          </Button>
        </form>

        {isHeld ? (
          <form action={releaseAction} noValidate>
            <ErrorBanner error={releaseState.error} />
            <Button type="submit" variant="secondary" loading={releasePending} loadingLabel="Releasing…" className="w-fit">
              Release benefits hold
            </Button>
          </form>
        ) : (
          <form action={holdAction} className="flex items-end gap-2" noValidate>
            <label htmlFor={`tier-hold-reason-${account.id}`} className="sr-only">
              Hold reason
            </label>
            <Input
              id={`tier-hold-reason-${account.id}`}
              name="reason"
              placeholder="Hold reason (required)"
              required
              className="text-xs"
              invalid={Boolean(holdState.error)}
              aria-describedby={holdState.error ? `tier-hold-${account.id}-error` : undefined}
            />
            <ErrorBanner id={`tier-hold-${account.id}-error`} error={holdState.error} />
            <Button type="submit" variant="destructive" loading={holdPending} loadingLabel="Holding…" className="w-fit">
              Hold benefits (fraud/dispute)
            </Button>
          </form>
        )}
      </div>
    </div>
  );
}
