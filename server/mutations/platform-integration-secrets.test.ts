/** Route-level unit tests for server/mutations/platform-integration-secrets.ts (user-directed extension of CG-AUDIT-2026-09-02 A6/D4). */
import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  setPlatformIntegrationSecret,
  getPlatformIntegrationSecret,
  listPlatformIntegrationSecrets,
  PlatformIntegrationSecretError,
  type PlatformIntegrationSecretsRpcClient,
} from "./platform-integration-secrets.ts";

const ACTOR_ID = "11111111-1111-4111-8111-111111111111";

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: PlatformIntegrationSecretsRpcClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as PlatformIntegrationSecretsRpcClient;
  return { client, calls };
}

const VALID_ROW = {
  secret_key: "virustotal_api_key",
  description: "VirusTotal free-tier API key",
  configured_by_auth_user_id: ACTOR_ID,
  configured_at: "2026-09-08T00:00:00.000Z",
  rotated_at: null,
};

describe("setPlatformIntegrationSecret", () => {
  test("sends the exact snake_case params, never a stray field", async () => {
    const { client, calls } = fakeRpcClient({ data: VALID_ROW, error: null });
    const secret = await setPlatformIntegrationSecret(client, {
      secretKey: "virustotal_api_key",
      secretValue: "the-real-secret-value",
      description: "VirusTotal free-tier API key",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "supreme-admin",
    });
    assert.equal(secret.secretKey, "virustotal_api_key");
    assert.deepEqual(calls, [
      {
        fn: "set_platform_integration_secret",
        args: {
          p_secret_key: "virustotal_api_key",
          p_secret_value: "the-real-secret-value",
          p_description: "VirusTotal free-tier API key",
          p_actor_auth_user_id: ACTOR_ID,
          p_actor_label: "supreme-admin",
        },
      },
    ]);
  });

  test("the returned value never carries the plaintext secret back (the RPC row itself has no such field)", async () => {
    const { client } = fakeRpcClient({ data: VALID_ROW, error: null });
    const secret = await setPlatformIntegrationSecret(client, {
      secretKey: "virustotal_api_key",
      secretValue: "the-real-secret-value",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "supreme-admin",
    });
    assert.ok(!("secretValue" in secret));
    assert.ok(!JSON.stringify(secret).includes("the-real-secret-value"));
  });

  test("rejects an empty secret value before ever calling the RPC (Zod .min(1))", async () => {
    const { client, calls } = fakeRpcClient({ data: VALID_ROW, error: null });
    await assert.rejects(() =>
      setPlatformIntegrationSecret(client, { secretKey: "virustotal_api_key", secretValue: "", actorAuthUserId: ACTOR_ID, actorLabel: "supreme-admin" }),
    );
    assert.equal(calls.length, 0);
  });

  test("rejects an invalid key shape before ever calling the RPC", async () => {
    const { client, calls } = fakeRpcClient({ data: VALID_ROW, error: null });
    await assert.rejects(() =>
      setPlatformIntegrationSecret(client, { secretKey: "Not Valid!", secretValue: "x", actorAuthUserId: ACTOR_ID, actorLabel: "supreme-admin" }),
    );
    assert.equal(calls.length, 0);
  });

  test("classifies insufficient_authority", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "insufficient_authority: identity may not configure a platform integration secret" } });
    await assert.rejects(
      setPlatformIntegrationSecret(client, { secretKey: "virustotal_api_key", secretValue: "x", actorAuthUserId: ACTOR_ID, actorLabel: "supreme-admin" }),
      (err: unknown) => err instanceof PlatformIntegrationSecretError && err.code === "insufficient_authority",
    );
  });

  test("classifies encryption_key_not_configured (CG-AUDIT-2026-09-02 D4) distinctly, not as a generic mutation_failed", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "encryption_key_not_configured: app.integration_secrets_encryption_key is not set for this session" } });
    await assert.rejects(
      setPlatformIntegrationSecret(client, { secretKey: "virustotal_api_key", secretValue: "x", actorAuthUserId: ACTOR_ID, actorLabel: "supreme-admin" }),
      (err: unknown) => err instanceof PlatformIntegrationSecretError && err.code === "encryption_key_not_configured",
    );
  });
});

describe("getPlatformIntegrationSecret", () => {
  test("resolves the decrypted value on the happy path", async () => {
    const { client, calls } = fakeRpcClient({ data: "the-real-secret-value", error: null });
    const value = await getPlatformIntegrationSecret(client, { secretKey: "virustotal_api_key" });
    assert.equal(value, "the-real-secret-value");
    assert.deepEqual(calls, [{ fn: "get_platform_integration_secret", args: { p_secret_key: "virustotal_api_key" } }]);
  });

  test("resolves null (never throws) for an unconfigured key", async () => {
    const { client } = fakeRpcClient({ data: null, error: null });
    const value = await getPlatformIntegrationSecret(client, { secretKey: "not_configured" });
    assert.equal(value, null);
  });

  test("classifies encryption_key_not_configured", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "encryption_key_not_configured: app.integration_secrets_encryption_key is not set for this session" } });
    await assert.rejects(
      getPlatformIntegrationSecret(client, { secretKey: "virustotal_api_key" }),
      (err: unknown) => err instanceof PlatformIntegrationSecretError && err.code === "encryption_key_not_configured",
    );
  });
});

describe("listPlatformIntegrationSecrets", () => {
  test("parses every row, never surfacing a value field", async () => {
    const { client, calls } = fakeRpcClient({ data: [VALID_ROW], error: null });
    const secrets = await listPlatformIntegrationSecrets(client, { actorAuthUserId: ACTOR_ID });
    assert.equal(secrets.length, 1);
    assert.equal(secrets[0]?.secretKey, "virustotal_api_key");
    assert.deepEqual(calls, [{ fn: "list_platform_integration_secrets", args: { p_actor_auth_user_id: ACTOR_ID } }]);
  });

  test("resolves an empty array when nothing is configured yet", async () => {
    const { client } = fakeRpcClient({ data: [], error: null });
    const secrets = await listPlatformIntegrationSecrets(client, { actorAuthUserId: ACTOR_ID });
    assert.deepEqual(secrets, []);
  });

  test("classifies insufficient_authority", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "insufficient_authority: identity may not list platform integration secrets" } });
    await assert.rejects(
      listPlatformIntegrationSecrets(client, { actorAuthUserId: ACTOR_ID }),
      (err: unknown) => err instanceof PlatformIntegrationSecretError && err.code === "insufficient_authority",
    );
  });

  test("throws invalid_response when the RPC does not return an array", async () => {
    const { client } = fakeRpcClient({ data: { not: "an array" }, error: null });
    await assert.rejects(
      listPlatformIntegrationSecrets(client, { actorAuthUserId: ACTOR_ID }),
      (err: unknown) => err instanceof PlatformIntegrationSecretError && err.code === "invalid_response",
    );
  });
});
