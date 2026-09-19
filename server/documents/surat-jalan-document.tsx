/**
 * Surat Jalan (Indonesian delivery note) PDF layout (audit remediation A7;
 * `docs/audit/2026-09-02-independent-launch-readiness-audit.md` finding A7:
 * "No PDF/print library; no printable document of any kind... `package.json`
 * carries no PDF/print/document library." Per the audit's own §6
 * dependency-ordered remediation step 4, "the printable document set, surat
 * jalan first" -- this is that first document.
 *
 * A pure presentation component: takes an already-assembled `SuratJalanData`
 * plain object (never the raw query/contract shapes directly), so this file
 * has zero database/RPC knowledge and stays independently testable/reusable
 * if a second caller ever needs the same layout. `generate-surat-jalan.server.ts`
 * is the only place that knows how to build this input from live data.
 *
 * `consigneeSnapshot`/`cargoServiceSnapshot`/`shipperBillingAddress` are
 * rendered as a generic label/value list rather than named fields: both
 * `app.shipment_orders.consignee_snapshot` and `.cargo_service_snapshot`
 * (20260727100000_create_operations_shipment_order.sql) and
 * `app.accounts.billing_address` are deliberately unstructured JSONB with no
 * fixed schema anywhere in this codebase ("a shipment's consignee may
 * legitimately differ from the Job Order's own billing customer... these are
 * not forced through the same account reference") -- hardcoding specific
 * field names here would silently drop whatever a caller actually stored.
 */

import ReactPDF from "@react-pdf/renderer";
import { type SuratJalanLabeledValue } from "./surat-jalan-labeled-values.ts";

const { Document, Page, View, Text, StyleSheet } = ReactPDF;

export type { SuratJalanLabeledValue } from "./surat-jalan-labeled-values.ts";

export interface SuratJalanData {
  readonly tenantLabel: string;
  readonly shipmentNumber: string;
  readonly printedAt: string;
  readonly shipperLegalName: string;
  readonly shipperDetails: readonly SuratJalanLabeledValue[];
  readonly consigneeDetails: readonly SuratJalanLabeledValue[];
  readonly notifyPartyDetails: readonly SuratJalanLabeledValue[];
  readonly origin: string;
  readonly destination: string;
  readonly plannedPickupAt: string | null;
  readonly plannedDeliveryAt: string | null;
  readonly serviceType: string;
  readonly mode: string;
  readonly cargoDetails: readonly SuratJalanLabeledValue[];
  readonly basisQuantity: number | null;
  readonly basisWeightKg: number | null;
  readonly basisVolumeCbm: number | null;
  readonly vehicleLabel: string | null;
  readonly driverLabel: string | null;
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
  label: { width: 90, color: "#4b5563" },
  value: { flex: 1 },
  table: { borderTop: "1pt solid #d1d5db", borderLeft: "1pt solid #d1d5db", marginTop: 4 },
  tableRow: { flexDirection: "row" },
  tableCellHeader: { flex: 1, padding: 4, fontWeight: 700, borderRight: "1pt solid #d1d5db", borderBottom: "1pt solid #d1d5db", backgroundColor: "#f3f4f6" },
  tableCell: { flex: 1, padding: 4, borderRight: "1pt solid #d1d5db", borderBottom: "1pt solid #d1d5db" },
  signatureRow: { flexDirection: "row", marginTop: 32, gap: 16 },
  signatureBlock: { flex: 1, textAlign: "center" },
  signatureLine: { borderTop: "1pt solid #111827", marginTop: 48, paddingTop: 4 },
});

function LabeledValues({ items }: { items: readonly SuratJalanLabeledValue[] }) {
  if (items.length === 0) {
    return <Text style={styles.value}>—</Text>;
  }
  return (
    <>
      {items.map((item) => (
        <View key={item.label} style={styles.labelValueRow}>
          <Text style={styles.label}>{item.label}</Text>
          <Text style={styles.value}>{item.value}</Text>
        </View>
      ))}
    </>
  );
}

export function SuratJalanDocument({ data }: { data: SuratJalanData }) {
  return (
    <Document title={`Surat Jalan ${data.shipmentNumber}`}>
      <Page size="A4" style={styles.page}>
        <View style={styles.headerRow}>
          <Text style={styles.tenantLabel}>{data.tenantLabel}</Text>
          <View>
            <Text style={styles.title}>SURAT JALAN</Text>
            <Text style={styles.meta}>No. {data.shipmentNumber}</Text>
            <Text style={styles.meta}>Dicetak: {data.printedAt}</Text>
          </View>
        </View>

        <View style={[styles.section, styles.twoColumn]}>
          <View style={styles.column}>
            <Text style={styles.sectionTitle}>Pengirim (Shipper)</Text>
            <Text style={{ marginBottom: 4, fontWeight: 700 }}>{data.shipperLegalName}</Text>
            <LabeledValues items={data.shipperDetails} />
          </View>
          <View style={styles.column}>
            <Text style={styles.sectionTitle}>Penerima (Consignee)</Text>
            <LabeledValues items={data.consigneeDetails} />
          </View>
        </View>

        {data.notifyPartyDetails.length > 0 ? (
          <View style={styles.section}>
            <Text style={styles.sectionTitle}>Notify Party</Text>
            <LabeledValues items={data.notifyPartyDetails} />
          </View>
        ) : null}

        <View style={[styles.section, styles.twoColumn]}>
          <View style={styles.column}>
            <Text style={styles.sectionTitle}>Rute (Route)</Text>
            <View style={styles.labelValueRow}>
              <Text style={styles.label}>Asal</Text>
              <Text style={styles.value}>{data.origin}</Text>
            </View>
            <View style={styles.labelValueRow}>
              <Text style={styles.label}>Tujuan</Text>
              <Text style={styles.value}>{data.destination}</Text>
            </View>
            <View style={styles.labelValueRow}>
              <Text style={styles.label}>Jemput</Text>
              <Text style={styles.value}>{data.plannedPickupAt ?? "—"}</Text>
            </View>
            <View style={styles.labelValueRow}>
              <Text style={styles.label}>Antar</Text>
              <Text style={styles.value}>{data.plannedDeliveryAt ?? "—"}</Text>
            </View>
          </View>
          <View style={styles.column}>
            <Text style={styles.sectionTitle}>Kendaraan &amp; Pengemudi</Text>
            <View style={styles.labelValueRow}>
              <Text style={styles.label}>Kendaraan</Text>
              <Text style={styles.value}>{data.vehicleLabel ?? "—"}</Text>
            </View>
            <View style={styles.labelValueRow}>
              <Text style={styles.label}>Pengemudi</Text>
              <Text style={styles.value}>{data.driverLabel ?? "—"}</Text>
            </View>
            <View style={styles.labelValueRow}>
              <Text style={styles.label}>Layanan</Text>
              <Text style={styles.value}>{data.serviceType} ({data.mode})</Text>
            </View>
          </View>
        </View>

        <View style={styles.section}>
          <Text style={styles.sectionTitle}>Barang (Cargo)</Text>
          <View style={styles.table}>
            <View style={styles.tableRow}>
              <Text style={styles.tableCellHeader}>Keterangan</Text>
              <Text style={styles.tableCellHeader}>Nilai</Text>
            </View>
            {[
              { label: "Kuantitas", value: data.basisQuantity !== null ? String(data.basisQuantity) : null },
              { label: "Berat (kg)", value: data.basisWeightKg !== null ? String(data.basisWeightKg) : null },
              { label: "Volume (cbm)", value: data.basisVolumeCbm !== null ? String(data.basisVolumeCbm) : null },
              ...data.cargoDetails.map((item) => ({ label: item.label, value: item.value })),
            ]
              .filter((row) => row.value !== null)
              .map((row) => (
                <View key={row.label} style={styles.tableRow}>
                  <Text style={styles.tableCell}>{row.label}</Text>
                  <Text style={styles.tableCell}>{row.value}</Text>
                </View>
              ))}
          </View>
        </View>

        <View style={styles.signatureRow}>
          <View style={styles.signatureBlock}>
            <Text>Pengirim</Text>
            <Text style={styles.signatureLine}>Nama &amp; Tanda Tangan</Text>
          </View>
          <View style={styles.signatureBlock}>
            <Text>Pengemudi</Text>
            <Text style={styles.signatureLine}>Nama &amp; Tanda Tangan</Text>
          </View>
          <View style={styles.signatureBlock}>
            <Text>Penerima</Text>
            <Text style={styles.signatureLine}>Nama, Tanda Tangan &amp; Cap</Text>
          </View>
        </View>
      </Page>
    </Document>
  );
}
