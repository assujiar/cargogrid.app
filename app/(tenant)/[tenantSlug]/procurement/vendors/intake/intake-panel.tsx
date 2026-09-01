"use client";

import { useActionState } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import { StatusBadge } from "../../../../../../components/ui/status-badge.tsx";
import { FormField } from "../../../../../../components/forms/form-field.tsx";
import { Input } from "../../../../../../components/forms/input.tsx";
import { Checkbox } from "../../../../../../components/forms/checkbox.tsx";
import { ValidationMessage } from "../../../../../../components/forms/validation-message.tsx";
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
          <Checkbox id="enabled" name="enabled" defaultChecked={selfRegistrationEnabled} label="Allow vendors to self-register for this organization" />
          <Button type="submit" variant="secondary" loading={togglePending} loadingLabel="Saving…">
            Save
          </Button>
        </form>
        {toggleState.error ? <ValidationMessage>{toggleState.error}</ValidationMessage> : null}
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
          <FormField id="intendedEmail" label={<span className="text-xs font-medium text-neutral-600">Vendor email</span>} error={issueState.error ?? undefined}>
            <Input id="intendedEmail" name="intendedEmail" type="email" required invalid={Boolean(issueState.error)} />
          </FormField>
          <FormField id="validityDays" label={<span className="text-xs font-medium text-neutral-600">Valid for (days)</span>}>
            <Input id="validityDays" name="validityDays" type="number" min="1" defaultValue={7} />
          </FormField>
          <Button type="submit" loading={issuePending} loadingLabel="Issuing…">
            Issue invitation
          </Button>
        </form>
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
