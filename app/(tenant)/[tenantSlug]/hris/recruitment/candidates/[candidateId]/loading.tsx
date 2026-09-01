export default function CandidateDetailLoading() {
  return (
    <div className="flex flex-col gap-4" role="status" aria-label="Loading candidate">
      <div className="h-8 w-64 animate-pulse rounded bg-neutral-200" />
      <div className="h-24 animate-pulse rounded-md border border-neutral-200 bg-neutral-100" />
      <div className="h-72 animate-pulse rounded-md border border-neutral-200 bg-neutral-100" />
    </div>
  );
}
