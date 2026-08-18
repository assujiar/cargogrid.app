import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseCustomerPortalDashboardCard,
  parseAccountsCardSummary,
  parseWarehouseInventoryCardSummary,
  parseTicketsCardSummary,
  DASHBOARD_CARD_KEYS,
  REAL_DASHBOARD_CARD_KEYS,
} from "./customer-portal-dashboard.ts";

describe("parseCustomerPortalDashboardCard", () => {
  test("maps a real, available card with a populated summary", () => {
    const card = parseCustomerPortalDashboardCard({
      card_key: "accounts",
      available: true,
      source_updated_at: "2026-08-16T00:00:00.000Z",
      degraded: false,
      summary: { activeAccountCount: 1, primaryAccountName: "Dash Co" },
      detail_path: "customer-portal",
    });
    assert.equal(card.cardKey, "accounts");
    assert.equal(card.available, true);
    assert.equal(card.degraded, false);
    assert.equal(card.detailPath, "customer-portal");
    assert.deepEqual(card.summary, { activeAccountCount: 1, primaryAccountName: "Dash Co" });
  });

  test("maps a stub card with no source/route", () => {
    const card = parseCustomerPortalDashboardCard({
      card_key: "bookings",
      available: false,
      source_updated_at: null,
      degraded: false,
      summary: {},
      detail_path: null,
    });
    assert.equal(card.available, false);
    assert.equal(card.sourceUpdatedAt, null);
    assert.equal(card.detailPath, null);
    assert.deepEqual(card.summary, {});
  });

  test("maps a degraded card -- available stays true with a safe empty summary", () => {
    const card = parseCustomerPortalDashboardCard({
      card_key: "tickets",
      available: true,
      source_updated_at: null,
      degraded: true,
      summary: { openTicketCount: 0, openTicketCountCapped: false },
      detail_path: "customer-tickets",
    });
    assert.equal(card.degraded, true);
    assert.equal(card.available, true);
  });

  test("defaults a missing summary to an empty object and a missing detail_path to null", () => {
    const card = parseCustomerPortalDashboardCard({
      card_key: "alerts",
      available: false,
      source_updated_at: null,
      degraded: false,
      summary: null,
      detail_path: undefined,
    });
    assert.deepEqual(card.summary, {});
    assert.equal(card.detailPath, null);
  });

  test("rejects an unrecognized card_key", () => {
    assert.throws(() =>
      parseCustomerPortalDashboardCard({
        card_key: "not_a_real_card",
        available: false,
        source_updated_at: null,
        degraded: false,
        summary: {},
        detail_path: null,
      }),
    );
  });
});

describe("card key sets", () => {
  test("DASHBOARD_CARD_KEYS has exactly 9 entries, REAL_DASHBOARD_CARD_KEYS exactly 3, and REAL is a subset of DASHBOARD", () => {
    assert.equal(DASHBOARD_CARD_KEYS.length, 9);
    assert.equal(REAL_DASHBOARD_CARD_KEYS.length, 3);
    for (const key of REAL_DASHBOARD_CARD_KEYS) {
      assert.ok((DASHBOARD_CARD_KEYS as readonly string[]).includes(key));
    }
  });
});

describe("per-card typed summary parsers", () => {
  test("parseAccountsCardSummary accepts a null primaryAccountName", () => {
    const summary = parseAccountsCardSummary({ activeAccountCount: 0, primaryAccountName: null });
    assert.equal(summary.activeAccountCount, 0);
    assert.equal(summary.primaryAccountName, null);
  });

  test("parseWarehouseInventoryCardSummary maps both halves and both Capped flags", () => {
    const summary = parseWarehouseInventoryCardSummary({
      activeInventoryBalanceCount: 3,
      activeInventoryBalanceCountCapped: false,
      openOutboundOrderCount: 200,
      openOutboundOrderCountCapped: true,
    });
    assert.equal(summary.openOutboundOrderCount, 200);
    assert.equal(summary.openOutboundOrderCountCapped, true);
  });

  test("parseTicketsCardSummary rejects a negative count", () => {
    assert.throws(() => parseTicketsCardSummary({ openTicketCount: -1, openTicketCountCapped: false }));
  });
});
