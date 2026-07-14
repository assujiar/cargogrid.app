# Prompt 34 — Step 2 Closure Verification

**Prompt ID:** `CG-S2-DISC-014`  
**Package document:** `CG-AABPP-DISC-034`  
**Version:** `0.3.0`  
**Parent:** Step 2 — Repository Discovery and Baseline  
**Runtime output:** `docs/discovery/14_STEP2_CLOSURE_REPORT.md`

## Objective

Independently verify that repository discovery is complete, internally consistent, code-free, and trustworthy enough to admit Step 3 architecture planning.

## Preconditions

Prompts 21–33 have been executed against one authoritative repository checkpoint. Review all discovery and persistent-context artifacts; rerun only safe read-only checks needed to validate closure.

## Required verification

1. Confirm all 14 required discovery outputs exist and are non-empty: execution index; repository; implementation; toolchain; database; route/module; security; test/quality; performance; accessibility/UX; placeholder/dead-code; debt/risk; strategy decision; evidence index.
2. Confirm repository identity/checkpoint consistency, command/result traceability, redaction, evidence classifications, cross-references, and worktree reconciliation.
3. Confirm no forbidden feature code, migration, dependency, configuration, data, service, deployment, or external-system change occurred.
4. Verify critical tenant, access, audit, finance, file, API, integration, recovery, direct-GA, and Supreme Admin accepted-risk findings are represented.
5. Verify the greenfield/brownfield classification is supported, preserves valuable assets, and does not silently authorize a rewrite.
6. Identify missing or stale artifacts, unsafe/not-run checks, contradictions, unresolved critical blockers, and required resume point.
7. Reconcile persistent context/status/ledger/error/issues/handoff documents with the closure result.

## Closure states

- `RUNTIME_DISCOVERY_VERIFIED`: every mandatory artifact and integrity gate passes; Step 3 architecture planning is eligible.
- `RUNTIME_DISCOVERY_PARTIAL`: evidence is useful but one or more non-critical closure gates remain; Step 3 is blocked unless the Master Prompt explicitly permits a bounded exception.
- `RUNTIME_DISCOVERY_BLOCKED`: checkpoint, safety, critical evidence, or strategy classification is missing/inconsistent; Step 3 is blocked.

Package-generation status such as `STEP_2_PACKAGE_COMPLETE` is not runtime verification.

## Required output

Write `docs/discovery/14_STEP2_CLOSURE_REPORT.md` containing checkpoint, artifact checklist, integrity/forbidden-change checks, critical-control coverage, unresolved findings, closure state, rationale, Step 3 eligibility, exact resume prompt when incomplete, and signed-off evidence references.

## Completion gate and next boundary

Mark `RUNTIME_DISCOVERY_VERIFIED` only when every mandatory gate passes. Otherwise record `PARTIAL` or `BLOCKED` and the exact recovery action. Even after verification, the next eligible runtime work is architecture and execution blueprinting—not feature implementation.

For this prompt-package build, the next package command after all Step 2 prompt files and controls are validated is: `LANJUT STEP 3`.
