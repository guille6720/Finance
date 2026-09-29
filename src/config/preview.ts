/**
 * Public preview (testers) switch. Explicit PUBLIC_PREVIEW_DEMO_ENABLED wins; otherwise
 * it is on only for Vercel Preview deployments or APP_ENV=staging, never by default in
 * Production. The database keeps its own switch (public.preview_demo_settings).
 */
type PreviewEnv = Record<string, string | undefined>;

const DEFAULT_MAX_TESTERS = 5;

export function isPublicPreviewDemoEnabled(env: PreviewEnv = process.env): boolean {
  const explicit = env.PUBLIC_PREVIEW_DEMO_ENABLED?.trim().toLowerCase();
  if (explicit === "true") return true;
  if (explicit === "false") return false;
  return env.VERCEL_ENV === "preview" || env.APP_ENV === "staging";
}

export function publicPreviewMaxTesters(env: PreviewEnv = process.env): number {
  const n = Number.parseInt(env.PUBLIC_PREVIEW_MAX_TESTERS ?? "", 10);
  return Number.isInteger(n) && n >= 1 && n <= DEFAULT_MAX_TESTERS ? n : DEFAULT_MAX_TESTERS;
}
