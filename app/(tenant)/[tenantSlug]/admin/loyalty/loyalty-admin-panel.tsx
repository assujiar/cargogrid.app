"use client";

/**
 * Loyalty Program and Earning admin client forms (CPL-316, CG-S13-CPL-018).
 * Same `useActionState`/bound-action split every prior capability's own
 * create-form already uses (e.g. `finance/config/finance-config-forms.tsx`).
 */

import { useActionState } from "react";
import Link from "next/link";
import { Button } from "../../../../../components/ui/button.tsx";
import { StatusBadge, type StatusTone } from "../../../../../components/ui/status-badge.tsx";
import { EmptyState } from "../../../../../components/ui/empty-state.tsx";
import type {
  LoyaltyProgram,
  LoyaltyProgramStatus,
  LoyaltyProgramRuleVersion,
  LoyaltyAccount,
  LoyaltyAccountStatus,
  LoyaltyEarningEvent,
} from "../../../../../server/contracts/customer-portal-loyalty-program/customer-portal-loyalty-program.ts";
import {
  createLoyaltyProgramAction,
  updateLoyaltyProgramStatusAction,
  createLoyaltyProgramRuleVersionAction,
  updateLoyaltyProgramRuleVersionDraftAction,
  publishLoyaltyProgramRuleVersionAction,
  enrollCustomerLoyaltyAccountAction,
  setLoyaltyAccountStatusAction,
  evaluateCustomerLoyaltyEarningForPaidInvoiceAction,
  reverseLoyaltyEarningEventAction,
  type LoyaltyAdminFormState,
} from "./actions.ts";

const INITIAL_STATE: LoyaltyAdminFormState = { error: null };

const PROGRAM_STATUS_TONE: Record<LoyaltyProgramStatus, StatusTone> = { draft: "neutral", active: "success", inactive: "warning" };
const RULE_VERSION_STATUS_TONE = { draft: "neutral", published: "success", superseded: "neutral" } as const;
const ACCOUNT_STATUS_TONE: Record<LoyaltyAccountStatus, StatusTone> = { active: "success", suspended: "warning", closed: "neutral" };

function ErrorBanner({ error }: { error: string | null }) {
  if (!error) return null;
  return (
    <p role="alert" className="text-sm text-danger">
      {error}
    </p>
  );
}

export function CreateProgramForm({ tenantSlug }: { tenantSlug: string }) {
  const [state, formAction, pending] = useActionState(createLoyaltyProgramAction.bind(null, tenantSlug), INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4" noValidate>
      <h2 className="text-sm font-semibold text-text-primary">Create a loyalty program</h2>
      <label htmlFor="lp-name" className="text-xs font-medium text-text-secondary">
        Program name
      </label>
      <input id="lp-name" name="name" type="text" required className="w-full rounded-md border border-neutral-300 px-3 py-2 text-sm" />
      <label htmlFor="lp-description" className="text-xs font-medium text-text-secondary">
        Description (optional)
      </label>
      <textarea id="lp-description" name="description" rows={2} className="w-full rounded-md border border-neutral-300 px-3 py-2 text-sm" />
      <ErrorBanner error={state.error} />
      <Button type="submit" loading={pending} loadingLabel="Creating…" className="w-fit">
        Create program
      </Button>
    </form>
  );
}

export function ProgramList({ tenantSlug, programs }: { tenantSlug: string; programs: readonly LoyaltyProgram[] }) {
  if (programs.length === 0) {
    return <EmptyState title="No loyalty programs yet" description="Create your tenant's first loyalty program above." />;
  }
  return (
    <div className="overflow-x-auto rounded-md border border-neutral-200">
      <table className="w-full border-collapse text-sm">
        <caption className="sr-only">Loyalty programs</caption>
        <thead>
          <tr className="text-left text-xs font-medium text-text-secondary">
            <th className="p-2">Name</th>
            <th className="p-2">Status</th>
            <th className="p-2">Updated</th>
          </tr>
        </thead>
        <tbody>
          {programs.map((program) => (
            <tr key={program.id} className="border-t border-neutral-100">
              <td className="p-2">
                <Link href={`/${tenantSlug}/admin/loyalty?programId=${program.id}`} className="font-medium text-primary underline">
                  {program.name}
                </Link>
              </td>
              <td className="p-2">
                <StatusBadge tone={PROGRAM_STATUS_TONE[program.status]} label={program.status} />
              </td>
              <td className="p-2 text-xs text-text-secondary">{new Date(program.updatedAt).toLocaleString()}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

export function ProgramStatusForm({ tenantSlug, program }: { tenantSlug: string; program: LoyaltyProgram }) {
  const nextStatus: LoyaltyProgramStatus | null = program.status === "draft" ? "active" : program.status === "active" ? "inactive" : "active";
  const label = program.status === "draft" ? "Activate" : program.status === "active" ? "Deactivate" : "Reactivate";
  const [state, formAction, pending] = useActionState(updateLoyaltyProgramStatusAction.bind(null, tenantSlug, program.id, program.recordVersion, nextStatus), INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col gap-2" noValidate>
      <ErrorBanner error={state.error} />
      <Button type="submit" variant={nextStatus === "inactive" ? "destructive" : "primary"} loading={pending} loadingLabel="Updating…" className="w-fit">
        {label}
      </Button>
    </form>
  );
}

export function CreateRuleVersionForm({ tenantSlug, programId, disabled }: { tenantSlug: string; programId: string; disabled: boolean }) {
  const [state, formAction, pending] = useActionState(createLoyaltyProgramRuleVersionAction.bind(null, tenantSlug, programId), INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4" noValidate>
      <h3 className="text-sm font-semibold text-text-primary">Start a new draft rule version</h3>
      {disabled ? <p className="text-xs text-text-secondary">This program already has an open draft -- edit or publish it below before starting another.</p> : null}
      <label htmlFor="rv-basis" className="text-xs font-medium text-text-secondary">
        Earning basis
      </label>
      <select id="rv-basis" name="earningBasis" defaultValue="per_paid_invoice_amount" disabled={disabled} className="rounded-md border border-neutral-300 px-2 py-1.5 text-sm">
        <option value="per_paid_invoice_amount">Per paid invoice amount (implemented)</option>
      </select>
      <label htmlFor="rv-reward" className="text-xs font-medium text-text-secondary">
        Reward type
      </label>
      <select id="rv-reward" name="rewardType" defaultValue="points" disabled={disabled} className="rounded-md border border-neutral-300 px-2 py-1.5 text-sm">
        <option value="points">Points</option>
        <option value="cashback">Cashback</option>
      </select>
      <label htmlFor="rv-rate" className="text-xs font-medium text-text-secondary">
        Rate (e.g. 0.1 = 10% of the paid amount)
      </label>
      <input id="rv-rate" name="rate" type="number" step="0.0001" min="0.0001" required disabled={disabled} className="w-full rounded-md border border-neutral-300 px-3 py-2 text-sm" />
      <label htmlFor="rv-min" className="text-xs font-medium text-text-secondary">
        Minimum invoice amount to be eligible (optional)
      </label>
      <input id="rv-min" name="minInvoiceAmount" type="number" step="0.01" min="0" disabled={disabled} className="w-full rounded-md border border-neutral-300 px-3 py-2 text-sm" />
      <ErrorBanner error={state.error} />
      <Button type="submit" loading={pending} loadingLabel="Creating…" disabled={disabled} className="w-fit">
        Create draft
      </Button>
    </form>
  );
}

export function EditRuleVersionDraftForm({ tenantSlug, programId, version }: { tenantSlug: string; programId: string; version: LoyaltyProgramRuleVersion }) {
  const [state, formAction, pending] = useActionState(updateLoyaltyProgramRuleVersionDraftAction.bind(null, tenantSlug, programId, version.id, version.recordVersion), INITIAL_STATE);
  const [publishState, publishAction, publishPending] = useActionState(publishLoyaltyProgramRuleVersionAction.bind(null, tenantSlug, programId, version.id, version.recordVersion), INITIAL_STATE);
  return (
    <div className="flex flex-col gap-3 rounded-md border border-info/30 bg-info/5 p-4">
      <div className="flex items-center gap-2">
        <StatusBadge tone="neutral" label={`Draft v${version.versionNumber}`} />
      </div>
      <form action={formAction} className="flex flex-col gap-2" noValidate>
        <label htmlFor={`rv-edit-basis-${version.id}`} className="text-xs font-medium text-text-secondary">
          Earning basis
        </label>
        <select id={`rv-edit-basis-${version.id}`} name="earningBasis" defaultValue={version.earningBasis} className="rounded-md border border-neutral-300 px-2 py-1.5 text-sm">
          <option value="per_paid_invoice_amount">Per paid invoice amount (implemented)</option>
        </select>
        <label htmlFor={`rv-edit-reward-${version.id}`} className="text-xs font-medium text-text-secondary">
          Reward type
        </label>
        <select id={`rv-edit-reward-${version.id}`} name="rewardType" defaultValue={version.rewardType} className="rounded-md border border-neutral-300 px-2 py-1.5 text-sm">
          <option value="points">Points</option>
          <option value="cashback">Cashback</option>
        </select>
        <label htmlFor={`rv-edit-rate-${version.id}`} className="text-xs font-medium text-text-secondary">
          Rate
        </label>
        <input id={`rv-edit-rate-${version.id}`} name="rate" type="number" step="0.0001" min="0.0001" defaultValue={version.rate} required className="w-full rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        <label htmlFor={`rv-edit-min-${version.id}`} className="text-xs font-medium text-text-secondary">
          Minimum invoice amount (optional)
        </label>
        <input
          id={`rv-edit-min-${version.id}`}
          name="minInvoiceAmount"
          type="number"
          step="0.01"
          min="0"
          defaultValue={typeof version.eligibilityConfig.min_invoice_amount === "number" ? version.eligibilityConfig.min_invoice_amount : ""}
          className="w-full rounded-md border border-neutral-300 px-3 py-2 text-sm"
        />
        <ErrorBanner error={state.error} />
        <Button type="submit" variant="secondary" loading={pending} loadingLabel="Saving…" className="w-fit">
          Save draft
        </Button>
      </form>
      <form action={publishAction} noValidate>
        <p className="text-xs text-text-secondary">Publishing locks this version forever and supersedes the program&apos;s current published version, if any -- historical earning events already recorded keep the rule they were evaluated under.</p>
        <ErrorBanner error={publishState.error} />
        <Button type="submit" loading={publishPending} loadingLabel="Publishing…" className="mt-2 w-fit">
          Publish this version
        </Button>
      </form>
    </div>
  );
}

export function RuleVersionHistory({ versions }: { versions: readonly LoyaltyProgramRuleVersion[] }) {
  const historical = versions.filter((version) => version.status !== "draft");
  if (historical.length === 0) {
    return <p className="text-xs text-text-secondary">No published rule version yet.</p>;
  }
  return (
    <div className="overflow-x-auto rounded-md border border-neutral-200">
      <table className="w-full border-collapse text-sm">
        <caption className="sr-only">Published and superseded rule versions</caption>
        <thead>
          <tr className="text-left text-xs font-medium text-text-secondary">
            <th className="p-2">Version</th>
            <th className="p-2">Status</th>
            <th className="p-2">Reward</th>
            <th className="p-2 text-right">Rate</th>
            <th className="p-2">Effective from</th>
            <th className="p-2">Effective to</th>
          </tr>
        </thead>
        <tbody>
          {historical.map((version) => (
            <tr key={version.id} className="border-t border-neutral-100">
              <td className="p-2">v{version.versionNumber}</td>
              <td className="p-2">
                <StatusBadge tone={RULE_VERSION_STATUS_TONE[version.status] ?? "neutral"} label={version.status} />
              </td>
              <td className="p-2">{version.rewardType}</td>
              <td className="p-2 text-right tabular-nums">{version.rate}</td>
              <td className="p-2 text-xs text-text-secondary">{version.effectiveFrom ? new Date(version.effectiveFrom).toLocaleString() : "—"}</td>
              <td className="p-2 text-xs text-text-secondary">{version.effectiveTo ? new Date(version.effectiveTo).toLocaleString() : "—"}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

export function EnrollAccountForm({ tenantSlug, programId }: { tenantSlug: string; programId: string }) {
  const [state, formAction, pending] = useActionState(enrollCustomerLoyaltyAccountAction.bind(null, tenantSlug, programId), INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4" noValidate>
      <h3 className="text-sm font-semibold text-text-primary">Enroll a customer account</h3>
      <label htmlFor="ea-account" className="text-xs font-medium text-text-secondary">
        Customer account ID
      </label>
      <input id="ea-account" name="customerAccountId" type="text" required className="w-full rounded-md border border-neutral-300 px-3 py-2 font-mono text-xs" />
      <p className="text-xs text-text-secondary">An account may hold at most one active loyalty enrollment at a time, across every program.</p>
      <ErrorBanner error={state.error} />
      <Button type="submit" loading={pending} loadingLabel="Enrolling…" className="w-fit">
        Enroll
      </Button>
    </form>
  );
}

export function AccountList({ tenantSlug, programId, accounts }: { tenantSlug: string; programId: string; accounts: readonly LoyaltyAccount[] }) {
  if (accounts.length === 0) {
    return <EmptyState title="No enrolled accounts yet" description="Enroll a customer account above to start earning." />;
  }
  return (
    <div className="flex flex-col gap-3">
      {accounts.map((account) => (
        <AccountRow key={account.id} tenantSlug={tenantSlug} programId={programId} account={account} />
      ))}
    </div>
  );
}

/** Only ever rendered for an active/suspended account (AccountList filters closed rows out visually below), so the active<->suspended toggle is always well-defined. */
function AccountRow({ tenantSlug, programId, account }: { tenantSlug: string; programId: string; account: LoyaltyAccount }) {
  const nextStatus: LoyaltyAccountStatus = account.status === "active" ? "suspended" : "active";
  const [state, formAction, pending] = useActionState(setLoyaltyAccountStatusAction.bind(null, tenantSlug, programId, account.id, account.recordVersion, nextStatus), INITIAL_STATE);
  const [closeState, closeAction, closePending] = useActionState(setLoyaltyAccountStatusAction.bind(null, tenantSlug, programId, account.id, account.recordVersion, "closed"), INITIAL_STATE);
  if (account.status === "closed") {
    return (
      <div className="flex items-center justify-between gap-2 rounded-md border border-neutral-200 p-3">
        <p className="font-mono text-xs text-text-secondary">{account.customerAccountId}</p>
        <StatusBadge tone={ACCOUNT_STATUS_TONE.closed} label="closed" />
      </div>
    );
  }
  return (
    <div className="flex flex-wrap items-center justify-between gap-2 rounded-md border border-neutral-200 p-3">
      <div>
        <p className="font-mono text-xs text-text-secondary">{account.customerAccountId}</p>
        <StatusBadge tone={ACCOUNT_STATUS_TONE[account.status]} label={account.status} />
      </div>
      <div className="flex flex-wrap gap-3">
        <form action={formAction} className="flex items-end gap-2" noValidate>
          {nextStatus === "suspended" ? <input name="reason" placeholder="Reason (required)" required className="rounded-md border border-neutral-300 px-2 py-1 text-xs" /> : null}
          <ErrorBanner error={state.error} />
          <Button type="submit" variant={nextStatus === "suspended" ? "destructive" : "secondary"} loading={pending} loadingLabel="Updating…" className="w-fit">
            {nextStatus === "suspended" ? "Suspend" : "Reactivate"}
          </Button>
        </form>
        <form action={closeAction} className="flex items-end gap-2" noValidate>
          <input name="reason" placeholder="Reason (required)" required className="rounded-md border border-neutral-300 px-2 py-1 text-xs" />
          <ErrorBanner error={closeState.error} />
          <Button type="submit" variant="destructive" loading={closePending} loadingLabel="Closing…" className="w-fit">
            Close
          </Button>
        </form>
      </div>
    </div>
  );
}

export function EvaluateEarningForm({ tenantSlug, programId }: { tenantSlug: string; programId: string }) {
  const [state, formAction, pending] = useActionState(evaluateCustomerLoyaltyEarningForPaidInvoiceAction.bind(null, tenantSlug, programId), INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4" noValidate>
      <h3 className="text-sm font-semibold text-text-primary">Evaluate earning for a paid invoice</h3>
      <p className="text-xs text-text-secondary">
        On-demand only in this checkpoint -- no automatic job triggers this yet (a real, complete, idempotent RPC; the trigger mechanism is a disclosed follow-up, see ISS-2026-126). Calling this twice for the same AR open item is a safe no-op.
      </p>
      <label htmlFor="ee-ar" className="text-xs font-medium text-text-secondary">
        AR open item ID (the paid invoice)
      </label>
      <input id="ee-ar" name="arOpenItemId" type="text" required className="w-full rounded-md border border-neutral-300 px-3 py-2 font-mono text-xs" />
      <ErrorBanner error={state.error} />
      <Button type="submit" loading={pending} loadingLabel="Evaluating…" className="w-fit">
        Evaluate earning
      </Button>
    </form>
  );
}

export function EarningEventList({ tenantSlug, programId, events }: { tenantSlug: string; programId: string; events: readonly LoyaltyEarningEvent[] }) {
  if (events.length === 0) {
    return <EmptyState title="No earning events yet" description="Earning events for this program will appear here once evaluated." />;
  }
  return (
    <div className="overflow-x-auto rounded-md border border-neutral-200">
      <table className="w-full border-collapse text-sm">
        <caption className="sr-only">Recent earning events</caption>
        <thead>
          <tr className="text-left text-xs font-medium text-text-secondary">
            <th className="p-2">Amount</th>
            <th className="p-2">Type</th>
            <th className="p-2">Source</th>
            <th className="p-2">Reason</th>
            <th className="p-2">Created</th>
            <th className="p-2">Action</th>
          </tr>
        </thead>
        <tbody>
          {events.map((event) => (
            <EarningEventRow key={event.id} tenantSlug={tenantSlug} programId={programId} event={event} />
          ))}
        </tbody>
      </table>
    </div>
  );
}

function EarningEventRow({ tenantSlug, programId, event }: { tenantSlug: string; programId: string; event: LoyaltyEarningEvent }) {
  const [state, formAction, pending] = useActionState(reverseLoyaltyEarningEventAction.bind(null, tenantSlug, programId, event.id), INITIAL_STATE);
  const isReversal = event.correctsEventId !== null;
  return (
    <tr className="border-t border-neutral-100">
      <td className="p-2 tabular-nums">{event.amount}</td>
      <td className="p-2">{event.rewardType}</td>
      <td className="p-2 text-xs">{isReversal ? `Reversal of ${event.correctsEventId}` : event.sourceType}</td>
      <td className="p-2 text-xs text-text-secondary">{event.reason ?? "—"}</td>
      <td className="p-2 text-xs text-text-secondary">{new Date(event.createdAt).toLocaleString()}</td>
      <td className="p-2">
        {!isReversal ? (
          <form action={formAction} className="flex items-center gap-2" noValidate>
            <input name="reason" placeholder="Reason (required)" required className="rounded-md border border-neutral-300 px-2 py-1 text-xs" />
            <ErrorBanner error={state.error} />
            <Button type="submit" variant="destructive" loading={pending} loadingLabel="Reversing…" className="w-fit">
              Reverse
            </Button>
          </form>
        ) : (
          <span className="text-xs text-text-secondary">—</span>
        )}
      </td>
    </tr>
  );
}
