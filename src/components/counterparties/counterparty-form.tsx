"use client";

import Link from "next/link";
import { useActionState, useState } from "react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { createCounterparty, type CounterpartyFormState } from "@/lib/counterparties/actions";
import {
  ENTITY_TYPE_LABELS,
  ENTITY_TYPES,
  TAX_ID_TYPE_LABELS,
  TAX_ID_TYPES,
  type CounterpartyRoleCode,
  type TaxIdType,
} from "@/lib/counterparties/schema";

const SELECT_CLASS = "flex h-10 w-full rounded-md border border-border bg-input px-3 text-sm";

const COPY: Record<CounterpartyRoleCode, { cancelHref: string; submit: string; other: string }> = {
  CUSTOMER: { cancelHref: "/customers", submit: "Guardar cliente", other: "También es proveedor" },
  SUPPLIER: { cancelHref: "/suppliers", submit: "Guardar proveedor", other: "También es cliente" },
};

function FieldError({ id, message }: { id: string; message?: string }) {
  if (!message) return null;
  return (
    <p id={id} className="text-xs text-danger" role="alert">
      {message}
    </p>
  );
}

export function CounterpartyForm({ role }: { role: CounterpartyRoleCode }) {
  const copy = COPY[role];
  const [state, formAction, pending] = useActionState<CounterpartyFormState, FormData>(
    createCounterparty.bind(null, role),
    {}
  );
  const values = state.values ?? {};
  const text = (key: string, fallback = "") =>
    typeof values[key] === "string" ? (values[key] as string) : fallback;
  const [taxIdType, setTaxIdType] = useState<TaxIdType>(
    (text("taxIdType", "CUIT") as TaxIdType) || "CUIT"
  );
  const errors = state.fieldErrors ?? {};
  const describedBy = (key: string) => (errors[key] ? `${key}-error` : undefined);

  return (
    <form action={formAction} className="space-y-5" noValidate data-testid="counterparty-form">
      {state.error ? (
        <p
          role="alert"
          className="rounded-md border border-danger/30 bg-danger/10 p-3 text-sm text-danger"
        >
          {state.error}
        </p>
      ) : null}

      <div className="grid gap-4 sm:grid-cols-2">
        <div className="space-y-2 sm:col-span-2">
          <Label htmlFor="legalName">Razón social o nombre *</Label>
          <Input
            id="legalName"
            name="legalName"
            required
            maxLength={200}
            defaultValue={text("legalName")}
            aria-invalid={Boolean(errors.legalName)}
            aria-describedby={describedBy("legalName")}
            placeholder="Ej.: Distribuidora del Sur SA"
          />
          <FieldError id="legalName-error" message={errors.legalName} />
        </div>

        <div className="space-y-2 sm:col-span-2">
          <Label htmlFor="tradeName">Nombre comercial</Label>
          <Input
            id="tradeName"
            name="tradeName"
            maxLength={200}
            defaultValue={text("tradeName")}
            placeholder="Opcional"
          />
          <FieldError id="tradeName-error" message={errors.tradeName} />
        </div>

        <div className="space-y-2">
          <Label htmlFor="entityType">Tipo</Label>
          <select
            id="entityType"
            name="entityType"
            className={SELECT_CLASS}
            defaultValue={text("entityType", "LEGAL_ENTITY")}
          >
            {ENTITY_TYPES.map((t) => (
              <option key={t} value={t}>
                {ENTITY_TYPE_LABELS[t]}
              </option>
            ))}
          </select>
          <FieldError id="entityType-error" message={errors.entityType} />
        </div>

        <div className="space-y-2">
          <Label htmlFor="taxIdType">Documento</Label>
          <select
            id="taxIdType"
            name="taxIdType"
            className={SELECT_CLASS}
            value={taxIdType}
            onChange={(e) => setTaxIdType(e.target.value as TaxIdType)}
          >
            {TAX_ID_TYPES.map((t) => (
              <option key={t} value={t}>
                {TAX_ID_TYPE_LABELS[t]}
              </option>
            ))}
          </select>
        </div>

        {taxIdType !== "NONE" ? (
          <div className="space-y-2 sm:col-span-2">
            <Label htmlFor="taxId">Número de {TAX_ID_TYPE_LABELS[taxIdType]} *</Label>
            <Input
              id="taxId"
              name="taxId"
              inputMode={taxIdType === "PASSPORT" ? "text" : "numeric"}
              maxLength={30}
              defaultValue={text("taxId")}
              aria-invalid={Boolean(errors.taxId)}
              aria-describedby={describedBy("taxId")}
              placeholder={taxIdType === "DNI" ? "Ej.: 30123456" : "Ej.: 30-71234567-8"}
            />
            <FieldError id="taxId-error" message={errors.taxId} />
          </div>
        ) : null}

        <div className="space-y-2">
          <Label htmlFor="email">Email</Label>
          <Input
            id="email"
            name="email"
            type="email"
            maxLength={200}
            defaultValue={text("email")}
            aria-invalid={Boolean(errors.email)}
            aria-describedby={describedBy("email")}
            placeholder="Opcional"
          />
          <FieldError id="email-error" message={errors.email} />
        </div>

        <div className="space-y-2">
          <Label htmlFor="phone">Teléfono</Label>
          <Input
            id="phone"
            name="phone"
            type="tel"
            maxLength={50}
            defaultValue={text("phone")}
            placeholder="Opcional"
          />
          <FieldError id="phone-error" message={errors.phone} />
        </div>
      </div>

      <label className="flex items-center gap-2 text-sm">
        <input
          type="checkbox"
          name="alsoOtherRole"
          defaultChecked={values.alsoOtherRole === true}
          className="h-4 w-4 rounded border-border"
        />
        {copy.other}
      </label>

      <div className="flex flex-wrap items-center gap-3">
        <Button type="submit" disabled={pending}>
          {pending ? "Guardando…" : copy.submit}
        </Button>
        <Button asChild variant="outline">
          <Link href={copy.cancelHref}>Cancelar</Link>
        </Button>
      </div>
    </form>
  );
}
