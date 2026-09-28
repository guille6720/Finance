import type { CounterpartyNotice } from "@/components/demo/counterparty-page";
import type { CounterpartyPageNotice } from "@/components/counterparties/edit-counterparty-page";

export type SearchParams = Record<string, string | string[] | undefined>;

export function noticeFromSearchParams(params: SearchParams | undefined): CounterpartyNotice {
  if (!params) return null;
  if (params.creado === "1") return "created";
  if (params.actualizado === "1") return "updated";
  if (params.guardado === "1") return "saved";
  if (params.eliminado === "1") return "deleted";
  return null;
}

export function statusNoticeFromSearchParams(params: SearchParams | undefined): CounterpartyPageNotice {
  if (params?.activado === "1") return "activado";
  if (params?.desactivado === "1") return "desactivado";
  return null;
}
