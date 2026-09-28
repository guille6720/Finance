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
import { loadAccounting, type AccountingSummary } from "@/lib/demo-data/loaders";
import {
  documentStatusLabel,
  formatARS,
  formatCount,
  formatDate,
  humanizeDescription,
  journalSourceLabel,
} from "@/lib/demo-data/format";

type RecentEntry = AccountingSummary["recent"][number];

export default async function AccountingPage() {
  const { supabase, organizationId } = await requireActiveOrganization();
  const result = await loadAccounting(supabase, organizationId);

  return (
    <div className="space-y-6">
      <ModuleHeader
        title="Contabilidad"
        description="Asientos registrados en el libro diario de la empresa activa."
      />
      {!result.ok ? (
        <LoadError />
      ) : (
        <>
          <StatGrid>
            <StatCard
              label="Asientos contabilizados"
              value={formatCount(result.data.postedCount)}
              testId="stat-posted-entries"
            />
            <StatCard
              label="Asientos revertidos"
              value={formatCount(result.data.reversedCount)}
              testId="stat-reversed-entries"
            />
            <StatCard
              label="Total débitos"
              value={formatARS(result.data.totals.debit)}
              hint="Líneas de asientos contabilizados y revertidos."
              testId="stat-total-debit"
            />
            <StatCard
              label="Total créditos"
              value={formatARS(result.data.totals.credit)}
              hint="Líneas de asientos contabilizados y revertidos."
              testId="stat-total-credit"
            />
          </StatGrid>

          <Card data-testid="double-entry-control">
            <CardHeader>
              <div className="flex flex-wrap items-center gap-2">
                <CardTitle>Control de partida doble</CardTitle>
                {result.data.totals.balanced ? (
                  <Badge tone="success">Balanceado</Badge>
                ) : (
                  <Badge tone="warning">Revisar</Badge>
                )}
              </div>
              <CardDescription>
                Compara el total del Debe con el total del Haber de las líneas visibles. Es un
                control interno de consistencia; no constituye una certificación contable.
              </CardDescription>
            </CardHeader>
            <CardContent>
              <dl className="grid gap-3 text-sm sm:grid-cols-3">
                <div>
                  <dt className="text-muted-foreground">Debe</dt>
                  <dd className="font-semibold tabular-nums">{formatARS(result.data.totals.debit)}</dd>
                </div>
                <div>
                  <dt className="text-muted-foreground">Haber</dt>
                  <dd className="font-semibold tabular-nums">{formatARS(result.data.totals.credit)}</dd>
                </div>
                <div>
                  <dt className="text-muted-foreground">Diferencia</dt>
                  <dd className="font-semibold tabular-nums" data-testid="double-entry-difference">
                    {formatARS(result.data.totals.difference)}
                  </dd>
                </div>
              </dl>
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle>Asientos recientes</CardTitle>
              <CardDescription>Últimos asientos contabilizados o revertidos.</CardDescription>
            </CardHeader>
            <CardContent>
              <ModuleTable<RecentEntry>
                caption="Asientos recientes"
                data={result.data.recent}
                rowKey={(e) => e.id}
                emptyMessage="Todavía no hay asientos contabilizados."
                columns={[
                  { key: "number", label: "N°", render: (e) => e.entry_number || "—" },
                  { key: "date", label: "Fecha", render: (e) => formatDate(e.entry_date) },
                  {
                    key: "description",
                    label: "Descripción",
                    render: (e) => (
                      <div>
                        <p>{humanizeDescription(e.description)}</p>
                        {e.reversal_of_entry_id ? (
                          <p className="text-xs text-muted-foreground">Asiento de reversión</p>
                        ) : null}
                      </div>
                    ),
                  },
                  { key: "source", label: "Origen", render: (e) => journalSourceLabel(e.source_type) },
                  {
                    key: "status",
                    label: "Estado",
                    render: (e) => {
                      const s = documentStatusLabel(e.status);
                      return <Badge tone={s.tone}>{s.label}</Badge>;
                    },
                  },
                  { key: "debit", label: "Debe", align: "right", render: (e) => formatARS(e.debit) },
                  { key: "credit", label: "Haber", align: "right", render: (e) => formatARS(e.credit) },
                ]}
              />
            </CardContent>
          </Card>
        </>
      )}
    </div>
  );
}
