import { notFound } from "next/navigation";
import { resolveSupremeAdminAccessForRequest } from "../../../../lib/portal/resolve-supreme-admin-access.server.ts";
import { createSupabaseServerClient } from "../../../../lib/supabase/server.ts";
import { listPlatformIntegrationSecrets, PlatformIntegrationSecretError, type PlatformIntegrationSecretsRpcClient } from "../../../../server/mutations/platform-integration-secrets.ts";
import { ErrorState } from "../../../../components/ui/error-state.tsx";
import { EmptyState } from "../../../../components/ui/empty-state.tsx";
import { PlatformIntegrationSecretForm } from "./platform-integration-secret-form.tsx";
import type { PlatformIntegrationSecret } from "../../../../server/contracts/platform-integration/platform-integration.ts";

function formatTimestamp(value: string): string {
  return new Date(value).toLocaleString();
}

/** The real Supabase client's own `rpc` overload set does not structurally satisfy PlatformIntegrationSecretsRpcClient's narrower literal-function-name interface -- identical adapter shape to document.ts's own toDocumentClient. */
function toPlatformIntegrationSecretsClient(client: Awaited<ReturnType<typeof createSupabaseServerClient>>): PlatformIntegrationSecretsRpcClient {
  return client as unknown as PlatformIntegrationSecretsRpcClient;
}

function SecretRow({ secret }: { secret: PlatformIntegrationSecret }) {
  return (
    <tr className="border-t border-neutral-100">
      <td className="p-2 font-mono text-sm">{secret.secretKey}</td>
      <td className="p-2 text-sm text-neutral-700">{secret.description ?? "—"}</td>
      <td className="p-2 text-xs text-neutral-500">{formatTimestamp(secret.configuredAt)}</td>
      <td className="p-2 text-xs text-neutral-500">{secret.rotatedAt ? formatTimestamp(secret.rotatedAt) : "never"}</td>
    </tr>
  );
}

/**
 * Platform Integrations (Supreme Admin) -- user-directed extension of
 * CG-AUDIT-2026-09-02 A6/D4. Every existing secret-bearing table in this repository
 * (app.integration_connection_credentials and siblings) holds a TENANT's own
 * credential for its own third-party account; there was no shape for a secret the
 * PLATFORM ITSELF holds to call an outbound service on every tenant's behalf (a
 * VirusTotal malware-scan API key being the first real one). This screen is that
 * shape's first UI, generalized so any FUTURE platform-level API key is added the
 * same way rather than as an environment variable requiring a redeploy.
 *
 * The value itself is never rendered here, before or after saving -- only the key
 * name, description, and who/when configured it. `app.list_platform_integration_
 * secrets`'s own RPC return shape structurally has no value column at all.
 */
export default async function SupremeIntegrationsPage() {
  const access = await resolveSupremeAdminAccessForRequest();
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();
  let loadFailed = false;
  let secrets: readonly PlatformIntegrationSecret[] = [];

  try {
    secrets = await listPlatformIntegrationSecrets(toPlatformIntegrationSecretsClient(supabase), { actorAuthUserId: access.authUserId });
  } catch (error) {
    if (!(error instanceof PlatformIntegrationSecretError)) throw error;
    loadFailed = true;
  }

  if (loadFailed) {
    return <ErrorState description="Something went wrong loading platform integration keys. Please try again." />;
  }

  return (
    <div className="flex flex-col gap-4">
      <div>
        <h1 className="text-xl font-semibold text-neutral-900">Platform integrations</h1>
        <p className="text-xs text-neutral-500">
          API keys the CargoGrid platform itself holds to call an outbound third-party service on every tenant&apos;s behalf — never a tenant&apos;s own credential
          (those are configured per-tenant under each tenant&apos;s own Integrations screen).
        </p>
      </div>

      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        {secrets.length === 0 ? (
          <EmptyState title="No platform keys configured yet" description="Keys saved below (e.g. a VirusTotal API key for malware scanning) will appear here." />
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full border-collapse">
              <thead>
                <tr className="text-left text-xs font-medium text-neutral-500">
                  <th className="p-2">Key</th>
                  <th className="p-2">Description</th>
                  <th className="p-2">Configured</th>
                  <th className="p-2">Last rotated</th>
                </tr>
              </thead>
              <tbody>
                {secrets.map((secret) => (
                  <SecretRow key={secret.secretKey} secret={secret} />
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>

      <PlatformIntegrationSecretForm />
    </div>
  );
}
