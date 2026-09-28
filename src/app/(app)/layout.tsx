import { redirect } from "next/navigation";
import { cookies } from "next/headers";
import { createClient } from "@/lib/supabase/server";
import { AppShell } from "@/components/shell/app-shell";
import {
  ACTIVE_ORG_COOKIE,
  loadUserOrganizations,
  resolveActiveOrganizationId,
} from "@/lib/authz/active-organization";
import { getUxMode } from "@/lib/ui-mode/server";
import { isOrganizationProvisioned } from "@/lib/onboarding/provision";
import { SetupBanner } from "@/components/onboarding/setup-banner";

export default async function AppLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    redirect("/login");
  }

  const cookieStore = await cookies();
  const organizations = await loadUserOrganizations(supabase, user.id);
  const activeOrganizationId = resolveActiveOrganizationId(
    organizations.map((o) => o.id),
    cookieStore.get(ACTIVE_ORG_COOKIE)?.value
  );
  const activeOrg = organizations.find((o) => o.id === activeOrganizationId);

  const { data: profile } = await supabase
    .from("profiles")
    .select("full_name")
    .eq("id", user.id)
    .maybeSingle();

  const uxMode = await getUxMode();
  const needsSetup =
    activeOrg?.role === "owner" && activeOrganizationId
      ? (await isOrganizationProvisioned(supabase, activeOrganizationId)) === false
      : false;

  return (
    <AppShell
      companyName={activeOrg?.displayName}
      userName={profile?.full_name || user.email || ""}
      organizations={organizations}
      activeOrganizationId={activeOrganizationId}
      uxMode={uxMode}
    >
      {needsSetup ? <SetupBanner /> : null}
      {children}
    </AppShell>
  );
}
