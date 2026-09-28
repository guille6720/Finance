import { NewCounterpartyPage } from "@/components/counterparties/new-counterparty-page";

export default async function NewCustomerPage() {
  return NewCounterpartyPage({ role: "CUSTOMER" });
}
