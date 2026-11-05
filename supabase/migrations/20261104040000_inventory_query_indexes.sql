-- Index common store/status and store/sort combinations used by inventory
-- searches, plus foreign-key and per-user dashboard lookups.
CREATE INDEX IF NOT EXISTS inventory_location_status_created_id_idx
  ON public.inventory (location, is_sold, created_at DESC, id);
CREATE INDEX IF NOT EXISTS inventory_location_created_id_idx
  ON public.inventory (location, created_at DESC, id);
CREATE INDEX IF NOT EXISTS inventory_category_location_created_id_idx
  ON public.inventory (category, location, created_at DESC, id);
CREATE INDEX IF NOT EXISTS inventory_gender_location_created_id_idx
  ON public.inventory (gender, location, created_at DESC, id);
CREATE INDEX IF NOT EXISTS inventory_location_price_id_idx
  ON public.inventory (location, price_est, id);
CREATE INDEX IF NOT EXISTS inventory_created_at_id_idx
  ON public.inventory (created_at DESC, id);
CREATE INDEX IF NOT EXISTS inventory_price_id_idx
  ON public.inventory (price_est, id);
CREATE INDEX IF NOT EXISTS inventory_status_created_id_idx
  ON public.inventory (is_sold, created_at DESC, id);
CREATE INDEX IF NOT EXISTS sales_recorded_by_sold_at_idx
  ON public.sales (recorded_by, sold_at DESC);
CREATE INDEX IF NOT EXISTS ai_intake_reviews_recorded_by_created_idx
  ON public.ai_intake_reviews (recorded_by, created_at DESC);
CREATE INDEX IF NOT EXISTS ai_intake_reviews_inventory_id_idx
  ON public.ai_intake_reviews (inventory_id);

-- The search service uses leading-wildcard ILIKE filters. Trigram GIN indexes
-- allow PostgreSQL to accelerate those filters without changing match rules.
CREATE EXTENSION IF NOT EXISTS pg_trgm WITH SCHEMA extensions;
DO $block$
DECLARE
  v_schema text;
  v_column text;
  v_index text;
BEGIN
  SELECT namespace.nspname INTO v_schema
  FROM pg_catalog.pg_opclass AS opclass
  JOIN pg_catalog.pg_namespace AS namespace ON namespace.oid = opclass.opcnamespace
  JOIN pg_catalog.pg_am AS access_method ON access_method.oid = opclass.opcmethod
  WHERE opclass.opcname = 'gin_trgm_ops'
    AND access_method.amname = 'gin'
  LIMIT 1;

  IF v_schema IS NULL THEN
    RAISE EXCEPTION 'pg_trgm GIN operator class is unavailable';
  END IF;

  FOREACH v_column IN ARRAY ARRAY['name', 'brand', 'color', 'pattern', 'condition'] LOOP
    v_index := 'inventory_' || v_column || '_trgm_idx';
    EXECUTE pg_catalog.format(
      'CREATE INDEX IF NOT EXISTS %I ON public.inventory USING gin (%I %I.%I)',
      v_index, v_column, v_schema, 'gin_trgm_ops'
    );
  END LOOP;
END;
$block$;
