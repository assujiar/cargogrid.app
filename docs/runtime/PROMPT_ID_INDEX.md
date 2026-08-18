# Prompt/Task ID Index

**Purpose:** one lookup table mapping every build-prompt number in
`docs/ai-agent-build-prompt-package/` to its canonical task ID, so an agent or
orchestrator can resolve an ID without scanning 430 prompt files.

**Status source of truth:** this file is a *derived index*, not a status ledger.
Per-task status lives in `docs/runtime/TASK_LEDGER.md` and each phase's own
execution index; current-phase state lives in
`docs/runtime/CARGOGRID_BUILD_STATUS.md`. Phase-level status shown in the
headings below is a convenience summary only — when it disagrees with
`TASK_LEDGER.md`, `TASK_LEDGER.md` wins.

## 1. ID format

```
CG-S<step>-<CODE>-<sequence>
```

The step number is **not** the phase number — Phase 0 is Step 5, Phase 1 is
Step 6, and so on. Sequence restarts at `001` in every phase.

| Phase | Code | ID range | Prompt range | Sequence = prompt − |
|---:|---|---|---|---:|
| 0 | `PH0` | `CG-S5-PH0-001..023` | 80–102 | 79 |
| 1 | `PLT` | `CG-S6-PLT-001..037` | 104–140 | 103 |
| 2 | `COM` | `CG-S7-COM-001..024` | 142–165 | 141 |
| 3 | `OPS` | `CG-S8-OPS-001..022` | 167–188 | 166 |
| 4 | `FIN` | `CG-S9-FIN-001..029` | 190–218 | 189 |
| 5 | `ATW` | `CG-S10-ATW-001..029` | 220–248 | 219 |
| 6 | `PRC` | `CG-S11-PRC-001..022` | 250–271 | 249 |
| 7 | `HRT` | `CG-S12-HRT-001..025` | 273–297 | 272 |
| 8 | `CPL` | `CG-S13-CPL-001..029` | 299–327 | 298 |
| 9 | `IAE` | `CG-S14-IAE-001..039` | 329–367 | 328 |
| 15 | `HDN` | `CG-S15-HDN-001..021` | 369–389 | 368 |
| 16 | `RGL` | `CG-S16-RGL-001..022` | 391–412 | 390 |
| — | `FPV` | `CG-S17-FPV-001..017` | 414–430 | 413 |

Each subtrahend is that phase's own README prompt number (the file immediately
preceding its kickoff prompt). The gaps in the prompt sequence — 103, 141, 166,
189, 219, 249, 272, 298, 328, 368, 390, 413 — are those README files, not
missing prompts. Prompts 1–79 are Steps 1–4 (governance, discovery,
architecture) and precede Phase 0; they are outside this index.

## 2. The arithmetic is a convenience, not a contract

**A task ID is not always derivable from a prompt number.** Phase 5 is the
worked example: the package ships 29 `ATW` prompts, but the phase's real WBS has
**39 rows**, because execution found two genuine package-level gaps and one
oversized prompt:

| Kind | Rows | Why |
|---|---:|---|
| Package prompts | 29 | `ATW-001..029`, prompts 220–248 |
| Inserted tasks | +2 | `ATW-011A` (Item/SKU and UOM Master), `ATW-016A` (WMS Outbound Order) — **no source prompt number exists**; both resolve circular dependencies the package itself did not (`ISS-2026-011`, `ADR-0019`) |
| Decomposition | +8 | `ATW-007` (prompt 226) was too large to execute atomically and became nine children, `ATW-226A`..`ATW-226I` |

29 + 2 + 8 = 39.

Consequences for anything that maps agents or work items to IDs:

- Do **not** derive a task ID statically from a prompt number and assume it is
  the unit of work. Read the phase's execution index instead.
- Inserted-task IDs (`NNNA` suffix) and decomposition children (`NNNx` suffix)
  are allocated **during** execution, when a dependency gap is found. In any
  concurrent execution model, that allocation must be owned by a single
  coordinator — two agents independently deciding to insert a task will collide
  on the same suffix, and the collision is silent (different files, no git
  conflict).
- The same applies to migration filenames, which are timestamp-ordered: see
  `docs/git/GIT_STRATEGY.md` §7 and `ISS-2026-002` for why this repository
  enforces single-writer discipline, and `ERR-2026-001`/`002`/`003` in
  `docs/runtime/ERROR_LEDGER.md` for what happened the five times it was not
  enforced.

## 3. Index

### Phase 0 — Discovery and Foundation (`CG-S5-PH0-…`) — `PHASE_0_VERIFIED`, 23/23

| Prompt | Task ID | Capability |
|---:|---|---|
| 80 | `CG-S5-PH0-001` | Phase 0 WBS and Runtime Kickoff |
| 81 | `CG-S5-PH0-002` | Source Alignment and Context Bootstrap |
| 82 | `CG-S5-PH0-003` | Requirement Traceability Baseline |
| 83 | `CG-S5-PH0-004` | Repository Audit Adoption and Gap Closure |
| 84 | `CG-S5-PH0-005` | ADR Baseline and Decision Governance |
| 85 | `CG-S5-PH0-006` | Development Environment Foundation |
| 86 | `CG-S5-PH0-007` | Environment Validation Foundation |
| 87 | `CG-S5-PH0-008` | Git Strategy Foundation |
| 88 | `CG-S5-PH0-009` | CI/CD Baseline |
| 89 | `CG-S5-PH0-010` | Coding Standards and Architecture Enforcement |
| 90 | `CG-S5-PH0-011` | Design System Foundation |
| 91 | `CG-S5-PH0-012` | Testing Foundation |
| 92 | `CG-S5-PH0-013` | Documentation Foundation |
| 93 | `CG-S5-PH0-014` | Observability Baseline |
| 94 | `CG-S5-PH0-015` | Security Baseline Controls |
| 95 | `CG-S5-PH0-016` | Data Classification Foundation |
| 96 | `CG-S5-PH0-017` | Initial Threat Model |
| 97 | `CG-S5-PH0-018` | Product Analytics Baseline |
| 98 | `CG-S5-PH0-019` | Feature Flag Foundation |
| 99 | `CG-S5-PH0-020` | Phase 0 Integrated Verification |
| 100 | `CG-S5-PH0-021` | Phase 0 Hardening |
| 101 | `CG-S5-PH0-022` | Phase 0 Documentation and Handoff |
| 102 | `CG-S5-PH0-023` | Phase 0 Closure Verification |

### Phase 1 — Platform Core (`CG-S6-PLT-…`) — `PHASE_1_VERIFIED`, 37/37

| Prompt | Task ID | Capability |
|---:|---|---|
| 104 | `CG-S6-PLT-001` | Platform Core WBS and Runtime Kickoff |
| 105 | `CG-S6-PLT-002` | Tenant Provisioning and Lifecycle |
| 106 | `CG-S6-PLT-003` | Subscription, Module and Feature Entitlement |
| 107 | `CG-S6-PLT-004` | Supabase Auth Integration |
| 108 | `CG-S6-PLT-005` | Four-Layer Identity and Access Context |
| 109 | `CG-S6-PLT-006` | Organization and Operational Hierarchy |
| 110 | `CG-S6-PLT-007` | User Lifecycle |
| 111 | `CG-S6-PLT-008` | Role and Permission Builder |
| 112 | `CG-S6-PLT-009` | RBAC Enforcement |
| 113 | `CG-S6-PLT-010` | RLS Tenant Policy Foundation |
| 114 | `CG-S6-PLT-011` | Field-Level and Record-Level Access |
| 115 | `CG-S6-PLT-012` | Support Access and Impersonation Control |
| 116 | `CG-S6-PLT-013` | Audit Trail Foundation |
| 117 | `CG-S6-PLT-014` | White-Label Foundation |
| 118 | `CG-S6-PLT-015` | Custom Domain |
| 119 | `CG-S6-PLT-016` | Localization |
| 120 | `CG-S6-PLT-017` | Master Data Foundation |
| 121 | `CG-S6-PLT-018` | Configuration Engine |
| 122 | `CG-S6-PLT-019` | Workflow Engine |
| 123 | `CG-S6-PLT-020` | Approval Engine |
| 124 | `CG-S6-PLT-021` | Status Engine |
| 125 | `CG-S6-PLT-022` | Numbering Engine |
| 126 | `CG-S6-PLT-023` | Form and Custom Field Builder |
| 127 | `CG-S6-PLT-024` | Notification Engine |
| 128 | `CG-S6-PLT-025` | Document and File Engine |
| 129 | `CG-S6-PLT-026` | API Key and Webhook Primitives |
| 130 | `CG-S6-PLT-027` | REST and GraphQL Platform API Foundation |
| 131 | `CG-S6-PLT-028` | Import/Export Job Framework |
| 132 | `CG-S6-PLT-029` | Background Job Framework |
| 133 | `CG-S6-PLT-030` | Feature Flags |
| 134 | `CG-S6-PLT-031` | PostGIS and Spatial Foundation |
| 135 | `CG-S6-PLT-032` | Tenant Admin Portal |
| 136 | `CG-S6-PLT-033` | Supreme Admin Portal |
| 137 | `CG-S6-PLT-034` | Platform Core Integrated Verification |
| 138 | `CG-S6-PLT-035` | Platform Core Tenant and Security Hardening |
| 139 | `CG-S6-PLT-036` | Platform Core Documentation and Handoff |
| 140 | `CG-S6-PLT-037` | Platform Core Closure Verification |

### Phase 2 — Commercial (`CG-S7-COM-…`) — `PHASE_2_VERIFIED`, 24/24

| Prompt | Task ID | Capability |
|---:|---|---|
| 142 | `CG-S7-COM-001` | Commercial WBS and Runtime Kickoff |
| 143 | `CG-S7-COM-002` | Lead Management |
| 144 | `CG-S7-COM-003` | Prospect Lifecycle |
| 145 | `CG-S7-COM-004` | Contact and Activity Management |
| 146 | `CG-S7-COM-005` | CRM Sales Plan and Pipeline |
| 147 | `CG-S7-COM-006` | Opportunity Management |
| 148 | `CG-S7-COM-007` | RFQ and Costing Request |
| 149 | `CG-S7-COM-008` | Rate and Cost Lookup |
| 150 | `CG-S7-COM-009` | Margin Calculation |
| 151 | `CG-S7-COM-010` | Quotation Builder |
| 152 | `CG-S7-COM-011` | Quotation Versioning |
| 153 | `CG-S7-COM-012` | Quotation Approval |
| 154 | `CG-S7-COM-013` | Customer Acceptance |
| 155 | `CG-S7-COM-014` | Customer and Account Conversion |
| 156 | `CG-S7-COM-015` | Contract and Customer Pricing |
| 157 | `CG-S7-COM-016` | Credit and Commercial Control |
| 158 | `CG-S7-COM-017` | Commercial Dashboard |
| 159 | `CG-S7-COM-018` | Commercial Reports |
| 160 | `CG-S7-COM-019` | Commercial Lineage into Job Order |
| 161 | `CG-S7-COM-020` | Commercial No-Reentry Enforcement |
| 162 | `CG-S7-COM-021` | Commercial Integrated Verification |
| 163 | `CG-S7-COM-022` | Commercial Tenant, Security, Financial and Data Hardening |
| 164 | `CG-S7-COM-023` | Commercial Documentation and Handoff |
| 165 | `CG-S7-COM-024` | Commercial Closure Verification |

### Phase 3 — Operations (`CG-S8-OPS-…`) — `PHASE_3_VERIFIED`, 22/22

| Prompt | Task ID | Capability |
|---:|---|---|
| 167 | `CG-S8-OPS-001` | Operations WBS and Runtime Kickoff |
| 168 | `CG-S8-OPS-002` | Job Order |
| 169 | `CG-S8-OPS-003` | Shipment Order |
| 170 | `CG-S8-OPS-004` | Shipment Lifecycle |
| 171 | `CG-S8-OPS-005` | Land, Air and Sea Baseline |
| 172 | `CG-S8-OPS-006` | Resource and Vendor Assignment |
| 173 | `CG-S8-OPS-007` | Milestone Management |
| 174 | `CG-S8-OPS-008` | Exception and Escalation |
| 175 | `CG-S8-OPS-009` | Basic Dispatch |
| 176 | `CG-S8-OPS-010` | Document Requirement |
| 177 | `CG-S8-OPS-011` | ePOD Capture and Review |
| 178 | `CG-S8-OPS-012` | Actual Cost |
| 179 | `CG-S8-OPS-013` | Basic Job Profitability |
| 180 | `CG-S8-OPS-014` | Basic Public and Customer Tracking |
| 181 | `CG-S8-OPS-015` | Billing Readiness |
| 182 | `CG-S8-OPS-016` | Operations Dashboard |
| 183 | `CG-S8-OPS-017` | Operations Reports |
| 184 | `CG-S8-OPS-018` | Operations Transaction Lineage |
| 185 | `CG-S8-OPS-019` | Operations Integrated Verification |
| 186 | `CG-S8-OPS-020` | Operations Tenant, Security, Financial and Data Hardening |
| 187 | `CG-S8-OPS-021` | Operations Documentation and Handoff |
| 188 | `CG-S8-OPS-022` | Operations Closure Verification |

### Phase 4 — Finance (`CG-S9-FIN-…`) — `PHASE_4_VERIFIED`, 29/29

| Prompt | Task ID | Capability |
|---:|---|---|
| 190 | `CG-S9-FIN-001` | Finance WBS and Runtime Kickoff |
| 191 | `CG-S9-FIN-002` | Finance Configuration |
| 192 | `CG-S9-FIN-003` | Chart of Accounts |
| 193 | `CG-S9-FIN-004` | Fiscal Period |
| 194 | `CG-S9-FIN-005` | Currency and Exchange Rate |
| 195 | `CG-S9-FIN-006` | Tax Baseline |
| 196 | `CG-S9-FIN-007` | Accounts Receivable |
| 197 | `CG-S9-FIN-008` | Invoice |
| 198 | `CG-S9-FIN-009` | Receipt and Payment Allocation |
| 199 | `CG-S9-FIN-010` | Accounts Payable |
| 200 | `CG-S9-FIN-011` | Vendor Bill |
| 201 | `CG-S9-FIN-012` | Settlement |
| 202 | `CG-S9-FIN-013` | Subledger |
| 203 | `CG-S9-FIN-014` | Double-Entry Journal |
| 204 | `CG-S9-FIN-015` | Posted-Journal Integrity |
| 205 | `CG-S9-FIN-016` | Draft versus Posted State |
| 206 | `CG-S9-FIN-017` | Reversal and Adjustment |
| 207 | `CG-S9-FIN-018` | Period Lock |
| 208 | `CG-S9-FIN-019` | Idempotent Posting |
| 209 | `CG-S9-FIN-020` | Reconciliation |
| 210 | `CG-S9-FIN-021` | Aging |
| 211 | `CG-S9-FIN-022` | Cash and Bank |
| 212 | `CG-S9-FIN-023` | Job, Customer and Service Profitability |
| 213 | `CG-S9-FIN-024` | Finance Dashboard and Reports |
| 214 | `CG-S9-FIN-025` | Financial Field-Level Security |
| 215 | `CG-S9-FIN-026` | Finance Integrated Verification |
| 216 | `CG-S9-FIN-027` | Finance Integrity and Security Hardening |
| 217 | `CG-S9-FIN-028` | Finance Documentation and Handoff |
| 218 | `CG-S9-FIN-029` | Finance Closure Verification |

### Phase 5 — Advanced TMS/WMS (`CG-S10-ATW-…`) — `PHASE_5_IN_PROGRESS`, 29/39 WBS rows

| Prompt | Task ID | Capability |
|---:|---|---|
| 220 | `CG-S10-ATW-001` | Advanced TMS/WMS WBS and Runtime Kickoff |
| 221 | `CG-S10-ATW-002` | Multi-Leg and Multimodal Shipment |
| 222 | `CG-S10-ATW-003` | Advanced Dispatch Board with Tracking Health |
| 223 | `CG-S10-ATW-004` | Fleet, Vehicle, Driver, Device and SIM Operational Baseline |
| 224 | `CG-S10-ATW-005` | Route and Load Planning Using Canonical Position |
| 225 | `CG-S10-ATW-006` | First-, Middle-, and Last-Mile Orchestration with Tracking Policy |
| 226 | `CG-S10-ATW-007` | Multi-Source GPS and Telematics Integration |
| 227 | `CG-S10-ATW-008` | Capacity, Utilization and Tracking Coverage |
| 228 | `CG-S10-ATW-009` | Advanced Milestone and Exception with Multi-Source Telemetry |
| 229 | `CG-S10-ATW-010` | Warehouse and Zone |
| 230 | `CG-S10-ATW-011` | Bin and Racking |
| 231 | `CG-S10-ATW-012` | WMS Inbound |
| 232 | `CG-S10-ATW-013` | WMS Receiving |
| 233 | `CG-S10-ATW-014` | WMS Putaway |
| 234 | `CG-S10-ATW-015` | Inventory Ledger |
| 235 | `CG-S10-ATW-016` | Lot, Batch, Serial and Expiry |
| 236 | `CG-S10-ATW-017` | WMS Picking |
| 237 | `CG-S10-ATW-018` | WMS Packing |
| 238 | `CG-S10-ATW-019` | WMS Outbound |
| 239 | `CG-S10-ATW-020` | Cycle Count and Inventory Adjustment |
| 240 | `CG-S10-ATW-021` | Label and Barcode Operations |
| 241 | `CG-S10-ATW-022` | Warehouse Billing Events |
| 242 | `CG-S10-ATW-023` | Customer Inventory Access Contract |
| 243 | `CG-S10-ATW-024` | High-Volume TMS/WMS and Multi-Source Telemetry Controls |
| 244 | `CG-S10-ATW-025` | Advanced Claim and Incident Operations |
| 245 | `CG-S10-ATW-026` | Advanced TMS/WMS Integrated Verification |
| 246 | `CG-S10-ATW-027` | Advanced TMS/WMS Integrity and Security Hardening |
| 247 | `CG-S10-ATW-028` | Advanced TMS/WMS Documentation and Handoff |
| 248 | `CG-S10-ATW-029` | Advanced TMS/WMS Closure Verification |

### Phase 6 — Procurement and Vendor (`CG-S11-PRC-…`) — `NOT_STARTED`

| Prompt | Task ID | Capability |
|---:|---|---|
| 250 | `CG-S11-PRC-001` | Procurement/Vendor WBS and Runtime Kickoff |
| 251 | `CG-S11-PRC-002` | Vendor Registration and Onboarding |
| 252 | `CG-S11-PRC-003` | Vendor Assessment |
| 253 | `CG-S11-PRC-004` | Compliance and Document Expiry |
| 254 | `CG-S11-PRC-005` | Vendor Banking and Tax Security |
| 255 | `CG-S11-PRC-006` | Vendor Rate and Pricelist |
| 256 | `CG-S11-PRC-007` | Sourcing |
| 257 | `CG-S11-PRC-008` | Procurement RFQ |
| 258 | `CG-S11-PRC-009` | Vendor Comparison |
| 259 | `CG-S11-PRC-010` | Procurement Approval |
| 260 | `CG-S11-PRC-011` | Purchase Order |
| 261 | `CG-S11-PRC-012` | Vendor Contract |
| 262 | `CG-S11-PRC-013` | Vendor Capacity and Availability |
| 263 | `CG-S11-PRC-014` | Vendor Assignment |
| 264 | `CG-S11-PRC-015` | Vendor Performance |
| 265 | `CG-S11-PRC-016` | Vendor Invoice Matching |
| 266 | `CG-S11-PRC-017` | Procurement Dashboard and Reports |
| 267 | `CG-S11-PRC-018` | Optional Vendor Portal |
| 268 | `CG-S11-PRC-019` | Procurement/Vendor Integrated Verification |
| 269 | `CG-S11-PRC-020` | Procurement/Vendor Integrity, Security and Financial Hardening |
| 270 | `CG-S11-PRC-021` | Procurement/Vendor Documentation and Handoff |
| 271 | `CG-S11-PRC-022` | Procurement/Vendor Closure Verification |

### Phase 7 — HRIS and Ticketing (`CG-S12-HRT-…`) — `NOT_STARTED`

| Prompt | Task ID | Capability |
|---:|---|---|
| 273 | `CG-S12-HRT-001` | HRIS and Ticketing WBS Runtime Kickoff |
| 274 | `CG-S12-HRT-002` | Employee Master |
| 275 | `CG-S12-HRT-003` | Organization and Position Linkage |
| 276 | `CG-S12-HRT-004` | Recruitment, Job Portal and ATS |
| 277 | `CG-S12-HRT-005` | Onboarding and Offboarding |
| 278 | `CG-S12-HRT-006` | Attendance |
| 279 | `CG-S12-HRT-007` | Shift, Roster and Scheduling |
| 280 | `CG-S12-HRT-008` | Leave, Permit and Business Trip |
| 281 | `CG-S12-HRT-009` | Overtime and Timesheet |
| 282 | `CG-S12-HRT-010` | Payroll Foundation, Benefit and Reimbursement |
| 283 | `CG-S12-HRT-011` | KPI and Performance |
| 284 | `CG-S12-HRT-012` | Training and Talent |
| 285 | `CG-S12-HRT-013` | Employee and Manager Self-Service |
| 286 | `CG-S12-HRT-014` | Internal and Interdepartmental Ticket |
| 287 | `CG-S12-HRT-015` | Customer-to-Tenant Ticket |
| 288 | `CG-S12-HRT-016` | Tenant-to-CargoGrid Helpdesk |
| 289 | `CG-S12-HRT-017` | Ticket SLA and Knowledge Base |
| 290 | `CG-S12-HRT-018` | Ticket Assignment |
| 291 | `CG-S12-HRT-019` | Ticket Escalation |
| 292 | `CG-S12-HRT-020` | Typed Ticket-Linked Records |
| 293 | `CG-S12-HRT-021` | Sensitive Personal and Payroll Data Controls |
| 294 | `CG-S12-HRT-022` | HRIS and Ticketing Integrated Verification |
| 295 | `CG-S12-HRT-023` | HRIS and Ticketing Privacy, Integrity and Service Hardening |
| 296 | `CG-S12-HRT-024` | HRIS and Ticketing Documentation and Handoff |
| 297 | `CG-S12-HRT-025` | HRIS and Ticketing Closure Verification |

### Phase 8 — Customer Portal and Loyalty (`CG-S13-CPL-…`) — `NOT_STARTED`

| Prompt | Task ID | Capability |
|---:|---|---|
| 299 | `CG-S13-CPL-001` | Customer Portal and Loyalty WBS Runtime Kickoff |
| 300 | `CG-S13-CPL-002` | Customer User Scope |
| 301 | `CG-S13-CPL-003` | Customer Portal Dashboard |
| 302 | `CG-S13-CPL-004` | Request Quotation |
| 303 | `CG-S13-CPL-005` | Booking |
| 304 | `CG-S13-CPL-006` | Shipment Order |
| 305 | `CG-S13-CPL-007` | Customer Portal Tracking from Canonical Multi-Source Projection |
| 306 | `CG-S13-CPL-008` | Customer Shipment Monitoring and Tracking-Health Alerts |
| 307 | `CG-S13-CPL-009` | ePOD Access |
| 308 | `CG-S13-CPL-010` | Document Center |
| 309 | `CG-S13-CPL-011` | Warehouse Inventory Visibility |
| 310 | `CG-S13-CPL-012` | Warehouse Order and Fulfillment Visibility |
| 311 | `CG-S13-CPL-013` | Invoice and Billing Visibility |
| 312 | `CG-S13-CPL-014` | Payment Visibility |
| 313 | `CG-S13-CPL-015` | Complaint and Ticket |
| 314 | `CG-S13-CPL-016` | Customer Profile |
| 315 | `CG-S13-CPL-017` | Customer User Management |
| 316 | `CG-S13-CPL-018` | Loyalty Program and Earning |
| 317 | `CG-S13-CPL-019` | Membership Tier |
| 318 | `CG-S13-CPL-020` | Points Ledger |
| 319 | `CG-S13-CPL-021` | Cashback Discount Voucher |
| 320 | `CG-S13-CPL-022` | Reward Catalogue |
| 321 | `CG-S13-CPL-023` | Redemption Approval and Fulfillment |
| 322 | `CG-S13-CPL-024` | Expiry and Fraud Prevention |
| 323 | `CG-S13-CPL-025` | Liability Reconciliation Analytics |
| 324 | `CG-S13-CPL-026` | Customer Portal and Loyalty Integrated Verification |
| 325 | `CG-S13-CPL-027` | Customer Portal and Loyalty Privacy Integrity Hardening |
| 326 | `CG-S13-CPL-028` | Customer Portal and Loyalty Documentation Handoff |
| 327 | `CG-S13-CPL-029` | Customer Portal and Loyalty Closure Verification |

### Phase 9 — Intelligence, Automation and Enterprise (`CG-S14-IAE-…`) — `NOT_STARTED`

| Prompt | Task ID | Capability |
|---:|---|---|
| 329 | `CG-S14-IAE-001` | Intelligence, Automation and Enterprise WBS Runtime Kickoff |
| 330 | `CG-S14-IAE-002` | Reporting Engine |
| 331 | `CG-S14-IAE-003` | Dashboard Builder |
| 332 | `CG-S14-IAE-004` | Saved View and Configurable Report |
| 333 | `CG-S14-IAE-005` | Analytics and Materialized Views |
| 334 | `CG-S14-IAE-006` | Scheduled Reports |
| 335 | `CG-S14-IAE-007` | Automation Rule Engine |
| 336 | `CG-S14-IAE-008` | Integration Hub |
| 337 | `CG-S14-IAE-009` | Public API Platform |
| 338 | `CG-S14-IAE-010` | Customer API |
| 339 | `CG-S14-IAE-011` | Vendor API |
| 340 | `CG-S14-IAE-012` | Webhook Management |
| 341 | `CG-S14-IAE-013` | n8n Integration |
| 342 | `CG-S14-IAE-014` | Email WhatsApp SMS Integrations |
| 343 | `CG-S14-IAE-015` | Enterprise Maps, GPS and Telematics Integrations |
| 344 | `CG-S14-IAE-016` | Carrier Port Airport Customs Integrations |
| 345 | `CG-S14-IAE-017` | Bank Payment E-Invoice Tax Integrations |
| 346 | `CG-S14-IAE-018` | External Accounting HR Integrations |
| 347 | `CG-S14-IAE-019` | AI Governance Provider Boundary |
| 348 | `CG-S14-IAE-020` | AI-Assisted Quotation |
| 349 | `CG-S14-IAE-021` | OCR Document Processing |
| 350 | `CG-S14-IAE-022` | Predictive ETA |
| 351 | `CG-S14-IAE-023` | Optimization Assistance |
| 352 | `CG-S14-IAE-024` | Fraud and Risk Assistance |
| 353 | `CG-S14-IAE-025` | Forecasting and Recommendation Assistance |
| 354 | `CG-S14-IAE-026` | Enterprise IAM SSO SAML OAuth SCIM |
| 355 | `CG-S14-IAE-027` | Enterprise MFA Session Controls |
| 356 | `CG-S14-IAE-028` | IP Restriction Network Access |
| 357 | `CG-S14-IAE-029` | Advanced Audit and Impersonation |
| 358 | `CG-S14-IAE-030` | Enterprise Monitoring Observability |
| 359 | `CG-S14-IAE-031` | Data Retention Archival |
| 360 | `CG-S14-IAE-032` | Dedicated Enterprise Deployment |
| 361 | `CG-S14-IAE-033` | Multi Region Data Residency |
| 362 | `CG-S14-IAE-034` | Scale-Up Architecture |
| 363 | `CG-S14-IAE-035` | Disaster Recovery Enterprise Support |
| 364 | `CG-S14-IAE-036` | Intelligence, Automation and Enterprise Integrated Verification |
| 365 | `CG-S14-IAE-037` | Intelligence, Automation and Enterprise Security AI Hardening |
| 366 | `CG-S14-IAE-038` | Intelligence, Automation and Enterprise Documentation Handoff |
| 367 | `CG-S14-IAE-039` | Intelligence, Automation and Enterprise Closure Verification |

### Phase 15 — Full-System Hardening (`CG-S15-HDN-…`) — `NOT_STARTED`

| Prompt | Task ID | Capability |
|---:|---|---|
| 369 | `CG-S15-HDN-001` | Full-System Hardening WBS Runtime Kickoff |
| 370 | `CG-S15-HDN-002` | Full Regression |
| 371 | `CG-S15-HDN-003` | Cross-Module Transactional Integrity |
| 372 | `CG-S15-HDN-004` | Tenant Isolation Audit |
| 373 | `CG-S15-HDN-005` | RLS and RBAC Audit |
| 374 | `CG-S15-HDN-006` | Financial Integrity Audit |
| 375 | `CG-S15-HDN-007` | Data Lineage Audit |
| 376 | `CG-S15-HDN-008` | API Compatibility Audit |
| 377 | `CG-S15-HDN-009` | Storage and Signed URL Audit |
| 378 | `CG-S15-HDN-010` | Security Hardening |
| 379 | `CG-S15-HDN-011` | Performance and Scalability |
| 380 | `CG-S15-HDN-012` | Accessibility Audit |
| 381 | `CG-S15-HDN-013` | Browser Device Compatibility |
| 382 | `CG-S15-HDN-014` | Observability Audit |
| 383 | `CG-S15-HDN-015` | Backup and Restore |
| 384 | `CG-S15-HDN-016` | Disaster Recovery Rehearsal |
| 385 | `CG-S15-HDN-017` | Data Migration Rehearsal |
| 386 | `CG-S15-HDN-018` | Full-System Hardening Integrated Verification |
| 387 | `CG-S15-HDN-019` | Release Blocker Triage and Remediation |
| 388 | `CG-S15-HDN-020` | Full-System Hardening Documentation Handoff |
| 389 | `CG-S15-HDN-021` | Full-System Hardening Closure Verification |

### Phase 16 — Release and Go-Live (`CG-S16-RGL-…`) — `NOT_STARTED`

| Prompt | Task ID | Capability |
|---:|---|---|
| 391 | `CG-S16-RGL-001` | Release Go-Live WBS Runtime Kickoff |
| 392 | `CG-S16-RGL-002` | Release Candidate Freeze |
| 393 | `CG-S16-RGL-003` | No-New-Feature Rule |
| 394 | `CG-S16-RGL-004` | Defect Triage |
| 395 | `CG-S16-RGL-005` | Full CI Gate |
| 396 | `CG-S16-RGL-006` | Clean Database Rebuild |
| 397 | `CG-S16-RGL-007` | Migration Validation |
| 398 | `CG-S16-RGL-008` | Seed Validation |
| 399 | `CG-S16-RGL-009` | Staging Deployment |
| 400 | `CG-S16-RGL-010` | UAT Deployment |
| 401 | `CG-S16-RGL-011` | Smoke Test |
| 402 | `CG-S16-RGL-012` | Penetration Test Evidence |
| 403 | `CG-S16-RGL-013` | Performance Evidence |
| 404 | `CG-S16-RGL-014` | Go/No-Go Report |
| 405 | `CG-S16-RGL-015` | Production Deployment |
| 406 | `CG-S16-RGL-016` | Post-Deployment Validation |
| 407 | `CG-S16-RGL-017` | Rollback Decision |
| 408 | `CG-S16-RGL-018` | Hypercare |
| 409 | `CG-S16-RGL-019` | Post-Implementation Review |
| 410 | `CG-S16-RGL-020` | Release Go-Live Integrated Verification |
| 411 | `CG-S16-RGL-021` | Release Go-Live Documentation Handoff |
| 412 | `CG-S16-RGL-022` | Release Go-Live Closure Verification |

### Final Package Validation (`CG-S17-FPV-…`) — package-level audit, not a build phase

| Prompt | Task ID | Capability |
|---:|---|---|
| 414 | `CG-S17-FPV-001` | Final Package Validation WBS Kickoff |
| 415 | `CG-S17-FPV-002` | Requirement Coverage Audit |
| 416 | `CG-S17-FPV-003` | Phase Module Prompt Coverage Audit |
| 417 | `CG-S17-FPV-004` | Dependency Completion Criteria Audit |
| 418 | `CG-S17-FPV-005` | Prompt Atomicity Oversize Audit |
| 419 | `CG-S17-FPV-006` | Circular Dependency Order Audit |
| 420 | `CG-S17-FPV-007` | Regression Risk Audit |
| 421 | `CG-S17-FPV-008` | Cross-Domain Closure Audit |
| 422 | `CG-S17-FPV-009` | Restartability Resume Audit |
| 423 | `CG-S17-FPV-010` | Context Completeness New Agent Audit |
| 424 | `CG-S17-FPV-011` | Allowed Forbidden Scope Audit |
| 425 | `CG-S17-FPV-012` | Evidence Documentation Update Audit |
| 426 | `CG-S17-FPV-013` | Package Consistency Version ID Audit |
| 427 | `CG-S17-FPV-014` | Final Gap Risk Register Audit |
| 428 | `CG-S17-FPV-015` | Final Execution Sequence Audit |
| 429 | `CG-S17-FPV-016` | START_HERE Entry Point Audit |
| 430 | `CG-S17-FPV-017` | Final Package Validation Closure Verification |

## 4. Totals

| | Count |
|---|---:|
| Prompts carrying a task ID | 339 |
| `VERIFIED` (Phases 0–4 complete, Phase 5 through prompt 238) | 163 |
| Not yet started | 176 |
| Extra WBS rows with no source prompt (Phase 5 insertions + `ATW-007` children) | 10 |

## 5. Maintenance

Regenerate rather than hand-edit. Every row below is derived from the
`**Prompt ID:**` line and the H1 title of each file in
`docs/ai-agent-build-prompt-package/<phase-dir>/`. When a phase's prompts change,
re-derive this table from those files; when execution inserts or decomposes a
task, record it in §2 and in the owning phase's execution index, not by
renumbering the package.
