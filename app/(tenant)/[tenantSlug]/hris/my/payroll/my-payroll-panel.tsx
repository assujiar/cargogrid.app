"use client";

import { useActionState, useState } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import { Input } from "../../../../../../components/forms/input.tsx";
import { Textarea } from "../../../../../../components/forms/textarea.tsx";
import { FormField } from "../../../../../../components/forms/form-field.tsx";
import { ValidationMessage } from "../../../../../../components/forms/validation-message.tsx";
import { StatusBadge, type StatusTone } from "../../../../../../components/ui/status-badge.tsx";
import { EmptyState } from "../../../../../../components/ui/empty-state.tsx";
import type { PayslipRow, PayrollReimbursementRow, PayrollLoanRow } from "../../../../../../server/contracts/payroll/payroll.ts";
import type { MyPayrollActionState } from "./actions.ts";

const INITIAL_STATE: MyPayrollActionState = { error: null };
const REIMB_STATUS_TONE: Record<string, StatusTone> = {
  draft: "neutral", pending_approval: "warning", approved: "success", rejected: "danger", cancelled: "neutral", paid: "success",
};
const LOAN_STATUS_TONE: Record<string, StatusTone> = { active: "info", completed: "success", cancelled: "danger" };

type BoundAction = (prevState: MyPayrollActionState, formData: FormData) => Promise<MyPayrollActionState>;

function ErrorLine({ error, id }: { error: string | null; id?: string }) {
  return error ? <ValidationMessage id={id}>{error}</ValidationMessage> : null;
}

function PayslipCard({ row }: { row: PayslipRow }) {
  const [expanded, setExpanded] = useState(false);
  return (
    <li className="flex flex-col gap-2 rounded-md border border-neutral-200 p-3 text-sm">
      <div className="flex items-center justify-between">
        <span>Pay period ending — net pay {row.netPay} {row.currency}</span>
        <Button type="button" variant="secondary" onClick={() => setExpanded((v) => !v)}>{expanded ? "Hide detail" : "Show detail"}</Button>
      </div>
      {expanded ? (
        <div className="flex flex-col gap-1 text-xs text-neutral-600">
          <div>Gross earnings: {row.grossEarnings} {row.currency}</div>
          <div>Deductions: {row.totalDeductions} {row.currency}</div>
          <div>Tax: {row.totalTax} {row.currency}</div>
          <div>Reimbursement: {row.totalReimbursement} {row.currency}</div>
          <div>Loan repayment: {row.totalLoanRepayment} {row.currency}</div>
          <ul className="mt-2 flex flex-col gap-1 border-t border-neutral-100 pt-2">
            {row.lineItems.map((li, idx) => (
              <li key={idx}>{li.description ?? li.lineType} — {li.amount} {li.currency}</li>
            ))}
          </ul>
        </div>
      ) : null}
    </li>
  );
}

function CreateReimbursementForm({ createMyReimbursementRequestAction }: { createMyReimbursementRequestAction: BoundAction }) {
  const [state, formAction, pending] = useActionState(createMyReimbursementRequestAction, INITIAL_STATE);
  const describedBy = state.error ? "create-reimbursement-error" : undefined;
  return (
    <form action={formAction} className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4" noValidate>
      <h3 className="text-sm font-semibold text-neutral-900">Submit a reimbursement request</h3>
      <div className="grid grid-cols-1 gap-2 sm:grid-cols-3">
        <FormField id="reimbursement-category" label="Category">
          <Input id="reimbursement-category" name="category" required placeholder="e.g. travel" invalid={Boolean(state.error)} aria-describedby={describedBy} />
        </FormField>
        <FormField id="reimbursement-amount" label="Amount (IDR)">
          <Input id="reimbursement-amount" type="number" name="amount" min={0} step="0.01" required invalid={Boolean(state.error)} aria-describedby={describedBy} />
        </FormField>
        <FormField id="reimbursement-expense-date" label="Expense date">
          <Input id="reimbursement-expense-date" type="date" name="expenseDate" required invalid={Boolean(state.error)} aria-describedby={describedBy} />
        </FormField>
      </div>
      <FormField id="reimbursement-description" label="Description">
        <Textarea id="reimbursement-description" name="description" required minLength={1} rows={2} invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <Button type="submit" variant="primary" loading={pending} loadingLabel="Submitting…">Submit request</Button>
      {state.error ? <ValidationMessage id="create-reimbursement-error">{state.error}</ValidationMessage> : null}
    </form>
  );
}

function ReimbursementRowItem({ row, submitMyReimbursementRequestAction, cancelMyReimbursementRequestAction }: {
  row: PayrollReimbursementRow;
  submitMyReimbursementRequestAction: (requestId: string, expectedVersion: number) => BoundAction;
  cancelMyReimbursementRequestAction: (requestId: string, expectedVersion: number) => BoundAction;
}) {
  const [submitState, submitAction, submitPending] = useActionState(submitMyReimbursementRequestAction(row.id, row.recordVersion), INITIAL_STATE);
  const [cancelState, cancelAction, cancelPending] = useActionState(cancelMyReimbursementRequestAction(row.id, row.recordVersion), INITIAL_STATE);
  return (
    <li className="flex flex-col gap-2 rounded-md border border-neutral-200 p-3 text-sm">
      <div className="flex items-center justify-between">
        <span>{row.category} — {row.amount} {row.currency} — {row.description}</span>
        <StatusBadge tone={REIMB_STATUS_TONE[row.status] ?? "neutral"} label={row.status.replace(/_/g, " ")} />
      </div>
      <div className="flex gap-2">
        {row.status === "draft" ? (
          <form action={submitAction}>
            <Button type="submit" variant="primary" loading={submitPending} loadingLabel="Submitting…">Submit</Button>
          </form>
        ) : null}
        {(row.status === "draft" || row.status === "pending_approval") ? (
          <form action={cancelAction} className="flex items-center gap-1">
            <label htmlFor={`reimb-cancel-reason-${row.id}`} className="sr-only">
              Reason
            </label>
            <Input id={`reimb-cancel-reason-${row.id}`} type="text" name="reason" placeholder="reason" required className="text-xs" invalid={Boolean(cancelState.error)} aria-describedby={cancelState.error ? `reimb-cancel-${row.id}-error` : undefined} />
            <Button type="submit" variant="destructive" loading={cancelPending} loadingLabel="Cancelling…">Cancel</Button>
          </form>
        ) : null}
      </div>
      <ErrorLine error={submitState.error ?? cancelState.error} id={`reimb-cancel-${row.id}-error`} />
    </li>
  );
}

export function MyPayrollPanel({
  payslips, reimbursements, loans, createMyReimbursementRequestAction, submitMyReimbursementRequestAction, cancelMyReimbursementRequestAction,
}: {
  payslips: PayslipRow[];
  reimbursements: PayrollReimbursementRow[];
  loans: PayrollLoanRow[];
  createMyReimbursementRequestAction: BoundAction;
  submitMyReimbursementRequestAction: (requestId: string, expectedVersion: number) => BoundAction;
  cancelMyReimbursementRequestAction: (requestId: string, expectedVersion: number) => BoundAction;
}) {
  return (
    <div className="flex flex-col gap-8 p-6">
      <header>
        <h1 className="text-lg font-semibold text-neutral-900">My payroll</h1>
        <p className="text-sm text-neutral-500">Your own payslips, reimbursement requests, and loans — private to you.</p>
      </header>

      <section className="flex flex-col gap-3">
        <h2 className="text-sm font-semibold text-neutral-700">Payslips</h2>
        {payslips.length === 0 ? (
          <EmptyState title="No payslips yet" description="A payslip appears here once a payroll run covering you is finalized." />
        ) : (
          <ul className="flex flex-col gap-2">{payslips.map((p) => <PayslipCard key={p.id} row={p} />)}</ul>
        )}
      </section>

      <section className="flex flex-col gap-3">
        <h2 className="text-sm font-semibold text-neutral-700">Reimbursements</h2>
        <CreateReimbursementForm createMyReimbursementRequestAction={createMyReimbursementRequestAction} />
        {reimbursements.length === 0 ? (
          <EmptyState title="No reimbursement requests yet" />
        ) : (
          <ul className="flex flex-col gap-2">
            {reimbursements.map((r) => (
              <ReimbursementRowItem key={r.id} row={r} submitMyReimbursementRequestAction={submitMyReimbursementRequestAction} cancelMyReimbursementRequestAction={cancelMyReimbursementRequestAction} />
            ))}
          </ul>
        )}
      </section>

      <section className="flex flex-col gap-3">
        <h2 className="text-sm font-semibold text-neutral-700">Loans</h2>
        {loans.length === 0 ? (
          <EmptyState title="No loans on record" />
        ) : (
          <ul className="flex flex-col gap-2">
            {loans.map((l) => (
              <li key={l.id} className="flex items-center justify-between rounded-md border border-neutral-200 p-3 text-sm">
                <span>Principal {l.principalAmount} {l.currency} — {l.remainingInstallments} of {l.termCount} installments remaining</span>
                <StatusBadge tone={LOAN_STATUS_TONE[l.status] ?? "neutral"} label={l.status} />
              </li>
            ))}
          </ul>
        )}
      </section>
    </div>
  );
}
