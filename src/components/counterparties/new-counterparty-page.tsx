import Link from "next/link";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { ModuleHeader } from "@/components/demo/module-ui";
import { CounterpartyForm } from "@/components/counterparties/counterparty-form";
import { roleHasPermission } from "@/lib/authz/permissions";
import { requireActiveOrganization } from "@/lib/demo-data/organization-context";
import type { CounterpartyRoleCode } from "@/lib/counterparties/schema";

const COPY: Record<CounterpartyRoleCode, { title: string; description: string; back: string; backHref: string }> = {
  CUSTOMER: {
    title: "Nuevo cliente",
    description: "Cargá los datos del cliente. Se agrega a la empresa activa.",
    back: "Volver a clientes",
    backHref: "/customers",
  },
  SUPPLIER: {
    title: "Nuevo proveedor",
    description: "Cargá los datos del proveedor. Se agrega a la empresa activa.",
    back: "Volver a proveedores",
    backHref: "/suppliers",
  },
};

export async function NewCounterpartyPage({ role }: { role: CounterpartyRoleCode }) {
  const copy = COPY[role];
  const { role: memberRole } = await requireActiveOrganization();
  const canCreate = roleHasPermission(memberRole, "counterparties.create");

  return (
    <div className="space-y-6">
      <ModuleHeader title={copy.title} description={copy.description} />
      <Card className="max-w-2xl">
        <CardHeader>
          <CardTitle>Datos</CardTitle>
          <CardDescription>Los campos con * son obligatorios.</CardDescription>
        </CardHeader>
        <CardContent>
          {canCreate ? (
            <CounterpartyForm role={role} />
          ) : (
            <div className="space-y-4" data-testid="counterparty-forbidden">
              <p role="alert" className="text-sm text-muted-foreground">
                Tu rol en esta empresa no permite dar de alta registros. Pedile a un administrador que lo
                haga o que te asigne un rol con ese permiso.
              </p>
              <Button asChild variant="outline">
                <Link href={copy.backHref}>{copy.back}</Link>
              </Button>
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
