import { createClient } from "@supabase/supabase-js";
import { getServerEnv } from "@/config/env";

/**
 * Service-role client. Server-only. Never import from client components.
 * Bypasses RLS — use only for trusted admin/system operations.
 */
export function createAdminClient() {
  const env = getServerEnv();
  if (!env.SUPABASE_SERVICE_ROLE_KEY) {
    throw new Error("SUPABASE_SERVICE_ROLE_KEY is required for admin operations");
  }
  return createClient(
    env.NEXT_PUBLIC_SUPABASE_URL,
    env.SUPABASE_SERVICE_ROLE_KEY,
    {
      auth: {
        persistSession: false,
        autoRefreshToken: false,
      },
    }
  );
}
