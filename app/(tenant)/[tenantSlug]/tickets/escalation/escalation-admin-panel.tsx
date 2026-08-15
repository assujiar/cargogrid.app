"use client";

import { useActionState } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
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
  return (
    <form action={formAction} className="flex flex-wrap items-end gap-2 rounded-md border border-neutral-200 p-3">
      <label className="flex flex-col gap-1 text-xs text-neutral-600">
        Channel
        <select name="channel" required defaultValue="internal" className="rounded border border-neutral-300 p-1.5 text-sm">
          <option value="internal">internal</option>
          <option value="customer">customer</option>
        </select>
      </label>
      <label className="flex flex-col gap-1 text-xs text-neutral-600">
        Category (optional = any)
        <select name="categoryId" defaultValue="" className="rounded border border-neutral-300 p-1.5 text-sm">
          <option value="">Any category</option>
          {categories.map((c) => (
            <option key={c.id} value={c.id}>
              {c.name}
            </option>
          ))}
        </select>
      </label>
      <label className="flex flex-col gap-1 text-xs text-neutral-600">
        Priority (optional = any)
        <select name="priority" defaultValue="" className="rounded border border-neutral-300 p-1.5 text-sm">
          <option value="">Any priority</option>
          {TICKET_PRIORITIES.map((p) => (
            <option key={p} value={p}>
              {p}
            </option>
          ))}
        </select>
      </label>
      <label className="flex flex-col gap-1 text-xs text-neutral-600">
        Queue (optional = any)
        <select name="queueId" defaultValue="" className="rounded border border-neutral-300 p-1.5 text-sm">
          <option value="">Any queue</option>
          {queues.map((q) => (
            <option key={q.id} value={q.id}>
              {q.name}
            </option>
          ))}
        </select>
      </label>
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Checking…">
        Preview escalation
      </Button>
      {state.error ? (
        <p role="alert" className="w-full text-xs text-danger">
          {state.error}
        </p>
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
  return (
    <form action={formAction} className="flex flex-wrap items-end gap-2 rounded-md border border-neutral-200 p-3">
      <label className="flex flex-col gap-1 text-xs text-neutral-600">
        Code
        <input name="code" required placeholder="GEN-ESC" className="rounded border border-neutral-300 p-1.5 text-sm" />
      </label>
      <label className="flex flex-col gap-1 text-xs text-neutral-600">
        Name
        <input name="name" required placeholder="General escalation" className="min-w-[12rem] rounded border border-neutral-300 p-1.5 text-sm" />
      </label>
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Creating…">
        New policy
      </Button>
      {state.error ? (
        <p role="alert" className="w-full text-xs text-danger">
          {state.error}
        </p>
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
  return (
    <form action={formAction} className="flex flex-wrap items-end gap-2 rounded bg-neutral-50 p-2">
      <label className="flex flex-col gap-1 text-xs text-neutral-600">
        Level #
        <input name="levelNumber" type="number" min={1} required defaultValue={1} className="w-16 rounded border border-neutral-300 p-1.5 text-sm" />
      </label>
      <label className="flex flex-col gap-1 text-xs text-neutral-600">
        Trigger
        <select name="triggerType" required defaultValue="inactivity" className="rounded border border-neutral-300 p-1.5 text-sm">
          {TICKET_ESCALATION_TRIGGER_TYPES.map((t) => (
            <option key={t} value={t}>
              {t.replace(/_/g, " ")}
            </option>
          ))}
        </select>
      </label>
      <label className="flex flex-col gap-1 text-xs text-neutral-600">
        Threshold minutes (inactivity/assignment_failure only)
        <input name="thresholdMinutes" type="number" min={1} placeholder="e.g. 30" className="w-24 rounded border border-neutral-300 p-1.5 text-sm" />
      </label>
      <label className="flex flex-col gap-1 text-xs text-neutral-600">
        Min priority (required for priority_threshold; optional extra gate otherwise)
        <select name="minPriority" defaultValue="" className="rounded border border-neutral-300 p-1.5 text-sm">
          <option value="">No extra gate</option>
          {TICKET_PRIORITIES.map((p) => (
            <option key={p} value={p}>
              {p}
            </option>
          ))}
        </select>
      </label>
      <label className="flex flex-col gap-1 text-xs text-neutral-600">
        Target type
        <select name="targetType" required defaultValue="queue" className="rounded border border-neutral-300 p-1.5 text-sm">
          <option value="queue">Queue</option>
          <option value="employee">Employee</option>
        </select>
      </label>
      <label className="flex flex-col gap-1 text-xs text-neutral-600">
        Target queue (if target type = queue)
        <select name="targetQueueId" defaultValue="" className="rounded border border-neutral-300 p-1.5 text-sm">
          <option value="">Select…</option>
          {queues.map((q) => (
            <option key={q.id} value={q.id}>
              {q.name}
            </option>
          ))}
        </select>
      </label>
      <label className="flex flex-col gap-1 text-xs text-neutral-600">
        Target employee id (if target type = employee)
        <input name="targetEmployeeId" placeholder="employee UUID" className="min-w-[14rem] rounded border border-neutral-300 p-1.5 text-sm" />
      </label>
      <label className="flex items-center gap-2 text-xs text-neutral-600">
        <input type="checkbox" name="actionNotify" defaultChecked />
        Notify
      </label>
      <label className="flex items-center gap-2 text-xs text-neutral-600">
        <input type="checkbox" name="actionReassign" />
        Reassign (employee target only)
      </label>
      <label className="flex flex-col gap-1 text-xs text-neutral-600">
        Cooldown minutes
        <input name="cooldownMinutes" type="number" min={1} defaultValue={60} className="w-20 rounded border border-neutral-300 p-1.5 text-sm" />
      </label>
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Saving…">
        Save level
      </Button>
      {state.error ? (
        <p role="alert" className="w-full text-xs text-danger">
          {state.error}
        </p>
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
  return (
    <form action={formAction} className="flex flex-wrap items-end gap-2 rounded bg-neutral-50 p-2">
      <label className="flex flex-col gap-1 text-xs text-neutral-600">
        Channel
        <select name="channel" required defaultValue="internal" className="rounded border border-neutral-300 p-1.5 text-sm">
          <option value="internal">internal</option>
          <option value="customer">customer</option>
        </select>
      </label>
      <label className="flex flex-col gap-1 text-xs text-neutral-600">
        Category (optional = any)
        <select name="categoryId" defaultValue="" className="rounded border border-neutral-300 p-1.5 text-sm">
          <option value="">Any category</option>
          {categories.map((c) => (
            <option key={c.id} value={c.id}>
              {c.name}
            </option>
          ))}
        </select>
      </label>
      <label className="flex flex-col gap-1 text-xs text-neutral-600">
        Priority (optional = any)
        <select name="priority" defaultValue="" className="rounded border border-neutral-300 p-1.5 text-sm">
          <option value="">Any priority</option>
          {TICKET_PRIORITIES.map((p) => (
            <option key={p} value={p}>
              {p}
            </option>
          ))}
        </select>
      </label>
      <label className="flex flex-col gap-1 text-xs text-neutral-600">
        Queue (optional = any)
        <select name="queueId" defaultValue="" className="rounded border border-neutral-300 p-1.5 text-sm">
          <option value="">Any queue</option>
          {queues.map((q) => (
            <option key={q.id} value={q.id}>
              {q.name}
            </option>
          ))}
        </select>
      </label>
      <label className="flex flex-col gap-1 text-xs text-neutral-600">
        Precedence rank
        <input name="precedenceRank" type="number" defaultValue={0} className="w-20 rounded border border-neutral-300 p-1.5 text-sm" />
      </label>
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Creating…">
        New draft version
      </Button>
      {state.error ? (
        <p role="alert" className="w-full text-xs text-danger">
          {state.error}
        </p>
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
