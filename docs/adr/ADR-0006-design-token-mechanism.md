# ADR-0006 — Design-token mechanism

Status: ACCEPTED
Date: 2026-07-15   Approver: Runtime build agent (Phase 0 governance authority, per `docs/adr/README.md` §3)   Supersedes/Superseded-by: —
Source candidate: `ADR-CAND-ARCH-021`   Owning phase/task: Phase 0 (`CG-S5-PH0-011`, Prompt 90, Design System Foundation)

## Question

`docs/architecture/09_UX_DESIGN_SYSTEM_WORKSTREAM.md` §13 (`ADR-CAND-ARCH-021`): exact design-token mechanism (CSS custom properties vs. a Tailwind-theme-config-driven approach) and token file location within `components/ui/`. Constraint: must support per-tenant runtime override (RPD-019's five white-label items) without a rebuild/redeploy per tenant, and must support the contrast-validation publish gate (`09_*.md` §9).

## Options

1. **CSS custom properties only**, hand-authored, no build-time framework.
   - Trade-off: no type-safe authoring surface, no utility-class ergonomics; every consumer would hand-write `var(--color-primary)` with no compile-time check that the variable exists.
2. **Tailwind theme-config only** (compiled at build time), no runtime CSS custom properties.
   - Trade-off: fails the core constraint directly — a compiled Tailwind theme cannot be overridden per tenant without a rebuild/redeploy per tenant, which RPD-019's runtime white-label requirement rules out.
3. **CSS custom properties for runtime override, Tailwind for build-time authoring, one token source (SELECTED).** Runtime: CSS custom properties (`--cg-color-*`, etc.), set per-tenant at the White-label domain-resolution middleware layer (Tech Arch §7.13, cited not re-derived). Build-time: Tailwind v4 (current stable `4.3.2`, verified via `npm view tailwindcss dist-tags` this checkpoint), whose CSS-first `@theme` configuration natively compiles to CSS custom properties — meaning the "build-time token source" and the "runtime override target" are the *same* custom-property set, not two token systems that could drift.
   - Trade-off: none material against the constraint; this is exactly `09_*.md` §13's own recommendation, verified against the current tool rather than assumed.

## Decision

**CSS custom properties as the single runtime token representation, authored via Tailwind v4's `@theme` CSS-first configuration** (not the legacy `tailwind.config.js` JS-object approach Tailwind v3 used — v4's native `@theme` block generates the same custom-property namespace directly, which is *why* v3-vs-v4 matters here, not merely a version bump). Per-tenant override (RPD-019's five items — logo, colors, domain, email, document presentation) sets the relevant custom-property values at the White-label domain-resolution middleware layer; no tenant ever triggers a rebuild to change its theme.

**Token file location:** `components/ui/tokens.css` (or equivalent `@theme` entry point), per `09_*.md` §13's own location guidance ("token file location within `components/ui/`") — **not created this checkpoint**, same Phase-1-scope boundary as `ADR-0005`.

**Contrast-validation gate:** the publish-time contrast check (`09_*.md` §9, "Contrast check is part of the White-label Studio's publish flow") validates the *resolved* custom-property values before a tenant's theme reaches `Active` — this ADR fixes where that check reads from (the same custom-property set), not the check's own implementation, which is Phase 1 White-label Studio scope (`PLT-117..119`).

## Evidence

- `docs/architecture/09_UX_DESIGN_SYSTEM_WORKSTREAM.md` §13's own recommendation, adopted after independent verification.
- Real, executed evidence this checkpoint: `npm view tailwindcss version` → `4.3.2`; `npm view tailwindcss dist-tags` → `latest: 4.3.2`, `v3-lts: 3.4.19` (confirms v4 is the current default line, v3 is explicitly the legacy-support tag, not a sign v4 is unstable).
- `docs/architecture/09_UX_DESIGN_SYSTEM_WORKSTREAM.md` §9 (contrast-validation publish gate) and §10 ("Contrast/fallback guardrails … theme contrast validated before publish").
- RPD-019 (`02_CONFIRMED_DECISION_REGISTER.md`) — the exact five-item white-label override surface this mechanism must support without a rebuild.

## Consequences

- **DB/API:** none.
- **UI:** fixes the exact mechanism Phase 1's `components/ui/tokens.css` (or equivalent) will implement — no risk of two competing token systems being tried before one is picked.
- **Security:** none beyond the existing publish-gate/fallback-to-safe-default rules already specified in `09_*.md` §10 (invalid branding assets fall back to a safe default theme rather than breaking login) — this ADR does not alter that rule, it fixes the representation the rule operates on.
- **Performance:** CSS custom properties resolve natively in the browser with no runtime JS theming cost; Tailwind v4's `@theme` compiles at build time — not measured as an SLA here (no build exists yet).
- **Migration/rollback:** trivial at this checkpoint (nothing implemented yet).
- **Downstream impact:** Phase 1's White-label Studio (`PLT-117..119`) and every `components/ui/` primitive consume this decision directly. **Explicit gap, not resolved by this ADR:** the actual CargoGrid base brand values (primary color, logo, typography family) are a product/design decision this ADR does not and cannot make — see `docs/standards/DESIGN_SYSTEM.md` §3 for the disclosed open item and its owner/resolution point.

## Propagation

Referenced by: `docs/standards/DESIGN_SYSTEM.md`; `docs/build-log/phase-00/PH0-90.md`; `docs/adr/README.md` §5.2 (marks `ADR-CAND-ARCH-021` `ACCEPTED`). Visual-regression/theme-testing tooling (the "bounded pattern" `09_*.md` §13 notes is "folded into the same Phase 0 Prompt 90/91 resolution") is deliberately **not** resolved here — that document's own text calls it "a test-infrastructure choice, not a design decision," so it is left to `PH0-091` (Testing Foundation, `ADR-CAND-ARCH-022`) rather than decided under this design-system ADR's authority. Does not alter any CPD/RPD or any `docs/architecture/**` decision.
