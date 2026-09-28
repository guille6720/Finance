import type { ReactNode } from "react";
import { AlertTriangle } from "lucide-react";
import { cn } from "@/lib/utils";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";

export const LOAD_ERROR_MESSAGE = "No pudimos cargar esta información.";

export const REPORTS_NOTICE =
  "Información demostrativa basada en datos registrados en Staging. No constituye una presentación fiscal.";

export function ModuleHeader({ title, description }: { title: string; description: string }) {
  return (
    <div>
      <h2 className="text-xl font-semibold tracking-tight">{title}</h2>
      <p className="mt-1 text-sm text-muted-foreground">{description}</p>
    </div>
  );
}

export function LoadError({ className }: { className?: string }) {
  return (
    <div
      role="alert"
      data-testid="module-load-error"
      className={cn(
        "flex items-start gap-3 rounded-md border border-danger/30 bg-danger/10 p-4 text-sm text-danger",
        className
      )}
    >
      <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" aria-hidden />
      <div>
        <p className="font-medium">{LOAD_ERROR_MESSAGE}</p>
        <p className="text-xs opacity-90">Intentá de nuevo en unos minutos.</p>
      </div>
    </div>
  );
}

export function StatCard({
  label,
  value,
  hint,
  testId,
}: {
  label: string;
  value: ReactNode;
  hint?: ReactNode;
  testId?: string;
}) {
  return (
    <Card data-testid={testId}>
      <CardHeader className="pb-2">
        <CardDescription>{label}</CardDescription>
        <CardTitle className="text-2xl tabular-nums">{value}</CardTitle>
      </CardHeader>
      {hint ? (
        <CardContent>
          <p className="text-xs text-muted-foreground">{hint}</p>
        </CardContent>
      ) : null}
    </Card>
  );
}

export function StatGrid({ children }: { children: ReactNode }) {
  return <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">{children}</div>;
}

export type Column<T> = {
  key: string;
  label: string;
  align?: "left" | "right";
  render: (row: T) => ReactNode;
};

export function ModuleTable<T>({
  columns,
  data,
  rowKey,
  emptyMessage,
  caption,
}: {
  columns: Column<T>[];
  data: T[];
  rowKey: (row: T) => string;
  emptyMessage: string;
  caption?: string;
}) {
  if (data.length === 0) {
    return (
      <div
        data-testid="module-empty"
        className="rounded-md border border-dashed border-border p-8 text-center text-sm text-muted-foreground"
      >
        {emptyMessage}
      </div>
    );
  }
  return (
    <div className="overflow-x-auto rounded-md border border-border">
      <table className="min-w-full divide-y divide-border text-sm">
        {caption ? <caption className="sr-only">{caption}</caption> : null}
        <thead className="bg-surface-elevated">
          <tr>
            {columns.map((c) => (
              <th
                key={c.key}
                scope="col"
                className={cn(
                  "whitespace-nowrap px-4 py-3 font-medium text-muted-foreground",
                  c.align === "right" ? "text-right" : "text-left"
                )}
              >
                {c.label}
              </th>
            ))}
          </tr>
        </thead>
        <tbody className="divide-y divide-border">
          {data.map((row) => (
            <tr key={rowKey(row)} className="hover:bg-muted/40">
              {columns.map((c) => (
                <td
                  key={c.key}
                  className={cn(
                    "px-4 py-3 text-foreground",
                    c.align === "right" ? "whitespace-nowrap text-right tabular-nums" : "text-left"
                  )}
                >
                  {c.render(row)}
                </td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

export function DemoNotice({ children }: { children: ReactNode }) {
  return (
    <p
      data-testid="demo-notice"
      className="rounded-md border border-warning/30 bg-warning/10 px-4 py-3 text-xs text-warning"
    >
      {children}
    </p>
  );
}
