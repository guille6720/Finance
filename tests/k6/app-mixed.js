import http from "k6/http";
import { check, sleep } from "k6";
import { SharedArray } from "k6/data";

const fixture = new SharedArray("fixture", () => {
  const raw = open("../../docs/qa/phase13/load-fixture.json");
  return [JSON.parse(raw)];
})[0];

const VUS = Number(__ENV.VUS || 10);
const DURATION = __ENV.DURATION || "20s";
const API = fixture.supabaseUrl;
const ORG = fixture.orgId;

http.setResponseCallback(http.expectedStatuses(200, 201, 404));

export const options = {
  vus: VUS,
  duration: DURATION,
  thresholds: {
    http_req_failed: ["rate<0.08"],
    http_req_duration: ["p(95)<4000"],
  },
};

export function setup() {
  const login = http.post(
    `${API}/auth/v1/token?grant_type=password`,
    JSON.stringify({ email: fixture.email, password: fixture.password }),
    {
      headers: {
        apikey: fixture.anonKey,
        "Content-Type": "application/json",
      },
    }
  );
  return { token: login.json("access_token"), userId: login.json("user.id") };
}

export default function mixedAppWorkload(data) {
  const headers = {
    apikey: fixture.anonKey,
    Authorization: `Bearer ${data.token}`,
    "Content-Type": "application/json",
  };

  const dash = http.get(
    `${API}/rest/v1/organizations?id=eq.${ORG}&select=id,status`,
    { headers }
  );
  check(dash, { "org read 200": (r) => r.status === 200 });

  const branches = http.get(
    `${API}/rest/v1/branches?organization_id=eq.${ORG}&select=id,name`,
    { headers }
  );
  check(branches, { "branches 200": (r) => r.status === 200 });

  const periods = http.get(
    `${API}/rest/v1/accounting_periods?organization_id=eq.${ORG}&select=id,name`,
    { headers }
  );
  check(periods, { "periods 200": (r) => r.status === 200 });

  if (__ITER % 3 === 0) {
    const w = http.post(
      `${API}/rest/v1/organization_settings?on_conflict=organization_id,key`,
      JSON.stringify({
        organization_id: ORG,
        key: "phase13.load.marker",
        value: { mixed: true, vu: __VU, iter: __ITER },
      }),
      {
        headers: {
          ...headers,
          Prefer: "resolution=merge-duplicates,return=representation",
        },
      }
    );
    check(w, {
      "write upsert ok": (r) => r.status === 200 || r.status === 201,
    });
  }

  // Domain reads: counterparties and products are real Phase 3/8 tables
  const counterparties = http.get(
    `${API}/rest/v1/counterparties?organization_id=eq.${ORG}&select=id,legal_name&limit=5`,
    { headers }
  );
  check(counterparties, { "counterparties 200": (r) => r.status === 200 });

  const products = http.get(
    `${API}/rest/v1/products?organization_id=eq.${ORG}&select=id,sku,name&limit=5`,
    { headers }
  );
  check(products, { "products 200": (r) => r.status === 200 });

  sleep(0.15);
}
