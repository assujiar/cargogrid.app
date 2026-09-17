/**
 * Proof of Delivery (POD) summary PDF layout (audit remediation A7, second
 * printable document after surat jalan; `docs/audit/2026-09-02-independent-
 * launch-readiness-audit.md` finding A7's own list: "packing list, POD or
 * purchase order"). Built on `getEpodCaptureHistory` (OPS-177), already real,
 * tested backend capability -- no new schema, no new RPC.
 *
 * Evidence images (audit remediation NEW-2, follow-on to A6's own closure):
 * `signatureImageUrl`/`photoImageUrls` are already-minted, short-lived
 * Storage signed URLs (`generate-pod.server.ts`'s own
 * `getEpodEvidenceSignedDownloadUrl` call) -- this component only ever
 * receives a URL it can hand straight to `@react-pdf/renderer`'s `Image`,
 * never a raw file id/storage path. A null `signatureImageUrl` or an empty
 * `photoImageUrls` array (access denied, a since-deleted file, or capture
 * simply never attached one) falls back to the same text note this
 * document originally shipped with -- never a broken image or a thrown
 * render error.
 */

import ReactPDF from "@react-pdf/renderer";

const { Document, Page, View, Text, Image, StyleSheet } = ReactPDF;

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
  readonly signatureImageUrl: string | null;
  readonly photoImageUrls: readonly string[];
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
  signatureImage: { width: 180, height: 90, objectFit: "contain", border: "1pt solid #d1d5db" },
  photoRow: { flexDirection: "row", flexWrap: "wrap", gap: 8, marginTop: 4 },
  photoImage: { width: 140, height: 140, objectFit: "cover", border: "1pt solid #d1d5db" },
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

        <View style={styles.section}>
          <Text style={styles.sectionTitle}>Signature</Text>
          {data.signatureImageUrl ? (
            // eslint-disable-next-line jsx-a11y/alt-text -- SUPPRESS(owner=ops-a7-printables, reason=react-pdf's Image renders into a PDF not the DOM and its ImageProps type has no alt prop at all, expires=NONE, adr=NONE)
            <Image style={styles.signatureImage} src={data.signatureImageUrl} />
          ) : (
            <Text style={styles.evidenceNote}>{data.hasSignature ? "Signature evidence is on file but could not be embedded." : "No signature captured for this delivery."}</Text>
          )}
        </View>

        <View style={styles.section}>
          <Text style={styles.sectionTitle}>Delivery photos</Text>
          {data.photoImageUrls.length > 0 ? (
            <View style={styles.photoRow}>
              {data.photoImageUrls.map((url) => (
                // eslint-disable-next-line jsx-a11y/alt-text -- SUPPRESS(owner=ops-a7-printables, reason=react-pdf's Image renders into a PDF not the DOM and its ImageProps type has no alt prop at all, expires=NONE, adr=NONE)
                <Image key={url} style={styles.photoImage} src={url} />
              ))}
            </View>
          ) : (
            <Text style={styles.evidenceNote}>{data.photoCount > 0 ? `${data.photoCount} photo(s) on file but could not be embedded.` : "No delivery photos captured for this delivery."}</Text>
          )}
        </View>
      </Page>
    </Document>
  );
}
