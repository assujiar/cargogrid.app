"use client";

/**
 * Reward Catalogue admin client forms (CPL-320, CG-S13-CPL-022). Same
 * `useActionState`/bound-action split every prior capability's own
 * create-form already uses (e.g. `admin/loyalty-tiers/loyalty-tier-admin-
 * panel.tsx`).
 */

import { useActionState, useState } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
import { StatusBadge } from "../../../../../components/ui/status-badge.tsx";
import { LOYALTY_REWARD_TERMS_ALLOWED_MIME_TYPES, type LoyaltyReward } from "../../../../../server/contracts/customer-portal-loyalty-rewards/customer-portal-loyalty-rewards.ts";
import type { LoyaltyTierDefinition } from "../../../../../server/contracts/customer-portal-loyalty-tier/customer-portal-loyalty-tier.ts";
import {
  createLoyaltyRewardDraftAction,
  updateLoyaltyRewardDraftAction,
  publishLoyaltyRewardAction,
  pauseLoyaltyRewardAction,
  resumeLoyaltyRewardAction,
  archiveLoyaltyRewardAction,
  enableLoyaltyRewardMediaUploadsAction,
  type LoyaltyRewardAdminFormState,
} from "./actions.ts";

const INITIAL_STATE: LoyaltyRewardAdminFormState = { error: null };

const REWARD_STATUS_TONE = { draft: "neutral", published: "success", paused: "warning", superseded: "neutral", archived: "neutral" } as const;

const MEDIA_UPLOAD_ACCEPT = LOYALTY_REWARD_TERMS_ALLOWED_MIME_TYPES.join(",");

/** describeMediaUploadError in actions.ts phrases this specific failure with this exact wording -- matched here (not a new server call) to decide when to surface the one-time enable action inline. */
function needsMediaUploadsEnabled(error: string | null): boolean {
  return !!error && error.includes("Enable reward media uploads");
}

function ErrorBanner({ error }: { error: string | null }) {
  if (!error) return null;
  return (
    <p role="alert" className="text-sm text-danger">
      {error}
    </p>
  );
}

/** Shown inline once a reward media upload fails with document_type_not_configured -- a one-time (re-runnable) per-tenant setup step, gated identically to every other action in this admin area. */
function EnableMediaUploadsButton({ tenantSlug, programId }: { tenantSlug: string; programId: string }) {
  const [state, formAction, pending] = useActionState(enableLoyaltyRewardMediaUploadsAction.bind(null, tenantSlug, programId), INITIAL_STATE);
  return (
    <form action={formAction} className="mt-1 flex flex-col items-start gap-1" noValidate>
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Enabling…" className="w-fit">
        Enable reward media uploads for this organization
      </Button>
      <ErrorBanner error={state.error} />
    </form>
  );
}

function RewardMediaFileField({ id }: { id: string }) {
  const [selected, setSelected] = useState<File | null>(null);
  return (
    <div className="flex flex-col gap-1">
      <label htmlFor={id} className="text-xs font-medium text-text-secondary">
        Upload terms/media file
      </label>
      <input id={id} type="file" accept={MEDIA_UPLOAD_ACCEPT} onChange={(event) => setSelected(event.currentTarget.files?.[0] ?? null)} className="text-xs" />
      <input type="hidden" name="mediaOriginalFilename" value={selected?.name ?? ""} />
      <input type="hidden" name="mediaMimeType" value={selected?.type || "application/octet-stream"} />
      <input type="hidden" name="mediaSizeBytes" value={selected?.size ?? 0} />
      <p className="text-[11px] text-text-secondary">Choosing a file here overrides the manual file id fallback below.</p>
    </div>
  );
}

function TierSelect({ id, publishedTiers, defaultValue }: { id: string; publishedTiers: readonly LoyaltyTierDefinition[]; defaultValue?: string | null }) {
  return (
    <select id={id} name="minTierId" defaultValue={defaultValue ?? ""} className="rounded-md border border-neutral-300 px-2 py-1.5 text-sm">
      <option value="">No tier requirement</option>
      {publishedTiers.map((tier) => (
        <option key={tier.id} value={tier.id}>
          {tier.tierName}
        </option>
      ))}
    </select>
  );
}

export function CreateLoyaltyRewardForm({ tenantSlug, programId, publishedTiers }: { tenantSlug: string; programId: string; publishedTiers: readonly LoyaltyTierDefinition[] }) {
  const [state, formAction, pending] = useActionState(createLoyaltyRewardDraftAction.bind(null, tenantSlug, programId), INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4" noValidate>
      <h3 className="text-sm font-semibold text-text-primary">Add a reward</h3>
      <label htmlFor="lr-name" className="text-xs font-medium text-text-secondary">
        Reward name
      </label>
      <input id="lr-name" name="rewardName" type="text" required placeholder="e.g. Free Shipping Pass" className="w-full rounded-md border border-neutral-300 px-3 py-2 text-sm" />
      <label htmlFor="lr-type" className="text-xs font-medium text-text-secondary">
        Reward type
      </label>
      <select id="lr-type" name="rewardType" defaultValue="discount_voucher" className="rounded-md border border-neutral-300 px-2 py-1.5 text-sm">
        <option value="discount_voucher">Discount voucher</option>
        <option value="physical_item">Physical item</option>
        <option value="service_credit">Service credit</option>
      </select>
      <label htmlFor="lr-description" className="text-xs font-medium text-text-secondary">
        Description (customer-facing)
      </label>
      <textarea id="lr-description" name="description" rows={2} className="w-full rounded-md border border-neutral-300 px-3 py-2 text-sm" />
      <label htmlFor="lr-terms" className="text-xs font-medium text-text-secondary">
        Terms text (customer-facing)
      </label>
      <textarea id="lr-terms" name="termsText" rows={2} className="w-full rounded-md border border-neutral-300 px-3 py-2 text-sm" />
      <div className="grid grid-cols-2 gap-2">
        <div className="flex flex-col gap-1">
          <label htmlFor="lr-min-tier" className="text-xs font-medium text-text-secondary">
            Minimum tier
          </label>
          <TierSelect id="lr-min-tier" publishedTiers={publishedTiers} />
        </div>
        <div className="flex flex-col gap-1">
          <label htmlFor="lr-min-points" className="text-xs font-medium text-text-secondary">
            Minimum points required
          </label>
          <input id="lr-min-points" name="minPointsRequired" type="number" step="0.01" min="0" className="w-full rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        </div>
        <div className="flex flex-col gap-1">
          <label htmlFor="lr-total-stock" className="text-xs font-medium text-text-secondary">
            Total stock (blank = unlimited)
          </label>
          <input id="lr-total-stock" name="totalStock" type="number" step="1" min="0" className="w-full rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        </div>
        <div className="flex flex-col gap-1">
          <label htmlFor="lr-internal-cost" className="text-xs font-medium text-text-secondary">
            Internal cost (never shown to customers)
          </label>
          <input id="lr-internal-cost" name="internalCost" type="number" step="0.01" min="0" className="w-full rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        </div>
        <div className="flex flex-col gap-1">
          <label htmlFor="lr-vendor-ref" className="text-xs font-medium text-text-secondary">
            Vendor reference (never shown to customers)
          </label>
          <input id="lr-vendor-ref" name="vendorRef" type="text" className="w-full rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        </div>
        <RewardMediaFileField id="lr-media-file" />
        <div className="flex flex-col gap-1">
          <label htmlFor="lr-file-id" className="text-xs font-medium text-text-secondary">
            Manual fallback: an existing file id (e.g. from the Document Center)
          </label>
          <input id="lr-file-id" name="fileId" type="text" placeholder="app.files.id" className="w-full rounded-md border border-neutral-300 px-3 py-2 font-mono text-xs" />
        </div>
      </div>
      <ErrorBanner error={state.error} />
      {needsMediaUploadsEnabled(state.error) ? <EnableMediaUploadsButton tenantSlug={tenantSlug} programId={programId} /> : null}
      <Button type="submit" loading={pending} loadingLabel="Creating…" className="w-fit">
        Add reward
      </Button>
    </form>
  );
}

export function EditLoyaltyRewardDraftForm({ tenantSlug, programId, reward, publishedTiers }: { tenantSlug: string; programId: string; reward: LoyaltyReward; publishedTiers: readonly LoyaltyTierDefinition[] }) {
  const [state, formAction, pending] = useActionState(updateLoyaltyRewardDraftAction.bind(null, tenantSlug, programId, reward.id, reward.recordVersion), INITIAL_STATE);
  const [publishState, publishAction, publishPending] = useActionState(publishLoyaltyRewardAction.bind(null, tenantSlug, programId, reward.id, reward.recordVersion), INITIAL_STATE);
  return (
    <div className="mt-2 flex flex-col gap-3 rounded-md border border-info/30 bg-info/5 p-3">
      <StatusBadge tone="neutral" label={`Draft v${reward.versionNumber}`} />
      <form action={formAction} className="flex flex-col gap-2" noValidate>
        <input type="hidden" name="rewardName" value={reward.rewardName} />
        <label htmlFor={`lr-edit-type-${reward.id}`} className="text-xs font-medium text-text-secondary">
          Reward type
        </label>
        <select id={`lr-edit-type-${reward.id}`} name="rewardType" defaultValue={reward.rewardType} className="rounded-md border border-neutral-300 px-2 py-1.5 text-sm">
          <option value="discount_voucher">Discount voucher</option>
          <option value="physical_item">Physical item</option>
          <option value="service_credit">Service credit</option>
        </select>
        <label htmlFor={`lr-edit-description-${reward.id}`} className="text-xs font-medium text-text-secondary">
          Description
        </label>
        <textarea id={`lr-edit-description-${reward.id}`} name="description" rows={2} defaultValue={reward.description ?? ""} className="w-full rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        <label htmlFor={`lr-edit-terms-${reward.id}`} className="text-xs font-medium text-text-secondary">
          Terms text
        </label>
        <textarea id={`lr-edit-terms-${reward.id}`} name="termsText" rows={2} defaultValue={reward.termsText ?? ""} className="w-full rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        <div className="grid grid-cols-2 gap-2">
          <div className="flex flex-col gap-1">
            <label htmlFor={`lr-edit-min-tier-${reward.id}`} className="text-xs font-medium text-text-secondary">
              Minimum tier
            </label>
            <TierSelect id={`lr-edit-min-tier-${reward.id}`} publishedTiers={publishedTiers} defaultValue={reward.minTierId} />
          </div>
          <div className="flex flex-col gap-1">
            <label htmlFor={`lr-edit-min-points-${reward.id}`} className="text-xs font-medium text-text-secondary">
              Minimum points required
            </label>
            <input id={`lr-edit-min-points-${reward.id}`} name="minPointsRequired" type="number" step="0.01" min="0" defaultValue={reward.minPointsRequired ?? ""} className="w-full rounded-md border border-neutral-300 px-3 py-2 text-sm" />
          </div>
          <div className="flex flex-col gap-1">
            <label htmlFor={`lr-edit-total-stock-${reward.id}`} className="text-xs font-medium text-text-secondary">
              Total stock (blank = unlimited)
            </label>
            <input id={`lr-edit-total-stock-${reward.id}`} name="totalStock" type="number" step="1" min="0" defaultValue={reward.totalStock ?? ""} className="w-full rounded-md border border-neutral-300 px-3 py-2 text-sm" />
          </div>
          <div className="flex flex-col gap-1">
            <label htmlFor={`lr-edit-internal-cost-${reward.id}`} className="text-xs font-medium text-text-secondary">
              Internal cost
            </label>
            <input id={`lr-edit-internal-cost-${reward.id}`} name="internalCost" type="number" step="0.01" min="0" defaultValue={reward.internalCost ?? ""} className="w-full rounded-md border border-neutral-300 px-3 py-2 text-sm" />
          </div>
          <div className="flex flex-col gap-1">
            <label htmlFor={`lr-edit-vendor-ref-${reward.id}`} className="text-xs font-medium text-text-secondary">
              Vendor reference
            </label>
            <input id={`lr-edit-vendor-ref-${reward.id}`} name="vendorRef" type="text" defaultValue={reward.vendorRef ?? ""} className="w-full rounded-md border border-neutral-300 px-3 py-2 text-sm" />
          </div>
          <RewardMediaFileField id={`lr-edit-media-file-${reward.id}`} />
          <div className="flex flex-col gap-1">
            <label htmlFor={`lr-edit-file-id-${reward.id}`} className="text-xs font-medium text-text-secondary">
              Manual fallback: an existing file id (e.g. from the Document Center)
            </label>
            <input id={`lr-edit-file-id-${reward.id}`} name="fileId" type="text" defaultValue={reward.fileId ?? ""} className="w-full rounded-md border border-neutral-300 px-3 py-2 font-mono text-xs" />
          </div>
        </div>
        <ErrorBanner error={state.error} />
        {needsMediaUploadsEnabled(state.error) ? <EnableMediaUploadsButton tenantSlug={tenantSlug} programId={programId} /> : null}
        <Button type="submit" variant="secondary" loading={pending} loadingLabel="Saving…" className="w-fit">
          Save draft
        </Button>
      </form>
      <form action={publishAction} noValidate>
        <p className="text-xs text-text-secondary">Publishing locks this version forever and supersedes this reward&apos;s own current live (published or paused) version, if any.</p>
        <ErrorBanner error={publishState.error} />
        <Button type="submit" loading={publishPending} loadingLabel="Publishing…" className="mt-2 w-fit">
          Publish this version
        </Button>
      </form>
    </div>
  );
}

export function LiveRewardActions({ tenantSlug, programId, reward }: { tenantSlug: string; programId: string; reward: LoyaltyReward }) {
  const [pauseState, pauseAction, pausePending] = useActionState(pauseLoyaltyRewardAction.bind(null, tenantSlug, programId, reward.id, reward.recordVersion), INITIAL_STATE);
  const [resumeState, resumeAction, resumePending] = useActionState(resumeLoyaltyRewardAction.bind(null, tenantSlug, programId, reward.id, reward.recordVersion), INITIAL_STATE);
  const [archiveState, archiveAction, archivePending] = useActionState(archiveLoyaltyRewardAction.bind(null, tenantSlug, programId, reward.id, reward.recordVersion), INITIAL_STATE);

  return (
    <div className="mt-2 flex flex-wrap items-end gap-3">
      {reward.status === "published" ? (
        <form action={pauseAction} className="flex items-end gap-2" noValidate>
          <input name="reason" placeholder="Pause reason (optional)" className="rounded-md border border-neutral-300 px-2 py-1 text-xs" />
          <ErrorBanner error={pauseState.error} />
          <Button type="submit" variant="secondary" loading={pausePending} loadingLabel="Pausing…" className="w-fit">
            Pause
          </Button>
        </form>
      ) : null}
      {reward.status === "paused" ? (
        <form action={resumeAction} noValidate>
          <ErrorBanner error={resumeState.error} />
          <Button type="submit" loading={resumePending} loadingLabel="Resuming…" className="w-fit">
            Resume
          </Button>
        </form>
      ) : null}
      <form action={archiveAction} className="flex items-end gap-2" noValidate>
        <input name="reason" placeholder="Archive reason (optional)" className="rounded-md border border-neutral-300 px-2 py-1 text-xs" />
        <ErrorBanner error={archiveState.error} />
        <Button type="submit" variant="destructive" loading={archivePending} loadingLabel="Archiving…" className="w-fit">
          Archive
        </Button>
      </form>
    </div>
  );
}

export function LoyaltyRewardHistory({ tenantSlug, programId, rewards }: { tenantSlug: string; programId: string; rewards: readonly LoyaltyReward[] }) {
  const nonDraft = rewards.filter((reward) => reward.status !== "draft");
  if (nonDraft.length === 0) {
    return <p className="text-xs text-text-secondary">No published reward version yet.</p>;
  }
  return (
    <div className="overflow-x-auto rounded-md border border-neutral-200">
      <table className="w-full border-collapse text-sm">
        <caption className="sr-only">Published, paused, superseded, and archived rewards</caption>
        <thead>
          <tr className="text-left text-xs font-medium text-text-secondary">
            <th className="p-2">Reward</th>
            <th className="p-2">Version</th>
            <th className="p-2">Status</th>
            <th className="p-2">Type</th>
            <th className="p-2">Effective from</th>
            <th className="p-2">Effective to</th>
            <th className="p-2">Actions</th>
          </tr>
        </thead>
        <tbody>
          {nonDraft.map((reward) => (
            <tr key={reward.id} className="border-t border-neutral-100 align-top">
              <td className="p-2">{reward.rewardName}</td>
              <td className="p-2">v{reward.versionNumber}</td>
              <td className="p-2">
                <StatusBadge tone={REWARD_STATUS_TONE[reward.status] ?? "neutral"} label={reward.status} />
              </td>
              <td className="p-2">{reward.rewardType}</td>
              <td className="p-2 text-xs text-text-secondary">{reward.effectiveFrom ? new Date(reward.effectiveFrom).toLocaleString() : "—"}</td>
              <td className="p-2 text-xs text-text-secondary">{reward.effectiveTo ? new Date(reward.effectiveTo).toLocaleString() : "—"}</td>
              <td className="p-2">{reward.status === "published" || reward.status === "paused" ? <LiveRewardActions tenantSlug={tenantSlug} programId={programId} reward={reward} /> : null}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
