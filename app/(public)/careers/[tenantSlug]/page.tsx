import Link from "next/link";
import { createSupabaseServiceRoleClient } from "../../../../lib/supabase/service-role.ts";
import { getPublicOpenVacancySummaries } from "../../../../server/queries/recruitment.ts";

/**
 * Public, unauthenticated careers listing (HRT-276, CG-S12-HRT-004). Deliberately
 * keyed by tenant SLUG, not tenant_id (mirrors app/(public)/vendor-intake/register/
 * [tenantSlug]/page.tsx's own established reasoning) -- a slug is already a public,
 * URL-visible identifier. Every field shown here (title/employment type/location/
 * headcount) is information a real careers page already displays; a bad slug or a
 * tenant with zero open vacancies renders the SAME empty state, never distinguished.
 */
export default async function CareersListingPage({ params }: { params: Promise<{ tenantSlug: string }> }) {
  const { tenantSlug } = await params;

  const summaries = await (async () => {
    try {
      const client = createSupabaseServiceRoleClient();
      return await getPublicOpenVacancySummaries(client, tenantSlug);
    } catch {
      return [];
    }
  })();

  return (
    <main className="mx-auto flex min-h-screen max-w-2xl flex-col gap-6 px-4 py-10">
      <div>
        <h1 className="text-xl font-semibold text-neutral-900">Open positions</h1>
        <p className="text-sm text-neutral-600">Browse current openings and apply directly -- no account required.</p>
      </div>

      {summaries.length === 0 ? (
        <p role="status" className="rounded-md border border-dashed border-neutral-300 p-8 text-center text-sm text-neutral-500">
          No open positions right now. Please check back later.
        </p>
      ) : (
        <ul className="flex flex-col gap-3">
          {summaries.map((s) => (
            <li key={s.postingToken} className="rounded-md border border-neutral-200 p-4">
              <Link href={`/careers/${tenantSlug}/${s.postingToken}`} className="text-base font-medium text-primary underline">
                {s.title}
              </Link>
              <p className="mt-1 text-sm text-neutral-600">
                {s.employmentType.replace("_", " ")} &middot; {s.orgUnitName} &middot; {s.headcount} opening{s.headcount === 1 ? "" : "s"}
              </p>
            </li>
          ))}
        </ul>
      )}
    </main>
  );
}
