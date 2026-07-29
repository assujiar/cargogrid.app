import { notFound } from "next/navigation";
import Link from "next/link";
import { resolveFinanceAccessForRequest } from "../../../../../lib/portal/resolve-finance-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { listFinanceReconciliationRuns, listFinanceReconciliationExceptions, ReconciliationQueryError } from "../../../../../server/queries/reconciliation.ts";
import type { FinanceReconciliationRun, FinanceReconciliationException } from "../../../../../server/contracts/reconciliation/reconciliation.ts";
import { DataTable, type DataTableColumn } from "../../../../../components/tables/data-table.tsx";
import { StatusBadge } from "../../../../../components/ui/status-badge.tsx";
import { FINANCE_RECONCILIATION_RUN_STATUS_TONE_MAP, FINANCE_RECONCILIATION_EXCEPTION_STATUS_TONE_MAP } from "../../../../../components/domain/status-tone-map.ts";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";
import { EmptyState } from "../../../../../components/ui/empty-state.tsx";
import { executeFinanceReconciliationRunAction, resolveFinanceReconciliationExceptionAction, certifyFinanceReconciliationRunAction } from "./actions.ts";
import { ExecuteFinanceReconciliationRunForm, ResolveFinanceReconciliationExceptionForm, CertifyFinanceReconciliationRunForm } from "./reconciliation-forms.tsx";

/**
 * Reconciliation workspace (FIN-209, CG-S9-FIN-020). A bounded (200-row)
 * run list across ar/ap scope, a run-execution form, per-run certification,
 * and an exception drill-down with resolution. Formalizes FIN-202's own
 * already-real live control-account comparison into a persisted, as-of,
 * certifiable run -- read-only against every source table, never writing a
 * balance to force equality.
 */
export default async function ReconciliationPage({
  params,
  searchParams,
}: {
  params: Promise<{ tenantSlug: string }>;
  searchParams: Promise<{ scope?: string; runId?: string }>;
}) {
  const { tenantSlug } = await params;
  const { scope, runId } = await searchParams;
  const access = await resolveFinanceAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();
  let runs: FinanceReconciliationRun[] = [];
  let exceptions: FinanceReconciliationException[] = [];
  let loadFailed = false;
  try {
    runs = await listFinanceReconciliationRuns(supabase, { tenantId: access.tenant.id, companyId: null, scope: scope ?? null, actorAuthUserId: access.authUserId });
    if (runId) {
      exceptions = await listFinanceReconciliationExceptions(supabase, { runId, actorAuthUserId: access.authUserId });
    }
  } catch (error) {
    if (!(error instanceof ReconciliationQueryError)) {
      throw error;
    }
    loadFailed = true;
  }

  const columns: readonly DataTableColumn<FinanceReconciliationRun>[] = [
    { key: "scope", header: "Scope", render: (run) => run.scope },
    { key: "asOfDate", header: "As-of date", render: (run) => run.asOfDate },
    { key: "controlTotal", header: "Control total", render: (run) => run.controlTotal },
    { key: "sourceTotal", header: "Source total", render: (run) => run.sourceTotal },
    { key: "variance", header: "Variance", render: (run) => run.varianceAmount },
    {
      key: "status",
      header: "Status",
      render: (run) => {
        const { tone, label } = FINANCE_RECONCILIATION_RUN_STATUS_TONE_MAP[run.status];
        return <StatusBadge tone={tone} label={label} />;
      },
    },
    { key: "view", header: "Exceptions", render: (run) => <Link href={`?runId=${run.id}`}>View exceptions</Link> },
    {
      key: "actions",
      header: "Actions",
      render: (run) => {
        if (run.status === "certified") {
          return <span className="text-xs text-text-secondary">Certified</span>;
        }
        return <CertifyFinanceReconciliationRunForm action={certifyFinanceReconciliationRunAction.bind(null, tenantSlug, run.id, run.recordVersion)} />;
      },
    },
  ];

  const exceptionColumns: readonly DataTableColumn<FinanceReconciliationException>[] = [
    { key: "description", header: "Description", render: (exception) => exception.description },
    { key: "expected", header: "Expected", render: (exception) => exception.expectedAmount },
    { key: "actual", header: "Actual", render: (exception) => exception.actualAmount },
    { key: "variance", header: "Variance", render: (exception) => exception.varianceAmount },
    {
      key: "status",
      header: "Status",
      render: (exception) => {
        const { tone, label } = FINANCE_RECONCILIATION_EXCEPTION_STATUS_TONE_MAP[exception.status];
        return <StatusBadge tone={tone} label={label} />;
      },
    },
    {
      key: "actions",
      header: "Actions",
      render: (exception) => {
        if (exception.status === "open") {
          return <ResolveFinanceReconciliationExceptionForm action={resolveFinanceReconciliationExceptionAction.bind(null, tenantSlug, exception.id, exception.recordVersion)} />;
        }
        return <span className="text-xs text-text-secondary">Resolved</span>;
      },
    },
  ];

  return (
    <div className="flex flex-col gap-6">
      <div>
        <h1 className="text-xl font-semibold text-text-primary">Reconciliation</h1>
        <p className="text-sm text-text-secondary">
          Deterministic, as-of reconciliation of the AR/AP subledger against its own GL control account. A run never silently writes a balance
          to force equality; certification requires an independent authority and zero open exceptions.
        </p>
      </div>

      <div>
        {loadFailed ? (
          <ErrorState description="Something went wrong loading reconciliation runs. Please try again." />
        ) : runs.length === 0 ? (
          <EmptyState title="No reconciliation runs yet" description="Execute a run below to compare a control account against its own open-item total." />
        ) : (
          <DataTable caption="Reconciliation runs" columns={columns} rows={runs} rowKey={(run) => run.id} emptyMessage="No reconciliation runs yet." />
        )}
      </div>

      {runId ? (
        <div>
          <h2 className="text-sm font-semibold text-text-primary">Exceptions for run {runId}</h2>
          <DataTable caption="Reconciliation exceptions" columns={exceptionColumns} rows={exceptions} rowKey={(exception) => exception.id} emptyMessage="No exceptions -- fully reconciled." />
        </div>
      ) : null}

      <ExecuteFinanceReconciliationRunForm action={executeFinanceReconciliationRunAction.bind(null, tenantSlug)} />
    </div>
  );
}
