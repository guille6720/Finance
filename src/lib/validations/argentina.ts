export function cleanCuit(cuit: string): string {
  return cuit.replace(/[-\s]/g, "");
}

export function formatCuit(cuit: string): string {
  const clean = cleanCuit(cuit);
  if (clean.length !== 11) return cuit;
  return `${clean.slice(0, 2)}-${clean.slice(2, 10)}-${clean.slice(10)}`;
}

export function isValidCuit(cuit: string): boolean {
  const clean = cleanCuit(cuit);
  if (!/^\d{11}$/.test(clean)) return false;

  const multipliers = [5, 4, 3, 2, 7, 6, 5, 4, 3, 2];
  const digits = clean.split("").map(Number);
  const checkDigit = digits[10];
  const sum = multipliers.reduce((acc, mult, i) => acc + digits[i] * mult, 0);
  const remainder = sum % 11;
  const expected = remainder === 0 ? 0 : remainder === 1 ? 9 : 11 - remainder;

  return checkDigit === expected;
}

export function isValidEmail(email: string): boolean {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
}

export const ARGENTINA_PROVINCES = [
  "Buenos Aires",
  "CABA",
  "Catamarca",
  "Chaco",
  "Chubut",
  "Córdoba",
  "Corrientes",
  "Entre Ríos",
  "Formosa",
  "Jujuy",
  "La Pampa",
  "La Rioja",
  "Mendoza",
  "Misiones",
  "Neuquén",
  "Río Negro",
  "Salta",
  "San Juan",
  "San Luis",
  "Santa Cruz",
  "Santa Fe",
  "Santiago del Estero",
  "Tierra del Fuego",
  "Tucumán",
] as const;

export const EXPENSE_CATEGORIES = [
  "Mercadería",
  "Alquiler",
  "Servicios",
  "Sueldos",
  "Impuestos",
  "Publicidad",
  "Transporte",
  "Comisiones",
  "Honorarios",
  "Mantenimiento",
  "Otros",
] as const;
