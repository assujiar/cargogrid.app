/**
 * Proof of Delivery (POD) summary PDF layout (audit remediation A7, second
 * printable document after surat jalan; `docs/audit/2026-09-02-independent-
 * launch-readiness-audit.md` finding A7's own list: "packing list, POD or
 * purchase order"). Built on `getEpodCaptureHistory` (OPS-177), already real,
 * tested backend capability -- no new schema, no new RPC.
 *
 * Deliberately TEXT-ONLY: `EpodCapture.signatureFileId`/`.photoFileIds`
 * reference real captured evidence in `app.files`, but no signed-download
 * capability exists anywhere in this codebase yet to fetch their bytes for
 * embedding (repo-wide grep for `createSignedUrl`/`storage.from(...).download`
 * confirms the only existing Storage read is the malware-scan job's own
 * internal download, never anything user-facing) -- audit finding A6's own
 * remaining scope, "wire upload + signed download + scanning," of which only
 * upload and scanning are done. Embedding the actual signature/photo images
 * is real future work once that exists, not something to fake here with an
 * unauthenticated or public URL. This summary is still genuinely useful on
 * its own (receiver identity, capture timestamp, review status/notes) --
 * exactly what a POD confirms even before its visual evidence is attached.
 */

import ReactPDF from "@react-pdf/renderer";

const { Document, Page, View, Text, StyleSheet } = ReactPDF;

export interface PodData {
  readonly tenantLabel: string;
  readonly shipmentNumber: string;
  readonly printedAt: string;
  readonly status: string;
  readonly receiverName: string | null;
  readonly receiverPosition: string | null;
  readonly capturedAt: string | null;
  readonly versionNumber: number;
  readonly reviewedAt: string | null;
  readonly reviewNotes: string | null;
  readonly photoCount: number;
  readonly hasSignature: boolean;
}

const styles = StyleSheet.create({
  page: { padding: 32, fontSize: 10, fontFamily: "Helvetica", color: "#111827" },
  headerRow: { flexDirection: "row", justifyContent: "space-between", alignItems: "flex-start", marginBottom: 16, borderBottom: "1pt solid #111827", paddingBottom: 8 },
  tenantLabel: { fontSize: 12, fontWeight: 700 },
  title: { fontSize: 16, fontWeight: 700, textAlign: "right" },
  meta: { fontSize: 9, textAlign: "right", color: "#4b5563" },
  section: { marginBottom: 12 },
  sectionTitle: { fontSize: 11, fontWeight: 700, marginBottom: 6, textTransform: "uppercase" },
  labelValueRow: { flexDirection: "row", marginBottom: 4 },
  label: { width: 140, color: "#4b5563" },
  value: { flex: 1 },
  note: { marginTop: 8, padding: 8, backgroundColor: "#f3f4f6", borderRadius: 2 },
  evidenceNote: { marginTop: 16, fontSize: 9, color: "#4b5563", fontStyle: "italic" },
});

export function PodDocument({ data }: { data: PodData }) {
  return (
    <Document title={`Proof of Delivery ${data.shipmentNumber}`}>
      <Page size="A4" style={styles.page}>
        <View style={styles.headerRow}>
          <Text style={styles.tenantLabel}>{data.tenantLabel}</Text>
          <View>
            <Text style={styles.title}>PROOF OF DELIVERY</Text>
            <Text style={styles.meta}>Shipment {data.shipmentNumber}</Text>
            <Text style={styles.meta}>Printed: {data.printedAt}</Text>
          </View>
        </View>

        <View style={styles.section}>
          <Text style={styles.sectionTitle}>Delivery capture</Text>
          <View style={styles.labelValueRow}>
            <Text style={styles.label}>Status</Text>
            <Text style={styles.value}>{data.status}</Text>
          </View>
          <View style={styles.labelValueRow}>
            <Text style={styles.label}>Version</Text>
            <Text style={styles.value}>v{data.versionNumber}</Text>
          </View>
          <View style={styles.labelValueRow}>
            <Text style={styles.label}>Captured at</Text>
            <Text style={styles.value}>{data.capturedAt ?? "—"}</Text>
          </View>
        </View>

        <View style={styles.section}>
          <Text style={styles.sectionTitle}>Receiver</Text>
          <View style={styles.labelValueRow}>
            <Text style={styles.label}>Name</Text>
            <Text style={styles.value}>{data.receiverName ?? "—"}</Text>
          </View>
          <View style={styles.labelValueRow}>
            <Text style={styles.label}>Position</Text>
            <Text style={styles.value}>{data.receiverPosition ?? "—"}</Text>
          </View>
        </View>

        <View style={styles.section}>
          <Text style={styles.sectionTitle}>Review</Text>
          <View style={styles.labelValueRow}>
            <Text style={styles.label}>Reviewed at</Text>
            <Text style={styles.value}>{data.reviewedAt ?? "Not yet reviewed"}</Text>
          </View>
          {data.reviewNotes ? (
            <View style={styles.note}>
              <Text>{data.reviewNotes}</Text>
            </View>
          ) : null}
        </View>

        <Text style={styles.evidenceNote}>
          {data.photoCount} photo(s) and {data.hasSignature ? "a signature" : "no signature"} captured for this delivery. Visual evidence is retained in this tenant&apos;s document storage and is not embedded in this summary.
        </Text>
      </Page>
    </Document>
  );
}
