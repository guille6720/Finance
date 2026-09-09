import { z } from "zod";

const appEnvSchema = z.enum(["local", "staging", "production"]);

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
    PRODUCTION_SUPABASE_PROJECT_REF: z.string().optional(),
  })
  .superRefine((data, ctx) => {
    const appEnv = data.NEXT_PUBLIC_APP_ENV ?? data.APP_ENV;

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
      const url = data.NEXT_PUBLIC_SUPABASE_URL;
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
      const url = data.NEXT_PUBLIC_SUPABASE_URL;
      if (url.includes(data.STAGING_SUPABASE_PROJECT_REF)) {
        ctx.addIssue({
          code: "custom",
          message:
            "APP_ENV=production cannot point NEXT_PUBLIC_SUPABASE_URL at the staging project",
          path: ["NEXT_PUBLIC_SUPABASE_URL"],
        });
      }
    }
  });

export type AppEnv = z.infer<typeof appEnvSchema>;
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
    PRODUCTION_SUPABASE_PROJECT_REF: process.env.PRODUCTION_SUPABASE_PROJECT_REF,
  };
}

/**
 * Validates environment. Never silently falls back between staging and production.
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
  };
}

export function resetEnvCacheForTests() {
  cached = null;
}
