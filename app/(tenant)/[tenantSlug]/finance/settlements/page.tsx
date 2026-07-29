import { notFound } from "next/navigation";
import { resolveFinanceAccessForRequest } from "../../../../../lib/portal/resolve-finance-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { listFinanceSettlements, SettlementQueryError } from "../../../../../server/queries/settlement.ts";
import type { FinanceSettlement } from "../../../../../server/contracts/settlement/settlement.ts";
import { DataTable, type DataTableColumn } from "../../../../../components/tables/data-table.tsx";
import { StatusBadge } from "../../../../../components/ui/status-badge.tsx";
import { FINANCE_SETTLEMENT_STATUS_TONE_MAP, FINANCE_LIFECYCLE_CANONICAL_STATE_TONE_MAP } from "../../../../../components/domain/status-tone-map.ts";
import { resolveFinanceLifecycleEditability } from "../../../../../server/contracts/lifecycle/lifecycle-editability-matrix.ts";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";
import { EmptyState } from "../../../../../components/ui/empty-state.tsx";
import {
  prepareFinanceSettlementAction,
  submitFinanceSettlementForApprovalAction,
  discardFinanceSettlementDraftAction,
  approveFinanceSettlementAction,
  executeFinanceSettlementAction,
  postFinanceSettlementAction,
  requestFinanceSettlementReversalAction,
} from "./actions.ts";
import {
  PrepareFinanceSettlementForm,
  SubmitFinanceSettlementForApprovalForm,
  DiscardFinanceSettlementDraftForm,
  ApproveFinanceSettlementForm,
  ExecuteFinanceSettlementForm,
  PostFinanceSettlementForm,
  RequestFinanceSettlementReversalForm,
} from "./settlement-forms.tsx";

/**
 * Settlement workspace (FIN-201, CG-S9-FIN-012). A bounded (200-row)
 * settlement queue -- prepare-with-exact-allocations form, per-row lifecycle
 * actions (submit/discard while draft, approve while submitted, record
 * execution while approved, post-to-AP while executed, governed reversal
 * once posted). Posting composes FIN-199's own AP settlement primitive
 * directly; execution and posting are distinct canonical states, so a
 * settlement cannot skip straight from approved to posted.
 */
export default async function SettlementsPage({ params }: { params: Promise<{ tenantSlug: string }> }) {
  const { tenantSlug } = await params;
  const access = await resolveFinanceAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();
  let settlements: FinanceSettlement[] = [];
  let loadFailed = false;
  try {
    settlements = await listFinanceSettlements(supabase, { tenantId: access.tenant.id, companyId: null, vendorMasterId: null, status: null, actorAuthUserId: access.authUserId });
  } catch (error) {
    if (!(error instanceof SettlementQueryError)) {
      throw error;
    }
    loadFailed = true;
  }

  const columns: readonly DataTableColumn<FinanceSettlement>[] = [
    { key: "number", header: "Settlement #", render: (settlement) => settlement.settlementNumber ?? "(unposted)" },
    { key: "vendor", header: "Vendor", render: (settlement) => settlement.vendorMasterId },
    { key: "currency", header: "Currency", render: (settlement) => settlement.currency },
    { key: "allocated", header: "Allocated", render: (settlement) => settlement.allocatedAmount },
    { key: "fee", header: "Fee", render: (settlement) => settlement.feeAmount },
    { key: "total", header: "Total", render: (settlement) => settlement.totalAmount },
    { key: "settlementDate", header: "Settlement date", render: (settlement) => settlement.settlementDate },
    { key: "executionReference", header: "Execution ref", render: (settlement) => settlement.executionReference ?? "—" },
    {
      key: "status",
      header: "Status",
      render: (settlement) => {
        const { tone, label } = FINANCE_SETTLEMENT_STATUS_TONE_MAP[settlement.status];
        return <StatusBadge tone={tone} label={label} />;
      },
    },
    {
      key: "lifecycle",
      header: "Lifecycle",
      render: (settlement) => {
        const editability = resolveFinanceLifecycleEditability("settlement", settlement.status);
        const { tone, label } = FINANCE_LIFECYCLE_CANONICAL_STATE_TONE_MAP[editability.canonicalState];
        return (
          <div className="flex flex-col gap-1">
            <StatusBadge tone={tone} label={label} />
            {editability.lockedReason ? <span className="text-xs text-text-secondary">{editability.lockedReason.replaceAll("_", " ")}</span> : null}
          </div>
        );
      },
    },
    {
      key: "actions",
      header: "Actions",
      render: (settlement) => {
        if (settlement.status === "draft") {
          return (
            <div className="flex flex-wrap gap-2">
              <SubmitFinanceSettlementForApprovalForm action={submitFinanceSettlementForApprovalAction.bind(null, tenantSlug, settlement.id, settlement.recordVersion)} />
              <DiscardFinanceSettlementDraftForm action={discardFinanceSettlementDraftAction.bind(null, tenantSlug, settlement.id, settlement.recordVersion)} />
            </div>
          );
        }
        if (settlement.status === "submitted") {
          return (
            <div className="flex flex-wrap gap-2">
              <ApproveFinanceSettlementForm action={approveFinanceSettlementAction.bind(null, tenantSlug, settlement.id, settlement.recordVersion)} />
              <DiscardFinanceSettlementDraftForm action={discardFinanceSettlementDraftAction.bind(null, tenantSlug, settlement.id, settlement.recordVersion)} />
            </div>
          );
        }
        if (settlement.status === "approved") {
          return <ExecuteFinanceSettlementForm action={executeFinanceSettlementAction.bind(null, tenantSlug, settlement.id, settlement.recordVersion)} />;
        }
        if (settlement.status === "executed") {
          return <PostFinanceSettlementForm action={postFinanceSettlementAction.bind(null, tenantSlug, settlement.id, settlement.recordVersion)} />;
        }
        if (settlement.status === "posted") {
          return <RequestFinanceSettlementReversalForm action={requestFinanceSettlementReversalAction.bind(null, tenantSlug, settlement.id)} />;
        }
        return "—";
      },
    },
  ];

  return (
    <div className="flex flex-col gap-6">
      <div>
        <h1 className="text-xl font-semibold text-text-primary">Settlements</h1>
        <p className="text-sm text-text-secondary">
          Governed vendor settlements allocated across accounts-payable open items. Execution (payment sent) and posting (AP reduced) are distinct,
          separately authorized steps. A normal role cannot edit a posted settlement -- correction is a governed reversal, not a direct edit.
        </p>
      </div>

      <div>
        {loadFailed ? (
          <ErrorState description="Something went wrong loading settlements. Please try again." />
        ) : settlements.length === 0 ? (
          <EmptyState title="No settlements yet" description="Prepare one against eligible AP open items below." />
        ) : (
          <DataTable caption="Settlements" columns={columns} rows={settlements} rowKey={(settlement) => settlement.id} emptyMessage="No settlements yet." />
        )}
      </div>

      <PrepareFinanceSettlementForm action={prepareFinanceSettlementAction.bind(null, tenantSlug)} />
    </div>
  );
}
