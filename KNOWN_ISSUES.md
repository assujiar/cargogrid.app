# KNOWN_ISSUES.md

**Template ID:** `CG-AABPP-GOV-018` (instance)
**Template version:** `0.2.0`
**Updated:** 2026-07-14T10:16:05+07:00

## 1. Standing accepted risks (from ratified decisions)

| ID | Risk | Severity | Required handling | Release effect | Owner |
|---|---|---|---|---|---|
| RPD-022 | Supreme Admin absolute CRUD can defeat audit/ledger/retention evidence | Critical (accepted) | Permanent disclosure; never claim tamper-proof/immutable | Product claims constrained | Product/Security/Finance |
| RPD-034/036 | Direct GA with no external pilot | High (accepted) | Full internal gates; zero critical defects | All pre-prod validation is internal | Product/QA/Security/SRE |
| RPD-031/037 | Contract-silent recovery is best effort | High | No implied RPO/RTO guarantee | DR claims must be evidence-backed | Legal/SRE |
| RPD-038 | Custom connectors lack generic provider abstraction | Medium/High | Shared code + explicit owner/tests/runbook | Integration maintenance cost | Architecture/Integration |

## 2. Discovery-raised issues

| ID | Issue | Severity | Discovered | Workaround | Blocks | Acceptance/closure |
|---|---|---|---|---|---|---|
| KI-001 | Repository is greenfield — no toolchain, database, CI, or ignore policy exists | Info/Low | CG-S2-DISC-001 (2026-07-14) | Expected; establish in Step 3 / Phase 0 | Nothing at discovery; blocks code until Phase 0 foundations exist | Open — resolves when Phase 0 foundations VERIFIED |
| KI-002 | `docs/blueprint/tes.md` is an unclassified placeholder inside the authoritative blueprint folder | Low | CG-S2-DISC-001 (2026-07-14) | Ignore as non-authoritative | Nothing | Open — classify/remove during Prompt 22 (existing implementation audit) or Prompt 30 (placeholder/dead-code) |
| KI-003 | No repository-root `.gitignore` before application scaffolding | Medium (future) | CG-S2-DISC-001 (2026-07-14) | Add ignore policy before introducing code/secrets | Safe secret/artifact handling once code is added | Open — resolve at Phase 0 (Prompt 85/87) before first code |

## 3. Rules

Track any issue/risk with a workaround, release effect, acceptance owner, and closure condition. Standing RPD risks are never "closed" — they carry permanent handling. Discovery-raised issues close only with evidence that the condition no longer holds.
