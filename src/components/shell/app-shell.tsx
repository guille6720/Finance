"use client";

import { AppSidebar } from "@/components/shell/app-sidebar";
import { AppTopbar } from "@/components/shell/app-topbar";
import type { UserOrganization } from "@/lib/authz/active-organization";
import type { UxMode } from "@/lib/ui-mode/constants";

export function AppShell({
  companyName,
  userName,
  title,
  organizations = [],
  activeOrganizationId = null,
  uxMode = "business",
  children,
}: {
  companyName?: string;
  userName?: string;
  title?: string;
  organizations?: UserOrganization[];
  activeOrganizationId?: string | null;
  uxMode?: UxMode;
  children: React.ReactNode;
}) {
  return (
    <div className="min-h-screen bg-background" data-ux-mode={uxMode}>
      <AppSidebar
        companyName={companyName}
        userName={userName}
        organizations={organizations}
        activeOrganizationId={activeOrganizationId}
        uxMode={uxMode}
      />
      <div className="lg:pl-64">
        <AppTopbar title={title} uxMode={uxMode} />
        <main className="mx-auto max-w-[1400px] p-4 lg:p-8">{children}</main>
      </div>
    </div>
  );
}
