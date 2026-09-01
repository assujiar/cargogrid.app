"use client";

import { useActionState, useState } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
import { StatusBadge, type StatusTone } from "../../../../../components/ui/status-badge.tsx";
import { EmptyState } from "../../../../../components/ui/empty-state.tsx";
import type {
  PayrollPeriodRow,
  PayrollComponentRow,
  PayrollRunRow,
  PayrollExceptionRow,
  PayrollReimbursementRow,
  PayrollFinanceHandoffBatchRow,
} from "../../../../../server/contracts/payroll/payroll.ts";
import type { PayrollAdminActionState } from "./actions.ts";

const INITIAL_STATE: PayrollAdminActionState = { error: null };
const PERIOD_STATUS_TONE: Record<string, StatusTone> = {
  open: "neutral", input_frozen: "info", calculating: "warning", calculated: "warning", under_review: "warning",
  pending_approval: "warning", finalized: "success", cancelled: "danger",
};
const RUN_STATUS_TONE: Record<string, StatusTone> = {
  draft: "neutral", calculating: "warning", calculated: "info", exception: "danger", pending_approval: "warning",
  finalized: "success", cancelled: "danger",
};

type BoundAction = (prevState: PayrollAdminActionState, formData: FormData) => Promise<PayrollAdminActionState>;

function ErrorLine({ error }: { error: string | null }) {
  return error ? <p role="alert" className="text-xs text-danger">{error}</p> : null;
}

function CreatePeriodForm({ createPayrollPeriodAction }: { createPayrollPeriodAction: BoundAction }) {
  const [state, formAction, pending] = useActionState(createPayrollPeriodAction, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
      <h3 className="text-sm font-semibold text-neutral-900">Create payroll period</h3>
      <label className="text-xs text-neutral-500">
        Code
        <input name="code" required className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" placeholder="e.g. 2026-08" />
      </label>
      <label className="text-xs text-neutral-500">
        Type
        <select name="periodType" defaultValue="monthly" className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm">
          <option value="monthly">Monthly</option>
          <option value="semi_monthly">Semi-monthly</option>
          <option value="biweekly">Biweekly</option>
          <option value="weekly">Weekly</option>
        </select>
      </label>
      <div className="grid grid-cols-1 gap-2 sm:grid-cols-3">
        <label className="text-xs text-neutral-500">
          Period start
          <input type="date" name="periodStart" required className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" />
        </label>
        <label className="text-xs text-neutral-500">
          Period end
          <input type="date" name="periodEnd" required className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" />
        </label>
        <label className="text-xs text-neutral-500">
          Pay date
          <input type="date" name="payDate" required className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" />
        </label>
      </div>
      <Button type="submit" variant="primary" loading={pending} loadingLabel="Creating…">Create period</Button>
      <ErrorLine error={state.error} />
    </form>
  );
}

function ReopenPeriodInputsForm({ row, reopenPayrollPeriodInputsAction }: { row: PayrollPeriodRow; reopenPayrollPeriodInputsAction: (periodId: string, expectedVersion: number) => BoundAction }) {
  const [state, formAction, pending] = useActionState(reopenPayrollPeriodInputsAction(row.id, row.recordVersion), INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col gap-2">
      <label className="text-xs text-neutral-500">
        Reason (required)
        <input name="reason" required className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" placeholder="e.g. correcting a frozen-input data error" />
      </label>
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Reopening…">Reopen inputs</Button>
      <ErrorLine error={state.error} />
    </form>
  );
}

function PeriodRowItem({
  row, freezePayrollPeriodInputsAction, reopenPayrollPeriodInputsAction,
}: {
  row: PayrollPeriodRow;
  freezePayrollPeriodInputsAction: (periodId: string, expectedVersion: number) => BoundAction;
  reopenPayrollPeriodInputsAction: (periodId: string, expectedVersion: number) => BoundAction;
}) {
  const [state, formAction, pending] = useActionState(freezePayrollPeriodInputsAction(row.id, row.recordVersion), INITIAL_STATE);
  return (
    <li className="flex flex-col gap-2 rounded-md border border-neutral-200 p-3 text-sm">
      <div className="flex items-center justify-between">
        <span>{row.code} — {row.periodStart} to {row.periodEnd} (pay {row.payDate})</span>
        <StatusBadge tone={PERIOD_STATUS_TONE[row.status] ?? "neutral"} label={row.status.replace(/_/g, " ")} />
      </div>
      {row.frozenEmployeeCount !== null ? <div className="text-xs text-neutral-500">frozen for {row.frozenEmployeeCount} employee(s)</div> : null}
      {row.status === "open" ? (
        <form action={formAction}>
          <Button type="submit" variant="secondary" loading={pending} loadingLabel="Freezing…">Freeze inputs</Button>
        </form>
      ) : null}
      <ErrorLine error={state.error} />
      {/* HRT-282 Tier C batch review fix: the only path back from
         input_frozen to open -- without this, an HR admin who freezes a
         period and finds a data error had no in-app way to correct it. */}
      {row.status === "input_frozen" ? (
        <ReopenPeriodInputsForm row={row} reopenPayrollPeriodInputsAction={reopenPayrollPeriodInputsAction} />
      ) : null}
    </li>
  );
}

function CreateComponentForm({ createPayrollComponentAction }: { createPayrollComponentAction: BoundAction }) {
  const [state, formAction, pending] = useActionState(createPayrollComponentAction, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
      <h3 className="text-sm font-semibold text-neutral-900">Create pay component</h3>
      <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">
        <label className="text-xs text-neutral-500">
          Code
          <input name="code" required className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" placeholder="e.g. base_salary" />
        </label>
        <label className="text-xs text-neutral-500">
          Name
          <input name="name" required className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" />
        </label>
      </div>
      <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">
        <label className="text-xs text-neutral-500">
          Type
          <select name="componentType" defaultValue="earning" className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm">
            <option value="earning">Earning</option>
            <option value="deduction">Deduction</option>
            <option value="benefit_employer_cost">Benefit (employer cost)</option>
            <option value="tax">Tax</option>
          </select>
        </label>
        <label className="text-xs text-neutral-500">
          GL mapping category
          <input name="glMappingCategory" required className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" placeholder="e.g. salary_expense" />
        </label>
      </div>
      <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">
        <label className="text-xs text-neutral-500">
          Calculation method (optional first version)
          <select name="calculationMethod" defaultValue="fixed_amount" className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm">
            <option value="fixed_amount">Fixed amount</option>
            <option value="hourly_rate">Hourly rate</option>
          </select>
        </label>
        <label className="text-xs text-neutral-500">
          Amount (IDR)
          <input type="number" name="fixedAmount" min={0} step="0.01" className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" />
        </label>
      </div>
      <Button type="submit" variant="primary" loading={pending} loadingLabel="Creating…">Create component</Button>
      <ErrorLine error={state.error} />
    </form>
  );
}

function AssignComponentForm({ components, assignPayrollComponentAction }: { components: PayrollComponentRow[]; assignPayrollComponentAction: BoundAction }) {
  const [state, formAction, pending] = useActionState(assignPayrollComponentAction, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
      <h3 className="text-sm font-semibold text-neutral-900">Assign a component to an employee</h3>
      <label className="text-xs text-neutral-500">
        Employee ID
        <input name="employeeId" required className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" placeholder="employee master_record_id" />
      </label>
      <label className="text-xs text-neutral-500">
        Component
        <select name="componentId" required className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm">
          {components.map((c) => (
            <option key={c.id} value={c.id}>{c.code} ({c.componentType}{c.isStatutory ? ", statutory — inactive pending SME evidence" : ""})</option>
          ))}
        </select>
      </label>
      <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">
        <label className="text-xs text-neutral-500">
          Effective from
          <input type="date" name="effectiveFrom" required className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" />
        </label>
        <label className="text-xs text-neutral-500">
          Manual amount (only for manual_per_run components)
          <input type="number" name="manualAmount" min={0} step="0.01" className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" />
        </label>
      </div>
      <Button type="submit" variant="primary" loading={pending} loadingLabel="Assigning…">Assign</Button>
      <ErrorLine error={state.error} />
    </form>
  );
}

function IssueLoanForm({ issuePayrollLoanAction }: { issuePayrollLoanAction: BoundAction }) {
  const [state, formAction, pending] = useActionState(issuePayrollLoanAction, INITIAL_STATE);
  const [termCount, setTermCount] = useState("");
  const [isOpeningBalance, setIsOpeningBalance] = useState(false);
  const termCountNumber = Number(termCount);
  const remainingMax = termCount && termCountNumber > 0 ? termCountNumber : undefined;

  return (
    <form action={formAction} className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
      <h3 className="text-sm font-semibold text-neutral-900">Issue an employee loan/advance</h3>
      <label className="text-xs text-neutral-500">
        Employee ID
        <input name="employeeId" required className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" />
      </label>
      <div className="grid grid-cols-1 gap-2 sm:grid-cols-3">
        <label className="text-xs text-neutral-500">
          Principal (IDR)
          <input type="number" name="principalAmount" min={0} step="0.01" required className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" />
        </label>
        <label className="text-xs text-neutral-500">
          Installment (IDR)
          <input type="number" name="installmentAmount" min={0} step="0.01" required className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" />
        </label>
        <label className="text-xs text-neutral-500">
          Term (installments)
          <input
            type="number" name="termCount" min={1} max={360} required value={termCount}
            onChange={(e) => setTermCount(e.target.value)}
            className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm"
          />
        </label>
      </div>
      <label className="inline-flex items-center gap-1 text-xs text-neutral-500">
        <input
          type="checkbox" name="isOpeningBalance" checked={isOpeningBalance}
          onChange={(e) => setIsOpeningBalance(e.target.checked)}
        /> This is an opening balance
      </label>
      <p className="text-xs text-neutral-400">
        Check this for a loan carried over from before this system was used, where some installments were already
        paid elsewhere. Leave unchecked for an ordinary new loan issued from today.
      </p>
      {isOpeningBalance ? (
        <label className="text-xs text-neutral-500">
          Remaining installments
          <input
            type="number" name="openingRemainingInstallments" min={0} max={remainingMax} required
            className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm"
          />
          <span className="mt-1 block text-xs text-neutral-400">
            How many of the {termCount || "term"} installments above are still unpaid (0 if this loan is already
            fully paid off, up to the full term count if none of it was paid before cutover). Cannot exceed the
            term count.
          </span>
        </label>
      ) : null}
      <Button type="submit" variant="primary" loading={pending} loadingLabel="Issuing…">Issue loan</Button>
      <ErrorLine error={state.error} />
    </form>
  );
}

function CreateRunForm({ periods, createPayrollRunAction }: { periods: PayrollPeriodRow[]; createPayrollRunAction: (periodId: string) => BoundAction }) {
  const eligible = periods.filter((p) => p.status !== "open");
  return (
    <div className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
      <h3 className="text-sm font-semibold text-neutral-900">Create a run</h3>
      {eligible.length === 0 ? (
        <p className="text-xs text-neutral-500">Freeze a period&apos;s inputs first before creating a run against it.</p>
      ) : (
        eligible.map((p) => <CreateRunFormRow key={p.id} period={p} createPayrollRunAction={createPayrollRunAction} />)
      )}
    </div>
  );
}

function CreateRunFormRow({ period, createPayrollRunAction }: { period: PayrollPeriodRow; createPayrollRunAction: (periodId: string) => BoundAction }) {
  const [state, formAction, pending] = useActionState(createPayrollRunAction(period.id), INITIAL_STATE);
  return (
    <form action={formAction} className="flex items-center gap-2 text-sm">
      <span className="flex-1">{period.code}</span>
      <select name="runType" defaultValue="regular" className="rounded border border-neutral-300 p-1 text-xs">
        <option value="regular">Regular</option>
        <option value="off_cycle">Off-cycle</option>
      </select>
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Creating…">Create run</Button>
      <ErrorLine error={state.error} />
    </form>
  );
}

function RunRowItem({
  row, myStepId, calculatePayrollRunAction, submitPayrollRunForFinalizationAction, finalizePayrollRunAction, cancelPayrollRunAction,
  requestPayrollRunCalculationCancellationAction, generateFinancePayrollHandoffAction,
}: {
  row: PayrollRunRow;
  myStepId: string | undefined;
  calculatePayrollRunAction: (runId: string, expectedVersion: number) => BoundAction;
  submitPayrollRunForFinalizationAction: (runId: string, expectedVersion: number) => BoundAction;
  finalizePayrollRunAction: (requestStepId: string, decision: "approved" | "rejected") => BoundAction;
  cancelPayrollRunAction: (runId: string, expectedVersion: number) => BoundAction;
  requestPayrollRunCalculationCancellationAction: (runId: string) => BoundAction;
  generateFinancePayrollHandoffAction: (runId: string) => BoundAction;
}) {
  const [calcState, calcAction, calcPending] = useActionState(calculatePayrollRunAction(row.id, row.recordVersion), INITIAL_STATE);
  const [submitState, submitAction, submitPending] = useActionState(submitPayrollRunForFinalizationAction(row.id, row.recordVersion), INITIAL_STATE);
  const [finalizeState, finalizeAction, finalizePending] = useActionState(finalizePayrollRunAction(myStepId ?? "", "approved"), INITIAL_STATE);
  const [rejectState, rejectAction, rejectPending] = useActionState(finalizePayrollRunAction(myStepId ?? "", "rejected"), INITIAL_STATE);
  const [cancelState, cancelAction, cancelPending] = useActionState(cancelPayrollRunAction(row.id, row.recordVersion), INITIAL_STATE);
  const [requestCancelState, requestCancelAction, requestCancelPending] = useActionState(requestPayrollRunCalculationCancellationAction(row.id), INITIAL_STATE);
  const [handoffState, handoffAction, handoffPending] = useActionState(generateFinancePayrollHandoffAction(row.id), INITIAL_STATE);

  return (
    <li className="flex flex-col gap-2 rounded-md border border-neutral-200 p-3 text-sm">
      <div className="flex items-center justify-between">
        <span>{row.runType} run — {row.employeeCount} employee(s), {row.exceptionCount} exception(s)</span>
        <StatusBadge tone={RUN_STATUS_TONE[row.status] ?? "neutral"} label={row.status.replace(/_/g, " ")} />
      </div>
      <div className="flex flex-wrap gap-2">
        {(row.status === "draft" || row.status === "calculated" || row.status === "exception") ? (
          <form action={calcAction}>
            <Button type="submit" variant="secondary" loading={calcPending} loadingLabel="Calculating…">
              {row.status === "draft" ? "Calculate" : "Recalculate"}
            </Button>
          </form>
        ) : null}
        {row.status === "calculated" ? (
          <form action={submitAction}>
            <Button type="submit" variant="primary" loading={submitPending} loadingLabel="Submitting…">Submit for finalization</Button>
          </form>
        ) : null}
        {row.status === "pending_approval" && myStepId ? (
          <>
            <form action={finalizeAction} className="flex items-center gap-1">
              <input type="text" name="reason" placeholder="reason" required className="rounded border border-neutral-300 p-1 text-xs" />
              <Button type="submit" variant="primary" loading={finalizePending} loadingLabel="Finalizing…">Approve &amp; finalize</Button>
            </form>
            <form action={rejectAction} className="flex items-center gap-1">
              <input type="text" name="reason" placeholder="reason" required className="rounded border border-neutral-300 p-1 text-xs" />
              <Button type="submit" variant="destructive" loading={rejectPending} loadingLabel="Rejecting…">Reject</Button>
            </form>
          </>
        ) : null}
        {row.status === "pending_approval" && !myStepId ? <span className="text-xs text-neutral-500">Awaiting a distinct eligible approver — you are not eligible to decide this step.</span> : null}
        {(row.status === "draft" || row.status === "calculated" || row.status === "exception") ? (
          <form action={cancelAction} className="flex items-center gap-1">
            <input type="text" name="reason" placeholder="reason" required className="rounded border border-neutral-300 p-1 text-xs" />
            <Button type="submit" variant="destructive" loading={cancelPending} loadingLabel="Cancelling…">Cancel run</Button>
          </form>
        ) : null}
        {row.status === "calculating" ? (
          <form action={requestCancelAction}>
            <Button type="submit" variant="destructive" loading={requestCancelPending} loadingLabel="Requesting…">Request cancellation</Button>
          </form>
        ) : null}
        {row.status === "finalized" ? (
          <form action={handoffAction}>
            <Button type="submit" variant="secondary" loading={handoffPending} loadingLabel="Generating…">Generate Finance handoff</Button>
          </form>
        ) : null}
      </div>
      <ErrorLine error={calcState.error ?? submitState.error ?? finalizeState.error ?? rejectState.error ?? cancelState.error ?? requestCancelState.error ?? handoffState.error} />
    </li>
  );
}

function ExceptionRowItem({ row, resolvePayrollExceptionAction, waivePayrollExceptionAction }: {
  row: PayrollExceptionRow;
  resolvePayrollExceptionAction: (exceptionId: string) => BoundAction;
  waivePayrollExceptionAction: (exceptionId: string) => BoundAction;
}) {
  const [resolveState, resolveAction, resolvePending] = useActionState(resolvePayrollExceptionAction(row.id), INITIAL_STATE);
  const [waiveState, waiveAction, waivePending] = useActionState(waivePayrollExceptionAction(row.id), INITIAL_STATE);
  return (
    <li className="flex flex-col gap-2 rounded-md border border-neutral-200 p-3 text-sm">
      <div className="flex items-center justify-between">
        <span>{row.exceptionType}: {row.message}</span>
        <StatusBadge tone={row.severity === "high" ? "danger" : row.severity === "medium" ? "warning" : "neutral"} label={row.severity} />
      </div>
      <form action={resolveAction} className="flex items-center gap-1">
        <input type="text" name="resolutionNote" placeholder="resolution note" required className="flex-1 rounded border border-neutral-300 p-1 text-xs" />
        <Button type="submit" variant="secondary" loading={resolvePending} loadingLabel="Resolving…">Resolve</Button>
      </form>
      <form action={waiveAction} className="flex items-center gap-1">
        <input type="text" name="resolutionNote" placeholder="waive reason" required className="flex-1 rounded border border-neutral-300 p-1 text-xs" />
        <Button type="submit" variant="destructive" loading={waivePending} loadingLabel="Waiving…">Waive (HRS:Override)</Button>
      </form>
      <ErrorLine error={resolveState.error ?? waiveState.error} />
    </li>
  );
}

function ReimbursementRowItem({ row, decidePayrollReimbursementAction }: { row: PayrollReimbursementRow; decidePayrollReimbursementAction: (requestId: string, expectedVersion: number, decision: "approve" | "reject") => BoundAction }) {
  const [approveState, approveAction, approvePending] = useActionState(decidePayrollReimbursementAction(row.id, row.recordVersion, "approve"), INITIAL_STATE);
  const [rejectState, rejectAction, rejectPending] = useActionState(decidePayrollReimbursementAction(row.id, row.recordVersion, "reject"), INITIAL_STATE);
  return (
    <li className="flex flex-col gap-2 rounded-md border border-neutral-200 p-3 text-sm">
      <div>{row.category} — {row.amount} {row.currency} — {row.description}</div>
      <div className="flex flex-wrap gap-2">
        <form action={approveAction} className="flex items-center gap-1">
          <input type="text" name="decidedReason" placeholder="reason" required className="rounded border border-neutral-300 p-1 text-xs" />
          <Button type="submit" variant="primary" loading={approvePending} loadingLabel="Approving…">Approve</Button>
        </form>
        <form action={rejectAction} className="flex items-center gap-1">
          <input type="text" name="decidedReason" placeholder="reason" required className="rounded border border-neutral-300 p-1 text-xs" />
          <Button type="submit" variant="destructive" loading={rejectPending} loadingLabel="Rejecting…">Reject</Button>
        </form>
      </div>
      <ErrorLine error={approveState.error ?? rejectState.error} />
    </li>
  );
}

function HandoffRowItem({ row, acknowledgeFinancePayrollHandoffAction }: { row: PayrollFinanceHandoffBatchRow; acknowledgeFinancePayrollHandoffAction: (batchId: string, expectedVersion: number) => BoundAction }) {
  const [state, formAction, pending] = useActionState(acknowledgeFinancePayrollHandoffAction(row.id, row.recordVersion), INITIAL_STATE);
  return (
    <li className="flex flex-col gap-2 rounded-md border border-neutral-200 p-3 text-sm">
      <div>Net pay total: {row.netPayTotal} {row.currency} — {row.employeeCount} employee(s)</div>
      <form action={formAction}>
        <Button type="submit" variant="primary" loading={pending} loadingLabel="Acknowledging…">Acknowledge (requires FIN:Edit)</Button>
      </form>
      <ErrorLine error={state.error} />
    </li>
  );
}

export function PayrollAdminPanel({
  periods, components, runs, openExceptions, pendingReimbursements, pendingHandoffs, finalizedRunTotals, myStepIdByApprovalRequestId,
  createPayrollPeriodAction, freezePayrollPeriodInputsAction, reopenPayrollPeriodInputsAction, createPayrollComponentAction, assignPayrollComponentAction,
  decidePayrollReimbursementAction, issuePayrollLoanAction, createPayrollRunAction, calculatePayrollRunAction,
  resolvePayrollExceptionAction, waivePayrollExceptionAction, submitPayrollRunForFinalizationAction, finalizePayrollRunAction,
  cancelPayrollRunAction, requestPayrollRunCalculationCancellationAction, generateFinancePayrollHandoffAction, acknowledgeFinancePayrollHandoffAction,
}: {
  periods: PayrollPeriodRow[];
  components: PayrollComponentRow[];
  runs: PayrollRunRow[];
  openExceptions: PayrollExceptionRow[];
  pendingReimbursements: PayrollReimbursementRow[];
  pendingHandoffs: PayrollFinanceHandoffBatchRow[];
  finalizedRunTotals: { runId: string; netPayTotal: number; currency: string }[];
  myStepIdByApprovalRequestId: Record<string, string>;
  createPayrollPeriodAction: BoundAction;
  freezePayrollPeriodInputsAction: (periodId: string, expectedVersion: number) => BoundAction;
  reopenPayrollPeriodInputsAction: (periodId: string, expectedVersion: number) => BoundAction;
  createPayrollComponentAction: BoundAction;
  assignPayrollComponentAction: BoundAction;
  decidePayrollReimbursementAction: (requestId: string, expectedVersion: number, decision: "approve" | "reject") => BoundAction;
  issuePayrollLoanAction: BoundAction;
  createPayrollRunAction: (periodId: string) => BoundAction;
  calculatePayrollRunAction: (runId: string, expectedVersion: number) => BoundAction;
  resolvePayrollExceptionAction: (exceptionId: string) => BoundAction;
  waivePayrollExceptionAction: (exceptionId: string) => BoundAction;
  submitPayrollRunForFinalizationAction: (runId: string, expectedVersion: number) => BoundAction;
  finalizePayrollRunAction: (requestStepId: string, decision: "approved" | "rejected") => BoundAction;
  cancelPayrollRunAction: (runId: string, expectedVersion: number) => BoundAction;
  requestPayrollRunCalculationCancellationAction: (runId: string) => BoundAction;
  generateFinancePayrollHandoffAction: (runId: string) => BoundAction;
  acknowledgeFinancePayrollHandoffAction: (batchId: string, expectedVersion: number) => BoundAction;
}) {
  return (
    <div className="flex flex-col gap-8 p-6">
      <header>
        <h1 className="text-lg font-semibold text-neutral-900">Payroll</h1>
        <p className="text-sm text-neutral-500">
          Configure components, freeze inputs, calculate and finalize runs, and hand off approved figures to Finance. Compensation
          visibility here requires the HRS:View payroll permission specifically — never inherited from org-hierarchy manager scope.
        </p>
      </header>

      <section className="flex flex-col gap-3">
        <h2 className="text-sm font-semibold text-neutral-700">Periods</h2>
        <CreatePeriodForm createPayrollPeriodAction={createPayrollPeriodAction} />
        {periods.length === 0 ? (
          <EmptyState title="No payroll periods yet" description="Create the first period above." />
        ) : (
          <ul className="flex flex-col gap-2">
            {periods.map((p) => (
              <PeriodRowItem
                key={p.id}
                row={p}
                freezePayrollPeriodInputsAction={freezePayrollPeriodInputsAction}
                reopenPayrollPeriodInputsAction={reopenPayrollPeriodInputsAction}
              />
            ))}
          </ul>
        )}
      </section>

      <section className="flex flex-col gap-3">
        <h2 className="text-sm font-semibold text-neutral-700">Components</h2>
        <CreateComponentForm createPayrollComponentAction={createPayrollComponentAction} />
        <AssignComponentForm components={components} assignPayrollComponentAction={assignPayrollComponentAction} />
        <ul className="flex flex-col gap-1 text-xs text-neutral-500">
          {components.map((c) => (
            <li key={c.id}>{c.code} — {c.componentType}{c.isStatutory ? " — statutory, inactive pending dated SME evidence (RPD-016)" : ""}</li>
          ))}
        </ul>
      </section>

      <section className="flex flex-col gap-3">
        <h2 className="text-sm font-semibold text-neutral-700">Loans</h2>
        <IssueLoanForm issuePayrollLoanAction={issuePayrollLoanAction} />
      </section>

      <section className="flex flex-col gap-3">
        <h2 className="text-sm font-semibold text-neutral-700">Reimbursements pending decision</h2>
        {pendingReimbursements.length === 0 ? (
          <EmptyState title="Nothing pending" description="No reimbursement requests are awaiting a decision." />
        ) : (
          <ul className="flex flex-col gap-2">{pendingReimbursements.map((r) => <ReimbursementRowItem key={r.id} row={r} decidePayrollReimbursementAction={decidePayrollReimbursementAction} />)}</ul>
        )}
      </section>

      <section className="flex flex-col gap-3">
        <h2 className="text-sm font-semibold text-neutral-700">Runs</h2>
        <CreateRunForm periods={periods} createPayrollRunAction={createPayrollRunAction} />
        {runs.length === 0 ? (
          <EmptyState title="No runs yet" description="Create a run against a period whose inputs are frozen." />
        ) : (
          <ul className="flex flex-col gap-2">
            {runs.map((r) => (
              <RunRowItem
                key={r.id}
                row={r}
                myStepId={r.approvalRequestId ? myStepIdByApprovalRequestId[r.approvalRequestId] : undefined}
                calculatePayrollRunAction={calculatePayrollRunAction}
                submitPayrollRunForFinalizationAction={submitPayrollRunForFinalizationAction}
                finalizePayrollRunAction={finalizePayrollRunAction}
                cancelPayrollRunAction={cancelPayrollRunAction}
                requestPayrollRunCalculationCancellationAction={requestPayrollRunCalculationCancellationAction}
                generateFinancePayrollHandoffAction={generateFinancePayrollHandoffAction}
              />
            ))}
          </ul>
        )}
      </section>

      <section className="flex flex-col gap-3">
        <h2 className="text-sm font-semibold text-neutral-700">Open exceptions</h2>
        {openExceptions.length === 0 ? (
          <EmptyState title="No open exceptions" />
        ) : (
          <ul className="flex flex-col gap-2">{openExceptions.map((e) => <ExceptionRowItem key={e.id} row={e} resolvePayrollExceptionAction={resolvePayrollExceptionAction} waivePayrollExceptionAction={waivePayrollExceptionAction} />)}</ul>
        )}
      </section>

      <section className="flex flex-col gap-3">
        <h2 className="text-sm font-semibold text-neutral-700">Finance handoff — pending Finance acknowledgement</h2>
        <p className="text-xs text-neutral-500">
          Payroll generates this from a finalized run; acknowledging it requires FIN:Edit — the one Finance-side authority gate in this
          whole capability. Payroll never writes to any Finance-owned ledger table.
        </p>
        {finalizedRunTotals.length > 0 ? (
          <p className="text-xs text-neutral-500">
            Finalized run totals (net pay): {finalizedRunTotals.map((t) => `${t.netPayTotal.toFixed(2)} ${t.currency}`).join(", ")}
          </p>
        ) : null}
        {pendingHandoffs.length === 0 ? (
          <EmptyState title="Nothing pending acknowledgement" />
        ) : (
          <ul className="flex flex-col gap-2">{pendingHandoffs.map((h) => <HandoffRowItem key={h.id} row={h} acknowledgeFinancePayrollHandoffAction={acknowledgeFinancePayrollHandoffAction} />)}</ul>
        )}
      </section>
    </div>
  );
}
