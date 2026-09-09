import { describe, it, expect } from "vitest";
import { recommendFeatures } from "@/lib/onboarding/schema";
import {
  featureNavVisible,
  isFeatureUsable,
} from "@/lib/features/entitlements";

describe("feature recommendations", () => {
  it("recommends inventory when selling products", () => {
    const rec = recommendFeatures({
      businessType: "retail",
      sellsProducts: true,
      sellsServices: false,
      managesInventory: true,
      hasEmployees: false,
      hasMultipleBranches: false,
      needsProjects: false,
      needsCostCenters: false,
      invoicesCustomers: true,
      worksWithSuppliers: true,
    });
    expect(rec.some((r) => r.code === "inventory")).toBe(true);
    expect(rec.some((r) => r.code === "customers")).toBe(true);
  });

  it("marks medical_legal for healthcare", () => {
    const rec = recommendFeatures({
      businessType: "healthcare",
      sellsProducts: false,
      sellsServices: true,
      managesInventory: false,
      hasEmployees: true,
      hasMultipleBranches: false,
      needsProjects: false,
      needsCostCenters: false,
      invoicesCustomers: true,
      worksWithSuppliers: false,
    });
    expect(rec.some((r) => r.code === "medical_legal")).toBe(true);
  });
});

describe("feature entitlements", () => {
  it("only enabled features are usable", () => {
    expect(isFeatureUsable("enabled")).toBe(true);
    expect(isFeatureUsable("disabled")).toBe(false);
    expect(isFeatureUsable("restricted")).toBe(false);
  });

  it("nav visibility respects flags", () => {
    expect(featureNavVisible("sales", "enabled")).toBe("active");
    expect(featureNavVisible("sales", "disabled")).toBe("coming_soon");
    expect(featureNavVisible("sales", "disabled", { showComingSoon: false })).toBe(
      "hidden"
    );
  });
});
