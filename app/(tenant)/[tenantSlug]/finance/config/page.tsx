import { notFound } from "next/navigation";
import Link from "next/link";
import { resolveFinanceAccessForRequest } from "../../../../../lib/portal/resolve-finance-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { listFinanceConfigVersions, resolveFinanceConfig, getFinanceConfigVersionItems, FinanceConfigQueryError } from "../../../../../server/queries/finance-config.ts";
import { FINANCE_CONFIG_CLASSES, type FinanceConfigClass, type ConfigVersion } from "../../../../../server/contracts/finance-config/finance-config.ts";
import { DataTable, type DataTableColumn } from "../../../../../components/tables/data-table.tsx";
import { StatusBadge } from "../../../../../components/ui/status-badge.tsx";
import { FINANCE_CONFIG_VERSION_STATUS_TONE_MAP } from "../../../../../components/domain/status-tone-map.ts";
import { EmptyState } from "../../../../../components/ui/empty-state.tsx";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";
import {
  createFinanceConfigDraftAction,
  setFinanceConfigItemsAction,
  publishFinanceConfigVersionAction,
  discardFinanceConfigDraftAction,
  rollbackFinanceConfigVersionAction,
} from "./actions.ts";
import {
  CreateFinanceConfigDraftForm,
  FinanceConfigItemsForm,
  PublishFinanceConfigVersionForm,
  DiscardFinanceConfigDraftForm,
  RollbackFinanceConfigVersionForm,
} from "./finance-config-forms.tsx";

const CLASS_LABELS: Record<FinanceConfigClass, string> = {
  finance_dimensions: "Accounting dimensions",
  finance_numbering: "Document numbering",
  finance_posting_map: "Posting map",
  finance_rounding: "Rounding rules",
  finance_recognition: "Budget/accrual/recognition",
  finance_close_policy: "Close policy baseline",
};

function isFinanceConfigClass(value: string | undefined): value is FinanceConfigClass {
  return (FINANCE_CONFIG_CLASSES as readonly string[]).includes(value ?? "");
}

/**
 * Finance Admin configuration workspace (FIN-191, CG-S9-FIN-002). Tabs for
 * dimensions/numbering/posting/rounding/budget-accrual-recognition/close-policy
 * (Prompt 191 §15) rendered as plain server-navigable links (`?class=...`) rather
 * than client-side Radix tabs -- every tab is its own full server render with the
 * exact effective policy/version list for that class, matching this repository's
 * own established server-component-first convention (`commercial/reports/[reportCode]`).
 * Tenant scope only this checkpoint (`scopeLevel='tenant'`, `scopeId=null`) -- the
 * database/API already support company/branch/role/user scope; a scope-selector UI
 * is a disclosed, bounded follow-up (Prompt 191 §22's "clone/future-date" alternative
 * flow is likewise not built in this first UI slice).
 */
export default async function FinanceConfigPage({
  params,
  searchParams,
}: {
  params: Promise<{ tenantSlug: string }>;
  searchParams: Promise<{ class?: string }>;
}) {
  const { tenantSlug } = await params;
  const { class: rawClass } = await searchParams;
  const access = await resolveFinanceAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const selectedClass: FinanceConfigClass = isFinanceConfigClass(rawClass) ? rawClass : "finance_dimensions";
  const supabase = await createSupabaseServerClient();

  let versions: ConfigVersion[] = [];
  let effectiveItems: Record<string, unknown> | null = null;
  let loadFailed = false;
  try {
    versions = await listFinanceConfigVersions(supabase, {
      configTypeCode: selectedClass,
      tenantId: access.tenant.id,
      scopeLevel: "tenant",
      scopeId: null,
      actorAuthUserId: access.authUserId,
    });
    const resolved = await resolveFinanceConfig(supabase, { configTypeCode: selectedClass, tenantId: access.tenant.id });
    effectiveItems = resolved?.items ?? null;
  } catch (error) {
    if (!(error instanceof FinanceConfigQueryError)) {
      throw error;
    }
    loadFailed = true;
  }

  const draft = versions.find((version) => version.status === "draft") ?? null;
  const published = versions.find((version) => version.status === "published") ?? null;

  let draftItemsJson = "{}";
  if (draft && !loadFailed) {
    try {
      const draftItems = await getFinanceConfigVersionItems(supabase, draft.id, access.authUserId);
      draftItemsJson = JSON.stringify(draftItems, null, 2);
    } catch {
      // Non-fatal: the items editor simply starts blank if this secondary read
      // fails (e.g. a permission edge case) -- the versions table above still
      // renders, and saving still fully replaces the item set either way.
      draftItemsJson = "{}";
    }
  }

  const columns: readonly DataTableColumn<ConfigVersion>[] = [
    { key: "versionNumber", header: "Version", render: (version) => `v${version.versionNumber}` },
    {
      key: "status",
      header: "Status",
      render: (version) => {
        const { tone, label } = FINANCE_CONFIG_VERSION_STATUS_TONE_MAP[version.status];
        return <StatusBadge tone={tone} label={label} />;
      },
    },
    { key: "effectiveFrom", header: "Effective from", render: (version) => version.effectiveFrom ?? "—" },
    { key: "publishedBy", header: "Published by", render: (version) => version.publishedBy ?? "—" },
  ];

  return (
    <div className="flex flex-col gap-6">
      <div>
        <h1 className="text-xl font-semibold text-text-primary">Finance Configuration</h1>
        <p className="text-sm text-text-secondary">Versioned accounting policy: dimensions, document numbering, posting map, rounding, budget/accrual/recognition, and close-dependency baseline.</p>
      </div>

      <nav aria-label="Finance Configuration classes" className="flex flex-wrap gap-1 border-b border-neutral-200">
        {FINANCE_CONFIG_CLASSES.map((configClass) => {
          const active = configClass === selectedClass;
          return (
            <Link
              key={configClass}
              href={`/${tenantSlug}/finance/config?class=${configClass}`}
              aria-current={active ? "page" : undefined}
              className={`border-b-2 px-3 py-2 text-sm font-medium ${active ? "border-primary text-primary" : "border-transparent text-text-secondary hover:text-text-primary"}`}
            >
              {CLASS_LABELS[configClass]}
            </Link>
          );
        })}
      </nav>

      {loadFailed ? (
        <ErrorState description="Something went wrong loading Finance Configuration. Please try again." />
      ) : (
        <>
          <section aria-labelledby="effective-policy-heading" className="rounded-md border border-neutral-200 p-4">
            <h2 id="effective-policy-heading" className="text-sm font-semibold text-text-primary">
              Effective policy (currently in force)
            </h2>
            {effectiveItems ? (
              <pre className="mt-2 overflow-x-auto rounded-md bg-neutral-50 p-3 text-xs" aria-label="Effective policy items, JSON">
                {JSON.stringify(effectiveItems, null, 2)}
              </pre>
            ) : (
              <p className="mt-2 text-sm text-text-secondary">No published version yet at any scope level -- no effective policy is currently in force for this class.</p>
            )}
          </section>

          <section aria-labelledby="versions-heading" className="rounded-md border border-neutral-200 p-4">
            <h2 id="versions-heading" className="text-sm font-semibold text-text-primary">
              Versions
            </h2>
            <div className="mt-2">
              {versions.length === 0 ? (
                <EmptyState
                  title="No versions yet"
                  description="Start a draft to configure this class."
                  primaryAction={<CreateFinanceConfigDraftForm action={createFinanceConfigDraftAction.bind(null, tenantSlug, selectedClass)} />}
                />
              ) : (
                <DataTable caption={`${CLASS_LABELS[selectedClass]} versions`} columns={columns} rows={versions} rowKey={(version) => version.id} emptyMessage="No versions yet." />
              )}
            </div>
          </section>

          {draft ? (
            <section aria-labelledby="draft-heading" className="rounded-md border border-neutral-200 p-4">
              <h2 id="draft-heading" className="text-sm font-semibold text-text-primary">
                Draft v{draft.versionNumber}
              </h2>
              <div className="mt-2 flex flex-col gap-4 sm:flex-row sm:gap-8">
                <div className="flex-1">
                  <FinanceConfigItemsForm action={setFinanceConfigItemsAction.bind(null, tenantSlug, draft.id)} initialItemsJson={draftItemsJson} />
                </div>
                <div className="flex flex-col gap-4">
                  <PublishFinanceConfigVersionForm action={publishFinanceConfigVersionAction.bind(null, tenantSlug, draft.id)} />
                  <DiscardFinanceConfigDraftForm action={discardFinanceConfigDraftAction.bind(null, tenantSlug, draft.id)} />
                </div>
              </div>
            </section>
          ) : (
            <CreateFinanceConfigDraftForm action={createFinanceConfigDraftAction.bind(null, tenantSlug, selectedClass)} />
          )}

          {published ? (
            <section aria-labelledby="rollback-heading" className="rounded-md border border-neutral-200 p-4">
              <h2 id="rollback-heading" className="text-sm font-semibold text-text-primary">
                Roll back the published version (v{published.versionNumber})
              </h2>
              <p className="mt-1 text-xs text-text-secondary">Clones this version&apos;s item set into a brand-new version and publishes it immediately -- never mutates history.</p>
              <div className="mt-2">
                <RollbackFinanceConfigVersionForm action={rollbackFinanceConfigVersionAction.bind(null, tenantSlug, published.id)} />
              </div>
            </section>
          ) : null}
        </>
      )}
    </div>
  );
}
