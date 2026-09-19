/**
 * CG-AUDIT-2026-09-02 A6: the single shared name for the real Supabase Storage
 * bucket `supabase/migrations/20260908010000_close_a6_storage_bucket_and_malware_scan_job_type.sql`
 * provisions. A plain string constant, not a database-backed lookup -- the bucket id
 * is fixed at provisioning time and never varies per tenant or per environment (the
 * migration's own file is the source of truth; this constant is kept in lockstep
 * with it by hand, the same convention this repository already uses for a handful
 * of other fixed identifiers with no runtime configurability).
 */
export const TENANT_DOCUMENTS_BUCKET_ID = "tenant-documents";
