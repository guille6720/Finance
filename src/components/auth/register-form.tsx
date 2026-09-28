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

export function RegisterForm() {
  const router = useRouter();
  const [fullName, setFullName] = useState("");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [pendingEmail, setPendingEmail] = useState<string | null>(null);

  async function onSubmit(e: React.FormEvent) {
    e.preventDefault();
    setLoading(true);
    setError(null);
    const supabase = createClient();
    const { data, error: signError } = await supabase.auth.signUp({
      email,
      password,
      options: {
        data: { full_name: fullName },
        emailRedirectTo: `${window.location.origin}/auth/confirm?next=/onboarding`,
      },
    });
    setLoading(false);
    if (signError) {
      setError(authErrorMessage(signError, "signup"));
      return;
    }
    if (!data.session) {
      setPendingEmail(email);
      return;
    }
    router.push("/onboarding");
    router.refresh();
  }

  if (pendingEmail) {
    return (
      <Card className="w-full max-w-md" data-testid="register-check-email">
        <CardHeader>
          <p className="text-sm font-semibold text-primary-bright">{brand.name}</p>
          <CardTitle>Revisá tu email</CardTitle>
          <CardDescription>
            Te enviamos un enlace de confirmación a <strong>{pendingEmail}</strong>.
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-3 text-sm text-muted-foreground">
          <p>
            Abrilo desde este mismo navegador para activar la cuenta y seguir con el alta de tu empresa. Si no
            lo ves en unos minutos, revisá la carpeta de spam o promociones.
          </p>
          <p>
            ¿Ya confirmaste?{" "}
            <Link href="/login" className="text-primary-bright hover:underline">
              Ingresar
            </Link>
          </p>
        </CardContent>
      </Card>
    );
  }

  return (
    <Card className="w-full max-w-md">
      <CardHeader>
        <p className="text-sm font-semibold text-primary-bright">{brand.name}</p>
        <CardTitle>Crear cuenta</CardTitle>
        <CardDescription>Empezá a organizar tu negocio en minutos</CardDescription>
      </CardHeader>
      <CardContent>
        <form onSubmit={onSubmit} className="space-y-4">
          <div className="space-y-2">
            <Label htmlFor="fullName">Nombre</Label>
            <Input
              id="fullName"
              required
              value={fullName}
              onChange={(e) => setFullName(e.target.value)}
            />
          </div>
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
              autoComplete="new-password"
              required
              minLength={8}
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
            {loading ? "Creando..." : "Crear cuenta"}
          </Button>
          <p className="text-center text-sm text-muted-foreground">
            ¿Ya tenés cuenta?{" "}
            <Link href="/login" className="text-primary-bright hover:underline">
              Ingresar
            </Link>
          </p>
        </form>
      </CardContent>
    </Card>
  );
}
