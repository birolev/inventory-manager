-- Store the AI's intake suggestions alongside the values saved by the user so
-- model accuracy can be reviewed with SQL without exposing this data in the app.
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
    CREATE TABLE public.ai_intake_reviews (
      id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
      inventory_id %s REFERENCES public.inventory(id) ON DELETE SET NULL,
      recorded_by uuid DEFAULT auth.uid()
        REFERENCES auth.users(id) ON DELETE SET NULL,
      model text NOT NULL,
      ai_values jsonb NOT NULL CHECK (jsonb_typeof(ai_values) = 'object'),
      final_values jsonb NOT NULL CHECK (jsonb_typeof(final_values) = 'object'),
      changed_fields text[] NOT NULL DEFAULT '{}',
      created_at timestamptz NOT NULL DEFAULT now()
    )
  $create_table$, inventory_id_type);
END;
$$;

CREATE INDEX ai_intake_reviews_created_at_idx
  ON public.ai_intake_reviews (created_at DESC);
CREATE INDEX ai_intake_reviews_model_idx
  ON public.ai_intake_reviews (model);

ALTER TABLE public.ai_intake_reviews ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.ai_intake_reviews FROM PUBLIC, anon, authenticated;
GRANT INSERT ON TABLE public.ai_intake_reviews TO authenticated;

CREATE POLICY "Authenticated users can record their AI intake reviews"
  ON public.ai_intake_reviews
  FOR INSERT
  TO authenticated
  WITH CHECK (recorded_by = (SELECT auth.uid()));
