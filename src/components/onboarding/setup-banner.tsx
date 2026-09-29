"use client";

import { useActionState } from "react";
import { Button } from "@/components/ui/button";
import { finishOrganizationSetup, type FinishSetupState } from "@/lib/onboarding/actions";

const COPY = {
  setup: {
    title: "Falta terminar la configuración de esta empresa.",
    body: "Se crean el plan de cuentas, el ejercicio contable, la caja y el depósito para que puedas cargar operaciones.",
  },
  demo: {
    title: "Faltan cargar los datos de prueba de esta empresa.",
    body: "Se agregan clientes, proveedores, productos, movimientos de caja, ventas y compras de ejemplo para que puedas probar el sistema.",
  },
} as const;

export function SetupBanner({ variant = "setup" }: { variant?: keyof typeof COPY }) {
  const [state, action, pending] = useActionState<FinishSetupState>(finishOrganizationSetup, {});
  const copy = COPY[variant];
  return (
    <div
      role="status"
      data-testid="setup-banner"
      className="mb-6 flex flex-wrap items-center justify-between gap-3 rounded-md border border-warning/40 bg-warning/10 p-4 text-sm"
    >
      <div>
        <p className="font-medium">{copy.title}</p>
        <p className="text-muted-foreground">{copy.body}</p>
        {state.error ? (
          <p role="alert" className="mt-1 text-danger">
            {state.error}
          </p>
        ) : null}
      </div>
      <form action={action}>
        <Button type="submit" disabled={pending}>
          {pending ? "Configurando…" : "Completar configuración"}
        </Button>
      </form>
    </div>
  );
}
