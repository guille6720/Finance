import Link from "next/link";
import { Plus } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import {
  LoadError,
  ModuleHeader,
  ModuleTable,
  StatCard,
  StatGrid,
} from "@/components/demo/module-ui";
import { roleHasPermission } from "@/lib/authz/permissions";
import { requireActiveOrganization } from "@/lib/demo-data/organization-context";
import {
  loadCounterparties,
  type CounterpartyRole,
  type CounterpartyRow,
} from "@/lib/demo-data/loaders";
import { activeLabel, counterpartyDisplayName, formatCount } from "@/lib/demo-data/format";

const COPY: Record<
  CounterpartyRole,
  {
    title: string;
    description: string;
    total: string;
    withDocuments: string;
    withDocumentsHint: string;
    column: string;
    tableTitle: string;
    empty: string;
    newLabel: string;
    newHref: string;
    created: string;
    updated: string;
  }
> = {
  CUSTOMER: {
    title: "Clientes",
    description: "Clientes registrados para la empresa activa.",
    total: "Total clientes",
    withDocuments: "Clientes con ventas",
    withDocumentsHint: "Con al menos un documento de venta registrado.",
    column: "Cliente",
    tableTitle: "Listado de clientes",
    empty: "Todavía no hay clientes registrados para esta empresa.",
    newLabel: "Nuevo cliente",
    newHref: "/customers/new",
    created: "Cliente creado correctamente.",
    updated: "Ya existía con ese documento: se lo marcó también como cliente.",
  },
  SUPPLIER: {
    title: "Proveedores",
    description: "Proveedores registrados para la empresa activa.",
    total: "Total proveedores",
    withDocuments: "Proveedores con compras",
    withDocumentsHint: "Con al menos un comprobante de compra registrado.",
    column: "Proveedor",
    tableTitle: "Listado de proveedores",
    empty: "Todavía no hay proveedores registrados para esta empresa.",
    newLabel: "Nuevo proveedor",
    newHref: "/suppliers/new",
    created: "Proveedor creado correctamente.",
    updated: "Ya existía con ese documento: se lo marcó también como proveedor.",
  },
};

export type CounterpartyNotice = "created" | "updated" | null;

export async function CounterpartyPage({
  role,
  notice = null,
}: {
  role: CounterpartyRole;
  notice?: CounterpartyNotice;
}) {
  const copy = COPY[role];
  const { supabase, organizationId, role: memberRole } = await requireActiveOrganization();
  const canCreate = roleHasPermission(memberRole, "counterparties.create");
  const result = await loadCounterparties(supabase, organizationId, role);

  return (
    <div className="space-y-6">
      <ModuleHeader
        title={copy.title}
        description={copy.description}
        action={
          canCreate ? (
            <Button asChild data-testid="counterparty-new">
              <Link href={copy.newHref}>
                <Plus className="h-4 w-4" aria-hidden />
                {copy.newLabel}
              </Link>
            </Button>
          ) : null
        }
      />
      {notice ? (
        <p
          role="status"
          data-testid="counterparty-notice"
          className="rounded-md border border-success/30 bg-success/10 p-3 text-sm text-success"
        >
          {notice === "created" ? copy.created : copy.updated}
        </p>
      ) : null}
      {!result.ok ? (
        <LoadError />
      ) : (
        <>
          <StatGrid>
            <StatCard label={copy.total} value={formatCount(result.data.total)} testId="stat-total" />
            <StatCard label="Activos" value={formatCount(result.data.active)} testId="stat-active" />
            <StatCard
              label={copy.withDocuments}
              value={formatCount(result.data.withDocuments)}
              hint={copy.withDocumentsHint}
              testId="stat-with-documents"
            />
          </StatGrid>
          <Card>
            <CardHeader>
              <CardTitle>{copy.tableTitle}</CardTitle>
              <CardDescription>Datos de la empresa activa.</CardDescription>
            </CardHeader>
            <CardContent>
              <ModuleTable<CounterpartyRow>
                caption={copy.tableTitle}
                data={result.data.counterparties}
                rowKey={(r) => r.id}
                emptyMessage={copy.empty}
                columns={[
                  {
                    key: "name",
                    label: copy.column,
                    render: (r) => (
                      <div>
                        <p className="font-medium">{counterpartyDisplayName(r)}</p>
                        {r.trade_name?.trim() && r.trade_name.trim() !== r.legal_name ? (
                          <p className="text-xs text-muted-foreground">{r.legal_name}</p>
                        ) : null}
                      </div>
                    ),
                  },
                  { key: "tax", label: "CUIT/DNI", render: (r) => r.tax_id || "—" },
                  { key: "email", label: "Email", render: (r) => r.email || "—" },
                  { key: "phone", label: "Teléfono", render: (r) => r.phone || "—" },
                  {
                    key: "status",
                    label: "Estado",
                    render: (r) => {
                      const s = activeLabel(r.is_active);
                      return <Badge tone={s.tone}>{s.label}</Badge>;
                    },
                  },
                ]}
              />
            </CardContent>
          </Card>
        </>
      )}
    </div>
  );
}
