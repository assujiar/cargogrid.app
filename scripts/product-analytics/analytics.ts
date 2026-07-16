/**
 * Vendor-neutral product-analytics foundation — docs/standards/
 * PRODUCT_ANALYTICS_STANDARDS.md, CG-S5-PH0-018 (Prompt 97). No provider is
 * integrated (§6 of that document — no ADR approves one yet, and Prompt 97
 * §12 forbids unapproved vendor integration); this module fixes the event
 * shape, validation, pseudonymization, dedup, and safe-degrade delivery
 * contract Phase 1's real transport wraps.
 */

import { createHmac } from "node:crypto";

export const EVENT_SCHEMA_VERSION = 1;

export type ConsentState = "granted" | "denied" | "not_required";

export type EventSource = "web" | "api" | "job";

export interface AnalyticsContext {
  readonly source: EventSource;
  readonly appVersion?: string;
}

export type JSONValue = string | number | boolean | null | JSONValue[] | { [key: string]: JSONValue };

export interface AnalyticsEventInput {
  readonly event: string;
  readonly pseudonymousId: string;
  readonly tenantRef: string;
  readonly context: AnalyticsContext;
  readonly properties?: Record<string, JSONValue>;
  readonly consentState: ConsentState;
}

export interface AnalyticsEvent extends AnalyticsEventInput {
  readonly version: number;
  readonly timestamp: string;
  readonly eventId: string;
}

/** docs/standards/PRODUCT_ANALYTICS_STANDARDS.md §2 — "<domain>.<action>", lowercase snake_case segments. */
const EVENT_NAME_PATTERN = /^[a-z][a-z0-9_]*\.[a-z][a-z0-9_]*$/;

export function validateEventName(name: string): boolean {
  return EVENT_NAME_PATTERN.test(name);
}

/**
 * docs/standards/PRODUCT_ANALYTICS_STANDARDS.md §3 — deliberately broader
 * than scripts/observability/logger.ts's redaction list: that list redacts
 * and still logs (operational debugging need); this one rejects the whole
 * event outright (no such need for an analytics payload).
 */
const PROHIBITED_PROPERTY_KEY_PATTERN =
  /secret|password|token|api[_-]?key|authorization|cookie|ssn|npwp|bank|account[_-]?number|salary|payroll|email|phone|address|\bname\b|tax/i;

export function findProhibitedProperties(properties: Record<string, JSONValue> | undefined): string[] {
  if (!properties) return [];
  return Object.keys(properties).filter((key) => PROHIBITED_PROPERTY_KEY_PATTERN.test(key));
}

export function isConsentGranted(state: ConsentState): boolean {
  return state === "granted" || state === "not_required";
}

const MAX_PROPERTIES_PAYLOAD_BYTES = 8192;

export function payloadSizeBytes(properties: Record<string, JSONValue> | undefined): number {
  return Buffer.byteLength(JSON.stringify(properties ?? {}), "utf8");
}

export type EventRejectionReason = "INVALID_EVENT_NAME" | "PROHIBITED_PROPERTY" | "OVERSIZED_PAYLOAD" | "CONSENT_NOT_GRANTED";

export interface EventValidationResult {
  readonly valid: boolean;
  readonly reasons: readonly EventRejectionReason[];
}

/** docs/standards/PRODUCT_ANALYTICS_STANDARDS.md §3 — every rejection reason is independently checkable, not short-circuited, so a caller sees every real problem at once. */
export function validateEvent(input: AnalyticsEventInput): EventValidationResult {
  const reasons: EventRejectionReason[] = [];
  if (!validateEventName(input.event)) reasons.push("INVALID_EVENT_NAME");
  if (findProhibitedProperties(input.properties).length > 0) reasons.push("PROHIBITED_PROPERTY");
  if (payloadSizeBytes(input.properties) > MAX_PROPERTIES_PAYLOAD_BYTES) reasons.push("OVERSIZED_PAYLOAD");
  if (!isConsentGranted(input.consentState)) reasons.push("CONSENT_NOT_GRANTED");
  return { valid: reasons.length === 0, reasons };
}

/**
 * docs/standards/PRODUCT_ANALYTICS_STANDARDS.md §3 — real HMAC-SHA256, not a
 * placeholder: deterministic per salt (same real user always pseudonymizes
 * identically, so funnel analysis works), non-reversible without the salt.
 * Disclosed limitation: the salt itself must be a secret-classified
 * environment variable once Phase 1 wires real delivery (§3), not a
 * hardcoded value — this function's contract is correct today, its real
 * production salt source is not.
 */
export function pseudonymizeId(rawId: string, salt: string): string {
  return createHmac("sha256", salt).update(rawId).digest("hex");
}

export function buildEvent(input: AnalyticsEventInput, eventId: string, now: () => Date = () => new Date()): AnalyticsEvent {
  return { ...input, version: EVENT_SCHEMA_VERSION, timestamp: now().toISOString(), eventId };
}

/** docs/standards/PRODUCT_ANALYTICS_STANDARDS.md §4 — in-memory per-process dedup; Phase 1 extends with a durable, time-windowed store, not a redesign. */
export class Deduplicator {
  private readonly seen = new Set<string>();

  isDuplicate(eventId: string): boolean {
    if (this.seen.has(eventId)) return true;
    this.seen.add(eventId);
    return false;
  }

  size(): number {
    return this.seen.size;
  }
}

export type AnalyticsSink = (event: AnalyticsEvent) => void;

const noopSink: AnalyticsSink = () => {};

export type TrackFailureReason = EventRejectionReason | "DISABLED" | "DUPLICATE" | "SINK_ERROR";

export interface TrackResult {
  readonly delivered: boolean;
  readonly reasons: readonly TrackFailureReason[];
}

export interface TrackOptions {
  /** Models "consent/provider/config absent" (Prompt 97 §22) — false means safely disabled, zero validation/sink work attempted. */
  readonly enabled: boolean;
  readonly sink?: AnalyticsSink;
  readonly deduplicator?: Deduplicator;
}

/**
 * docs/standards/PRODUCT_ANALYTICS_STANDARDS.md §4 — safe-disablement and
 * safe-degrade are both binding (Prompt 97 §21/§22/§23): disabled short-
 * circuits before any work; a sink failure never propagates to the caller.
 */
export function track(input: AnalyticsEventInput, eventId: string, options: TrackOptions): TrackResult {
  if (!options.enabled) {
    return { delivered: false, reasons: ["DISABLED"] };
  }

  const validation = validateEvent(input);
  if (!validation.valid) {
    return { delivered: false, reasons: validation.reasons };
  }

  if (options.deduplicator?.isDuplicate(eventId)) {
    return { delivered: false, reasons: ["DUPLICATE"] };
  }

  const event = buildEvent(input, eventId);
  const sink = options.sink ?? noopSink;
  try {
    sink(event);
  } catch {
    return { delivered: false, reasons: ["SINK_ERROR"] };
  }
  return { delivered: true, reasons: [] };
}
