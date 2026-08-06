import { notFound } from "next/navigation";
import { resolveProcurementAccessForRequest } from "../../../../../../../lib/portal/resolve-procurement-access.server.ts";
import { createSupabaseServerClient } from "../../../../../../../lib/supabase/server.ts";
import { getVendorProfile, VendorProfileQueryError } from "../../../../../../../server/queries/vendor-profile.ts";
import {
  listVendorBankAccountsMasked,
  listVendorTaxIdentitiesMasked,
  listVendorPaymentTermProposals,
  getVendorFinancialVerificationStatus,
  VendorFinancialQueryError,
} from "../../../../../../../server/queries/vendor-financial.ts";
import { ErrorState } from "../../../../../../../components/ui/error-state.tsx";
import { VendorFinancialPanel } from "./financial-panel.tsx";
import {
  createVendorBankAccountDraftAction,
  updateVendorBankAccountDraftAction,
  submitVendorBankAccountForApprovalAction,
  decideVendorBankAccountApprovalAction,
  holdVendorBankAccountAction,
  reactivateVendorBankAccountAction,
  deactivateVendorBankAccountAction,
  revealVendorBankAccountNumberAction,
  accessVendorBankAccountEvidenceAction,
  createVendorTaxIdentityDraftAction,
  updateVendorTaxIdentityDraftAction,
  submitVendorTaxIdentityForApprovalAction,
  decideVendorTaxIdentityApprovalAction,
  holdVendorTaxIdentityAction,
  reactivateVendorTaxIdentityAction,
  deactivateVendorTaxIdentityAction,
  revealVendorTaxIdentityNumberAction,
  accessVendorTaxIdentityEvidenceAction,
  proposeVendorPaymentTermChangeAction,
  decideVendorPaymentTermChangeProposalAction,
} from "./actions.ts";

/**
 * A single vendor's own banking/tax security dashboard (PRC-254, CG-S11-PRC-005):
 * masked bank account / tax identity lists, a maker-checker approval queue (nested
 * per-vendor, mirroring PRC-253's own design decision 9 -- no tenant-wide pending-
 * approval list RPC was built, matching the same reasoning), a payment-term change
 * proposal/approval section, and the downstream verification-status/hold banner.
 * Mirrors procurement/compliance/vendors/[vendorMasterRecordId]/page.tsx's own
 * "authorization enforced server-side" precedent.
 */
export default async function VendorFinancialPage({ params }: { params: Promise<{ tenantSlug: string; masterRecordId: string }> }) {
  const { tenantSlug, masterRecordId } = await params;
  const access = await resolveProcurementAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();

  type Loaded = {
    vendor: Awaited<ReturnType<typeof getVendorProfile>>;
    bankAccounts: Awaited<ReturnType<typeof listVendorBankAccountsMasked>>;
    taxIdentities: Awaited<ReturnType<typeof listVendorTaxIdentitiesMasked>>;
    paymentTermProposals: Awaited<ReturnType<typeof listVendorPaymentTermProposals>>;
    verificationStatus: Awaited<ReturnType<typeof getVendorFinancialVerificationStatus>>;
  };

  let loaded: Loaded | null = null;
  let loadFailed = false;
  try {
    const vendor = await getVendorProfile(supabase, masterRecordId, access.authUserId);
    const [bankAccounts, taxIdentities, paymentTermProposals, verificationStatus] = await Promise.all([
      listVendorBankAccountsMasked(supabase, masterRecordId, access.authUserId, { limit: 200 }),
      listVendorTaxIdentitiesMasked(supabase, masterRecordId, access.authUserId, { limit: 200 }),
      listVendorPaymentTermProposals(supabase, masterRecordId, access.authUserId, { limit: 50 }),
      getVendorFinancialVerificationStatus(supabase, masterRecordId, access.authUserId),
    ]);
    loaded = { vendor, bankAccounts, taxIdentities, paymentTermProposals, verificationStatus };
  } catch (error) {
    if (!(error instanceof VendorFinancialQueryError) && !(error instanceof VendorProfileQueryError) && !(error instanceof Error)) throw error;
    if (error instanceof VendorProfileQueryError && error.message.startsWith("vendor_profile_not_found")) {
      notFound();
    }
    loadFailed = true;
  }

  if (loadFailed || !loaded) {
    return <ErrorState description="Something went wrong loading this vendor's banking and tax security record. Please try again." />;
  }

  const { vendor, bankAccounts, taxIdentities, paymentTermProposals, verificationStatus } = loaded;

  return (
    <VendorFinancialPanel
      tenantSlug={tenantSlug}
      vendor={vendor}
      bankAccounts={bankAccounts}
      taxIdentities={taxIdentities}
      paymentTermProposals={paymentTermProposals}
      verificationStatus={verificationStatus}
      createBankAccountAction={createVendorBankAccountDraftAction.bind(null, tenantSlug, masterRecordId)}
      updateBankAccountActionFor={(accountId, expectedVersion) => updateVendorBankAccountDraftAction.bind(null, tenantSlug, masterRecordId, accountId, expectedVersion)}
      submitBankAccountActionFor={(accountId, expectedVersion) => submitVendorBankAccountForApprovalAction.bind(null, tenantSlug, masterRecordId, accountId, expectedVersion)}
      decideBankAccountAction={(accountId, expectedVersion, decision, rejectionReason, reauthConfirmedAt) =>
        decideVendorBankAccountApprovalAction(tenantSlug, masterRecordId, accountId, expectedVersion, decision, rejectionReason, reauthConfirmedAt)
      }
      holdBankAccountAction={(accountId, expectedVersion, reason, reauthConfirmedAt) => holdVendorBankAccountAction(tenantSlug, masterRecordId, accountId, expectedVersion, reason, reauthConfirmedAt)}
      reactivateBankAccountAction={(accountId, expectedVersion, reauthConfirmedAt) => reactivateVendorBankAccountAction(tenantSlug, masterRecordId, accountId, expectedVersion, reauthConfirmedAt)}
      deactivateBankAccountAction={(accountId, expectedVersion, reason, reauthConfirmedAt) => deactivateVendorBankAccountAction(tenantSlug, masterRecordId, accountId, expectedVersion, reason, reauthConfirmedAt)}
      revealBankAccountAction={(accountId, revealReason, reauthConfirmedAt) => revealVendorBankAccountNumberAction(tenantSlug, accountId, revealReason, reauthConfirmedAt)}
      accessBankAccountEvidenceAction={(accountId, accessType) => accessVendorBankAccountEvidenceAction(tenantSlug, accountId, accessType)}
      createTaxIdentityAction={createVendorTaxIdentityDraftAction.bind(null, tenantSlug, masterRecordId)}
      updateTaxIdentityActionFor={(taxIdentityId, expectedVersion) => updateVendorTaxIdentityDraftAction.bind(null, tenantSlug, masterRecordId, taxIdentityId, expectedVersion)}
      submitTaxIdentityActionFor={(taxIdentityId, expectedVersion) => submitVendorTaxIdentityForApprovalAction.bind(null, tenantSlug, masterRecordId, taxIdentityId, expectedVersion)}
      decideTaxIdentityAction={(taxIdentityId, expectedVersion, decision, rejectionReason, reauthConfirmedAt) =>
        decideVendorTaxIdentityApprovalAction(tenantSlug, masterRecordId, taxIdentityId, expectedVersion, decision, rejectionReason, reauthConfirmedAt)
      }
      holdTaxIdentityAction={(taxIdentityId, expectedVersion, reason, reauthConfirmedAt) => holdVendorTaxIdentityAction(tenantSlug, masterRecordId, taxIdentityId, expectedVersion, reason, reauthConfirmedAt)}
      reactivateTaxIdentityAction={(taxIdentityId, expectedVersion, reauthConfirmedAt) => reactivateVendorTaxIdentityAction(tenantSlug, masterRecordId, taxIdentityId, expectedVersion, reauthConfirmedAt)}
      deactivateTaxIdentityAction={(taxIdentityId, expectedVersion, reason, reauthConfirmedAt) => deactivateVendorTaxIdentityAction(tenantSlug, masterRecordId, taxIdentityId, expectedVersion, reason, reauthConfirmedAt)}
      revealTaxIdentityAction={(taxIdentityId, revealReason, reauthConfirmedAt) => revealVendorTaxIdentityNumberAction(tenantSlug, taxIdentityId, revealReason, reauthConfirmedAt)}
      accessTaxIdentityEvidenceAction={(taxIdentityId, accessType) => accessVendorTaxIdentityEvidenceAction(tenantSlug, taxIdentityId, accessType)}
      proposePaymentTermAction={proposeVendorPaymentTermChangeAction.bind(null, tenantSlug, masterRecordId)}
      decidePaymentTermProposalAction={(proposalId, expectedVersion, decision, decisionReason, reauthConfirmedAt) =>
        decideVendorPaymentTermChangeProposalAction(tenantSlug, masterRecordId, proposalId, expectedVersion, decision, decisionReason, reauthConfirmedAt)
      }
    />
  );
}
