import { cleanCuit, formatCuit, isValidCuit } from "@/lib/validations/argentina";

export { cleanCuit as normalizeCuit, formatCuit, isValidCuit };

export function assertValidCuit(cuit: string): string {
  const normalized = cleanCuit(cuit);
  if (!isValidCuit(normalized)) {
    throw new Error("El CUIT ingresado no es válido");
  }
  return normalized;
}
