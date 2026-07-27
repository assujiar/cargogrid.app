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
3. ~~Build the first real Data Grid/Table primitive against whichever Commercial list screen needs sort/filter/column-config first.~~ **Done — §8 (2026-07-26).** Display/density/empty-state/pagination only; sort/filter/column-config remain `DOCUMENTED_ONLY` (no real consumer needs them yet).
4. ~~Extract Form Field/Input from the first form that needs shared validation-state styling across more than one screen.~~ **Done — §10 (2026-07-26).** Built ahead of a single named consumer this time (a deliberate departure from this document's own earlier "wait for a real consumer" caution, made explicit given 39 existing forms already need it identically) — not yet wired into any of those 39 forms (migration map, `08_COMPONENT_INVENTORY.md` §4).
5. Wire `next/font` for Inter/Space Grotesk/JetBrains Mono.
6. Wire `evaluateTenantBrandPolicy` into the enforced white-label publish path, with its own dedicated test-fixture review.
7. Reconcile the DB contrast reference value, as its own migration-bearing task.

## 6. Confirmation

This task is out-of-band: no `CG-S*-*` task ID was assigned; `docs/runtime/CARGOGRID_BUILD_STATUS.md`'s "Active task"/"Next eligible task" rows (`CG-S7-COM-010`, Prompt 151, Quotation Builder) were left untouched by this checkpoint. This document, `docs/adr/ADR-0016`/`ADR-0017`, and the corresponding `docs/runtime/CHANGE_MANIFEST.md` entry are the durable record of what changed; they do not renumber, supersede, or consume Prompt 151 or any later roadmap prompt.

## 7. Mission context (2026-07-26 checkpoint)

A separate, much broader "CargoGrid UI Modernization & Design System Enforcement" instruction was issued this session, asking (among other things) to audit and refactor every existing Commercial page, build the full ~70-component catalogue, and standardize navigation/search/notifications/charts/forms/accessibility across the whole application in one pass. Per this repository's own `AGENTS.md` ("Work on one authorized CargoGrid task at a time"; default task size "approximately 5–15 changed files"; "Broad refactors... require dedicated prompts and ADR/change control") and this document's own §5 precedent (a named, sequenced, one-item-at-a-time roadmap, not a single mega-task), that full scope was not attempted in one checkpoint. The user was asked to pick the first concrete slice; item 3 above (Data Grid/Table primitive) was selected. §8 records what was actually built. The remaining mission scope stays exactly as broad and exactly as un-executed as before — nothing below should be read as closing it.

## 8. Checkpoint 2 — Table and Pagination primitives (2026-07-26, out-of-band)

**What changed:** `components/tables/data-table.tsx` and `components/tables/pagination.tsx` added (full spec: `02_COMPONENTS.md` §1); `lib/tables/pagination-range.ts` (+ `.test.ts`, 9 cases) extracted as the pure page-window calculation, same "plain `.ts` for testability" discipline as `lib/theme/resolve-portal-theme.ts`. Two real consumers migrated onto both, deliberately one Commercial screen and one Supreme screen to validate the primitives' API against more than a single caller before calling them `IMPLEMENTED`: `app/(tenant)/[tenantSlug]/commercial/leads/page.tsx` and `app/(supreme)/supreme/tenants/page.tsx`. Both previously rendered a raw hand-rolled `<table>` and a static "Page X — Y total" string with no actual prev/next control; both now render through the shared primitives with a real, working pagination control (a genuine behavior improvement, not purely cosmetic) and identical query/data behavior otherwise.

**Deliberately not done this checkpoint (named, not silently skipped):** sorting, filtering, grouping, saved views, column visibility/pinning, bulk actions, row selection, export, and virtualization — no current screen has server-side support for any of these, so building the UI ahead of a real backing capability would be exactly the speculative-abstraction pattern `AGENTS.md` forbids; each remains `DOCUMENTED_ONLY` in `02_COMPONENTS.md` §2, to be built against whichever real screen needs it first. `DataTable`'s Loading/Error states remain page-owned (route `loading.tsx` Suspense boundary; inline `role="alert"`), matching every existing screen's own convention — not consolidated into the primitive. No other Commercial list screen (prospects, contacts, accounts, opportunities, quotations, contracts, rates, approvals, credit-approvals, costing-requests, margin-rules, pipeline) was migrated this checkpoint — each remains on its own raw `<table>`/inline pagination, a real, disclosed gap and the natural next candidate for a follow-up checkpoint of the same shape as this one.

**Evidence:** `pnpm install`, `pnpm run typecheck`/`lint` (0 errors; pre-existing `@next/next/no-html-link-for-pages` warnings only, none introduced), `pnpm run test` (1369 tests, 1 pre-existing failure — `checkWorktreeCollision`, confirmed identical on the unmodified baseline via `git stash`, unrelated to this change), `npx next build` (PASS, same 32-route count, no route added/removed), `pnpm run docs:check`/`security:check`/`data-classification:check`/`threat-model:check`/`standards:check` all PASS. `pnpm run db:test`/`pnpm run test:e2e` not run — no migration in this change (nothing new to exercise against the database layer); e2e requires a browser-driven server, same disclosed condition as checkpoint 1.

**Scope:** 4 new files (`components/tables/{data-table,pagination}.tsx`, `lib/tables/pagination-range.ts`(`.test.ts`)), 2 modified screens, 3 modified docs (`02_COMPONENTS.md`, this file, `docs/runtime/CHANGE_MANIFEST.md`), 0 migrations — within the standard 5–15 file atomic-sizing guideline.

## 9. Checkpoint 3 — Shared component inventory and Design System Showcase (2026-07-26, out-of-band)

A third, separate instruction this session asked for a full shared-component inventory (14 requested categories) and a protected internal showcase visualizing every component, foundation, pattern, and business example. Full detail: `08_COMPONENT_INVENTORY.md` (new). Summary:

**What changed:** `lib/design-system/{environment,tokens,component-registry,mock-business-data,pattern-registry,migration-map}.ts` (+ 3 `.test.ts` files, 20 net-new unit tests) and a new, isolated route group `app/(internal)/internal/design-system/` (layout + 9 section pages + 6 small client/shared widgets), gated by `isNonProductionEnvironment()` (this repository's own `CARGOGRID_ENV`/`NODE_ENV`) **or** a real Supreme Admin session — reachable outside production without a seeded account, reachable by staff even in production, `notFound()` otherwise (not a friendly denial page, since the route's own existence is itself development-only information). No new shared component was built — the showcase renders exactly the 6 real primitives this document's checkpoints 1–2 already produced, plus honest, cited disclosures (`DOCUMENTED_ONLY`/`BLOCKED`/`NOT_NAMED`) for everything else this checkpoint's instruction named.

**Most consequential finding (not previously disclosed anywhere):** `Badge` and `StatusBadge` are both production-ready and have **zero real consumers** — verified by grep against `app/`. The exact screens that need them (`commercial/leads/page.tsx`'s status/source columns, `supreme/tenants/page.tsx`'s status column) already exist and render that data as plain text instead. Recorded as the highest-priority, lowest-risk entry in the new duplicate-component migration map (`08_COMPONENT_INVENTORY.md` §4), blocked only on a not-yet-built canonical-status-to-tone mapping (a Domain Component).

**Deliberately not done:** no legacy page was migrated onto a shared primitive (the migration map is a map for future, individually-authorized checkpoints, not a migration performed here); no new shared component was built ahead of a real need; light/dark mode is scoped honestly — CargoGrid has no tenant-facing dark theme token set decided anywhere, so the showcase's own toggle only recombines the existing neutral scale for its own reading chrome, verified live not to change how the real showcased components render.

**Evidence:** `pnpm run typecheck`/`lint` (0 errors, pre-existing warnings only), `pnpm run test` (1382/1382, 20 net new), `npx next build` (PASS, 10 new routes registered, all dynamic), plus a live `next dev` + Playwright verification pass (all 9 section pages load 200 with no new console errors; the one pre-existing 404 console message reproduces identically on `/login`, confirmed unrelated; real pagination click updates the URL and re-renders the correct slice; the theme toggle and viewport control both work and were screenshotted).

**Scope:** ~29 new files, 3 modified docs, 0 migrations — larger than the standard 5–15 file guideline for the same reason checkpoint 1 was (a design-system checkpoint's coherent unit of work spans a full inventory + a full showcase together), disclosed here rather than split into an unreviewable partial state.

## 10. Checkpoint 4 — Build the remaining shared components (2026-07-26, out-of-band)

A fourth instruction this session, after reviewing checkpoint 3's inventory, asked to build every shared component not yet built. This is the largest single departure from this document's own earlier caution (§2's original scope note, §5's "wait for a real consumer" reasoning) — building ahead of a named consumer for most of these, rather than per-consumer as each of checkpoints 1–3 did. The user made this trade-off explicitly (asked twice, in these words), so it is recorded here as an authorized, deliberate exception, not a silent policy reversal.

**What changed:** ~40 `ComponentEntry` rows in `lib/design-system/component-registry.ts` flipped from `DOCUMENTED_ONLY`/`NOT_NAMED` to `IMPLEMENTED`, backed by real code in three new/extended directories:

- `components/forms/` (new): `Input`, `Textarea`, `NumberInput`, `SearchInput`, `PasswordInput`, `CurrencyInput`, `DateInput`/`DateRangeInput`, `Select`, `Combobox`, `MultiSelect`, `Checkbox`, `Radio`/`RadioGroup`, `Switch`, `FormField`, `FormSection`, `ValidationMessage`/`ValidationSummary`.
- `components/ui/` (extended): `IconButton`, `ButtonGroup`, `Link`, `SplitButton`, `DropdownAction`, `Skeleton`/`SkeletonText`/`SkeletonTable`, `Spinner`, `Progress`, `EmptyState`, `ErrorState`, `SuccessState`, `PermissionState`, `Alert`, `Toast`(+`ToastProvider`/`useToast`), `Dialog`/`ConfirmationDialog`, `Drawer` (also serves Sheet), `Popover`, `Tooltip`, `DropdownMenu`, `ContextMenu`, `Tabs`, `Breadcrumb`, `CommandMenu`, `Accordion`, `Card`, `KpiCard`, `DescriptionList`, `Stat`, `Timeline`/`ActivityItem`, `Avatar`, `UserMenu`.
- `components/domain/` (new): `status-tone-map.ts` (the canonical `canonical_ref`→`StatusBadge`-tone mapping StatusBadge's own spec named as a future `components/domain/` concern) and `ApprovalDecisionPanel`.

**Zero new npm dependencies.** Every overlay/navigation primitive (`Dialog`, `Drawer`, `Popover`, `Tooltip`, `DropdownMenu`, `ContextMenu`, `Tabs`, `Toast`, `Avatar`) is built on Radix primitives already available via the `radix-ui` package (`ADR-0005`'s copy-in mechanism) — none were previously imported by this repository's own code beyond `Slot` (`Button`), so this checkpoint is the first real use of most of that dependency's surface, not a new addition. Everything else (`Input`/`Select`/`Checkbox`/`Radio`/`Switch`/`Accordion`/etc.) is plain native HTML, styled to match every existing hand-rolled field's own current appearance exactly — server-safe, zero client JS where the native element allows it (`Switch` and `Accordion` in particular need no JavaScript at all).

**Two real consumers migrated as a direct, low-risk consequence** of finally having the missing piece: `commercial/leads/page.tsx` (status + source columns) and `supreme/tenants/page.tsx` (status column) now render through `StatusBadge`/`Badge` via the new `status-tone-map.ts`, closing the single highest-priority item checkpoint 3's own migration map identified (`StatusBadge` was production-ready with zero consumers because nothing owned the domain-specific tone mapping). No other migration was performed — `docs/design-system/08_COMPONENT_INVENTORY.md` §4's updated migration map records every remaining gap (27 unmigrated `loading.tsx` files, 21+ unmigrated error blocks, 19+ unmigrated empty states, 39 unmigrated forms, 2 unmigrated approval-decision forms) as future, individually-scoped work, not done here.

**Deliberately still not built, named rather than silently skipped:**

- **Time picker** — no real consumer named it.
- **File upload / Document preview / Attachment list** — still `BLOCKED` on the same missing storage/upload pipeline as before.
- **Kanban board** — needs a drag-and-drop dependency and has no real data model/consumer to build the right shape against.
- **Calendar** (full scheduling grid) — `DateInput`/`DateRangeInput` cover the entry use case; a full grid has no real consumer.
- **Chart wrapper** — the one item in this list requiring a genuine architectural decision (which charting library, if any, to add as a new dependency) rather than just more component code. Not decided unilaterally; flagged back to the user.
- **Filter bar / Saved views / Bulk action bar** — no screen has server-side sort/filter/bulk-mutation support to build against yet (same "one owner, real consumer first" reasoning §5 already applied to Data Grid before checkpoint 2 built it against a real need).
- **Stepper / Approval queue** — no multi-step form or queue-shaped screen exists yet.
- **Sidebar item / Navigation group / Page header / Persistent top bar** — these are application-shell elements, not standalone components; both real portals still work fine as a flat 2-link top bar at their current page count, and building shell primitives without a shell redesign to consume them would be exactly the speculative-abstraction pattern this checkpoint otherwise chose to set aside for named, deliberate reasons.

**Evidence:** `pnpm run typecheck`/`lint` PASS (0 errors, same pre-existing warnings only). `pnpm run test` 1382/1382 PASS (no net-new automated tests this checkpoint — the new components are presentational/interactive UI without the kind of pure-function logic the existing `node:test` suite is set up to test; correctness was instead verified live). `npx next build` PASS, no route changed. **Live verification**: `next dev` + Playwright against `/internal/design-system/components` — confirmed live: Dialog opens via its trigger and closes via Escape (real focus-trap behavior), Tabs switches panels, Accordion expands, DropdownMenu opens and lists items, the category filter narrows to exactly the expected count (16 of 76 for "Data Entry"), and the Input live demo renders all 4 states (default/disabled/read-only/invalid) with the invalid state's red border visible in a screenshot. No new console errors.

**Scope:** ~40 new component files across 3 directories, 2 small migrated consumer files, 1 one-line addition to `button.tsx` (exporting its existing `VARIANT_CLASSES` for `IconButton` to reuse), and updates to `lib/design-system/component-registry.ts`/`migration-map.ts` plus this document and `02_COMPONENTS.md`/`08_COMPONENT_INVENTORY.md` — the largest single checkpoint in this series by file count, consistent with the user's own explicit "build everything remaining" instruction rather than this document's usual one-slice-at-a-time default.
