CREATE OR REPLACE FUNCTION public.record_sale(
  p_location text,
  p_payment_method text,
  p_items jsonb,
  p_sold_at timestamptz DEFAULT now(),
  p_notes text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_sale_id uuid;
  v_item jsonb;
  v_inventory public.inventory%ROWTYPE;
  v_actual_price numeric(12, 2);
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'You must be signed in to record a sale';
  END IF;

  IF p_location IS NULL OR btrim(p_location) = '' THEN
    RAISE EXCEPTION 'Sale location is required';
  END IF;

  IF p_items IS NULL
     OR pg_catalog.jsonb_typeof(p_items) <> 'array'
     OR pg_catalog.jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'A sale must contain at least one inventory item';
  END IF;

  INSERT INTO public.sales (sold_at, location, payment_method, notes, recorded_by)
  VALUES (
    COALESCE(p_sold_at, now()),
    btrim(p_location),
    p_payment_method,
    NULLIF(btrim(p_notes), ''),
    auth.uid()
  )
  RETURNING id INTO v_sale_id;

  FOR v_item IN
    SELECT item
    FROM pg_catalog.jsonb_array_elements(p_items) AS items(item)
  LOOP
    IF COALESCE(v_item ->> 'inventory_id', '') = '' THEN
      RAISE EXCEPTION 'Every sale item must include an inventory_id';
    END IF;

    BEGIN
      v_actual_price := (v_item ->> 'actual_price')::numeric(12, 2);
    EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range THEN
      RAISE EXCEPTION 'Sale item actual_price must be a valid non-negative amount';
    END;

    IF v_actual_price < 0 THEN
      RAISE EXCEPTION 'Sale item actual_price cannot be negative';
    END IF;

    UPDATE public.inventory AS inventory
    SET is_sold = true
    WHERE inventory.id = (
      pg_catalog.jsonb_populate_record(
        NULL::public.inventory,
        pg_catalog.jsonb_build_object('id', v_item -> 'inventory_id')
      )
    ).id
      AND inventory.is_sold IS DISTINCT FROM true
    RETURNING inventory.* INTO v_inventory;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Inventory item % is missing or already sold',
        v_item ->> 'inventory_id';
    END IF;

    INSERT INTO public.sale_items (
      sale_id,
      inventory_id,
      item_name,
      brand,
      category,
      gender,
      size,
      original_price,
      actual_price
    )
    VALUES (
      v_sale_id,
      v_inventory.id,
      COALESCE(NULLIF(v_inventory.name, ''), 'Unknown item'),
      v_inventory.brand,
      COALESCE(NULLIF(v_inventory.category, ''), 'other'),
      COALESCE(NULLIF(v_inventory.gender, ''), 'férfi'),
      v_inventory.size,
      COALESCE(v_inventory.price_est, 0),
      v_actual_price
    );
  END LOOP;

  RETURN v_sale_id;
END;
$function$;

-- Keep sale records readable by signed-in users, and route writes through the
-- transaction above so inventory status and sale snapshots stay in sync.
DROP POLICY IF EXISTS "Authenticated users can manage sales" ON public.sales;
DROP POLICY IF EXISTS "Authenticated users can manage sale items" ON public.sale_items;

CREATE POLICY "Authenticated users can read sales"
  ON public.sales FOR SELECT TO authenticated USING (true);
CREATE POLICY "Authenticated users can read sale items"
  ON public.sale_items FOR SELECT TO authenticated USING (true);

GRANT SELECT ON public.sales, public.sale_items TO authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.sales, public.sale_items
  FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.record_sale(text, text, jsonb, timestamptz, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.record_sale(text, text, jsonb, timestamptz, text)
  TO authenticated;
