import { cookies } from "next/headers";
import { UX_MODE_COOKIE, parseUxMode, type UxMode } from "@/lib/ui-mode/constants";

export async function getUxMode(): Promise<UxMode> {
  const cookieStore = await cookies();
  return parseUxMode(cookieStore.get(UX_MODE_COOKIE)?.value);
}
