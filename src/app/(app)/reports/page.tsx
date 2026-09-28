import type { ReactNode } from "react";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import {
  DemoNotice,
  LoadError,
  ModuleHeader,
  ModuleTable,
  REPORTS_NOTICE,
} from "@/components/demo/module-ui";
import { requireActiveOrganization } from "@/lib/demo-data/organization-context";
import {
  countPostedJournalEntries,
  loadConfirmedSales,
  loadJournalTotals,
  loadPostedPurchases,
  loadPostedTreasuryVolume,
  loadRecentTaxPeriods,
  type TaxPeriodRow,
} from "@/lib/demo-data/loaders";
import {
  formatARS,
  formatCount,
  formatPeriod,
  taxCodeLabel,
  taxPeriodStatusLabel,
} from "@/lib/demo-data/format";

function SnapshotCard({
  title,
  description,
  testId,
  children,
}: {
  title: string;
  description: string;
  testId: string;
  children: ReactNode;
}) {
  return (
    <Card data-testid={testId}>
      <CardHeader>
        <CardTitle>{title}</CardTitle>
        <CardDescription>{description}</CardDescription>
      </CardHeader>
      <CardContent>{children}</CardContent>
    </Card>
  );
}

function Metric({ label, value }: { label: string; value: ReactNode }) {
  return (
    <div className="flex items-baseline justify-between gap-3 border-b border-border py-2 text-sm last:border-b-0">
      <span className="text-muted-foreground">{label}</span>
      <span className="font-semibold tabular-nums">{value}</span>
    </div>
  );
}

export default async function ReportsPage() {
  const { supabase, organizationId } = await requireActiveOrganization();
  const [sales, purchases, treasury, postedEntries, journal, taxPeriods] = await Promise.all([
    loadConfirmedSales(supabase, organizationId),
    loadPostedPurchases(supabase, organizationId),
    loadPostedTreasuryVolume(supabase, organizationId),
    countPostedJournalEntries(supabase, organizationId),
    loadJournalTotals(supabase, organizationId),
    loadRecentTaxPeriods(supabase, organizationId, 3),
  ]);

  return (
    <div className="space-y-6">
      <ModuleHeader
        title="Reportes"
        description="Resumen ejecutivo de solo lectura generado a partir de los datos de la empresa activa."
      />
      <DemoNotice>{REPORTS_NOTICE}</DemoNotice>

      <div className="grid gap-4 md:grid-cols-2">
        <SnapshotCard
          title="Ventas"
          description="Pedidos de venta confirmados. Excluye presupuestos, borradores y cancelados. Son documentos comerciales, no facturas fiscales."
          testId="report-sales"
        >
          {sales.ok ? (
            <>
              <Metric label="Pedidos confirmados" value={formatCount(sales.data.count)} />
              <Metric label="Importe total" value={formatARS(sales.data.amount)} />
            </>
          ) : (
            <LoadError />
          )}
        </SnapshotCard>

        <SnapshotCard
          title="Compras"
          description="Comprobantes de proveedores contabilizados. Las notas de crédito restan."
          testId="report-purchases"
        >
          {purchases.ok ? (
            <>
              <Metric label="Comprobantes contabilizados" value={formatCount(purchases.data.count)} />
              <Metric label="Importe total" value={formatARS(purchases.data.amount)} />
            </>
          ) : (
            <LoadError />
          )}
        </SnapshotCard>

        <SnapshotCard
          title="Tesorería"
          description="Operaciones de caja y bancos contabilizadas. El importe es volumen de movimientos, no saldo disponible."
          testId="report-treasury"
        >
          {treasury.ok ? (
            <>
              <Metric label="Operaciones contabilizadas" value={formatCount(treasury.data.count)} />
              <Metric label="Volumen de movimientos" value={formatARS(treasury.data.amount)} />
            </>
          ) : (
            <LoadError />
          )}
        </SnapshotCard>

        <SnapshotCard
          title="Contabilidad"
          description="Debe y Haber de las líneas de asientos contabilizados y revertidos."
          testId="report-accounting"
        >
          {postedEntries.ok && journal.ok ? (
            <>
              <Metric label="Asientos contabilizados" value={formatCount(postedEntries.data)} />
              <Metric label="Debe" value={formatARS(journal.data.debit)} />
              <Metric label="Haber" value={formatARS(journal.data.credit)} />
              <Metric
                label="Diferencia"
                value={
                  <span className="inline-flex items-center gap-2">
                    {formatARS(journal.data.difference)}
                    {journal.data.balanced ? (
                      <Badge tone="success">Balanceado</Badge>
                    ) : (
                      <Badge tone="warning">Revisar</Badge>
                    )}
                  </span>
                }
              />
            </>
          ) : (
            <LoadError />
          )}
        </SnapshotCard>
      </div>

      <SnapshotCard
        title="Períodos fiscales"
        description="Últimos períodos registrados y su estado interno de trabajo. Un período cerrado no implica una presentación ante ARCA."
        testId="report-tax-periods"
      >
        {taxPeriods.ok ? (
          <ModuleTable<TaxPeriodRow>
            caption="Últimos períodos fiscales"
            data={taxPeriods.data}
            rowKey={(p) => p.id}
            emptyMessage="Todavía no hay períodos fiscales registrados."
            columns={[
              {
                key: "tax",
                label: "Impuesto",
                render: (p) =>
                  p.jurisdiction_code
                    ? `${taxCodeLabel(p.tax_code)} (${p.jurisdiction_code})`
                    : taxCodeLabel(p.tax_code),
              },
              {
                key: "period",
                label: "Período fiscal",
                render: (p) => formatPeriod(p.period_year, p.period_month),
              },
              {
                key: "status",
                label: "Estado",
                render: (p) => {
                  const s = taxPeriodStatusLabel(p.status);
                  return <Badge tone={s.tone}>{s.label}</Badge>;
                },
              },
            ]}
          />
        ) : (
          <LoadError />
        )}
      </SnapshotCard>
    </div>
  );
}
