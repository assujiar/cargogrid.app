"use client";

import { useActionState, useState } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
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

function ErrorLine({ error }: { error: string | null }) {
  return error ? <p role="alert" className="text-xs text-danger">{error}</p> : null;
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
  return (
    <form action={formAction} className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
      <h3 className="text-sm font-semibold text-neutral-900">Submit a reimbursement request</h3>
      <div className="grid grid-cols-1 gap-2 sm:grid-cols-3">
        <label className="text-xs text-neutral-500">
          Category
          <input name="category" required className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" placeholder="e.g. travel" />
        </label>
        <label className="text-xs text-neutral-500">
          Amount (IDR)
          <input type="number" name="amount" min={0} step="0.01" required className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" />
        </label>
        <label className="text-xs text-neutral-500">
          Expense date
          <input type="date" name="expenseDate" required className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" />
        </label>
      </div>
      <label className="text-xs text-neutral-500">
        Description
        <textarea name="description" required minLength={1} rows={2} className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" />
      </label>
      <Button type="submit" variant="primary" loading={pending} loadingLabel="Submitting…">Submit request</Button>
      <ErrorLine error={state.error} />
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
            <input type="text" name="reason" placeholder="reason" required className="rounded border border-neutral-300 p-1 text-xs" />
            <Button type="submit" variant="destructive" loading={cancelPending} loadingLabel="Cancelling…">Cancel</Button>
          </form>
        ) : null}
      </div>
      <ErrorLine error={submitState.error ?? cancelState.error} />
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
