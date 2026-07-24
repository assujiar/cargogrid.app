# ADR-0017 — CargoGrid Adaptive Industrial UI: design language and white-label governance boundary

Status: ACCEPTED
Date: 2026-07-24   Approver: Runtime build agent (repository governance authority, per `docs/adr/README.md` §3)   Supersedes/Superseded-by: —
Source candidate: None — formalizes this task's own Product/Design instruction as a binding design-governance record, the same pattern `ADR-0015` used for a qualitative decision not previously promoted to a numbered ADR.
Owning task: CargoGrid Design System Expansion and Implementation (see `ADR-0016`'s header for why this is out-of-band, not a numbered Commercial-phase prompt).

## Question

Two related questions this task's instruction settles and this ADR records durably: (1) what is CargoGrid's permanent design identity/visual language, replacing the placeholder-neutral posture `docs/standards/DESIGN_SYSTEM.md` has carried since Prompt 90; (2) exactly which presentation properties a tenant may override under white-label (RPD-019) versus which remain platform-controlled always — restated here at implementation precision now that `components/ui/` and the white-label backend (`PLT-117`) both exist, where `09_UX_DESIGN_SYSTEM_WORKSTREAM.md` §10 and `DESIGN_SYSTEM.md` §6 only fixed it at planning precision.

## Decision

### 1. Design identity

CargoGrid's permanent design language is **"CargoGrid Adaptive Industrial UI"** — the product should feel like an **Enterprise Logistics Control Tower**: dense, exception-first, calm by default, vivid only where a decision or a problem needs attention.

Binding principles (verbatim from Product/Design, recorded here as the canonical source every future UI checkpoint cites instead of re-deriving):

- Flat first; depth on demand.
- Desktop-first for internal portals (already `RPD-004`/`09_*.md` §8 — restated, not changed).
- Dense ERP-style information architecture.
- Exception-first: the UI foregrounds what needs a decision, not decorative summary.
- Calm by default; vivid only for action, selection, warning, or exception.
- Performance-first, accessibility-first (already `AGENTS.md` binding — restated, not changed).
- Shared primitives first (already `ADR-0005`/`09_*.md` §4.2's "one component owner, many consumers" — restated, not changed).
- White-label capable, audit-aware, role-aware, tenant-safe (already binding via `PLT-111/112/113/114/117` — restated, not changed).

Recommended visual balance: **85% flat, 10% subtle elevation, 5% soft tactile interaction.** The 3-level elevation scale `DESIGN_SYSTEM.md` §2 already decided (`--shadow-sm/md/lg`, this checkpoint's `app/globals.css` addition — those tokens did not exist in CSS before this task) is deliberately restrained (no blur, no glassmorphism) to hold that ratio.

**Never use:** glassmorphism, heavy neumorphism, excessive blur, decorative startup dashboards, oversized marketing cards inside operational portals, excessive gradients, deeply nested cards, decorative animation, arbitrary tenant-specific layouts, tenant-specific component forks. This list is binding on every future component/screen checkpoint, the same way `09_*.md` §8's browser matrix or §9's accessibility table are binding, not aspirational.

### 2. White-label governance boundary (precision restatement of RPD-019)

**Architecture:** `CargoGrid Core Design System` + `Tenant Theme Layer` — unchanged from `ADR-0006`'s mechanism (CSS custom properties, resolved server-side, no client-supplied theme authority). This ADR fixes the *exact property list* on each side of the boundary, since `RPD-019`'s original five items (logo, colors, domain, email, document presentation) were fixed before `components/ui/` or the brand schema existed to check the list against.

**Tenant-configurable** (subject to `app.tenant_brand_versions`' schema — see the gap analysis for which of these the current schema already stores versus would need a new column for):

| Property | Schema status |
|---|---|
| Primary color | Implemented (`tokens.primary`, `BrandTokensSchema`) |
| Secondary color | Implemented (`tokens.secondary`, `BrandTokensSchema`) |
| Primary logo | Implemented (`logo_asset_url`) |
| Login branding | Implemented via the same logo/token surface (login page renders the resolved default until a future checkpoint wires pre-auth tenant resolution — see gap analysis) |
| Customer Portal branding | Implemented via the same logo/token surface (no Customer Portal route exists yet, Phase 8 — nothing to wire today) |
| Email branding | Implemented (`email_sender_name`, `email_logo_asset_url`) |
| Document branding | Implemented (`document_template_refs`, whitelisted keys only, `DocumentTemplateRefsSchema`) |
| Compact logo | **Not yet in schema** — no `compact_logo_asset_url` column exists; documented as a deferred, additive migration in the gap analysis, not implemented silently here |
| Favicon | **Not yet in schema** — same as compact logo |
| Accent color | **Not applicable at this precision** — `RPD-019`'s five-item surface is exactly primary/secondary/logo/domain/email+document presentation; an "accent" third color was never ratified and is not added here (adding a third tenant-controlled hue is a product decision, not a design-system implementation detail — named as an open question in the gap analysis, not decided unilaterally) |
| Supported custom-domain presentation | Implemented at the schema/routing layer (`supabase/migrations/20260717103015_create_custom_domain.sql`, out of this ADR's scope to re-describe) |

**Never tenant-configurable, always platform-controlled** (restates `DESIGN_SYSTEM.md` §6 at implementation precision):

Layout structure; navigation architecture; typography scale (`--text-*`, `--font-*` families); spacing scale; radius system (`--radius-*`); elevation system (`--shadow-*`); table density rules (`--row-height-*`, §3 below); workflow behavior; semantic status colors (`--color-success/warning/danger/info` — structurally impossible to override: `BrandTokensSchema` is a `.strict()` Zod object with exactly `primary`/`secondary` keys, so a tenant payload containing a `danger`/`success`/etc. key is rejected by validation before it ever reaches storage, not merely hidden in the UI); destructive-action treatment (`components/ui/button.tsx`'s `destructive` variant resolves `bg-danger`, never `bg-primary`/`bg-secondary` — a tenant cannot make their delete button look like their brand color); focus behavior; accessibility rules; component geometry; authorization behavior.

**Theme resolution order** (restates `DESIGN_SYSTEM.md` §6/`09_*.md` §10, fixed at implementation precision against the real `app.evaluate_tenant_brand()` contract, `server/queries/white-label.ts`):

1. Published valid tenant theme (`EffectiveTenantBrand.source === "tenant"`).
2. Supported platform or plan default — **not implemented today**: `app.evaluate_tenant_brand()` currently has exactly two sources, `tenant` and `default` (`BRAND_SOURCES` in `server/contracts/white-label/white-label.ts`); a plan-tier default tier does not exist in schema. Named as a deferred item, not fabricated here.
3. CargoGrid default theme (`ADR-0016`, `source === "default"`).

Fallback is atomic at the schema layer already: `BrandTokensSchema` validates the entire token object at write time (`set_tenant_brand_tokens`), and `app.evaluate_tenant_brand()` returns one complete row per tenant, never a partial merge of tenant-plus-default fields — there is no code path that could return `{ primary: <tenant value>, secondary: <default value> }` as a hybrid. This ADR records that guarantee as binding, not merely observed.

**Theme authority is never accepted from:** URL color parameters, arbitrary cookies, local storage, user-supplied CSS/HTML/JavaScript. Confirmed by inspection this checkpoint — no route, middleware, or component in this repository reads a theme value from any of those sources; the only theme-authority path is `app.evaluate_tenant_brand()`'s server-side RPC. This ADR fixes that as a permanent constraint, not merely today's implementation state.

### 3. Density (restates and completes `DESIGN_SYSTEM.md` §2's spacing decision)

Three density tiers — **not tenant-controlled** (platform-controlled per §2 above): Compact, Default, Comfortable. Row-height reference values (`--row-height-compact/default/comfortable`, `app/globals.css`, this checkpoint): 34px / 38px / 46px, within the instructed 32–36 / 36–40 / 44–48px bands. No `components/tables/` primitive exists yet to consume these tokens (Phase 1's design-system inventory named `components/tables/` as a target home, `09_*.md` §4.1, not yet built) — tokens are authored now so the first table primitive has no density decision left to make.

### 4. Portal branding rules (restates `09_*.md` §7/§10 at implementation precision)

- **Supreme Admin Portal shell** (`app/(supreme)/supreme/layout.tsx`) renders CargoGrid's own default brand only — this ADR forbids any future checkpoint from wiring tenant-brand resolution into that layout's own chrome. Tenant branding may only appear in a tenant-scoped preview/detail context nested inside the Supreme shell (not built yet — no such screen exists in this repository today; `docs/design-system/07_GAP_ANALYSIS_AND_ROADMAP.md` names it as future Supreme Admin White-label Studio work, `09_*.md` §14's already-planned slice).
- **Tenant Internal Portal shell** (`app/(tenant)/[tenantSlug]/**/layout.tsx`) resolves and applies the tenant's effective brand (primary/secondary/logo) this checkpoint, for the Admin route group specifically (`admin/layout.tsx`) — see `docs/design-system/07_GAP_ANALYSIS_AND_ROADMAP.md` for which other tenant route groups (`commercial/layout.tsx` etc.) still render CargoGrid-default and are named as a follow-up alignment pass, not silently left inconsistent without disclosure. Layout structure, navigation, component geometry, and status colors remain CargoGrid's regardless of tenant branding (§2 above).
- **Customer Portal:** no route exists yet (`app/(customer)/`, Phase 8) — nothing to align today. This ADR's rules bind whichever future checkpoint builds it: stronger tenant branding permitted, but CargoGrid interaction/accessibility/semantic-state rules still apply (§2 above, unconditionally).
- **Authentication surfaces** (`app/(public)/login`): pre-auth tenant resolution is **not implemented today** — the login page renders CargoGrid's default brand unconditionally; no tenant-slug-to-brand resolution occurs before authentication. This is a real, disclosed gap (named in `docs/design-system/07_GAP_ANALYSIS_AND_ROADMAP.md`), not a claim of a feature that exists. When a future checkpoint implements it, this ADR's fallback rule already binds it: on any tenant-resolution failure, render CargoGrid default, never a partial/flash-of-invalid theme, never leak the internal resolution error to the response.

## Evidence

- Product/Design instruction (this task's own prompt) — the authoritative source for §1's identity language and §2/§3/§4's governance boundaries.
- `docs/ai-agent-build-prompt-package/00-control/02_CONFIRMED_DECISION_REGISTER.md` RPD-019 (verbatim, already cited by `ADR-0005`) — this ADR does not alter RPD-019, it makes its five-item surface precise against the schema/component reality that now exists.
- `server/contracts/white-label/white-label.ts` (`BrandTokensSchema`'s `.strict()` shape) — direct code inspection confirming the structural (not merely conventional) guarantee that semantic colors cannot be tenant-submitted.
- `components/ui/button.tsx` (`VARIANT_CLASSES.destructive`) — direct code inspection confirming destructive actions never resolve to a brand token.
- Direct repository search this checkpoint (`grep` for URL/cookie/localStorage/inline-style theme reads) — zero matches, supporting §2's "never accepted from" claim as an observed fact, not an assumption.

## Consequences

- **DB/API:** none directly (no migration this checkpoint). Two schema gaps are named, not fixed: compact-logo/favicon columns, and a plan-tier default theme source. Both require an additive migration and are explicitly deferred — see the gap analysis for owner/trigger.
- **UI:** binds every future component/screen checkpoint to the anti-pattern list and 85/10/5 elevation ratio (§1); binds the Tenant Admin layout's theme wiring added this checkpoint (`docs/design-system/07_GAP_ANALYSIS_AND_ROADMAP.md` §"Implemented this checkpoint") as the pattern future route-group alignment must follow, not a one-off.
- **Security:** restates, does not weaken, the existing structural guarantee that tenant input cannot reach semantic/destructive/authorization-relevant presentation.
- **Performance:** none.
- **Migration/rollback:** trivial — this is a documentation/governance ADR; reverting it does not touch code behavior beyond the two files this checkpoint's own change manifest entry lists.
- **Downstream impact:** every future Supreme Admin tenant-preview screen, Customer Portal build-out, and pre-auth branding checkpoint inherits this ADR's rules rather than re-deriving them.

## Propagation

Referenced by: `docs/standards/DESIGN_SYSTEM.md` §6; `docs/design-system/00_INDEX.md`, `01_TOKENS_AND_THEME.md`, `03_LAYOUT_NAVIGATION.md`, `07_GAP_ANALYSIS_AND_ROADMAP.md`; `ADR-0016`; `docs/adr/README.md` §6 (index). Does not alter `RPD-019`, `ADR-0005`, `ADR-0006`, or any `docs/architecture/**` planning document.
