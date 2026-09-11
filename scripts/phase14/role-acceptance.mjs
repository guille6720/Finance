#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { PHASE14_DIR } from "./env.mjs";
import { runCrossTenantMatrix } from "../phase13/cross-tenant-matrix.mjs";

const ROLE_PERMISSIONS = {
  owner: ["*"],
  admin: ["org.update", "members.manage_roles", "features.manage", "accounting.manage_periods"],
  manager: ["org.read", "branches.manage", "accounting.read"],
  operator: ["org.read", "features.read"],
  accountant: ["fiscal.update", "accounting.manage_periods", "audit.read"],
  viewer: ["org.read", "accounting.read", "audit.read"],
};

const RESOURCES = [
  "organization",
  "members",
  "sales",
  "purchases",
  "treasury",
  "inventory",
  "accounting",
  "taxes",
  "pos",
  "dashboard",
  "export",
  "configure",
];

const ROLES = ["owner", "admin", "manager", "operator", "accountant", "viewer"];

function cell(role, resource, action) {
  const mutate = role !== "viewer";
  const configure = role === "owner" || role === "admin";
  const post = ["owner", "admin", "manager", "operator", "accountant"].includes(role);
  const reverse = ["owner", "admin", "accountant"].includes(role);
  const read = true;

  if (action === "read") return read;
  if (action === "create" || action === "update") return mutate && resource !== "configure";
  if (action === "post") return post && !["dashboard", "export", "configure"].includes(resource);
  if (action === "reverse") return reverse && ["sales", "purchases", "treasury", "inventory", "accounting", "taxes"].includes(resource);
  if (action === "delete/configure") return configure;
  return false;
}

export async function runAuthorizationAcceptance() {
  const live = await runCrossTenantMatrix();
  const matrix = [];
  for (const role of ROLES) {
    for (const resource of RESOURCES) {
      matrix.push({
        role,
        resource,
        read: cell(role, resource, "read"),
        create: cell(role, resource, "create"),
        update: cell(role, resource, "update"),
        post: cell(role, resource, "post"),
        reverse: cell(role, resource, "reverse"),
        "delete/configure": cell(role, resource, "delete/configure"),
        app_permissions: ROLE_PERMISSIONS[role] || [],
      });
    }
  }

  const result = {
    AUTHORIZATION_ACCEPTANCE: live.status,
    status: live.status,
    live_cases: live.detail,
    failed: live.failed || [],
    matrix,
    note: "Positive/negative live cases from cross-tenant × roles; matrix documents expected module verbs.",
  };

  fs.mkdirSync(PHASE14_DIR, { recursive: true });
  fs.writeFileSync(
    path.join(PHASE14_DIR, "authorization-acceptance-last-run.json"),
    JSON.stringify(result, null, 2) + "\n"
  );
  return result;
}

if (process.argv[1]?.endsWith("role-acceptance.mjs")) {
  runAuthorizationAcceptance().then((r) => {
    console.log(JSON.stringify({ status: r.status, cases: r.live_cases }, null, 2));
    if (r.status !== "PASS") process.exit(1);
  }).catch((e) => { console.error(e); process.exit(1); });
}
