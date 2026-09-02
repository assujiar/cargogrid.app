"use client";

import { useActionState } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
import { Input } from "../../../../../components/forms/input.tsx";
import { NumberInput } from "../../../../../components/forms/number-input.tsx";
import { Select } from "../../../../../components/forms/select.tsx";
import { FormField } from "../../../../../components/forms/form-field.tsx";
import { ValidationMessage } from "../../../../../components/forms/validation-message.tsx";
import { StatusBadge, type StatusTone } from "../../../../../components/ui/status-badge.tsx";
import type { TicketActionState, TicketRoutingPreviewActionState } from "../actions.ts";
import { TICKET_PRIORITIES, TICKET_ROUTING_ASSIGNMENT_MODES } from "../../../../../server/contracts/ticketing/ticketing.ts";
import type { TicketRoutingRuleRow, TicketRoutingRuleVersionRow, TicketCategoryRow, TicketQueueRow } from "../../../../../server/contracts/ticketing/ticketing.ts";

const INITIAL_STATE: TicketActionState = { error: null };
const PREVIEW_INITIAL_STATE: TicketRoutingPreviewActionState = { error: null, result: null };

const VERSION_TONE: Record<string, StatusTone> = { draft: "neutral", published: "success", superseded: "neutral", archived: "neutral" };

type BoundAction = (prevState: TicketActionState, formData: FormData) => Promise<TicketActionState>;
type PreviewBoundAction = (prevState: TicketRoutingPreviewActionState, formData: FormData) => Promise<TicketRoutingPreviewActionState>;

// section 14 ("routing preview"): verify which published rule version (if
// any) matches a given scope before it ever affects a real ticket -- a real
// UI caller for app.preview_ticket_routing, never a built-but-unreachable
// capability (taxonomy C-20).
function PreviewRoutingForm({ categories, previewAction }: { categories: readonly TicketCategoryRow[]; previewAction: PreviewBoundAction }) {
  const [state, formAction, pending] = useActionState(previewAction, PREVIEW_INITIAL_STATE);
  const describedBy = state.error ? "routing-preview-error" : undefined;
  return (
    <form action={formAction} className="flex flex-wrap items-end gap-2 rounded-md border border-neutral-200 p-3">
      <FormField id="routing-preview-channel" label="Channel">
        <Select id="routing-preview-channel" name="channel" required defaultValue="internal" invalid={Boolean(state.error)} aria-describedby={describedBy}>
          <option value="internal">internal</option>
          <option value="customer">customer</option>
        </Select>
      </FormField>
      <FormField id="routing-preview-category" label="Category (optional = any)">
        <Select id="routing-preview-category" name="categoryId" defaultValue="" invalid={Boolean(state.error)} aria-describedby={describedBy}>
          <option value="">Any category</option>
          {categories.map((c) => (
            <option key={c.id} value={c.id}>
              {c.name}
            </option>
          ))}
        </Select>
      </FormField>
      <FormField id="routing-preview-priority" label="Priority (optional = any)">
        <Select id="routing-preview-priority" name="priority" defaultValue="" invalid={Boolean(state.error)} aria-describedby={describedBy}>
          <option value="">Any priority</option>
          {TICKET_PRIORITIES.map((p) => (
            <option key={p} value={p}>
              {p}
            </option>
          ))}
        </Select>
      </FormField>
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Checking…">
        Preview routing
      </Button>
      {state.error ? (
        <div className="w-full">
          <ValidationMessage id="routing-preview-error">{state.error}</ValidationMessage>
        </div>
      ) : null}
      {state.result ? (
        <p className="w-full text-xs text-neutral-700">
          {state.result.matched ? (
            <>
              Matches rule version <span className="font-mono">{state.result.ruleVersionId}</span> (v{state.result.versionNumber}) → queue <strong>{state.result.targetQueueCode}</strong>, mode{" "}
              {state.result.assignmentMode?.replace(/_/g, " ")}
              {state.result.maxActiveAssignmentsPerMember ? `, cap ${state.result.maxActiveAssignmentsPerMember}/member` : ", no cap"}.
            </>
          ) : (
            "No published rule matches this scope -- a ticket here stays on its category's own default queue, manually assigned."
          )}
        </p>
      ) : null}
    </form>
  );
}

/**
 * Routing rule administration (HRT-290, CG-S12-HRT-018). Mirrors
 * app/(tenant)/[tenantSlug]/tickets/sla/sla-admin-panel.tsx's own shape
 * exactly (same "always rendered, TKT:Edit-enforced at the RPC layer"
 * discipline that page's own header documents) -- channel is restricted to
 * internal/customer at the RPC layer (decision 2 of the migration: helpdesk
 * has no eligibility model to route within, Supreme-Admin-only staffing via
 * the existing, unmodified app.assign_helpdesk_ticket).
 */

function PublishRuleVersionButton({ versionId, expectedVersion, publishRuleVersionAction }: { versionId: string; expectedVersion: number; publishRuleVersionAction: (versionId: string, expectedVersion: number) => BoundAction }) {
  const [state, formAction, pending] = useActionState(publishRuleVersionAction(versionId, expectedVersion), INITIAL_STATE);
  return (
    <form action={formAction} className="inline">
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Publishing…">
        Publish
      </Button>
      {state.error ? (
        <p role="alert" className="text-xs text-danger">
          {state.error}
        </p>
      ) : null}
    </form>
  );
}

function CreateRuleForm({ createRuleAction }: { createRuleAction: BoundAction }) {
  const [state, formAction, pending] = useActionState(createRuleAction, INITIAL_STATE);
  const describedBy = state.error ? "create-routing-rule-error" : undefined;
  return (
    <form action={formAction} className="flex flex-wrap items-end gap-2 rounded-md border border-neutral-200 p-3">
      <FormField id="routing-rule-code" label="Code">
        <Input id="routing-rule-code" name="code" required placeholder="GEN-ROUTE" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <FormField id="routing-rule-name" label="Name">
        <Input id="routing-rule-name" name="name" required placeholder="General routing" className="min-w-[12rem]" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Creating…">
        New rule
      </Button>
      {state.error ? (
        <div className="w-full">
          <ValidationMessage id="create-routing-rule-error">{state.error}</ValidationMessage>
        </div>
      ) : null}
    </form>
  );
}

function RuleCard({
  rule,
  versions,
  categories,
  queues,
  createRuleVersionAction,
  publishRuleVersionAction,
}: {
  rule: TicketRoutingRuleRow;
  versions: readonly TicketRoutingRuleVersionRow[];
  categories: readonly TicketCategoryRow[];
  queues: readonly TicketQueueRow[];
  createRuleVersionAction: (ruleId: string) => BoundAction;
  publishRuleVersionAction: (versionId: string, expectedVersion: number) => BoundAction;
}) {
  const [state, formAction, pending] = useActionState(createRuleVersionAction(rule.id), INITIAL_STATE);
  // One card per rule, all on the same page -- every id in this form is rule-scoped.
  const errorId = `routing-rule-version-${rule.id}-error`;
  const describedBy = state.error ? errorId : undefined;
  return (
    <div className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
      <div className="flex items-center gap-2">
        <h3 className="text-sm font-semibold text-neutral-900">{rule.name}</h3>
        <span className="font-mono text-xs text-neutral-500">{rule.code}</span>
      </div>

      <ul className="flex flex-col gap-1 text-xs">
        {versions.length === 0 ? <li className="text-neutral-500">No versions yet.</li> : null}
        {versions.map((v) => (
          <li key={v.id} className="flex flex-wrap items-center gap-2">
            <StatusBadge tone={VERSION_TONE[v.status] ?? "neutral"} label={v.status} />
            <span>
              v{v.versionNumber} — {v.channel}
              {v.priority ? `/${v.priority}` : ""} — {v.assignmentMode.replace(/_/g, " ")}
              {v.maxActiveAssignmentsPerMember ? `, cap ${v.maxActiveAssignmentsPerMember}/member` : ", no cap"} (rank {v.precedenceRank})
            </span>
            {v.status === "draft" ? <PublishRuleVersionButton versionId={v.id} expectedVersion={v.recordVersion} publishRuleVersionAction={publishRuleVersionAction} /> : null}
          </li>
        ))}
      </ul>

      <form action={formAction} className="flex flex-wrap items-end gap-2 rounded bg-neutral-50 p-2">
        <FormField id={`routing-version-channel-${rule.id}`} label="Channel">
          <Select id={`routing-version-channel-${rule.id}`} name="channel" required defaultValue="internal" invalid={Boolean(state.error)} aria-describedby={describedBy}>
            <option value="internal">internal</option>
            <option value="customer">customer</option>
          </Select>
        </FormField>
        <FormField id={`routing-version-category-${rule.id}`} label="Category (optional = any)">
          <Select id={`routing-version-category-${rule.id}`} name="categoryId" defaultValue="" invalid={Boolean(state.error)} aria-describedby={describedBy}>
            <option value="">Any category</option>
            {categories.map((c) => (
              <option key={c.id} value={c.id}>
                {c.name}
              </option>
            ))}
          </Select>
        </FormField>
        <FormField id={`routing-version-priority-${rule.id}`} label="Priority (optional = any)">
          <Select id={`routing-version-priority-${rule.id}`} name="priority" defaultValue="" invalid={Boolean(state.error)} aria-describedby={describedBy}>
            <option value="">Any priority</option>
            {TICKET_PRIORITIES.map((p) => (
              <option key={p} value={p}>
                {p}
              </option>
            ))}
          </Select>
        </FormField>
        <FormField id={`routing-version-target-queue-${rule.id}`} label="Target queue">
          <Select id={`routing-version-target-queue-${rule.id}`} name="targetQueueId" required defaultValue="" invalid={Boolean(state.error)} aria-describedby={describedBy}>
            <option value="" disabled>
              Select…
            </option>
            {queues.map((q) => (
              <option key={q.id} value={q.id}>
                {q.name}
              </option>
            ))}
          </Select>
        </FormField>
        <FormField id={`routing-version-assignment-mode-${rule.id}`} label="Assignment mode">
          <Select id={`routing-version-assignment-mode-${rule.id}`} name="assignmentMode" defaultValue="manual" invalid={Boolean(state.error)} aria-describedby={describedBy}>
            {TICKET_ROUTING_ASSIGNMENT_MODES.map((m) => (
              <option key={m} value={m}>
                {m.replace(/_/g, " ")}
              </option>
            ))}
          </Select>
        </FormField>
        <FormField id={`routing-version-workload-cap-${rule.id}`} label="Workload cap (optional)">
          <NumberInput
            id={`routing-version-workload-cap-${rule.id}`}
            name="maxActiveAssignmentsPerMember"
            min={1}
            placeholder="No cap"
            className="w-24"
            invalid={Boolean(state.error)}
            aria-describedby={describedBy}
          />
        </FormField>
        <FormField id={`routing-version-precedence-${rule.id}`} label="Precedence rank">
          <NumberInput
            id={`routing-version-precedence-${rule.id}`}
            name="precedenceRank"
            defaultValue={0}
            className="w-20"
            invalid={Boolean(state.error)}
            aria-describedby={describedBy}
          />
        </FormField>
        <Button type="submit" variant="secondary" loading={pending} loadingLabel="Creating…">
          New draft version
        </Button>
        {state.error ? (
          <div className="w-full">
            <ValidationMessage id={errorId}>{state.error}</ValidationMessage>
          </div>
        ) : null}
      </form>
    </div>
  );
}

export function RoutingAdminPanel({
  rules,
  ruleVersionsByRule,
  categories,
  queues,
  createRuleAction,
  createRuleVersionAction,
  publishRuleVersionAction,
  previewAction,
}: {
  rules: readonly TicketRoutingRuleRow[];
  ruleVersionsByRule: Record<string, readonly TicketRoutingRuleVersionRow[]>;
  categories: readonly TicketCategoryRow[];
  queues: readonly TicketQueueRow[];
  createRuleAction: BoundAction;
  createRuleVersionAction: (ruleId: string) => BoundAction;
  publishRuleVersionAction: (versionId: string, expectedVersion: number) => BoundAction;
  previewAction: PreviewBoundAction;
}) {
  return (
    <div className="flex flex-col gap-6">
      <section className="flex flex-col gap-3">
        <h2 className="text-sm font-semibold text-neutral-900">Preview a scope</h2>
        <PreviewRoutingForm categories={categories} previewAction={previewAction} />
      </section>

      <section className="flex flex-col gap-3">
        <h2 className="text-sm font-semibold text-neutral-900">Routing rules</h2>
        <CreateRuleForm createRuleAction={createRuleAction} />
        <div className="flex flex-col gap-3">
          {rules.map((r) => (
            <RuleCard
              key={r.id}
              rule={r}
              versions={ruleVersionsByRule[r.id] ?? []}
              categories={categories}
              queues={queues}
              createRuleVersionAction={createRuleVersionAction}
              publishRuleVersionAction={publishRuleVersionAction}
            />
          ))}
        </div>
      </section>
    </div>
  );
}
