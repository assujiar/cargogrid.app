import type { Quotation } from "../../../../../../server/contracts/quotation/quotation.ts";
import type { QuotationAcceptanceToken } from "../../../../../../server/contracts/quotation/quotation-acceptance.ts";
import { SendAcceptanceForm } from "./send-acceptance-form.tsx";
import { revokeQuotationAcceptanceTokenAction } from "./actions.ts";
import { DataTable, type DataTableColumn } from "../../../../../../components/tables/data-table.tsx";
import { StatusBadge } from "../../../../../../components/ui/status-badge.tsx";
import { QUOTATION_ACCEPTANCE_TOKEN_STATUS_TONE_MAP } from "../../../../../../components/domain/status-tone-map.ts";

/**
 * Customer Acceptance panel (COM-154, CG-S7-COM-013, Prompt 154 §15: "send confirmation/
 * status"). Renders only for an acceptance-eligible quotation (status=submitted,
 * approvalStatus approved/not_required, isCurrent) or one that already carries send/
 * decision history -- a draft or superseded version has nothing to show here. The
 * customer's own decision surface is the separate public `/quote-decision/[token]` route
 * (app/(public)/), never rendered inside this authenticated portal.
 */
export function CustomerAcceptancePanel({
  tenantSlug,
  quotation,
  tokens,
  contacts,
}: {
  tenantSlug: string;
  quotation: Quotation;
  tokens: QuotationAcceptanceToken[];
  contacts: readonly { id: string; fullName: string; email: string | null }[];
}) {
  const eligible = quotation.status === "submitted" && quotation.isCurrent && (quotation.approvalStatus === "approved" || quotation.approvalStatus === "not_required") && quotation.customerDecision === null;

  if (!eligible && tokens.length === 0 && quotation.customerDecision === null) {
    return null;
  }

  const activeToken = tokens.find((token) => token.status === "active") ?? null;

  const tokenColumns: readonly DataTableColumn<QuotationAcceptanceToken>[] = [
    { key: "sent", header: "Sent", render: (token) => new Date(token.sentAt).toLocaleString() },
    { key: "channel", header: "Channel", render: (token) => token.channel },
    {
      key: "status",
      header: "Status",
      render: (token) => {
        const { tone, label } = QUOTATION_ACCEPTANCE_TOKEN_STATUS_TONE_MAP[token.status];
        return <StatusBadge tone={tone} label={label} />;
      },
    },
    { key: "expires", header: "Expires", render: (token) => new Date(token.expiresAt).toLocaleString() },
    {
      key: "action",
      header: "Action",
      render: (token) =>
        token.status === "active" ? (
          <form action={revokeQuotationAcceptanceTokenAction.bind(null, tenantSlug, quotation.id, token.id, "Revoked by sender")}>
            <button type="submit" className="text-sm font-medium text-danger underline">
              Revoke
            </button>
          </form>
        ) : (
          "—"
        ),
    },
  ];

  return (
    <div className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
      <h2 className="text-sm font-semibold text-neutral-900">Customer acceptance</h2>

      {quotation.customerDecision ? (
        <p className="text-sm text-neutral-900">
          Customer decision: <span className="font-medium">{quotation.customerDecision}</span>
          {quotation.customerDecisionAt ? ` on ${new Date(quotation.customerDecisionAt).toLocaleString()}` : ""}
        </p>
      ) : null}

      {tokens.length > 0 ? (
        <div className="flex flex-col gap-1">
          <h3 className="text-xs font-semibold uppercase tracking-wide text-neutral-500">Send history</h3>
          <DataTable
            caption="Customer acceptance send history"
            columns={tokenColumns}
            rows={tokens}
            rowKey={(token) => token.id}
            emptyMessage="No send history yet."
          />
        </div>
      ) : null}

      {eligible ? <SendAcceptanceForm tenantSlug={tenantSlug} quotationId={quotation.id} hasActiveToken={activeToken !== null} contacts={contacts} /> : null}
    </div>
  );
}
