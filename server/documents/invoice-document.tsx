/**
 * Invoice PDF layout (audit remediation A7, fourth printable document after
 * surat jalan, POD, and purchase order). Built entirely on already-existing,
 * already-tested read queries (`getFinanceInvoice`, `getFinanceInvoiceLines`,
 * `getAccountById`) plus one new single-record read this checkpoint adds
 * (`app.get_finance_invoice`, mirroring `app.get_finance_invoice_lines`'s own
 * shape) -- no schema redesign, no touch on B3 (credit notes)/B4
 * (multi-currency), both of which remain fully deferred.
 *
 * A pure presentation component, mirroring purchase-order-document.tsx
 * exactly: takes an already-assembled `InvoiceData` plain object, zero
 * database/RPC knowledge.
 */

import ReactPDF from "@react-pdf/renderer";

const { Document, Page, View, Text, StyleSheet } = ReactPDF;

export interface InvoiceLineData {
  readonly lineNo: number;
  readonly lineType: "charge" | "tax";
  readonly description: string;
  readonly amount: number;
}

export interface InvoiceData {
  readonly tenantLabel: string;
  readonly sellerTaxId: string | null;
  readonly invoiceNumber: string | null;
  readonly printedAt: string;
  readonly status: string;
  readonly billToName: string;
  readonly billToTaxId: string | null;
  readonly billToAddress: string | null;
  readonly currency: string;
  readonly issueDate: string | null;
  readonly dueDate: string | null;
  readonly paymentTermDays: number;
  readonly subtotalAmount: number;
  readonly taxAmount: number;
  readonly withholdingTaxAmount: number;
  readonly totalAmount: number;
  readonly lines: readonly InvoiceLineData[];
  readonly issuedAt: string | null;
  readonly issuedBy: string | null;
}

const styles = StyleSheet.create({
  page: { padding: 32, fontSize: 9, fontFamily: "Helvetica", color: "#111827" },
  headerRow: { flexDirection: "row", justifyContent: "space-between", alignItems: "flex-start", marginBottom: 12, borderBottom: "1pt solid #111827", paddingBottom: 8 },
  tenantLabel: { fontSize: 12, fontWeight: 700 },
  sellerMeta: { fontSize: 9, color: "#4b5563", marginTop: 2 },
  title: { fontSize: 16, fontWeight: 700, textAlign: "right" },
  meta: { fontSize: 9, textAlign: "right", color: "#4b5563" },
  section: { marginBottom: 10 },
  sectionTitle: { fontSize: 10, fontWeight: 700, marginBottom: 4, textTransform: "uppercase" },
  twoColumn: { flexDirection: "row", gap: 16 },
  column: { flex: 1 },
  labelValueRow: { flexDirection: "row", marginBottom: 2 },
  label: { width: 120, color: "#4b5563" },
  value: { flex: 1 },
  table: { borderTop: "1pt solid #d1d5db", borderLeft: "1pt solid #d1d5db", marginTop: 4 },
  tableRow: { flexDirection: "row" },
  lineNoCell: { width: 24, padding: 4, borderRight: "1pt solid #d1d5db", borderBottom: "1pt solid #d1d5db" },
  typeCell: { width: 48, padding: 4, borderRight: "1pt solid #d1d5db", borderBottom: "1pt solid #d1d5db" },
  descriptionCell: { flex: 3, padding: 4, borderRight: "1pt solid #d1d5db", borderBottom: "1pt solid #d1d5db" },
  amountCell: { flex: 1, padding: 4, borderRight: "1pt solid #d1d5db", borderBottom: "1pt solid #d1d5db", textAlign: "right" },
  tableCellHeader: { fontWeight: 700, backgroundColor: "#f3f4f6" },
  totalsBlock: { marginTop: 8, alignSelf: "flex-end", width: 220 },
  totalsRow: { flexDirection: "row", justifyContent: "space-between", marginBottom: 2 },
  totalsLabel: { color: "#4b5563" },
  totalsValueEmphasis: { fontWeight: 700 },
  signatureRow: { flexDirection: "row", marginTop: 32, gap: 16 },
  signatureBlock: { flex: 1, textAlign: "center" },
  signatureLine: { borderTop: "1pt solid #111827", marginTop: 48, paddingTop: 4 },
});

function formatAmount(currency: string, amount: number): string {
  return `${currency} ${amount.toLocaleString()}`.trim();
}

export function InvoiceDocument({ data }: { data: InvoiceData }) {
  return (
    <Document title={`Invoice ${data.invoiceNumber ?? "(unissued)"}`}>
      <Page size="A4" style={styles.page}>
        <View style={styles.headerRow}>
          <View>
            <Text style={styles.tenantLabel}>{data.tenantLabel}</Text>
            {data.sellerTaxId ? <Text style={styles.sellerMeta}>Tax ID: {data.sellerTaxId}</Text> : null}
          </View>
          <View>
            <Text style={styles.title}>INVOICE</Text>
            <Text style={styles.meta}>No. {data.invoiceNumber ?? "(unissued)"}</Text>
            <Text style={styles.meta}>Status: {data.status}</Text>
            <Text style={styles.meta}>Printed: {data.printedAt}</Text>
          </View>
        </View>

        <View style={[styles.section, styles.twoColumn]}>
          <View style={styles.column}>
            <Text style={styles.sectionTitle}>Bill to</Text>
            <Text style={{ marginBottom: 4, fontWeight: 700 }}>{data.billToName}</Text>
            {data.billToTaxId ? (
              <View style={styles.labelValueRow}>
                <Text style={styles.label}>Tax ID</Text>
                <Text style={styles.value}>{data.billToTaxId}</Text>
              </View>
            ) : null}
            <View style={styles.labelValueRow}>
              <Text style={styles.label}>Address</Text>
              <Text style={styles.value}>{data.billToAddress ?? "—"}</Text>
            </View>
          </View>
          <View style={styles.column}>
            <Text style={styles.sectionTitle}>Details</Text>
            <View style={styles.labelValueRow}>
              <Text style={styles.label}>Currency</Text>
              <Text style={styles.value}>{data.currency}</Text>
            </View>
            <View style={styles.labelValueRow}>
              <Text style={styles.label}>Issue date</Text>
              <Text style={styles.value}>{data.issueDate ?? "—"}</Text>
            </View>
            <View style={styles.labelValueRow}>
              <Text style={styles.label}>Due date</Text>
              <Text style={styles.value}>{data.dueDate ?? "—"}</Text>
            </View>
            <View style={styles.labelValueRow}>
              <Text style={styles.label}>Payment terms</Text>
              <Text style={styles.value}>{data.paymentTermDays} days</Text>
            </View>
          </View>
        </View>

        <View style={styles.section}>
          <Text style={styles.sectionTitle}>Line items</Text>
          <View style={styles.table}>
            <View style={styles.tableRow}>
              <Text style={[styles.lineNoCell, styles.tableCellHeader]}>#</Text>
              <Text style={[styles.typeCell, styles.tableCellHeader]}>Type</Text>
              <Text style={[styles.descriptionCell, styles.tableCellHeader]}>Description</Text>
              <Text style={[styles.amountCell, styles.tableCellHeader]}>Amount</Text>
            </View>
            {data.lines.map((line) => (
              <View key={line.lineNo} style={styles.tableRow}>
                <Text style={styles.lineNoCell}>{line.lineNo}</Text>
                <Text style={styles.typeCell}>{line.lineType}</Text>
                <Text style={styles.descriptionCell}>{line.description}</Text>
                <Text style={styles.amountCell}>{formatAmount(data.currency, line.amount)}</Text>
              </View>
            ))}
          </View>
        </View>

        <View style={styles.totalsBlock}>
          <View style={styles.totalsRow}>
            <Text style={styles.totalsLabel}>Subtotal</Text>
            <Text>{formatAmount(data.currency, data.subtotalAmount)}</Text>
          </View>
          <View style={styles.totalsRow}>
            <Text style={styles.totalsLabel}>Tax</Text>
            <Text>{formatAmount(data.currency, data.taxAmount)}</Text>
          </View>
          <View style={styles.totalsRow}>
            <Text style={[styles.totalsLabel, styles.totalsValueEmphasis]}>Total</Text>
            <Text style={styles.totalsValueEmphasis}>{formatAmount(data.currency, data.totalAmount)}</Text>
          </View>
          {data.withholdingTaxAmount > 0 ? (
            <>
              <View style={styles.totalsRow}>
                <Text style={styles.totalsLabel}>Less: withholding tax</Text>
                <Text>-{formatAmount(data.currency, data.withholdingTaxAmount)}</Text>
              </View>
              <View style={styles.totalsRow}>
                <Text style={[styles.totalsLabel, styles.totalsValueEmphasis]}>Net amount due</Text>
                <Text style={styles.totalsValueEmphasis}>{formatAmount(data.currency, data.totalAmount - data.withholdingTaxAmount)}</Text>
              </View>
            </>
          ) : null}
        </View>

        {data.withholdingTaxAmount > 0 ? (
          <Text style={{ marginTop: 4, fontSize: 8, color: "#4b5563" }}>
            Withholding tax is deducted at source by the customer and remitted directly to the tax authority; please provide the
            corresponding bukti potong (withholding tax certificate) for this amount.
          </Text>
        ) : null}

        <View style={styles.signatureRow}>
          <View style={styles.signatureBlock}>
            <Text>Issued by</Text>
            <Text style={styles.signatureLine}>{data.issuedBy ?? "Name & Signature"}</Text>
            {data.issuedAt ? <Text style={{ marginTop: 2, color: "#4b5563" }}>{data.issuedAt}</Text> : null}
          </View>
          <View style={styles.signatureBlock}>
            <Text>Received by (customer)</Text>
            <Text style={styles.signatureLine}>Name &amp; Signature</Text>
          </View>
        </View>
      </Page>
    </Document>
  );
}
