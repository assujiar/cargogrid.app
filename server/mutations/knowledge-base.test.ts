import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  createKbArticle,
  createKbArticleVersion,
  submitKbArticleVersionForReview,
  reviewKbArticleVersion,
  publishKbArticleVersion,
  archiveKbArticleVersion,
  expireKbArticleVersionsBatch,
  linkTicketKnowledgeArticle,
  unlinkTicketKnowledgeArticle,
  KbMutationError,
  type KbMutationRpcClient,
} from "./knowledge-base.ts";

const TENANT_ID = "123e4567-e89b-12d3-a456-426614174000";
const ID_1 = "223e4567-e89b-12d3-a456-426614174000";
const ID_2 = "323e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "423e4567-e89b-12d3-a456-426614174000";

function fakeClient(response: { data: unknown; error: { message: string } | null }): { client: KbMutationRpcClient; calls: { fn: string; args: Record<string, unknown> }[] } {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as KbMutationRpcClient;
  return { client, calls };
}

describe("authoring lifecycle wrappers", () => {
  test("createKbArticle / createKbArticleVersion forward audience flags", async () => {
    const { client, calls } = fakeClient({ data: {}, error: null });
    await createKbArticle(client, { tenantId: TENANT_ID, code: "printer-offline", actorAuthUserId: ACTOR_ID, actorLabel: "staff1" });
    await createKbArticleVersion(client, {
      articleId: ID_1, title: "Printer offline", summary: null, body: "Restart the spooler.", tags: ["printer"],
      audienceInternal: true, audienceCustomer: false, audienceHelpdesk: false, actorAuthUserId: ACTOR_ID, actorLabel: "staff1",
    });
    assert.equal(calls[1]?.args.p_audience_internal, true);
    assert.equal(calls[1]?.args.p_audience_customer, false);
  });

  test("submitKbArticleVersionForReview classifies self_review_forbidden distinctly", async () => {
    const { client } = fakeClient({ data: null, error: { message: "self_review_forbidden: the author (X) may not review their own article version" } });
    await assert.rejects(
      () => submitKbArticleVersionForReview(client, { versionId: ID_1, expectedVersion: 1, reviewerAuthUserId: ACTOR_ID, actorAuthUserId: ACTOR_ID, actorLabel: "staff1" }),
      (err: unknown) => {
        assert.ok(err instanceof KbMutationError);
        assert.equal(err.code, "self_review_forbidden");
        return true;
      },
    );
  });

  test("reviewKbArticleVersion forwards decision/notes", async () => {
    const { client, calls } = fakeClient({ data: {}, error: null });
    await reviewKbArticleVersion(client, { versionId: ID_1, expectedVersion: 2, decision: "changes_requested", notes: "add a screenshot", actorAuthUserId: ACTOR_ID, actorLabel: "staff2" });
    assert.equal(calls[0]?.args.p_decision, "changes_requested");
    assert.equal(calls[0]?.args.p_notes, "add a screenshot");
  });

  test("publishKbArticleVersion classifies invalid_state distinctly (publish-requires-approved, no bypass)", async () => {
    const { client } = fakeClient({ data: null, error: { message: "invalid_state: article version X is draft not approved -- publish requires a reviewer approval first" } });
    await assert.rejects(
      () => publishKbArticleVersion(client, { versionId: ID_1, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "staff1" }),
      (err: unknown) => {
        assert.ok(err instanceof KbMutationError);
        assert.equal(err.code, "invalid_state");
        return true;
      },
    );
  });

  test("archiveKbArticleVersion requires and forwards a reason", async () => {
    const { client, calls } = fakeClient({ data: {}, error: null });
    await archiveKbArticleVersion(client, { versionId: ID_1, expectedVersion: 3, reason: "superseded", actorAuthUserId: ACTOR_ID, actorLabel: "staff1" });
    assert.equal(calls[0]?.args.p_reason, "superseded");
  });

  test("expireKbArticleVersionsBatch forwards period_label -- the job-level idempotency key", async () => {
    const { client, calls } = fakeClient({ data: { expired_count: 1, job_id: ID_1 }, error: null });
    await expireKbArticleVersionsBatch(client, { tenantId: TENANT_ID, asOf: null, periodLabel: "kb-expiry-2026-08-14", actorAuthUserId: ACTOR_ID, actorLabel: "staff1" });
    assert.equal(calls[0]?.args.p_period_label, "kb-expiry-2026-08-14");
  });
});

describe("ticket-article linking wrappers", () => {
  test("linkTicketKnowledgeArticle classifies article_not_audience_permitted distinctly", async () => {
    const { client } = fakeClient({ data: null, error: { message: "article_not_audience_permitted: article version X is not audience-permitted for a public link on a customer ticket" } });
    await assert.rejects(
      () => linkTicketKnowledgeArticle(client, { ticketId: ID_1, articleId: ID_2, visibility: "public", note: null, actorAuthUserId: ACTOR_ID, actorLabel: "staff1" }),
      (err: unknown) => {
        assert.ok(err instanceof KbMutationError);
        assert.equal(err.code, "article_not_audience_permitted");
        return true;
      },
    );
  });

  test("linkTicketKnowledgeArticle classifies kb_article_already_linked distinctly", async () => {
    const { client } = fakeClient({ data: null, error: { message: "kb_article_already_linked: article X is already linked to ticket Y" } });
    await assert.rejects(
      () => linkTicketKnowledgeArticle(client, { ticketId: ID_1, articleId: ID_2, visibility: "internal", note: null, actorAuthUserId: ACTOR_ID, actorLabel: "staff1" }),
      (err: unknown) => {
        assert.ok(err instanceof KbMutationError);
        assert.equal(err.code, "kb_article_already_linked");
        return true;
      },
    );
  });

  test("unlinkTicketKnowledgeArticle forwards linkId/expectedVersion", async () => {
    const { client, calls } = fakeClient({ data: {}, error: null });
    await unlinkTicketKnowledgeArticle(client, { linkId: ID_1, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "staff1" });
    assert.equal(calls[0]?.fn, "unlink_ticket_knowledge_article");
    assert.equal(calls[0]?.args.p_link_id, ID_1);
  });

  test("an unrecognized error message classifies as mutation_failed, never a false-positive known code", async () => {
    const { client } = fakeClient({ data: null, error: { message: "unexpected_pg_error: connection reset" } });
    await assert.rejects(
      () => linkTicketKnowledgeArticle(client, { ticketId: ID_1, articleId: ID_2, visibility: "internal", note: null, actorAuthUserId: ACTOR_ID, actorLabel: "staff1" }),
      (err: unknown) => {
        assert.ok(err instanceof KbMutationError);
        assert.equal(err.code, "mutation_failed");
        return true;
      },
    );
  });
});
