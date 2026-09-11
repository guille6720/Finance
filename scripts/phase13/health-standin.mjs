#!/usr/bin/env node
/**
 * Lightweight Phase 13 stand-in for GET /api/health when Next.js cannot
 * co-reside with local Supabase Docker (host OOM). Same JSON contract as
 * src/app/api/health/route.ts.
 */
import http from "node:http";

const port = Number(process.env.PORT || 3000);

const server = http.createServer((req, res) => {
  if (req.url?.startsWith("/api/health")) {
    const body = JSON.stringify({
      ok: true,
      phase: 1,
      timestamp: new Date().toISOString(),
      stand_in: "phase13-health",
    });
    res.writeHead(200, { "Content-Type": "application/json" });
    res.end(body);
    return;
  }
  res.writeHead(404).end("not found");
});

server.listen(port, "127.0.0.1", () => {
  console.log(`phase13 health stand-in on http://127.0.0.1:${port}`);
});
