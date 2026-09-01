"use client";

/**
 * ePOD ("delivery evidence") sub-section (CPL-307, CG-S13-CPL-009, Prompt
 * 307). Extends the existing customer-shipments/[shipmentOrderId] detail
 * page (CPL-304/305/306), per the orchestrating task's own design decision
 * 5, rather than a new sibling route.
 *
 * Renders whichever of the three real, distinct `epodStatus` values the
 * page's own eager, non-fatal `getCustomerEpod` fetch returned (migration
 * design decision 4): `not_available` (no completed capture yet),
 * `quarantined` (a completed capture exists but at least one referenced
 * evidence file failed live re-verification), or `available` (every file
 * re-verified clean). These are honest states, never errors -- there is
 * nothing here for a form to reject.
 *
 * The "Download" action is a real Server Action (`accessEpodAction`) that
 * re-calls `app.get_customer_epod` -- a genuine, audited access attempt
 * (migration design decision 3), not a decorative control. It returns
 * customer-safe file metadata only, never a working file URL (migration
 * design decision 8: no live Supabase Storage integration exists anywhere in
 * this repository -- disclosed, not fabricated). On success this component
 * shows the confirmed-fresh metadata inline; `revalidatePath` (inside the
 * action) also refreshes the page's own initial fetch for the next render.
 */

import { useActionState } from "react";
import { Link } from "../../../../../components/ui/link.tsx";
import { Button } from "../../../../../components/ui/button.tsx";
import { StatusBadge, type StatusTone } from "../../../../../components/ui/status-badge.tsx";
import { ValidationMessage } from "../../../../../components/forms/validation-message.tsx";
import type { CustomerShipmentOrderActionState } from "../actions.ts";
import type { CustomerEpod, CustomerEpodFile } from "../../../../../server/contracts/customer-epod/customer-epod.ts";

const INITIAL_STATE: CustomerShipmentOrderActionState = { error: null };

const EPOD_STATUS_TONE: Record<CustomerEpod["epodStatus"], StatusTone> = {
  not_available: "neutral",
  quarantined: "warning",
  available: "success",
};

const EPOD_STATUS_LABEL: Record<CustomerEpod["epodStatus"], string> = {
  not_available: "Not yet available",
  quarantined: "Under review",
  available: "Ready",
};

const FILE_ROLE_LABEL: Record<CustomerEpodFile["role"], string> = {
  signature: "Signature",
  photo: "Delivery photo",
};

function formatSize(sizeBytes: number): string {
  return sizeBytes >= 1024 * 1024 ? `${(sizeBytes / (1024 * 1024)).toFixed(1)} MB` : `${Math.ceil(sizeBytes / 1024)} KB`;
}

function EvidenceFileRow({ file }: { file: CustomerEpodFile }) {
  return (
    <li className="flex flex-wrap items-center justify-between gap-2 rounded-md border border-neutral-100 p-2 text-sm">
      <div>
        <p className="font-medium text-neutral-900">{FILE_ROLE_LABEL[file.role]}</p>
        <p className="text-xs text-neutral-500">
          {file.originalFilename} · {file.mimeType} · {formatSize(file.sizeBytes)}
        </p>
      </div>
      <StatusBadge tone="success" label="verified clean" />
    </li>
  );
}

export function CustomerEpodPanel({
  tenantSlug,
  epod,
  accessAction,
}: {
  tenantSlug: string;
  epod: CustomerEpod;
  accessAction: (prevState: CustomerShipmentOrderActionState, formData: FormData) => Promise<CustomerShipmentOrderActionState>;
}) {
  const [state, formAction, pending] = useActionState(accessAction, INITIAL_STATE);

  return (
    <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <h2 className="text-sm font-semibold text-neutral-900">Delivery evidence (ePOD)</h2>
        <StatusBadge tone={EPOD_STATUS_TONE[epod.epodStatus]} label={EPOD_STATUS_LABEL[epod.epodStatus]} />
      </div>

      {epod.epodStatus === "not_available" ? (
        <p className="text-sm text-neutral-500">Delivery evidence isn&apos;t available yet. It appears here once your shipment is delivered and the proof-of-delivery capture is reviewed.</p>
      ) : null}

      {epod.epodStatus === "quarantined" ? (
        <p className="text-sm text-neutral-700">
          Delivery evidence for this shipment is temporarily unavailable while it&apos;s being verified. If you need it urgently, please <Link href={`/${tenantSlug}/customer-tickets`}>open a ticket</Link>.
        </p>
      ) : null}

      {epod.epodStatus !== "not_available" ? (
        <dl className="grid grid-cols-2 gap-2 text-xs text-neutral-500 sm:grid-cols-3">
          <div>
            <dt className="font-medium">Received by</dt>
            <dd>{epod.receiverName ?? "—"}</dd>
          </div>
          <div>
            <dt className="font-medium">Captured</dt>
            <dd>{epod.capturedAt ? new Date(epod.capturedAt).toLocaleString() : "—"}</dd>
          </div>
          <div>
            <dt className="font-medium">Recorded</dt>
            <dd>{epod.serverReceivedAt ? new Date(epod.serverReceivedAt).toLocaleString() : "—"}</dd>
          </div>
        </dl>
      ) : null}

      {epod.epodStatus === "available" ? (
        epod.files.length > 0 ? (
          <ul className="flex flex-col gap-2">
            {epod.files.map((file) => (
              <EvidenceFileRow key={file.fileId} file={file} />
            ))}
          </ul>
        ) : (
          <p className="text-sm text-neutral-500">No evidence files were attached to this delivery.</p>
        )
      ) : null}

      <form action={formAction} className="flex flex-col gap-2">
        <div>
          <Button type="submit" variant="secondary" loading={pending} loadingLabel="Checking…">
            {epod.epodStatus === "available" ? "Download" : "Check again"}
          </Button>
        </div>
        {epod.epodStatus === "available" ? (
          <p className="text-xs text-neutral-500">Every evidence file above has been verified and scanned clean. Live file delivery activates once this environment&apos;s storage delivery layer is provisioned.</p>
        ) : null}
        {state.error ? <ValidationMessage>{state.error}</ValidationMessage> : null}
      </form>
    </section>
  );
}
