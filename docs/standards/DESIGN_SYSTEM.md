# CargoGrid Design System Foundation — "CargoGrid Adaptive Industrial UI"

**Established by:** `CG-S5-PH0-011` (Prompt 90 — Design System Foundation)
**Expanded by:** CargoGrid Design System Expansion and Implementation task (2026-07-24, out-of-band — not a numbered `CG-S*-*` Commercial-phase prompt; does not consume, rename, or renumber Prompt 151/`CG-S7-COM-010`. See `docs/runtime/CHANGE_MANIFEST.md`'s corresponding entry and `docs/design-system/07_GAP_ANALYSIS_AND_ROADMAP.md`.)
**Status:** Active — this document remains the canonical index/foundations record (decisions and structural conventions). It is reconciled in place, not superseded: every decision Prompt 90 fixed is preserved verbatim below except §3 (brand identity), which was an explicitly disclosed **open** item now **resolved** by `ADR-0016`. Detailed component/pattern specifications (anatomy, variants, states, keyboard/a11y, white-label/density behavior — precision this document was never meant to carry, per its own original §0 framing) live in the `docs/design-system/` subtree this expansion adds; this document links to it rather than duplicating it.

This document distills the normative design-system foundation from `docs/architecture/09_UX_DESIGN_SYSTEM_WORKSTREAM.md` (already `VERIFIED`, not re-derived) plus `ADR-0005`/`ADR-0006` (Prompt 90) and `ADR-0016`/`ADR-0017` (this expansion). It extends `docs/standards/CODING_STANDARDS.md` §9, which explicitly deferred UX/component conventions here.

**Design identity (this expansion, `ADR-0017`):** CargoGrid's permanent design language is **CargoGrid Adaptive Industrial UI** — the product should feel like an **Enterprise Logistics Control Tower**: flat first, depth on demand, dense ERP-style information architecture, exception-first, calm by default with vividness reserved for action/selection/warning/exception, performance- and accessibility-first, shared-primitives-first, white-label capable, audit-aware, role-aware, tenant-safe. Recommended visual balance: 85% flat / 10% subtle elevation / 5% soft tactile interaction. Full anti-pattern list and rationale: `ADR-0017` §1.

## 1. Mechanism (decided — `ADR-0005`, `ADR-0006`)

- **Component foundation:** Radix UI primitives (`radix-ui`, current stable `1.6.2`), consumed via a copy-in pattern into `components/ui/` — never a black-box runtime UI-kit dependency (`ADR-0005`).
- **Token mechanism:** CSS custom properties as the single runtime representation, authored via Tailwind v4's CSS-first `@theme` configuration (current stable `4.3.2`) — one token source, not two systems that could drift (`ADR-0006`).
- **Ownership rule** (`09_*.md` §4.2, verbatim): "one component owner, many consumers" — a table/form/status/timeline primitive is implemented once in `components/{ui,tables,forms}/` and composed by every domain's page. No domain re-implements its own table pagination or approval-decision panel. `components/domain/` holds domain-aware compositions built from `components/ui/`/`components/tables/` primitives, never a domain-local fork of a primitive.

## 2. Token category structure (structure decided now; brand values partly open — §3)

| Category | Scale/structure | Status |
|---|---|---|
| Color roles | `primary`, `secondary`, `neutral` (full gray scale), `success`, `warning`, `danger`, `info` — each with a light/dark-mode-ready value pair | **Structure decided.** `primary`/`secondary` **values open** (§3). `neutral`/`success`/`warning`/`danger`/`info` have proposed reference values below (§2.1) — pending the real contrast-validation gate `09_*.md` §9 requires before any value is treated as final. |
| Typography | A modular scale (`xs`–`4xl`, 7–8 steps), one body font family + one heading/display family (family choice open, §3) | Structure decided; family open |
| Spacing | 4px-based scale (`0, 1=4px, 2=8px, 3=12px, 4=16px, 6=24px, 8=32px, 12=48px, 16=64px`) — standard Tailwind-compatible scale, no CargoGrid-specific deviation needed | Decided |
| Radius | `none, sm=2px, md=6px, lg=10px, full` | Decided |
| Elevation | 3 levels (`sm`/`md`/`lg` shadow tokens) — internal ERP is desktop-first with dense data surfaces (`09_*.md` §8), so elevation is used sparingly (drawers/dialogs/dropdowns only), not a decorative card-shadow system | Decided; **implemented** this expansion (`--shadow-sm/md/lg`, `app/globals.css`) — restrained values only (no blur/glassmorphism), holding the 85/10/5 flat/elevated/tactile ratio `ADR-0017` §1 fixes |
| Breakpoint | Tailwind's default breakpoint scale (`sm=640px, md=768px, lg=1024px, xl=1280px, 2xl=1536px`), consistent with `09_*.md` §8's desktop-first-internal/mobile-first-field-and-portal split (internal ERP routes primarily target `lg`+, field/portal routes target base/`sm`) | Decided |
| Motion | `fast=100ms, base=200ms, slow=300ms`, `prefers-reduced-motion` respected everywhere motion is non-essential (`09_*.md` §9 "Reduced motion") | Decided |
| Surface/text/border (semantic) | `--color-app-background`, `--color-surface`, `--color-surface-subtle`, `--color-text-primary`, `--color-text-secondary`, `--color-border-default` (the last mapped to the already-decided `--color-neutral-200`, not a new invented value) | **New this expansion** (`ADR-0016`) — components consume these, never the brand hex directly (§1's copy-in components already followed this discipline for `--color-primary`/neutral; this row extends the same discipline to surface/text/border) |
| Density (row height) | `--row-height-compact=34px`, `--row-height-default=38px`, `--row-height-comfortable=46px` — platform-controlled, never tenant-configurable (`ADR-0017` §3) | **New this expansion** — no `components/tables/` primitive consumes these yet (none exists, `09_*.md` §4.1); tokens authored ahead of that primitive so it has no density decision left open |

### 2.1 Reference values for non-brand-specific roles (proposed, pending Phase 1's real contrast-validation gate)

These are **reference starting values**, not yet run through an automated contrast checker (none exists until Phase 1 implements the `09_*.md` §9 publish-gate) — they are chosen from well-established, widely-vetted accessible color scales (not invented ad hoc), but this document does not claim WCAG certification it cannot actually verify yet:

| Role | Light-mode value | Rationale |
|---|---|---|
| `neutral-*` | A 10-step gray scale (`neutral-50` ≈ `#fafafa` through `neutral-900` ≈ `#171717`) | Standard perceptually-even gray scale; text/background pairs at the extremes (`neutral-900` on `neutral-50`) exceed WCAG AA's 4.5:1 body-text minimum by a wide margin |
| `success` | `#15803d` (green-700-equivalent) | Meets 4.5:1 against white; avoided the lighter/brighter green shades that commonly fail contrast |
| `warning` | `#b45309` (amber-700-equivalent) | Amber/yellow families frequently fail contrast at lighter shades — this value is deliberately a darker step for text-safe use; a lighter shade may still be used for non-text fill (badge background) paired with a dark-enough label per `09_*.md` §9's non-color-alone rule |
| `danger` | `#b91c1c` (red-700-equivalent) | Meets 4.5:1 against white |
| `info` | `#1d4ed8` (blue-700-equivalent) | Meets 4.5:1 against white |

**Non-color status rule (`09_*.md` §9, binding, restated):** every status/badge uses a label and/or icon, never color alone — these values inform fill/text color, not the sole signal.

## 3. CargoGrid base brand identity — **resolved** (`ADR-0016`, 2026-07-24)

**Historical note (preserved, not deleted):** as of Prompt 90, no hex color, logo, or typography family for CargoGrid's own default brand identity existed anywhere in `docs/blueprint/**` — this section originally disclosed that as a genuine open item, explicitly refusing to invent a placeholder brand decision (the same category as `HANDOFF.md`'s `BLOCKED_DECISION` precedents). `app/globals.css` correspondingly mapped `--color-primary`/`--color-secondary` to the neutral scale rather than a fabricated brand color, from Prompt 135 (`PLT-135`) through this expansion.

**Resolution:** Product/Design has since fixed CargoGrid's default brand identity. Full values, contrast disclosures, and typography-loading gap: `ADR-0016`. Summary:

| Item | Status | Value | Resolution record |
|---|---|---|---|
| Primary/secondary brand color values | **Decided** | Primary `#0097B2` / Secondary `#CB3421` (plus hover pairs) | `ADR-0016` |
| App background / surface / text colors | **Decided** | `#EAF0F6` / `#FFFFFF` (+ `#F0F4F8` subtle) / `#2C3E50` (+ `#4A5C6E` secondary) | `ADR-0016` |
| Logo/wordmark | **Still open** | — | No logo asset exists in this repository; `logo_asset_url` remains a tenant-supplied URL field with no CargoGrid-default asset configured. Named in `docs/design-system/07_GAP_ANALYSIS_AND_ROADMAP.md`, not fabricated here. |
| Typography family (body + heading + technical/mono) | **Decided (values), loading deferred** | Inter / Space Grotesk / JetBrains Mono | `ADR-0016` — CSS `font-family` stacks authored in `app/globals.css`; no `@font-face`/`next/font` loading wired yet, so every browser renders the system-font fallback today (disclosed gap, `ADR-0016`) |

This section is retained (not deleted) as the historical record of the open item and its resolution, per this document's own reconciliation discipline (§0 header) — a prior decision is corrected/updated in place with the change visible, never silently overwritten.

## 4. Component/state contract (`09_*.md` §5, cited verbatim, not re-derived)

Every data-bearing component (table, detail page, form, dashboard widget) implements the same 11 states as a binding contract: **Loading, Empty, Error, Offline, Partial, Unauthorized, Forbidden, Conflict, Success, Retry, Destructive confirmation.** Full trigger/contract definitions: `docs/architecture/09_UX_DESIGN_SYSTEM_WORKSTREAM.md` §5. Every state is itself permission/scope-aware — an empty state never reveals a create action the viewer cannot use; an error state never leaks tenant data or a stack trace.

## 5. Accessibility acceptance criteria (`09_*.md` §9, WCAG 2.2 AA, cited verbatim)

Keyboard/focus reachability with visible focus indicators; programmatic semantic labels; specific field-adjacent validation errors plus a live region for async state; contrast validated per white-label theme before publish; reflow/zoom usable at 125–150%; reduced motion respected; minimum touch targets on mobile-first routes; non-color status signaling; accessible chart/table/file alternatives. Full acceptance criteria: `docs/architecture/09_UX_DESIGN_SYSTEM_WORKSTREAM.md` §9.

## 6. Theming and white-label rules (`09_*.md` §10, RPD-019, cited; precision restatement `ADR-0017`)

Canonical status/entity semantics never move with a tenant relabel — the badge/status component always renders from `canonical_ref`, never the tenant label alone (`07_CONFIGURATION_ENGINE_WORKSTREAM.md` §6). The white-label override surface is exactly RPD-019's five items (logo, colors, domain, email presentation, document templates) — not an open-ended theming API. Invalid branding assets fall back to a safe default theme rather than breaking login. Template variables are whitelisted, never arbitrary executable code.

**`ADR-0017`** fixes this at implementation precision now that the white-label backend (`PLT-117`) and `components/ui/` both exist: the exact tenant-configurable property list and its current schema-implemented/deferred split; the always-platform-controlled list (layout, navigation, typography scale, spacing, radius, elevation, density, workflow behavior, semantic status colors, destructive-action treatment, focus behavior, accessibility rules, component geometry, authorization behavior — structurally enforced, not merely conventional, via `BrandTokensSchema`'s `.strict()` shape); the three-step theme resolution order (published tenant theme → plan/platform default [not yet implemented — only two sources exist today] → CargoGrid default); the atomic-fallback guarantee; and the explicit list of theme-authority sources that must never be trusted (URL params, cookies, local storage, user-supplied CSS/HTML/JS — verified zero matches in this repository this checkpoint). Portal-specific branding rules (Supreme Admin never tenant-branded in its main shell; Tenant Internal Admin route group now resolves tenant brand, this expansion; Customer Portal rules bind a route that does not exist yet; pre-auth tenant resolution is a disclosed gap, not implemented) are also fixed there.

## 7. Test strategy (structural now, tooling deferred)

Per `09_*.md` §13's own framing ("a test-infrastructure choice, not a design decision"), the exact visual-regression/component-testing tool is deliberately **not** chosen by this document — deferred to `PH0-091` (Testing Foundation, `ADR-CAND-ARCH-022`). What this document fixes structurally, so `PH0-091` doesn't have to re-derive it: component tests exercise all 11 states (§4) per primitive, not just the happy path; accessibility tests cover keyboard-only completion and screen-reader label presence (§5); theme tests verify a tenant override changes presentation without changing canonical semantics (§6).

## 8. Rollout note

**Historical (Prompt 90):** no `components/ui/`, `lib/`, or token file existed yet at authoring time — consistent with `04_REPOSITORY_TARGET_STRUCTURE.md`'s wave-2/Phase-1 boundary. This document and `ADR-0005`/`ADR-0006` were what Phase 1's `components/ui/` implementation read first.

**Current state (this expansion, 2026-07-24):** `app/globals.css` (token source), `components/ui/button.tsx`, `components/ui/banner.tsx`, `components/ui/badge.tsx`, `components/ui/status-badge.tsx` exist. §3's open item is resolved (`ADR-0016`). The remaining ~60+ shared primitives this task's own instruction enumerates (input, select, table, dialog, drawer, toast, etc.) are **documented, not yet implemented** — `docs/design-system/02_COMPONENTS.md` carries the full catalogue with an explicit `IMPLEMENTED` / `DOCUMENTED_ONLY` / `DEFERRED` status per component, so no future checkpoint mistakes "specified" for "built." Building the full catalogue against real screens is a multi-checkpoint program, not a single-session task — see `docs/design-system/07_GAP_ANALYSIS_AND_ROADMAP.md` for the sequencing this expansion recommends without unilaterally executing it.

## 9. Canonical detail specifications

This document remains the foundations/decisions index. Full component/pattern/layout/data-experience/workflow/AI-interaction specifications (purpose, anatomy, variants, sizes, states, keyboard behavior, accessibility, responsive behavior, white-label behavior, density behavior, examples, anti-patterns, implementation notes — the precision this document was never meant to carry) live in `docs/design-system/`, added by this expansion:

- `docs/design-system/00_INDEX.md` — canonical entry point, identity statement, cross-reference map, status legend.
- `docs/design-system/01_TOKENS_AND_THEME.md` — full token catalogue, theme resolution, white-label validation coverage.
- `docs/design-system/02_COMPONENTS.md` — component catalogue and specifications.
- `docs/design-system/03_LAYOUT_NAVIGATION.md` — application shell, navigation, portal/module switching.
- `docs/design-system/04_DATA_EXPERIENCE_AND_WORKFLOW_PATTERNS.md` — tables, filters, dashboards, and 20+ workflow patterns (create/approve/escalate/batch/etc.).
- `docs/design-system/05_AI_ASSISTED_INTERACTION.md` — AI suggestion/summary/draft/recommendation patterns and the human-approval/audit rule.
- `docs/design-system/06_ACCESSIBILITY_PERFORMANCE.md` — WCAG 2.2 AA acceptance criteria and performance budgets at component precision.
- `docs/design-system/07_GAP_ANALYSIS_AND_ROADMAP.md` — repository audit findings, implemented/documented/deferred/blocked classification, and the recommended (not unilaterally executed) sequencing for future checkpoints.

None of these duplicate this document, `docs/architecture/09_UX_DESIGN_SYSTEM_WORKSTREAM.md`, or the ADRs — each cites rather than re-derives the decisions those documents already fixed.
