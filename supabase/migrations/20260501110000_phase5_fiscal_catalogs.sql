-- Phase 5 — Fiscal catalogs + seed rule version (STAGING)

-- Official WSFE voucher types (Phase 5 enabled subset)
insert into public.fiscal_document_types (
  internal_code, arca_cbte_tipo, name, document_class, operation_kind, enabled_phase5, effective_from
) values
  ('INVOICE_A', 1, 'Factura A', 'A', 'INVOICE', true, '2000-01-01'),
  ('DEBIT_NOTE_A', 2, 'Nota de Débito A', 'A', 'DEBIT_NOTE', true, '2000-01-01'),
  ('CREDIT_NOTE_A', 3, 'Nota de Crédito A', 'A', 'CREDIT_NOTE', true, '2000-01-01'),
  ('INVOICE_B', 6, 'Factura B', 'B', 'INVOICE', true, '2000-01-01'),
  ('DEBIT_NOTE_B', 7, 'Nota de Débito B', 'B', 'DEBIT_NOTE', true, '2000-01-01'),
  ('CREDIT_NOTE_B', 8, 'Nota de Crédito B', 'B', 'CREDIT_NOTE', true, '2000-01-01'),
  ('INVOICE_C', 11, 'Factura C', 'C', 'INVOICE', true, '2000-01-01'),
  ('DEBIT_NOTE_C', 12, 'Nota de Débito C', 'C', 'DEBIT_NOTE', true, '2000-01-01'),
  ('CREDIT_NOTE_C', 13, 'Nota de Crédito C', 'C', 'CREDIT_NOTE', true, '2000-01-01'),
  -- Disabled Phase 5 (architecture: prepare but do not enable)
  ('INVOICE_M', 51, 'Factura M', 'M', 'INVOICE', false, '2000-01-01'),
  ('INVOICE_E', 19, 'Factura E', 'E', 'INVOICE', false, '2000-01-01')
on conflict (internal_code) do update set
  arca_cbte_tipo = excluded.arca_cbte_tipo,
  name = excluded.name,
  document_class = excluded.document_class,
  operation_kind = excluded.operation_kind,
  enabled_phase5 = excluded.enabled_phase5;
-- Unique for global (organization_id null) catalogs — Postgres UNIQUE treats NULLs as distinct
create unique index if not exists fiscal_parameter_catalogs_global_uidx
  on public.fiscal_parameter_catalogs (environment, catalog_kind, code)
  where organization_id is null;
-- Seed CondicionIVAReceptor catalog placeholders (codes refreshed via FEParamGetCondicionIvaReceptor)
-- These are bootstrap labels only; live homologation must refresh from ARCA.
insert into public.fiscal_parameter_catalogs (
  organization_id, environment, catalog_kind, code, label, valid_from, raw, fetched_at
)
select null, v.environment::public.fiscal_environment, v.catalog_kind, v.code, v.label, v.valid_from::date, v.raw::jsonb, timezone('utc', now())
from (values
  ('HOMOLOGATION', 'CONDICION_IVA_RECEPTOR', '1', 'IVA Responsable Inscripto', '2025-04-15',
   '{"source":"bootstrap","method":"FEParamGetCondicionIvaReceptor","refresh_required":true}'),
  ('HOMOLOGATION', 'CONDICION_IVA_RECEPTOR', '4', 'IVA Sujeto Exento', '2025-04-15',
   '{"source":"bootstrap","method":"FEParamGetCondicionIvaReceptor","refresh_required":true}'),
  ('HOMOLOGATION', 'CONDICION_IVA_RECEPTOR', '5', 'Consumidor Final', '2025-04-15',
   '{"source":"bootstrap","method":"FEParamGetCondicionIvaReceptor","refresh_required":true}'),
  ('HOMOLOGATION', 'CONDICION_IVA_RECEPTOR', '6', 'Responsable Monotributo', '2025-04-15',
   '{"source":"bootstrap","method":"FEParamGetCondicionIvaReceptor","refresh_required":true}'),
  ('HOMOLOGATION', 'CONDICION_IVA_RECEPTOR', '8', 'Proveedor del Exterior', '2025-04-15',
   '{"source":"bootstrap","method":"FEParamGetCondicionIvaReceptor","refresh_required":true}'),
  ('HOMOLOGATION', 'CONDICION_IVA_RECEPTOR', '9', 'Cliente del Exterior', '2025-04-15',
   '{"source":"bootstrap","method":"FEParamGetCondicionIvaReceptor","refresh_required":true}'),
  ('HOMOLOGATION', 'CONDICION_IVA_RECEPTOR', '10', 'IVA Liberado – Ley N° 19.640', '2025-04-15',
   '{"source":"bootstrap","method":"FEParamGetCondicionIvaReceptor","refresh_required":true}'),
  ('HOMOLOGATION', 'CONDICION_IVA_RECEPTOR', '13', 'Monotributista Social', '2025-04-15',
   '{"source":"bootstrap","method":"FEParamGetCondicionIvaReceptor","refresh_required":true}'),
  ('HOMOLOGATION', 'CONDICION_IVA_RECEPTOR', '15', 'IVA No Alcanzado', '2025-04-15',
   '{"source":"bootstrap","method":"FEParamGetCondicionIvaReceptor","refresh_required":true}'),
  ('HOMOLOGATION', 'TIPOS_IVA', '5', '21%', '2000-01-01',
   '{"source":"bootstrap","method":"FEParamGetTiposIva","Id":5,"Desc":"21%","Aliq":21}'),
  ('HOMOLOGATION', 'TIPOS_IVA', '4', '10.5%', '2000-01-01',
   '{"source":"bootstrap","method":"FEParamGetTiposIva","Id":4,"Desc":"10.5%","Aliq":10.5}'),
  ('HOMOLOGATION', 'TIPOS_IVA', '3', '0%', '2000-01-01',
   '{"source":"bootstrap","method":"FEParamGetTiposIva","Id":3,"Desc":"0%","Aliq":0}'),
  ('HOMOLOGATION', 'TIPOS_IVA', '6', '27%', '2000-01-01',
   '{"source":"bootstrap","method":"FEParamGetTiposIva","Id":6,"Desc":"27%","Aliq":27}'),
  ('HOMOLOGATION', 'MONEDAS', 'PES', 'Pesos Argentinos', '2000-01-01',
   '{"source":"bootstrap","method":"FEParamGetTiposMonedas","Id":"PES","Desc":"Pesos Argentinos","phase5_mvp":true}'),
  ('HOMOLOGATION', 'MONEDAS', 'DOL', 'Dólar Estadounidense', '2000-01-01',
   '{"source":"bootstrap","method":"FEParamGetTiposMonedas","Id":"DOL","Desc":"Dólar Estadounidense","phase5_mvp_enabled":false}')
) as v(environment, catalog_kind, code, label, valid_from, raw)
where not exists (
  select 1 from public.fiscal_parameter_catalogs c
  where c.organization_id is null
    and c.environment = v.environment::public.fiscal_environment
    and c.catalog_kind = v.catalog_kind
    and c.code = v.code
);
-- Platform fiscal rule version (ACTIVE for homologation engine; LEGAL_REVIEW_STATUS remains REVIEW_REQUIRED)
insert into public.fiscal_rule_versions (
  organization_id,
  code,
  version,
  effective_from,
  effective_to,
  source_reference,
  source_document,
  status,
  rules,
  reviewed_at,
  activated_at
) values (
  null,
  'RULES_2026_Q3',
  1,
  '2025-04-15',
  null,
  'RG 5616/2024; WSFEv1 Manual V4.8 (RG 4291); CondicionIVAReceptorId mandatory per official manual timeline',
  'https://www.arca.gob.ar/fe/ayuda/documentos/wsfev1-RG-4291.pdf',
  'ACTIVE',
  jsonb_build_object(
    'schema_version', 1,
    'manual', jsonb_build_object(
      'name', 'Manual del Desarrollador WSFEv1',
      'version', '4.8',
      'project', 'RG 4291 – Proyecto FE v4.8',
      'source_url', 'https://www.arca.gob.ar/fe/ayuda/documentos/wsfev1-RG-4291.pdf',
      'verified_at', '2026-09-04'
    ),
    'currency', jsonb_build_object(
      'mvp_enabled', jsonb_build_array('PES'),
      'foreign_disabled', true,
      'require_official_rate', true
    ),
    'receiver', jsonb_build_object(
      'condicion_iva_receptor_required', true,
      'condicion_iva_receptor_method', 'FEParamGetCondicionIvaReceptor',
      'snapshot_field', 'CondicionIVAReceptorId'
    ),
    'document_matrix', jsonb_build_object(
      'enabled_internal_codes', jsonb_build_array(
        'INVOICE_A','INVOICE_B','INVOICE_C',
        'CREDIT_NOTE_A','CREDIT_NOTE_B','CREDIT_NOTE_C',
        'DEBIT_NOTE_A','DEBIT_NOTE_B','DEBIT_NOTE_C'
      ),
      'disabled_until_separate_gate', jsonb_build_array('INVOICE_M','INVOICE_E','FCE')
    ),
    'vat', jsonb_build_object(
      'default_rate_code', '5',
      'default_rate', 21,
      'reconcile_tolerance', 0.01
    ),
    'qr', jsonb_build_object(
      'enabled_after_authorized', true,
      'schema_version', 1
    ),
    'wsaa', jsonb_build_object(
      'service_name', 'wsfe'
    ),
    'legal_review_status', 'REVIEW_REQUIRED'
  ),
  null,
  timezone('utc', now())
)
on conflict do nothing;
-- If unique conflict path differs for null org, ensure one ACTIVE platform rule exists
do $$
begin
  if not exists (
    select 1 from public.fiscal_rule_versions
    where organization_id is null and code = 'RULES_2026_Q3' and version = 1
  ) then
    insert into public.fiscal_rule_versions (
      organization_id, code, version, effective_from, source_reference, source_document, status, rules, activated_at
    ) values (
      null, 'RULES_2026_Q3', 1, '2025-04-15',
      'RG 5616/2024; WSFEv1 Manual V4.8',
      'https://www.arca.gob.ar/fe/ayuda/documentos/wsfev1-RG-4291.pdf',
      'ACTIVE',
      '{"schema_version":1,"legal_review_status":"REVIEW_REQUIRED"}'::jsonb,
      timezone('utc', now())
    );
  end if;
end $$;
