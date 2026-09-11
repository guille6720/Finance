import http from "k6/http";
import { check, sleep } from "k6";

const BASE = __ENV.BASE_URL || "http://127.0.0.1:3000";
const VUS = Number(__ENV.VUS || 10);
const DURATION = __ENV.DURATION || "30s";

export const options = {
  vus: VUS,
  duration: DURATION,
  thresholds: {
    http_req_failed: ["rate<0.05"],
    http_req_duration: ["p(95)<2000"],
  },
};

export default function readWorkload() {
  const res = http.get(`${BASE}/api/health`);
  check(res, {
    "status 200": (r) => r.status === 200,
    "ok true": (r) => {
      try {
        return r.json("ok") === true;
      } catch {
        return false;
      }
    },
  });
  sleep(0.2);
}
