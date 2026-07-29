import { notFound } from "next/navigation";
import Link from "next/link";
import { resolveFinanceAccessForRequest } from "../../../../../lib/portal/resolve-finance-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { listFinanceJournalCorrections, getFinanceCorrectionChain, JournalCorrectionQueryError } from "../../../../../server/queries/journal-correction.ts";
import type { FinanceJournalCorrection } from "../../../../../server/contracts/journal-correction/journal-correction.ts";
import { DataTable, type DataTableColumn } from "../../../../../components/tables/data-table.tsx";
import { StatusBadge } from "../../../../../components/ui/status-badge.tsx";
import { FINANCE_CORRECTION_STATUS_TONE_MAP } from "../../../../../components/domain/status-tone-map.ts";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";
import { EmptyState } from "../../../../../components/ui/empty-state.tsx";
import {
  prepareFinanceJournalReversalAction,
  prepareFinanceJournalAdjustmentAction,
  submitFinanceCorrectionForApprovalAction,
  discardFinanceCorrectionDraftAction,
  approveFinanceCorrectionAction,
  postFinanceCorrectionAction,
} from "./actions.ts";
import {
  PrepareFinanceJournalReversalForm,
  PrepareFinanceJournalAdjustmentForm,
  SubmitFinanceCorrectionForApprovalForm,
  DiscardFinanceCorrectionDraftForm,
  ApproveFinanceCorrectionForm,
  PostFinanceCorrectionForm,
} from "./correction-forms.tsx";

/**
 * Reversal and Adjustment workspace (FIN-206, CG-S9-FIN-017). A bounded
 * (200-row) correction-request list -- reversal and adjustment share this
 * same list and lifecycle (draft/submitted/approved/posted/discarded) --
 * prepare-reversal and prepare-adjustment forms, per-row lifecycle actions,
 * and a drill-down showing the original posted journal alongside the posted
 * correction journal once one exists. The original journal itself is never
 * edited here -- FIN-204's own posted-journal-integrity triggers already
 * make that impossible for a normal role.
 */
export default async function CorrectionsPage({
  params,
  searchParams,
}: {
  params: Promise<{ tenantSlug: string }>;
  searchParams: Promise<{ status?: string; correctionId?: string }>;
}) {
  const { tenantSlug } = await params;
  const { status, correctionId } = await searchParams;
  const access = await resolveFinanceAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();
  let corrections: FinanceJournalCorrection[] = [];
  let chain: { correction: Record<string, unknown>; originalJournal: Record<string, unknown>; correctionJournal: Record<string, unknown> | null } | null = null;
  let loadFailed = false;
  try {
    corrections = await listFinanceJournalCorrections(supabase, { tenantId: access.tenant.id, companyId: null, correctionType: null, status: status ?? null, actorAuthUserId: access.authUserId });
    if (correctionId) {
      chain = await getFinanceCorrectionChain(supabase, { correctionId, actorAuthUserId: access.authUserId });
    }
  } catch (error) {
    if (!(error instanceof JournalCorrectionQueryError)) {
      throw error;
    }
    loadFailed = true;
  }

  const columns: readonly DataTableColumn<FinanceJournalCorrection>[] = [
    { key: "type", header: "Type", render: (correction) => correction.correctionType },
    { key: "original", header: "Original journal", render: (correction) => correction.originalJournalId },
    { key: "correctionDate", header: "Correction date", render: (correction) => correction.correctionDate },
    { key: "reason", header: "Reason", render: (correction) => correction.reason },
    {
      key: "status",
      header: "Status",
      render: (correction) => {
        const { tone, label } = FINANCE_CORRECTION_STATUS_TONE_MAP[correction.status];
        return <StatusBadge tone={tone} label={label} />;
      },
    },
    { key: "view", header: "Chain", render: (correction) => <Link href={`?correctionId=${correction.id}`}>View chain</Link> },
    {
      key: "actions",
      header: "Actions",
      render: (correction) => {
        if (correction.status === "draft") {
          return (
            <div className="flex flex-wrap gap-2">
              <SubmitFinanceCorrectionForApprovalForm action={submitFinanceCorrectionForApprovalAction.bind(null, tenantSlug, correction.id, correction.recordVersion)} />
              <DiscardFinanceCorrectionDraftForm action={discardFinanceCorrectionDraftAction.bind(null, tenantSlug, correction.id, correction.recordVersion)} />
            </div>
          );
        }
        if (correction.status === "submitted") {
          return (
            <div className="flex flex-wrap gap-2">
              <ApproveFinanceCorrectionForm action={approveFinanceCorrectionAction.bind(null, tenantSlug, correction.id, correction.recordVersion)} />
              <DiscardFinanceCorrectionDraftForm action={discardFinanceCorrectionDraftAction.bind(null, tenantSlug, correction.id, correction.recordVersion)} />
            </div>
          );
        }
        if (correction.status === "approved") {
          return <PostFinanceCorrectionForm action={postFinanceCorrectionAction.bind(null, tenantSlug, correction.id, correction.recordVersion)} />;
        }
        return <span className="text-xs text-text-secondary">{correction.status === "posted" ? "Posted -- see chain" : "—"}</span>;
      },
    },
  ];

  return (
    <div className="flex flex-col gap-6">
      <div>
        <h1 className="text-xl font-semibold text-text-primary">Reversals &amp; Adjustments</h1>
        <p className="text-sm text-text-secondary">
          Governed correction of a posted journal through a new linked record -- a reversal derives its own exact opposite lines automatically;
          an adjustment posts a preparer-supplied balanced set of lines. The original posted journal is never rewritten for a normal role; at most
          one active reversal is allowed per original journal.
        </p>
      </div>

      <div>
        {loadFailed ? (
          <ErrorState description="Something went wrong loading corrections. Please try again." />
        ) : corrections.length === 0 ? (
          <EmptyState title="No corrections yet" description="Prepare a reversal or adjustment below against a posted journal." />
        ) : (
          <DataTable caption="Reversals and adjustments" columns={columns} rows={corrections} rowKey={(correction) => correction.id} emptyMessage="No corrections yet." />
        )}
      </div>

      {chain ? (
        <div className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
          <h2 className="text-sm font-semibold text-text-primary">Correction chain for {correctionId}</h2>
          <p className="text-xs text-text-secondary">
            Original journal status: {String((chain.originalJournal as { status?: string }).status ?? "unknown")}. Correction journal:{" "}
            {chain.correctionJournal ? String((chain.correctionJournal as { journalNumber?: string }).journalNumber ?? (chain.correctionJournal as { id?: string }).id) : "not yet posted"}.
          </p>
        </div>
      ) : null}

      <div className="flex flex-col gap-4 md:flex-row">
        <PrepareFinanceJournalReversalForm action={prepareFinanceJournalReversalAction.bind(null, tenantSlug)} />
        <PrepareFinanceJournalAdjustmentForm action={prepareFinanceJournalAdjustmentAction.bind(null, tenantSlug)} />
      </div>
    </div>
  );
}
