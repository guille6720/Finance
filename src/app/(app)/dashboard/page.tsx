import Link from "next/link";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { cookies } from "next/headers";
import { ACTIVE_ORG_COOKIE } from "@/lib/authz/context";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";

function completeness(parts: boolean[]) {
  const done = parts.filter(Boolean).length;
  return Math.round((done / parts.length) * 100);
}

export default async function DashboardPage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) redirect("/login");

  const cookieStore = await cookies();
  const activeOrgId = cookieStore.get(ACTIVE_ORG_COOKIE)?.value;

  const { data: memberships } = await supabase
    .from("organization_members")
    .select("organization_id")
    .eq("user_id", user.id)
    .eq("status", "active");

  if (!memberships?.length) {
    redirect("/onboarding");
  }

  const orgId =
    memberships.find((m) => m.organization_id === activeOrgId)?.organization_id ??
    memberships[0].organization_id;

  const [
    { data: org },
    { data: fiscal },
    { data: branch },
    { data: business },
    { count: memberCount },
  ] = await Promise.all([
    supabase.from("organizations").select("*").eq("id", orgId).maybeSingle(),
    supabase.from("fiscal_profiles").select("id, fiscal_condition_id, fiscal_address").eq("organization_id", orgId).maybeSingle(),
    supabase.from("branches").select("id").eq("organization_id", orgId).limit(1).maybeSingle(),
    supabase.from("business_profiles").select("id").eq("organization_id", orgId).maybeSingle(),
    supabase
      .from("organization_members")
      .select("id", { count: "exact", head: true })
      .eq("organization_id", orgId)
      .eq("status", "active"),
  ]);

  const checks = {
    fiscal: Boolean(fiscal?.fiscal_condition_id && fiscal?.fiscal_address),
    branch: Boolean(branch?.id),
    business: Boolean(business?.id),
    members: (memberCount ?? 0) > 1,
    orgActive: org?.status === "active",
  };

  const pct = completeness([
    checks.orgActive,
    checks.fiscal,
    checks.branch,
    checks.business,
    checks.members,
  ]);

  const actions = [
    {
      done: checks.fiscal,
      title: "Completar datos fiscales",
      href: "/company",
      hint: "CUIT, condición y domicilio",
    },
    {
      done: checks.branch,
      title: "Configurar sucursal",
      href: "/company",
      hint: "Casa central u otras sedes",
    },
    {
      done: checks.members,
      title: "Invitar usuario",
      href: "/users",
      hint: "Sumá a tu equipo o contador",
    },
    {
      done: checks.business,
      title: "Configurar perfil del negocio",
      href: "/company",
      hint: "Qué vendés y qué necesitás",
    },
  ];

  return (
    <div className="space-y-6">
      <div>
        <h2 className="text-xl font-semibold tracking-tight">
          Hola{org?.commercial_name || org?.legal_name ? `, ${org.commercial_name || org.legal_name}` : ""}
        </h2>
        <p className="mt-1 text-sm text-muted-foreground">
          Todavía no hay movimientos. Completá la configuración para empezar con buen pie.
        </p>
      </div>

      <Card>
        <CardHeader>
          <div className="flex flex-wrap items-center gap-2">
            <CardTitle>Tu empresa está lista al {pct}%</CardTitle>
            <Badge tone={pct >= 80 ? "success" : "warning"}>
              {pct >= 80 ? "Casi lista" : "En configuración"}
            </Badge>
          </div>
          <CardDescription>
            No inventamos números de ventas ni saldos. Cuando haya movimientos reales, van a aparecer acá.
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="h-2 overflow-hidden rounded-full bg-muted" role="progressbar" aria-valuenow={pct} aria-valuemin={0} aria-valuemax={100}>
            <div className="h-full bg-primary transition-all" style={{ width: `${pct}%` }} />
          </div>
          <ul className="grid gap-3 sm:grid-cols-2">
            {actions.map((a) => (
              <li
                key={a.title}
                className="flex items-start justify-between gap-3 rounded-md border border-border bg-surface-elevated p-3"
              >
                <div>
                  <p className="text-sm font-medium">
                    {a.done ? "✓ " : ""}
                    {a.title}
                  </p>
                  <p className="text-xs text-muted-foreground">{a.hint}</p>
                </div>
                {!a.done ? (
                  <Button asChild size="sm" variant="outline">
                    <Link href={a.href}>Ir</Link>
                  </Button>
                ) : (
                  <Badge tone="success">Listo</Badge>
                )}
              </li>
            ))}
          </ul>
        </CardContent>
      </Card>

      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
        {[
          "Ventas del mes",
          "Gastos del mes",
          "Resultado estimado",
          "Disponible",
          "Clientes que me deben",
          "Proveedores a pagar",
        ].map((label) => (
          <Card key={label} className="opacity-90">
            <CardHeader className="pb-2">
              <CardDescription>{label}</CardDescription>
              <CardTitle className="text-base text-muted-foreground">Sin datos aún</CardTitle>
            </CardHeader>
            <CardContent>
              <p className="text-xs text-muted-foreground">
                Disponible cuando el módulo correspondiente esté activo.
              </p>
            </CardContent>
          </Card>
        ))}
      </div>
    </div>
  );
}
