import type { FeatureCode, FeatureStatus } from "@/config/features";

export function isFeatureUsable(status: FeatureStatus | string | null | undefined) {
  return status === "enabled";
}

export function isFeatureComingSoon(status: FeatureStatus | string | null | undefined) {
  return status === "disabled" || status === "restricted" || !status;
}

export function featureNavVisible(
  code: FeatureCode,
  status: FeatureStatus | string | null | undefined,
  opts?: { showComingSoon?: boolean }
) {
  if (status === "enabled") return "active" as const;
  if (opts?.showComingSoon !== false) return "coming_soon" as const;
  return "hidden" as const;
}
