"use client";

import { useActionState } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import { StatusBadge } from "../../../../../../components/ui/status-badge.tsx";
import type { IntakeConfigActionState } from "./actions.ts";
import type { IssueTokenActionState } from "../actions.ts";

const TOGGLE_INITIAL: IntakeConfigActionState = { error: null };
const ISSUE_INITIAL: IssueTokenActionState = { error: null, rawToken: null, intendedEmail: null };

/** PRC-251: self-registration flag toggle (tenant-scoped, off by default -- BP-A08) plus one-time-visible invitation token issuance. */
export function IntakePanel({
  selfRegistrationEnabled,
  tenantSlug,
  toggleAction,
  issueTokenAction,
}: {
  selfRegistrationEnabled: boolean;
  tenantSlug: string;
  toggleAction: (prevState: IntakeConfigActionState, formData: FormData) => Promise<IntakeConfigActionState>;
  issueTokenAction: (prevState: IssueTokenActionState, formData: FormData) => Promise<IssueTokenActionState>;
}) {
  const [toggleState, toggleFormAction, togglePending] = useActionState(toggleAction, TOGGLE_INITIAL);
  const [issueState, issueFormAction, issuePending] = useActionState(issueTokenAction, ISSUE_INITIAL);

  return (
    <div className="flex flex-col gap-4">
      <div>
        <h1 className="text-xl font-semibold text-neutral-900">Vendor intake settings</h1>
        <p className="text-xs text-neutral-500">Invite a specific vendor by email, or allow vendors to self-register a staged (non-authoritative) submission.</p>
      </div>

      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Self-registration</h2>
        <div className="flex items-center gap-2">
          <StatusBadge tone={selfRegistrationEnabled ? "success" : "neutral"} label={selfRegistrationEnabled ? "enabled" : "disabled (default)"} />
        </div>
        <form action={toggleFormAction} className="flex items-center gap-3">
          <label className="flex items-center gap-2 text-sm text-neutral-700">
            <input name="enabled" type="checkbox" defaultChecked={selfRegistrationEnabled} /> Allow vendors to self-register for this organization
          </label>
          <Button type="submit" variant="secondary" loading={togglePending} loadingLabel="Saving…">
            Save
          </Button>
        </form>
        {toggleState.error ? (
          <p role="alert" className="text-sm text-danger">
            {toggleState.error}
          </p>
        ) : null}
        <p className="text-xs text-neutral-400">A self-registered submission is always staged (status=submitted) -- never automatically approved or granted access.</p>
        {selfRegistrationEnabled ? (
          <p className="text-xs text-neutral-600">
            Public registration link: <code className="break-all rounded bg-neutral-100 px-1">/vendor-intake/register/{tenantSlug}</code>
          </p>
        ) : null}
      </section>

      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Invite a vendor</h2>
        <form action={issueFormAction} className="flex flex-wrap items-end gap-2">
          <div className="flex flex-col gap-1">
            <label htmlFor="intendedEmail" className="text-xs font-medium text-neutral-600">
              Vendor email
            </label>
            <input id="intendedEmail" name="intendedEmail" type="email" required className="rounded-md border border-neutral-300 px-2 py-1 text-sm" />
          </div>
          <div className="flex flex-col gap-1">
            <label htmlFor="validityDays" className="text-xs font-medium text-neutral-600">
              Valid for (days)
            </label>
            <input id="validityDays" name="validityDays" type="number" min="1" defaultValue={7} className="rounded-md border border-neutral-300 px-2 py-1 text-sm" />
          </div>
          <Button type="submit" loading={issuePending} loadingLabel="Issuing…">
            Issue invitation
          </Button>
        </form>
        {issueState.error ? (
          <p role="alert" className="text-sm text-danger">
            {issueState.error}
          </p>
        ) : null}
        {issueState.rawToken ? (
          <div role="status" className="rounded-md border border-success/30 bg-success/10 p-3 text-sm">
            <p className="font-medium text-neutral-900">Invitation issued for {issueState.intendedEmail}.</p>
            <p className="mt-1 text-xs text-neutral-600">
              This link is shown once and cannot be retrieved again. Share it with the vendor directly: <code className="break-all rounded bg-neutral-100 px-1">/vendor-intake/{issueState.rawToken}</code>
            </p>
          </div>
        ) : null}
      </section>
    </div>
  );
}
