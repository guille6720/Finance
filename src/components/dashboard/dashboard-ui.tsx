import type { ComponentType, ReactNode } from "react";
import Link from "next/link";
import { ArrowUpRight, ChevronRight } from "lucide-react";
import { cn } from "@/lib/utils";
import { Badge } from "@/components/ui/badge";
import { LoadError } from "@/components/demo/module-ui";
import { formatARS, unitsToNumber } from "@/lib/demo-data/format";
import type { MonthlyActivity } from "@/lib/demo-data/loaders";

type Icon = ComponentType<{ className?: string }>;
type Tone = "neutral" | "success" | "warning" | "danger" | "primary";

const ICON_TONES: Record<Tone, string> = {
  neutral: "bg-muted text-muted-foreground",
  primary: "bg-primary/15 text-primary-bright",
  success: "bg-success/15 text-success",
  warning: "bg-warning/15 text-warning",
  danger: "bg-danger/15 text-danger",
};

export function DashboardHeader({
  title,
  organizationName,
  context,
  modeBadge,
}: {
  title: string;
  organizationName: string;
  context: ReactNode;
  modeBadge: ReactNode;
}) {
  return (
    <div className="flex flex-col gap-3 border-b border-border pb-5 sm:flex-row sm:items-end sm:justify-between">
      <div className="min-w-0">
        <div className="flex flex-wrap items-center gap-2">
          <h2 className="text-2xl font-semibold tracking-tight" data-testid="dashboard-title">
            {title}
          </h2>
          {modeBadge}
        </div>
        <p className="mt-1 truncate text-sm text-muted-foreground" data-testid="dashboard-org">
          {organizationName}
        </p>
      </div>
      <div className="text-xs text-muted-foreground sm:text-right">{context}</div>
    </div>
  );
}

export function KpiCard({
  label,
  icon: IconCmp,
  tone = "primary",
  loadFailed,
  value,
  status,
  hint,
  href,
  testId,
}: {
  label: string;
  icon: Icon;
  tone?: Tone;
  loadFailed?: boolean;
  value?: ReactNode;
  status?: ReactNode;
  hint?: ReactNode;
  href?: string;
  testId: string;
}) {
  const body = (
    <div
      data-testid={testId}
      className={cn(
        "flex h-full flex-col gap-3 rounded-xl border border-border bg-surface p-5 shadow-sm transition-colors",
        href && "group-hover:border-primary/40 group-hover:bg-surface-elevated"
      )}
    >
      <div className="flex items-center justify-between gap-2">
        <p className="text-sm font-medium text-muted-foreground">{label}</p>
        <span className={cn("flex h-8 w-8 items-center justify-center rounded-lg", ICON_TONES[tone])}>
          <IconCmp className="h-4 w-4" aria-hidden />
        </span>
      </div>
      {loadFailed ? (
        <LoadError />
      ) : (
        <>
          <div className="flex flex-wrap items-center gap-2">
            {value !== undefined ? (
              <h3 className="text-2xl font-semibold tracking-tight tabular-nums xl:text-[1.75rem]">
                {value}
              </h3>
            ) : null}
            {status}
          </div>
          {hint ? <p className="mt-auto text-xs text-muted-foreground">{hint}</p> : null}
        </>
      )}
    </div>
  );
  if (!href) return body;
  return (
    <Link href={href} className="group block rounded-xl focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary/60">
      {body}
    </Link>
  );
}

export function Panel({
  title,
  description,
  action,
  children,
  className,
  testId,
}: {
  title: string;
  description?: ReactNode;
  action?: ReactNode;
  children: ReactNode;
  className?: string;
  testId?: string;
}) {
  return (
    <section
      data-testid={testId}
      className={cn("flex flex-col rounded-xl border border-border bg-surface shadow-sm", className)}
    >
      <header className="flex items-start justify-between gap-3 border-b border-border px-5 py-4">
        <div className="min-w-0">
          <h3 className="text-sm font-semibold tracking-tight">{title}</h3>
          {description ? <p className="mt-0.5 text-xs text-muted-foreground">{description}</p> : null}
        </div>
        {action}
      </header>
      <div className="flex-1 p-5">{children}</div>
    </section>
  );
}

export function PanelLink({ href, children }: { href: string; children: ReactNode }) {
  return (
    <Link
      href={href}
      className="inline-flex shrink-0 items-center gap-1 text-xs font-medium text-primary-bright hover:underline"
    >
      {children}
      <ChevronRight className="h-3.5 w-3.5" aria-hidden />
    </Link>
  );
}

export function ModuleCard({
  label,
  icon: IconCmp,
  href,
  loadFailed,
  value,
  hint,
  testId,
}: {
  label: string;
  icon: Icon;
  href: string;
  loadFailed?: boolean;
  value?: ReactNode;
  hint?: ReactNode;
  testId: string;
}) {
  return (
    <Link
      href={href}
      data-testid={testId}
      className="group flex items-center gap-4 rounded-xl border border-border bg-surface p-4 shadow-sm transition-colors hover:border-primary/40 hover:bg-surface-elevated focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary/60"
    >
      <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-lg bg-muted text-muted-foreground group-hover:text-primary-bright">
        <IconCmp className="h-5 w-5" aria-hidden />
      </span>
      <div className="min-w-0 flex-1">
        <p className="text-xs font-medium text-muted-foreground">{label}</p>
        {loadFailed ? (
          <p className="text-sm text-danger" role="alert">
            No pudimos cargar esta información.
          </p>
        ) : (
          <>
            <h3 className="text-xl font-semibold tabular-nums">{value}</h3>
            {hint ? <p className="truncate text-xs text-muted-foreground">{hint}</p> : null}
          </>
        )}
      </div>
      <ArrowUpRight
        className="h-4 w-4 shrink-0 text-muted-foreground transition-colors group-hover:text-primary-bright"
        aria-hidden
      />
    </Link>
  );
}

export function BalanceBadge({ balanced, empty }: { balanced: boolean; empty?: boolean }) {
  if (empty) return <Badge tone="neutral">Sin movimientos</Badge>;
  return balanced ? (
    <Badge tone="success" className="gap-1">
      <span className="h-1.5 w-1.5 rounded-full bg-success" aria-hidden />
      Balanceado
    </Badge>
  ) : (
    <Badge tone="warning" className="gap-1">
      <span className="h-1.5 w-1.5 rounded-full bg-warning" aria-hidden />
      Revisar
    </Badge>
  );
}

export function EmptyState({ icon: IconCmp, children }: { icon: Icon; children: ReactNode }) {
  return (
    <div
      data-testid="dashboard-empty"
      className="flex h-full min-h-32 flex-col items-center justify-center gap-2 rounded-lg border border-dashed border-border p-6 text-center text-sm text-muted-foreground"
    >
      <IconCmp className="h-5 w-5" aria-hidden />
      <p>{children}</p>
    </div>
  );
}

const MONTHS = ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic"];

export function monthLabel(key: string) {
  const [y, m] = key.split("-").map(Number);
  return `${MONTHS[m - 1]} ${y}`;
}

/** Monthly sales vs purchases from stored document dates. No trend or growth is derived. */
export function ActivityChart({ data }: { data: MonthlyActivity[] }) {
  const max = data.reduce((acc, d) => {
    const s = Math.abs(unitsToNumber(d.sales));
    const p = Math.abs(unitsToNumber(d.purchases));
    return Math.max(acc, s, p);
  }, 0);
  const pct = (units: bigint) =>
    max === 0 ? 0 : Math.max(0, (unitsToNumber(units) / max) * 100);

  return (
    <div data-testid="activity-chart">
      <div className="mb-4 flex flex-wrap items-center gap-4 text-xs text-muted-foreground">
        <span className="inline-flex items-center gap-1.5">
          <span className="h-2.5 w-2.5 rounded-sm bg-primary" aria-hidden />
          Ventas comerciales
        </span>
        <span className="inline-flex items-center gap-1.5">
          <span className="h-2.5 w-2.5 rounded-sm bg-muted-foreground/60" aria-hidden />
          Compras
        </span>
      </div>
      <div className="flex h-52 items-end gap-3 border-b border-border sm:gap-5" aria-hidden>
        {data.map((d) => (
          <div key={d.month} className="flex h-full flex-1 flex-col justify-end">
            <div className="flex h-full items-end justify-center gap-1">
              <div
                className="w-full max-w-7 rounded-t-sm bg-primary transition-opacity hover:opacity-80"
                style={{ height: `${pct(d.sales)}%` }}
                title={`Ventas ${monthLabel(d.month)}: ${formatARS(d.sales)}`}
              />
              <div
                className="w-full max-w-7 rounded-t-sm bg-muted-foreground/60 transition-opacity hover:opacity-80"
                style={{ height: `${pct(d.purchases)}%` }}
                title={`Compras ${monthLabel(d.month)}: ${formatARS(d.purchases)}`}
              />
            </div>
          </div>
        ))}
      </div>
      <div className="mt-2 flex gap-3 sm:gap-5" aria-hidden>
        {data.map((d) => (
          <p key={d.month} className="flex-1 text-center text-[11px] capitalize text-muted-foreground">
            {monthLabel(d.month)}
          </p>
        ))}
      </div>
      <table className="sr-only">
        <caption>Ventas comerciales y compras por mes</caption>
        <thead>
          <tr>
            <th scope="col">Mes</th>
            <th scope="col">Ventas comerciales</th>
            <th scope="col">Compras</th>
          </tr>
        </thead>
        <tbody>
          {data.map((d) => (
            <tr key={d.month}>
              <td>{monthLabel(d.month)}</td>
              <td>{formatARS(d.sales)}</td>
              <td>{formatARS(d.purchases)}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

export type QuickAction = { label: string; description: string; href: string; icon: Icon };

export function QuickActions({ actions, note }: { actions: QuickAction[]; note: string }) {
  return (
    <Panel title="Acciones rápidas" description={note} testId="quick-actions">
      <ul className="grid gap-2 sm:grid-cols-2 xl:grid-cols-1">
        {actions.map((a) => (
          <li key={a.href + a.label}>
            <Link
              href={a.href}
              className="group flex items-center gap-3 rounded-lg border border-border px-3 py-2.5 transition-colors hover:border-primary/40 hover:bg-surface-elevated focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary/60"
            >
              <a.icon className="h-4 w-4 shrink-0 text-muted-foreground group-hover:text-primary-bright" aria-hidden />
              <span className="min-w-0 flex-1">
                <span className="block text-sm font-medium">{a.label}</span>
                <span className="block truncate text-xs text-muted-foreground">{a.description}</span>
              </span>
              <ChevronRight className="h-4 w-4 shrink-0 text-muted-foreground" aria-hidden />
            </Link>
          </li>
        ))}
      </ul>
    </Panel>
  );
}

export function Skeleton({ className }: { className?: string }) {
  return <div className={cn("animate-pulse rounded-md bg-muted/70", className)} />;
}

export function todayContext(now: Date = new Date()) {
  return new Intl.DateTimeFormat("es-AR", {
    dateStyle: "long",
    timeZone: "America/Argentina/Buenos_Aires",
  }).format(now);
}
