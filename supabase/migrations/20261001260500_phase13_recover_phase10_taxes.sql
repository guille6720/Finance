-- ORIGINAL_MIGRATION_SQL_UNAVAILABLE
-- RECOVERED_FROM_STAGING_CATALOG
-- SOURCE_OBJECTS: tax_jurisdictions, tax_rule_sets, tax_rule_versions,
--   organization_tax_registrations, tax_periods, tax_determinations,
--   tax_determination_sources, tax_determination_lines,
--   tax_determination_rule_snapshots, vat_purchase_classifications,
--   tax_obligations, tax_filing_records, tax_payment_records, tax_adjustments,
--   tax_withholdings_perceptions, iibb_cm_coefficients,
--   iibb_jurisdiction_allocations + tax/iibb enums + tax functions
-- SOURCE = docs/qa/phase13/forensics/staging-public-schema.sql
-- STAGING_PROJECT = rpcpdrzbcclofvjpgldb
-- RATIONALE: Phase 10 migration files 20261001210000-20261001260000 contained corrupt
--   ';' (empty) payloads. This forward migration recovers all Phase 10 tax DDL
--   from the authoritative staging catalog dump.
--   Sorting: AFTER 20261001260000 (last empty Phase 10 slot) as 20261001260500,
--   BEFORE 20261001270000 (phase10_hardening_fixture_counterparty_reuse).
--   Do not edit semantic behavior; DDL is verbatim from staging catalog.
-- SKIPPED: finalize_pos_sale_impl (staging-only refactor; Phase 9 uses
--   finalize_pos_sale; not required for cleanroom correctness).

CREATE TYPE "public"."iibb_distribution_method" AS ENUM (
    'GENERAL',
    'SPECIAL_REGIME',
    'MANUAL_REVIEW'
);

CREATE TYPE "public"."iibb_sales_allocation_strategy" AS ENUM (
    'MANUAL',
    'CONFIGURED_RULE',
    'REVIEW_REQUIRED'
);

CREATE TYPE "public"."tax_adjustment_direction" AS ENUM (
    'DEBIT',
    'CREDIT'
);

CREATE TYPE "public"."tax_adjustment_status" AS ENUM (
    'DRAFT',
    'APPROVED',
    'REVERSED'
);

CREATE TYPE "public"."tax_cm_form_code" AS ENUM (
    'CM03',
    'CM04',
    'CM05'
);

CREATE TYPE "public"."tax_code" AS ENUM (
    'IVA',
    'IIBB_LOCAL',
    'IIBB_CM',
    'GANANCIAS',
    'OTHER'
);

CREATE TYPE "public"."tax_determination_line_kind" AS ENUM (
    'DEBIT_FISCAL',
    'CREDIT_FISCAL_COMPUTABLE',
    'CREDIT_FISCAL_NON_COMPUTABLE',
    'RETENTION_CREDIT',
    'PERCEPTION_CREDIT',
    'ADJUSTMENT_DEBIT',
    'ADJUSTMENT_CREDIT',
    'PRIOR_BALANCE',
    'OTHER_ALLOWED_ITEM',
    'IIBB_TAX',
    'IIBB_WITHHOLDING',
    'IIBB_PERCEPTION'
);

CREATE TYPE "public"."tax_determination_status" AS ENUM (
    'DRAFT',
    'CALCULATED',
    'REVIEW_REQUIRED',
    'REVIEWED',
    'STALE',
    'SUPERSEDED'
);

CREATE TYPE "public"."tax_filing_kind" AS ENUM (
    'ORIGINAL',
    'RECTIFICATION'
);

CREATE TYPE "public"."tax_filing_status" AS ENUM (
    'FILED_EXTERNAL'
);

CREATE TYPE "public"."tax_obligation_status" AS ENUM (
    'OPEN',
    'PARTIALLY_PAID',
    'PAID',
    'CANCELLED',
    'REVIEW_REQUIRED'
);

CREATE TYPE "public"."tax_obligation_type" AS ENUM (
    'VAT_BALANCE',
    'IIBB_BALANCE',
    'WITHHOLDING_PAYABLE',
    'OTHER'
);

CREATE TYPE "public"."tax_period_status" AS ENUM (
    'OPEN',
    'IN_REVIEW',
    'REVIEWED',
    'CLOSED',
    'REOPENED'
);

CREATE TYPE "public"."tax_registration_status" AS ENUM (
    'ACTIVE',
    'INACTIVE'
);

CREATE TYPE "public"."tax_rule_status" AS ENUM (
    'DRAFT',
    'REVIEWED',
    'ACTIVE',
    'RETIRED'
);

CREATE TYPE "public"."tax_source_domain" AS ENUM (
    'FISCAL_DOCUMENT',
    'PURCHASE_DOCUMENT',
    'WITHHOLDING_PERCEPTION',
    'TAX_ADJUSTMENT',
    'PRIOR_BALANCE',
    'OTHER_CONTROLLED'
);

CREATE TYPE "public"."tax_workspace_environment" AS ENUM (
    'HOMOLOGATION',
    'PRODUCTION'
);

CREATE TYPE "public"."tax_wp_status" AS ENUM (
    'DRAFT',
    'CONFIRMED',
    'VOID',
    'REVERSED'
);

CREATE TYPE "public"."tax_wp_type" AS ENUM (
    'WITHHOLDING_SUFFERED',
    'PERCEPTION_SUFFERED',
    'WITHHOLDING_PRACTICED',
    'PERCEPTION_PRACTICED'
);

CREATE TYPE "public"."vat_credit_classification" AS ENUM (
    'COMPUTABLE',
    'NON_COMPUTABLE',
    'PARTIAL',
    'REVIEW_REQUIRED'
);

ALTER TYPE "public"."iibb_distribution_method" OWNER TO "postgres";

ALTER TYPE "public"."iibb_sales_allocation_strategy" OWNER TO "postgres";

ALTER TYPE "public"."tax_adjustment_direction" OWNER TO "postgres";

ALTER TYPE "public"."tax_adjustment_status" OWNER TO "postgres";

ALTER TYPE "public"."tax_cm_form_code" OWNER TO "postgres";

ALTER TYPE "public"."tax_code" OWNER TO "postgres";

ALTER TYPE "public"."tax_determination_line_kind" OWNER TO "postgres";

ALTER TYPE "public"."tax_determination_status" OWNER TO "postgres";

ALTER TYPE "public"."tax_filing_kind" OWNER TO "postgres";

ALTER TYPE "public"."tax_filing_status" OWNER TO "postgres";

ALTER TYPE "public"."tax_obligation_status" OWNER TO "postgres";

ALTER TYPE "public"."tax_obligation_type" OWNER TO "postgres";

ALTER TYPE "public"."tax_period_status" OWNER TO "postgres";

ALTER TYPE "public"."tax_registration_status" OWNER TO "postgres";

ALTER TYPE "public"."tax_rule_status" OWNER TO "postgres";

ALTER TYPE "public"."tax_source_domain" OWNER TO "postgres";

ALTER TYPE "public"."tax_workspace_environment" OWNER TO "postgres";

ALTER TYPE "public"."tax_wp_status" OWNER TO "postgres";

ALTER TYPE "public"."tax_wp_type" OWNER TO "postgres";

ALTER TYPE "public"."vat_credit_classification" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "public"."vat_purchase_classifications" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid" NOT NULL,
    "purchase_document_id" "uuid" NOT NULL,
    "purchase_tax_summary_id" "uuid" NOT NULL,
    "classification" "public"."vat_credit_classification" DEFAULT 'REVIEW_REQUIRED'::"public"."vat_credit_classification" NOT NULL,
    "informed_vat_amount" numeric(19,4) NOT NULL,
    "computable_amount" numeric(19,4) DEFAULT 0 NOT NULL,
    "noncomputable_amount" numeric(19,4) DEFAULT 0 NOT NULL,
    "reason_code" "text",
    "reason_notes" "text",
    "rule_version_id" "uuid",
    "classified_by" "uuid",
    "classified_at" timestamp with time zone,
    "reviewed_by" "uuid",
    "reviewed_at" timestamp with time zone,
    "status" "text" DEFAULT 'CONFIRMED'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    CONSTRAINT "vat_class_amounts_sum" CHECK (("abs"((("computable_amount" + "noncomputable_amount") - "informed_vat_amount")) <= 0.01)),
    CONSTRAINT "vat_purchase_classifications_computable_amount_check" CHECK (("computable_amount" >= (0)::numeric)),
    CONSTRAINT "vat_purchase_classifications_informed_vat_amount_check" CHECK (("informed_vat_amount" >= (0)::numeric)),
    CONSTRAINT "vat_purchase_classifications_noncomputable_amount_check" CHECK (("noncomputable_amount" >= (0)::numeric)),
    CONSTRAINT "vat_purchase_classifications_status_check" CHECK (("status" = ANY (ARRAY['DRAFT'::"text", 'CONFIRMED'::"text", 'SUPERSEDED'::"text"])))
);

CREATE TABLE IF NOT EXISTS "public"."tax_rule_versions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "rule_set_id" "uuid" NOT NULL,
    "status" "public"."tax_rule_status" DEFAULT 'DRAFT'::"public"."tax_rule_status" NOT NULL,
    "effective_from" "date" NOT NULL,
    "effective_to" "date",
    "rule_payload" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "payload_schema_version" "text" DEFAULT '1'::"text" NOT NULL,
    "source_reference" "text" NOT NULL,
    "source_title" "text",
    "source_verified_at" timestamp with time zone,
    "source_content_digest" "text",
    "reviewed_by" "uuid",
    "reviewed_at" timestamp with time zone,
    "activated_by" "uuid",
    "activated_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    CONSTRAINT "tax_rule_versions_dates" CHECK ((("effective_to" IS NULL) OR ("effective_to" >= "effective_from")))
);

CREATE TABLE IF NOT EXISTS "public"."iibb_cm_coefficients" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid" NOT NULL,
    "fiscal_year" integer NOT NULL,
    "jurisdiction_code" "text" NOT NULL,
    "coefficient" numeric(12,8) NOT NULL,
    "source" "text" NOT NULL,
    "status" "public"."tax_rule_status" DEFAULT 'DRAFT'::"public"."tax_rule_status" NOT NULL,
    "effective_from" "date" NOT NULL,
    "effective_to" "date",
    "rule_version_id" "uuid",
    "art14_first_year" boolean DEFAULT false NOT NULL,
    "reviewed_by" "uuid",
    "reviewed_at" timestamp with time zone,
    "activated_by" "uuid",
    "activated_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    CONSTRAINT "iibb_cm_coef_dates" CHECK ((("effective_to" IS NULL) OR ("effective_to" >= "effective_from"))),
    CONSTRAINT "iibb_cm_coefficients_coefficient_check" CHECK (("coefficient" >= (0)::numeric)),
    CONSTRAINT "iibb_cm_coefficients_fiscal_year_check" CHECK ((("fiscal_year" >= 2000) AND ("fiscal_year" <= 2100)))
);

CREATE TABLE IF NOT EXISTS "public"."iibb_jurisdiction_allocations" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid" NOT NULL,
    "tax_period_id" "uuid" NOT NULL,
    "tax_determination_id" "uuid",
    "jurisdiction_code" "text" NOT NULL,
    "cm_form_code" "public"."tax_cm_form_code",
    "distribution_method" "public"."iibb_distribution_method" DEFAULT 'MANUAL_REVIEW'::"public"."iibb_distribution_method" NOT NULL,
    "sales_allocation_strategy" "public"."iibb_sales_allocation_strategy" DEFAULT 'REVIEW_REQUIRED'::"public"."iibb_sales_allocation_strategy" NOT NULL,
    "gross_revenue_amount" numeric(19,4) DEFAULT 0 NOT NULL,
    "taxable_base" numeric(19,4) DEFAULT 0 NOT NULL,
    "coefficient" numeric(12,8),
    "allocated_base" numeric(19,4),
    "rate" numeric(7,4),
    "calculated_tax" numeric(19,4),
    "withholdings_amount" numeric(19,4) DEFAULT 0 NOT NULL,
    "perceptions_amount" numeric(19,4) DEFAULT 0 NOT NULL,
    "prior_balance" numeric(19,4) DEFAULT 0 NOT NULL,
    "estimated_due" numeric(19,4),
    "rule_version_id" "uuid",
    "review_status" "text" DEFAULT 'REVIEW_REQUIRED'::"text" NOT NULL,
    "narrative" "text",
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    CONSTRAINT "iibb_jurisdiction_allocations_review_status_check" CHECK (("review_status" = ANY (ARRAY['OK'::"text", 'REVIEW_REQUIRED'::"text", 'MANUAL_REVIEW'::"text"])))
);

CREATE TABLE IF NOT EXISTS "public"."organization_tax_registrations" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid" NOT NULL,
    "tax_code" "public"."tax_code" NOT NULL,
    "jurisdiction_code" "text" NOT NULL,
    "registration_number" "text",
    "status" "public"."tax_registration_status" DEFAULT 'ACTIVE'::"public"."tax_registration_status" NOT NULL,
    "effective_from" "date" NOT NULL,
    "effective_to" "date",
    "regime_metadata" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    CONSTRAINT "org_tax_reg_dates" CHECK ((("effective_to" IS NULL) OR ("effective_to" >= "effective_from")))
);

CREATE TABLE IF NOT EXISTS "public"."tax_adjustments" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid" NOT NULL,
    "tax_period_id" "uuid" NOT NULL,
    "tax_code" "public"."tax_code" NOT NULL,
    "direction" "public"."tax_adjustment_direction" NOT NULL,
    "amount" numeric(19,4) NOT NULL,
    "reason_code" "text" NOT NULL,
    "reason" "text" NOT NULL,
    "supporting_reference" "text",
    "status" "public"."tax_adjustment_status" DEFAULT 'DRAFT'::"public"."tax_adjustment_status" NOT NULL,
    "created_by" "uuid",
    "approved_by" "uuid",
    "approved_at" timestamp with time zone,
    "reversed_by" "uuid",
    "reversed_at" timestamp with time zone,
    "reverse_reason" "text",
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    CONSTRAINT "tax_adjustments_amount_check" CHECK (("amount" > (0)::numeric))
);

CREATE TABLE IF NOT EXISTS "public"."tax_determination_lines" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid" NOT NULL,
    "tax_determination_id" "uuid" NOT NULL,
    "line_kind" "public"."tax_determination_line_kind" NOT NULL,
    "amount" numeric(19,4) NOT NULL,
    "rate_code" "text",
    "rate" numeric(7,4),
    "tax_determination_source_id" "uuid",
    "narrative" "text",
    "sort_order" integer DEFAULT 100 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    CONSTRAINT "tax_det_line_has_origin" CHECK ((("tax_determination_source_id" IS NOT NULL) OR ("line_kind" = ANY (ARRAY['PRIOR_BALANCE'::"public"."tax_determination_line_kind", 'OTHER_ALLOWED_ITEM'::"public"."tax_determination_line_kind"]))))
);

CREATE TABLE IF NOT EXISTS "public"."tax_determination_rule_snapshots" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid" NOT NULL,
    "tax_determination_id" "uuid" NOT NULL,
    "tax_rule_version_id" "uuid" NOT NULL,
    "rule_key" "text" NOT NULL,
    "effective_from" "date" NOT NULL,
    "effective_to" "date",
    "payload_hash" "text" NOT NULL,
    "source_reference" "text" NOT NULL,
    "source_verified_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL
);

CREATE TABLE IF NOT EXISTS "public"."tax_determination_sources" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid" NOT NULL,
    "tax_determination_id" "uuid" NOT NULL,
    "source_domain" "public"."tax_source_domain" NOT NULL,
    "source_id" "uuid" NOT NULL,
    "source_component_id" "uuid",
    "tax_effective_date" "date" NOT NULL,
    "tax_period_attribution" "text" NOT NULL,
    "attribution_rule_version_id" "uuid",
    "source_environment" "public"."tax_workspace_environment",
    "amount" numeric(19,4) DEFAULT 0 NOT NULL,
    "tax_component_code" "text",
    "informed_amount" numeric(19,4),
    "computable_amount" numeric(19,4),
    "noncomputable_amount" numeric(19,4),
    "classification_id" "uuid",
    "rule_version_id" "uuid",
    "canonical_source_hash" "text" NOT NULL,
    "sort_key" "text" NOT NULL,
    "metadata" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL
);

CREATE TABLE IF NOT EXISTS "public"."tax_determinations" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid" NOT NULL,
    "tax_period_id" "uuid" NOT NULL,
    "determination_version" integer DEFAULT 1 NOT NULL,
    "status" "public"."tax_determination_status" DEFAULT 'DRAFT'::"public"."tax_determination_status" NOT NULL,
    "source_environment" "public"."tax_workspace_environment" NOT NULL,
    "source_snapshot_hash" "text",
    "totals_snapshot" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "calculated_by" "uuid",
    "calculated_at" timestamp with time zone,
    "reviewed_by" "uuid",
    "reviewed_at" timestamp with time zone,
    "stale_detected_at" timestamp with time zone,
    "stale_reason" "text",
    "is_current" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    CONSTRAINT "tax_determinations_determination_version_check" CHECK (("determination_version" >= 1))
);

CREATE TABLE IF NOT EXISTS "public"."tax_filing_records" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid" NOT NULL,
    "tax_period_id" "uuid" NOT NULL,
    "tax_code" "public"."tax_code" NOT NULL,
    "jurisdiction_code" "text",
    "filing_kind" "public"."tax_filing_kind" NOT NULL,
    "status" "public"."tax_filing_status" DEFAULT 'FILED_EXTERNAL'::"public"."tax_filing_status" NOT NULL,
    "external_form_code" "text" NOT NULL,
    "external_receipt_number" "text" NOT NULL,
    "filed_at" timestamp with time zone NOT NULL,
    "filed_by" "uuid" NOT NULL,
    "evidence_reference" "text",
    "evidence_hash" "text",
    "supersedes_filing_id" "uuid",
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    CONSTRAINT "tax_filing_rectification_link" CHECK (((("filing_kind" = 'ORIGINAL'::"public"."tax_filing_kind") AND ("supersedes_filing_id" IS NULL)) OR (("filing_kind" = 'RECTIFICATION'::"public"."tax_filing_kind") AND ("supersedes_filing_id" IS NOT NULL))))
);

CREATE TABLE IF NOT EXISTS "public"."tax_jurisdictions" (
    "code" "text" NOT NULL,
    "name" "text" NOT NULL,
    "kind" "text" NOT NULL,
    "comarb_code" "text",
    "active" boolean DEFAULT true NOT NULL,
    "sort_order" integer DEFAULT 100 NOT NULL,
    CONSTRAINT "tax_jurisdictions_kind_check" CHECK (("kind" = ANY (ARRAY['NATIONAL'::"text", 'PROVINCE'::"text", 'CABA'::"text", 'OTHER'::"text"])))
);

CREATE TABLE IF NOT EXISTS "public"."tax_obligations" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid" NOT NULL,
    "tax_period_id" "uuid" NOT NULL,
    "tax_determination_id" "uuid",
    "obligation_type" "public"."tax_obligation_type" NOT NULL,
    "tax_code" "public"."tax_code" NOT NULL,
    "jurisdiction_code" "text",
    "amount" numeric(19,4) NOT NULL,
    "due_date" "date",
    "status" "public"."tax_obligation_status" DEFAULT 'OPEN'::"public"."tax_obligation_status" NOT NULL,
    "narrative" "text",
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    CONSTRAINT "tax_obligations_amount_check" CHECK (("amount" >= (0)::numeric))
);

CREATE TABLE IF NOT EXISTS "public"."tax_payment_records" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid" NOT NULL,
    "tax_obligation_id" "uuid" NOT NULL,
    "payment_date" "date" NOT NULL,
    "amount" numeric(19,4) NOT NULL,
    "external_reference" "text" NOT NULL,
    "payment_method_description" "text",
    "evidence_reference" "text",
    "evidence_hash" "text",
    "recorded_by" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    CONSTRAINT "tax_payment_records_amount_check" CHECK (("amount" > (0)::numeric))
);

CREATE TABLE IF NOT EXISTS "public"."tax_periods" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid" NOT NULL,
    "tax_code" "public"."tax_code" NOT NULL,
    "jurisdiction_code" "text",
    "period_year" integer NOT NULL,
    "period_month" integer,
    "period_start" "date" NOT NULL,
    "period_end" "date" NOT NULL,
    "status" "public"."tax_period_status" DEFAULT 'OPEN'::"public"."tax_period_status" NOT NULL,
    "workspace_environment" "public"."tax_workspace_environment" DEFAULT 'HOMOLOGATION'::"public"."tax_workspace_environment" NOT NULL,
    "source_changed" boolean DEFAULT false NOT NULL,
    "reopen_reason" "text",
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "reviewed_by" "uuid",
    "reviewed_at" timestamp with time zone,
    "closed_by" "uuid",
    "closed_at" timestamp with time zone,
    "reopened_by" "uuid",
    "reopened_at" timestamp with time zone,
    CONSTRAINT "tax_periods_dates" CHECK (("period_end" >= "period_start")),
    CONSTRAINT "tax_periods_period_month_check" CHECK ((("period_month" IS NULL) OR (("period_month" >= 1) AND ("period_month" <= 12)))),
    CONSTRAINT "tax_periods_period_year_check" CHECK ((("period_year" >= 2000) AND ("period_year" <= 2100)))
);

CREATE TABLE IF NOT EXISTS "public"."tax_rule_sets" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tax_code" "public"."tax_code" NOT NULL,
    "jurisdiction_code" "text",
    "rule_key" "text" NOT NULL,
    "description" "text",
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL
);

CREATE TABLE IF NOT EXISTS "public"."tax_withholdings_perceptions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid" NOT NULL,
    "counterparty_id" "uuid",
    "wp_type" "public"."tax_wp_type" NOT NULL,
    "tax_code" "public"."tax_code" NOT NULL,
    "jurisdiction_code" "text",
    "certificate_number" "text",
    "external_reference" "text",
    "operation_date" "date" NOT NULL,
    "tax_period_date" "date" NOT NULL,
    "base_amount" numeric(19,4),
    "rate" numeric(7,4),
    "amount" numeric(19,4) NOT NULL,
    "source_document_type" "text",
    "source_document_id" "uuid",
    "status" "public"."tax_wp_status" DEFAULT 'CONFIRMED'::"public"."tax_wp_status" NOT NULL,
    "evidence_hash" "text",
    "import_batch_id" "uuid",
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    CONSTRAINT "tax_withholdings_perceptions_amount_check" CHECK (("amount" > (0)::numeric))
);

ALTER TABLE "public"."vat_purchase_classifications" OWNER TO "postgres";

ALTER TABLE "public"."tax_rule_versions" OWNER TO "postgres";

ALTER TABLE "public"."iibb_cm_coefficients" OWNER TO "postgres";

ALTER TABLE "public"."iibb_jurisdiction_allocations" OWNER TO "postgres";

ALTER TABLE "public"."organization_tax_registrations" OWNER TO "postgres";

ALTER TABLE "public"."tax_adjustments" OWNER TO "postgres";

ALTER TABLE "public"."tax_determination_lines" OWNER TO "postgres";

ALTER TABLE "public"."tax_determination_rule_snapshots" OWNER TO "postgres";

ALTER TABLE "public"."tax_determination_sources" OWNER TO "postgres";

ALTER TABLE "public"."tax_determinations" OWNER TO "postgres";

ALTER TABLE "public"."tax_filing_records" OWNER TO "postgres";

ALTER TABLE "public"."tax_jurisdictions" OWNER TO "postgres";

ALTER TABLE "public"."tax_obligations" OWNER TO "postgres";

ALTER TABLE "public"."tax_payment_records" OWNER TO "postgres";

ALTER TABLE "public"."tax_periods" OWNER TO "postgres";

ALTER TABLE "public"."tax_rule_sets" OWNER TO "postgres";

ALTER TABLE "public"."tax_withholdings_perceptions" OWNER TO "postgres";

ALTER TABLE ONLY "public"."iibb_cm_coefficients"
    ADD CONSTRAINT "iibb_cm_coefficients_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."iibb_jurisdiction_allocations"
    ADD CONSTRAINT "iibb_jurisdiction_allocations_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."organization_tax_registrations"
    ADD CONSTRAINT "organization_tax_registrations_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."tax_adjustments"
    ADD CONSTRAINT "tax_adjustments_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."tax_determination_lines"
    ADD CONSTRAINT "tax_determination_lines_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."tax_determination_rule_snapshots"
    ADD CONSTRAINT "tax_determination_rule_snapshots_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."tax_determination_sources"
    ADD CONSTRAINT "tax_determination_sources_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."tax_determinations"
    ADD CONSTRAINT "tax_determinations_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."tax_filing_records"
    ADD CONSTRAINT "tax_filing_records_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."tax_jurisdictions"
    ADD CONSTRAINT "tax_jurisdictions_pkey" PRIMARY KEY ("code");

ALTER TABLE ONLY "public"."tax_obligations"
    ADD CONSTRAINT "tax_obligations_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."tax_payment_records"
    ADD CONSTRAINT "tax_payment_records_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."tax_periods"
    ADD CONSTRAINT "tax_periods_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."tax_rule_sets"
    ADD CONSTRAINT "tax_rule_sets_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."tax_rule_versions"
    ADD CONSTRAINT "tax_rule_versions_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."tax_withholdings_perceptions"
    ADD CONSTRAINT "tax_withholdings_perceptions_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."vat_purchase_classifications"
    ADD CONSTRAINT "vat_purchase_classifications_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."iibb_jurisdiction_allocations"
    ADD CONSTRAINT "iibb_alloc_org_id_unique" UNIQUE ("organization_id", "id");

ALTER TABLE ONLY "public"."iibb_jurisdiction_allocations"
    ADD CONSTRAINT "iibb_alloc_period_jurisdiction_unique" UNIQUE ("tax_period_id", "jurisdiction_code");

ALTER TABLE ONLY "public"."iibb_cm_coefficients"
    ADD CONSTRAINT "iibb_cm_coef_org_id_unique" UNIQUE ("organization_id", "id");

ALTER TABLE ONLY "public"."organization_tax_registrations"
    ADD CONSTRAINT "org_tax_reg_org_id_unique" UNIQUE ("organization_id", "id");

ALTER TABLE ONLY "public"."tax_adjustments"
    ADD CONSTRAINT "tax_adj_org_id_unique" UNIQUE ("organization_id", "id");

ALTER TABLE ONLY "public"."tax_determinations"
    ADD CONSTRAINT "tax_det_org_id_unique" UNIQUE ("organization_id", "id");

ALTER TABLE ONLY "public"."tax_determinations"
    ADD CONSTRAINT "tax_det_period_version_unique" UNIQUE ("tax_period_id", "determination_version");

ALTER TABLE ONLY "public"."tax_determination_rule_snapshots"
    ADD CONSTRAINT "tax_det_rule_snap_unique" UNIQUE ("tax_determination_id", "rule_key", "tax_rule_version_id");

ALTER TABLE ONLY "public"."tax_filing_records"
    ADD CONSTRAINT "tax_filing_org_id_unique" UNIQUE ("organization_id", "id");

ALTER TABLE ONLY "public"."tax_obligations"
    ADD CONSTRAINT "tax_obl_org_id_unique" UNIQUE ("organization_id", "id");

ALTER TABLE ONLY "public"."tax_payment_records"
    ADD CONSTRAINT "tax_pay_org_id_unique" UNIQUE ("organization_id", "id");

ALTER TABLE ONLY "public"."tax_periods"
    ADD CONSTRAINT "tax_periods_org_id_unique" UNIQUE ("organization_id", "id");

ALTER TABLE ONLY "public"."tax_periods"
    ADD CONSTRAINT "tax_periods_unique" UNIQUE NULLS NOT DISTINCT ("organization_id", "tax_code", "jurisdiction_code", "period_year", "period_month", "workspace_environment");

ALTER TABLE ONLY "public"."tax_rule_sets"
    ADD CONSTRAINT "tax_rule_sets_unique" UNIQUE ("tax_code", "jurisdiction_code", "rule_key");

ALTER TABLE ONLY "public"."tax_withholdings_perceptions"
    ADD CONSTRAINT "tax_wp_org_id_unique" UNIQUE ("organization_id", "id");

ALTER TABLE ONLY "public"."vat_purchase_classifications"
    ADD CONSTRAINT "vat_class_org_id_unique" UNIQUE ("organization_id", "id");

CREATE OR REPLACE FUNCTION "public"."activate_tax_rule_version"("p_rule_version_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_ver public.tax_rule_versions%rowtype;
begin
  perform public.tax_assert_service_role();

  select * into v_ver from public.tax_rule_versions where id = p_rule_version_id;
  if not found then
    raise exception 'rule version not found';
  end if;
  if v_ver.status not in ('DRAFT', 'REVIEWED') then
    raise exception 'only DRAFT/REVIEWED can activate';
  end if;

  perform set_config('tax.engine_write', '1', true);

  update public.tax_rule_versions
  set status = 'RETIRED'
  where rule_set_id = v_ver.rule_set_id
    and status = 'ACTIVE'
    and id is distinct from v_ver.id;

  update public.tax_rule_versions
  set status = 'ACTIVE',
      activated_at = timezone('utc', now())
  where id = v_ver.id;
end;
$$;

CREATE OR REPLACE FUNCTION "public"."calculate_tax_determination"("p_tax_period_id" "uuid") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_uid uuid;
  v_period public.tax_periods%rowtype;
  v_det_id uuid;
  v_version int;
  v_rule_elig public.tax_rule_versions%rowtype;
  v_rule_attr public.tax_rule_versions%rowtype;
  v_rule_comp public.tax_rule_versions%rowtype;
  v_fd public.fiscal_documents%rowtype;
  v_fts public.fiscal_tax_summaries%rowtype;
  v_dtype public.fiscal_document_types%rowtype;
  v_pd public.purchase_documents%rowtype;
  v_pts public.purchase_document_tax_summaries%rowtype;
  v_cls public.vat_purchase_classifications%rowtype;
  v_wp public.tax_withholdings_perceptions%rowtype;
  v_adj public.tax_adjustments%rowtype;
  v_rec record;
  v_src_id uuid;
  v_hash text;
  v_parts text := '';
  v_debit numeric(19,4) := 0;
  v_credit_comp numeric(19,4) := 0;
  v_credit_non numeric(19,4) := 0;
  v_informed numeric(19,4) := 0;
  v_ret numeric(19,4) := 0;
  v_perc numeric(19,4) := 0;
  v_adj_d numeric(19,4) := 0;
  v_adj_c numeric(19,4) := 0;
  v_estimated numeric(19,4) := 0;
  v_sort int := 0;
  v_tax_eff date;
  v_attr_field text;
  v_signed numeric(19,4);
  v_sign numeric;
  v_review_required boolean := false;
  v_env_label text;
  v_journals_before bigint;
begin
  select * into v_period
  from public.tax_periods
  where id = p_tax_period_id
  for update;

  if not found then
    raise exception 'tax period not found';
  end if;

  v_uid := public.tax_assert_role(
    v_period.organization_id,
    array['owner','admin','accountant']::public.member_role[]
  );
  perform public.tax_assert_feature(v_period.organization_id);

  if v_period.status = 'CLOSED' then
    raise exception 'cannot calculate CLOSED tax period; reopen first';
  end if;

  if v_period.tax_code is distinct from 'IVA' then
    raise exception 'MVP calculate_tax_determination currently supports IVA only; use IIBB allocations for IIBB periods';
  end if;

  if not exists (
    select 1 from public.organization_tax_registrations r
    where r.organization_id = v_period.organization_id
      and r.tax_code = 'IVA'
      and r.status = 'ACTIVE'
      and r.effective_from <= v_period.period_end
      and (r.effective_to is null or r.effective_to >= v_period.period_start)
  ) then
    raise exception 'active IVA tax registration required';
  end if;

  select count(*) into v_journals_before
  from public.journal_entries
  where organization_id = v_period.organization_id;

  v_rule_elig := public.tax_resolve_active_rule('IVA', 'NATIONAL', 'vat_source_eligibility', v_period.period_end);
  v_rule_attr := public.tax_resolve_active_rule('IVA', 'NATIONAL', 'vat_period_attribution', v_period.period_end);
  v_rule_comp := public.tax_resolve_active_rule('IVA', 'NATIONAL', 'vat_computability_default', v_period.period_end);
  v_attr_field := coalesce(v_rule_attr.rule_payload->>'tax_effective_date_field', 'issue_date');

  perform set_config('tax.engine_write', '1', true);

  update public.tax_determinations
  set is_current = false,
      status = case when status in ('REVIEWED','CALCULATED') then 'SUPERSEDED'::public.tax_determination_status else status end
  where tax_period_id = v_period.id
    and is_current;

  select coalesce(max(determination_version), 0) + 1 into v_version
  from public.tax_determinations
  where tax_period_id = v_period.id;

  insert into public.tax_determinations (
    organization_id, tax_period_id, determination_version, status,
    source_environment, calculated_by, calculated_at, is_current
  ) values (
    v_period.organization_id, v_period.id, v_version, 'CALCULATED',
    v_period.workspace_environment, v_uid, timezone('utc', now()), true
  )
  returning id into v_det_id;

  insert into public.tax_determination_rule_snapshots (
    organization_id, tax_determination_id, tax_rule_version_id, rule_key,
    effective_from, effective_to, payload_hash, source_reference, source_verified_at
  )
  select
    v_period.organization_id, v_det_id, r.id, s.rule_key,
    r.effective_from, r.effective_to,
    public.tax_sha256(r.rule_payload::text),
    r.source_reference, r.source_verified_at
  from (values
    (v_rule_elig.id), (v_rule_attr.id), (v_rule_comp.id)
  ) as x(id)
  join public.tax_rule_versions r on r.id = x.id
  join public.tax_rule_sets s on s.id = r.rule_set_id;

  for v_rec in
    select fd, fts, fdt
    from public.fiscal_documents fd
    join public.fiscal_tax_summaries fts
      on fts.fiscal_document_id = fd.id
     and fts.organization_id = fd.organization_id
    join public.fiscal_document_types fdt on fdt.id = fd.document_type_id
    where fd.organization_id = v_period.organization_id
      and fts.summary_kind = 'IVA'
      and fd.status = 'AUTHORIZED'
  loop
    v_fd := v_rec.fd;
    v_fts := v_rec.fts;
    v_dtype := v_rec.fdt;

    if v_fd.fiscal_environment::text is distinct from v_period.workspace_environment::text then
      continue;
    end if;

    v_tax_eff := public.tax_resolve_effective_date(
      'IVA'::public.tax_code,
      'FISCAL_DOCUMENT'::public.tax_source_domain,
      v_fd.issue_date,
      null,
      v_rule_attr
    );
    if v_tax_eff is null then
      v_review_required := true;
      continue;
    end if;
    if v_tax_eff < v_period.period_start or v_tax_eff > v_period.period_end then
      continue;
    end if;

    v_sign := public.tax_fiscal_vat_economic_sign(v_dtype.operation_kind);
    v_signed := round(v_fts.amount * v_sign, 4);

    v_sort := v_sort + 1;
    v_hash := public.tax_canonical_fiscal_hash(v_fd, v_fts);

    insert into public.tax_determination_sources (
      organization_id, tax_determination_id, source_domain, source_id, source_component_id,
      tax_effective_date, tax_period_attribution, attribution_rule_version_id,
      source_environment, amount, tax_component_code, informed_amount,
      rule_version_id, canonical_source_hash, sort_key, metadata
    ) values (
      v_period.organization_id, v_det_id, 'FISCAL_DOCUMENT', v_fd.id, v_fts.id,
      v_tax_eff, v_attr_field, v_rule_attr.id,
      v_period.workspace_environment, v_signed, v_fts.code, v_fts.amount,
      v_rule_elig.id, v_hash, lpad(v_sort::text, 8, '0') || ':FD:' || v_fd.id::text,
      jsonb_build_object(
        'related_fiscal_document_id', v_fd.related_fiscal_document_id,
        'operation_kind', v_dtype.operation_kind,
        'document_amount_magnitude', v_fts.amount,
        'economic_sign', v_sign
      )
    )
    returning id into v_src_id;

    v_debit := v_debit + v_signed;
    insert into public.tax_determination_lines (
      organization_id, tax_determination_id, line_kind, amount, rate_code, rate,
      tax_determination_source_id, narrative, sort_order
    ) values (
      v_period.organization_id, v_det_id, 'DEBIT_FISCAL', v_signed, v_fts.code, v_fts.rate,
      v_src_id,
      case when v_sign < 0 then 'Débito fiscal (nota de crédito)'
           when v_dtype.operation_kind = 'DEBIT_NOTE' then 'Débito fiscal (nota de débito)'
           else 'Débito fiscal (autorizado)' end,
      v_sort
    );

    v_parts := v_parts || v_hash || chr(10);
  end loop;

  for v_rec in
    select pd, pts, cls
    from public.purchase_documents pd
    join public.purchase_document_tax_summaries pts
      on pts.purchase_document_id = pd.id
     and pts.organization_id = pd.organization_id
    left join public.vat_purchase_classifications cls
      on cls.purchase_tax_summary_id = pts.id
     and cls.organization_id = pd.organization_id
     and cls.status = 'CONFIRMED'
    where pd.organization_id = v_period.organization_id
      and pts.summary_kind = 'IVA'
      and pd.status in ('REVIEWED', 'POSTED')
  loop
    v_pd := v_rec.pd;
    v_pts := v_rec.pts;
    v_cls := v_rec.cls;

    v_tax_eff := public.tax_resolve_effective_date(
      'IVA'::public.tax_code,
      'PURCHASE_DOCUMENT'::public.tax_source_domain,
      v_pd.issue_date,
      v_pd.accounting_date,
      v_rule_attr
    );
    if v_tax_eff is null then
      v_review_required := true;
      continue;
    end if;
    if v_tax_eff < v_period.period_start or v_tax_eff > v_period.period_end then
      continue;
    end if;

    v_informed := v_informed + v_pts.amount;

    if v_cls.id is null
       or v_cls.classification = 'REVIEW_REQUIRED' then
      v_review_required := true;
      continue;
    end if;

    if abs((v_cls.computable_amount + v_cls.noncomputable_amount) - v_cls.informed_vat_amount) > 0.01 then
      raise exception 'invalid VAT classification amounts for summary %', v_pts.id;
    end if;
    if abs(v_cls.informed_vat_amount - v_pts.amount) > 0.01 then
      raise exception 'classification informed amount must match tax summary component';
    end if;

    v_sort := v_sort + 1;
    v_hash := public.tax_canonical_purchase_hash(v_pd, v_pts, v_cls);

    insert into public.tax_determination_sources (
      organization_id, tax_determination_id, source_domain, source_id, source_component_id,
      tax_effective_date, tax_period_attribution, attribution_rule_version_id,
      source_environment, amount, tax_component_code,
      informed_amount, computable_amount, noncomputable_amount,
      classification_id, rule_version_id, canonical_source_hash, sort_key
    ) values (
      v_period.organization_id, v_det_id, 'PURCHASE_DOCUMENT', v_pd.id, v_pts.id,
      v_tax_eff, v_attr_field, v_rule_attr.id,
      v_period.workspace_environment, v_cls.computable_amount, v_pts.code,
      v_cls.informed_vat_amount, v_cls.computable_amount, v_cls.noncomputable_amount,
      v_cls.id, v_rule_comp.id, v_hash, lpad(v_sort::text, 8, '0') || ':PD:' || v_pd.id::text
    )
    returning id into v_src_id;

    v_credit_comp := v_credit_comp + v_cls.computable_amount;
    v_credit_non := v_credit_non + v_cls.noncomputable_amount;

    if v_cls.computable_amount > 0 then
      insert into public.tax_determination_lines (
        organization_id, tax_determination_id, line_kind, amount, rate_code, rate,
        tax_determination_source_id, narrative, sort_order
      ) values (
        v_period.organization_id, v_det_id, 'CREDIT_FISCAL_COMPUTABLE', v_cls.computable_amount,
        v_pts.code, v_pts.rate, v_src_id, 'Crédito fiscal computable', v_sort
      );
    end if;
    if v_cls.noncomputable_amount > 0 then
      v_sort := v_sort + 1;
      insert into public.tax_determination_lines (
        organization_id, tax_determination_id, line_kind, amount, rate_code, rate,
        tax_determination_source_id, narrative, sort_order
      ) values (
        v_period.organization_id, v_det_id, 'CREDIT_FISCAL_NON_COMPUTABLE', v_cls.noncomputable_amount,
        v_pts.code, v_pts.rate, v_src_id, 'Crédito fiscal no computable / pendiente', v_sort
      );
    end if;

    v_parts := v_parts || v_hash || chr(10);
  end loop;

  for v_wp in
    select *
    from public.tax_withholdings_perceptions wp
    where wp.organization_id = v_period.organization_id
      and wp.tax_code = 'IVA'
      and wp.status = 'CONFIRMED'
      and wp.tax_period_date between v_period.period_start and v_period.period_end
      and wp.wp_type in ('WITHHOLDING_SUFFERED', 'PERCEPTION_SUFFERED')
  loop
    v_sort := v_sort + 1;
    v_hash := public.tax_sha256(concat_ws('|',
      v_wp.id::text, v_wp.wp_type::text, v_wp.amount::text,
      v_wp.tax_period_date::text, v_wp.status::text,
      coalesce(v_wp.certificate_number, '')
    ));

    insert into public.tax_determination_sources (
      organization_id, tax_determination_id, source_domain, source_id,
      tax_effective_date, tax_period_attribution, source_environment,
      amount, canonical_source_hash, sort_key
    ) values (
      v_period.organization_id, v_det_id, 'WITHHOLDING_PERCEPTION', v_wp.id,
      v_wp.tax_period_date, 'tax_period_date', v_period.workspace_environment,
      v_wp.amount, v_hash, lpad(v_sort::text, 8, '0') || ':WP:' || v_wp.id::text
    )
    returning id into v_src_id;

    if v_wp.wp_type = 'WITHHOLDING_SUFFERED' then
      v_ret := v_ret + v_wp.amount;
      insert into public.tax_determination_lines (
        organization_id, tax_determination_id, line_kind, amount,
        tax_determination_source_id, narrative, sort_order
      ) values (
        v_period.organization_id, v_det_id, 'RETENTION_CREDIT', v_wp.amount,
        v_src_id, 'Retención sufrida', v_sort
      );
    else
      v_perc := v_perc + v_wp.amount;
      insert into public.tax_determination_lines (
        organization_id, tax_determination_id, line_kind, amount,
        tax_determination_source_id, narrative, sort_order
      ) values (
        v_period.organization_id, v_det_id, 'PERCEPTION_CREDIT', v_wp.amount,
        v_src_id, 'Percepción sufrida', v_sort
      );
    end if;
    v_parts := v_parts || v_hash || chr(10);
  end loop;

  for v_adj in
    select *
    from public.tax_adjustments a
    where a.tax_period_id = v_period.id
      and a.status = 'APPROVED'
  loop
    v_sort := v_sort + 1;
    v_hash := public.tax_sha256(concat_ws('|',
      v_adj.id::text, v_adj.direction::text, v_adj.amount::text, v_adj.status::text
    ));
    insert into public.tax_determination_sources (
      organization_id, tax_determination_id, source_domain, source_id,
      tax_effective_date, tax_period_attribution, source_environment,
      amount, canonical_source_hash, sort_key
    ) values (
      v_period.organization_id, v_det_id, 'TAX_ADJUSTMENT', v_adj.id,
      v_period.period_end, 'period_end', v_period.workspace_environment,
      v_adj.amount, v_hash, lpad(v_sort::text, 8, '0') || ':ADJ:' || v_adj.id::text
    )
    returning id into v_src_id;

    if v_adj.direction = 'DEBIT' then
      v_adj_d := v_adj_d + v_adj.amount;
      insert into public.tax_determination_lines (
        organization_id, tax_determination_id, line_kind, amount,
        tax_determination_source_id, narrative, sort_order
      ) values (
        v_period.organization_id, v_det_id, 'ADJUSTMENT_DEBIT', v_adj.amount,
        v_src_id, v_adj.reason, v_sort
      );
    else
      v_adj_c := v_adj_c + v_adj.amount;
      insert into public.tax_determination_lines (
        organization_id, tax_determination_id, line_kind, amount,
        tax_determination_source_id, narrative, sort_order
      ) values (
        v_period.organization_id, v_det_id, 'ADJUSTMENT_CREDIT', v_adj.amount,
        v_src_id, v_adj.reason, v_sort
      );
    end if;
    v_parts := v_parts || v_hash || chr(10);
  end loop;

  v_estimated := v_debit - v_credit_comp - v_ret - v_perc + v_adj_d - v_adj_c;
  v_env_label := case when v_period.workspace_environment = 'HOMOLOGATION'
    then 'HOMOLOGACIÓN / DATOS DE PRUEBA' else 'PRODUCTION' end;

  update public.tax_determinations
  set source_snapshot_hash = public.tax_sha256(v_parts),
      status = case when v_review_required then 'REVIEW_REQUIRED'::public.tax_determination_status
                    else 'CALCULATED'::public.tax_determination_status end,
      totals_snapshot = jsonb_build_object(
        'debit_fiscal', v_debit,
        'iva_informado_compras', v_informed,
        'credit_fiscal_computable', v_credit_comp,
        'credit_fiscal_non_computable', v_credit_non,
        'retenciones', v_ret,
        'percepciones', v_perc,
        'ajustes_debit', v_adj_d,
        'ajustes_credit', v_adj_c,
        'saldo_estimado', v_estimated,
        'label_saldo', 'Saldo estimado según Contabilium',
        'workspace_banner', v_env_label,
        'journals_before', v_journals_before,
        'official_filing', false,
        'attribution_rule_field', v_attr_field,
        'attribution_rule_version_id', v_rule_attr.id
      ),
      calculated_at = timezone('utc', now()),
      calculated_by = v_uid
  where id = v_det_id;

  if v_period.status in ('OPEN', 'REOPENED', 'IN_REVIEW') then
    update public.tax_periods
    set source_changed = false,
        status = case when status = 'OPEN' then 'IN_REVIEW'::public.tax_period_status else status end
    where id = v_period.id;
  end if;

  perform public.accounting_write_audit(
    v_period.organization_id,
    v_uid,
    'tax.calculate',
    'tax_determination',
    v_det_id::text,
    'calculate',
    jsonb_build_object(
      'tax_period_id', v_period.id,
      'version', v_version,
      'source_snapshot_hash', public.tax_sha256(v_parts),
      'environment', v_period.workspace_environment
    )
  );

  return v_det_id;
end;
$$;

CREATE OR REPLACE FUNCTION "public"."calculate_tax_period"("p_tax_period_id" "uuid") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  return public.calculate_tax_determination(p_tax_period_id);
end;
$$;

CREATE OR REPLACE FUNCTION "public"."close_tax_period"("p_tax_period_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_uid uuid;
  v_period public.tax_periods%rowtype;
  v_det public.tax_determinations%rowtype;
  v_reval text;
begin
  select * into v_period from public.tax_periods where id = p_tax_period_id for update;
  if not found then raise exception 'tax period not found'; end if;
  v_uid := public.tax_assert_role(
    v_period.organization_id,
    array['owner','accountant']::public.member_role[]
  );
  perform public.tax_assert_feature(v_period.organization_id);

  if v_period.status is distinct from 'REVIEWED' then
    raise exception 'period must be REVIEWED before close';
  end if;
  if v_period.source_changed then
    raise exception 'SOURCE_CHANGED — cannot close';
  end if;

  select * into v_det from public.tax_determinations
  where tax_period_id = p_tax_period_id and is_current;
  if v_det.status is distinct from 'REVIEWED' then
    raise exception 'determination must be REVIEWED';
  end if;

  v_reval := public.revalidate_tax_determination_sources(p_tax_period_id);
  if v_reval = 'SOURCE_CHANGED' then
    raise exception 'Los datos fuente cambiaron desde la última revisión.';
  end if;

  perform set_config('tax.engine_write', '1', true);
  update public.tax_periods
  set status = 'CLOSED', closed_by = v_uid, closed_at = timezone('utc', now())
  where id = v_period.id;

  perform public.accounting_write_audit(
    v_period.organization_id, v_uid, 'tax.period.close', 'tax_period', v_period.id::text, 'close',
    jsonb_build_object('note', 'CLOSE freezes internal workpaper only; does not file or pay')
  );
end;
$$;

CREATE OR REPLACE FUNCTION "public"."create_tax_obligation"("p_tax_period_id" "uuid", "p_obligation_type" "public"."tax_obligation_type", "p_amount" numeric, "p_due_date" "date" DEFAULT NULL::"date", "p_narrative" "text" DEFAULT NULL::"text") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_uid uuid;
  v_period public.tax_periods%rowtype;
  v_det_id uuid;
  v_id uuid;
begin
  select * into v_period from public.tax_periods where id = p_tax_period_id;
  if not found then raise exception 'tax period not found'; end if;
  v_uid := public.tax_assert_role(
    v_period.organization_id,
    array['owner','accountant']::public.member_role[]
  );
  perform public.tax_assert_feature(v_period.organization_id);
  select id into v_det_id from public.tax_determinations
  where tax_period_id = p_tax_period_id and is_current;

  insert into public.tax_obligations (
    organization_id, tax_period_id, tax_determination_id, obligation_type,
    tax_code, jurisdiction_code, amount, due_date, status, narrative, created_by
  ) values (
    v_period.organization_id, v_period.id, v_det_id, p_obligation_type,
    v_period.tax_code, v_period.jurisdiction_code, p_amount, p_due_date, 'OPEN',
    p_narrative, v_uid
  )
  returning id into v_id;
  return v_id;
end;
$$;

CREATE OR REPLACE FUNCTION "public"."ensure_tax_period"("p_organization_id" "uuid", "p_tax_code" "public"."tax_code", "p_jurisdiction_code" "text", "p_period_year" integer, "p_period_month" integer, "p_workspace_environment" "public"."tax_workspace_environment" DEFAULT 'HOMOLOGATION'::"public"."tax_workspace_environment") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_uid uuid;
  v_id uuid;
  v_start date;
  v_end date;
begin
  v_uid := public.tax_assert_role(
    p_organization_id,
    array['owner','admin','accountant','manager']::public.member_role[]
  );
  perform public.tax_assert_feature(p_organization_id);

  if p_period_month is null or p_period_month < 1 or p_period_month > 12 then
    raise exception 'period_month required (1-12) for MVP';
  end if;

  v_start := make_date(p_period_year, p_period_month, 1);
  v_end := (v_start + interval '1 month' - interval '1 day')::date;

  select id into v_id
  from public.tax_periods
  where organization_id = p_organization_id
    and tax_code = p_tax_code
    and jurisdiction_code is not distinct from p_jurisdiction_code
    and period_year = p_period_year
    and period_month = p_period_month
    and workspace_environment = p_workspace_environment;

  if v_id is not null then
    return v_id;
  end if;

  insert into public.tax_periods (
    organization_id, tax_code, jurisdiction_code,
    period_year, period_month, period_start, period_end,
    workspace_environment, status
  ) values (
    p_organization_id, p_tax_code, p_jurisdiction_code,
    p_period_year, p_period_month, v_start, v_end,
    p_workspace_environment, 'OPEN'
  )
  returning id into v_id;

  perform public.accounting_write_audit(
    p_organization_id, v_uid, 'tax.period.ensure', 'tax_period', v_id::text, 'create',
    jsonb_build_object('environment', p_workspace_environment)
  );
  return v_id;
end;
$$;

CREATE OR REPLACE FUNCTION "public"."prevent_active_tax_rule_mutation"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
begin
  if tg_op = 'UPDATE' and old.status = 'ACTIVE' then
    if current_setting('tax.engine_write', true) is distinct from '1' then
      raise exception 'ACTIVE tax rule versions are immutable; create a new version';
    end if;
    -- engine may only RETIRE, not rewrite payload
    if new.rule_payload is distinct from old.rule_payload
      or new.effective_from is distinct from old.effective_from
      or new.source_reference is distinct from old.source_reference
    then
      raise exception 'ACTIVE tax rule payload/effective dates cannot change';
    end if;
  end if;
  if tg_op = 'DELETE' and old.status = 'ACTIVE' then
    raise exception 'cannot delete ACTIVE tax rule version';
  end if;
  return coalesce(new, old);
end;
$$;

CREATE OR REPLACE FUNCTION "public"."prevent_tax_determination_client_mutation"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
begin
  if current_setting('tax.engine_write', true) is distinct from '1' then
    raise exception 'tax determinations are trusted-engine only';
  end if;
  return coalesce(new, old);
end;
$$;

CREATE OR REPLACE FUNCTION "public"."prevent_tax_filing_mutation"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
begin
  if tg_op = 'DELETE' then
    raise exception 'tax_filing_records are append-only; cannot delete';
  end if;
  if tg_op = 'UPDATE' then
    raise exception 'tax_filing_records are append-only; record a RECTIFICATION instead';
  end if;
  if current_setting('tax.engine_write', true) is distinct from '1' then
    raise exception 'tax_filing_records insert is trusted-engine only';
  end if;
  return new;
end;
$$;

CREATE OR REPLACE FUNCTION "public"."prevent_tax_payment_mutation"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
begin
  if tg_op = 'DELETE' then
    raise exception 'tax_payment_records are append-only';
  end if;
  if tg_op = 'UPDATE' then
    raise exception 'tax_payment_records are append-only';
  end if;
  if current_setting('tax.engine_write', true) is distinct from '1' then
    raise exception 'tax_payment_records insert is trusted-engine only';
  end if;
  return new;
end;
$$;

CREATE OR REPLACE FUNCTION "public"."prevent_tax_period_status_forgery"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
begin
  if current_setting('tax.engine_write', true) = '1' then
    return new;
  end if;
  if tg_op = 'UPDATE' then
    if new.status is distinct from old.status
      or new.reviewed_at is distinct from old.reviewed_at
      or new.closed_at is distinct from old.closed_at
      or new.source_changed is distinct from old.source_changed
    then
      raise exception 'tax_periods status fields are trusted-only';
    end if;
  end if;
  return new;
end;
$$;

CREATE OR REPLACE FUNCTION "public"."reconcile_vat_accounting"("p_tax_period_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_period public.tax_periods%rowtype;
  v_det public.tax_determinations%rowtype;
  v_out_acct uuid;
  v_in_acct uuid;
  v_out_bal numeric(19,4) := 0;
  v_in_bal numeric(19,4) := 0;
  v_debit numeric(19,4) := 0;
  v_credit numeric(19,4) := 0;
begin
  select * into v_period from public.tax_periods where id = p_tax_period_id;
  if not found then raise exception 'tax period not found'; end if;
  if not public.is_org_member(v_period.organization_id) then
    raise exception 'not a member';
  end if;

  select vat_output_account_id into v_out_acct
  from public.fiscal_accounting_mappings
  where organization_id = v_period.organization_id;
  select vat_input_account_id into v_in_acct
  from public.purchase_accounting_mappings
  where organization_id = v_period.organization_id;

  if v_out_acct is null or v_in_acct is null then
    return jsonb_build_object(
      'status', 'TAX_RECONCILIATION_REQUIRES_CONFIG',
      'message', 'Missing vat_output_account_id or vat_input_account_id mapping'
    );
  end if;

  select * into v_det from public.tax_determinations
  where tax_period_id = p_tax_period_id and is_current;
  if found then
    v_debit := coalesce((v_det.totals_snapshot->>'debit_fiscal')::numeric, 0);
    v_credit := coalesce((v_det.totals_snapshot->>'credit_fiscal_computable')::numeric, 0);
  end if;

  select coalesce(sum(jl.debit - jl.credit), 0) into v_out_bal
  from public.journal_entry_lines jl
  join public.journal_entries je on je.id = jl.journal_entry_id
  where jl.organization_id = v_period.organization_id
    and jl.account_id = v_out_acct
    and je.status = 'POSTED'
    and je.entry_date between v_period.period_start and v_period.period_end;

  select coalesce(sum(jl.debit - jl.credit), 0) into v_in_bal
  from public.journal_entry_lines jl
  join public.journal_entries je on je.id = jl.journal_entry_id
  where jl.organization_id = v_period.organization_id
    and jl.account_id = v_in_acct
    and je.status = 'POSTED'
    and je.entry_date between v_period.period_start and v_period.period_end;

  return jsonb_build_object(
    'status', 'OK',
    'vat_output_account_id', v_out_acct,
    'vat_input_account_id', v_in_acct,
    'workpaper_debit', v_debit,
    'ledger_vat_output_movement', v_out_bal,
    'debit_difference', v_debit - abs(v_out_bal),
    'workpaper_credit_computable', v_credit,
    'ledger_vat_input_movement', v_in_bal,
    'credit_difference', v_credit - abs(v_in_bal),
    'auto_fixed', false
  );
end;
$$;

CREATE OR REPLACE FUNCTION "public"."record_tax_filing_external"("p_tax_period_id" "uuid", "p_filing_kind" "public"."tax_filing_kind", "p_external_form_code" "text", "p_external_receipt_number" "text", "p_filed_at" timestamp with time zone, "p_evidence_reference" "text" DEFAULT NULL::"text", "p_evidence_hash" "text" DEFAULT NULL::"text", "p_supersedes_filing_id" "uuid" DEFAULT NULL::"uuid") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_uid uuid;
  v_period public.tax_periods%rowtype;
  v_prior public.tax_filing_records%rowtype;
  v_id uuid;
  v_walk uuid;
  v_guard int := 0;
begin
  select * into v_period from public.tax_periods where id = p_tax_period_id;
  if not found then raise exception 'tax period not found'; end if;
  v_uid := public.tax_assert_role(
    v_period.organization_id,
    array['owner','accountant']::public.member_role[]
  );
  perform public.tax_assert_feature(v_period.organization_id);

  if p_external_receipt_number is null or length(trim(p_external_receipt_number)) < 1 then
    raise exception 'external receipt required for FILED_EXTERNAL';
  end if;

  if p_filing_kind = 'ORIGINAL' then
    if p_supersedes_filing_id is not null then
      raise exception 'ORIGINAL filing must have supersedes_filing_id NULL';
    end if;
  elsif p_filing_kind = 'RECTIFICATION' then
    if p_supersedes_filing_id is null then
      raise exception 'rectification requires supersedes_filing_id';
    end if;
    if p_supersedes_filing_id = p_tax_period_id then
      raise exception 'invalid supersedes reference';
    end if;

    select * into v_prior
    from public.tax_filing_records
    where id = p_supersedes_filing_id
    for share;

    if not found then
      raise exception 'superseded filing not found';
    end if;
    if v_prior.organization_id is distinct from v_period.organization_id then
      raise exception 'cross-tenant filing rectification denied';
    end if;
    if v_prior.tax_period_id is distinct from v_period.id then
      raise exception 'rectification must target same tax period';
    end if;
    if v_prior.tax_code is distinct from v_period.tax_code then
      raise exception 'rectification must target same tax_code';
    end if;
    if v_prior.jurisdiction_code is distinct from v_period.jurisdiction_code then
      raise exception 'rectification must target same jurisdiction';
    end if;
    if v_prior.status is distinct from 'FILED_EXTERNAL' then
      raise exception 'can only rectify FILED_EXTERNAL evidence';
    end if;

    -- Cycle guard: walk supersedes chain
    v_walk := v_prior.supersedes_filing_id;
    while v_walk is not null loop
      v_guard := v_guard + 1;
      if v_guard > 50 then
        raise exception 'filing chain too deep / cyclic';
      end if;
      if v_walk = p_supersedes_filing_id then
        raise exception 'cyclic filing rectification chain';
      end if;
      select supersedes_filing_id into v_walk
      from public.tax_filing_records
      where id = v_walk
        and organization_id = v_period.organization_id;
    end loop;
  else
    raise exception 'unsupported filing_kind';
  end if;

  perform set_config('tax.engine_write', '1', true);
  insert into public.tax_filing_records (
    organization_id, tax_period_id, tax_code, jurisdiction_code,
    filing_kind, status, external_form_code, external_receipt_number,
    filed_at, filed_by, evidence_reference, evidence_hash, supersedes_filing_id
  ) values (
    v_period.organization_id, v_period.id, v_period.tax_code, v_period.jurisdiction_code,
    p_filing_kind, 'FILED_EXTERNAL', p_external_form_code, p_external_receipt_number,
    coalesce(p_filed_at, timezone('utc', now())), v_uid,
    p_evidence_reference, p_evidence_hash, p_supersedes_filing_id
  )
  returning id into v_id;
  return v_id;
end;
$$;

CREATE OR REPLACE FUNCTION "public"."record_tax_payment_external"("p_tax_obligation_id" "uuid", "p_payment_date" "date", "p_amount" numeric, "p_external_reference" "text", "p_payment_method_description" "text" DEFAULT NULL::"text", "p_evidence_reference" "text" DEFAULT NULL::"text", "p_evidence_hash" "text" DEFAULT NULL::"text") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_uid uuid;
  v_obl public.tax_obligations%rowtype;
  v_id uuid;
  v_paid numeric(19, 4);
  v_outstanding numeric(19, 4);
begin
  select * into v_obl from public.tax_obligations where id = p_tax_obligation_id for update;
  if not found then raise exception 'obligation not found'; end if;
  v_uid := public.tax_assert_role(
    v_obl.organization_id,
    array['owner','accountant']::public.member_role[]
  );
  perform public.tax_assert_feature(v_obl.organization_id);

  if p_amount is null or p_amount <= 0 then
    raise exception 'payment amount must be > 0';
  end if;
  if p_external_reference is null or length(trim(p_external_reference)) < 1 then
    raise exception 'external_reference required';
  end if;

  -- Idempotent retry: same evidence identity returns existing row
  select id into v_id
  from public.tax_payment_records
  where organization_id = v_obl.organization_id
    and tax_obligation_id = v_obl.id
    and external_reference = p_external_reference
    and payment_date = p_payment_date
    and amount = p_amount
  limit 1;
  if v_id is not null then
    return v_id;
  end if;

  select coalesce(sum(amount), 0) into v_paid
  from public.tax_payment_records
  where tax_obligation_id = v_obl.id;

  v_outstanding := v_obl.amount - v_paid;
  if v_outstanding < 0 then
    v_outstanding := 0;
  end if;

  if p_amount > v_outstanding then
    raise exception 'TAX_PAYMENT_EXCEEDS_OUTSTANDING';
  end if;

  perform set_config('tax.engine_write', '1', true);
  begin
    insert into public.tax_payment_records (
      organization_id, tax_obligation_id, payment_date, amount, external_reference,
      payment_method_description, evidence_reference, evidence_hash, recorded_by
    ) values (
      v_obl.organization_id, v_obl.id, p_payment_date, p_amount, p_external_reference,
      p_payment_method_description, p_evidence_reference, p_evidence_hash, v_uid
    )
    returning id into v_id;
  exception
    when unique_violation then
      select id into v_id
      from public.tax_payment_records
      where organization_id = v_obl.organization_id
        and tax_obligation_id = v_obl.id
        and external_reference = p_external_reference
        and payment_date = p_payment_date
        and amount = p_amount
      limit 1;
      return v_id;
  end;

  select coalesce(sum(amount), 0) into v_paid
  from public.tax_payment_records where tax_obligation_id = v_obl.id;
  v_outstanding := v_obl.amount - v_paid;
  if v_outstanding < 0 then
    raise exception 'negative outstanding forbidden';
  end if;

  update public.tax_obligations
  set status = case
      when v_outstanding = 0 then 'PAID'::public.tax_obligation_status
      when v_paid > 0 then 'PARTIALLY_PAID'::public.tax_obligation_status
      else 'OPEN'::public.tax_obligation_status
    end,
    updated_at = timezone('utc', now())
  where id = v_obl.id;

  return v_id;
end;
$$;

CREATE OR REPLACE FUNCTION "public"."register_tax_wp"("p_organization_id" "uuid", "p_wp_type" "public"."tax_wp_type", "p_tax_code" "public"."tax_code", "p_operation_date" "date", "p_tax_period_date" "date", "p_amount" numeric, "p_certificate_number" "text" DEFAULT NULL::"text", "p_jurisdiction_code" "text" DEFAULT NULL::"text", "p_counterparty_id" "uuid" DEFAULT NULL::"uuid") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_uid uuid;
  v_id uuid;
begin
  v_uid := public.tax_assert_role(
    p_organization_id,
    array['owner','admin','accountant','manager']::public.member_role[]
  );
  perform public.tax_assert_feature(p_organization_id);
  insert into public.tax_withholdings_perceptions (
    organization_id, counterparty_id, wp_type, tax_code, jurisdiction_code,
    certificate_number, operation_date, tax_period_date, amount, status, created_by
  ) values (
    p_organization_id, p_counterparty_id, p_wp_type, p_tax_code, p_jurisdiction_code,
    p_certificate_number, p_operation_date, p_tax_period_date, p_amount, 'CONFIRMED', v_uid
  )
  returning id into v_id;
  return v_id;
exception
  when unique_violation then
    raise exception 'duplicate withholding/perception certificate';
end;
$$;

CREATE OR REPLACE FUNCTION "public"."reopen_tax_period"("p_tax_period_id" "uuid", "p_reason" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_uid uuid;
  v_period public.tax_periods%rowtype;
begin
  if p_reason is null or length(trim(p_reason)) < 3 then
    raise exception 'reopen reason mandatory';
  end if;
  select * into v_period from public.tax_periods where id = p_tax_period_id for update;
  if not found then raise exception 'tax period not found'; end if;
  v_uid := public.tax_assert_role(
    v_period.organization_id,
    array['owner','accountant']::public.member_role[]
  );
  perform public.tax_assert_feature(v_period.organization_id);
  if v_period.status is distinct from 'CLOSED' then
    raise exception 'only CLOSED periods can be reopened';
  end if;

  perform set_config('tax.engine_write', '1', true);
  update public.tax_periods
  set status = 'REOPENED',
      reopen_reason = p_reason,
      reopened_by = v_uid,
      reopened_at = timezone('utc', now())
  where id = v_period.id;
end;
$$;

CREATE OR REPLACE FUNCTION "public"."revalidate_tax_determination_sources"("p_tax_period_id" "uuid") RETURNS "text"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_period public.tax_periods%rowtype;
  v_det public.tax_determinations%rowtype;
  v_src public.tax_determination_sources%rowtype;
  v_fd public.fiscal_documents%rowtype;
  v_fts public.fiscal_tax_summaries%rowtype;
  v_pd public.purchase_documents%rowtype;
  v_pts public.purchase_document_tax_summaries%rowtype;
  v_cls public.vat_purchase_classifications%rowtype;
  v_new text;
  v_changed boolean := false;
begin
  select * into v_period from public.tax_periods where id = p_tax_period_id;
  if not found then raise exception 'tax period not found'; end if;
  if not public.is_org_member(v_period.organization_id) then
    raise exception 'not a member';
  end if;

  select * into v_det
  from public.tax_determinations
  where tax_period_id = p_tax_period_id and is_current
  limit 1;
  if not found then
    return 'NO_DETERMINATION';
  end if;

  for v_src in
    select * from public.tax_determination_sources
    where tax_determination_id = v_det.id
  loop
    if v_src.source_domain = 'FISCAL_DOCUMENT' then
      select * into v_fd from public.fiscal_documents where id = v_src.source_id;
      select * into v_fts from public.fiscal_tax_summaries where id = v_src.source_component_id;
      if found and v_fd.id is not null then
        v_new := public.tax_canonical_fiscal_hash(v_fd, v_fts);
        if v_new is distinct from v_src.canonical_source_hash then
          v_changed := true;
        end if;
      else
        v_changed := true;
      end if;
    elsif v_src.source_domain = 'PURCHASE_DOCUMENT' then
      select * into v_pd from public.purchase_documents where id = v_src.source_id;
      select * into v_pts from public.purchase_document_tax_summaries where id = v_src.source_component_id;
      select * into v_cls from public.vat_purchase_classifications where id = v_src.classification_id;
      if v_pd.id is not null and v_pts.id is not null and v_cls.id is not null then
        v_new := public.tax_canonical_purchase_hash(v_pd, v_pts, v_cls);
        if v_new is distinct from v_src.canonical_source_hash then
          v_changed := true;
        end if;
      else
        v_changed := true;
      end if;
    end if;
  end loop;

  if v_changed and v_det.status in ('REVIEWED', 'CALCULATED') then
    perform set_config('tax.engine_write', '1', true);
    update public.tax_determinations
    set status = 'STALE',
        stale_detected_at = timezone('utc', now()),
        stale_reason = 'Los datos fuente cambiaron desde la última revisión.'
    where id = v_det.id;
    update public.tax_periods
    set source_changed = true
    where id = v_period.id;
    return 'SOURCE_CHANGED';
  end if;

  if v_changed then
    return 'SOURCE_CHANGED';
  end if;
  return 'OK';
end;
$$;

CREATE OR REPLACE FUNCTION "public"."review_tax_period"("p_tax_period_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_uid uuid;
  v_period public.tax_periods%rowtype;
  v_det public.tax_determinations%rowtype;
  v_reval text;
begin
  select * into v_period from public.tax_periods where id = p_tax_period_id for update;
  if not found then raise exception 'tax period not found'; end if;

  v_uid := public.tax_assert_role(
    v_period.organization_id,
    array['owner','accountant']::public.member_role[]
  );
  perform public.tax_assert_feature(v_period.organization_id);

  select * into v_det from public.tax_determinations
  where tax_period_id = p_tax_period_id and is_current;
  if not found then raise exception 'calculate determination first'; end if;
  if v_det.status = 'REVIEW_REQUIRED' then
    raise exception 'unresolved REVIEW_REQUIRED items remain';
  end if;
  if v_det.status = 'STALE' then
    raise exception 'SOURCE_CHANGED — recalculate after reopen if closed';
  end if;

  v_reval := public.revalidate_tax_determination_sources(p_tax_period_id);
  if v_reval = 'SOURCE_CHANGED' then
    raise exception 'Los datos fuente cambiaron desde la última revisión.';
  end if;

  perform set_config('tax.engine_write', '1', true);
  update public.tax_determinations
  set status = 'REVIEWED', reviewed_by = v_uid, reviewed_at = timezone('utc', now())
  where id = v_det.id;
  update public.tax_periods
  set status = 'REVIEWED', reviewed_by = v_uid, reviewed_at = timezone('utc', now()), source_changed = false
  where id = v_period.id;
end;
$$;

CREATE OR REPLACE FUNCTION "public"."tax_assert_feature"("p_org_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  if not exists (
    select 1
    from public.organization_features ofeat
    join public.feature_catalog fc on fc.id = ofeat.feature_id
    where ofeat.organization_id = p_org_id
      and fc.code = 'taxes'
      and ofeat.status = 'enabled'
  ) then
    raise exception 'feature taxes is not enabled';
  end if;
end;
$$;

CREATE OR REPLACE FUNCTION "public"."tax_assert_role"("p_org_id" "uuid", "p_roles" "public"."member_role"[]) RETURNS "uuid"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'authentication required';
  end if;
  if not public.has_org_role(p_org_id, p_roles) then
    raise exception 'insufficient role for tax operation';
  end if;
  return v_uid;
end;
$$;

CREATE OR REPLACE FUNCTION "public"."tax_assert_service_role"() RETURNS "void"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
begin
  if auth.role() is distinct from 'service_role' then
    raise exception 'global tax rule governance requires service_role (platform governance)';
  end if;
end;
$$;

CREATE OR REPLACE FUNCTION "public"."tax_canonical_fiscal_hash"("p_doc" "public"."fiscal_documents", "p_summary" "public"."fiscal_tax_summaries") RETURNS "text"
    LANGUAGE "plpgsql" STABLE
    SET "search_path" TO ''
    AS $$
begin
  return public.tax_sha256(
    concat_ws('|',
      p_doc.id::text,
      p_doc.status::text,
      p_doc.document_class::text,
      p_doc.issue_date::text,
      coalesce(p_doc.fiscal_environment::text, ''),
      coalesce(p_doc.net_taxed_amount::text, '0'),
      coalesce(p_doc.net_exempt_amount::text, '0'),
      coalesce(p_doc.net_untaxed_amount::text, '0'),
      coalesce(p_doc.vat_amount::text, '0'),
      coalesce(p_doc.other_taxes_amount::text, '0'),
      coalesce(p_doc.related_fiscal_document_id::text, ''),
      coalesce(p_doc.relationship_type::text, ''),
      coalesce(p_summary.id::text, ''),
      coalesce(p_summary.summary_kind, ''),
      coalesce(p_summary.code, ''),
      coalesce(p_summary.base_amount::text, '0'),
      coalesce(p_summary.rate::text, '0'),
      coalesce(p_summary.amount::text, '0')
    )
  );
end;
$$;

CREATE OR REPLACE FUNCTION "public"."tax_canonical_purchase_hash"("p_doc" "public"."purchase_documents", "p_summary" "public"."purchase_document_tax_summaries", "p_class" "public"."vat_purchase_classifications") RETURNS "text"
    LANGUAGE "plpgsql" STABLE
    SET "search_path" TO ''
    AS $$
begin
  return public.tax_sha256(
    concat_ws('|',
      p_doc.id::text,
      p_doc.status::text,
      p_doc.issue_date::text,
      coalesce(p_doc.accounting_date::text, ''),
      coalesce(p_doc.vat_amount::text, '0'),
      coalesce(p_summary.id::text, ''),
      coalesce(p_summary.summary_kind, ''),
      coalesce(p_summary.code, ''),
      coalesce(p_summary.amount::text, '0'),
      coalesce(p_class.id::text, ''),
      coalesce(p_class.classification::text, ''),
      coalesce(p_class.informed_vat_amount::text, '0'),
      coalesce(p_class.computable_amount::text, '0'),
      coalesce(p_class.noncomputable_amount::text, '0'),
      coalesce(p_class.status, '')
    )
  );
end;
$$;

CREATE OR REPLACE FUNCTION "public"."tax_fiscal_vat_economic_sign"("p_operation_kind" "public"."fiscal_operation_kind") RETURNS numeric
    LANGUAGE "sql" IMMUTABLE
    SET "search_path" TO ''
    AS $$
  select case p_operation_kind
    when 'INVOICE' then 1::numeric
    when 'DEBIT_NOTE' then 1::numeric
    when 'CREDIT_NOTE' then -1::numeric
    else 1::numeric
  end;
$$;

CREATE OR REPLACE FUNCTION "public"."tax_obligation_outstanding"("p_tax_obligation_id" "uuid") RETURNS numeric
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  select o.amount - coalesce((
    select sum(p.amount) from public.tax_payment_records p where p.tax_obligation_id = o.id
  ), 0)
  from public.tax_obligations o
  where o.id = p_tax_obligation_id
    and public.is_org_member(o.organization_id);
$$;

CREATE OR REPLACE FUNCTION "public"."tax_resolve_active_rule"("p_tax_code" "public"."tax_code", "p_jurisdiction_code" "text", "p_rule_key" "text", "p_as_of" "date") RETURNS "public"."tax_rule_versions"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_row public.tax_rule_versions%rowtype;
begin
  select trv.* into v_row
  from public.tax_rule_versions trv
  join public.tax_rule_sets trs on trs.id = trv.rule_set_id
  where trs.tax_code = p_tax_code
    and trs.rule_key = p_rule_key
    and (
      (p_jurisdiction_code is null and trs.jurisdiction_code is null)
      or trs.jurisdiction_code = p_jurisdiction_code
      or (p_jurisdiction_code is not null and trs.jurisdiction_code = p_jurisdiction_code)
    )
    and trv.status = 'ACTIVE'
    and trv.effective_from <= p_as_of
    and (trv.effective_to is null or trv.effective_to >= p_as_of)
  order by trv.effective_from desc
  limit 1;

  if not found then
    -- fallback NATIONAL jurisdiction key when period jurisdiction null
    select trv.* into v_row
    from public.tax_rule_versions trv
    join public.tax_rule_sets trs on trs.id = trv.rule_set_id
    where trs.tax_code = p_tax_code
      and trs.rule_key = p_rule_key
      and trs.jurisdiction_code = 'NATIONAL'
      and trv.status = 'ACTIVE'
      and trv.effective_from <= p_as_of
      and (trv.effective_to is null or trv.effective_to >= p_as_of)
    order by trv.effective_from desc
    limit 1;
  end if;

  if not found then
    raise exception 'no ACTIVE tax rule for % / % / % as of %',
      p_tax_code, p_jurisdiction_code, p_rule_key, p_as_of;
  end if;

  return v_row;
end;
$$;

CREATE OR REPLACE FUNCTION "public"."tax_resolve_effective_date"("p_tax_code" "public"."tax_code", "p_source_domain" "public"."tax_source_domain", "p_issue_date" "date", "p_accounting_date" "date", "p_rule_version" "public"."tax_rule_versions") RETURNS "date"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_field text;
begin
  if p_rule_version.id is null then
    raise exception 'attribution rule version required';
  end if;

  v_field := coalesce(p_rule_version.rule_payload->>'tax_effective_date_field', 'issue_date');

  if p_source_domain = 'FISCAL_DOCUMENT' then
    if v_field = 'issue_date' then
      if p_issue_date is null then
        return null; -- caller → REVIEW_REQUIRED
      end if;
      return p_issue_date;
    end if;
    return null;
  end if;

  if p_source_domain = 'PURCHASE_DOCUMENT' then
    if v_field = 'issue_date' then
      return p_issue_date;
    elsif v_field = 'accounting_date' then
      return coalesce(p_accounting_date, p_issue_date);
    elsif v_field = 'coalesce_issue_accounting' then
      return coalesce(p_issue_date, p_accounting_date);
    else
      return null; -- ambiguous / unknown → REVIEW_REQUIRED
    end if;
  end if;

  return null;
end;
$$;

CREATE OR REPLACE FUNCTION "public"."tax_sha256"("p_text" "text") RETURNS "text"
    LANGUAGE "sql" IMMUTABLE
    SET "search_path" TO ''
    AS $$
  select encode(extensions.digest(convert_to(p_text, 'UTF8'), 'sha256'::text), 'hex');
$$;

CREATE OR REPLACE FUNCTION "public"."tax_test_fixture_purchase_iva_components"("p_organization_id" "uuid", "p_supplier_id" "uuid", "p_issue_date" "date", "p_components" "jsonb") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_doc_id uuid;
  v_comp jsonb;
  v_sum_id uuid;
  v_total_vat numeric(19,4) := 0;
  v_total_net numeric(19,4) := 0;
  v_amt numeric(19,4);
  v_base numeric(19,4);
  v_code text;
  v_num bigint := (extract(epoch from clock_timestamp()) * 1000)::bigint;
begin
  if auth.role() is distinct from 'service_role' then
    raise exception 'tax_test_fixture_purchase_iva_components is service_role only';
  end if;

  for v_comp in select * from jsonb_array_elements(p_components)
  loop
    v_total_vat := v_total_vat + coalesce((v_comp->>'amount')::numeric, 0);
    v_total_net := v_total_net + coalesce((v_comp->>'base')::numeric, 0);
  end loop;

  insert into public.purchase_documents (
    organization_id, document_type, status, supplier_id,
    issue_date, accounting_date,
    point_of_sale, document_number, currency_code, currency_rate,
    net_taxed_amount, net_exempt_amount, net_untaxed_amount,
    vat_amount, other_taxes_amount, total_amount,
    accounting_status, idempotency_key
  ) values (
    p_organization_id, 'SUPPLIER_INVOICE', 'REVIEWED', p_supplier_id,
    p_issue_date, p_issue_date,
    77, v_num, 'ARS', 1,
    v_total_net, 0, 0,
    v_total_vat, 0, v_total_net + v_total_vat,
    'PENDING', 'tax-fix-pd-' || gen_random_uuid()::text
  )
  returning id into v_doc_id;

  for v_comp in select * from jsonb_array_elements(p_components)
  loop
    v_amt := (v_comp->>'amount')::numeric;
    v_base := coalesce((v_comp->>'base')::numeric, 0);
    v_code := coalesce(v_comp->>'code', '5');
    insert into public.purchase_document_tax_summaries (
      organization_id, purchase_document_id, summary_kind, code, base_amount, rate, amount
    ) values (
      p_organization_id, v_doc_id, 'IVA', v_code, v_base,
      coalesce((v_comp->>'rate')::numeric, 21), v_amt
    )
    returning id into v_sum_id;

    if v_comp ? 'computable' then
      insert into public.vat_purchase_classifications (
        organization_id, purchase_document_id, purchase_tax_summary_id,
        classification, informed_vat_amount, computable_amount, noncomputable_amount,
        status, classified_at
      ) values (
        p_organization_id, v_doc_id, v_sum_id,
        case
          when coalesce((v_comp->>'noncomputable')::numeric, 0) > 0
               and (v_comp->>'computable')::numeric > 0 then 'PARTIAL'::public.vat_credit_classification
          when (v_comp->>'computable')::numeric = v_amt then 'COMPUTABLE'::public.vat_credit_classification
          when (v_comp->>'computable')::numeric = 0 then 'NON_COMPUTABLE'::public.vat_credit_classification
          else 'PARTIAL'::public.vat_credit_classification
        end,
        v_amt,
        (v_comp->>'computable')::numeric,
        coalesce((v_comp->>'noncomputable')::numeric, 0),
        'CONFIRMED', timezone('utc', now())
      );
    end if;
  end loop;

  return v_doc_id;
end;
$$;

CREATE OR REPLACE FUNCTION "public"."upsert_iibb_jurisdiction_allocation"("p_tax_period_id" "uuid", "p_jurisdiction_code" "text", "p_distribution_method" "public"."iibb_distribution_method", "p_sales_allocation_strategy" "public"."iibb_sales_allocation_strategy", "p_gross_revenue_amount" numeric DEFAULT 0, "p_cm_form_code" "public"."tax_cm_form_code" DEFAULT 'CM03'::"public"."tax_cm_form_code", "p_coefficient" numeric DEFAULT NULL::numeric, "p_narrative" "text" DEFAULT NULL::"text") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_uid uuid;
  v_period public.tax_periods%rowtype;
  v_id uuid;
  v_review text := 'OK';
  v_method public.iibb_distribution_method := p_distribution_method;
begin
  select * into v_period from public.tax_periods where id = p_tax_period_id;
  if not found then raise exception 'tax period not found'; end if;
  v_uid := public.tax_assert_role(
    v_period.organization_id,
    array['owner','admin','accountant']::public.member_role[]
  );
  perform public.tax_assert_feature(v_period.organization_id);

  if p_sales_allocation_strategy = 'REVIEW_REQUIRED'
     or p_jurisdiction_code is null then
    v_review := 'REVIEW_REQUIRED';
  end if;
  if v_method = 'SPECIAL_REGIME' then
    v_method := 'MANUAL_REVIEW';
    v_review := 'MANUAL_REVIEW';
  end if;
  if v_method = 'GENERAL' and p_coefficient is null and v_period.tax_code = 'IIBB_CM' then
    raise exception 'missing CM coefficient — cannot finalize general CM determination';
  end if;

  insert into public.iibb_jurisdiction_allocations (
    organization_id, tax_period_id, jurisdiction_code, cm_form_code,
    distribution_method, sales_allocation_strategy, gross_revenue_amount,
    coefficient, review_status, narrative
  ) values (
    v_period.organization_id, v_period.id, p_jurisdiction_code, p_cm_form_code,
    v_method, p_sales_allocation_strategy, p_gross_revenue_amount,
    p_coefficient, v_review, p_narrative
  )
  on conflict (tax_period_id, jurisdiction_code) do update set
    distribution_method = excluded.distribution_method,
    sales_allocation_strategy = excluded.sales_allocation_strategy,
    gross_revenue_amount = excluded.gross_revenue_amount,
    coefficient = excluded.coefficient,
    cm_form_code = excluded.cm_form_code,
    review_status = excluded.review_status,
    narrative = excluded.narrative,
    updated_at = timezone('utc', now())
  returning id into v_id;
  return v_id;
end;
$$;

CREATE OR REPLACE FUNCTION "public"."upsert_organization_tax_registration"("p_organization_id" "uuid", "p_tax_code" "public"."tax_code", "p_jurisdiction_code" "text", "p_registration_number" "text" DEFAULT NULL::"text", "p_effective_from" "date" DEFAULT CURRENT_DATE, "p_regime_metadata" "jsonb" DEFAULT '{}'::"jsonb") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_uid uuid;
  v_id uuid;
begin
  v_uid := public.tax_assert_role(
    p_organization_id,
    array['owner','admin','accountant']::public.member_role[]
  );
  perform public.tax_assert_feature(p_organization_id);

  update public.organization_tax_registrations
  set status = 'INACTIVE', updated_at = timezone('utc', now())
  where organization_id = p_organization_id
    and tax_code = p_tax_code
    and jurisdiction_code = p_jurisdiction_code
    and status = 'ACTIVE';

  insert into public.organization_tax_registrations (
    organization_id, tax_code, jurisdiction_code, registration_number,
    status, effective_from, regime_metadata, created_by
  ) values (
    p_organization_id, p_tax_code, p_jurisdiction_code, p_registration_number,
    'ACTIVE', p_effective_from, coalesce(p_regime_metadata, '{}'::jsonb), v_uid
  )
  returning id into v_id;
  return v_id;
end;
$$;

CREATE OR REPLACE FUNCTION "public"."upsert_vat_purchase_classification"("p_organization_id" "uuid", "p_purchase_document_id" "uuid", "p_purchase_tax_summary_id" "uuid", "p_classification" "public"."vat_credit_classification", "p_computable_amount" numeric, "p_noncomputable_amount" numeric, "p_reason_code" "text" DEFAULT NULL::"text", "p_reason_notes" "text" DEFAULT NULL::"text") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_uid uuid;
  v_sum public.purchase_document_tax_summaries%rowtype;
  v_id uuid;
  v_informed numeric(19,4);
begin
  v_uid := public.tax_assert_role(
    p_organization_id,
    array['owner','admin','accountant']::public.member_role[]
  );
  perform public.tax_assert_feature(p_organization_id);

  select * into v_sum
  from public.purchase_document_tax_summaries
  where id = p_purchase_tax_summary_id
    and organization_id = p_organization_id
    and purchase_document_id = p_purchase_document_id;

  if not found then
    raise exception 'purchase tax summary not found';
  end if;
  if v_sum.summary_kind is distinct from 'IVA' then
    raise exception 'classification only for IVA tax summaries';
  end if;

  v_informed := v_sum.amount;
  if p_computable_amount < 0 or p_noncomputable_amount < 0 then
    raise exception 'classification amounts must be >= 0';
  end if;
  if abs((p_computable_amount + p_noncomputable_amount) - v_informed) > 0.01 then
    raise exception 'computable + noncomputable must equal informed component amount';
  end if;

  update public.vat_purchase_classifications
  set status = 'SUPERSEDED', updated_at = timezone('utc', now())
  where purchase_tax_summary_id = p_purchase_tax_summary_id
    and status = 'CONFIRMED';

  insert into public.vat_purchase_classifications (
    organization_id, purchase_document_id, purchase_tax_summary_id,
    classification, informed_vat_amount, computable_amount, noncomputable_amount,
    reason_code, reason_notes, classified_by, classified_at, status
  ) values (
    p_organization_id, p_purchase_document_id, p_purchase_tax_summary_id,
    p_classification, v_informed, p_computable_amount, p_noncomputable_amount,
    p_reason_code, p_reason_notes, v_uid, timezone('utc', now()), 'CONFIRMED'
  )
  returning id into v_id;
  return v_id;
end;
$$;

CREATE INDEX "iibb_alloc_det_idx" ON "public"."iibb_jurisdiction_allocations" USING "btree" ("tax_determination_id");

CREATE INDEX "iibb_alloc_jurisdiction_idx" ON "public"."iibb_jurisdiction_allocations" USING "btree" ("jurisdiction_code");

CREATE INDEX "iibb_alloc_org_period_idx" ON "public"."iibb_jurisdiction_allocations" USING "btree" ("organization_id", "tax_period_id");

CREATE INDEX "iibb_alloc_period_idx" ON "public"."iibb_jurisdiction_allocations" USING "btree" ("tax_period_id", "review_status");

CREATE INDEX "iibb_alloc_rule_idx" ON "public"."iibb_jurisdiction_allocations" USING "btree" ("rule_version_id");

CREATE INDEX "iibb_cm_coef_activated_by_idx" ON "public"."iibb_cm_coefficients" USING "btree" ("activated_by");

CREATE UNIQUE INDEX "iibb_cm_coef_active_unique" ON "public"."iibb_cm_coefficients" USING "btree" ("organization_id", "fiscal_year", "jurisdiction_code") WHERE ("status" = 'ACTIVE'::"public"."tax_rule_status");

CREATE INDEX "iibb_cm_coef_jurisdiction_idx" ON "public"."iibb_cm_coefficients" USING "btree" ("jurisdiction_code");

CREATE INDEX "iibb_cm_coef_org_year_idx" ON "public"."iibb_cm_coefficients" USING "btree" ("organization_id", "fiscal_year", "status");

CREATE INDEX "iibb_cm_coef_reviewed_by_idx" ON "public"."iibb_cm_coefficients" USING "btree" ("reviewed_by");

CREATE INDEX "iibb_coef_rule_idx" ON "public"."iibb_cm_coefficients" USING "btree" ("rule_version_id");

CREATE UNIQUE INDEX "org_tax_reg_active_unique" ON "public"."organization_tax_registrations" USING "btree" ("organization_id", "tax_code", "jurisdiction_code") WHERE ("status" = 'ACTIVE'::"public"."tax_registration_status");

CREATE INDEX "org_tax_reg_created_by_idx" ON "public"."organization_tax_registrations" USING "btree" ("created_by");

CREATE INDEX "org_tax_reg_jurisdiction_idx" ON "public"."organization_tax_registrations" USING "btree" ("jurisdiction_code");

CREATE INDEX "org_tax_reg_org_idx" ON "public"."organization_tax_registrations" USING "btree" ("organization_id", "tax_code");

CREATE INDEX "tax_adj_approved_by_idx" ON "public"."tax_adjustments" USING "btree" ("approved_by");

CREATE INDEX "tax_adj_created_by_idx" ON "public"."tax_adjustments" USING "btree" ("created_by");

CREATE INDEX "tax_adj_org_period_idx" ON "public"."tax_adjustments" USING "btree" ("organization_id", "tax_period_id");

CREATE INDEX "tax_adj_period_idx" ON "public"."tax_adjustments" USING "btree" ("tax_period_id", "status");

CREATE INDEX "tax_adj_reversed_by_idx" ON "public"."tax_adjustments" USING "btree" ("reversed_by");

CREATE INDEX "tax_det_calculated_by_idx" ON "public"."tax_determinations" USING "btree" ("calculated_by");

CREATE UNIQUE INDEX "tax_det_current_unique" ON "public"."tax_determinations" USING "btree" ("tax_period_id") WHERE "is_current";

CREATE INDEX "tax_det_line_det_idx" ON "public"."tax_determination_lines" USING "btree" ("tax_determination_id", "sort_order");

CREATE INDEX "tax_det_line_org_det_idx" ON "public"."tax_determination_lines" USING "btree" ("organization_id", "tax_determination_id");

CREATE INDEX "tax_det_line_org_idx" ON "public"."tax_determination_lines" USING "btree" ("organization_id");

CREATE INDEX "tax_det_line_src_idx" ON "public"."tax_determination_lines" USING "btree" ("tax_determination_source_id");

CREATE INDEX "tax_det_org_period_idx" ON "public"."tax_determinations" USING "btree" ("organization_id", "tax_period_id", "is_current");

CREATE INDEX "tax_det_reviewed_by_idx" ON "public"."tax_determinations" USING "btree" ("reviewed_by");

CREATE INDEX "tax_det_rule_snap_det_idx" ON "public"."tax_determination_rule_snapshots" USING "btree" ("tax_determination_id");

CREATE INDEX "tax_det_rule_snap_org_det_idx" ON "public"."tax_determination_rule_snapshots" USING "btree" ("organization_id", "tax_determination_id");

CREATE INDEX "tax_det_rule_snap_org_idx" ON "public"."tax_determination_rule_snapshots" USING "btree" ("organization_id");

CREATE INDEX "tax_det_rule_snap_ver_idx" ON "public"."tax_determination_rule_snapshots" USING "btree" ("tax_rule_version_id");

CREATE INDEX "tax_det_src_attr_rule_idx" ON "public"."tax_determination_sources" USING "btree" ("attribution_rule_version_id");

CREATE INDEX "tax_det_src_class_idx" ON "public"."tax_determination_sources" USING "btree" ("classification_id");

CREATE INDEX "tax_det_src_det_idx" ON "public"."tax_determination_sources" USING "btree" ("tax_determination_id", "sort_key");

CREATE INDEX "tax_det_src_org_det_idx" ON "public"."tax_determination_sources" USING "btree" ("organization_id", "tax_determination_id");

CREATE INDEX "tax_det_src_org_idx" ON "public"."tax_determination_sources" USING "btree" ("organization_id");

CREATE INDEX "tax_det_src_rule_idx" ON "public"."tax_determination_sources" USING "btree" ("rule_version_id");

CREATE UNIQUE INDEX "tax_det_src_unique_idx" ON "public"."tax_determination_sources" USING "btree" ("tax_determination_id", "source_domain", "source_id", COALESCE("source_component_id", '00000000-0000-0000-0000-000000000000'::"uuid"));

CREATE INDEX "tax_filing_filed_by_idx" ON "public"."tax_filing_records" USING "btree" ("filed_by");

CREATE INDEX "tax_filing_jurisdiction_idx" ON "public"."tax_filing_records" USING "btree" ("jurisdiction_code");

CREATE INDEX "tax_filing_org_period_idx" ON "public"."tax_filing_records" USING "btree" ("organization_id", "tax_period_id");

CREATE INDEX "tax_filing_period_idx" ON "public"."tax_filing_records" USING "btree" ("tax_period_id", "created_at");

CREATE INDEX "tax_filing_supersedes_idx" ON "public"."tax_filing_records" USING "btree" ("supersedes_filing_id");

CREATE INDEX "tax_filing_supersedes_org_idx" ON "public"."tax_filing_records" USING "btree" ("organization_id", "supersedes_filing_id");

CREATE INDEX "tax_obl_created_by_idx" ON "public"."tax_obligations" USING "btree" ("created_by");

CREATE INDEX "tax_obl_det_idx" ON "public"."tax_obligations" USING "btree" ("tax_determination_id");

CREATE INDEX "tax_obl_jurisdiction_idx" ON "public"."tax_obligations" USING "btree" ("jurisdiction_code");

CREATE INDEX "tax_obl_org_det_comp_idx" ON "public"."tax_obligations" USING "btree" ("organization_id", "tax_determination_id");

CREATE INDEX "tax_obl_org_period_comp_idx" ON "public"."tax_obligations" USING "btree" ("organization_id", "tax_period_id");

CREATE INDEX "tax_obl_period_idx" ON "public"."tax_obligations" USING "btree" ("tax_period_id", "status");

CREATE INDEX "tax_pay_obl_idx" ON "public"."tax_payment_records" USING "btree" ("tax_obligation_id", "payment_date");

CREATE INDEX "tax_pay_org_obl_comp_idx" ON "public"."tax_payment_records" USING "btree" ("organization_id", "tax_obligation_id");

CREATE INDEX "tax_pay_recorded_by_idx" ON "public"."tax_payment_records" USING "btree" ("recorded_by");

CREATE UNIQUE INDEX "tax_payment_evidence_idempotent_uidx" ON "public"."tax_payment_records" USING "btree" ("organization_id", "tax_obligation_id", "external_reference", "payment_date", "amount");

CREATE INDEX "tax_periods_closed_by_idx" ON "public"."tax_periods" USING "btree" ("closed_by");

CREATE INDEX "tax_periods_jurisdiction_idx" ON "public"."tax_periods" USING "btree" ("jurisdiction_code");

CREATE INDEX "tax_periods_org_status_idx" ON "public"."tax_periods" USING "btree" ("organization_id", "tax_code", "status", "period_year" DESC, "period_month" DESC);

CREATE INDEX "tax_periods_reopened_by_idx" ON "public"."tax_periods" USING "btree" ("reopened_by");

CREATE INDEX "tax_periods_reviewed_by_idx" ON "public"."tax_periods" USING "btree" ("reviewed_by");

CREATE INDEX "tax_rule_sets_jurisdiction_idx" ON "public"."tax_rule_sets" USING "btree" ("jurisdiction_code");

CREATE INDEX "tax_rule_versions_activated_by_idx" ON "public"."tax_rule_versions" USING "btree" ("activated_by");

CREATE INDEX "tax_rule_versions_reviewed_by_idx" ON "public"."tax_rule_versions" USING "btree" ("reviewed_by");

CREATE INDEX "tax_rule_versions_rule_set_id_idx" ON "public"."tax_rule_versions" USING "btree" ("rule_set_id");

CREATE INDEX "tax_rule_versions_set_status_idx" ON "public"."tax_rule_versions" USING "btree" ("rule_set_id", "status", "effective_from");

CREATE UNIQUE INDEX "tax_wp_certificate_dedup" ON "public"."tax_withholdings_perceptions" USING "btree" ("organization_id", "tax_code", "wp_type", "certificate_number", "operation_date", "amount") WHERE (("status" = ANY (ARRAY['CONFIRMED'::"public"."tax_wp_status", 'DRAFT'::"public"."tax_wp_status"])) AND ("certificate_number" IS NOT NULL));

CREATE INDEX "tax_wp_created_by_idx" ON "public"."tax_withholdings_perceptions" USING "btree" ("created_by");

CREATE INDEX "tax_wp_jurisdiction_idx" ON "public"."tax_withholdings_perceptions" USING "btree" ("jurisdiction_code");

CREATE INDEX "tax_wp_org_cp_idx" ON "public"."tax_withholdings_perceptions" USING "btree" ("organization_id", "counterparty_id");

CREATE INDEX "tax_wp_org_period_idx" ON "public"."tax_withholdings_perceptions" USING "btree" ("organization_id", "tax_code", "tax_period_date");

CREATE INDEX "vat_class_classified_by_idx" ON "public"."vat_purchase_classifications" USING "btree" ("classified_by");

CREATE INDEX "vat_class_purchase_document_idx" ON "public"."vat_purchase_classifications" USING "btree" ("purchase_document_id");

CREATE INDEX "vat_class_purchase_idx" ON "public"."vat_purchase_classifications" USING "btree" ("organization_id", "purchase_document_id");

CREATE INDEX "vat_class_reviewed_by_idx" ON "public"."vat_purchase_classifications" USING "btree" ("reviewed_by");

CREATE INDEX "vat_class_rule_version_id_idx" ON "public"."vat_purchase_classifications" USING "btree" ("rule_version_id");

CREATE UNIQUE INDEX "vat_class_summary_active_unique" ON "public"."vat_purchase_classifications" USING "btree" ("purchase_tax_summary_id") WHERE ("status" = 'CONFIRMED'::"text");

CREATE OR REPLACE TRIGGER "iibb_jurisdiction_allocations_set_updated_at" BEFORE UPDATE ON "public"."iibb_jurisdiction_allocations" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();

CREATE OR REPLACE TRIGGER "organization_tax_registrations_set_updated_at" BEFORE UPDATE ON "public"."organization_tax_registrations" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();

CREATE OR REPLACE TRIGGER "tax_det_engine_guard" BEFORE INSERT OR DELETE OR UPDATE ON "public"."tax_determinations" FOR EACH ROW EXECUTE FUNCTION "public"."prevent_tax_determination_client_mutation"();

CREATE OR REPLACE TRIGGER "tax_det_line_engine_guard" BEFORE INSERT OR DELETE OR UPDATE ON "public"."tax_determination_lines" FOR EACH ROW EXECUTE FUNCTION "public"."prevent_tax_determination_client_mutation"();

CREATE OR REPLACE TRIGGER "tax_det_rule_snap_engine_guard" BEFORE INSERT OR DELETE OR UPDATE ON "public"."tax_determination_rule_snapshots" FOR EACH ROW EXECUTE FUNCTION "public"."prevent_tax_determination_client_mutation"();

CREATE OR REPLACE TRIGGER "tax_det_src_engine_guard" BEFORE INSERT OR DELETE OR UPDATE ON "public"."tax_determination_sources" FOR EACH ROW EXECUTE FUNCTION "public"."prevent_tax_determination_client_mutation"();

CREATE OR REPLACE TRIGGER "tax_filing_append_only" BEFORE INSERT OR DELETE OR UPDATE ON "public"."tax_filing_records" FOR EACH ROW EXECUTE FUNCTION "public"."prevent_tax_filing_mutation"();

CREATE OR REPLACE TRIGGER "tax_obligations_set_updated_at" BEFORE UPDATE ON "public"."tax_obligations" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();

CREATE OR REPLACE TRIGGER "tax_payment_append_only" BEFORE INSERT OR DELETE OR UPDATE ON "public"."tax_payment_records" FOR EACH ROW EXECUTE FUNCTION "public"."prevent_tax_payment_mutation"();

CREATE OR REPLACE TRIGGER "tax_periods_engine_guard" BEFORE UPDATE ON "public"."tax_periods" FOR EACH ROW EXECUTE FUNCTION "public"."prevent_tax_period_status_forgery"();

CREATE OR REPLACE TRIGGER "tax_rule_versions_active_guard" BEFORE DELETE OR UPDATE ON "public"."tax_rule_versions" FOR EACH ROW EXECUTE FUNCTION "public"."prevent_active_tax_rule_mutation"();

CREATE OR REPLACE TRIGGER "vat_purchase_classifications_set_updated_at" BEFORE UPDATE ON "public"."vat_purchase_classifications" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();

ALTER TABLE "public"."iibb_cm_coefficients" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."iibb_jurisdiction_allocations" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."organization_tax_registrations" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."tax_adjustments" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."tax_determination_lines" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."tax_determination_rule_snapshots" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."tax_determination_sources" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."tax_determinations" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."tax_filing_records" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."tax_jurisdictions" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."tax_obligations" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."tax_payment_records" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."tax_periods" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."tax_rule_sets" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."tax_rule_versions" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."tax_withholdings_perceptions" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."vat_purchase_classifications" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "iibb_alloc_select" ON "public"."iibb_jurisdiction_allocations" FOR SELECT TO "authenticated" USING ("public"."is_org_member"("organization_id"));

CREATE POLICY "iibb_coef_insert" ON "public"."iibb_cm_coefficients" FOR INSERT TO "authenticated" WITH CHECK ("public"."has_org_role"("organization_id", ARRAY['owner'::"public"."member_role", 'accountant'::"public"."member_role"]));

CREATE POLICY "iibb_coef_select" ON "public"."iibb_cm_coefficients" FOR SELECT TO "authenticated" USING ("public"."is_org_member"("organization_id"));

CREATE POLICY "iibb_coef_update" ON "public"."iibb_cm_coefficients" FOR UPDATE TO "authenticated" USING ("public"."has_org_role"("organization_id", ARRAY['owner'::"public"."member_role", 'accountant'::"public"."member_role"])) WITH CHECK ("public"."has_org_role"("organization_id", ARRAY['owner'::"public"."member_role", 'accountant'::"public"."member_role"]));

CREATE POLICY "org_tax_reg_insert" ON "public"."organization_tax_registrations" FOR INSERT TO "authenticated" WITH CHECK ("public"."has_org_role"("organization_id", ARRAY['owner'::"public"."member_role", 'admin'::"public"."member_role", 'accountant'::"public"."member_role"]));

CREATE POLICY "org_tax_reg_select" ON "public"."organization_tax_registrations" FOR SELECT TO "authenticated" USING ("public"."is_org_member"("organization_id"));

CREATE POLICY "org_tax_reg_update" ON "public"."organization_tax_registrations" FOR UPDATE TO "authenticated" USING ("public"."has_org_role"("organization_id", ARRAY['owner'::"public"."member_role", 'admin'::"public"."member_role", 'accountant'::"public"."member_role"])) WITH CHECK ("public"."has_org_role"("organization_id", ARRAY['owner'::"public"."member_role", 'admin'::"public"."member_role", 'accountant'::"public"."member_role"]));

CREATE POLICY "tax_adj_select" ON "public"."tax_adjustments" FOR SELECT TO "authenticated" USING ("public"."is_org_member"("organization_id"));

CREATE POLICY "tax_det_line_select" ON "public"."tax_determination_lines" FOR SELECT TO "authenticated" USING ("public"."is_org_member"("organization_id"));

CREATE POLICY "tax_det_select" ON "public"."tax_determinations" FOR SELECT TO "authenticated" USING ("public"."is_org_member"("organization_id"));

CREATE POLICY "tax_det_snap_select" ON "public"."tax_determination_rule_snapshots" FOR SELECT TO "authenticated" USING ("public"."is_org_member"("organization_id"));

CREATE POLICY "tax_det_src_select" ON "public"."tax_determination_sources" FOR SELECT TO "authenticated" USING ("public"."is_org_member"("organization_id"));

CREATE POLICY "tax_filing_select" ON "public"."tax_filing_records" FOR SELECT TO "authenticated" USING ("public"."is_org_member"("organization_id"));

CREATE POLICY "tax_jurisdictions_select" ON "public"."tax_jurisdictions" FOR SELECT TO "authenticated" USING (true);

CREATE POLICY "tax_obl_select" ON "public"."tax_obligations" FOR SELECT TO "authenticated" USING ("public"."is_org_member"("organization_id"));

CREATE POLICY "tax_pay_select" ON "public"."tax_payment_records" FOR SELECT TO "authenticated" USING ("public"."is_org_member"("organization_id"));

CREATE POLICY "tax_periods_select" ON "public"."tax_periods" FOR SELECT TO "authenticated" USING ("public"."is_org_member"("organization_id"));

CREATE POLICY "tax_rule_sets_select" ON "public"."tax_rule_sets" FOR SELECT TO "authenticated" USING (true);

CREATE POLICY "tax_rule_versions_select" ON "public"."tax_rule_versions" FOR SELECT TO "authenticated" USING (true);

CREATE POLICY "tax_wp_select" ON "public"."tax_withholdings_perceptions" FOR SELECT TO "authenticated" USING ("public"."is_org_member"("organization_id"));

CREATE POLICY "vat_class_select" ON "public"."vat_purchase_classifications" FOR SELECT TO "authenticated" USING ("public"."is_org_member"("organization_id"));

REVOKE ALL ON FUNCTION "public"."activate_tax_rule_version"("p_rule_version_id" "uuid") FROM PUBLIC;

GRANT ALL ON FUNCTION "public"."activate_tax_rule_version"("p_rule_version_id" "uuid") TO "service_role";

REVOKE ALL ON FUNCTION "public"."calculate_tax_determination"("p_tax_period_id" "uuid") FROM PUBLIC;

GRANT ALL ON FUNCTION "public"."calculate_tax_determination"("p_tax_period_id" "uuid") TO "authenticated";

GRANT ALL ON FUNCTION "public"."calculate_tax_determination"("p_tax_period_id" "uuid") TO "service_role";

REVOKE ALL ON FUNCTION "public"."calculate_tax_period"("p_tax_period_id" "uuid") FROM PUBLIC;

GRANT ALL ON FUNCTION "public"."calculate_tax_period"("p_tax_period_id" "uuid") TO "authenticated";

GRANT ALL ON FUNCTION "public"."calculate_tax_period"("p_tax_period_id" "uuid") TO "service_role";

REVOKE ALL ON FUNCTION "public"."close_tax_period"("p_tax_period_id" "uuid") FROM PUBLIC;

GRANT ALL ON FUNCTION "public"."close_tax_period"("p_tax_period_id" "uuid") TO "authenticated";

GRANT ALL ON FUNCTION "public"."close_tax_period"("p_tax_period_id" "uuid") TO "service_role";

REVOKE ALL ON FUNCTION "public"."create_tax_obligation"("p_tax_period_id" "uuid", "p_obligation_type" "public"."tax_obligation_type", "p_amount" numeric, "p_due_date" "date", "p_narrative" "text") FROM PUBLIC;

GRANT ALL ON FUNCTION "public"."create_tax_obligation"("p_tax_period_id" "uuid", "p_obligation_type" "public"."tax_obligation_type", "p_amount" numeric, "p_due_date" "date", "p_narrative" "text") TO "authenticated";

GRANT ALL ON FUNCTION "public"."create_tax_obligation"("p_tax_period_id" "uuid", "p_obligation_type" "public"."tax_obligation_type", "p_amount" numeric, "p_due_date" "date", "p_narrative" "text") TO "service_role";

REVOKE ALL ON FUNCTION "public"."ensure_tax_period"("p_organization_id" "uuid", "p_tax_code" "public"."tax_code", "p_jurisdiction_code" "text", "p_period_year" integer, "p_period_month" integer, "p_workspace_environment" "public"."tax_workspace_environment") FROM PUBLIC;

GRANT ALL ON FUNCTION "public"."ensure_tax_period"("p_organization_id" "uuid", "p_tax_code" "public"."tax_code", "p_jurisdiction_code" "text", "p_period_year" integer, "p_period_month" integer, "p_workspace_environment" "public"."tax_workspace_environment") TO "authenticated";

GRANT ALL ON FUNCTION "public"."ensure_tax_period"("p_organization_id" "uuid", "p_tax_code" "public"."tax_code", "p_jurisdiction_code" "text", "p_period_year" integer, "p_period_month" integer, "p_workspace_environment" "public"."tax_workspace_environment") TO "service_role";

REVOKE ALL ON FUNCTION "public"."prevent_active_tax_rule_mutation"() FROM PUBLIC;

GRANT ALL ON FUNCTION "public"."prevent_active_tax_rule_mutation"() TO "service_role";

REVOKE ALL ON FUNCTION "public"."prevent_tax_determination_client_mutation"() FROM PUBLIC;

GRANT ALL ON FUNCTION "public"."prevent_tax_determination_client_mutation"() TO "service_role";

REVOKE ALL ON FUNCTION "public"."prevent_tax_filing_mutation"() FROM PUBLIC;

GRANT ALL ON FUNCTION "public"."prevent_tax_filing_mutation"() TO "service_role";

REVOKE ALL ON FUNCTION "public"."prevent_tax_payment_mutation"() FROM PUBLIC;

GRANT ALL ON FUNCTION "public"."prevent_tax_payment_mutation"() TO "service_role";

REVOKE ALL ON FUNCTION "public"."prevent_tax_period_status_forgery"() FROM PUBLIC;

GRANT ALL ON FUNCTION "public"."prevent_tax_period_status_forgery"() TO "service_role";

REVOKE ALL ON FUNCTION "public"."reconcile_vat_accounting"("p_tax_period_id" "uuid") FROM PUBLIC;

GRANT ALL ON FUNCTION "public"."reconcile_vat_accounting"("p_tax_period_id" "uuid") TO "authenticated";

GRANT ALL ON FUNCTION "public"."reconcile_vat_accounting"("p_tax_period_id" "uuid") TO "service_role";

REVOKE ALL ON FUNCTION "public"."record_tax_filing_external"("p_tax_period_id" "uuid", "p_filing_kind" "public"."tax_filing_kind", "p_external_form_code" "text", "p_external_receipt_number" "text", "p_filed_at" timestamp with time zone, "p_evidence_reference" "text", "p_evidence_hash" "text", "p_supersedes_filing_id" "uuid") FROM PUBLIC;

GRANT ALL ON FUNCTION "public"."record_tax_filing_external"("p_tax_period_id" "uuid", "p_filing_kind" "public"."tax_filing_kind", "p_external_form_code" "text", "p_external_receipt_number" "text", "p_filed_at" timestamp with time zone, "p_evidence_reference" "text", "p_evidence_hash" "text", "p_supersedes_filing_id" "uuid") TO "authenticated";

GRANT ALL ON FUNCTION "public"."record_tax_filing_external"("p_tax_period_id" "uuid", "p_filing_kind" "public"."tax_filing_kind", "p_external_form_code" "text", "p_external_receipt_number" "text", "p_filed_at" timestamp with time zone, "p_evidence_reference" "text", "p_evidence_hash" "text", "p_supersedes_filing_id" "uuid") TO "service_role";

REVOKE ALL ON FUNCTION "public"."record_tax_payment_external"("p_tax_obligation_id" "uuid", "p_payment_date" "date", "p_amount" numeric, "p_external_reference" "text", "p_payment_method_description" "text", "p_evidence_reference" "text", "p_evidence_hash" "text") FROM PUBLIC;

GRANT ALL ON FUNCTION "public"."record_tax_payment_external"("p_tax_obligation_id" "uuid", "p_payment_date" "date", "p_amount" numeric, "p_external_reference" "text", "p_payment_method_description" "text", "p_evidence_reference" "text", "p_evidence_hash" "text") TO "authenticated";

GRANT ALL ON FUNCTION "public"."record_tax_payment_external"("p_tax_obligation_id" "uuid", "p_payment_date" "date", "p_amount" numeric, "p_external_reference" "text", "p_payment_method_description" "text", "p_evidence_reference" "text", "p_evidence_hash" "text") TO "service_role";

REVOKE ALL ON FUNCTION "public"."register_tax_wp"("p_organization_id" "uuid", "p_wp_type" "public"."tax_wp_type", "p_tax_code" "public"."tax_code", "p_operation_date" "date", "p_tax_period_date" "date", "p_amount" numeric, "p_certificate_number" "text", "p_jurisdiction_code" "text", "p_counterparty_id" "uuid") FROM PUBLIC;

GRANT ALL ON FUNCTION "public"."register_tax_wp"("p_organization_id" "uuid", "p_wp_type" "public"."tax_wp_type", "p_tax_code" "public"."tax_code", "p_operation_date" "date", "p_tax_period_date" "date", "p_amount" numeric, "p_certificate_number" "text", "p_jurisdiction_code" "text", "p_counterparty_id" "uuid") TO "authenticated";

GRANT ALL ON FUNCTION "public"."register_tax_wp"("p_organization_id" "uuid", "p_wp_type" "public"."tax_wp_type", "p_tax_code" "public"."tax_code", "p_operation_date" "date", "p_tax_period_date" "date", "p_amount" numeric, "p_certificate_number" "text", "p_jurisdiction_code" "text", "p_counterparty_id" "uuid") TO "service_role";

REVOKE ALL ON FUNCTION "public"."reopen_tax_period"("p_tax_period_id" "uuid", "p_reason" "text") FROM PUBLIC;

GRANT ALL ON FUNCTION "public"."reopen_tax_period"("p_tax_period_id" "uuid", "p_reason" "text") TO "authenticated";

GRANT ALL ON FUNCTION "public"."reopen_tax_period"("p_tax_period_id" "uuid", "p_reason" "text") TO "service_role";

REVOKE ALL ON FUNCTION "public"."revalidate_tax_determination_sources"("p_tax_period_id" "uuid") FROM PUBLIC;

GRANT ALL ON FUNCTION "public"."revalidate_tax_determination_sources"("p_tax_period_id" "uuid") TO "authenticated";

GRANT ALL ON FUNCTION "public"."revalidate_tax_determination_sources"("p_tax_period_id" "uuid") TO "service_role";

REVOKE ALL ON FUNCTION "public"."review_tax_period"("p_tax_period_id" "uuid") FROM PUBLIC;

GRANT ALL ON FUNCTION "public"."review_tax_period"("p_tax_period_id" "uuid") TO "authenticated";

GRANT ALL ON FUNCTION "public"."review_tax_period"("p_tax_period_id" "uuid") TO "service_role";

REVOKE ALL ON FUNCTION "public"."tax_assert_feature"("p_org_id" "uuid") FROM PUBLIC;

GRANT ALL ON FUNCTION "public"."tax_assert_feature"("p_org_id" "uuid") TO "service_role";

REVOKE ALL ON FUNCTION "public"."tax_assert_role"("p_org_id" "uuid", "p_roles" "public"."member_role"[]) FROM PUBLIC;

GRANT ALL ON FUNCTION "public"."tax_assert_role"("p_org_id" "uuid", "p_roles" "public"."member_role"[]) TO "service_role";

REVOKE ALL ON FUNCTION "public"."tax_assert_service_role"() FROM PUBLIC;

GRANT ALL ON FUNCTION "public"."tax_assert_service_role"() TO "service_role";

REVOKE ALL ON FUNCTION "public"."tax_canonical_fiscal_hash"("p_doc" "public"."fiscal_documents", "p_summary" "public"."fiscal_tax_summaries") FROM PUBLIC;

GRANT ALL ON FUNCTION "public"."tax_canonical_fiscal_hash"("p_doc" "public"."fiscal_documents", "p_summary" "public"."fiscal_tax_summaries") TO "service_role";

GRANT ALL ON TABLE "public"."vat_purchase_classifications" TO "authenticated";

GRANT ALL ON TABLE "public"."vat_purchase_classifications" TO "service_role";

REVOKE ALL ON FUNCTION "public"."tax_canonical_purchase_hash"("p_doc" "public"."purchase_documents", "p_summary" "public"."purchase_document_tax_summaries", "p_class" "public"."vat_purchase_classifications") FROM PUBLIC;

GRANT ALL ON FUNCTION "public"."tax_canonical_purchase_hash"("p_doc" "public"."purchase_documents", "p_summary" "public"."purchase_document_tax_summaries", "p_class" "public"."vat_purchase_classifications") TO "service_role";

REVOKE ALL ON FUNCTION "public"."tax_fiscal_vat_economic_sign"("p_operation_kind" "public"."fiscal_operation_kind") FROM PUBLIC;

GRANT ALL ON FUNCTION "public"."tax_fiscal_vat_economic_sign"("p_operation_kind" "public"."fiscal_operation_kind") TO "service_role";

REVOKE ALL ON FUNCTION "public"."tax_obligation_outstanding"("p_tax_obligation_id" "uuid") FROM PUBLIC;

GRANT ALL ON FUNCTION "public"."tax_obligation_outstanding"("p_tax_obligation_id" "uuid") TO "authenticated";

GRANT ALL ON FUNCTION "public"."tax_obligation_outstanding"("p_tax_obligation_id" "uuid") TO "service_role";

GRANT ALL ON TABLE "public"."tax_rule_versions" TO "authenticated";

GRANT ALL ON TABLE "public"."tax_rule_versions" TO "service_role";

REVOKE ALL ON FUNCTION "public"."tax_resolve_active_rule"("p_tax_code" "public"."tax_code", "p_jurisdiction_code" "text", "p_rule_key" "text", "p_as_of" "date") FROM PUBLIC;

GRANT ALL ON FUNCTION "public"."tax_resolve_active_rule"("p_tax_code" "public"."tax_code", "p_jurisdiction_code" "text", "p_rule_key" "text", "p_as_of" "date") TO "service_role";

REVOKE ALL ON FUNCTION "public"."tax_resolve_effective_date"("p_tax_code" "public"."tax_code", "p_source_domain" "public"."tax_source_domain", "p_issue_date" "date", "p_accounting_date" "date", "p_rule_version" "public"."tax_rule_versions") FROM PUBLIC;

GRANT ALL ON FUNCTION "public"."tax_resolve_effective_date"("p_tax_code" "public"."tax_code", "p_source_domain" "public"."tax_source_domain", "p_issue_date" "date", "p_accounting_date" "date", "p_rule_version" "public"."tax_rule_versions") TO "service_role";

REVOKE ALL ON FUNCTION "public"."tax_sha256"("p_text" "text") FROM PUBLIC;

GRANT ALL ON FUNCTION "public"."tax_sha256"("p_text" "text") TO "service_role";

REVOKE ALL ON FUNCTION "public"."tax_test_fixture_purchase_iva_components"("p_organization_id" "uuid", "p_supplier_id" "uuid", "p_issue_date" "date", "p_components" "jsonb") FROM PUBLIC;

GRANT ALL ON FUNCTION "public"."tax_test_fixture_purchase_iva_components"("p_organization_id" "uuid", "p_supplier_id" "uuid", "p_issue_date" "date", "p_components" "jsonb") TO "service_role";

REVOKE ALL ON FUNCTION "public"."upsert_iibb_jurisdiction_allocation"("p_tax_period_id" "uuid", "p_jurisdiction_code" "text", "p_distribution_method" "public"."iibb_distribution_method", "p_sales_allocation_strategy" "public"."iibb_sales_allocation_strategy", "p_gross_revenue_amount" numeric, "p_cm_form_code" "public"."tax_cm_form_code", "p_coefficient" numeric, "p_narrative" "text") FROM PUBLIC;

GRANT ALL ON FUNCTION "public"."upsert_iibb_jurisdiction_allocation"("p_tax_period_id" "uuid", "p_jurisdiction_code" "text", "p_distribution_method" "public"."iibb_distribution_method", "p_sales_allocation_strategy" "public"."iibb_sales_allocation_strategy", "p_gross_revenue_amount" numeric, "p_cm_form_code" "public"."tax_cm_form_code", "p_coefficient" numeric, "p_narrative" "text") TO "authenticated";

GRANT ALL ON FUNCTION "public"."upsert_iibb_jurisdiction_allocation"("p_tax_period_id" "uuid", "p_jurisdiction_code" "text", "p_distribution_method" "public"."iibb_distribution_method", "p_sales_allocation_strategy" "public"."iibb_sales_allocation_strategy", "p_gross_revenue_amount" numeric, "p_cm_form_code" "public"."tax_cm_form_code", "p_coefficient" numeric, "p_narrative" "text") TO "service_role";

REVOKE ALL ON FUNCTION "public"."upsert_organization_tax_registration"("p_organization_id" "uuid", "p_tax_code" "public"."tax_code", "p_jurisdiction_code" "text", "p_registration_number" "text", "p_effective_from" "date", "p_regime_metadata" "jsonb") FROM PUBLIC;

GRANT ALL ON FUNCTION "public"."upsert_organization_tax_registration"("p_organization_id" "uuid", "p_tax_code" "public"."tax_code", "p_jurisdiction_code" "text", "p_registration_number" "text", "p_effective_from" "date", "p_regime_metadata" "jsonb") TO "authenticated";

GRANT ALL ON FUNCTION "public"."upsert_organization_tax_registration"("p_organization_id" "uuid", "p_tax_code" "public"."tax_code", "p_jurisdiction_code" "text", "p_registration_number" "text", "p_effective_from" "date", "p_regime_metadata" "jsonb") TO "service_role";

REVOKE ALL ON FUNCTION "public"."upsert_vat_purchase_classification"("p_organization_id" "uuid", "p_purchase_document_id" "uuid", "p_purchase_tax_summary_id" "uuid", "p_classification" "public"."vat_credit_classification", "p_computable_amount" numeric, "p_noncomputable_amount" numeric, "p_reason_code" "text", "p_reason_notes" "text") FROM PUBLIC;

GRANT ALL ON FUNCTION "public"."upsert_vat_purchase_classification"("p_organization_id" "uuid", "p_purchase_document_id" "uuid", "p_purchase_tax_summary_id" "uuid", "p_classification" "public"."vat_credit_classification", "p_computable_amount" numeric, "p_noncomputable_amount" numeric, "p_reason_code" "text", "p_reason_notes" "text") TO "authenticated";

GRANT ALL ON FUNCTION "public"."upsert_vat_purchase_classification"("p_organization_id" "uuid", "p_purchase_document_id" "uuid", "p_purchase_tax_summary_id" "uuid", "p_classification" "public"."vat_credit_classification", "p_computable_amount" numeric, "p_noncomputable_amount" numeric, "p_reason_code" "text", "p_reason_notes" "text") TO "service_role";

GRANT ALL ON TABLE "public"."iibb_cm_coefficients" TO "authenticated";

GRANT ALL ON TABLE "public"."iibb_cm_coefficients" TO "service_role";

GRANT ALL ON TABLE "public"."iibb_jurisdiction_allocations" TO "authenticated";

GRANT ALL ON TABLE "public"."iibb_jurisdiction_allocations" TO "service_role";

GRANT ALL ON TABLE "public"."organization_tax_registrations" TO "authenticated";

GRANT ALL ON TABLE "public"."organization_tax_registrations" TO "service_role";

GRANT ALL ON TABLE "public"."tax_adjustments" TO "authenticated";

GRANT ALL ON TABLE "public"."tax_adjustments" TO "service_role";

GRANT ALL ON TABLE "public"."tax_determination_lines" TO "authenticated";

GRANT ALL ON TABLE "public"."tax_determination_lines" TO "service_role";

GRANT ALL ON TABLE "public"."tax_determination_rule_snapshots" TO "authenticated";

GRANT ALL ON TABLE "public"."tax_determination_rule_snapshots" TO "service_role";

GRANT ALL ON TABLE "public"."tax_determination_sources" TO "authenticated";

GRANT ALL ON TABLE "public"."tax_determination_sources" TO "service_role";

GRANT ALL ON TABLE "public"."tax_determinations" TO "authenticated";

GRANT ALL ON TABLE "public"."tax_determinations" TO "service_role";

GRANT ALL ON TABLE "public"."tax_filing_records" TO "authenticated";

GRANT ALL ON TABLE "public"."tax_filing_records" TO "service_role";

GRANT ALL ON TABLE "public"."tax_jurisdictions" TO "authenticated";

GRANT ALL ON TABLE "public"."tax_jurisdictions" TO "service_role";

GRANT ALL ON TABLE "public"."tax_obligations" TO "authenticated";

GRANT ALL ON TABLE "public"."tax_obligations" TO "service_role";

GRANT ALL ON TABLE "public"."tax_payment_records" TO "authenticated";

GRANT ALL ON TABLE "public"."tax_payment_records" TO "service_role";

GRANT ALL ON TABLE "public"."tax_periods" TO "authenticated";

GRANT ALL ON TABLE "public"."tax_periods" TO "service_role";

GRANT ALL ON TABLE "public"."tax_rule_sets" TO "authenticated";

GRANT ALL ON TABLE "public"."tax_rule_sets" TO "service_role";

GRANT ALL ON TABLE "public"."tax_withholdings_perceptions" TO "authenticated";

GRANT ALL ON TABLE "public"."tax_withholdings_perceptions" TO "service_role";

ALTER TABLE ONLY "public"."iibb_jurisdiction_allocations"
    ADD CONSTRAINT "iibb_alloc_org_period_fk" FOREIGN KEY ("organization_id", "tax_period_id") REFERENCES "public"."tax_periods"("organization_id", "id") ON DELETE RESTRICT;

ALTER TABLE ONLY "public"."iibb_cm_coefficients"
    ADD CONSTRAINT "iibb_cm_coefficients_activated_by_fkey" FOREIGN KEY ("activated_by") REFERENCES "auth"."users"("id");

ALTER TABLE ONLY "public"."iibb_cm_coefficients"
    ADD CONSTRAINT "iibb_cm_coefficients_jurisdiction_code_fkey" FOREIGN KEY ("jurisdiction_code") REFERENCES "public"."tax_jurisdictions"("code");

ALTER TABLE ONLY "public"."iibb_cm_coefficients"
    ADD CONSTRAINT "iibb_cm_coefficients_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."iibb_cm_coefficients"
    ADD CONSTRAINT "iibb_cm_coefficients_reviewed_by_fkey" FOREIGN KEY ("reviewed_by") REFERENCES "auth"."users"("id");

ALTER TABLE ONLY "public"."iibb_cm_coefficients"
    ADD CONSTRAINT "iibb_cm_coefficients_rule_version_id_fkey" FOREIGN KEY ("rule_version_id") REFERENCES "public"."tax_rule_versions"("id");

ALTER TABLE ONLY "public"."iibb_jurisdiction_allocations"
    ADD CONSTRAINT "iibb_jurisdiction_allocations_jurisdiction_code_fkey" FOREIGN KEY ("jurisdiction_code") REFERENCES "public"."tax_jurisdictions"("code");

ALTER TABLE ONLY "public"."iibb_jurisdiction_allocations"
    ADD CONSTRAINT "iibb_jurisdiction_allocations_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."iibb_jurisdiction_allocations"
    ADD CONSTRAINT "iibb_jurisdiction_allocations_rule_version_id_fkey" FOREIGN KEY ("rule_version_id") REFERENCES "public"."tax_rule_versions"("id");

ALTER TABLE ONLY "public"."organization_tax_registrations"
    ADD CONSTRAINT "organization_tax_registrations_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id");

ALTER TABLE ONLY "public"."organization_tax_registrations"
    ADD CONSTRAINT "organization_tax_registrations_jurisdiction_code_fkey" FOREIGN KEY ("jurisdiction_code") REFERENCES "public"."tax_jurisdictions"("code");

ALTER TABLE ONLY "public"."organization_tax_registrations"
    ADD CONSTRAINT "organization_tax_registrations_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."tax_adjustments"
    ADD CONSTRAINT "tax_adj_org_period_fk" FOREIGN KEY ("organization_id", "tax_period_id") REFERENCES "public"."tax_periods"("organization_id", "id") ON DELETE RESTRICT;

ALTER TABLE ONLY "public"."tax_adjustments"
    ADD CONSTRAINT "tax_adjustments_approved_by_fkey" FOREIGN KEY ("approved_by") REFERENCES "auth"."users"("id");

ALTER TABLE ONLY "public"."tax_adjustments"
    ADD CONSTRAINT "tax_adjustments_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id");

ALTER TABLE ONLY "public"."tax_adjustments"
    ADD CONSTRAINT "tax_adjustments_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."tax_adjustments"
    ADD CONSTRAINT "tax_adjustments_reversed_by_fkey" FOREIGN KEY ("reversed_by") REFERENCES "auth"."users"("id");

ALTER TABLE ONLY "public"."tax_determination_lines"
    ADD CONSTRAINT "tax_det_line_org_det_fk" FOREIGN KEY ("organization_id", "tax_determination_id") REFERENCES "public"."tax_determinations"("organization_id", "id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."tax_determination_lines"
    ADD CONSTRAINT "tax_det_line_src_fk" FOREIGN KEY ("tax_determination_source_id") REFERENCES "public"."tax_determination_sources"("id") ON DELETE RESTRICT;

ALTER TABLE ONLY "public"."tax_determinations"
    ADD CONSTRAINT "tax_det_org_period_fk" FOREIGN KEY ("organization_id", "tax_period_id") REFERENCES "public"."tax_periods"("organization_id", "id") ON DELETE RESTRICT;

ALTER TABLE ONLY "public"."tax_determination_rule_snapshots"
    ADD CONSTRAINT "tax_det_rule_snap_org_det_fk" FOREIGN KEY ("organization_id", "tax_determination_id") REFERENCES "public"."tax_determinations"("organization_id", "id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."tax_determination_sources"
    ADD CONSTRAINT "tax_det_src_org_det_fk" FOREIGN KEY ("organization_id", "tax_determination_id") REFERENCES "public"."tax_determinations"("organization_id", "id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."tax_determination_lines"
    ADD CONSTRAINT "tax_determination_lines_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."tax_determination_rule_snapshots"
    ADD CONSTRAINT "tax_determination_rule_snapshots_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."tax_determination_rule_snapshots"
    ADD CONSTRAINT "tax_determination_rule_snapshots_tax_rule_version_id_fkey" FOREIGN KEY ("tax_rule_version_id") REFERENCES "public"."tax_rule_versions"("id") ON DELETE RESTRICT;

ALTER TABLE ONLY "public"."tax_determination_sources"
    ADD CONSTRAINT "tax_determination_sources_attribution_rule_version_id_fkey" FOREIGN KEY ("attribution_rule_version_id") REFERENCES "public"."tax_rule_versions"("id");

ALTER TABLE ONLY "public"."tax_determination_sources"
    ADD CONSTRAINT "tax_determination_sources_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."tax_determination_sources"
    ADD CONSTRAINT "tax_determination_sources_rule_version_id_fkey" FOREIGN KEY ("rule_version_id") REFERENCES "public"."tax_rule_versions"("id");

ALTER TABLE ONLY "public"."tax_determinations"
    ADD CONSTRAINT "tax_determinations_calculated_by_fkey" FOREIGN KEY ("calculated_by") REFERENCES "auth"."users"("id");

ALTER TABLE ONLY "public"."tax_determinations"
    ADD CONSTRAINT "tax_determinations_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."tax_determinations"
    ADD CONSTRAINT "tax_determinations_reviewed_by_fkey" FOREIGN KEY ("reviewed_by") REFERENCES "auth"."users"("id");

ALTER TABLE ONLY "public"."tax_filing_records"
    ADD CONSTRAINT "tax_filing_org_period_fk" FOREIGN KEY ("organization_id", "tax_period_id") REFERENCES "public"."tax_periods"("organization_id", "id") ON DELETE RESTRICT;

ALTER TABLE ONLY "public"."tax_filing_records"
    ADD CONSTRAINT "tax_filing_records_filed_by_fkey" FOREIGN KEY ("filed_by") REFERENCES "auth"."users"("id");

ALTER TABLE ONLY "public"."tax_filing_records"
    ADD CONSTRAINT "tax_filing_records_jurisdiction_code_fkey" FOREIGN KEY ("jurisdiction_code") REFERENCES "public"."tax_jurisdictions"("code");

ALTER TABLE ONLY "public"."tax_filing_records"
    ADD CONSTRAINT "tax_filing_records_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."tax_filing_records"
    ADD CONSTRAINT "tax_filing_supersedes_org_fk" FOREIGN KEY ("organization_id", "supersedes_filing_id") REFERENCES "public"."tax_filing_records"("organization_id", "id") ON DELETE RESTRICT;

ALTER TABLE ONLY "public"."tax_obligations"
    ADD CONSTRAINT "tax_obl_org_det_fk" FOREIGN KEY ("organization_id", "tax_determination_id") REFERENCES "public"."tax_determinations"("organization_id", "id") ON DELETE RESTRICT;

ALTER TABLE ONLY "public"."tax_obligations"
    ADD CONSTRAINT "tax_obl_org_period_fk" FOREIGN KEY ("organization_id", "tax_period_id") REFERENCES "public"."tax_periods"("organization_id", "id") ON DELETE RESTRICT;

ALTER TABLE ONLY "public"."tax_obligations"
    ADD CONSTRAINT "tax_obligations_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id");

ALTER TABLE ONLY "public"."tax_obligations"
    ADD CONSTRAINT "tax_obligations_jurisdiction_code_fkey" FOREIGN KEY ("jurisdiction_code") REFERENCES "public"."tax_jurisdictions"("code");

ALTER TABLE ONLY "public"."tax_obligations"
    ADD CONSTRAINT "tax_obligations_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."tax_payment_records"
    ADD CONSTRAINT "tax_pay_org_obl_fk" FOREIGN KEY ("organization_id", "tax_obligation_id") REFERENCES "public"."tax_obligations"("organization_id", "id") ON DELETE RESTRICT;

ALTER TABLE ONLY "public"."tax_payment_records"
    ADD CONSTRAINT "tax_payment_records_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."tax_payment_records"
    ADD CONSTRAINT "tax_payment_records_recorded_by_fkey" FOREIGN KEY ("recorded_by") REFERENCES "auth"."users"("id");

ALTER TABLE ONLY "public"."tax_periods"
    ADD CONSTRAINT "tax_periods_closed_by_fkey" FOREIGN KEY ("closed_by") REFERENCES "auth"."users"("id");

ALTER TABLE ONLY "public"."tax_periods"
    ADD CONSTRAINT "tax_periods_jurisdiction_code_fkey" FOREIGN KEY ("jurisdiction_code") REFERENCES "public"."tax_jurisdictions"("code");

ALTER TABLE ONLY "public"."tax_periods"
    ADD CONSTRAINT "tax_periods_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."tax_periods"
    ADD CONSTRAINT "tax_periods_reopened_by_fkey" FOREIGN KEY ("reopened_by") REFERENCES "auth"."users"("id");

ALTER TABLE ONLY "public"."tax_periods"
    ADD CONSTRAINT "tax_periods_reviewed_by_fkey" FOREIGN KEY ("reviewed_by") REFERENCES "auth"."users"("id");

ALTER TABLE ONLY "public"."tax_rule_sets"
    ADD CONSTRAINT "tax_rule_sets_jurisdiction_code_fkey" FOREIGN KEY ("jurisdiction_code") REFERENCES "public"."tax_jurisdictions"("code");

ALTER TABLE ONLY "public"."tax_rule_versions"
    ADD CONSTRAINT "tax_rule_versions_activated_by_fkey" FOREIGN KEY ("activated_by") REFERENCES "auth"."users"("id");

ALTER TABLE ONLY "public"."tax_rule_versions"
    ADD CONSTRAINT "tax_rule_versions_reviewed_by_fkey" FOREIGN KEY ("reviewed_by") REFERENCES "auth"."users"("id");

ALTER TABLE ONLY "public"."tax_rule_versions"
    ADD CONSTRAINT "tax_rule_versions_rule_set_id_fkey" FOREIGN KEY ("rule_set_id") REFERENCES "public"."tax_rule_sets"("id") ON DELETE RESTRICT;

ALTER TABLE ONLY "public"."tax_withholdings_perceptions"
    ADD CONSTRAINT "tax_withholdings_perceptions_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id");

ALTER TABLE ONLY "public"."tax_withholdings_perceptions"
    ADD CONSTRAINT "tax_withholdings_perceptions_jurisdiction_code_fkey" FOREIGN KEY ("jurisdiction_code") REFERENCES "public"."tax_jurisdictions"("code");

ALTER TABLE ONLY "public"."tax_withholdings_perceptions"
    ADD CONSTRAINT "tax_withholdings_perceptions_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."tax_withholdings_perceptions"
    ADD CONSTRAINT "tax_wp_org_cp_fk" FOREIGN KEY ("organization_id", "counterparty_id") REFERENCES "public"."counterparties"("organization_id", "id") ON DELETE RESTRICT;

ALTER TABLE ONLY "public"."vat_purchase_classifications"
    ADD CONSTRAINT "vat_class_org_purchase_fk" FOREIGN KEY ("organization_id", "purchase_document_id") REFERENCES "public"."purchase_documents"("organization_id", "id") ON DELETE RESTRICT;

ALTER TABLE ONLY "public"."vat_purchase_classifications"
    ADD CONSTRAINT "vat_purchase_classifications_classified_by_fkey" FOREIGN KEY ("classified_by") REFERENCES "auth"."users"("id");

ALTER TABLE ONLY "public"."vat_purchase_classifications"
    ADD CONSTRAINT "vat_purchase_classifications_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."vat_purchase_classifications"
    ADD CONSTRAINT "vat_purchase_classifications_purchase_document_id_fkey" FOREIGN KEY ("purchase_document_id") REFERENCES "public"."purchase_documents"("id") ON DELETE RESTRICT;

ALTER TABLE ONLY "public"."vat_purchase_classifications"
    ADD CONSTRAINT "vat_purchase_classifications_purchase_tax_summary_id_fkey" FOREIGN KEY ("purchase_tax_summary_id") REFERENCES "public"."purchase_document_tax_summaries"("id") ON DELETE RESTRICT;

ALTER TABLE ONLY "public"."vat_purchase_classifications"
    ADD CONSTRAINT "vat_purchase_classifications_reviewed_by_fkey" FOREIGN KEY ("reviewed_by") REFERENCES "auth"."users"("id");

ALTER TABLE ONLY "public"."vat_purchase_classifications"
    ADD CONSTRAINT "vat_purchase_classifications_rule_version_id_fkey" FOREIGN KEY ("rule_version_id") REFERENCES "public"."tax_rule_versions"("id");
