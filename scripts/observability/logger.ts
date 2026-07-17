/**
 * Vendor-neutral structured-logging foundation — docs/standards/
 * OBSERVABILITY_STANDARDS.md §3–§5/§8, CG-S5-PH0-014 (Prompt 93). Real Better
 * Stack export (ADR-0009) is wired in Phase 1 via Next.js's own
 * `@vercel/otel`/`instrumentation.ts` mechanism, not this module — this
 * module only fixes the event shape, redaction, and safe-degrade contract
 * that future instrumentation consumes unchanged.
 */

import { fingerprint } from "../env/redact.ts";

export const SEVERITIES = ["debug", "info", "warn", "error", "critical"] as const;
export type Severity = (typeof SEVERITIES)[number];

const SEVERITY_ORDER: Record<Severity, number> = { debug: 0, info: 1, warn: 2, error: 3, critical: 4 };

/** Total ordering: negative if `a` is less severe than `b`, positive if more severe, 0 if equal. */
export function compareSeverity(a: Severity, b: Severity): number {
  return SEVERITY_ORDER[a] - SEVERITY_ORDER[b];
}

export const SOURCES = ["api", "job", "webhook", "db", "auth", "system"] as const;
export type Source = (typeof SOURCES)[number];

export type JSONValue = string | number | boolean | null | JSONValue[] | { [key: string]: JSONValue };

/**
 * Key-name patterns that trigger redaction — docs/standards/
 * OBSERVABILITY_STANDARDS.md §4's fixed sensitive-key list. Case-insensitive,
 * matches a key that *contains* the pattern (e.g. "supabaseServiceKey"
 * matches "key").
 */
const SENSITIVE_KEY_PATTERN = /secret|password|token|key|authorization|cookie|ssn|npwp|bank|account_number|salary|payroll/i;

function redactValue(value: JSONValue): JSONValue {
  if (typeof value === "string") return fingerprint(value);
  if (typeof value === "number" || typeof value === "boolean" || value === null) return fingerprint(String(value));
  return fingerprint(JSON.stringify(value));
}

/**
 * Recursively replaces every value whose key matches SENSITIVE_KEY_PATTERN
 * with a non-reversible fingerprint (never the literal value, never a naive
 * mask that leaks length/shape) — docs/standards/OBSERVABILITY_STANDARDS.md
 * §4. Only covers structured `fields`; free-text `message` is a
 * caller-discipline surface (same document, §3) — not claimed here.
 */
export function redact(value: Record<string, JSONValue>): Record<string, JSONValue> {
  const out: Record<string, JSONValue> = {};
  for (const [key, v] of Object.entries(value)) {
    if (SENSITIVE_KEY_PATTERN.test(key)) {
      out[key] = redactValue(v);
    } else if (v !== null && typeof v === "object" && !Array.isArray(v)) {
      out[key] = redact(v as Record<string, JSONValue>);
    } else {
      out[key] = v;
    }
  }
  return out;
}

/** docs/standards/OBSERVABILITY_STANDARDS.md §2 — production callers use crypto.randomUUID(); tests inject a fixed id. */
export function generateCorrelationId(): string {
  return crypto.randomUUID();
}

export interface LogEvent {
  readonly timestamp: string;
  readonly severity: Severity;
  readonly event: string;
  readonly message: string;
  readonly correlation_id: string;
  readonly source: Source;
  readonly tenant_id?: string;
  readonly fields?: Record<string, JSONValue>;
}

export interface LogInput {
  readonly severity: Severity;
  readonly event: string;
  readonly message: string;
  readonly correlationId: string;
  readonly source: Source;
  readonly tenantId?: string;
  readonly fields?: Record<string, JSONValue>;
}

/** docs/standards/OBSERVABILITY_STANDARDS.md §3's fixed event shape — pure, no I/O, easy to test independent of any sink. */
export function buildLogEvent(input: LogInput, now: () => Date = () => new Date()): LogEvent {
  return {
    timestamp: now().toISOString(),
    severity: input.severity,
    event: input.event,
    message: input.message,
    correlation_id: input.correlationId,
    source: input.source,
    ...(input.tenantId !== undefined ? { tenant_id: input.tenantId } : {}),
    ...(input.fields !== undefined ? { fields: redact(input.fields) } : {}),
  };
}

export type Sink = (line: string) => void;

const defaultPrimarySink: Sink = (line) => {
  console.log(line);
};

const defaultFallbackSink: Sink = (line) => {
  process.stderr.write(line + "\n");
};

/**
 * Safe-degrade rule — docs/standards/OBSERVABILITY_STANDARDS.md §8, Prompt 93
 * §21/§22 (binding): a telemetry sink failure must never propagate to the
 * caller. Wraps `primary`; on throw, falls back to `fallback` (itself
 * swallowed if it also throws) rather than rethrowing.
 */
export function emit(event: LogEvent, primary: Sink = defaultPrimarySink, fallback: Sink = defaultFallbackSink): void {
  const line = JSON.stringify(event);
  try {
    primary(line);
  } catch {
    try {
      fallback(line);
    } catch {
      // Deliberately swallowed — a logging failure must never surface as an
      // exception to the caller's real request/job/transaction (§8).
    }
  }
}

export function log(input: LogInput, primary?: Sink, fallback?: Sink): void {
  emit(buildLogEvent(input), primary, fallback);
}

/**
 * Bounded-dimension guard — docs/standards/OBSERVABILITY_STANDARDS.md §5.
 * `tenant_id`/`correlation_id`/free text must never be used as a metric
 * label (unbounded cardinality); only a fixed, finite allowlist may. Returns
 * false (does not throw — a bad dimension is a data-quality signal, not a
 * reason to crash the caller, same safe-degrade spirit as §8) when `value`
 * is not in `allowed`.
 */
export function assertBoundedDimension(value: string, allowed: readonly string[]): boolean {
  return allowed.includes(value);
}
