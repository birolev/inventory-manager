-- One row per checkout and one row per inventory item sold in that checkout.
CREATE TABLE public.sales (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  sold_at timestamptz NOT NULL DEFAULT now(),
  location text NOT NULL,
  payment_method text NOT NULL
    CHECK (payment_method IN ('cash', 'card', 'mixed')),
  notes text,
  recorded_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- Match inventory.id's existing type so this migration works whether the
-- current project uses UUID or an integer inventory key.
DO $$
DECLARE
  inventory_id_type text;
BEGIN
  SELECT format_type(attribute.atttypid, attribute.atttypmod)
  INTO inventory_id_type
  FROM pg_attribute AS attribute
  WHERE attribute.attrelid = 'public.inventory'::regclass
    AND attribute.attname = 'id'
    AND attribute.attnum > 0
    AND NOT attribute.attisdropped;

  IF inventory_id_type IS NULL THEN
    RAISE EXCEPTION 'Could not determine public.inventory.id type';
  END IF;

  EXECUTE format($create_table$
    CREATE TABLE public.sale_items (
      id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
      sale_id uuid NOT NULL REFERENCES public.sales(id) ON DELETE CASCADE,
      inventory_id %s REFERENCES public.inventory(id) ON DELETE SET NULL,
      item_name text NOT NULL,
      brand text,
      category text NOT NULL,
      gender text NOT NULL CHECK (gender IN ('női', 'férfi')),
      size text,
      original_price numeric(12, 2) NOT NULL CHECK (original_price >= 0),
      actual_price numeric(12, 2) NOT NULL CHECK (actual_price >= 0),
      created_at timestamptz NOT NULL DEFAULT now(),
      UNIQUE (inventory_id)
    )
  $create_table$, inventory_id_type);
END;
$$;

CREATE INDEX sales_sold_at_idx ON public.sales (sold_at DESC);
CREATE INDEX sales_location_sold_at_idx ON public.sales (location, sold_at DESC);
CREATE INDEX sale_items_sale_id_idx ON public.sale_items (sale_id);

ALTER TABLE public.sales ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sale_items ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated users can manage sales"
  ON public.sales
  FOR ALL
  TO authenticated
  USING (true)
  WITH CHECK (true);

CREATE POLICY "Authenticated users can manage sale items"
  ON public.sale_items
  FOR ALL
  TO authenticated
  USING (true)
  WITH CHECK (true);
