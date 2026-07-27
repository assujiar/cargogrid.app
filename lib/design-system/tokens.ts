/**
 * Foundations catalogue for `/internal/design-system/foundations` (CargoGrid UI
 * Modernization checkpoint 3). Every `cssVar` below is a literal, unit-tested-against-
 * source string (`tokens.test.ts` asserts it appears in `app/globals.css`) -- the
 * showcase renders swatches via the named Tailwind utility class or a `var(--x)`
 * reference, never a duplicated/approximated hex or pixel value, so a future token
 * change is reflected automatically rather than silently drifting from this file.
 *
 * `status` is honest, not aspirational: `IMPLEMENTED` means a real CSS custom property
 * exists in `app/globals.css` today; `DECIDED_NOT_IMPLEMENTED` means
 * `docs/standards/DESIGN_SYSTEM.md` §2 already decided the category but no CSS exists
 * for it yet (disclosed gap, not fabricated here); `FRAMEWORK_DEFAULT` means the value
 * comes from Tailwind v4's own un-overridden default theme, adopted by reference, not
 * authored by CargoGrid; `NOT_DECIDED` means neither this repository's code nor its
 * design-system docs have decided this category at all.
 */

export type TokenCategoryStatus = "IMPLEMENTED" | "DECIDED_NOT_IMPLEMENTED" | "FRAMEWORK_DEFAULT" | "NOT_DECIDED";

export interface TokenItem {
  readonly cssVar: string;
  readonly label: string;
  /** A Tailwind utility class that already reads this exact token, when one is auto-generated (Tailwind v4 `@theme` namespaces) -- the showcase renders the swatch through this class, not a copied value. */
  readonly utilityClass?: string;
}

export interface TokenCategory {
  readonly key: string;
  readonly title: string;
  readonly sourceFile: string;
  readonly status: TokenCategoryStatus;
  readonly note?: string;
  readonly items: readonly TokenItem[];
}

export const TOKEN_CATEGORIES: readonly TokenCategory[] = [
  {
    key: "neutral",
    title: "Neutral scale",
    sourceFile: "app/globals.css",
    status: "IMPLEMENTED",
    items: [
      { cssVar: "--color-neutral-50", label: "Neutral 50", utilityClass: "bg-neutral-50" },
      { cssVar: "--color-neutral-100", label: "Neutral 100", utilityClass: "bg-neutral-100" },
      { cssVar: "--color-neutral-200", label: "Neutral 200", utilityClass: "bg-neutral-200" },
      { cssVar: "--color-neutral-300", label: "Neutral 300", utilityClass: "bg-neutral-300" },
      { cssVar: "--color-neutral-400", label: "Neutral 400", utilityClass: "bg-neutral-400" },
      { cssVar: "--color-neutral-500", label: "Neutral 500", utilityClass: "bg-neutral-500" },
      { cssVar: "--color-neutral-600", label: "Neutral 600", utilityClass: "bg-neutral-600" },
      { cssVar: "--color-neutral-700", label: "Neutral 700", utilityClass: "bg-neutral-700" },
      { cssVar: "--color-neutral-800", label: "Neutral 800", utilityClass: "bg-neutral-800" },
      { cssVar: "--color-neutral-900", label: "Neutral 900", utilityClass: "bg-neutral-900" },
    ],
  },
  {
    key: "semantic",
    title: "Semantic status colors",
    sourceFile: "app/globals.css",
    status: "IMPLEMENTED",
    note: "Platform-controlled -- never tenant-overridable (ADR-0017 §2, structurally enforced by BrandTokensSchema's .strict() shape).",
    items: [
      { cssVar: "--color-success", label: "Success", utilityClass: "bg-success" },
      { cssVar: "--color-warning", label: "Warning", utilityClass: "bg-warning" },
      { cssVar: "--color-danger", label: "Danger", utilityClass: "bg-danger" },
      { cssVar: "--color-info", label: "Info", utilityClass: "bg-info" },
    ],
  },
  {
    key: "brand",
    title: "Brand (CargoGrid default, ADR-0016)",
    sourceFile: "app/globals.css",
    status: "IMPLEMENTED",
    note: "Tenant-overridable within RPD-019/ADR-0017 §2's boundary via lib/theme/resolve-portal-theme.ts.",
    items: [
      { cssVar: "--color-primary", label: "Primary", utilityClass: "bg-primary" },
      { cssVar: "--color-primary-hover", label: "Primary (hover)", utilityClass: "hover:bg-primary-hover" },
      { cssVar: "--color-secondary", label: "Secondary", utilityClass: "bg-secondary" },
      { cssVar: "--color-secondary-hover", label: "Secondary (hover)", utilityClass: "hover:bg-secondary-hover" },
    ],
  },
  {
    key: "surface",
    title: "Surface, text, and border",
    sourceFile: "app/globals.css",
    status: "IMPLEMENTED",
    items: [
      { cssVar: "--color-app-background", label: "App background", utilityClass: "bg-app-background" },
      { cssVar: "--color-surface", label: "Surface", utilityClass: "bg-surface" },
      { cssVar: "--color-surface-subtle", label: "Surface (subtle)", utilityClass: "bg-surface-subtle" },
      { cssVar: "--color-text-primary", label: "Text (primary)", utilityClass: "text-text-primary" },
      { cssVar: "--color-text-secondary", label: "Text (secondary)", utilityClass: "text-text-secondary" },
      { cssVar: "--color-border-default", label: "Border (default)", utilityClass: "border-border-default" },
    ],
  },
  {
    key: "typography-family",
    title: "Typography — font families",
    sourceFile: "app/globals.css",
    status: "IMPLEMENTED",
    note: "Real family names are decided (ADR-0016), but no @font-face/next/font loading is wired yet (docs/design-system/01_TOKENS_AND_THEME.md §5) -- every browser renders the system-font fallback in this stack today, not the named face. Disclosed here, not hidden.",
    items: [
      { cssVar: "--font-sans", label: "Sans (body) — Inter, fallback stack", utilityClass: "font-sans" },
      { cssVar: "--font-display", label: "Display (heading) — Space Grotesk, fallback stack", utilityClass: "font-display" },
      { cssVar: "--font-mono", label: "Mono (technical) — JetBrains Mono, fallback stack", utilityClass: "font-mono" },
    ],
  },
  {
    key: "typography-scale",
    title: "Typography — size scale",
    sourceFile: "app/globals.css",
    status: "IMPLEMENTED",
    items: [
      { cssVar: "--text-xs", label: "xs", utilityClass: "text-xs" },
      { cssVar: "--text-sm", label: "sm", utilityClass: "text-sm" },
      { cssVar: "--text-base", label: "base", utilityClass: "text-base" },
      { cssVar: "--text-lg", label: "lg", utilityClass: "text-lg" },
      { cssVar: "--text-xl", label: "xl", utilityClass: "text-xl" },
      { cssVar: "--text-2xl", label: "2xl", utilityClass: "text-2xl" },
      { cssVar: "--text-3xl", label: "3xl", utilityClass: "text-3xl" },
      { cssVar: "--text-4xl", label: "4xl", utilityClass: "text-4xl" },
    ],
  },
  {
    key: "font-weight",
    title: "Typography — font weights",
    sourceFile: "app/globals.css",
    status: "NOT_DECIDED",
    note: "No dedicated font-weight scale is authored in app/globals.css or decided in docs/standards/DESIGN_SYSTEM.md §2's token table -- existing screens use Tailwind's own default font-weight utilities (font-medium/font-semibold) directly, not a CargoGrid-specific scale. Not fabricated here.",
    items: [],
  },
  {
    key: "radius",
    title: "Border radius",
    sourceFile: "app/globals.css",
    status: "IMPLEMENTED",
    items: [
      { cssVar: "--radius-none", label: "none", utilityClass: "rounded-none" },
      { cssVar: "--radius-sm", label: "sm", utilityClass: "rounded-sm" },
      { cssVar: "--radius-md", label: "md", utilityClass: "rounded-md" },
      { cssVar: "--radius-lg", label: "lg", utilityClass: "rounded-lg" },
      { cssVar: "--radius-full", label: "full", utilityClass: "rounded-full" },
    ],
  },
  {
    key: "border",
    title: "Border tokens",
    sourceFile: "app/globals.css",
    status: "IMPLEMENTED",
    note: "One border color token exists (--color-border-default, listed under Surface above); there is no separate border-width scale decided or implemented -- screens use Tailwind's default border-width utility (border, 1px).",
    items: [{ cssVar: "--color-border-default", label: "Border (default)", utilityClass: "border-border-default" }],
  },
  {
    key: "shadow",
    title: "Shadow and elevation",
    sourceFile: "app/globals.css",
    status: "IMPLEMENTED",
    note: "Used sparingly by design (drawers/dialogs/dropdowns only, ADR-0017 §1's 85% flat / 10% elevated / 5% tactile balance) -- now consumed for real: Dialog/Drawer use shadow-lg, Popover/DropdownMenu/ContextMenu use shadow-md (checkpoint 4).",
    items: [
      { cssVar: "--shadow-sm", label: "sm", utilityClass: "shadow-sm" },
      { cssVar: "--shadow-md", label: "md", utilityClass: "shadow-md" },
      { cssVar: "--shadow-lg", label: "lg", utilityClass: "shadow-lg" },
    ],
  },
  {
    key: "density",
    title: "Density (table row height)",
    sourceFile: "app/globals.css",
    status: "IMPLEMENTED",
    note: "No auto-generated Tailwind utility exists for this custom namespace -- consumed via inline style var() reference, the same mechanism components/tables/data-table.tsx uses (its own real, current consumer).",
    items: [
      { cssVar: "--row-height-compact", label: "Compact (34px)" },
      { cssVar: "--row-height-default", label: "Default (38px)" },
      { cssVar: "--row-height-comfortable", label: "Comfortable (46px)" },
    ],
  },
  {
    key: "motion",
    title: "Motion",
    sourceFile: "app/globals.css",
    status: "IMPLEMENTED",
    note: "docs/standards/DESIGN_SYSTEM.md §2 decided a 3-step scale (fast=100ms/base=200ms/slow=300ms), but only the single default transition duration below has ever been authored as real CSS -- fast/slow were never implemented. Disclosed gap, not invented here.",
    items: [{ cssVar: "--default-transition-duration", label: "Default transition duration (200ms)" }],
  },
  {
    key: "breakpoint",
    title: "Breakpoints",
    sourceFile: "Tailwind v4 framework default (not overridden in app/globals.css)",
    status: "FRAMEWORK_DEFAULT",
    note: "docs/standards/DESIGN_SYSTEM.md §2 adopts Tailwind's own default breakpoint scale by reference rather than authoring a CargoGrid-specific one -- these values come from the framework, not this repository's own token source.",
    items: [
      { cssVar: "sm", label: "sm — 640px" },
      { cssVar: "md", label: "md — 768px" },
      { cssVar: "lg", label: "lg — 1024px" },
      { cssVar: "xl", label: "xl — 1280px" },
      { cssVar: "2xl", label: "2xl — 1536px" },
    ],
  },
  {
    key: "z-index",
    title: "Z-index scale",
    sourceFile: "—",
    status: "NOT_DECIDED",
    note: "No z-index scale exists in app/globals.css, and docs/standards/DESIGN_SYSTEM.md §2's token table has no z-index row -- this category has not been decided anywhere in this repository. Not fabricated here.",
    items: [],
  },
  {
    key: "icon-size",
    title: "Icon sizes",
    sourceFile: "—",
    status: "NOT_DECIDED",
    note: "No icon library or icon-wrapper component exists in this repository (docs/design-system/02_COMPONENTS.md has no Icon row at all), so no icon-size scale has anything to attach to yet. Not fabricated here.",
    items: [],
  },
  {
    key: "spacing",
    title: "Spacing scale",
    sourceFile: "Tailwind v4 framework default (not overridden in app/globals.css)",
    status: "FRAMEWORK_DEFAULT",
    note: "docs/standards/DESIGN_SYSTEM.md §2: \"standard Tailwind-compatible scale, no CargoGrid-specific deviation needed.\" Shown here as the framework's own 4px-based steps, not a CargoGrid override.",
    items: [
      { cssVar: "1", label: "1 — 4px", utilityClass: "p-1" },
      { cssVar: "2", label: "2 — 8px", utilityClass: "p-2" },
      { cssVar: "3", label: "3 — 12px", utilityClass: "p-3" },
      { cssVar: "4", label: "4 — 16px", utilityClass: "p-4" },
      { cssVar: "6", label: "6 — 24px", utilityClass: "p-6" },
      { cssVar: "8", label: "8 — 32px", utilityClass: "p-8" },
      { cssVar: "12", label: "12 — 48px", utilityClass: "p-12" },
      { cssVar: "16", label: "16 — 64px", utilityClass: "p-16" },
    ],
  },
  {
    key: "chart",
    title: "Chart tokens (CargoGrid Chart System)",
    sourceFile: "app/globals.css",
    status: "IMPLEMENTED",
    note: "Added checkpoint 5 (Apache ECharts). Deliberately not under --color-* -- these are resolved to concrete color strings client-side by components/charts/chart-colors.ts (getComputedStyle), never consumed as a Tailwind bg-*/text-* utility, so no dedicated utility class exists for them (swatches below use inline var() reference, the same mechanism density tokens already use).",
    items: [
      { cssVar: "--chart-primary", label: "Primary" },
      { cssVar: "--chart-secondary", label: "Secondary" },
      { cssVar: "--chart-tertiary", label: "Tertiary" },
      { cssVar: "--chart-quaternary", label: "Quaternary" },
      { cssVar: "--chart-positive", label: "Positive" },
      { cssVar: "--chart-warning", label: "Warning" },
      { cssVar: "--chart-negative", label: "Negative" },
      { cssVar: "--chart-neutral", label: "Neutral" },
      { cssVar: "--chart-forecast", label: "Forecast (dashed series)" },
      { cssVar: "--chart-target", label: "Target (mark line)" },
      { cssVar: "--chart-comparison", label: "Comparison period" },
      { cssVar: "--chart-grid", label: "Grid line" },
      { cssVar: "--chart-axis", label: "Axis label" },
      { cssVar: "--chart-axis-muted", label: "Axis line (muted)" },
      { cssVar: "--chart-tooltip-background", label: "Tooltip background" },
      { cssVar: "--chart-tooltip-foreground", label: "Tooltip text" },
      { cssVar: "--chart-tooltip-border", label: "Tooltip border" },
      { cssVar: "--chart-selection", label: "Selection" },
    ],
  },
];
