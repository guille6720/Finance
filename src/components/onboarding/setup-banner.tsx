"use client";

import { useActionState } from "react";
import { Button } from "@/components/ui/button";
import { finishOrganizationSetup, type FinishSetupState } from "@/lib/onboarding/actions";

export function SetupBanner() {
  const [state, action, pending] = useActionState<FinishSetupState>(finishOrganizationSetup, {});
  return (
    <div
      role="status"
      data-testid="setup-banner"
      className="mb-6 flex flex-wrap items-center justify-between gap-3 rounded-md border border-warning/40 bg-warning/10 p-4 text-sm"
    >
      <div>
        <p className="font-medium">Falta terminar la configuración de esta empresa.</p>
        <p className="text-muted-foreground">
          Se crean el plan de cuentas, el ejercicio contable, la caja y el depósito para que puedas cargar
          operaciones.
        </p>
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
