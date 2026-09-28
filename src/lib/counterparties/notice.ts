import type { CounterpartyNotice } from "@/components/demo/counterparty-page";

export type SearchParams = Record<string, string | string[] | undefined>;

export function noticeFromSearchParams(params: SearchParams | undefined): CounterpartyNotice {
  if (!params) return null;
  if (params.creado === "1") return "created";
  if (params.actualizado === "1") return "updated";
  return null;
}
