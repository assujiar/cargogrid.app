"use client";

import { useActionState } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
import { Input } from "../../../../../components/forms/input.tsx";
import { NumberInput } from "../../../../../components/forms/number-input.tsx";
import { Select } from "../../../../../components/forms/select.tsx";
import { Checkbox } from "../../../../../components/forms/checkbox.tsx";
import { FormField } from "../../../../../components/forms/form-field.tsx";
import { ValidationMessage } from "../../../../../components/forms/validation-message.tsx";
import { StatusBadge, type StatusTone } from "../../../../../components/ui/status-badge.tsx";
import type { TicketActionState, TicketEscalationPreviewActionState } from "../actions.ts";
import { TICKET_PRIORITIES, TICKET_ESCALATION_TRIGGER_TYPES } from "../../../../../server/contracts/ticketing/ticketing.ts";
import type {
  TicketEscalationPolicyRow,
  TicketEscalationPolicyVersionRow,
  TicketEscalationLevelRow,
  TicketCategoryRow,
  TicketQueueRow,
} from "../../../../../server/contracts/ticketing/ticketing.ts";

const INITIAL_STATE: TicketActionState = { error: null };
const PREVIEW_INITIAL_STATE: TicketEscalationPreviewActionState = { error: null, result: null };

const VERSION_TONE: Record<string, StatusTone> = { draft: "neutral", published: "success", superseded: "neutral" };

type BoundAction = (prevState: TicketActionState, formData: FormData) => Promise<TicketActionState>;
type PreviewBoundAction = (prevState: TicketEscalationPreviewActionState, formData: FormData) => Promise<TicketEscalationPreviewActionState>;

// section 14 ("policy preview"): verify which published policy version (if
// any) matches a given scope before it ever affects a real ticket -- a real
// UI caller for app.preview_ticket_escalation, never a built-but-unreachable
// capability (taxonomy C-20), mirrors the routing admin panel's own
// PreviewRoutingForm exactly.
function PreviewEscalationForm({ categories, queues, previewAction }: { categories: readonly TicketCategoryRow[]; queues: readonly TicketQueueRow[]; previewAction: PreviewBoundAction }) {
  const [state, formAction, pending] = useActionState(previewAction, PREVIEW_INITIAL_STATE);
  const describedBy = state.error ? "escalation-preview-error" : undefined;
  return (
    <form action={formAction} className="flex flex-wrap items-end gap-2 rounded-md border border-neutral-200 p-3">
      <FormField id="escalation-preview-channel" label="Channel">
        <Select id="escalation-preview-channel" name="channel" required defaultValue="internal" invalid={Boolean(state.error)} aria-describedby={describedBy}>
          <option value="internal">internal</option>
          <option value="customer">customer</option>
        </Select>
      </FormField>
      <FormField id="escalation-preview-category" label="Category (optional = any)">
        <Select id="escalation-preview-category" name="categoryId" defaultValue="" invalid={Boolean(state.error)} aria-describedby={describedBy}>
          <option value="">Any category</option>
          {categories.map((c) => (
            <option key={c.id} value={c.id}>
              {c.name}
            </option>
          ))}
        </Select>
      </FormField>
      <FormField id="escalation-preview-priority" label="Priority (optional = any)">
        <Select id="escalation-preview-priority" name="priority" defaultValue="" invalid={Boolean(state.error)} aria-describedby={describedBy}>
          <option value="">Any priority</option>
          {TICKET_PRIORITIES.map((p) => (
            <option key={p} value={p}>
              {p}
            </option>
          ))}
        </Select>
      </FormField>
      <FormField id="escalation-preview-queue" label="Queue (optional = any)">
        <Select id="escalation-preview-queue" name="queueId" defaultValue="" invalid={Boolean(state.error)} aria-describedby={describedBy}>
          <option value="">Any queue</option>
          {queues.map((q) => (
            <option key={q.id} value={q.id}>
              {q.name}
            </option>
          ))}
        </Select>
      </FormField>
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Checking…">
        Preview escalation
      </Button>
      {state.error ? (
        <div className="w-full">
          <ValidationMessage id="escalation-preview-error">{state.error}</ValidationMessage>
        </div>
      ) : null}
      {state.result ? (
        <p className="w-full text-xs text-neutral-700">
          {state.result.matched ? (
            <>
              Matches policy version <span className="font-mono">{state.result.policyVersionId}</span> (v{state.result.versionNumber}) with {state.result.levelCount} configured level
              {state.result.levelCount === 1 ? "" : "s"}.
            </>
          ) : (
            "No published policy matches this scope -- a ticket here never auto-escalates until one is configured, but manual escalation always remains available."
          )}
        </p>
      ) : null}
    </form>
  );
}

function PublishVersionButton({ versionId, expectedVersion, publishPolicyVersionAction }: { versionId: string; expectedVersion: number; publishPolicyVersionAction: (versionId: string, expectedVersion: number) => BoundAction }) {
  const [state, formAction, pending] = useActionState(publishPolicyVersionAction(versionId, expectedVersion), INITIAL_STATE);
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

function CreatePolicyForm({ createPolicyAction }: { createPolicyAction: BoundAction }) {
  const [state, formAction, pending] = useActionState(createPolicyAction, INITIAL_STATE);
  const describedBy = state.error ? "create-escalation-policy-error" : undefined;
  return (
    <form action={formAction} className="flex flex-wrap items-end gap-2 rounded-md border border-neutral-200 p-3">
      <FormField id="escalation-policy-code" label="Code">
        <Input id="escalation-policy-code" name="code" required placeholder="GEN-ESC" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <FormField id="escalation-policy-name" label="Name">
        <Input id="escalation-policy-name" name="name" required placeholder="General escalation" className="min-w-[12rem]" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Creating…">
        New policy
      </Button>
      {state.error ? (
        <div className="w-full">
          <ValidationMessage id="create-escalation-policy-error">{state.error}</ValidationMessage>
        </div>
      ) : null}
    </form>
  );
}

function AddLevelForm({
  versionId,
  queues,
  addLevelAction,
}: {
  versionId: string;
  queues: readonly TicketQueueRow[];
  addLevelAction: (versionId: string) => BoundAction;
}) {
  const [state, formAction, pending] = useActionState(addLevelAction(versionId), INITIAL_STATE);
  // One of these per draft version, several per page -- every id is version-scoped.
  const errorId = `escalation-level-${versionId}-error`;
  const describedBy = state.error ? errorId : undefined;
  return (
    <form action={formAction} className="flex flex-wrap items-end gap-2 rounded bg-neutral-50 p-2">
      <FormField id={`escalation-level-number-${versionId}`} label="Level #">
        <NumberInput
          id={`escalation-level-number-${versionId}`}
          name="levelNumber"
          min={1}
          required
          defaultValue={1}
          className="w-16"
          invalid={Boolean(state.error)}
          aria-describedby={describedBy}
        />
      </FormField>
      <FormField id={`escalation-level-trigger-${versionId}`} label="Trigger">
        <Select id={`escalation-level-trigger-${versionId}`} name="triggerType" required defaultValue="inactivity" invalid={Boolean(state.error)} aria-describedby={describedBy}>
          {TICKET_ESCALATION_TRIGGER_TYPES.map((t) => (
            <option key={t} value={t}>
              {t.replace(/_/g, " ")}
            </option>
          ))}
        </Select>
      </FormField>
      <FormField id={`escalation-level-threshold-${versionId}`} label="Threshold minutes (inactivity/assignment_failure only)">
        <NumberInput
          id={`escalation-level-threshold-${versionId}`}
          name="thresholdMinutes"
          min={1}
          placeholder="e.g. 30"
          className="w-24"
          invalid={Boolean(state.error)}
          aria-describedby={describedBy}
        />
      </FormField>
      <FormField id={`escalation-level-min-priority-${versionId}`} label="Min priority (required for priority_threshold; optional extra gate otherwise)">
        <Select id={`escalation-level-min-priority-${versionId}`} name="minPriority" defaultValue="" invalid={Boolean(state.error)} aria-describedby={describedBy}>
          <option value="">No extra gate</option>
          {TICKET_PRIORITIES.map((p) => (
            <option key={p} value={p}>
              {p}
            </option>
          ))}
        </Select>
      </FormField>
      <FormField id={`escalation-level-target-type-${versionId}`} label="Target type">
        <Select id={`escalation-level-target-type-${versionId}`} name="targetType" required defaultValue="queue" invalid={Boolean(state.error)} aria-describedby={describedBy}>
          <option value="queue">Queue</option>
          <option value="employee">Employee</option>
        </Select>
      </FormField>
      <FormField id={`escalation-level-target-queue-${versionId}`} label="Target queue (if target type = queue)">
        <Select id={`escalation-level-target-queue-${versionId}`} name="targetQueueId" defaultValue="" invalid={Boolean(state.error)} aria-describedby={describedBy}>
          <option value="">Select…</option>
          {queues.map((q) => (
            <option key={q.id} value={q.id}>
              {q.name}
            </option>
          ))}
        </Select>
      </FormField>
      <FormField id={`escalation-level-target-employee-${versionId}`} label="Target employee id (if target type = employee)">
        <Input
          id={`escalation-level-target-employee-${versionId}`}
          name="targetEmployeeId"
          placeholder="employee UUID"
          className="min-w-[14rem]"
          invalid={Boolean(state.error)}
          aria-describedby={describedBy}
        />
      </FormField>
      <Checkbox id={`escalation-level-notify-${versionId}`} name="actionNotify" defaultChecked label="Notify" aria-describedby={describedBy} />
      <Checkbox id={`escalation-level-reassign-${versionId}`} name="actionReassign" label="Reassign (employee target only)" aria-describedby={describedBy} />
      <FormField id={`escalation-level-cooldown-${versionId}`} label="Cooldown minutes">
        <NumberInput
          id={`escalation-level-cooldown-${versionId}`}
          name="cooldownMinutes"
          min={1}
          defaultValue={60}
          className="w-20"
          invalid={Boolean(state.error)}
          aria-describedby={describedBy}
        />
      </FormField>
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Saving…">
        Save level
      </Button>
      {state.error ? (
        <div className="w-full">
          <ValidationMessage id={errorId}>{state.error}</ValidationMessage>
        </div>
      ) : null}
    </form>
  );
}

function LevelRow({ level }: { level: TicketEscalationLevelRow }) {
  return (
    <li className="flex flex-wrap items-center gap-2 text-xs">
      <StatusBadge tone="info" label={`Level ${level.levelNumber}`} />
      <span>{level.triggerType.replace(/_/g, " ")}</span>
      {level.thresholdMinutes ? <span>≥ {level.thresholdMinutes}m</span> : null}
      {level.minPriority ? <span>priority ≥ {level.minPriority}</span> : null}
      <span>
        → {level.targetType === "queue" ? `queue ${level.targetQueueCode ?? level.targetQueueId}` : `employee ${level.targetEmployeeName ?? level.targetEmployeeId}`}
      </span>
      {level.actionNotify ? <StatusBadge tone="success" label="Notify" /> : null}
      {level.actionReassign ? <StatusBadge tone="warning" label="Reassign" /> : null}
      <span className="text-neutral-500">cooldown {level.cooldownMinutes}m</span>
    </li>
  );
}

function CreatePolicyVersionForm({
  policyId,
  categories,
  queues,
  createPolicyVersionAction,
}: {
  policyId: string;
  categories: readonly TicketCategoryRow[];
  queues: readonly TicketQueueRow[];
  createPolicyVersionAction: (policyId: string) => BoundAction;
}) {
  const [state, formAction, pending] = useActionState(createPolicyVersionAction(policyId), INITIAL_STATE);
  // One of these per policy card -- every id is policy-scoped.
  const errorId = `escalation-policy-version-${policyId}-error`;
  const describedBy = state.error ? errorId : undefined;
  return (
    <form action={formAction} className="flex flex-wrap items-end gap-2 rounded bg-neutral-50 p-2">
      <FormField id={`escalation-version-channel-${policyId}`} label="Channel">
        <Select id={`escalation-version-channel-${policyId}`} name="channel" required defaultValue="internal" invalid={Boolean(state.error)} aria-describedby={describedBy}>
          <option value="internal">internal</option>
          <option value="customer">customer</option>
        </Select>
      </FormField>
      <FormField id={`escalation-version-category-${policyId}`} label="Category (optional = any)">
        <Select id={`escalation-version-category-${policyId}`} name="categoryId" defaultValue="" invalid={Boolean(state.error)} aria-describedby={describedBy}>
          <option value="">Any category</option>
          {categories.map((c) => (
            <option key={c.id} value={c.id}>
              {c.name}
            </option>
          ))}
        </Select>
      </FormField>
      <FormField id={`escalation-version-priority-${policyId}`} label="Priority (optional = any)">
        <Select id={`escalation-version-priority-${policyId}`} name="priority" defaultValue="" invalid={Boolean(state.error)} aria-describedby={describedBy}>
          <option value="">Any priority</option>
          {TICKET_PRIORITIES.map((p) => (
            <option key={p} value={p}>
              {p}
            </option>
          ))}
        </Select>
      </FormField>
      <FormField id={`escalation-version-queue-${policyId}`} label="Queue (optional = any)">
        <Select id={`escalation-version-queue-${policyId}`} name="queueId" defaultValue="" invalid={Boolean(state.error)} aria-describedby={describedBy}>
          <option value="">Any queue</option>
          {queues.map((q) => (
            <option key={q.id} value={q.id}>
              {q.name}
            </option>
          ))}
        </Select>
      </FormField>
      <FormField id={`escalation-version-precedence-${policyId}`} label="Precedence rank">
        <NumberInput
          id={`escalation-version-precedence-${policyId}`}
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
  );
}

function PolicyCard({
  policy,
  versions,
  levelsByVersion,
  categories,
  queues,
  createPolicyVersionAction,
  addLevelAction,
  publishPolicyVersionAction,
}: {
  policy: TicketEscalationPolicyRow;
  versions: readonly TicketEscalationPolicyVersionRow[];
  levelsByVersion: Record<string, readonly TicketEscalationLevelRow[]>;
  categories: readonly TicketCategoryRow[];
  queues: readonly TicketQueueRow[];
  createPolicyVersionAction: (policyId: string) => BoundAction;
  addLevelAction: (versionId: string) => BoundAction;
  publishPolicyVersionAction: (versionId: string, expectedVersion: number) => BoundAction;
}) {
  return (
    <div className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
      <div className="flex items-center gap-2">
        <h3 className="text-sm font-semibold text-neutral-900">{policy.name}</h3>
        <span className="font-mono text-xs text-neutral-500">{policy.code}</span>
      </div>

      <div className="flex flex-col gap-3">
        {versions.length === 0 ? <p className="text-xs text-neutral-500">No versions yet.</p> : null}
        {versions.map((v) => {
          const levels = levelsByVersion[v.id] ?? [];
          return (
            <div key={v.id} className="flex flex-col gap-1 rounded border border-neutral-100 p-2">
              <div className="flex flex-wrap items-center gap-2">
                <StatusBadge tone={VERSION_TONE[v.status] ?? "neutral"} label={v.status} />
                <span className="text-xs">
                  v{v.versionNumber} — {v.channel}
                  {v.categoryId ? " · category-scoped" : ""}
                  {v.priority ? `/${v.priority}` : ""}
                  {v.queueId ? " · queue-scoped" : ""} (rank {v.precedenceRank})
                </span>
                {v.status === "draft" ? <PublishVersionButton versionId={v.id} expectedVersion={v.recordVersion} publishPolicyVersionAction={publishPolicyVersionAction} /> : null}
              </div>
              {levels.length > 0 ? (
                <ul className="flex flex-col gap-1">
                  {levels.map((l) => (
                    <LevelRow key={l.id} level={l} />
                  ))}
                </ul>
              ) : (
                <p className="text-xs text-neutral-500">No levels configured yet -- publish is blocked until at least one exists.</p>
              )}
              {v.status === "draft" ? <AddLevelForm versionId={v.id} queues={queues} addLevelAction={addLevelAction} /> : null}
            </div>
          );
        })}
      </div>

      <CreatePolicyVersionForm policyId={policy.id} categories={categories} queues={queues} createPolicyVersionAction={createPolicyVersionAction} />
    </div>
  );
}

export function EscalationAdminPanel({
  policies,
  versionsByPolicy,
  levelsByVersion,
  categories,
  queues,
  createPolicyAction,
  createPolicyVersionAction,
  addLevelAction,
  publishPolicyVersionAction,
  previewAction,
}: {
  policies: readonly TicketEscalationPolicyRow[];
  versionsByPolicy: Record<string, readonly TicketEscalationPolicyVersionRow[]>;
  levelsByVersion: Record<string, readonly TicketEscalationLevelRow[]>;
  categories: readonly TicketCategoryRow[];
  queues: readonly TicketQueueRow[];
  createPolicyAction: BoundAction;
  createPolicyVersionAction: (policyId: string) => BoundAction;
  addLevelAction: (versionId: string) => BoundAction;
  publishPolicyVersionAction: (versionId: string, expectedVersion: number) => BoundAction;
  previewAction: PreviewBoundAction;
}) {
  return (
    <div className="flex flex-col gap-6">
      <section className="flex flex-col gap-3">
        <h2 className="text-sm font-semibold text-neutral-900">Preview a scope</h2>
        <PreviewEscalationForm categories={categories} queues={queues} previewAction={previewAction} />
      </section>

      <section className="flex flex-col gap-3">
        <h2 className="text-sm font-semibold text-neutral-900">Escalation policies</h2>
        <CreatePolicyForm createPolicyAction={createPolicyAction} />
        <div className="flex flex-col gap-3">
          {policies.map((p) => (
            <PolicyCard
              key={p.id}
              policy={p}
              versions={versionsByPolicy[p.id] ?? []}
              levelsByVersion={levelsByVersion}
              categories={categories}
              queues={queues}
              createPolicyVersionAction={createPolicyVersionAction}
              addLevelAction={addLevelAction}
              publishPolicyVersionAction={publishPolicyVersionAction}
            />
          ))}
        </div>
      </section>
    </div>
  );
}
