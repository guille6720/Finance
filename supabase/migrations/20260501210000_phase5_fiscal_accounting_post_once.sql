-- Phase 5 — Fiscal → GL accounting post exactly once
-- Uses existing post_journal_entry / reverse_journal_entry. No second accounting engine.
-- Staging / tests only. No live ARCA calls in this migration.

-- ---------------------------------------------------------------------------
-- accounting_posted_at on fiscal_documents
-- ---------------------------------------------------------------------------

alter table public.fiscal_documents
  add column if not exists accounting_posted_at timestamptz;

comment on column public.fiscal_documents.accounting_posted_at is
  'Set when fiscal AUTHORIZED document is posted to GL exactly once.';

-- ---------------------------------------------------------------------------
-- DB-enforced source uniqueness for SALE journals (fiscal_document_id)
-- ---------------------------------------------------------------------------

create unique index if not exists journal_entries_sale_source_uidx
  on public.journal_entries (organization_id, source_type, source_id)
  where source_type = 'SALE'::public.journal_source_type
    and source_id is not null;

-- Explicit ARCA_AUTHORIZED event key (organization_id + fiscal_document_id + event)
create table if not exists public.fiscal_accounting_post_keys (
  organization_id uuid not null references public.organizations (id) on delete cascade,
  fiscal_document_id uuid not null,
  event text not null default 'ARCA_AUTHORIZED'
    check (event = 'ARCA_AUTHORIZED'),
  journal_entry_id uuid not null references public.journal_entries (id) on delete restrict,
  created_at timestamptz not null default timezone('utc', now()),
  primary key (organization_id, fiscal_document_id, event),
  constraint fiscal_accounting_post_keys_org_fiscal_fk
    foreign key (organization_id, fiscal_document_id)
    references public.fiscal_documents (organization_id, id)
    on delete restrict,
  constraint fiscal_accounting_post_keys_journal_unique unique (journal_entry_id)
);

create index if not exists fiscal_accounting_post_keys_journal_idx
  on public.fiscal_accounting_post_keys (journal_entry_id);

comment on table public.fiscal_accounting_post_keys is
  'Exactly-once accounting source key: (org, fiscal_document, ARCA_AUTHORIZED) → journal.';

alter table public.fiscal_accounting_post_keys enable row level security;

-- No direct client writes; engine/RPC only
create policy fiscal_accounting_post_keys_select_member
  on public.fiscal_accounting_post_keys
  for select
  to authenticated
  using (public.is_org_member(organization_id));

revoke all on table public.fiscal_accounting_post_keys from public, anon;
grant select on table public.fiscal_accounting_post_keys to authenticated;
grant all on table public.fiscal_accounting_post_keys to service_role;

-- ---------------------------------------------------------------------------
-- post_fiscal_document_accounting — exactly-once GL post for AUTHORIZED docs
-- ---------------------------------------------------------------------------

create or replace function public.post_fiscal_document_accounting(p_fiscal_document_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_doc public.fiscal_documents%rowtype;
  v_map public.fiscal_accounting_mappings%rowtype;
  v_dtype public.fiscal_document_types%rowtype;
  v_existing uuid;
  v_entry_id uuid;
  v_period_id uuid;
  v_line_no int := 0;
  v_net numeric(19,4);
  v_is_credit boolean;
  v_desc text;
  v_key_journal uuid;
begin
  if v_uid is null then
    raise exception 'authentication required';
  end if;

  select * into v_doc
  from public.fiscal_documents
  where id = p_fiscal_document_id
  for update;

  if not found then
    raise exception 'fiscal document not found';
  end if;

  perform public.fiscal_assert_feature(v_doc.organization_id);
  perform public.fiscal_assert_role(
    v_doc.organization_id,
    array['owner','admin','accountant']::public.member_role[]
  );

  -- Idempotent: already linked
  if v_doc.accounting_status = 'POSTED' and v_doc.journal_entry_id is not null then
    return v_doc.journal_entry_id;
  end if;

  -- Source key already present
  select journal_entry_id into v_key_journal
  from public.fiscal_accounting_post_keys
  where organization_id = v_doc.organization_id
    and fiscal_document_id = p_fiscal_document_id
    and event = 'ARCA_AUTHORIZED';
  if v_key_journal is not null then
    update public.fiscal_documents
    set journal_entry_id = v_key_journal,
        accounting_status = 'POSTED',
        accounting_posted_at = coalesce(accounting_posted_at, timezone('utc', now())),
        updated_at = timezone('utc', now())
    where id = p_fiscal_document_id;
    return v_key_journal;
  end if;

  -- CORE RULE: only AUTHORIZED (covers APPROVED + RECONCILED_AUTHORIZED)
  if v_doc.status is distinct from 'AUTHORIZED' then
    raise exception
      using errcode = 'P0001',
            message = format(
              'fiscal accounting blocked: status %s is not AUTHORIZED',
              v_doc.status::text
            ),
            detail = 'ACCOUNTING_POST_BLOCKED';
  end if;

  if v_doc.cae is null or length(trim(v_doc.cae)) = 0 then
    raise exception 'AUTHORIZED fiscal document requires CAE before accounting post';
  end if;

  if v_doc.currency_code not in ('ARS', 'PES') then
    raise exception 'unsupported currency for fiscal accounting post: %', v_doc.currency_code;
  end if;

  if abs(
    (v_doc.net_taxed_amount + v_doc.net_exempt_amount + v_doc.net_untaxed_amount
      + v_doc.vat_amount + v_doc.other_taxes_amount) - v_doc.total_amount
  ) > 0.01 then
    raise exception 'fiscal totals do not reconcile';
  end if;

  if v_doc.other_taxes_amount > 0 then
    raise exception 'fiscal other taxes require accounting review (no mapping account)';
  end if;

  if v_doc.total_amount <= 0 then
    raise exception 'fiscal document total must be positive for accounting post';
  end if;

  select * into v_dtype
  from public.fiscal_document_types
  where id = v_doc.document_type_id;
  if not found then
    raise exception 'fiscal document type not found';
  end if;

  v_is_credit := (
    v_dtype.operation_kind = 'CREDIT_NOTE'::public.fiscal_operation_kind
    or v_doc.relationship_type = 'CREDIT_NOTE'::public.fiscal_relationship_type
  );

  select * into v_map
  from public.fiscal_accounting_mappings
  where organization_id = v_doc.organization_id;
  if not found then
    raise exception 'Falta configurar el mapeo contable fiscal (ventas / IVA / clientes)';
  end if;

  select period_id into v_period_id
  from public.resolve_open_period(v_doc.organization_id, v_doc.issue_date);
  if v_period_id is null then
    update public.fiscal_documents
    set accounting_status = 'REQUIRES_REVIEW',
        updated_at = timezone('utc', now())
    where id = p_fiscal_document_id;
    raise exception 'no OPEN period covers fiscal issue_date; accounting requires review';
  end if;

  -- Existing SALE journal for this source? (idempotent retry / race survivor)
  select id into v_existing
  from public.journal_entries
  where organization_id = v_doc.organization_id
    and source_type = 'SALE'::public.journal_source_type
    and source_id = p_fiscal_document_id
  limit 1;

  if v_existing is not null then
    -- Ensure posted via engine if still DRAFT (recovery path)
    if exists (
      select 1 from public.journal_entries
      where id = v_existing and status = 'DRAFT'::public.journal_entry_status
    ) then
      begin
        perform public.post_journal_entry(v_existing);
      exception when others then
        delete from public.journal_entries
        where id = v_existing and status = 'DRAFT'::public.journal_entry_status;
        raise;
      end;
    end if;

    insert into public.fiscal_accounting_post_keys (
      organization_id, fiscal_document_id, event, journal_entry_id
    ) values (
      v_doc.organization_id, p_fiscal_document_id, 'ARCA_AUTHORIZED', v_existing
    )
    on conflict (organization_id, fiscal_document_id, event) do nothing;

    update public.fiscal_documents
    set journal_entry_id = v_existing,
        accounting_status = 'POSTED',
        accounting_posted_at = coalesce(accounting_posted_at, timezone('utc', now())),
        updated_at = timezone('utc', now())
    where id = p_fiscal_document_id;

    return v_existing;
  end if;

  v_net := v_doc.net_taxed_amount + v_doc.net_exempt_amount + v_doc.net_untaxed_amount;
  v_desc := left(
    'ARCA ' || v_dtype.internal_code || ' PV'
      || v_doc.arca_point_of_sale::text || '-'
      || coalesce(v_doc.document_number::text, '?')
      || ' ARCA_AUTHORIZED',
    500
  );

  begin
    insert into public.journal_entries (
      organization_id,
      entry_date,
      description,
      status,
      source_type,
      source_id,
      external_reference,
      created_by
    ) values (
      v_doc.organization_id,
      v_doc.issue_date,
      v_desc,
      'DRAFT',
      'SALE'::public.journal_source_type,
      p_fiscal_document_id,
      'ARCA_AUTHORIZED:' || p_fiscal_document_id::text,
      v_uid
    )
    returning id into v_entry_id;
  exception
    when unique_violation then
      select id into v_existing
      from public.journal_entries
      where organization_id = v_doc.organization_id
        and source_type = 'SALE'::public.journal_source_type
        and source_id = p_fiscal_document_id
      limit 1;
      if v_existing is null then
        raise;
      end if;
      if exists (
        select 1 from public.journal_entries
        where id = v_existing and status = 'DRAFT'::public.journal_entry_status
      ) then
        begin
          perform public.post_journal_entry(v_existing);
        exception when others then
          delete from public.journal_entries
          where id = v_existing and status = 'DRAFT'::public.journal_entry_status;
          raise;
        end;
      end if;
      insert into public.fiscal_accounting_post_keys (
        organization_id, fiscal_document_id, event, journal_entry_id
      ) values (
        v_doc.organization_id, p_fiscal_document_id, 'ARCA_AUTHORIZED', v_existing
      )
      on conflict (organization_id, fiscal_document_id, event) do nothing;
      update public.fiscal_documents
      set journal_entry_id = v_existing,
          accounting_status = 'POSTED',
          accounting_posted_at = coalesce(accounting_posted_at, timezone('utc', now())),
          updated_at = timezone('utc', now())
      where id = p_fiscal_document_id;
      return v_existing;
  end;

  if not v_is_credit then
    -- Invoice / DN: Dr receivables, Cr sales, Cr VAT
    v_line_no := 1;
    insert into public.journal_entry_lines (
      organization_id, journal_entry_id, line_number, account_id, description,
      debit, credit, counterparty_id
    ) values (
      v_doc.organization_id, v_entry_id, v_line_no, v_map.receivables_account_id,
      'Clientes',
      v_doc.total_amount, 0, v_doc.counterparty_id
    );

    if v_net > 0 then
      v_line_no := v_line_no + 1;
      insert into public.journal_entry_lines (
        organization_id, journal_entry_id, line_number, account_id, description,
        debit, credit, counterparty_id
      ) values (
        v_doc.organization_id, v_entry_id, v_line_no, v_map.sales_account_id,
        'Ventas',
        0, v_net, v_doc.counterparty_id
      );
    end if;

    if v_doc.vat_amount > 0 then
      v_line_no := v_line_no + 1;
      insert into public.journal_entry_lines (
        organization_id, journal_entry_id, line_number, account_id, description,
        debit, credit, counterparty_id
      ) values (
        v_doc.organization_id, v_entry_id, v_line_no, v_map.vat_output_account_id,
        'IVA débito fiscal',
        0, v_doc.vat_amount, v_doc.counterparty_id
      );
    end if;
  else
    -- Credit note: Dr sales/VAT, Cr receivables
    if v_net > 0 then
      v_line_no := v_line_no + 1;
      insert into public.journal_entry_lines (
        organization_id, journal_entry_id, line_number, account_id, description,
        debit, credit, counterparty_id
      ) values (
        v_doc.organization_id, v_entry_id, v_line_no, v_map.sales_account_id,
        'Ventas (NC)',
        v_net, 0, v_doc.counterparty_id
      );
    end if;

    if v_doc.vat_amount > 0 then
      v_line_no := v_line_no + 1;
      insert into public.journal_entry_lines (
        organization_id, journal_entry_id, line_number, account_id, description,
        debit, credit, counterparty_id
      ) values (
        v_doc.organization_id, v_entry_id, v_line_no, v_map.vat_output_account_id,
        'IVA débito fiscal (NC)',
        v_doc.vat_amount, 0, v_doc.counterparty_id
      );
    end if;

    v_line_no := v_line_no + 1;
    insert into public.journal_entry_lines (
      organization_id, journal_entry_id, line_number, account_id, description,
      debit, credit, counterparty_id
    ) values (
      v_doc.organization_id, v_entry_id, v_line_no, v_map.receivables_account_id,
      'Clientes (NC)',
      0, v_doc.total_amount, v_doc.counterparty_id
    );
  end if;

  -- Atomic post via Phase 2 engine; delete DRAFT on failure (no partial accounting)
  begin
    perform public.post_journal_entry(v_entry_id);
  exception when others then
    delete from public.journal_entries
    where id = v_entry_id and status = 'DRAFT'::public.journal_entry_status;
    raise;
  end;

  begin
    insert into public.fiscal_accounting_post_keys (
      organization_id, fiscal_document_id, event, journal_entry_id
    ) values (
      v_doc.organization_id, p_fiscal_document_id, 'ARCA_AUTHORIZED', v_entry_id
    );
  exception
    when unique_violation then
      select journal_entry_id into v_key_journal
      from public.fiscal_accounting_post_keys
      where organization_id = v_doc.organization_id
        and fiscal_document_id = p_fiscal_document_id
        and event = 'ARCA_AUTHORIZED';
      -- Prefer the key-holder; orphan draft/posted race should not happen after SALE unique
      if v_key_journal is not null and v_key_journal is distinct from v_entry_id then
        -- Keep key winner; fiscal doc links to winner
        v_entry_id := v_key_journal;
      end if;
  end;

  update public.fiscal_documents
  set journal_entry_id = v_entry_id,
      accounting_status = 'POSTED',
      accounting_posted_at = timezone('utc', now()),
      updated_at = timezone('utc', now())
  where id = p_fiscal_document_id;

  return v_entry_id;
end;
$$;

comment on function public.post_fiscal_document_accounting(uuid) is
  'Exactly-once GL post for AUTHORIZED fiscal documents via post_journal_entry. Idempotent on ARCA_AUTHORIZED source key.';

revoke all on function public.post_fiscal_document_accounting(uuid) from public, anon;
grant execute on function public.post_fiscal_document_accounting(uuid) to authenticated;
grant execute on function public.post_fiscal_document_accounting(uuid) to service_role;
