/**
 * Post-authentication redirect-target validator (PLT-107, CG-S6-PLT-004). Prompt 107
 * §16/§23/§25/§28: "redirect allowlist," "invalid redirect... fails safely," "no...
 * open redirect." A pure function -- no live request context needed to test it.
 *
 * A redirect target is safe when it is either:
 * 1. A same-origin relative path (starts with exactly one `/`, never `//` or `/\`,
 *    both of which some browsers/parsers interpret as protocol-relative and will
 *    happily navigate to an attacker-controlled host); or
 * 2. An absolute URL whose origin is explicitly present in `allowedOrigins`.
 *
 * Everything else -- `javascript:`, `data:`, `vbscript:` schemes, a bare backslash, an
 * absolute URL to a non-allowlisted origin, or a string that is neither a valid relative
 * path nor a parseable absolute URL -- is rejected.
 */

const DANGEROUS_PREFIXES = ["//", "/\\", "\\", "javascript:", "data:", "vbscript:"];

export type RedirectRejectionReason = "empty_target" | "dangerous_prefix" | "origin_not_allowlisted" | "not_a_relative_path_or_valid_url";

export interface RedirectValidationResult {
  readonly safe: boolean;
  readonly reason?: RedirectRejectionReason;
}

export function validateRedirectTarget(target: string, allowedOrigins: readonly string[] = []): RedirectValidationResult {
  if (!target || typeof target !== "string" || target.trim().length === 0) {
    return { safe: false, reason: "empty_target" };
  }

  const trimmed = target.trim();
  const lower = trimmed.toLowerCase();

  if (DANGEROUS_PREFIXES.some((prefix) => lower.startsWith(prefix))) {
    return { safe: false, reason: "dangerous_prefix" };
  }

  if (trimmed.startsWith("/")) {
    return { safe: true };
  }

  try {
    const url = new URL(trimmed);
    if (allowedOrigins.includes(url.origin)) {
      return { safe: true };
    }
    return { safe: false, reason: "origin_not_allowlisted" };
  } catch {
    return { safe: false, reason: "not_a_relative_path_or_valid_url" };
  }
}
