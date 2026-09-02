"use client";

import { useState, useTransition } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import { requestCostingAction } from "../actions.ts";
import { Input } from "../../../../../../components/forms/input.tsx";
import { FormField } from "../../../../../../components/forms/form-field.tsx";
import { ValidationMessage } from "../../../../../../components/forms/validation-message.tsx";

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

  const describedBy = error ? "request-costing-error" : undefined;
  const invalid = Boolean(error);

  function updateRow(index: number, field: keyof ComponentRow, value: string) {
    setRows((prev) => prev.map((row, i) => (i === index ? { ...row, [field]: value } : row)));
  }

  return (
    <div className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
      <h2 className="text-sm font-semibold text-neutral-900">Request costing</h2>
      {disabled ? <p className="text-sm text-neutral-600">Complete the opportunity&apos;s requirements above before requesting costing.</p> : null}

      {rows.map((row, index) => (
        <div key={index} className="flex gap-2">
          <div className="w-48">
            <FormField id={`request-costing-code-${index}`} label={<span className="sr-only">{`Component ${index + 1} code`}</span>}>
              <Input
                id={`request-costing-code-${index}`}
                placeholder="Component code (e.g. ocean_freight)"
                value={row.code}
                onChange={(e) => updateRow(index, "code", e.target.value)}
                disabled={disabled}
                invalid={invalid}
                aria-describedby={describedBy}
              />
            </FormField>
          </div>
          <div className="flex-1">
            <FormField id={`request-costing-description-${index}`} label={<span className="sr-only">{`Component ${index + 1} description`}</span>}>
              <Input
                id={`request-costing-description-${index}`}
                placeholder="Description"
                value={row.description}
                onChange={(e) => updateRow(index, "description", e.target.value)}
                disabled={disabled}
                invalid={invalid}
                aria-describedby={describedBy}
              />
            </FormField>
          </div>
        </div>
      ))}

      <FormField
        id="due-at"
        label={
          <>
            Due date <span className="font-normal text-neutral-500">(optional)</span>
          </>
        }
      >
        <Input id="due-at" type="datetime-local" value={dueAt} onChange={(e) => setDueAt(e.target.value)} disabled={disabled} invalid={invalid} aria-describedby={describedBy} />
      </FormField>

      {error ? <ValidationMessage id="request-costing-error">{error}</ValidationMessage> : null}

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
