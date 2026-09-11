-- Phase 4 fix — sequence allocation must bypass sequences RLS (read-only policy)

create or replace function public.next_sales_internal_number(
  p_organization_id uuid,
  p_document_type public.sales_document_type,
  p_document_date date
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_year int := extract(year from p_document_date)::int;
  v_seq bigint;
  v_prefix text;
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  if not public.is_org_member(p_organization_id) then
    raise exception 'not a member of organization';
  end if;

  if p_document_type = 'QUOTE' then
    v_prefix := 'PRES';
  else
    v_prefix := 'PED';
  end if;

  insert into public.sales_document_sequences (organization_id, document_type, sequence_year, last_value)
  values (p_organization_id, p_document_type, v_year, 0)
  on conflict (organization_id, document_type, sequence_year) do nothing;

  select last_value into v_seq
  from public.sales_document_sequences
  where organization_id = p_organization_id
    and document_type = p_document_type
    and sequence_year = v_year
  for update;

  v_seq := v_seq + 1;

  update public.sales_document_sequences
  set last_value = v_seq, updated_at = timezone('utc', now())
  where organization_id = p_organization_id
    and document_type = p_document_type
    and sequence_year = v_year;

  return v_prefix || '-' || v_year::text || '-' || lpad(v_seq::text, 6, '0');
end;
$$;
revoke all on function public.next_sales_internal_number(uuid, public.sales_document_type, date) from public;
grant execute on function public.next_sales_internal_number(uuid, public.sales_document_type, date) to authenticated;
