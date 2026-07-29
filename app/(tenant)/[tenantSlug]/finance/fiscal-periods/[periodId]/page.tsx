import { notFound } from "next/navigation";
import Link from "next/link";
import { resolveFinanceAccessForRequest } from "../../../../../../lib/portal/resolve-finance-access.server.ts";
import { createSupabaseServerClient } from "../../../../../../lib/supabase/server.ts";
import {
  listFinanceFiscalPeriods,
  listFinancePeriodChecklistItems,
  getFinancePeriodCloseReadiness,
  getFinancePeriodTransitionHistory,
  FiscalPeriodQueryError,
} from "../../../../../../server/queries/fiscal-period.ts";
import { StatusBadge } from "../../../../../../components/ui/status-badge.tsx";
import { FINANCE_PERIOD_STATUS_TONE_MAP } from "../../../../../../components/domain/status-tone-map.ts";
import { ErrorState } from "../../../../../../components/ui/error-state.tsx";
import {
  softCloseFinancePeriodAction,
  closeFinancePeriodAction,
  reopenFinancePeriodAction,
  acknowledgeFinancePeriodChecklistItemAction,
} from "../actions.ts";
import { SoftCloseFinancePeriodForm, CloseFinancePeriodForm, ReopenFinancePeriodForm, AcknowledgeChecklistItemForm } from "../fiscal-period-forms.tsx";

/** Fiscal Period detail (FIN-193, CG-S9-FIN-004): close checklist, readiness, lifecycle actions, and full transition history. */
export default async function FiscalPeriodDetailPage({ params }: { params: Promise<{ tenantSlug: string; periodId: string }> }) {
  const { tenantSlug, periodId } = await params;
  const access = await resolveFinanceAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();
  let loadFailed = false;
  let period;
  let checklistItems;
  let readiness;
  let history;
  try {
    const periods = await listFinanceFiscalPeriods(supabase, { tenantId: access.tenant.id, companyId: null, calendarId: null, actorAuthUserId: access.authUserId });
    period = periods.find((p) => p.id === periodId);
    if (!period) {
      notFound();
    }
    checklistItems = await listFinancePeriodChecklistItems(supabase, periodId);
    readiness = await getFinancePeriodCloseReadiness(supabase, periodId, access.authUserId);
    history = await getFinancePeriodTransitionHistory(supabase, periodId, access.authUserId);
  } catch (error) {
    if (!(error instanceof FiscalPeriodQueryError)) {
      throw error;
    }
    loadFailed = true;
  }

  if (loadFailed || !period) {
    return <ErrorState description="Something went wrong loading this fiscal period. Please try again." />;
  }

  const { tone, label } = FINANCE_PERIOD_STATUS_TONE_MAP[period.status];

  return (
    <div className="flex flex-col gap-6">
      <div>
        <Link href={`/${tenantSlug}/finance/fiscal-periods`} className="text-sm text-primary underline">
          ← Fiscal periods
        </Link>
        <h1 className="mt-1 text-xl font-semibold text-text-primary">
          {period.periodCode} <StatusBadge tone={tone} label={label} />
        </h1>
        <p className="text-sm text-text-secondary">
          {period.startDate} -- {period.endDate}
        </p>
      </div>

      <section aria-labelledby="checklist-heading" className="rounded-md border border-neutral-200 p-4">
        <h2 id="checklist-heading" className="text-sm font-semibold text-text-primary">
          Close checklist ({readiness?.ready ? "ready to close" : "not ready"})
        </h2>
        {checklistItems && checklistItems.length > 0 ? (
          <ul className="mt-2 flex flex-col gap-3">
            {checklistItems.map((item) => (
              <li key={item.id} className="flex flex-wrap items-center justify-between gap-2 border-b border-neutral-100 pb-2">
                <div>
                  <p className="text-sm text-text-primary">
                    {item.label} {item.required ? <span className="text-xs text-danger">(required)</span> : <span className="text-xs text-text-secondary">(optional)</span>}
                  </p>
                  <p className="text-xs text-text-secondary">
                    {item.satisfied ? `Satisfied by ${item.satisfiedBy ?? "—"} at ${item.satisfiedAt ?? "—"}` : "Not yet satisfied"}
                  </p>
                </div>
                {period.status !== "closed" ? (
                  <AcknowledgeChecklistItemForm
                    action={acknowledgeFinancePeriodChecklistItemAction.bind(null, tenantSlug, period.id, item.itemKey)}
                    satisfied={!item.satisfied}
                  />
                ) : null}
              </li>
            ))}
          </ul>
        ) : (
          <p className="mt-2 text-sm text-text-secondary">No close-policy checklist was effective when this period was generated -- nothing to acknowledge.</p>
        )}
      </section>

      <section aria-labelledby="lifecycle-heading" className="rounded-md border border-neutral-200 p-4">
        <h2 id="lifecycle-heading" className="text-sm font-semibold text-text-primary">
          Lifecycle
        </h2>
        <div className="mt-2 flex flex-wrap gap-4">
          {period.status === "open" ? <SoftCloseFinancePeriodForm action={softCloseFinancePeriodAction.bind(null, tenantSlug, period.id, period.recordVersion)} /> : null}
          {period.status === "soft_closed" ? (
            <CloseFinancePeriodForm action={closeFinancePeriodAction.bind(null, tenantSlug, period.id, period.recordVersion)} disabled={!readiness?.ready} />
          ) : null}
          {period.status === "closed" ? <ReopenFinancePeriodForm action={reopenFinancePeriodAction.bind(null, tenantSlug, period.id, period.recordVersion)} /> : null}
        </div>
      </section>

      <section aria-labelledby="history-heading" className="rounded-md border border-neutral-200 p-4">
        <h2 id="history-heading" className="text-sm font-semibold text-text-primary">
          Transition history
        </h2>
        <ul className="mt-2 flex flex-col gap-1 text-sm text-text-secondary">
          {history?.map((transition) => (
            <li key={transition.id}>
              {transition.fromStatus} → {transition.toStatus} by {transition.actorLabel ?? "—"} at {transition.createdAt}
              {transition.reason ? ` -- reason: ${transition.reason}` : ""}
            </li>
          ))}
        </ul>
      </section>
    </div>
  );
}
