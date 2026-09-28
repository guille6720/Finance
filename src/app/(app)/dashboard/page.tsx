import Link from "next/link";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { LoadError } from "@/components/demo/module-ui";
import { requireActiveOrganization } from "@/lib/demo-data/organization-context";
import { logQueryFailure, type QueryResult } from "@/lib/demo-data/query";
import {
  countCounterpartiesByRole,
  countPostedJournalEntries,
  loadConfirmedSales,
  loadPostedPurchases,
  loadPostedTreasuryVolume,
} from "@/lib/demo-data/loaders";
import { formatARS, formatCount } from "@/lib/demo-data/format";

function completeness(parts: boolean[]) {
  const done = parts.filter(Boolean).length;
  return Math.round((done / parts.length) * 100);
}

function MetricCard<T>({
  label,
  result,
  value,
  hint,
  href,
  testId,
}: {
  label: string;
  result: QueryResult<T>;
  value: (data: T) => string;
  hint: (data: T) => string;
  href: string;
  testId: string;
}) {
  return (
    <Card data-testid={testId}>
      <CardHeader className="pb-2">
        <CardDescription>{label}</CardDescription>
        {result.ok ? (
          <CardTitle className="text-2xl tabular-nums">{value(result.data)}</CardTitle>
        ) : null}
      </CardHeader>
      <CardContent className="space-y-2">
        {result.ok ? (
          <p className="text-xs text-muted-foreground">{hint(result.data)}</p>
        ) : (
          <LoadError />
        )}
        <Link href={href} className="text-xs font-medium text-primary-bright hover:underline">
          Ver detalle
        </Link>
      </CardContent>
    </Card>
  );
}

export default async function DashboardPage() {
  const { supabase, organizationId: orgId } = await requireActiveOrganization();

  const [
    orgRes,
    fiscalRes,
    branchRes,
    businessRes,
    memberCountRes,
    sales,
    purchases,
    treasury,
    postedEntries,
    customers,
    suppliers,
  ] = await Promise.all([
    supabase
      .from("organizations")
      .select("id, legal_name, commercial_name, status")
      .eq("id", orgId)
      .maybeSingle(),
    supabase
      .from("fiscal_profiles")
      .select("id, fiscal_condition_id, fiscal_address")
      .eq("organization_id", orgId)
      .maybeSingle(),
    supabase.from("branches").select("id").eq("organization_id", orgId).limit(1).maybeSingle(),
    supabase.from("business_profiles").select("id").eq("organization_id", orgId).maybeSingle(),
    supabase
      .from("organization_members")
      .select("id", { count: "exact", head: true })
      .eq("organization_id", orgId)
      .eq("status", "active"),
    loadConfirmedSales(supabase, orgId),
    loadPostedPurchases(supabase, orgId),
    loadPostedTreasuryVolume(supabase, orgId),
    countPostedJournalEntries(supabase, orgId),
    countCounterpartiesByRole(supabase, orgId, "CUSTOMER"),
    countCounterpartiesByRole(supabase, orgId, "SUPPLIER"),
  ]);

  const setupErrors = [
    ["organizations", orgRes.error],
    ["fiscal_profiles", fiscalRes.error],
    ["branches", branchRes.error],
    ["business_profiles", businessRes.error],
    ["organization_members.count", memberCountRes.error],
  ] as const;
  for (const [label, error] of setupErrors) {
    if (error) logQueryFailure(`dashboard.${label}`, error);
  }
  const setupFailed = setupErrors.some(([, error]) => Boolean(error));

  const org = orgRes.data;
  const fiscal = fiscalRes.data;
  const checks = {
    fiscal: Boolean(fiscal?.fiscal_condition_id && fiscal?.fiscal_address),
    branch: Boolean(branchRes.data?.id),
    business: Boolean(businessRes.data?.id),
    members: (memberCountRes.count ?? 0) > 1,
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

  const hasActivity =
    (sales.ok && sales.data.count > 0) ||
    (purchases.ok && purchases.data.count > 0) ||
    (treasury.ok && treasury.data.count > 0) ||
    (postedEntries.ok && postedEntries.data > 0);

  return (
    <div className="space-y-6">
      <div>
        <h2 className="text-xl font-semibold tracking-tight">
          Hola{org?.commercial_name || org?.legal_name ? `, ${org.commercial_name || org.legal_name}` : ""}
        </h2>
        <p className="mt-1 text-sm text-muted-foreground">
          {hasActivity
            ? "Resumen de la actividad registrada para la empresa activa."
            : "Todavía no hay movimientos. Completá la configuración para empezar con buen pie."}
        </p>
      </div>

      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
        <MetricCard
          label="Ventas"
          result={sales}
          value={(d) => formatARS(d.amount)}
          hint={(d) => `${formatCount(d.count)} pedidos de venta confirmados.`}
          href="/reports"
          testId="metric-sales"
        />
        <MetricCard
          label="Compras / gastos"
          result={purchases}
          value={(d) => formatARS(d.amount)}
          hint={(d) => `${formatCount(d.count)} comprobantes de compra contabilizados.`}
          href="/suppliers"
          testId="metric-purchases"
        />
        <MetricCard
          label="Movimientos de tesorería"
          result={treasury}
          value={(d) => formatCount(d.count)}
          hint={(d) => `Volumen contabilizado: ${formatARS(d.amount)} (no es saldo disponible).`}
          href="/cash"
          testId="metric-treasury"
        />
        <MetricCard
          label="Asientos contabilizados"
          result={postedEntries}
          value={(n) => formatCount(n)}
          hint={() => "Asientos contabilizados en el libro diario."}
          href="/accounting"
          testId="metric-journal"
        />
        <MetricCard
          label="Clientes"
          result={customers}
          value={(n) => formatCount(n)}
          hint={() => "Clientes registrados."}
          href="/customers"
          testId="metric-customers"
        />
        <MetricCard
          label="Proveedores"
          result={suppliers}
          value={(n) => formatCount(n)}
          hint={() => "Proveedores registrados."}
          href="/suppliers"
          testId="metric-suppliers"
        />
      </div>

      <Card>
        <CardHeader>
          <div className="flex flex-wrap items-center gap-2">
            <CardTitle>Tu empresa está lista al {setupFailed ? "—" : `${pct}%`}</CardTitle>
            {!setupFailed ? (
              <Badge tone={pct >= 80 ? "success" : "warning"}>
                {pct >= 80 ? "Casi lista" : "En configuración"}
              </Badge>
            ) : null}
          </div>
          <CardDescription>Pasos de configuración de la empresa activa.</CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          {setupFailed ? (
            <LoadError />
          ) : (
            <>
              <div
                className="h-2 overflow-hidden rounded-full bg-muted"
                role="progressbar"
                aria-valuenow={pct}
                aria-valuemin={0}
                aria-valuemax={100}
              >
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
            </>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
