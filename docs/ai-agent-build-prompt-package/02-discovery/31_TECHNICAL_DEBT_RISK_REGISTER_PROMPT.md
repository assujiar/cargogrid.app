# Prompt 31 — Technical Debt and Risk Register

**Prompt ID:** `CG-S2-DISC-011`  
**Package document:** `CG-AABPP-DISC-031`  
**Version:** `0.3.0`  
**Parent:** Step 2 — Repository Discovery and Baseline  
**Runtime output:** `docs/discovery/11_TECHNICAL_DEBT_RISK_REGISTER.md`

## Objective

Consolidate and prioritize discovery evidence into one deduplicated technical-debt and implementation-risk register suitable for architecture planning.

## Preconditions

Prompts 21–30 are complete at the same checkpoint. This prompt may update discovery/status/ledger documents only. It must not implement fixes or convert unverified suspicions into facts.

## Required tasks

1. Reconcile findings across architecture, dependencies, database, routes, security, tests, performance, accessibility/UX, and placeholder audits.
2. Separate `TECHNICAL_DEBT`, `IMPLEMENTATION_GAP`, `ACCEPTED_PRODUCT_RISK`, `MISSING_EVIDENCE`, and `EXTERNAL_DEPENDENCY`.
3. Cover architecture, tenant isolation, access control, auditability, data/finance integrity, REST/GraphQL, integrations, jobs, files, UX/accessibility, quality, performance, DevOps, documentation, compliance, recovery, and operations.
4. Deduplicate root causes while preserving all source finding IDs and affected requirements.
5. Score severity, likelihood, exposure, blast radius, dependency criticality, reversibility, detection strength, and remediation complexity using documented scales.
6. Identify critical-path blockers, direct-GA implications, accepted-risk interactions (especially RPD-022/031/034/036/037/038), and risks that require ADR, legal/SME, contract, or runtime evidence.
7. Propose bounded candidate follow-up tasks and verification evidence, not implementation designs or silent product decisions.

## Required output

Write `docs/discovery/11_TECHNICAL_DEBT_RISK_REGISTER.md` with scoring method, deduplicated register, critical-path view, accepted-risk overlay, dependency map, quick containment candidates, architecture inputs, external decisions/evidence needed, and totals by class/severity/status.

Each item must include ID, class, root cause, evidence IDs, requirement/control links, affected assets/tenants, severity, likelihood, exposure, priority, owner, dependency, candidate task, verification, and status.

## Completion gate

Complete only when every critical/high source finding is represented or explicitly rejected with rationale, duplicates are linked, accepted decisions are not reopened, and no fix is executed.
