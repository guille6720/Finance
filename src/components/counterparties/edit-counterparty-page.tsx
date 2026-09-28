import Link from "next/link";
import { notFound } from "next/navigation";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { LoadError, ModuleHeader } from "@/components/demo/module-ui";
import { CounterpartyForm } from "@/components/counterparties/counterparty-form";
import { CounterpartyStatusActions } from "@/components/counterparties/counterparty-status-actions";
import { roleHasPermission } from "@/lib/authz/permissions";
import { isUuid } from "@/lib/authz/active-organization";
import { requireActiveOrganization } from "@/lib/demo-data/organization-context";
import type { CounterpartyRoleCode } from "@/lib/counterparties/schema";

const COPY: Record<CounterpartyRoleCode, { singular: string; back: string; backHref: string }> = {
  CUSTOMER: { singular: "cliente", back: "Volver a clientes", backHref: "/customers" },
  SUPPLIER: { singular: "proveedor", back: "Volver a proveedores", backHref: "/suppliers" },
};

export type CounterpartyPageNotice = "activado" | "desactivado" | null;

export async function EditCounterpartyPage({
  role,
  id,
  notice = null,
}: {
  role: CounterpartyRoleCode;
  id: string;
  notice?: CounterpartyPageNotice;
}) {
  if (!isUuid(id)) notFound();
  const copy = COPY[role];
  const { supabase, organizationId, role: memberRole } = await requireActiveOrganization();
  const { data, error } = await supabase
    .from("counterparties")
    .select(
      "id, legal_name, trade_name, entity_type, tax_id_type, tax_id, email, phone, is_active, counterparty_roles ( role )"
    )
    .eq("id", id)
    .eq("organization_id", organizationId)
    .maybeSingle();

  if (error) {
    console.error("[counterparties] load for edit failed", { code: error.code });
    return (
      <div className="space-y-6">
        <ModuleHeader title={`Editar ${copy.singular}`} description="" />
        <LoadError />
      </div>
    );
  }
  const roles = new Set(((data?.counterparty_roles as { role: string }[] | null) ?? []).map((r) => r.role));
  if (!data || !roles.has(role)) notFound();

  const canUpdate = roleHasPermission(memberRole, "counterparties.update");
  const canDelete = roleHasPermission(memberRole, "counterparties.delete");
  const other = role === "CUSTOMER" ? "SUPPLIER" : "CUSTOMER";
  const name = (data.trade_name as string | null)?.trim() || (data.legal_name as string);
  const initial: Record<string, string | boolean> = {
    legalName: data.legal_name ?? "",
    tradeName: data.trade_name ?? "",
    entityType: data.entity_type === "INDIVIDUAL" ? "INDIVIDUAL" : "LEGAL_ENTITY",
    taxIdType: ["CUIT", "CUIL", "DNI", "PASSPORT", "NONE"].includes(data.tax_id_type) ? data.tax_id_type : "NONE",
    taxId: data.tax_id ?? "",
    email: data.email ?? "",
    phone: data.phone ?? "",
    alsoOtherRole: roles.has(other),
  };

  return (
    <div className="space-y-6">
      <ModuleHeader
        title={name}
        description={`Datos del ${copy.singular} en la empresa activa.`}
        action={
          <Button asChild variant="outline">
            <Link href={copy.backHref}>{copy.back}</Link>
          </Button>
        }
      />
      {notice ? (
        <p
          role="status"
          className="rounded-md border border-success/30 bg-success/10 p-3 text-sm text-success"
        >
          {notice === "activado" ? "Reactivado correctamente." : "Desactivado: ya no se ofrece para nuevas operaciones."}
        </p>
      ) : null}
      <Card className="max-w-2xl">
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            Datos{" "}
            <Badge tone={data.is_active ? "success" : "neutral"}>{data.is_active ? "Activo" : "Inactivo"}</Badge>
          </CardTitle>
          <CardDescription>
            {canUpdate ? "Modificá los datos y guardá los cambios." : "Tu rol permite ver estos datos pero no modificarlos."}
          </CardDescription>
        </CardHeader>
        <CardContent>
          {canUpdate ? (
            <CounterpartyForm
              role={role}
              edit={{
                id: data.id as string,
                initial,
                showOtherRole: !roles.has(other) && roleHasPermission(memberRole, "counterparties.create"),
              }}
            />
          ) : (
            <dl className="grid gap-2 text-sm">
              <div>
                <dt className="text-muted-foreground">Documento</dt>
                <dd>{data.tax_id || "—"}</dd>
              </div>
              <div>
                <dt className="text-muted-foreground">Email</dt>
                <dd>{data.email || "—"}</dd>
              </div>
            </dl>
          )}
        </CardContent>
      </Card>
      {canUpdate || canDelete ? (
        <Card className="max-w-2xl">
          <CardHeader>
            <CardTitle>Estado</CardTitle>
            <CardDescription>
              Desactivar lo oculta para nuevas operaciones sin perder el historial. Eliminar solo es posible si no
              tiene comprobantes ni asientos.
            </CardDescription>
          </CardHeader>
          <CardContent>
            <CounterpartyStatusActions
              role={role}
              id={data.id as string}
              name={name}
              isActive={Boolean(data.is_active)}
              canUpdate={canUpdate}
              canDelete={canDelete}
            />
          </CardContent>
        </Card>
      ) : null}
    </div>
  );
}
