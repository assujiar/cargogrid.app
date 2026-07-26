import { Banner } from "../../../../../components/ui/banner.tsx";
import { StatusBadge, type StatusTone } from "../../../../../components/ui/status-badge.tsx";
import { DataTable, type DataTableColumn } from "../../../../../components/tables/data-table.tsx";
import {
  MOCK_LEAD_STATUSES,
  MOCK_OPPORTUNITY_STAGES,
  MOCK_QUOTATION_APPROVAL,
  MOCK_MARGIN_WARNING,
  MOCK_CREDIT_HOLD,
  MOCK_CONTRACT_EXPIRY,
  MOCK_RATE_VALIDITY,
  MOCK_JOB_ORDER_HANDOFF,
  MOCK_ACCOUNT_HEADER,
  MOCK_PIPELINE_ROWS,
  MOCK_APPROVAL_TIMELINE,
} from "../../../../../lib/design-system/mock-business-data.ts";

const LEAD_STATUS_TONE: Record<(typeof MOCK_LEAD_STATUSES)[number]["status"], StatusTone> = {
  new: "info",
  qualified: "success",
  disqualified: "neutral",
};

const OPPORTUNITY_STAGE_TONE: Record<(typeof MOCK_OPPORTUNITY_STAGES)[number]["stage"], StatusTone> = {
  prospecting: "neutral",
  negotiation: "warning",
  closed_won: "success",
  closed_lost: "danger",
};

const ACCOUNT_STATUS_TONE: Record<string, StatusTone> = { active: "success", inactive: "neutral" };
const CREDIT_STATUS_TONE: Record<string, StatusTone> = { cleared: "success", hold: "danger", pending: "warning" };

type PipelineRow = (typeof MOCK_PIPELINE_ROWS)[number];

const PIPELINE_COLUMNS: readonly DataTableColumn<PipelineRow>[] = [
  { key: "name", header: "Opportunity", render: (row) => row.name },
  {
    key: "stage",
    header: "Stage",
    render: (row) => <StatusBadge tone={OPPORTUNITY_STAGE_TONE[row.stage as keyof typeof OPPORTUNITY_STAGE_TONE]} label={row.stage.replace("_", " ")} />,
  },
  { key: "owner", header: "Owner", render: (row) => row.owner },
  { key: "value", header: "Value", align: "right", render: (row) => row.value },
];

/**
 * Real CargoGrid usage examples, mock data only (CargoGrid UI Modernization checkpoint
 * 3). Every mapping below (e.g. lead status → StatusBadge tone) is an example of the
 * domain-specific composition `components/domain/` would own once built — it is not a
 * real shared utility today, and is not presented as one.
 */
export default function DomainExamplesPage() {
  return (
    <div className="flex flex-col gap-8">
      <div>
        <h1 className="text-xl font-semibold">Real business examples</h1>
        <p className="mt-1 text-sm text-[var(--ds-text-secondary)]">
          Mock data only — never connected to production data or a live query. Built entirely from the 6 real shared
          primitives plus plain semantic-token markup where no shared primitive exists yet (Card, Timeline).
        </p>
      </div>

      <section className="flex flex-col gap-2">
        <h2 className="text-base font-semibold">Lead status badge</h2>
        <div className="flex flex-wrap gap-3">
          {MOCK_LEAD_STATUSES.map((lead) => (
            <div key={lead.contactName} className="flex items-center gap-2 rounded-md border border-[var(--ds-border)] p-2 text-sm">
              <span>
                {lead.contactName} — {lead.company}
              </span>
              <StatusBadge tone={LEAD_STATUS_TONE[lead.status]} label={lead.status} />
            </div>
          ))}
        </div>
      </section>

      <section className="flex flex-col gap-2">
        <h2 className="text-base font-semibold">Opportunity probability badge</h2>
        <div className="flex flex-wrap gap-3">
          {MOCK_OPPORTUNITY_STAGES.map((opp) => (
            <div key={opp.name} className="flex items-center gap-2 rounded-md border border-[var(--ds-border)] p-2 text-sm">
              <span>{opp.name}</span>
              <StatusBadge tone={OPPORTUNITY_STAGE_TONE[opp.stage]} label={`${opp.stage.replace("_", " ")} — ${opp.probability}%`} />
            </div>
          ))}
        </div>
      </section>

      <section className="flex flex-col gap-2">
        <h2 className="text-base font-semibold">Quotation approval card</h2>
        <p className="text-xs text-[var(--ds-text-secondary)]">No Card primitive exists yet — plain semantic-token markup, consistent with real Commercial screens today.</p>
        <div className="max-w-sm rounded-md border border-[var(--ds-border)] bg-[var(--ds-surface)] p-4 shadow-sm">
          <div className="flex items-center justify-between">
            <span className="font-semibold">{MOCK_QUOTATION_APPROVAL.quotationNumber}</span>
            <StatusBadge tone="warning" label="Pending approval" />
          </div>
          <dl className="mt-2 grid grid-cols-2 gap-1 text-xs text-[var(--ds-text-secondary)]">
            <dt>Customer</dt>
            <dd>{MOCK_QUOTATION_APPROVAL.customer}</dd>
            <dt>Total</dt>
            <dd>{MOCK_QUOTATION_APPROVAL.totalAmount}</dd>
            <dt>Margin</dt>
            <dd>{MOCK_QUOTATION_APPROVAL.marginPercent}%</dd>
            <dt>Submitted by</dt>
            <dd>{MOCK_QUOTATION_APPROVAL.submittedBy}</dd>
          </dl>
        </div>
      </section>

      <section className="flex flex-col gap-2">
        <h2 className="text-base font-semibold">Margin warning alert</h2>
        <Banner variant="warning">
          {MOCK_MARGIN_WARNING.quotationNumber}: margin is {MOCK_MARGIN_WARNING.marginPercent}%, below the account&apos;s
          minimum of {MOCK_MARGIN_WARNING.minimumMarginPercent}%.
        </Banner>
      </section>

      <section className="flex flex-col gap-2">
        <h2 className="text-base font-semibold">Credit hold notification</h2>
        <Banner variant="danger">
          {MOCK_CREDIT_HOLD.accountName} is on credit hold (checked {MOCK_CREDIT_HOLD.checkedAt}) — new quotations require
          an override.
        </Banner>
      </section>

      <section className="flex flex-col gap-2">
        <h2 className="text-base font-semibold">Contract expiry banner</h2>
        <Banner variant="warning">
          Contract {MOCK_CONTRACT_EXPIRY.contractNumber} ({MOCK_CONTRACT_EXPIRY.customer}) expires on{" "}
          {MOCK_CONTRACT_EXPIRY.expiresOn} ({MOCK_CONTRACT_EXPIRY.daysRemaining} days remaining).
        </Banner>
      </section>

      <section className="flex flex-col gap-2">
        <h2 className="text-base font-semibold">Rate validity indicator</h2>
        <div className="flex items-center gap-2 text-sm">
          <span>{MOCK_RATE_VALIDITY.rateVersion}</span>
          <StatusBadge tone="success" label={`Active — valid ${MOCK_RATE_VALIDITY.validFrom} to ${MOCK_RATE_VALIDITY.validTo}`} />
        </div>
      </section>

      <section className="flex flex-col gap-2">
        <h2 className="text-base font-semibold">Job Order handoff summary</h2>
        <div className="max-w-sm rounded-md border border-[var(--ds-border)] bg-[var(--ds-surface)] p-4">
          <p className="font-semibold">{MOCK_JOB_ORDER_HANDOFF.quotationNumber}</p>
          <dl className="mt-2 grid grid-cols-2 gap-1 text-xs text-[var(--ds-text-secondary)]">
            <dt>Customer</dt>
            <dd>{MOCK_JOB_ORDER_HANDOFF.customer}</dd>
            <dt>Accepted</dt>
            <dd>{MOCK_JOB_ORDER_HANDOFF.acceptedAt}</dd>
            <dt>Contract</dt>
            <dd>{MOCK_JOB_ORDER_HANDOFF.contractLinked ? "Linked" : "None"}</dd>
            <dt>Credit</dt>
            <dd>
              <StatusBadge tone="success" label={MOCK_JOB_ORDER_HANDOFF.creditOutcome} />
            </dd>
          </dl>
        </div>
      </section>

      <section className="flex flex-col gap-2">
        <h2 className="text-base font-semibold">Customer account header</h2>
        <div className="flex flex-wrap items-center gap-3 rounded-md border border-[var(--ds-border)] bg-[var(--ds-surface)] p-3">
          <span className="font-semibold">{MOCK_ACCOUNT_HEADER.accountName}</span>
          <StatusBadge tone={ACCOUNT_STATUS_TONE[MOCK_ACCOUNT_HEADER.status] ?? "neutral"} label={MOCK_ACCOUNT_HEADER.status} />
          <StatusBadge
            tone={CREDIT_STATUS_TONE[MOCK_ACCOUNT_HEADER.creditStatus] ?? "neutral"}
            label={`Credit: ${MOCK_ACCOUNT_HEADER.creditStatus}`}
          />
          <span className="text-xs text-[var(--ds-text-secondary)]">Owner: {MOCK_ACCOUNT_HEADER.owner}</span>
        </div>
        <p className="text-xs text-[var(--ds-text-secondary)]">
          No shared Summary Header / Workspace Header primitive exists yet (docs/design-system/03_LAYOUT_NAVIGATION.md
          §1) — every real detail page still builds its own ad hoc header.
        </p>
      </section>

      <section className="flex flex-col gap-2">
        <h2 className="text-base font-semibold">Pipeline table row</h2>
        <DataTable
          caption="Mock pipeline"
          columns={PIPELINE_COLUMNS}
          rows={MOCK_PIPELINE_ROWS}
          rowKey={(row) => row.name}
          emptyMessage="No opportunities."
        />
      </section>

      <section className="flex flex-col gap-2">
        <h2 className="text-base font-semibold">Approval timeline</h2>
        <p className="text-xs text-[var(--ds-text-secondary)]">No Timeline primitive exists yet — plain ordered list.</p>
        <ol className="flex flex-col gap-2 border-l-2 border-[var(--ds-border)] pl-4 text-sm">
          {MOCK_APPROVAL_TIMELINE.map((event) => (
            <li key={event.at}>
              <span className="text-xs text-[var(--ds-text-secondary)]">{new Date(event.at).toLocaleString()}</span>
              <p>
                <strong>{event.actor}</strong> — {event.event}
              </p>
            </li>
          ))}
        </ol>
      </section>
    </div>
  );
}
