import { SkeletonTable } from "../../../../../../components/ui/skeleton.tsx";

export default function VendorBillMatchDetailLoading() {
  return <SkeletonTable rows={5} columns={6} label="Loading the match case…" />;
}
