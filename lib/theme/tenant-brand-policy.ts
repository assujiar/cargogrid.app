/**
 * Tenant brand distinguishability policy (CargoGrid Design System Expansion,
 * docs/design-system/01_TOKENS_AND_THEME.md §3.1). Defense-in-depth heuristic for a
 * tenant's proposed `primary`/`secondary` colors -- NOT a substitute for the DB-layer
 * WCAG contrast gate (`app.hex_color_contrast_ratio`, `supabase/migrations/
 * 20260717090512_create_white_label.sql`), which remains the authoritative text-contrast
 * enforcement. This module catches a different failure mode that gate does not: a
 * tenant color that is a near-exact duplicate of a reserved platform semantic color (so
 * a "primary" action could be visually confused with a danger/warning/success/info
 * signal), or of the tenant's own other brand color.
 *
 * Standalone this checkpoint -- not yet called from `server/mutations/white-label.ts`'s
 * `setTenantBrandTokens`/`publishTenantBrandVersion`. Wiring it into that enforced path
 * changes tested `PLT-117` publish behavior and is deliberately deferred, not silently
 * skipped -- see docs/design-system/01_TOKENS_AND_THEME.md §3.1 and
 * docs/design-system/07_GAP_ANALYSIS_AND_ROADMAP.md.
 */

export interface TenantBrandTokensLike {
  readonly primary?: string;
  readonly secondary?: string;
}

export type BrandPolicyViolationCode = "invalid_hex" | "near_duplicate_of_semantic_color" | "primary_secondary_indistinguishable";

export interface BrandPolicyViolation {
  readonly code: BrandPolicyViolationCode;
  readonly message: string;
}

export interface BrandPolicyResult {
  readonly ok: boolean;
  readonly violations: readonly BrandPolicyViolation[];
}

/** Mirrors app/globals.css's `--color-success/warning/danger/info` -- reproduced here (not imported) since this module intentionally has no build/CSS dependency, only plain TS. */
const RESERVED_SEMANTIC_COLORS = {
  success: "#15803d",
  warning: "#b45309",
  danger: "#b91c1c",
  info: "#1d4ed8",
} as const;

/**
 * RGB Euclidean distance below this is treated as visually indistinguishable, not merely
 * "similar hue family" -- deliberately tight so a legitimate brand red (e.g. CargoGrid's
 * own default secondary, `#CB3421`, distance ~30 from danger `#B91C1C`) never trips this
 * check. See docs/design-system/01_TOKENS_AND_THEME.md §3.1.
 */
const NEAR_DUPLICATE_THRESHOLD = 12;

const HEX_PATTERN = /^#[0-9a-fA-F]{6}$/;

function hexToRgb(hex: string): readonly [number, number, number] {
  const value = parseInt(hex.slice(1), 16);
  return [(value >> 16) & 0xff, (value >> 8) & 0xff, value & 0xff];
}

function rgbDistance(a: string, b: string): number {
  const [ar, ag, ab] = hexToRgb(a);
  const [br, bg, bb] = hexToRgb(b);
  return Math.sqrt((ar - br) ** 2 + (ag - bg) ** 2 + (ab - bb) ** 2);
}

export function evaluateTenantBrandPolicy(tokens: TenantBrandTokensLike): BrandPolicyResult {
  const violations: BrandPolicyViolation[] = [];
  const entries = (Object.entries(tokens) as Array<[string, string | undefined]>).filter(
    (entry): entry is [string, string] => Boolean(entry[1]),
  );

  for (const [key, hex] of entries) {
    if (!HEX_PATTERN.test(hex)) {
      violations.push({ code: "invalid_hex", message: `${key} is not a #RRGGBB hex color: ${hex}` });
      continue;
    }
    for (const [semanticName, semanticHex] of Object.entries(RESERVED_SEMANTIC_COLORS)) {
      if (rgbDistance(hex, semanticHex) < NEAR_DUPLICATE_THRESHOLD) {
        violations.push({
          code: "near_duplicate_of_semantic_color",
          message: `${key} (${hex}) is visually indistinguishable from the reserved "${semanticName}" semantic color (${semanticHex})`,
        });
      }
    }
  }

  if (
    tokens.primary &&
    tokens.secondary &&
    HEX_PATTERN.test(tokens.primary) &&
    HEX_PATTERN.test(tokens.secondary) &&
    rgbDistance(tokens.primary, tokens.secondary) < NEAR_DUPLICATE_THRESHOLD
  ) {
    violations.push({
      code: "primary_secondary_indistinguishable",
      message: `primary (${tokens.primary}) and secondary (${tokens.secondary}) are visually indistinguishable from each other`,
    });
  }

  return { ok: violations.length === 0, violations };
}
