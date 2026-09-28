import {
  ArrowDownLeft,
  ArrowUpRight,
  BookOpenCheck,
  Building2,
  CalendarRange,
  FileText,
  History,
  Scale,
  Undo2,
} from "lucide-react";
import type { SupabaseClient } from "@supabase/supabase-js";
import { Badge } from "@/components/ui/badge";
import {
  BalanceBadge,
  DashboardHeader,
  EmptyState,
  KpiCard,
  ModuleCard,
  Panel,
  PanelLink,
  QuickActions,
  todayContext,
  type QuickAction,
} from "@/components/dashboard/dashboard-ui";
import { LoadError, ModuleTable } from "@/components/demo/module-ui";
import {
  loadAccounting,
  loadRecentTaxPeriods,
  type AccountingSummary,
  type TaxPeriodRow,
} from "@/lib/demo-data/loaders";
import {
  documentStatusLabel,
  formatARS,
  formatCount,
  formatDate,
  formatPeriod,
  humanizeDescription,
  journalSourceLabel,
  taxCodeLabel,
  taxPeriodStatusLabel,
} from "@/lib/demo-data/format";

type RecentEntry = AccountingSummary["recent"][number];

const ACCOUNTING_ACTIONS: QuickAction[] = [
  { label: "Libro diario", description: "Asientos y control de partida doble", href: "/accounting", icon: BookOpenCheck },
  { label: "Reporte ejecutivo", description: "Debe, Haber y períodos fiscales", href: "/reports", icon: FileText },
  { label: "Datos fiscales", description: "Condición fiscal y domicilio de la empresa", href: "/company", icon: Building2 },
];

export async function AccountingDashboard({
  supabase,
  organizationId,
  organizationName,
}: {
  supabase: SupabaseClient;
  organizationId: string;
  organizationName: string;
}) {
  const [accounting, taxPeriods] = await Promise.all([
    loadAccounting(supabase, organizationId),
    loadRecentTaxPeriods(supabase, organizationId, 6),
  ]);
  const totals = accounting.ok ? accounting.data.totals : null;
  const empty = totals ? totals.debit === BigInt(0) && totals.credit === BigInt(0) : false;
  const reversals = accounting.ok
    ? accounting.data.recent.filter((e) => e.reversal_of_entry_id).length
    : 0;

  return (
    <div className="space-y-6" data-testid="accounting-dashboard">
      <DashboardHeader
        title="Resumen contable"
        organizationName={organizationName}
        modeBadge={
          <Badge tone="success" className="gap-1">
            <BookOpenCheck className="h-3 w-3" aria-hidden />
            Modo contabilidad
          </Badge>
        }
        context={<p>Datos al {todayContext()}</p>}
      />

      <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <KpiCard
          label="Debe"
          icon={ArrowDownLeft}
          tone="primary"
          loadFailed={!totals}
          value={totals ? formatARS(totals.debit) : undefined}
          hint="Líneas de asientos contabilizados y revertidos"
          testId="kpi-debit"
        />
        <KpiCard
          label="Haber"
          icon={ArrowUpRight}
          tone="primary"
          loadFailed={!totals}
          value={totals ? formatARS(totals.credit) : undefined}
          hint="Líneas de asientos contabilizados y revertidos"
          testId="kpi-credit"
        />
        <KpiCard
          label="Estado del balance"
          icon={Scale}
          tone={totals && !totals.balanced ? "warning" : "success"}
          loadFailed={!totals}
          status={totals ? <BalanceBadge balanced={totals.balanced} empty={empty} /> : undefined}
          hint={totals ? `Diferencia: ${formatARS(totals.difference)}` : undefined}
          href="/accounting"
          testId="kpi-balance-status"
        />
        <KpiCard
          label="Asientos contabilizados"
          icon={BookOpenCheck}
          tone="neutral"
          loadFailed={!accounting.ok}
          value={accounting.ok ? formatCount(accounting.data.postedCount) : undefined}
          hint="Asientos confirmados en el libro diario"
          href="/accounting"
          testId="kpi-posted-entries"
        />
      </div>

      <div className="grid gap-4 xl:grid-cols-3">
        <Panel
          title="Últimos asientos"
          description="Asientos contabilizados o revertidos más recientes."
          action={<PanelLink href="/accounting">Ver libro diario</PanelLink>}
          className="xl:col-span-2"
          testId="latest-entries"
        >
          {!accounting.ok ? (
            <LoadError />
          ) : (
            <ModuleTable<RecentEntry>
              caption="Últimos asientos"
              data={accounting.data.recent.slice(0, 8)}
              rowKey={(e) => e.id}
              emptyMessage="Todavía no hay asientos contabilizados."
              columns={[
                { key: "number", label: "N°", render: (e) => e.entry_number || "—" },
                { key: "date", label: "Fecha", render: (e) => formatDate(e.entry_date) },
                {
                  key: "description",
                  label: "Descripción",
                  render: (e) => <span className="line-clamp-1">{humanizeDescription(e.description)}</span>,
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
          )}
        </Panel>

        <Panel
          title="Períodos fiscales"
          description="Estado interno de trabajo. Un período cerrado no implica una presentación ante ARCA."
          action={<PanelLink href="/reports">Ver reportes</PanelLink>}
          testId="dashboard-tax-periods"
        >
          {!taxPeriods.ok ? (
            <LoadError />
          ) : taxPeriods.data.length === 0 ? (
            <EmptyState icon={CalendarRange}>Todavía no hay períodos fiscales registrados.</EmptyState>
          ) : (
            <ul className="divide-y divide-border">
              {taxPeriods.data.map((p: TaxPeriodRow) => {
                const s = taxPeriodStatusLabel(p.status);
                return (
                  <li key={p.id} className="flex items-center justify-between gap-3 py-2.5 text-sm">
                    <div>
                      <p className="font-medium">
                        {taxCodeLabel(p.tax_code)}
                        {p.jurisdiction_code ? ` (${p.jurisdiction_code})` : ""}
                      </p>
                      <p className="text-xs text-muted-foreground">
                        Período fiscal {formatPeriod(p.period_year, p.period_month)}
                      </p>
                    </div>
                    <Badge tone={s.tone}>{s.label}</Badge>
                  </li>
                );
              })}
            </ul>
          )}
        </Panel>
      </div>

      <div className="grid gap-4 xl:grid-cols-3">
        <div className="grid gap-4 sm:grid-cols-3 xl:col-span-2">
          <ModuleCard
            label="Contabilizados"
            icon={BookOpenCheck}
            href="/accounting"
            loadFailed={!accounting.ok}
            value={accounting.ok ? formatCount(accounting.data.postedCount) : undefined}
            hint="Asientos en estado Contabilizado"
            testId="card-posted"
          />
          <ModuleCard
            label="Revertidos"
            icon={Undo2}
            href="/accounting"
            loadFailed={!accounting.ok}
            value={accounting.ok ? formatCount(accounting.data.reversedCount) : undefined}
            hint="Asientos anulados por reversión"
            testId="card-reversed"
          />
          <ModuleCard
            label="Reversiones recientes"
            icon={History}
            href="/accounting"
            loadFailed={!accounting.ok}
            value={accounting.ok ? formatCount(reversals) : undefined}
            hint="Entre los últimos 15 asientos"
            testId="card-recent-reversals"
          />
        </div>
        <QuickActions
          actions={ACCOUNTING_ACTIONS}
          note="Accesos a secciones disponibles. La carga manual de asientos aún no está habilitada."
        />
      </div>
    </div>
  );
}
