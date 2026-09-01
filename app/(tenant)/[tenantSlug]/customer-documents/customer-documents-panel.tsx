import Link from "next/link";
import { StatusBadge, type StatusTone } from "../../../../components/ui/status-badge.tsx";
import { EmptyState } from "../../../../components/ui/empty-state.tsx";
import { Select } from "../../../../components/forms/select.tsx";
import { Input } from "../../../../components/forms/input.tsx";
import { CUSTOMER_DOCUMENT_SOURCE_MODULES, type CustomerDocument, type CustomerDocumentSourceModule } from "../../../../server/contracts/customer-document/customer-document.ts";
import type { CustomerPortalScopeContextRow } from "../../../../server/contracts/customer-portal-scope/customer-portal-scope.ts";
import type { CustomerDocumentActionState } from "./actions.ts";
import { CustomerDocumentDownloadForm } from "./customer-document-download-form.tsx";

const SOURCE_MODULE_LABEL: Record<CustomerDocumentSourceModule, string> = {
  quote_request: "Quote request",
  epod: "Delivery evidence (ePOD)",
  invoice: "Invoice",
  ticket: "Ticket",
};

const SCAN_STATUS_TONE: Record<string, StatusTone> = {
  clean: "success",
  pending: "neutral",
  infected: "danger",
  error: "warning",
};

const SCAN_STATUS_LABEL: Record<string, string> = {
  clean: "Verified clean",
  pending: "Scanning",
  infected: "Quarantined",
  error: "Scan error",
};

export interface CustomerDocumentFilterValues {
  readonly sourceModule: string;
  readonly accountId: string;
  readonly dateFrom: string;
  readonly dateTo: string;
}

function formatSize(sizeBytes: number): string {
  return sizeBytes >= 1024 * 1024 ? `${(sizeBytes / (1024 * 1024)).toFixed(1)} MB` : `${Math.ceil(sizeBytes / 1024)} KB`;
}

/**
 * A document link grants no access to its source record or any other linked
 * document (business rule 4) -- this navigable link is honest, not a
 * disclosure widener: the destination page independently re-authorizes
 * scope through its own RPC (getCustomerQuoteRequest / the customer-
 * shipments detail page), never trusting anything carried in this URL.
 */
function sourceLink(tenantSlug: string, doc: CustomerDocument): string | null {
  if (doc.sourceModule === "quote_request") return `/${tenantSlug}/customer-quotes/${doc.sourceEntityId}`;
  if (doc.sourceModule === "epod") return `/${tenantSlug}/customer-shipments/${doc.sourceEntityId}`;
  return null;
}

function DocumentRow({
  tenantSlug,
  doc,
  accountName,
  downloadAction,
}: {
  tenantSlug: string;
  doc: CustomerDocument;
  accountName: string;
  downloadAction: (documentId: string, prevState: CustomerDocumentActionState, formData: FormData) => Promise<CustomerDocumentActionState>;
}) {
  const link = sourceLink(tenantSlug, doc);
  return (
    <tr className="border-t border-neutral-100">
      <td className="p-2 text-sm">
        <p className="font-medium text-neutral-900">{doc.originalFilename}</p>
        <p className="text-xs text-neutral-500">
          {SOURCE_MODULE_LABEL[doc.sourceModule]} · {doc.documentType.replaceAll("_", " ")} · {formatSize(doc.sizeBytes)}
        </p>
      </td>
      <td className="p-2 text-xs text-neutral-500">{accountName}</td>
      <td className="p-2 text-sm">
        <StatusBadge tone={SCAN_STATUS_TONE[doc.malwareScanStatus] ?? "neutral"} label={SCAN_STATUS_LABEL[doc.malwareScanStatus] ?? doc.malwareScanStatus} />
      </td>
      <td className="p-2 text-xs text-neutral-500">{new Date(doc.createdAt).toLocaleString()}</td>
      <td className="p-2 text-xs text-neutral-500">
        {link ? (
          <Link href={link} className="text-primary underline">
            View source
          </Link>
        ) : (
          "—"
        )}
      </td>
      <td className="p-2">
        <CustomerDocumentDownloadForm downloadable={doc.malwareScanStatus === "clean"} action={downloadAction.bind(null, doc.documentId)} />
      </td>
    </tr>
  );
}

export function CustomerDocumentsPanel({
  tenantSlug,
  accounts,
  documents,
  filters,
  downloadAction,
}: {
  tenantSlug: string;
  accounts: readonly CustomerPortalScopeContextRow[];
  documents: readonly CustomerDocument[];
  filters: CustomerDocumentFilterValues;
  downloadAction: (documentId: string, prevState: CustomerDocumentActionState, formData: FormData) => Promise<CustomerDocumentActionState>;
}) {
  const accountNameById = new Map(accounts.map((a) => [a.accountId, a.accountName]));
  const stubSelected = filters.sourceModule === "invoice" || filters.sourceModule === "ticket";

  return (
    <div className="flex flex-col gap-4">
      <form method="get" className="flex flex-wrap items-end gap-3 rounded-md border border-neutral-200 p-3">
        <div className="flex flex-col gap-1">
          <label htmlFor="sourceModule" className="text-xs font-medium text-neutral-600">
            Source
          </label>
          <Select id="sourceModule" name="sourceModule" defaultValue={filters.sourceModule}>
            <option value="">All sources</option>
            {CUSTOMER_DOCUMENT_SOURCE_MODULES.map((m) => (
              <option key={m} value={m}>
                {SOURCE_MODULE_LABEL[m]}
              </option>
            ))}
          </Select>
        </div>
        <div className="flex flex-col gap-1">
          <label htmlFor="accountId" className="text-xs font-medium text-neutral-600">
            Account
          </label>
          <Select id="accountId" name="accountId" defaultValue={filters.accountId}>
            <option value="">All accounts</option>
            {accounts.map((a) => (
              <option key={a.accountId} value={a.accountId}>
                {a.accountName}
              </option>
            ))}
          </Select>
        </div>
        <div className="flex flex-col gap-1">
          <label htmlFor="dateFrom" className="text-xs font-medium text-neutral-600">
            From
          </label>
          <Input id="dateFrom" type="date" name="dateFrom" defaultValue={filters.dateFrom} />
        </div>
        <div className="flex flex-col gap-1">
          <label htmlFor="dateTo" className="text-xs font-medium text-neutral-600">
            To
          </label>
          <Input id="dateTo" type="date" name="dateTo" defaultValue={filters.dateTo} />
        </div>
        <button type="submit" className="rounded bg-primary px-3 py-1.5 text-sm font-medium text-neutral-50">
          Apply filters
        </button>
        <Link href={`/${tenantSlug}/customer-documents`} className="text-xs text-neutral-500 underline">
          Clear filters
        </Link>
      </form>

      {stubSelected ? (
        <p className="text-xs text-neutral-500">
          {SOURCE_MODULE_LABEL[filters.sourceModule as CustomerDocumentSourceModule]} documents aren&apos;t available yet -- this filter is recognized and will populate once that capability ships.
        </p>
      ) : null}

      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Your documents</h2>
        {documents.length === 0 ? (
          <EmptyState
            title="No documents found"
            description={stubSelected ? "This source has no documents yet." : "Documents from your quote request attachments and delivery evidence will appear here."}
          />
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full border-collapse">
              <thead>
                <tr className="text-left text-xs font-medium text-neutral-500">
                  <th className="p-2">Document</th>
                  <th className="p-2">Account</th>
                  <th className="p-2">Scan status</th>
                  <th className="p-2">Added</th>
                  <th className="p-2">Source</th>
                  <th className="p-2">Action</th>
                </tr>
              </thead>
              <tbody>
                {documents.map((doc) => (
                  <DocumentRow key={doc.documentId} tenantSlug={tenantSlug} doc={doc} accountName={accountNameById.get(doc.accountId) ?? "—"} downloadAction={downloadAction} />
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>
    </div>
  );
}
