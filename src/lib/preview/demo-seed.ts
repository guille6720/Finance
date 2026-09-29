import type { SupabaseClient } from "@supabase/supabase-js";
import { createAdminClient } from "@/lib/supabase/admin";
import { isPublicPreviewDemoEnabled, publicPreviewMaxTesters } from "@/config/preview";

export const TESTER_LIMIT_CODE = "STAGING_TESTER_LIMIT_REACHED";

/** Modules a tester organization gets on top of the regular provisioning. */
export const PREVIEW_EXTRA_FEATURES = ["taxes"] as const;

type Env = Parameters<typeof isPublicPreviewDemoEnabled>[0];
type DbError = { code?: string; message?: string; details?: string } | null | undefined;

export function isTesterLimitError(error: DbError): boolean {
  if (!error) return false;
  return [error.message, error.details].some((v) => typeof v === "string" && v.includes(TESTER_LIMIT_CODE));
}

export function testerLimitMessage(env?: Env): string {
  return `Se alcanzó el límite de ${publicPreviewMaxTesters(env)} usuarios de prueba. Contactanos si necesitás acceso.`;
}

export type PreviewDemoStatus = { eligible: boolean; complete: boolean };

/** null = unknown (query failed); callers must not force UI on it. */
export async function loadPreviewDemoStatus(
  supabase: SupabaseClient,
  organizationId: string,
  env?: Env
): Promise<PreviewDemoStatus | null> {
  if (!isPublicPreviewDemoEnabled(env)) return { eligible: false, complete: false };
  const { data, error } = await supabase.rpc("preview_demo_seed_status", { p_organization_id: organizationId });
  if (error || !data || typeof data !== "object") return null;
  const status = data as Partial<PreviewDemoStatus>;
  return { eligible: status.eligible === true, complete: status.complete === true };
}

export type PreviewDemoResult =
  | { ok: true; seeded: false; reason: "disabled" | "not_eligible" }
  | { ok: true; seeded: true; summary: Record<string, unknown> }
  | { ok: false; step: "status" | "modules" | "seed" };

async function grantPreviewModules(organizationId: string): Promise<boolean> {
  let admin;
  try {
    admin = createAdminClient();
  } catch {
    return false;
  }
  for (const code of PREVIEW_EXTRA_FEATURES) {
    const r = await admin.rpc("platform_enable_organization_feature", {
      p_organization_id: organizationId,
      p_feature_code: code,
    });
    if (r.error) return false;
  }
  const re = await admin.rpc("recompute_organization_features", { p_organization_id: organizationId });
  return !re.error;
}

/**
 * Loads the synthetic demo dataset into a tester organization. The database decides
 * eligibility (preview enabled, tester slot, owner, not a platform demo org) and the
 * seed itself runs with the caller's own client, so RLS and the posting engines apply.
 * Safe to call repeatedly: the seed is idempotent.
 */
export async function runPreviewDemoSetup(
  supabase: SupabaseClient,
  organizationId: string,
  env?: Env
): Promise<PreviewDemoResult> {
  if (!isPublicPreviewDemoEnabled(env)) return { ok: true, seeded: false, reason: "disabled" };

  const status = await loadPreviewDemoStatus(supabase, organizationId, env);
  if (!status) return { ok: false, step: "status" };
  if (!status.eligible) return { ok: true, seeded: false, reason: "not_eligible" };

  if (!(await grantPreviewModules(organizationId))) return { ok: false, step: "modules" };

  const { data, error } = await supabase.rpc("seed_preview_demo_data", { p_organization_id: organizationId });
  if (error) {
    console.error("[preview-demo] seed failed", { code: error.code });
    return { ok: false, step: "seed" };
  }
  return { ok: true, seeded: true, summary: (data ?? {}) as Record<string, unknown> };
}
