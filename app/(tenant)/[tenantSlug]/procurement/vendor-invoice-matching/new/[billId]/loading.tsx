import { SkeletonTable } from "../../../../../../../components/ui/skeleton.tsx";

export default function NewVendorBillMatchLoading() {
  return <SkeletonTable rows={4} columns={7} label="Loading the bill's lines…" />;
}
