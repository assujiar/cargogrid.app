# Design Tokens and Theme System

Source of decisions: `docs/standards/DESIGN_SYSTEM.md` §2/§3 (structure, values), `ADR-0006` (mechanism), `ADR-0016` (brand values), `ADR-0017` (governance boundary, resolution order). This document is the implementation-precision detail layer — it does not re-decide anything those documents already fixed.

## 1. Token catalogue (as authored in `app/globals.css`, this checkpoint)

| Category | Tokens | Status |
|---|---|---|
| Neutral scale | `--color-neutral-50`…`--color-neutral-900` | `IMPLEMENTED` (unchanged this checkpoint, Prompt 135) |
| Semantic status | `--color-success`, `--color-warning`, `--color-danger`, `--color-info` | `IMPLEMENTED` (unchanged this checkpoint; platform-controlled, never tenant-overridable — `ADR-0017` §2) |
| Brand | `--color-primary` (`#0097B2`), `--color-primary-hover` (`#007D94`), `--color-secondary` (`#CB3421`), `--color-secondary-hover` (`#A52313`) | `IMPLEMENTED` this checkpoint (`ADR-0016`) — previously a disclosed neutral-scale placeholder |
| Surface/text/border | `--color-app-background` (`#EAF0F6`), `--color-surface` (`#FFFFFF`), `--color-surface-subtle` (`#F0F4F8`), `--color-text-primary` (`#2C3E50`), `--color-text-secondary` (`#4A5C6E`), `--color-border-default` (= `--color-neutral-200`) | `IMPLEMENTED` this checkpoint — new token category, did not exist before |
| Typography scale | `--text-xs`…`--text-4xl` | `IMPLEMENTED` (unchanged, Prompt 135) |
| Typography family | `--font-sans` (Inter stack), `--font-display` (Space Grotesk stack), `--font-mono` (JetBrains Mono stack) | `IMPLEMENTED` this checkpoint (`ADR-0016`) — **font-loading gap**: stacks are authored with system fallbacks; no `@font-face`/`next/font` self-hosting exists, so every browser renders the fallback face today, not the named one. `DEFERRED` — see §5. |
| Spacing | Tailwind's default 4px-based scale (no CargoGrid override) | `IMPLEMENTED` (Tailwind v4 default, unchanged) |
| Radius | `--radius-none/sm/md/lg/full` | `IMPLEMENTED` (unchanged, Prompt 135) |
| Elevation | `--shadow-sm/md/lg` | `IMPLEMENTED` this checkpoint — decided in principle since Prompt 90, never authored in CSS until now |
| Motion | `--default-transition-duration: 200ms` | `IMPLEMENTED` (unchanged, Prompt 135). `fast=100ms`/`slow=300ms` remain decided values (`DESIGN_SYSTEM.md` §2) with no second CSS custom property authored for them yet — components apply them via Tailwind's `duration-*` utilities directly where needed; `DOCUMENTED_ONLY` as named tokens. |
| Density (row height) | `--row-height-compact` (34px), `--row-height-default` (38px), `--row-height-comfortable` (46px) | `IMPLEMENTED` this checkpoint (tokens only — no table primitive consumes them yet, `02_COMPONENTS.md`) |

**Consumption rule (unchanged, restated):** components consume semantic token names (`var(--color-primary)`, Tailwind's generated `bg-primary`/`text-primary-hover`/etc. utilities), never a hardcoded hex. Verified this checkpoint: zero hardcoded `#RRGGBB`/`rgb()`/`hsl()` literals in `app/`, `components/`, `lib/`, `server/` (`grep` across all four trees, excluding test fixtures — see `07_GAP_ANALYSIS_AND_ROADMAP.md` §"Hardcoded value audit").

## 2. Contrast disclosures (`ADR-0016` evidence, reproduced here at full detail)

Hand-computed WCAG 2.2 relative-luminance/contrast-ratio (same formula as `app.hex_color_contrast_ratio`, `supabase/migrations/20260717090512_create_white_label.sql`):

| Foreground | Background | Ratio (≈) | AA large-text/UI (3:1) | AA body-text (4.5:1) |
|---|---|---|---|---|
| Primary `#0097B2` | App Background `#EAF0F6` | 3.1:1 | Pass | **Fail** |
| Primary `#0097B2` | Surface `#FFFFFF` | 3.4:1 | Pass | **Fail** |
| Primary Text `#2C3E50` | App Background `#EAF0F6` | 9.9:1 | Pass | Pass |
| Primary Text `#2C3E50` | Surface `#FFFFFF` | 10.9:1 | Pass | Pass |
| Secondary Text `#4A5C6E` | App Background `#EAF0F6` | 6.1:1 | Pass | Pass |
| White text | Primary `#0097B2` (button fill) | 3.0:1 | Marginal pass | **Fail** |

**Binding consequence for every future component built against these tokens:** `--color-primary` is safe as a UI-component fill (buttons, focus rings, selected-state borders — the 3:1 non-text minimum) and as large/bold text, but must never be used as small body text on `--color-app-background`/`--color-surface`. `components/ui/button.tsx`'s primary variant already satisfies this (white text at 14px/500-weight on a `#0097B2` fill sits at the "marginal pass" boundary — acceptable per WCAG 2.2's large/UI-component allowance for a 500-weight button label, but any future variant that shrinks or lightens button text must re-check this, not assume the existing primary variant's ratio still holds). `--color-text-primary`/`--color-text-secondary` are the correct defaults for body copy — `app/globals.css`'s `body{}` rule uses `--color-text-primary`, not `--color-primary`, for exactly this reason.

## 3. White-label tenant-override architecture

`CargoGrid Core Design System` + `Tenant Theme Layer` (`ADR-0006` mechanism, `ADR-0017` governance boundary). Full tenant-configurable/never-configurable property lists and the three-step resolution order: `ADR-0017` §2. Restated here only as a pointer, not duplicated.

### 3.1 Validation coverage — what is enforced today vs. named as a gap

| Validation requirement (this task's instruction) | Enforcement today | Layer | Status |
|---|---|---|---|
| Valid color syntax | `#RRGGBB` regex, `BrandTokensSchema` (`server/contracts/white-label/white-label.ts`) | Schema (write time) | `IMPLEMENTED` |
| Contrast (primary vs. background) | `app.hex_color_contrast_ratio` ≥ 4.5:1 against a fixed `#fafafa` (`--color-neutral-50`) reference, enforced at publish/rollback | DB function, publish-time gate | `IMPLEMENTED` — **disclosed reference-value gap**: the DB gate checks against `#fafafa`, not the new `--color-app-background` (`#EAF0F6`) this checkpoint introduces. Reconciling that reference is a migration-touching change (`CREATE OR REPLACE FUNCTION` against a `VERIFIED` Phase-1 capability, `PLT-117`) and is `DEFERRED`, not silently changed here — see `07_GAP_ANALYSIS_AND_ROADMAP.md`. |
| Focus visibility | Focus rings are a fixed component-geometry property, never tenant-overridable (`ADR-0017` §2, structural) — nothing to validate per-tenant because tenants cannot touch it | N/A by design | `IMPLEMENTED` (by construction) |
| Semantic-status distinction | `BrandTokensSchema` is `.strict()` with exactly `primary`/`secondary` keys — a tenant payload cannot contain `success`/`warning`/`danger`/`info` at all (rejected before storage) | Schema (write time) | `IMPLEMENTED` (structural) |
| Destructive-action distinction | `components/ui/button.tsx`'s `destructive` variant hardcodes `bg-danger`, never resolves from `--color-primary`/`--color-secondary` | Component (render time) | `IMPLEMENTED` (structural) |
| Red tenant-primary behavior / near-duplicate-of-semantic-color detection | `lib/theme/tenant-brand-policy.ts` (`evaluateTenantBrandPolicy`, this checkpoint) — RGB-distance heuristic flags a tenant `primary`/`secondary` that is a near-duplicate of a reserved semantic hue, or of each other | Pure TS function, unit-tested | `IMPLEMENTED` **standalone** — not yet called from `server/mutations/white-label.ts`'s `setTenantBrandTokens`/`publishTenantBrandVersion`. Wiring it into that enforced path changes `PLT-117`'s tested publish behavior and was judged out of this task's bounded scope (`AGENTS.md`: broad-refactor/behavior-change discipline) — `DEFERRED`, named explicitly rather than silently left unintegrated. |
| Logo file type / image dimensions / asset size / executable-content rejection | `validate_brand_asset_url` (DB CHECK, `https://` URL shape only) + `BrandAssetUrlSchema` (max length, `https://` regex) | DB constraint + schema | **`BLOCKED`** — no asset-upload/storage pipeline exists anywhere in this repository (verified this checkpoint: no `server/*/storage*`, no Supabase Storage bucket migration, no upload route). File type/dimension/size/executable-content validation is meaningless without an actual upload path to validate at — there is no file to inspect, only a URL string. This is not a design-system gap; it is a missing prerequisite feature (an upload/storage slice), out of this task's authority to invent. Named here so it is not silently assumed covered. |

### 3.2 Theme resolution order (restated from `ADR-0017` §2 for locality)

1. Published valid tenant theme.
2. Supported platform or plan default — **not implemented** (`app.evaluate_tenant_brand()` has exactly two sources today, `tenant`/`default`).
3. CargoGrid default theme (`ADR-0016`).

Atomic fallback is a structural guarantee (schema-level, not merged at read time) — see `ADR-0017` §2 for the code-level reasoning.

## 4. Portal theme wiring — implemented this checkpoint

`lib/theme/resolve-portal-theme.ts` — pure function, `EffectiveTenantBrand | null → { source, cssVars, logoAssetUrl }`. `null` input (no tenant, or resolution failed) always returns the empty-`cssVars`/`null`-logo default, which lets the compiled CSS defaults (`ADR-0016`'s values) show through untouched — this is the atomic-fallback mechanism at the UI layer, not a second theming system. Unit-tested: default fallback, tenant override with both/one token present, tenant override with a logo, empty/whitespace-only token values ignored rather than emitted as broken CSS.

`lib/portal/resolve-tenant-portal-theme.server.ts` — server wrapper, `React.cache()`-memoized per request (same pattern `resolveTenantAdminAccessForRequest` already uses), calls `evaluateTenantBrand` and falls back to the default (never throws, never surfaces the underlying error to the response) on any RPC/network failure — satisfies "avoid flash of invalid/partial theme... do not reveal internal tenant-resolution errors."

Wired into `app/(tenant)/[tenantSlug]/admin/layout.tsx` only, this checkpoint (`02_COMPONENTS.md`/`07_GAP_ANALYSIS_AND_ROADMAP.md` for which other tenant route-group layouts remain unwired). Explicitly **not** wired into `app/(supreme)/supreme/layout.tsx` — `ADR-0017` §4 forbids it.

## 5. Deferred: real font loading

`--font-sans`/`--font-display`/`--font-mono` name Inter/Space Grotesk/JetBrains Mono, but no `@font-face` or `next/font` integration exists — browsers render the system-fallback face. Implementing this requires choosing a loading strategy (self-hosted static assets vs. `next/font/google`'s build-time fetch) and verifying it against this environment's network/build constraints, which this checkpoint did not attempt (introducing a new build-time network dependency mid-task was judged higher-risk than the value of a font swap that doesn't change any layout/behavior). Recommended follow-up, not executed: `next/font/google` for Inter/Space Grotesk (both are Google Fonts) with `display: "swap"`; JetBrains Mono similarly, scoped to components that render technical/monospace values (rate figures, IDs) once those components exist.
