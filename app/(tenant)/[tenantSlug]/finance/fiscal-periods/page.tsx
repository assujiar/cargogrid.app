import { notFound } from "next/navigation";
import Link from "next/link";
import { resolveFinanceAccessForRequest } from "../../../../../lib/portal/resolve-finance-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { listFinanceFiscalPeriods, FiscalPeriodQueryError } from "../../../../../server/queries/fiscal-period.ts";
import type { FinanceFiscalPeriod } from "../../../../../server/contracts/fiscal-period/fiscal-period.ts";
import { DataTable, type DataTableColumn } from "../../../../../components/tables/data-table.tsx";
import { StatusBadge } from "../../../../../components/ui/status-badge.tsx";
import { FINANCE_PERIOD_STATUS_TONE_MAP } from "../../../../../components/domain/status-tone-map.ts";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";
import { EmptyState } from "../../../../../components/ui/empty-state.tsx";
import { generateFinanceFiscalCalendarAction } from "./actions.ts";
import { GenerateFinanceFiscalCalendarForm } from "./fiscal-period-forms.tsx";

/**
 * Fiscal Period workspace (FIN-193, CG-S9-FIN-004). A tenant-wide period
 * list (bounded, admin-managed reference set -- at most 24 periods per
 * generated calendar, matching FIN-192's own "no pagination needed for a
 * bounded reference set" precedent), with a generate-calendar form and links
 * to each period's own close-checklist/lifecycle detail page.
 */
export default async function FiscalPeriodsPage({ params }: { params: Promise<{ tenantSlug: string }> }) {
  const { tenantSlug } = await params;
  const access = await resolveFinanceAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();
  let periods: FinanceFiscalPeriod[] = [];
  let loadFailed = false;
  try {
    periods = await listFinanceFiscalPeriods(supabase, { tenantId: access.tenant.id, companyId: null, calendarId: null, actorAuthUserId: access.authUserId });
  } catch (error) {
    if (!(error instanceof FiscalPeriodQueryError)) {
      throw error;
    }
    loadFailed = true;
  }

  const columns: readonly DataTableColumn<FinanceFiscalPeriod>[] = [
    {
      key: "periodCode",
      header: "Period",
      render: (period) => (
        <Link href={`/${tenantSlug}/finance/fiscal-periods/${period.id}`} className="font-medium text-primary underline">
          {period.periodCode}
        </Link>
      ),
    },
    { key: "dates", header: "Date range", render: (period) => `${period.startDate} -- ${period.endDate}` },
    {
      key: "status",
      header: "Status",
      render: (period) => {
        const { tone, label } = FINANCE_PERIOD_STATUS_TONE_MAP[period.status];
        return <StatusBadge tone={tone} label={label} />;
      },
    },
    { key: "closedBy", header: "Closed by", render: (period) => period.closedBy ?? "—" },
  ];

  return (
    <div className="flex flex-col gap-6">
      <div>
        <h1 className="text-xl font-semibold text-text-primary">Fiscal Periods</h1>
        <p className="text-sm text-text-secondary">Governed period lifecycle -- open, soft-close, close, and governed reopen. Hard-lock enforcement at a real posting boundary is a later Finance capability.</p>
      </div>

      {loadFailed ? (
        <ErrorState description="Something went wrong loading fiscal periods. Please try again." />
      ) : periods.length === 0 ? (
        <EmptyState title="No fiscal calendar yet" description="Generate one below." />
      ) : (
        <DataTable caption="Fiscal periods" columns={columns} rows={periods} rowKey={(period) => period.id} emptyMessage="No periods yet." />
      )}

      <GenerateFinanceFiscalCalendarForm action={generateFinanceFiscalCalendarAction.bind(null, tenantSlug)} />
    </div>
  );
}
