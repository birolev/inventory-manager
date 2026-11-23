-- Require matching categories and normalized color families for duplicate
-- candidates. Name similarity ranks candidates but cannot override attributes.
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
  WITH inventory_with_color_family AS (
    SELECT
      inventory.*,
      CASE
        WHEN pg_catalog.lower(pg_catalog.btrim(inventory.color)) LIKE ANY (
          ARRAY['%blue%', '%kék%', '%kek%', '%navy%', '%tengerészkék%', '%azúr%', '%turquoise%', '%türkiz%', '%cyan%']
        ) THEN 'blue'
        WHEN pg_catalog.lower(pg_catalog.btrim(inventory.color)) LIKE ANY (
          ARRAY['%pink%', '%rózsaszín%', '%rozsaszin%', '%magenta%', '%fuchsia%', '%fukszia%', '%ciklámen%', '%ciklamen%']
        ) THEN 'pink'
        WHEN pg_catalog.lower(pg_catalog.btrim(inventory.color)) LIKE ANY (
          ARRAY['%red%', '%piros%', '%vörös%', '%voros%', '%burgundy%', '%bordó%', '%bordo%']
        ) THEN 'red'
        WHEN pg_catalog.lower(pg_catalog.btrim(inventory.color)) LIKE ANY (
          ARRAY['%green%', '%zöld%', '%zold%', '%olive%', '%olíva%', '%oliva%', '%khaki%']
        ) THEN 'green'
        WHEN pg_catalog.lower(pg_catalog.btrim(inventory.color)) LIKE ANY (
          ARRAY['%yellow%', '%sárga%', '%sarga%', '%mustard%', '%mustár%']
        ) THEN 'yellow'
        WHEN pg_catalog.lower(pg_catalog.btrim(inventory.color)) LIKE ANY (
          ARRAY['%orange%', '%narancs%', '%peach%', '%barack%']
        ) THEN 'orange'
        WHEN pg_catalog.lower(pg_catalog.btrim(inventory.color)) LIKE ANY (
          ARRAY['%purple%', '%lila%', '%violet%', '%ibolya%', '%lavender%', '%levendula%']
        ) THEN 'purple'
        WHEN pg_catalog.lower(pg_catalog.btrim(inventory.color)) LIKE ANY (
          ARRAY['%brown%', '%barna%', '%beige%', '%bézs%', '%chocolate%', '%csoki%']
        ) THEN 'brown'
        WHEN pg_catalog.lower(pg_catalog.btrim(inventory.color)) LIKE ANY (
          ARRAY['%gray%', '%grey%', '%szürke%', '%szurke%', '%silver%', '%ezüst%']
        ) THEN 'gray'
        WHEN pg_catalog.lower(pg_catalog.btrim(inventory.color)) LIKE ANY (
          ARRAY['%white%', '%fehér%', '%feher%', '%cream%', '%krém%', '%krem%', '%ivory%']
        ) THEN 'white'
        WHEN pg_catalog.lower(pg_catalog.btrim(inventory.color)) LIKE ANY (
          ARRAY['%black%', '%fekete%']
        ) THEN 'black'
        ELSE pg_catalog.lower(pg_catalog.btrim(inventory.color))
      END AS _color_family
    FROM public.inventory AS inventory
  )
  SELECT
    pg_catalog.to_jsonb(a) - '_color_family' AS first_item,
    pg_catalog.to_jsonb(b) - '_color_family' AS second_item,
    extensions.similarity(
      pg_catalog.lower(pg_catalog.btrim(a.name)),
      pg_catalog.lower(pg_catalog.btrim(b.name))
    ) AS description_similarity
  FROM inventory_with_color_family AS a
  JOIN inventory_with_color_family AS b ON a.id < b.id
  WHERE
    NULLIF(pg_catalog.btrim(a.brand), '') IS NOT NULL
    AND pg_catalog.lower(pg_catalog.btrim(a.brand)) =
        pg_catalog.lower(pg_catalog.btrim(b.brand))
    AND NULLIF(pg_catalog.btrim(a.name), '') IS NOT NULL
    AND NULLIF(pg_catalog.btrim(b.name), '') IS NOT NULL
    AND NULLIF(pg_catalog.btrim(a.category), '') IS NOT NULL
    AND pg_catalog.lower(pg_catalog.btrim(a.category)) =
        pg_catalog.lower(pg_catalog.btrim(b.category))
    AND NULLIF(pg_catalog.btrim(a.color), '') IS NOT NULL
    AND NULLIF(pg_catalog.btrim(b.color), '') IS NOT NULL
    AND a._color_family = b._color_family
    AND a.price_est IS NOT NULL
    AND a.price_est = b.price_est
    AND extensions.similarity(
      pg_catalog.lower(pg_catalog.btrim(a.name)),
      pg_catalog.lower(pg_catalog.btrim(b.name))
    ) >= 0.35
  ORDER BY description_similarity DESC, a.id, b.id;
$function$;
