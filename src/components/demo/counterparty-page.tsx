import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import {
  LoadError,
  ModuleHeader,
  ModuleTable,
  StatCard,
  StatGrid,
} from "@/components/demo/module-ui";
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
  },
};

export async function CounterpartyPage({ role }: { role: CounterpartyRole }) {
  const copy = COPY[role];
  const { supabase, organizationId } = await requireActiveOrganization();
  const result = await loadCounterparties(supabase, organizationId, role);

  return (
    <div className="space-y-6">
      <ModuleHeader title={copy.title} description={copy.description} />
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
              <CardDescription>Solo lectura. Datos de la empresa activa.</CardDescription>
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
