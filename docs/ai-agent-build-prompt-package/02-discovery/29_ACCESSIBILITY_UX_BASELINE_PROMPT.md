# Prompt 29 — Accessibility and UX Baseline

**Prompt ID:** `CG-S2-DISC-009`  
**Package document:** `CG-AABPP-DISC-029`  
**Version:** `0.3.0`  
**Parent:** Step 2 — Repository Discovery and Baseline  
**Runtime output:** `docs/discovery/09_ACCESSIBILITY_UX_BASELINE.md`

## Objective

Baseline existing UX architecture and accessibility evidence across CargoGrid portals without redesigning or modifying the product.

## Source requirements

- UX, Data and Access Design, including WCAG 2.2 AA, responsive/PWA, state, navigation, forms, tables, and portal rules.
- Master Prompt §§7–11, 15–16 and Step 2.
- Delivery Plan test/browser/readiness requirements.
- GOV-010 UX/accessibility and non-regression controls.

## Preconditions and guardrails

Prompts 21–28 are complete. Use static inspection and existing safe accessibility/browser commands only. Do not install browsers, change snapshots, modify styles/components/content, start production-linked services, or claim conformance from static inspection alone.

## Required tasks

1. Inventory design-system tokens, components, icons, typography, spacing, breakpoints, responsive layouts, PWA assets, localization, and portal-specific shells.
2. Map principal navigation, dashboard, list/table, search/filter, detail, form, modal/drawer, upload, import/export, notification, and error experiences.
3. Inspect loading, empty, error, offline, partial, unauthorized, forbidden, success, retry, and destructive-confirmation states.
4. Inspect semantic structure, landmarks, headings, names/labels, keyboard order, focus visibility/restoration/trapping, skip links, validation, live regions, status messages, reduced motion, zoom/reflow, and touch targets.
5. Inspect contrast evidence, non-color cues, chart/table alternatives, file-upload feedback, and accessible authentication/MFA/session-expiry flows.
6. Inventory existing automated and manual accessibility tests, browser matrix, device coverage, and the latest-two-supported-browser policy evidence.
7. Run existing safe axe/Playwright/component checks only when prerequisites already exist and are isolated. Record exact result and limitations.
8. Classify each control as `TESTED`, `INSPECTED`, `NOT_RUN`, or `NOT_FOUND`; rank user impact and affected portals.

## Required output

Write `docs/discovery/09_ACCESSIBILITY_UX_BASELINE.md` with checkpoint, portal/view inventory, design-system assessment, state coverage, WCAG 2.2 AA control matrix, keyboard/focus/forms/table findings, responsive/PWA/browser evidence, automated/manual test results, ranked defects/gaps, and baseline trust classification.

## Completion gate

Complete only when tested and inspected evidence are clearly separated, affected routes/components are cited, no conformance is overstated, and the worktree remains reconciled.
