/**
 * Customer Portal Dashboard contract (CPL-301, CG-S13-CPL-003, Prompt 301).
 * Mirrors supabase/migrations/
 * 20260801020000_create_customer_portal_dashboard_summary.sql's single RPC:
 * app.get_customer_portal_dashboard_summary. One row per card -- `cardKey`
 * names it, `available` is true only for a card whose real data source
 * exists and was queried (never a proxy for "the UI has something to
 * show" -- a real card can be `available: true` with a genuine zero count),
 * `degraded` marks a card whose own composed source failed this call
 * (every sibling card is unaffected -- see the migration's own design
 * decision 5), `summary` is a small, card-specific, already-safe jsonb
 * object (never internal-only fields), `detailPath` is a relative portal
 * route (no leading slash) the "view details" action should link to, or
 * `null` when no real route exists yet -- the caller must never render a
 * dead action for a `null` `detailPath` (source prompt §15).
 */

import { z } from "zod";

export const DASHBOARD_CARD_KEYS = ["accounts", "warehouse_inventory", "tickets", "bookings", "shipments", "invoices", "payments", "loyalty", "alerts"] as const;
export const DashboardCardKeySchema = z.enum(DASHBOARD_CARD_KEYS);
export type DashboardCardKey = z.infer<typeof DashboardCardKeySchema>;

/** The three cards with a real, already-shipped customer-facing data source as of this checkpoint (migration design decision 2). Every other DashboardCardKey is a disclosed stub -- `available: false` always. */
export const REAL_DASHBOARD_CARD_KEYS = ["accounts", "warehouse_inventory", "tickets"] as const;

// --- Row schema ---

export const CustomerPortalDashboardCardSchema = z.object({
  cardKey: DashboardCardKeySchema,
  available: z.boolean(),
  sourceUpdatedAt: z.string().nullable(),
  degraded: z.boolean(),
  summary: z.record(z.string(), z.unknown()),
  detailPath: z.string().nullable(),
});
export type CustomerPortalDashboardCard = z.infer<typeof CustomerPortalDashboardCardSchema>;

export function parseCustomerPortalDashboardCard(row: Record<string, unknown>): CustomerPortalDashboardCard {
  return CustomerPortalDashboardCardSchema.parse({
    cardKey: row.card_key,
    available: row.available,
    sourceUpdatedAt: row.source_updated_at ?? null,
    degraded: row.degraded,
    summary: row.summary ?? {},
    detailPath: row.detail_path ?? null,
  });
}

// --- Per-card typed summary shapes (parsed from the generic `summary` jsonb once the caller already knows which card it is) ---

export const AccountsCardSummarySchema = z.object({
  activeAccountCount: z.number().int().nonnegative(),
  primaryAccountName: z.string().nullable(),
});
export type AccountsCardSummary = z.infer<typeof AccountsCardSummarySchema>;
export function parseAccountsCardSummary(summary: Record<string, unknown>): AccountsCardSummary {
  return AccountsCardSummarySchema.parse(summary);
}

/** Bounded, disclosed-approximate counts (migration design decision 6) -- the `*Capped` flag is true when the underlying 200-row page itself came back full, meaning the true count may exceed what is shown. */
export const WarehouseInventoryCardSummarySchema = z.object({
  activeInventoryBalanceCount: z.number().int().nonnegative(),
  activeInventoryBalanceCountCapped: z.boolean(),
  openOutboundOrderCount: z.number().int().nonnegative(),
  openOutboundOrderCountCapped: z.boolean(),
});
export type WarehouseInventoryCardSummary = z.infer<typeof WarehouseInventoryCardSummarySchema>;
export function parseWarehouseInventoryCardSummary(summary: Record<string, unknown>): WarehouseInventoryCardSummary {
  return WarehouseInventoryCardSummarySchema.parse(summary);
}

/**
 * `ISS-2026-118`: the four cards that stopped being stubs. Each mirrors the bounded-count shape
 * the three original cards already use — a count plus its own `*Capped` flag, true when the
 * underlying 200-row page came back full and the real number may be higher.
 */
export const BookingsCardSummarySchema = z.object({
  openBookingRequestCount: z.number().int().nonnegative(),
  openBookingRequestCountCapped: z.boolean(),
});
export type BookingsCardSummary = z.infer<typeof BookingsCardSummarySchema>;
export function parseBookingsCardSummary(summary: Record<string, unknown>): BookingsCardSummary {
  return BookingsCardSummarySchema.parse(summary);
}

export const ShipmentsCardSummarySchema = z.object({
  activeShipmentCount: z.number().int().nonnegative(),
  activeShipmentCountCapped: z.boolean(),
});
export type ShipmentsCardSummary = z.infer<typeof ShipmentsCardSummarySchema>;
export function parseShipmentsCardSummary(summary: Record<string, unknown>): ShipmentsCardSummary {
  return ShipmentsCardSummarySchema.parse(summary);
}

export const InvoicesCardSummarySchema = z.object({
  issuedInvoiceCount: z.number().int().nonnegative(),
  issuedInvoiceCountCapped: z.boolean(),
});
export type InvoicesCardSummary = z.infer<typeof InvoicesCardSummarySchema>;
export function parseInvoicesCardSummary(summary: Record<string, unknown>): InvoicesCardSummary {
  return InvoicesCardSummarySchema.parse(summary);
}

/**
 * A COUNT, deliberately, and there is no amount field to add later without thought: receipts carry
 * per-row currencies, so a summed total would be true in none of them (`ISS-2026-136`'s own trap).
 */
export const PaymentsCardSummarySchema = z.object({
  unallocatedPaymentCount: z.number().int().nonnegative(),
  unallocatedPaymentCountCapped: z.boolean(),
});
export type PaymentsCardSummary = z.infer<typeof PaymentsCardSummarySchema>;
export function parsePaymentsCardSummary(summary: Record<string, unknown>): PaymentsCardSummary {
  return PaymentsCardSummarySchema.parse(summary);
}

export const TicketsCardSummarySchema = z.object({
  openTicketCount: z.number().int().nonnegative(),
  openTicketCountCapped: z.boolean(),
});
export type TicketsCardSummary = z.infer<typeof TicketsCardSummarySchema>;
export function parseTicketsCardSummary(summary: Record<string, unknown>): TicketsCardSummary {
  return TicketsCardSummarySchema.parse(summary);
}
