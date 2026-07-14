# Step 5 — Phase 0 Discovery and Foundation Prompt Package

**Document ID:** `CG-AABPP-PH0-079`  
**Version:** `0.6.0`  
**Status:** `FINAL_FOR_STEP`  
**Package authorization:** Prompt generation only. No Phase 0 runtime work is claimed or authorized by package completion.

## 1. Purpose

This package turns verified discovery and architecture into atomic Phase 0 foundation tasks. It establishes repository-aligned source/requirement controls, ADRs, environments, Git/CI/standards, design/testing/documentation foundations, observability/security/data/threat controls, analytics, feature flags, integrated verification, hardening, and handoff before Platform Core implementation.

## 2. Runtime entry gate

Before Prompt 80 or any operational Prompt 81–101:

1. Prompt 34 states `RUNTIME_DISCOVERY_VERIFIED` at the active repository checkpoint.
2. Prompt 51 states `RUNTIME_ARCHITECTURE_VERIFIED` and supplies WBS/traceability/critical path.
3. Step 4 reusable library is `PACKAGE_STEP_4_VERIFIED`.
4. Repository `AGENTS.md` and persistent context/ledgers exist and agree.
5. Phase 0 task authority, branch/worktree ownership, environment boundaries, package manager and baseline commands are known.

If not, set `PHASE_0_BLOCKED`, record exact missing evidence and stop. `STEP_5_PACKAGE_COMPLETE` is not runtime Phase 0 completion.

## 3. Required hierarchy

Prompt 80 must instantiate and maintain:

`Phase 0 → Workstream → Epic → Capability → Feature slice → Atomic implementation task → Verification task → Hardening task → Documentation task → Phase closure task`.

Prompts 81–98 are one bounded capability slice each. Prompt 99 is integrated verification, Prompt 100 hardening, Prompt 101 documentation/handoff, and Prompt 102 closure.

## 4. Execution catalogue

| Order | ID | Prompt | Primary dependency |
|---:|---|---|---|
| 0 | PH0-080 | Phase 0 WBS and runtime kickoff | Runtime entry gate |
| 1 | PH0-081 | Source alignment and context bootstrap | PH0-080 |
| 2 | PH0-082 | Requirement traceability baseline | PH0-081 |
| 3 | PH0-083 | Repository audit adoption and gap closure | PH0-081..082 |
| 4 | PH0-084 | ADR baseline and decision governance | PH0-081..083 |
| 5 | PH0-085 | Development environment foundation | PH0-083..084 |
| 6 | PH0-086 | Environment validation foundation | PH0-085 |
| 7 | PH0-087 | Git strategy foundation | PH0-083..086 |
| 8 | PH0-088 | CI/CD baseline | PH0-085..087 |
| 9 | PH0-089 | Coding standards and architecture enforcement | PH0-084..088 |
| 10 | PH0-090 | Design system foundation | PH0-083..089 |
| 11 | PH0-091 | Testing foundation | PH0-082..090 |
| 12 | PH0-092 | Documentation foundation | PH0-081..091 |
| 13 | PH0-093 | Observability baseline | PH0-083..092 |
| 14 | PH0-094 | Security baseline controls | PH0-082..093 |
| 15 | PH0-095 | Data classification foundation | PH0-081..094 |
| 16 | PH0-096 | Initial threat model | PH0-083..095 |
| 17 | PH0-097 | Product analytics baseline | PH0-082..096 |
| 18 | PH0-098 | Feature flag foundation | PH0-084..097 |
| 19 | PH0-099 | Integrated Phase 0 verification | PH0-081..098 |
| 20 | PH0-100 | Phase 0 hardening | PH0-099 |
| 21 | PH0-101 | Documentation and handoff | PH0-100 |
| 22 | PH0-102 | Phase 0 closure verification | PH0-101 |

Parallel execution is allowed only when Prompt 80 proves no dependency/file/schema/environment collision. One agent/task owns one branch and one atomic objective.

## 5. Universal operational rules

- Instantiate all `{{VARIABLES}}` from verified runtime evidence; unresolved variables block coding.
- Prompts 81–101 preserve the mandatory 36-field order and Step 4 guardrails.
- Default task boundary: one feature slice, one module boundary, one branch, one objective, normally 1–3 migrations and 5–15 changed files.
- Do not replace existing credible brownfield tooling merely to match a preferred convention.
- No feature/domain functionality beyond foundation enablement.
- No tenant-specific fork, service-role key in client, real tenant data in fixtures, applied-migration edits, hidden failures, weakened tests/RLS/RBAC, or unsupported production-ready claims.
- Every task captures baseline/post-change evidence and updates context, status, task/change/regression/traceability/error/issues/build-log/handoff documents.
- RPD-022, direct GA/no external pilot, contract-silent recovery, and custom integration policy remain visible where relevant.

## 6. Runtime states

- `PHASE_0_NOT_STARTED`
- `PHASE_0_IN_PROGRESS`
- `PHASE_0_BLOCKED`
- `PHASE_0_PARTIALLY_COMPLETE`
- `PHASE_0_VERIFIED`
- `PHASE_0_ROLLED_BACK`

Only Prompt 102 can set `PHASE_0_VERIFIED`. Package status uses `STEP_5_PACKAGE_COMPLETE` and must not be confused with runtime state.

## 7. Package completion

Package completion requires 24 non-empty files, IDs `PH0-079..102`, 21 operational prompts with 36/36 fields, all 18 mandatory Phase 0 capabilities, explicit verification/hardening/documentation/closure tasks, dependency and next-prompt links, and updated controls.

**Next package command:** `LANJUT STEP 6`
