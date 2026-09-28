/** Values mirror the existing `public.ux_mode` enum; stored only in a cookie. */
export const UX_MODES = ["business", "accountant"] as const;
export type UxMode = (typeof UX_MODES)[number];

export const UX_MODE_COOKIE = "ux_mode";
export const UX_MODE_ENDPOINT = "/api/preferences/ux-mode";
export const DEFAULT_UX_MODE: UxMode = "business";

export const UX_MODE_LABELS: Record<UxMode, string> = {
  business: "Modo negocio",
  accountant: "Modo contabilidad",
};

export function isUxMode(value: unknown): value is UxMode {
  return typeof value === "string" && (UX_MODES as readonly string[]).includes(value);
}

/** Unknown or tampered cookie values fall back to the default mode. */
export function parseUxMode(value: string | null | undefined): UxMode {
  return isUxMode(value) ? value : DEFAULT_UX_MODE;
}
