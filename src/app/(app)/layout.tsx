import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { AppShell } from "@/components/shell/app-shell";
import { ACTIVE_ORG_COOKIE } from "@/lib/authz/context";
import { cookies } from "next/headers";

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
  const activeOrgId = cookieStore.get(ACTIVE_ORG_COOKIE)?.value;

  const { data: memberships } = await supabase
    .from("organization_members")
    .select("organization_id, organizations ( legal_name, commercial_name )")
    .eq("user_id", user.id)
    .eq("status", "active");

  const membership =
    memberships?.find((m) => m.organization_id === activeOrgId) ??
    memberships?.[0];

  const org = membership?.organizations as unknown as
    | { legal_name: string; commercial_name: string | null }
    | null
    | undefined;

  const { data: profile } = await supabase
    .from("profiles")
    .select("full_name")
    .eq("id", user.id)
    .maybeSingle();

  return (
    <AppShell
      companyName={org?.commercial_name || org?.legal_name}
      userName={profile?.full_name || user.email || ""}
    >
      {children}
    </AppShell>
  );
}
