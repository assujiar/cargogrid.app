import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { buildTooltipHtml } from "./chart-tooltip.ts";

describe("buildTooltipHtml", () => {
  test("escapes HTML-shaped content in the heading and row values", () => {
    const html = buildTooltipHtml({
      heading: "<img src=x onerror=alert(1)>",
      rows: [{ label: "Customer", value: "<script>alert(1)</script>" }],
    });
    assert.ok(!html.includes("<img"));
    assert.ok(!html.includes("<script>"));
    assert.ok(html.includes("&lt;img"));
    assert.ok(html.includes("&lt;script&gt;"));
  });

  test("renders a comparison line only when provided", () => {
    const withComparison = buildTooltipHtml({ heading: "June 2026", rows: [{ label: "Revenue", value: "Rp4,82 miliar", comparison: "vs May 2026  +8,4%" }] });
    assert.ok(withComparison.includes("vs May 2026"));

    const withoutComparison = buildTooltipHtml({ heading: "June 2026", rows: [{ label: "Revenue", value: "Rp4,82 miliar" }] });
    assert.ok(!withoutComparison.includes("vs "));
  });
});
