/**
 * Feature-flag evaluation foundation — docs/standards/FEATURE_FLAG_STANDARDS.md,
 * CG-S5-PH0-019 (Prompt 98). Server-authoritative, deterministic, and
 * structurally incapable of granting authorization (§6 of that document —
 * DUP-012 "flags never bypass security"): this module has no import path to
 * anything RLS/RBAC/session-related, by construction.
 */

import { createHash } from "node:crypto";

export type Environment = "local" | "development" | "testing" | "staging" | "uat" | "production" | "sandbox";

export interface FlagDefinition {
  readonly id: string;
  readonly description: string;
  readonly owner: string;
  /** Tech Arch §27.4 dimension: environment. */
  readonly environments: readonly Environment[];
  /** Tech Arch §27.4 dimension: rollback (the kill switch — always wins, docs/standards/FEATURE_FLAG_STANDARDS.md §2). */
  readonly killSwitch: boolean;
  /** Tech Arch §27.4 dimension: rollout percentage, [0, 100]. */
  readonly rolloutPercentage: number;
  /** Tech Arch §27.4 dimension: effective date window (inclusive), both ISO 8601 or undefined for "no bound". */
  readonly effectiveFrom?: string;
  readonly effectiveUntil?: string;
  /** Tech Arch §27.4 dimension: tenant. */
  readonly tenantAllowList?: readonly string[];
  readonly tenantDenyList?: readonly string[];
  /** Tech Arch §27.4 dimension: role/user cohort. Empty/undefined means "no cohort restriction". */
  readonly cohorts?: readonly string[];
}

export interface EvaluationContext {
  readonly tenantId: string;
  readonly environment: Environment;
  readonly cohorts: readonly string[];
  readonly now: Date;
}

/** docs/standards/FEATURE_FLAG_STANDARDS.md §3 — deterministic, not Math.random(): same tenant+flag always buckets identically. */
export function bucketFor(tenantId: string, flagId: string): number {
  const hash = createHash("sha256").update(`${tenantId}:${flagId}`).digest();
  const value = hash.readUInt32BE(0);
  return value % 100;
}

export type EvaluationDecisionReason =
  | "kill_switch"
  | "environment_gate"
  | "effective_date_window"
  | "tenant_deny_list"
  | "tenant_allow_list"
  | "cohort_mismatch"
  | "rollout_bucket"
  | "default";

export interface EvaluationResult {
  readonly enabled: boolean;
  readonly reason: EvaluationDecisionReason;
}

/** docs/standards/FEATURE_FLAG_STANDARDS.md §2's fixed precedence order — evaluated top to bottom, first match decides. */
export function evaluate(flag: FlagDefinition, context: EvaluationContext): EvaluationResult {
  if (flag.killSwitch) {
    return { enabled: false, reason: "kill_switch" };
  }
  if (!flag.environments.includes(context.environment)) {
    return { enabled: false, reason: "environment_gate" };
  }
  if (flag.effectiveFrom && context.now < new Date(flag.effectiveFrom)) {
    return { enabled: false, reason: "effective_date_window" };
  }
  if (flag.effectiveUntil && context.now > new Date(flag.effectiveUntil)) {
    return { enabled: false, reason: "effective_date_window" };
  }
  if (flag.tenantDenyList?.includes(context.tenantId)) {
    return { enabled: false, reason: "tenant_deny_list" };
  }
  if (flag.tenantAllowList?.includes(context.tenantId)) {
    return { enabled: true, reason: "tenant_allow_list" };
  }
  if (flag.cohorts && flag.cohorts.length > 0) {
    const matches = flag.cohorts.some((c) => context.cohorts.includes(c));
    if (!matches) {
      return { enabled: false, reason: "cohort_mismatch" };
    }
  }
  if (bucketFor(context.tenantId, flag.id) < flag.rolloutPercentage) {
    return { enabled: true, reason: "rollout_bucket" };
  }
  return { enabled: false, reason: "default" };
}

export interface FallbackEvaluationResult {
  readonly enabled: boolean;
  readonly unknown: boolean;
  readonly degraded: boolean;
  readonly reason?: EvaluationDecisionReason;
}

/** docs/standards/FEATURE_FLAG_STANDARDS.md §4 — never throws; fail-closed by default (safeDefault should normally be false). */
export function evaluateWithFallback(
  flagId: string,
  flags: readonly FlagDefinition[] | undefined,
  context: EvaluationContext,
  safeDefault: boolean,
): FallbackEvaluationResult {
  if (flags === undefined) {
    return { enabled: safeDefault, unknown: true, degraded: true };
  }
  const flag = flags.find((f) => f.id === flagId);
  if (!flag) {
    return { enabled: safeDefault, unknown: true, degraded: false };
  }
  const result = evaluate(flag, context);
  return { enabled: result.enabled, unknown: false, degraded: false, reason: result.reason };
}

export type FlagRegistryViolationKind = "DUPLICATE_ID" | "MISSING_OWNER" | "INVALID_ROLLOUT_PERCENTAGE" | "INVALID_EFFECTIVE_WINDOW";

export interface FlagRegistryViolation {
  readonly id: string;
  readonly kind: FlagRegistryViolationKind;
}

/** docs/standards/FEATURE_FLAG_STANDARDS.md §4 — validated at registry-load time, never per-evaluation. */
export function validateFlagRegistry(flags: readonly FlagDefinition[]): FlagRegistryViolation[] {
  const violations: FlagRegistryViolation[] = [];
  const seenIds = new Set<string>();

  for (const flag of flags) {
    if (seenIds.has(flag.id)) {
      violations.push({ id: flag.id, kind: "DUPLICATE_ID" });
    }
    seenIds.add(flag.id);

    if (flag.owner.trim().length === 0) {
      violations.push({ id: flag.id, kind: "MISSING_OWNER" });
    }
    if (flag.rolloutPercentage < 0 || flag.rolloutPercentage > 100) {
      violations.push({ id: flag.id, kind: "INVALID_ROLLOUT_PERCENTAGE" });
    }
    if (flag.effectiveFrom && flag.effectiveUntil && new Date(flag.effectiveFrom) > new Date(flag.effectiveUntil)) {
      violations.push({ id: flag.id, kind: "INVALID_EFFECTIVE_WINDOW" });
    }
  }

  return violations;
}

interface CacheEntry {
  readonly value: EvaluationResult;
  readonly expiresAt: number;
}

/** docs/standards/FEATURE_FLAG_STANDARDS.md §5 — bounded, TTL-based; a stale entry expires and re-evaluates, never served indefinitely. */
export class FlagCache {
  private readonly entries = new Map<string, CacheEntry>();
  private readonly ttlMs: number;

  constructor(ttlMs: number) {
    this.ttlMs = ttlMs;
  }

  get(flagId: string, now: () => Date = () => new Date()): EvaluationResult | undefined {
    const entry = this.entries.get(flagId);
    if (!entry) return undefined;
    if (now().getTime() >= entry.expiresAt) {
      this.entries.delete(flagId);
      return undefined;
    }
    return entry.value;
  }

  set(flagId: string, value: EvaluationResult, now: () => Date = () => new Date()): void {
    this.entries.set(flagId, { value, expiresAt: now().getTime() + this.ttlMs });
  }

  invalidate(flagId: string): void {
    this.entries.delete(flagId);
  }

  size(): number {
    return this.entries.size;
  }
}
