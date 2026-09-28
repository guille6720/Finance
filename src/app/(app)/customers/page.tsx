import { CounterpartyPage } from "@/components/demo/counterparty-page";

export default async function CustomersPage() {
  return CounterpartyPage({ role: "CUSTOMER" });
}
