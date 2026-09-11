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

// 404 on missing domain tables is expected (PGRST205), not an app failure
http.setResponseCallback(http.expectedStatuses(200, 404));

export const options = {
  vus: VUS,
  duration: DURATION,
  thresholds: {
    http_req_failed: ["rate<0.05"],
    http_req_duration: ["p(95)<3000"],
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
  return { token: login.json("access_token") };
}

function h(token) {
  return {
    apikey: fixture.anonKey,
    Authorization: `Bearer ${token}`,
  };
}

export default function readAppWorkload(data) {
  const headers = h(data.token);

  // Real Phase-1 dashboard / catalog reads (same contracts as app)
  const real = [
    `organizations?id=eq.${ORG}&select=id,legal_name,status`,
    `organization_members?organization_id=eq.${ORG}&status=eq.active&select=id,role`,
    `organization_features?organization_id=eq.${ORG}&select=id,status,feature_id`,
    `branches?organization_id=eq.${ORG}&select=id,name,code`,
    `fiscal_profiles?organization_id=eq.${ORG}&select=id,fiscal_condition_id`,
    `business_profiles?organization_id=eq.${ORG}&select=id,business_type`,
    `accounting_periods?organization_id=eq.${ORG}&select=id,name,is_closed`,
    `audit_events?organization_id=eq.${ORG}&select=id,event_type,created_at&order=created_at.desc&limit=10`,
    // Phase 3–8 domain tables (now present in schema)
    `counterparties?organization_id=eq.${ORG}&select=id,legal_name,tax_id&limit=5`,
    `products?organization_id=eq.${ORG}&select=id,sku,name,product_type&limit=5`,
    `journal_entries?organization_id=eq.${ORG}&select=id,entry_date,status&limit=5`,
    `treasury_accounts?organization_id=eq.${ORG}&select=id,code,account_type&limit=5`,
    `warehouses?organization_id=eq.${ORG}&select=id,code,name&limit=5`,
  ];

  for (const q of real) {
    const res = http.get(`${API}/rest/v1/${q}`, { headers });
    check(res, { [`200 ${q.split("?")[0]}`]: (r) => r.status === 200 });
  }

  // Only truly non-existent table aliases should be expected as 404
  const missing = ["customers", "tax_books"];
  for (const t of missing) {
    const res = http.get(`${API}/rest/v1/${t}?select=id&limit=1`, { headers });
    check(res, { [`404 missing ${t}`]: (r) => r.status === 404 });
  }

  sleep(0.15);
}
