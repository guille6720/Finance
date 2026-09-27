"use client";

import { useId, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { Building2, ChevronsUpDown, Loader2 } from "lucide-react";
import { cn } from "@/lib/utils";
import type { UserOrganization } from "@/lib/authz/active-organization";

export const ACTIVE_ORGANIZATION_ENDPOINT = "/api/organizations/active";

export async function requestActiveOrganization(
  organizationId: string,
  fetcher: typeof fetch = fetch
): Promise<{ ok: true } | { ok: false; status: number }> {
  const res = await fetcher(ACTIVE_ORGANIZATION_ENDPOINT, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    credentials: "same-origin",
    body: JSON.stringify({ organizationId }),
  });
  return res.ok ? { ok: true } : { ok: false, status: res.status };
}

export function OrganizationSwitcher({
  organizations,
  activeOrganizationId,
  onSwitched,
}: {
  organizations: UserOrganization[];
  activeOrganizationId: string | null;
  onSwitched?: () => void;
}) {
  const router = useRouter();
  const selectId = useId();
  const [selected, setSelected] = useState(activeOrganizationId ?? "");
  const [switching, setSwitching] = useState(false);
  const [isPending, startTransition] = useTransition();
  const [error, setError] = useState<string | null>(null);
  const [lastServerValue, setLastServerValue] = useState(activeOrganizationId);

  // Server-side active org changed (e.g. after refresh): follow it.
  if (activeOrganizationId !== lastServerValue) {
    setLastServerValue(activeOrganizationId);
    setSelected(activeOrganizationId ?? "");
  }

  const busy = switching || isPending;
  const active = organizations.find((o) => o.id === (activeOrganizationId ?? selected));

  if (organizations.length === 0) {
    return (
      <p className="text-xs text-sidebar-muted" data-testid="org-switcher-empty">
        Sin empresa
      </p>
    );
  }

  if (organizations.length === 1) {
    const only = organizations[0];
    return (
      <div data-testid="org-switcher-single">
        <p className="text-[11px] font-semibold uppercase tracking-wider text-sidebar-muted">
          Empresa
        </p>
        <p className="mt-1 flex items-center gap-2 truncate text-sm font-medium" title={only.legalName}>
          <Building2 className="h-4 w-4 shrink-0 text-sidebar-muted" aria-hidden />
          <span className="truncate">{only.displayName}</span>
        </p>
      </div>
    );
  }

  async function handleChange(nextId: string) {
    if (!nextId || nextId === selected || busy) return;
    const previous = selected;
    setSelected(nextId);
    setError(null);
    setSwitching(true);
    try {
      const result = await requestActiveOrganization(nextId);
      if (!result.ok) {
        setSelected(previous);
        setError(
          result.status === 403
            ? "No tenés acceso a esa empresa."
            : "No se pudo cambiar de empresa. Intentá de nuevo."
        );
        return;
      }
      startTransition(() => {
        router.push("/dashboard");
        router.refresh();
      });
      onSwitched?.();
    } catch {
      setSelected(previous);
      setError("No se pudo cambiar de empresa. Intentá de nuevo.");
    } finally {
      setSwitching(false);
    }
  }

  return (
    <div data-testid="org-switcher-multi">
      <label
        htmlFor={selectId}
        className="text-[11px] font-semibold uppercase tracking-wider text-sidebar-muted"
      >
        Empresa
      </label>
      <div className="relative mt-1">
        <Building2
          className="pointer-events-none absolute left-2.5 top-1/2 h-4 w-4 -translate-y-1/2 text-sidebar-muted"
          aria-hidden
        />
        <select
          id={selectId}
          value={selected}
          disabled={busy}
          aria-busy={busy}
          title={active?.legalName}
          onChange={(e) => handleChange(e.target.value)}
          className={cn(
            "w-full appearance-none truncate rounded-md border border-white/10 bg-sidebar-active/60 py-2 pl-8 pr-8 text-sm font-medium text-sidebar-foreground",
            "focus:outline-none focus:ring-2 focus:ring-primary/60",
            "disabled:cursor-wait disabled:opacity-70"
          )}
        >
          {organizations.map((o) => (
            <option key={o.id} value={o.id} className="bg-sidebar text-sidebar-foreground">
              {o.displayName}
            </option>
          ))}
        </select>
        {busy ? (
          <Loader2
            className="pointer-events-none absolute right-2.5 top-1/2 h-4 w-4 -translate-y-1/2 animate-spin text-sidebar-muted"
            aria-label="Cambiando de empresa"
          />
        ) : (
          <ChevronsUpDown
            className="pointer-events-none absolute right-2.5 top-1/2 h-4 w-4 -translate-y-1/2 text-sidebar-muted"
            aria-hidden
          />
        )}
      </div>
      {busy ? (
        <p className="mt-1 text-xs text-sidebar-muted" role="status">
          Cambiando de empresa…
        </p>
      ) : null}
      {error ? (
        <p className="mt-1 text-xs text-danger" role="alert">
          {error}
        </p>
      ) : null}
    </div>
  );
}
