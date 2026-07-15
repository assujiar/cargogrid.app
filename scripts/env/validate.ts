/**
 * Fail-fast, redacted environment validation.
 *
 * Prompt 86 (Environment Validation Foundation, CG-S5-PH0-007) task #2/#3:
 * "Implement typed schema and redacted fail-fast validation at approved
 * startup/build boundaries" + "Add cross-variable rules for environment
 * class, URLs, auth/storage/integration keys and production safeguards."
 *
 * This module supersedes Prompt 85's standalone `preflight-env-check.ts`
 * logic — that script now delegates here (see its updated body) so the
 * existing `pnpm run preflight` contract keeps working unchanged.
 */

import { z } from "zod";
import {
  ENV_REGISTRY,
  ENVIRONMENT_CLASSES,
  LOOPBACK_REQUIRED_CLASSES,
  isRequiredIn,
  type EnvironmentClass,
} from "./schema.ts";
import { describeForAudit, fingerprint } from "./redact.ts";

const LOCAL_HOSTS = new Set(["127.0.0.1", "localhost", "::1"]);

export class EnvValidationError extends Error {
  readonly failures: readonly string[];

  constructor(message: string, failures: readonly string[]) {
    super(message);
    this.name = "EnvValidationError";
    this.failures = failures;
  }
}

/** A plain env-var map — deliberately not `NodeJS.ProcessEnv` so plain test fixtures (and any
 * future non-Node runtime) can be passed without fighting Node's fixed NODE_ENV union type. */
export type EnvSource = Readonly<Record<string, string | undefined>>;

export interface ValidatedEnv {
  readonly environmentClass: EnvironmentClass;
  readonly values: Readonly<Record<string, string>>;
}

function detectEnvironmentClass(source: EnvSource): EnvironmentClass {
  const raw = source.CARGOGRID_ENV;
  const parsed = z.enum(ENVIRONMENT_CLASSES).safeParse(raw);
  if (!parsed.success) {
    throw new EnvValidationError(
      `CARGOGRID_ENV is missing or invalid — must be one of: ${ENVIRONMENT_CLASSES.join(", ")}. Got: ${raw === undefined ? "(unset)" : "(set but invalid — value withheld)"}.`,
      ["CARGOGRID_ENV"],
    );
  }
  return parsed.data;
}

function hostOf(rawUrl: string): string | undefined {
  try {
    return new URL(rawUrl).hostname;
  } catch {
    return undefined;
  }
}

/**
 * Cross-field rule (task #3): a Supabase URL's loopback-ness must match its
 * environment class. `local` must be loopback (never accidentally point a
 * developer machine at a shared project); every other tier must NOT be
 * loopback (each has its own isolated Supabase project per
 * `docs/architecture/11_*.md` §2 — a non-local tier pointed at loopback is a
 * misconfigured deploy, not a valid state).
 */
function checkProductionLinkage(envClass: EnvironmentClass, values: Record<string, string>, failures: string[]): void {
  const url = values.NEXT_PUBLIC_SUPABASE_URL;
  if (!url) return; // already reported as a missing required var

  const host = hostOf(url);
  const isLoopback = host !== undefined && LOCAL_HOSTS.has(host);
  const mustBeLoopback = LOOPBACK_REQUIRED_CLASSES.includes(envClass);

  if (mustBeLoopback && !isLoopback) {
    failures.push(
      `NEXT_PUBLIC_SUPABASE_URL must be a loopback address when CARGOGRID_ENV=${envClass} (got a non-local host) — ` +
        `local development must use \`supabase start\`, never a shared/production project.`,
    );
  }
  if (!mustBeLoopback && isLoopback) {
    failures.push(
      `NEXT_PUBLIC_SUPABASE_URL is a loopback address but CARGOGRID_ENV=${envClass} requires its own isolated Supabase project — ` +
        `a non-local tier pointed at 127.0.0.1 is a misconfigured deployment, not a valid state.`,
    );
  }
}

/**
 * Fail-fast entry point. Throws `EnvValidationError` (message never contains
 * a raw variable value — only variable names and Zod's own value-free issue
 * messages) on any failure; returns the typed, validated values on success.
 */
export function loadEnv(source: EnvSource = process.env): ValidatedEnv {
  const environmentClass = detectEnvironmentClass(source);
  const failures: string[] = [];
  const values: Record<string, string> = {};

  for (const def of ENV_REGISTRY) {
    if (def.name === "CARGOGRID_ENV") {
      values[def.name] = environmentClass;
      continue;
    }
    if (!isRequiredIn(def, environmentClass)) continue;

    const raw = source[def.name];
    if (raw === undefined || raw === "") {
      failures.push(`${def.name} is required in the "${environmentClass}" environment but is not set.`);
      continue;
    }

    const result = def.schema.safeParse(raw);
    if (!result.success) {
      const detail = result.error.issues.map((i) => i.message).join("; ");
      failures.push(`${def.name} is invalid: ${detail} (value withheld).`);
      continue;
    }

    values[def.name] = raw;
  }

  if (values.NEXT_PUBLIC_SUPABASE_URL) {
    checkProductionLinkage(environmentClass, values, failures);
  }

  if (failures.length > 0) {
    throw new EnvValidationError(
      `Environment validation failed for "${environmentClass}" (${failures.length} issue(s)):\n` +
        failures.map((f) => `  - ${f}`).join("\n"),
      failures,
    );
  }

  return { environmentClass, values };
}

/** Audit-safe summary — names/classifications/set-state only, never values (§18). */
export function summarizeForAudit(env: ValidatedEnv): string[] {
  return ENV_REGISTRY.filter((def) => isRequiredIn(def, env.environmentClass)).map((def) =>
    describeForAudit(def, def.name in env.values),
  );
}

/** Non-reversible fingerprints for evidence-readback in tests — proves a value was actually loaded without revealing it. */
export function fingerprintAll(env: ValidatedEnv): Record<string, string> {
  const out: Record<string, string> = {};
  for (const [key, value] of Object.entries(env.values)) {
    out[key] = fingerprint(value);
  }
  return out;
}
