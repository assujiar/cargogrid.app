"use client";

/**
 * Reward Catalogue admin client forms (CPL-320, CG-S13-CPL-022). Same
 * `useActionState`/bound-action split every prior capability's own
 * create-form already uses (e.g. `admin/loyalty-tiers/loyalty-tier-admin-
 * panel.tsx`).
 */

import { useActionState, useState } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
import { Input } from "../../../../../components/forms/input.tsx";
import { Select } from "../../../../../components/forms/select.tsx";
import { Textarea } from "../../../../../components/forms/textarea.tsx";
import { NumberInput } from "../../../../../components/forms/number-input.tsx";
import { FormField } from "../../../../../components/forms/form-field.tsx";
import { ValidationMessage } from "../../../../../components/forms/validation-message.tsx";
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

/** ISS-2026-242: the shared field-error renderer -- `id` is what each control's `aria-describedby` points at. */
function ErrorBanner({ id, error }: { id?: string; error: string | null }) {
  if (!error) return null;
  return <ValidationMessage id={id}>{error}</ValidationMessage>;
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
    <FormField id={id} label="Upload terms/media file" helpText="Choosing a file here overrides the manual file id fallback below.">
      <Input
        id={id}
        type="file"
        accept={MEDIA_UPLOAD_ACCEPT}
        onChange={(event) => setSelected(event.currentTarget.files?.[0] ?? null)}
        className="text-xs"
        aria-describedby={`${id}-help`}
      />
      <input type="hidden" name="mediaOriginalFilename" value={selected?.name ?? ""} />
      <input type="hidden" name="mediaMimeType" value={selected?.type || "application/octet-stream"} />
      <input type="hidden" name="mediaSizeBytes" value={selected?.size ?? 0} />
    </FormField>
  );
}

function TierSelect({
  id,
  publishedTiers,
  defaultValue,
  invalid,
  describedBy,
}: {
  id: string;
  publishedTiers: readonly LoyaltyTierDefinition[];
  defaultValue?: string | null;
  invalid?: boolean;
  describedBy?: string;
}) {
  return (
    <Select id={id} name="minTierId" defaultValue={defaultValue ?? ""} invalid={invalid} aria-describedby={describedBy}>
      <option value="">No tier requirement</option>
      {publishedTiers.map((tier) => (
        <option key={tier.id} value={tier.id}>
          {tier.tierName}
        </option>
      ))}
    </Select>
  );
}

export function CreateLoyaltyRewardForm({ tenantSlug, programId, publishedTiers }: { tenantSlug: string; programId: string; publishedTiers: readonly LoyaltyTierDefinition[] }) {
  const [state, formAction, pending] = useActionState(createLoyaltyRewardDraftAction.bind(null, tenantSlug, programId), INITIAL_STATE);
  // ISS-2026-242: the draft RPC returns one error for the whole reward, never per-field ones.
  const describedBy = state.error ? "lr-create-error" : undefined;
  return (
    <form action={formAction} className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4" noValidate>
      <h3 className="text-sm font-semibold text-text-primary">Add a reward</h3>
      <FormField id="lr-name" label="Reward name">
        <Input id="lr-name" name="rewardName" type="text" required placeholder="e.g. Free Shipping Pass" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <FormField id="lr-type" label="Reward type">
        <Select id="lr-type" name="rewardType" defaultValue="discount_voucher" invalid={Boolean(state.error)} aria-describedby={describedBy}>
          <option value="discount_voucher">Discount voucher</option>
          <option value="physical_item">Physical item</option>
          <option value="service_credit">Service credit</option>
        </Select>
      </FormField>
      <FormField id="lr-description" label="Description (customer-facing)">
        <Textarea id="lr-description" name="description" rows={2} invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <FormField id="lr-terms" label="Terms text (customer-facing)">
        <Textarea id="lr-terms" name="termsText" rows={2} invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <div className="grid grid-cols-2 gap-2">
        <FormField id="lr-min-tier" label="Minimum tier">
          <TierSelect id="lr-min-tier" publishedTiers={publishedTiers} invalid={Boolean(state.error)} describedBy={describedBy} />
        </FormField>
        <FormField id="lr-min-points" label="Minimum points required">
          <NumberInput id="lr-min-points" name="minPointsRequired" step="0.01" min="0" invalid={Boolean(state.error)} aria-describedby={describedBy} />
        </FormField>
        <FormField id="lr-total-stock" label="Total stock (blank = unlimited)">
          <NumberInput id="lr-total-stock" name="totalStock" step="1" min="0" invalid={Boolean(state.error)} aria-describedby={describedBy} />
        </FormField>
        <FormField id="lr-internal-cost" label="Internal cost (never shown to customers)">
          <Input type="number" inputMode="decimal" id="lr-internal-cost" name="internalCost" step="0.01" min="0" invalid={Boolean(state.error)} aria-describedby={describedBy} />
        </FormField>
        <FormField id="lr-vendor-ref" label="Vendor reference (never shown to customers)">
          <Input id="lr-vendor-ref" name="vendorRef" type="text" invalid={Boolean(state.error)} aria-describedby={describedBy} />
        </FormField>
        <RewardMediaFileField id="lr-media-file" />
        <FormField id="lr-file-id" label="Manual fallback: an existing file id (e.g. from the Document Center)">
          <Input id="lr-file-id" name="fileId" type="text" placeholder="app.files.id" className="font-mono text-xs" invalid={Boolean(state.error)} aria-describedby={describedBy} />
        </FormField>
      </div>
      <ErrorBanner id="lr-create-error" error={state.error} />
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
  // ISS-2026-242: the update RPC returns one error for the whole draft, never per-field ones.
  const describedBy = state.error ? `lr-edit-${reward.id}-error` : undefined;
  return (
    <div className="mt-2 flex flex-col gap-3 rounded-md border border-info/30 bg-info/5 p-3">
      <StatusBadge tone="neutral" label={`Draft v${reward.versionNumber}`} />
      <form action={formAction} className="flex flex-col gap-2" noValidate>
        <input type="hidden" name="rewardName" value={reward.rewardName} />
        <FormField id={`lr-edit-type-${reward.id}`} label="Reward type">
          <Select id={`lr-edit-type-${reward.id}`} name="rewardType" defaultValue={reward.rewardType} invalid={Boolean(state.error)} aria-describedby={describedBy}>
            <option value="discount_voucher">Discount voucher</option>
            <option value="physical_item">Physical item</option>
            <option value="service_credit">Service credit</option>
          </Select>
        </FormField>
        <FormField id={`lr-edit-description-${reward.id}`} label="Description">
          <Textarea id={`lr-edit-description-${reward.id}`} name="description" rows={2} defaultValue={reward.description ?? ""} invalid={Boolean(state.error)} aria-describedby={describedBy} />
        </FormField>
        <FormField id={`lr-edit-terms-${reward.id}`} label="Terms text">
          <Textarea id={`lr-edit-terms-${reward.id}`} name="termsText" rows={2} defaultValue={reward.termsText ?? ""} invalid={Boolean(state.error)} aria-describedby={describedBy} />
        </FormField>
        <div className="grid grid-cols-2 gap-2">
          <FormField id={`lr-edit-min-tier-${reward.id}`} label="Minimum tier">
            <TierSelect id={`lr-edit-min-tier-${reward.id}`} publishedTiers={publishedTiers} defaultValue={reward.minTierId} invalid={Boolean(state.error)} describedBy={describedBy} />
          </FormField>
          <FormField id={`lr-edit-min-points-${reward.id}`} label="Minimum points required">
            <NumberInput
              id={`lr-edit-min-points-${reward.id}`}
              name="minPointsRequired"
              step="0.01"
              min="0"
              defaultValue={reward.minPointsRequired ?? ""}
              invalid={Boolean(state.error)}
              aria-describedby={describedBy}
            />
          </FormField>
          <FormField id={`lr-edit-total-stock-${reward.id}`} label="Total stock (blank = unlimited)">
            <NumberInput
              id={`lr-edit-total-stock-${reward.id}`}
              name="totalStock"
              step="1"
              min="0"
              defaultValue={reward.totalStock ?? ""}
              invalid={Boolean(state.error)}
              aria-describedby={describedBy}
            />
          </FormField>
          <FormField id={`lr-edit-internal-cost-${reward.id}`} label="Internal cost">
            <NumberInput
              id={`lr-edit-internal-cost-${reward.id}`}
              name="internalCost"
              step="0.01"
              min="0"
              defaultValue={reward.internalCost ?? ""}
              invalid={Boolean(state.error)}
              aria-describedby={describedBy}
            />
          </FormField>
          <FormField id={`lr-edit-vendor-ref-${reward.id}`} label="Vendor reference">
            <Input id={`lr-edit-vendor-ref-${reward.id}`} name="vendorRef" type="text" defaultValue={reward.vendorRef ?? ""} invalid={Boolean(state.error)} aria-describedby={describedBy} />
          </FormField>
          <RewardMediaFileField id={`lr-edit-media-file-${reward.id}`} />
          <FormField id={`lr-edit-file-id-${reward.id}`} label="Manual fallback: an existing file id (e.g. from the Document Center)">
            <Input
              id={`lr-edit-file-id-${reward.id}`}
              name="fileId"
              type="text"
              defaultValue={reward.fileId ?? ""}
              className="font-mono text-xs"
              invalid={Boolean(state.error)}
              aria-describedby={describedBy}
            />
          </FormField>
        </div>
        <ErrorBanner id={`lr-edit-${reward.id}-error`} error={state.error} />
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
          <label htmlFor={`lr-pause-reason-${reward.id}`} className="sr-only">
            Pause reason
          </label>
          <Input
            id={`lr-pause-reason-${reward.id}`}
            name="reason"
            placeholder="Pause reason (optional)"
            className="text-xs"
            invalid={Boolean(pauseState.error)}
            aria-describedby={pauseState.error ? `lr-pause-${reward.id}-error` : undefined}
          />
          <ErrorBanner id={`lr-pause-${reward.id}-error`} error={pauseState.error} />
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
        <label htmlFor={`lr-archive-reason-${reward.id}`} className="sr-only">
          Archive reason
        </label>
        <Input
          id={`lr-archive-reason-${reward.id}`}
          name="reason"
          placeholder="Archive reason (optional)"
          className="text-xs"
          invalid={Boolean(archiveState.error)}
          aria-describedby={archiveState.error ? `lr-archive-${reward.id}-error` : undefined}
        />
        <ErrorBanner id={`lr-archive-${reward.id}-error`} error={archiveState.error} />
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
