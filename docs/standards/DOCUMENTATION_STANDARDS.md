# CargoGrid Documentation Foundation

**Established by:** `CG-S5-PH0-013` (Prompt 92 — Documentation Foundation)
**Status:** Active — taxonomy, ownership, lifecycle, and validation tooling for the documentation that already exists (`docs/runtime/**`, `docs/adr/**`, `docs/standards/**`, `docs/build-log/**`, `docs/git/**`). Templates for audience-facing doc types with no real subject yet (user/admin/API-reference/support-runbook/release-notes — Phase 1+, once a real feature/contract/incident/release exists) are structure-only, per `docs/templates/` (§4) — the same "decide the convention now, do not write content with nothing real to describe" discipline `docs/standards/DESIGN_SYSTEM.md` §1 and `docs/standards/TESTING_STANDARDS.md` §7 already established for components and tests.

This document distills `docs/ai-agent-build-prompt-package/05-phase-00-discovery-foundation/92_DOCUMENTATION_FOUNDATION_PROMPT.md` §20–26 (already read in full, not re-derived) against what this repository's documentation actually looks like today (inventoried §1 below), not a generic documentation policy.

## 1. Inventory (Prompt 92 §20 task 1 — existing docs, duplicates, stale content, ownership)

| Location | Contains | Owner | Real duplicate? |
|---|---|---|---|
| `docs/runtime/*.md` (7 files) | Agent/runtime context — `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, `CHANGE_MANIFEST.md`, `ERROR_LEDGER.md`, `KNOWN_ISSUES.md`, `HANDOFF.md` | Runtime build agent | No |
| `docs/architecture/01_*.md`–`16_*.md` | Step 3 architecture/execution blueprint (`VERIFIED`, Lineage A reconciled) | Architecture workstream | No — `ERR-2026-003` already resolved this exact question |
| `docs/discovery/00_*.md`–`14_*.md` | Step 2 repository/runtime discovery | Architecture workstream | No |
| `docs/adr/README.md` + `ADR-000N-*.md` (8) | Bounded technical decisions | Runtime build agent (Phase 0 authority) | No |
| `docs/standards/*.md` (`CODING_STANDARDS.md`, `DESIGN_SYSTEM.md`, `TESTING_STANDARDS.md`, this document) | Engineering conventions | Owning capability prompt | No |
| `docs/git/GIT_STRATEGY.md` | Branch/merge/collision process | DevOps | No |
| `docs/build-log/phase-00/PH0-NN.md` + `00_PHASE0_EXECUTION_INDEX.md`/`00_PHASE0_WBS.md` | Phase 0 capability-prompt evidence (singular, current convention since the `ERR-2026-003` consolidation) | Runtime build agent | No |
| `docs/build-logs/CG-S2-DISC-001*.md` (2 files) | Step 2 discovery build evidence, plural-directory naming | Runtime build agent (historical) | **Disclosed, not a duplicate:** an older naming convention from Step 2, predating the `docs/build-log/phase-00/` (singular) convention Phase 0 established. Both are real, legitimate, non-overlapping evidence — `ERR-2026-003`'s consolidation removed the *Lineage B Phase 0* duplicates that briefly existed under the plural path, not this pair. Left in place; renaming/moving it would rewrite history for no evidenced benefit and is out of this task's scope. |
| `docs/blueprint/*.md` (6 files + `tes.md`) | Product/business/technical source of truth | Product | No — read-only for build agents (`AGENTS.md`) |
| `docs/ai-agent-build-prompt-package/**` | The build-prompt package itself (governance templates, phase prompts) | Governance | No — read-only for build agents except its own templates (§4 below reuses its pattern, does not edit it) |
| `AGENTS.md`, `README.md` (root) | Repository operating rules; developer entrypoint | Runtime build agent / DevEx | No |

**No stale/conflicting content found beyond what is already tracked:** the two known staleness issues (`CARGOGRID_BUILD_STATUS.md` §9's historical resume plan, `HANDOFF.md`'s previously-stale resume-instruction numbered list) were corrected at `PH0-91` (`docs/build-log/phase-00/PH0-91.md`), and the `CHANGE_MANIFEST.md` Prompts-83–90 gap is tracked as `ISS-2026-005` (`KNOWN_ISSUES.md`), not silently left undocumented. This inventory is the audit Prompt 92 §20 task 1 asks for — it does not invent new problems beyond what prior checkpoints already found and disclosed.

## 2. Audience classes

Every document belongs to exactly one class; a document serving two audiences is split, not dual-purposed (mirrors `DESIGN_SYSTEM.md` §4's "one component owner, many consumers," applied to documentation):

| Class | Audience | Location |
|---|---|---|
| Agent/runtime | Any resuming build agent, no chat context | `docs/runtime/**` |
| Architecture/governance | Architecture, Engineering | `docs/architecture/**`, `docs/discovery/**`, `docs/adr/**` |
| Engineering standards | Developer | `docs/standards/**` |
| Process | Developer, DevOps | `docs/git/**` |
| Build evidence | Runtime/audit | `docs/build-log/**`, `docs/build-logs/**` |
| Product source of truth | Product | `docs/blueprint/**` (read-only to build agents) |
| Build-prompt package | Governance | `docs/ai-agent-build-prompt-package/**` (read-only to build agents except templates) |
| Developer entrypoint | Contributor/operator | root `README.md`, `AGENTS.md` |
| User-facing *(no content yet — template only, §4)* | End user (tenant staff/customer portal) | `docs/user/` (created when Phase 1+ ships a real user-facing flow) |
| Admin-facing *(no content yet)* | Tenant Admin / Supreme Admin | `docs/admin/` |
| API reference *(no content yet)* | External integrator | `docs/api/` |
| Support/runbook *(no content yet)* | Support, DevOps/on-call | `docs/runbooks/` |
| Release notes *(no content yet)* | All | `docs/releases/` |

## 3. Lifecycle, ownership, one-authoritative-location rule

- **Lifecycle states:** `DRAFT` (being authored, not yet cited by another document) → `ACTIVE` (current, citable) → `SUPERSEDED` (replaced, retained for history, header links forward — exact vocabulary/mechanism already established by `docs/adr/README.md` §2 for ADRs; extended here as the same rule for every doc class in §2, not a competing scheme). Nothing under `docs/runtime/**`, `docs/adr/**`, `docs/architecture/**`, or `docs/build-log/**` is ever deleted once `ACTIVE` — append-only, matching `AGENTS.md`'s "never rewrite shared history" and the ADR framework's own append-only rule.
- **One authoritative location per fact, explicit derived views (business rule §24):** every fact has exactly one owning document; another document may *cite* it but must name the source, never restate a conflicting value. Concrete examples already in force: `CARGOGRID_BUILD_STATUS.md` is an explicit *dashboard/derived view* of `TASK_LEDGER.md` (not a second source of task status — restated in its own header, "Single current-state dashboard"); every `docs/standards/*.md` file opens with "distills... already `VERIFIED`, not re-derived" naming its exact source (`DESIGN_SYSTEM.md` §"This document distills...", `TESTING_STANDARDS.md` same pattern, this document's own intro above). A new document that needs this pattern states its source in its first paragraph — checked by convention (human review at authoring time), not mechanically (§5 explains why: prose-pattern matching is fragile and produces false positives, the same class of risk `check-suppressions.ts`'s self-referential-exclusion note already discovered for a different checker).
- **Update triggers/ownership:**

| Event | Documents updated in the same checkpoint |
|---|---|
| Capability prompt completed | Its own `docs/build-log/phase-NN/PH-NN.md`; `docs/runtime/TASK_LEDGER.md`; `docs/runtime/CHANGE_MANIFEST.md`; `docs/runtime/CARGOGRID_BUILD_STATUS.md`; `docs/runtime/HANDOFF.md` §3/§4; `docs/build-log/phase-NN/00_*_EXECUTION_INDEX.md` |
| ADR decided | `docs/adr/ADR-NNNN-*.md`; `docs/adr/README.md` §5/§6 |
| Error/blocker found | `docs/runtime/ERROR_LEDGER.md`; `docs/runtime/HANDOFF.md` if blocking |
| Non-blocking defect/gap found | `docs/runtime/KNOWN_ISSUES.md` |
| Standard/convention ratified | Its owning `docs/standards/*.md`; any document that previously deferred to it (cross-reference added, not restated) |

## 4. Templates for audience-facing doc types (Prompt 92 §20 task 2)

`docs/templates/USER_GUIDE_TEMPLATE.md`, `ADMIN_GUIDE_TEMPLATE.md`, `API_REFERENCE_TEMPLATE.md`, `SUPPORT_RUNBOOK_TEMPLATE.md`, `RELEASE_NOTES_TEMPLATE.md` (this checkpoint) — mirror `docs/ai-agent-build-prompt-package/01-agent-governance/12_*.md`–`19_*.md`'s existing template pattern (a fillable skeleton with required sections and an owner/audience/status header), reused rather than reinvented. Every other doc type Prompt 92 §20 task 2 names (context/status/task/build/change/decision/error/issues/handoff/ADR/schema/API-contract/data-flow/module) already has an established, working, real-instance format — `docs/ai-agent-build-prompt-package/01-agent-governance/12_*.md`–`19_*.md` for the seven runtime files, `docs/adr/README.md` §4 for ADRs, and every `docs/architecture/0N_*.md`/`docs/build-log/phase-00/PH0-NN.md` file for schema/API/data-flow/module/build formats — creating a second, parallel template for an already-real, already-working format would itself violate §1's "no real duplicate" finding. Only the five audience-facing types with **zero existing instance** (because no user-facing feature, admin surface, public API, incident, or release has ever happened in this repository — confirmed: `docs/discovery/05_ROUTE_MODULE_INVENTORY.md` and `git log` show zero `app/`/`server/` code) get a new template. Each template is structure only — no invented screenshot, endpoint, error code, or incident scenario; instantiating it with placeholder/fake content when a real feature ships would violate `AGENTS.md`'s "no demo-only persistence, no unresolved TODOs."

## 5. Validation (Prompt 92 §20 task 3, §28)

`scripts/docs/check-doc-links.ts` (this checkpoint, `pnpm run docs:check`, wired into CI) checks what is mechanically checkable without false positives:

1. **Internal link resolution:** every relative Markdown link and backtick-quoted repository-relative path across `docs/runtime/`, `docs/adr/`, `docs/standards/`, `docs/build-log/`, `docs/build-logs/`, `docs/git/`, `docs/templates/`, root `AGENTS.md`/`README.md` resolves to a real file (anchors stripped before the existence check; `http(s)://`/`mailto:` links skipped — external, not this repository's to verify).
2. **Canonical runtime-file presence:** the exact 7 files `AGENTS.md`'s "Required pre-flight" section names all exist and are non-empty — the mechanical half of the "fresh agent can reconstruct without chat" contract (§21 "Main flow").
3. **ADR index consistency:** every `ADR-NNNN` cited in `docs/adr/README.md` §6's index has a matching `docs/adr/ADR-NNNN-*.md` file.
4. **HANDOFF/TASK_LEDGER coherence:** `HANDOFF.md` §4's "Task ID/name" value is a real row in `TASK_LEDGER.md` — catches exactly the class of drift a future checkpoint could introduce by updating one and not the other.

**Deliberately not mechanically checked (§23 "Exception flow" — named, not silently skipped):** prose-level staleness (a claim that reads as current but describes an old checkpoint, as `CARGOGRID_BUILD_STATUS.md` §9 and `HANDOFF.md`'s resume instructions were before `PH0-91`'s manual fix) has no reliable automatable signal without a much larger effort (e.g. an LLM-based staleness reviewer) that this checkpoint does not build — flagged here as a known validation gap, not fabricated as covered. Required-section-per-template-type conformance is deferred until a real audience-facing document is instantiated from §4's templates (nothing to validate against yet).

## 6. Fresh-agent reconstruction contract (§21 "Main flow")

Restates `AGENTS.md`'s existing "Required pre-flight" list as the binding entry chain, now with a name and mechanical backing (§5 item 2): `docs/runtime/HANDOFF.md` → `AGENTS.md` → the other 6 `docs/runtime/*.md` files → the current phase's execution index/WBS → the relevant `docs/build-log/**` entries → the task prompt itself. No document outside this chain is required reading to resume safely — anything else is deeper context for a specific decision, not part of the mandatory path.
