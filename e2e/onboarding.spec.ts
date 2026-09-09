import { test, expect } from "@playwright/test";

/**
 * Critical path smoke tests.
 * Full authenticated onboarding requires a staging Supabase project.
 * These tests cover the public/first-run surfaces that must always work.
 */

test.describe("critical surfaces", () => {
  test("landing shows brand and CTAs", async ({ page }) => {
    await page.goto("/");
    await expect(page.getByRole("link", { name: "Empezar" })).toBeVisible();
    await expect(page.getByRole("link", { name: "Ingresar" })).toBeVisible();
  });

  test("login form is accessible", async ({ page }) => {
    await page.goto("/login");
    await expect(page.getByLabel("Email")).toBeVisible();
    await expect(page.getByLabel("Contraseña")).toBeVisible();
    await expect(page.getByRole("button", { name: "Ingresar" })).toBeVisible();
  });

  test("register form is accessible", async ({ page }) => {
    await page.goto("/register");
    await expect(page.getByLabel("Nombre")).toBeVisible();
    await expect(page.getByLabel("Email")).toBeVisible();
    await expect(page.getByRole("button", { name: "Crear cuenta" })).toBeVisible();
  });

  test("unauthenticated dashboard redirects to login", async ({ page }) => {
    await page.goto("/dashboard");
    await expect(page).toHaveURL(/login/);
  });

  test("register page renders heading", async ({ page }) => {
    await page.goto("/register");
    await expect(page.getByRole("heading", { name: "Crear cuenta" })).toBeVisible();
  });
});

test.describe("onboarding path (requires staging auth)", () => {
  test.skip(
    !process.env.E2E_EMAIL || !process.env.E2E_PASSWORD,
    "Set E2E_EMAIL and E2E_PASSWORD against staging to run"
  );

  test("authenticated user can open onboarding wizard", async ({ page }) => {
    await page.goto("/login");
    await page.getByLabel("Email").fill(process.env.E2E_EMAIL!);
    await page.getByLabel("Contraseña").fill(process.env.E2E_PASSWORD!);
    await page.getByRole("button", { name: "Ingresar" }).click();
    await page.waitForURL(/dashboard|onboarding/);
    if (page.url().includes("dashboard")) {
      test.info().annotations.push({
        type: "note",
        description: "User already onboarded — dashboard reached",
      });
      return;
    }
    await expect(page.getByText(/Configuremos tu empresa/i)).toBeVisible();
    await expect(page.getByText(/Paso 1 de 7/i)).toBeVisible();
    await page.getByRole("button", { name: "Continuar" }).click();
    await expect(page.getByText(/Paso 2 de 7/i)).toBeVisible();
  });
});
