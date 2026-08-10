/**
 * Data classification registry — docs/standards/DATA_CLASSIFICATION_STANDARDS.md
 * §2–§6, CG-S5-PH0-016 (Prompt 95). Sensitivity-level scale and
 * strongest-resolution rule are this checkpoint's own construction from
 * docs/architecture/02_CANONICAL_DATA_FLOW_MAP.md §10's prose defaults
 * (disclosed, §1 of the standards doc); categories and retention mapping are
 * reproduced from that same §10/§11, not re-derived.
 */

export const SENSITIVITY_LEVELS = ["public", "internal", "confidential", "restricted", "credential"] as const;
export type SensitivityLevel = (typeof SENSITIVITY_LEVELS)[number];

const LEVEL_ORDER: Record<SensitivityLevel, number> = {
  public: 0,
  internal: 1,
  confidential: 2,
  restricted: 3,
  credential: 4,
};

/** Total ordering: negative if `a` is weaker than `b`, positive if stronger, 0 if equal. */
export function compareLevel(a: SensitivityLevel, b: SensitivityLevel): number {
  return LEVEL_ORDER[a] - LEVEL_ORDER[b];
}

/** docs/standards/DATA_CLASSIFICATION_STANDARDS.md §2 — Prompt 95 §22's "strongest applicable handling" rule. */
export function strongest(levels: readonly SensitivityLevel[]): SensitivityLevel {
  if (levels.length === 0) {
    throw new Error("strongest: levels must be non-empty");
  }
  return levels.reduce((max, level) => (compareLevel(level, max) > 0 ? level : max));
}

export const CATEGORIES = ["cost_margin", "finance", "payroll", "pii", "security_credential", "support"] as const;
export type Category = (typeof CATEGORIES)[number];

/** docs/standards/DATA_CLASSIFICATION_STANDARDS.md §1's disclosed mapping from 02_*.md §10's 6 field groups. */
export const CATEGORY_DEFAULT_LEVEL: Record<Category, SensitivityLevel> = {
  cost_margin: "confidential",
  pii: "confidential",
  finance: "restricted",
  payroll: "restricted",
  support: "restricted",
  security_credential: "credential",
};

export type RetentionClass = "finance_tax_10y" | "audit_security_7y" | "operational_contract_plus_90d";

/** docs/standards/DATA_CLASSIFICATION_STANDARDS.md §5 (RPD-025, docs/architecture/02_*.md §11). */
export const CATEGORY_RETENTION_CLASS: Record<Category, RetentionClass> = {
  finance: "finance_tax_10y",
  payroll: "finance_tax_10y", // disclosed inference, not an itemized RPD-025 row — see standards doc §5
  security_credential: "audit_security_7y",
  support: "audit_security_7y",
  cost_margin: "operational_contract_plus_90d",
  pii: "operational_contract_plus_90d",
};

export interface HandlingRule {
  readonly visibleByDefault: boolean;
  readonly maskable: boolean;
  readonly exportable: boolean;
  readonly auditRequired: boolean;
}

/** docs/standards/DATA_CLASSIFICATION_STANDARDS.md §4 — the 4 machine-checkable columns of the 8-dimension matrix (the remaining 4 — editability, printability, filterability, API exposure — are role/context-dependent and enforced by the Phase 1 policy engine, not this static table). */
export const HANDLING_MATRIX: Record<SensitivityLevel, HandlingRule> = {
  public: { visibleByDefault: true, maskable: false, exportable: true, auditRequired: false },
  internal: { visibleByDefault: true, maskable: false, exportable: true, auditRequired: false },
  confidential: { visibleByDefault: false, maskable: true, exportable: true, auditRequired: true },
  restricted: { visibleByDefault: false, maskable: true, exportable: true, auditRequired: true },
  credential: { visibleByDefault: false, maskable: true, exportable: false, auditRequired: true },
};

export interface ClassificationEntry {
  readonly id: string;
  readonly category: Category;
  readonly level: SensitivityLevel;
  readonly owner: string;
  readonly description: string;
  /** `"<MODULE>:<action>"` (e.g. `"FIN:View margin"`) when this entry classifies data exposed specifically through one seeded, `protected: true` RBAC permission action — FIN-214 (CG-S9-FIN-025) §7's adoption gate, extended to protected-permission traceability. Omitted for an entry with no single owning protected action. */
  readonly protectedAction?: string;
}

export type RegistryViolationKind = "MISSING_OWNER" | "LEVEL_BELOW_CATEGORY_DEFAULT" | "DUPLICATE_ID";

export interface RegistryViolation {
  readonly id: string;
  readonly kind: RegistryViolationKind;
}

/** docs/standards/DATA_CLASSIFICATION_STANDARDS.md §6 — Prompt 95 §25's validation rules. */
export function validateRegistry(entries: readonly ClassificationEntry[]): RegistryViolation[] {
  const violations: RegistryViolation[] = [];
  const seenIds = new Set<string>();
  for (const entry of entries) {
    if (seenIds.has(entry.id)) {
      violations.push({ id: entry.id, kind: "DUPLICATE_ID" });
    }
    seenIds.add(entry.id);

    if (entry.owner.trim().length === 0) {
      violations.push({ id: entry.id, kind: "MISSING_OWNER" });
    }

    const floor = CATEGORY_DEFAULT_LEVEL[entry.category];
    if (compareLevel(entry.level, floor) < 0) {
      violations.push({ id: entry.id, kind: "LEVEL_BELOW_CATEGORY_DEFAULT" });
    }
  }
  return violations;
}

/**
 * This repository's actual Phase 0 assets, classified — docs/standards/
 * DATA_CLASSIFICATION_STANDARDS.md §6/§7. Extended by each future capability
 * prompt that introduces a new sensitive field/variable, never
 * retroactively invented for a field that does not exist yet.
 */
export const PHASE_0_REGISTRY: readonly ClassificationEntry[] = [
  {
    id: "env:SUPABASE_SERVICE_ROLE_KEY",
    category: "security_credential",
    level: "credential",
    owner: "Platform/Security",
    description: "Supabase service-role key (scripts/env/schema.ts) — server-only, never sent to the browser bundle.",
  },
];

/**
 * Finance domain (FIN-191..213) sensitive `server/contracts/<domain>/` field groups,
 * classified — FIN-214 (Financial Field-Level Security, CG-S9-FIN-025), §7's adoption
 * gate applied retroactively to every Finance capability that shipped a sensitive
 * field before this checkpoint (each was already access-controlled at the point it was
 * built — FIN:View margin deny-outright, masked bank storage — this registry makes
 * that classification explicit and mechanically checkable, not a new control).
 * Field-*group* granularity (docs/standards/DATA_CLASSIFICATION_STANDARDS.md §1's own
 * 6-group model), not one entry per literal database column.
 */
export const FINANCE_REGISTRY: readonly ClassificationEntry[] = [
  {
    id: "fin:job_profitability.financial_figures",
    category: "cost_margin",
    level: "restricted",
    owner: "Finance",
    protectedAction: "FIN:View margin",
    description:
      "revenue_amount/cost_amount/profit_amount/margin_percent on app.finance_job_profitability_facts and its two read RPCs (app.get_finance_job_profitability, app.get_finance_profitability_summary) — deny outright without FIN:View margin (FIN-212); the base table grants authenticated zero direct privilege.",
  },
  {
    id: "fin:cash_bank.account_identifier",
    category: "finance",
    level: "restricted",
    owner: "Finance",
    description: "account_number_last4 on app.finance_bank_accounts — masked at rest to at most 4 characters; the full account number is never stored anywhere in this repository (FIN-211).",
  },
  {
    id: "fin:tax_baseline.tax_identity",
    category: "finance",
    level: "restricted",
    owner: "Finance",
    description: "Tax identity/rule fields (NPWP-shaped tax codes, rule versions) on app.finance_tax_codes/app.finance_tax_rule_versions — FIN:View-gated, tenant-scoped (FIN-195).",
  },
  {
    id: "fin:accounts_receivable.credit_exposure",
    category: "finance",
    level: "restricted",
    owner: "Finance",
    description: "Customer credit exposure/aging totals from app.get_finance_ar_exposure_summary and app.get_finance_aging_summary — FIN:View-gated; internal Finance aggregate only, customer-facing visibility deferred to Step 13 (FIN-196/FIN-210).",
  },
  {
    id: "fin:ledger.posted_amounts",
    category: "finance",
    level: "restricted",
    owner: "Finance",
    description: "Posted subledger/journal line amounts on app.finance_subledger_lines/app.finance_journal_lines and every posting/reversal/adjustment RPC — FIN:View-gated reads, FIN:Edit/Approve-gated posting, period-lock and idempotent-posting invariants apply (FIN-201/203/206/208).",
  },
];

/**
 * Procurement domain (PRC-254, Vendor Banking and Tax Security, CG-S11-PRC-005)
 * sensitive `server/contracts/vendor-financial/` field group, classified. This
 * repository's FIRST at-rest-ENCRYPTED field group (`level: "credential"`, not just
 * `"restricted"` masking) — unlike `fin:cash_bank.account_identifier` above (FIN-211,
 * which never stores the full account number at all), this capability's own
 * `app.vendor_bank_accounts`/`app.vendor_tax_identities` genuinely store the full
 * value, `pgp_sym_encrypt`-encrypted, and decrypt it only through one narrow, MFA-
 * gated, audited reveal RPC per table (see the migration's own header for the full
 * encryption design and its disclosed key-custody boundary).
 */
export const PROCUREMENT_REGISTRY: readonly ClassificationEntry[] = [
  {
    id: "prc:vendor_bank_accounts.account_number",
    category: "finance",
    level: "credential",
    owner: "Procurement",
    protectedAction: "PRC:View personal data",
    description:
      "account_number_encrypted (pgp_sym_encrypt bytea, app.vendor_financial_encryption_key()) + account_number_hash (sha256, duplicate detection only, never decrypted for comparison) on app.vendor_bank_accounts — decrypted only via the PRC:View personal data-gated, MFA-reauth-gated, unconditionally-audited app.reveal_vendor_bank_account_number RPC. account_number_last4 (plain, unencrypted) is the masked-display value every ordinary PRC:View caller sees by default; the encrypted/hash columns are additionally withheld from the authenticated role's own table GRANT (column-restricted, mirrors COM-149).",
  },
  {
    id: "prc:vendor_tax_identities.tax_id",
    category: "finance",
    level: "credential",
    owner: "Procurement",
    protectedAction: "PRC:View personal data",
    description:
      "tax_id_encrypted (pgp_sym_encrypt bytea) + tax_id_hash (sha256, duplicate detection only) on app.vendor_tax_identities — decrypted only via the PRC:View personal data-gated, MFA-reauth-gated, unconditionally-audited app.reveal_vendor_tax_identity_number RPC. tax_id_last4 is the plain masked-display value every ordinary PRC:View caller sees by default. tax_id_type is deliberately free text (RPD-016) — no NPWP-specific statutory format validation is hardcoded here.",
  },
];

/**
 * HRT-274 (Employee Master, CG-S12-HRT-002) — Phase 7's first HRIS registry entries.
 * Every sensitive personal field on app.employees/app.employee_emergency_contacts is
 * masked by app.has_view_personal_data (PLT-114, reused unchanged — HRS:View personal
 * data was already seeded at PLT-111) unless the caller is reading their own linked
 * profile. category 'pii' (not 'payroll' — that category is reserved for the future
 * Payroll capability, Prompt 282; Employee Master carries zero bank/tax/payroll-shaped
 * column). national_id_number is classified one level above the category default
 * (`restricted`, not the 'pii' floor of `confidential`) — a government identity
 * number is more sensitive than an ordinary contact field.
 */
export const HRS_REGISTRY: readonly ClassificationEntry[] = [
  {
    id: "hrs:employees.national_id_number",
    category: "pii",
    level: "restricted",
    owner: "HRIS",
    protectedAction: "HRS:View personal data",
    description:
      "national_id_number on app.employees — a government-issued identity number, masked to null for any reader lacking HRS:View personal data and for anyone other than the employee themself (app.get_employee_profile's own v_is_self branch). Never copied into app.employee_lifecycle_events.metadata, app.audit_logs, or app.list_employees' list projection (list rows carry zero PII columns at all).",
  },
  {
    id: "hrs:employees.date_of_birth_gender",
    category: "pii",
    level: "confidential",
    owner: "HRIS",
    protectedAction: "HRS:View personal data",
    description: "date_of_birth/gender on app.employees — masked identically to national_id_number, own-profile-or-permission-gated.",
  },
  {
    id: "hrs:employees.personal_contact",
    category: "pii",
    level: "confidential",
    owner: "HRIS",
    protectedAction: "HRS:View personal data",
    description:
      "personal_email/personal_phone on app.employees — an employee's own non-work contact channel, distinct from work_email/work_phone (unmasked — a corporate identity field, not personal data). Self-editable via app.request_employee_change/app.decide_employee_change_request (a governed correction-request flow, never a direct self-write).",
  },
  {
    id: "hrs:employees.personal_address",
    category: "pii",
    level: "confidential",
    owner: "HRIS",
    protectedAction: "HRS:View personal data",
    description: "personal_address_street/city/province/postal_code/country on app.employees — masked identically to personal_email/personal_phone, and the same five fields app.request_employee_change's own field_key allow-list covers.",
  },
  {
    id: "hrs:employee_emergency_contacts.phone_email",
    category: "pii",
    level: "confidential",
    owner: "HRIS",
    protectedAction: "HRS:View personal data",
    description:
      "phone/email on app.employee_emergency_contacts — personal data of a named third party (not the employee themself), masked by app.list_employee_emergency_contacts identically to app.vendor_contacts' own email/phone masking (PRC-251) — name/relationship remain visible unmasked, mirroring the vendor-contact precedent exactly.",
  },
  {
    id: "hrs:candidates.national_id_number",
    category: "pii",
    level: "restricted",
    owner: "HRIS",
    protectedAction: "HRS:View personal data",
    description:
      "national_id_number on app.candidates (HRT-276, Recruitment/ATS) — a government-issued identity number, masked to null for any reader lacking HRS:View personal data via app.get_candidate_profile's own server-computed personal_data_masked flag. Never in app.list_candidates/app.export_candidates' own zero-pii projections, and never copied into app.audit_logs (app.candidate_audit_projection is an explicit non-pii jsonb_build_object, never to_jsonb(row)).",
  },
  {
    id: "hrs:candidates.date_of_birth",
    category: "pii",
    level: "confidential",
    owner: "HRIS",
    protectedAction: "HRS:View personal data",
    description: "date_of_birth on app.candidates — masked identically to national_id_number.",
  },
  {
    id: "hrs:candidates.personal_contact",
    category: "pii",
    level: "confidential",
    owner: "HRIS",
    protectedAction: "HRS:View personal data",
    description:
      "email/phone on app.candidates — a candidate's own contact channel, the entire point of contact with a real person before they are anything else in this system. Column-restricted at the grant layer from day one (authenticated has no column-level SELECT on this column at all, PLT-114 pattern) and masked at the RPC layer by app.get_candidate_profile.",
  },
  {
    id: "hrs:candidates.address",
    category: "pii",
    level: "confidential",
    owner: "HRIS",
    protectedAction: "HRS:View personal data",
    description: "address on app.candidates — masked identically to email/phone.",
  },
  {
    id: "hrs:attendance_events.location",
    category: "pii",
    level: "confidential",
    owner: "HRIS",
    protectedAction: "HRS:View personal data",
    description:
      "location on app.attendance_events (HRT-278, Attendance) — a real-time GPS coordinate tied to one employee's clock-in/out moment. Structurally minimized at write time (app._ingest_attendance_event never persists a coordinate unless the resolved policy's own location_enforcement_mode requires evaluating it — decision 4); column-restricted from the plain authenticated grant (service_role only) from this migration's own first grant block, never retrofitted.",
  },
  {
    id: "hrs:attendance_correction_requests.reason",
    category: "pii",
    level: "confidential",
    owner: "HRIS",
    protectedAction: "HRS:View personal data",
    description:
      "reason/decided_reason on app.attendance_correction_requests (HRT-278) — an employee's own stated justification for a missed/incorrect punch, which can incidentally disclose sensitive personal circumstances (medical, family). Column-restricted from authenticated (service_role only); visible to the requester themselves and HRS:View-personal-data holders only, via the owning read RPC's own masking, mirroring app.employees' own personal-field pattern.",
  },
  {
    id: "hrs:attendance_exceptions.waive_reason",
    category: "pii",
    level: "confidential",
    owner: "HRIS",
    protectedAction: "HRS:View personal data",
    description: "waive_reason/resolution_note on app.attendance_exceptions (HRT-278) — masked identically to attendance_correction_requests.reason.",
  },
  {
    id: "hrs:schedule_assignments.cancel_reason",
    category: "pii",
    level: "confidential",
    owner: "HRIS",
    protectedAction: "HRS:View personal data",
    description:
      "cancel_reason on app.schedule_assignments (HRT-279) — the stated reason a shift assignment was cancelled, which can incidentally disclose sensitive personal circumstances (medical, family). Column-restricted from authenticated (service_role only) from this migration's own first grant block, never retrofitted; never projected by any read RPC (structural masking by omission, mirroring app.attendance_correction_requests' own established convention).",
  },
  {
    id: "hrs:schedule_swap_requests.reason",
    category: "pii",
    level: "confidential",
    owner: "HRIS",
    protectedAction: "HRS:View personal data",
    description: "reason/decided_reason on app.schedule_swap_requests (HRT-279) — an employee's own stated justification for requesting a shift swap. Column-restricted and masked identically to app.attendance_correction_requests.reason.",
  },
  {
    id: "hrs:leave_requests.reason",
    category: "pii",
    level: "confidential",
    owner: "HRIS",
    protectedAction: "HRS:View personal data",
    description:
      "reason/destination/decided_reason/cancel_reason on app.leave_requests (HRT-280, Leave/Permit/Business Trip) — an employee's own stated justification for a leave/permit/business-trip request, which can incidentally disclose sensitive personal or medical circumstances. Column-restricted from authenticated (service_role only) from this migration's own first grant block, never retrofitted; masked at the RPC layer (app.get_leave_request_detail/app.list_leave_requests) to self-or-HRS:View-personal-data, mirroring app.attendance_correction_requests.reason exactly.",
  },
  {
    id: "hrs:leave_types.evidence_classification",
    category: "pii",
    level: "confidential",
    owner: "HRIS",
    protectedAction: "HRS:View personal data",
    description:
      "evidence_classification ('personal'/'medical') on app.leave_types (HRT-280) — a domain-owned classification of what KIND of justification a leave type demands, distinct from app.files.classification (PLT-128's own storage-classification scale, set by the uploader before this domain's RPCs ever see the file id). Registered here per this checkpoint's own task instructions to consider a data-classification-registry row for medical/personal leave reason text — the column itself is not masked (it describes policy, not a person), but every leave_requests.reason/evidence_file_id pairing for a 'medical'-classified type inherits the SAME confidential handling as the reason field above.",
  },
  {
    id: "hrs:leave_balance_ledger.reason",
    category: "pii",
    level: "confidential",
    owner: "HRIS",
    protectedAction: "HRS:View personal data",
    description:
      "reason on app.leave_balance_ledger (HRT-280) — an HR adjustment/opening-balance reason that can incidentally disclose sensitive personal circumstances. Column-restricted from authenticated (service_role only); masked identically to app.leave_requests.reason.",
  },
];
