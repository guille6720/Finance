import { createClient } from "@/lib/supabase/server";
import { cookies } from "next/headers";
import { redirect } from "next/navigation";
import { ACTIVE_ORG_COOKIE } from "@/lib/authz/context";
import { resolveActiveOrganizationId } from "@/lib/authz/active-organization";
import { ORGANIZATION_MEMBERS_WITH_PROFILE_SELECT } from "@/lib/members/queries";
import { ROLE_LABELS, type MemberRole } from "@/config/features";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";

export default async function UsersPage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) redirect("/login");

  const cookieStore = await cookies();
  const activeOrgId = cookieStore.get(ACTIVE_ORG_COOKIE)?.value;

  const { data: myMemberships } = await supabase
    .from("organization_members")
    .select("organization_id, role")
    .eq("user_id", user.id)
    .eq("status", "active");

  const orgId = resolveActiveOrganizationId(
    (myMemberships ?? []).map((m) => m.organization_id),
    activeOrgId
  );

  if (!orgId) redirect("/onboarding");

  const { data: members, error: membersError } = await supabase
    .from("organization_members")
    .select(ORGANIZATION_MEMBERS_WITH_PROFILE_SELECT)
    .eq("organization_id", orgId)
    .order("created_at", { ascending: true });

  if (membersError) {
    console.error("[users] members query failed", { code: membersError.code });
  }

  return (
    <div className="space-y-6">
      <div>
        <h2 className="text-xl font-semibold">Usuarios</h2>
        <p className="text-sm text-muted-foreground">
          Miembros de la empresa. Las invitaciones por email se habilitan en una próxima iteración.
        </p>
      </div>
      <Card>
        <CardHeader>
          <CardTitle>Equipo</CardTitle>
          <CardDescription>
            Solo propietarios y administradores pueden cambiar roles (RLS + capa de autorización).
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-2">
          {membersError ? (
            <p className="text-sm text-danger" role="alert" data-testid="users-load-error">
              No se pudieron cargar los miembros de la empresa. Intentá de nuevo más tarde.
            </p>
          ) : null}
          {(membersError ? [] : members ?? []).map((m) => {
            const profile = m.profiles as unknown as {
              full_name: string;
              email: string;
            } | null;
            return (
              <div
                key={m.id}
                className="flex items-center justify-between gap-3 rounded-md border border-border px-3 py-2 text-sm"
              >
                <div>
                  <p className="font-medium">{profile?.full_name || "Usuario"}</p>
                  <p className="text-muted-foreground">{profile?.email}</p>
                </div>
                <div className="flex items-center gap-2">
                  <Badge tone="primary">
                    {ROLE_LABELS[m.role as MemberRole] ?? m.role}
                  </Badge>
                  <Badge tone={m.status === "active" ? "success" : "neutral"}>
                    {m.status}
                  </Badge>
                </div>
              </div>
            );
          })}
        </CardContent>
      </Card>
    </div>
  );
}
