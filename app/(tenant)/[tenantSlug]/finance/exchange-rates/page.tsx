import { notFound } from "next/navigation";
import { resolveFinanceAccessForRequest } from "../../../../../lib/portal/resolve-finance-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { listFinanceCurrencies, listFinanceExchangeRates, CurrencyExchangeRateQueryError } from "../../../../../server/queries/currency-exchange-rate.ts";
import type { FinanceCurrency, FinanceExchangeRate } from "../../../../../server/contracts/currency-exchange-rate/currency-exchange-rate.ts";
import { DataTable, type DataTableColumn } from "../../../../../components/tables/data-table.tsx";
import { StatusBadge } from "../../../../../components/ui/status-badge.tsx";
import { FINANCE_EXCHANGE_RATE_STATUS_TONE_MAP } from "../../../../../components/domain/status-tone-map.ts";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";
import { EmptyState } from "../../../../../components/ui/empty-state.tsx";
import {
  createFinanceExchangeRateDraftAction,
  discardFinanceExchangeRateDraftAction,
  approveFinanceExchangeRateAction,
  convertFinanceAmountAction,
} from "./actions.ts";
import {
  CreateFinanceExchangeRateDraftForm,
  DiscardFinanceExchangeRateDraftForm,
  ApproveFinanceExchangeRateForm,
  ConvertFinanceAmountForm,
} from "./exchange-rate-forms.tsx";

/**
 * Currency and Exchange Rate workspace (FIN-194, CG-S9-FIN-005). A tenant-
 * scoped rate list (bounded, admin-managed reference set -- the same "no
 * pagination needed for a bounded reference set" precedent FIN-192/193
 * already established), the governed currency registry, a create-draft
 * form, per-row discard/approve actions, and a read-only convert-preview
 * tool.
 */
export default async function ExchangeRatesPage({ params }: { params: Promise<{ tenantSlug: string }> }) {
  const { tenantSlug } = await params;
  const access = await resolveFinanceAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();
  let rates: FinanceExchangeRate[] = [];
  let currencies: FinanceCurrency[] = [];
  let loadFailed = false;
  try {
    [rates, currencies] = await Promise.all([
      listFinanceExchangeRates(supabase, { tenantId: access.tenant.id, rateType: null, sourceCurrency: null, targetCurrency: null, actorAuthUserId: access.authUserId }),
      listFinanceCurrencies(supabase),
    ]);
  } catch (error) {
    if (!(error instanceof CurrencyExchangeRateQueryError)) {
      throw error;
    }
    loadFailed = true;
  }

  const rateColumns: readonly DataTableColumn<FinanceExchangeRate>[] = [
    { key: "pair", header: "Pair", render: (rate) => `${rate.sourceCurrency} → ${rate.targetCurrency}` },
    { key: "rateType", header: "Type", render: (rate) => rate.rateType },
    { key: "rate", header: "Rate", render: (rate) => rate.rate },
    { key: "effectiveFrom", header: "Effective from", render: (rate) => rate.effectiveFrom },
    { key: "effectiveTo", header: "Effective to", render: (rate) => rate.effectiveTo ?? "—" },
    {
      key: "status",
      header: "Status",
      render: (rate) => {
        const { tone, label } = FINANCE_EXCHANGE_RATE_STATUS_TONE_MAP[rate.status];
        return <StatusBadge tone={tone} label={label} />;
      },
    },
    {
      key: "actions",
      header: "Actions",
      render: (rate) =>
        rate.status === "draft" ? (
          <div className="flex gap-2">
            <ApproveFinanceExchangeRateForm action={approveFinanceExchangeRateAction.bind(null, tenantSlug, rate.id, rate.recordVersion)} />
            <DiscardFinanceExchangeRateDraftForm action={discardFinanceExchangeRateDraftAction.bind(null, tenantSlug, rate.id, rate.recordVersion)} />
          </div>
        ) : (
          "—"
        ),
    },
  ];

  const currencyColumns: readonly DataTableColumn<FinanceCurrency>[] = [
    { key: "code", header: "Code", render: (currency) => currency.code },
    { key: "name", header: "Name", render: (currency) => currency.name },
    { key: "minorUnitPrecision", header: "Minor unit precision", render: (currency) => currency.minorUnitPrecision },
    {
      key: "isActive",
      header: "Active",
      render: (currency) => <StatusBadge tone={currency.isActive ? "success" : "neutral"} label={currency.isActive ? "Active" : "Inactive"} />,
    },
  ];

  return (
    <div className="flex flex-col gap-6">
      <div>
        <h1 className="text-xl font-semibold text-text-primary">Currency and Exchange Rates</h1>
        <p className="text-sm text-text-secondary">Governed currency registry and versioned, deterministic exchange-rate quotes. A missing or unapproved rate blocks conversion -- never a silent default.</p>
      </div>

      <div>
        <h2 className="mb-2 text-sm font-semibold text-text-primary">Governed currencies</h2>
        {loadFailed ? (
          <ErrorState description="Something went wrong loading currencies. Please try again." />
        ) : (
          <DataTable caption="Currencies" columns={currencyColumns} rows={currencies} rowKey={(currency) => currency.code} emptyMessage="No currencies registered." />
        )}
      </div>

      <div>
        <h2 className="mb-2 text-sm font-semibold text-text-primary">Exchange rates</h2>
        {loadFailed ? (
          <ErrorState description="Something went wrong loading exchange rates. Please try again." />
        ) : rates.length === 0 ? (
          <EmptyState title="No exchange rates yet" description="Create a draft rate below." />
        ) : (
          <DataTable caption="Exchange rates" columns={rateColumns} rows={rates} rowKey={(rate) => rate.id} emptyMessage="No rates yet." />
        )}
      </div>

      <CreateFinanceExchangeRateDraftForm action={createFinanceExchangeRateDraftAction.bind(null, tenantSlug)} />
      <ConvertFinanceAmountForm action={convertFinanceAmountAction.bind(null, tenantSlug)} />
    </div>
  );
}
