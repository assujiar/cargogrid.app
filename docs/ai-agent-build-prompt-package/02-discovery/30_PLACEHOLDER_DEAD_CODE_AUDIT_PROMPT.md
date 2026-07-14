# Prompt 30 — Placeholder and Dead-Code Audit

**Prompt ID:** `CG-S2-DISC-010`  
**Package document:** `CG-AABPP-DISC-030`  
**Version:** `0.3.0`  
**Parent:** Step 2 — Repository Discovery and Baseline  
**Runtime output:** `docs/discovery/10_PLACEHOLDER_DEAD_CODE_INVENTORY.md`

## Objective

Find unfinished, misleading, unreachable, duplicated, or obsolete implementation surfaces that could distort discovery or later delivery planning. Do not delete or repair them.

## Preconditions and guardrails

Prompts 21–29 are complete at one checkpoint. Search source, tests, configuration, migrations, scripts, fixtures, and documentation. Generated/vendor/build directories may be summarized but must not inflate findings. Every automated match requires human-context review before classification.

## Required tasks

1. Search for TODO/FIXME/HACK/XXX, “not implemented”, “coming soon”, empty handlers, unconditional success, swallowed errors, placeholder returns, fake identifiers, and hard-coded demo values.
2. Locate mock/in-memory persistence, fixture data, bypass authentication/authorization, permissive tenant filters, disabled scanning, and fake integration responses reachable from production paths.
3. Find dead routes, nonfunctional buttons, orphan modules, unreachable branches, unused exports/dependencies, abandoned migrations, duplicate implementations, and stale feature flags.
4. Inventory skipped/disabled/focused tests, broad exclusions, commented-out code, temporary suppressions, and quality/security rule exceptions.
5. Cross-check route/module and implementation inventories to identify documented-only capabilities or UI without persistence/API behavior.
6. For each candidate record evidence, reachability, consumer, environment, ownership, intended disposition if documented, and confidence.
7. Classify as `CONFIRMED_PLACEHOLDER`, `CONFIRMED_DEAD`, `SUSPECTED`, `INTENTIONAL_STUB`, or `FALSE_POSITIVE`.

## Required output

Write `docs/discovery/10_PLACEHOLDER_DEAD_CODE_INVENTORY.md` with search scope/commands, exclusion rules, reviewed counts, and a finding table containing ID, location, classification, confidence, reachability, affected capability, tenant/security/data impact, severity, evidence, owner/consumer, and follow-up.

## Completion gate

Complete only when false positives are separated, high-risk reachable behavior is highlighted, no source is changed, and every confirmed item has traceable evidence.
