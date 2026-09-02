"use client";

import { useActionState } from "react";
import NextLink from "next/link";
import { Button } from "../../../../components/ui/button.tsx";
import { Input } from "../../../../components/forms/input.tsx";
import { SearchInput } from "../../../../components/forms/search-input.tsx";
import { FormField } from "../../../../components/forms/form-field.tsx";
import { ValidationMessage } from "../../../../components/forms/validation-message.tsx";
import { StatusBadge, type StatusTone } from "../../../../components/ui/status-badge.tsx";
import type { KbActionState } from "./actions.ts";
import type { KbArticleRow, KbArticleSearchRow, KbArticleStatus } from "../../../../server/contracts/knowledge-base/knowledge-base.ts";

const INITIAL_STATE: KbActionState = { error: null };

const STATUS_TONE: Record<KbArticleStatus, StatusTone> = {
  draft: "neutral",
  in_review: "warning",
  approved: "info",
  published: "success",
  archived: "neutral",
};

function CreateArticleForm({ createArticleAction }: { createArticleAction: (prevState: KbActionState, formData: FormData) => Promise<KbActionState> }) {
  const [state, formAction, pending] = useActionState(createArticleAction, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-wrap items-end gap-2 rounded-md border border-neutral-200 p-3">
      <FormField id="kb-new-article-code" label="Code (lowercase-with-dashes)">
        <Input
          id="kb-new-article-code"
          name="code"
          required
          pattern="[a-z0-9-]{2,80}"
          placeholder="printer-offline"
          className="min-w-[14rem]"
          invalid={Boolean(state.error)}
          aria-describedby={state.error ? "kb-create-article-error" : undefined}
        />
      </FormField>
      <Button type="submit" variant="primary" loading={pending} loadingLabel="Creating…">
        New article
      </Button>
      {state.error ? (
        <div className="w-full">
          <ValidationMessage id="kb-create-article-error">{state.error}</ValidationMessage>
        </div>
      ) : null}
    </form>
  );
}

export function KbListPanel({
  tenantSlug,
  articles,
  query,
  searchResults,
  createArticleAction,
}: {
  tenantSlug: string;
  articles: readonly KbArticleRow[];
  query: string;
  searchResults: readonly KbArticleSearchRow[];
  createArticleAction: (prevState: KbActionState, formData: FormData) => Promise<KbActionState>;
}) {
  return (
    <div className="flex flex-col gap-4">
      <form method="get" className="flex items-center gap-2">
        <div className="min-w-[16rem] flex-1">
          <FormField id="kb-search" label={<span className="sr-only">Search published articles</span>}>
            <SearchInput id="kb-search" name="q" defaultValue={query} placeholder="Search published articles…" />
          </FormField>
        </div>
        <Button type="submit" variant="secondary">
          Search
        </Button>
      </form>

      {query.trim().length > 0 ? (
        <section className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
          <h2 className="text-sm font-semibold text-neutral-900">Search results for &quot;{query}&quot;</h2>
          {searchResults.length === 0 ? (
            <p className="text-xs text-neutral-500">No published articles matched.</p>
          ) : (
            <ul className="flex flex-col gap-1">
              {searchResults.map((r) => (
                <li key={r.id}>
                  <NextLink href={`/${tenantSlug}/knowledge-base/${r.articleId}`} className="text-sm text-info hover:underline">
                    {r.title}
                  </NextLink>
                  {r.summary ? <p className="text-xs text-neutral-500">{r.summary}</p> : null}
                </li>
              ))}
            </ul>
          )}
        </section>
      ) : null}

      <CreateArticleForm createArticleAction={createArticleAction} />

      <section className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">All articles</h2>
        {articles.length === 0 ? (
          <p className="text-xs text-neutral-500">No articles yet.</p>
        ) : (
          <ul className="flex flex-col gap-1">
            {articles.map((a) => (
              <li key={a.id} className="flex flex-wrap items-center gap-2 text-sm">
                <NextLink href={`/${tenantSlug}/knowledge-base/${a.id}`} className="text-info hover:underline">
                  {a.title ?? a.code}
                </NextLink>
                <span className="font-mono text-xs text-neutral-400">{a.code}</span>
                {a.currentStatus ? <StatusBadge tone={STATUS_TONE[a.currentStatus]} label={a.currentStatus.replace(/_/g, " ")} /> : <span className="text-xs text-neutral-400">no version yet</span>}
              </li>
            ))}
          </ul>
        )}
      </section>
    </div>
  );
}
