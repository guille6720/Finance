-- Phase 10 hardening: reuse fixture counterparty (idempotent CN/DN fixtures)

create or replace function public.tax_test_fixture_authorized_fiscal(
  p_organization_id uuid,
  p_issue_date date,
  p_fiscal_environment public.fiscal_environment,
  p_vat_amount numeric,
  p_net_taxed numeric default null,
  p_counterparty_id uuid default null,
  p_point_of_sale_id uuid default null,
  p_document_type_internal_code text default 'INVOICE_A'
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_dtype public.fiscal_document_types%rowtype;
  v_doc_id uuid;
  v_net numeric(19,4) := coalesce(p_net_taxed, round(p_vat_amount / 0.21, 4));
  v_cp uuid := p_counterparty_id;
  v_pos uuid := p_point_of_sale_id;
  v_pos_n int;
  v_rule uuid;
  v_fixture_tax_id text := '20111111112';
begin
  if auth.role() is distinct from 'service_role' then
    raise exception 'tax_test_fixture_authorized_fiscal is service_role only';
  end if;

  select * into v_dtype
  from public.fiscal_document_types
  where internal_code = coalesce(p_document_type_internal_code, 'INVOICE_A')
  limit 1;
  if not found then
    select * into v_dtype from public.fiscal_document_types
    where operation_kind = 'INVOICE' limit 1;
  end if;
  if v_dtype.id is null then
    raise exception 'TAX_FIXTURE_NO_DOCUMENT_TYPE';
  end if;

  if v_cp is null then
    select c.id into v_cp
    from public.counterparties c
    where c.organization_id = p_organization_id
      and c.tax_id_normalized = public.normalize_counterparty_tax_id('CUIT', v_fixture_tax_id)
    limit 1;

    if v_cp is null then
      insert into public.counterparties (
        organization_id, legal_name, tax_id_type, tax_id, is_active
      ) values (
        p_organization_id, 'Tax Fixture Customer', 'CUIT', v_fixture_tax_id, true
      )
      returning id into v_cp;
    end if;

    insert into public.counterparty_roles (organization_id, counterparty_id, role)
    values (p_organization_id, v_cp, 'CUSTOMER')
    on conflict do nothing;
  end if;

  if v_pos is null then
    insert into public.fiscal_points_of_sale (
      organization_id, environment, arca_point_of_sale, description, is_active
    ) values (
      p_organization_id, p_fiscal_environment, 99, 'Tax fixture POS', true
    )
    on conflict (organization_id, environment, arca_point_of_sale) do update
      set description = excluded.description
    returning id into v_pos;
    if v_pos is null then
      select id into v_pos from public.fiscal_points_of_sale
      where organization_id = p_organization_id
        and environment = p_fiscal_environment
        and arca_point_of_sale = 99;
    end if;
  end if;

  select arca_point_of_sale into v_pos_n
  from public.fiscal_points_of_sale where id = v_pos;

  select id into v_rule
  from public.fiscal_rule_versions
  where organization_id = p_organization_id
    and status = 'ACTIVE'
  order by effective_from desc
  limit 1;
  if v_rule is null then
    insert into public.fiscal_rule_versions (
      organization_id, code, version, effective_from, source_reference, status, rules
    ) values (
      p_organization_id, 'TAX_FIXTURE', 1, '2020-01-01',
      'Phase10 staging fixture', 'ACTIVE', '{}'::jsonb
    )
    returning id into v_rule;
  end if;

  perform set_config('fiscal.engine_write', '1', true);

  insert into public.fiscal_documents (
    organization_id, document_type_id, document_class, arca_cbte_tipo,
    point_of_sale_id, arca_point_of_sale, document_number,
    status, fiscal_environment, issue_date, counterparty_id,
    currency_code, currency_rate,
    net_taxed_amount, net_exempt_amount, net_untaxed_amount,
    vat_amount, other_taxes_amount, total_amount,
    cae, authorized_at, fiscal_rule_version_id, idempotency_key
  ) values (
    p_organization_id, v_dtype.id, v_dtype.document_class, v_dtype.arca_cbte_tipo,
    v_pos, v_pos_n, (extract(epoch from clock_timestamp()) * 1000)::bigint,
    'AUTHORIZED', p_fiscal_environment, p_issue_date, v_cp,
    'PES', 1,
    v_net, 0, 0,
    p_vat_amount, 0, v_net + p_vat_amount,
    'TESTCAE' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 10),
    timezone('utc', now()), v_rule, 'tax-fix-fd-' || gen_random_uuid()::text
  )
  returning id into v_doc_id;

  insert into public.fiscal_tax_summaries (
    organization_id, fiscal_document_id, summary_kind, code, base_amount, rate, amount
  ) values (
    p_organization_id, v_doc_id, 'IVA', '5', v_net, 21.0000, p_vat_amount
  );

  return v_doc_id;
end;
$$;
revoke all on function public.tax_test_fixture_authorized_fiscal(uuid, date, public.fiscal_environment, numeric, numeric, uuid, uuid, text)
  from public, anon, authenticated;
grant execute on function public.tax_test_fixture_authorized_fiscal(uuid, date, public.fiscal_environment, numeric, numeric, uuid, uuid, text)
  to service_role;
