"use client";

import { ThemeToggle } from "@/components/theme/theme-toggle";
import { UxModeSwitcher } from "@/components/shell/ux-mode-switcher";
import type { UxMode } from "@/lib/ui-mode/constants";

export function AppTopbar({
  title,
  uxMode = "business",
}: {
  title?: string;
  uxMode?: UxMode;
}) {
  return (
    <header className="sticky top-0 z-30 flex h-14 items-center justify-between gap-3 border-b border-border bg-surface/95 px-4 backdrop-blur lg:px-8">
      <div className="min-w-0 pl-12 lg:pl-0">
        {title ? <h1 className="truncate text-sm font-semibold text-foreground">{title}</h1> : null}
      </div>
      <div className="flex items-center gap-2">
        <UxModeSwitcher mode={uxMode} />
        <ThemeToggle />
      </div>
    </header>
  );
}
