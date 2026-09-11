-- Phase 9: allow SALES_ORDER status INVOICED (Phase 5 added enum; trigger never updated)

create or replace function public.validate_sales_document_status_for_type()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if new.document_type = 'QUOTE' then
    if new.status not in ('DRAFT', 'SENT', 'ACCEPTED', 'REJECTED', 'CANCELLED', 'CONVERTED') then
      raise exception 'invalid quote status: %', new.status;
    end if;
  elsif new.document_type = 'SALES_ORDER' then
    if new.status not in (
      'DRAFT', 'CONFIRMED', 'READY_TO_INVOICE', 'INVOICED', 'CANCELLED'
    ) then
      raise exception 'invalid sales order status: %', new.status;
    end if;
  end if;
  return new;
end;
$$;
comment on function public.validate_sales_document_status_for_type() is
  'Phase 9: includes INVOICED for SALES_ORDER (Phase 5 fiscal handoff).';
