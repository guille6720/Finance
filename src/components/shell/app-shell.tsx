"use client";

import { useState } from "react";
import { AppSidebar } from "@/components/shell/app-sidebar";
import { AppTopbar } from "@/components/shell/app-topbar";
import type { UserOrganization } from "@/lib/authz/active-organization";

export function AppShell({
  companyName,
  userName,
  title,
  organizations = [],
  activeOrganizationId = null,
  children,
}: {
  companyName?: string;
  userName?: string;
  title?: string;
  organizations?: UserOrganization[];
  activeOrganizationId?: string | null;
  children: React.ReactNode;
}) {
  const [uxMode, setUxMode] = useState<"business" | "accountant">("business");

  return (
    <div className="min-h-screen bg-background">
      <AppSidebar
        companyName={companyName}
        userName={userName}
        organizations={organizations}
        activeOrganizationId={activeOrganizationId}
      />
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
