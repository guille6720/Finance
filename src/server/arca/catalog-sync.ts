import type { CatalogRow } from "./wsfe";

/**
 * Map ARCA FEParam rows to Phase 5 fiscal_parameter_catalogs-shaped records.
 * Does not invent IDs. Does not write to the database (no unsafe contract yet).
 * Live homologation evidence + future secure upsert should use this mapping.
 */
export type FiscalCatalogUpsertRow = {
  environment: "HOMOLOGATION";
  catalog_kind: string;
  code: string;
  label: string | null;
  valid_from: string | null;
  valid_to: string | null;
  raw: Record<string, string | null>;
  source_method: string;
};

function mapRows(
  catalog_kind: string,
  source_method: string,
  rows: CatalogRow[],
  idField = "Id",
  labelField = "Desc"
): FiscalCatalogUpsertRow[] {
  return rows
    .filter((r) => r[idField] != null && String(r[idField]).length > 0)
    .map((r) => ({
      environment: "HOMOLOGATION" as const,
      catalog_kind,
      code: String(r[idField]),
      label: r[labelField] != null ? String(r[labelField]) : null,
      valid_from: r.FchDesde != null ? String(r.FchDesde) : null,
      valid_to: r.FchHasta != null ? String(r.FchHasta) : null,
      raw: { ...r },
      source_method,
    }));
}

export function mapCondicionIvaReceptor(rows: CatalogRow[]) {
  return mapRows(
    "CONDICION_IVA_RECEPTOR",
    "FEParamGetCondicionIvaReceptor",
    rows
  );
}

export function mapTiposCbte(rows: CatalogRow[]) {
  return mapRows("TIPOS_CBTE", "FEParamGetTiposCbte", rows);
}

export function mapTiposDoc(rows: CatalogRow[]) {
  return mapRows("TIPOS_DOC", "FEParamGetTiposDoc", rows);
}

export function mapTiposMonedas(rows: CatalogRow[]) {
  return mapRows("MONEDAS", "FEParamGetTiposMonedas", rows);
}
