# CargoGrid Product Concept Brief

## 1. Product Overview

CargoGrid adalah produk SaaS berbentuk ERP system yang dirancang khusus untuk:

- Perusahaan 3PL
- Cargo company
- Freight forwarder
- Trucking company
- Warehouse operator
- Distribution company
- Project logistics provider
- In-house logistics operation milik perusahaan manufaktur, distributor, retailer, atau enterprise customer

CargoGrid diposisikan sebagai **all-in-one, end-to-end logistics ERP system** yang mampu mendukung proses bisnis dan operasional perusahaan logistik secara menyeluruh, advanced, komprehensif, modular, dan configurable.

CargoGrid akan ditawarkan kepada perusahaan logistik dengan konsep:

- Multi-tenant SaaS
- White-label platform
- Modular subscription
- Row-Level Security atau RLS
- Role-Based Access Control atau RBAC
- Configurable workflow
- Configurable module
- Configurable role and permission
- Configurable service
- Configurable approval
- Configurable business process
- Configurable operational process

Seluruh konfigurasi sistem harus dapat dilakukan melalui user interface tanpa perlu melakukan perubahan source code backend.

---

## 2. Core Product Principles

CargoGrid harus dibangun berdasarkan prinsip berikut:

1. **End-to-end logistics business and operational process**
2. **Single source of truth**
3. **Tidak ada redundant data entry**
4. **Antarmodul terhubung secara direksional dan transaksional**
5. **Data hanya perlu diinput satu kali dan dapat digunakan kembali oleh modul lain**
6. **Multi-tenant dengan isolasi data yang ketat**
7. **White-label dan dapat disesuaikan untuk setiap tenant**
8. **Role, permission, workflow, approval, form, field, status, numbering, dan service dapat dikonfigurasi**
9. **Seluruh konfigurasi dilakukan melalui UI**
10. **Tidak membutuhkan perubahan source code backend untuk menyesuaikan kebutuhan customer**
11. **Mendukung proses bisnis dan operasional yang berbeda pada setiap tenant**
12. **Mendukung subscription berdasarkan modul dan feature**
13. **Mendukung audit trail secara menyeluruh**
14. **Mendukung integrasi dengan sistem eksternal melalui API dan webhook**
15. **Mendukung pertumbuhan dari skala SME sampai enterprise**

---

## 3. User Access Layer

CargoGrid memiliki empat layer utama.

### 3.1 Layer 1 — Supreme Admin

Supreme Admin adalah administrator internal CargoGrid yang memiliki absolute CRUD terhadap seluruh program dan seluruh tenant.

Supreme Admin memiliki kewenangan untuk:

- Membuat, mengubah, menonaktifkan, dan menghapus tenant
- Mengaktifkan atau menonaktifkan modul
- Mengatur subscription
- Mengatur feature availability
- Mengatur white-label
- Mengatur custom domain
- Mengatur role
- Mengatur hierarchy
- Mengatur permission
- Mengatur field-level access
- Mengatur workflow
- Mengatur approval
- Mengatur form
- Mengatur custom field
- Mengatur status
- Mengatur numbering
- Mengatur notification
- Mengatur automation
- Mengatur service
- Mengatur document template
- Mengatur report
- Mengatur dashboard
- Mengatur API
- Mengatur webhook
- Mengatur integration
- Melakukan impersonation dengan kontrol dan audit trail
- Melakukan konfigurasi seluruh sistem melalui UI

Prinsip utama:

> Seluruh konfigurasi tenant harus dapat dilakukan oleh Supreme Admin melalui user interface tanpa perlu mengubah source code backend.

---

### 3.2 Layer 2 — User Admin

User Admin adalah administrator milik customer atau tenant CargoGrid.

User Admin memiliki akses CRUD terhadap modul dan feature yang disubscribe oleh perusahaannya, sesuai scope yang diberikan oleh Supreme Admin.

User Admin dapat:

- Mengelola user tenant
- Mengelola role tenant
- Mengelola permission tenant
- Mengelola organization structure
- Mengelola hierarchy
- Mengelola master data
- Mengelola workflow
- Mengelola approval
- Mengelola form dan custom field
- Mengelola notification
- Mengelola dashboard dan report
- Mengelola konfigurasi tenant
- Mengelola customer user
- Mengelola integrasi tenant sesuai hak akses

Batas kewenangan User Admin tetap mengikuti subscription, module entitlement, policy, dan permission yang ditetapkan Supreme Admin.

---

### 3.3 Layer 3 — Internal Organizational User

Layer 3 adalah user internal milik tenant CargoGrid.

Hak akses setiap user ditentukan berdasarkan:

- Role
- Position
- Hierarchy
- Department
- Branch
- Business unit
- Team
- Region
- Service
- Record ownership
- Transaction value
- Transaction status
- Scope lain yang ditentukan tenant

Role pada Layer 3 dapat dibuat, diubah, dan dikonfigurasi oleh Supreme Admin maupun User Admin sesuai kewenangan.

Title dan scope akses dapat disesuaikan berdasarkan kebutuhan customer.

Hierarki standar Layer 3:

1. Director
2. General Manager
3. Manager
4. Assistant Manager
5. Supervisor
6. Team Leader
7. Staff

CargoGrid harus memungkinkan tenant untuk:

- Mengubah nama title
- Menambahkan level hierarchy
- Menghapus level yang tidak digunakan
- Mengatur reporting line
- Mengatur approval authority
- Mengatur scope CRUD
- Mengatur access level per module
- Mengatur access level per field
- Mengatur own data versus team data versus all data

---

### 3.4 Layer 4 — Customer User

Customer User adalah user eksternal milik customer dari perusahaan yang menggunakan CargoGrid.

Customer User mengakses Customer Portal berdasarkan company, account, dan access scope yang diberikan.

Fitur Customer Portal mencakup:

- Request quotation
- Booking shipment
- Shipment order
- Shipment tracking
- Shipment monitoring
- Akses ePOD
- Akses shipment document
- Warehouse inventory control
- Warehouse order monitoring
- Order fulfillment monitoring
- Billing control
- Invoice control
- Payment monitoring
- Complaint
- Ticketing
- Loyalty
- Rewards
- Customer profile
- Customer user management

Customer User hanya dapat melihat data yang terkait dengan company, account, shipment, warehouse, invoice, dan transaksi yang berada dalam scope aksesnya.

---

## 4. Multi-Tenant and White-Label Concept

CargoGrid menggunakan konsep multi-tenant.

Setiap tenant harus memiliki:

- Data isolation
- User isolation
- Role isolation
- Permission isolation
- Configuration isolation
- Workflow isolation
- Branding isolation
- Subscription isolation
- Reporting isolation
- Document isolation
- Integration isolation

White-label configuration dapat mencakup:

- Nama produk
- Logo
- Warna utama
- Typography
- Login page
- Domain
- Email template
- Document template
- Invoice template
- Quotation template
- Customer portal
- Notification template
- Terminology
- Menu naming

Sistem harus mendukung kombinasi:

- Global default configuration dari CargoGrid
- Tenant-level override
- Company-level override
- Branch-level override
- Role-level override
- User-level override

---

## 5. Configurability Principle

CargoGrid harus menggunakan pendekatan metadata-driven dan configuration-driven.

Supreme Admin harus dapat melakukan konfigurasi melalui UI untuk:

- Module
- Feature
- Subscription
- Role
- Permission
- Hierarchy
- Organization structure
- Form
- Field
- Custom field
- Workflow
- Approval
- Status
- Notification
- Automation
- SLA
- Numbering
- Service
- Shipment mode
- Document template
- Dashboard
- Report
- Terminology
- Branding
- Integration
- API
- Webhook

Konfigurasi harus mendukung:

- Draft
- Publish
- Versioning
- Rollback
- Tenant override
- Dependency validation
- Audit trail
- Activation date
- Deactivation date

---

## 6. End-to-End Data Flow Principle

Seluruh modul CargoGrid harus saling terkait.

Prinsip utamanya:

- Data lead dapat digunakan pada CRM
- Lead yang qualified dapat dikonversi menjadi prospect
- Prospect dapat dikonversi menjadi customer
- Customer dapat digunakan pada opportunity
- Opportunity dapat digunakan untuk request costing
- Costing dapat digunakan untuk quotation
- Quotation yang accepted dapat dikonversi menjadi contract atau job order
- Job order dapat dikonversi menjadi shipment
- Shipment dapat menggunakan vendor, fleet, driver, route, warehouse, service, dan rate
- Shipment update dapat ditampilkan ke customer portal
- ePOD dapat digunakan sebagai dasar billing readiness
- Actual cost dapat digunakan untuk profitability
- Invoice dapat digunakan untuk accounts receivable
- Vendor invoice dapat digunakan untuk accounts payable
- Payment dapat digunakan untuk settlement dan reconciliation
- Customer transaction dapat digunakan untuk loyalty point
- Ticket dapat terkait dengan customer, shipment, invoice, warehouse order, atau user
- Employee master dapat digunakan pada approval, assignment, attendance, payroll, KPI, dan performance

Tidak boleh ada pengisian ulang terhadap data yang sudah tersedia, kecuali terdapat alasan bisnis yang jelas dan dapat diaudit.

---

# 7. Main Modules

## 7.1 Commercial

### Lead Management

Lead dapat berasal dari:

- Contact form digital
- Landing page
- Campaign
- Social media
- API
- Referral
- Manual input user
- Import file
- Integration

Capability:

- Lead capture
- Lead source
- Lead scoring
- Lead qualification
- Lead assignment
- Lead ownership
- Lead activity
- Lead conversion
- Duplicate detection
- Lead status
- Lead aging
- Lead analytics

### CRM

CRM mencakup:

- Sales plan
- Create, update, delete sales plan
- Sales pipeline
- Lead qualification
- Opportunity management
- Account management
- Contact management
- Sales activity
- Call
- Email
- Meeting
- Visit
- Follow-up
- Task
- Reminder
- Sales target
- Sales forecast
- Sales conversion
- Closing
- Lost reason
- Win-loss analysis
- Comprehensive sales analytics

### Quotation

Quotation mencakup:

- Search cost
- Request costing
- Cost comparison
- Vendor rate comparison
- Create customer quotation
- Quotation versioning
- Margin calculation
- Discount
- Approval
- Quotation validity
- Terms and conditions
- Document generation
- Send quotation
- Customer acceptance
- Customer rejection
- Quotation conversion
- Contract linkage
- Job order conversion

---

## 7.2 Operations

### Transportation Management System

CargoGrid harus memiliki TMS yang lengkap dan komprehensif, termasuk:

- Shipment order
- Job order
- Transport planning
- Route planning
- Load planning
- Capacity planning
- Multi-pickup
- Multi-drop
- Multi-leg shipment
- Multi-modal shipment
- Dispatch
- Fleet assignment
- Driver assignment
- Vehicle assignment
- Vendor assignment
- Trip management
- GPS integration
- Telematics integration
- Milestone management
- Exception management
- Delay management
- Delivery planning
- Proof of pickup
- Proof of delivery
- Costing
- Actual cost
- Shipment profitability
- Claims
- Incident
- Shipment closing

Mode yang perlu didukung:

- Land freight
- Air freight
- Sea freight
- Rail freight
- Courier
- Last-mile
- First-mile
- Middle-mile
- Project logistics
- Cross-border
- Customs clearance
- Consolidation
- Break bulk
- LTL
- FTL
- LCL
- FCL

### Warehouse Management System

CargoGrid harus memiliki WMS yang lengkap dan komprehensif, termasuk:

- Warehouse master
- Zone
- Area
- Rack
- Bin
- Location
- Inbound
- Receiving
- Quality check
- Putaway
- Inventory
- Stock movement
- Stock adjustment
- Cycle count
- Physical count
- Replenishment
- Picking
- Packing
- Staging
- Loading
- Outbound
- Return
- Reverse logistics
- Cross-docking
- Value-added service
- Kitting
- Bundling
- Labeling
- Barcode
- QR code
- Serial number
- Batch
- Lot
- Expiry
- FIFO
- FEFO
- LIFO
- Inventory aging
- Inventory ownership
- Customer inventory
- Warehouse billing
- Warehouse productivity
- Warehouse SLA

### Shipment Update and Monitoring

Capability:

- Real-time shipment status
- Milestone update
- ETA
- ETD
- Actual arrival
- Actual departure
- Delay reason
- Exception
- Location update
- Customer notification
- Internal notification
- Map tracking
- Timeline tracking
- Status history
- Event log
- Multi-leg visibility
- Multi-modal visibility

### ePOD and Document Management

Capability:

- Electronic proof of delivery
- Photo
- Signature
- Receiver name
- Receiver position
- Geolocation
- Timestamp
- Document upload
- Document versioning
- Document approval
- Document expiry
- Document access control
- Document template
- Shipment document
- Vendor document
- Customer document
- Financial document
- HR document
- Audit document

### Costing

Costing mencakup:

- Estimated cost
- Standard cost
- Vendor cost
- Internal cost
- Surcharge
- Accessorial charge
- Fuel surcharge
- Handling
- Toll
- Parking
- Labor
- Warehouse cost
- Customs cost
- Documentation cost
- Actual cost
- Cost variance
- Cost approval
- Cost overrun
- Cost allocation
- Job profitability

---

## 7.3 Procurement and Vendor Management

### Vendor Registration

Capability:

- Vendor registration
- Vendor self-registration
- Vendor onboarding
- Vendor document
- Vendor verification
- Vendor approval
- Vendor category
- Vendor service
- Vendor coverage
- Vendor fleet
- Vendor warehouse
- Vendor contact
- Vendor bank account
- Vendor payment term
- Vendor tax
- Vendor compliance

### Vendor Assessment

Capability:

- Initial assessment
- Periodic assessment
- Risk assessment
- Compliance assessment
- Financial assessment
- Operational assessment
- Safety assessment
- Document completeness
- Corrective action
- Assessment score
- Approval
- Expiry
- Reassessment

### Vendor Management

Capability:

- Vendor profile
- Vendor contract
- Vendor service
- Vendor coverage
- Vendor capacity
- Vendor availability
- Vendor performance
- Vendor issue
- Vendor claim
- Vendor incident
- Vendor blacklist
- Vendor suspension
- Vendor reactivation
- Vendor analytics

### Vendor Performance

KPI dapat mencakup:

- On-time pickup
- On-time delivery
- Acceptance rate
- Response time
- Capacity fulfillment
- Document compliance
- Claim rate
- Damage rate
- Cost competitiveness
- Rate validity
- Invoice accuracy
- Service quality
- Customer complaint
- SLA compliance

### Vendor Quotation and Pricelist

Capability:

- Vendor quotation
- Vendor rate card
- Vendor pricelist
- Route-based rate
- Service-based rate
- Fleet-based rate
- Weight-based rate
- Volume-based rate
- Zone-based rate
- Distance-based rate
- Container-based rate
- Shipment mode rate
- Validity
- Surcharge
- Currency
- Tax
- Minimum charge
- Tiering
- Rate comparison
- Cost selection
- Rate approval

---

## 7.4 Financial and Accounting

CargoGrid harus memiliki full financial and accounting system.

Capability:

- Chart of accounts
- General ledger
- Subledger
- Journal
- Journal approval
- Accounts receivable
- Accounts payable
- Invoice generation
- Billing
- Customer billing
- Vendor billing
- Payment
- Receipt
- Payment allocation
- Credit note
- Debit note
- Tax
- Withholding tax
- VAT
- Bank reconciliation
- Cash management
- Petty cash
- Budget
- Cost center
- Profit center
- Accrual
- Prepayment
- Revenue recognition
- Cost recognition
- Cost allocation
- Job profitability
- Customer profitability
- Service profitability
- Branch profitability
- Multi-company
- Multi-branch
- Multi-currency
- Exchange rate
- Financial consolidation
- Period closing
- Period lock
- Trial balance
- Profit and loss
- Balance sheet
- Cash flow statement
- Aging AR
- Aging AP
- Financial audit trail

Sistem keuangan harus mendukung prinsip double-entry accounting dan immutable posted journal.

---

## 7.5 HRIS

CargoGrid harus memiliki full HR system.

Capability:

- Organization structure
- Position
- Job level
- Job grade
- Employee master
- Contract
- Recruitment
- Job portal
- Vacancy
- Applicant tracking
- Candidate assessment
- Interview
- Offering
- Onboarding
- Attendance
- Shift
- Roster
- Leave
- Permit
- Overtime
- Business trip
- Timesheet
- Payroll
- Benefit
- Allowance
- Deduction
- Tax
- Loan
- Reimbursement
- Performance management
- KPI
- Competency
- Training
- Learning
- Career
- Succession
- Talent management
- Employee self-service
- Manager self-service
- Employee document
- Disciplinary action
- Offboarding
- Exit clearance

---

## 7.6 Ticketing

Ticketing mencakup:

### Internal Ticketing

- User internal ke user internal
- Antar-department
- Antar-branch
- Antar-company dalam satu tenant
- Assignment
- Priority
- Category
- SLA
- Escalation
- Resolution
- Internal note
- Attachment
- Linked transaction

### Customer Ticketing

- Customer ke tenant
- Customer complaint
- Shipment issue
- Billing issue
- Warehouse issue
- Document issue
- Claim
- Service request
- Feedback

### Tenant to CargoGrid Helpdesk

- User Admin ke CargoGrid
- Technical support
- Functional support
- Subscription issue
- Configuration issue
- Integration issue
- Bug report
- Feature request
- Security issue

---

## 7.7 Loyalty and Rewards

CargoGrid harus memiliki loyalty program yang komprehensif dan customizable.

Capability:

- Loyalty program
- Membership tier
- Point earning
- Point multiplier
- Cashback
- Discount
- Voucher
- Coupon
- Reward
- Redemption
- Referral
- Promotion
- Campaign
- Customer segmentation
- Transaction-based earning
- Volume-based earning
- Revenue-based earning
- Service-based earning
- Tier upgrade
- Tier downgrade
- Point expiration
- Reward expiration
- Redemption approval
- Fraud prevention
- Loyalty liability
- Loyalty analytics
- Customer engagement analytics

Setiap tenant dapat mengatur:

- Rule
- Formula
- Threshold
- Tier
- Expiry
- Reward catalogue
- Redemption method
- Approval
- Eligible customer
- Eligible transaction
- Campaign period

---

## 8. Service Configuration

CargoGrid harus memiliki service configuration engine.

Service dapat dikonfigurasi berdasarkan:

- Service name
- Service category
- Shipment mode
- Origin
- Destination
- Coverage
- SLA
- Transit time
- Weight rule
- Volume rule
- Dimensional weight
- Package type
- Commodity
- Fleet
- Container
- Warehouse
- Handling requirement
- Cost component
- Revenue component
- Tax
- Surcharge
- Approval
- Document requirement
- Operational workflow
- Milestone
- Status lifecycle
- Customer eligibility
- Vendor eligibility

Supreme Admin dapat membuat service template.

Tenant dapat menggunakan template tersebut atau melakukan override sesuai hak akses.

---

## 9. Technology Stack

CargoGrid menggunakan:

### Frontend

- Next.js
- TypeScript
- React
- Server-side rendering jika diperlukan
- Static generation jika relevan
- Responsive web application
- Progressive Web App sebagai opsi

### Backend and Database

- Supabase
- PostgreSQL
- Supabase Auth
- Supabase Row-Level Security
- Supabase Storage
- Supabase Realtime jika relevan
- Supabase Edge Functions jika relevan
- Database function dan trigger hanya untuk kebutuhan yang tepat

### Integration

- REST API
- Webhook
- Background job
- Queue
- n8n untuk workflow integration tertentu
- External API integration

---

## 10. Performance and Efficiency Principles

CargoGrid harus dirancang agar tidak lemot, berat, atau menghasilkan API call yang tidak efisien.

Prinsip teknis utama:

1. Hindari excessive client-side fetching.
2. Hindari N+1 query.
3. Gunakan server-side data fetching secara tepat.
4. Gunakan pagination untuk data besar.
5. Gunakan cursor pagination jika diperlukan.
6. Gunakan database index yang sesuai.
7. Gunakan selective column query.
8. Hindari penggunaan `SELECT *` pada transaksi utama.
9. Gunakan caching secara terkontrol.
10. Gunakan materialized view untuk report yang kompleks jika relevan.
11. Pisahkan transactional query dan analytical query.
12. Gunakan background job untuk proses berat.
13. Gunakan queue untuk notification, report, integration, dan automation.
14. Gunakan batch processing untuk bulk operation.
15. Gunakan optimistic update hanya jika aman.
16. Gunakan realtime subscription hanya pada data yang memang membutuhkan realtime.
17. Hindari global realtime subscription.
18. Terapkan rate limiting.
19. Terapkan API response compression.
20. Terapkan lazy loading dan code splitting.
21. Terapkan database connection pooling.
22. Terapkan query monitoring.
23. Terapkan slow-query logging.
24. Terapkan performance budget.
25. Terapkan pagination, filtering, dan sorting di server.
26. Hindari membawa seluruh dataset ke browser.
27. Gunakan precomputed summary untuk dashboard jika diperlukan.
28. Gunakan file storage terpisah untuk document.
29. Gunakan signed URL untuk file access.
30. Terapkan tenant-aware indexing.

---

## 11. Detailed Data Requirement

Seluruh data utama harus dirancang detail dan komprehensif.

Entity utama minimal mencakup:

### Tenant Data

- Tenant profile
- Subscription
- Module
- Feature
- Branding
- Domain
- Company
- Branch
- Department
- Business unit
- Organization structure
- User
- Role
- Permission

### Customer Data

- Customer profile
- Legal entity
- Tax identity
- Billing identity
- Customer category
- Industry
- Contact
- Address
- Site
- Branch
- PIC
- Service requirement
- Credit limit
- Payment term
- Contract
- Pricelist
- SLA
- Customer status
- Customer document
- Customer hierarchy
- Parent company
- Subsidiary
- Customer user
- Customer portal access

### Shipment Data

- Shipment number
- Job order
- Booking
- Customer
- Shipper
- Consignee
- Notify party
- Service
- Shipment mode
- Shipment type
- Origin
- Destination
- Pickup address
- Delivery address
- Port of loading
- Port of discharge
- Airport of departure
- Airport of arrival
- Route
- Shipment leg
- Multi-pickup
- Multi-drop
- Commodity
- HS code
- Package
- Quantity
- Weight
- Volume
- Dimension
- Chargeable weight
- Container
- Fleet
- Vehicle
- Driver
- Vendor
- Warehouse
- Schedule
- ETA
- ETD
- Actual time
- Milestone
- Status
- Exception
- Delay
- Cost
- Revenue
- Margin
- Document
- ePOD
- Claim
- Incident
- Invoice
- Payment
- Audit trail

### Vendor Data

- Vendor profile
- Legal identity
- Tax identity
- Contact
- Address
- Service
- Coverage
- Fleet
- Capacity
- Warehouse
- Rate
- Pricelist
- Contract
- Payment term
- Bank account
- Compliance
- Document
- Assessment
- Performance
- Incident
- Claim
- Invoice
- Payment

### Warehouse Data

- Warehouse
- Zone
- Area
- Rack
- Bin
- Location
- Inventory
- SKU
- Batch
- Lot
- Serial
- Expiry
- Ownership
- Inbound
- Putaway
- Movement
- Picking
- Packing
- Outbound
- Return
- Adjustment
- Cycle count
- Billing

### Financial Data

- Chart of account
- Journal
- Ledger
- Invoice
- Billing
- Payment
- Receipt
- Credit note
- Debit note
- Tax
- Currency
- Exchange rate
- Cost center
- Profit center
- Budget
- Accrual
- Revenue
- Cost
- AR
- AP
- Bank
- Reconciliation
- Financial statement

### Employee Data

- Employee
- Position
- Grade
- Department
- Branch
- Manager
- Contract
- Attendance
- Shift
- Leave
- Overtime
- Payroll
- Benefit
- KPI
- Performance
- Training
- Document
- Offboarding

---

## 12. Security Principles

CargoGrid harus menerapkan:

- Strict tenant isolation
- Row-Level Security
- Role-Based Access Control
- Field-level access
- Record-level access
- Company-level access
- Branch-level access
- Department-level access
- Team-level access
- Customer-level access
- Secure authentication
- MFA
- SSO sebagai opsi enterprise
- Session control
- Audit trail
- Impersonation logging
- Support access control
- Encryption in transit
- Encryption at rest
- Signed file URL
- Secret management
- Rate limiting
- API authentication
- Webhook signing
- Data masking
- Sensitive data control
- Financial data protection
- Personal data protection
- Backup
- Recovery
- Incident logging

---

## 13. Reporting and Analytics Principles

CargoGrid harus menyediakan:

- Role-specific dashboard
- Executive dashboard
- Commercial dashboard
- Sales dashboard
- Operations dashboard
- TMS dashboard
- WMS dashboard
- Procurement dashboard
- Vendor dashboard
- Finance dashboard
- Accounting dashboard
- HR dashboard
- Ticketing dashboard
- Loyalty dashboard
- Customer portal dashboard
- Supreme Admin SaaS dashboard

Report dan dashboard harus:

- Tenant-aware
- Permission-aware
- Filterable
- Exportable
- Configurable
- Drill-down capable
- Scheduled
- Auditable
- Optimized for performance

---

## 14. Product Vision

CargoGrid harus menjadi:

> All-in-one, end-to-end, configurable logistics ERP system untuk perusahaan 3PL, freight forwarder, cargo company, warehouse operator, trucking company, distribution company, project logistics provider, dan in-house logistics operation.

CargoGrid harus mampu menyesuaikan proses bisnis, struktur organisasi, service, workflow, approval, role, permission, terminology, form, field, status, document, report, dashboard, dan operational model setiap tenant tanpa perlu melakukan perubahan source code backend.

CargoGrid bukan hanya software administrasi, tetapi menjadi sistem operasi utama untuk menjalankan seluruh bisnis logistik dari lead sampai revenue, dari booking sampai delivery, dari vendor sampai payment, dari employee sampai performance, dan dari customer transaction sampai loyalty.

---

## 15. Confirmed Product Decisions

Keputusan yang sudah dikonfirmasi:

- Nama produk: CargoGrid
- Model: SaaS ERP
- Target market: 3PL dan logistics-related company
- Multi-tenant
- White-label
- RLS
- RBAC
- Empat user layer
- Configurable hierarchy
- Configurable role dan permission
- Configurable module
- Configurable workflow
- Configurable approval
- Configurable service
- UI-based configuration
- Tidak membutuhkan perubahan backend untuk konfigurasi tenant
- End-to-end process
- Antar-modul saling terhubung
- Tidak ada redundant data entry
- Next.js frontend
- Supabase backend
- Detail customer dan shipment harus komprehensif
- Backend dan API harus efisien, ringan, dan scalable

---

## 16. Future Considerations

Area yang dapat dipertimbangkan pada fase selanjutnya:

- Native mobile application
- AI-assisted quotation
- AI sales assistant
- Predictive ETA
- Predictive maintenance
- Route optimization
- Dynamic pricing
- Fraud detection
- OCR document processing
- Automated document classification
- Demand forecasting
- Warehouse slotting optimization
- Vendor recommendation engine
- Customer churn prediction
- Revenue forecasting
- Embedded finance
- IoT integration
- Blockchain-based document verification
- Multi-region deployment
- Dedicated enterprise instance
