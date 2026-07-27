"use client";

import { useActionState } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import type { JobOrderFormState } from "./actions.ts";
import { OVERRIDABLE_SNAPSHOT_COLUMNS, type OverridableSnapshotColumn } from "../../../../../../server/contracts/job-order/job-order.ts";

const INITIAL_STATE: JobOrderFormState = { error: null };

const SNAPSHOT_COLUMN_LABELS: Record<OverridableSnapshotColumn, string> = {
  customer_snapshot: "Customer",
  cargo_service_snapshot: "Cargo & service",
};

/**
 * The one bounded, reasoned, audited post-conversion correction path (OPS-168, Prompt
 * 168 §22) -- restricted to customer/cargo-service fields, never revenue/contract/
 * credit/acceptance (those remain immutable financial/acceptance evidence; a pricing
 * or acceptance correction is a new Commercial quotation version, not an Operations
 * override). A non-empty reason is mandatory, enforced server-side too.
 */
export function OverrideJobOrderForm({
  action,
}: {
  action: (snapshotColumn: OverridableSnapshotColumn, fieldPath: string, newValue: string, reason: string, prevState: JobOrderFormState, formData: FormData) => Promise<JobOrderFormState>;
}) {
  const [state, formAction, pending] = useActionState(
    async (prevState: JobOrderFormState, formData: FormData) => {
      const snapshotColumn = String(formData.get("snapshotColumn")) as OverridableSnapshotColumn;
      const fieldPath = String(formData.get("fieldPath") ?? "").trim();
      const newValue = String(formData.get("newValue") ?? "");
      const reason = String(formData.get("reason") ?? "").trim();
      return action(snapshotColumn, fieldPath, newValue, reason, prevState, formData);
    },
    INITIAL_STATE,
  );

  return (
    <form action={formAction} className="flex flex-col gap-2" noValidate>
      <div className="flex flex-col gap-1">
        <label htmlFor="snapshotColumn" className="text-sm font-medium text-neutral-700">
          Snapshot
        </label>
        <select id="snapshotColumn" name="snapshotColumn" className="w-64 rounded-md border border-neutral-300 px-3 py-2 text-sm" defaultValue={OVERRIDABLE_SNAPSHOT_COLUMNS[0]}>
          {OVERRIDABLE_SNAPSHOT_COLUMNS.map((column) => (
            <option key={column} value={column}>
              {SNAPSHOT_COLUMN_LABELS[column]}
            </option>
          ))}
        </select>
      </div>

      <div className="flex flex-col gap-1">
        <label htmlFor="fieldPath" className="text-sm font-medium text-neutral-700">
          Field path
        </label>
        <input id="fieldPath" name="fieldPath" type="text" required placeholder="e.g. contactPhone" className="w-64 rounded-md border border-neutral-300 px-3 py-2 text-sm" />
      </div>

      <div className="flex flex-col gap-1">
        <label htmlFor="newValue" className="text-sm font-medium text-neutral-700">
          New value
        </label>
        <input id="newValue" name="newValue" type="text" required className="w-64 rounded-md border border-neutral-300 px-3 py-2 text-sm" />
      </div>

      <div className="flex flex-col gap-1">
        <label htmlFor="reason" className="text-sm font-medium text-neutral-700">
          Reason (required)
        </label>
        <input id="reason" name="reason" type="text" required minLength={1} className="w-96 rounded-md border border-neutral-300 px-3 py-2 text-sm" />
      </div>

      {state.error ? (
        <p role="alert" className="text-sm text-danger">
          {state.error}
        </p>
      ) : null}

      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Applying…" className="w-fit">
        Apply override
      </Button>
    </form>
  );
}
