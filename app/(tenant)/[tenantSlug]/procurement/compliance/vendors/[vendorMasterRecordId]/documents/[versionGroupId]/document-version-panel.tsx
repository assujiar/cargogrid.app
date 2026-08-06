"use client";

import Link from "next/link";
import { useActionState } from "react";
import { Button } from "../../../../../../../../../components/ui/button.tsx";
import { StatusBadge } from "../../../../../../../../../components/ui/status-badge.tsx";
import type { VendorComplianceDocument, VendorComplianceAccessResult } from "../../../../../../../../../server/contracts/vendor-compliance/vendor-compliance.ts";
import type { VendorComplianceEvidenceAccessState } from "../../../actions.ts";

const INITIAL_STATE: VendorComplianceEvidenceAccessState = { error: null, access: null };

const ACCESS_RESULT_TONE: Record<VendorComplianceAccessResult, "success" | "danger"> = {
  granted: "success",
  denied: "danger",
};

type EvidenceAccessAction = (prevState: VendorComplianceEvidenceAccessState, formData: FormData) => Promise<VendorComplianceEvidenceAccessState>;

function VersionRow({ version, accessAction }: { version: VendorComplianceDocument; accessAction: EvidenceAccessAction }) {
  const [state, formAction, pending] = useActionState(accessAction, INITIAL_STATE);

  return (
    <li className="flex flex-col gap-2 rounded-md border border-neutral-100 p-3">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <div>
          <p className="font-medium text-neutral-900">
            Version {version.versionNumber} {version.isLatestVersion ? <StatusBadge tone="info" label="latest" /> : null}
          </p>
          <p className="text-xs text-neutral-500">
            issued {version.issueDate ?? "—"} · expires {version.expiryDate ?? "no expiry"} · submitted {version.createdAt}
          </p>
        </div>
        <StatusBadge tone={version.verificationStatus === "verified" ? "success" : version.verificationStatus === "pending" ? "info" : "danger"} label={version.verificationStatus.replace(/_/g, " ")} />
      </div>
      {version.rejectionReason ? <p className="text-xs text-danger">{version.rejectionReason}</p> : null}

      <form action={formAction} className="flex flex-col gap-2">
        {state.error ? (
          <p role="alert" className="text-sm text-danger">
            {state.error}
          </p>
        ) : null}
        <Button type="submit" variant="secondary" loading={pending} loadingLabel="Checking access…" className="w-fit">
          View evidence
        </Button>
        {state.access ? (
          state.access.accessResult === "granted" ? (
            <dl className="grid grid-cols-2 gap-x-4 gap-y-1 rounded-md bg-neutral-50 p-2 text-xs text-neutral-700 sm:grid-cols-4">
              <dt className="font-medium">File</dt>
              <dd className="col-span-3">{state.access.originalFilename ?? "—"}</dd>
              <dt className="font-medium">Type</dt>
              <dd>{state.access.mimeType ?? "—"}</dd>
              <dt className="font-medium">Size</dt>
              <dd>{state.access.sizeBytes != null ? `${Math.ceil(state.access.sizeBytes / 1024)} KB` : "—"}</dd>
              <dt className="font-medium">Scan status</dt>
              <dd>{state.access.malwareScanStatus ?? "—"}</dd>
              <dt className="font-medium">Legal hold</dt>
              <dd>{state.access.legalHold ? "yes" : "no"}</dd>
            </dl>
          ) : (
            <p role="status" className="flex items-center gap-2 text-xs">
              <StatusBadge tone={ACCESS_RESULT_TONE[state.access.accessResult]} label="access denied" />
              {state.access.accessReason ?? "no reason recorded"}
            </p>
          )
        ) : null}
      </form>
    </li>
  );
}

export function DocumentVersionPanel({
  tenantSlug,
  vendorMasterRecordId,
  vendorLegalName,
  requirementName,
  versions,
  accessActionFor,
}: {
  tenantSlug: string;
  vendorMasterRecordId: string;
  vendorLegalName: string;
  requirementName: string | null;
  versions: readonly VendorComplianceDocument[];
  accessActionFor: (documentId: string) => EvidenceAccessAction;
}) {
  return (
    <div className="flex flex-col gap-4">
      <header>
        <Link href={`/${tenantSlug}/procurement/compliance/vendors/${vendorMasterRecordId}`} className="text-xs text-primary underline">
          ← Back to {vendorLegalName}
        </Link>
        <h1 className="mt-1 text-xl font-semibold text-neutral-900">{requirementName ?? "Compliance evidence"} — version history</h1>
        <p className="text-xs text-neutral-500">Every submitted/renewed version, oldest to newest. Renewal never deletes prior evidence.</p>
      </header>

      <ul className="flex flex-col gap-3">
        {versions.map((version) => (
          <VersionRow key={version.id} version={version} accessAction={accessActionFor(version.id)} />
        ))}
      </ul>
    </div>
  );
}
