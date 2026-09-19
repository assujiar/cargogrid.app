/**
 * Purchase Order PDF layout (audit remediation A7, third printable document
 * after surat jalan and POD; `docs/audit/2026-09-02-independent-launch-
 * readiness-audit.md` finding A7's own remaining list: "invoice, faktur pajak,
 * packing list, POD (done) or purchase order"). Built entirely on already-
 * existing, already-tested read queries (`getPurchaseOrder`,
 * `listPurchaseOrderLines`, `getVendorProfile`) -- no new schema, no new RPC.
 *
 * A pure presentation component, mirroring surat-jalan-document.tsx/
 * pod-document.tsx exactly: takes an already-assembled `PurchaseOrderData`
 * plain object, zero database/RPC knowledge.
 *
 * `costMasked` (a real field on `app.purchase_orders`, PRC-260's own access
 * rule 26: a viewer without `PRC:View cost` sees every non-cost field but not
 * amounts/payment terms/commercial terms) is honored here exactly the way
 * `purchase-order-detail-panel.tsx` already renders it on-screen -- "Masked"
 * text, never a blank or a silently-substituted zero.
 */

import ReactPDF from "@react-pdf/renderer";

const { Document, Page, View, Text, StyleSheet } = ReactPDF;

export interface PurchaseOrderLineData {
  readonly lineNo: number;
  readonly description: string;
  readonly quantity: number | null;
  readonly uom: string | null;
  readonly notes: string | null;
}

export interface PurchaseOrderData {
  readonly tenantLabel: string;
  readonly poNumber: string;
  readonly version: number;
  readonly printedAt: string;
  readonly status: string;
  readonly vendorLegalName: string;
  readonly vendorCode: string;
  readonly vendorAddress: string | null;
  readonly currency: string | null;
  readonly subtotalAmount: number | null;
  readonly taxCode: string | null;
  readonly taxAmount: number | null;
  readonly totalAmount: number | null;
  readonly costMasked: boolean;
  readonly paymentTermDays: number | null;
  readonly expectedDeliveryDate: string | null;
  readonly servicePeriodStart: string | null;
  readonly servicePeriodEnd: string | null;
  readonly commercialTerms: string | null;
  readonly notes: string | null;
  readonly lines: readonly PurchaseOrderLineData[];
  readonly issuedAt: string | null;
  readonly issuedBy: string | null;
}

const styles = StyleSheet.create({
  page: { padding: 32, fontSize: 9, fontFamily: "Helvetica", color: "#111827" },
  headerRow: { flexDirection: "row", justifyContent: "space-between", alignItems: "flex-start", marginBottom: 12, borderBottom: "1pt solid #111827", paddingBottom: 8 },
  tenantLabel: { fontSize: 12, fontWeight: 700 },
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
  descriptionCell: { flex: 3, padding: 4, borderRight: "1pt solid #d1d5db", borderBottom: "1pt solid #d1d5db" },
  qtyCell: { flex: 1, padding: 4, borderRight: "1pt solid #d1d5db", borderBottom: "1pt solid #d1d5db", textAlign: "right" },
  uomCell: { flex: 1, padding: 4, borderRight: "1pt solid #d1d5db", borderBottom: "1pt solid #d1d5db" },
  notesCell: { flex: 2, padding: 4, borderRight: "1pt solid #d1d5db", borderBottom: "1pt solid #d1d5db" },
  tableCellHeader: { fontWeight: 700, backgroundColor: "#f3f4f6" },
  totalsBlock: { marginTop: 8, alignSelf: "flex-end", width: 220 },
  totalsRow: { flexDirection: "row", justifyContent: "space-between", marginBottom: 2 },
  totalsLabel: { color: "#4b5563" },
  totalsValueEmphasis: { fontWeight: 700 },
  signatureRow: { flexDirection: "row", marginTop: 32, gap: 16 },
  signatureBlock: { flex: 1, textAlign: "center" },
  signatureLine: { borderTop: "1pt solid #111827", marginTop: 48, paddingTop: 4 },
});

function formatAmount(currency: string | null, amount: number | null, masked: boolean): string {
  if (masked) return "Masked";
  if (amount === null) return "—";
  return `${currency ?? ""} ${amount.toLocaleString()}`.trim();
}

export function PurchaseOrderDocument({ data }: { data: PurchaseOrderData }) {
  return (
    <Document title={`Purchase Order ${data.poNumber}`}>
      <Page size="A4" style={styles.page}>
        <View style={styles.headerRow}>
          <Text style={styles.tenantLabel}>{data.tenantLabel}</Text>
          <View>
            <Text style={styles.title}>PURCHASE ORDER</Text>
            <Text style={styles.meta}>No. {data.poNumber} (v{data.version})</Text>
            <Text style={styles.meta}>Status: {data.status}</Text>
            <Text style={styles.meta}>Printed: {data.printedAt}</Text>
          </View>
        </View>

        <View style={[styles.section, styles.twoColumn]}>
          <View style={styles.column}>
            <Text style={styles.sectionTitle}>Vendor</Text>
            <Text style={{ marginBottom: 4, fontWeight: 700 }}>{data.vendorLegalName}</Text>
            <View style={styles.labelValueRow}>
              <Text style={styles.label}>Vendor code</Text>
              <Text style={styles.value}>{data.vendorCode}</Text>
            </View>
            <View style={styles.labelValueRow}>
              <Text style={styles.label}>Address</Text>
              <Text style={styles.value}>{data.vendorAddress ?? "—"}</Text>
            </View>
          </View>
          <View style={styles.column}>
            <Text style={styles.sectionTitle}>Terms</Text>
            <View style={styles.labelValueRow}>
              <Text style={styles.label}>Payment terms</Text>
              <Text style={styles.value}>{data.costMasked ? "Masked" : data.paymentTermDays !== null ? `${data.paymentTermDays} days` : "—"}</Text>
            </View>
            <View style={styles.labelValueRow}>
              <Text style={styles.label}>Expected delivery</Text>
              <Text style={styles.value}>{data.expectedDeliveryDate ?? "—"}</Text>
            </View>
            <View style={styles.labelValueRow}>
              <Text style={styles.label}>Service period</Text>
              <Text style={styles.value}>{data.servicePeriodStart && data.servicePeriodEnd ? `${data.servicePeriodStart} — ${data.servicePeriodEnd}` : "—"}</Text>
            </View>
          </View>
        </View>

        {data.commercialTerms || data.notes ? (
          <View style={styles.section}>
            {data.commercialTerms ? (
              <View style={styles.labelValueRow}>
                <Text style={styles.label}>Commercial terms</Text>
                <Text style={styles.value}>{data.costMasked ? "Masked" : data.commercialTerms}</Text>
              </View>
            ) : null}
            {data.notes ? (
              <View style={styles.labelValueRow}>
                <Text style={styles.label}>Notes</Text>
                <Text style={styles.value}>{data.notes}</Text>
              </View>
            ) : null}
          </View>
        ) : null}

        <View style={styles.section}>
          <Text style={styles.sectionTitle}>Line items</Text>
          <View style={styles.table}>
            <View style={styles.tableRow}>
              <Text style={[styles.lineNoCell, styles.tableCellHeader]}>#</Text>
              <Text style={[styles.descriptionCell, styles.tableCellHeader]}>Description</Text>
              <Text style={[styles.qtyCell, styles.tableCellHeader]}>Qty</Text>
              <Text style={[styles.uomCell, styles.tableCellHeader]}>UoM</Text>
              <Text style={[styles.notesCell, styles.tableCellHeader]}>Notes</Text>
            </View>
            {data.lines.map((line) => (
              <View key={line.lineNo} style={styles.tableRow}>
                <Text style={styles.lineNoCell}>{line.lineNo}</Text>
                <Text style={styles.descriptionCell}>{line.description}</Text>
                <Text style={styles.qtyCell}>{line.quantity !== null ? line.quantity.toLocaleString() : "—"}</Text>
                <Text style={styles.uomCell}>{line.uom ?? "—"}</Text>
                <Text style={styles.notesCell}>{line.notes ?? "—"}</Text>
              </View>
            ))}
          </View>
        </View>

        <View style={styles.totalsBlock}>
          <View style={styles.totalsRow}>
            <Text style={styles.totalsLabel}>Subtotal</Text>
            <Text>{formatAmount(data.currency, data.subtotalAmount, data.costMasked)}</Text>
          </View>
          <View style={styles.totalsRow}>
            <Text style={styles.totalsLabel}>Tax {data.taxCode && !data.costMasked ? `(${data.taxCode})` : ""}</Text>
            <Text>{formatAmount(data.currency, data.taxAmount, data.costMasked)}</Text>
          </View>
          <View style={styles.totalsRow}>
            <Text style={[styles.totalsLabel, styles.totalsValueEmphasis]}>Total</Text>
            <Text style={styles.totalsValueEmphasis}>{formatAmount(data.currency, data.totalAmount, data.costMasked)}</Text>
          </View>
        </View>

        <View style={styles.signatureRow}>
          <View style={styles.signatureBlock}>
            <Text>Issued by</Text>
            <Text style={styles.signatureLine}>{data.issuedBy ?? "Name & Signature"}</Text>
            {data.issuedAt ? <Text style={{ marginTop: 2, color: "#4b5563" }}>{data.issuedAt}</Text> : null}
          </View>
          <View style={styles.signatureBlock}>
            <Text>Acknowledged by (vendor)</Text>
            <Text style={styles.signatureLine}>Name &amp; Signature</Text>
          </View>
        </View>
      </Page>
    </Document>
  );
}
