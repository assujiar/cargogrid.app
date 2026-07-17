/**
 * Initial threat model — docs/security/THREAT_MODEL.md, CG-S5-PH0-017
 * (Prompt 96). A typed, validated register rather than a prose-only table,
 * matching this session's established pattern (scripts/data-classification/
 * registry.ts) — "risk ranking is reproducible" (Prompt 96 §25) is a
 * property this file's tests prove, not merely a documentation claim.
 *
 * Likelihood/impact are assessed against the *planned* architecture as if
 * built without its named control — the only way a pre-implementation
 * threat model can be actionable (docs/security/THREAT_MODEL.md §2's
 * methodology note). Nothing here is exploitable today: no application code
 * exists yet (docs/discovery/06_SECURITY_BASELINE.md).
 */

export const STRIDE_CATEGORIES = ["spoofing", "tampering", "repudiation", "information_disclosure", "denial_of_service", "elevation_of_privilege"] as const;
export type StrideCategory = (typeof STRIDE_CATEGORIES)[number];

export const LIKELIHOODS = ["low", "medium", "high"] as const;
export type Likelihood = (typeof LIKELIHOODS)[number];

export const IMPACTS = ["low", "medium", "high", "critical"] as const;
export type Impact = (typeof IMPACTS)[number];

export type RiskRank = "low" | "medium" | "high" | "critical";

/**
 * Explicit lookup table rather than a multiplicative score — a
 * likelihood×impact product would place every "critical impact" threat
 * below "critical" rank unless likelihood is also "high" (verified: max
 * product at likelihood=medium is 2×4=8, which a >=9 threshold would rank
 * only "high"), understating exactly the low-likelihood/catastrophic-impact
 * threats (e.g. THR-011's malware-scan bypass, THR-015's posted-journal
 * tampering) that docs/architecture/10_TESTING_WORKSTREAM.md §5.2/§5.3
 * already rate Critical regardless of likelihood. This table instead lets
 * "critical" impact alone reach "critical" rank once likelihood is at least
 * medium, matching that established severity framing rather than
 * contradicting it (docs/security/THREAT_MODEL.md §3's methodology note).
 */
const RISK_MATRIX: Record<Likelihood, Record<Impact, RiskRank>> = {
  low: { low: "low", medium: "low", high: "medium", critical: "high" },
  medium: { low: "low", medium: "medium", high: "high", critical: "critical" },
  high: { low: "medium", medium: "high", high: "critical", critical: "critical" },
};

/** Reproducible: a pure function of (likelihood, impact) only — same inputs always produce the same rank (Prompt 96 §25). */
export function computeRiskRank(likelihood: Likelihood, impact: Impact): RiskRank {
  return RISK_MATRIX[likelihood][impact];
}

export type ControlStatus = "existing" | "planned_phase1" | "gap_disclosed";

export interface ThreatEntry {
  readonly id: string;
  readonly area: string;
  readonly stride: readonly StrideCategory[];
  readonly description: string;
  readonly likelihood: Likelihood;
  readonly impact: Impact;
  readonly controlStatus: ControlStatus;
  readonly control: string;
  readonly owner: string;
  readonly source: string;
}

/**
 * 25 entries across the 9 areas Prompt 96 §20 task 2 names (tenants, access,
 * admin/support, APIs, jobs, files, integrations, finance/data, operations)
 * plus UI/portal. Every entry maps to an already-catalogued source
 * (06_RLS_RBAC_WORKSTREAM.md §10's 15-item negative-test matrix,
 * 10_TESTING_WORKSTREAM.md §5.2's 18 TI-* scenarios, 08_API_INTEGRATION_
 * WORKSTREAM.md §13's test matrix, this session's own PH0-93/94/95 output,
 * or docs/discovery/06_SECURITY_BASELINE.md's SEC-2026-001) — this document
 * applies the STRIDE lens and risk-ranks what is already catalogued, it does
 * not invent a parallel, competing threat list.
 */
export const THREAT_REGISTER: readonly ThreatEntry[] = [
  {
    id: "THR-001",
    area: "tenants",
    stride: ["information_disclosure", "elevation_of_privilege"],
    description: "Tenant A's authenticated user reads/mutates Tenant B's rows via a missing or misconfigured RLS policy.",
    likelihood: "medium",
    impact: "critical",
    controlStatus: "planned_phase1",
    control: "Shared-schema RLS on every tenant-scoped table (06_RLS_RBAC_WORKSTREAM.md §4); negative test #1 (06_*.md §10) / TI-001 (10_TESTING_WORKSTREAM.md §5.2).",
    owner: "Architecture/Security",
    source: "06_RLS_RBAC_WORKSTREAM.md §10 test #1; 10_TESTING_WORKSTREAM.md §5.2 TI-001",
  },
  {
    id: "THR-002",
    area: "tenants",
    stride: ["tampering"],
    description: "A client-supplied tenant_id field in a request payload is trusted instead of the server-derived session tenant, letting a user address another tenant's record.",
    likelihood: "medium",
    impact: "critical",
    controlStatus: "planned_phase1",
    control: "tenant_id is always server-derived from the authenticated session, never accepted from client payload (06_*.md §4); TI-003.",
    owner: "Architecture/Security",
    source: "10_TESTING_WORKSTREAM.md §5.2 TI-003",
  },
  {
    id: "THR-003",
    area: "access",
    stride: ["elevation_of_privilege"],
    description: "A support engineer's time-bound elevated access grant expires but a cached session continues reading tenant data past expiry.",
    likelihood: "low",
    impact: "critical",
    controlStatus: "planned_phase1",
    control: "Support access is purpose/time-bound, logged, tenant-visible, revocable (AGENTS.md); negative test #5; TI-010.",
    owner: "Architecture/Security",
    source: "06_RLS_RBAC_WORKSTREAM.md §10 test #5; 10_TESTING_WORKSTREAM.md §5.2 TI-010",
  },
  {
    id: "THR-004",
    area: "admin",
    stride: ["repudiation", "tampering"],
    description: "Supreme Admin mutates or deletes a normally-immutable record (journal, audit row) with no audit trail of the change.",
    likelihood: "medium",
    impact: "high",
    controlStatus: "gap_disclosed",
    control: "RPD-022 grants Supreme Admin absolute CRUD as a ratified, disclosed exception — every mutation still produces an audit_logs before/after entry (negative test #9); CargoGrid never claims tamper-proof records (docs/runtime/KNOWN_ISSUES.md §2).",
    owner: "Product/Governance",
    source: "06_RLS_RBAC_WORKSTREAM.md §10 test #9; RPD-022",
  },
  {
    id: "THR-005",
    area: "access",
    stride: ["elevation_of_privilege"],
    description: "A role/permission revocation does not take effect until an already-logged-in session's cache expires, leaving a stale-privilege window.",
    likelihood: "medium",
    impact: "medium",
    controlStatus: "planned_phase1",
    control: "A role/permission change is reflected in the very next request from an already-logged-in session (negative test #12).",
    owner: "Architecture/Security",
    source: "06_RLS_RBAC_WORKSTREAM.md §10 test #12",
  },
  {
    id: "THR-006",
    area: "apis",
    stride: ["elevation_of_privilege"],
    description: "An API key or OAuth token's granted scope exceeds the underlying RBAC permission of the identity it represents, allowing scope-widening abuse.",
    likelihood: "medium",
    impact: "high",
    controlStatus: "planned_phase1",
    control: "API-key/OAuth scope cannot exceed underlying RBAC grant (08_API_INTEGRATION_WORKSTREAM.md §13 Security row).",
    owner: "Backend/Security",
    source: "08_API_INTEGRATION_WORKSTREAM.md §13",
  },
  {
    id: "THR-007",
    area: "apis",
    stride: ["elevation_of_privilege", "information_disclosure"],
    description: "REST and GraphQL surfaces for the same record produce different authorization/masking outcomes, letting a caller pick whichever surface leaks more.",
    likelihood: "medium",
    impact: "medium",
    controlStatus: "planned_phase1",
    control: "REST vs. GraphQL identical authorization/masking outcome for the same actor/record (negative test #15, RPD-033).",
    owner: "Backend/Security",
    source: "06_RLS_RBAC_WORKSTREAM.md §10 test #15",
  },
  {
    id: "THR-008",
    area: "apis",
    stride: ["denial_of_service"],
    description: "A caller bypasses rate limiting on one of the five enforced dimensions (per-IP/per-key/per-tenant/per-endpoint/global) to exhaust backend capacity.",
    likelihood: "medium",
    impact: "medium",
    controlStatus: "planned_phase1",
    control: "Rate limit enforced per all five dimensions (08_API_INTEGRATION_WORKSTREAM.md §6/§13).",
    owner: "Backend/DevOps",
    source: "08_API_INTEGRATION_WORKSTREAM.md §6",
  },
  {
    id: "THR-009",
    area: "jobs",
    stride: ["denial_of_service"],
    description: "A malicious or buggy bulk-trigger enqueues an excessive volume of jobs, starving the queue for legitimate work (job storm).",
    likelihood: "medium",
    impact: "medium",
    controlStatus: "planned_phase1",
    control: "Queue-backlog-age alert (docs/standards/OBSERVABILITY_STANDARDS.md §1, 8 named alerts); job cancellation is cooperative (08_*.md §9/§13).",
    owner: "Backend/DevOps",
    source: "docs/architecture/11_DEVOPS_WORKSTREAM.md §6.1; 08_API_INTEGRATION_WORKSTREAM.md §9",
  },
  {
    id: "THR-010",
    area: "jobs",
    stride: ["elevation_of_privilege"],
    description: "A background job executes with more privilege than the user who triggered it, letting a low-privilege trigger cause a high-privilege side effect.",
    likelihood: "low",
    impact: "high",
    controlStatus: "planned_phase1",
    control: "A job never escalates privilege beyond the triggering user (08_API_INTEGRATION_WORKSTREAM.md §13 Job row, explicit).",
    owner: "Backend/Security",
    source: "08_API_INTEGRATION_WORKSTREAM.md §13",
  },
  {
    id: "THR-011",
    area: "files",
    stride: ["tampering", "information_disclosure"],
    description: "A signed download URL is issued before a file's malware scan completes, letting an infected or not-yet-verified file reach another tenant's user.",
    likelihood: "low",
    impact: "critical",
    controlStatus: "planned_phase1",
    control: "Signed URL never issued while malware_scan_status != 'clean', even to the uploader's own later requests (negative test #13, RPD-032, binding gate).",
    owner: "Backend/Security",
    source: "06_RLS_RBAC_WORKSTREAM.md §10 test #13; 08_API_INTEGRATION_WORKSTREAM.md §10.2",
  },
  {
    id: "THR-012",
    area: "files",
    stride: ["information_disclosure"],
    description: "A tenant document is placed in a public storage bucket or CDN-cached at a shared edge, exposing it to an unauthenticated or cross-tenant fetch.",
    likelihood: "low",
    impact: "critical",
    controlStatus: "planned_phase1",
    control: "No public bucket ever used for tenant documents; tenant document signed URLs never shared-CDN-cached (docs/architecture/11_DEVOPS_WORKSTREAM.md §7).",
    owner: "DevOps/Security",
    source: "docs/architecture/11_DEVOPS_WORKSTREAM.md §7",
  },
  {
    id: "THR-013",
    area: "integrations",
    stride: ["spoofing", "repudiation"],
    description: "An inbound webhook is accepted without verifying its signature/timestamp, letting an attacker forge events from a trusted integration.",
    likelihood: "medium",
    impact: "high",
    controlStatus: "planned_phase1",
    control: "Webhook signature/timestamp-tolerance rejection (08_API_INTEGRATION_WORKSTREAM.md §7.3/§13).",
    owner: "Backend/Security",
    source: "08_API_INTEGRATION_WORKSTREAM.md §7.3",
  },
  {
    id: "THR-014",
    area: "integrations",
    stride: ["information_disclosure", "elevation_of_privilege"],
    description: "A third-party integration credential is scoped broader than its own category needs, so its compromise exposes more than one integration's data.",
    likelihood: "medium",
    impact: "medium",
    controlStatus: "existing",
    control: "Every CI/CD credential, service-role key, and third-party integration credential is scoped to the minimum environment/action set (docs/standards/SECURITY_STANDARDS.md §2, ADR-0010).",
    owner: "DevOps/Security",
    source: "docs/standards/SECURITY_STANDARDS.md §2",
  },
  {
    id: "THR-015",
    area: "finance",
    stride: ["tampering"],
    description: "A posted journal or ledger row is mutated or deleted by a role other than Supreme Admin, breaking financial-integrity guarantees.",
    likelihood: "low",
    impact: "critical",
    controlStatus: "planned_phase1",
    control: "A posted journal/ledger row rejects UPDATE/DELETE from every role except Supreme Admin (negative test #8); append-only ledger policy family (06_*.md §4); FINTEST-022.",
    owner: "Finance/Security",
    source: "06_RLS_RBAC_WORKSTREAM.md §10 test #8; 10_TESTING_WORKSTREAM.md §5.3 FINTEST-022",
  },
  {
    id: "THR-016",
    area: "finance",
    stride: ["repudiation"],
    description: "A Supreme Admin financial-record mutation occurs without the risk being disclosed to the affected tenant/auditor, misrepresenting CargoGrid's integrity claims.",
    likelihood: "low",
    impact: "medium",
    controlStatus: "existing",
    control: "RPD-022's absolute-CRUD exception and 'never claim tamper-proof' rule is disclosed consistently across every product/security document this build has authored (AGENTS.md, docs/standards/SECURITY_STANDARDS.md §6, this document §5) — proven by direct grep, not assumed.",
    owner: "Product/Governance",
    source: "RPD-022; docs/standards/SECURITY_STANDARDS.md §6",
  },
  {
    id: "THR-017",
    area: "finance",
    stride: ["information_disclosure"],
    description: "A user without the view_cost permission accesses vendor cost or job margin fields via a report/export/API view that does not re-apply field-level policy.",
    likelihood: "medium",
    impact: "medium",
    controlStatus: "planned_phase1",
    control: "A user without view_cost cannot access cost fields via API/view (negative test #4); field-level security layer (06_*.md §4).",
    owner: "Backend/Security",
    source: "06_RLS_RBAC_WORKSTREAM.md §10 test #4",
  },
  {
    id: "THR-018",
    area: "operations",
    stride: ["information_disclosure"],
    description: "A known-vulnerable dependency ships undetected because no working automated supply-chain audit gate exists.",
    likelihood: "medium",
    impact: "medium",
    controlStatus: "gap_disclosed",
    control: "pnpm audit is genuinely broken upstream (npm's classic advisory endpoints retired); disclosed as ISS-2026-007, not silently faked; pnpm install --frozen-lockfile remains a real, working determinism control.",
    owner: "DevEx",
    source: "docs/runtime/KNOWN_ISSUES.md ISS-2026-007",
  },
  {
    id: "THR-019",
    area: "operations",
    stride: ["information_disclosure"],
    description: "A credential (API key, private key, service-role secret) is accidentally committed to source control and reaches a public or wide-audience history.",
    likelihood: "low",
    impact: "critical",
    controlStatus: "existing",
    control: "scripts/security/check-secrets.ts scans every tracked file in CI (0 findings, proven this build); GitHub's own push-protection scanner is a second, independent layer (proven for real during PH0-94's authoring — it correctly blocked a secret-shaped test fixture).",
    owner: "DevOps/Security",
    source: "docs/standards/SECURITY_STANDARDS.md §3; docs/runbooks/secret-leak-incident-response.md",
  },
  {
    id: "THR-020",
    area: "operations",
    stride: ["denial_of_service"],
    description: "The observability exporter is unreachable during a real Sev1 condition (e.g. cross-tenant policy test failure), delaying detection.",
    likelihood: "low",
    impact: "high",
    controlStatus: "existing",
    control: "scripts/observability/logger.ts's safe-degrade rule never blocks the underlying request/job, and falls back to local stderr capture (proven under real failure injection); docs/runbooks/observability-exporter-outage.md.",
    owner: "DevOps",
    source: "docs/standards/OBSERVABILITY_STANDARDS.md §8; docs/runbooks/observability-exporter-outage.md",
  },
  {
    id: "THR-021",
    area: "ui",
    stride: ["tampering"],
    description: "Unescaped user-generated content (e.g. a shipment note, ticket comment) renders as executable script in another user's browser (stored XSS).",
    likelihood: "medium",
    impact: "high",
    controlStatus: "planned_phase1",
    control: "Content-Security-Policy header, React's default JSX escaping, no dangerouslySetInnerHTML on untrusted content (docs/standards/SECURITY_STANDARDS.md §4, NOT_RUN — no UI exists).",
    owner: "Frontend/Security",
    source: "docs/standards/SECURITY_STANDARDS.md §4",
  },
  {
    id: "THR-022",
    area: "ui",
    stride: ["spoofing", "tampering"],
    description: "A cookie-authenticated Server Action mutation is triggered from a third-party origin without same-origin/CSRF-token verification.",
    likelihood: "medium",
    impact: "high",
    controlStatus: "planned_phase1",
    control: "Same-origin/CSRF-token verification for cookie-authenticated mutation routes (docs/standards/SECURITY_STANDARDS.md §4, NOT_RUN — no route exists).",
    owner: "Frontend/Security",
    source: "docs/standards/SECURITY_STANDARDS.md §4",
  },
  {
    id: "THR-023",
    area: "operations",
    stride: ["tampering", "denial_of_service"],
    description: "A migration is validated only via clean-rebuild (empty-to-head), never via upgrade-from-a-populated-database, and silently loses data on a real Production upgrade.",
    likelihood: "medium",
    impact: "critical",
    controlStatus: "planned_phase1",
    control: "Every migration slice has both a clean-rebuild test and an upgrade test against synthetic pre-populated data (docs/architecture/10_TESTING_WORKSTREAM.md §7.1, binding); currently NOT_RUN (docs/standards/TESTING_STANDARDS.md §7 — no migration exists).",
    owner: "DB Engineer/QA",
    source: "docs/architecture/10_TESTING_WORKSTREAM.md §7.1",
  },
  {
    id: "THR-024",
    area: "operations",
    stride: ["tampering", "denial_of_service"],
    description: "A backup/restore is never rehearsed, so a real restore silently succeeds with files and database rows out of sync (an incomplete restore accepted as complete).",
    likelihood: "medium",
    impact: "critical",
    controlStatus: "planned_phase1",
    control: "Restore validation requires both storage-object and OLTP-metadata restore to succeed together (docs/architecture/11_DEVOPS_WORKSTREAM.md §7/§8.2); currently NOT_RUN — no backup exists yet.",
    owner: "DevOps",
    source: "docs/architecture/11_DEVOPS_WORKSTREAM.md §8.2",
  },
  {
    id: "THR-025",
    area: "admin",
    stride: ["elevation_of_privilege"],
    description: "A normal authenticated user directly invokes a service-role-only database function or bypasses RLS via a misconfigured server-side client.",
    likelihood: "low",
    impact: "critical",
    controlStatus: "planned_phase1",
    control: "Service-role function cannot be called by a normal user (negative test #6); service-role key never reaches the browser, never used to bypass correct RLS design (AGENTS.md).",
    owner: "Backend/Security",
    source: "06_RLS_RBAC_WORKSTREAM.md §10 test #6",
  },
] as const;

export type RegistryViolationKind = "DUPLICATE_ID" | "MISSING_OWNER" | "MISSING_CONTROL" | "EMPTY_STRIDE" | "INVALID_STRIDE_CATEGORY" | "UNOWNED_CRITICAL_WITH_NO_CONTROL";

export interface ThreatRegisterViolation {
  readonly id: string;
  readonly kind: RegistryViolationKind;
}

/** Prompt 96 §25's validation rules, §23's exception flow ("critical unowned path ... blocks entry"). */
export function validateThreatRegister(entries: readonly ThreatEntry[]): ThreatRegisterViolation[] {
  const violations: ThreatRegisterViolation[] = [];
  const seenIds = new Set<string>();

  for (const entry of entries) {
    if (seenIds.has(entry.id)) {
      violations.push({ id: entry.id, kind: "DUPLICATE_ID" });
    }
    seenIds.add(entry.id);

    if (entry.owner.trim().length === 0) {
      violations.push({ id: entry.id, kind: "MISSING_OWNER" });
    }
    if (entry.control.trim().length === 0) {
      violations.push({ id: entry.id, kind: "MISSING_CONTROL" });
    }
    if (entry.stride.length === 0) {
      violations.push({ id: entry.id, kind: "EMPTY_STRIDE" });
    }
    for (const category of entry.stride) {
      if (!STRIDE_CATEGORIES.includes(category)) {
        violations.push({ id: entry.id, kind: "INVALID_STRIDE_CATEGORY" });
      }
    }

    const rank = computeRiskRank(entry.likelihood, entry.impact);
    const hasOwnerAndControl = entry.owner.trim().length > 0 && entry.control.trim().length > 0;
    if (rank === "critical" && !hasOwnerAndControl) {
      violations.push({ id: entry.id, kind: "UNOWNED_CRITICAL_WITH_NO_CONTROL" });
    }
  }

  return violations;
}

function main(): void {
  const violations = validateThreatRegister(THREAT_REGISTER);
  if (violations.length > 0) {
    for (const v of violations) {
      console.error(`✖ ${v.id} [${v.kind}]`);
    }
    console.error(`\n${violations.length} threat-register issue(s) — see docs/security/THREAT_MODEL.md.`);
    process.exit(1);
  }

  const rankCounts: Record<RiskRank, number> = { low: 0, medium: 0, high: 0, critical: 0 };
  for (const entry of THREAT_REGISTER) {
    rankCounts[computeRiskRank(entry.likelihood, entry.impact)]++;
  }
  console.log(`✔ threat register valid — ${THREAT_REGISTER.length} entries (critical=${rankCounts.critical}, high=${rankCounts.high}, medium=${rankCounts.medium}, low=${rankCounts.low}).`);
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main();
}
