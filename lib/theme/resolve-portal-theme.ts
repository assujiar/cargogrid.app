/**
 * Portal theme resolution (CargoGrid Design System Expansion, docs/design-system/
 * 01_TOKENS_AND_THEME.md §4). Pure function -- no Supabase/network dependency, fully
 * unit-testable -- that turns an `EffectiveTenantBrand` (or `null`, meaning "no tenant
 * context or resolution failed") into the inline CSS custom-property overrides and logo
 * URL a portal shell renders. `null` always resolves to an empty `cssVars` object and a
 * `null` logo, which lets `app/globals.css`'s compiled default (ADR-0016) show through
 * untouched -- this *is* the atomic-fallback mechanism at the UI layer: there is no
 * partial-merge code path, `resolvePortalTheme` either emits the full tenant override or
 * nothing at all.
 *
 * Deliberately has no `portal` parameter distinguishing Supreme/Tenant/Customer -- the
 * Supreme Admin shell's exclusion from tenant branding (ADR-0017 §4) is enforced by
 * `app/(supreme)/supreme/layout.tsx` never importing this module at all, not by a runtime
 * branch here a future edit could accidentally flip.
 */

export interface EffectiveTenantBrandLike {
  readonly source: "tenant" | "default";
  readonly tokens: { readonly primary?: string; readonly secondary?: string };
  readonly logoAssetUrl: string | null;
}

export interface PortalThemeResult {
  readonly source: "tenant" | "default";
  /** Inline `style` overrides for the two tenant-configurable brand tokens. Empty when there is nothing to override. */
  readonly cssVars: Readonly<Record<string, string>>;
  readonly logoAssetUrl: string | null;
}

const DEFAULT_THEME: PortalThemeResult = { source: "default", cssVars: {}, logoAssetUrl: null };

/** Resolves the CSS-variable overrides/logo for a portal shell. `brand === null` covers both "no tenant context" and "resolution failed" -- both fall back identically, on purpose (ADR-0017 §4: never a partial/flash-of-invalid theme). */
export function resolvePortalTheme(brand: EffectiveTenantBrandLike | null): PortalThemeResult {
  if (!brand) return DEFAULT_THEME;

  const cssVars: Record<string, string> = {};
  if (brand.tokens.primary) cssVars["--color-primary"] = brand.tokens.primary;
  if (brand.tokens.secondary) cssVars["--color-secondary"] = brand.tokens.secondary;

  return {
    source: brand.source,
    cssVars,
    logoAssetUrl: brand.logoAssetUrl ?? null,
  };
}
