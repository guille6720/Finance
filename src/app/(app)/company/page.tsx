import { createClient } from "@/lib/supabase/server";
import { cookies } from "next/headers";
import { redirect } from "next/navigation";
import { ACTIVE_ORG_COOKIE } from "@/lib/authz/context";
import { ROLE_LABELS, type MemberRole } from "@/config/features";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { formatCuit } from "@/lib/validations/argentina";

export default async function CompanyPage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) redirect("/login");

  const cookieStore = await cookies();
  const activeOrgId = cookieStore.get(ACTIVE_ORG_COOKIE)?.value;

  const { data: membership } = await supabase
    .from("organization_members")
    .select("role, organization_id")
    .eq("user_id", user.id)
    .eq("status", "active")
    .order("created_at", { ascending: true })
    .limit(20);

  const orgId =
    membership?.find((m) => m.organization_id === activeOrgId)?.organization_id ??
    membership?.[0]?.organization_id;

  if (!orgId) redirect("/onboarding");

  const [{ data: org }, { data: fiscal }, { data: business }, { data: branches }] =
    await Promise.all([
      supabase.from("organizations").select("*").eq("id", orgId).single(),
      supabase
        .from("fiscal_profiles")
        .select("*, fiscal_conditions ( name_business )")
        .eq("organization_id", orgId)
        .maybeSingle(),
      supabase.from("business_profiles").select("*").eq("organization_id", orgId).maybeSingle(),
      supabase.from("branches").select("*").eq("organization_id", orgId),
    ]);

  const role = membership?.find((m) => m.organization_id === orgId)?.role as
    | MemberRole
    | undefined;

  return (
    <div className="space-y-6">
      <div>
        <h2 className="text-xl font-semibold">Empresa</h2>
        <p className="text-sm text-muted-foreground">
          Datos de tu negocio. Tu rol: {role ? ROLE_LABELS[role] : "—"}.
        </p>
      </div>

      <Card>
        <CardHeader>
          <CardTitle>{org?.legal_name}</CardTitle>
          <CardDescription>{org?.commercial_name || "Sin nombre comercial"}</CardDescription>
        </CardHeader>
        <CardContent className="grid gap-2 text-sm sm:grid-cols-2">
          <p>
            <span className="text-muted-foreground">CUIT:</span>{" "}
            {org?.cuit ? formatCuit(org.cuit) : "—"}
          </p>
          <p>
            <span className="text-muted-foreground">Provincia:</span> {org?.province || "—"}
          </p>
          <p>
            <span className="text-muted-foreground">Ciudad:</span> {org?.city || "—"}
          </p>
          <p>
            <span className="text-muted-foreground">Moneda:</span> {org?.base_currency}
          </p>
          <p>
            <span className="text-muted-foreground">Condición:</span>{" "}
            {(fiscal?.fiscal_conditions as unknown as { name_business?: string } | null)
              ?.name_business || "—"}
          </p>
          <p>
            <span className="text-muted-foreground">Domicilio fiscal:</span>{" "}
            {fiscal?.fiscal_address || "—"}
          </p>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>Sucursales</CardTitle>
        </CardHeader>
        <CardContent className="space-y-2 text-sm">
          {(branches ?? []).map((b) => (
            <div key={b.id} className="rounded-md border border-border px-3 py-2">
              {b.name}
              {b.is_main ? " · Principal" : ""}
            </div>
          ))}
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>Perfil del negocio</CardTitle>
          <CardDescription>Respuestas del alta inicial</CardDescription>
        </CardHeader>
        <CardContent className="grid gap-2 text-sm sm:grid-cols-2">
          <p>Tipo: {business?.business_type ?? "—"}</p>
          <p>Productos: {business?.sells_products ? "Sí" : "No"}</p>
          <p>Servicios: {business?.sells_services ? "Sí" : "No"}</p>
          <p>Inventario: {business?.manages_inventory ? "Sí" : "No"}</p>
          <p>Empleados: {business?.has_employees ? "Sí" : "No"}</p>
          <p>Multi-sucursal: {business?.has_multiple_branches ? "Sí" : "No"}</p>
        </CardContent>
      </Card>
    </div>
  );
}
