import { notFound } from "next/navigation";
import { resolveFinanceAccessForRequest } from "../../../../../lib/portal/resolve-finance-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { listFinancePeriodLocks, PeriodLockQueryError } from "../../../../../server/queries/period-lock.ts";
import type { FinancePeriodLock } from "../../../../../server/contracts/period-lock/period-lock.ts";
import { DataTable, type DataTableColumn } from "../../../../../components/tables/data-table.tsx";
import { StatusBadge } from "../../../../../components/ui/status-badge.tsx";
import { FINANCE_PERIOD_LOCK_STATUS_TONE_MAP } from "../../../../../components/domain/status-tone-map.ts";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";
import { EmptyState } from "../../../../../components/ui/empty-state.tsx";
import {
  lockFinancePeriodAction,
  requestFinancePeriodReopenAction,
  approveFinancePeriodReopenAction,
  relockFinancePeriodAction,
} from "./actions.ts";
import { LockFinancePeriodForm, RequestFinancePeriodReopenForm, ApproveFinancePeriodReopenForm, RelockFinancePeriodForm } from "./lock-forms.tsx";

/**
 * Period Lock and Governed Reopen workspace (FIN-207, CG-S9-FIN-018). A
 * bounded (200-row) lock list across every fiscal period/scope, a lock form,
 * and per-row governed reopen/approve/re-lock actions. The one authoritative
 * guard this console reflects (`app.assert_finance_period_open_for_posting`)
 * is enforced at the database layer by every GL-affecting posting service --
 * this page is a control surface over that guard, never the guard itself.
 */
export default async function PeriodLocksPage({ params }: { params: Promise<{ tenantSlug: string }> }) {
  const { tenantSlug } = await params;
  const access = await resolveFinanceAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();
  let locks: FinancePeriodLock[] = [];
  let loadFailed = false;
  try {
    locks = await listFinancePeriodLocks(supabase, { tenantId: access.tenant.id, companyId: null, periodId: null, actorAuthUserId: access.authUserId });
  } catch (error) {
    if (!(error instanceof PeriodLockQueryError)) {
      throw error;
    }
    loadFailed = true;
  }

  const columns: readonly DataTableColumn<FinancePeriodLock>[] = [
    { key: "period", header: "Period", render: (lock) => lock.periodId },
    { key: "scope", header: "Scope", render: (lock) => lock.lockScope },
    {
      key: "status",
      header: "Status",
      render: (lock) => {
        const { tone, label } = FINANCE_PERIOD_LOCK_STATUS_TONE_MAP[lock.status];
        return <StatusBadge tone={tone} label={label} />;
      },
    },
    { key: "reason", header: "Reason", render: (lock) => lock.lockReason },
    { key: "reopenWindow", header: "Reopen window expires", render: (lock) => lock.reopenWindowExpiresAt ?? "—" },
    {
      key: "actions",
      header: "Actions",
      render: (lock) => {
        if (lock.status === "locked") {
          return <RequestFinancePeriodReopenForm action={requestFinancePeriodReopenAction.bind(null, tenantSlug, lock.id, lock.recordVersion)} />;
        }
        if (lock.status === "reopen_requested") {
          return <ApproveFinancePeriodReopenForm action={approveFinancePeriodReopenAction.bind(null, tenantSlug, lock.id, lock.recordVersion)} />;
        }
        if (lock.status === "reopened") {
          return <RelockFinancePeriodForm action={relockFinancePeriodAction.bind(null, tenantSlug, lock.id, lock.recordVersion)} />;
        }
        return "—";
      },
    },
  ];

  return (
    <div className="flex flex-col gap-6">
      <div>
        <h1 className="text-xl font-semibold text-text-primary">Period Locks</h1>
        <p className="text-sm text-text-secondary">
          Company/ledger/module-aware period locks enforced at the posting boundary by every GL-affecting posting service in this repository --
          the database layer, never UI-only. A reopen is minimum-scope, approved, reasoned, time-boxed and always followed by a governed re-lock.
          Supreme Admin retains a separately-disclosed absolute-CRUD exception (RPD-022); this console makes no absolute-prevention claim beyond
          that boundary.
        </p>
      </div>

      <div>
        {loadFailed ? (
          <ErrorState description="Something went wrong loading period locks. Please try again." />
        ) : locks.length === 0 ? (
          <EmptyState title="No period locks yet" description="Lock a period scope below to enforce a posting boundary." />
        ) : (
          <DataTable caption="Period locks" columns={columns} rows={locks} rowKey={(lock) => lock.id} emptyMessage="No period locks yet." />
        )}
      </div>

      <LockFinancePeriodForm action={lockFinancePeriodAction.bind(null, tenantSlug)} />
    </div>
  );
}
