import http from "k6/http";
import { check, sleep } from "k6";

const API = __ENV.SUPABASE_URL || "http://127.0.0.1:54321";
const ANON = __ENV.SUPABASE_ANON_KEY || "";
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

export default function writeWorkload() {
  const email = `k6.write.${__VU}.${Date.now()}@example.com`;
  const password = "Phase13-Test-Only-1!";

  const signup = http.post(
    `${API}/auth/v1/signup`,
    JSON.stringify({
      email,
      password,
      data: { full_name: "k6 write" },
    }),
    {
      headers: {
        apikey: ANON,
        "Content-Type": "application/json",
      },
    }
  );

  check(signup, {
    "signup not 5xx": (r) => r.status < 500,
  });

  const login = http.post(
    `${API}/auth/v1/token?grant_type=password`,
    JSON.stringify({ email, password }),
    {
      headers: {
        apikey: ANON,
        "Content-Type": "application/json",
      },
    }
  );

  const token = login.json("access_token");
  check(login, {
    "login 200": (r) => r.status === 200,
    "has token": () => !!token,
  });

  if (!token) {
    sleep(0.3);
    return;
  }

  const userId = login.json("user.id");
  const org = http.post(
    `${API}/rest/v1/organizations`,
    JSON.stringify({
      legal_name: `k6 org ${__VU} ${Date.now()}`,
      created_by: userId,
      status: "active",
    }),
    {
      headers: {
        apikey: ANON,
        Authorization: `Bearer ${token}`,
        "Content-Type": "application/json",
        Prefer: "return=representation",
      },
    }
  );

  check(org, {
    "org create ok": (r) => r.status === 201 || r.status === 200,
  });

  sleep(0.25);
}
