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
import { loadCash, type CashMovement, type CashSummary } from "@/lib/demo-data/loaders";
import {
  activeLabel,
  documentStatusLabel,
  formatARS,
  formatCount,
  formatDate,
  legDirectionLabel,
  treasuryOperationTypeLabel,
} from "@/lib/demo-data/format";

type CashAccountRow = CashSummary["accounts"][number];

export default async function CashPage() {
  const { supabase, organizationId } = await requireActiveOrganization();
  const result = await loadCash(supabase, organizationId);

  return (
    <div className="space-y-6">
      <ModuleHeader
        title="Caja"
        description="Cuentas de caja y sus movimientos para la empresa activa."
      />
      {!result.ok ? (
        <LoadError />
      ) : (
        <>
          <StatGrid>
            <StatCard
              label="Cuentas de caja"
              value={formatCount(result.data.accounts.length)}
              testId="stat-cash-accounts"
            />
            <StatCard
              label="Operaciones contabilizadas"
              value={formatCount(result.data.postedOperations)}
              hint="Operaciones de tesorería contabilizadas que afectan cuentas de caja."
              testId="stat-posted-operations"
            />
            <StatCard
              label="Ingresos"
              value={formatARS(result.data.inflows)}
              hint="Solo movimientos contabilizados."
              testId="stat-inflows"
            />
            <StatCard
              label="Egresos"
              value={formatARS(result.data.outflows)}
              hint="Solo movimientos contabilizados."
              testId="stat-outflows"
            />
          </StatGrid>

          <Card>
            <CardHeader>
              <CardTitle>Cuentas de caja</CardTitle>
              <CardDescription>
                Saldo según movimientos contabilizados (ingresos menos egresos). Los movimientos
                revertidos o en borrador no se suman.
              </CardDescription>
            </CardHeader>
            <CardContent className="space-y-3">
              <ModuleTable<CashAccountRow>
                caption="Cuentas de caja"
                data={result.data.accounts}
                rowKey={(a) => a.id}
                emptyMessage="Esta empresa todavía no tiene cuentas de caja."
                columns={[
                  { key: "code", label: "Código", render: (a) => a.code },
                  { key: "name", label: "Cuenta", render: (a) => a.name },
                  {
                    key: "status",
                    label: "Estado",
                    render: (a) => {
                      const s = activeLabel(a.is_active);
                      return <Badge tone={s.tone}>{s.label}</Badge>;
                    },
                  },
                  {
                    key: "balance",
                    label: "Saldo contabilizado",
                    align: "right",
                    render: (a) => formatARS(a.postedBalance),
                  },
                ]}
              />
              {result.data.accounts.length > 0 ? (
                <p className="text-right text-sm" data-testid="cash-balance">
                  <span className="text-muted-foreground">Saldo total de caja: </span>
                  <span className="font-semibold tabular-nums">{formatARS(result.data.balance)}</span>
                </p>
              ) : null}
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle>Movimientos recientes</CardTitle>
              <CardDescription>Últimos movimientos que afectan cuentas de caja.</CardDescription>
            </CardHeader>
            <CardContent>
              <ModuleTable<CashMovement>
                caption="Movimientos recientes de caja"
                data={result.data.recent}
                rowKey={(m) => m.legId}
                emptyMessage="Todavía no hay movimientos de caja."
                columns={[
                  { key: "date", label: "Fecha", render: (m) => formatDate(m.operation.operation_date) },
                  { key: "number", label: "Número", render: (m) => m.operation.internal_number },
                  { key: "description", label: "Descripción", render: (m) => m.operation.description },
                  {
                    key: "type",
                    label: "Tipo",
                    render: (m) => {
                      const d = legDirectionLabel(m.direction);
                      return (
                        <div className="flex flex-wrap items-center gap-2">
                          <span>{treasuryOperationTypeLabel(m.operation.operation_type)}</span>
                          <Badge tone={d.tone}>{d.label}</Badge>
                        </div>
                      );
                    },
                  },
                  {
                    key: "status",
                    label: "Estado",
                    render: (m) => {
                      const s = documentStatusLabel(m.operation.status);
                      return <Badge tone={s.tone}>{s.label}</Badge>;
                    },
                  },
                  {
                    key: "amount",
                    label: "Importe",
                    align: "right",
                    render: (m) =>
                      `${m.direction === "OUTFLOW" ? "−" : ""}${formatARS(m.amount)}`,
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
