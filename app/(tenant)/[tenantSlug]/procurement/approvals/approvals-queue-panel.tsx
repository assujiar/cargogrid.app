"use client";

import { useActionState } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
import { Input } from "../../../../../components/forms/input.tsx";
import { Select } from "../../../../../components/forms/select.tsx";
import { Checkbox } from "../../../../../components/forms/checkbox.tsx";
import { FormField } from "../../../../../components/forms/form-field.tsx";
import { ValidationMessage } from "../../../../../components/forms/validation-message.tsx";
import { StatusBadge, type StatusTone } from "../../../../../components/ui/status-badge.tsx";
import { EmptyState } from "../../../../../components/ui/empty-state.tsx";
import { DataTable, type DataTableColumn } from "../../../../../components/tables/data-table.tsx";
import {
  PROCUREMENT_APPROVAL_ENTITY_TYPES,
  type ProcurementApprovalPolicyVersion,
  type ProcurementExceptionRequest,
} from "../../../../../server/contracts/procurement-approval/procurement-approval.ts";
import type { ProcurementApprovalInboxItem } from "../../../../../server/queries/procurement-approval.ts";
import type { ProcurementApprovalActionState } from "./actions.ts";

const INITIAL_STATE: ProcurementApprovalActionState = { error: null };

const ENTITY_TYPE_LABELS: Record<string, string> = {
  vendor_activation: "Vendor activation",
  rate_version: "Rate approval",
  vendor_selection: "Vendor selection",
  purchase_order: "Purchase order",
  vendor_contract: "Vendor contract",
  exception_override: "Exception / override",
};

const POLICY_STATUS_TONE: Record<string, StatusTone> = { draft: "neutral", published: "success", archived: "neutral" };
const EXCEPTION_STATUS_TONE: Record<string, StatusTone> = { submitted: "info", approved: "success", rejected: "danger", cancelled: "neutral" };

type PolicyFormAction = (prevState: ProcurementApprovalActionState, formData: FormData) => Promise<ProcurementApprovalActionState>;
type ExceptionFormAction = (prevState: ProcurementApprovalActionState, formData: FormData) => Promise<ProcurementApprovalActionState>;
type PublishAction = (policyVersionId: string, expectedVersion: number, supersedesVersionId: string | null, prevState: ProcurementApprovalActionState, formData: FormData) => Promise<ProcurementApprovalActionState>;
type CancelAction = (id: string, expectedVersion: number, prevState: ProcurementApprovalActionState, formData: FormData) => Promise<ProcurementApprovalActionState>;

export function ProcurementApprovalsQueuePanel({
  tenantSlug,
  inbox,
  policies,
  exceptions,
  createPolicyAction,
  publishPolicyAction,
  createExceptionAction,
  cancelExceptionAction,
}: {
  tenantSlug: string;
  inbox: readonly ProcurementApprovalInboxItem[];
  policies: readonly ProcurementApprovalPolicyVersion[];
  exceptions: readonly ProcurementExceptionRequest[];
  createPolicyAction: PolicyFormAction;
  publishPolicyAction: PublishAction;
  createExceptionAction: ExceptionFormAction;
  cancelExceptionAction: CancelAction;
}) {
  return (
    <div className="flex flex-col gap-6">
      <InboxSection tenantSlug={tenantSlug} inbox={inbox} />
      <PoliciesSection policies={policies} createPolicyAction={createPolicyAction} publishPolicyAction={publishPolicyAction} />
      <ExceptionsSection exceptions={exceptions} createExceptionAction={createExceptionAction} cancelExceptionAction={cancelExceptionAction} />
    </div>
  );
}

function InboxSection({ tenantSlug, inbox }: { tenantSlug: string; inbox: readonly ProcurementApprovalInboxItem[] }) {
  const columns: readonly DataTableColumn<ProcurementApprovalInboxItem>[] = [
    { key: "entityType", header: "Decision type", render: (row) => ENTITY_TYPE_LABELS[row.entityType] ?? row.entityType },
    { key: "step", header: "Step", render: (row) => `Step ${row.stepOrder}` },
    {
      key: "action",
      header: "Action",
      render: (row) => (
        <a href={`/${tenantSlug}/procurement/approvals/${row.stepId}`} className="text-sm font-medium text-primary underline">
          Review
        </a>
      ),
    },
  ];

  return (
    <section className="rounded-md border border-neutral-200 p-4">
      <h2 className="text-sm font-semibold text-neutral-900">Waiting on your decision</h2>
      <div className="mt-2">
        {inbox.length === 0 ? (
          <EmptyState title="Nothing is waiting on you right now" description="Every governed procurement decision your role is eligible to decide will appear here." />
        ) : (
          <DataTable caption="Procurement approvals waiting on your decision" columns={columns} rows={inbox} rowKey={(row) => row.stepId} emptyMessage="Nothing is waiting on you right now." />
        )}
      </div>
    </section>
  );
}

function PoliciesSection({ policies, createPolicyAction, publishPolicyAction }: { policies: readonly ProcurementApprovalPolicyVersion[]; createPolicyAction: PolicyFormAction; publishPolicyAction: PublishAction }) {
  const [createState, createFormAction, createPending] = useActionState(createPolicyAction, INITIAL_STATE);
  const createErrorId = "policy-create-error";
  const createDescribedBy = createState.error ? createErrorId : undefined;

  const columns: readonly DataTableColumn<ProcurementApprovalPolicyVersion>[] = [
    { key: "entityType", header: "Decision type", render: (row) => ENTITY_TYPE_LABELS[row.entityType] ?? row.entityType },
    { key: "threshold", header: "Threshold", render: (row) => (row.alwaysRequired ? "Always required" : row.minValueAmount !== null ? `≥ ${row.minValueAmount}` : "—") },
    { key: "status", header: "Status", render: (row) => <StatusBadge tone={POLICY_STATUS_TONE[row.status] ?? "neutral"} label={row.status} /> },
    { key: "version", header: "Version", render: (row) => row.recordVersion },
    { key: "action", header: "Action", render: (row) => (row.status === "draft" ? <PublishPolicyButton policy={row} publishPolicyAction={publishPolicyAction} /> : null) },
  ];

  return (
    <section className="rounded-md border border-neutral-200 p-4">
      <h2 className="text-sm font-semibold text-neutral-900">Governed approval policies</h2>
      <p className="text-xs text-neutral-500">
        Whether a decision routes through the Platform Approval Engine at all -- opt-in per (tenant, decision type). No published policy for a decision type means it never routes
        (approval_status=not_required), matching Commercial Quotation Approval&apos;s own precedent.
      </p>

      <form action={createFormAction} className="mt-3 flex flex-col gap-2 rounded-md border border-neutral-200 p-3 sm:flex-row sm:items-end sm:gap-3" noValidate>
        <FormField id="entityType" label="Decision type">
          <Select id="entityType" name="entityType" required invalid={Boolean(createState.error)} aria-describedby={createDescribedBy}>
            {PROCUREMENT_APPROVAL_ENTITY_TYPES.map((entityType) => (
              <option key={entityType} value={entityType}>
                {ENTITY_TYPE_LABELS[entityType] ?? entityType}
              </option>
            ))}
          </Select>
        </FormField>
        <FormField id="minValueAmount" label="Min value amount (only for rate/selection/PO)">
          <Input id="minValueAmount" name="minValueAmount" type="number" min={0} invalid={Boolean(createState.error)} aria-describedby={createDescribedBy} />
        </FormField>
        <Checkbox id="alwaysRequired" name="alwaysRequired" label="Always required" aria-describedby={createDescribedBy} />
        <Button type="submit" disabled={createPending}>
          {createPending ? "Creating…" : "Create policy draft"}
        </Button>
      </form>
      {createState.error ? <ValidationMessage id={createErrorId}>{createState.error}</ValidationMessage> : null}

      <div className="mt-3">
        {policies.length === 0 ? (
          <EmptyState title="No governed policies yet" description="Create one above to require Platform-engine approval for a Procurement decision type." />
        ) : (
          <DataTable caption="Governed procurement approval policies" columns={columns} rows={policies} rowKey={(row) => row.id} emptyMessage="No governed policies yet." />
        )}
      </div>
    </section>
  );
}

function PublishPolicyButton({ policy, publishPolicyAction }: { policy: ProcurementApprovalPolicyVersion; publishPolicyAction: PublishAction }) {
  const bound = publishPolicyAction.bind(null, policy.id, policy.recordVersion, null);
  const [state, formAction, pending] = useActionState(bound, INITIAL_STATE);
  return (
    <form action={formAction} className="inline-flex flex-col gap-1">
      <Button type="submit" variant="secondary" disabled={pending}>
        {pending ? "Publishing…" : "Publish"}
      </Button>
      {state.error ? <ValidationMessage>{state.error}</ValidationMessage> : null}
    </form>
  );
}

function ExceptionsSection({ exceptions, createExceptionAction, cancelExceptionAction }: { exceptions: readonly ProcurementExceptionRequest[]; createExceptionAction: ExceptionFormAction; cancelExceptionAction: CancelAction }) {
  const [createState, createFormAction, createPending] = useActionState(createExceptionAction, INITIAL_STATE);
  const exceptionErrorId = "exception-create-error";
  const exceptionDescribedBy = createState.error ? exceptionErrorId : undefined;

  const columns: readonly DataTableColumn<ProcurementExceptionRequest>[] = [
    { key: "exceptionType", header: "Exception type", render: (row) => row.exceptionType },
    { key: "reason", header: "Reason", render: (row) => row.reason },
    { key: "status", header: "Status", render: (row) => <StatusBadge tone={EXCEPTION_STATUS_TONE[row.status] ?? "neutral"} label={row.status} /> },
    { key: "approvalStatus", header: "Approval", render: (row) => row.approvalStatus },
    { key: "action", header: "Action", render: (row) => (row.status === "submitted" ? <CancelExceptionForm request={row} cancelExceptionAction={cancelExceptionAction} /> : null) },
  ];

  return (
    <section className="rounded-md border border-neutral-200 p-4">
      <h2 className="text-sm font-semibold text-neutral-900">Exception / override requests</h2>
      <p className="text-xs text-neutral-500">Every Override action requires a reason and, when an exception_override policy is published for this tenant, real governed approval.</p>

      <form action={createFormAction} className="mt-3 flex flex-col gap-2 rounded-md border border-neutral-200 p-3" noValidate>
        <div className="grid grid-cols-1 gap-2 sm:grid-cols-3">
          <FormField id="exceptionType" label="Exception type (required)">
            <Input id="exceptionType" name="exceptionType" type="text" required invalid={Boolean(createState.error)} aria-describedby={exceptionDescribedBy} />
          </FormField>
          <FormField id="relatedEntityType" label="Related entity type">
            <Input id="relatedEntityType" name="relatedEntityType" type="text" invalid={Boolean(createState.error)} aria-describedby={exceptionDescribedBy} />
          </FormField>
          <FormField id="relatedEntityId" label="Related entity id">
            <Input id="relatedEntityId" name="relatedEntityId" type="text" invalid={Boolean(createState.error)} aria-describedby={exceptionDescribedBy} />
          </FormField>
          <div className="sm:col-span-2">
            <FormField id="reason" label="Reason (required)">
              <Input id="reason" name="reason" type="text" required invalid={Boolean(createState.error)} aria-describedby={exceptionDescribedBy} />
            </FormField>
          </div>
          <FormField id="requestedOutcome" label="Requested outcome">
            <Input id="requestedOutcome" name="requestedOutcome" type="text" invalid={Boolean(createState.error)} aria-describedby={exceptionDescribedBy} />
          </FormField>
        </div>
        <Button type="submit" disabled={createPending} className="w-fit">
          {createPending ? "Submitting…" : "Request exception / override"}
        </Button>
      </form>
      {createState.error ? <ValidationMessage id={exceptionErrorId}>{createState.error}</ValidationMessage> : null}

      <div className="mt-3">
        {exceptions.length === 0 ? (
          <EmptyState title="No exception/override requests yet" description="Request one above when a governed decision needs to bypass its normal path, with a reason." />
        ) : (
          <DataTable caption="Procurement exception/override requests" columns={columns} rows={exceptions} rowKey={(row) => row.id} emptyMessage="No exception/override requests yet." />
        )}
      </div>
    </section>
  );
}

function CancelExceptionForm({ request, cancelExceptionAction }: { request: ProcurementExceptionRequest; cancelExceptionAction: CancelAction }) {
  const bound = cancelExceptionAction.bind(null, request.id, request.recordVersion);
  const [state, formAction, pending] = useActionState(bound, INITIAL_STATE);
  const errorId = `withdraw-${request.id}-error`;
  const describedBy = state.error ? errorId : undefined;
  return (
    <form action={formAction} className="flex flex-col gap-1">
      <label htmlFor={`withdraw-reason-${request.id}`} className="sr-only">
        Withdrawal reason
      </label>
      <Input id={`withdraw-reason-${request.id}`} name="reason" type="text" placeholder="Withdrawal reason" required className="text-xs" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      <Button type="submit" variant="destructive" disabled={pending}>
        {pending ? "Withdrawing…" : "Withdraw"}
      </Button>
      {state.error ? <ValidationMessage id={errorId}>{state.error}</ValidationMessage> : null}
    </form>
  );
}
