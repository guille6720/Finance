-- ORIGINAL_MIGRATION_SQL_UNAVAILABLE
-- RECOVERED_FROM_STAGING_CATALOG
-- SOURCE_OBJECTS: product_categories, products, warehouses, inventory_operations,
--   inventory_operation_lines, inventory_operation_sequences, inventory_reservations,
--   inventory_stock_state, inventory_cost_state, inventory_ledger_entries,
--   inventory_accounting_mappings + enums (product_type, inventory_unit_code,
--   inventory_operation_type, inventory_operation_status, inventory_line_direction,
--   inventory_reservation_status, inventory_accounting_status) + inventory functions
-- SOURCE = docs/qa/phase13/forensics/staging-public-schema.sql
-- STAGING_PROJECT = rpcpdrzbcclofvjpgldb
-- RATIONALE: Phase 8 migration files 20260801100000-20260801200000 contained corrupt
--   '{q}' payloads (non-executable). This forward migration recovers all Phase 8
--   inventory/product DDL from the authoritative staging catalog dump.
--   Sorting: AFTER 20260801200000 (last Phase 8 slot), BEFORE 20260901100000 (Phase 9).
--   Do not edit semantic behavior; DDL is verbatim from staging catalog.

CREATE TYPE "public"."inventory_accounting_status" AS ENUM (
    'PENDING',
    'POSTED',
    'ACCOUNTING_REQUIRES_REVIEW',
    'ERROR',
    'NOT_APPLICABLE'
);

CREATE TYPE "public"."inventory_line_direction" AS ENUM (
    'IN',
    'OUT'
);

CREATE TYPE "public"."inventory_operation_status" AS ENUM (
    'DRAFT',
    'POSTED',
    'REVERSED'
);

CREATE TYPE "public"."inventory_operation_type" AS ENUM (
    'RECEIPT',
    'ISSUE',
    'TRANSFER',
    'ADJUSTMENT_IN',
    'ADJUSTMENT_OUT',
    'RETURN_TO_SUPPLIER',
    'REVERSAL'
);

CREATE TYPE "public"."inventory_reservation_status" AS ENUM (
    'ACTIVE',
    'RELEASED',
    'CONSUMED',
    'CANCELLED'
);

CREATE TYPE "public"."inventory_unit_code" AS ENUM (
    'UNIT',
    'HOUR',
    'KG',
    'M',
    'OTHER'
);

CREATE TYPE "public"."product_type" AS ENUM (
    'STOCK_ITEM',
    'SERVICE',
    'NON_STOCK'
);

ALTER TYPE "public"."inventory_accounting_status" OWNER TO "postgres";

ALTER TYPE "public"."inventory_line_direction" OWNER TO "postgres";

ALTER TYPE "public"."inventory_operation_status" OWNER TO "postgres";

ALTER TYPE "public"."inventory_operation_type" OWNER TO "postgres";

ALTER TYPE "public"."inventory_reservation_status" OWNER TO "postgres";

ALTER TYPE "public"."inventory_unit_code" OWNER TO "postgres";

ALTER TYPE "public"."product_type" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "public"."inventory_accounting_mappings" (
    "organization_id" "uuid" NOT NULL,
    "inventory_asset_account_id" "uuid" NOT NULL,
    "inventory_purchase_clearing_account_id" "uuid" NOT NULL,
    "cogs_account_id" "uuid" NOT NULL,
    "adjustment_gain_account_id" "uuid" NOT NULL,
    "adjustment_loss_account_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL
);

CREATE TABLE IF NOT EXISTS "public"."inventory_cost_state" (
    "organization_id" "uuid" NOT NULL,
    "product_id" "uuid" NOT NULL,
    "quantity_on_hand_total" numeric(18,4) DEFAULT 0 NOT NULL,
    "inventory_value" numeric(19,4) DEFAULT 0 NOT NULL,
    "average_unit_cost" numeric(19,6) DEFAULT 0 NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    CONSTRAINT "inventory_cost_state_average_unit_cost_check" CHECK (("average_unit_cost" >= (0)::numeric)),
    CONSTRAINT "inventory_cost_state_quantity_on_hand_total_check" CHECK (("quantity_on_hand_total" >= (0)::numeric)),
    CONSTRAINT "inventory_cost_state_zero_ck" CHECK (((("quantity_on_hand_total" = (0)::numeric) AND ("inventory_value" = (0)::numeric) AND ("average_unit_cost" = (0)::numeric)) OR ("quantity_on_hand_total" > (0)::numeric)))
);

CREATE TABLE IF NOT EXISTS "public"."inventory_ledger_entries" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid" NOT NULL,
    "inventory_operation_id" "uuid" NOT NULL,
    "inventory_operation_line_id" "uuid" NOT NULL,
    "product_id" "uuid" NOT NULL,
    "warehouse_id" "uuid" NOT NULL,
    "movement_date" "date" NOT NULL,
    "operation_type" "public"."inventory_operation_type" NOT NULL,
    "direction" "public"."inventory_line_direction" NOT NULL,
    "quantity" numeric(18,4) NOT NULL,
    "unit_cost" numeric(19,6) NOT NULL,
    "value_delta" numeric(19,4) NOT NULL,
    "source_type" "text",
    "source_id" "uuid",
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    CONSTRAINT "inventory_ledger_entries_quantity_check" CHECK (("quantity" > (0)::numeric))
);

CREATE TABLE IF NOT EXISTS "public"."inventory_operation_lines" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid" NOT NULL,
    "inventory_operation_id" "uuid" NOT NULL,
    "line_number" integer NOT NULL,
    "product_id" "uuid" NOT NULL,
    "warehouse_id" "uuid" NOT NULL,
    "direction" "public"."inventory_line_direction" NOT NULL,
    "quantity" numeric(18,4) NOT NULL,
    "unit_code" "public"."inventory_unit_code" NOT NULL,
    "unit_cost" numeric(19,6),
    "value_delta" numeric(19,4),
    "reservation_id" "uuid",
    "source_sales_line_id" "uuid",
    "source_purchase_line_id" "uuid",
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    CONSTRAINT "inventory_operation_lines_line_number_check" CHECK (("line_number" > 0)),
    CONSTRAINT "inventory_operation_lines_quantity_check" CHECK (("quantity" > (0)::numeric))
);

CREATE TABLE IF NOT EXISTS "public"."inventory_operation_sequences" (
    "organization_id" "uuid" NOT NULL,
    "operation_type" "public"."inventory_operation_type" NOT NULL,
    "sequence_year" integer NOT NULL,
    "last_value" bigint DEFAULT 0 NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    CONSTRAINT "inventory_operation_sequences_last_value_check" CHECK (("last_value" >= 0)),
    CONSTRAINT "inventory_operation_sequences_sequence_year_check" CHECK ((("sequence_year" >= 2000) AND ("sequence_year" <= 2100)))
);

CREATE TABLE IF NOT EXISTS "public"."inventory_operations" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid" NOT NULL,
    "internal_number" "text" NOT NULL,
    "operation_type" "public"."inventory_operation_type" NOT NULL,
    "status" "public"."inventory_operation_status" DEFAULT 'DRAFT'::"public"."inventory_operation_status" NOT NULL,
    "accounting_status" "public"."inventory_accounting_status" DEFAULT 'PENDING'::"public"."inventory_accounting_status" NOT NULL,
    "operation_date" "date" NOT NULL,
    "warehouse_id" "uuid" NOT NULL,
    "destination_warehouse_id" "uuid",
    "counterparty_id" "uuid",
    "source_purchase_order_id" "uuid",
    "source_purchase_document_id" "uuid",
    "source_sales_document_id" "uuid",
    "source_receipt_operation_id" "uuid",
    "reversed_operation_id" "uuid",
    "reason" "text",
    "description" "text" DEFAULT ''::"text" NOT NULL,
    "reference" "text",
    "idempotency_key" "text" NOT NULL,
    "journal_entry_id" "uuid",
    "reverse_journal_entry_id" "uuid",
    "created_by" "uuid",
    "posted_by" "uuid",
    "reversed_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "posted_at" timestamp with time zone,
    "reversed_at" timestamp with time zone,
    CONSTRAINT "inventory_operations_adjust_reason_ck" CHECK ((("operation_type" <> ALL (ARRAY['ADJUSTMENT_IN'::"public"."inventory_operation_type", 'ADJUSTMENT_OUT'::"public"."inventory_operation_type"])) OR (("reason" IS NOT NULL) AND ("length"("btrim"("reason")) >= 3)))),
    CONSTRAINT "inventory_operations_return_reason_optional" CHECK (true),
    CONSTRAINT "inventory_operations_transfer_ck" CHECK (((("operation_type" = 'TRANSFER'::"public"."inventory_operation_type") AND ("destination_warehouse_id" IS NOT NULL) AND ("destination_warehouse_id" <> "warehouse_id")) OR (("operation_type" <> 'TRANSFER'::"public"."inventory_operation_type") AND ("destination_warehouse_id" IS NULL))))
);

CREATE TABLE IF NOT EXISTS "public"."inventory_reservations" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid" NOT NULL,
    "product_id" "uuid" NOT NULL,
    "warehouse_id" "uuid" NOT NULL,
    "sales_document_id" "uuid" NOT NULL,
    "sales_document_line_id" "uuid" NOT NULL,
    "quantity_reserved" numeric(18,4) NOT NULL,
    "quantity_consumed" numeric(18,4) DEFAULT 0 NOT NULL,
    "status" "public"."inventory_reservation_status" DEFAULT 'ACTIVE'::"public"."inventory_reservation_status" NOT NULL,
    "idempotency_key" "text" NOT NULL,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    CONSTRAINT "inventory_reservations_consume_ck" CHECK (("quantity_consumed" <= "quantity_reserved")),
    CONSTRAINT "inventory_reservations_quantity_consumed_check" CHECK (("quantity_consumed" >= (0)::numeric)),
    CONSTRAINT "inventory_reservations_quantity_reserved_check" CHECK (("quantity_reserved" > (0)::numeric))
);

CREATE TABLE IF NOT EXISTS "public"."inventory_stock_state" (
    "organization_id" "uuid" NOT NULL,
    "warehouse_id" "uuid" NOT NULL,
    "product_id" "uuid" NOT NULL,
    "on_hand_quantity" numeric(18,4) DEFAULT 0 NOT NULL,
    "reserved_quantity" numeric(18,4) DEFAULT 0 NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    CONSTRAINT "inventory_stock_state_available_ck" CHECK (("reserved_quantity" <= "on_hand_quantity")),
    CONSTRAINT "inventory_stock_state_on_hand_quantity_check" CHECK (("on_hand_quantity" >= (0)::numeric)),
    CONSTRAINT "inventory_stock_state_reserved_quantity_check" CHECK (("reserved_quantity" >= (0)::numeric))
);

CREATE TABLE IF NOT EXISTS "public"."product_categories" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid" NOT NULL,
    "code" "text" NOT NULL,
    "name" "text" NOT NULL,
    "parent_id" "uuid",
    "active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    CONSTRAINT "product_categories_code_norm" CHECK (("code" = "upper"("btrim"("code")))),
    CONSTRAINT "product_categories_name_len" CHECK (("length"("btrim"("name")) >= 1))
);

CREATE TABLE IF NOT EXISTS "public"."products" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid" NOT NULL,
    "sku" "text",
    "barcode" "text",
    "name" "text" NOT NULL,
    "description" "text",
    "category_id" "uuid",
    "product_type" "public"."product_type" NOT NULL,
    "base_unit_code" "public"."inventory_unit_code" NOT NULL,
    "track_inventory" boolean NOT NULL,
    "active" boolean DEFAULT true NOT NULL,
    "sale_description" "text",
    "purchase_description" "text",
    "default_sale_price" numeric(19,4),
    "default_purchase_price" numeric(19,4),
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    CONSTRAINT "products_barcode_norm" CHECK ((("barcode" IS NULL) OR ("barcode" = "btrim"("barcode")))),
    CONSTRAINT "products_name_len" CHECK (("length"("btrim"("name")) >= 1)),
    CONSTRAINT "products_price_nonneg" CHECK (((("default_sale_price" IS NULL) OR ("default_sale_price" >= (0)::numeric)) AND (("default_purchase_price" IS NULL) OR ("default_purchase_price" >= (0)::numeric)))),
    CONSTRAINT "products_sku_norm" CHECK ((("sku" IS NULL) OR ("sku" = "upper"("btrim"("sku"))))),
    CONSTRAINT "products_track_inventory_ck" CHECK (((("product_type" = 'STOCK_ITEM'::"public"."product_type") AND ("track_inventory" = true)) OR (("product_type" = ANY (ARRAY['SERVICE'::"public"."product_type", 'NON_STOCK'::"public"."product_type"])) AND ("track_inventory" = false))))
);

CREATE TABLE IF NOT EXISTS "public"."warehouses" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid" NOT NULL,
    "branch_id" "uuid",
    "code" "text" NOT NULL,
    "name" "text" NOT NULL,
    "active" boolean DEFAULT true NOT NULL,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    CONSTRAINT "warehouses_code_norm" CHECK (("code" = "upper"("btrim"("code")))),
    CONSTRAINT "warehouses_name_len" CHECK (("length"("btrim"("name")) >= 1))
);

ALTER TABLE "public"."inventory_accounting_mappings" OWNER TO "postgres";

ALTER TABLE "public"."inventory_cost_state" OWNER TO "postgres";

ALTER TABLE "public"."inventory_ledger_entries" OWNER TO "postgres";

ALTER TABLE "public"."inventory_operation_lines" OWNER TO "postgres";

ALTER TABLE "public"."inventory_operation_sequences" OWNER TO "postgres";

ALTER TABLE "public"."inventory_operations" OWNER TO "postgres";

ALTER TABLE "public"."inventory_reservations" OWNER TO "postgres";

ALTER TABLE "public"."inventory_stock_state" OWNER TO "postgres";

ALTER TABLE "public"."product_categories" OWNER TO "postgres";

ALTER TABLE "public"."products" OWNER TO "postgres";

ALTER TABLE "public"."warehouses" OWNER TO "postgres";

ALTER TABLE ONLY "public"."inventory_accounting_mappings"
    ADD CONSTRAINT "inventory_accounting_mappings_pkey" PRIMARY KEY ("organization_id");

ALTER TABLE ONLY "public"."inventory_cost_state"
    ADD CONSTRAINT "inventory_cost_state_pkey" PRIMARY KEY ("organization_id", "product_id");

ALTER TABLE ONLY "public"."inventory_ledger_entries"
    ADD CONSTRAINT "inventory_ledger_entries_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."inventory_operation_lines"
    ADD CONSTRAINT "inventory_operation_lines_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."inventory_operation_sequences"
    ADD CONSTRAINT "inventory_operation_sequences_pkey" PRIMARY KEY ("organization_id", "operation_type", "sequence_year");

ALTER TABLE ONLY "public"."inventory_operations"
    ADD CONSTRAINT "inventory_operations_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."inventory_reservations"
    ADD CONSTRAINT "inventory_reservations_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."inventory_stock_state"
    ADD CONSTRAINT "inventory_stock_state_pkey" PRIMARY KEY ("organization_id", "warehouse_id", "product_id");

ALTER TABLE ONLY "public"."product_categories"
    ADD CONSTRAINT "product_categories_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."products"
    ADD CONSTRAINT "products_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."warehouses"
    ADD CONSTRAINT "warehouses_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."inventory_ledger_entries"
    ADD CONSTRAINT "inventory_ledger_org_id_unique" UNIQUE ("organization_id", "id");

ALTER TABLE ONLY "public"."inventory_operation_lines"
    ADD CONSTRAINT "inventory_operation_lines_op_line_unique" UNIQUE ("inventory_operation_id", "line_number");

ALTER TABLE ONLY "public"."inventory_operation_lines"
    ADD CONSTRAINT "inventory_operation_lines_org_id_unique" UNIQUE ("organization_id", "id");

ALTER TABLE ONLY "public"."inventory_operations"
    ADD CONSTRAINT "inventory_operations_idempotency_unique" UNIQUE ("organization_id", "idempotency_key");

ALTER TABLE ONLY "public"."inventory_operations"
    ADD CONSTRAINT "inventory_operations_number_unique" UNIQUE ("organization_id", "internal_number");

ALTER TABLE ONLY "public"."inventory_operations"
    ADD CONSTRAINT "inventory_operations_org_id_unique" UNIQUE ("organization_id", "id");

ALTER TABLE ONLY "public"."inventory_reservations"
    ADD CONSTRAINT "inventory_reservations_idempotency_unique" UNIQUE ("organization_id", "idempotency_key");

ALTER TABLE ONLY "public"."inventory_reservations"
    ADD CONSTRAINT "inventory_reservations_org_id_unique" UNIQUE ("organization_id", "id");

ALTER TABLE ONLY "public"."product_categories"
    ADD CONSTRAINT "product_categories_code_unique" UNIQUE ("organization_id", "code");

ALTER TABLE ONLY "public"."product_categories"
    ADD CONSTRAINT "product_categories_org_id_unique" UNIQUE ("organization_id", "id");

ALTER TABLE ONLY "public"."products"
    ADD CONSTRAINT "products_org_id_unique" UNIQUE ("organization_id", "id");

ALTER TABLE ONLY "public"."warehouses"
    ADD CONSTRAINT "warehouses_code_unique" UNIQUE ("organization_id", "code");

ALTER TABLE ONLY "public"."warehouses"
    ADD CONSTRAINT "warehouses_org_id_unique" UNIQUE ("organization_id", "id");

CREATE OR REPLACE FUNCTION "public"."create_inventory_reservation"("p_organization_id" "uuid", "p_product_id" "uuid", "p_warehouse_id" "uuid", "p_sales_document_id" "uuid", "p_sales_document_line_id" "uuid", "p_quantity" numeric, "p_idempotency_key" "text") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_uid uuid := auth.uid();
  v_existing uuid;
  v_product public.products%rowtype;
  v_on_hand numeric(18,4);
  v_reserved numeric(18,4);
  v_id uuid;
begin
  if v_uid is null then raise exception 'authentication required'; end if;
  if p_quantity is null or p_quantity <= 0 then raise exception 'quantity must be positive'; end if;
  if not public.is_org_member(p_organization_id) then raise exception 'not a member'; end if;
  perform public.inventory_assert_feature(p_organization_id);
  if not public.has_org_role(
    p_organization_id,
    array['owner','admin','manager','operator','accountant']::public.member_role[]
  ) then
    raise exception 'insufficient role to reserve';
  end if;

  select id into v_existing
  from public.inventory_reservations
  where organization_id = p_organization_id and idempotency_key = p_idempotency_key;
  if v_existing is not null then return v_existing; end if;

  select * into v_product from public.products
  where id = p_product_id and organization_id = p_organization_id;
  if not found then raise exception 'product not found'; end if;
  if v_product.product_type is distinct from 'STOCK_ITEM' or not v_product.track_inventory then
    raise exception 'only STOCK_ITEM can be reserved';
  end if;
  if not v_product.active then raise exception 'product inactive'; end if;

  perform set_config('inventory.engine_write', '1', true);
  perform public.ensure_inventory_stock_row(p_organization_id, p_warehouse_id, p_product_id);

  select on_hand_quantity, reserved_quantity
    into v_on_hand, v_reserved
  from public.inventory_stock_state
  where organization_id = p_organization_id
    and warehouse_id = p_warehouse_id
    and product_id = p_product_id
  for update;

  if (v_on_hand - v_reserved) < p_quantity then
    raise exception 'insufficient available stock for reservation';
  end if;

  update public.inventory_stock_state
  set reserved_quantity = reserved_quantity + p_quantity,
      updated_at = timezone('utc', now())
  where organization_id = p_organization_id
    and warehouse_id = p_warehouse_id
    and product_id = p_product_id;

  insert into public.inventory_reservations (
    organization_id, product_id, warehouse_id, sales_document_id, sales_document_line_id,
    quantity_reserved, quantity_consumed, status, idempotency_key, created_by
  ) values (
    p_organization_id, p_product_id, p_warehouse_id, p_sales_document_id, p_sales_document_line_id,
    p_quantity, 0, 'ACTIVE', p_idempotency_key, v_uid
  )
  returning id into v_id;

  return v_id;
end;
$$;

CREATE OR REPLACE FUNCTION "public"."deactivate_product"("p_product_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_uid uuid := auth.uid();
  v_p public.products%rowtype;
  v_on numeric(18,4);
  v_res numeric(18,4);
  v_draft int;
begin
  if v_uid is null then raise exception 'authentication required'; end if;
  select * into v_p from public.products where id = p_product_id for update;
  if not found then raise exception 'product not found'; end if;
  if not public.has_org_role(v_p.organization_id, array['owner','admin','manager','accountant']::public.member_role[]) then
    raise exception 'insufficient role';
  end if;
  if v_p.product_type = 'STOCK_ITEM' then
    select coalesce(sum(on_hand_quantity),0), coalesce(sum(reserved_quantity),0)
      into v_on, v_res
    from public.inventory_stock_state
    where organization_id = v_p.organization_id and product_id = p_product_id;
    if v_on <> 0 or v_res <> 0 then
      raise exception 'cannot deactivate STOCK_ITEM with on-hand or reserved stock';
    end if;
    select count(*) into v_draft from public.inventory_operation_lines l
    join public.inventory_operations o on o.id = l.inventory_operation_id
    where l.product_id = p_product_id and o.status = 'DRAFT';
    if v_draft > 0 then
      raise exception 'cannot deactivate product with DRAFT inventory operations';
    end if;
  end if;
  update public.products set active = false, updated_at = timezone('utc', now()) where id = p_product_id;
end;
$$;

CREATE OR REPLACE FUNCTION "public"."ensure_inventory_chart_accounts"("p_org_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_uid uuid := auth.uid();
  v_parent uuid;
  v_id uuid;
begin
  if v_uid is null then raise exception 'authentication required'; end if;
  if not public.has_org_role(p_org_id, array['owner','admin','accountant']::public.member_role[]) then
    raise exception 'insufficient role';
  end if;

  select id into v_parent from public.accounts
  where organization_id = p_org_id and code = '1.1' limit 1;

  if v_parent is not null and not exists (
    select 1 from public.accounts where organization_id = p_org_id and system_role = 'inventory' and is_postable
  ) then
    if not exists (select 1 from public.accounts where organization_id = p_org_id and code = '1.1.05') then
      insert into public.accounts (
        organization_id, parent_id, code, name, account_type, normal_balance, is_postable, system_role
      ) values (
        p_org_id, v_parent, '1.1.05', 'Mercaderías', 'ASSET', 'DEBIT', true, 'inventory'
      );
    end if;
  end if;

  select id into v_parent from public.accounts
  where organization_id = p_org_id and code = '2.1' limit 1;

  if v_parent is not null and not exists (
    select 1 from public.accounts where organization_id = p_org_id and system_role = 'inventory_purchase_clearing' and is_postable
  ) then
    if not exists (select 1 from public.accounts where organization_id = p_org_id and code = '2.1.03') then
      insert into public.accounts (
        organization_id, parent_id, code, name, account_type, normal_balance, is_postable, system_role
      ) values (
        p_org_id, v_parent, '2.1.03', 'Mercaderías a recibir / clearing', 'LIABILITY', 'CREDIT', true, 'inventory_purchase_clearing'
      );
    end if;
  end if;

  select id into v_parent from public.accounts
  where organization_id = p_org_id and code = '4' limit 1;
  if v_parent is null then
    select id into v_parent from public.accounts
    where organization_id = p_org_id and code = '4.1.01' limit 1;
  end if;

  if not exists (
    select 1 from public.accounts where organization_id = p_org_id and system_role = 'inventory_adjustment_gain' and is_postable
  ) then
    if not exists (select 1 from public.accounts where organization_id = p_org_id and code = '4.1.02') then
      select id into v_parent from public.accounts where organization_id = p_org_id and code like '4%' and not is_postable order by code limit 1;
      insert into public.accounts (
        organization_id, parent_id, code, name, account_type, normal_balance, is_postable, system_role
      ) values (
        p_org_id, v_parent, '4.1.02', 'Sobrantes de inventario', 'REVENUE', 'CREDIT', true, 'inventory_adjustment_gain'
      );
    end if;
  end if;

  if not exists (
    select 1 from public.accounts where organization_id = p_org_id and system_role = 'inventory_adjustment_loss' and is_postable
  ) then
    select id into v_parent from public.accounts
    where organization_id = p_org_id and code = '6' and not is_postable limit 1;
    if not exists (select 1 from public.accounts where organization_id = p_org_id and code = '6.1.02') then
      insert into public.accounts (
        organization_id, parent_id, code, name, account_type, normal_balance, is_postable, system_role
      ) values (
        p_org_id, v_parent, '6.1.02', 'Faltantes de inventario', 'EXPENSE', 'DEBIT', true, 'inventory_adjustment_loss'
      );
    end if;
  end if;
end;
$$;

CREATE OR REPLACE FUNCTION "public"."ensure_inventory_cost_row"("p_org" "uuid", "p_product" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  insert into public.inventory_cost_state (organization_id, product_id)
  values (p_org, p_product)
  on conflict do nothing;
end;
$$;

CREATE OR REPLACE FUNCTION "public"."ensure_inventory_stock_row"("p_org" "uuid", "p_wh" "uuid", "p_product" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  insert into public.inventory_stock_state (organization_id, warehouse_id, product_id)
  values (p_org, p_wh, p_product)
  on conflict do nothing;
end;
$$;

CREATE OR REPLACE FUNCTION "public"."inventory_assert_feature"("p_org_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_status text;
begin
  select of.status::text into v_status
  from public.organization_features of
  join public.feature_catalog fc on fc.id = of.feature_id
  where of.organization_id = p_org_id and fc.code = 'inventory';
  if v_status is distinct from 'enabled' then
    raise exception 'inventory feature not enabled';
  end if;
end;
$$;

CREATE OR REPLACE FUNCTION "public"."inventory_round_avg"("p_value" numeric, "p_qty" numeric) RETURNS numeric
    LANGUAGE "sql" IMMUTABLE
    SET "search_path" TO ''
    AS $$
  select case when p_qty > 0 then round(p_value / p_qty, 6)::numeric(19,6) else 0::numeric(19,6) end;
$$;

CREATE OR REPLACE FUNCTION "public"."inventory_round_value"("p_qty" numeric, "p_unit_cost" numeric) RETURNS numeric
    LANGUAGE "sql" IMMUTABLE
    SET "search_path" TO ''
    AS $$
  select round(p_qty * p_unit_cost, 4)::numeric(19,4);
$$;

CREATE OR REPLACE FUNCTION "public"."next_inventory_operation_number"("p_org_id" "uuid", "p_operation_type" "public"."inventory_operation_type") RETURNS "text"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_year int := extract(year from timezone('utc', now()))::int;
  v_next bigint;
  v_prefix text;
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  if not public.is_org_member(p_org_id) then raise exception 'not a member'; end if;
  perform public.inventory_assert_feature(p_org_id);

  insert into public.inventory_operation_sequences (organization_id, operation_type, sequence_year, last_value)
  values (p_org_id, p_operation_type, v_year, 1)
  on conflict (organization_id, operation_type, sequence_year)
  do update set last_value = public.inventory_operation_sequences.last_value + 1,
                updated_at = timezone('utc', now())
  returning last_value into v_next;

  v_prefix := case p_operation_type
    when 'RECEIPT' then 'REC'
    when 'ISSUE' then 'ISS'
    when 'TRANSFER' then 'TRF'
    when 'ADJUSTMENT_IN' then 'ADI'
    when 'ADJUSTMENT_OUT' then 'ADO'
    when 'RETURN_TO_SUPPLIER' then 'RTS'
    when 'REVERSAL' then 'REV'
    else 'INV'
  end;

  return v_prefix || '-' || v_year::text || '-' || lpad(v_next::text, 6, '0');
end;
$$;

CREATE OR REPLACE FUNCTION "public"."post_inventory_operation"("p_operation_id" "uuid") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_uid uuid := auth.uid();
  v_op public.inventory_operations%rowtype;
  v_map public.inventory_accounting_mappings%rowtype;
  v_period_id uuid;
  v_existing uuid;
  v_line record;
  v_product public.products%rowtype;
  v_lock_keys text[];
  v_key text;
  v_wh uuid;
  v_prod uuid;
  v_cost public.inventory_cost_state%rowtype;
  v_stock public.inventory_stock_state%rowtype;
  v_unit_cost numeric(19,6);
  v_value numeric(19,4);
  v_q0 numeric(18,4);
  v_v0 numeric(19,4);
  v_q1 numeric(18,4);
  v_v1 numeric(19,4);
  v_avg numeric(19,6);
  v_entry_id uuid;
  v_line_no int := 0;
  v_need_journal boolean := false;
  v_asset uuid;
  v_clearing uuid;
  v_cogs uuid;
  v_gain uuid;
  v_loss uuid;
  v_max_date date;
  v_res public.inventory_reservations%rowtype;
  v_consume numeric(18,4);
  v_remain numeric(18,4);
  v_sum_wh numeric(18,4);
  v_wh_a uuid;
  v_wh_b uuid;
begin
  if v_uid is null then raise exception 'authentication required'; end if;

  select * into v_op from public.inventory_operations where id = p_operation_id for update;
  if not found then raise exception 'inventory operation not found'; end if;

  perform public.inventory_assert_feature(v_op.organization_id);

  if v_op.status = 'POSTED' and v_op.journal_entry_id is not null then
    return p_operation_id;
  end if;
  if v_op.status = 'POSTED' and v_op.accounting_status = 'NOT_APPLICABLE' then
    return p_operation_id;
  end if;
  if v_op.status = 'POSTED' then
    return p_operation_id;
  end if;
  if v_op.status is distinct from 'DRAFT' then
    raise exception 'only DRAFT operations can be posted';
  end if;

  -- Role gates
  if v_op.operation_type in ('ADJUSTMENT_IN', 'ADJUSTMENT_OUT') then
    if not public.has_org_role(
      v_op.organization_id, array['owner','accountant']::public.member_role[]
    ) then
      raise exception 'only owner/accountant may post adjustments';
    end if;
    if v_op.reason is null or length(btrim(v_op.reason)) < 3 then
      raise exception 'adjustment reason is required';
    end if;
  elsif v_op.operation_type = 'RETURN_TO_SUPPLIER' then
    if not public.has_org_role(
      v_op.organization_id, array['owner','admin','accountant','manager']::public.member_role[]
    ) then
      raise exception 'insufficient role for supplier return';
    end if;
  else
    if not public.has_org_role(
      v_op.organization_id,
      array['owner','admin','accountant','manager','operator']::public.member_role[]
    ) then
      raise exception 'insufficient role to post inventory';
    end if;
  end if;

  -- Closed period: fail closed (no stock mutation)
  select period_id into v_period_id
  from public.resolve_open_period(v_op.organization_id, v_op.operation_date);
  if v_period_id is null and v_op.operation_type is distinct from 'TRANSFER' then
    -- TRANSFER may skip GL but still needs open period? Fail closed for all valuation ops.
    -- Transfer has no GL — still allow physical transfer in open period only for consistency.
    null;
  end if;
  if v_period_id is null then
    raise exception 'ACCOUNTING_REQUIRES_REVIEW: accounting period is closed';
  end if;

  -- Load mapping when journal may be needed
  if v_op.operation_type is distinct from 'TRANSFER' then
    select * into v_map from public.inventory_accounting_mappings
    where organization_id = v_op.organization_id;
    if not found then
      raise exception 'Falta configurar el mapeo contable de inventario';
    end if;
    v_asset := v_map.inventory_asset_account_id;
    v_clearing := v_map.inventory_purchase_clearing_account_id;
    v_cogs := v_map.cogs_account_id;
    v_gain := v_map.adjustment_gain_account_id;
    v_loss := v_map.adjustment_loss_account_id;
  end if;

  -- Collect lines and lock keys
  if not exists (
    select 1 from public.inventory_operation_lines where inventory_operation_id = p_operation_id
  ) then
    raise exception 'operation has no lines';
  end if;

  -- Deterministic locks: cost state then stock state by product/warehouse
  for v_prod in
    select distinct product_id from public.inventory_operation_lines
    where inventory_operation_id = p_operation_id
    order by 1
  loop
    -- backdate check per product
    select max(movement_date) into v_max_date
    from public.inventory_ledger_entries
    where organization_id = v_op.organization_id and product_id = v_prod;
    if v_max_date is not null and v_op.operation_date < v_max_date then
      raise exception 'INVENTORY_BACKDATED_REQUIRES_REVIEW';
    end if;

    perform set_config('inventory.engine_write', '1', true);
    perform public.ensure_inventory_cost_row(v_op.organization_id, v_prod);
    perform 1 from public.inventory_cost_state
    where organization_id = v_op.organization_id and product_id = v_prod
    for update;
  end loop;

  -- Lock stock rows (transfer: both warehouses sorted)
  for v_line in
    select distinct warehouse_id, product_id
    from public.inventory_operation_lines
    where inventory_operation_id = p_operation_id
    order by product_id, warehouse_id
  loop
    perform set_config('inventory.engine_write', '1', true);
    perform public.ensure_inventory_stock_row(v_op.organization_id, v_line.warehouse_id, v_line.product_id);
    perform 1 from public.inventory_stock_state
    where organization_id = v_op.organization_id
      and warehouse_id = v_line.warehouse_id
      and product_id = v_line.product_id
    for update;
  end loop;

  if v_op.operation_type = 'TRANSFER' and v_op.destination_warehouse_id is not null then
    v_wh_a := least(v_op.warehouse_id, v_op.destination_warehouse_id);
    v_wh_b := greatest(v_op.warehouse_id, v_op.destination_warehouse_id);
    for v_prod in
      select distinct product_id from public.inventory_operation_lines
      where inventory_operation_id = p_operation_id order by 1
    loop
      perform set_config('inventory.engine_write', '1', true);
      perform public.ensure_inventory_stock_row(v_op.organization_id, v_wh_a, v_prod);
      perform public.ensure_inventory_stock_row(v_op.organization_id, v_wh_b, v_prod);
      perform 1 from public.inventory_stock_state
      where organization_id = v_op.organization_id and warehouse_id = v_wh_a and product_id = v_prod
      for update;
      perform 1 from public.inventory_stock_state
      where organization_id = v_op.organization_id and warehouse_id = v_wh_b and product_id = v_prod
      for update;
    end loop;
  end if;

  -- Idempotent journal?
  select id into v_existing
  from public.journal_entries
  where organization_id = v_op.organization_id
    and source_type = 'INVENTORY'
    and source_id = p_operation_id
    and status = 'POSTED'
  limit 1;
  if v_existing is not null then
    perform set_config('inventory.engine_write', '1', true);
    update public.inventory_operations
    set status = 'POSTED', journal_entry_id = v_existing, accounting_status = 'POSTED',
        posted_by = coalesce(posted_by, v_uid),
        posted_at = coalesce(posted_at, timezone('utc', now()))
    where id = p_operation_id;
    return p_operation_id;
  end if;

  -- Process each line
  for v_line in
    select * from public.inventory_operation_lines
    where inventory_operation_id = p_operation_id
    order by line_number
  loop
    select * into v_product from public.products
    where id = v_line.product_id and organization_id = v_op.organization_id;
    if not found then raise exception 'product not found on line %', v_line.line_number; end if;
    if v_product.product_type is distinct from 'STOCK_ITEM' or not v_product.track_inventory then
      raise exception 'SERVICE/NON_STOCK cannot create stock movements';
    end if;
    if v_line.unit_code::text is distinct from v_product.base_unit_code::text then
      raise exception 'unit must equal product base unit (no conversion)';
    end if;

    select * into v_cost from public.inventory_cost_state
    where organization_id = v_op.organization_id and product_id = v_line.product_id;

    select * into v_stock from public.inventory_stock_state
    where organization_id = v_op.organization_id
      and warehouse_id = v_line.warehouse_id
      and product_id = v_line.product_id;

    if v_op.operation_type = 'RECEIPT' or v_op.operation_type = 'ADJUSTMENT_IN' then
      if v_line.direction is distinct from 'IN' then
        raise exception 'receipt/adjustment in requires IN direction';
      end if;
      if v_line.unit_cost is null or v_line.unit_cost < 0 then
        raise exception 'receipt/adjustment in requires unit cost';
      end if;
      v_unit_cost := v_line.unit_cost;
      v_value := public.inventory_round_value(v_line.quantity, v_unit_cost);
      v_q0 := v_cost.quantity_on_hand_total;
      v_v0 := v_cost.inventory_value;
      v_q1 := v_q0 + v_line.quantity;
      v_v1 := v_v0 + v_value;
      v_avg := public.inventory_round_avg(v_v1, v_q1);

      update public.inventory_cost_state
      set quantity_on_hand_total = v_q1, inventory_value = v_v1, average_unit_cost = v_avg,
          updated_at = timezone('utc', now())
      where organization_id = v_op.organization_id and product_id = v_line.product_id;

      update public.inventory_stock_state
      set on_hand_quantity = on_hand_quantity + v_line.quantity,
          updated_at = timezone('utc', now())
      where organization_id = v_op.organization_id
        and warehouse_id = v_line.warehouse_id
        and product_id = v_line.product_id;

      update public.inventory_operation_lines
      set unit_cost = v_unit_cost, value_delta = v_value
      where id = v_line.id;

      insert into public.inventory_ledger_entries (
        organization_id, inventory_operation_id, inventory_operation_line_id,
        product_id, warehouse_id, movement_date, operation_type, direction,
        quantity, unit_cost, value_delta, source_type, source_id
      ) values (
        v_op.organization_id, p_operation_id, v_line.id,
        v_line.product_id, v_line.warehouse_id, v_op.operation_date, v_op.operation_type, 'IN',
        v_line.quantity, v_unit_cost, v_value, 'INVENTORY_OPERATION', p_operation_id
      );
      v_need_journal := true;

    elsif v_op.operation_type in ('ISSUE', 'ADJUSTMENT_OUT', 'RETURN_TO_SUPPLIER') then
      if v_line.direction is distinct from 'OUT' then
        raise exception 'issue/out/return requires OUT direction';
      end if;
      if v_stock.on_hand_quantity < v_line.quantity then
        raise exception 'insufficient on-hand stock';
      end if;
      if (v_stock.on_hand_quantity - v_stock.reserved_quantity) < v_line.quantity
         and v_line.reservation_id is null then
        -- allow issue against reservation path below; without reservation need available
        if v_op.operation_type = 'ISSUE' then
          raise exception 'insufficient available stock';
        end if;
      end if;

      v_unit_cost := v_cost.average_unit_cost;
      if v_op.operation_type = 'RETURN_TO_SUPPLIER' and v_line.unit_cost is not null then
        -- explicit cost only if equals current avg; else review
        if abs(v_line.unit_cost - v_cost.average_unit_cost) > 0.000001 then
          raise exception 'INVENTORY_REQUIRES_REVIEW: return cost variance vs average';
        end if;
      end if;
      v_value := public.inventory_round_value(v_line.quantity, v_unit_cost);
      v_q0 := v_cost.quantity_on_hand_total;
      v_v0 := v_cost.inventory_value;
      if v_q0 < v_line.quantity then
        raise exception 'insufficient organization stock';
      end if;
      v_q1 := v_q0 - v_line.quantity;
      v_v1 := v_v0 - v_value;
      if v_q1 = 0 then
        v_v1 := 0;
        v_avg := 0;
      else
        v_avg := public.inventory_round_avg(v_v1, v_q1);
      end if;

      -- Reservation consume (ISSUE)
      if v_line.reservation_id is not null then
        select * into v_res from public.inventory_reservations
        where id = v_line.reservation_id for update;
        if not found or v_res.status is distinct from 'ACTIVE' then
          raise exception 'reservation not active';
        end if;
        v_remain := v_res.quantity_reserved - v_res.quantity_consumed;
        v_consume := least(v_line.quantity, v_remain);
        if v_consume < v_line.quantity then
          raise exception 'cannot consume above reservation remaining';
        end if;
        update public.inventory_reservations
        set quantity_consumed = quantity_consumed + v_consume,
            status = case
              when quantity_consumed + v_consume >= quantity_reserved then 'CONSUMED'::public.inventory_reservation_status
              else 'ACTIVE'::public.inventory_reservation_status
            end,
            updated_at = timezone('utc', now())
        where id = v_res.id;
        update public.inventory_stock_state
        set reserved_quantity = reserved_quantity - v_consume,
            updated_at = timezone('utc', now())
        where organization_id = v_op.organization_id
          and warehouse_id = v_line.warehouse_id
          and product_id = v_line.product_id;
      end if;

      update public.inventory_cost_state
      set quantity_on_hand_total = v_q1, inventory_value = v_v1, average_unit_cost = v_avg,
          updated_at = timezone('utc', now())
      where organization_id = v_op.organization_id and product_id = v_line.product_id;

      update public.inventory_stock_state
      set on_hand_quantity = on_hand_quantity - v_line.quantity,
          updated_at = timezone('utc', now())
      where organization_id = v_op.organization_id
        and warehouse_id = v_line.warehouse_id
        and product_id = v_line.product_id
        and on_hand_quantity >= v_line.quantity;
      if not found then
        raise exception 'concurrent stock update failed';
      end if;

      update public.inventory_operation_lines
      set unit_cost = v_unit_cost, value_delta = v_value
      where id = v_line.id;

      insert into public.inventory_ledger_entries (
        organization_id, inventory_operation_id, inventory_operation_line_id,
        product_id, warehouse_id, movement_date, operation_type, direction,
        quantity, unit_cost, value_delta, source_type, source_id
      ) values (
        v_op.organization_id, p_operation_id, v_line.id,
        v_line.product_id, v_line.warehouse_id, v_op.operation_date, v_op.operation_type, 'OUT',
        v_line.quantity, v_unit_cost, v_value, 'INVENTORY_OPERATION', p_operation_id
      );
      v_need_journal := true;

    elsif v_op.operation_type = 'TRANSFER' then
      -- Lines should be paired OUT then IN same qty/product; validate per OUT
      if v_line.direction = 'OUT' then
        if v_stock.on_hand_quantity < v_line.quantity then
          raise exception 'insufficient stock for transfer';
        end if;
        if (v_stock.on_hand_quantity - v_stock.reserved_quantity) < v_line.quantity then
          raise exception 'insufficient available stock for transfer';
        end if;
        v_unit_cost := v_cost.average_unit_cost;
        v_value := public.inventory_round_value(v_line.quantity, v_unit_cost);
        -- org cost unchanged
        update public.inventory_stock_state
        set on_hand_quantity = on_hand_quantity - v_line.quantity,
            updated_at = timezone('utc', now())
        where organization_id = v_op.organization_id
          and warehouse_id = v_line.warehouse_id
          and product_id = v_line.product_id
          and on_hand_quantity >= v_line.quantity;
        if not found then raise exception 'concurrent transfer source failed'; end if;

        update public.inventory_operation_lines
        set unit_cost = v_unit_cost, value_delta = v_value where id = v_line.id;

        insert into public.inventory_ledger_entries (
          organization_id, inventory_operation_id, inventory_operation_line_id,
          product_id, warehouse_id, movement_date, operation_type, direction,
          quantity, unit_cost, value_delta, source_type, source_id
        ) values (
          v_op.organization_id, p_operation_id, v_line.id,
          v_line.product_id, v_line.warehouse_id, v_op.operation_date, 'TRANSFER', 'OUT',
          v_line.quantity, v_unit_cost, v_value, 'INVENTORY_OPERATION', p_operation_id
        );
      elsif v_line.direction = 'IN' then
        v_unit_cost := coalesce(v_line.unit_cost, v_cost.average_unit_cost);
        v_value := public.inventory_round_value(v_line.quantity, v_unit_cost);
        update public.inventory_stock_state
        set on_hand_quantity = on_hand_quantity + v_line.quantity,
            updated_at = timezone('utc', now())
        where organization_id = v_op.organization_id
          and warehouse_id = v_line.warehouse_id
          and product_id = v_line.product_id;

        update public.inventory_operation_lines
        set unit_cost = v_unit_cost, value_delta = v_value where id = v_line.id;

        insert into public.inventory_ledger_entries (
          organization_id, inventory_operation_id, inventory_operation_line_id,
          product_id, warehouse_id, movement_date, operation_type, direction,
          quantity, unit_cost, value_delta, source_type, source_id
        ) values (
          v_op.organization_id, p_operation_id, v_line.id,
          v_line.product_id, v_line.warehouse_id, v_op.operation_date, 'TRANSFER', 'IN',
          v_line.quantity, v_unit_cost, v_value, 'INVENTORY_OPERATION', p_operation_id
        );
      end if;
      v_need_journal := false;
    else
      raise exception 'unsupported operation type %', v_op.operation_type;
    end if;
  end loop;

  -- Reconcile org qty vs warehouses for touched products
  for v_prod in
    select distinct product_id from public.inventory_operation_lines
    where inventory_operation_id = p_operation_id order by 1
  loop
    select coalesce(sum(on_hand_quantity), 0) into v_sum_wh
    from public.inventory_stock_state
    where organization_id = v_op.organization_id and product_id = v_prod;
    select quantity_on_hand_total into v_q1
    from public.inventory_cost_state
    where organization_id = v_op.organization_id and product_id = v_prod;
    if v_sum_wh is distinct from v_q1 then
      raise exception 'stock reconciliation failed: warehouse sum % <> cost state %', v_sum_wh, v_q1;
    end if;
  end loop;

  -- Journal
  if v_op.operation_type = 'TRANSFER' then
    perform set_config('inventory.engine_write', '1', true);
    update public.inventory_operations
    set status = 'POSTED', accounting_status = 'NOT_APPLICABLE',
        posted_by = v_uid, posted_at = timezone('utc', now()), updated_at = timezone('utc', now())
    where id = p_operation_id;
    return p_operation_id;
  end if;

  insert into public.journal_entries (
    organization_id, entry_date, description, status, source_type, source_id, created_by
  ) values (
    v_op.organization_id, v_op.operation_date,
    'Inventario ' || v_op.operation_type::text || ' ' || v_op.internal_number,
    'DRAFT', 'INVENTORY', p_operation_id, v_uid
  ) returning id into v_entry_id;

  if v_op.operation_type = 'RECEIPT' then
    for v_line in
      select * from public.inventory_operation_lines where inventory_operation_id = p_operation_id order by line_number
    loop
      v_line_no := v_line_no + 1;
      insert into public.journal_entry_lines (
        organization_id, journal_entry_id, line_number, account_id, description, debit, credit
      ) values (
        v_op.organization_id, v_entry_id, v_line_no, v_asset, 'Ingreso mercadería', v_line.value_delta, 0
      );
      v_line_no := v_line_no + 1;
      insert into public.journal_entry_lines (
        organization_id, journal_entry_id, line_number, account_id, description, debit, credit
      ) values (
        v_op.organization_id, v_entry_id, v_line_no, v_clearing, 'Clearing compras inventariables', 0, v_line.value_delta
      );
    end loop;
  elsif v_op.operation_type = 'ISSUE' then
    for v_line in
      select * from public.inventory_operation_lines where inventory_operation_id = p_operation_id order by line_number
    loop
      v_line_no := v_line_no + 1;
      insert into public.journal_entry_lines (
        organization_id, journal_entry_id, line_number, account_id, description, debit, credit
      ) values (
        v_op.organization_id, v_entry_id, v_line_no, v_cogs, 'CMV', v_line.value_delta, 0
      );
      v_line_no := v_line_no + 1;
      insert into public.journal_entry_lines (
        organization_id, journal_entry_id, line_number, account_id, description, debit, credit
      ) values (
        v_op.organization_id, v_entry_id, v_line_no, v_asset, 'Salida mercadería', 0, v_line.value_delta
      );
    end loop;
  elsif v_op.operation_type = 'ADJUSTMENT_IN' then
    for v_line in
      select * from public.inventory_operation_lines where inventory_operation_id = p_operation_id order by line_number
    loop
      v_line_no := v_line_no + 1;
      insert into public.journal_entry_lines (
        organization_id, journal_entry_id, line_number, account_id, description, debit, credit
      ) values (
        v_op.organization_id, v_entry_id, v_line_no, v_asset, coalesce(v_op.reason,'Ajuste IN'), v_line.value_delta, 0
      );
      v_line_no := v_line_no + 1;
      insert into public.journal_entry_lines (
        organization_id, journal_entry_id, line_number, account_id, description, debit, credit
      ) values (
        v_op.organization_id, v_entry_id, v_line_no, v_gain, coalesce(v_op.reason,'Sobrante'), 0, v_line.value_delta
      );
    end loop;
  elsif v_op.operation_type = 'ADJUSTMENT_OUT' then
    for v_line in
      select * from public.inventory_operation_lines where inventory_operation_id = p_operation_id order by line_number
    loop
      v_line_no := v_line_no + 1;
      insert into public.journal_entry_lines (
        organization_id, journal_entry_id, line_number, account_id, description, debit, credit
      ) values (
        v_op.organization_id, v_entry_id, v_line_no, v_loss, coalesce(v_op.reason,'Faltante'), v_line.value_delta, 0
      );
      v_line_no := v_line_no + 1;
      insert into public.journal_entry_lines (
        organization_id, journal_entry_id, line_number, account_id, description, debit, credit
      ) values (
        v_op.organization_id, v_entry_id, v_line_no, v_asset, coalesce(v_op.reason,'Ajuste OUT'), 0, v_line.value_delta
      );
    end loop;
  elsif v_op.operation_type = 'RETURN_TO_SUPPLIER' then
    for v_line in
      select * from public.inventory_operation_lines where inventory_operation_id = p_operation_id order by line_number
    loop
      v_line_no := v_line_no + 1;
      insert into public.journal_entry_lines (
        organization_id, journal_entry_id, line_number, account_id, description, debit, credit
      ) values (
        v_op.organization_id, v_entry_id, v_line_no, v_clearing, 'Devolución a proveedor', v_line.value_delta, 0
      );
      v_line_no := v_line_no + 1;
      insert into public.journal_entry_lines (
        organization_id, journal_entry_id, line_number, account_id, description, debit, credit
      ) values (
        v_op.organization_id, v_entry_id, v_line_no, v_asset, 'Salida por devolución proveedor', 0, v_line.value_delta
      );
    end loop;
  end if;

  begin
    perform public.post_journal_entry(v_entry_id);
  exception when others then
    delete from public.journal_entries where id = v_entry_id and status = 'DRAFT';
    raise;
  end;

  perform set_config('inventory.engine_write', '1', true);
  update public.inventory_operations
  set status = 'POSTED', accounting_status = 'POSTED', journal_entry_id = v_entry_id,
      posted_by = v_uid, posted_at = timezone('utc', now()), updated_at = timezone('utc', now())
  where id = p_operation_id;

  return p_operation_id;
end;
$$;

CREATE OR REPLACE FUNCTION "public"."prevent_inventory_ledger_mutation"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
begin
  if current_setting('inventory.engine_write', true) is distinct from '1' then
    raise exception 'inventory ledger is immutable';
  end if;
  if tg_op = 'DELETE' then
    raise exception 'inventory ledger rows cannot be deleted';
  end if;
  if tg_op = 'UPDATE' then
    raise exception 'inventory ledger rows cannot be updated';
  end if;
  return new;
end;
$$;

CREATE OR REPLACE FUNCTION "public"."prevent_inventory_projection_client_write"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
begin
  if current_setting('inventory.engine_write', true) is distinct from '1' then
    raise exception 'inventory stock/cost state is engine-managed only';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

CREATE OR REPLACE FUNCTION "public"."prevent_posted_inventory_line_mutation"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
declare
  v_status public.inventory_operation_status;
begin
  if current_setting('inventory.engine_write', true) = '1' then
    return case when tg_op = 'DELETE' then old else new end;
  end if;
  select status into v_status
  from public.inventory_operations
  where id = coalesce(new.inventory_operation_id, old.inventory_operation_id);
  if v_status in ('POSTED', 'REVERSED') then
    raise exception 'cannot mutate lines of posted/reversed inventory operation';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

CREATE OR REPLACE FUNCTION "public"."prevent_posted_inventory_op_mutation"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
begin
  if current_setting('inventory.engine_write', true) = '1' then
    return case when tg_op = 'DELETE' then old else new end;
  end if;
  if tg_op = 'DELETE' then
    if old.status in ('POSTED', 'REVERSED') then
      raise exception 'cannot delete posted/reversed inventory operation';
    end if;
    return old;
  end if;
  if old.status in ('POSTED', 'REVERSED') then
    raise exception 'cannot mutate posted/reversed inventory operation';
  end if;
  if new.status is distinct from old.status
     or new.journal_entry_id is distinct from old.journal_entry_id
     or new.accounting_status is distinct from old.accounting_status then
    raise exception 'status/journal changes require inventory engine';
  end if;
  return new;
end;
$$;

CREATE OR REPLACE FUNCTION "public"."prevent_reservation_client_mutate"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
begin
  if current_setting('inventory.engine_write', true) is distinct from '1' then
    -- Allow insert of ACTIVE draft reservations only via RPC (also engine)
    raise exception 'inventory reservations require inventory engine';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

CREATE OR REPLACE FUNCTION "public"."purchase_line_inventory_debit_account"("p_organization_id" "uuid", "p_product_id" "uuid", "p_fallback_expense" "uuid") RETURNS "uuid"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_type public.product_type;
  v_clearing uuid;
begin
  if p_product_id is null then
    return p_fallback_expense;
  end if;
  select product_type into v_type
  from public.products
  where id = p_product_id and organization_id = p_organization_id;
  if v_type is distinct from 'STOCK_ITEM' then
    return p_fallback_expense;
  end if;
  select inventory_purchase_clearing_account_id into v_clearing
  from public.inventory_accounting_mappings
  where organization_id = p_organization_id;
  if v_clearing is null then
    raise exception 'STOCK_ITEM line requires inventory purchase clearing mapping';
  end if;
  return v_clearing;
end;
$$;

CREATE OR REPLACE FUNCTION "public"."release_inventory_reservation"("p_reservation_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_uid uuid := auth.uid();
  v_res public.inventory_reservations%rowtype;
  v_remain numeric(18,4);
begin
  if v_uid is null then raise exception 'authentication required'; end if;

  perform set_config('inventory.engine_write', '1', true);
  select * into v_res from public.inventory_reservations where id = p_reservation_id for update;
  if not found then raise exception 'reservation not found'; end if;
  if not public.is_org_member(v_res.organization_id) then raise exception 'not a member'; end if;
  perform public.inventory_assert_feature(v_res.organization_id);
  if v_res.status is distinct from 'ACTIVE' then return; end if;

  v_remain := v_res.quantity_reserved - v_res.quantity_consumed;
  update public.inventory_stock_state
  set reserved_quantity = reserved_quantity - v_remain,
      updated_at = timezone('utc', now())
  where organization_id = v_res.organization_id
    and warehouse_id = v_res.warehouse_id
    and product_id = v_res.product_id;

  update public.inventory_reservations
  set status = 'RELEASED', updated_at = timezone('utc', now())
  where id = p_reservation_id;
end;
$$;

CREATE OR REPLACE FUNCTION "public"."reverse_inventory_operation"("p_operation_id" "uuid", "p_reversal_date" "date", "p_reason" "text") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_uid uuid := auth.uid();
  v_op public.inventory_operations%rowtype;
  v_line record;
  v_later int;
  v_rev_id uuid;
  v_num text;
  v_cost public.inventory_cost_state%rowtype;
  v_q1 numeric(18,4);
  v_v1 numeric(19,4);
  v_avg numeric(19,6);
  v_rev_line_no int := 0;
  v_new_line uuid;
  v_sum_wh numeric(18,4);
  v_prod uuid;
  v_period_id uuid;
  v_rev_journal uuid;
begin
  if v_uid is null then raise exception 'authentication required'; end if;
  if p_reason is null or length(btrim(p_reason)) < 3 then
    raise exception 'reversal reason required';
  end if;

  select * into v_op from public.inventory_operations where id = p_operation_id for update;
  if not found then raise exception 'operation not found'; end if;
  if v_op.status is distinct from 'POSTED' then
    raise exception 'only POSTED operations can be reversed';
  end if;

  perform public.inventory_assert_feature(v_op.organization_id);
  if not public.has_org_role(
    v_op.organization_id, array['owner','admin','accountant']::public.member_role[]
  ) then
    raise exception 'insufficient role to reverse';
  end if;

  select period_id into v_period_id
  from public.resolve_open_period(v_op.organization_id, p_reversal_date);
  if v_period_id is null then
    raise exception 'ACCOUNTING_REQUIRES_REVIEW: accounting period is closed';
  end if;

  -- Receipt reversal safety: no later valuation movements for product
  if v_op.operation_type = 'RECEIPT' then
    for v_prod in
      select distinct product_id from public.inventory_operation_lines
      where inventory_operation_id = p_operation_id order by 1
    loop
      select count(*) into v_later
      from public.inventory_ledger_entries le
      where le.organization_id = v_op.organization_id
        and le.product_id = v_prod
        and le.inventory_operation_id is distinct from p_operation_id
        and (
          le.movement_date > v_op.operation_date
          or (le.movement_date = v_op.operation_date and le.created_at > (
            select posted_at from public.inventory_operations where id = p_operation_id
          ))
        )
        and le.operation_type in (
          'RECEIPT','ISSUE','RETURN_TO_SUPPLIER','ADJUSTMENT_IN','ADJUSTMENT_OUT'
        );
      if v_later > 0 then
        raise exception 'INVENTORY_REQUIRES_REVIEW: receipt reversal unsafe after later valuation movements';
      end if;
    end loop;
  end if;

  perform set_config('inventory.engine_write', '1', true);

  v_num := public.next_inventory_operation_number(v_op.organization_id, 'REVERSAL');

  insert into public.inventory_operations (
    organization_id, internal_number, operation_type, status, accounting_status,
    operation_date, warehouse_id, destination_warehouse_id, counterparty_id,
    reversed_operation_id, reason, description, idempotency_key, created_by
  ) values (
    v_op.organization_id, v_num, 'REVERSAL', 'DRAFT', 'PENDING',
    p_reversal_date, v_op.warehouse_id, v_op.destination_warehouse_id, v_op.counterparty_id,
    p_operation_id, p_reason, 'Reversión de ' || v_op.internal_number,
    'rev-' || p_operation_id::text, v_uid
  )
  returning id into v_rev_id;

  -- Lock products
  for v_prod in
    select distinct product_id from public.inventory_operation_lines
    where inventory_operation_id = p_operation_id order by 1
  loop
    perform public.ensure_inventory_cost_row(v_op.organization_id, v_prod);
    perform 1 from public.inventory_cost_state
    where organization_id = v_op.organization_id and product_id = v_prod for update;
  end loop;

  for v_line in
    select * from public.inventory_operation_lines
    where inventory_operation_id = p_operation_id
    order by line_number
  loop
    perform public.ensure_inventory_stock_row(v_op.organization_id, v_line.warehouse_id, v_line.product_id);
    perform 1 from public.inventory_stock_state
    where organization_id = v_op.organization_id
      and warehouse_id = v_line.warehouse_id and product_id = v_line.product_id
    for update;

    select * into v_cost from public.inventory_cost_state
    where organization_id = v_op.organization_id and product_id = v_line.product_id;

    v_rev_line_no := v_rev_line_no + 1;

    if v_line.direction = 'IN' then
      -- reverse IN => OUT at original cost
      if exists (
        select 1 from public.inventory_stock_state
        where organization_id = v_op.organization_id
          and warehouse_id = v_line.warehouse_id and product_id = v_line.product_id
          and on_hand_quantity < v_line.quantity
      ) then
        raise exception 'INVENTORY_REQUIRES_REVIEW: cannot reverse IN — stock consumed';
      end if;

      v_q1 := v_cost.quantity_on_hand_total - v_line.quantity;
      v_v1 := v_cost.inventory_value - v_line.value_delta;
      if v_q1 = 0 then v_v1 := 0; v_avg := 0;
      else v_avg := public.inventory_round_avg(v_v1, v_q1); end if;

      if v_op.operation_type is distinct from 'TRANSFER' then
        update public.inventory_cost_state
        set quantity_on_hand_total = v_q1, inventory_value = v_v1, average_unit_cost = v_avg,
            updated_at = timezone('utc', now())
        where organization_id = v_op.organization_id and product_id = v_line.product_id;
      end if;

      update public.inventory_stock_state
      set on_hand_quantity = on_hand_quantity - v_line.quantity, updated_at = timezone('utc', now())
      where organization_id = v_op.organization_id
        and warehouse_id = v_line.warehouse_id and product_id = v_line.product_id
        and on_hand_quantity >= v_line.quantity;

      insert into public.inventory_operation_lines (
        organization_id, inventory_operation_id, line_number, product_id, warehouse_id,
        direction, quantity, unit_code, unit_cost, value_delta
      ) values (
        v_op.organization_id, v_rev_id, v_rev_line_no, v_line.product_id, v_line.warehouse_id,
        'OUT', v_line.quantity, v_line.unit_code, v_line.unit_cost, v_line.value_delta
      ) returning id into v_new_line;

      insert into public.inventory_ledger_entries (
        organization_id, inventory_operation_id, inventory_operation_line_id,
        product_id, warehouse_id, movement_date, operation_type, direction,
        quantity, unit_cost, value_delta, source_type, source_id
      ) values (
        v_op.organization_id, v_rev_id, v_new_line,
        v_line.product_id, v_line.warehouse_id, p_reversal_date, 'REVERSAL', 'OUT',
        v_line.quantity, v_line.unit_cost, v_line.value_delta, 'INVENTORY_OPERATION', v_rev_id
      );

    else
      -- reverse OUT => IN at original snapshotted cost
      v_q1 := v_cost.quantity_on_hand_total + v_line.quantity;
      v_v1 := v_cost.inventory_value + v_line.value_delta;
      v_avg := public.inventory_round_avg(v_v1, v_q1);

      if v_op.operation_type is distinct from 'TRANSFER' then
        update public.inventory_cost_state
        set quantity_on_hand_total = v_q1, inventory_value = v_v1, average_unit_cost = v_avg,
            updated_at = timezone('utc', now())
        where organization_id = v_op.organization_id and product_id = v_line.product_id;
      end if;

      update public.inventory_stock_state
      set on_hand_quantity = on_hand_quantity + v_line.quantity, updated_at = timezone('utc', now())
      where organization_id = v_op.organization_id
        and warehouse_id = v_line.warehouse_id and product_id = v_line.product_id;

      insert into public.inventory_operation_lines (
        organization_id, inventory_operation_id, line_number, product_id, warehouse_id,
        direction, quantity, unit_code, unit_cost, value_delta
      ) values (
        v_op.organization_id, v_rev_id, v_rev_line_no, v_line.product_id, v_line.warehouse_id,
        'IN', v_line.quantity, v_line.unit_code, v_line.unit_cost, v_line.value_delta
      ) returning id into v_new_line;

      insert into public.inventory_ledger_entries (
        organization_id, inventory_operation_id, inventory_operation_line_id,
        product_id, warehouse_id, movement_date, operation_type, direction,
        quantity, unit_cost, value_delta, source_type, source_id
      ) values (
        v_op.organization_id, v_rev_id, v_new_line,
        v_line.product_id, v_line.warehouse_id, p_reversal_date, 'REVERSAL', 'IN',
        v_line.quantity, v_line.unit_cost, v_line.value_delta, 'INVENTORY_OPERATION', v_rev_id
      );
    end if;
  end loop;

  for v_prod in
    select distinct product_id from public.inventory_operation_lines
    where inventory_operation_id = p_operation_id order by 1
  loop
    select coalesce(sum(on_hand_quantity),0) into v_sum_wh
    from public.inventory_stock_state
    where organization_id = v_op.organization_id and product_id = v_prod;
    select quantity_on_hand_total into v_q1 from public.inventory_cost_state
    where organization_id = v_op.organization_id and product_id = v_prod;
    if v_op.operation_type is distinct from 'TRANSFER' and v_sum_wh is distinct from v_q1 then
      raise exception 'reversal reconciliation failed';
    end if;
  end loop;

  -- Accounting reverse
  if v_op.journal_entry_id is not null then
    v_rev_journal := (public.reverse_journal_entry(v_op.journal_entry_id, p_reversal_date, p_reason)).id;
  end if;

  update public.inventory_operations
  set status = 'POSTED',
      accounting_status = case when v_op.journal_entry_id is null then 'NOT_APPLICABLE' else 'POSTED' end,
      journal_entry_id = v_rev_journal,
      posted_by = v_uid, posted_at = timezone('utc', now()),
      updated_at = timezone('utc', now())
  where id = v_rev_id;

  update public.inventory_operations
  set status = 'REVERSED',
      reverse_journal_entry_id = v_rev_journal,
      reversed_by = v_uid,
      reversed_at = timezone('utc', now()),
      updated_at = timezone('utc', now())
  where id = p_operation_id;

  return v_rev_id;
end;
$$;

CREATE INDEX "inventory_ledger_line_idx" ON "public"."inventory_ledger_entries" USING "btree" ("inventory_operation_line_id");

CREATE INDEX "inventory_ledger_operation_idx" ON "public"."inventory_ledger_entries" USING "btree" ("inventory_operation_id");

CREATE INDEX "inventory_ledger_org_line_idx" ON "public"."inventory_ledger_entries" USING "btree" ("organization_id", "inventory_operation_line_id");

CREATE INDEX "inventory_ledger_org_op_idx" ON "public"."inventory_ledger_entries" USING "btree" ("organization_id", "inventory_operation_id");

CREATE INDEX "inventory_ledger_org_product_date_idx" ON "public"."inventory_ledger_entries" USING "btree" ("organization_id", "product_id", "movement_date");

CREATE INDEX "inventory_ledger_org_wh_product_date_idx" ON "public"."inventory_ledger_entries" USING "btree" ("organization_id", "warehouse_id", "product_id", "movement_date");

CREATE INDEX "inventory_map_asset_idx" ON "public"."inventory_accounting_mappings" USING "btree" ("inventory_asset_account_id");

CREATE INDEX "inventory_map_clearing_idx" ON "public"."inventory_accounting_mappings" USING "btree" ("inventory_purchase_clearing_account_id");

CREATE INDEX "inventory_map_cogs_idx" ON "public"."inventory_accounting_mappings" USING "btree" ("cogs_account_id");

CREATE INDEX "inventory_map_gain_idx" ON "public"."inventory_accounting_mappings" USING "btree" ("adjustment_gain_account_id");

CREATE INDEX "inventory_map_loss_idx" ON "public"."inventory_accounting_mappings" USING "btree" ("adjustment_loss_account_id");

CREATE INDEX "inventory_map_org_asset_idx" ON "public"."inventory_accounting_mappings" USING "btree" ("organization_id", "inventory_asset_account_id");

CREATE INDEX "inventory_map_org_clearing_idx" ON "public"."inventory_accounting_mappings" USING "btree" ("organization_id", "inventory_purchase_clearing_account_id");

CREATE INDEX "inventory_map_org_cogs_idx" ON "public"."inventory_accounting_mappings" USING "btree" ("organization_id", "cogs_account_id");

CREATE INDEX "inventory_map_org_gain_idx" ON "public"."inventory_accounting_mappings" USING "btree" ("organization_id", "adjustment_gain_account_id");

CREATE INDEX "inventory_map_org_loss_idx" ON "public"."inventory_accounting_mappings" USING "btree" ("organization_id", "adjustment_loss_account_id");

CREATE INDEX "inventory_operation_lines_org_op_idx" ON "public"."inventory_operation_lines" USING "btree" ("organization_id", "inventory_operation_id");

CREATE INDEX "inventory_operation_lines_org_product_idx" ON "public"."inventory_operation_lines" USING "btree" ("organization_id", "product_id");

CREATE INDEX "inventory_operation_lines_org_wh_product_idx" ON "public"."inventory_operation_lines" USING "btree" ("organization_id", "warehouse_id", "product_id");

CREATE INDEX "inventory_operation_lines_purchase_line_idx" ON "public"."inventory_operation_lines" USING "btree" ("source_purchase_line_id") WHERE ("source_purchase_line_id" IS NOT NULL);

CREATE INDEX "inventory_operation_lines_reservation_idx" ON "public"."inventory_operation_lines" USING "btree" ("reservation_id") WHERE ("reservation_id" IS NOT NULL);

CREATE INDEX "inventory_operation_lines_sales_line_idx" ON "public"."inventory_operation_lines" USING "btree" ("source_sales_line_id") WHERE ("source_sales_line_id" IS NOT NULL);

CREATE INDEX "inventory_operations_created_by_idx" ON "public"."inventory_operations" USING "btree" ("created_by") WHERE ("created_by" IS NOT NULL);

CREATE INDEX "inventory_operations_journal_idx" ON "public"."inventory_operations" USING "btree" ("journal_entry_id") WHERE ("journal_entry_id" IS NOT NULL);

CREATE INDEX "inventory_operations_org_cp_idx" ON "public"."inventory_operations" USING "btree" ("organization_id", "counterparty_id") WHERE ("counterparty_id" IS NOT NULL);

CREATE INDEX "inventory_operations_org_date_idx" ON "public"."inventory_operations" USING "btree" ("organization_id", "operation_date" DESC);

CREATE INDEX "inventory_operations_org_dest_wh_idx" ON "public"."inventory_operations" USING "btree" ("organization_id", "destination_warehouse_id") WHERE ("destination_warehouse_id" IS NOT NULL);

CREATE INDEX "inventory_operations_org_status_idx" ON "public"."inventory_operations" USING "btree" ("organization_id", "status");

CREATE INDEX "inventory_operations_org_type_date_idx" ON "public"."inventory_operations" USING "btree" ("organization_id", "operation_type", "operation_date" DESC);

CREATE INDEX "inventory_operations_org_wh_idx" ON "public"."inventory_operations" USING "btree" ("organization_id", "warehouse_id");

CREATE INDEX "inventory_operations_po_idx" ON "public"."inventory_operations" USING "btree" ("source_purchase_order_id") WHERE ("source_purchase_order_id" IS NOT NULL);

CREATE INDEX "inventory_operations_posted_by_idx" ON "public"."inventory_operations" USING "btree" ("posted_by") WHERE ("posted_by" IS NOT NULL);

CREATE INDEX "inventory_operations_purchase_idx" ON "public"."inventory_operations" USING "btree" ("source_purchase_document_id") WHERE ("source_purchase_document_id" IS NOT NULL);

CREATE INDEX "inventory_operations_receipt_idx" ON "public"."inventory_operations" USING "btree" ("source_receipt_operation_id") WHERE ("source_receipt_operation_id" IS NOT NULL);

CREATE INDEX "inventory_operations_rev_journal_idx" ON "public"."inventory_operations" USING "btree" ("reverse_journal_entry_id") WHERE ("reverse_journal_entry_id" IS NOT NULL);

CREATE INDEX "inventory_operations_reversed_by_idx" ON "public"."inventory_operations" USING "btree" ("reversed_by") WHERE ("reversed_by" IS NOT NULL);

CREATE INDEX "inventory_operations_reversed_op_idx" ON "public"."inventory_operations" USING "btree" ("reversed_operation_id") WHERE ("reversed_operation_id" IS NOT NULL);

CREATE INDEX "inventory_operations_sales_idx" ON "public"."inventory_operations" USING "btree" ("source_sales_document_id") WHERE ("source_sales_document_id" IS NOT NULL);

CREATE UNIQUE INDEX "inventory_reservations_active_line_uidx" ON "public"."inventory_reservations" USING "btree" ("sales_document_line_id") WHERE ("status" = 'ACTIVE'::"public"."inventory_reservation_status");

CREATE INDEX "inventory_reservations_created_by_idx" ON "public"."inventory_reservations" USING "btree" ("created_by") WHERE ("created_by" IS NOT NULL);

CREATE INDEX "inventory_reservations_org_product_wh_status_idx" ON "public"."inventory_reservations" USING "btree" ("organization_id", "product_id", "warehouse_id", "status");

CREATE INDEX "inventory_reservations_org_wh_idx" ON "public"."inventory_reservations" USING "btree" ("organization_id", "warehouse_id");

CREATE INDEX "inventory_reservations_sales_idx" ON "public"."inventory_reservations" USING "btree" ("sales_document_id");

CREATE INDEX "inventory_reservations_sales_line_idx" ON "public"."inventory_reservations" USING "btree" ("sales_document_line_id");

CREATE INDEX "inventory_stock_state_org_product_idx" ON "public"."inventory_stock_state" USING "btree" ("organization_id", "product_id");

CREATE INDEX "inventory_stock_state_org_wh_idx" ON "public"."inventory_stock_state" USING "btree" ("organization_id", "warehouse_id");

CREATE INDEX "product_categories_org_active_idx" ON "public"."product_categories" USING "btree" ("organization_id", "active");

CREATE INDEX "product_categories_org_parent_idx" ON "public"."product_categories" USING "btree" ("organization_id", "parent_id") WHERE ("parent_id" IS NOT NULL);

CREATE INDEX "product_categories_parent_idx" ON "public"."product_categories" USING "btree" ("parent_id") WHERE ("parent_id" IS NOT NULL);

CREATE INDEX "products_category_idx" ON "public"."products" USING "btree" ("category_id") WHERE ("category_id" IS NOT NULL);

CREATE INDEX "products_created_by_idx" ON "public"."products" USING "btree" ("created_by") WHERE ("created_by" IS NOT NULL);

CREATE INDEX "products_org_active_type_idx" ON "public"."products" USING "btree" ("organization_id", "active", "product_type");

CREATE UNIQUE INDEX "products_org_barcode_uidx" ON "public"."products" USING "btree" ("organization_id", "barcode") WHERE ("barcode" IS NOT NULL);

CREATE INDEX "products_org_category_idx" ON "public"."products" USING "btree" ("organization_id", "category_id") WHERE ("category_id" IS NOT NULL);

CREATE INDEX "products_org_name_idx" ON "public"."products" USING "btree" ("organization_id", "name");

CREATE UNIQUE INDEX "products_org_sku_uidx" ON "public"."products" USING "btree" ("organization_id", "sku") WHERE ("sku" IS NOT NULL);

CREATE INDEX "warehouses_created_by_idx" ON "public"."warehouses" USING "btree" ("created_by") WHERE ("created_by" IS NOT NULL);

CREATE INDEX "warehouses_org_active_idx" ON "public"."warehouses" USING "btree" ("organization_id", "active");

CREATE INDEX "warehouses_org_branch_idx" ON "public"."warehouses" USING "btree" ("organization_id", "branch_id") WHERE ("branch_id" IS NOT NULL);

CREATE OR REPLACE TRIGGER "inventory_accounting_mappings_set_updated_at" BEFORE UPDATE ON "public"."inventory_accounting_mappings" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();

CREATE OR REPLACE TRIGGER "inventory_cost_state_engine_only" BEFORE INSERT OR DELETE OR UPDATE ON "public"."inventory_cost_state" FOR EACH ROW EXECUTE FUNCTION "public"."prevent_inventory_projection_client_write"();

CREATE OR REPLACE TRIGGER "inventory_ledger_no_update" BEFORE DELETE OR UPDATE ON "public"."inventory_ledger_entries" FOR EACH ROW EXECUTE FUNCTION "public"."prevent_inventory_ledger_mutation"();

CREATE OR REPLACE TRIGGER "inventory_operation_lines_posted_guard" BEFORE DELETE OR UPDATE ON "public"."inventory_operation_lines" FOR EACH ROW EXECUTE FUNCTION "public"."prevent_posted_inventory_line_mutation"();

CREATE OR REPLACE TRIGGER "inventory_operations_posted_guard" BEFORE DELETE OR UPDATE ON "public"."inventory_operations" FOR EACH ROW EXECUTE FUNCTION "public"."prevent_posted_inventory_op_mutation"();

CREATE OR REPLACE TRIGGER "inventory_operations_set_updated_at" BEFORE UPDATE ON "public"."inventory_operations" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();

CREATE OR REPLACE TRIGGER "inventory_reservations_engine_only" BEFORE INSERT OR DELETE OR UPDATE ON "public"."inventory_reservations" FOR EACH ROW EXECUTE FUNCTION "public"."prevent_reservation_client_mutate"();

CREATE OR REPLACE TRIGGER "inventory_reservations_set_updated_at" BEFORE UPDATE ON "public"."inventory_reservations" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();

CREATE OR REPLACE TRIGGER "inventory_stock_state_engine_only" BEFORE INSERT OR DELETE OR UPDATE ON "public"."inventory_stock_state" FOR EACH ROW EXECUTE FUNCTION "public"."prevent_inventory_projection_client_write"();

CREATE OR REPLACE TRIGGER "product_categories_set_updated_at" BEFORE UPDATE ON "public"."product_categories" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();

CREATE OR REPLACE TRIGGER "products_set_updated_at" BEFORE UPDATE ON "public"."products" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();

CREATE OR REPLACE TRIGGER "warehouses_set_updated_at" BEFORE UPDATE ON "public"."warehouses" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();

ALTER TABLE "public"."inventory_accounting_mappings" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."inventory_cost_state" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."inventory_ledger_entries" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."inventory_operation_lines" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."inventory_operation_sequences" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."inventory_operations" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."inventory_reservations" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."inventory_stock_state" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."product_categories" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."products" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."warehouses" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "inventory_cost_state_select" ON "public"."inventory_cost_state" FOR SELECT TO "authenticated" USING ("public"."is_org_member"("organization_id"));

CREATE POLICY "inventory_ledger_select" ON "public"."inventory_ledger_entries" FOR SELECT TO "authenticated" USING ("public"."is_org_member"("organization_id"));

CREATE POLICY "inventory_mappings_delete" ON "public"."inventory_accounting_mappings" FOR DELETE TO "authenticated" USING ("public"."has_org_role"("organization_id", ARRAY['owner'::"public"."member_role", 'admin'::"public"."member_role", 'accountant'::"public"."member_role"]));

CREATE POLICY "inventory_mappings_insert" ON "public"."inventory_accounting_mappings" FOR INSERT TO "authenticated" WITH CHECK ("public"."has_org_role"("organization_id", ARRAY['owner'::"public"."member_role", 'admin'::"public"."member_role", 'accountant'::"public"."member_role"]));

CREATE POLICY "inventory_mappings_select" ON "public"."inventory_accounting_mappings" FOR SELECT TO "authenticated" USING ("public"."is_org_member"("organization_id"));

CREATE POLICY "inventory_mappings_update" ON "public"."inventory_accounting_mappings" FOR UPDATE TO "authenticated" USING ("public"."has_org_role"("organization_id", ARRAY['owner'::"public"."member_role", 'admin'::"public"."member_role", 'accountant'::"public"."member_role"])) WITH CHECK ("public"."has_org_role"("organization_id", ARRAY['owner'::"public"."member_role", 'admin'::"public"."member_role", 'accountant'::"public"."member_role"]));

CREATE POLICY "inventory_operation_lines_delete" ON "public"."inventory_operation_lines" FOR DELETE TO "authenticated" USING ("public"."has_org_role"("organization_id", ARRAY['owner'::"public"."member_role", 'admin'::"public"."member_role", 'manager'::"public"."member_role", 'operator'::"public"."member_role", 'accountant'::"public"."member_role"]));

CREATE POLICY "inventory_operation_lines_insert" ON "public"."inventory_operation_lines" FOR INSERT TO "authenticated" WITH CHECK ("public"."has_org_role"("organization_id", ARRAY['owner'::"public"."member_role", 'admin'::"public"."member_role", 'manager'::"public"."member_role", 'operator'::"public"."member_role", 'accountant'::"public"."member_role"]));

CREATE POLICY "inventory_operation_lines_select" ON "public"."inventory_operation_lines" FOR SELECT TO "authenticated" USING ("public"."is_org_member"("organization_id"));

CREATE POLICY "inventory_operation_lines_update" ON "public"."inventory_operation_lines" FOR UPDATE TO "authenticated" USING ("public"."has_org_role"("organization_id", ARRAY['owner'::"public"."member_role", 'admin'::"public"."member_role", 'manager'::"public"."member_role", 'operator'::"public"."member_role", 'accountant'::"public"."member_role"])) WITH CHECK ("public"."has_org_role"("organization_id", ARRAY['owner'::"public"."member_role", 'admin'::"public"."member_role", 'manager'::"public"."member_role", 'operator'::"public"."member_role", 'accountant'::"public"."member_role"]));

CREATE POLICY "inventory_operations_insert" ON "public"."inventory_operations" FOR INSERT TO "authenticated" WITH CHECK ("public"."has_org_role"("organization_id", ARRAY['owner'::"public"."member_role", 'admin'::"public"."member_role", 'manager'::"public"."member_role", 'operator'::"public"."member_role", 'accountant'::"public"."member_role"]));

CREATE POLICY "inventory_operations_select" ON "public"."inventory_operations" FOR SELECT TO "authenticated" USING ("public"."is_org_member"("organization_id"));

CREATE POLICY "inventory_operations_update" ON "public"."inventory_operations" FOR UPDATE TO "authenticated" USING ("public"."has_org_role"("organization_id", ARRAY['owner'::"public"."member_role", 'admin'::"public"."member_role", 'manager'::"public"."member_role", 'operator'::"public"."member_role", 'accountant'::"public"."member_role"])) WITH CHECK ("public"."has_org_role"("organization_id", ARRAY['owner'::"public"."member_role", 'admin'::"public"."member_role", 'manager'::"public"."member_role", 'operator'::"public"."member_role", 'accountant'::"public"."member_role"]));

CREATE POLICY "inventory_reservations_select" ON "public"."inventory_reservations" FOR SELECT TO "authenticated" USING ("public"."is_org_member"("organization_id"));

CREATE POLICY "inventory_stock_state_select" ON "public"."inventory_stock_state" FOR SELECT TO "authenticated" USING ("public"."is_org_member"("organization_id"));

CREATE POLICY "product_categories_delete" ON "public"."product_categories" FOR DELETE TO "authenticated" USING ("public"."has_org_role"("organization_id", ARRAY['owner'::"public"."member_role", 'admin'::"public"."member_role", 'manager'::"public"."member_role", 'accountant'::"public"."member_role"]));

CREATE POLICY "product_categories_insert" ON "public"."product_categories" FOR INSERT TO "authenticated" WITH CHECK ("public"."has_org_role"("organization_id", ARRAY['owner'::"public"."member_role", 'admin'::"public"."member_role", 'manager'::"public"."member_role", 'accountant'::"public"."member_role"]));

CREATE POLICY "product_categories_select" ON "public"."product_categories" FOR SELECT TO "authenticated" USING ("public"."is_org_member"("organization_id"));

CREATE POLICY "product_categories_update" ON "public"."product_categories" FOR UPDATE TO "authenticated" USING ("public"."has_org_role"("organization_id", ARRAY['owner'::"public"."member_role", 'admin'::"public"."member_role", 'manager'::"public"."member_role", 'accountant'::"public"."member_role"])) WITH CHECK ("public"."has_org_role"("organization_id", ARRAY['owner'::"public"."member_role", 'admin'::"public"."member_role", 'manager'::"public"."member_role", 'accountant'::"public"."member_role"]));

CREATE POLICY "products_insert" ON "public"."products" FOR INSERT TO "authenticated" WITH CHECK ("public"."has_org_role"("organization_id", ARRAY['owner'::"public"."member_role", 'admin'::"public"."member_role", 'manager'::"public"."member_role", 'accountant'::"public"."member_role"]));

CREATE POLICY "products_select" ON "public"."products" FOR SELECT TO "authenticated" USING ("public"."is_org_member"("organization_id"));

CREATE POLICY "products_update" ON "public"."products" FOR UPDATE TO "authenticated" USING ("public"."has_org_role"("organization_id", ARRAY['owner'::"public"."member_role", 'admin'::"public"."member_role", 'manager'::"public"."member_role", 'accountant'::"public"."member_role"])) WITH CHECK ("public"."has_org_role"("organization_id", ARRAY['owner'::"public"."member_role", 'admin'::"public"."member_role", 'manager'::"public"."member_role", 'accountant'::"public"."member_role"]));

CREATE POLICY "warehouses_delete" ON "public"."warehouses" FOR DELETE TO "authenticated" USING ("public"."has_org_role"("organization_id", ARRAY['owner'::"public"."member_role", 'admin'::"public"."member_role", 'manager'::"public"."member_role", 'accountant'::"public"."member_role"]));

CREATE POLICY "warehouses_insert" ON "public"."warehouses" FOR INSERT TO "authenticated" WITH CHECK ("public"."has_org_role"("organization_id", ARRAY['owner'::"public"."member_role", 'admin'::"public"."member_role", 'manager'::"public"."member_role", 'accountant'::"public"."member_role"]));

CREATE POLICY "warehouses_select" ON "public"."warehouses" FOR SELECT TO "authenticated" USING ("public"."is_org_member"("organization_id"));

CREATE POLICY "warehouses_update" ON "public"."warehouses" FOR UPDATE TO "authenticated" USING ("public"."has_org_role"("organization_id", ARRAY['owner'::"public"."member_role", 'admin'::"public"."member_role", 'manager'::"public"."member_role", 'accountant'::"public"."member_role"])) WITH CHECK ("public"."has_org_role"("organization_id", ARRAY['owner'::"public"."member_role", 'admin'::"public"."member_role", 'manager'::"public"."member_role", 'accountant'::"public"."member_role"]));

REVOKE ALL ON FUNCTION "public"."create_inventory_reservation"("p_organization_id" "uuid", "p_product_id" "uuid", "p_warehouse_id" "uuid", "p_sales_document_id" "uuid", "p_sales_document_line_id" "uuid", "p_quantity" numeric, "p_idempotency_key" "text") FROM PUBLIC;

GRANT ALL ON FUNCTION "public"."create_inventory_reservation"("p_organization_id" "uuid", "p_product_id" "uuid", "p_warehouse_id" "uuid", "p_sales_document_id" "uuid", "p_sales_document_line_id" "uuid", "p_quantity" numeric, "p_idempotency_key" "text") TO "authenticated";

GRANT ALL ON FUNCTION "public"."create_inventory_reservation"("p_organization_id" "uuid", "p_product_id" "uuid", "p_warehouse_id" "uuid", "p_sales_document_id" "uuid", "p_sales_document_line_id" "uuid", "p_quantity" numeric, "p_idempotency_key" "text") TO "service_role";

REVOKE ALL ON FUNCTION "public"."deactivate_product"("p_product_id" "uuid") FROM PUBLIC;

GRANT ALL ON FUNCTION "public"."deactivate_product"("p_product_id" "uuid") TO "authenticated";

GRANT ALL ON FUNCTION "public"."deactivate_product"("p_product_id" "uuid") TO "service_role";

REVOKE ALL ON FUNCTION "public"."ensure_inventory_chart_accounts"("p_org_id" "uuid") FROM PUBLIC;

GRANT ALL ON FUNCTION "public"."ensure_inventory_chart_accounts"("p_org_id" "uuid") TO "authenticated";

GRANT ALL ON FUNCTION "public"."ensure_inventory_chart_accounts"("p_org_id" "uuid") TO "service_role";

REVOKE ALL ON FUNCTION "public"."ensure_inventory_cost_row"("p_org" "uuid", "p_product" "uuid") FROM PUBLIC;

GRANT ALL ON FUNCTION "public"."ensure_inventory_cost_row"("p_org" "uuid", "p_product" "uuid") TO "service_role";

REVOKE ALL ON FUNCTION "public"."ensure_inventory_stock_row"("p_org" "uuid", "p_wh" "uuid", "p_product" "uuid") FROM PUBLIC;

GRANT ALL ON FUNCTION "public"."ensure_inventory_stock_row"("p_org" "uuid", "p_wh" "uuid", "p_product" "uuid") TO "service_role";

REVOKE ALL ON FUNCTION "public"."inventory_assert_feature"("p_org_id" "uuid") FROM PUBLIC;

GRANT ALL ON FUNCTION "public"."inventory_assert_feature"("p_org_id" "uuid") TO "service_role";

REVOKE ALL ON FUNCTION "public"."inventory_round_avg"("p_value" numeric, "p_qty" numeric) FROM PUBLIC;

GRANT ALL ON FUNCTION "public"."inventory_round_avg"("p_value" numeric, "p_qty" numeric) TO "authenticated";

GRANT ALL ON FUNCTION "public"."inventory_round_avg"("p_value" numeric, "p_qty" numeric) TO "service_role";

REVOKE ALL ON FUNCTION "public"."inventory_round_value"("p_qty" numeric, "p_unit_cost" numeric) FROM PUBLIC;

GRANT ALL ON FUNCTION "public"."inventory_round_value"("p_qty" numeric, "p_unit_cost" numeric) TO "authenticated";

GRANT ALL ON FUNCTION "public"."inventory_round_value"("p_qty" numeric, "p_unit_cost" numeric) TO "service_role";

REVOKE ALL ON FUNCTION "public"."next_inventory_operation_number"("p_org_id" "uuid", "p_operation_type" "public"."inventory_operation_type") FROM PUBLIC;

GRANT ALL ON FUNCTION "public"."next_inventory_operation_number"("p_org_id" "uuid", "p_operation_type" "public"."inventory_operation_type") TO "authenticated";

GRANT ALL ON FUNCTION "public"."next_inventory_operation_number"("p_org_id" "uuid", "p_operation_type" "public"."inventory_operation_type") TO "service_role";

REVOKE ALL ON FUNCTION "public"."post_inventory_operation"("p_operation_id" "uuid") FROM PUBLIC;

GRANT ALL ON FUNCTION "public"."post_inventory_operation"("p_operation_id" "uuid") TO "authenticated";

GRANT ALL ON FUNCTION "public"."post_inventory_operation"("p_operation_id" "uuid") TO "service_role";

GRANT ALL ON FUNCTION "public"."prevent_inventory_ledger_mutation"() TO "anon";

GRANT ALL ON FUNCTION "public"."prevent_inventory_ledger_mutation"() TO "authenticated";

GRANT ALL ON FUNCTION "public"."prevent_inventory_ledger_mutation"() TO "service_role";

GRANT ALL ON FUNCTION "public"."prevent_inventory_projection_client_write"() TO "anon";

GRANT ALL ON FUNCTION "public"."prevent_inventory_projection_client_write"() TO "authenticated";

GRANT ALL ON FUNCTION "public"."prevent_inventory_projection_client_write"() TO "service_role";

GRANT ALL ON FUNCTION "public"."prevent_posted_inventory_line_mutation"() TO "anon";

GRANT ALL ON FUNCTION "public"."prevent_posted_inventory_line_mutation"() TO "authenticated";

GRANT ALL ON FUNCTION "public"."prevent_posted_inventory_line_mutation"() TO "service_role";

GRANT ALL ON FUNCTION "public"."prevent_posted_inventory_op_mutation"() TO "anon";

GRANT ALL ON FUNCTION "public"."prevent_posted_inventory_op_mutation"() TO "authenticated";

GRANT ALL ON FUNCTION "public"."prevent_posted_inventory_op_mutation"() TO "service_role";

GRANT ALL ON FUNCTION "public"."prevent_reservation_client_mutate"() TO "anon";

GRANT ALL ON FUNCTION "public"."prevent_reservation_client_mutate"() TO "authenticated";

GRANT ALL ON FUNCTION "public"."prevent_reservation_client_mutate"() TO "service_role";

REVOKE ALL ON FUNCTION "public"."purchase_line_inventory_debit_account"("p_organization_id" "uuid", "p_product_id" "uuid", "p_fallback_expense" "uuid") FROM PUBLIC;

GRANT ALL ON FUNCTION "public"."purchase_line_inventory_debit_account"("p_organization_id" "uuid", "p_product_id" "uuid", "p_fallback_expense" "uuid") TO "service_role";

REVOKE ALL ON FUNCTION "public"."release_inventory_reservation"("p_reservation_id" "uuid") FROM PUBLIC;

GRANT ALL ON FUNCTION "public"."release_inventory_reservation"("p_reservation_id" "uuid") TO "authenticated";

GRANT ALL ON FUNCTION "public"."release_inventory_reservation"("p_reservation_id" "uuid") TO "service_role";

REVOKE ALL ON FUNCTION "public"."reverse_inventory_operation"("p_operation_id" "uuid", "p_reversal_date" "date", "p_reason" "text") FROM PUBLIC;

GRANT ALL ON FUNCTION "public"."reverse_inventory_operation"("p_operation_id" "uuid", "p_reversal_date" "date", "p_reason" "text") TO "authenticated";

GRANT ALL ON FUNCTION "public"."reverse_inventory_operation"("p_operation_id" "uuid", "p_reversal_date" "date", "p_reason" "text") TO "service_role";

GRANT ALL ON TABLE "public"."inventory_accounting_mappings" TO "authenticated";

GRANT ALL ON TABLE "public"."inventory_accounting_mappings" TO "service_role";

GRANT ALL ON TABLE "public"."inventory_cost_state" TO "authenticated";

GRANT ALL ON TABLE "public"."inventory_cost_state" TO "service_role";

GRANT ALL ON TABLE "public"."inventory_ledger_entries" TO "authenticated";

GRANT ALL ON TABLE "public"."inventory_ledger_entries" TO "service_role";

GRANT ALL ON TABLE "public"."inventory_operation_lines" TO "authenticated";

GRANT ALL ON TABLE "public"."inventory_operation_lines" TO "service_role";

GRANT ALL ON TABLE "public"."inventory_operation_sequences" TO "service_role";

GRANT ALL ON TABLE "public"."inventory_operations" TO "authenticated";

GRANT ALL ON TABLE "public"."inventory_operations" TO "service_role";

GRANT ALL ON TABLE "public"."inventory_reservations" TO "authenticated";

GRANT ALL ON TABLE "public"."inventory_reservations" TO "service_role";

GRANT ALL ON TABLE "public"."inventory_stock_state" TO "authenticated";

GRANT ALL ON TABLE "public"."inventory_stock_state" TO "service_role";

GRANT ALL ON TABLE "public"."product_categories" TO "authenticated";

GRANT ALL ON TABLE "public"."product_categories" TO "service_role";

GRANT ALL ON TABLE "public"."products" TO "authenticated";

GRANT ALL ON TABLE "public"."products" TO "service_role";

GRANT ALL ON TABLE "public"."warehouses" TO "authenticated";

GRANT ALL ON TABLE "public"."warehouses" TO "service_role";

ALTER TABLE ONLY "public"."inventory_accounting_mappings"
    ADD CONSTRAINT "inventory_accounting_mappings_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."inventory_cost_state"
    ADD CONSTRAINT "inventory_cost_state_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."inventory_cost_state"
    ADD CONSTRAINT "inventory_cost_state_product_fk" FOREIGN KEY ("organization_id", "product_id") REFERENCES "public"."products"("organization_id", "id") ON DELETE RESTRICT;

ALTER TABLE ONLY "public"."inventory_ledger_entries"
    ADD CONSTRAINT "inventory_ledger_entries_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."inventory_ledger_entries"
    ADD CONSTRAINT "inventory_ledger_org_line_fk" FOREIGN KEY ("organization_id", "inventory_operation_line_id") REFERENCES "public"."inventory_operation_lines"("organization_id", "id") ON DELETE RESTRICT;

ALTER TABLE ONLY "public"."inventory_ledger_entries"
    ADD CONSTRAINT "inventory_ledger_org_op_fk" FOREIGN KEY ("organization_id", "inventory_operation_id") REFERENCES "public"."inventory_operations"("organization_id", "id") ON DELETE RESTRICT;

ALTER TABLE ONLY "public"."inventory_ledger_entries"
    ADD CONSTRAINT "inventory_ledger_product_fk" FOREIGN KEY ("organization_id", "product_id") REFERENCES "public"."products"("organization_id", "id") ON DELETE RESTRICT;

ALTER TABLE ONLY "public"."inventory_ledger_entries"
    ADD CONSTRAINT "inventory_ledger_wh_fk" FOREIGN KEY ("organization_id", "warehouse_id") REFERENCES "public"."warehouses"("organization_id", "id") ON DELETE RESTRICT;

ALTER TABLE ONLY "public"."inventory_accounting_mappings"
    ADD CONSTRAINT "inventory_map_asset_fk" FOREIGN KEY ("organization_id", "inventory_asset_account_id") REFERENCES "public"."accounts"("organization_id", "id") ON DELETE RESTRICT;

ALTER TABLE ONLY "public"."inventory_accounting_mappings"
    ADD CONSTRAINT "inventory_map_clearing_fk" FOREIGN KEY ("organization_id", "inventory_purchase_clearing_account_id") REFERENCES "public"."accounts"("organization_id", "id") ON DELETE RESTRICT;

ALTER TABLE ONLY "public"."inventory_accounting_mappings"
    ADD CONSTRAINT "inventory_map_cogs_fk" FOREIGN KEY ("organization_id", "cogs_account_id") REFERENCES "public"."accounts"("organization_id", "id") ON DELETE RESTRICT;

ALTER TABLE ONLY "public"."inventory_accounting_mappings"
    ADD CONSTRAINT "inventory_map_gain_fk" FOREIGN KEY ("organization_id", "adjustment_gain_account_id") REFERENCES "public"."accounts"("organization_id", "id") ON DELETE RESTRICT;

ALTER TABLE ONLY "public"."inventory_accounting_mappings"
    ADD CONSTRAINT "inventory_map_loss_fk" FOREIGN KEY ("organization_id", "adjustment_loss_account_id") REFERENCES "public"."accounts"("organization_id", "id") ON DELETE RESTRICT;

ALTER TABLE ONLY "public"."inventory_operation_lines"
    ADD CONSTRAINT "inventory_operation_lines_org_op_fk" FOREIGN KEY ("organization_id", "inventory_operation_id") REFERENCES "public"."inventory_operations"("organization_id", "id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."inventory_operation_lines"
    ADD CONSTRAINT "inventory_operation_lines_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."inventory_operation_lines"
    ADD CONSTRAINT "inventory_operation_lines_product_fk" FOREIGN KEY ("organization_id", "product_id") REFERENCES "public"."products"("organization_id", "id") ON DELETE RESTRICT;

ALTER TABLE ONLY "public"."inventory_operation_lines"
    ADD CONSTRAINT "inventory_operation_lines_purchase_line_fk" FOREIGN KEY ("source_purchase_line_id") REFERENCES "public"."purchase_document_lines"("id") ON DELETE RESTRICT;

ALTER TABLE ONLY "public"."inventory_operation_lines"
    ADD CONSTRAINT "inventory_operation_lines_reservation_fk" FOREIGN KEY ("reservation_id") REFERENCES "public"."inventory_reservations"("id") ON DELETE RESTRICT;

ALTER TABLE ONLY "public"."inventory_operation_lines"
    ADD CONSTRAINT "inventory_operation_lines_sales_line_fk" FOREIGN KEY ("source_sales_line_id") REFERENCES "public"."sales_document_lines"("id") ON DELETE RESTRICT;

ALTER TABLE ONLY "public"."inventory_operation_lines"
    ADD CONSTRAINT "inventory_operation_lines_wh_fk" FOREIGN KEY ("organization_id", "warehouse_id") REFERENCES "public"."warehouses"("organization_id", "id") ON DELETE RESTRICT;

ALTER TABLE ONLY "public"."inventory_operation_sequences"
    ADD CONSTRAINT "inventory_operation_sequences_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."inventory_operations"
    ADD CONSTRAINT "inventory_operations_cp_fk" FOREIGN KEY ("organization_id", "counterparty_id") REFERENCES "public"."counterparties"("organization_id", "id") ON DELETE RESTRICT;

ALTER TABLE ONLY "public"."inventory_operations"
    ADD CONSTRAINT "inventory_operations_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id");

ALTER TABLE ONLY "public"."inventory_operations"
    ADD CONSTRAINT "inventory_operations_dest_wh_fk" FOREIGN KEY ("organization_id", "destination_warehouse_id") REFERENCES "public"."warehouses"("organization_id", "id") ON DELETE RESTRICT;

ALTER TABLE ONLY "public"."inventory_operations"
    ADD CONSTRAINT "inventory_operations_journal_fk" FOREIGN KEY ("journal_entry_id") REFERENCES "public"."journal_entries"("id") ON DELETE RESTRICT;

ALTER TABLE ONLY "public"."inventory_operations"
    ADD CONSTRAINT "inventory_operations_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."inventory_operations"
    ADD CONSTRAINT "inventory_operations_pd_fk" FOREIGN KEY ("source_purchase_document_id") REFERENCES "public"."purchase_documents"("id") ON DELETE RESTRICT;

ALTER TABLE ONLY "public"."inventory_operations"
    ADD CONSTRAINT "inventory_operations_po_fk" FOREIGN KEY ("source_purchase_order_id") REFERENCES "public"."purchase_orders"("id") ON DELETE RESTRICT;

ALTER TABLE ONLY "public"."inventory_operations"
    ADD CONSTRAINT "inventory_operations_posted_by_fkey" FOREIGN KEY ("posted_by") REFERENCES "auth"."users"("id");

ALTER TABLE ONLY "public"."inventory_operations"
    ADD CONSTRAINT "inventory_operations_receipt_fk" FOREIGN KEY ("source_receipt_operation_id") REFERENCES "public"."inventory_operations"("id") ON DELETE RESTRICT;

ALTER TABLE ONLY "public"."inventory_operations"
    ADD CONSTRAINT "inventory_operations_rev_journal_fk" FOREIGN KEY ("reverse_journal_entry_id") REFERENCES "public"."journal_entries"("id") ON DELETE RESTRICT;

ALTER TABLE ONLY "public"."inventory_operations"
    ADD CONSTRAINT "inventory_operations_reversed_by_fkey" FOREIGN KEY ("reversed_by") REFERENCES "auth"."users"("id");

ALTER TABLE ONLY "public"."inventory_operations"
    ADD CONSTRAINT "inventory_operations_reversed_fk" FOREIGN KEY ("reversed_operation_id") REFERENCES "public"."inventory_operations"("id") ON DELETE RESTRICT;

ALTER TABLE ONLY "public"."inventory_operations"
    ADD CONSTRAINT "inventory_operations_sd_fk" FOREIGN KEY ("source_sales_document_id") REFERENCES "public"."sales_documents"("id") ON DELETE RESTRICT;

ALTER TABLE ONLY "public"."inventory_operations"
    ADD CONSTRAINT "inventory_operations_warehouse_fk" FOREIGN KEY ("organization_id", "warehouse_id") REFERENCES "public"."warehouses"("organization_id", "id") ON DELETE RESTRICT;

ALTER TABLE ONLY "public"."inventory_reservations"
    ADD CONSTRAINT "inventory_reservations_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id");

ALTER TABLE ONLY "public"."inventory_reservations"
    ADD CONSTRAINT "inventory_reservations_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."inventory_reservations"
    ADD CONSTRAINT "inventory_reservations_product_fk" FOREIGN KEY ("organization_id", "product_id") REFERENCES "public"."products"("organization_id", "id") ON DELETE RESTRICT;

ALTER TABLE ONLY "public"."inventory_reservations"
    ADD CONSTRAINT "inventory_reservations_sales_fk" FOREIGN KEY ("sales_document_id") REFERENCES "public"."sales_documents"("id") ON DELETE RESTRICT;

ALTER TABLE ONLY "public"."inventory_reservations"
    ADD CONSTRAINT "inventory_reservations_sales_line_fk" FOREIGN KEY ("sales_document_line_id") REFERENCES "public"."sales_document_lines"("id") ON DELETE RESTRICT;

ALTER TABLE ONLY "public"."inventory_reservations"
    ADD CONSTRAINT "inventory_reservations_wh_fk" FOREIGN KEY ("organization_id", "warehouse_id") REFERENCES "public"."warehouses"("organization_id", "id") ON DELETE RESTRICT;

ALTER TABLE ONLY "public"."inventory_stock_state"
    ADD CONSTRAINT "inventory_stock_state_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."inventory_stock_state"
    ADD CONSTRAINT "inventory_stock_state_product_fk" FOREIGN KEY ("organization_id", "product_id") REFERENCES "public"."products"("organization_id", "id") ON DELETE RESTRICT;

ALTER TABLE ONLY "public"."inventory_stock_state"
    ADD CONSTRAINT "inventory_stock_state_wh_fk" FOREIGN KEY ("organization_id", "warehouse_id") REFERENCES "public"."warehouses"("organization_id", "id") ON DELETE RESTRICT;

ALTER TABLE ONLY "public"."product_categories"
    ADD CONSTRAINT "product_categories_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."product_categories"
    ADD CONSTRAINT "product_categories_parent_fk" FOREIGN KEY ("organization_id", "parent_id") REFERENCES "public"."product_categories"("organization_id", "id") ON DELETE RESTRICT;

ALTER TABLE ONLY "public"."products"
    ADD CONSTRAINT "products_category_fk" FOREIGN KEY ("organization_id", "category_id") REFERENCES "public"."product_categories"("organization_id", "id") ON DELETE RESTRICT;

ALTER TABLE ONLY "public"."products"
    ADD CONSTRAINT "products_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id");

ALTER TABLE ONLY "public"."products"
    ADD CONSTRAINT "products_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."warehouses"
    ADD CONSTRAINT "warehouses_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id");

ALTER TABLE ONLY "public"."warehouses"
    ADD CONSTRAINT "warehouses_org_branch_fk" FOREIGN KEY ("organization_id", "branch_id") REFERENCES "public"."branches"("organization_id", "id") ON DELETE RESTRICT;

ALTER TABLE ONLY "public"."warehouses"
    ADD CONSTRAINT "warehouses_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;
