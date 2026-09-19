import { notFound } from "next/navigation";
import { resolveTenantAdminAccessForRequest } from "../../../../../lib/portal/resolve-tenant-admin-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { createSupabaseServiceRoleClient } from "../../../../../lib/supabase/service-role.ts";
import { listConfigVersions, ConfigQueryError, type ConfigQueryRpcClient } from "../../../../../server/queries/config.ts";
import { listTenantRoles, toRolePermissionLookupClient, RolePermissionLookupError } from "../../../../../server/queries/role-permission.ts";
import type { ConfigVersion, ConfigVersionStatus } from "../../../../../server/contracts/config/config.ts";
import type { Role } from "../../../../../server/contracts/role-permission/role-permission.ts";
import { DataTable, type DataTableColumn } from "../../../../../components/tables/data-table.tsx";
import { StatusBadge, type StatusTone } from "../../../../../components/ui/status-badge.tsx";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";
import { PublishApprovalDefinitionForm, RollbackApprovalDefinitionForm } from "./approval-definition-forms.tsx";
import { publishApprovalDefinitionAction, rollbackApprovalDefinitionAction } from "./actions.ts";

const APPROVAL_CONFIG_TYPE_CODE = "approval";

const VERSION_STATUS_TONE: Record<ConfigVersionStatus, { tone: StatusTone; label: string }> = {
  draft: { tone: "neutral", label: "Draft" },
  published: { tone: "success", label: "Published" },
  archived: { tone: "neutral", label: "Archived" },
};

/**
 * Approval-definition authoring page (audit remediation A3b;
 * `docs/audit/2026-09-02-independent-launch-readiness-audit.md` finding A3b:
 * "publishApprovalDefinition has no caller anywhere ... The approval engine is
 * real, tested and unreachable"). One generic, tenant-scoped definition
 * (config_type_code='approval') unblocks all 8 of the finding's own named
 * dependent functions -- see `actions.ts`'s own header for why a single page
 * is the correct scope, not eight domain-specific ones. Gated the same way
 * `admin/roles` is (`resolveTenantAdminAccessForRequest`, tenant_admin/Supreme
 * only) -- PLT-121's own `app.check_config_object_authority` has no narrower
 * "who may author approval routing" permission to defer to at a tenant scope.
 *
 * Reads use two different clients on purpose: `listTenantRoles` is
 * `authenticated`-callable (the RLS-scoped client, matching `admin/roles`),
 * while `listConfigVersions` (app.list_config_versions) is service_role-only
 * -- see `server/queries/config.ts`'s own comment on that function, and the
 * adjacent finance/config bug this same discovery led to fixing.
 */
export default async function TenantAdminApprovalsPage({ params }: { params: Promise<{ tenantSlug: string }> }) {
  const { tenantSlug } = await params;
  const access = await resolveTenantAdminAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();
  const serviceRoleClient = createSupabaseServiceRoleClient();
  // Same thenable-to-Promise adapter procurement/vendors/intake/page.tsx uses.
  const configVersionsClient: ConfigQueryRpcClient = { rpc: async (fn, args) => await serviceRoleClient.rpc(fn, args) };

  let roles: Role[] = [];
  let versions: ConfigVersion[] = [];
  let loadFailed = false;
  try {
    roles = await listTenantRoles(toRolePermissionLookupClient(supabase), access.tenant.id, access.authUserId);
    versions = await listConfigVersions(configVersionsClient, {
      configTypeCode: APPROVAL_CONFIG_TYPE_CODE,
      tenantId: access.tenant.id,
      scopeLevel: "tenant",
      scopeId: null,
      actorAuthUserId: access.authUserId,
    });
  } catch (error) {
    if (!(error instanceof RolePermissionLookupError) && !(error instanceof ConfigQueryError)) {
      throw error;
    }
    loadFailed = true;
  }

  const published = versions.find((version) => version.status === "published") ?? null;

  const roleColumns: readonly DataTableColumn<Role>[] = [
    { key: "id", header: "role_id", render: (role) => <code className="text-xs">{role.id}</code> },
    { key: "name", header: "Name", render: (role) => role.name },
  ];

  const versionColumns: readonly DataTableColumn<ConfigVersion>[] = [
    { key: "versionNumber", header: "Version", render: (version) => `v${version.versionNumber}` },
    {
      key: "status",
      header: "Status",
      render: (version) => {
        const { tone, label } = VERSION_STATUS_TONE[version.status];
        return <StatusBadge tone={tone} label={label} />;
      },
    },
    { key: "effectiveFrom", header: "Effective from", render: (version) => version.effectiveFrom ?? "—" },
    { key: "publishedBy", header: "Published by", render: (version) => version.publishedBy ?? "—" },
  ];

  return (
    <div className="flex flex-col gap-6">
      <div>
        <h1 className="text-xl font-semibold text-text-primary">Approval routing</h1>
        <p className="text-sm text-text-secondary">
          Publish this organization&apos;s approval definition -- the routing every approval-gated flow (procurement, quotations, leave, payroll, onboarding, customer credit, and any generic
          request) uses once no narrower per-domain override has been published.
        </p>
      </div>

      {loadFailed ? (
        <ErrorState description="Something went wrong loading approval routing. Please try again." />
      ) : (
        <>
          <section aria-labelledby="versions-heading" className="rounded-md border border-neutral-200 p-4">
            <h2 id="versions-heading" className="text-sm font-semibold text-text-primary">
              Versions
            </h2>
            <div className="mt-2">
              <DataTable caption="Approval definition versions" columns={versionColumns} rows={versions} rowKey={(version) => version.id} emptyMessage="No approval definition has been published yet -- every approval-gated flow will fail until one is." />
            </div>
          </section>

          <section aria-labelledby="publish-heading" className="rounded-md border border-neutral-200 p-4">
            <h2 id="publish-heading" className="text-sm font-semibold text-text-primary">
              Publish a new version
            </h2>
            <p className="mt-1 text-xs text-text-secondary">Publishing supersedes any currently published version immediately -- approval requests already in flight keep the routing they started with.</p>
            <div className="mt-2">
              <PublishApprovalDefinitionForm action={publishApprovalDefinitionAction.bind(null, tenantSlug)} />
            </div>
          </section>

          {published ? (
            <section aria-labelledby="rollback-heading" className="rounded-md border border-neutral-200 p-4">
              <h2 id="rollback-heading" className="text-sm font-semibold text-text-primary">
                Roll back the published version (v{published.versionNumber})
              </h2>
              <p className="mt-1 text-xs text-text-secondary">Clones this version&apos;s item set into a brand-new version and publishes it immediately -- never mutates history.</p>
              <div className="mt-2">
                <RollbackApprovalDefinitionForm action={rollbackApprovalDefinitionAction.bind(null, tenantSlug, published.id)} />
              </div>
            </section>
          ) : null}

          <section aria-labelledby="roles-heading" className="rounded-md border border-neutral-200 p-4">
            <h2 id="roles-heading" className="text-sm font-semibold text-text-primary">
              Roles (for the definition&apos;s role_id references)
            </h2>
            <div className="mt-2">
              <DataTable caption="Roles" columns={roleColumns} rows={roles} rowKey={(role) => role.id} emptyMessage="No roles have been created for this organization yet -- create one at Admin > Roles first." />
            </div>
          </section>
        </>
      )}
    </div>
  );
}
