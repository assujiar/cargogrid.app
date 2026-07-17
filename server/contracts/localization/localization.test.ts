import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  LocaleSchema,
  TerminologyOverridesSchema,
  parseTenantLocaleVersion,
  parseLocaleContext,
  parseCanonicalTerm,
} from "./localization.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const VERSION_ID = "323e4567-e89b-12d3-a456-426614174000";

const ROW = {
  id: VERSION_ID,
  tenant_id: TENANT_ID,
  version_number: 1,
  status: "draft",
  default_locale: "id",
  default_timezone: "Asia/Jakarta",
  default_currency: "IDR",
  terminology_overrides: {},
  effective_from: null,
  cloned_from_version_id: null,
  rollback_of_version_id: null,
  created_by: "tester",
  published_by: null,
  published_at: null,
  archived_at: null,
  archived_reason: null,
  record_version: 1,
  created_at: "2026-07-17T00:00:00.000Z",
  updated_at: "2026-07-17T00:00:00.000Z",
};

describe("LocaleSchema", () => {
  test("accepts id and en", () => {
    assert.equal(LocaleSchema.parse("id"), "id");
    assert.equal(LocaleSchema.parse("en"), "en");
  });

  test("rejects an unsupported locale", () => {
    assert.throws(() => LocaleSchema.parse("fr"));
  });
});

describe("TerminologyOverridesSchema", () => {
  test("accepts a plain-text label map", () => {
    const parsed = TerminologyOverridesSchema.parse({ "tenant_status.active": "Live" });
    assert.equal(parsed["tenant_status.active"], "Live");
  });

  test("rejects a label containing an angle bracket (no HTML/script injection)", () => {
    assert.throws(() => TerminologyOverridesSchema.parse({ "tenant_status.active": "<b>Live</b>" }));
  });

  test("rejects an empty label", () => {
    assert.throws(() => TerminologyOverridesSchema.parse({ "tenant_status.active": "" }));
  });
});

describe("parseTenantLocaleVersion", () => {
  test("maps a raw snake_case row to the camelCase contract shape", () => {
    const version = parseTenantLocaleVersion(ROW);
    assert.equal(version.defaultLocale, "id");
    assert.equal(version.defaultTimezone, "Asia/Jakarta");
    assert.equal(version.defaultCurrency, "IDR");
  });
});

describe("parseLocaleContext", () => {
  test("maps a raw resolver row (tenant source)", () => {
    const context = parseLocaleContext({
      tenant_id: TENANT_ID,
      source: "tenant",
      locale: "en",
      timezone: "UTC",
      currency: "USD",
      terminology_overrides: { "tenant_status.active": "Live" },
    });
    assert.equal(context.source, "tenant");
    assert.equal(context.locale, "en");
  });

  test("maps a raw resolver row (platform-default source)", () => {
    const context = parseLocaleContext({
      tenant_id: TENANT_ID,
      source: "default",
      locale: "id",
      timezone: "Asia/Jakarta",
      currency: "IDR",
      terminology_overrides: {},
    });
    assert.equal(context.source, "default");
  });
});

describe("parseCanonicalTerm", () => {
  test("maps a raw app.canonical_terms row", () => {
    const term = parseCanonicalTerm({
      code: "tenant_status.active",
      category: "tenant_status",
      default_label_en: "Active",
      default_label_id: "Aktif",
      created_at: "2026-07-17T00:00:00.000Z",
    });
    assert.equal(term.code, "tenant_status.active");
    assert.equal(term.defaultLabelId, "Aktif");
  });
});
