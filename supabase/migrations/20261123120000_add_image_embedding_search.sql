-- Uses the existing inventory.embedding pgvector column. Image vectors are
-- generated with gemini-embedding-2 at 1536 dimensions.
CREATE OR REPLACE FUNCTION public.search_inventory_by_embedding(
  p_embedding double precision[],
  p_location text DEFAULT NULL,
  p_only_unsold boolean DEFAULT false,
  p_limit integer DEFAULT 50,
  p_category text DEFAULT NULL,
  p_gender text DEFAULT NULL,
  p_size text DEFAULT NULL,
  p_brand text DEFAULT NULL,
  p_color text DEFAULT NULL,
  p_pattern text DEFAULT NULL,
  p_name text DEFAULT NULL,
  p_condition text DEFAULT NULL
)
RETURNS SETOF jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = ''
AS $function$
DECLARE
  v_embedding extensions.vector;
BEGIN
  IF p_embedding IS NULL OR cardinality(p_embedding) <> 1536 OR
     EXISTS (SELECT 1 FROM pg_catalog.unnest(p_embedding) AS u(value) WHERE value IS NULL OR value = 'NaN'::double precision OR value = 'Infinity'::double precision OR value = '-Infinity'::double precision) THEN
    RAISE EXCEPTION 'Expected a finite 1536-dimensional image embedding';
  END IF;
  v_embedding := p_embedding::real[]::extensions.vector;

  RETURN QUERY
  SELECT (pg_catalog.to_jsonb(i) - 'embedding') || pg_catalog.jsonb_build_object(
           'similarity', (1 - (i.embedding <=> v_embedding))::real
         )
  FROM public.inventory AS i
  WHERE i.embedding IS NOT NULL
    AND (p_location IS NULL OR p_location = '' OR i.location = p_location)
    AND (NOT p_only_unsold OR i.is_sold = false)
    AND (p_category IS NULL OR i.category = p_category OR i.secondary_categories::text ILIKE '%' || p_category || '%')
    AND (p_gender IS NULL OR i.gender = p_gender)
    AND (p_size IS NULL OR i.size ILIKE p_size)
    AND (p_brand IS NULL OR i.brand ILIKE '%' || p_brand || '%')
    AND (p_color IS NULL OR i.color ILIKE '%' || p_color || '%')
    AND (p_pattern IS NULL OR i.pattern ILIKE '%' || p_pattern || '%')
    AND (p_name IS NULL OR i.name ILIKE '%' || p_name || '%')
    AND (p_condition IS NULL OR i.condition ILIKE '%' || p_condition || '%')
  ORDER BY i.embedding <=> v_embedding, i.id
  LIMIT greatest(1, least(coalesce(p_limit, 50), 100));
END;
$function$;

REVOKE ALL ON FUNCTION public.search_inventory_by_embedding(double precision[], text, boolean, integer, text, text, text, text, text, text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.search_inventory_by_embedding(double precision[], text, boolean, integer, text, text, text, text, text, text, text, text) TO authenticated;
