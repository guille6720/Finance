"use client";

import type { ComponentType } from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import {
  LayoutDashboard,
  Users,
  Truck,
  Wallet,
  Landmark,
  Calculator,
  FileText,
  Building2,
  UserCog,
  Settings,
  Menu,
  X,
  LogOut,
  Clock3,
  Briefcase,
  BookOpenCheck,
} from "lucide-react";
import { useState } from "react";
import { cn } from "@/lib/utils";
import { brand } from "@/config/brand";
import { createClient } from "@/lib/supabase/client";
import { useRouter } from "next/navigation";
import { OrganizationSwitcher } from "@/components/shell/organization-switcher";
import type { UserOrganization } from "@/lib/authz/active-organization";
import { UX_MODE_LABELS, type UxMode } from "@/lib/ui-mode/constants";

type NavItem = {
  name: string;
  href: string;
  icon: ComponentType<{ className?: string }>;
  status?: "active" | "coming_soon";
};

type NavEmphasis = "primary" | "secondary" | "admin";

type NavGroup = {
  label?: string;
  emphasis: NavEmphasis;
  items: NavItem[];
};

const ITEMS = {
  dashboard: { name: "Dashboard", href: "/dashboard", icon: LayoutDashboard, status: "active" },
  customers: { name: "Clientes", href: "/customers", icon: Users, status: "active" },
  suppliers: { name: "Proveedores", href: "/suppliers", icon: Truck, status: "active" },
  cash: { name: "Caja", href: "/cash", icon: Wallet, status: "active" },
  banks: { name: "Bancos", href: "/banks", icon: Landmark, status: "coming_soon" },
  accounting: { name: "Contabilidad", href: "/accounting", icon: Calculator, status: "active" },
  reports: { name: "Reportes", href: "/reports", icon: FileText, status: "active" },
  company: { name: "Empresa", href: "/company", icon: Building2, status: "active" },
  users: { name: "Usuarios", href: "/users", icon: UserCog, status: "active" },
  settings: { name: "Configuración", href: "/settings", icon: Settings, status: "active" },
} satisfies Record<string, NavItem>;

const ADMIN_GROUP: NavGroup = {
  label: "Administración",
  emphasis: "admin",
  items: [ITEMS.company, ITEMS.users, ITEMS.settings],
};

/** Same destinations in both modes; only order and emphasis change. */
export function navigationForMode(mode: UxMode): NavGroup[] {
  if (mode === "accountant") {
    return [
      {
        label: "Contabilidad",
        emphasis: "primary",
        items: [ITEMS.dashboard, ITEMS.accounting, ITEMS.reports],
      },
      {
        label: "Gestión comercial",
        emphasis: "secondary",
        items: [ITEMS.customers, ITEMS.suppliers, ITEMS.cash, ITEMS.banks],
      },
      ADMIN_GROUP,
    ];
  }
  return [
    {
      label: "Tu negocio",
      emphasis: "primary",
      items: [
        ITEMS.dashboard,
        ITEMS.customers,
        ITEMS.suppliers,
        ITEMS.cash,
        ITEMS.banks,
        ITEMS.reports,
      ],
    },
    {
      label: "Contabilidad",
      emphasis: "secondary",
      items: [ITEMS.accounting],
    },
    ADMIN_GROUP,
  ];
}

export const navigation: NavGroup[] = navigationForMode("business");

export function AppSidebar({
  companyName,
  userName,
  organizations = [],
  activeOrganizationId = null,
  uxMode = "business",
}: {
  companyName?: string;
  userName?: string;
  organizations?: UserOrganization[];
  activeOrganizationId?: string | null;
  uxMode?: UxMode;
}) {
  const pathname = usePathname();
  const router = useRouter();
  const [mobileOpen, setMobileOpen] = useState(false);
  const groups = navigationForMode(uxMode);
  const ModeIcon = uxMode === "accountant" ? BookOpenCheck : Briefcase;

  async function handleSignOut() {
    const supabase = createClient();
    await supabase.auth.signOut();
    router.push("/login");
    router.refresh();
  }

  const Nav = (
    <div className="flex h-full flex-col bg-sidebar text-sidebar-foreground">
      <div className="border-b border-white/10 p-4">
        <div className="flex items-start justify-between gap-2">
          <Link href="/dashboard" className="flex min-w-0 items-center gap-3">
            {/* Place temporary logo at public/brand/logo-dark.png — config-driven */}
            <div
              className="flex h-9 w-9 items-center justify-center rounded-md bg-primary/20 text-primary-bright"
              aria-hidden
            >
              <Building2 className="h-5 w-5" />
            </div>
            <div className="min-w-0">
              <p className="truncate text-sm font-semibold tracking-tight">{brand.name}</p>
              {organizations.length === 0 ? (
                <p className="truncate text-xs text-sidebar-muted">
                  {companyName || "Sin empresa"}
                </p>
              ) : null}
            </div>
          </Link>
          <button
            type="button"
            className="rounded-md p-1.5 text-sidebar-muted hover:bg-sidebar-active hover:text-sidebar-foreground lg:hidden"
            aria-label="Cerrar menú"
            onClick={() => setMobileOpen(false)}
          >
            <X className="h-5 w-5" />
          </button>
        </div>
        {organizations.length > 0 ? (
          <div className="mt-4">
            <OrganizationSwitcher
              organizations={organizations}
              activeOrganizationId={activeOrganizationId}
              onSwitched={() => setMobileOpen(false)}
            />
          </div>
        ) : null}
        <p
          data-testid="sidebar-mode"
          className={cn(
            "mt-3 inline-flex items-center gap-1.5 rounded-md px-2 py-1 text-[11px] font-semibold uppercase tracking-wider",
            uxMode === "accountant"
              ? "bg-success/15 text-success"
              : "bg-primary/20 text-primary-bright"
          )}
        >
          <ModeIcon className="h-3.5 w-3.5" aria-hidden />
          {UX_MODE_LABELS[uxMode]}
        </p>
      </div>

      <nav className="flex-1 space-y-5 overflow-y-auto p-3" aria-label="Principal">
        {groups.map((group) => (
          <div
            key={group.label ?? "root"}
            className="space-y-1"
            data-testid={`nav-group-${group.emphasis}`}
          >
            {group.label ? (
              <p
                className={cn(
                  "px-3 pb-1 text-[11px] font-semibold uppercase tracking-wider",
                  group.emphasis === "primary" ? "text-sidebar-foreground/80" : "text-sidebar-muted"
                )}
              >
                {group.label}
              </p>
            ) : null}
            {group.items.map((item) => {
              const active =
                pathname === item.href || pathname.startsWith(item.href + "/");
              const coming = item.status === "coming_soon";
              const primary = group.emphasis === "primary";
              return (
                <Link
                  key={item.href}
                  href={item.href}
                  onClick={() => setMobileOpen(false)}
                  aria-current={active ? "page" : undefined}
                  data-emphasis={group.emphasis}
                  className={cn(
                    "relative flex items-center gap-3 rounded-md px-3 transition-colors",
                    primary ? "py-2 text-sm font-medium" : "py-1.5 text-[13px]",
                    active
                      ? "bg-sidebar-active text-sidebar-foreground before:absolute before:inset-y-1.5 before:left-0 before:w-0.5 before:rounded-full before:bg-primary-bright"
                      : primary
                        ? "text-sidebar-foreground/85 hover:bg-sidebar-active/70 hover:text-sidebar-foreground"
                        : "text-sidebar-muted hover:bg-sidebar-active/50 hover:text-sidebar-foreground"
                  )}
                >
                  <item.icon className={cn("shrink-0", primary ? "h-4 w-4" : "h-3.5 w-3.5")} />
                  <span className="flex-1 truncate">{item.name}</span>
                  {coming ? (
                    <span className="inline-flex items-center gap-1 text-[10px] text-sidebar-muted">
                      <Clock3 className="h-3 w-3" />
                      Pronto
                    </span>
                  ) : null}
                </Link>
              );
            })}
          </div>
        ))}
      </nav>

      <div className="border-t border-white/10 p-4">
        <p className="truncate text-sm font-medium">{userName}</p>
        <button
          type="button"
          onClick={handleSignOut}
          className="mt-2 flex items-center gap-2 text-sm text-sidebar-muted hover:text-danger"
        >
          <LogOut className="h-4 w-4" />
          Cerrar sesión
        </button>
      </div>
    </div>
  );

  return (
    <>
      {mobileOpen ? null : (
        <button
          type="button"
          className="fixed left-4 top-4 z-50 rounded-md border border-border bg-surface p-2 lg:hidden"
          aria-label="Abrir menú"
          aria-expanded={false}
          onClick={() => setMobileOpen(true)}
        >
          <Menu className="h-5 w-5" />
        </button>
      )}

      {mobileOpen ? (
        <div
          className="fixed inset-0 z-40 bg-[color:var(--overlay)] lg:hidden"
          onClick={() => setMobileOpen(false)}
        />
      ) : null}

      <aside
        className={cn(
          "fixed inset-y-0 left-0 z-50 w-64 border-r border-white/10 transition-transform lg:translate-x-0",
          mobileOpen ? "translate-x-0" : "-translate-x-full"
        )}
      >
        {Nav}
      </aside>
    </>
  );
}
