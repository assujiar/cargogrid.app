# {{INCIDENT_OR_OPERATIONAL_TASK_NAME}} — Runbook

**Template ID:** `CG-DOCS-RUNBOOK-001`
**Template version:** `0.1.0` (established `CG-S5-PH0-013`, Prompt 92)
**Audience:** Support, DevOps/on-call — see `docs/standards/DOCUMENTATION_STANDARDS.md` §2
**Status:** `{{DRAFT | ACTIVE | SUPERSEDED}}`
**Owner:** `{{ROLE_OR_TEAM}}`
**Since:** Phase `{{PHASE_NUMBER}}`
**Severity class:** `{{SEV_LEVEL}}` (align to `docs/architecture/10_TESTING_WORKSTREAM.md` §8.2's severity-based exit criteria where security-relevant)

> A runbook describes a real, previously-observed or deliberately-rehearsed operational scenario. Do not author a runbook for a hypothetical incident with no rehearsal evidence — mark it `{{NOT_YET_REHEARSED}}` explicitly instead (mirrors `docs/adr/ADR-0008`'s DR-cadence honesty: a policy can be decided before its first real execution, but the execution itself is never assumed).

## 1. Symptom / trigger

How this scenario is detected (alert name, user report pattern, monitoring signal): `{{DETECTION}}`.

## 2. Impact

Who/what is affected, and severity: `{{IMPACT}}`. Tenant-isolation/financial-integrity implications, if any (`AGENTS.md`): `{{IMPLICATIONS_OR_NONE}}`.

## 3. Diagnosis steps

1. `{{STEP}}`
2. `{{STEP}}`

## 4. Resolution steps

1. `{{STEP}}`
2. `{{STEP}}`

Rollback procedure if resolution fails (`docs/architecture/10_TESTING_WORKSTREAM.md` §10.2's stop/rollback thresholds, restated per-scenario, not re-derived): `{{ROLLBACK}}`.

## 5. Communication

Who is notified, when, and via what channel: `{{COMM_PLAN}}`.

## 6. Post-incident

RCA requirement, evidence to capture, rehearsal-vs-real-incident classification: `{{POST_INCIDENT_PROCESS}}`.

## 7. Rehearsal history

| Date | Type (rehearsal/real) | Outcome | Evidence |
|---|---|---|---|
| `{{DATE}}` | `{{TYPE}}` | `{{OUTCOME}}` | `{{LINK}}` |

## 8. Revision history

| Date | Version | Change | Author |
|---|---|---|---|
| `{{DATE}}` | `0.1.0` | Initial | `{{AUTHOR}}` |
