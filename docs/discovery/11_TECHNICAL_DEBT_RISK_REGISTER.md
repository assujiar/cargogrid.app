# 11 — Technical Debt and Risk Register

**Prompt:** `CG-S2-DISC-011` (`CG-AABPP-DISC-031` v0.3.0)
**Runtime output of:** `docs/ai-agent-build-prompt-package/02-discovery/31_TECHNICAL_DEBT_RISK_REGISTER_PROMPT.md`
**Status:** `VERIFIED`

## Scoring method

Severity/likelihood/exposure use the same Low/Medium/High/Critical scale used throughout Step 2 (Prompts 26/30). Priority = qualitative combination of severity × blast radius × reversibility, not a numeric formula, since there is not yet enough implementation surface for a quantitative model to be meaningful.

## Deduplicated register

| ID | Class | Root cause | Evidence IDs | Requirement/control links | Affected assets | Severity | Likelihood | Priority | Owner | Dependency | Candidate task | Verification | Status |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| RISK-001 | `IMPLEMENTATION_GAP` | No application code, toolchain, database, or CI exists yet (greenfield) | Prompts 01–09 (all) | Whole prompt package Phases 0–9 | Everything | Info | Certain (expected) | — (not a defect) | Architecture | none | Phase 0 foundation prompts (85–99) | Phase 0 closure gates | Open — expected, tracked as roadmap not debt |
| RISK-002 | `MISSING_EVIDENCE` (resolved) | Discovery document corruption from a parallel-PR merge (`docs/discovery/01_REPOSITORY_INVENTORY.md`) | `ERR-2026-001` | Prompt 21 integrity rule | Discovery record only | Medium | Occurred once | High (time-sensitive, now closed) | Runtime build agent | none | Repair (done this checkpoint) | Hash re-verified (`c7f8d22f…`), addendum logged | **Resolved** |
| RISK-003 | `TECHNICAL_DEBT` (documentation) | `docs/runtime/*.md` duplicate persistent-context ledgers diverged from root canonical copies; `AGENTS.md` pointed at the stale copy | `KI-004`, Prompt 22 §7 | Governance file discipline (`AGENTS.md`) | Future-agent orientation accuracy | Medium | Occurred once | Medium (mitigated) | Runtime build agent | none | Banners added + `AGENTS.md` repointed (done); full removal is a follow-up | Superseded banners present in all 7 files; `AGENTS.md` pointer verified | Mitigated — full cleanup still open |
| RISK-004 | `ACCEPTED_PRODUCT_RISK` | RPD-022: Supreme Admin absolute CRUD can defeat audit/ledger/retention evidence | `KNOWN_ISSUES.md` §1 | RPD-022 | Audit/finance/retention subsystems (once built) | Critical (accepted) | N/A (design decision, not a bug) | Standing | Product/Security/Finance | none | None — permanent disclosure requirement, not a fix candidate | Disclosure present in `AGENTS.md`/`CARGOGRID_CONTEXT.md`/`KNOWN_ISSUES.md` | Standing accepted risk — never "closed" |
| RISK-005 | `ACCEPTED_PRODUCT_RISK` | RPD-034/036: direct GA, no external pilot | `KNOWN_ISSUES.md` §1 | RPD-034/036 | Whole release process | High (accepted) | N/A | Standing | Product/QA/Security/SRE | Phase 0–9 + hardening | None | Full internal gate table `VERIFIED` at Step 16 | Standing accepted risk |
| RISK-006 | `ACCEPTED_PRODUCT_RISK` | RPD-031/037: contract-silent recovery is best effort | `KNOWN_ISSUES.md` §1 | RPD-031/037 | DR/backup claims | High (accepted) | N/A | Standing | Legal/SRE | none | None | Evidence-backed DR claims only | Standing accepted risk |
| RISK-007 | `ACCEPTED_PRODUCT_RISK` | RPD-038: custom connectors without generic provider abstraction | `KNOWN_ISSUES.md` §1 | RPD-038 | Integration workstream | Medium/High (accepted) | N/A | Standing | Architecture/Integration | none | Shared code + explicit owner/tests/runbook per connector | Reviewed per connector at build time | Standing accepted risk |
| RISK-008 | `TECHNICAL_DEBT` (documentation) | `docs/blueprint/tes.md` is an empty placeholder file inside the authoritative blueprint folder | `PH-001`, `KI-002` | none (non-authoritative) | `docs/blueprint/` cleanliness | Low | Occurred once | Low | Product | none | Owner-approved deletion | File removed and commit recorded | Open — low priority |
| RISK-009 | `EXTERNAL_DEPENDENCY` | No `.gitignore` exists before any code/secret is introduced | `KI-003` | GOV-011 / repo hygiene | First code commit safety | Medium (future) | Will occur at Phase 0 start | Medium | DevEx | Phase 0 kickoff | Add `.gitignore` before first scaffold commit | `.gitignore` present and covers secrets/build output before code lands | Open — scheduled for Phase 0 |

## Critical-path view

The only true critical-path blocker to **any** feature work is RISK-001 (nothing built yet) — this is the expected, sequential state of a repository still inside Step 2 discovery, not a defect requiring remediation. No other item blocks Step 3 architecture planning.

## Accepted-risk overlay

RPD-022/031/034/036/037/038 (RISK-004..007) are standing, ratified, permanent-disclosure risks. None is reopened, weakened, or silently resolved by this register; each is carried forward with its existing owner and disclosure location unchanged.

## Dependency map

RISK-002 and RISK-003 were resolved/mitigated independently of any other item. RISK-008 and RISK-009 depend on Phase 0 kickoff timing. RISK-004..007 depend on the corresponding Phase (Finance for RISK-004, Step 16 for RISK-005, SRE runbooks for RISK-006, Integration workstream for RISK-007) but require no action now.

## Quick containment candidates

- RISK-008 (delete `tes.md`): trivial, low-risk, needs only owner approval since it sits inside the authoritative blueprint folder.
- RISK-009 (`.gitignore`): trivial to add at the moment Phase 0 scaffolding begins; should be the very first file added alongside the first manifest.

## Architecture inputs (for Step 3)

- No legacy code/schema/API to reconcile — Step 3 starts from the blueprint documents and ratified decision register only.
- `docs/runtime/*` duplication (RISK-003) shows that parallel-agent bootstrap work must write to one canonical location; Step 3 repository-structure planning (Prompt 39) should make this explicit to prevent recurrence once real application code exists.

## External decisions/evidence needed

None blocking Step 2 closure. RISK-008 needs a one-line owner approval to delete `tes.md`; this is not required to close Step 2 (Prompt 30 already classified it without deleting it).

## Totals by class/severity/status

| Class | Count |
|---|---|
| `IMPLEMENTATION_GAP` | 1 |
| `MISSING_EVIDENCE` (resolved) | 1 |
| `TECHNICAL_DEBT` | 2 |
| `ACCEPTED_PRODUCT_RISK` | 4 |
| `EXTERNAL_DEPENDENCY` | 1 |
| **Total** | **9** |

| Severity | Count |
|---|---|
| Critical (accepted) | 1 |
| High (accepted) | 2 |
| Medium | 4 |
| Low | 1 |
| Info | 1 |

| Status | Count |
|---|---|
| Resolved | 1 |
| Mitigated | 1 |
| Open (scheduled, non-blocking) | 3 |
| Standing accepted | 4 |

## Completion gate

Every critical/high source finding from Prompts 22–30 is represented (RISK-001 through RISK-009) or explicitly not applicable (no critical/high code-level defect exists because no code exists). Duplicates are linked (RISK-002/003 trace to `ERR-2026-001`/`KI-004`). Accepted decisions (RPD-022/031/034/036/037/038) are not reopened. No fix beyond the already-completed Prompt 22 documentation repair was executed here.

Output hash: `docs/discovery/11_TECHNICAL_DEBT_RISK_REGISTER.sha256`. Next eligible prompt: `CG-S2-DISC-012` — Greenfield/Brownfield Decision.
