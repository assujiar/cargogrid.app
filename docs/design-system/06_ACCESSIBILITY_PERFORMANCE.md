# Accessibility and Performance

Source of decisions: `docs/architecture/09_UX_DESIGN_SYSTEM_WORKSTREAM.md` §8/§9/§11 (`VERIFIED`, cited not re-derived), `docs/adr/ADR-0008` (`@axe-core/playwright` tooling choice), `AGENTS.md` (WCAG 2.2 AA and performance rules, binding). This document maps those already-decided requirements onto this checkpoint's actual token/component-level implementation.

## 1. Accessibility (WCAG 2.2 AA) — requirement-to-implementation map

| Requirement (`09_*.md` §9) | Token/component-level implementation this checkpoint | Status |
|---|---|---|
| Contrast validated per white-label theme before publish | `app.hex_color_contrast_ratio`/`app.publish_tenant_brand_version` (`PLT-117`, unchanged) enforce ≥4.5:1 for tenant `primary` against a fixed reference; CargoGrid's own default brand contrast is hand-verified and disclosed (`01_TOKENS_AND_THEME.md` §2) with a binding usage constraint (Primary is a UI-fill/large-text color, never small body text) | `IMPLEMENTED` (tenant gate) / `IMPLEMENTED` + disclosed constraint (default brand) |
| Non-color status | `StatusBadge` structurally requires a text `label`; `Banner` structurally requires text `children` — neither component has a color-only render path | `IMPLEMENTED` (for the 2 components that exist) |
| Visible focus indicators | `Button`'s `focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2` (unchanged this checkpoint) — focus treatment is fixed component geometry, never tenant-overridable (`ADR-0017` §2) | `IMPLEMENTED` (Button); `DOCUMENTED_ONLY` for every not-yet-built interactive primitive |
| Semantic labels | `StatusBadge.icon` is additive only, never a label substitute; `admin/layout.tsx`'s tenant logo `<img>` carries a real `alt` (`${tenant.slug} logo`), never empty/decorative-alt on informative content | `IMPLEMENTED` (this checkpoint's new surfaces) |
| Reduced motion | `--default-transition-duration` is respected at the component level (unchanged); no new checkpoint code introduces motion, so no new reduced-motion surface was added or needed | `IMPLEMENTED` (unchanged; nothing new to check) |
| Reflow/zoom 125–150% | No new layout was added that could break reflow (token-only + 2 small components + 1 layout's inline style) | Not separately re-tested this checkpoint — no layout-shape change occurred; `e2e/tenant-admin-portal.spec.ts`/`supreme-admin-portal.spec.ts` (pre-existing) continue to pass, unaffected |
| Touch targets | No new interactive control smaller than the existing Button's touch target was added | `IMPLEMENTED` (unchanged) |
| Accessible charts/tables/files | No chart/table/file component exists yet (`02_COMPONENTS.md` §2) | `DOCUMENTED_ONLY`/`BLOCKED` |

**Automated evidence this checkpoint:** `pnpm run test` (1128/1128, including 13 new unit tests for the theme-resolution/brand-policy pure functions), `pnpm run lint` (0 errors, pre-existing warnings unrelated to this checkpoint's changes), `pnpm run typecheck` (0 errors), `next build` (21 routes, unchanged route count, all compile). **Not run this checkpoint:** `pnpm run test:e2e` (Playwright + axe-core) — requires a browser-driven dev/build server; not executed in this pass (see `07_GAP_ANALYSIS_AND_ROADMAP.md` for why, and the recommendation to run it before this branch merges).

## 2. Performance

| Budget (`09_*.md` §11) | This checkpoint's impact |
|---|---|
| No client-side filtering of large datasets | Unaffected — no data-fetching pattern changed |
| No `SELECT *` to browser | Unaffected |
| Bundle size (dynamic import for heavy libraries) | Unaffected — no chart/map/PDF/builder library added |
| Hydration (small, task-specific Client Components) | `admin/layout.tsx` remains a Server Component (unchanged `async function`, no `"use client"` added); the new theme resolution runs server-side (`lib/portal/resolve-tenant-portal-theme.server.ts`), adding zero client JS |
| Additional network cost | One additional server-side RPC call (`app.evaluate_tenant_brand`) per Tenant Admin portal request, memoized per request via `React.cache()` (same pattern the existing access guard already uses) — no additional client-visible request; wrapped in `try`/`catch` so a slow/failing RPC degrades to the default theme rather than blocking the page indefinitely (though no explicit timeout is set — named as a follow-up hardening item, not implemented this checkpoint, since no live environment exists yet to measure real RPC latency against) |
| Font loading | Zero new network requests — `--font-sans`/`--font-display`/`--font-mono` are CSS `font-family` stacks with system fallbacks only, no `@font-face`/remote font fetch added (`01_TOKENS_AND_THEME.md` §5) |

No performance budget in `09_*.md` §11 is violated by this checkpoint's changes; the one new cost (the brand-evaluation RPC) is additive, request-memoized, and fail-soft.
