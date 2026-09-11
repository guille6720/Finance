-- Phase 9: CLEARING treasury account type + CoA system_role helper
-- STAGING ONLY — NEW migration; do not edit Phase 1–8 files.

do $$ begin
  alter type public.treasury_account_type add value if not exists 'CLEARING';
exception when duplicate_object then null;
end $$;
-- Allow CLEARING accounts without bank metadata (reuse bank_meta_check via replace)
alter table public.treasury_accounts
  drop constraint if exists treasury_accounts_bank_meta_check;
alter table public.treasury_accounts
  add constraint treasury_accounts_bank_meta_check check (
    account_type = 'BANK'
    or (bank_name is null and account_mask is null and cbu_cvu_alias is null)
  );
comment on type public.treasury_account_type is
  'CASH | BANK | CLEARING (Phase 9 POS card/QR processor receivables).';
-- Additive CoA: payment processor clearing asset
create or replace function public.ensure_treasury_clearing_coa(p_org_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_parent uuid;
  v_id uuid;
begin
  if v_uid is null then raise exception 'authentication required'; end if;
  if not public.has_org_role(p_org_id, array['owner','admin','accountant']::public.member_role[]) then
    raise exception 'insufficient role';
  end if;

  select id into v_id
  from public.accounts
  where organization_id = p_org_id
    and system_role = 'clearing'
    and is_postable
  limit 1;

  if v_id is not null then
    return v_id;
  end if;

  select id into v_parent
  from public.accounts
  where organization_id = p_org_id and code = '1.1'
  limit 1;

  if v_parent is null then
    raise exception 'missing CoA parent 1.1 for clearing account';
  end if;

  if not exists (
    select 1 from public.accounts where organization_id = p_org_id and code = '1.1.06'
  ) then
    insert into public.accounts (
      organization_id, parent_id, code, name, account_type, normal_balance, is_postable, system_role
    ) values (
      p_org_id, v_parent, '1.1.06', 'Medios electrónicos a cobrar / clearing',
      'ASSET', 'DEBIT', true, 'clearing'
    )
    returning id into v_id;
  else
    update public.accounts
    set system_role = 'clearing', is_postable = true, updated_at = timezone('utc', now())
    where organization_id = p_org_id and code = '1.1.06'
    returning id into v_id;
  end if;

  return v_id;
end;
$$;
revoke all on function public.ensure_treasury_clearing_coa(uuid) from public, anon;
grant execute on function public.ensure_treasury_clearing_coa(uuid) to authenticated;
comment on function public.ensure_treasury_clearing_coa(uuid) is
  'Phase 9: ensure postable accounts.system_role=clearing (1.1.06).';
