/**
 * Packing List PDF layout (audit remediation A7, "packing list" -- the
 * audit's own remaining printable-document item alongside faktur pajak;
 * `docs/audit/2026-09-02-independent-launch-readiness-audit.md` finding A7).
 * Built entirely on already-existing, already-tested read queries
 * (`getWmsPackingTask`, `listWmsPackages`, `listWmsPackageLines`,
 * `getWmsOutboundOrder`, `listTenantWarehouses`, `getAccountById`,
 * `getItemMaster`) -- no new schema, no new RPC. ATW-018's own domain
 * (`app.wms_packing_tasks`/`app.wms_packages`/`app.wms_package_lines`) was
 * real and fully tested, but had zero pages/actions anywhere -- there was
 * nothing yet to print.
 *
 * A pure presentation component, mirroring surat-jalan-document.tsx/
 * pod-document.tsx/purchase-order-document.tsx exactly: takes an
 * already-assembled `PackingListData` plain object, zero database/RPC
 * knowledge. One packing task can hold multiple packages/cartons, each with
 * its own line items -- rendered as repeated package sections rather than a
 * single flat table, since a warehouse worker checks off one physical
 * package at a time against its own printed section.
 */

import ReactPDF from "@react-pdf/renderer";

const { Document, Page, View, Text, StyleSheet } = ReactPDF;

export interface PackingListLineData {
  readonly itemCode: string;
  readonly itemName: string;
  readonly lotNumber: string | null;
  readonly serialNumber: string | null;
  readonly expiryDate: string | null;
  readonly quantity: number;
  readonly uomCode: string;
}

export interface PackingListPackageData {
  readonly packageNumber: string;
  readonly packageType: string;
  readonly status: string;
  readonly qcStatus: string;
  readonly weightValue: number | null;
  readonly weightUomCode: string | null;
  readonly lengthValue: number | null;
  readonly widthValue: number | null;
  readonly heightValue: number | null;
  readonly dimensionUomCode: string | null;
  readonly sealNumber: string | null;
  readonly confirmedAt: string | null;
  readonly confirmedByLabel: string | null;
  readonly lines: readonly PackingListLineData[];
}

export interface PackingListData {
  readonly tenantLabel: string;
  readonly packingTaskNumber: string;
  readonly outboundNumber: string;
  readonly warehouseLabel: string;
  readonly ownerAccountLabel: string;
  readonly printedAt: string;
  readonly packages: readonly PackingListPackageData[];
  readonly totalPackages: number;
  readonly totalQuantity: number;
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
  label: { width: 110, color: "#4b5563" },
  value: { flex: 1 },
  packageBlock: { marginBottom: 12, border: "1pt solid #d1d5db", padding: 8 },
  packageHeaderRow: { flexDirection: "row", justifyContent: "space-between", alignItems: "flex-start", marginBottom: 6 },
  packageTitle: { fontSize: 11, fontWeight: 700 },
  packageMeta: { fontSize: 8, color: "#4b5563", textAlign: "right" },
  table: { borderTop: "1pt solid #d1d5db", borderLeft: "1pt solid #d1d5db", marginTop: 4 },
  tableRow: { flexDirection: "row" },
  itemCell: { flex: 2, padding: 4, borderRight: "1pt solid #d1d5db", borderBottom: "1pt solid #d1d5db" },
  lotCell: { flex: 1, padding: 4, borderRight: "1pt solid #d1d5db", borderBottom: "1pt solid #d1d5db" },
  expiryCell: { flex: 1, padding: 4, borderRight: "1pt solid #d1d5db", borderBottom: "1pt solid #d1d5db" },
  qtyCell: { flex: 1, padding: 4, borderRight: "1pt solid #d1d5db", borderBottom: "1pt solid #d1d5db", textAlign: "right" },
  tableCellHeader: { fontWeight: 700, backgroundColor: "#f3f4f6" },
  totalsBlock: { marginTop: 8, alignSelf: "flex-end", width: 220 },
  totalsRow: { flexDirection: "row", justifyContent: "space-between", marginBottom: 2 },
  totalsLabel: { color: "#4b5563" },
  totalsValueEmphasis: { fontWeight: 700 },
  signatureRow: { flexDirection: "row", marginTop: 32, gap: 16 },
  signatureBlock: { flex: 1, textAlign: "center" },
  signatureLine: { borderTop: "1pt solid #111827", marginTop: 48, paddingTop: 4 },
});

function formatDimensions(pkg: PackingListPackageData): string {
  if (pkg.lengthValue === null || pkg.widthValue === null || pkg.heightValue === null) return "—";
  return `${pkg.lengthValue} x ${pkg.widthValue} x ${pkg.heightValue} ${pkg.dimensionUomCode ?? ""}`.trim();
}

function formatWeight(pkg: PackingListPackageData): string {
  if (pkg.weightValue === null) return "—";
  return `${pkg.weightValue} ${pkg.weightUomCode ?? ""}`.trim();
}

export function PackingListDocument({ data }: { data: PackingListData }) {
  return (
    <Document title={`Packing List ${data.packingTaskNumber}`}>
      <Page size="A4" style={styles.page}>
        <View style={styles.headerRow}>
          <Text style={styles.tenantLabel}>{data.tenantLabel}</Text>
          <View>
            <Text style={styles.title}>PACKING LIST</Text>
            <Text style={styles.meta}>Task No. {data.packingTaskNumber}</Text>
            <Text style={styles.meta}>Outbound No. {data.outboundNumber}</Text>
            <Text style={styles.meta}>Printed: {data.printedAt}</Text>
          </View>
        </View>

        <View style={[styles.section, styles.twoColumn]}>
          <View style={styles.column}>
            <Text style={styles.sectionTitle}>Ship from</Text>
            <View style={styles.labelValueRow}>
              <Text style={styles.label}>Warehouse</Text>
              <Text style={styles.value}>{data.warehouseLabel}</Text>
            </View>
          </View>
          <View style={styles.column}>
            <Text style={styles.sectionTitle}>Ship to</Text>
            <View style={styles.labelValueRow}>
              <Text style={styles.label}>Account</Text>
              <Text style={styles.value}>{data.ownerAccountLabel}</Text>
            </View>
          </View>
        </View>

        {data.packages.map((pkg) => (
          <View key={pkg.packageNumber} style={styles.packageBlock} wrap={false}>
            <View style={styles.packageHeaderRow}>
              <Text style={styles.packageTitle}>
                Package {pkg.packageNumber} ({pkg.packageType})
              </Text>
              <View>
                <Text style={styles.packageMeta}>Status: {pkg.status} · QC: {pkg.qcStatus}</Text>
                <Text style={styles.packageMeta}>Weight: {formatWeight(pkg)} · Dimensions: {formatDimensions(pkg)}</Text>
                <Text style={styles.packageMeta}>Seal: {pkg.sealNumber ?? "—"}</Text>
                {pkg.confirmedAt ? <Text style={styles.packageMeta}>Confirmed by {pkg.confirmedByLabel ?? "—"} at {pkg.confirmedAt}</Text> : null}
              </View>
            </View>

            <View style={styles.table}>
              <View style={styles.tableRow}>
                <Text style={[styles.itemCell, styles.tableCellHeader]}>Item</Text>
                <Text style={[styles.lotCell, styles.tableCellHeader]}>Lot / Serial</Text>
                <Text style={[styles.expiryCell, styles.tableCellHeader]}>Expiry</Text>
                <Text style={[styles.qtyCell, styles.tableCellHeader]}>Qty</Text>
              </View>
              {pkg.lines.length === 0 ? (
                <View style={styles.tableRow}>
                  <Text style={[styles.itemCell, { flex: 5 }]}>No lines packed into this package yet.</Text>
                </View>
              ) : (
                pkg.lines.map((line, index) => (
                  <View key={`${pkg.packageNumber}-${index}`} style={styles.tableRow}>
                    <Text style={styles.itemCell}>
                      {line.itemCode} — {line.itemName}
                    </Text>
                    <Text style={styles.lotCell}>{line.lotNumber ?? line.serialNumber ?? "—"}</Text>
                    <Text style={styles.expiryCell}>{line.expiryDate ?? "—"}</Text>
                    <Text style={styles.qtyCell}>
                      {line.quantity.toLocaleString()} {line.uomCode}
                    </Text>
                  </View>
                ))
              )}
            </View>
          </View>
        ))}

        <View style={styles.totalsBlock}>
          <View style={styles.totalsRow}>
            <Text style={styles.totalsLabel}>Packages</Text>
            <Text>{data.totalPackages.toLocaleString()}</Text>
          </View>
          <View style={styles.totalsRow}>
            <Text style={[styles.totalsLabel, styles.totalsValueEmphasis]}>Total quantity</Text>
            <Text style={styles.totalsValueEmphasis}>{data.totalQuantity.toLocaleString()}</Text>
          </View>
        </View>

        <View style={styles.signatureRow}>
          <View style={styles.signatureBlock}>
            <Text>Packed by</Text>
            <Text style={styles.signatureLine}>Name &amp; Signature</Text>
          </View>
          <View style={styles.signatureBlock}>
            <Text>Checked by</Text>
            <Text style={styles.signatureLine}>Name &amp; Signature</Text>
          </View>
          <View style={styles.signatureBlock}>
            <Text>Received by</Text>
            <Text style={styles.signatureLine}>Name &amp; Signature</Text>
          </View>
        </View>
      </Page>
    </Document>
  );
}
