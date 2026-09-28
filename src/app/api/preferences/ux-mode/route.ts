import { NextRequest, NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { activeOrgCookieOptions } from "@/lib/authz/active-organization";
import { UX_MODE_COOKIE, isUxMode } from "@/lib/ui-mode/constants";

const ONE_YEAR_SECONDS = 60 * 60 * 24 * 365;

/** Persists the UI mode (presentation only; grants no data access). */
export async function POST(request: NextRequest) {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) {
    return NextResponse.json({ error: "UNAUTHORIZED" }, { status: 401 });
  }

  let mode: unknown;
  try {
    mode = (await request.json())?.mode;
  } catch {
    mode = undefined;
  }
  if (!isUxMode(mode)) {
    return NextResponse.json({ error: "INVALID_MODE" }, { status: 400 });
  }

  const response = NextResponse.json({ ok: true, mode });
  response.cookies.set(UX_MODE_COOKIE, mode, {
    ...activeOrgCookieOptions({
      host: request.headers.get("host"),
      protocol: request.nextUrl.protocol,
    }),
    maxAge: ONE_YEAR_SECONDS,
  });
  return response;
}
