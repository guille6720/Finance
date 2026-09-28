import { EditCounterpartyPage } from "@/components/counterparties/edit-counterparty-page";
import { statusNoticeFromSearchParams, type SearchParams } from "@/lib/counterparties/notice";

export default async function SupplierPage({
  params,
  searchParams,
}: {
  params: Promise<{ id: string }>;
  searchParams?: Promise<SearchParams>;
}) {
  const { id } = await params;
  return EditCounterpartyPage({
    role: "SUPPLIER",
    id,
    notice: statusNoticeFromSearchParams(await searchParams),
  });
}
