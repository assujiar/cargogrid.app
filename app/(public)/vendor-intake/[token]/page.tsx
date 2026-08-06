import { VendorIntakeForm } from "./intake-form.tsx";

/**
 * Public vendor intake page (PRC-251, CG-S11-PRC-002). Deliberately outside every
 * tenant-authenticated portal guard (app/(public)/, the same route group
 * app/(public)/login/ and app/(public)/quote-decision/[token]/ already established) --
 * the invited vendor has no CargoGrid account. There is no separate "preview the
 * token" read here: app.redeem_vendor_intake_token_and_submit is itself the only
 * server-side action this page performs, and it never reads any existing tenant/
 * vendor data (Prompt 251 §16) -- only writes the caller's own staged submission.
 * A bad/expired/revoked/already-used-differently token surfaces as a form error
 * after submission, never a page crash.
 */
export default async function VendorIntakePage({ params }: { params: Promise<{ token: string }> }) {
  const { token } = await params;

  return (
    <main className="mx-auto flex min-h-screen max-w-md flex-col gap-6 px-4 py-10">
      <div>
        <h1 className="text-xl font-semibold text-neutral-900">Vendor registration</h1>
        <p className="text-sm text-neutral-600">You&apos;ve been invited to register as a vendor. Please provide your company details below.</p>
      </div>
      <VendorIntakeForm rawToken={token} />
    </main>
  );
}
