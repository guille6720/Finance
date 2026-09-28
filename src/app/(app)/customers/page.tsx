import { CounterpartyPage } from "@/components/demo/counterparty-page";
import { noticeFromSearchParams, type SearchParams } from "@/lib/counterparties/notice";

export default async function CustomersPage({
  searchParams,
}: { searchParams?: Promise<SearchParams> } = {}) {
  return CounterpartyPage({ role: "CUSTOMER", notice: noticeFromSearchParams(await searchParams) });
}
