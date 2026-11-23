-- Find likely duplicate inventory entries using broad attribute matches and
-- PostgreSQL trigram similarity for the item name/description.
CREATE OR REPLACE FUNCTION public.find_possible_inventory_duplicates()
RETURNS TABLE (
  first_item jsonb,
  second_item jsonb,
  description_similarity real
)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = ''
AS $function$
  SELECT
    pg_catalog.to_jsonb(a) AS first_item,
    pg_catalog.to_jsonb(b) AS second_item,
    extensions.similarity(
      pg_catalog.lower(pg_catalog.btrim(a.name)),
      pg_catalog.lower(pg_catalog.btrim(b.name))
    ) AS description_similarity
  FROM public.inventory AS a
  JOIN public.inventory AS b ON a.id < b.id
  WHERE
    NULLIF(pg_catalog.btrim(a.brand), '') IS NOT NULL
    AND NULLIF(pg_catalog.btrim(a.name), '') IS NOT NULL
    AND NULLIF(pg_catalog.btrim(b.name), '') IS NOT NULL
    AND NULLIF(pg_catalog.btrim(a.color), '') IS NOT NULL
    AND NULLIF(pg_catalog.btrim(b.color), '') IS NOT NULL
    AND pg_catalog.lower(pg_catalog.btrim(a.brand)) =
        pg_catalog.lower(pg_catalog.btrim(b.brand))
    AND a.price_est IS NOT NULL
    AND b.price_est IS NOT NULL
    AND abs(a.price_est - b.price_est) <=
        greatest(abs(a.price_est), abs(b.price_est)) * 0.10
    AND (
      pg_catalog.lower(pg_catalog.btrim(a.color)) = pg_catalog.lower(pg_catalog.btrim(b.color))
      OR extensions.similarity(
        pg_catalog.lower(coalesce(a.color, '')),
        pg_catalog.lower(coalesce(b.color, ''))
      ) >= 0.30
    )
    AND extensions.similarity(
      pg_catalog.lower(pg_catalog.btrim(a.name)),
      pg_catalog.lower(pg_catalog.btrim(b.name))
    ) >= 0.35
  ORDER BY description_similarity DESC, a.id, b.id;
$function$;

REVOKE ALL ON FUNCTION public.find_possible_inventory_duplicates() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.find_possible_inventory_duplicates() TO authenticated;
