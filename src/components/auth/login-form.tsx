"use client";

import { useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { brand } from "@/config/brand";
import { authErrorMessage } from "@/lib/auth/messages";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";

const NOTICES: Record<string, { tone: "ok" | "error"; text: string }> = {
  confirmado: { tone: "ok", text: "Email confirmado. Ingresá con tu contraseña." },
  confirmacion: {
    tone: "error",
    text: "No pudimos iniciar sesión desde el enlace (puede haber vencido o haberse abierto en otro navegador). Probá ingresar con tu email y contraseña.",
  },
};

export function LoginForm({ notice }: { notice?: string }) {
  const router = useRouter();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const banner = notice ? NOTICES[notice] : undefined;
  const [loading, setLoading] = useState(false);

  async function onSubmit(e: React.FormEvent) {
    e.preventDefault();
    setLoading(true);
    setError(null);
    const supabase = createClient();
    const { error: signError } = await supabase.auth.signInWithPassword({
      email,
      password,
    });
    setLoading(false);
    if (signError) {
      setError(authErrorMessage(signError, "login"));
      return;
    }
    router.push("/dashboard");
    router.refresh();
  }

  return (
    <Card className="w-full max-w-md">
      <CardHeader>
        <p className="text-sm font-semibold text-primary-bright">{brand.name}</p>
        <CardTitle>Ingresar</CardTitle>
        <CardDescription>{brand.tagline}</CardDescription>
      </CardHeader>
      <CardContent>
        <form onSubmit={onSubmit} className="space-y-4">
          {banner ? (
            <p
              role={banner.tone === "error" ? "alert" : "status"}
              className={
                banner.tone === "error"
                  ? "rounded-md border border-danger/30 bg-danger/10 p-3 text-sm text-danger"
                  : "rounded-md border border-success/30 bg-success/10 p-3 text-sm text-success"
              }
            >
              {banner.text}
            </p>
          ) : null}
          <div className="space-y-2">
            <Label htmlFor="email">Email</Label>
            <Input
              id="email"
              type="email"
              autoComplete="email"
              required
              value={email}
              onChange={(e) => setEmail(e.target.value)}
            />
          </div>
          <div className="space-y-2">
            <Label htmlFor="password">Contraseña</Label>
            <Input
              id="password"
              type="password"
              autoComplete="current-password"
              required
              value={password}
              onChange={(e) => setPassword(e.target.value)}
            />
          </div>
          {error ? (
            <p className="text-sm text-danger" role="alert">
              {error}
            </p>
          ) : null}
          <Button type="submit" className="w-full" disabled={loading}>
            {loading ? "Ingresando..." : "Ingresar"}
          </Button>
          <p className="text-center text-sm text-muted-foreground">
            ¿No tenés cuenta?{" "}
            <Link href="/register" className="text-primary-bright hover:underline">
              Crear cuenta
            </Link>
          </p>
        </form>
      </CardContent>
    </Card>
  );
}
