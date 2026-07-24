# Layout and Navigation

Source of decisions: `docs/architecture/09_UX_DESIGN_SYSTEM_WORKSTREAM.md` §2/§3 (portal architecture, route map — `VERIFIED`, cited not re-derived), `ADR-0017` (portal branding rules). This document adds implementation-precision detail (what actually exists today vs. specified) that `09_*.md` deliberately left at planning precision.

## 1. Application shell — current implementation vs. specification

| Element | Specified (`09_*.md` §2) | Implemented today | Status |
|---|---|---|---|
| Route-group-per-portal (`(public)`/`(supreme)`/`(tenant)`/`(customer)`) | 4 route groups, route group is UX boundary only, never authorization | `(public)`, `(supreme)`, `(tenant)` exist; `(customer)` does not (Phase 8, not yet due) | `IMPLEMENTED` (3/4) |
| Persistent top bar | Portal name, primary nav, org-context selector, global search, notifications, user menu | Supreme/Tenant Admin layouts render a minimal header (name + 2 nav links) — no search, notifications, user menu, or org-context selector | `DOCUMENTED_ONLY` for the missing pieces — none needed yet (each portal has ≤2 pages today) |
| Sidebar | Full navigation-group tree (10/11/10 groups per portal, `09_*.md` §2.2) | None — both portals use a flat top-bar link list, appropriate at 2 pages | `DOCUMENTED_ONLY` — due once a portal's page count makes a flat top-bar list unusable (roughly 5+ top-level destinations) |
| Breadcrumb | Hierarchical location trail | None | `DOCUMENTED_ONLY` |
| Workspace header | Record-detail page header (title, status, primary actions) | Each detail page (`leads/[leadId]`, `opportunities/[opportunityId]`, etc.) renders its own ad hoc header | `DOCUMENTED_ONLY` — extraction due once a second detail-page pattern diverges/converges enough to prove the shared shape |
| Tabs / secondary navigation | Within-record view switch | None yet | `DOCUMENTED_ONLY` |
| Context panel / drawers | Side-anchored supplementary content | None yet | `DOCUMENTED_ONLY` |
| Sticky regions | Sticky table header/toolbar for long scrolls | None yet (no table long enough to need it) | `DOCUMENTED_ONLY` |
| Page width | Desktop-first internal ERP: full-width for dense tables, readable max-width for long forms/settings/narrative content (this task's own §7 instruction) | Not yet formalized as a token/utility — pages use ad hoc `max-w-*` or none | `DOCUMENTED_ONLY` — recommend a `--content-max-width` token (e.g. `72ch`/`960px`) for narrative/settings pages when the first such page is built; not invented here without a real consumer |
| Scroll behavior | Sticky toolbar, virtualized rows for large tables | None yet | `DOCUMENTED_ONLY` |
| Mobile behavior | Desktop-first internal, mobile-usable field/customer flows (`09_*.md` §8, `RPD-004`) | Internal portals render fine at mobile widths today only because they are simple (flex/stack layouts); no dedicated mobile navigation pattern (e.g. a collapsing sidebar) exists because no sidebar exists yet | `DEFERRED` alongside sidebar |
| Tenant and branch context | Company/branch/customer selector, permission-filtered options (`09_*.md` §2.3) | None — every implemented screen is single-tenant-scoped via the route's own `[tenantSlug]`, no multi-company/branch switcher UI exists | `DOCUMENTED_ONLY` — no multi-company/branch domain model surfaced in the UI yet |
| Portal switching | Supreme ↔ Tenant Admin is via full navigation (sign-out/sign-in-as-different-account links), never a live in-app switcher (correct — they are different mental models, `09_*.md` §2.1) | `IMPLEMENTED` (by absence — no switcher exists, matching the "distinct mental model" rule) | `IMPLEMENTED` |
| Module switching | Cross-domain navigation within the Tenant Internal Portal | Only Commercial and Admin route groups exist; module switching is 2 top-bar links today | `DOCUMENTED_ONLY` for the eventual multi-module nav; correct/complete for the current 2-module reality |
| Permission-aware navigation | A nav link never appears for a destination the viewer cannot access | Both layouts' nav links are static (not permission-filtered) — because both portals currently have exactly the pages every "allowed" viewer of that portal can reach (no finer-grained per-link permission exists yet at this page count) | `DOCUMENTED_ONLY`/`DEFERRED` — becomes a real requirement the moment a portal adds a page not every "allowed" viewer should see |

## 2. Tenant white-label wiring — current state (implemented this checkpoint)

`app/(tenant)/[tenantSlug]/admin/layout.tsx` resolves and applies the tenant's effective brand (primary/secondary colors as CSS custom-property overrides on the shell root; tenant logo rendered in the header, falling back to the CargoGrid wordmark) — see `01_TOKENS_AND_THEME.md` §4 for the mechanism. **Not yet applied** to `app/(tenant)/[tenantSlug]/commercial/layout.tsx` (the only other tenant route-group layout that exists) — that layout renders CargoGrid-default styling today. This is a disclosed, scoped gap (`07_GAP_ANALYSIS_AND_ROADMAP.md`), not an inconsistency left silently: extending the same two-line pattern (`resolveTenantPortalThemeForRequest` + `style={theme?.cssVars}`) to `commercial/layout.tsx` is a small, low-risk follow-up this task did not execute in order to keep this checkpoint's diff bounded and independently reviewable, consistent with `AGENTS.md`'s atomic-task-sizing discipline (this task already touches `app/globals.css`, 2 ADRs, 7 new docs, 6 new/changed component files, and 1 layout — adding a second layout edit for a mechanically identical change was judged marginal value against diff size, not a technical blocker).

## 3. Supreme Admin Portal — branding boundary (restated, `ADR-0017` §4)

`app/(supreme)/supreme/layout.tsx` renders CargoGrid's own brand only, by construction (it does not import `lib/theme/resolve-portal-theme.ts` or any tenant-brand resolution — verified this checkpoint, and a header comment now states this explicitly so a future edit does not "fix" it into tenant-branded by mistake). No tenant-scoped preview/detail screen exists yet inside the Supreme shell (`09_*.md` §14 names a future White-label Studio slice) — when one is built, `ADR-0017` §4 already fixes the rule: tenant branding may appear inside that nested context, never in the shell's own persistent chrome.

## 4. Customer Portal — not yet built

`app/(customer)/` does not exist (Phase 8, `09_*.md` §14's atomic backlog). Nothing to align. `ADR-0017` §4's rules (stronger tenant branding permitted, CargoGrid interaction/accessibility/semantic-state rules still mandatory) bind whichever future checkpoint builds it.

## 5. Authentication surfaces — pre-auth branding gap

`app/(public)/login/page.tsx` renders CargoGrid's default styling unconditionally — no tenant-slug-to-brand pre-auth resolution exists. Named as a disclosed gap in `ADR-0017` §4 and `01_TOKENS_AND_THEME.md`, not implemented this checkpoint (it requires a tenant-resolution strategy before authentication — e.g. subdomain/custom-domain parsing — that touches routing/middleware decisions beyond a design-system checkpoint's scope).
