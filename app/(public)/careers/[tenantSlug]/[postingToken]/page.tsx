import { createHash } from "node:crypto";
import { headers } from "next/headers";
import { createSupabaseServiceRoleClient } from "../../../../../lib/supabase/service-role.ts";
import { resolvePublicJobPosting } from "../../../../../server/queries/recruitment.ts";
import { ApplyForm } from "./apply-form.tsx";

/**
 * Public job posting detail + application form (HRT-276, CG-S12-HRT-004). Every
 * failure mode (bad token, expired, revoked, vacancy no longer open) renders the SAME
 * "not available" state -- never distinguished, mirroring app.resolve_public_job_
 * posting's own uniform-collapse contract server-side.
 */
export default async function CareersPostingPage({ params }: { params: Promise<{ tenantSlug: string; postingToken: string }> }) {
  const { tenantSlug, postingToken } = await params;

  const requestHeaders = await headers();
  const ipAddress = requestHeaders.get("x-forwarded-for")?.split(",")[0]?.trim() ?? "unknown";
  const clientKey = createHash("sha256").update(ipAddress).digest("hex");

  const detail = await (async () => {
    try {
      const client = createSupabaseServiceRoleClient();
      return await resolvePublicJobPosting(client, postingToken, clientKey);
    } catch {
      return null;
    }
  })();

  if (!detail) {
    return (
      <main className="mx-auto flex min-h-screen max-w-md flex-col gap-4 px-4 py-10">
        <h1 className="text-xl font-semibold text-neutral-900">This job posting is not available</h1>
        <p className="text-sm text-neutral-600">The link may have expired, or the position may no longer be open. Please check the careers page for current openings.</p>
        <a href={`/careers/${tenantSlug}`} className="w-fit text-sm text-primary underline">
          Back to open positions
        </a>
      </main>
    );
  }

  return (
    <main className="mx-auto flex min-h-screen max-w-md flex-col gap-6 px-4 py-10">
      <div>
        <h1 className="text-xl font-semibold text-neutral-900">{detail.title}</h1>
        <p className="text-sm text-neutral-600">
          {detail.employmentType.replace("_", " ")} &middot; {detail.orgUnitName}
        </p>
      </div>
      {detail.description ? <p className="whitespace-pre-line text-sm text-neutral-700">{detail.description}</p> : null}
      {detail.requirements ? (
        <div>
          <h2 className="text-sm font-semibold text-neutral-900">Requirements</h2>
          <p className="whitespace-pre-line text-sm text-neutral-700">{detail.requirements}</p>
        </div>
      ) : null}
      <ApplyForm postingToken={postingToken} />
    </main>
  );
}
