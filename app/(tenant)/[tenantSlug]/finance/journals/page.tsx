import { notFound } from "next/navigation";
import Link from "next/link";
import { resolveFinanceAccessForRequest } from "../../../../../lib/portal/resolve-finance-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { listFinanceJournals, getFinanceJournalLines, JournalQueryError } from "../../../../../server/queries/journal.ts";
import type { FinanceJournal, FinanceJournalLine } from "../../../../../server/contracts/journal/journal.ts";
import { DataTable, type DataTableColumn } from "../../../../../components/tables/data-table.tsx";
import { StatusBadge } from "../../../../../components/ui/status-badge.tsx";
import { FINANCE_JOURNAL_STATUS_TONE_MAP } from "../../../../../components/domain/status-tone-map.ts";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";
import { EmptyState } from "../../../../../components/ui/empty-state.tsx";
import {
  createFinanceJournalDraftAction,
  submitFinanceJournalForApprovalAction,
  discardFinanceJournalDraftAction,
  approveFinanceJournalAction,
  postFinanceJournalAction,
} from "./actions.ts";
import {
  CreateFinanceJournalDraftForm,
  SubmitFinanceJournalForApprovalForm,
  DiscardFinanceJournalDraftForm,
  ApproveFinanceJournalForm,
  PostFinanceJournalForm,
} from "./journal-forms.tsx";

/**
 * Double-Entry Journal workspace (FIN-203, CG-S9-FIN-014). A bounded
 * (200-row) journal list -- manual and system (subledger-sourced) journals
 * share this same list, filterable by source type -- a prepare-manual-
 * journal form, per-row lifecycle actions for manual journals
 * (submit/discard while draft, approve while submitted, post while
 * approved), and a per-journal line drill-down. A system journal has no
 * lifecycle action here -- it posts immediately at creation, per Prompt 203
 * section 21's own "the journal posts once" for an already-authorized
 * source event.
 */
export default async function JournalsPage({
  params,
  searchParams,
}: {
  params: Promise<{ tenantSlug: string }>;
  searchParams: Promise<{ sourceType?: string; journalId?: string }>;
}) {
  const { tenantSlug } = await params;
  const { sourceType, journalId } = await searchParams;
  const access = await resolveFinanceAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();
  let journals: FinanceJournal[] = [];
  let lines: FinanceJournalLine[] = [];
  let loadFailed = false;
  try {
    journals = await listFinanceJournals(supabase, { tenantId: access.tenant.id, companyId: null, sourceType: sourceType ?? null, status: null, actorAuthUserId: access.authUserId });
    if (journalId) {
      lines = await getFinanceJournalLines(supabase, { journalId, actorAuthUserId: access.authUserId });
    }
  } catch (error) {
    if (!(error instanceof JournalQueryError)) {
      throw error;
    }
    loadFailed = true;
  }

  const columns: readonly DataTableColumn<FinanceJournal>[] = [
    { key: "number", header: "Journal #", render: (journal) => journal.journalNumber ?? "(unposted)" },
    { key: "sourceType", header: "Source", render: (journal) => journal.sourceType },
    { key: "currency", header: "Currency", render: (journal) => journal.currency },
    { key: "total", header: "Total", render: (journal) => journal.totalAmount },
    { key: "journalDate", header: "Journal date", render: (journal) => journal.journalDate },
    {
      key: "status",
      header: "Status",
      render: (journal) => {
        const { tone, label } = FINANCE_JOURNAL_STATUS_TONE_MAP[journal.status];
        return <StatusBadge tone={tone} label={label} />;
      },
    },
    { key: "view", header: "Lines", render: (journal) => <Link href={`?journalId=${journal.id}`}>View lines</Link> },
    {
      key: "actions",
      header: "Actions",
      render: (journal) => {
        if (journal.sourceType !== "manual") {
          return "—";
        }
        if (journal.status === "draft") {
          return (
            <div className="flex flex-wrap gap-2">
              <SubmitFinanceJournalForApprovalForm action={submitFinanceJournalForApprovalAction.bind(null, tenantSlug, journal.id, journal.recordVersion)} />
              <DiscardFinanceJournalDraftForm action={discardFinanceJournalDraftAction.bind(null, tenantSlug, journal.id, journal.recordVersion)} />
            </div>
          );
        }
        if (journal.status === "submitted") {
          return (
            <div className="flex flex-wrap gap-2">
              <ApproveFinanceJournalForm action={approveFinanceJournalAction.bind(null, tenantSlug, journal.id, journal.recordVersion)} />
              <DiscardFinanceJournalDraftForm action={discardFinanceJournalDraftAction.bind(null, tenantSlug, journal.id, journal.recordVersion)} />
            </div>
          );
        }
        if (journal.status === "approved") {
          return <PostFinanceJournalForm action={postFinanceJournalAction.bind(null, tenantSlug, journal.id, journal.recordVersion)} />;
        }
        return "—";
      },
    },
  ];

  const lineColumns: readonly DataTableColumn<FinanceJournalLine>[] = [
    { key: "lineNumber", header: "#", render: (line) => line.lineNumber },
    { key: "direction", header: "Direction", render: (line) => line.direction },
    { key: "amount", header: "Amount", render: (line) => line.amount },
    { key: "accountId", header: "Account", render: (line) => line.accountId },
    { key: "description", header: "Description", render: (line) => line.description ?? "—" },
  ];

  return (
    <div className="flex flex-col gap-6">
      <div>
        <h1 className="text-xl font-semibold text-text-primary">Journals</h1>
        <p className="text-sm text-text-secondary">
          Canonical double-entry journal -- manual and system (subledger-sourced) journals share identical debit=credit balance and posting
          controls. A normal role cannot edit a posted journal -- correction is a governed reversal (FIN-206), not a direct edit.
        </p>
      </div>

      <div>
        {loadFailed ? (
          <ErrorState description="Something went wrong loading journals. Please try again." />
        ) : journals.length === 0 ? (
          <EmptyState title="No journals yet" description="Prepare a manual journal below, or post an invoice/receipt/bill/settlement to see a system journal appear here." />
        ) : (
          <DataTable caption="Journals" columns={columns} rows={journals} rowKey={(journal) => journal.id} emptyMessage="No journals yet." />
        )}
      </div>

      {journalId ? (
        <div>
          <h2 className="text-sm font-semibold text-text-primary">Lines for journal {journalId}</h2>
          <DataTable caption="Journal lines" columns={lineColumns} rows={lines} rowKey={(line) => line.id} emptyMessage="No lines found." />
        </div>
      ) : null}

      <CreateFinanceJournalDraftForm action={createFinanceJournalDraftAction.bind(null, tenantSlug)} />
    </div>
  );
}
