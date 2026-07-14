# Prompt 44 — UX and Design System Workstream

**Prompt ID:** `CG-S3-ARCH-009`  
**Package document:** `CG-AABPP-ARCH-044`  
**Version:** `0.4.0`  
**Runtime output:** `docs/architecture/09_UX_DESIGN_SYSTEM_WORKSTREAM.md`

## Objective and value

Plan a coherent, accessible, responsive CargoGrid experience across Supreme Admin, Tenant Admin, Internal User, and Customer Portal surfaces while retaining canonical business semantics.

## Preconditions

Prompts 36–43 are complete. Read verified route/component/accessibility evidence, UX/Data/Access Design, canonical flows, access model, configuration engines, and design-system assets to preserve.

## Required tasks

1. Define portal shells, navigation, role/context switching, tenant/organization/branch context, search/command patterns, notifications, help, and responsive/PWA boundaries.
2. Define design tokens, primitives, form controls, tables/grids, filters, status/badges, dialogs/drawers, timeline, upload, chart/report, feedback, and layout ownership.
3. Specify standard loading, empty, error, offline, partial, unauthorized, forbidden, conflict, success, retry, and destructive-confirmation states.
4. Translate canonical workflows into page/route/action maps with main, alternative, exception, approval, cancellation, reversal, and recovery states.
5. Define field/record visibility, masking, disabled-versus-hidden behavior, export/search/report access, support-mode indicators, and Supreme Admin disclosures.
6. Enforce WCAG 2.2 AA, keyboard/focus, semantic names/labels, validation/live regions, contrast, reflow/zoom, reduced motion, touch targets, and accessible charts/tables/files.
7. Define latest-two stable Chrome/Edge/Safari/Firefox matrix, desktop-first internal ERP, mobile-usable field/portal workflows, PWA/offline limits, localization, branding, and terminology mapping.
8. Create page/component/test/documentation backlogs in atomic feature slices, including visual/non-regression evidence and performance budgets.

## Required output

Include experience architecture, portal/route map, design-system inventory and target, component/state contracts, workflow maps, access presentation rules, responsive/PWA/browser matrix, accessibility plan, localization/branding rules, test strategy, ADR candidates, atomic backlog, and acceptance gates.

## Completion gate

Complete only when every critical flow has states and access behavior, component reuse and preserved assets are explicit, WCAG/browser evidence is planned, and no UI code or design asset is changed.
