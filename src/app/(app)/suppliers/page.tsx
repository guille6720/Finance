import { CounterpartyPage } from "@/components/demo/counterparty-page";

export default async function SuppliersPage() {
  return CounterpartyPage({ role: "SUPPLIER" });
}
