import { notFound } from "next/navigation";
import { resolveTenantAdminAccessForRequest } from "../../../../../lib/portal/resolve-tenant-admin-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { listPortalUsers, PortalUsersQueryError, type ListPortalUsersResult } from "../../../../../server/queries/portal-users.ts";

const PAGE_SIZE = 20;

/**
 * Users list (PLT-135, CG-S6-PLT-032) -- the one bounded "core management" child slice
 * this checkpoint ships (Prompt 135 §11/§12: "exact bounded workflow adapters," never
 * an "all-admin-pages mega task"). Read-only: invite/suspend/role-assignment mutations
 * already exist as real backend capability (PLT-110/111) but their own UI is deferred
 * to a later, separately-scoped slice -- this page proves the full route -> guard ->
 * RLS-scoped query -> render pattern end to end without expanding scope beyond it.
 *
 * States (`docs/standards/DESIGN_SYSTEM.md` §4): Empty and Error are both real, distinct
 * renders below, not a bare table that silently shows nothing. A dedicated `loading.tsx`
 * sibling covers the Loading state (Suspense boundary) for this route segment. Data is
 * fetched into a plain result/error value first, with JSX construction kept entirely
 * outside the `try`/`catch` (`react-hooks/error-boundaries`) -- JSX itself never throws
 * synchronously, only the `await` above it can.
 */
export default async function TenantAdminUsersPage({
  params,
  searchParams,
}: {
  params: Promise<{ tenantSlug: string }>;
  searchParams: Promise<{ page?: string }>;
}) {
  const { tenantSlug } = await params;
  const access = await resolveTenantAdminAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const { page: pageParam } = await searchParams;
  const page = Math.max(Number.parseInt(pageParam ?? "1", 10) || 1, 1);

  const supabase = await createSupabaseServerClient();

  let result: ListPortalUsersResult | null = null;
  let loadFailed = false;
  try {
    result = await listPortalUsers(supabase, { tenantId: access.tenant.id, page, pageSize: PAGE_SIZE });
  } catch (error) {
    if (!(error instanceof PortalUsersQueryError)) {
      throw error;
    }
    loadFailed = true;
  }

  if (loadFailed || !result) {
    return (
      <div className="flex flex-col gap-2" role="alert">
        <h1 className="text-xl font-semibold text-neutral-900">Users</h1>
        <p className="text-sm text-danger">Something went wrong loading users. Please try again.</p>
      </div>
    );
  }

  if (result.users.length === 0) {
    return (
      <div className="flex flex-col gap-2">
        <h1 className="text-xl font-semibold text-neutral-900">Users</h1>
        <p className="text-sm text-neutral-600">No users found for this organization yet.</p>
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-4">
      <h1 className="text-xl font-semibold text-neutral-900">Users</h1>
      <table className="w-full border-collapse text-sm">
        <thead>
          <tr className="border-b border-neutral-200 text-left text-neutral-600">
            <th scope="col" className="py-2 pr-4 font-medium">
              Name
            </th>
            <th scope="col" className="py-2 pr-4 font-medium">
              Email
            </th>
            <th scope="col" className="py-2 font-medium">
              Status
            </th>
          </tr>
        </thead>
        <tbody>
          {result.users.map((user) => (
            <tr key={user.id} className="border-b border-neutral-100">
              <td className="py-2 pr-4 text-neutral-900">{user.displayName}</td>
              <td className="py-2 pr-4 text-neutral-600">
                {user.email ?? "—"}
                {user.emailMasked ? <span className="ml-1 text-xs text-neutral-400">(masked)</span> : null}
              </td>
              <td className="py-2 text-neutral-600">{user.status}</td>
            </tr>
          ))}
        </tbody>
      </table>
      <p className="text-xs text-neutral-500">
        Page {result.page} — {result.totalCount} total user{result.totalCount === 1 ? "" : "s"}
      </p>
    </div>
  );
}
