import http from "k6/http";
import { check, sleep } from "k6";

const API = __ENV.SUPABASE_URL || "http://127.0.0.1:54321";
const ANON = __ENV.SUPABASE_ANON_KEY || "";
const APP = __ENV.BASE_URL || "http://127.0.0.1:3000";
const VUS = Number(__ENV.VUS || 10);
const DURATION = __ENV.DURATION || "30s";

export const options = {
  vus: VUS,
  duration: DURATION,
  thresholds: {
    http_req_failed: ["rate<0.1"],
    http_req_duration: ["p(95)<3000"],
  },
};

export default function mixedWorkload() {
  const health = http.get(`${APP}/api/health`);
  check(health, { "health 200": (r) => r.status === 200 });

  const catalog = http.get(
    `${API}/rest/v1/feature_catalog?select=code&limit=5`,
    {
      headers: {
        apikey: ANON,
        Authorization: `Bearer ${ANON}`,
      },
    }
  );
  check(catalog, {
    "catalog not 5xx": (r) => r.status < 500,
  });

  if (__ITER % 5 === 0) {
    const email = `k6.mixed.${__VU}.${Date.now()}@example.com`;
    const password = "Phase13-Test-Only-1!";
    const signup = http.post(
      `${API}/auth/v1/signup`,
      JSON.stringify({ email, password }),
      {
        headers: {
          apikey: ANON,
          "Content-Type": "application/json",
        },
      }
    );
    check(signup, { "signup not 5xx": (r) => r.status < 500 });
  }

  sleep(0.2);
}
