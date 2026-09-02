"use client";

import { useActionState } from "react";
import Link from "next/link";
import { Button } from "../../../../components/ui/button.tsx";
import { Input } from "../../../../components/forms/input.tsx";
import { Textarea } from "../../../../components/forms/textarea.tsx";
import { FormField } from "../../../../components/forms/form-field.tsx";
import { ValidationMessage } from "../../../../components/forms/validation-message.tsx";
import { StatusBadge, type StatusTone } from "../../../../components/ui/status-badge.tsx";
import { EmptyState } from "../../../../components/ui/empty-state.tsx";
import type { AutomationRuleActionState } from "./actions.ts";
import type { AutomationRule, AutomationRuleStatus } from "../../../../server/contracts/automation-rule/automation-rule.ts";

const INITIAL_STATE: AutomationRuleActionState = { error: null };

const STATUS_TONE: Record<AutomationRuleStatus, StatusTone> = {
  active: "success",
  paused: "warning",
  archived: "neutral",
};

export function AutomationRuleManagementPanel({
  tenantSlug,
  rules,
  createAction,
}: {
  tenantSlug: string;
  rules: readonly AutomationRule[];
  createAction: (prevState: AutomationRuleActionState, formData: FormData) => Promise<AutomationRuleActionState>;
}) {
  const [state, formAction, pending] = useActionState(createAction, INITIAL_STATE);
  const describedBy = state.error ? "create-automation-rule-error" : undefined;

  return (
    <div className="flex flex-col gap-4">
      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        {rules.length === 0 ? (
          <EmptyState title="No automation rules yet" description="Create one below." />
        ) : (
          <div className="overflow-x-auto">
          <table className="w-full min-w-[480px] text-sm">
            <thead>
              <tr className="text-left text-xs text-neutral-500">
                <th className="pb-1">Name</th>
                <th className="pb-1">Status</th>
                <th className="pb-1">Published</th>
                <th className="pb-1">Last fired</th>
              </tr>
            </thead>
            <tbody>
              {rules.map((r) => (
                <tr key={r.id} className="border-t border-neutral-100">
                  <td className="py-1">
                    <Link href={`/${tenantSlug}/automation-rules/${r.id}`} className="text-primary underline">
                      {r.name}
                    </Link>
                  </td>
                  <td className="py-1">
                    <StatusBadge tone={STATUS_TONE[r.status]} label={r.status} />
                  </td>
                  <td className="py-1">{r.currentVersionId ? "Yes" : "Not yet published"}</td>
                  <td className="py-1">{r.lastFiredAt ?? "Never"}</td>
                </tr>
              ))}
            </tbody>
          </table>
          </div>
        )}
      </section>

      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Create a new automation rule</h2>
        <form action={formAction} className="grid grid-cols-1 gap-3 sm:grid-cols-2">
          <FormField id="name" label="Name">
            <Input id="name" name="name" type="text" required invalid={Boolean(state.error)} aria-describedby={describedBy} />
          </FormField>
          <div className="sm:col-span-2">
            <FormField id="description" label="Description (optional)">
              <Textarea id="description" name="description" rows={2} invalid={Boolean(state.error)} aria-describedby={describedBy} />
            </FormField>
          </div>

          {state.error ? (
            <div className="col-span-full">
              <ValidationMessage id="create-automation-rule-error">{state.error}</ValidationMessage>
            </div>
          ) : null}

          <div className="col-span-full">
            <Button type="submit" loading={pending} loadingLabel="Creating…">
              Create rule
            </Button>
          </div>
        </form>
      </section>
    </div>
  );
}
