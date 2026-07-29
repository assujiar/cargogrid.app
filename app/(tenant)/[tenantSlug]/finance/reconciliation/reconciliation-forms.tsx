"use client";

/** Reconciliation client forms (FIN-209, CG-S9-FIN-020). Same `useActionState`/bound-action split every prior capability's own forms already use. */

import { useActionState } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
import type { FinanceReconciliationFormState } from "./actions.ts";

const INITIAL_STATE: FinanceReconciliationFormState = { error: null };

type BoundAction = (prevState: FinanceReconciliationFormState, formData: FormData) => Promise<FinanceReconciliationFormState>;

export function ExecuteFinanceReconciliationRunForm({ action }: { action: BoundAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);

  return (
    <form action={formAction} className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4" noValidate>
      <h2 className="text-sm font-semibold text-text-primary">Execute a reconciliation run</h2>
      <p className="text-xs text-text-secondary">
        Requires FIN:Edit. Compares the ar/ap control account&apos;s own GL balance against the open-item total as of a fixed date; a variance
        beyond tolerance creates one exception. Reconciliation never silently writes a balance to force equality.
      </p>

      <div className="flex flex-wrap gap-3">
        <div className="flex flex-col gap-1">
          <label htmlFor="recon-scope" className="text-sm font-medium text-text-primary">
            Scope
          </label>
          <select id="recon-scope" name="scope" required defaultValue="ar" className="w-24 rounded-md border border-neutral-300 px-3 py-2 text-sm">
            <option value="ar">ar</option>
            <option value="ap">ap</option>
          </select>
        </div>

        <div className="flex flex-col gap-1">
          <label htmlFor="recon-asOfDate" className="text-sm font-medium text-text-primary">
            As-of date
          </label>
          <input id="recon-asOfDate" name="asOfDate" type="date" required className="w-40 rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        </div>

        <div className="flex flex-col gap-1">
          <label htmlFor="recon-toleranceAmount" className="text-sm font-medium text-text-primary">
            Tolerance amount
          </label>
          <input id="recon-toleranceAmount" name="toleranceAmount" type="number" min={0} step="0.01" defaultValue={0} className="w-32 rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        </div>
      </div>

      {state.error ? (
        <p role="alert" className="text-sm text-danger">
          {state.error}
        </p>
      ) : null}

      <Button type="submit" loading={pending} loadingLabel="Running…" className="w-fit">
        Execute run
      </Button>
    </form>
  );
}

export function ResolveFinanceReconciliationExceptionForm({ action }: { action: BoundAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col gap-1" noValidate>
      <input name="resolutionReason" type="text" required placeholder="Resolution reason (required)" className="w-48 rounded-md border border-neutral-300 px-2 py-1 text-xs" />
      {state.error ? (
        <p role="alert" className="text-xs text-danger">
          {state.error}
        </p>
      ) : null}
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Resolving…">
        Resolve
      </Button>
    </form>
  );
}

export function CertifyFinanceReconciliationRunForm({ action }: { action: BoundAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col gap-1" noValidate>
      <input name="reason" type="text" required placeholder="Certification reason (required)" className="w-48 rounded-md border border-neutral-300 px-2 py-1 text-xs" />
      {state.error ? (
        <p role="alert" className="text-xs text-danger">
          {state.error}
        </p>
      ) : null}
      <Button type="submit" loading={pending} loadingLabel="Certifying…">
        Certify
      </Button>
    </form>
  );
}
