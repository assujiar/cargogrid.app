/**
 * Minimal structured (JSON-line) logging to stdout (226_GPS_TELEMATICS_INTEGRATION_
 * PROMPT.md §14B: "structured logs"). Deliberately not an import of scripts/observability/
 * logger.ts -- this package is independently deployed (see README.md) and cannot depend
 * on the main Next.js app's own module tree. The sensitive-key-name redaction pattern
 * below is intentionally duplicated from that module's own SENSITIVE_KEY_PATTERN, the
 * same "a SQL function and a TS module cannot share one source" reasoning
 * supabase/migrations/20260716113048_create_audit_trail.sql already applied to
 * app.redact_audit_payload, extended here to a second, cross-package instance.
 */

const SENSITIVE_KEY_PATTERN = /secret|password|token|key|authorization|cookie/i;

export type LogFields = Record<string, string | number | boolean | null>;

function redactFields(fields: LogFields): LogFields {
  const out: LogFields = {};
  for (const [key, value] of Object.entries(fields)) {
    out[key] = SENSITIVE_KEY_PATTERN.test(key) ? "[REDACTED]" : value;
  }
  return out;
}

export function log(level: "info" | "warn" | "error", message: string, fields: LogFields = {}): void {
  const line = JSON.stringify({
    timestamp: new Date().toISOString(),
    level,
    message,
    ...redactFields(fields),
  });
  if (level === "error") {
    console.error(line);
  } else {
    console.log(line);
  }
}
