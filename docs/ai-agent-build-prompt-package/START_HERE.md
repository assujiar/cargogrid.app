# START_HERE - CargoGrid AI Agent Build Prompt Package

**Package ID:** `CG-AABPP`  
**Package version:** `0.18.0-step17`  
**Status:** Final package-generation checkpoint  
**Use this file when:** a new AI agent needs to understand and execute the CargoGrid build prompt package without prior conversation context.

## 1. What this package is

This is a controlled prompt package for building CargoGrid, a multi-tenant SaaS ERP for logistics, freight forwarding, 3PL and in-house logistics operations. The package contains source alignment controls, governance templates, discovery prompts, architecture prompts, reusable execution templates, phase implementation prompts, hardening prompts, release/go-live prompts and final package validation prompts.

## 2. What this package is not

This package is not proof that CargoGrid has been implemented. It is not production-ready, market-ready or generally available by itself. Runtime execution must happen later against one authorized target repository and must pass the gates in order.

## 3. Source authority order

1. `CargoGrid_Product_Concept_Brief.md` is the primary source of truth.
2. Documents `01`-`05` refine the product and delivery plan without overriding confirmed product decisions.
3. Control files in `00-control/` record ratified decisions, assumptions, conflicts, requirement coverage, build status and manifest.
4. Later prompts must preserve all accepted-risk disclosures and runtime gates.

## 4. First files to read

1. `00-control/00_PACKAGE_README.md`
2. `00-control/01_SOURCE_OF_TRUTH_MATRIX.md`
3. `00-control/02_CONFIRMED_DECISION_REGISTER.md`
4. `00-control/03_ASSUMPTION_REGISTER.md`
5. `00-control/04_CONFLICT_REGISTER.md`
6. `00-control/05_REQUIREMENT_COVERAGE_MATRIX.md`
7. `00-control/06_PACKAGE_BUILD_STATUS.md`
8. `00-control/07_PROMPT_PACKAGE_MANIFEST.md`

## 5. Runtime execution order

1. Use Step 1 governance templates before making repository changes.
2. Run Step 2 discovery prompts `20`-`34` against one authoritative repository checkpoint.
3. Run Step 3 architecture prompts `35`-`51` only after Step 2 runtime closure.
4. Use Step 4 reusable templates only for authorized bounded tasks.
5. Run Phase 0 prompts `79`-`102` after runtime Step 2-3 closure.
6. Run Phase 1 prompts `103`-`140` only after `PHASE_0_VERIFIED`.
7. Run Phase 2 prompts `141`-`165` only after `PHASE_1_VERIFIED`.
8. Run Phase 3 prompts `166`-`188` only after `PHASE_2_VERIFIED`.
9. Run Phase 4 prompts `189`-`218` only after `PHASE_3_VERIFIED`.
10. Run Phase 5 prompts `219`-`248` only after `PHASE_4_VERIFIED`.
11. Run Phase 6 prompts `249`-`271` only after `PHASE_5_VERIFIED`.
12. Run Phase 7 prompts `272`-`297` only after `PHASE_6_VERIFIED`.
13. Run Phase 8 prompts `298`-`327` only after `PHASE_7_VERIFIED`.
14. Run Phase 9 prompts `328`-`367` only after `PHASE_8_VERIFIED`.
15. Run Step 15 hardening prompts `368`-`389` only after `PHASE_9_VERIFIED`.
16. Run Step 16 release/go-live prompts `390`-`412` only after `FULL_SYSTEM_HARDENING_VERIFIED`.
17. Use Step 17 prompts `413`-`430` to validate the package itself.

## 6. Non-negotiable safety rules

- Do not edit applied migrations.
- Do not disable RLS, RBAC, tests, audit, security, financial integrity or validation to pass a gate.
- Do not put tenant-real data, secrets, signed URLs or credentials in source control or evidence.
- Do not claim production-ready, market-ready or GA without the required runtime gates and approvals.
- Do not proceed past a critical/high tenant, security, financial, data-loss, migration, rollback or release blocker.
- Preserve user-owned changes and use controlled patches.

## 7. Resume rule

If a task fails or is interrupted, resume from the latest verified checkpoint using the task ledger, error ledger, change manifest, known issues and handoff. Do not restart the full build unless the repository or database is no longer trustworthy and rollback authority is recorded.

## 8. Final package state

At this checkpoint, Step 0 through Step 17 package files are generated and validated as prompt-package artifacts. Runtime discovery, architecture, implementation, hardening and release/go-live execution remain separate future work.
