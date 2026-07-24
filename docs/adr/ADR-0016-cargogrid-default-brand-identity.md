# ADR-0016 — CargoGrid default brand identity (color, typography)

Status: ACCEPTED
Date: 2026-07-24   Approver: Runtime build agent (repository governance authority, per `docs/adr/README.md` §3)   Supersedes/Superseded-by: —
Source candidate: None — resolves the explicitly disclosed open item at `docs/standards/DESIGN_SYSTEM.md` §3 (recorded `CG-S5-PH0-011`, Prompt 90), not one of the original 27/30 architecture-stage `ADR-CAND-ARCH-*` candidates.
Owning task: CargoGrid Design System Expansion and Implementation (out-of-band documentation/design-system task; not a numbered `CG-S*-*` Commercial-phase prompt — see this task's own closing report for why, and `docs/runtime/CHANGE_MANIFEST.md`'s corresponding entry).

## Question

`docs/standards/DESIGN_SYSTEM.md` §3 disclosed, since Prompt 90 (`CG-S5-PH0-011`), that no hex color, logo, or typography family for CargoGrid's own default (pre-white-label) brand identity had ever been decided by Product/Design — every prior checkpoint deliberately mapped `--color-primary`/`--color-secondary` to the already-vetted neutral scale rather than invent one. This ADR exists because that decision has now genuinely been made by Product/Design and communicated as an explicit instruction, not because an implementing agent chose it unilaterally.

## Options

Not applicable in the usual multi-option ADR sense — this is a product/brand decision handed down by Product/Design (the same authority `DESIGN_SYSTEM.md` §3 named as the item's owner), not an architecture trade-off with competing technical options. This ADR's job is to record the decision durably, bind it to the token mechanism `ADR-0006` already fixed, and close the previously-open item so no future checkpoint re-derives or re-litigates it.

## Decision

**CargoGrid's default (pre-white-label) brand identity is fixed as follows.** These are the values every tenant's theme falls back to per the theme resolution order `ADR-0017` §"Theme resolution order" fixes, and the values `app/globals.css`'s `@theme` block now authors as the compiled default (this checkpoint).

### Color

| Token | Value | Tailwind `@theme` variable |
|---|---|---|
| Primary | `#0097B2` | `--color-primary` |
| Primary Hover | `#007D94` | `--color-primary-hover` |
| Secondary | `#CB3421` | `--color-secondary` |
| Secondary Hover | `#A52313` | `--color-secondary-hover` |
| App Background | `#EAF0F6` | `--color-app-background` |
| Surface (default) | `#FFFFFF` | `--color-surface` |
| Subtle Surface | `#F0F4F8` | `--color-surface-subtle` |
| Primary Text | `#2C3E50` | `--color-text-primary` |
| Secondary Text | `#4A5C6E` | `--color-text-secondary` |

`--color-neutral-*`, `--color-success`, `--color-warning`, `--color-danger`, `--color-info` are **unchanged** by this ADR — those were already decided and contrast-vetted at `DESIGN_SYSTEM.md` §2.1 and remain platform-controlled, never tenant-overridable (`ADR-0017` restates why).

### Typography

| Role | Family | Tailwind `@theme` variable |
|---|---|---|
| Primary UI | Inter | `--font-sans` |
| Display headings | Space Grotesk | `--font-display` |
| Technical values (rates, weights, IDs, monetary figures, timestamps) | JetBrains Mono | `--font-mono` |

**Disclosed gap, not resolved by this ADR:** the three families above are authored as CSS `font-family` stacks with robust system-font fallbacks (`app/globals.css`, this checkpoint) but no `@font-face`/`next/font` self-hosting or Google Fonts network loading is wired up — every browser today renders the system-font fallback, not the named face, until a future checkpoint adds real font loading. This is a deliberate, disclosed boundary (introducing a new font-loading dependency and verifying it against this repository's offline/sandboxed build environment is out of this task's bounded scope), not a silent omission — see this task's gap-analysis document (`docs/design-system/07_GAP_ANALYSIS_AND_ROADMAP.md`) for the exact follow-up.

## Evidence

- Product/Design instruction (this task's own prompt), the same authority `docs/standards/DESIGN_SYSTEM.md` §3's table named as owner and resolution point ("Before Phase 1's White-label Studio / Supreme Admin portal work... needs a default theme to render").
- `docs/adr/ADR-0006` (design-token mechanism) — this ADR supplies the *values*; `ADR-0006` already fixed the *mechanism* (CSS custom properties via Tailwind v4 `@theme`) those values are authored through. No mechanism change.
- Real contrast check performed this checkpoint (reproducing `app.hex_color_contrast_ratio`'s WCAG 2.2 formula by hand against the fixed app background): Primary `#0097B2` on App Background `#EAF0F6` ≈ 3.1:1 (fails the 4.5:1 AA body-text minimum used for small text) but ≈ passes the 3:1 AA large-text/UI-component minimum — **binding consequence**: Primary is safe for buttons/UI-component fills (3:1 minimum applies) and for text ≥ 18.66px bold/24px regular, but must not be used as small body text on the app background; `Primary Text` (`#2C3E50`) on `App Background`/`Surface`/`Subtle Surface` all exceed 4.5:1 comfortably and is the correct default body-text color. Recorded here so no future checkpoint has to re-derive it; full detail and the exact numbers are in `docs/design-system/01_TOKENS_AND_THEME.md` §"Contrast disclosures."
- `server/mutations`/`supabase/migrations/20260717090512_create_white_label.sql`'s `app.hex_color_contrast_ratio`/`app.publish_tenant_brand_version` remain the authoritative, automatically-enforced publish-time gate for *tenant* overrides of `primary`/`secondary` (unchanged by this ADR — it gates tenant values against the fixed `#fafafa` reference, a pre-existing, narrower reference than the new `App Background` token; reconciling that reference value is named as a deferred item in the gap analysis, not silently fixed here since it is a schema-adjacent change).

## Consequences

- **DB/API:** none — no migration. Tenant brand storage/validation (`app.tenant_brand_versions`) is unchanged.
- **UI:** `app/globals.css`'s `@theme` block now compiles `--color-primary`/`--color-secondary`/`--color-primary-hover`/`--color-secondary-hover`/`--color-app-background`/`--color-surface`/`--color-surface-subtle`/`--color-text-primary`/`--color-text-secondary`/`--font-sans`/`--font-display`/`--font-mono` to these real values instead of the prior neutral-scale placeholder. `components/ui/button.tsx`'s `primary` variant (already `bg-primary`) now renders the real teal without any component code change; its hover state is updated from a generic `hover:opacity-90` to the named `hover:bg-primary-hover` token this ADR introduces, matching this task's explicit `var(--brand-primary-hover)` consumption requirement.
- **Security:** none.
- **Performance:** none — CSS custom-property value changes only, no new network request (font loading remains system-fallback per the disclosed gap above).
- **Migration/rollback:** trivial — reverting `app/globals.css`'s token values reverts to the neutral-scale placeholder; no data migration involved.
- **Downstream impact:** every future `components/ui/` primitive and every future portal-shell alignment pass (`docs/design-system/00_INDEX.md`'s roadmap) now has a real default brand to render against instead of a disclosed placeholder — this was the exact blocking condition `DESIGN_SYSTEM.md` §3 named ("blocks only the first screen that actually needs to render CargoGrid's own default... visual identity"). Tenant white-label override (`ADR-0017`) is unaffected in mechanism — the fixed five/nine-item override surface still resolves against this new default, not a new default surface.

## Propagation

Referenced by: `docs/standards/DESIGN_SYSTEM.md` §3 (updated to point here, this checkpoint); `docs/design-system/00_INDEX.md`, `01_TOKENS_AND_THEME.md`; `docs/adr/ADR-0017`; `docs/adr/README.md` §6 (index). Does not alter `ADR-0005`/`ADR-0006`'s mechanism decisions, any CPD/RPD, or any `docs/architecture/**` planning document — it supplies values into a slot those documents and ADRs already reserved.
