import { createClient } from "@/lib/supabase/server";
import { cookies } from "next/headers";
import { redirect } from "next/navigation";
import { ACTIVE_ORG_COOKIE } from "@/lib/authz/context";
import {
  BUSINESS_TYPE_LABELS,
  ROLE_LABELS,
  type BusinessType,
  type MemberRole,
} from "@/config/features";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { LoadError } from "@/components/demo/module-ui";
import { formatCuit } from "@/lib/validations/argentina";

const NOT_LOADED = <span className="text-muted-foreground italic">Sin cargar</span>;

function yesNo(value: boolean | null | undefined) {
  return value ? "Sí" : "No";
}

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

  const [
    { data: org, error: orgError },
    { data: fiscal, error: fiscalError },
    { data: business, error: businessError },
    { data: branches, error: branchesError },
  ] = await Promise.all([
    supabase.from("organizations").select("*").eq("id", orgId).single(),
    supabase
      .from("fiscal_profiles")
      .select("*, fiscal_conditions ( name_business )")
      .eq("organization_id", orgId)
      .maybeSingle(),
    supabase.from("business_profiles").select("*").eq("organization_id", orgId).maybeSingle(),
    supabase.from("branches").select("*").eq("organization_id", orgId),
  ]);

  for (const [scope, error] of [
    ["organization", orgError],
    ["fiscal_profile", fiscalError],
    ["business_profile", businessError],
    ["branches", branchesError],
  ] as const) {
    if (error) console.error("[company] query failed", { scope, code: error.code });
  }

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
          <CardTitle>{org?.legal_name ?? "Datos de la empresa"}</CardTitle>
          {org ? (
            <CardDescription>{org.commercial_name || "Sin nombre comercial"}</CardDescription>
          ) : null}
        </CardHeader>
        <CardContent>
          {orgError || fiscalError || !org ? (
            <LoadError />
          ) : (
            <div className="grid gap-2 text-sm sm:grid-cols-2">
              <p>
                <span className="text-muted-foreground">CUIT:</span>{" "}
                {org.cuit ? formatCuit(org.cuit) : NOT_LOADED}
              </p>
              <p>
                <span className="text-muted-foreground">Provincia:</span>{" "}
                {org.province || NOT_LOADED}
              </p>
              <p>
                <span className="text-muted-foreground">Ciudad:</span> {org.city || NOT_LOADED}
              </p>
              <p>
                <span className="text-muted-foreground">Moneda:</span>{" "}
                {org.base_currency || NOT_LOADED}
              </p>
              <p>
                <span className="text-muted-foreground">Condición:</span>{" "}
                {(fiscal?.fiscal_conditions as unknown as { name_business?: string } | null)
                  ?.name_business || NOT_LOADED}
              </p>
              <p>
                <span className="text-muted-foreground">Domicilio fiscal:</span>{" "}
                {fiscal?.fiscal_address || NOT_LOADED}
              </p>
            </div>
          )}
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>Sucursales</CardTitle>
        </CardHeader>
        <CardContent className="space-y-2 text-sm">
          {branchesError ? (
            <LoadError />
          ) : (branches ?? []).length === 0 ? (
            <p className="text-muted-foreground">Todavía no hay sucursales cargadas.</p>
          ) : (
            (branches ?? []).map((b) => (
              <div key={b.id} className="rounded-md border border-border px-3 py-2">
                {b.name}
                {b.is_main ? " · Principal" : ""}
              </div>
            ))
          )}
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>Perfil del negocio</CardTitle>
          <CardDescription>Respuestas del alta inicial</CardDescription>
        </CardHeader>
        <CardContent className="text-sm">
          {businessError ? (
            <LoadError />
          ) : !business ? (
            <p className="text-muted-foreground" data-testid="business-profile-empty">
              Todavía no se completó el perfil del negocio.
            </p>
          ) : (
            <div className="grid gap-2 sm:grid-cols-2">
              <p>
                Tipo:{" "}
                {business.business_type
                  ? BUSINESS_TYPE_LABELS[business.business_type as BusinessType] ??
                    business.business_type
                  : NOT_LOADED}
              </p>
              <p>Productos: {yesNo(business.sells_products)}</p>
              <p>Servicios: {yesNo(business.sells_services)}</p>
              <p>Inventario: {yesNo(business.manages_inventory)}</p>
              <p>Empleados: {yesNo(business.has_employees)}</p>
              <p>Multi-sucursal: {yesNo(business.has_multiple_branches)}</p>
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
