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
} from "lucide-react";
import { useState } from "react";
import { cn } from "@/lib/utils";
import { brand } from "@/config/brand";
import { createClient } from "@/lib/supabase/client";
import { useRouter } from "next/navigation";
import { OrganizationSwitcher } from "@/components/shell/organization-switcher";
import type { UserOrganization } from "@/lib/authz/active-organization";

type NavItem = {
  name: string;
  href: string;
  icon: ComponentType<{ className?: string }>;
  status?: "active" | "coming_soon";
};

type NavGroup = {
  label?: string;
  items: NavItem[];
};

const navigation: NavGroup[] = [
  {
    items: [
      { name: "Dashboard", href: "/dashboard", icon: LayoutDashboard, status: "active" },
    ],
  },
  {
    label: "Gestión",
    items: [
      { name: "Clientes", href: "/customers", icon: Users, status: "coming_soon" },
      { name: "Proveedores", href: "/suppliers", icon: Truck, status: "coming_soon" },
    ],
  },
  {
    label: "Finanzas",
    items: [
      { name: "Caja", href: "/cash", icon: Wallet, status: "coming_soon" },
      { name: "Bancos", href: "/banks", icon: Landmark, status: "coming_soon" },
    ],
  },
  {
    label: "Contabilidad",
    items: [
      { name: "Contabilidad", href: "/accounting", icon: Calculator, status: "coming_soon" },
    ],
  },
  {
    label: "Reportes",
    items: [
      { name: "Reportes", href: "/reports", icon: FileText, status: "coming_soon" },
    ],
  },
  {
    label: "Administración",
    items: [
      { name: "Empresa", href: "/company", icon: Building2, status: "active" },
      { name: "Usuarios", href: "/users", icon: UserCog, status: "active" },
      { name: "Configuración", href: "/settings", icon: Settings, status: "active" },
    ],
  },
];

export function AppSidebar({
  companyName,
  userName,
  organizations = [],
  activeOrganizationId = null,
}: {
  companyName?: string;
  userName?: string;
  organizations?: UserOrganization[];
  activeOrganizationId?: string | null;
}) {
  const pathname = usePathname();
  const router = useRouter();
  const [mobileOpen, setMobileOpen] = useState(false);

  async function handleSignOut() {
    const supabase = createClient();
    await supabase.auth.signOut();
    router.push("/login");
    router.refresh();
  }

  const Nav = (
    <div className="flex h-full flex-col bg-sidebar text-sidebar-foreground">
      <div className="border-b border-white/10 p-4">
        <Link href="/dashboard" className="flex items-center gap-3">
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
        {organizations.length > 0 ? (
          <div className="mt-4">
            <OrganizationSwitcher
              organizations={organizations}
              activeOrganizationId={activeOrganizationId}
              onSwitched={() => setMobileOpen(false)}
            />
          </div>
        ) : null}
      </div>

      <nav className="flex-1 space-y-4 overflow-y-auto p-3" aria-label="Principal">
        {navigation.map((group) => (
          <div key={group.label ?? "root"} className="space-y-1">
            {group.label ? (
              <p className="px-3 pb-1 text-[11px] font-semibold uppercase tracking-wider text-sidebar-muted">
                {group.label}
              </p>
            ) : null}
            {group.items.map((item) => {
              const active =
                pathname === item.href || pathname.startsWith(item.href + "/");
              const coming = item.status === "coming_soon";
              return (
                <Link
                  key={item.href}
                  href={item.href}
                  onClick={() => setMobileOpen(false)}
                  aria-current={active ? "page" : undefined}
                  className={cn(
                    "flex items-center gap-3 rounded-md px-3 py-2 text-sm font-medium transition-colors",
                    active
                      ? "bg-sidebar-active text-sidebar-foreground"
                      : "text-sidebar-muted hover:bg-sidebar-active/70 hover:text-sidebar-foreground"
                  )}
                >
                  <item.icon className="h-4 w-4 shrink-0" />
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
      <button
        type="button"
        className="fixed left-4 top-4 z-50 rounded-md border border-border bg-surface p-2 lg:hidden"
        aria-label={mobileOpen ? "Cerrar menú" : "Abrir menú"}
        onClick={() => setMobileOpen((v) => !v)}
      >
        {mobileOpen ? <X className="h-5 w-5" /> : <Menu className="h-5 w-5" />}
      </button>

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
