"use client";

import { useActionState } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
import { Input } from "../../../../../components/forms/input.tsx";
import { Textarea } from "../../../../../components/forms/textarea.tsx";
import { FormField } from "../../../../../components/forms/form-field.tsx";
import { ValidationMessage } from "../../../../../components/forms/validation-message.tsx";
import { StatusBadge, type StatusTone } from "../../../../../components/ui/status-badge.tsx";
import { EmptyState } from "../../../../../components/ui/empty-state.tsx";
import type { AutomationRuleActionState, DryRunActionState } from "../actions.ts";
import type { AutomationRule, AutomationRuleVersion, AutomationRuleExecution, AutomationRuleStatus } from "../../../../../server/contracts/automation-rule/automation-rule.ts";
import type { ApprovalRequest, ApprovalRequestStep } from "../../../../../server/contracts/approval/approval.ts";

const RULE_STATUS_TONE: Record<AutomationRuleStatus, StatusTone> = {
  active: "success",
  paused: "warning",
  archived: "neutral",
};

const EXECUTION_STATUS_TONE: Record<AutomationRuleExecution["status"], StatusTone> = {
  completed: "success",
  suppressed: "warning",
  failed: "danger",
};

const OK: AutomationRuleActionState = { error: null };
const DRY_RUN_OK: DryRunActionState = { error: null, result: null };

function DefinitionEditor({ draft, setDefinitionAction }: { draft: AutomationRuleVersion | undefined; setDefinitionAction: (prevState: AutomationRuleActionState, formData: FormData) => Promise<AutomationRuleActionState> }) {
  const [state, formAction, pending] = useActionState(setDefinitionAction, OK);
  const describedBy = state.error ? "automation-rule-definition-error" : undefined;

  return (
    <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
      <h2 className="text-sm font-semibold text-neutral-900">Draft definition (version {draft?.versionNumber ?? "—"})</h2>
      <form action={formAction} className="flex flex-col gap-3">
        <FormField id="triggerEventType" label="Trigger event type">
          <Input
            id="triggerEventType"
            name="triggerEventType"
            type="text"
            placeholder="ticket.created"
            defaultValue={draft?.triggerEventType ?? ""}
            required
            invalid={Boolean(state.error)}
            aria-describedby={describedBy}
          />
        </FormField>
        <FormField id="conditions" label={<>Conditions (JSON array of {"{field,operator,value}"}, AND-combined; empty array = always matches)</>}>
          <Textarea
            id="conditions"
            name="conditions"
            rows={3}
            defaultValue={JSON.stringify(draft?.conditions ?? [], null, 2)}
            className="font-mono"
            invalid={Boolean(state.error)}
            aria-describedby={describedBy}
          />
        </FormField>
        <FormField id="actions" label="Actions (JSON array, 1-10 entries, each action_type in notify/transition_workflow/enqueue_job)">
          <Textarea
            id="actions"
            name="actions"
            rows={5}
            defaultValue={JSON.stringify(draft?.actions ?? [], null, 2)}
            className="font-mono"
            invalid={Boolean(state.error)}
            aria-describedby={describedBy}
          />
        </FormField>

        {state.error ? <ValidationMessage id="automation-rule-definition-error">{state.error}</ValidationMessage> : null}

        <div>
          <Button type="submit" loading={pending} loadingLabel="Saving…">
            Save draft
          </Button>
        </div>
      </form>
    </section>
  );
}

function DryRunTester({ dryRunAction }: { dryRunAction: (prevState: DryRunActionState, formData: FormData) => Promise<DryRunActionState> }) {
  const [state, formAction, pending] = useActionState(dryRunAction, DRY_RUN_OK);
  const describedBy = state.error ? "automation-rule-dry-run-error" : undefined;

  return (
    <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
      <h2 className="text-sm font-semibold text-neutral-900">Dry run</h2>
      <p className="text-xs text-neutral-500">Pure simulation against the current draft -- never sends a real notification, enqueues a real job, or transitions a real workflow instance.</p>
      <form action={formAction} className="flex flex-col gap-3">
        <FormField id="sampleEventPayload" label="Sample event payload (JSON object)">
          <Textarea
            id="sampleEventPayload"
            name="sampleEventPayload"
            rows={3}
            placeholder="{}"
            className="font-mono"
            invalid={Boolean(state.error)}
            aria-describedby={describedBy}
          />
        </FormField>

        {state.error ? <ValidationMessage id="automation-rule-dry-run-error">{state.error}</ValidationMessage> : null}
        {state.result ? (
          <div className="rounded-md bg-neutral-50 p-3 text-xs">
            <p>
              <strong>Matched:</strong> {state.result.matched ? "Yes" : "No"}
            </p>
            {!state.result.valid ? (
              <p role="alert" className="mt-1 text-danger">
                <strong>This draft is not yet publishable:</strong> {state.result.validationError}
              </p>
            ) : null}
            <pre className="mt-1 overflow-x-auto">{JSON.stringify(state.result.wouldFireActions, null, 2)}</pre>
          </div>
        ) : null}

        <div>
          <Button type="submit" variant="secondary" loading={pending} loadingLabel="Running…">
            Run dry run
          </Button>
        </div>
      </form>
    </section>
  );
}

function ApprovalFlow({
  draft,
  approvalRequest,
  approvalSteps,
  requestApprovalAction,
  decideApprovalActionFor,
  publishActionFor,
}: {
  draft: AutomationRuleVersion | undefined;
  approvalRequest: ApprovalRequest | null;
  approvalSteps: readonly ApprovalRequestStep[];
  requestApprovalAction: (prevState: AutomationRuleActionState, formData: FormData) => Promise<AutomationRuleActionState>;
  decideApprovalActionFor: (stepId: string, decision: "approved" | "rejected") => (prevState: AutomationRuleActionState, formData: FormData) => Promise<AutomationRuleActionState>;
  publishActionFor: (approvalRequestId: string) => (prevState: AutomationRuleActionState, formData: FormData) => Promise<AutomationRuleActionState>;
}) {
  const [requestState, requestFormAction, requestPending] = useActionState(requestApprovalAction, OK);
  const activeStep = approvalSteps.find((s) => s.status === "active" || s.status === "pending");

  return (
    <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
      <h2 className="text-sm font-semibold text-neutral-900">Publish approval</h2>
      <p className="text-xs text-neutral-500">An AI-drafted or human-drafted rule can never publish itself -- publishing this draft requires a real, decided approval request.</p>

      {approvalRequest ? (
        <div className="flex flex-col gap-2 text-sm">
          <p>
            Request status: <StatusBadge tone={approvalRequest.status === "approved" ? "success" : approvalRequest.status === "rejected" ? "danger" : "warning"} label={approvalRequest.status} />
          </p>
          {activeStep ? (
            <DecideApprovalForm stepId={activeStep.id} decideApprovalActionFor={decideApprovalActionFor} />
          ) : null}
          {approvalRequest.status === "approved" ? <PublishForm approvalRequestId={approvalRequest.id} publishActionFor={publishActionFor} /> : null}
        </div>
      ) : (
        <form action={requestFormAction} className="flex flex-col gap-2">
          {requestState.error ? (
            <p role="alert" className="text-sm text-danger">
              {requestState.error}
            </p>
          ) : null}
          <div>
            <Button type="submit" disabled={!draft?.triggerEventType} loading={requestPending} loadingLabel="Requesting…">
              Request publish approval
            </Button>
          </div>
        </form>
      )}
    </section>
  );
}

function DecideApprovalForm({
  stepId,
  decideApprovalActionFor,
}: {
  stepId: string;
  decideApprovalActionFor: (stepId: string, decision: "approved" | "rejected") => (prevState: AutomationRuleActionState, formData: FormData) => Promise<AutomationRuleActionState>;
}) {
  const [approveState, approveFormAction, approvePending] = useActionState(decideApprovalActionFor(stepId, "approved"), OK);
  const [rejectState, rejectFormAction, rejectPending] = useActionState(decideApprovalActionFor(stepId, "rejected"), OK);

  return (
    <div className="flex flex-col gap-2">
      <p className="text-xs text-neutral-500">A pending step is waiting on its own eligible approver -- these buttons are safe to show broadly since the RPC itself denies an ineligible actor.</p>
      <div className="flex gap-2">
        <form action={approveFormAction}>
          <Button type="submit" loading={approvePending} loadingLabel="Approving…">
            Approve
          </Button>
        </form>
        <form action={rejectFormAction}>
          <Button type="submit" variant="destructive" loading={rejectPending} loadingLabel="Rejecting…">
            Reject
          </Button>
        </form>
      </div>
      {approveState.error ? (
        <p role="alert" className="text-sm text-danger">
          {approveState.error}
        </p>
      ) : null}
      {rejectState.error ? (
        <p role="alert" className="text-sm text-danger">
          {rejectState.error}
        </p>
      ) : null}
    </div>
  );
}

function PublishForm({
  approvalRequestId,
  publishActionFor,
}: {
  approvalRequestId: string;
  publishActionFor: (approvalRequestId: string) => (prevState: AutomationRuleActionState, formData: FormData) => Promise<AutomationRuleActionState>;
}) {
  const [state, formAction, pending] = useActionState(publishActionFor(approvalRequestId), OK);

  return (
    <form action={formAction} className="flex flex-col gap-2">
      {state.error ? (
        <p role="alert" className="text-sm text-danger">
          {state.error}
        </p>
      ) : null}
      <div>
        <Button type="submit" loading={pending} loadingLabel="Publishing…">
          Publish this version
        </Button>
      </div>
    </form>
  );
}

function StatusControls({ rule, setStatusActionFor }: { rule: AutomationRule; setStatusActionFor: (status: AutomationRuleStatus) => (prevState: AutomationRuleActionState, formData: FormData) => Promise<AutomationRuleActionState> }) {
  const nextStatus: AutomationRuleStatus = rule.status === "active" ? "paused" : "active";
  const [state, formAction, pending] = useActionState(setStatusActionFor(nextStatus), OK);
  const [archiveState, archiveFormAction, archivePending] = useActionState(setStatusActionFor("archived"), OK);

  return (
    <section className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
      <h2 className="text-sm font-semibold text-neutral-900">Status</h2>
      <p className="text-xs text-neutral-500">Pausing a rule structurally excludes it from evaluation immediately -- the safe first response to a misfiring rule.</p>
      <div className="flex gap-2">
        <form action={formAction}>
          <Button type="submit" variant="secondary" loading={pending} loadingLabel="Updating…" disabled={rule.status === "archived"}>
            {nextStatus === "paused" ? "Pause" : "Resume"}
          </Button>
        </form>
        <form action={archiveFormAction}>
          <Button type="submit" variant="destructive" loading={archivePending} loadingLabel="Archiving…" disabled={rule.status === "archived"}>
            Archive
          </Button>
        </form>
      </div>
      {state.error ? (
        <p role="alert" className="text-sm text-danger">
          {state.error}
        </p>
      ) : null}
      {archiveState.error ? (
        <p role="alert" className="text-sm text-danger">
          {archiveState.error}
        </p>
      ) : null}
    </section>
  );
}

export function AutomationRuleDetailPanel({
  rule,
  versions,
  executions,
  approvalRequest,
  approvalSteps,
  setDefinitionAction,
  dryRunAction,
  requestApprovalAction,
  decideApprovalActionFor,
  publishActionFor,
  setStatusActionFor,
}: {
  rule: AutomationRule;
  versions: readonly AutomationRuleVersion[];
  executions: readonly AutomationRuleExecution[];
  approvalRequest: ApprovalRequest | null;
  approvalSteps: readonly ApprovalRequestStep[];
  setDefinitionAction: (prevState: AutomationRuleActionState, formData: FormData) => Promise<AutomationRuleActionState>;
  dryRunAction: (prevState: DryRunActionState, formData: FormData) => Promise<DryRunActionState>;
  requestApprovalAction: (prevState: AutomationRuleActionState, formData: FormData) => Promise<AutomationRuleActionState>;
  decideApprovalActionFor: (stepId: string, decision: "approved" | "rejected") => (prevState: AutomationRuleActionState, formData: FormData) => Promise<AutomationRuleActionState>;
  publishActionFor: (approvalRequestId: string) => (prevState: AutomationRuleActionState, formData: FormData) => Promise<AutomationRuleActionState>;
  setStatusActionFor: (status: AutomationRuleStatus) => (prevState: AutomationRuleActionState, formData: FormData) => Promise<AutomationRuleActionState>;
}) {
  const draft = versions.find((v) => v.status === "draft");
  const published = versions.find((v) => v.id === rule.currentVersionId);

  return (
    <div className="flex flex-col gap-4">
      <div className="flex items-center gap-2">
        <h1 className="text-xl font-semibold text-neutral-900">{rule.name}</h1>
        <StatusBadge tone={RULE_STATUS_TONE[rule.status]} label={rule.status} />
      </div>
      {rule.description ? <p className="text-sm text-neutral-600">{rule.description}</p> : null}

      {published ? (
        <section className="flex flex-col gap-1 rounded-md border border-neutral-200 p-4 text-sm">
          <h2 className="text-sm font-semibold text-neutral-900">Currently published (version {published.versionNumber})</h2>
          <p>
            Trigger: <code>{published.triggerEventType}</code>
          </p>
          <p>
            Cooldown: {rule.cooldownSeconds}s · Max {rule.maxFiresPerWindow} fires per {rule.windowSeconds}s window · Fired {rule.fireCountInWindow} time(s) in the current window
          </p>
        </section>
      ) : (
        <EmptyState title="Not yet published" description="This rule has never had an approved publish -- it is structurally never evaluated until it is." />
      )}

      <DefinitionEditor draft={draft} setDefinitionAction={setDefinitionAction} />
      <DryRunTester dryRunAction={dryRunAction} />
      <ApprovalFlow
        draft={draft}
        approvalRequest={approvalRequest}
        approvalSteps={approvalSteps}
        requestApprovalAction={requestApprovalAction}
        decideApprovalActionFor={decideApprovalActionFor}
        publishActionFor={publishActionFor}
      />
      <StatusControls rule={rule} setStatusActionFor={setStatusActionFor} />

      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Execution log</h2>
        {executions.length === 0 ? (
          <EmptyState title="No executions yet" description="Real firings, suppressions and failures will appear here." />
        ) : (
          <table className="w-full text-sm">
            <thead>
              <tr className="text-left text-xs text-neutral-500">
                <th className="pb-1">Executed</th>
                <th className="pb-1">Status</th>
                <th className="pb-1">Detail</th>
              </tr>
            </thead>
            <tbody>
              {executions.map((e) => (
                <tr key={e.id} className="border-t border-neutral-100 align-top">
                  <td className="py-1">{e.executedAt}</td>
                  <td className="py-1">
                    <StatusBadge tone={EXECUTION_STATUS_TONE[e.status]} label={e.status} />
                  </td>
                  <td className="py-1 font-mono text-xs">{e.suppressedReason ?? (e.actionsTaken.length > 0 ? JSON.stringify(e.actionsTaken) : "—")}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </section>
    </div>
  );
}
