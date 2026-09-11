-- Phase 3 — Counterparty RLS + grants (STAGING)

alter table public.counterparties enable row level security;
alter table public.counterparty_roles enable row level security;
alter table public.counterparty_fiscal_profiles enable row level security;
alter table public.counterparty_addresses enable row level security;
alter table public.counterparty_contacts enable row level security;
-- ---------------------------------------------------------------------------
-- counterparties
-- ---------------------------------------------------------------------------

drop policy if exists counterparties_select on public.counterparties;
create policy counterparties_select
  on public.counterparties for select to authenticated
  using ((select public.is_org_member(organization_id)));
drop policy if exists counterparties_insert on public.counterparties;
create policy counterparties_insert
  on public.counterparties for insert to authenticated
  with check ((select public.has_org_role(
    organization_id,
    array['owner','admin','manager','operator','accountant']::public.member_role[]
  )));
drop policy if exists counterparties_update on public.counterparties;
create policy counterparties_update
  on public.counterparties for update to authenticated
  using ((select public.has_org_role(
    organization_id,
    array['owner','admin','manager','operator','accountant']::public.member_role[]
  )))
  with check ((select public.has_org_role(
    organization_id,
    array['owner','admin','manager','operator','accountant']::public.member_role[]
  )));
drop policy if exists counterparties_delete on public.counterparties;
create policy counterparties_delete
  on public.counterparties for delete to authenticated
  using ((select public.has_org_role(
    organization_id,
    array['owner','admin']::public.member_role[]
  )));
-- ---------------------------------------------------------------------------
-- counterparty_roles
-- ---------------------------------------------------------------------------

drop policy if exists counterparty_roles_select on public.counterparty_roles;
create policy counterparty_roles_select
  on public.counterparty_roles for select to authenticated
  using ((select public.is_org_member(organization_id)));
drop policy if exists counterparty_roles_insert on public.counterparty_roles;
create policy counterparty_roles_insert
  on public.counterparty_roles for insert to authenticated
  with check ((select public.has_org_role(
    organization_id,
    array['owner','admin','manager','operator']::public.member_role[]
  )));
drop policy if exists counterparty_roles_delete on public.counterparty_roles;
create policy counterparty_roles_delete
  on public.counterparty_roles for delete to authenticated
  using ((select public.has_org_role(
    organization_id,
    array['owner','admin','manager']::public.member_role[]
  )));
-- ---------------------------------------------------------------------------
-- counterparty_fiscal_profiles
-- ---------------------------------------------------------------------------

drop policy if exists counterparty_fiscal_profiles_select on public.counterparty_fiscal_profiles;
create policy counterparty_fiscal_profiles_select
  on public.counterparty_fiscal_profiles for select to authenticated
  using ((select public.is_org_member(organization_id)));
drop policy if exists counterparty_fiscal_profiles_insert on public.counterparty_fiscal_profiles;
create policy counterparty_fiscal_profiles_insert
  on public.counterparty_fiscal_profiles for insert to authenticated
  with check ((select public.has_org_role(
    organization_id,
    array['owner','admin','manager','accountant']::public.member_role[]
  )));
drop policy if exists counterparty_fiscal_profiles_update on public.counterparty_fiscal_profiles;
create policy counterparty_fiscal_profiles_update
  on public.counterparty_fiscal_profiles for update to authenticated
  using ((select public.has_org_role(
    organization_id,
    array['owner','admin','manager','accountant']::public.member_role[]
  )))
  with check ((select public.has_org_role(
    organization_id,
    array['owner','admin','manager','accountant']::public.member_role[]
  )));
-- ---------------------------------------------------------------------------
-- counterparty_addresses
-- ---------------------------------------------------------------------------

drop policy if exists counterparty_addresses_select on public.counterparty_addresses;
create policy counterparty_addresses_select
  on public.counterparty_addresses for select to authenticated
  using ((select public.is_org_member(organization_id)));
drop policy if exists counterparty_addresses_insert on public.counterparty_addresses;
create policy counterparty_addresses_insert
  on public.counterparty_addresses for insert to authenticated
  with check ((select public.has_org_role(
    organization_id,
    array['owner','admin','manager','operator']::public.member_role[]
  )));
drop policy if exists counterparty_addresses_update on public.counterparty_addresses;
create policy counterparty_addresses_update
  on public.counterparty_addresses for update to authenticated
  using ((select public.has_org_role(
    organization_id,
    array['owner','admin','manager','operator']::public.member_role[]
  )))
  with check ((select public.has_org_role(
    organization_id,
    array['owner','admin','manager','operator']::public.member_role[]
  )));
drop policy if exists counterparty_addresses_delete on public.counterparty_addresses;
create policy counterparty_addresses_delete
  on public.counterparty_addresses for delete to authenticated
  using ((select public.has_org_role(
    organization_id,
    array['owner','admin','manager']::public.member_role[]
  )));
-- ---------------------------------------------------------------------------
-- counterparty_contacts
-- ---------------------------------------------------------------------------

drop policy if exists counterparty_contacts_select on public.counterparty_contacts;
create policy counterparty_contacts_select
  on public.counterparty_contacts for select to authenticated
  using ((select public.is_org_member(organization_id)));
drop policy if exists counterparty_contacts_insert on public.counterparty_contacts;
create policy counterparty_contacts_insert
  on public.counterparty_contacts for insert to authenticated
  with check ((select public.has_org_role(
    organization_id,
    array['owner','admin','manager','operator']::public.member_role[]
  )));
drop policy if exists counterparty_contacts_update on public.counterparty_contacts;
create policy counterparty_contacts_update
  on public.counterparty_contacts for update to authenticated
  using ((select public.has_org_role(
    organization_id,
    array['owner','admin','manager','operator']::public.member_role[]
  )))
  with check ((select public.has_org_role(
    organization_id,
    array['owner','admin','manager','operator']::public.member_role[]
  )));
-- ---------------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------------

grant select, insert, update, delete on public.counterparties to authenticated;
grant select, insert, delete on public.counterparty_roles to authenticated;
grant select, insert, update on public.counterparty_fiscal_profiles to authenticated;
grant select, insert, update, delete on public.counterparty_addresses to authenticated;
grant select, insert, update on public.counterparty_contacts to authenticated;
revoke all on public.counterparties from anon;
revoke all on public.counterparty_roles from anon;
revoke all on public.counterparty_fiscal_profiles from anon;
revoke all on public.counterparty_addresses from anon;
revoke all on public.counterparty_contacts from anon;
-- ---------------------------------------------------------------------------
-- STAGING synthetic fixtures (clearly fake tax IDs)
-- ---------------------------------------------------------------------------

do $$
declare
  v_org_id uuid;
  v_fc_id uuid;
  v_c1 uuid;
  v_c2 uuid;
  v_c3 uuid;
begin
  select id into v_org_id
  from public.organizations
  where legal_name ilike '%demo%' or commercial_name ilike '%demo%'
  order by created_at
  limit 1;

  if v_org_id is null then
    select id into v_org_id from public.organizations order by created_at limit 1;
  end if;

  if v_org_id is null then
    raise notice 'phase3 fixtures skipped: no organization';
    return;
  end if;

  select id into v_fc_id
  from public.fiscal_conditions
  where code = 'responsable_inscripto'
  limit 1;

  -- Synthetic CUITs (valid check digit, non-real entities)
  insert into public.counterparties (
    organization_id, entity_type, legal_name, trade_name,
    tax_id_type, tax_id, email, phone, is_active
  ) values (
    v_org_id, 'LEGAL_ENTITY', 'Cliente Demo Uno SA', 'Demo Uno',
    'CUIT', '30-99999900-6', 'cliente.demo@example.invalid', '+54 11 4000-0001', true
  )
  on conflict do nothing
  returning id into v_c1;

  if v_c1 is null then
    select id into v_c1 from public.counterparties
    where organization_id = v_org_id and legal_name = 'Cliente Demo Uno SA';
  end if;

  insert into public.counterparty_roles (counterparty_id, organization_id, role)
  values (v_c1, v_org_id, 'CUSTOMER')
  on conflict do nothing;

  insert into public.counterparty_fiscal_profiles (
    counterparty_id, organization_id, fiscal_condition_id,
    fiscal_address, province, city, postal_code
  ) values (
    v_c1, v_org_id, v_fc_id,
    'Av. Demo 100', 'CABA', 'CABA', 'C1000'
  )
  on conflict (counterparty_id) do nothing;

  insert into public.counterparties (
    organization_id, entity_type, legal_name, trade_name,
    tax_id_type, tax_id, email, phone, is_active
  ) values (
    v_org_id, 'LEGAL_ENTITY', 'Proveedor Demo Dos SRL', 'Demo Dos',
    'CUIT', '30-99999901-4', 'proveedor.demo@example.invalid', '+54 11 4000-0002', true
  )
  on conflict do nothing
  returning id into v_c2;

  if v_c2 is null then
    select id into v_c2 from public.counterparties
    where organization_id = v_org_id and legal_name = 'Proveedor Demo Dos SRL';
  end if;

  insert into public.counterparty_roles (counterparty_id, organization_id, role)
  values (v_c2, v_org_id, 'SUPPLIER')
  on conflict do nothing;

  insert into public.counterparties (
    organization_id, entity_type, legal_name, trade_name,
    tax_id_type, tax_id, email, phone, is_active
  ) values (
    v_org_id, 'LEGAL_ENTITY', 'Contraparte Demo Mixta SA', 'Mixta Demo',
    'CUIT', '30-99999902-2', 'mixta.demo@example.invalid', '+54 11 4000-0003', true
  )
  on conflict do nothing
  returning id into v_c3;

  if v_c3 is null then
    select id into v_c3 from public.counterparties
    where organization_id = v_org_id and legal_name = 'Contraparte Demo Mixta SA';
  end if;

  insert into public.counterparty_roles (counterparty_id, organization_id, role)
  values
    (v_c3, v_org_id, 'CUSTOMER'),
    (v_c3, v_org_id, 'SUPPLIER')
  on conflict do nothing;

  raise notice 'phase3 fixtures applied for org %', v_org_id;
end $$;
