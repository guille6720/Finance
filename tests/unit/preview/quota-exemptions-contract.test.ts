/**
 * Static contract for the quota-exemption migration. Behaviour against a real database
 * is covered by supabase/tests/preview_quota_exemptions.sql (self rolling back).
 */
import { readFileSync } from "node:fs";
import path from "node:path";
import { describe, it, expect } from "vitest";

const read = (p: string) => readFileSync(path.join(process.cwd(), p), "utf8");
const strip = (s: string) =>
  s
    .split("\n")
    .filter((l) => !l.trim().startsWith("--"))
    .join("\n");

const code = strip(read("supabase/migrations/20261401110000_preview_quota_exemptions.sql"));
const behaviour = read("supabase/tests/preview_quota_exemptions.sql");

function fn(name: string) {
  const start = code.indexOf(`create or replace function public.${name}(`);
  expect(start, name).toBeGreaterThanOrEqual(0);
  const next = code.indexOf("create or replace function", start + 10);
  return code.slice(start, next > 0 ? next : undefined);
}

const trigger = fn("staging_reserve_tester_and_seed");
const mark = fn("preview_set_quota_exemption");
const quota = fn("preview_tester_quota");
const eligible = fn("preview_demo_org_eligible");

describe("exemptions are explicit and server-controlled", () => {
  it("lives in a table clients cannot read or write", () => {
    expect(code).toContain("create table if not exists public.preview_quota_exemptions");
    expect(code).toContain("revoke all on table public.preview_quota_exemptions from public, anon, authenticated;");
    expect(code).toContain("alter table public.preview_quota_exemptions enable row level security;");
    expect(code).toMatch(/check \(reason in \('owner', 'internal', 'internal_qa', 'e2e'\)\)/);
  });

  it("only the platform can mark an account exempt", () => {
    expect(mark).toContain("perform public.modules_assert_service_role();");
    expect(code).toContain(
      "revoke all on function public.preview_set_quota_exemption(uuid, text, text) from public, anon, authenticated;"
    );
    expect(code).toContain("grant execute on function public.preview_set_quota_exemption(uuid, text, text) to service_role;");
  });

  it("never derives exemptions from names, emails or user metadata", () => {
    for (const block of [trigger, mark, quota, eligible]) {
      expect(block).not.toMatch(/email|legal_name|trade_name|user_metadata|raw_user_meta_data|app_metadata|\blike\b|ilike/i);
    }
  });
});

describe("slot allocation", () => {
  it("skips exempt accounts under the same lock, before looking at slots", () => {
    const lock = trigger.indexOf("pg_advisory_xact_lock(hashtext('finance_staging_public_tester_slots_v1'))");
    const exempt = trigger.indexOf("public.preview_quota_exemptions e where e.user_id = new.created_by");
    const retry = trigger.indexOf("public.staging_tester_slots s where s.user_id = new.created_by");
    const allocate = trigger.indexOf("generate_series(1, v_settings.max_testers)");
    expect(lock).toBeGreaterThan(0);
    expect(lock).toBeLessThan(exempt);
    expect(exempt).toBeLessThan(retry);
    expect(retry).toBeLessThan(allocate);
  });

  it("still rejects once every external slot is taken", () => {
    expect(trigger).toMatch(/if v_slot is null then\s+raise exception using\s+errcode = 'P0001',\s+message = 'STAGING_TESTER_LIMIT_REACHED'/);
  });

  it("marking an account exempt releases only that account's slot, serialized with allocation", () => {
    expect(mark).toContain("pg_advisory_xact_lock(hashtext('finance_staging_public_tester_slots_v1'))");
    expect(mark).toContain("delete from public.staging_tester_slots s where s.user_id = p_user_id;");
    expect(mark.match(/delete from/g)).toHaveLength(1);
    expect(code.match(/delete from/g)).toHaveLength(1);
  });
});

describe("reporting and eligibility", () => {
  it("counts only slots of non-exempt users, and only internal callers can read it", () => {
    expect(quota).toContain("auth.role() is distinct from 'service_role'");
    expect(quota).toContain("not public.preview_is_quota_exempt(auth.uid())");
    expect(quota).toMatch(/return null;/);
    expect(quota).toContain("where not exists (select 1 from public.preview_quota_exemptions e where e.user_id = s.user_id)");
  });

  it("exempt creators keep demo data; tenant rules unchanged (owner of that org, not a demo org)", () => {
    expect(eligible).toContain("join public.preview_quota_exemptions e on e.user_id = o.created_by");
    expect(eligible).toContain("where o.id = p_organization_id");
    expect(eligible).toContain("public.staging_tester_slots s where s.organization_id = p_organization_id");
    expect(eligible).toContain("os.key = 'demo.is_demo'");
    expect(eligible).toContain("public.has_org_role(p_organization_id, array['owner']::public.member_role[])");
  });

  it("is non-destructive", () => {
    expect(code).not.toMatch(/\bdrop\s+(table|function|trigger|policy)\b|\btruncate\b|disable row level security/i);
  });
});

describe("database behaviour script", () => {
  it("covers every quota scenario and always rolls back", () => {
    for (const scenario of [
      "owner_no_slot",
      "internal_qa_no_slot",
      "external_1_5_accepted",
      "external_6_rejected",
      "external_retry_no_new_slot",
      "internal_retry_no_slot",
      "internal_remark_quota_unchanged",
      "tenant_isolation",
      "quota_report",
    ]) {
      expect(behaviour).toContain(scenario);
    }
    expect(behaviour).toContain("raise exception 'PREVIEW_QUOTA_TEST_PASSED");
  });
});
