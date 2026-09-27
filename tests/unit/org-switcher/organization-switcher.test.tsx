// @vitest-environment jsdom
/**
 * OrganizationSwitcher UI: single vs multiple orgs, switching flow, 403 handling.
 */
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, fireEvent, waitFor, cleanup } from "@testing-library/react";

const router = { push: vi.fn(), refresh: vi.fn() };
vi.mock("next/navigation", () => ({ useRouter: () => router }));

import {
  OrganizationSwitcher,
  ACTIVE_ORGANIZATION_ENDPOINT,
} from "@/components/shell/organization-switcher";
import type { UserOrganization } from "@/lib/authz/active-organization";

const A: UserOrganization = {
  id: "11111111-1111-4111-8111-111111111111",
  role: "owner",
  legalName: "EMPRESA DEMO ARGENTINA SA",
  commercialName: "Empresa Demo",
  displayName: "Empresa Demo",
};
const B: UserOrganization = {
  id: "22222222-2222-4222-8222-222222222222",
  role: "owner",
  legalName: "EMPRESA DEMO BETA SRL",
  commercialName: "Demo Beta",
  displayName: "Demo Beta",
};

beforeEach(() => {
  router.push.mockReset();
  router.refresh.mockReset();
});
afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
});

describe("OrganizationSwitcher", () => {
  it("single organization: shows its name, no dropdown", () => {
    render(<OrganizationSwitcher organizations={[A]} activeOrganizationId={A.id} />);
    expect(screen.getByText("Empresa")).toBeTruthy();
    expect(screen.getByText("Empresa Demo")).toBeTruthy();
    expect(screen.queryByRole("combobox")).toBeNull();
  });

  it("multiple organizations: labelled 'Empresa' select with both names", () => {
    render(<OrganizationSwitcher organizations={[A, B]} activeOrganizationId={A.id} />);
    const select = screen.getByLabelText("Empresa") as HTMLSelectElement;
    expect(select.value).toBe(A.id);
    expect(Array.from(select.options).map((o) => o.textContent)).toEqual([
      "Empresa Demo",
      "Demo Beta",
    ]);
  });

  it("switching calls the secure endpoint, then refreshes and goes to /dashboard", async () => {
    const fetchMock = vi.fn(async () => new Response(JSON.stringify({ ok: true }), { status: 200 }));
    vi.stubGlobal("fetch", fetchMock);
    const onSwitched = vi.fn();
    render(
      <OrganizationSwitcher organizations={[A, B]} activeOrganizationId={A.id} onSwitched={onSwitched} />
    );
    fireEvent.change(screen.getByLabelText("Empresa"), { target: { value: B.id } });

    await waitFor(() => expect(router.refresh).toHaveBeenCalled());
    expect(fetchMock).toHaveBeenCalledWith(
      ACTIVE_ORGANIZATION_ENDPOINT,
      expect.objectContaining({ method: "POST", body: JSON.stringify({ organizationId: B.id }) })
    );
    expect(router.push).toHaveBeenCalledWith("/dashboard");
    expect(onSwitched).toHaveBeenCalled();
  });

  it("shows a loading state while switching", async () => {
    let release: (r: Response) => void = () => {};
    vi.stubGlobal(
      "fetch",
      vi.fn(() => new Promise<Response>((res) => (release = res)))
    );
    render(<OrganizationSwitcher organizations={[A, B]} activeOrganizationId={A.id} />);
    fireEvent.change(screen.getByLabelText("Empresa"), { target: { value: B.id } });
    expect(await screen.findByRole("status")).toBeTruthy();
    expect((screen.getByLabelText("Empresa") as HTMLSelectElement).disabled).toBe(true);
    release(new Response("{}", { status: 200 }));
    await waitFor(() => expect(router.refresh).toHaveBeenCalled());
  });

  it("403: reverts selection, shows error, does not navigate", async () => {
    vi.stubGlobal("fetch", vi.fn(async () => new Response("{}", { status: 403 })));
    render(<OrganizationSwitcher organizations={[A, B]} activeOrganizationId={A.id} />);
    const select = screen.getByLabelText("Empresa") as HTMLSelectElement;
    fireEvent.change(select, { target: { value: B.id } });
    expect((await screen.findByRole("alert")).textContent).toMatch(/No tenés acceso/);
    expect(select.value).toBe(A.id);
    expect(router.push).not.toHaveBeenCalled();
    expect(router.refresh).not.toHaveBeenCalled();
  });
});
