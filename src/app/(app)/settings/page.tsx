import { createClient } from "@/lib/supabase/server";
import { cookies } from "next/headers";
import { redirect } from "next/navigation";
import { ACTIVE_ORG_COOKIE } from "@/lib/authz/context";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { getAppEnv } from "@/config/env";
import { featureStatusLabel } from "@/lib/demo-data/format";

export default async function SettingsPage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) redirect("/login");

  const cookieStore = await cookies();
  const activeOrgId = cookieStore.get(ACTIVE_ORG_COOKIE)?.value;

  const { data: membership } = await supabase
    .from("organization_members")
    .select("organization_id")
    .eq("user_id", user.id)
    .eq("status", "active")
    .limit(20);

  const orgId =
    membership?.find((m) => m.organization_id === activeOrgId)?.organization_id ??
    membership?.[0]?.organization_id;

  if (!orgId) redirect("/onboarding");

  const { data: features } = await supabase
    .from("organization_features")
    .select("status, feature_catalog ( code, name, category )")
    .eq("organization_id", orgId);

  let appEnv = "local";
  try {
    appEnv = getAppEnv();
  } catch {
    appEnv = process.env.APP_ENV ?? "local";
  }

  return (
    <div className="space-y-6">
      <div>
        <h2 className="text-xl font-semibold">Configuración</h2>
        <p className="text-sm text-muted-foreground">
          Entorno: <Badge tone="neutral">{appEnv}</Badge>
        </p>
      </div>

      <Card>
        <CardHeader>
          <CardTitle>Módulos de la empresa</CardTitle>
          <CardDescription>
            Qué módulos están disponibles para esta empresa.
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-2">
          {(features ?? []).map((f, idx) => {
            const cat = f.feature_catalog as unknown as {
              code: string;
              name: string;
              category: string;
            } | null;
            return (
              <div
                key={`${cat?.code ?? idx}`}
                className="flex items-center justify-between rounded-md border border-border px-3 py-2 text-sm"
              >
                <p className="font-medium">{cat?.name ?? "—"}</p>
                <Badge tone={featureStatusLabel(f.status).tone}>
                  {featureStatusLabel(f.status).label}
                </Badge>
              </div>
            );
          })}
        </CardContent>
      </Card>
    </div>
  );
}
