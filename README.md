# CargoGrid

CargoGrid is a multi-tenant, modular enterprise SaaS ERP built for logistics and supply chain operators.

It connects commercial, operational, financial, customer, and enterprise workflows in one governed platform designed for freight forwarding, cargo, trucking, warehousing, distribution, and project logistics businesses.

> One Platform. Every Shipment. Complete Visibility.

---

## Current Build Status

CargoGrid is currently under active development.

| Phase | Scope | Status |
|---|---|---|
| Phase 0 | Discovery and Foundation | Verified |
| Phase 1 | Platform Core | Verified |
| Phase 2 | Commercial | Verified |
| Phase 3 | Operations | In Progress |
| Phase 4 | Finance | Not Started |
| Phase 5 | Advanced TMS and WMS | Not Started |
| Phase 6 | Procurement and Vendor Management | Not Started |
| Phase 7 | HRIS and Ticketing | Not Started |
| Phase 8 | Customer Portal and Loyalty | Not Started |
| Phase 9 | Intelligence and Enterprise | Not Started |
| Phase 15 | Full-System Hardening | Not Started |
| Phase 16 | Release Candidate and Go-Live | Not Started |

### Current checkpoint

- Platform Core: complete
- Commercial: complete
- Operations: 16 of 22 tasks verified
- Current main branch checkpoint: Operations Dashboard
- Next task: Operations Reports
- Production deployment: not yet completed
- Live Supabase environment: not yet provisioned

---

## Implemented Capabilities

### Platform Core

The Platform Core provides the shared technical and governance foundation for every CargoGrid module.

Implemented capabilities include:

- Multi-tenant architecture
- Tenant provisioning and lifecycle
- Entitlement management
- Supabase authentication
- Organization and branch hierarchy
- User, role, and permission management
- Row-Level Security and record-level access
- Field-level data masking
- Audit logging and access disclosure
- White-label configuration
- Custom-domain foundation
- Master-data management
- Configuration engine
- Workflow engine
- Approval engine
- Status engine
- Numbering engine
- Form engine
- Notification engine
- Document and file engine
- API key and webhook foundation
- Import and export jobs
- Durable background jobs
- Feature flags
- PostGIS spatial foundation
- Tenant Admin portal
- Supreme Admin portal

---

### Commercial

The Commercial module supports the complete journey from lead generation to an accepted, operation-ready commercial handoff.

Implemented capabilities include:

- Lead management
- Prospect management
- Contact and activity management
- CRM sales planning
- Opportunity management
- Costing requests and responses
- Vendor rate lookup and selection
- Margin calculation and approval
- Quotation creation
- Quotation versioning
- Quotation approval
- Customer quotation acceptance
- Customer and account conversion
- Contract management
- Credit checking and override
- Sales targets and achievement
- Commercial dashboard
- Commercial reports
- Job Order handoff
- Duplicate detection and customer intelligence
- Commercial integrated verification and hardening

The Commercial workflow preserves source and version lineage from the initial lead through quotation acceptance and downstream Job Order preparation.

---

### Operations

The Operations module currently covers the main shipment execution and control-tower workflow.

Implemented capabilities include:

- Job Order
- Shipment Order
- Canonical shipment lifecycle
- Land, air, and sea baseline profiles
- Vendor, fleet, vehicle, and driver assignment
- Milestone management
- ETA and shipment-status projection
- Exception and escalation management
- Dispatch
- Shipment document requirements
- Electronic Proof of Delivery
- Actual operational cost capture
- Estimated-versus-actual cost variance
- Job profitability
- Public shipment tracking
- Billing-readiness evaluation
- Operations dashboard

Remaining Operations work includes:

- Operations reports
- Transaction lineage
- Integrated verification
- Operations hardening
- Documentation and handoff
- Phase closure verification

---

## Architecture

CargoGrid uses a shared application and database architecture with strict tenant isolation.

Core architecture principles:

- One shared product codebase
- Shared PostgreSQL schema with tenant-scoped records
- Row-Level Security as a primary authorization boundary
- No authorization based only on hidden UI elements
- Versioned and auditable business configuration
- Governed snapshots for transactional evidence
- Exact decimal arithmetic for financial values
- Idempotent mutation commands
- Deterministic business evaluations
- Explicit record and field-level permissions
- Reusable platform engines instead of module-specific duplicates
- Additive database migrations
- No silent financial, status, or workflow mutations

---

## Technology Stack

### Application

- Next.js 16
- React 19
- TypeScript 5
- Tailwind CSS 4
- Radix UI
- ECharts
- Zod

### Platform and Data

- Supabase
- PostgreSQL
- Row-Level Security
- PostGIS
- Supabase Auth
- Supabase Storage

### Engineering

- Node.js 22+
- pnpm
- ESLint
- Node Test Runner
- Playwright
- GitHub Actions
- Vercel target architecture

---

## Local Development

### Prerequisites

Install:

- Node.js `>=22.11.0`
- pnpm `10.33.0`
- Docker
- Supabase CLI

### Setup

```bash
pnpm install
cp .env.example .env.local
npx supabase start
pnpm run preflight
```

Copy the local Supabase URL and keys produced by `supabase start` into `.env.local`.

Never use production or shared-environment credentials for local development.

---

## Development Commands

```bash
pnpm run typecheck
pnpm run lint
pnpm test
pnpm run db:test
pnpm run docs:check
pnpm run security:check
pnpm run data-classification:check
pnpm run threat-model:check
pnpm run standards:check
pnpm run git:check
pnpm run git:check-paths
pnpm run test:e2e
```

### Production build

```bash
pnpm exec next build
```

---

## Repository Structure

```text
app/
  (public)/
  (tenant)/
  (supreme)/

components/
docs/
  adr/
  architecture/
  blueprint/
  build-log/
  runtime/

e2e/
lib/
scripts/
  db-tests/
  security/
  standards/

server/
  contracts/
  mutations/
  queries/

supabase/
  migrations/
```

---

## Quality and Verification

Every implemented capability is expected to include the relevant combination of:

- Database migration
- Row-Level Security policy
- Permission and record-scope enforcement
- Typed input and output contract
- Mutation or query service
- Positive tests
- Negative authorization tests
- Cross-tenant isolation tests
- Regression tests
- User-facing interface
- Build log
- Runtime status update

The latest Operations checkpoint verified:

- Type checking
- Linting
- Unit and service tests
- Database rebuild and database tests
- Documentation checks
- Security checks
- Data-classification checks
- Threat-model checks
- Standards checks
- Git collision and protected-path checks
- Next.js production build

---

## Environment Status

CargoGrid does not yet have a verified production environment.

Current limitations:

- No live production Supabase project
- No production tenant data
- No production deployment verification
- No full real-user authentication validation
- No production performance benchmark
- No external pilot or partial go-live claim
- Some browser-based E2E validation still depends on a provisioned execution environment

A completed internal phase means that its implementation and evidence are internally verified. It does not mean the overall product is production-ready.

---

## Documentation

Primary documentation locations:

- `docs/blueprint/`  
  Product, business-process, UX, data, architecture, and delivery source documents.

- `docs/architecture/`  
  Architecture decisions, dependency mapping, workstreams, and execution design.

- `docs/adr/`  
  Architecture Decision Records.

- `docs/build-log/`  
  Per-capability implementation and verification evidence.

- `docs/runtime/CARGOGRID_BUILD_STATUS.md`  
  Current build checkpoint.

- `docs/runtime/HANDOFF.md`  
  Runtime handoff and next execution task.

- `docs/runtime/TASK_LEDGER.md`  
  Complete task and verification ledger.

---

## Product Roadmap

The planned execution order is:

1. Complete Operations
2. Finance
3. Advanced TMS and WMS
4. Procurement and Vendor Management
5. HRIS and Ticketing
6. Customer Portal and Loyalty
7. Intelligence and Enterprise
8. Full-System Hardening
9. Release Candidate
10. Go-Live

---

## Product Ownership

CargoGrid is developed as a modular logistics SaaS platform under SAIKI Group.

Website: `cargogrid.net`  
Email: `service@cargogrid.net`
