-- Documented reference seeds for clean-room rebuilds.
-- Catalog rows for fiscal_conditions / feature_catalog / app_settings are
-- applied by migrations. This seed file re-asserts invariants only (idempotent).

-- Ensure Phase 1 catalog cardinality after migrations.
do $$
declare
  fiscal_count int;
  feature_count int;
begin
  select count(*) into fiscal_count from public.fiscal_conditions;
  select count(*) into feature_count from public.feature_catalog;

  if fiscal_count < 4 then
    raise exception 'reference seed invariant failed: fiscal_conditions expected >= 4, got %', fiscal_count;
  end if;

  if feature_count < 16 then
    raise exception 'reference seed invariant failed: feature_catalog expected >= 16, got %', feature_count;
  end if;
end $$;
