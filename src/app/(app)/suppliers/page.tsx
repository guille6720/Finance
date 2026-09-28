import { CounterpartyPage } from "@/components/demo/counterparty-page";
import { noticeFromSearchParams, type SearchParams } from "@/lib/counterparties/notice";

export default async function SuppliersPage({
  searchParams,
}: { searchParams?: Promise<SearchParams> } = {}) {
  return CounterpartyPage({ role: "SUPPLIER", notice: noticeFromSearchParams(await searchParams) });
}
