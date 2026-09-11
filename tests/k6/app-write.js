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

http.setResponseCallback(http.expectedStatuses(200, 201));

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

export default function writeAppWorkload(data) {
  const headers = {
    apikey: fixture.anonKey,
    Authorization: `Bearer ${data.token}`,
    "Content-Type": "application/json",
    Prefer: "resolution=merge-duplicates,return=representation",
  };

  const key = "phase13.load.marker";
  const upsert = http.post(
    `${API}/rest/v1/organization_settings?on_conflict=organization_id,key`,
    JSON.stringify({
      organization_id: ORG,
      key,
      value: { v: 1, vu: __VU, iter: __ITER, ts: Date.now() },
    }),
    { headers }
  );

  check(upsert, {
    "settings upsert ok": (r) => r.status === 200 || r.status === 201,
  });

  const audit = http.post(
    `${API}/rest/v1/audit_events`,
    JSON.stringify({
      organization_id: ORG,
      actor_user_id: data.userId,
      event_type: "phase13.load",
      entity_type: "organization_settings",
      entity_id: key,
      action: "upsert",
      metadata: { vu: __VU, iter: __ITER },
    }),
    {
      headers: {
        ...headers,
        Prefer: "return=minimal",
      },
    }
  );
  check(audit, {
    "audit insert ok": (r) => r.status === 201 || r.status === 200,
  });

  sleep(0.2);
}
