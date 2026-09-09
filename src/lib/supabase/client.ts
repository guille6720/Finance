import { createBrowserClient } from "@supabase/ssr";
import { getPublicEnv } from "@/config/env";

export function createClient() {
  const { supabaseUrl, supabaseAnonKey } = getPublicEnv();
  if (!supabaseUrl || !supabaseAnonKey) {
    throw new Error("Missing NEXT_PUBLIC_SUPABASE_URL or NEXT_PUBLIC_SUPABASE_ANON_KEY");
  }
  return createBrowserClient(supabaseUrl, supabaseAnonKey);
}
