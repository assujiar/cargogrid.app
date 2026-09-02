"use client";

/**
 * Vendor Performance detail panel (PRC-264, CG-S11-PRC-015). Same
 * useActionState + <form action> convention as vendor-contracts'
 * `[contractId]/vendor-contract-detail-panel.tsx`: one small `ActionForm` wrapper per
 * mutation, one `useActionState` per rendered form (including per-row forms inside a
 * list, each in its own row component so hooks stay valid). Renders, in order: the
 * current scorecard summary, calculate/publish forms, scorecard version history, the
 * per-KPI drilldown (with masked-evidence disclosure and a per-line dispute-raise
 * form), open source disputes with a decide form, issues with status updates and
 * nested corrective actions, manual adjustments with a decide form, and the governed
 * lifecycle recommendation surface (system-recommended, human-decided only -- this
 * panel never auto-executes a suspend/blacklist/reactivate itself).
 */

import { useActionState, useId, useState } from "react";
import type { ReactNode } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import { Input } from "../../../../../../components/forms/input.tsx";
import { Select } from "../../../../../../components/forms/select.tsx";
import { FormField } from "../../../../../../components/forms/form-field.tsx";
import { ValidationMessage } from "../../../../../../components/forms/validation-message.tsx";
import { StatusBadge, type StatusTone } from "../../../../../../components/ui/status-badge.tsx";
import { DataTable, type DataTableColumn } from "../../../../../../components/tables/data-table.tsx";
import { EmptyState } from "../../../../../../components/ui/empty-state.tsx";
import {
  VENDOR_KPI_CODES,
  VENDOR_LIFECYCLE_RECOMMENDATION_ACTIONS,
  isVendorKpiEvidenceMasked,
  isVendorPerformanceCorrectiveActionOverdue,
  type VendorKpiBand,
  type VendorKpiManualAdjustment,
  type VendorKpiScorecard,
  type VendorKpiScorecardDrilldownLine,
  type VendorKpiSourceDispute,
  type VendorLifecycleRecommendation,
  type VendorPerformanceCorrectiveAction,
  type VendorPerformanceIssue,
} from "../../../../../../server/contracts/vendor-performance/vendor-performance.ts";
import type { VendorLifecycleStatus } from "../../../../../../server/contracts/vendor-profile/vendor-profile.ts";
import type { VendorPerformanceActionState } from "./actions.ts";

const INITIAL_STATE: VendorPerformanceActionState = { error: null };

type SimpleFormAction = (prevState: VendorPerformanceActionState, formData: FormData) => Promise<VendorPerformanceActionState>;

const BAND_TONE: Record<VendorKpiBand, StatusTone> = {
  excellent: "success",
  good: "success",
  watch: "warning",
  poor: "danger",
};

const VENDOR_LIFECYCLE_TONE: Record<VendorLifecycleStatus, StatusTone> = {
  draft: "neutral",
  submitted: "info",
  under_review: "info",
  approved: "info",
  active: "success",
  suspended: "danger",
  archived: "neutral",
  blacklisted: "danger",
};

const ISSUE_STATUS_TONE: Record<VendorPerformanceIssue["status"], StatusTone> = {
  open: "danger",
  in_progress: "warning",
  resolved: "success",
  closed: "neutral",
};

const ISSUE_SEVERITY_TONE: Record<VendorPerformanceIssue["severity"], StatusTone> = {
  low: "neutral",
  medium: "info",
  high: "warning",
  critical: "danger",
};

const CORRECTIVE_ACTION_STATUS_TONE: Record<VendorPerformanceCorrectiveAction["status"], StatusTone> = {
  open: "neutral",
  in_progress: "warning",
  completed: "success",
  cancelled: "neutral",
};

const DISPUTE_STATUS_TONE: Record<VendorKpiSourceDispute["status"], StatusTone> = {
  pending: "warning",
  upheld: "success",
  rejected: "neutral",
};

const ADJUSTMENT_STATUS_TONE: Record<VendorKpiManualAdjustment["status"], StatusTone> = {
  pending_approval: "warning",
  approved: "success",
  rejected: "danger",
};

const RECOMMENDATION_STATUS_TONE: Record<VendorLifecycleRecommendation["status"], StatusTone> = {
  pending: "warning",
  decided: "neutral",
};

const RECOMMENDATION_ACTION_TONE: Record<(typeof VENDOR_LIFECYCLE_RECOMMENDATION_ACTIONS)[number], StatusTone> = {
  none: "neutral",
  watch: "info",
  suspend: "warning",
  blacklist: "danger",
  reactivate: "success",
};

function toDatetimeLocal(iso: string): string {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return "";
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

function ActionForm({
  action,
  children,
  submitLabel,
  loadingLabel,
  variant = "primary",
  className,
}: {
  action: SimpleFormAction;
  children?: (describedBy: string | undefined) => ReactNode;
  submitLabel: string;
  loadingLabel?: string;
  variant?: "primary" | "secondary" | "destructive";
  className?: string;
}) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  const reactId = useId();
  const errorId = `${reactId}-error`;
  const describedBy = state.error ? errorId : undefined;
  return (
    <form action={formAction} className={className ?? "flex flex-col gap-2"}>
      {children?.(describedBy)}
      {state.error ? <ValidationMessage id={errorId}>{state.error}</ValidationMessage> : null}
      <Button type="submit" variant={variant} loading={pending} loadingLabel={loadingLabel ?? "Working…"} className="w-fit">
        {submitLabel}
      </Button>
    </form>
  );
}

function SummaryRow({ label, value }: { label: string; value: ReactNode }) {
  return (
    <div className="flex flex-col gap-0.5">
      <dt className="text-xs font-medium text-neutral-500">{label}</dt>
      <dd className="text-sm text-neutral-900">{value}</dd>
    </div>
  );
}

// -- Drilldown row (KPI line + per-line dispute-raise form) ------------------

function DrilldownRow({ line, raiseDisputeAction }: { line: VendorKpiScorecardDrilldownLine; raiseDisputeAction: SimpleFormAction }) {
  const masked = isVendorKpiEvidenceMasked(line);
  const sourceIds = (line.sourceEvidence?.contributing_source_ids as unknown[] | undefined) ?? [];
  const [open, setOpen] = useState(false);
  return (
    <tr className="border-t border-neutral-200 align-top">
      <td className="px-3 py-2">
        <p className="font-medium text-neutral-900">{line.kpiNameSnapshot}</p>
        <p className="text-xs text-neutral-500">
          {line.kpiCode} · weight {line.weightSnapshot} · target {line.targetOperatorSnapshot} {line.targetValueSnapshot}
        </p>
      </td>
      <td className="px-3 py-2 text-neutral-700">{line.isComputable ? (line.computedValue != null ? line.computedValue.toFixed(2) : "—") : "not computable"}</td>
      <td className="px-3 py-2 text-neutral-700">{line.normalizedScore != null ? line.normalizedScore.toFixed(1) : "—"}</td>
      <td className="px-3 py-2">{line.band ? <StatusBadge tone={BAND_TONE[line.band]} label={line.band} /> : "—"}</td>
      <td className="px-3 py-2 text-xs text-neutral-500">
        {line.adjusted ? <StatusBadge tone="info" label="manually adjusted" /> : null}
        {line.sampleSize != null ? <div>n={line.sampleSize}{line.excludedCount ? `, ${line.excludedCount} excluded (disputed)` : ""}</div> : null}
        {line.computationNote ? <div className="mt-0.5 max-w-xs">{line.computationNote}</div> : null}
        {masked ? <div className="mt-0.5 text-neutral-400">Source evidence masked (requires Procurement: View cost).</div> : null}
      </td>
      <td className="px-3 py-2">
        {!masked && line.isComputable ? (
          <>
            <Button type="button" variant="secondary" onClick={() => setOpen((v) => !v)} className="text-xs">
              {open ? "Cancel" : "Dispute source"}
            </Button>
            {open ? (
              <div className="mt-2 w-64">
                <ActionForm action={raiseDisputeAction} submitLabel="Raise dispute" loadingLabel="Raising…" variant="destructive">
                  {(describedBy) => (
                    <>
                      <input type="hidden" name="kpiCode" value={line.kpiCode} />
                      <FormField id={`dispute-source-${line.lineId}`} label="Source event id (required)">
                        <Select id={`dispute-source-${line.lineId}`} name="sourceId" required aria-describedby={describedBy}>
                          <option value="">Select a contributing source…</option>
                          {sourceIds.map((id) => (
                            <option key={String(id)} value={String(id)}>
                              {String(id)}
                            </option>
                          ))}
                        </Select>
                      </FormField>
                      <FormField id={`dispute-source-label-${line.lineId}`} label="Source label">
                        <Input id={`dispute-source-label-${line.lineId}`} name="sourceLabel" placeholder="Optional human label" aria-describedby={describedBy} />
                      </FormField>
                      <FormField id={`dispute-reason-${line.lineId}`} label="Reason (required)">
                        <Input id={`dispute-reason-${line.lineId}`} name="reason" required aria-describedby={describedBy} />
                      </FormField>
                    </>
                  )}
                </ActionForm>
              </div>
            ) : null}
          </>
        ) : null}
      </td>
    </tr>
  );
}

// -- Disputes ------------------------------------------------------------

function DisputeRow({ dispute, decideDisputeAction }: { dispute: VendorKpiSourceDispute; decideDisputeAction: SimpleFormAction }) {
  return (
    <div className="flex flex-col gap-2 rounded-md border border-neutral-200 p-3">
      <div className="flex flex-wrap items-center gap-2">
        <StatusBadge tone={DISPUTE_STATUS_TONE[dispute.status]} label={dispute.status} />
        <span className="text-sm font-medium text-neutral-900">{dispute.kpiCode}</span>
        <span className="text-xs text-neutral-500">source {dispute.sourceLabel ?? dispute.sourceId}</span>
      </div>
      <p className="text-sm text-neutral-700">{dispute.reason}</p>
      <p className="text-xs text-neutral-500">
        Raised by {dispute.raisedBy ?? dispute.raisedByAuthUserId ?? "—"} on {new Date(dispute.raisedAt).toLocaleString()}
      </p>
      {dispute.status !== "pending" ? (
        <p className="text-xs text-neutral-500">
          Decided by {dispute.decidedBy ?? dispute.decidedByAuthUserId ?? "—"} on {dispute.decidedAt ? new Date(dispute.decidedAt).toLocaleString() : "—"}: {dispute.decisionNotes ?? "—"}
        </p>
      ) : (
        <ActionForm action={decideDisputeAction} submitLabel="Record decision" loadingLabel="Deciding…" variant="secondary" className="flex flex-col gap-2 border-t border-neutral-200 pt-2">
          {(describedBy) => (
            <>
              <input type="hidden" name="disputeId" value={dispute.id} />
              <input type="hidden" name="expectedVersion" value={dispute.recordVersion} />
              <FormField id={`dispute-decision-${dispute.id}`} label="Decision (required)">
                <Select id={`dispute-decision-${dispute.id}`} name="decision" required aria-describedby={describedBy}>
                  <option value="upheld">Uphold (exclude this source from the metric)</option>
                  <option value="rejected">Reject (keep the source, no change)</option>
                </Select>
              </FormField>
              <FormField id={`dispute-decision-notes-${dispute.id}`} label="Decision notes (required)">
                <Input id={`dispute-decision-notes-${dispute.id}`} name="decisionNotes" required aria-describedby={describedBy} />
              </FormField>
            </>
          )}
        </ActionForm>
      )}
    </div>
  );
}

// -- Corrective actions ----------------------------------------------------

function CorrectiveActionRow({ action, updateAction }: { action: VendorPerformanceCorrectiveAction; updateAction: SimpleFormAction }) {
  const overdue = isVendorPerformanceCorrectiveActionOverdue(action);
  const canUpdate = action.status === "open" || action.status === "in_progress";
  return (
    <div className="flex flex-col gap-1 rounded-md border border-neutral-200 p-2">
      <div className="flex flex-wrap items-center gap-2">
        <StatusBadge tone={CORRECTIVE_ACTION_STATUS_TONE[action.status]} label={action.status} />
        {overdue ? <StatusBadge tone="danger" label="overdue" /> : null}
        <span className="text-sm text-neutral-900">{action.description}</span>
      </div>
      <p className="text-xs text-neutral-500">
        Owner {action.ownerLabel ?? "—"} · due {action.dueDate ?? "—"}
        {action.status === "completed" ? ` · completed ${action.completedAt ? new Date(action.completedAt).toLocaleString() : "—"}` : ""}
      </p>
      {action.completionNote ? <p className="text-xs text-neutral-500">{action.completionNote}</p> : null}
      {canUpdate ? (
        <ActionForm action={updateAction} submitLabel="Update status" loadingLabel="Updating…" variant="secondary" className="mt-1 flex flex-wrap items-end gap-2">
          {(describedBy) => (
            <>
              <input type="hidden" name="actionId" value={action.id} />
              <input type="hidden" name="expectedVersion" value={action.recordVersion} />
              <FormField id={`ca-status-${action.id}`} label="Status">
                <Select id={`ca-status-${action.id}`} name="status" aria-describedby={describedBy}>
                  <option value="in_progress">in_progress</option>
                  <option value="completed">completed</option>
                  <option value="cancelled">cancelled</option>
                </Select>
              </FormField>
              <FormField id={`ca-completion-note-${action.id}`} label="Completion note">
                <Input id={`ca-completion-note-${action.id}`} name="completionNote" aria-describedby={describedBy} />
              </FormField>
            </>
          )}
        </ActionForm>
      ) : null}
    </div>
  );
}

// -- Issues ------------------------------------------------------------

function IssueRow({
  issue,
  correctiveActions,
  updateIssueStatusAction,
  addCorrectiveActionAction,
  updateCorrectiveActionStatusAction,
}: {
  issue: VendorPerformanceIssue;
  correctiveActions: readonly VendorPerformanceCorrectiveAction[];
  updateIssueStatusAction: SimpleFormAction;
  addCorrectiveActionAction: SimpleFormAction;
  updateCorrectiveActionStatusAction: SimpleFormAction;
}) {
  const canUpdate = issue.status === "open" || issue.status === "in_progress";
  return (
    <div className="flex flex-col gap-3 rounded-md border border-neutral-200 p-3">
      <div className="flex flex-wrap items-center gap-2">
        <StatusBadge tone={ISSUE_STATUS_TONE[issue.status]} label={issue.status} />
        <StatusBadge tone={ISSUE_SEVERITY_TONE[issue.severity]} label={issue.severity} />
        <span className="text-sm font-medium text-neutral-900">{issue.title}</span>
        {issue.kpiCode ? <span className="text-xs text-neutral-500">({issue.kpiCode})</span> : null}
      </div>
      {issue.description ? <p className="text-sm text-neutral-700">{issue.description}</p> : null}
      <p className="text-xs text-neutral-500">
        Raised by {issue.raisedBy ?? issue.raisedByAuthUserId ?? "—"} on {new Date(issue.raisedAt).toLocaleString()}
      </p>
      {issue.status === "resolved" || issue.status === "closed" ? (
        <p className="text-xs text-neutral-500">
          {issue.status === "resolved" ? "Resolved" : "Closed"} by {issue.resolvedBy ?? issue.resolvedByAuthUserId ?? "—"} on {issue.resolvedAt ? new Date(issue.resolvedAt).toLocaleString() : "—"}
          {issue.resolutionNote ? `: ${issue.resolutionNote}` : ""}
        </p>
      ) : null}

      {canUpdate ? (
        <ActionForm action={updateIssueStatusAction} submitLabel="Update status" loadingLabel="Updating…" variant="secondary" className="flex flex-wrap items-end gap-2 border-t border-neutral-200 pt-2">
          {(describedBy) => (
            <>
              <input type="hidden" name="issueId" value={issue.id} />
              <input type="hidden" name="expectedVersion" value={issue.recordVersion} />
              <FormField id={`issue-status-${issue.id}`} label="Status">
                <Select id={`issue-status-${issue.id}`} name="status" aria-describedby={describedBy}>
                  <option value="in_progress">in_progress</option>
                  <option value="resolved">resolved</option>
                  <option value="closed">closed</option>
                </Select>
              </FormField>
              <FormField id={`issue-resolution-note-${issue.id}`} label="Resolution note">
                <Input id={`issue-resolution-note-${issue.id}`} name="resolutionNote" aria-describedby={describedBy} />
              </FormField>
            </>
          )}
        </ActionForm>
      ) : null}

      <div className="flex flex-col gap-2 border-t border-neutral-200 pt-2">
        <h3 className="text-xs font-semibold uppercase text-neutral-500">Corrective actions</h3>
        {correctiveActions.length === 0 ? <p className="text-xs text-neutral-500">None recorded yet.</p> : null}
        {correctiveActions.map((action) => (
          <CorrectiveActionRow key={action.id} action={action} updateAction={updateCorrectiveActionStatusAction} />
        ))}
        <ActionForm action={addCorrectiveActionAction} submitLabel="Add corrective action" loadingLabel="Adding…" variant="secondary" className="flex flex-wrap items-end gap-2">
          {(describedBy) => (
            <>
              <input type="hidden" name="issueId" value={issue.id} />
              <FormField id={`ca-new-description-${issue.id}`} label="Description (required)">
                <Input id={`ca-new-description-${issue.id}`} name="description" required className="min-w-[16rem]" aria-describedby={describedBy} />
              </FormField>
              <FormField id={`ca-new-owner-${issue.id}`} label="Owner">
                <Input id={`ca-new-owner-${issue.id}`} name="ownerLabel" aria-describedby={describedBy} />
              </FormField>
              <FormField id={`ca-new-due-date-${issue.id}`} label="Due date">
                <Input id={`ca-new-due-date-${issue.id}`} name="dueDate" type="date" aria-describedby={describedBy} />
              </FormField>
            </>
          )}
        </ActionForm>
      </div>
    </div>
  );
}

// -- Manual adjustments ----------------------------------------------------

function AdjustmentRow({ adjustment, decideAdjustmentAction }: { adjustment: VendorKpiManualAdjustment; decideAdjustmentAction: SimpleFormAction }) {
  return (
    <div className="flex flex-col gap-2 rounded-md border border-neutral-200 p-3">
      <div className="flex flex-wrap items-center gap-2">
        <StatusBadge tone={ADJUSTMENT_STATUS_TONE[adjustment.status]} label={adjustment.status} />
        <span className="text-sm font-medium text-neutral-900">{adjustment.kpiCode}</span>
        <span className="text-xs text-neutral-500">
          {adjustment.originalNormalizedScore != null ? adjustment.originalNormalizedScore.toFixed(1) : "—"} → {adjustment.adjustedNormalizedScore.toFixed(1)}
        </span>
      </div>
      <p className="text-sm text-neutral-700">{adjustment.reason}</p>
      <p className="text-xs text-neutral-500">
        Requested by {adjustment.requestedBy ?? adjustment.requestedByAuthUserId} on {new Date(adjustment.requestedAt).toLocaleString()}
      </p>
      {adjustment.status !== "pending_approval" ? (
        <p className="text-xs text-neutral-500">
          Decided by {adjustment.decidedBy ?? adjustment.decidedByAuthUserId ?? "—"} on {adjustment.decidedAt ? new Date(adjustment.decidedAt).toLocaleString() : "—"}: {adjustment.decisionNotes ?? "—"}
        </p>
      ) : (
        <ActionForm action={decideAdjustmentAction} submitLabel="Record decision" loadingLabel="Deciding…" variant="secondary" className="flex flex-col gap-2 border-t border-neutral-200 pt-2">
          {(describedBy) => (
            <>
              <input type="hidden" name="adjustmentId" value={adjustment.id} />
              <input type="hidden" name="expectedVersion" value={adjustment.recordVersion} />
              <FormField id={`adjustment-decision-${adjustment.id}`} label="Decision (required)">
                <Select id={`adjustment-decision-${adjustment.id}`} name="decision" required aria-describedby={describedBy}>
                  <option value="approved">Approve</option>
                  <option value="rejected">Reject</option>
                </Select>
              </FormField>
              <FormField id={`adjustment-decision-notes-${adjustment.id}`} label="Decision notes (required)">
                <Input id={`adjustment-decision-notes-${adjustment.id}`} name="decisionNotes" required aria-describedby={describedBy} />
              </FormField>
            </>
          )}
        </ActionForm>
      )}
    </div>
  );
}

// -- Lifecycle recommendations ----------------------------------------------

function RecommendationRow({ recommendation, decideRecommendationAction }: { recommendation: VendorLifecycleRecommendation; decideRecommendationAction: SimpleFormAction }) {
  return (
    <div className="flex flex-col gap-2 rounded-md border border-neutral-200 p-3">
      <div className="flex flex-wrap items-center gap-2">
        <StatusBadge tone={RECOMMENDATION_STATUS_TONE[recommendation.status]} label={recommendation.status} />
        <span className="text-sm font-medium text-neutral-900">
          system recommends: <StatusBadge tone={RECOMMENDATION_ACTION_TONE[recommendation.recommendedAction]} label={recommendation.recommendedAction} />
        </span>
      </div>
      <p className="text-sm text-neutral-700">{recommendation.recommendedRationale}</p>
      <p className="text-xs text-neutral-500">
        Recommended by {recommendation.recommendedBy ?? recommendation.recommendedByAuthUserId ?? "system"} on {new Date(recommendation.recommendedAt).toLocaleString()}
      </p>
      {recommendation.status === "decided" ? (
        <p className="text-xs text-neutral-500">
          Decided: <StatusBadge tone={recommendation.decidedAction ? RECOMMENDATION_ACTION_TONE[recommendation.decidedAction] : "neutral"} label={recommendation.decidedAction ?? "—"} /> by{" "}
          {recommendation.decidedBy ?? recommendation.decidedByAuthUserId ?? "—"} on {recommendation.decidedAt ? new Date(recommendation.decidedAt).toLocaleString() : "—"}
          {recommendation.decisionNotes ? ` — ${recommendation.decisionNotes}` : ""}
          {recommendation.executed ? ` (executed ${recommendation.executedAt ? new Date(recommendation.executedAt).toLocaleString() : ""})` : recommendation.decidedAction && recommendation.decidedAction !== "none" ? " (not yet executed)" : ""}
        </p>
      ) : (
        <ActionForm
          action={decideRecommendationAction}
          submitLabel="Record human decision"
          loadingLabel="Deciding…"
          variant="destructive"
          className="flex flex-col gap-2 border-t border-neutral-200 pt-2"
        >
          {(describedBy) => (
            <>
              <input type="hidden" name="recommendationId" value={recommendation.id} />
              <input type="hidden" name="expectedVersion" value={recommendation.recordVersion} />
              <FormField id={`recommendation-decided-action-${recommendation.id}`} label="Decided action (required -- this system never auto-executes; a human always decides)">
                <Select id={`recommendation-decided-action-${recommendation.id}`} name="decidedAction" defaultValue={recommendation.recommendedAction} required aria-describedby={describedBy}>
                  {VENDOR_LIFECYCLE_RECOMMENDATION_ACTIONS.map((a) => (
                    <option key={a} value={a}>
                      {a}
                    </option>
                  ))}
                </Select>
              </FormField>
              <FormField id={`recommendation-decision-notes-${recommendation.id}`} label="Decision notes (required)">
                <Input id={`recommendation-decision-notes-${recommendation.id}`} name="decisionNotes" required aria-describedby={describedBy} />
              </FormField>
              <FormField id={`recommendation-evidence-ref-${recommendation.id}`} label="Evidence reference (required for suspend/blacklist)">
                <Input id={`recommendation-evidence-ref-${recommendation.id}`} name="evidenceRef" placeholder="e.g. incident id, contract clause, audit ref" aria-describedby={describedBy} />
              </FormField>
            </>
          )}
        </ActionForm>
      )}
    </div>
  );
}

// -- Root panel ------------------------------------------------------------

export function VendorPerformanceDetailPanel({
  vendorMasterId,
  vendorLifecycleStatus,
  currentCard,
  scorecardVersions,
  drilldown,
  issues,
  correctiveActionsByIssue,
  adjustments,
  recommendations,
  disputes,
  calculateAction,
  publishAction,
  raiseDisputeAction,
  decideDisputeAction,
  raiseIssueAction,
  updateIssueStatusAction,
  addCorrectiveActionAction,
  updateCorrectiveActionStatusAction,
  requestAdjustmentAction,
  decideAdjustmentAction,
  evaluateRecommendationAction,
  decideRecommendationAction,
}: {
  tenantSlug: string;
  vendorMasterId: string;
  vendorLifecycleStatus: VendorLifecycleStatus;
  currentCard: VendorKpiScorecard | null;
  scorecardVersions: readonly VendorKpiScorecard[];
  drilldown: readonly VendorKpiScorecardDrilldownLine[];
  issues: readonly VendorPerformanceIssue[];
  correctiveActionsByIssue: Record<string, readonly VendorPerformanceCorrectiveAction[]>;
  adjustments: readonly VendorKpiManualAdjustment[];
  recommendations: readonly VendorLifecycleRecommendation[];
  disputes: readonly VendorKpiSourceDispute[];
  calculateAction: SimpleFormAction;
  publishAction: SimpleFormAction;
  raiseDisputeAction: SimpleFormAction;
  decideDisputeAction: SimpleFormAction;
  raiseIssueAction: SimpleFormAction;
  updateIssueStatusAction: SimpleFormAction;
  addCorrectiveActionAction: SimpleFormAction;
  updateCorrectiveActionStatusAction: SimpleFormAction;
  requestAdjustmentAction: SimpleFormAction;
  decideAdjustmentAction: SimpleFormAction;
  evaluateRecommendationAction: SimpleFormAction;
  decideRecommendationAction: SimpleFormAction;
}) {
  const defaultWindowStart = currentCard ? toDatetimeLocal(currentCard.windowStart) : "";
  const defaultWindowEnd = currentCard ? toDatetimeLocal(currentCard.windowEnd) : "";
  const pendingDisputes = disputes.filter((d) => d.status === "pending");
  const decidedDisputes = disputes.filter((d) => d.status !== "pending");
  const pendingRecommendations = recommendations.filter((r) => r.status === "pending");
  const decidedRecommendations = recommendations.filter((r) => r.status !== "pending");

  const versionColumns: readonly DataTableColumn<VendorKpiScorecard>[] = [
    { key: "version", header: "Version", render: (row) => `v${row.versionNo}${row.isCurrent ? " (current)" : ""}` },
    { key: "status", header: "Status", render: (row) => <StatusBadge tone={row.status === "published" ? "success" : "neutral"} label={row.status} /> },
    { key: "band", header: "Band", render: (row) => (row.band ? <StatusBadge tone={BAND_TONE[row.band]} label={row.band} /> : "—") },
    { key: "score", header: "Composite", render: (row) => (row.compositeScore != null ? row.compositeScore.toFixed(1) : "—") },
    { key: "window", header: "Window", render: (row) => `${new Date(row.windowStart).toLocaleDateString()} – ${new Date(row.windowEnd).toLocaleDateString()}` },
    { key: "publishedBy", header: "Published by", render: (row) => row.publishedBy ?? row.publishedByAuthUserId ?? "—" },
  ];

  return (
    <div className="flex flex-col gap-6">
      <section className="rounded-md border border-neutral-200 p-4">
        <div className="flex flex-wrap items-center gap-2">
          <h2 className="text-sm font-semibold text-neutral-900">Current scorecard</h2>
          <StatusBadge tone={VENDOR_LIFECYCLE_TONE[vendorLifecycleStatus]} label={`vendor: ${vendorLifecycleStatus}`} />
        </div>
        {currentCard ? (
          <dl className="mt-2 grid grid-cols-1 gap-3 text-sm sm:grid-cols-4">
            <SummaryRow label="Band" value={currentCard.band ? <StatusBadge tone={BAND_TONE[currentCard.band]} label={currentCard.band} /> : "—"} />
            <SummaryRow label="Composite score" value={currentCard.compositeScore != null ? currentCard.compositeScore.toFixed(1) : "—"} />
            <SummaryRow label="Coverage" value={`${currentCard.computableWeightTotal} of ${currentCard.totalWeightDefined} weight computable`} />
            <SummaryRow label="Window" value={`${new Date(currentCard.windowStart).toLocaleString()} – ${new Date(currentCard.windowEnd).toLocaleString()}`} />
            {currentCard.coverageNote ? <SummaryRow label="Coverage note" value={currentCard.coverageNote} /> : null}
          </dl>
        ) : (
          <p className="mt-2 text-sm text-neutral-500">No scorecard has been published for this vendor yet. Calculate a window&apos;s metrics, then publish.</p>
        )}
      </section>

      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4 sm:flex-row sm:gap-6">
        <div className="flex-1">
          <h3 className="text-xs font-semibold uppercase text-neutral-500">1. Calculate metrics for a window</h3>
          <ActionForm action={calculateAction} submitLabel="Calculate" loadingLabel="Calculating…" variant="secondary" className="mt-2 flex flex-wrap items-end gap-2">
            {(describedBy) => (
              <>
                <FormField id="calc-window-start" label="Window start (required)">
                  <Input id="calc-window-start" name="windowStart" type="datetime-local" defaultValue={defaultWindowStart} required aria-describedby={describedBy} />
                </FormField>
                <FormField id="calc-window-end" label="Window end (required)">
                  <Input id="calc-window-end" name="windowEnd" type="datetime-local" defaultValue={defaultWindowEnd} required aria-describedby={describedBy} />
                </FormField>
              </>
            )}
          </ActionForm>
        </div>
        <div className="flex-1">
          <h3 className="text-xs font-semibold uppercase text-neutral-500">2. Publish the scorecard for that window</h3>
          <ActionForm action={publishAction} submitLabel="Publish" loadingLabel="Publishing…" className="mt-2 flex flex-wrap items-end gap-2">
            {(describedBy) => (
              <>
                <FormField id="publish-window-start" label="Window start (required, must match a calculated run)">
                  <Input id="publish-window-start" name="windowStart" type="datetime-local" defaultValue={defaultWindowStart} required aria-describedby={describedBy} />
                </FormField>
                <FormField id="publish-window-end" label="Window end (required)">
                  <Input id="publish-window-end" name="windowEnd" type="datetime-local" defaultValue={defaultWindowEnd} required aria-describedby={describedBy} />
                </FormField>
              </>
            )}
          </ActionForm>
        </div>
      </section>

      <section className="rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Scorecard version history</h2>
        <div className="mt-2">
          <DataTable caption="Vendor KPI scorecard versions" columns={versionColumns} rows={scorecardVersions} rowKey={(row) => row.id} emptyMessage="No scorecards published yet." />
        </div>
      </section>

      <section className="rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Per-KPI drilldown (current scorecard)</h2>
        <p className="text-xs text-neutral-500">
          invoice_accuracy is disclosed here, never fabricated: its real evidence source is Prompt 265 (not yet built) -- it renders as not computable with an explicit source note until that
          capability lands.
        </p>
        {drilldown.length === 0 ? (
          <div className="mt-2">
            <EmptyState title="No drilldown to show" description="Publish a scorecard first." />
          </div>
        ) : (
          <div className="mt-2 overflow-x-auto rounded-md border border-neutral-200">
            <table className="w-full text-sm">
              <thead className="bg-neutral-50 text-left text-xs font-medium uppercase text-neutral-500">
                <tr>
                  <th className="px-3 py-2">KPI</th>
                  <th className="px-3 py-2">Computed</th>
                  <th className="px-3 py-2">Normalized</th>
                  <th className="px-3 py-2">Band</th>
                  <th className="px-3 py-2">Detail</th>
                  <th className="px-3 py-2">Dispute</th>
                </tr>
              </thead>
              <tbody>
                {drilldown.map((line) => (
                  <DrilldownRow key={line.lineId} line={line} raiseDisputeAction={raiseDisputeAction} />
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>

      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Source disputes</h2>
        {pendingDisputes.length === 0 && decidedDisputes.length === 0 ? (
          <p className="text-sm text-neutral-500">No disputes raised.</p>
        ) : (
          <>
            {pendingDisputes.map((d) => (
              <DisputeRow key={d.id} dispute={d} decideDisputeAction={decideDisputeAction} />
            ))}
            {decidedDisputes.map((d) => (
              <DisputeRow key={d.id} dispute={d} decideDisputeAction={decideDisputeAction} />
            ))}
          </>
        )}
      </section>

      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Issues &amp; corrective actions</h2>
        <ActionForm action={raiseIssueAction} submitLabel="Raise issue" loadingLabel="Raising…" variant="secondary" className="flex flex-wrap items-end gap-2 rounded-md border border-neutral-200 p-3">
          {(describedBy) => (
            <>
              <input type="hidden" name="scorecardId" value={currentCard?.id ?? ""} />
              <FormField id="raise-issue-title" label="Title (required)">
                <Input id="raise-issue-title" name="title" required className="min-w-[16rem]" aria-describedby={describedBy} />
              </FormField>
              <FormField id="raise-issue-severity" label="Severity (required)">
                <Select id="raise-issue-severity" name="severity" required defaultValue="medium" aria-describedby={describedBy}>
                  <option value="low">low</option>
                  <option value="medium">medium</option>
                  <option value="high">high</option>
                  <option value="critical">critical</option>
                </Select>
              </FormField>
              <FormField id="raise-issue-kpi-code" label="KPI category">
                <Select id="raise-issue-kpi-code" name="kpiCode" aria-describedby={describedBy}>
                  <option value="">(not tied to one category)</option>
                  {VENDOR_KPI_CODES.map((c) => (
                    <option key={c} value={c}>
                      {c}
                    </option>
                  ))}
                </Select>
              </FormField>
              <FormField id="raise-issue-description" label="Description">
                <Input id="raise-issue-description" name="description" className="min-w-[16rem]" aria-describedby={describedBy} />
              </FormField>
            </>
          )}
        </ActionForm>

        {issues.length === 0 ? (
          <EmptyState title="No issues raised" description="Raise an issue above when a vendor's performance needs to be tracked and corrected." />
        ) : (
          issues.map((issue) => (
            <IssueRow
              key={issue.id}
              issue={issue}
              correctiveActions={correctiveActionsByIssue[issue.id] ?? []}
              updateIssueStatusAction={updateIssueStatusAction}
              addCorrectiveActionAction={addCorrectiveActionAction}
              updateCorrectiveActionStatusAction={updateCorrectiveActionStatusAction}
            />
          ))
        )}
      </section>

      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Manual adjustments</h2>
        <p className="text-xs text-neutral-500">Every manual override to a computed KPI score requires a reason and a separate approver&apos;s decision -- it is never applied silently.</p>
        <ActionForm
          action={requestAdjustmentAction}
          submitLabel="Request adjustment"
          loadingLabel="Requesting…"
          variant="secondary"
          className="flex flex-wrap items-end gap-2 rounded-md border border-neutral-200 p-3"
        >
          {(describedBy) => (
            <>
              <input type="hidden" name="scorecardId" value={currentCard?.id ?? ""} />
              <FormField id="adjustment-kpi-code" label="KPI category (required)">
                <Select id="adjustment-kpi-code" name="kpiCode" required aria-describedby={describedBy}>
                  {VENDOR_KPI_CODES.map((c) => (
                    <option key={c} value={c}>
                      {c}
                    </option>
                  ))}
                </Select>
              </FormField>
              <FormField id="adjustment-score" label="Adjusted normalized score, 0-100 (required)">
                <Input id="adjustment-score" name="adjustedNormalizedScore" type="number" min={0} max={100} step="any" required aria-describedby={describedBy} />
              </FormField>
              <FormField id="adjustment-reason" label="Reason (required)">
                <Input id="adjustment-reason" name="reason" required className="min-w-[16rem]" aria-describedby={describedBy} />
              </FormField>
            </>
          )}
        </ActionForm>

        {adjustments.length === 0 ? (
          <p className="text-sm text-neutral-500">No manual adjustments recorded for the current scorecard.</p>
        ) : (
          adjustments.map((a) => <AdjustmentRow key={a.id} adjustment={a} decideAdjustmentAction={decideAdjustmentAction} />)
        )}
      </section>

      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Governed lifecycle recommendation</h2>
        <p className="text-xs text-neutral-500">
          The system only ever <em>recommends</em> suspend/blacklist/reactivate from a published scorecard&apos;s band -- a human always records the actual decision below, and only a decided
          suspend/blacklist/reactivate is ever executed against the vendor&apos;s eligibility.
        </p>
        <ActionForm
          action={evaluateRecommendationAction}
          submitLabel="Evaluate recommendation"
          loadingLabel="Evaluating…"
          variant="secondary"
          className="flex flex-wrap items-end gap-2 rounded-md border border-neutral-200 p-3"
        >
          {(describedBy) => (
            <>
              <input type="hidden" name="scorecardId" value={currentCard?.id ?? ""} />
              <FormField id="recommendation-override-action" label="Override action (optional -- leave blank to use the current scorecard's band)">
                <Select id="recommendation-override-action" name="overrideAction" aria-describedby={describedBy}>
                  <option value="">(derive from current scorecard band)</option>
                  {VENDOR_LIFECYCLE_RECOMMENDATION_ACTIONS.map((a) => (
                    <option key={a} value={a}>
                      {a}
                    </option>
                  ))}
                </Select>
              </FormField>
              <FormField id="recommendation-rationale" label="Rationale (required if overriding)">
                <Input id="recommendation-rationale" name="rationale" className="min-w-[16rem]" aria-describedby={describedBy} />
              </FormField>
            </>
          )}
        </ActionForm>

        {pendingRecommendations.length === 0 && decidedRecommendations.length === 0 ? (
          <p className="text-sm text-neutral-500">No lifecycle recommendation evaluated yet.</p>
        ) : (
          <>
            {pendingRecommendations.map((r) => (
              <RecommendationRow key={r.id} recommendation={r} decideRecommendationAction={decideRecommendationAction} />
            ))}
            {decidedRecommendations.map((r) => (
              <RecommendationRow key={r.id} recommendation={r} decideRecommendationAction={decideRecommendationAction} />
            ))}
          </>
        )}
      </section>

      <p className="text-xs text-neutral-400">Vendor {vendorMasterId} (app.master_records, ADR-0020) -- performance identity is never duplicated into a second vendor-shaped table.</p>
    </div>
  );
}
