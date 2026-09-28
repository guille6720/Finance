import Link from "next/link";
import { CheckCircle2, Circle } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { LoadError } from "@/components/demo/module-ui";
import { Panel } from "@/components/dashboard/dashboard-ui";

export type SetupState =
  | { ok: false }
  | {
      ok: true;
      checks: { orgActive: boolean; fiscal: boolean; branch: boolean; business: boolean; members: boolean };
    };

export function setupPercent(checks: Record<string, boolean>) {
  const values = Object.values(checks);
  return Math.round((values.filter(Boolean).length / values.length) * 100);
}

export function SetupProgress({ setup }: { setup: SetupState }) {
  if (!setup.ok) {
    return (
      <Panel title="Configuración de la empresa" testId="setup-progress">
        <LoadError />
      </Panel>
    );
  }
  const pct = setupPercent(setup.checks);
  const steps = [
    { done: setup.checks.fiscal, label: "Datos fiscales", href: "/company" },
    { done: setup.checks.branch, label: "Sucursal", href: "/company" },
    { done: setup.checks.business, label: "Perfil del negocio", href: "/company" },
    { done: setup.checks.members, label: "Equipo", href: "/users" },
  ];
  return (
    <Panel
      title="Configuración de la empresa"
      action={<Badge tone={pct >= 80 ? "success" : "warning"}>{pct}%</Badge>}
      testId="setup-progress"
    >
      <div
        className="h-1.5 overflow-hidden rounded-full bg-muted"
        role="progressbar"
        aria-label="Configuración de la empresa"
        aria-valuenow={pct}
        aria-valuemin={0}
        aria-valuemax={100}
      >
        <div className="h-full bg-primary" style={{ width: `${pct}%` }} />
      </div>
      <ul className="mt-3 space-y-1.5 text-sm">
        {steps.map((s) => (
          <li key={s.label}>
            <Link href={s.href} className="flex items-center gap-2 hover:text-primary-bright">
              {s.done ? (
                <CheckCircle2 className="h-4 w-4 text-success" aria-hidden />
              ) : (
                <Circle className="h-4 w-4 text-muted-foreground" aria-hidden />
              )}
              <span className={s.done ? "text-muted-foreground" : ""}>{s.label}</span>
            </Link>
          </li>
        ))}
      </ul>
    </Panel>
  );
}
