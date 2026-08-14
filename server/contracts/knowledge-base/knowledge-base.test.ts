import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseKbArticleRow,
  parseKbArticleVersionSummaryRow,
  parseKbArticleVersionRow,
  parseKbArticleSearchRow,
  parseKbArticleDetailRow,
  parseKbTicketArticleLinkRow,
  parseKbTicketArticleLinkForRequesterRow,
  CreateKbArticleVersionInputSchema,
  LinkTicketKnowledgeArticleInputSchema,
} from "./knowledge-base.ts";

const ID_1 = "223e4567-e89b-12d3-a456-426614174000";
const ID_2 = "323e4567-e89b-12d3-a456-426614174000";
const ACTOR = "423e4567-e89b-12d3-a456-426614174000";

describe("KB article rows", () => {
  test("parseKbArticleRow carries a null current version for a genuinely versionless article", () => {
    const a = parseKbArticleRow({ id: ID_1, code: "printer-offline", current_status: null, current_version_id: null, current_version_number: null, title: null });
    assert.equal(a.currentStatus, null);
  });

  test("parseKbArticleVersionSummaryRow maps audience flags and review state", () => {
    const v = parseKbArticleVersionSummaryRow({
      id: ID_1, version_number: 1, status: "approved", title: "Printer offline", audience_internal: true, audience_customer: false,
      audience_helpdesk: false, reviewer_label: "Staff Two", review_decision: "approved", published_at: null, expires_at: null, record_version: 3,
    });
    assert.equal(v.status, "approved");
    assert.equal(v.audienceCustomer, false);
  });

  test("parseKbArticleVersionRow (full authoring row) carries review_notes/archived_reason -- the staff-only fields", () => {
    const v = parseKbArticleVersionRow({
      id: ID_1, article_id: ID_2, version_number: 1, status: "draft", title: "T", summary: null, body: "B", tags: ["a"],
      audience_internal: true, audience_customer: false, audience_helpdesk: false, reviewer_label: null, review_decision: null,
      review_notes: "add a screenshot", published_at: null, expires_at: null, archived_reason: null, record_version: 1,
    });
    assert.equal(v.reviewNotes, "add a screenshot");
  });

  test("parseKbArticleSearchRow (audience-safe search result) has NO body/reviewNotes fields at all -- structurally narrower", () => {
    const s = parseKbArticleSearchRow({ id: ID_1, article_id: ID_2, version_number: 1, title: "How to reset your password", summary: "self-service", tags: ["account"], published_at: "2026-01-01T00:00:00Z" });
    assert.equal((s as unknown as Record<string, unknown>).body, undefined);
    assert.equal((s as unknown as Record<string, unknown>).reviewNotes, undefined);
  });

  test("parseKbArticleDetailRow extends the search row with body only", () => {
    const d = parseKbArticleDetailRow({ id: ID_1, article_id: ID_2, version_number: 1, title: "T", summary: null, tags: [], published_at: null, body: "Click forgot password." });
    assert.equal(d.body, "Click forgot password.");
    assert.equal((d as unknown as Record<string, unknown>).reviewNotes, undefined);
  });

  test("parseKbTicketArticleLinkRow (staff) vs parseKbTicketArticleLinkForRequesterRow (customer-safe) differ in shape", () => {
    const staffLink = parseKbTicketArticleLinkRow({ id: ID_1, article_id: ID_2, article_version_id: ID_1, article_title: "T", visibility: "internal", note: "internal ref", linked_by: "staff1", linked_at: "2026-01-01T00:00:00Z", record_version: 1 });
    assert.equal(staffLink.visibility, "internal");
    assert.equal(staffLink.note, "internal ref");

    const requesterLink = parseKbTicketArticleLinkForRequesterRow({ id: ID_1, article_id: ID_2, article_version_id: ID_1, article_title: "T", article_summary: "s", linked_at: "2026-01-01T00:00:00Z" });
    assert.equal((requesterLink as unknown as Record<string, unknown>).visibility, undefined);
    assert.equal((requesterLink as unknown as Record<string, unknown>).note, undefined);
  });
});

describe("KB mutation inputs", () => {
  test("CreateKbArticleVersionInputSchema requires a non-empty title and body", () => {
    assert.throws(() =>
      CreateKbArticleVersionInputSchema.parse({ articleId: ID_1, title: "", summary: null, body: "b", tags: [], audienceInternal: true, audienceCustomer: false, audienceHelpdesk: false, actorAuthUserId: ACTOR, actorLabel: "staff1" })
    );
  });

  test("LinkTicketKnowledgeArticleInputSchema rejects a visibility value outside public/internal", () => {
    assert.throws(() =>
      LinkTicketKnowledgeArticleInputSchema.parse({ ticketId: ID_1, articleId: ID_2, visibility: "everyone", note: null, actorAuthUserId: ACTOR, actorLabel: "staff1" })
    );
  });

  test("LinkTicketKnowledgeArticleInputSchema accepts a null note", () => {
    const v = LinkTicketKnowledgeArticleInputSchema.parse({ ticketId: ID_1, articleId: ID_2, visibility: "public", note: null, actorAuthUserId: ACTOR, actorLabel: "staff1" });
    assert.equal(v.note, null);
  });
});
