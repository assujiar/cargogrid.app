/**
 * Redaction helpers — Prompt 86 §18 (audit): "Log validation outcome/
 * environment class/version without values" and §24: "Errors name variable/
 * control without outputting value."
 */

import type { EnvVarDefinition } from "./schema.ts";

/** Never returns the actual value — only whether it was set, and its declared classification. */
export function describeForAudit(def: EnvVarDefinition, isSet: boolean): string {
  return `${def.name} [${def.classification}]: ${isSet ? "SET" : "MISSING"}`;
}

/**
 * A short, non-reversible fingerprint for evidence-readback in tests/logs —
 * proves a value was consumed without revealing or making it guessable.
 * Not a security control (not constant-time, not cryptographically sized for
 * secret-storage use) — purely a "which value did we actually load" debugging aid.
 */
export function fingerprint(value: string): string {
  let hash = 0;
  for (let i = 0; i < value.length; i++) {
    hash = (hash * 31 + value.charCodeAt(i)) | 0;
  }
  return `len${value.length}:${(hash >>> 0).toString(16)}`;
}
