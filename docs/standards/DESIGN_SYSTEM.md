# CargoGrid Design System Foundation

**Established by:** `CG-S5-PH0-011` (Prompt 90 — Design System Foundation)
**Status:** Active — decisions and structural conventions only. **No `components/ui/`, `lib/`, or token CSS file is created by this checkpoint** — those paths are Phase 1 Platform Core scope (`docs/architecture/04_REPOSITORY_TARGET_STRUCTURE.md`'s migration-wave table, wave 2), the same boundary `ADR-0001` established for domain folders and `PH0-085`/`PH0-086` respected for `app/`/`lib/`. This document fixes every decision Phase 1 needs so implementation there requires zero re-litigation — see `docs/build-log/phase-00/PH0-90.md` §2 for why implementation is deferred, not silently skipped.

This document distills the normative design-system foundation from `docs/architecture/09_UX_DESIGN_SYSTEM_WORKSTREAM.md` (already `VERIFIED`, not re-derived) plus `ADR-0005`/`ADR-0006` (this checkpoint). It extends `docs/standards/CODING_STANDARDS.md` §9, which explicitly deferred UX/component conventions here.

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
| Elevation | 3 levels (`sm`/`md`/`lg` shadow tokens) — internal ERP is desktop-first with dense data surfaces (`09_*.md` §8), so elevation is used sparingly (drawers/dialogs/dropdowns only), not a decorative card-shadow system | Decided |
| Breakpoint | Tailwind's default breakpoint scale (`sm=640px, md=768px, lg=1024px, xl=1280px, 2xl=1536px`), consistent with `09_*.md` §8's desktop-first-internal/mobile-first-field-and-portal split (internal ERP routes primarily target `lg`+, field/portal routes target base/`sm`) | Decided |
| Motion | `fast=100ms, base=200ms, slow=300ms`, `prefers-reduced-motion` respected everywhere motion is non-essential (`09_*.md` §9 "Reduced motion") | Decided |

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

## 3. Explicit open item — CargoGrid base brand identity (not decided by this task)

**No hex color, logo, or typography family for CargoGrid's own default brand identity exists anywhere in `docs/blueprint/**`** (verified this checkpoint: `grep` across all six blueprint documents for brand color/logo/hex specification returns only the *tenant-configurable white-label surface* — Blueprint §18: "Logo, color, domain, template, terminology" — never CargoGrid's own base values). This is a genuine, undecided product/design decision, not an oversight — inventing a specific brand color here would be exactly the kind of unauthorized product decision this build's governance has consistently refused to make (the same category as `HANDOFF.md`'s prior `BLOCKED_DECISION` precedents).

| Item | Status | Owner | Resolution point |
|---|---|---|---|
| Primary/secondary brand color values | **Open** | Product/Design | Before Phase 1's White-label Studio / Supreme Admin portal work (`PLT-117..119`) needs a default theme to render |
| Logo/wordmark | **Open** | Product/Design | Same |
| Typography family (body + heading) | **Open** | Product/Design | Same |

This is **not blocking** for the remainder of Phase 0 (no Phase 0 task renders UI) and is **not blocking** for Phase 1's non-visual Platform Core work (auth, tenant provisioning, RBAC) — it blocks only the first screen that actually needs to render CargoGrid's own default (pre-white-label) visual identity. Tracked here so it surfaces before that point, not discovered mid-implementation.

## 4. Component/state contract (`09_*.md` §5, cited verbatim, not re-derived)

Every data-bearing component (table, detail page, form, dashboard widget) implements the same 11 states as a binding contract: **Loading, Empty, Error, Offline, Partial, Unauthorized, Forbidden, Conflict, Success, Retry, Destructive confirmation.** Full trigger/contract definitions: `docs/architecture/09_UX_DESIGN_SYSTEM_WORKSTREAM.md` §5. Every state is itself permission/scope-aware — an empty state never reveals a create action the viewer cannot use; an error state never leaks tenant data or a stack trace.

## 5. Accessibility acceptance criteria (`09_*.md` §9, WCAG 2.2 AA, cited verbatim)

Keyboard/focus reachability with visible focus indicators; programmatic semantic labels; specific field-adjacent validation errors plus a live region for async state; contrast validated per white-label theme before publish; reflow/zoom usable at 125–150%; reduced motion respected; minimum touch targets on mobile-first routes; non-color status signaling; accessible chart/table/file alternatives. Full acceptance criteria: `docs/architecture/09_UX_DESIGN_SYSTEM_WORKSTREAM.md` §9.

## 6. Theming and white-label rules (`09_*.md` §10, RPD-019, cited)

Canonical status/entity semantics never move with a tenant relabel — the badge/status component always renders from `canonical_ref`, never the tenant label alone (`07_CONFIGURATION_ENGINE_WORKSTREAM.md` §6). The white-label override surface is exactly RPD-019's five items (logo, colors, domain, email presentation, document templates) — not an open-ended theming API. Invalid branding assets fall back to a safe default theme rather than breaking login. Template variables are whitelisted, never arbitrary executable code.

## 7. Test strategy (structural now, tooling deferred)

Per `09_*.md` §13's own framing ("a test-infrastructure choice, not a design decision"), the exact visual-regression/component-testing tool is deliberately **not** chosen by this document — deferred to `PH0-091` (Testing Foundation, `ADR-CAND-ARCH-022`). What this document fixes structurally, so `PH0-091` doesn't have to re-derive it: component tests exercise all 11 states (§4) per primitive, not just the happy path; accessibility tests cover keyboard-only completion and screen-reader label presence (§5); theme tests verify a tenant override changes presentation without changing canonical semantics (§6).

## 8. Rollout note

No `components/ui/`, `lib/`, or token file exists yet — consistent with `04_REPOSITORY_TARGET_STRUCTURE.md`'s wave-2/Phase-1 boundary for those paths (the same discipline `PH0-085`/`086`/`089` applied to `app/`/`lib/`/`server/`). This document and `ADR-0005`/`ADR-0006` are what Phase 1's `components/ui/` implementation reads first — no design decision should need to be re-opened when that implementation begins, except the explicitly disclosed open item in §3.
