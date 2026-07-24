"use client";

import { useState, useTransition } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import { requestCostingAction } from "../actions.ts";

interface ComponentRow {
  code: string;
  description: string;
}

const EMPTY_ROW: ComponentRow = { code: "", description: "" };

/** Request-costing trigger (COM-148) -- collects up to 3 initial line items; a fully dynamic add/remove component list is a disclosed UI scope boundary (COM-148 build log). Blocked server-side unless the opportunity's own costing readiness is ready=true. */
export function RequestCostingForm({ tenantSlug, opportunityId, disabled }: { tenantSlug: string; opportunityId: string; disabled: boolean }) {
  const [rows, setRows] = useState<ComponentRow[]>([{ ...EMPTY_ROW }, { ...EMPTY_ROW }, { ...EMPTY_ROW }]);
  const [dueAt, setDueAt] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();

  function updateRow(index: number, field: keyof ComponentRow, value: string) {
    setRows((prev) => prev.map((row, i) => (i === index ? { ...row, [field]: value } : row)));
  }

  return (
    <div className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
      <h2 className="text-sm font-semibold text-neutral-900">Request costing</h2>
      {disabled ? <p className="text-sm text-neutral-600">Complete the opportunity&apos;s requirements above before requesting costing.</p> : null}

      {rows.map((row, index) => (
        <div key={index} className="flex gap-2">
          <input
            placeholder="Component code (e.g. ocean_freight)"
            value={row.code}
            onChange={(e) => updateRow(index, "code", e.target.value)}
            disabled={disabled}
            className="w-48 rounded-md border border-neutral-300 px-3 py-2 text-sm"
          />
          <input
            placeholder="Description"
            value={row.description}
            onChange={(e) => updateRow(index, "description", e.target.value)}
            disabled={disabled}
            className="flex-1 rounded-md border border-neutral-300 px-3 py-2 text-sm"
          />
        </div>
      ))}

      <div className="flex flex-col gap-1">
        <label htmlFor="due-at" className="text-sm font-medium text-neutral-700">
          Due date <span className="font-normal text-neutral-500">(optional)</span>
        </label>
        <input id="due-at" type="datetime-local" value={dueAt} onChange={(e) => setDueAt(e.target.value)} disabled={disabled} className="rounded-md border border-neutral-300 px-3 py-2 text-sm" />
      </div>

      {error ? (
        <p role="alert" className="text-sm text-danger">
          {error}
        </p>
      ) : null}

      <Button
        type="button"
        disabled={disabled}
        loading={pending}
        loadingLabel="Requesting…"
        onClick={() =>
          startTransition(async () => {
            const components = rows.filter((row) => row.code.trim()).map((row) => ({ code: row.code.trim(), description: row.description.trim() || null }));
            const result = await requestCostingAction(tenantSlug, opportunityId, components, dueAt ? new Date(dueAt).toISOString() : null);
            setError(result.error);
          })
        }
      >
        Request costing
      </Button>
    </div>
  );
}
