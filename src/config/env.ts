import { z } from "zod";

const appEnvSchema = z.enum(["local", "staging", "rehearsal", "production"]);
const arcaEnvSchema = z.enum(["disabled", "homologation", "production"]);

const LOCAL_DEMO_ANON_FRAGMENT = "CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0";
const LOCAL_HOSTS = ["127.0.0.1", "localhost", "0.0.0.0", "[::1]"];

function hostnameOf(url: string): string {
  try {
    return new URL(url).hostname;
  } catch {
    return "";
  }
}

function isLocalHost(host: string): boolean {
  return LOCAL_HOSTS.includes(host) || host.endsWith(".local");
}

const envSchema = z
  .object({
    NODE_ENV: z.enum(["development", "test", "production"]).default("development"),
    APP_ENV: appEnvSchema.default("local"),
    NEXT_PUBLIC_APP_ENV: appEnvSchema.optional(),
    NEXT_PUBLIC_APP_NAME: z.string().min(1).default("Plataforma"),
    NEXT_PUBLIC_APP_SHORT_NAME: z.string().min(1).default("App"),
    NEXT_PUBLIC_APP_TAGLINE: z.string().optional(),
    NEXT_PUBLIC_APP_URL: z.string().url().optional(),
    NEXT_PUBLIC_SUPABASE_URL: z.string().url({
      message: "NEXT_PUBLIC_SUPABASE_URL must be a valid URL",
    }),
    NEXT_PUBLIC_SUPABASE_ANON_KEY: z.string().min(20, {
      message: "NEXT_PUBLIC_SUPABASE_ANON_KEY is required",
    }),
    SUPABASE_SERVICE_ROLE_KEY: z.string().min(20).optional(),
    SUPABASE_PROJECT_REF: z.string().optional(),
    STAGING_SUPABASE_PROJECT_REF: z.string().optional(),
    REHEARSAL_SUPABASE_PROJECT_REF: z.string().optional(),
    PRODUCTION_SUPABASE_PROJECT_REF: z.string().optional(),
    ARCA_ENV: arcaEnvSchema.default("disabled"),
    FISCAL_GATEWAY_ENV: arcaEnvSchema.optional(),
    ARCA_REPRESENTED_CUIT: z.string().optional(),
    ARCA_HOMO_PRIVATE_KEY_B64: z.string().optional(),
    ARCA_HOMO_CERT_B64: z.string().optional(),
    ARCA_HOMO_PTO_VENTA: z.string().optional(),
    ARCA_WSAA_SERVICE: z.string().optional(),
    ARCA_WSAA_URL: z.string().url().optional(),
    ARCA_WSFE_URL: z.string().url().optional(),
    ARCA_CERT_ALIAS: z.string().optional(),
  })
  .superRefine((data, ctx) => {
    const appEnv = data.NEXT_PUBLIC_APP_ENV ?? data.APP_ENV;
    const arcaEnv = data.FISCAL_GATEWAY_ENV ?? data.ARCA_ENV;
    const supabaseHost = hostnameOf(data.NEXT_PUBLIC_SUPABASE_URL);
    const appHost = data.NEXT_PUBLIC_APP_URL
      ? hostnameOf(data.NEXT_PUBLIC_APP_URL)
      : "";
    const url = data.NEXT_PUBLIC_SUPABASE_URL;
    const refs = [
      data.STAGING_SUPABASE_PROJECT_REF,
      data.REHEARSAL_SUPABASE_PROJECT_REF,
      data.PRODUCTION_SUPABASE_PROJECT_REF,
    ].filter(Boolean) as string[];

    const uniqueRefs = new Set(refs);
    if (uniqueRefs.size !== refs.length) {
      ctx.addIssue({
        code: "custom",
        message:
          "Staging, rehearsal, and production must never share the same Supabase project",
        path: ["STAGING_SUPABASE_PROJECT_REF"],
      });
    }

    if (
      data.STAGING_SUPABASE_PROJECT_REF &&
      data.PRODUCTION_SUPABASE_PROJECT_REF &&
      data.STAGING_SUPABASE_PROJECT_REF === data.PRODUCTION_SUPABASE_PROJECT_REF
    ) {
      ctx.addIssue({
        code: "custom",
        message:
          "Staging and Production must never share the same Supabase project",
        path: ["STAGING_SUPABASE_PROJECT_REF"],
      });
    }

    if (appEnv === "staging" && data.PRODUCTION_SUPABASE_PROJECT_REF) {
      if (url.includes(data.PRODUCTION_SUPABASE_PROJECT_REF)) {
        ctx.addIssue({
          code: "custom",
          message:
            "APP_ENV=staging cannot point NEXT_PUBLIC_SUPABASE_URL at the production project",
          path: ["NEXT_PUBLIC_SUPABASE_URL"],
        });
      }
    }

    if (appEnv === "production" && data.STAGING_SUPABASE_PROJECT_REF) {
      if (url.includes(data.STAGING_SUPABASE_PROJECT_REF)) {
        ctx.addIssue({
          code: "custom",
          message:
            "APP_ENV=production cannot point NEXT_PUBLIC_SUPABASE_URL at the staging project",
          path: ["NEXT_PUBLIC_SUPABASE_URL"],
        });
      }
    }

    if (appEnv === "rehearsal" && data.PRODUCTION_SUPABASE_PROJECT_REF) {
      if (url.includes(data.PRODUCTION_SUPABASE_PROJECT_REF)) {
        ctx.addIssue({
          code: "custom",
          message:
            "APP_ENV=rehearsal cannot point NEXT_PUBLIC_SUPABASE_URL at the production project",
          path: ["NEXT_PUBLIC_SUPABASE_URL"],
        });
      }
    }

    if (appEnv === "local" && data.PRODUCTION_SUPABASE_PROJECT_REF) {
      if (url.includes(data.PRODUCTION_SUPABASE_PROJECT_REF)) {
        ctx.addIssue({
          code: "custom",
          message:
            "Local app cannot use Production secrets or Production Supabase URL",
          path: ["NEXT_PUBLIC_SUPABASE_URL"],
        });
      }
    }

    if (appEnv === "production" && isLocalHost(supabaseHost)) {
      ctx.addIssue({
        code: "custom",
        message: "APP_ENV=production cannot use a local Supabase URL",
        path: ["NEXT_PUBLIC_SUPABASE_URL"],
      });
    }

    if (appEnv === "production" && appHost && isLocalHost(appHost)) {
      ctx.addIssue({
        code: "custom",
        message: "APP_ENV=production cannot use a local application URL",
        path: ["NEXT_PUBLIC_APP_URL"],
      });
    }

    if (
      appEnv === "production" &&
      data.NEXT_PUBLIC_SUPABASE_ANON_KEY.includes(LOCAL_DEMO_ANON_FRAGMENT)
    ) {
      ctx.addIssue({
        code: "custom",
        message: "APP_ENV=production cannot use local disposable Auth keys",
        path: ["NEXT_PUBLIC_SUPABASE_ANON_KEY"],
      });
    }

    if (arcaEnv === "production") {
      ctx.addIssue({
        code: "custom",
        message:
          "ARCA production is blocked (Phase 5 homologation pending). Use ARCA_ENV=disabled or homologation.",
        path: ["ARCA_ENV"],
      });
    }

    if (
      (appEnv === "local" || appEnv === "staging" || appEnv === "rehearsal") &&
      arcaEnv === "production"
    ) {
      ctx.addIssue({
        code: "custom",
        message: `${appEnv} app cannot connect to ARCA Production`,
        path: ["ARCA_ENV"],
      });
    }

    if (arcaEnv === "homologation") {
      if (!data.ARCA_REPRESENTED_CUIT || !/^\d{11}$/.test(data.ARCA_REPRESENTED_CUIT)) {
        ctx.addIssue({
          code: "custom",
          message: "ARCA_REPRESENTED_CUIT must be exactly 11 digits when ARCA_ENV=homologation",
          path: ["ARCA_REPRESENTED_CUIT"],
        });
      }
      if (!data.ARCA_HOMO_PRIVATE_KEY_B64) {
        ctx.addIssue({
          code: "custom",
          message: "ARCA_HOMO_PRIVATE_KEY_B64 is required when ARCA_ENV=homologation",
          path: ["ARCA_HOMO_PRIVATE_KEY_B64"],
        });
      }
      if (!data.ARCA_HOMO_CERT_B64) {
        ctx.addIssue({
          code: "custom",
          message: "ARCA_HOMO_CERT_B64 is required when ARCA_ENV=homologation",
          path: ["ARCA_HOMO_CERT_B64"],
        });
      }
      const ptoRaw = (data.ARCA_HOMO_PTO_VENTA ?? "").trim();
      if (!/^\d+$/.test(ptoRaw)) {
        ctx.addIssue({
          code: "custom",
          message:
            "ARCA_HOMO_PTO_VENTA must be an integer 1..99998 when ARCA_ENV=homologation",
          path: ["ARCA_HOMO_PTO_VENTA"],
        });
      } else {
        const pto = Number(ptoRaw);
        if (!Number.isInteger(pto) || pto < 1 || pto > 99998) {
          ctx.addIssue({
            code: "custom",
            message:
              "ARCA_HOMO_PTO_VENTA must be an integer 1..99998 when ARCA_ENV=homologation",
            path: ["ARCA_HOMO_PTO_VENTA"],
          });
        }
      }
      const svc = data.ARCA_WSAA_SERVICE ?? "wsfe";
      if (svc !== "wsfe") {
        ctx.addIssue({
          code: "custom",
          message: "ARCA_WSAA_SERVICE must equal wsfe",
          path: ["ARCA_WSAA_SERVICE"],
        });
      }
      const wsaa =
        data.ARCA_WSAA_URL ??
        "https://wsaahomo.afip.gov.ar/ws/services/LoginCms";
      const wsfe =
        data.ARCA_WSFE_URL ??
        "https://wswhomo.afip.gov.ar/wsfev1/service.asmx";
      if (wsaa !== "https://wsaahomo.afip.gov.ar/ws/services/LoginCms") {
        ctx.addIssue({
          code: "custom",
          message: "ARCA_WSAA_URL must be the homologation LoginCms endpoint",
          path: ["ARCA_WSAA_URL"],
        });
      }
      if (wsfe !== "https://wswhomo.afip.gov.ar/wsfev1/service.asmx") {
        ctx.addIssue({
          code: "custom",
          message: "ARCA_WSFE_URL must be the homologation WSFEv1 endpoint",
          path: ["ARCA_WSFE_URL"],
        });
      }
      if (/wsaa\.afip\.gov\.ar/i.test(wsaa) && !/wsaahomo/i.test(wsaa)) {
        ctx.addIssue({
          code: "custom",
          message: "Production WSAA URL is forbidden",
          path: ["ARCA_WSAA_URL"],
        });
      }
      if (/servicios1\.afip\.gov\.ar/i.test(wsfe)) {
        ctx.addIssue({
          code: "custom",
          message: "Production WSFE URL is forbidden",
          path: ["ARCA_WSFE_URL"],
        });
      }
    }
  });

export type AppEnv = z.infer<typeof appEnvSchema>;
export type ArcaEnv = z.infer<typeof arcaEnvSchema>;
export type ServerEnv = z.infer<typeof envSchema>;

let cached: ServerEnv | null = null;

function readRawEnv(): Record<string, string | undefined> {
  return {
    NODE_ENV: process.env.NODE_ENV,
    APP_ENV: process.env.APP_ENV,
    NEXT_PUBLIC_APP_ENV: process.env.NEXT_PUBLIC_APP_ENV,
    NEXT_PUBLIC_APP_NAME: process.env.NEXT_PUBLIC_APP_NAME,
    NEXT_PUBLIC_APP_SHORT_NAME: process.env.NEXT_PUBLIC_APP_SHORT_NAME,
    NEXT_PUBLIC_APP_TAGLINE: process.env.NEXT_PUBLIC_APP_TAGLINE,
    NEXT_PUBLIC_APP_URL: process.env.NEXT_PUBLIC_APP_URL,
    NEXT_PUBLIC_SUPABASE_URL: process.env.NEXT_PUBLIC_SUPABASE_URL,
    NEXT_PUBLIC_SUPABASE_ANON_KEY: process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY,
    SUPABASE_SERVICE_ROLE_KEY: process.env.SUPABASE_SERVICE_ROLE_KEY,
    SUPABASE_PROJECT_REF: process.env.SUPABASE_PROJECT_REF,
    STAGING_SUPABASE_PROJECT_REF: process.env.STAGING_SUPABASE_PROJECT_REF,
    REHEARSAL_SUPABASE_PROJECT_REF: process.env.REHEARSAL_SUPABASE_PROJECT_REF,
    PRODUCTION_SUPABASE_PROJECT_REF: process.env.PRODUCTION_SUPABASE_PROJECT_REF,
    ARCA_ENV: process.env.ARCA_ENV,
    FISCAL_GATEWAY_ENV: process.env.FISCAL_GATEWAY_ENV,
    ARCA_REPRESENTED_CUIT: process.env.ARCA_REPRESENTED_CUIT,
    ARCA_HOMO_PRIVATE_KEY_B64: process.env.ARCA_HOMO_PRIVATE_KEY_B64,
    ARCA_HOMO_CERT_B64: process.env.ARCA_HOMO_CERT_B64,
    ARCA_HOMO_PTO_VENTA: process.env.ARCA_HOMO_PTO_VENTA,
    ARCA_WSAA_SERVICE: process.env.ARCA_WSAA_SERVICE,
    ARCA_WSAA_URL: process.env.ARCA_WSAA_URL,
    ARCA_WSFE_URL: process.env.ARCA_WSFE_URL,
    ARCA_CERT_ALIAS: process.env.ARCA_CERT_ALIAS,
  };
}

/**
 * Validates environment. Never silently falls back between staging and production.
 * Fail-closed on unsafe cross-environment combinations.
 */
export function getServerEnv(): ServerEnv {
  if (cached) return cached;
  const parsed = envSchema.safeParse(readRawEnv());
  if (!parsed.success) {
    const details = parsed.error.issues
      .map((i) => `${i.path.join(".")}: ${i.message}`)
      .join("; ");
    throw new Error(`Invalid environment configuration: ${details}`);
  }
  cached = parsed.data;
  return cached;
}

export function getAppEnv(): AppEnv {
  const env = getServerEnv();
  return env.NEXT_PUBLIC_APP_ENV ?? env.APP_ENV;
}

export function getArcaEnv(): ArcaEnv {
  const env = getServerEnv();
  return env.FISCAL_GATEWAY_ENV ?? env.ARCA_ENV;
}

/** Public subset safe for client bundles (no service role). */
export function getPublicEnv() {
  return {
    appEnv: (process.env.NEXT_PUBLIC_APP_ENV ??
      process.env.APP_ENV ??
      "local") as AppEnv,
    appName: process.env.NEXT_PUBLIC_APP_NAME ?? "Plataforma",
    appShortName: process.env.NEXT_PUBLIC_APP_SHORT_NAME ?? "App",
    supabaseUrl: process.env.NEXT_PUBLIC_SUPABASE_URL ?? "",
    supabaseAnonKey: process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ?? "",
    arcaEnv: (process.env.FISCAL_GATEWAY_ENV ??
      process.env.ARCA_ENV ??
      "disabled") as ArcaEnv,
  };
}

export function resetEnvCacheForTests() {
  cached = null;
}
