"use client";

import { useMemo, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { brand } from "@/config/brand";
import { BUSINESS_TYPE_LABELS, BUSINESS_TYPES } from "@/config/features";
import { ARGENTINA_PROVINCES } from "@/lib/validations/argentina";
import { recommendFeatures } from "@/lib/onboarding/schema";
import { completeOnboarding } from "@/lib/onboarding/actions";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";

const STEPS = [
  "Bienvenida",
  "Empresa",
  "Datos fiscales",
  "Actividad",
  "Necesidades",
  "Módulos",
  "Confirmación",
] as const;

type FormState = {
  legalName: string;
  commercialName: string;
  cuit: string;
  province: string;
  city: string;
  fiscalConditionCode: string;
  fiscalAddress: string;
  branchName: string;
  businessType: (typeof BUSINESS_TYPES)[number];
  businessTypeOther: string;
  sellsProducts: boolean;
  sellsServices: boolean;
  managesInventory: boolean;
  hasEmployees: boolean;
  hasMultipleBranches: boolean;
  needsProjects: boolean;
  needsCostCenters: boolean;
  invoicesCustomers: boolean;
  worksWithSuppliers: boolean;
  acceptedRecommendedModules: boolean;
};

const initial: FormState = {
  legalName: "",
  commercialName: "",
  cuit: "",
  province: "Buenos Aires",
  city: "",
  fiscalConditionCode: "monotributo",
  fiscalAddress: "",
  branchName: "Casa central",
  businessType: "retail",
  businessTypeOther: "",
  sellsProducts: true,
  sellsServices: false,
  managesInventory: true,
  hasEmployees: false,
  hasMultipleBranches: false,
  needsProjects: false,
  needsCostCenters: false,
  invoicesCustomers: true,
  worksWithSuppliers: true,
  acceptedRecommendedModules: true,
};

function Toggle({
  label,
  checked,
  onChange,
}: {
  label: string;
  checked: boolean;
  onChange: (v: boolean) => void;
}) {
  return (
    <label className="flex items-center justify-between gap-4 rounded-md border border-border bg-surface-elevated px-3 py-3 text-sm">
      <span>{label}</span>
      <input
        type="checkbox"
        className="h-4 w-4 accent-[color:var(--primary)]"
        checked={checked}
        onChange={(e) => onChange(e.target.checked)}
      />
    </label>
  );
}

export function OnboardingWizard() {
  const router = useRouter();
  const [step, setStep] = useState(0);
  const [form, setForm] = useState<FormState>(initial);
  const [error, setError] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();

  const recommended = useMemo(() => recommendFeatures(form), [form]);
  const progress = ((step + 1) / STEPS.length) * 100;

  function next() {
    setError(null);
    if (step === 1 && form.legalName.trim().length < 2) {
      setError("Ingresá la razón social o nombre de tu negocio");
      return;
    }
    if (step === 2 && form.fiscalAddress.trim().length < 2) {
      setError("Ingresá el domicilio fiscal");
      return;
    }
    setStep((s) => Math.min(s + 1, STEPS.length - 1));
  }

  function back() {
    setError(null);
    setStep((s) => Math.max(s - 1, 0));
  }

  function submit() {
    setError(null);
    startTransition(async () => {
      const result = await completeOnboarding(form);
      if (!result.ok) {
        setError(result.error);
        return;
      }
      router.push("/dashboard");
      router.refresh();
    });
  }

  return (
    <div className="mx-auto flex min-h-screen max-w-3xl flex-col justify-center px-4 py-10">
      <div className="mb-6">
        <p className="text-sm font-semibold text-primary-bright">{brand.name}</p>
        <h1 className="mt-1 text-2xl font-semibold tracking-tight">
          Configuremos tu empresa
        </h1>
        <p className="mt-1 text-sm text-muted-foreground">
          En unos minutos dejamos todo listo. Sin jerga contable.
        </p>
        <div className="mt-4 h-2 overflow-hidden rounded-full bg-muted" role="progressbar" aria-valuenow={Math.round(progress)} aria-valuemin={0} aria-valuemax={100}>
          <div className="h-full bg-primary transition-all" style={{ width: `${progress}%` }} />
        </div>
        <p className="mt-2 text-xs text-muted-foreground">
          Paso {step + 1} de {STEPS.length}: {STEPS[step]}
        </p>
      </div>

      <Card>
        <CardHeader>
          <CardTitle>{STEPS[step]}</CardTitle>
          <CardDescription>
            {step === 0 && "Te damos la bienvenida a la plataforma."}
            {step === 1 && "Contanos cómo se llama tu negocio."}
            {step === 2 && "Datos que usa AFIP / ARCA. Podés completarlos con tu contador."}
            {step === 3 && "¿Qué tipo de negocio tenés?"}
            {step === 4 && "Esto nos ayuda a activar lo que necesitás."}
            {step === 5 && "Recomendamos módulos. Todavía no están todos activos."}
            {step === 6 && "Revisá y confirmá para empezar."}
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          {step === 0 && (
            <div className="space-y-3 text-sm text-muted-foreground">
              <p>
                Vos administrás el negocio. La plataforma se ocupa de la
                contabilidad por debajo.
              </p>
              <p>
                No necesitás saber de débitos, créditos ni códigos de cuenta.
              </p>
            </div>
          )}

          {step === 1 && (
            <div className="grid gap-4 sm:grid-cols-2">
              <div className="space-y-2 sm:col-span-2">
                <Label htmlFor="legalName">Nombre / razón social *</Label>
                <Input
                  id="legalName"
                  value={form.legalName}
                  onChange={(e) => setForm({ ...form, legalName: e.target.value })}
                  placeholder="Ej: Almacén del Centro SRL"
                />
              </div>
              <div className="space-y-2">
                <Label htmlFor="commercialName">Nombre comercial</Label>
                <Input
                  id="commercialName"
                  value={form.commercialName}
                  onChange={(e) => setForm({ ...form, commercialName: e.target.value })}
                  placeholder="Cómo te conocen los clientes"
                />
              </div>
              <div className="space-y-2">
                <Label htmlFor="branchName">Sucursal principal</Label>
                <Input
                  id="branchName"
                  value={form.branchName}
                  onChange={(e) => setForm({ ...form, branchName: e.target.value })}
                />
              </div>
              <div className="space-y-2">
                <Label htmlFor="province">Provincia</Label>
                <select
                  id="province"
                  className="flex h-10 w-full rounded-md border border-border bg-input px-3 text-sm"
                  value={form.province}
                  onChange={(e) => setForm({ ...form, province: e.target.value })}
                >
                  {ARGENTINA_PROVINCES.map((p) => (
                    <option key={p} value={p}>
                      {p}
                    </option>
                  ))}
                </select>
              </div>
              <div className="space-y-2">
                <Label htmlFor="city">Ciudad</Label>
                <Input
                  id="city"
                  value={form.city}
                  onChange={(e) => setForm({ ...form, city: e.target.value })}
                />
              </div>
            </div>
          )}

          {step === 2 && (
            <div className="grid gap-4 sm:grid-cols-2">
              <div className="space-y-2">
                <Label htmlFor="cuit">CUIT *</Label>
                <Input
                  id="cuit"
                  value={form.cuit}
                  onChange={(e) => setForm({ ...form, cuit: e.target.value })}
                  placeholder="20-12345678-6"
                />
              </div>
              <div className="space-y-2">
                <Label htmlFor="fiscalCondition">Condición frente al IVA</Label>
                <select
                  id="fiscalCondition"
                  className="flex h-10 w-full rounded-md border border-border bg-input px-3 text-sm"
                  value={form.fiscalConditionCode}
                  onChange={(e) =>
                    setForm({ ...form, fiscalConditionCode: e.target.value })
                  }
                >
                  <option value="monotributo">Monotributo</option>
                  <option value="responsable_inscripto">Responsable inscripto</option>
                  <option value="exento">Exento de IVA</option>
                  <option value="consumidor_final">Consumidor final</option>
                </select>
              </div>
              <div className="space-y-2 sm:col-span-2">
                <Label htmlFor="fiscalAddress">Domicilio fiscal *</Label>
                <Input
                  id="fiscalAddress"
                  value={form.fiscalAddress}
                  onChange={(e) => setForm({ ...form, fiscalAddress: e.target.value })}
                />
              </div>
            </div>
          )}

          {step === 3 && (
            <div className="space-y-3">
              <Label htmlFor="businessType">¿Qué tipo de negocio tenés?</Label>
              <select
                id="businessType"
                className="flex h-10 w-full rounded-md border border-border bg-input px-3 text-sm"
                value={form.businessType}
                onChange={(e) =>
                  setForm({
                    ...form,
                    businessType: e.target.value as FormState["businessType"],
                  })
                }
              >
                {BUSINESS_TYPES.map((t) => (
                  <option key={t} value={t}>
                    {BUSINESS_TYPE_LABELS[t]}
                  </option>
                ))}
              </select>
              {form.businessType === "other" ? (
                <Input
                  placeholder="Describí tu actividad"
                  value={form.businessTypeOther}
                  onChange={(e) =>
                    setForm({ ...form, businessTypeOther: e.target.value })
                  }
                />
              ) : null}
            </div>
          )}

          {step === 4 && (
            <div className="space-y-2">
              <Toggle label="¿Vendés productos?" checked={form.sellsProducts} onChange={(v) => setForm({ ...form, sellsProducts: v })} />
              <Toggle label="¿Vendés servicios?" checked={form.sellsServices} onChange={(v) => setForm({ ...form, sellsServices: v })} />
              <Toggle label="¿Manejás inventario / stock?" checked={form.managesInventory} onChange={(v) => setForm({ ...form, managesInventory: v })} />
              <Toggle label="¿Tenés empleados?" checked={form.hasEmployees} onChange={(v) => setForm({ ...form, hasEmployees: v })} />
              <Toggle label="¿Tenés más de una sucursal?" checked={form.hasMultipleBranches} onChange={(v) => setForm({ ...form, hasMultipleBranches: v })} />
              <Toggle label="¿Necesitás proyectos?" checked={form.needsProjects} onChange={(v) => setForm({ ...form, needsProjects: v })} />
              <Toggle label="¿Necesitás centros de costo?" checked={form.needsCostCenters} onChange={(v) => setForm({ ...form, needsCostCenters: v })} />
              <Toggle label="¿Facturás a clientes?" checked={form.invoicesCustomers} onChange={(v) => setForm({ ...form, invoicesCustomers: v })} />
              <Toggle label="¿Trabajás con proveedores?" checked={form.worksWithSuppliers} onChange={(v) => setForm({ ...form, worksWithSuppliers: v })} />
            </div>
          )}

          {step === 5 && (
            <div className="space-y-3">
              <p className="text-sm text-muted-foreground">
                Según tus respuestas, te recomendamos estos módulos. En Fase 1
                quedan preparados; la mayoría se habilita en fases siguientes.
              </p>
              <ul className="space-y-2">
                {recommended.map((r) => (
                  <li
                    key={r.code}
                    className="rounded-md border border-border bg-surface-elevated px-3 py-2 text-sm"
                  >
                    <span className="font-medium">{r.code}</span>
                    <span className="mt-0.5 block text-muted-foreground">{r.reason}</span>
                  </li>
                ))}
              </ul>
              <Toggle
                label="Aceptar recomendaciones"
                checked={form.acceptedRecommendedModules}
                onChange={(v) => setForm({ ...form, acceptedRecommendedModules: v })}
              />
            </div>
          )}

          {step === 6 && (
            <div className="space-y-2 text-sm">
              <p>
                <span className="text-muted-foreground">Empresa:</span>{" "}
                {form.legalName || "—"}
              </p>
              <p>
                <span className="text-muted-foreground">CUIT:</span> {form.cuit || "—"}
              </p>
              <p>
                <span className="text-muted-foreground">Actividad:</span>{" "}
                {BUSINESS_TYPE_LABELS[form.businessType]}
              </p>
              <p>
                <span className="text-muted-foreground">Sucursal:</span>{" "}
                {form.branchName}
              </p>
              <p className="pt-2 text-muted-foreground">
                Al confirmar creamos tu empresa, tu perfil fiscal y el registro
                de auditoría inicial.
              </p>
            </div>
          )}

          {error ? (
            <p className="text-sm text-danger" role="alert">
              {error}
            </p>
          ) : null}

          <div className="flex items-center justify-between gap-3 pt-2">
            <Button type="button" variant="outline" onClick={back} disabled={step === 0 || pending}>
              Atrás
            </Button>
            {step < STEPS.length - 1 ? (
              <Button type="button" onClick={next}>
                Continuar
              </Button>
            ) : (
              <Button type="button" onClick={submit} disabled={pending}>
                {pending ? "Guardando..." : "Confirmar y entrar"}
              </Button>
            )}
          </div>
        </CardContent>
      </Card>
    </div>
  );
}
