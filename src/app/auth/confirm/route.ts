import { NextResponse, type NextRequest } from "next/server";
import type { EmailOtpType } from "@supabase/supabase-js";
import { createClient } from "@/lib/supabase/server";
import { safeNextPath } from "@/lib/auth/messages";

const OTP_TYPES: readonly EmailOtpType[] = ["signup", "email", "invite", "magiclink", "recovery", "email_change"];

/** Landing point of Supabase confirmation links (PKCE `code` or `token_hash`). */
export async function GET(request: NextRequest) {
  const url = request.nextUrl;
  const next = safeNextPath(url.searchParams.get("next"), "/onboarding");
  const code = url.searchParams.get("code");
  const tokenHash = url.searchParams.get("token_hash");
  const type = url.searchParams.get("type") as EmailOtpType | null;

  const supabase = await createClient();
  let ok = false;
  if (code) {
    ok = !(await supabase.auth.exchangeCodeForSession(code)).error;
  } else if (tokenHash && type && OTP_TYPES.includes(type)) {
    ok = !(await supabase.auth.verifyOtp({ type, token_hash: tokenHash })).error;
  }

  const target = url.clone();
  target.search = "";
  if (ok) {
    target.pathname = next;
  } else {
    target.pathname = "/login";
    target.searchParams.set("aviso", "confirmacion");
  }
  return NextResponse.redirect(target);
}
