import { NextRequest, NextResponse } from "next/server";

export async function GET(request: NextRequest) {
  const correlationId =
    request.headers.get("x-request-id") ||
    request.headers.get("x-correlation-id") ||
    crypto.randomUUID();

  return NextResponse.json(
    {
      ok: true,
      phase: 14,
      app_env: process.env.NEXT_PUBLIC_APP_ENV ?? process.env.APP_ENV ?? "local",
      arca_env: process.env.ARCA_ENV ?? "disabled",
      production_authorized: false,
      timestamp: new Date().toISOString(),
    },
    {
      headers: {
        "x-request-id": correlationId,
        "x-correlation-id": correlationId,
      },
    }
  );
}
