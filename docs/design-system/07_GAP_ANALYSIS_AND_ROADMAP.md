# Gap Analysis and Recommended Roadmap

CargoGrid Design System Expansion and Implementation task, 2026-07-24. This document is the audit trail behind every `IMPLEMENTED`/`DOCUMENTED_ONLY`/`DEFERRED`/`BLOCKED` classification used across `docs/design-system/`, and the honest accounting this task's own instruction (§16) requires. It does not claim full completion of the ~70-component/full-screen-alignment scope this task's instruction enumerated — that scope is a multi-checkpoint program, not a single-session task, and claiming otherwise would violate `AGENTS.md`'s "Never label a task, phase, or product complete beyond the evidence actually obtained."

## 1. Repository audit method and findings

Performed by direct inspection (`Read`/`Grep`/`Glob`), not assumed, before any code change:

- **Existing design-system documents found:** `docs/standards/DESIGN_SYSTEM.md` (Prompt 90 foundation, the canonical index), `docs/architecture/09_UX_DESIGN_SYSTEM_WORKSTREAM.md` (`VERIFIED` planning-precision experience architecture), `docs/adr/ADR-0005`/`ADR-0006` (component/token mechanism), `docs/blueprint/03_CargoGrid_UX_Data_Access_Design.md` (source blueprint, cited by `09_*.md`), `docs/discovery/09_ACCESSIBILITY_UX_BASELINE.md` (Phase 0 absence-confirmation baseline). No competing/duplicate foundation document existed — confirmed before writing anything.
- **Existing implementation found:** `app/globals.css` (token source, `@theme`), `components/ui/button.tsx`, `components/ui/banner.tsx` (2 primitives only), full white-label backend (`supabase/migrations/20260717090512_create_white_label.sql`, `server/contracts|queries|mutations/white-label*`) — versioned draft/publish/rollback, DB-level contrast gate, structurally restricted to primary/secondary/logo/email/document-template overrides — but **zero UI wiring**: no route or layout anywhere in the repository called `evaluateTenantBrand` or rendered a resolved tenant brand before this checkpoint.
- **Hardcoded-value audit:** `grep` for `#[0-9a-fA-F]{3,6}` across `app/`, `components/`, `lib/`, `server/` (excluding test fixtures) returned **zero matches** — every existing surface already consumes semantic Tailwind utility classes reading `@theme` tokens, no hardcoded hex/rgb/hsl color, no inline `style` object carrying a color value. This is a clean baseline; this checkpoint's job was additive (new tokens/components), not remedial.
- **Component library/form/table/chart/icon library:** none of the last four exist. No Storybook/component-preview tooling. No dedicated visual-regression tooling beyond `@axe-core/playwright` (`ADR-0008`, accessibility-focused, not pixel-diff visual regression — `09_*.md` §13 left the exact visual-regression tool an open, non-blocking item, still open).
- **Test infrastructure:** `node:test` (unit, `lib/`/`server/`/`scripts/`/`tests/`), Playwright + axe-core (`e2e/`). No component-level (`.test.tsx`) test infrastructure exists — `node --experimental-strip-types` does not transform JSX, so a `.tsx` test file cannot be imported by the current `pnpm run test` runner. This is why this checkpoint's new component-adjacent logic (`resolvePortalTheme`, `evaluateTenantBrandPolicy`) was deliberately extracted into plain `.ts` modules with real unit tests, rather than left untested inside `.tsx` files.

## 2. What this task implemented

| Area | Change |
|---|---|
| Brand identity decision | Resolved `docs/standards/DESIGN_SYSTEM.md` §3's disclosed open item (`ADR-0016`) |
| Design governance | Recorded "CargoGrid Adaptive Industrial UI" identity and precision white-label boundary (`ADR-0017`) |
| Tokens | `app/globals.css`: brand (+hover), surface/text/border, elevation, density tokens added; typography families named (font-loading itself deferred, §5) |
| Components | `components/ui/badge.tsx`, `status-badge.tsx` added; `button.tsx` (hover token), `banner.tsx` (2 new variants) extended |
| Theme resolution | `lib/theme/resolve-portal-theme.ts` + tests; `lib/theme/tenant-brand-policy.ts` + tests (standalone); `lib/portal/resolve-tenant-portal-theme.server.ts` |
| Portal wiring | `app/(tenant)/[tenantSlug]/admin/layout.tsx` now resolves and renders tenant brand/logo, with atomic default-theme fallback; `app/(supreme)/supreme/layout.tsx` documented as deliberately excluded |
| Documentation | `docs/standards/DESIGN_SYSTEM.md` reconciled in place; `docs/design-system/00–07` added (this subtree); `docs/adr/ADR-0016`/`ADR-0017` added; `docs/adr/README.md` index updated |

Full per-file list and test/build evidence: this task's final report (chat) and the corresponding `docs/runtime/CHANGE_MANIFEST.md` entry.

## 3. Deferred items (named, scoped, reasoned — not silently skipped)

| Item | Why deferred | Trigger to pick it up |
|---|---|---|
| Wire `resolveTenantPortalThemeForRequest` into `commercial/layout.tsx` (and any future tenant route-group layout) | Mechanically identical to the `admin/layout.tsx` change; excluded to keep this checkpoint's diff bounded and reviewable | Any future checkpoint touching that layout, or a dedicated small follow-up |
| Wire `evaluateTenantBrandPolicy` (`lib/theme/tenant-brand-policy.ts`) into `server/mutations/white-label.ts`'s enforced publish path | Changes tested `PLT-117` publish behavior (a `VERIFIED` Phase-1 capability) — a behavior change to an already-shipped, tested mutation is a distinct, reviewable change, not a documentation/token-layer addition | A dedicated white-label hardening task, with its own test-fixture review against `server/mutations/white-label.test.ts` |
| Reconcile `app.publish_tenant_brand_version`'s fixed `#fafafa` contrast reference with the new `--color-app-background` (`#EAF0F6`) token | Requires a `CREATE OR REPLACE FUNCTION` migration against a `VERIFIED` Phase-1 capability plus a live-environment contrast re-verification | A dedicated white-label/migration task |
| Compact logo / favicon schema columns | New `app.tenant_brand_versions` columns — an additive migration, out of a documentation/token-layer checkpoint's bounded scope | Whenever product prioritizes those two white-label surfaces |
| Real font loading (Inter/Space Grotesk/JetBrains Mono via `next/font` or self-hosted) | New build-time network dependency; not verified against this environment | A small, low-risk follow-up — recommended next design-system checkpoint |
| Data Grid / Table primitive with density-tier support | No real paginated/sortable/filterable screen exists yet to build the primitive against — building it speculatively risks an API that doesn't fit the first real consumer | The first screen that needs sort/filter/column-config (several Commercial list screens are candidates already) |
| Full ~60-component `DOCUMENTED_ONLY` catalogue (`02_COMPONENTS.md` §2) | Multi-checkpoint program; each primitive should be extracted from (or built alongside) a real consuming screen, per `09_*.md` §4.2's "one owner" rule, not speculatively | Per-component, as each's first real consumer is built |
| Pre-auth tenant branding on `app/(public)/login` | Requires a tenant-resolution strategy (subdomain/custom-domain parsing) before authentication — a routing/middleware decision beyond this checkpoint's scope | A dedicated custom-domain/pre-auth checkpoint |
| Supreme Admin tenant-branded preview/detail screen | No such screen exists yet (`09_*.md` §14 names it as future White-label Studio work) | Whichever future checkpoint builds the Supreme Admin White-label Studio |
| `e2e`/Playwright + axe-core run against this checkpoint's changes | Requires a browser-driven server; not executed in this pass (unit/typecheck/lint/build were run and are green) | Before this branch merges — recommended, not run here |
| RGB-distance heuristic (`tenant-brand-policy.ts`) replaced or supplemented by a perceptual (Lab/Delta-E) distance | RGB Euclidean is a defensible, simple heuristic (verified against both CargoGrid's own default colors and the reserved semantic set, zero false positives); a perceptual model would be more accurate but is unvalidated extra complexity for a standalone, not-yet-wired module | If/when the module is wired into the enforced publish path |

## 4. Blocked items (outside this task's authority)

| Item | Blocker |
|---|---|
| Logo file type / image dimensions / asset size / executable-content validation | No asset-upload/storage pipeline exists anywhere in this repository — nothing to validate at (`01_TOKENS_AND_THEME.md` §3.1) |
| File upload / Document preview / Attachment list components | Same storage-pipeline prerequisite |
| Live-environment theme resolution testing (real Supabase project, real tenant, real sign-in) | No deployed environment or live Supabase project exists yet (`docs/runtime/CARGOGRID_BUILD_STATUS.md` §1, unchanged fact, not caused by this task) |
| CargoGrid logo/wordmark asset | Still an open product decision (`docs/standards/DESIGN_SYSTEM.md` §3, only the color/typography half was resolved this checkpoint) |
| Third accent color / plan-tier default theme source | Product decisions this task's own instruction did not authorize inventing (`ADR-0017` §2) |

## 5. Recommended (not executed) sequencing for future checkpoints

This is a recommendation, consistent with this task's own instruction §12's ordering, not an authorization to execute it autonomously — each item remains its own atomic task under `AGENTS.md`'s sizing/collision discipline:

1. Extend tenant-theme wiring to `commercial/layout.tsx` (small, mechanical).
2. Run `pnpm run test:e2e` against this checkpoint's changes and record the result.
3. Build the first real Data Grid/Table primitive against whichever Commercial list screen needs sort/filter/column-config first.
4. Extract Form Field/Input from the first form that needs shared validation-state styling across more than one screen.
5. Wire `next/font` for Inter/Space Grotesk/JetBrains Mono.
6. Wire `evaluateTenantBrandPolicy` into the enforced white-label publish path, with its own dedicated test-fixture review.
7. Reconcile the DB contrast reference value, as its own migration-bearing task.

## 6. Confirmation

This task is out-of-band: no `CG-S*-*` task ID was assigned; `docs/runtime/CARGOGRID_BUILD_STATUS.md`'s "Active task"/"Next eligible task" rows (`CG-S7-COM-010`, Prompt 151, Quotation Builder) were left untouched by this checkpoint. This document, `docs/adr/ADR-0016`/`ADR-0017`, and the corresponding `docs/runtime/CHANGE_MANIFEST.md` entry are the durable record of what changed; they do not renumber, supersede, or consume Prompt 151 or any later roadmap prompt.
