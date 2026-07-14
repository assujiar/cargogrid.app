# 12 — Greenfield/Brownfield Decision

**Prompt:** `CG-S2-DISC-012` (`CG-AABPP-DISC-032` v0.3.0)
**Runtime output of:** `docs/ai-agent-build-prompt-package/02-discovery/32_GREENFIELD_BROWNFIELD_DECISION_PROMPT.md`
**Status:** `VERIFIED`

## Checkpoint

Branch `claude/eloquent-mayer-s40hn4`, HEAD `d587445`. Analysis only — no scaffold, migration, deletion, rewrite, upgrade, or dependency change was made as part of this decision.

## Evidence matrix

| Dimension | Evidence | Source |
|---|---|---|
| Repository history/topology | 6 commits total; single documentation-only lineage; no application commit ever existed | `docs/discovery/01_REPOSITORY_INVENTORY.md` §1 |
| Implemented capability | 0 platform/domain capabilities implemented; all `NOT_FOUND`/`DOCUMENTED_ONLY` | `docs/discovery/02_EXISTING_IMPLEMENTATION_AUDIT.md` |
| Fixed-stack fit | No stack exists to fit or conflict with the ratified target (Next.js/Supabase/PostgreSQL) | `docs/discovery/03_TOOLCHAIN_DEPENDENCY_BASELINE.md` |
| Dependency health | No dependency exists | `docs/discovery/03_TOOLCHAIN_DEPENDENCY_BASELINE.md` |
| Database/migration state | No schema/migration exists | `docs/discovery/04_DATABASE_MIGRATION_BASELINE.md` |
| Tenant/security controls | None implemented | `docs/discovery/06_SECURITY_BASELINE.md` |
| Routes/APIs | None exist | `docs/discovery/05_ROUTE_MODULE_INVENTORY.md` |
| Tests/build | No test/build/CI exists; baseline `UNKNOWN` (not `RED`) | `docs/discovery/07_TEST_QUALITY_BASELINE.md` |
| Performance | No measurable application; baseline `UNKNOWN` | `docs/discovery/08_PERFORMANCE_BASELINE.md` |
| UX/accessibility | No UI exists; baseline `UNKNOWN` | `docs/discovery/09_ACCESSIBILITY_UX_BASELINE.md` |
| Placeholders | One trivial empty placeholder (`tes.md`); one documentation duplication, already mitigated | `docs/discovery/10_PLACEHOLDER_DEAD_CODE_INVENTORY.md` |
| Technical debt | 9 register items, of which only 2 are true technical debt (both documentation, both resolved/mitigated) | `docs/discovery/11_TECHNICAL_DEBT_RISK_REGISTER.md` |

## Asset value assessment

- **Assets with real value to preserve:** the six blueprint documents, the 430-file AI Agent Build Prompt Package, the ratified decision/assumption/conflict registers, and the persistent-context/ledger governance set (root canonical copies). These represent substantial planning investment and must not be discarded or rewritten casually.
- **Assets with zero code value:** none exist — there is no code, so there is nothing to assess for correctness, coverage, operability, extensibility, or migration cost.
- **Rewrite risk:** none — a "rewrite" is not meaningful when there is nothing to rewrite. The only risk is *scope creep in the opposite direction*: skipping ratified planning steps and jumping straight to code without an architecture step, which is exactly what this governed process is designed to prevent.
- **Data continuity / non-regression risk:** none — no data or working behavior exists to lose.

## Classification comparison

| Classification | Fit | Rationale |
|---|---|---|
| `GREENFIELD` | **Selected** | No material implementation exists (0 of 10+ platform/domain capability families implemented); all evidence across Prompts 22–31 is consistent and unambiguous |
| `BROWNFIELD_EXTEND` | Rejected | Requires a credible existing foundation; none exists |
| `BROWNFIELD_REHABILITATE` | Rejected | Requires an existing system with bounded blockers; none exists |
| `BROWNFIELD_MIGRATE` | Rejected | Requires an existing system to migrate from; none exists |
| `UNKNOWN_BLOCKED` | Rejected | Evidence is sufficient, consistent, and safe — the checkpoint is authoritative (repaired and reconfirmed in Prompt 21/22) |

## Decision

**`GREENFIELD`** — establish the application within this repository/workspace. **Confidence: High.** No dissenting evidence was found across any of Prompts 22–31.

## Assets to preserve

- `docs/blueprint/**` (6 authoritative sources) — do not edit without a ratified decision change.
- `docs/ai-agent-build-prompt-package/**` (430 files) — read-only source of execution prompts; do not delete or bulk-edit.
- `docs/ai-agent-build-prompt-package/00-control/**` registers — authoritative decisions; never silently overridden.
- Root persistent-context/ledger set (`CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, `ERROR_LEDGER.md`, `KNOWN_ISSUES.md`, `HANDOFF.md`) — canonical; keep current.
- `docs/discovery/**` (this Step 2 evidence set) — the record Step 3 architecture planning must build on.

## Boundaries needing isolation / prohibited broad rewrites

No broad rewrite is authorized or needed — there is nothing to rewrite. Prohibited: deleting or bulk-editing `docs/ai-agent-build-prompt-package/**` or `docs/blueprint/**`; skipping Step 3 architecture planning and jumping directly to Phase 1+ feature code; treating this GREENFIELD decision as license to deviate from the ratified fixed stack in `AGENTS.md` without a dedicated ADR.

## Conditions under which this decision must be revisited

- If any future session discovers untracked/hidden application code not visible to this audit (none is currently suspected).
- If a future merge reintroduces the kind of document-duplication defect seen in `ERR-2026-001`/`KI-004`, this decision's evidentiary basis (Prompts 22–31) must be re-verified against the new checkpoint before being relied upon.

## Step 3 entry/exit implications

- **Entry conditions for Step 3:** `RUNTIME_DISCOVERY_VERIFIED` (Prompt 34) plus this GREENFIELD decision.
- **Mandatory ADR topics for Step 3:** initial repository/workspace layout (Prompt 39), database schema baseline (Prompt 40), RLS/RBAC workstream (Prompt 41), configuration engine (Prompt 42), API/integration workstream (Prompt 43), UX design system (Prompt 44), testing workstream (Prompt 45).
- **Sequencing constraint:** Step 3 architecture and planning must precede any Phase 1+ feature implementation; Phase 0 (foundation: toolchain, `.gitignore`, CI, environments) must precede Phase 1 (Platform Core).
- **Evidence gaps carried into Step 3:** none blocking; RISK-008/009 (tes.md deletion, `.gitignore` timing) are Phase-0-scoped, not Step-3-blocking.

## Completion gate

Classification is supported by cited discovery evidence (Prompts 21–31, all cross-referenced above). No broad rewrite is implicitly authorized (none is possible — nothing exists to rewrite). Uncertainty is explicit (none found; confidence High). All identified risks (RISK-001..009) have an owner or an explicit non-blocking status.

Output hash: `docs/discovery/12_GREENFIELD_BROWNFIELD_DECISION.sha256`. Next eligible prompt: `CG-S2-DISC-013` — Baseline Evidence Capture.
