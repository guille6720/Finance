/**
 * Centralized branding. Product name must never appear in DB, APIs, or IDs.
 * Replace via NEXT_PUBLIC_APP_* env vars when the temporary identity changes.
 */
export const brand = {
  name: process.env.NEXT_PUBLIC_APP_NAME ?? "Plataforma",
  shortName: process.env.NEXT_PUBLIC_APP_SHORT_NAME ?? "App",
  tagline:
    process.env.NEXT_PUBLIC_APP_TAGLINE ?? "Gestión contable inteligente",
  logoLight: "/brand/logo-light.png",
  logoDark: "/brand/logo-dark.png",
  supportEmail: process.env.NEXT_PUBLIC_SUPPORT_EMAIL ?? "soporte@example.com",
} as const;

export type Brand = typeof brand;
