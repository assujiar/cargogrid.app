/** Shared between showcase-nav.tsx's search results and components/page.tsx's anchor ids, so a search hit always scrolls to the right card. */
export function slugifyComponentName(name: string): string {
  return name
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/(^-|-$)/g, "");
}
