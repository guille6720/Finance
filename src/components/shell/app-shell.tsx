"use client";

import { useState } from "react";
import { AppSidebar } from "@/components/shell/app-sidebar";
import { AppTopbar } from "@/components/shell/app-topbar";

export function AppShell({
  companyName,
  userName,
  title,
  children,
}: {
  companyName?: string;
  userName?: string;
  title?: string;
  children: React.ReactNode;
}) {
  const [uxMode, setUxMode] = useState<"business" | "accountant">("business");

  return (
    <div className="min-h-screen bg-background">
      <AppSidebar companyName={companyName} userName={userName} />
      <div className="lg:pl-64">
        <AppTopbar
          title={title}
          uxMode={uxMode}
          onToggleUxMode={() =>
            setUxMode((m) => (m === "business" ? "accountant" : "business"))
          }
        />
        <main className="mx-auto max-w-6xl p-4 lg:p-6">{children}</main>
      </div>
    </div>
  );
}
