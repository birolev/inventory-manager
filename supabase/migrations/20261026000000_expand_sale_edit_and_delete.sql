-- Replace the earlier edit routine so it can remove sale lines, and add the
-- whole-sale delete routine exposed by the dashboard.
CREATE OR REPLACE FUNCTION public.update_sale(
  p_sale_id uuid,
  p_sold_at timestamptz,
  p_location text,
  p_payment_method text,
  p_notes text,
  p_items jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_sale public.sales%ROWTYPE;
  v_item jsonb;
  v_sale_item_id uuid;
  v_actual_price numeric(12, 2);
  v_item_count integer;
  v_updated_count integer;
  v_seen_ids uuid[] := ARRAY[]::uuid[];
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'You must be signed in to edit a sale';
  END IF;

  SELECT * INTO v_sale
  FROM public.sales
  WHERE id = p_sale_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Sale not found';
  END IF;

  IF v_sale.recorded_by IS DISTINCT FROM auth.uid()
     AND NOT public.has_app_role('manager')
     AND NOT public.has_app_role('admin') THEN
    RAISE EXCEPTION 'You can only edit your own sales';
  END IF;

  IF p_location IS NULL OR pg_catalog.btrim(p_location) = '' THEN
    RAISE EXCEPTION 'Sale location is required';
  END IF;
  IF p_payment_method NOT IN ('cash', 'card', 'mixed') THEN
    RAISE EXCEPTION 'Invalid payment method';
  END IF;
  IF p_items IS NULL
     OR pg_catalog.jsonb_typeof(p_items) <> 'array'
     OR pg_catalog.jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'A sale must keep at least one item; delete the sale to remove all items';
  END IF;

  SELECT count(*) INTO v_item_count
  FROM public.sale_items
  WHERE sale_id = p_sale_id;

  IF pg_catalog.jsonb_array_length(p_items) > v_item_count THEN
    RAISE EXCEPTION 'Items cannot be added while editing a sale';
  END IF;

  UPDATE public.sales
  SET sold_at = COALESCE(p_sold_at, sold_at),
      location = pg_catalog.btrim(p_location),
      payment_method = p_payment_method,
      notes = NULLIF(pg_catalog.btrim(p_notes), '')
  WHERE id = p_sale_id;

  FOR v_item IN
    SELECT item
    FROM pg_catalog.jsonb_array_elements(p_items) AS items(item)
  LOOP
    BEGIN
      v_sale_item_id := (v_item ->> 'sale_item_id')::uuid;
      v_actual_price := (v_item ->> 'actual_price')::numeric(12, 2);
    EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range THEN
      RAISE EXCEPTION 'Each sale item needs a valid id and price';
    END;

    IF v_sale_item_id = ANY(v_seen_ids) THEN
      RAISE EXCEPTION 'Sale item ids must not be repeated';
    END IF;
    v_seen_ids := pg_catalog.array_append(v_seen_ids, v_sale_item_id);

    IF v_actual_price < 0 THEN
      RAISE EXCEPTION 'Sale item price cannot be negative';
    END IF;
    IF COALESCE(pg_catalog.btrim(v_item ->> 'item_name'), '') = '' THEN
      RAISE EXCEPTION 'Every sale item must have a name';
    END IF;

    UPDATE public.sale_items
    SET actual_price = v_actual_price,
        item_name = pg_catalog.btrim(v_item ->> 'item_name'),
        brand = NULLIF(pg_catalog.btrim(v_item ->> 'brand'), ''),
        category = COALESCE(
          NULLIF(pg_catalog.btrim(v_item ->> 'category'), ''),
          category
        ),
        size = NULLIF(pg_catalog.btrim(v_item ->> 'size'), '')
    WHERE id = v_sale_item_id
      AND sale_id = p_sale_id;
    GET DIAGNOSTICS v_updated_count = ROW_COUNT;
    IF v_updated_count <> 1 THEN
      RAISE EXCEPTION 'Sale item not found in this sale';
    END IF;

    UPDATE public.inventory AS inventory
    SET name = pg_catalog.btrim(v_item ->> 'item_name'),
        brand = COALESCE(NULLIF(pg_catalog.btrim(v_item ->> 'brand'), ''), ''),
        category = COALESCE(
          NULLIF(pg_catalog.btrim(v_item ->> 'category'), ''),
          inventory.category
        ),
        size = NULLIF(pg_catalog.btrim(v_item ->> 'size'), '')
    WHERE inventory.id = (
      SELECT sale_item.inventory_id
      FROM public.sale_items AS sale_item
      WHERE sale_item.id = v_sale_item_id
        AND sale_item.sale_id = p_sale_id
    );
  END LOOP;

  UPDATE public.inventory AS inventory
  SET is_sold = false
  FROM public.sale_items AS sale_item
  WHERE sale_item.sale_id = p_sale_id
    AND NOT (sale_item.id = ANY(v_seen_ids))
    AND inventory.id = sale_item.inventory_id;

  DELETE FROM public.sale_items AS sale_item
  WHERE sale_item.sale_id = p_sale_id
    AND NOT (sale_item.id = ANY(v_seen_ids));
END;
$function$;

REVOKE ALL ON FUNCTION public.update_sale(uuid, timestamptz, text, text, text, jsonb)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_sale(uuid, timestamptz, text, text, text, jsonb)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.delete_sale(p_sale_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_sale public.sales%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'You must be signed in to delete a sale';
  END IF;

  SELECT * INTO v_sale
  FROM public.sales
  WHERE id = p_sale_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Sale not found';
  END IF;

  IF v_sale.recorded_by IS DISTINCT FROM auth.uid()
     AND NOT public.has_app_role('manager')
     AND NOT public.has_app_role('admin') THEN
    RAISE EXCEPTION 'You can only delete your own sales';
  END IF;

  UPDATE public.inventory AS inventory
  SET is_sold = false
  FROM public.sale_items AS sale_item
  WHERE sale_item.sale_id = p_sale_id
    AND inventory.id = sale_item.inventory_id;

  DELETE FROM public.sales WHERE id = p_sale_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.delete_sale(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.delete_sale(uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';
