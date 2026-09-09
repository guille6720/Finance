import { describe, it, expect } from "vitest";
import { onboardingSchema } from "@/lib/onboarding/schema";

describe("onboarding schema", () => {
  it("accepts a complete payload", () => {
    const parsed = onboardingSchema.safeParse({
      legalName: "Demo SRL",
      commercialName: "Demo",
      cuit: "20-12345678-6",
      province: "Buenos Aires",
      city: "CABA",
      fiscalConditionCode: "monotributo",
      fiscalAddress: "Calle 123",
      branchName: "Casa central",
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
      acceptedRecommendedModules: true,
    });
    expect(parsed.success).toBe(true);
    if (parsed.success) {
      expect(parsed.data.cuit).toBe("20123456786");
    }
  });

  it("rejects invalid CUIT", () => {
    const parsed = onboardingSchema.safeParse({
      legalName: "Demo SRL",
      cuit: "20-12345678-0",
      province: "Buenos Aires",
      fiscalConditionCode: "monotributo",
      fiscalAddress: "Calle 123",
      businessType: "retail",
      sellsProducts: true,
      sellsServices: false,
      managesInventory: false,
      hasEmployees: false,
      hasMultipleBranches: false,
      needsProjects: false,
      needsCostCenters: false,
      invoicesCustomers: true,
      worksWithSuppliers: false,
    });
    expect(parsed.success).toBe(false);
  });
});
