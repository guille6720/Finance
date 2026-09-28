import { NewCounterpartyPage } from "@/components/counterparties/new-counterparty-page";

export default async function NewSupplierPage() {
  return NewCounterpartyPage({ role: "SUPPLIER" });
}
