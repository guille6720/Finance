import { describe, it, expect } from "vitest";
import { isPublicPreviewDemoEnabled, publicPreviewMaxTesters } from "@/config/preview";

describe("public preview flag", () => {
  it("is off by default in Production and locally", () => {
    expect(isPublicPreviewDemoEnabled({ VERCEL_ENV: "production" })).toBe(false);
    expect(isPublicPreviewDemoEnabled({ APP_ENV: "production" })).toBe(false);
    expect(isPublicPreviewDemoEnabled({})).toBe(false);
  });

  it("is on by default in Vercel Preview and APP_ENV=staging", () => {
    expect(isPublicPreviewDemoEnabled({ VERCEL_ENV: "preview" })).toBe(true);
    expect(isPublicPreviewDemoEnabled({ APP_ENV: "staging" })).toBe(true);
  });

  it("an explicit PUBLIC_PREVIEW_DEMO_ENABLED wins", () => {
    expect(isPublicPreviewDemoEnabled({ VERCEL_ENV: "preview", PUBLIC_PREVIEW_DEMO_ENABLED: "false" })).toBe(false);
    expect(isPublicPreviewDemoEnabled({ PUBLIC_PREVIEW_DEMO_ENABLED: "true" })).toBe(true);
    expect(isPublicPreviewDemoEnabled({ PUBLIC_PREVIEW_DEMO_ENABLED: " TRUE " })).toBe(true);
  });

  it("PUBLIC_PREVIEW_MAX_TESTERS defaults to 5 and never exceeds it", () => {
    expect(publicPreviewMaxTesters({})).toBe(5);
    expect(publicPreviewMaxTesters({ PUBLIC_PREVIEW_MAX_TESTERS: "3" })).toBe(3);
    expect(publicPreviewMaxTesters({ PUBLIC_PREVIEW_MAX_TESTERS: "50" })).toBe(5);
    expect(publicPreviewMaxTesters({ PUBLIC_PREVIEW_MAX_TESTERS: "abc" })).toBe(5);
  });
});
