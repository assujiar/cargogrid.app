/**
 * Invoice generation (audit remediation A7). Assembles an `InvoiceData` from
 * `getFinanceInvoice` (this checkpoint's own new single-record read, mirroring
 * app.get_finance_invoice_lines' shape) plus the already-existing
 * `getFinanceInvoiceLines` and `getAccountById` -- no new schema beyond the
 * one read RPC, no touch on B3 (credit notes)/B4 (multi-currency), both fully
 * deferred. Renders to a PDF buffer via `@react-pdf/renderer`, the exact
 * pattern established for surat jalan/POD/purchase order.
 *
 * Bill-to address: `app.accounts.billing_address` is a free-form JSONB
 * object (no fixed shape, ADR-0018's own disclosed reasoning) -- picks
 * common street/city/province/postalCode/country keys defensively, same
 * "best available, never an error" posture generate-purchase-order.server.ts's
 * own pickVendorAddress already established for a differently-shaped source.
 */

import { createElement } from "react";
import { renderToBuffer } from "@react-pdf/renderer";
import { getFinanceInvoice, getFinanceInvoiceLines, InvoiceQueryError, type InvoiceQueryRpcClient } from "../queries/invoice.ts";
import { getAccountById, AccountQueryError, type AccountQueryClient } from "../queries/account.ts";
import { InvoiceDocument, type InvoiceData, type InvoiceLineData } from "./invoice-document.tsx";
import type { FinanceInvoice, FinanceInvoiceLine } from "../contracts/invoice/invoice.ts";

export class InvoiceGenerationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "InvoiceGenerationError";
  }
}

type InvoiceGenerationClient = InvoiceQueryRpcClient & AccountQueryClient;

function formatDate(value: string | null): string | null {
  if (!value) return null;
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) return value;
  return parsed.toLocaleDateString("id-ID", { dateStyle: "medium" });
}

function formatPrintedAt(value: string): string {
  return new Date(value).toLocaleString("id-ID", { dateStyle: "medium", timeStyle: "short" });
}

function pickBillToAddress(billingAddress: Record<string, unknown>): string | null {
  const asString = (key: string): string | null => {
    const value = billingAddress[key];
    return typeof value === "string" && value.length > 0 ? value : null;
  };
  const parts = [asString("street"), asString("city"), asString("province"), asString("postalCode"), asString("country")].filter((part): part is string => part !== null);
  return parts.length > 0 ? parts.join(", ") : null;
}

function toInvoiceLineData(line: FinanceInvoiceLine): InvoiceLineData {
  return { lineNo: line.lineNumber, lineType: line.lineType, description: line.description, amount: line.amount };
}

async function buildInvoiceData(client: InvoiceGenerationClient, tenantLabel: string, invoice: FinanceInvoice, lines: readonly FinanceInvoiceLine[], actorAuthUserId: string): Promise<InvoiceData> {
  const account = await getAccountById(client, invoice.customerAccountId, actorAuthUserId);

  return {
    tenantLabel,
    invoiceNumber: invoice.invoiceNumber,
    printedAt: formatPrintedAt(new Date().toISOString()),
    status: invoice.status,
    billToName: account?.legalName ?? invoice.customerAccountId,
    billToTaxId: account?.taxId ?? null,
    billToAddress: account ? pickBillToAddress(account.billingAddress) : null,
    currency: invoice.currency,
    issueDate: formatDate(invoice.issueDate),
    dueDate: formatDate(invoice.dueDate),
    paymentTermDays: invoice.paymentTermDays,
    subtotalAmount: invoice.subtotalAmount,
    taxAmount: invoice.taxAmount,
    withholdingTaxAmount: invoice.withholdingTaxAmount,
    totalAmount: invoice.totalAmount,
    lines: lines.map(toInvoiceLineData),
    issuedAt: formatDate(invoice.issuedAt),
    issuedBy: invoice.issuedBy,
  };
}

/** Fetches the invoice (throws InvoiceGenerationError for not-found/insufficient-authority) and every piece of data its printable needs, then renders a PDF buffer. */
export async function generateInvoicePdf(client: InvoiceGenerationClient, tenantLabel: string, invoiceId: string, actorAuthUserId: string): Promise<{ invoice: FinanceInvoice; pdfBuffer: Buffer }> {
  let invoice: FinanceInvoice;
  let lines: FinanceInvoiceLine[];
  try {
    invoice = await getFinanceInvoice(client, { invoiceId, actorAuthUserId });
    lines = await getFinanceInvoiceLines(client, { invoiceId, actorAuthUserId });
  } catch (error) {
    if (error instanceof InvoiceQueryError) throw new InvoiceGenerationError(error.message);
    throw error;
  }

  let data: InvoiceData;
  try {
    data = await buildInvoiceData(client, tenantLabel, invoice, lines, actorAuthUserId);
  } catch (error) {
    if (error instanceof AccountQueryError) throw new InvoiceGenerationError(error.message);
    throw error;
  }

  const pdfBuffer = await renderToBuffer(createElement(InvoiceDocument, { data }) as unknown as Parameters<typeof renderToBuffer>[0]);
  return { invoice, pdfBuffer };
}
