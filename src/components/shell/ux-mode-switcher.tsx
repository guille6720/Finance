"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { BookOpenCheck, Briefcase, Loader2 } from "lucide-react";
import { cn } from "@/lib/utils";
import {
  UX_MODE_ENDPOINT,
  UX_MODE_LABELS,
  type UxMode,
} from "@/lib/ui-mode/constants";

export async function requestUxMode(
  mode: UxMode,
  fetcher: typeof fetch = fetch
): Promise<{ ok: boolean; status: number }> {
  const res = await fetcher(UX_MODE_ENDPOINT, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    credentials: "same-origin",
    body: JSON.stringify({ mode }),
  });
  return { ok: res.ok, status: res.status };
}

const OPTIONS: { mode: UxMode; icon: typeof Briefcase; short: string }[] = [
  { mode: "business", icon: Briefcase, short: "Negocio" },
  { mode: "accountant", icon: BookOpenCheck, short: "Contabilidad" },
];

export function UxModeSwitcher({ mode }: { mode: UxMode }) {
  const router = useRouter();
  const [selected, setSelected] = useState<UxMode>(mode);
  const [lastServerMode, setLastServerMode] = useState<UxMode>(mode);
  const [saving, setSaving] = useState(false);
  const [isPending, startTransition] = useTransition();
  const [error, setError] = useState(false);

  if (mode !== lastServerMode) {
    setLastServerMode(mode);
    setSelected(mode);
  }

  const busy = saving || isPending;

  async function choose(next: UxMode) {
    if (next === selected || busy) return;
    const previous = selected;
    setSelected(next);
    setError(false);
    setSaving(true);
    try {
      const result = await requestUxMode(next);
      if (!result.ok) {
        setSelected(previous);
        setError(true);
        return;
      }
      startTransition(() => router.refresh());
    } catch {
      setSelected(previous);
      setError(true);
    } finally {
      setSaving(false);
    }
  }

  return (
    <div className="flex items-center gap-2">
      <div
        role="group"
        aria-label="Modo de experiencia"
        data-testid="ux-mode-switcher"
        data-mode={selected}
        className="inline-flex items-center rounded-lg border border-border bg-surface-elevated p-0.5"
      >
        {OPTIONS.map(({ mode: option, icon: Icon, short }) => {
          const active = option === selected;
          return (
            <button
              key={option}
              type="button"
              onClick={() => choose(option)}
              aria-pressed={active}
              disabled={busy}
              title={UX_MODE_LABELS[option]}
              data-testid={`ux-mode-${option}`}
              className={cn(
                "inline-flex items-center gap-1.5 rounded-md px-2.5 py-1 text-xs font-medium transition-colors",
                "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary/60",
                "disabled:cursor-wait",
                active
                  ? option === "business"
                    ? "bg-primary text-primary-foreground shadow-sm"
                    : "bg-success/90 text-success-foreground shadow-sm"
                  : "text-muted-foreground hover:bg-muted hover:text-foreground"
              )}
            >
              <Icon className="h-3.5 w-3.5" aria-hidden />
              <span className="hidden md:inline">{UX_MODE_LABELS[option]}</span>
              <span className="md:hidden">{short}</span>
            </button>
          );
        })}
      </div>
      {busy ? (
        <Loader2 className="h-4 w-4 animate-spin text-muted-foreground" aria-label="Cambiando de modo" />
      ) : null}
      {error ? (
        <span role="alert" className="text-xs text-danger">
          No se pudo cambiar el modo.
        </span>
      ) : null}
    </div>
  );
}
