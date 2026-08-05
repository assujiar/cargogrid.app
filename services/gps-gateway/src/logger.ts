/**
 * Minimal structured (JSON-line) logging to stdout (226_GPS_TELEMATICS_INTEGRATION_
 * PROMPT.md §14B: "structured logs"). Deliberately not an import of scripts/observability/
 * logger.ts -- this package is independently deployed and cannot depend on the main
 * Next.js app's own module tree. The sensitive-key-name redaction pattern below is
 * intentionally duplicated from that module's own SENSITIVE_KEY_PATTERN, the same "a SQL
 * function and a TS module cannot share one source" reasoning
 * supabase/migrations/20260716113048_create_audit_trail.sql already applied to
 * app.redact_audit_payload, extended here to a second, cross-package instance.
 *
 * ATW-246 hardening (finding 7, log redaction bypass): the original redaction here only
 * ever inspected `fields`' own KEYS -- every real call site in server.ts instead routes
 * dynamic/error-derived content through the free-text `message` string (e.g.
 * codec8e.ts's own thrown-error messages, which embed unbounded attacker-controlled
 * payload content such as `JSON.stringify(imei)` verbatim), which was never
 * redaction-scanned at all, and an oversized value embedded there was never bounded
 * either. Widened two ways:
 *   1. `CREDENTIAL_SHAPED_VALUE_PATTERNS` scans STRING VALUES (both `message` and every
 *      string field value, not just field KEYS) for a credential shape and redacts any
 *      match in place. These four patterns are duplicated (not imported -- this package
 *      cannot depend on the main app's own module tree, see this file's own header
 *      above) from scripts/security/check-secrets.ts's own four unambiguous,
 *      low-false-positive-risk credential shapes (docs/standards/SECURITY_STANDARDS.md
 *      §3) rather than inventing a new pattern -- its fifth pattern
 *      (GENERIC_HARDCODED_SECRET_ASSIGNMENT, a "key = quoted-literal" SOURCE-CODE
 *      assignment shape) is deliberately included too, loosened to not require quote
 *      characters, since a raw device payload embedding e.g. `token=<40 random chars>`
 *      as plain text is a realistic way a credential-shaped value could end up here.
 *   2. `message` is now truncated to a bounded length after redaction -- an unbounded
 *      attacker-controlled value embedded in a log message (the exact codec8e.ts
 *      scenario above) can no longer flood log storage.
 * `fields`' own existing KEY-based redaction (SENSITIVE_KEY_PATTERN) is unchanged --
 * this widening is additive, not a replacement.
 */

const SENSITIVE_KEY_PATTERN = /secret|password|token|key|authorization|cookie/i;

// Duplicated from scripts/security/check-secrets.ts (this package cannot import it --
// see this file's own header) -- a VALUE-content scan, deliberately orthogonal to
// SENSITIVE_KEY_PATTERN's own KEY-name scan above: a field or message can carry a
// credential-shaped VALUE under a perfectly innocuous-looking key, or embedded in
// free text with no key at all. All five are given the global flag so `.replace()`
// redacts every match, not just the first.
const CREDENTIAL_SHAPED_VALUE_PATTERNS: readonly RegExp[] = [
  /\bAKIA[0-9A-Z]{16}\b/g, // AWS_ACCESS_KEY_ID
  /-----BEGIN\s+(RSA|EC|OPENSSH|DSA|ENCRYPTED)?\s?PRIVATE KEY-----/g, // PRIVATE_KEY_BLOCK
  /\bsk_live_[0-9a-zA-Z]{16,}\b/g, // STRIPE_LIVE_KEY
  /\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\b/g, // JWT_SHAPED_TOKEN
  /\b(?:secret|password|token|api[_-]?key|private[_-]?key)\b\s*[:=]\s*["']?[A-Za-z0-9+/=_.-]{20,}["']?/gi, // GENERIC_HARDCODED_SECRET_ASSIGNMENT (quotes optional -- runtime text, not source)
];

// A malformed IMEI handshake can be up to 65,535 bytes (codec8e.ts's own 2-byte
// length-prefixed handshake frame) and an AVL packet up to MAX_BUFFERED_BYTES
// (server.ts, 65,536 bytes) before either is rejected -- both already bound how much
// attacker-controlled content could ever reach a single log message, but a 2,000-
// character cap keeps any individual log line comfortably readable and bounds storage
// cost regardless of what future call site embeds dynamic content in `message`.
const MAX_MESSAGE_LENGTH = 2_000;

export type LogFields = Record<string, string | number | boolean | null>;

function redactCredentialShapedValues(value: string): string {
  let out = value;
  for (const pattern of CREDENTIAL_SHAPED_VALUE_PATTERNS) {
    out = out.replace(pattern, "[REDACTED]");
  }
  return out;
}

function truncate(value: string): string {
  if (value.length <= MAX_MESSAGE_LENGTH) {
    return value;
  }
  return `${value.slice(0, MAX_MESSAGE_LENGTH)}...[truncated ${value.length - MAX_MESSAGE_LENGTH} more chars]`;
}

function redactFields(fields: LogFields): LogFields {
  const out: LogFields = {};
  for (const [key, value] of Object.entries(fields)) {
    if (SENSITIVE_KEY_PATTERN.test(key)) {
      out[key] = "[REDACTED]";
    } else if (typeof value === "string") {
      out[key] = redactCredentialShapedValues(value);
    } else {
      out[key] = value;
    }
  }
  return out;
}

export function log(level: "info" | "warn" | "error", message: string, fields: LogFields = {}): void {
  const safeMessage = truncate(redactCredentialShapedValues(message));
  const line = JSON.stringify({
    timestamp: new Date().toISOString(),
    level,
    message: safeMessage,
    ...redactFields(fields),
  });
  if (level === "error") {
    console.error(line);
  } else {
    console.log(line);
  }
}
