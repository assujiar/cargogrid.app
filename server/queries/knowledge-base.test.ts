import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  listKbArticles,
  listKbArticleVersions,
  getKbArticleForStaff,
  searchKnowledgeArticles,
  searchCustomerKnowledgeArticles,
  searchHelpdeskKnowledgeArticles,
  getKbArticleForCustomer,
  getKbArticleForHelpdesk,
  listTicketKnowledgeArticleLinks,
  listTicketKnowledgeArticleLinksForRequester,
  KbQueryError,
  type KbQueryClient,
} from "./knowledge-base.ts";

const TENANT_ID = "123e4567-e89b-12d3-a456-426614174000";
const ID_1 = "223e4567-e89b-12d3-a456-426614174000";
const ID_2 = "323e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "423e4567-e89b-12d3-a456-426614174000";

function fakeClient(response: { data: unknown; error: { message: string } | null }): { client: KbQueryClient; calls: { fn: string; args: Record<string, unknown> }[] } {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as KbQueryClient;
  return { client, calls };
}

describe("listKbArticles / listKbArticleVersions / getKbArticleForStaff", () => {
  test("listKbArticles passes tenant/actor through", async () => {
    const { client, calls } = fakeClient({ data: [{ id: ID_1, code: "printer-offline", current_status: "published", current_version_id: ID_2, current_version_number: 1, title: "Printer offline" }], error: null });
    const result = await listKbArticles(client, TENANT_ID, ACTOR_ID);
    assert.deepEqual(calls[0]?.args, { p_tenant_id: TENANT_ID, p_actor_auth_user_id: ACTOR_ID });
    assert.equal(result[0]?.code, "printer-offline");
  });

  test("listKbArticleVersions throws KbQueryError on RPC error", async () => {
    const { client } = fakeClient({ data: null, error: { message: "boom" } });
    await assert.rejects(() => listKbArticleVersions(client, ID_1, ACTOR_ID), KbQueryError);
  });

  test("getKbArticleForStaff returns null when the RPC returns null (non-member caller)", async () => {
    const { client } = fakeClient({ data: null, error: null });
    const result = await getKbArticleForStaff(client, ID_1, ACTOR_ID);
    assert.equal(result, null);
  });
});

describe("audience-safe search/get -- each function calls its OWN distinct RPC, never a shared one a caller could misuse across audiences", () => {
  test("searchKnowledgeArticles (staff/internal) calls search_knowledge_articles", async () => {
    const { client, calls } = fakeClient({ data: [], error: null });
    await searchKnowledgeArticles(client, TENANT_ID, ACTOR_ID, { query: "printer" });
    assert.equal(calls[0]?.fn, "search_knowledge_articles");
    assert.equal(calls[0]?.args.p_query, "printer");
  });

  test("searchCustomerKnowledgeArticles requires and forwards a customerAccountId", async () => {
    const { client, calls } = fakeClient({ data: [], error: null });
    await searchCustomerKnowledgeArticles(client, TENANT_ID, ACTOR_ID, ID_2);
    assert.equal(calls[0]?.fn, "search_customer_knowledge_articles");
    assert.equal(calls[0]?.args.p_account_id, ID_2);
  });

  test("searchHelpdeskKnowledgeArticles calls the distinct helpdesk-audience RPC", async () => {
    const { client, calls } = fakeClient({ data: [], error: null });
    await searchHelpdeskKnowledgeArticles(client, TENANT_ID, ACTOR_ID);
    assert.equal(calls[0]?.fn, "search_helpdesk_knowledge_articles");
  });

  test("getKbArticleForCustomer returns null on zero rows (not audience-permitted or not found)", async () => {
    const { client } = fakeClient({ data: [], error: null });
    const result = await getKbArticleForCustomer(client, ID_1, ACTOR_ID, TENANT_ID, ID_2);
    assert.equal(result, null);
  });

  test("getKbArticleForHelpdesk returns null on zero rows", async () => {
    const { client } = fakeClient({ data: [], error: null });
    const result = await getKbArticleForHelpdesk(client, ID_1, ACTOR_ID, TENANT_ID);
    assert.equal(result, null);
  });
});

describe("ticket-article link listings", () => {
  test("listTicketKnowledgeArticleLinks (staff) parses visibility/note", async () => {
    const { client } = fakeClient({ data: [{ id: ID_1, article_id: ID_2, article_version_id: ID_1, article_title: "T", visibility: "internal", note: "n", linked_by: "staff1", linked_at: "2026-01-01T00:00:00Z", record_version: 1 }], error: null });
    const result = await listTicketKnowledgeArticleLinks(client, ID_1, ACTOR_ID);
    assert.equal(result[0]?.visibility, "internal");
  });

  test("listTicketKnowledgeArticleLinksForRequester calls the distinct requester-safe RPC", async () => {
    const { client, calls } = fakeClient({ data: [], error: null });
    await listTicketKnowledgeArticleLinksForRequester(client, ID_1, ACTOR_ID);
    assert.equal(calls[0]?.fn, "list_ticket_knowledge_article_links_for_requester");
  });
});
