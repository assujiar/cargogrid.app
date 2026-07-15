/**
 * Central typed environment schema — single source of truth for every
 * environment variable this repository consumes.
 *
 * Prompt 86 (Environment Validation Foundation, CG-S5-PH0-007) task #1:
 * "Inventory variables and classify public/server/secret/environment-specific/
 * optional/deprecated."
 *
 * Every variable is declared exactly once here, with:
 *   - a Zod schema (the typed contract),
 *   - a classification (`public` = safe to expose to the browser bundle via
 *     Next.js's `NEXT_PUBLIC_` convention, `server` = server-only but not
 *     secret-grade, `secret` = server-only and never logged even redacted-partial),
 *   - a human description,
 *   - which environment classes require it (some variables are only
 *     meaningful in a subset of the seven tiers, `docs/architecture/11_*.md` §2).
 *
 * `validate.ts` builds the runtime-parsed schema from this registry — no
 * variable may be consumed anywhere in the codebase without first being
 * declared here (Prompt 86 §25 validation rule: "every consumed variable is
 * defined/classified and every declared variable has a consumer or
 * deprecation plan").
 */

import { z } from "zod";

/** The seven environment tiers, verbatim from `docs/architecture/11_DEVOPS_WORKSTREAM.md` §2 (Blueprint §25.1). */
export const ENVIRONMENT_CLASSES = [
  "local",
  "development",
  "testing",
  "staging",
  "uat",
  "production",
  "sandbox",
] as const;

export type EnvironmentClass = (typeof ENVIRONMENT_CLASSES)[number];

/** Tiers that must use the loopback local Supabase stack, never a shared/remote project. */
export const LOOPBACK_REQUIRED_CLASSES: readonly EnvironmentClass[] = ["local"];

export type VarClassification = "public" | "server" | "secret";

export interface EnvVarDefinition {
  readonly name: string;
  readonly classification: VarClassification;
  readonly description: string;
  readonly schema: z.ZodTypeAny;
  /** Omit to mean "required in every environment class". */
  readonly requiredIn?: readonly EnvironmentClass[];
  readonly deprecated?: boolean;
}

const urlSchema = z.url({ message: "must be a valid URL" });

/**
 * The variable registry. Adding a new environment variable anywhere in this
 * repository means adding a row here first — that is the enforcement
 * mechanism for "no unclassified variable" (§25).
 */
export const ENV_REGISTRY: readonly EnvVarDefinition[] = [
  {
    name: "CARGOGRID_ENV",
    classification: "server",
    description: "Deployment tier discriminator — one of the seven environment classes (distinct from Node's own NODE_ENV build mode).",
    schema: z.enum(ENVIRONMENT_CLASSES),
  },
  {
    name: "NODE_ENV",
    classification: "server",
    description: "Node.js/Next.js build-mode flag (development/test/production) — framework-native, not the CargoGrid environment-class discriminator.",
    schema: z.enum(["development", "test", "production"]),
  },
  {
    name: "NEXT_PUBLIC_SUPABASE_URL",
    classification: "public",
    description: "Supabase project API URL for this environment's isolated project (docs/architecture/11_*.md §2 — every non-Local environment is a fully separate Supabase project).",
    schema: urlSchema,
  },
  {
    name: "NEXT_PUBLIC_SUPABASE_ANON_KEY",
    classification: "public",
    description: "Supabase anonymous/public API key — safe for browser exposure by Supabase's own RLS-enforced design, but still validated non-empty here.",
    schema: z.string().min(1, "must not be empty"),
  },
  {
    name: "SUPABASE_SERVICE_ROLE_KEY",
    classification: "secret",
    description: "Supabase service-role key — bypasses RLS. Server-only per AGENTS.md; must never be imported from a Client Component or logged.",
    schema: z.string().min(1, "must not be empty"),
  },
  {
    name: "NEXT_PUBLIC_SITE_URL",
    classification: "public",
    description: "Canonical site URL used for auth redirect allow-listing and constructing links in emails.",
    schema: urlSchema,
  },
] as const;

/** Fails loudly at module-load time if a `secret`-classified variable is misdeclared with the NEXT_PUBLIC_ prefix — the one static leak-check we can perform before a real bundler exists (Phase 1). */
for (const def of ENV_REGISTRY) {
  if (def.classification === "secret" && def.name.startsWith("NEXT_PUBLIC_")) {
    throw new Error(
      `Environment schema error: "${def.name}" is classified "secret" but uses the NEXT_PUBLIC_ prefix, ` +
        `which Next.js inlines into the browser bundle. This is a declaration bug, not a runtime condition — fix scripts/env/schema.ts.`,
    );
  }
}

export function isRequiredIn(def: EnvVarDefinition, envClass: EnvironmentClass): boolean {
  if (def.deprecated) return false;
  if (!def.requiredIn) return true;
  return def.requiredIn.includes(envClass);
}
