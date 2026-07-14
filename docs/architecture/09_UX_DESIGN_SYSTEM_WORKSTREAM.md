# 09 — UX and Design System Workstream

**Prompt:** `CG-S3-ARCH-009` (`CG-AABPP-ARCH-044` v0.4.0)
**Runtime output of:** `docs/ai-agent-build-prompt-package/03-architecture-and-plan/44_UX_DESIGN_SYSTEM_WORKSTREAM_PROMPT.md`
**Status:** `VERIFIED`

## 0. Checkpoint

| Field | Value |
|---|---|
| Repository | `assujiar/cargogrid.app` |
| Working branch | `agent/cargogrid-autonomous-build` (tracked by GitHub PR #7) |
| HEAD at authoring time | `7b310413407b7e80e344c04ed40281eceb13109b` (parent of this checkpoint's commit) |
| Precondition | `docs/architecture/01_*.md` through `08_*.md` all `VERIFIED` |
| Repository state | Unchanged: zero component, zero token, zero route, zero design asset (`docs/discovery/09_ACCESSIBILITY_UX_BASELINE.md` confirms every UX/accessibility surface `NOT_FOUND`) |
| Mutation performed | **NONE** — planning only |

### Inputs read (beyond `01–08_*.md`, already fully loaded)

- Blueprint `03_CargoGrid_UX_Data_Access_Design.md` §6 (Information Architecture, full: 3-portal map, global navigation, navigation behavior, module navigation, page hierarchy), §7 (7 user-flow diagrams, full), §8 (Screen Inventory, representative rows read in full detail), §9–18 (Form/Table/Dashboard/Responsive/Accessibility/UX-Writing/State/Approval-UX/Configuration-UX/White-label-UX, all full), §29 (Performance-aware UX), §30 (QA Acceptance Framework), §31 (Open Decisions `OD-UX-001/002`, `OD-OPS-001`, `OD-DATA-001`, `OD-SEC-001`, `OD-LOC-001`), §32 (Final Design Guardrails, 10 items, verbatim)
- Tech Arch §7 (Frontend Architecture, full: App Router structure, Server/Client Component boundaries, Server Actions, Route Handlers, data-fetching/cache strategy, streaming/Suspense, dynamic import, middleware, auth session handling, tenant-aware routing, white-label domain resolution, hydration avoidance, form handling, large-table strategy, bulk-upload strategy)
- `04_REPOSITORY_TARGET_STRUCTURE.md` §4 (`app/(public|supreme|tenant|customer)/**`, `components/{ui,domain,tables,forms}/`), `docs/discovery/09_ACCESSIBILITY_UX_BASELINE.md` (confirms zero implementation)
- `00-control/02_CONFIRMED_DECISION_REGISTER.md` RPD-004 (responsive PWA, online-first, no native mobile/offline for first production), RPD-019 (controlled white-label — CargoGrid owns component structure/interaction patterns, tenant customizes logo/colors/domain/email/document presentation only)

## 1. Scope and method

This document does not create a component, token, route, or design asset (prompt completion gate). It defines the **experience contract layer** every Phase-1–9 UI capability prompt must implement against: portal shells and navigation (§2), the portal/route map (§3), the design-system inventory and its target repository home (§4), component/state contracts (§5), canonical workflow-to-page/route/action maps (§6), access-presentation rules (§7), the responsive/PWA/browser matrix (§8), the accessibility plan (§9), localization/branding rules (§10), performance budgets (§11), test strategy (§12), ADR candidates (§13), the atomic backlog (§14), and acceptance gates (§15).

## 2. Experience architecture

### 2.1 Three portals, three mental models

Reproduces Blueprint §6's principle verbatim: Supreme Admin does not work in the same workspace as tenant users, and a Customer User is never given a hidden internal menu — each portal is a distinct mental model, data boundary, and navigation, not a role-filtered view of one shared shell. This maps exactly onto `04_REPOSITORY_TARGET_STRUCTURE.md` §4's four App Router route groups (Tech Arch §7.1, verbatim): `app/(public)/` (login, forgot-password — unauthenticated), `app/(supreme)/supreme/` (Supreme Admin Portal), `app/(tenant)/[tenantSlug]/` (Tenant Internal Portal), `app/(customer)/portal/[tenantSlug]/` (Customer Portal). **Route group is UX/routing boundary only, never an authorization boundary** (Tech Arch §7.1 guardrail, verbatim) — every page inside every group still passes through the full `06_*.md` §3 8-stage evaluation flow; a route group prevents a Customer User from *seeing* the tenant-internal navigation, it does not by itself prevent a misauthorized request from reaching tenant-internal data.

### 2.2 Portal shells and navigation

| Portal | Navigation groups (Blueprint §6.1, verbatim, 10/11/10 groups) | Owning domain(s) (`01_*.md` §2) |
|---|---|---|
| Supreme Admin Portal | Tenant, Subscription, Module & Feature, White-label, Access Control, Configuration Studio, Integration Hub, Builder Studio, Audit & Security, Billing & Support | Platform (`TEN-IAM`, `WLB`, `CFG`, `API-WH`, `AUD`) |
| Tenant Internal Portal | Home, Commercial, Operations, Warehouse, Procurement & Vendor, Finance & Accounting, HRIS, Ticketing, Loyalty, Reports, Administration | Every business domain (`COM`, `OPS`, `PRC`, `FIN`, `HRS`, `TKT`, `LYL`, `REP`) plus Platform for Administration |
| Customer Portal | Dashboard, Request Quote, Booking, Shipment & Tracking, Warehouse & Inventory, Document & ePOD, Invoice/Billing/Payment, Ticket, Loyalty & Reward, Account | `CPT` intake, entering through `COM`/`TKT`'s own creation paths (`03_*.md` §5's two intake contracts) — never a parallel `cpt.*` data model |

### 2.3 Role/context switching and org context

Company/branch/customer/tenant selectors (Blueprint §6.2's top-bar row) are constrained by the requesting principal's scope from the moment they render — the selector's option list is itself a permission-filtered query (§7's access-presentation rule extended to navigation chrome), never a full list with client-side hiding (Blueprint §32 guardrail #2, verbatim: "Jangan mengambil hidden sensitive field ke browser hanya untuk disembunyikan di UI" — extended here to org-context options, not just data fields). Tenant/company switcher is reserved for Supreme Admin, shared-service, and multi-company-scoped users (Blueprint §6.2) — a single-company internal user never sees a switcher with one disabled option; the control itself is omitted.

### 2.4 Search, notifications, help

Global search (top bar, Blueprint §6.2) returns only RLS/field-masking-compliant results — search is a read path through the identical `06_*.md` §3 evaluation flow every list/detail query uses, backed by RPD-039's PostgreSQL FTS/trigram-first strategy (`06_*.md` §7), never a separate unscoped search index. The notification center groups by approval/exception/SLA/finance/system (Blueprint §6.2) and sources from the Notification Engine (`07_*.md` §3, `config_type = 'notification'`) — payload respects field-level security exactly as a direct query would (Blueprint §6.2's "Notification payload respects field-level security," restated as a hard rule, not a UI nicety). Help/documentation surfaces are out of this workstream's atomic backlog (§14) unless a specific in-app help widget is later scoped by a capability prompt — no generic "help system" is invented ahead of evidence.

### 2.5 Responsive/PWA boundary (portal-level)

Per RPD-004 (responsive PWA, online-first — resolves Blueprint `OD-UX-002` "native mobile app timing," see §13), every portal is a single responsive web application, never a separate native codebase; a PWA manifest/service-worker enables installability and basic offline-shell behavior only (§8 details the exact boundary) — this is a portal-shell property, not a per-page opt-in.

## 3. Portal/route map

Directly extends `04_REPOSITORY_TARGET_STRUCTURE.md` §4's App Router tree with Blueprint §6.3's module navigation, tying every navigation group to its owning domain's route segment and phase:

| Portal segment | Route | Owning domain | Phase (`01_*.md` §7) |
|---|---|---|---|
| `app/(supreme)/supreme/tenants` | Tenant list/detail | Platform `TEN-IAM` | 1 |
| `app/(supreme)/supreme/subscriptions` | Subscription/module/feature-flag | Platform `TEN-IAM`/`FLAG` | 1 |
| `app/(supreme)/supreme/system` | White-label studio, Configuration Studio, Integration Hub, Builder Studio, Audit & Security, Billing & Support | Platform `WLB`/`CFG`/`API-WH`/`REP`/`AUD` | 1 (foundation), 9 (Builder Studio's report/dashboard builder, `REP`) |
| `app/(tenant)/[tenantSlug]/dashboard` | Home | Platform (role-based, cross-domain widgets) | 1 |
| `app/(tenant)/[tenantSlug]/commercial` | Lead, CRM, Opportunity, Costing, Quotation, Contract | `COM` | 2 |
| `app/(tenant)/[tenantSlug]/operations` | Job Order, Shipment, Dispatch, Milestone, ePOD, Claim, Incident | `OPS` | 3 |
| `app/(tenant)/[tenantSlug]/operations` (Warehouse sub-tree, per `01_*.md` `WMS` note) | Inbound, Putaway, Inventory, Picking, Packing, Outbound | `OPS` (`WMS` sub-capability) | 3 (basic), 5 (Advanced WMS) |
| `app/(tenant)/[tenantSlug]/procurement` | Vendor, Onboarding, Rate, Sourcing, PO, Invoice matching | `PRC` | 6 |
| `app/(tenant)/[tenantSlug]/finance` | Billing Readiness, Invoice, AR/AP, Payment, Journal, GL, Closing | `FIN` | 4 |
| `app/(tenant)/[tenantSlug]/hris` | Employee, Recruitment, Attendance, Leave, Payroll, ESS | `HRS` | 7 |
| `app/(tenant)/[tenantSlug]/support` | Ticket Queue, SLA, Escalation, Knowledge Base | `TKT` | 7 |
| `app/(tenant)/[tenantSlug]/loyalty` | Program, Tier, Point, Reward, Redemption, Campaign | `LYL` | 8 |
| `app/(tenant)/[tenantSlug]/reports` | Dashboards, operational/finance reports, scheduled export | `REP` (reads every domain's governed dataset, `06_*.md` §7) | Rolling, per domain readiness; full Builder Studio at 9 |
| `app/(tenant)/[tenantSlug]/admin` | Master data, User, Role, Permission, Workflow, Approval, Form, Service, Integration | Platform (`TEN-IAM`/`CFG`/`API-WH`) | 1 |
| `app/(customer)/portal/[tenantSlug]/dashboard,shipments,invoices,...` | Dashboard, Request Quote, Booking, Tracking, Warehouse/Inventory, Document/ePOD, Invoice, Ticket, Loyalty, Account | `CPT` (read + 2 intake contracts into `COM`/`TKT`, `03_*.md` §5) | 3 (basic Portal: dashboard/shipments), rolling per domain, full scope by 8 |

No route segment is created ahead of its owning domain's phase (`01_*.md` §7, restated from `08_*.md` §2 rule 4 for the UI layer) — the Warehouse route note above is the one intentional exception, already resolved as a sub-capability of `OPS` rather than a separate top-level segment (`01_*.md`'s `WMS` module is owned by `OPS`, not a distinct domain).

## 4. Design-system inventory and target

### 4.1 Inventory (Blueprint §17's builder catalogue's UI-primitive counterpart)

| Category | Primitives (Blueprint §6.4/§9/§10/§11, consolidated) | Target home (`04_*.md` §4) |
|---|---|---|
| Design tokens | Color, typography, spacing, radius, elevation, breakpoint, motion — one CargoGrid-owned base set, tenant overrides limited to §10's white-label variables (RPD-019) | `components/ui/` (exact token mechanism `ADR_REQUIRED`, §13) |
| Primitives | Button, input, select, checkbox/radio, badge, avatar, tooltip, icon | `components/ui/` |
| Form controls | Section/step wizard, conditional field, reference picker (RLS-aware), attachment upload, bulk-edit affected-record preview | `components/forms/` |
| Tables/grids | Server-paginated table, saved filter, configurable column, bulk-action selection-token pattern (never thousands of IDs from browser, Tech Arch §7.16), row detail drawer, pinned exception row | `components/tables/` |
| Filters | Explicit allowlist filter bar (mirrors `08_*.md` §4.4's server-side allowlist — one shared allowlist definition, not a UI-only convenience) | `components/tables/` |
| Status/badges | Canonical-status-to-tenant-label rendering (never the reverse — `07_*.md` §6's `canonical_ref` is the binding source, the badge is a projection of it) | `components/ui/` |
| Dialogs/drawers | Confirmation (destructive-action variant, §5), record detail drawer, approval decision panel | `components/domain/` (approval panel is domain-aware) |
| Timeline | Activity timeline, approval timeline (Blueprint §16), shipment milestone timeline | `components/domain/` |
| Upload | Async progress, type/size validation, signed-URL-gated preview (never renders a file whose `malware_scan_status != 'clean'`, `08_*.md` §10.2) | `components/domain/` |
| Chart/report | Dynamically imported (Tech Arch §7.9 — never in the initial bundle) | `components/domain/` |
| Feedback | Toast/inline validation/empty-state/error-state components (§5's state contracts) | `components/ui/` |
| Layout | Portal shell, module dashboard, list/queue/board/calendar/map switcher, record detail composition (Blueprint §6.4's page-hierarchy diagram) | `app/(*)/layout.tsx` per route group + `components/ui/` shared chrome |

### 4.2 Ownership rule

Exactly as `08_*.md` §2 rule 1 established "one business-service owner, two protocol faces" for the API layer, this document establishes **one component owner, many consumers**: a table/form/status/timeline primitive is implemented once in `components/{ui,tables,forms}/` and composed by every domain's page — no domain re-implements its own table pagination or its own approval-decision panel. `components/domain/` holds compositions that are domain-aware (e.g., a Shipment milestone timeline) but still built from `components/ui/`/`components/tables/` primitives, never a domain-local fork of a primitive.

## 5. Component/state contracts

Every data-bearing component (table, detail page, form, dashboard widget) implements the same 11 states — this is the binding contract, not a per-page decision:

| State | Trigger (Blueprint §15) | Contract |
|---|---|---|
| Loading | Data fetch, background job, export/import, document generation | Skeleton for known layout; progress bar for upload/import/export/generation; never a blank screen (Tech Arch §7.8 Suspense guardrail) |
| Empty | No data in scope; filter too narrow; module not configured | Explanation + next action, only if the user holds the create permission (Blueprint §32 guardrail #2 extended to actions, not just fields) |
| Error | Validation, access denied, integration failed, server error | Human-readable message + `error.request_id` (`08_*.md` §4.5's correlation ID) + retry if safe + support link; never a raw exception/SQL detail |
| Offline | PWA offline-shell activation (§8) | Read-only cached shell where defined; no silent data-loss on a queued mutation — an unsent mutation is visibly pending, not dropped |
| Partial | Widget-level fetch failure inside a multi-widget dashboard | Only the failed widget shows an error state; the rest of the page remains interactive (Blueprint §15 loading-state note, "Avoid blocking entire page if only widget loads") |
| Unauthorized | Stage 1/2 (entitlement/tenant membership) denial | Redirect/blocked-page pattern, no partial-page render of data the request never received |
| Forbidden | Stage 3–6 (RBAC/scope/field/status) denial | Blueprint §14's exact copy pattern: state *what* is inaccessible without describing *why* in a way that leaks existence/shape of hidden data (`"You do not have access to view cost information for this shipment."`) |
| Conflict | `record_version` mismatch (`08_*.md` §4.8) | Explicit conflict message, offer reload-and-reapply, never silently overwrite |
| Success | Mutation committed | Confirmation matching Blueprint §14's UX-writing rule (verb + object, e.g. "Quotation submitted") |
| Retry | Transient integration/job failure | Retry affordance only where Tech Arch §26.2/`08_*.md` §7.4 mark the failure retryable; a `dead_letter`/business-critical exception state shows the exception (`07_*.md` §7.4's 16 `EXC-*` catalogue), not a bare retry button |
| Destructive confirmation | Delete, override, reopen, reject, reason-required action (Blueprint §9 "Reason required") | Confirmation dialog requires the typed/selected reason before the action is enabled; the reason is what lands in `audit_logs`, not a decorative field |

Every one of these 11 states is itself permission/scope-aware (Blueprint §15's "Access/Security Note" column, verbatim principle applied uniformly) — an empty state never reveals a create action the viewer cannot use, and an error state never leaks tenant data or a stack trace.

## 6. Workflow maps

Each of Blueprint §7's 7 canonical user flows is translated into a page/route/action sequence, cross-referenced to `07_*.md`'s 24 status transitions and 14 approval use cases (the same catalogues `07_*.md` §7.1/§7.2 already bound to the Configuration Engine — this document does not re-derive them, it binds them to screens):

| Flow (Blueprint §7.x) | Primary route(s) (§3) | Status transitions used (`07_*.md` §7.2) | Approval use case (`07_*.md` §7.1) | Alternative/exception/reversal states |
|---|---|---|---|---|
| Platform Setup (§7.1) | `admin` (tenant) / `supreme/system` (Configuration Studio) | N/A (config lifecycle, `07_*.md` §5, not a business-entity transition) | N/A | "Rule Valid?" no-branch loops to fix (Blueprint diagram); config publish failure shows dependency-validation error (`07_*.md` §8) |
| Commercial: Lead→Quotation (§7.2) | `commercial` | Lead: New→Assigned→Contacted, Qualified→Converted; Quotation: Draft→Submitted→Approved→Sent→Accepted/Expired | Customer approval, Cost request, Quotation approval | Disqualify-with-reason (destructive-confirmation state, §5); Revise-or-Reject loop back to Quotation Builder; Lost-reason capture on rejection |
| Operations: Job→Invoice (§7.3) | `operations` | Shipment: Draft→Confirmed→Planned→Dispatched→In Transit→Delivered→ePOD Completed→Closed | Job creation override, Shipment assignment override, Cost overrun, Job closing | Exception/delay/incident recording loops back to Milestone Update (§5's error/retry states); ePOD revision-request loop; Job-closing-checklist "not ready" loop |
| Vendor: Registration→Payment (§7.4) | `procurement` | Vendor: Draft→Submitted(Under Review)→Approved(Active) | Vendor rate approval, Vendor invoice mismatch | Reject-or-request-revision loop; Dispute/adjustment loop on invoice mismatch |
| Warehouse: Inbound→Outbound (§7.5) | `operations` (WMS sub-tree) | (WMS-specific transitions, Phase 3/5 scope, not among the 6 entities `07_*.md` §7.2 lists — no transition invented here ahead of Phase 5 evidence) | N/A at MVP scope | Hold/damage/return branch on QC reject; short-pick/substitute/exception branch on picking |
| HRIS: Recruitment→Payroll (§7.6) | `hris` | (Employee/Payroll-specific, Phase 7 scope) | Payroll finalization | Close-candidate branch on offer decline; Approval loop on leave/overtime request |
| Ticket/Loyalty (§7.7) | `support`, `loyalty`, Customer Portal `ticket`/`loyalty` | Ticket: Open→Assigned→In Progress→Resolved→Closed | Ticket escalation, Loyalty redemption | Escalation loop on SLA breach (§5's retry-vs-exception distinction) |

Blueprint §8's Screen Inventory (representative rows read: `SUP-TNT-001/002`, `SUP-SUB-001`, `SUP-WLB-001`, `SUP-CFG-001/002/003`, `TNT-HOM-001`, `COM-LEAD-001/002`, `COM-OPP-001`, `COM-CST-001`, `COM-QTN-001`) is the binding baseline for every future page prompt's empty/error/loading/permission/desktop/mobile columns — this document does not re-type the full inventory (it is a growing baseline per Blueprint §8's own framing: "Screen boleh bertambah, tapi behaviour dasar tidak boleh dilanggar"), it fixes the 11-state contract (§5) that every current and future screen-inventory row must satisfy.

## 7. Access-presentation rules

- **Field/record visibility mirrors `06_*.md` exactly.** A `field_masked`-family field (cost/margin/finance/payroll/PII/security, `06_*.md` §5.2) is never fetched to the browser only to be hidden by CSS/conditional render (Blueprint §32 guardrail #2, binding) — the server omits the field from the response entirely when the viewer lacks the gating permission; the component renders "not available" only when the field is legitimately absent from the payload, never by client-side branching on a value it was never supposed to receive.
- **Disabled vs. hidden is a deliberate choice, not a default.** A control is **hidden** when the viewer has no path to ever use it (no permission, no entitlement) and **disabled** when the viewer could use it but a state/lifecycle/precondition currently blocks it (e.g., "Approve" disabled while a prior parallel-approval branch is still pending) — a disabled control always carries a reason (tooltip/inline text), never a silent no-op.
- **Export/search/report access is the same policy family as list/detail** (`06_*.md` §4, negative test #7, restated at the UI layer): an export button is hidden if the viewer lacks `Export` permission on that resource (`06_*.md` §5.1's 19 actions), and a completed export never contains a field the same viewer's list/detail view would have masked.
- **Support-mode indicators.** Any page rendered under an active `support_access_grants` row (`06_*.md` §2.3) shows a persistent, non-dismissible impersonation banner naming the grant's reason/case/expiry (Tech Arch §23.9 "Visible banner during impersonation," `06_*.md` §6) — this is a portal-shell-level component (§2), not a per-page opt-in, so no page can be built that forgets it.
- **Supreme Admin disclosures.** Every screen that could expose a Supreme Admin mutation of a normally-immutable record (§8 of `06_*.md`, RPD-022) must render that mutation's audit trail (before/after values) inline, not just log it silently — the UI is where "CargoGrid must never claim audit/financial records are immutable" (`06_*.md` §8, verbatim) becomes visible to a reviewing human, not only queryable in `audit_logs`.

## 8. Responsive/PWA/browser matrix

- **Browser support:** latest two stable versions of Chrome, Edge, Safari, Firefox (prompt task #7, no blueprint-evidenced wider matrix — IE/legacy browsers are out of scope, consistent with a 2026-launch greenfield product).
- **Desktop-first internal ERP, mobile-usable field/portal workflows:** Tenant Internal Portal and Supreme Admin Portal are desktop-first (wide tables, split drawers, keyboard shortcuts, canvas/matrix builders — Blueprint §12); field-facing flows (dispatch, warehouse task, ePOD) and the entire Customer Portal are mobile-usable by design, not a cut-down desktop view (Blueprint §12's per-context table, reproduced by reference — internal ERP list/complex form/configuration builder/dashboard rows are desktop-first with tablet/mobile degradation; dispatch/warehouse-task/ePOD/customer-portal rows are mobile-first).
- **PWA/offline limits (resolves `OD-OPS-001`, see §13):** per RPD-004, the baseline is online-first responsive PWA — installable shell, no per-transaction offline queue/sync at MVP. A PWA manifest and service-worker provide app installability and a cached-shell offline state (§5's "Offline" contract: read-only cached shell, no silent mutation loss) for field-facing routes (dispatch, warehouse task, ePOD) specifically, since those are the routes Blueprint `OD-OPS-001` names as the future-enhancement candidate — this document does not build offline sync, it only ensures the offline-shell state (§5) does not block that future enhancement, per RPD-004's explicit framing ("design should not block it").
- **Realtime scope:** identical to `06_*.md` §7's allow-listed channels (dispatch board, active shipment timeline, approval counter, ticket assignment, warehouse task queue) — no UI component subscribes to an unlisted channel, and no realtime widget is the primary data source for a page (it augments a server-fetched initial state, per Tech Arch §7.6).

## 9. Accessibility plan (WCAG 2.2 AA)

Reproduces Blueprint §13 verbatim as the binding acceptance criteria, one row per prompt task #6 item:

| Area | Requirement | Acceptance |
|---|---|---|
| Keyboard/focus | All core actions keyboard-reachable; visible focus indicator; focus not lost after validation error or modal close | User completes form/table/modal/approval action without a mouse |
| Semantic names/labels | Programmatic labels on every input | Screen reader identifies field label and error |
| Validation/live regions | Errors specific, adjacent to field, summarized at top for long forms; live region announces async validation/submission result | User can jump to first error; screen-reader users are notified of async state changes without a page reload |
| Contrast | Text/buttons/status badges meet readable contrast, validated per white-label theme before publish (ties to `07_*.md`'s config lifecycle — a branding config cannot reach `Active` without a contrast check, restated as a publish-time gate, not a design-time suggestion) | Contrast check is part of the White-label Studio's publish flow (Blueprint §18) |
| Reflow/zoom | Layout usable at 125–150% browser zoom | No hidden primary action at that zoom range |
| Reduced motion | Avoid unnecessary motion; no critical information depends on animation | Loading state remains clear with motion reduced/disabled |
| Touch targets | Minimum touch-target size on mobile-first routes (§8) | No accidental mis-tap on dispatch/warehouse-task/ePOD/customer-portal primary actions |
| Non-color status | Status uses label + icon/text, not color alone (Blueprint §13, restated at the badge-primitive level, §4.1) | Color-blind user distinguishes status/exception without relying on hue |
| Accessible charts/tables/files | Chart/report components (dynamically imported, §4.1) carry a data-table or text-summary alternative; large tables (§4.1) support keyboard navigation without breaking focus/permission boundaries (Blueprint §10's "Focus does not bypass permission") | Screen-reader user can extract the same information a sighted user gets from a chart |

## 10. Localization/branding rules

- **Canonical semantics never move.** Restates `07_*.md` §6's binding rule at the UX layer: a tenant may relabel a status/menu/entity term (Blueprint §17's Custom Terminology builder, Blueprint §32 guardrail #10 — "Jangan menghilangkan canonical state/entity walaupun tenant mengubah label"), but the badge/status component (§4.1) always renders from `canonical_ref`, never from the tenant label alone, so downstream reporting/finance/audit are never confused by a relabeled status.
- **RPD-019 fixes the branding boundary.** Tenant customization is scoped to logo, colors, domain, email presentation, and document templates (Blueprint §18); CargoGrid owns component structure and interaction patterns — this **resolves Blueprint `OD-UX-001`** ("exact visual design system tokens beyond white-label variables," see §13): the token set (§4.1) is one CargoGrid-owned base, and the white-label override surface is exactly RPD-019's five items, not an open-ended theming API.
- **Contrast/fallback guardrails (Blueprint §18, verbatim):** theme contrast validated before publish (ties to §9); invalid branding assets fall back to a safe default theme rather than breaking login; template variables are whitelisted, never arbitrary code (matches `07_*.md` §11's "no arbitrary executable code" prohibition applied to document/email templates).
- **Localization sequencing** follows RPD-016 (Indonesia-first, later multi-country) — the UI's localization bundle structure accommodates additional locales without a tenant-specific source fork (Blueprint §32 guardrail #4), but only Bahasa Indonesia/English are populated at MVP; `OD-LOC-001`'s country sequencing remains Finance/HR's decision, not re-litigated here.

## 11. Performance budgets

Reproduces Blueprint §29 (UX/data performance requirements) bound to `08_*.md` §12's already-fixed numeric budgets — this document adds no second, conflicting performance doctrine:

| Requirement | UX-layer rule | Shared budget/mechanism |
|---|---|---|
| No client-side filtering of large datasets | Server-side filter/sort/search only (Blueprint §32 guardrail #1) | `08_*.md` §4.4 allowlist |
| No `SELECT *` to browser | Column-projected fetch; configurable-column state informs the query, not a client-side hide | `04_*.md` §4's `server/queries/` layer |
| Pagination class | Offset/cursor/keyset exactly as `08_*.md` §4.3 assigns per table | `08_*.md` §4.3 |
| Common page/API budget | 500ms; complex report 2s | Tech Arch §32.7, `08_*.md` §12 (same numbers, not restated differently) |
| Heavy/long-running UI action (export, bulk import, document generation) | Async job + progress UI + result file, never a blocking request | `08_*.md` §9/§10.3 long-running job pattern |
| Dashboard widgets | Pre-aggregated/materialized where heavy (Blueprint §11's per-dashboard "Data Strategy" column); partial-failure state (§5) isolates one slow widget from the page | Blueprint §29 "Materialized views," `07_*.md` §13 `report`/`dashboard` config type |
| Bundle size | Chart/map/PDF-preview/builder/rich-text libraries dynamically imported (Tech Arch §7.9) | This document, §4.1 |
| Hydration | Small, task-specific Client Components; no large permission matrix serialized to the client (Tech Arch §7.14, verbatim) | Tech Arch §7.14 |

## 12. Test strategy

| Test type | Applied to |
|---|---|
| Portal access | Each persona (Supreme Admin, Tenant Internal roles, Customer Portal user) sees only its correct portal/menu/module/action (Blueprint §30, restated) |
| State contract | Every one of §5's 11 states has at least one test per component category (§4.1) — loading/empty/error/offline/partial/unauthorized/forbidden/conflict/success/retry/destructive-confirmation |
| Field-masking parity | A UI field hidden/masked for a role matches exactly what `06_*.md` §5.2/§10's negative tests assert at the API layer — no UI-only masking that the API would still leak, and no API masking the UI fails to also hide |
| Workflow/status | Invalid lifecycle transition blocked in the UI (button disabled with reason, §7) and rejected server-side if attempted anyway; valid transition creates an audit entry visible in the activity timeline (§4.1) |
| Approval | Sequential/parallel/conditional/threshold/delegation/escalation/rejection/revision/resubmission all render correctly in the Approval Timeline/Decision Panel (Blueprint §16) |
| Configuration publish | Draft/validate/preview/publish/rollback/effective-date/dependency-validation flow (Blueprint §17.1) works end-to-end in the Configuration Studio UI, matching `07_*.md` §5/§8's lifecycle and dependency-validation gates exactly |
| Responsive | Every screen-inventory row (§6) usable per its desktop/tablet/mobile behavior column at the postures fixed in §8 |
| Accessibility | WCAG 2.2 AA automated + manual pass per §9's 8 areas |
| Performance | Every §11 budget row has a corresponding load/latency test |
| Visual/non-regression | Screenshot-diff baseline per component category (§4.1) and per portal shell (§2), gated in CI before merge — prevents an unreviewed visual change from shipping silently; exact tooling `ADR_REQUIRED` (§13) |

## 13. ADR candidates — 3 resolved (via existing RPDs, no new document needed), 2 new

**Blueprint `OD-UX-002` resolved**: native mobile app timing is fixed by RPD-004 — responsive PWA, online-first, no native mobile app for first production (§2.5, §8).

**Blueprint `OD-OPS-001` resolved**: offline mode for warehouse/ePOD is fixed by RPD-004's "design should not block it" framing — the offline-shell state (§5, §8) is planned now; offline sync/queue is an explicit future enhancement, not built at MVP.

**Blueprint `OD-UX-001` resolved**: "exact visual design system tokens beyond white-label variables" is fixed by RPD-019 — CargoGrid owns one base token set and component structure; the tenant override surface is exactly RPD-019's five items (logo, colors, domain, email, document presentation), not an open theming API (§10).

| ID | Question | Constraint | Recommendation | Owner | Blocking state |
|---|---|---|---|---|---|
| `ADR-CAND-ARCH-020` | Component library foundation: fully custom primitives, or built on a headless/unstyled component library (e.g. a Radix-primitives-style foundation) under CargoGrid's own token layer? | Must not weaken RPD-019 (CargoGrid owns component structure) or introduce a tenant-visible dependency; must support WCAG 2.2 AA keyboard/focus semantics (§9) out of the box where possible | Adopt a headless/unstyled primitive foundation wrapped by CargoGrid's own `components/ui/` layer — reduces the accessibility-primitive surface CargoGrid must build/test from scratch (focus trapping, ARIA roles) while keeping 100% visual/structural control, consistent with RPD-019 | Architecture/UX | `ADR_REQUIRED`, non-blocking — resolve at Phase 0 design-system foundation (Prompt 90) |
| `ADR-CAND-ARCH-021` | Exact design-token mechanism (CSS custom properties vs. a Tailwind-theme-config-driven approach) and token file location within `components/ui/` | Must support per-tenant runtime override (RPD-019's 5 items) without a rebuild/redeploy per tenant, and must support the contrast-validation publish gate (§9) | Adopt CSS custom properties scoped per tenant (set at the White-label domain-resolution middleware layer, Tech Arch §7.13) as the runtime-override mechanism, with a build-time token source of truth (exact tool, e.g. Tailwind theme extension referencing the same custom properties) — avoids a rebuild per tenant while keeping one authored token source | Architecture/UX | `ADR_REQUIRED`, non-blocking — resolve at Phase 0 design-system foundation (Prompt 90), alongside `ADR-CAND-ARCH-020` |

Visual/non-regression tooling (§12's last row) is a bounded pattern, `ADR_REQUIRED`, folded into the same Phase 0 Prompt 90/91 resolution rather than given a separate numbered candidate — it is a test-infrastructure choice, not a design decision.

## 14. Atomic backlog

Sized 1–3 slices each, sequenced to `01_*.md`'s phase order and this document's own §2–§11:

| Slice | Phase | Content | Depends on |
|---|---|---|---|
| Design-system foundation | 0 (Prompt 90) | Token mechanism (resolves `ADR-CAND-ARCH-021`), component-library foundation (resolves `ADR-CAND-ARCH-020`), `components/ui/` primitives, 11-state contract (§5) implemented once per primitive category | API/webhook/job foundation (`08_*.md` §15, shared route/middleware layer) |
| Portal shells | 1 | 4 route groups (§2.1) with layout/navigation chrome, role-based Home dashboard shell, support-mode banner (§7), tenant/company/branch selector (§2.3) | Design-system foundation, Platform identity core (`05_*.md`/`06_*.md` Phase-1 slices) |
| Configuration Studio UI | 1 | Workflow/Approval/Role/Permission/Form/Field/Status/Notification/Numbering builders (Blueprint §17), publish-pattern flow (§17.1) bound to `07_*.md`'s lifecycle | Portal shells, Configuration Engine backend (`07_*.md` §15) |
| White-label Studio | 1 | Branding/domain/terminology/template editor with preview-as-role/customer and contrast-gated publish (§9/§10) | Portal shells |
| Commercial UI | 2 | Lead/Opportunity/Costing/Quotation screens per §6's workflow map; first parity pass against `08_*.md` REST/GraphQL fields | Portal shells, Commercial REST/GraphQL fields (`08_*.md` §15) |
| Operations + basic WMS + basic Portal UI | 3 | Job/Shipment/Dispatch/Milestone/ePOD screens; Warehouse task UI (mobile-first, §8); Customer Portal dashboard/shipments (read + 2 intake contracts) | Commercial UI, Operations REST/GraphQL fields |
| Finance UI | 4 | Billing readiness/Invoice/AR-AP/Payment/Journal/Closing screens, posted-record-locked state (§5) | Operations + basic WMS + basic Portal UI, Finance REST/GraphQL fields |
| Advanced WMS UI | 5 | Full warehouse task/zone/bin UI beyond basic WMS | Operations + basic WMS + basic Portal UI, Advanced TMS/WMS schema |
| Procurement UI | 6 | Vendor/Onboarding/Rate/Sourcing/PO/Invoice-matching screens | Finance UI, Procurement REST/GraphQL fields |
| HRIS/Ticketing UI | 7 | Employee/Payroll/ESS screens; Ticket queue/SLA/escalation screens | Procurement UI, HRIS/Ticketing REST/GraphQL fields |
| Loyalty + full Customer Portal | 8 | Program/Tier/Redemption screens; remaining Customer Portal navigation groups (§2.2) | HRIS/Ticketing UI, Loyalty REST/GraphQL fields |
| Builder Studio + Reports UI | 9 | Report/Dashboard builder (Blueprint §17), scheduled report UI, remaining `REP` dashboards per domain | Loyalty + full Customer Portal, `07_*.md` §13's `report`/`dashboard` config-type adoption |
| PWA/offline-shell for field routes | 3 (with Operations), hardened through 5 | Manifest/service-worker install + cached-shell offline state (§8) for dispatch/warehouse-task/ePOD routes specifically | Operations + basic WMS + basic Portal UI |
| Accessibility/visual-regression CI gate | 0 (infrastructure), exercised from Phase 1 onward | WCAG 2.2 AA automated checks + screenshot-diff baseline (§12), wired into the same CI pipeline Tech Arch §28.1 already defines | Design-system foundation |

No slice ships a screen for a domain ahead of that domain's own schema/API phase (§3's rule, restated) — the UX workstream never becomes a second, faster track that outruns the data/API layers it depends on.

## 15. Acceptance gates

Every critical flow (§6's 7 canonical flows) has its full state set defined (§5) and its access behavior specified (§7) — not just a happy-path mock. Component reuse is explicit and enforced structurally (§4.2's "one component owner, many consumers"), and every asset this document references as "preserved" is the Blueprint's own catalogued asset (design tokens, screen inventory, builder catalogue), never an invented one. WCAG 2.2 AA evidence is planned as a CI gate (§9, §12, §14), not deferred to an end-of-project audit. No UI code, token file, or design asset was created or changed (§0, confirmed against `git status`).

## 16. Completion statement

Experience architecture (§2), the portal/route map (§3), the design-system inventory and its target repository home (§4), the 11-state component contract (§5), 7 workflow-to-page/route/action maps (§6), access-presentation rules (§7), the responsive/PWA/browser matrix (§8), the 8-area WCAG 2.2 AA accessibility plan (§9), localization/branding rules (§10), performance budgets aligned to `08_*.md` §12's numbers (§11), and a 10-row test strategy (§12) are all defined as planning artifacts, with zero UI code or design asset created. 3 blueprint-level Open Decisions are resolved by already-ratified RPDs (`OD-UX-001` by RPD-019, `OD-UX-002`/`OD-OPS-001` by RPD-004) rather than left open or re-litigated; 2 new ADR candidates are raised (`020` component-library foundation, `021` design-token mechanism), both non-blocking and deferred to Phase 0 Prompt 90. The 14-slice atomic backlog (§14) sequences every UI slice strictly behind its owning domain's schema/API phase — no UI slice outruns the data layer it depends on.

Next eligible prompt: `03-architecture-and-plan/45_TESTING_WORKSTREAM_PROMPT.md` → `docs/architecture/10_TESTING_WORKSTREAM.md`.
