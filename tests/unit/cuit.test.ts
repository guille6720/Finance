import { describe, it, expect } from "vitest";
import { isValidCuit, cleanCuit, formatCuit } from "@/lib/validations/argentina";
import { assertValidCuit } from "@/lib/cuit/validate";

describe("CUIT validation", () => {
  it("accepts valid CUIT", () => {
    expect(isValidCuit("20-12345678-6")).toBe(true);
    expect(cleanCuit("20-12345678-6")).toBe("20123456786");
    expect(formatCuit("20123456786")).toBe("20-12345678-6");
  });

  it("rejects invalid CUIT", () => {
    expect(isValidCuit("20-12345678-0")).toBe(false);
    expect(() => assertValidCuit("123")).toThrow();
  });
});
