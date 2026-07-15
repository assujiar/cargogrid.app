# ADR-0005 — Component library foundation

Status: ACCEPTED
Date: 2026-07-15   Approver: Runtime build agent (Phase 0 governance authority, per `docs/adr/README.md` §3)   Supersedes/Superseded-by: —
Source candidate: `ADR-CAND-ARCH-020`   Owning phase/task: Phase 0 (`CG-S5-PH0-011`, Prompt 90, Design System Foundation)

## Question

`docs/architecture/09_UX_DESIGN_SYSTEM_WORKSTREAM.md` §13 (`ADR-CAND-ARCH-020`): build CargoGrid's component library on fully custom primitives, or on a headless/unstyled component library under CargoGrid's own token layer? Constraint: must not weaken RPD-019 (CargoGrid owns component structure, tenants only override logo/colors/domain/email/document presentation) or introduce a tenant-visible dependency; must support WCAG 2.2 AA keyboard/focus semantics out of the box where possible.

## Options

1. **Fully custom primitives**, built from scratch.
   - Trade-off: CargoGrid would need to independently build and test focus-trapping, ARIA roles, and keyboard interaction for every primitive (dialog, select, tooltip, etc.) — real, non-trivial accessibility engineering that a mature headless library already solves, duplicated for no benefit given RPD-019 already guarantees CargoGrid owns the visual/structural layer either way.
2. **A headless/unstyled component library, wrapped by `components/ui/` (SELECTED).** Specifically: Radix UI primitives (the unified `radix-ui` npm package, current stable `1.6.2` — verified via `npm view radix-ui version`/`dist-tags` this checkpoint), consumed via a **copy-in pattern** (source copied into `components/ui/` and owned/edited in-repo, the shadcn/ui convention — not installed as an opaque runtime UI-kit dependency).
   - Trade-off: none material against the constraint. Radix's primitives ship zero default styling (no CSS, no visual opinion) — RPD-019's "CargoGrid owns component structure" is satisfied exactly, since CargoGrid's own `components/ui/` wrapper is 100% of what renders. The copy-in pattern (not `npm install @radix-ui/react-*` consumed as a black box) means the dependency is never tenant-visible in any way (it's build-time source, not a shipped runtime API surface tenants interact with), and CargoGrid can freely modify the copied source without waiting on an upstream release.

## Decision

**Radix UI primitives (`radix-ui` package), consumed via a copy-in pattern into `components/ui/`**, not installed as a black-box runtime dependency. Every primitive CargoGrid ships is Radix's accessibility/interaction behavior (focus trap, ARIA roles, keyboard nav) plus CargoGrid's own visual layer on top — never Radix's default (nonexistent) visual styling.

**Not implemented this checkpoint.** No `components/ui/` file is created — that path is Phase 1 Platform Core scope (`docs/architecture/04_REPOSITORY_TARGET_STRUCTURE.md`'s migration-wave table, wave 2), the same boundary `ADR-0001` established for domain folders and `PH0-085`/`PH0-086` respected for `app/`/`lib/`. This ADR fixes the *decision* so Phase 1 has zero ambiguity when it creates that path; `docs/standards/DESIGN_SYSTEM.md` (this checkpoint) records the structural conventions Phase 1 must follow.

## Evidence

- `docs/architecture/09_UX_DESIGN_SYSTEM_WORKSTREAM.md` §13: `ADR-CAND-ARCH-020`'s own text and recommendation (headless/unstyled foundation wrapped by CargoGrid's own layer) — this ADR adopts that recommendation after independently verifying the concrete library choice against the current registry, not merely restating the architecture document's illustrative example.
- Real, executed evidence this checkpoint: `npm view radix-ui version` → `1.6.2`; `npm view radix-ui dist-tags` → `latest: 1.6.2` (non-prerelease; `next: 1.6.3-rc...` confirms `1.6.2` is the settled stable release, not a fluke).
- `docs/ai-agent-build-prompt-package/00-control/02_CONFIRMED_DECISION_REGISTER.md` RPD-019 (verbatim): "Tenant may change logo, colors, domain, email, and document presentation; CargoGrid controls component structure and interaction patterns."
- `docs/architecture/09_UX_DESIGN_SYSTEM_WORKSTREAM.md` §9 (WCAG 2.2 AA acceptance table) — the exact keyboard/focus/semantic-label requirements Radix's primitive layer is purpose-built to satisfy.

## Consequences

- **DB/API:** none.
- **UI:** fixes the foundation Phase 1's `components/ui/` build starts from — no primitive is built twice (once ad hoc, once "properly") because the foundation choice is settled before any component code exists.
- **Security:** copy-in (not black-box) consumption means every primitive's source is auditable in-repo like any other CargoGrid code — no hidden third-party runtime behavior.
- **Performance:** Radix primitives are individually tree-shakeable; not measured as an SLA here (no bundle exists yet to measure).
- **Migration/rollback:** trivial at this checkpoint (nothing implemented yet); once Phase 1 copies primitive source in, "rollback" means reverting those specific copied files, standard practice for any in-repo source.
- **Downstream impact:** Phase 1 Platform Core's `components/ui/` slice (`PLT-135/136` portal work) consumes this decision directly; `docs/standards/DESIGN_SYSTEM.md` §2 states the exact ownership rule ("one component owner, many consumers," from `09_*.md` §4.2) this ADR's copy-in pattern must follow.

## Propagation

Referenced by: `docs/standards/DESIGN_SYSTEM.md`; `docs/build-log/phase-00/PH0-90.md`; `docs/adr/README.md` §5.2 (marks `ADR-CAND-ARCH-020` `ACCEPTED`). Does not alter any CPD/RPD or any `docs/architecture/**` decision — it resolves the ADR that document's own §13 already scoped to this exact task.
