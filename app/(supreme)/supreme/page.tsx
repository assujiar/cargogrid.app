import { notFound } from "next/navigation";
import { resolveSupremeAdminAccessForRequest } from "../../../lib/portal/resolve-supreme-admin-access.server.ts";

/**
 * Supreme Admin Home (PLT-136, CG-S6-PLT-033, Prompt 136 §20 task 3's "bounded
 * workflows"). Deliberately minimal for the same reason `app/(tenant)/[tenantSlug]/
 * admin/page.tsx` (`PLT-135`) is minimal -- no dashboard tile summarizes data this
 * checkpoint does not yet expose a real page for (§24: "no dead buttons").
 */
export default async function SupremeHomePage() {
  const access = await resolveSupremeAdminAccessForRequest();
  if (access.status !== "allowed") {
    notFound();
  }

  return (
    <div className="flex flex-col gap-2">
      <h1 className="text-xl font-semibold text-neutral-900">Control Plane</h1>
      <p className="text-sm text-neutral-600">Signed in as Supreme Admin.</p>
    </div>
  );
}
