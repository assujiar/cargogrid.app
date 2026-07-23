import { redirect } from "next/navigation";

/** No public marketing page is in this checkpoint's scope (PLT-135 §11) -- the root path's only job is to route an unauthenticated visitor to sign-in. */
export default function RootPage() {
  redirect("/login");
}
