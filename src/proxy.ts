import { type NextRequest } from "next/server";
import { updateSession } from "@/lib/supabase/middleware";

function correlationId(request: NextRequest): string {
  return (
    request.headers.get("x-request-id") ||
    request.headers.get("x-correlation-id") ||
    crypto.randomUUID()
  );
}

export async function proxy(request: NextRequest) {
  const response = await updateSession(request);
  const id = correlationId(request);
  response.headers.set("x-request-id", id);
  response.headers.set("x-correlation-id", id);
  return response;
}

export const config = {
  matcher: [
    "/((?!_next/static|_next/image|favicon.ico|brand/|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)",
  ],
};
