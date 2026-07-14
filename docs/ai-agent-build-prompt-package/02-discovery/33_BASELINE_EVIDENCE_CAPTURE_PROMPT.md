# Prompt 33 — Baseline Evidence Capture

**Prompt ID:** `CG-S2-DISC-013`  
**Package document:** `CG-AABPP-DISC-033`  
**Version:** `0.3.0`  
**Parent:** Step 2 — Repository Discovery and Baseline  
**Runtime outputs:** `docs/discovery/00_EXECUTION_INDEX.md`, `docs/discovery/13_BASELINE_EVIDENCE_INDEX.md`

## Objective

Reconcile all Step 2 outputs into a durable, redacted, checkpoint-bound evidence set that another agent can independently audit and resume.

## Preconditions and guardrails

Prompts 21–32 are complete. Evidence capture may write discovery docs and Step 1 persistent context/status/ledger/error/issues/handoff documents only. Do not modify product source, tests, migrations, dependencies, configuration, data, or generated application artifacts.

## Required tasks

1. Reconfirm repository identity, branch, commit, worktree, workspace/package manager, environment class, and execution window.
2. Verify every discovery output exists, is non-empty, cites the same checkpoint, and distinguishes observed, executed, inferred, and unavailable evidence.
3. Assign stable evidence IDs; index source locations, redacted commands, exit codes, durations, result artifacts, checksums where useful, environment, limitations, and related findings.
4. Redact secrets, credentials, tokens, personal data, sensitive business data, signed URLs, and internal endpoints while preserving audit value.
5. Detect stale evidence, checkpoint drift, contradictory counts/classifications, unexplained worktree changes, missing raw results, and broken cross-references.
6. Create an execution index showing order, prerequisite, status, output, checkpoint, and resume instruction for every Step 2 prompt.
7. Update persistent context, build status, task ledger, error ledger, known issues, change manifest, decision log, and handoff only where evidence requires it.
8. Do not declare runtime discovery verified; that decision belongs to Prompt 34.

## Required outputs

`docs/discovery/00_EXECUTION_INDEX.md` must contain checkpoint, execution sequence, prompt status, output paths, command/result references, deviations, and resume pointer.

`docs/discovery/13_BASELINE_EVIDENCE_INDEX.md` must contain evidence schema, indexed evidence, checksum/checkpoint information, redaction record, limitations, contradictions, missing evidence, stale-evidence rules, and cross-reference health.

## Completion gate

Complete only when all Step 2 evidence is indexable from a fresh context, sensitive values are absent, contradictions are resolved or blocked explicitly, and persistent records reconcile with the unchanged product worktree.
