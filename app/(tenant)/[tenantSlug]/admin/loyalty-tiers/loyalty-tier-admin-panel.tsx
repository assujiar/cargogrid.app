"use client";

/**
 * Membership Tier admin client forms (CPL-317, CG-S13-CPL-019). Same
 * `useActionState`/bound-action split every prior capability's own
 * create-form already uses (e.g. `admin/loyalty/loyalty-admin-panel.tsx`).
 */

import { useActionState } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
import { StatusBadge } from "../../../../../components/ui/status-badge.tsx";
import type { LoyaltyTierDefinition, LoyaltyAccountTierState } from "../../../../../server/contracts/customer-portal-loyalty-tier/customer-portal-loyalty-tier.ts";
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

function ErrorBanner({ error }: { error: string | null }) {
  if (!error) return null;
  return (
    <p role="alert" className="text-sm text-danger">
      {error}
    </p>
  );
}

export function CreateTierDefinitionForm({ tenantSlug, programId }: { tenantSlug: string; programId: string }) {
  const [state, formAction, pending] = useActionState(createLoyaltyTierDefinitionAction.bind(null, tenantSlug, programId), INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4" noValidate>
      <h3 className="text-sm font-semibold text-text-primary">Add a tier</h3>
      <label htmlFor="td-name" className="text-xs font-medium text-text-secondary">
        Tier name
      </label>
      <input id="td-name" name="tierName" type="text" required placeholder="e.g. Gold" className="w-full rounded-md border border-neutral-300 px-3 py-2 text-sm" />
      <label htmlFor="td-rank" className="text-xs font-medium text-text-secondary">
        Tier rank (higher = more prestigious)
      </label>
      <input id="td-rank" name="tierRank" type="number" step="1" min="1" required className="w-full rounded-md border border-neutral-300 px-3 py-2 text-sm" />
      <label htmlFor="td-dimension" className="text-xs font-medium text-text-secondary">
        Threshold dimension
      </label>
      <select id="td-dimension" name="thresholdDimension" defaultValue="earning_amount_ytd" className="rounded-md border border-neutral-300 px-2 py-1.5 text-sm">
        <option value="earning_amount_ytd">Year-to-date earning amount (implemented)</option>
      </select>
      <label htmlFor="td-threshold" className="text-xs font-medium text-text-secondary">
        Threshold value (customer qualifies once earning reaches this amount)
      </label>
      <input id="td-threshold" name="thresholdValue" type="number" step="0.01" min="0" required className="w-full rounded-md border border-neutral-300 px-3 py-2 text-sm" />
      <label htmlFor="td-review" className="text-xs font-medium text-text-secondary">
        Review period (days a customer keeps this tier before a downgrade can apply; 0 = immediate)
      </label>
      <input id="td-review" name="reviewPeriodDays" type="number" step="1" min="0" defaultValue={0} className="w-full rounded-md border border-neutral-300 px-3 py-2 text-sm" />
      <label htmlFor="td-benefits" className="text-xs font-medium text-text-secondary">
        Benefits (JSON object, optional)
      </label>
      <textarea id="td-benefits" name="benefits" rows={2} placeholder='{"free_shipping": true}' className="w-full rounded-md border border-neutral-300 px-3 py-2 font-mono text-xs" />
      <ErrorBanner error={state.error} />
      <Button type="submit" loading={pending} loadingLabel="Creating…" className="w-fit">
        Add tier
      </Button>
    </form>
  );
}

export function EditTierDefinitionDraftForm({ tenantSlug, programId, version }: { tenantSlug: string; programId: string; version: LoyaltyTierDefinition }) {
  const [state, formAction, pending] = useActionState(updateLoyaltyTierDefinitionDraftAction.bind(null, tenantSlug, programId, version.id, version.recordVersion), INITIAL_STATE);
  const [publishState, publishAction, publishPending] = useActionState(publishLoyaltyTierDefinitionAction.bind(null, tenantSlug, programId, version.id, version.recordVersion), INITIAL_STATE);
  return (
    <div className="mt-2 flex flex-col gap-3 rounded-md border border-info/30 bg-info/5 p-3">
      <StatusBadge tone="neutral" label={`Draft v${version.versionNumber}`} />
      <form action={formAction} className="flex flex-col gap-2" noValidate>
        <input type="hidden" name="tierName" value={version.tierName} />
        <label htmlFor={`td-edit-rank-${version.id}`} className="text-xs font-medium text-text-secondary">
          Tier rank
        </label>
        <input id={`td-edit-rank-${version.id}`} name="tierRank" type="number" step="1" min="1" defaultValue={version.tierRank} required className="w-full rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        <label htmlFor={`td-edit-dimension-${version.id}`} className="text-xs font-medium text-text-secondary">
          Threshold dimension
        </label>
        <select id={`td-edit-dimension-${version.id}`} name="thresholdDimension" defaultValue={version.thresholdDimension} className="rounded-md border border-neutral-300 px-2 py-1.5 text-sm">
          <option value="earning_amount_ytd">Year-to-date earning amount (implemented)</option>
        </select>
        <label htmlFor={`td-edit-threshold-${version.id}`} className="text-xs font-medium text-text-secondary">
          Threshold value
        </label>
        <input id={`td-edit-threshold-${version.id}`} name="thresholdValue" type="number" step="0.01" min="0" defaultValue={version.thresholdValue} required className="w-full rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        <label htmlFor={`td-edit-review-${version.id}`} className="text-xs font-medium text-text-secondary">
          Review period (days)
        </label>
        <input id={`td-edit-review-${version.id}`} name="reviewPeriodDays" type="number" step="1" min="0" defaultValue={version.reviewPeriodDays} className="w-full rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        <label htmlFor={`td-edit-benefits-${version.id}`} className="text-xs font-medium text-text-secondary">
          Benefits (JSON object)
        </label>
        <textarea id={`td-edit-benefits-${version.id}`} name="benefits" rows={2} defaultValue={JSON.stringify(version.benefits)} className="w-full rounded-md border border-neutral-300 px-3 py-2 font-mono text-xs" />
        <ErrorBanner error={state.error} />
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
            <input name="reason" placeholder="Hold reason (required)" required className="rounded-md border border-neutral-300 px-2 py-1 text-xs" />
            <ErrorBanner error={holdState.error} />
            <Button type="submit" variant="destructive" loading={holdPending} loadingLabel="Holding…" className="w-fit">
              Hold benefits (fraud/dispute)
            </Button>
          </form>
        )}
      </div>
    </div>
  );
}
