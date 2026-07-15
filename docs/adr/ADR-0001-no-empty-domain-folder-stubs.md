# ADR-0001 — No empty domain-folder stubs

Status: ACCEPTED
Date: 2026-07-15   Approver: Runtime build agent (Phase 0 governance authority, per `docs/adr/README.md` §3)   Supersedes/Superseded-by: —
Source candidate: `ADR-CAND-ARCH-011`   Owning phase/task: Phase 0 (`CG-S5-PH0-004` raised the resolution; formalized here at `CG-S5-PH0-005`)

## Question

When a domain's route group and query/module files (`procurement/`, `hris/`, `support/`, `loyalty/`, and every other phase-scoped domain) are first created in the repository, are they created **eagerly** as empty, unrouted stubs at Phase 1 platform scaffolding, or **only when their owning phase begins** (Procurement Phase 6, HRIS/Ticketing Phase 7, Loyalty/Portal Phase 8)?

## Options

1. **Eager empty stubs at Phase 1.** Create every domain folder up front so the target tree is visible early.
   - Trade-off: recreates the `tes.md` placeholder class of defect (`docs/discovery/10_*.md` `PH-001`, `RISK-008`) at directory granularity; produces false "coverage" signals (a folder that looks implemented but is not); makes the `NOT_FOUND`-vs-`IMPLEMENTED` honesty the discovery baseline depends on unverifiable; invites dead/unrouted code that later audits must special-case.
2. **Per-phase creation (SELECTED).** A domain folder is created only in the same capability slice that lands its first working, tested capability.
   - Trade-off: the full target tree is not visible from day one — but it is fully specified in `docs/architecture/04_REPOSITORY_TARGET_STRUCTURE.md`, which is the correct place for a *plan*, whereas the repository should reflect *built* state.

## Decision

**Option 2.** The repository must not contain empty or placeholder domain-folder scaffolds. A domain folder (route group, module directory, query file) is created only in the slice that implements and tests its first real capability. The architecture *plan* for those folders lives in `04_REPOSITORY_TARGET_STRUCTURE.md`; the *repository* reflects only built, tested state.

## Evidence

- `docs/discovery/12_GREENFIELD_BROWNFIELD_DECISION.md` — greenfield; nothing to preserve, so no pre-existing stub forces option 1.
- `docs/discovery/10_PLACEHOLDER_DEAD_CODE_INVENTORY.md` (`PH-001`) and `docs/discovery/11_TECHNICAL_DEBT_RISK_REGISTER.md` (`RISK-008`) — the one existing placeholder (`tes.md`) is already classified as debt; eager stubs would multiply exactly this class of finding.
- `docs/build-log/phase-00/PH0-83.md` §4 — this rule was raised and adopted as a scaffold-hygiene rule during repository-audit adoption; this ADR formalizes it.
- `docs/architecture/04_REPOSITORY_TARGET_STRUCTURE.md` — establishes the target tree as a plan with `ADR_REQUIRED` bounded patterns, consistent with deferring physical folder creation to the owning slice.

## Consequences

- **DB/API/UI:** none now (no code). Forward: each phase's scaffolding prompt creates only its own domain surface.
- **Security:** positive — no unrouted/dead surface that RLS/RBAC audits must special-case.
- **Performance:** none.
- **Migration/rollback:** none; rule is preventive. Rollback is trivial (rule is documentation).
- **Downstream impact:** binds every scaffold-creating prompt from `PH0-085` onward and every phase's capability slice; enforced by stale-evidence trigger **T3** in `PH0-83.md` §5 (reject a PR introducing an empty domain folder).

## Propagation

Referenced by: `docs/build-log/phase-00/PH0-83.md` §4 and §5 (T3); `docs/build-log/phase-00/PH0-84.md`; `docs/adr/README.md` §5.2/§6; `docs/runtime/KNOWN_ISSUES.md` (scaffold-hygiene rule). Does not alter any CPD/RPD or any `docs/architecture/**` decision — it operationalizes `04_*.md`'s plan-vs-built distinction.
