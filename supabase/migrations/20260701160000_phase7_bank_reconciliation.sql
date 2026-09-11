-- Phase 7 — Bank statements + 1:1 reconciliation (evidence only, no auto-post)

do $$ begin
  create type public.bank_statement_match_status as enum (
    'UNMATCHED', 'MATCHED', 'IGNORED'
  );
exception when duplicate_object then null;
end $$;
do $$ begin
  create type public.bank_import_status as enum ('IMPORTED', 'VOID');
exception when duplicate_object then null;
end $$;
create table public.bank_statement_imports (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  treasury_account_id uuid not null,
  source_filename text,
  source_hash text not null,
  row_count int not null default 0 check (row_count >= 0),
  status public.bank_import_status not null default 'IMPORTED',
  imported_by uuid references auth.users (id),
  created_at timestamptz not null default timezone('utc', now()),
  unique (organization_id, treasury_account_id, source_hash),
  constraint bank_statement_imports_org_id_unique unique (organization_id, id),
  constraint bank_statement_imports_org_account_fk
    foreign key (organization_id, treasury_account_id)
    references public.treasury_accounts (organization_id, id)
    on delete restrict
);
create index bank_statement_imports_org_account_date_idx
  on public.bank_statement_imports (organization_id, treasury_account_id, created_at desc);
create index bank_statement_imports_imported_by_idx
  on public.bank_statement_imports (imported_by)
  where imported_by is not null;
create table public.bank_statement_lines (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  import_id uuid not null,
  treasury_account_id uuid not null,
  value_date date not null,
  description text,
  reference text,
  debit numeric(19, 4) not null default 0 check (debit >= 0),
  credit numeric(19, 4) not null default 0 check (credit >= 0),
  line_hash text not null,
  match_status public.bank_statement_match_status not null default 'UNMATCHED',
  ignore_reason text,
  created_at timestamptz not null default timezone('utc', now()),
  constraint bank_statement_lines_one_side check (
    (debit > 0 and credit = 0) or (credit > 0 and debit = 0)
  ),
  unique (organization_id, treasury_account_id, line_hash),
  constraint bank_statement_lines_org_id_unique unique (organization_id, id),
  constraint bank_statement_lines_org_import_fk
    foreign key (organization_id, import_id)
    references public.bank_statement_imports (organization_id, id)
    on delete cascade,
  constraint bank_statement_lines_org_account_fk
    foreign key (organization_id, treasury_account_id)
    references public.treasury_accounts (organization_id, id)
    on delete restrict,
  constraint bank_statement_lines_ignore_reason check (
    match_status <> 'IGNORED' or (ignore_reason is not null and char_length(trim(ignore_reason)) >= 3)
  )
);
create index bank_statement_lines_import_idx
  on public.bank_statement_lines (import_id);
create index bank_statement_lines_org_account_date_idx
  on public.bank_statement_lines (organization_id, treasury_account_id, value_date);
create index bank_statement_lines_match_status_idx
  on public.bank_statement_lines (organization_id, treasury_account_id, match_status);
create table public.bank_reconciliation_matches (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  statement_line_id uuid not null,
  treasury_operation_id uuid not null,
  treasury_operation_leg_id uuid,
  amount numeric(19, 4) not null check (amount > 0),
  created_by uuid references auth.users (id),
  created_at timestamptz not null default timezone('utc', now()),
  -- MVP 1:1
  unique (statement_line_id),
  unique (treasury_operation_id),
  constraint bank_recon_matches_org_line_fk
    foreign key (organization_id, statement_line_id)
    references public.bank_statement_lines (organization_id, id)
    on delete cascade,
  constraint bank_recon_matches_org_op_fk
    foreign key (organization_id, treasury_operation_id)
    references public.treasury_operations (organization_id, id)
    on delete restrict,
  constraint bank_recon_matches_org_leg_fk
    foreign key (organization_id, treasury_operation_leg_id)
    references public.treasury_operation_legs (organization_id, id)
    on delete restrict
);
create index bank_recon_matches_op_idx
  on public.bank_reconciliation_matches (treasury_operation_id);
create index bank_recon_matches_leg_idx
  on public.bank_reconciliation_matches (treasury_operation_leg_id)
  where treasury_operation_leg_id is not null;
create index bank_recon_matches_created_by_idx
  on public.bank_reconciliation_matches (created_by)
  where created_by is not null;
comment on table public.bank_statement_lines is
  'External bank evidence only — never auto-posts accounting.';
comment on table public.bank_reconciliation_matches is
  '1:1 match metadata; does not create/alter journals or amounts.';
-- Match / unmatch / ignore RPCs (no journal side effects)
create or replace function public.match_bank_statement_line(
  p_statement_line_id uuid,
  p_treasury_operation_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_line public.bank_statement_lines%rowtype;
  v_op public.treasury_operations%rowtype;
  v_amount numeric(19,4);
  v_id uuid;
begin
  if v_uid is null then raise exception 'authentication required'; end if;
  select * into v_line from public.bank_statement_lines where id = p_statement_line_id for update;
  if not found then raise exception 'statement line not found'; end if;
  if not public.has_org_role(
    v_line.organization_id, array['owner','admin','accountant']::public.member_role[]
  ) then
    raise exception 'insufficient role to reconcile';
  end if;
  perform public.treasury_assert_feature(v_line.organization_id, array['banks']);

  if v_line.match_status is distinct from 'UNMATCHED' then
    raise exception 'statement line is not unmatched';
  end if;

  select * into v_op from public.treasury_operations where id = p_treasury_operation_id for update;
  if not found then raise exception 'treasury operation not found'; end if;
  if v_op.organization_id is distinct from v_line.organization_id then
    raise exception 'cross-tenant match denied';
  end if;
  if v_op.status is distinct from 'POSTED' then
    raise exception 'only POSTED operations can be matched';
  end if;

  v_amount := case when v_line.debit > 0 then v_line.debit else v_line.credit end;
  if v_amount <> v_op.amount then
    raise exception 'MVP 1:1 match requires equal amounts';
  end if;

  if exists (
    select 1 from public.bank_reconciliation_matches where treasury_operation_id = p_treasury_operation_id
  ) then
    raise exception 'operation already matched';
  end if;

  insert into public.bank_reconciliation_matches (
    organization_id, statement_line_id, treasury_operation_id, amount, created_by
  ) values (
    v_line.organization_id, p_statement_line_id, p_treasury_operation_id, v_amount, v_uid
  ) returning id into v_id;

  update public.bank_statement_lines
  set match_status = 'MATCHED'
  where id = p_statement_line_id;

  return v_id;
end;
$$;
create or replace function public.unmatch_bank_statement_line(p_statement_line_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_line public.bank_statement_lines%rowtype;
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  select * into v_line from public.bank_statement_lines where id = p_statement_line_id for update;
  if not found then raise exception 'statement line not found'; end if;
  if not public.has_org_role(
    v_line.organization_id, array['owner','admin','accountant']::public.member_role[]
  ) then
    raise exception 'insufficient role';
  end if;
  delete from public.bank_reconciliation_matches where statement_line_id = p_statement_line_id;
  update public.bank_statement_lines
  set match_status = 'UNMATCHED', ignore_reason = null
  where id = p_statement_line_id;
  return p_statement_line_id;
end;
$$;
create or replace function public.ignore_bank_statement_line(
  p_statement_line_id uuid,
  p_reason text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_line public.bank_statement_lines%rowtype;
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  if p_reason is null or char_length(trim(p_reason)) < 3 then
    raise exception 'ignore reason required';
  end if;
  select * into v_line from public.bank_statement_lines where id = p_statement_line_id for update;
  if not found then raise exception 'statement line not found'; end if;
  if not public.has_org_role(
    v_line.organization_id, array['owner','admin','accountant']::public.member_role[]
  ) then
    raise exception 'insufficient role';
  end if;
  if v_line.match_status = 'MATCHED' then
    raise exception 'unmatch before ignore';
  end if;
  update public.bank_statement_lines
  set match_status = 'IGNORED', ignore_reason = trim(p_reason)
  where id = p_statement_line_id;
  return p_statement_line_id;
end;
$$;
revoke all on function public.match_bank_statement_line(uuid, uuid) from public, anon;
revoke all on function public.unmatch_bank_statement_line(uuid) from public, anon;
revoke all on function public.ignore_bank_statement_line(uuid, text) from public, anon;
grant execute on function public.match_bank_statement_line(uuid, uuid) to authenticated;
grant execute on function public.unmatch_bank_statement_line(uuid) to authenticated;
grant execute on function public.ignore_bank_statement_line(uuid, text) to authenticated;
