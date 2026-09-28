"use client";

import { useState, useTransition } from "react";
import { Button } from "@/components/ui/button";
import { deleteCounterparty, setCounterpartyActive } from "@/lib/counterparties/actions";
import type { CounterpartyRoleCode } from "@/lib/counterparties/schema";

export function CounterpartyStatusActions({
  role,
  id,
  name,
  isActive,
  canUpdate,
  canDelete,
}: {
  role: CounterpartyRoleCode;
  id: string;
  name: string;
  isActive: boolean;
  canUpdate: boolean;
  canDelete: boolean;
}) {
  const [pending, startTransition] = useTransition();
  const [error, setError] = useState<string | null>(null);

  function run(fn: () => Promise<{ error?: string } | void>) {
    setError(null);
    startTransition(async () => {
      const result = await fn();
      if (result?.error) setError(result.error);
    });
  }

  return (
    <div className="space-y-3" data-testid="counterparty-status-actions">
      <div className="flex flex-wrap gap-3">
        {canUpdate ? (
          <Button
            type="button"
            variant="outline"
            disabled={pending}
            onClick={() => run(() => setCounterpartyActive(role, id, !isActive))}
          >
            {isActive ? "Desactivar" : "Reactivar"}
          </Button>
        ) : null}
        {canDelete ? (
          <Button
            type="button"
            variant="outline"
            className="border-danger/40 text-danger hover:bg-danger/10"
            disabled={pending}
            onClick={() => {
              if (window.confirm(`¿Eliminar "${name}"? Esta acción no se puede deshacer.`)) {
                run(() => deleteCounterparty(role, id));
              }
            }}
          >
            Eliminar
          </Button>
        ) : null}
      </div>
      {error ? (
        <p role="alert" className="text-sm text-danger">
          {error}
        </p>
      ) : null}
    </div>
  );
}
