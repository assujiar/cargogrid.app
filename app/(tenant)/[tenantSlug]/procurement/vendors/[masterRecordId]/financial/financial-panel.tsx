"use client";

import { useActionState, useId, useState, useTransition } from "react";
import { Button } from "../../../../../../../components/ui/button.tsx";
import { StatusBadge, type StatusTone } from "../../../../../../../components/ui/status-badge.tsx";
import { EmptyState } from "../../../../../../../components/ui/empty-state.tsx";
import { Input } from "../../../../../../../components/forms/input.tsx";
import { Select } from "../../../../../../../components/forms/select.tsx";
import { Checkbox } from "../../../../../../../components/forms/checkbox.tsx";
import { FormField } from "../../../../../../../components/forms/form-field.tsx";
import { ValidationMessage } from "../../../../../../../components/forms/validation-message.tsx";
import type { VendorFinancialActionState, VendorBankAccountRevealActionState, VendorTaxIdentityRevealActionState, VendorFinancialEvidenceAccessState } from "./actions.ts";
import type {
  VendorBankAccount,
  VendorTaxIdentity,
  VendorPaymentTermProposal,
  VendorFinancialVerificationStatus,
  VendorFinancialLifecycleStatus,
  VendorFinancialDecision,
  VendorFinancialAccessType,
} from "../../../../../../../server/contracts/vendor-financial/vendor-financial.ts";
import type { VendorProfile } from "../../../../../../../server/contracts/vendor-profile/vendor-profile.ts";

const INITIAL_STATE: VendorFinancialActionState = { error: null };

const LIFECYCLE_TONE: Record<VendorFinancialLifecycleStatus, StatusTone> = {
  draft: "neutral",
  pending_approval: "info",
  active: "success",
  rejected: "danger",
  hold: "warning",
  deactivated: "neutral",
};

type PlainAction = (prevState: VendorFinancialActionState, formData: FormData) => Promise<VendorFinancialActionState>;

/**
 * hold/reactivate/deactivate all now require the same client-captured reauth
 * attestation timestamp as DecideForm/RevealControl (spec-compliance fix -- these
 * actions mutate the record's own effective, downstream-consumed verification
 * status). A single button (optionally with a required reason) gated on the same
 * "I have recently re-authenticated" checkbox.
 */
function ReauthActionForm({
  action,
  submitLabel,
  loadingLabel,
  variant = "primary",
  requireReason = false,
}: {
  action: (reauthConfirmedAt: string, reason: string | null) => Promise<VendorFinancialActionState>;
  submitLabel: string;
  loadingLabel?: string;
  variant?: "primary" | "secondary" | "destructive";
  requireReason?: boolean;
}) {
  const [reason, setReason] = useState("");
  const [reauthConfirmed, setReauthConfirmed] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();
  const reactId = useId();
  return (
    <div className="flex flex-col gap-2">
      {requireReason ? (
        <FormField id={reactId} label={<span className="sr-only">Reason</span>} error={error ?? undefined}>
          <Input id={reactId} placeholder="Reason (required)" value={reason} onChange={(e) => setReason(e.target.value)} invalid={Boolean(error)} aria-describedby={error ? `${reactId}-error` : undefined} />
        </FormField>
      ) : null}
      <Checkbox
        checked={reauthConfirmed}
        onChange={(e) => setReauthConfirmed(e.target.checked)}
        label="I have recently re-authenticated (required for this action)"
      />
      {!requireReason && error ? <ValidationMessage>{error}</ValidationMessage> : null}
      <Button
        type="button"
        variant={variant}
        disabled={!reauthConfirmed || (requireReason && reason.trim().length === 0)}
        loading={pending}
        loadingLabel={loadingLabel ?? "Working…"}
        className="w-fit"
        onClick={() =>
          startTransition(async () => {
            const result = await action(new Date().toISOString(), requireReason ? reason.trim() : null);
            setError(result.error);
          })
        }
      >
        {submitLabel}
      </Button>
    </div>
  );
}

/**
 * The mandatory maker-checker + MFA decision control (design notes 6-7). No live MFA
 * challenge UI exists anywhere in this repository -- the checkbox captures a
 * client-side attestation timestamp, mirroring credit-approval-decision-form.tsx's
 * (COM-157) already-established pattern exactly; the server independently
 * re-validates freshness (<=5 minutes) on every call.
 */
function DecideForm({
  decide,
  pending,
  error,
}: {
  decide: (decision: VendorFinancialDecision, rejectionReason: string | null, reauthConfirmedAt: string) => void;
  pending: boolean;
  error: string | null;
}) {
  const [reason, setReason] = useState("");
  const [reauthConfirmed, setReauthConfirmed] = useState(false);
  const reactId = useId();
  return (
    <div className="flex flex-col gap-2 rounded-md border border-info/40 bg-info/5 p-3">
      <p className="text-sm font-medium text-neutral-900">Pending your decision (a different identity than the proposer must decide)</p>
      <FormField id={reactId} label={<span className="sr-only">Reason</span>} error={error ?? undefined}>
        <Input id={reactId} placeholder="Reason (required to reject)" value={reason} onChange={(e) => setReason(e.target.value)} invalid={Boolean(error)} aria-describedby={error ? `${reactId}-error` : undefined} />
      </FormField>
      <Checkbox
        checked={reauthConfirmed}
        onChange={(e) => setReauthConfirmed(e.target.checked)}
        label="I have recently re-authenticated (required for this decision)"
      />
      <div className="flex gap-2">
        <Button type="button" disabled={!reauthConfirmed} loading={pending} loadingLabel="Approving…" onClick={() => decide("approved", null, new Date().toISOString())}>
          Approve
        </Button>
        <Button type="button" variant="secondary" disabled={!reauthConfirmed || !reason.trim()} loading={pending} loadingLabel="Rejecting…" onClick={() => decide("rejected", reason.trim(), new Date().toISOString())}>
          Reject
        </Button>
      </div>
    </div>
  );
}

/** The reveal control -- an explicit, deliberate user action (never fired on page load/render). Purpose-bound (revealReason mandatory) and MFA-gated (same client-attestation checkbox). */
function RevealControl<T extends { status: string }>({
  reveal,
  render,
}: {
  reveal: (revealReason: string, reauthConfirmedAt: string) => Promise<{ error: string | null; reveal: T | null }>;
  render: (revealed: T) => React.ReactNode;
}) {
  const [open, setOpen] = useState(false);
  const [reason, setReason] = useState("");
  const [reauthConfirmed, setReauthConfirmed] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [revealed, setRevealed] = useState<T | null>(null);
  const [pending, startTransition] = useTransition();
  const revealReasonId = useId();

  if (revealed) {
    return (
      <div className="rounded-md border border-warning/40 bg-warning/5 p-3">
        <p className="mb-1 text-xs font-medium text-warning">Revealed -- this access has been recorded in the audit trail</p>
        {render(revealed)}
        <Button type="button" variant="secondary" className="mt-2" onClick={() => setRevealed(null)}>
          Hide
        </Button>
      </div>
    );
  }

  if (!open) {
    return (
      <Button type="button" variant="secondary" onClick={() => setOpen(true)}>
        Reveal
      </Button>
    );
  }

  return (
    <div className="flex flex-col gap-2 rounded-md border border-neutral-200 p-3">
      <FormField id={revealReasonId} label={<span className="sr-only">Reveal reason</span>} error={error ?? undefined}>
        <Input id={revealReasonId} placeholder="Reveal reason, e.g. invoice matching (required)" value={reason} onChange={(e) => setReason(e.target.value)} invalid={Boolean(error)} aria-describedby={error ? `${revealReasonId}-error` : undefined} />
      </FormField>
      <Checkbox
        checked={reauthConfirmed}
        onChange={(e) => setReauthConfirmed(e.target.checked)}
        label="I have recently re-authenticated (required to reveal)"
      />
      <div className="flex gap-2">
        <Button
          type="button"
          disabled={!reauthConfirmed || !reason.trim()}
          loading={pending}
          loadingLabel="Revealing…"
          onClick={() =>
            startTransition(async () => {
              const result = await reveal(reason.trim(), new Date().toISOString());
              if (result.error) setError(result.error);
              else if (result.reveal) setRevealed(result.reveal);
            })
          }
        >
          Confirm reveal
        </Button>
        <Button type="button" variant="secondary" onClick={() => setOpen(false)}>
          Cancel
        </Button>
      </div>
    </div>
  );
}

function EvidenceLink({ access }: { access: (accessType: VendorFinancialAccessType) => Promise<VendorFinancialEvidenceAccessState> }) {
  const [state, setState] = useState<VendorFinancialEvidenceAccessState | null>(null);
  const [pending, startTransition] = useTransition();
  if (state?.access?.accessResult === "granted") {
    return <p className="text-xs text-neutral-600">Evidence on file: {state.access.originalFilename}</p>;
  }
  return (
    <div className="flex flex-col gap-1">
      <Button type="button" variant="secondary" loading={pending} loadingLabel="Checking…" onClick={() => startTransition(async () => setState(await access("metadata_view")))}>
        View evidence
      </Button>
      {state?.error || state?.access?.accessResult === "denied" ? <ValidationMessage>{state.error ?? `Access denied: ${state.access?.accessReason ?? "unknown"}`}</ValidationMessage> : null}
    </div>
  );
}

function BankAccountCard({
  account,
  submitActionFor,
  decideAction,
  holdAction,
  reactivateAction,
  deactivateAction,
  revealAction,
  accessEvidenceAction,
}: {
  account: VendorBankAccount;
  submitActionFor: (accountId: string, expectedVersion: number) => PlainAction;
  decideAction: (accountId: string, expectedVersion: number, decision: VendorFinancialDecision, rejectionReason: string | null, reauthConfirmedAt: string) => Promise<VendorFinancialActionState>;
  holdAction: (accountId: string, expectedVersion: number, reason: string, reauthConfirmedAt: string) => Promise<VendorFinancialActionState>;
  reactivateAction: (accountId: string, expectedVersion: number, reauthConfirmedAt: string) => Promise<VendorFinancialActionState>;
  deactivateAction: (accountId: string, expectedVersion: number, reason: string, reauthConfirmedAt: string) => Promise<VendorFinancialActionState>;
  revealAction: (accountId: string, revealReason: string, reauthConfirmedAt: string) => Promise<VendorBankAccountRevealActionState>;
  accessEvidenceAction: (accountId: string, accessType: VendorFinancialAccessType) => Promise<VendorFinancialEvidenceAccessState>;
}) {
  const [decideError, setDecideError] = useState<string | null>(null);
  const [decidePending, startDecide] = useTransition();
  const submitAction = useActionState(submitActionFor(account.id, account.recordVersion), INITIAL_STATE);

  return (
    <div className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <div>
          <p className="text-sm font-medium text-neutral-900">
            {account.bankName} •••• {account.accountNumberLast4} <span className="text-xs text-neutral-500">({account.purpose}, {account.currency})</span>
          </p>
          <p className="text-xs text-neutral-500">{account.accountHolderName}</p>
        </div>
        <div className="flex items-center gap-2">
          {account.isDuplicateCandidate ? <StatusBadge tone="warning" label="duplicate candidate" /> : null}
          <StatusBadge tone={LIFECYCLE_TONE[account.status]} label={account.status.replace(/_/g, " ")} />
        </div>
      </div>
      {account.holdReason ? <p className="text-xs text-warning">On hold: {account.holdReason}</p> : null}
      {account.rejectionReason ? <p className="text-xs text-danger">Rejected: {account.rejectionReason}</p> : null}
      {account.deactivationReason ? <p className="text-xs text-neutral-500">Deactivated: {account.deactivationReason}</p> : null}
      {account.evidenceFileId ? <EvidenceLink access={(t) => accessEvidenceAction(account.id, t)} /> : null}

      {account.status === "draft" ? (
        <div className="flex gap-2">
          <form action={submitAction[1]}>
            <Button type="submit" loading={submitAction[2]} loadingLabel="Submitting…">
              Submit for approval
            </Button>
          </form>
        </div>
      ) : null}
      {submitAction[0].error ? <ValidationMessage>{submitAction[0].error}</ValidationMessage> : null}

      {account.status === "pending_approval" ? (
        <DecideForm
          pending={decidePending}
          error={decideError}
          decide={(decision, rejectionReason, reauthConfirmedAt) =>
            startDecide(async () => {
              const result = await decideAction(account.id, account.recordVersion, decision, rejectionReason, reauthConfirmedAt);
              setDecideError(result.error);
            })
          }
        />
      ) : null}

      {account.status === "active" ? (
        <div className="flex flex-wrap items-start gap-2">
          <RevealControl reveal={(reason, reauth) => revealAction(account.id, reason, reauth)} render={(r) => <p className="font-mono text-sm text-neutral-900">{r.bankAccountNumber}</p>} />
          <ReauthActionForm
            action={(reauthConfirmedAt, reason) => holdAction(account.id, account.recordVersion, reason ?? "", reauthConfirmedAt)}
            submitLabel="Place on hold"
            variant="destructive"
            requireReason
            loadingLabel="Holding…"
          />
        </div>
      ) : null}
      {account.status === "hold" ? (
        <div className="flex flex-wrap items-start gap-2">
          <ReauthActionForm action={(reauthConfirmedAt) => reactivateAction(account.id, account.recordVersion, reauthConfirmedAt)} submitLabel="Reactivate" loadingLabel="Reactivating…" />
          <ReauthActionForm
            action={(reauthConfirmedAt, reason) => deactivateAction(account.id, account.recordVersion, reason ?? "", reauthConfirmedAt)}
            submitLabel="Deactivate"
            variant="destructive"
            requireReason
            loadingLabel="Deactivating…"
          />
        </div>
      ) : null}
    </div>
  );
}

function AddBankAccountForm({ action }: { action: PlainAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  const describedBy = state.error ? "add-bank-account-error" : undefined;
  return (
    <form action={formAction} className="flex flex-col gap-2 rounded-md border border-dashed border-neutral-300 p-4">
      <p className="text-sm font-medium text-neutral-900">Propose a bank account</p>
      <label htmlFor="bank-account-holder-name" className="sr-only">
        Account holder name
      </label>
      <Input id="bank-account-holder-name" name="accountHolderName" placeholder="Account holder name" required invalid={Boolean(state.error)} aria-describedby={describedBy} />
      <label htmlFor="bank-account-bank-name" className="sr-only">
        Bank name
      </label>
      <Input id="bank-account-bank-name" name="bankName" placeholder="Bank name" required invalid={Boolean(state.error)} aria-describedby={describedBy} />
      <label htmlFor="bank-account-number" className="sr-only">
        Account number
      </label>
      <Input id="bank-account-number" name="bankAccountNumber" placeholder="Account number" required minLength={4} invalid={Boolean(state.error)} aria-describedby={describedBy} />
      <div className="flex gap-2">
        <label htmlFor="bank-account-currency" className="sr-only">
          Currency
        </label>
        <Input id="bank-account-currency" name="currency" placeholder="Currency (e.g. IDR)" maxLength={3} required className="w-32" invalid={Boolean(state.error)} aria-describedby={describedBy} />
        <label htmlFor="bank-account-purpose" className="sr-only">
          Purpose
        </label>
        <Select id="bank-account-purpose" name="purpose" defaultValue="primary" invalid={Boolean(state.error)} aria-describedby={describedBy}>
          <option value="primary">Primary</option>
          <option value="settlement">Settlement</option>
          <option value="other">Other</option>
        </Select>
      </div>
      <label htmlFor="bank-account-evidence" className="text-xs text-neutral-600">
        Evidence (optional)
        <input id="bank-account-evidence" type="file" name="evidenceFile" className="mt-1 block w-full text-xs" aria-describedby={describedBy} />
      </label>
      {state.error ? <ValidationMessage id="add-bank-account-error">{state.error}</ValidationMessage> : null}
      <Button type="submit" loading={pending} loadingLabel="Proposing…" className="w-fit">
        Propose
      </Button>
    </form>
  );
}

function TaxIdentityCard({
  taxIdentity,
  submitActionFor,
  decideAction,
  holdAction,
  reactivateAction,
  deactivateAction,
  revealAction,
  accessEvidenceAction,
}: {
  taxIdentity: VendorTaxIdentity;
  submitActionFor: (taxIdentityId: string, expectedVersion: number) => PlainAction;
  decideAction: (taxIdentityId: string, expectedVersion: number, decision: VendorFinancialDecision, rejectionReason: string | null, reauthConfirmedAt: string) => Promise<VendorFinancialActionState>;
  holdAction: (taxIdentityId: string, expectedVersion: number, reason: string, reauthConfirmedAt: string) => Promise<VendorFinancialActionState>;
  reactivateAction: (taxIdentityId: string, expectedVersion: number, reauthConfirmedAt: string) => Promise<VendorFinancialActionState>;
  deactivateAction: (taxIdentityId: string, expectedVersion: number, reason: string, reauthConfirmedAt: string) => Promise<VendorFinancialActionState>;
  revealAction: (taxIdentityId: string, revealReason: string, reauthConfirmedAt: string) => Promise<VendorTaxIdentityRevealActionState>;
  accessEvidenceAction: (taxIdentityId: string, accessType: VendorFinancialAccessType) => Promise<VendorFinancialEvidenceAccessState>;
}) {
  const [decideError, setDecideError] = useState<string | null>(null);
  const [decidePending, startDecide] = useTransition();
  const submitAction = useActionState(submitActionFor(taxIdentity.id, taxIdentity.recordVersion), INITIAL_STATE);

  return (
    <div className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <div>
          <p className="text-sm font-medium text-neutral-900">
            {taxIdentity.taxIdType} •••• {taxIdentity.taxIdLast4}
          </p>
          <p className="text-xs text-neutral-500">{taxIdentity.legalNameOnFile}</p>
        </div>
        <div className="flex items-center gap-2">
          {taxIdentity.isDuplicateCandidate ? <StatusBadge tone="warning" label="duplicate candidate" /> : null}
          <StatusBadge tone={LIFECYCLE_TONE[taxIdentity.status]} label={taxIdentity.status.replace(/_/g, " ")} />
        </div>
      </div>
      {taxIdentity.holdReason ? <p className="text-xs text-warning">On hold: {taxIdentity.holdReason}</p> : null}
      {taxIdentity.rejectionReason ? <p className="text-xs text-danger">Rejected: {taxIdentity.rejectionReason}</p> : null}
      {taxIdentity.deactivationReason ? <p className="text-xs text-neutral-500">Deactivated: {taxIdentity.deactivationReason}</p> : null}
      {taxIdentity.evidenceFileId ? <EvidenceLink access={(t) => accessEvidenceAction(taxIdentity.id, t)} /> : null}

      {taxIdentity.status === "draft" ? (
        <form action={submitAction[1]}>
          <Button type="submit" loading={submitAction[2]} loadingLabel="Submitting…">
            Submit for approval
          </Button>
        </form>
      ) : null}
      {submitAction[0].error ? <ValidationMessage>{submitAction[0].error}</ValidationMessage> : null}

      {taxIdentity.status === "pending_approval" ? (
        <DecideForm
          pending={decidePending}
          error={decideError}
          decide={(decision, rejectionReason, reauthConfirmedAt) =>
            startDecide(async () => {
              const result = await decideAction(taxIdentity.id, taxIdentity.recordVersion, decision, rejectionReason, reauthConfirmedAt);
              setDecideError(result.error);
            })
          }
        />
      ) : null}

      {taxIdentity.status === "active" ? (
        <div className="flex flex-wrap items-start gap-2">
          <RevealControl reveal={(reason, reauth) => revealAction(taxIdentity.id, reason, reauth)} render={(r) => <p className="font-mono text-sm text-neutral-900">{r.taxIdNumber}</p>} />
          <ReauthActionForm
            action={(reauthConfirmedAt, reason) => holdAction(taxIdentity.id, taxIdentity.recordVersion, reason ?? "", reauthConfirmedAt)}
            submitLabel="Place on hold"
            variant="destructive"
            requireReason
            loadingLabel="Holding…"
          />
        </div>
      ) : null}
      {taxIdentity.status === "hold" ? (
        <div className="flex flex-wrap items-start gap-2">
          <ReauthActionForm action={(reauthConfirmedAt) => reactivateAction(taxIdentity.id, taxIdentity.recordVersion, reauthConfirmedAt)} submitLabel="Reactivate" loadingLabel="Reactivating…" />
          <ReauthActionForm
            action={(reauthConfirmedAt, reason) => deactivateAction(taxIdentity.id, taxIdentity.recordVersion, reason ?? "", reauthConfirmedAt)}
            submitLabel="Deactivate"
            variant="destructive"
            requireReason
            loadingLabel="Deactivating…"
          />
        </div>
      ) : null}
    </div>
  );
}

function AddTaxIdentityForm({ action }: { action: PlainAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  const describedBy = state.error ? "add-tax-identity-error" : undefined;
  return (
    <form action={formAction} className="flex flex-col gap-2 rounded-md border border-dashed border-neutral-300 p-4">
      <p className="text-sm font-medium text-neutral-900">Propose a tax identity</p>
      <label htmlFor="tax-identity-type" className="sr-only">
        Tax ID type
      </label>
      <Input id="tax-identity-type" name="taxIdType" placeholder="Tax ID type (e.g. NPWP)" required invalid={Boolean(state.error)} aria-describedby={describedBy} />
      <label htmlFor="tax-identity-number" className="sr-only">
        Tax identifier
      </label>
      <Input id="tax-identity-number" name="taxIdNumber" placeholder="Tax identifier" required minLength={4} invalid={Boolean(state.error)} aria-describedby={describedBy} />
      <label htmlFor="tax-identity-legal-name" className="sr-only">
        Legal name on file
      </label>
      <Input id="tax-identity-legal-name" name="legalNameOnFile" placeholder="Legal name on file" required invalid={Boolean(state.error)} aria-describedby={describedBy} />
      <label htmlFor="tax-identity-evidence" className="text-xs text-neutral-600">
        Evidence (optional)
        <input id="tax-identity-evidence" type="file" name="evidenceFile" className="mt-1 block w-full text-xs" aria-describedby={describedBy} />
      </label>
      {state.error ? <ValidationMessage id="add-tax-identity-error">{state.error}</ValidationMessage> : null}
      <Button type="submit" loading={pending} loadingLabel="Proposing…" className="w-fit">
        Propose
      </Button>
    </form>
  );
}

function PaymentTermSection({
  vendor,
  proposals,
  proposeAction,
  decideAction,
}: {
  vendor: VendorProfile;
  proposals: readonly VendorPaymentTermProposal[];
  proposeAction: PlainAction;
  decideAction: (proposalId: string, expectedVersion: number, decision: VendorFinancialDecision, decisionReason: string | null, reauthConfirmedAt: string) => Promise<VendorFinancialActionState>;
}) {
  const [proposeState, proposeFormAction, proposePending] = useActionState(proposeAction, INITIAL_STATE);
  const [decideError, setDecideError] = useState<string | null>(null);
  const [decidePending, startDecide] = useTransition();
  const pending = proposals.find((p) => p.status === "pending_approval");

  return (
    <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
      <h2 className="text-sm font-semibold text-neutral-900">Payment term</h2>
      <p className="text-sm text-neutral-700">Current: {vendor.paymentTermDays !== null ? `${vendor.paymentTermDays} days` : "not set"}</p>

      {pending ? (
        <div className="rounded-md border border-info/40 bg-info/5 p-3">
          <p className="text-sm text-neutral-900">
            Proposed change: {pending.currentPaymentTermDays ?? "—"} → {pending.proposedPaymentTermDays} days. Reason: {pending.reason}
          </p>
          <DecideForm
            pending={decidePending}
            error={decideError}
            decide={(decision, decisionReason, reauthConfirmedAt) =>
              startDecide(async () => {
                const result = await decideAction(pending.id, pending.recordVersion, decision, decisionReason, reauthConfirmedAt);
                setDecideError(result.error);
              })
            }
          />
        </div>
      ) : (
        <form action={proposeFormAction} className="flex flex-col gap-2">
          <label htmlFor="payment-term-days" className="sr-only">
            Proposed payment term (days)
          </label>
          <Input id="payment-term-days" name="proposedPaymentTermDays" type="number" min={0} placeholder="Proposed payment term (days)" required invalid={Boolean(proposeState.error)} aria-describedby={proposeState.error ? "payment-term-error" : undefined} />
          <label htmlFor="payment-term-reason" className="sr-only">
            Reason
          </label>
          <Input id="payment-term-reason" name="reason" placeholder="Reason (required)" required invalid={Boolean(proposeState.error)} aria-describedby={proposeState.error ? "payment-term-error" : undefined} />
          {proposeState.error ? <ValidationMessage id="payment-term-error">{proposeState.error}</ValidationMessage> : null}
          <Button type="submit" loading={proposePending} loadingLabel="Proposing…" className="w-fit">
            Propose change
          </Button>
        </form>
      )}
    </section>
  );
}

export function VendorFinancialPanel({
  vendor,
  bankAccounts,
  taxIdentities,
  paymentTermProposals,
  verificationStatus,
  createBankAccountAction,
  updateBankAccountActionFor: _updateBankAccountActionFor,
  submitBankAccountActionFor,
  decideBankAccountAction,
  holdBankAccountAction,
  reactivateBankAccountAction,
  deactivateBankAccountAction,
  revealBankAccountAction,
  accessBankAccountEvidenceAction,
  createTaxIdentityAction,
  updateTaxIdentityActionFor: _updateTaxIdentityActionFor,
  submitTaxIdentityActionFor,
  decideTaxIdentityAction,
  holdTaxIdentityAction,
  reactivateTaxIdentityAction,
  deactivateTaxIdentityAction,
  revealTaxIdentityAction,
  accessTaxIdentityEvidenceAction,
  proposePaymentTermAction,
  decidePaymentTermProposalAction,
}: {
  tenantSlug: string;
  vendor: VendorProfile;
  bankAccounts: readonly VendorBankAccount[];
  taxIdentities: readonly VendorTaxIdentity[];
  paymentTermProposals: readonly VendorPaymentTermProposal[];
  verificationStatus: VendorFinancialVerificationStatus;
  createBankAccountAction: PlainAction;
  updateBankAccountActionFor: (accountId: string, expectedVersion: number) => PlainAction;
  submitBankAccountActionFor: (accountId: string, expectedVersion: number) => PlainAction;
  decideBankAccountAction: (accountId: string, expectedVersion: number, decision: VendorFinancialDecision, rejectionReason: string | null, reauthConfirmedAt: string) => Promise<VendorFinancialActionState>;
  holdBankAccountAction: (accountId: string, expectedVersion: number, reason: string, reauthConfirmedAt: string) => Promise<VendorFinancialActionState>;
  reactivateBankAccountAction: (accountId: string, expectedVersion: number, reauthConfirmedAt: string) => Promise<VendorFinancialActionState>;
  deactivateBankAccountAction: (accountId: string, expectedVersion: number, reason: string, reauthConfirmedAt: string) => Promise<VendorFinancialActionState>;
  revealBankAccountAction: (accountId: string, revealReason: string, reauthConfirmedAt: string) => Promise<VendorBankAccountRevealActionState>;
  accessBankAccountEvidenceAction: (accountId: string, accessType: VendorFinancialAccessType) => Promise<VendorFinancialEvidenceAccessState>;
  createTaxIdentityAction: PlainAction;
  updateTaxIdentityActionFor: (taxIdentityId: string, expectedVersion: number) => PlainAction;
  submitTaxIdentityActionFor: (taxIdentityId: string, expectedVersion: number) => PlainAction;
  decideTaxIdentityAction: (taxIdentityId: string, expectedVersion: number, decision: VendorFinancialDecision, rejectionReason: string | null, reauthConfirmedAt: string) => Promise<VendorFinancialActionState>;
  holdTaxIdentityAction: (taxIdentityId: string, expectedVersion: number, reason: string, reauthConfirmedAt: string) => Promise<VendorFinancialActionState>;
  reactivateTaxIdentityAction: (taxIdentityId: string, expectedVersion: number, reauthConfirmedAt: string) => Promise<VendorFinancialActionState>;
  deactivateTaxIdentityAction: (taxIdentityId: string, expectedVersion: number, reason: string, reauthConfirmedAt: string) => Promise<VendorFinancialActionState>;
  revealTaxIdentityAction: (taxIdentityId: string, revealReason: string, reauthConfirmedAt: string) => Promise<VendorTaxIdentityRevealActionState>;
  accessTaxIdentityEvidenceAction: (taxIdentityId: string, accessType: VendorFinancialAccessType) => Promise<VendorFinancialEvidenceAccessState>;
  proposePaymentTermAction: PlainAction;
  decidePaymentTermProposalAction: (proposalId: string, expectedVersion: number, decision: VendorFinancialDecision, decisionReason: string | null, reauthConfirmedAt: string) => Promise<VendorFinancialActionState>;
}) {
  return (
    <div className="flex flex-col gap-6">
      <header>
        <h1 className="text-xl font-semibold text-neutral-900">{vendor.legalName} — Banking &amp; tax security</h1>
        <p className="text-xs text-neutral-500">Masked by default. Revealing a value is an audited, deliberate action.</p>
      </header>

      {verificationStatus.onHold ? (
        <div role="alert" className="rounded-md border border-danger/40 bg-danger/5 p-3 text-sm text-danger">
          Downstream hold: this vendor has a bank account or tax identity currently on hold. Sourcing/PO/invoice-matching capabilities should treat this vendor as not financially verified until resolved.
        </div>
      ) : (
        <div className="flex flex-wrap gap-2">
          <StatusBadge tone={verificationStatus.hasVerifiedBankAccount ? "success" : "neutral"} label={verificationStatus.hasVerifiedBankAccount ? "verified bank account" : "no verified bank account"} />
          <StatusBadge tone={verificationStatus.hasVerifiedTaxIdentity ? "success" : "neutral"} label={verificationStatus.hasVerifiedTaxIdentity ? "verified tax identity" : "no verified tax identity"} />
        </div>
      )}

      <section className="flex flex-col gap-3">
        <h2 className="text-sm font-semibold text-neutral-900">Bank accounts</h2>
        {bankAccounts.length === 0 ? (
          <EmptyState title="No bank accounts on file" description="Propose a bank account below to begin the maker-checker approval flow." />
        ) : (
          <div className="flex flex-col gap-3">
            {bankAccounts.map((account) => (
              <BankAccountCard
                key={account.id}
                account={account}
                submitActionFor={submitBankAccountActionFor}
                decideAction={decideBankAccountAction}
                holdAction={holdBankAccountAction}
                reactivateAction={reactivateBankAccountAction}
                deactivateAction={deactivateBankAccountAction}
                revealAction={revealBankAccountAction}
                accessEvidenceAction={accessBankAccountEvidenceAction}
              />
            ))}
          </div>
        )}
        <AddBankAccountForm action={createBankAccountAction} />
      </section>

      <section className="flex flex-col gap-3">
        <h2 className="text-sm font-semibold text-neutral-900">Tax identities</h2>
        {taxIdentities.length === 0 ? (
          <EmptyState title="No tax identities on file" description="Propose a tax identity below to begin the maker-checker approval flow." />
        ) : (
          <div className="flex flex-col gap-3">
            {taxIdentities.map((taxIdentity) => (
              <TaxIdentityCard
                key={taxIdentity.id}
                taxIdentity={taxIdentity}
                submitActionFor={submitTaxIdentityActionFor}
                decideAction={decideTaxIdentityAction}
                holdAction={holdTaxIdentityAction}
                reactivateAction={reactivateTaxIdentityAction}
                deactivateAction={deactivateTaxIdentityAction}
                revealAction={revealTaxIdentityAction}
                accessEvidenceAction={accessTaxIdentityEvidenceAction}
              />
            ))}
          </div>
        )}
        <AddTaxIdentityForm action={createTaxIdentityAction} />
      </section>

      <PaymentTermSection vendor={vendor} proposals={paymentTermProposals} proposeAction={proposePaymentTermAction} decideAction={decidePaymentTermProposalAction} />
    </div>
  );
}
