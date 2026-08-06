"use client";

import { useActionState } from "react";
import Link from "next/link";
import { Button } from "../../../../../../../components/ui/button.tsx";
import { StatusBadge, type StatusTone } from "../../../../../../../components/ui/status-badge.tsx";
import { EmptyState } from "../../../../../../../components/ui/empty-state.tsx";
import type { VendorComplianceActionState } from "../actions.ts";
import type {
  VendorComplianceEligibilityRow,
  VendorComplianceDocument,
  VendorComplianceWaiver,
  VendorComplianceRequirement,
  VendorComplianceStatusValue,
} from "../../../../../../../server/contracts/vendor-compliance/vendor-compliance.ts";
import type { VendorProfile } from "../../../../../../../server/contracts/vendor-profile/vendor-profile.ts";

const INITIAL_STATE: VendorComplianceActionState = { error: null };

const STATUS_TONE: Record<VendorComplianceStatusValue, StatusTone> = {
  not_submitted: "neutral",
  pending_verification: "info",
  verified: "success",
  expiring_soon: "warning",
  expired: "danger",
  waived: "info",
  rejected: "danger",
};

type BoundFormAction = (prevState: VendorComplianceActionState, formData: FormData) => Promise<VendorComplianceActionState>;

function ActionForm({
  action,
  children,
  submitLabel,
  loadingLabel,
  variant = "primary",
  className = "flex flex-col gap-2",
}: {
  action: BoundFormAction;
  children?: React.ReactNode;
  submitLabel: string;
  loadingLabel?: string;
  variant?: "primary" | "secondary" | "destructive";
  className?: string;
}) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  return (
    <form action={formAction} className={className}>
      {children}
      {state.error ? (
        <p role="alert" className="text-sm text-danger">
          {state.error}
        </p>
      ) : null}
      <Button type="submit" variant={variant} loading={pending} loadingLabel={loadingLabel ?? "Working…"} className="w-fit">
        {submitLabel}
      </Button>
    </form>
  );
}

export function VendorCompliancePanel({
  tenantSlug,
  vendor,
  eligibility,
  documents,
  waivers,
  publishedRequirements,
  submitDocumentAction,
  renewDocumentActionFor,
  decideDocumentActionFor,
  requestWaiverAction,
  decideWaiverActionFor,
  revokeWaiverActionFor,
  recalculateAction,
}: {
  tenantSlug: string;
  vendor: VendorProfile;
  eligibility: readonly VendorComplianceEligibilityRow[];
  documents: readonly VendorComplianceDocument[];
  waivers: readonly VendorComplianceWaiver[];
  publishedRequirements: readonly VendorComplianceRequirement[];
  submitDocumentAction: BoundFormAction;
  renewDocumentActionFor: (previousDocumentId: string) => BoundFormAction;
  decideDocumentActionFor: (documentId: string, expectedVersion: number) => BoundFormAction;
  requestWaiverAction: BoundFormAction;
  decideWaiverActionFor: (waiverId: string, expectedVersion: number) => BoundFormAction;
  revokeWaiverActionFor: (waiverId: string, expectedVersion: number) => BoundFormAction;
  recalculateAction: (prevState: VendorComplianceActionState, formData: FormData) => Promise<VendorComplianceActionState>;
}) {
  const [recalcState, recalcFormAction, recalcPending] = useActionState(recalculateAction, INITIAL_STATE);
  const documentsByRequirement = new Map(documents.map((d) => [d.requirementVersionId, d]));
  const hasHold = eligibility.some((row) => row.eligibilityHold);

  return (
    <div className="flex flex-col gap-6">
      <header className="flex flex-wrap items-center justify-between gap-2">
        <div>
          <h1 className="text-xl font-semibold text-neutral-900">{vendor.legalName}</h1>
          <p className="text-xs text-neutral-500">{vendor.vendorCategory ?? "uncategorized"} · compliance dashboard</p>
        </div>
        <div className="flex items-center gap-2">
          {hasHold ? <StatusBadge tone="danger" label="eligibility hold active" /> : <StatusBadge tone="success" label="no eligibility hold" />}
          <form action={recalcFormAction}>
            <Button type="submit" variant="secondary" loading={recalcPending} loadingLabel="Recalculating…">
              Recalculate
            </Button>
          </form>
        </div>
      </header>
      {recalcState.error ? (
        <p role="alert" className="text-sm text-danger">
          {recalcState.error}
        </p>
      ) : null}

      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Requirement eligibility</h2>
        {eligibility.length === 0 ? (
          <EmptyState title="No requirements tracked yet" description="Submit a document below against a published requirement to begin tracking." />
        ) : (
          <table className="w-full text-sm">
            <thead>
              <tr className="text-left text-xs text-neutral-500">
                <th className="pb-1">Requirement</th>
                <th className="pb-1">Blocking</th>
                <th className="pb-1">Status</th>
                <th className="pb-1">Hold</th>
                <th className="pb-1">Expiry</th>
                <th className="pb-1">Reminder tier</th>
              </tr>
            </thead>
            <tbody>
              {eligibility.map((row) => (
                <tr key={row.requirementFamilyId} className="border-t border-neutral-100">
                  <td className="py-1">{row.requirementName ?? "(requirement archived, not republished)"}</td>
                  <td className="py-1 text-xs">{row.blockingEffect ?? "—"}</td>
                  <td className="py-1">
                    <StatusBadge tone={STATUS_TONE[row.status]} label={row.status.replace(/_/g, " ")} />
                  </td>
                  <td className="py-1">{row.eligibilityHold ? <StatusBadge tone="danger" label="hold" /> : "—"}</td>
                  <td className="py-1 text-xs">{row.expiryDate ?? "—"}</td>
                  <td className="py-1 text-xs">
                    {row.reminderTierDays != null ? `${row.reminderTierDays}-day tier (${row.daysUntilExpiry} day${row.daysUntilExpiry === 1 ? "" : "s"} left)` : "—"}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </section>

      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Documents</h2>
        {documents.length === 0 ? (
          <EmptyState title="No evidence submitted yet" />
        ) : (
          <ul className="flex flex-col gap-3">
            {documents.map((doc) => {
              const requirement = publishedRequirements.find((r) => r.id === doc.requirementVersionId);
              return (
                <li key={doc.id} className="flex flex-col gap-2 rounded-md border border-neutral-100 p-3">
                  <div className="flex flex-wrap items-center justify-between gap-2">
                    <div>
                      <p className="font-medium text-neutral-900">{requirement?.name ?? doc.requirementVersionId}</p>
                      <p className="text-xs text-neutral-500">
                        version {doc.versionNumber} · issued {doc.issueDate ?? "—"} · expires {doc.expiryDate ?? "no expiry"}
                      </p>
                    </div>
                    <StatusBadge tone={doc.verificationStatus === "verified" ? "success" : doc.verificationStatus === "pending" ? "info" : "danger"} label={doc.verificationStatus.replace(/_/g, " ")} />
                  </div>
                  {doc.rejectionReason ? <p className="text-xs text-danger">{doc.rejectionReason}</p> : null}

                  <Link href={`/${tenantSlug}/procurement/compliance/vendors/${vendor.masterRecordId}/documents/${doc.versionGroupId}`} className="w-fit text-xs text-primary underline">
                    View versions &amp; evidence
                  </Link>

                  {doc.verificationStatus === "pending" ? (
                    <div className="flex flex-wrap gap-2">
                      <ActionForm action={decideDocumentActionFor(doc.id, doc.recordVersion)} submitLabel="Verify" loadingLabel="Verifying…" className="flex items-center gap-2">
                        <input type="hidden" name="decision" value="verified" />
                      </ActionForm>
                      <ActionForm action={decideDocumentActionFor(doc.id, doc.recordVersion)} submitLabel="Reject" loadingLabel="Rejecting…" variant="destructive" className="flex items-center gap-2">
                        <input type="hidden" name="decision" value="rejected" />
                        <input name="rejectionReason" placeholder="Reason (required)" required className="rounded-md border border-neutral-300 px-2 py-1 text-xs" />
                      </ActionForm>
                      <ActionForm action={decideDocumentActionFor(doc.id, doc.recordVersion)} submitLabel="Request revision" loadingLabel="Requesting…" variant="secondary" className="flex items-center gap-2">
                        <input type="hidden" name="decision" value="revision_requested" />
                        <input name="rejectionReason" placeholder="Reason (required)" required className="rounded-md border border-neutral-300 px-2 py-1 text-xs" />
                      </ActionForm>
                    </div>
                  ) : null}

                  <details className="text-xs">
                    <summary className="cursor-pointer text-primary">Renew (upload a newer version)</summary>
                    <ActionForm action={renewDocumentActionFor(doc.id)} submitLabel="Submit renewal" loadingLabel="Uploading…" variant="secondary" className="mt-2 grid grid-cols-1 gap-2 sm:grid-cols-4">
                      <input type="hidden" name="documentTypeCode" value={requirement?.documentTypeCode ?? ""} />
                      <input name="evidenceFile" type="file" required className="text-xs sm:col-span-2" />
                      <input name="issueDate" type="date" placeholder="Issue date" className="rounded-md border border-neutral-300 px-2 py-1 text-xs" />
                      <input name="expiryDate" type="date" placeholder="Expiry date" className="rounded-md border border-neutral-300 px-2 py-1 text-xs" />
                    </ActionForm>
                  </details>
                </li>
              );
            })}
          </ul>
        )}

        <div className="rounded-md border border-neutral-100 p-3">
          <h3 className="mb-2 text-xs font-semibold text-neutral-900">Submit a new document</h3>
          <ActionForm action={submitDocumentAction} submitLabel="Submit" loadingLabel="Uploading…" className="grid grid-cols-1 gap-2 sm:grid-cols-4">
            <select name="requirementVersionId" required className="rounded-md border border-neutral-300 px-2 py-1 text-sm sm:col-span-2" defaultValue="">
              <option value="" disabled>
                Select a requirement
              </option>
              {publishedRequirements
                .filter((r) => !documentsByRequirement.has(r.id))
                .map((r) => (
                  <option key={r.id} value={r.id}>
                    {r.name} ({r.documentTypeCode})
                  </option>
                ))}
            </select>
            <input name="evidenceFile" type="file" required className="text-sm sm:col-span-2" />
            <input name="issueDate" type="date" placeholder="Issue date" className="rounded-md border border-neutral-300 px-2 py-1 text-sm" />
            <input name="expiryDate" type="date" placeholder="Expiry date (leave blank if the requirement does not track expiry)" className="rounded-md border border-neutral-300 px-2 py-1 text-sm" />
          </ActionForm>
        </div>
      </section>

      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Waivers</h2>
        {waivers.length === 0 ? (
          <EmptyState title="No waivers on record" />
        ) : (
          <ul className="flex flex-col gap-2">
            {waivers.map((w) => (
              <li key={w.id} className="flex flex-col gap-2 rounded-md border border-neutral-100 p-3">
                <div className="flex flex-wrap items-center justify-between gap-2">
                  <div>
                    <p className="text-sm text-neutral-900">{w.reason}</p>
                    <p className="text-xs text-neutral-500">
                      valid {w.validFrom} → {w.validUntil} · requested by {w.requestedBy ?? w.requestedByAuthUserId}
                    </p>
                  </div>
                  <StatusBadge
                    tone={w.status === "approved" ? "success" : w.status === "pending" ? "info" : w.status === "rejected" || w.status === "revoked" ? "danger" : "neutral"}
                    label={w.status}
                  />
                </div>
                {w.decisionReason ? <p className="text-xs text-neutral-600">{w.decisionReason}</p> : null}

                {w.status === "pending" ? (
                  <div className="flex flex-wrap gap-2">
                    <ActionForm action={decideWaiverActionFor(w.id, w.recordVersion)} submitLabel="Approve" loadingLabel="Approving…" className="flex items-center gap-2">
                      <input type="hidden" name="decision" value="approved" />
                    </ActionForm>
                    <ActionForm action={decideWaiverActionFor(w.id, w.recordVersion)} submitLabel="Reject" loadingLabel="Rejecting…" variant="destructive" className="flex items-center gap-2">
                      <input type="hidden" name="decision" value="rejected" />
                      <input name="decisionReason" placeholder="Reason (required)" required className="rounded-md border border-neutral-300 px-2 py-1 text-xs" />
                    </ActionForm>
                  </div>
                ) : null}
                {w.status === "approved" ? (
                  <ActionForm action={revokeWaiverActionFor(w.id, w.recordVersion)} submitLabel="Revoke" loadingLabel="Revoking…" variant="destructive" className="flex items-center gap-2">
                    <input name="reason" placeholder="Revocation reason (required)" required className="rounded-md border border-neutral-300 px-2 py-1 text-xs" />
                  </ActionForm>
                ) : null}
              </li>
            ))}
          </ul>
        )}

        <div className="rounded-md border border-neutral-100 p-3">
          <h3 className="mb-2 text-xs font-semibold text-neutral-900">Request a waiver</h3>
          <ActionForm action={requestWaiverAction} submitLabel="Request" loadingLabel="Requesting…" className="grid grid-cols-1 gap-2 sm:grid-cols-4">
            <select name="requirementVersionId" required className="rounded-md border border-neutral-300 px-2 py-1 text-sm sm:col-span-2" defaultValue="">
              <option value="" disabled>
                Select a requirement
              </option>
              {publishedRequirements.map((r) => (
                <option key={r.id} value={r.id}>
                  {r.name}
                </option>
              ))}
            </select>
            <input name="validFrom" type="date" required className="rounded-md border border-neutral-300 px-2 py-1 text-sm" />
            <input name="validUntil" type="date" required className="rounded-md border border-neutral-300 px-2 py-1 text-sm" />
            <input name="reason" placeholder="Reason (required)" required className="rounded-md border border-neutral-300 px-2 py-1 text-sm sm:col-span-4" />
          </ActionForm>
        </div>
      </section>
    </div>
  );
}
