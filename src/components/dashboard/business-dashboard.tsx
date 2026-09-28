import {
  BarChart3,
  BookOpenCheck,
  Briefcase,
  Building2,
  FileText,
  Receipt,
  Scale,
  ShoppingCart,
  Truck,
  UserCog,
  Users,
  Wallet,
} from "lucide-react";
import type { SupabaseClient } from "@supabase/supabase-js";
import { Badge } from "@/components/ui/badge";
import {
  ActivityChart,
  BalanceBadge,
  DashboardHeader,
  EmptyState,
  KpiCard,
  ModuleCard,
  Panel,
  PanelLink,
  QuickActions,
  monthLabel,
  todayContext,
  type QuickAction,
} from "@/components/dashboard/dashboard-ui";
import { LoadError } from "@/components/demo/module-ui";
import { SetupProgress, type SetupState } from "@/components/dashboard/setup-progress";
import {
  buildMonthlyActivity,
  buildRecentActivity,
  countCounterpartiesByRole,
  countPostedJournalEntries,
  loadCash,
  loadConfirmedSalesRows,
  loadJournalTotals,
  loadPostedPurchasesRows,
  loadPostedTreasuryVolume,
  summarizePurchases,
  summarizeSales,
  type RecentActivityItem,
} from "@/lib/demo-data/loaders";
import { formatARS, formatCount, formatDate } from "@/lib/demo-data/format";

const BUSINESS_ACTIONS: QuickAction[] = [
  { label: "Ver clientes", description: "Listado y estado de tus clientes", href: "/customers", icon: Users },
  { label: "Ver proveedores", description: "Proveedores y compras registradas", href: "/suppliers", icon: Truck },
  { label: "Revisar caja", description: "Saldo y movimientos contabilizados", href: "/cash", icon: Wallet },
  { label: "Reporte ejecutivo", description: "Resumen de ventas, compras y tesorería", href: "/reports", icon: FileText },
  { label: "Datos de la empresa", description: "Datos fiscales y sucursales", href: "/company", icon: Building2 },
  { label: "Equipo", description: "Usuarios con acceso a la empresa", href: "/users", icon: UserCog },
];

const KIND_LABEL: Record<RecentActivityItem["kind"], { label: string; icon: typeof Wallet }> = {
  sale: { label: "Venta", icon: Receipt },
  purchase: { label: "Compra", icon: ShoppingCart },
  cash: { label: "Caja", icon: Wallet },
};

export async function BusinessDashboard({
  supabase,
  organizationId,
  organizationName,
  setup,
}: {
  supabase: SupabaseClient;
  organizationId: string;
  organizationName: string;
  setup: SetupState;
}) {
  const [salesRows, purchaseRows, cash, journal, postedEntries, treasury, customers, suppliers] =
    await Promise.all([
      loadConfirmedSalesRows(supabase, organizationId),
      loadPostedPurchasesRows(supabase, organizationId),
      loadCash(supabase, organizationId),
      loadJournalTotals(supabase, organizationId),
      countPostedJournalEntries(supabase, organizationId),
      loadPostedTreasuryVolume(supabase, organizationId),
      countCounterpartiesByRole(supabase, organizationId, "CUSTOMER"),
      countCounterpartiesByRole(supabase, organizationId, "SUPPLIER"),
    ]);

  const sales = salesRows.ok ? summarizeSales(salesRows.data) : null;
  const purchases = purchaseRows.ok ? summarizePurchases(purchaseRows.data) : null;
  const monthly =
    salesRows.ok && purchaseRows.ok ? buildMonthlyActivity(salesRows.data, purchaseRows.data) : null;
  const recent =
    salesRows.ok && purchaseRows.ok && cash.ok
      ? buildRecentActivity(salesRows.data, purchaseRows.data, cash.data.recent)
      : null;
  const journalEmpty =
    journal.ok && journal.data.debit === BigInt(0) && journal.data.credit === BigInt(0);

  const period =
    monthly && monthly.length > 0
      ? `Actividad registrada: ${monthLabel(monthly[0].month)} – ${monthLabel(monthly[monthly.length - 1].month)}`
      : null;

  return (
    <div className="space-y-6" data-testid="business-dashboard">
      <DashboardHeader
        title="Resumen de tu negocio"
        organizationName={organizationName}
        modeBadge={
          <Badge tone="primary" className="gap-1">
            <Briefcase className="h-3 w-3" aria-hidden />
            Modo negocio
          </Badge>
        }
        context={
          <>
            <p>Datos al {todayContext()}</p>
            {period ? <p>{period}</p> : null}
          </>
        }
      />

      <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <KpiCard
          label="Ventas comerciales"
          icon={Receipt}
          tone="primary"
          loadFailed={!sales}
          value={sales ? formatARS(sales.amount) : undefined}
          hint={sales ? `${formatCount(sales.count)} pedidos de venta confirmados` : undefined}
          href="/reports"
          testId="kpi-sales"
        />
        <KpiCard
          label="Compras"
          icon={ShoppingCart}
          tone="neutral"
          loadFailed={!purchases}
          value={purchases ? formatARS(purchases.amount) : undefined}
          hint={
            purchases
              ? `${formatCount(purchases.count)} comprobantes contabilizados (notas de crédito restan)`
              : undefined
          }
          href="/suppliers"
          testId="kpi-purchases"
        />
        <KpiCard
          label="Saldo de caja"
          icon={Wallet}
          tone="success"
          loadFailed={!cash.ok}
          value={cash.ok ? formatARS(cash.data.balance) : undefined}
          hint={
            cash.ok
              ? cash.data.accounts.length === 0
                ? "Sin cuentas de caja registradas"
                : "Según movimientos de caja contabilizados"
              : undefined
          }
          href="/cash"
          testId="kpi-cash-balance"
        />
        <KpiCard
          label="Estado contable"
          icon={Scale}
          tone={journal.ok && !journal.data.balanced ? "warning" : "success"}
          loadFailed={!journal.ok}
          status={journal.ok ? <BalanceBadge balanced={journal.data.balanced} empty={journalEmpty} /> : undefined}
          hint={journal.ok ? "Control Debe = Haber de los asientos registrados" : undefined}
          href="/accounting"
          testId="kpi-accounting-status"
        />
      </div>

      <div className="grid gap-4 xl:grid-cols-3">
        <Panel
          title="Actividad del negocio"
          description="Ventas comerciales confirmadas y compras contabilizadas, agrupadas por mes del documento."
          action={<PanelLink href="/reports">Ver reportes</PanelLink>}
          className="xl:col-span-2"
          testId="business-activity"
        >
          {!monthly ? (
            <LoadError />
          ) : monthly.length === 0 ? (
            <EmptyState icon={BarChart3}>
              Todavía no hay ventas confirmadas ni compras contabilizadas para graficar.
            </EmptyState>
          ) : (
            <ActivityChart data={monthly} />
          )}
        </Panel>

        <Panel
          title="Estado contable"
          description="Asientos contabilizados y revertidos."
          action={<PanelLink href="/accounting">Ver libro diario</PanelLink>}
          testId="business-accounting-status"
        >
          {journal.ok ? (
            <dl className="space-y-3 text-sm">
              <div className="flex items-baseline justify-between gap-3">
                <dt className="text-muted-foreground">Debe</dt>
                <dd className="font-semibold tabular-nums">{formatARS(journal.data.debit)}</dd>
              </div>
              <div className="flex items-baseline justify-between gap-3">
                <dt className="text-muted-foreground">Haber</dt>
                <dd className="font-semibold tabular-nums">{formatARS(journal.data.credit)}</dd>
              </div>
              <div className="flex items-baseline justify-between gap-3 border-t border-border pt-3">
                <dt className="text-muted-foreground">Diferencia</dt>
                <dd className="font-semibold tabular-nums">{formatARS(journal.data.difference)}</dd>
              </div>
              <div className="flex items-center justify-between gap-3">
                <dt className="text-muted-foreground">Estado</dt>
                <dd>
                  <BalanceBadge balanced={journal.data.balanced} empty={journalEmpty} />
                </dd>
              </div>
              <p className="pt-1 text-xs text-muted-foreground">
                Control interno de consistencia; no constituye una certificación contable.
              </p>
            </dl>
          ) : (
            <LoadError />
          )}
        </Panel>
      </div>

      <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <ModuleCard
          label="Clientes"
          icon={Users}
          href="/customers"
          loadFailed={!customers.ok}
          value={customers.ok ? formatCount(customers.data) : undefined}
          hint="Clientes registrados"
          testId="card-customers"
        />
        <ModuleCard
          label="Proveedores"
          icon={Truck}
          href="/suppliers"
          loadFailed={!suppliers.ok}
          value={suppliers.ok ? formatCount(suppliers.data) : undefined}
          hint="Proveedores registrados"
          testId="card-suppliers"
        />
        <ModuleCard
          label="Asientos"
          icon={BookOpenCheck}
          href="/accounting"
          loadFailed={!postedEntries.ok}
          value={postedEntries.ok ? formatCount(postedEntries.data) : undefined}
          hint="Asientos contabilizados"
          testId="card-journal"
        />
        <ModuleCard
          label="Movimientos de caja"
          icon={Wallet}
          href="/cash"
          loadFailed={!cash.ok || !treasury.ok}
          value={cash.ok ? formatCount(cash.data.postedOperations) : undefined}
          hint={
            treasury.ok
              ? `Tesorería total: ${formatCount(treasury.data.count)} operaciones · ${formatARS(treasury.data.amount)}`
              : undefined
          }
          testId="card-cash-movements"
        />
      </div>

      <div className="grid gap-4 xl:grid-cols-3">
        <Panel
          title="Actividad reciente"
          description="Últimas ventas confirmadas, compras y movimientos de caja contabilizados."
          className="xl:col-span-2"
          testId="recent-activity"
        >
          {!recent ? (
            <LoadError />
          ) : recent.length === 0 ? (
            <EmptyState icon={Receipt}>Todavía no hay actividad registrada.</EmptyState>
          ) : (
            <ul className="divide-y divide-border">
              {recent.map((item) => {
                const kind = KIND_LABEL[item.kind];
                return (
                  <li key={item.id} className="flex items-center gap-3 py-2.5">
                    <span className="flex h-8 w-8 shrink-0 items-center justify-center rounded-lg bg-muted text-muted-foreground">
                      <kind.icon className="h-4 w-4" aria-hidden />
                    </span>
                    <div className="min-w-0 flex-1">
                      <p className="truncate text-sm font-medium">{item.description}</p>
                      <p className="text-xs text-muted-foreground">
                        {kind.label} · {item.reference} · {formatDate(item.date)}
                      </p>
                    </div>
                    <span
                      className={
                        item.direction === "in"
                          ? "whitespace-nowrap text-sm font-semibold tabular-nums text-success"
                          : "whitespace-nowrap text-sm font-semibold tabular-nums"
                      }
                    >
                      {item.direction === "out" ? "−" : "+"}
                      {formatARS(item.amount)}
                    </span>
                  </li>
                );
              })}
            </ul>
          )}
        </Panel>

        <div className="space-y-4">
          <QuickActions
            actions={BUSINESS_ACTIONS}
            note="Accesos a secciones disponibles. La carga de comprobantes aún no está habilitada."
          />
          <SetupProgress setup={setup} />
        </div>
      </div>
    </div>
  );
}
