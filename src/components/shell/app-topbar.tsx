"use client";

import { ThemeToggle } from "@/components/theme/theme-toggle";
import { Badge } from "@/components/ui/badge";

export function AppTopbar({
  title,
  uxMode = "business",
  onToggleUxMode,
}: {
  title?: string;
  uxMode?: "business" | "accountant";
  onToggleUxMode?: () => void;
}) {
  return (
    <header className="sticky top-0 z-30 flex h-14 items-center justify-between border-b border-border bg-surface/95 px-4 backdrop-blur lg:px-6">
      <div className="pl-12 lg:pl-0">
        <h1 className="text-sm font-semibold text-foreground">{title}</h1>
      </div>
      <div className="flex items-center gap-2">
        <button
          type="button"
          onClick={onToggleUxMode}
          className="hidden items-center gap-2 rounded-md border border-border px-2 py-1 text-xs sm:inline-flex"
          aria-label="Cambiar modo de experiencia"
        >
          <Badge tone={uxMode === "business" ? "primary" : "neutral"}>
            {uxMode === "business" ? "Modo negocio" : "Modo contador"}
          </Badge>
        </button>
        <ThemeToggle />
      </div>
    </header>
  );
}
