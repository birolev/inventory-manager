ALTER TABLE public.inventory
  ADD COLUMN IF NOT EXISTS secondary_categories text[] NOT NULL DEFAULT '{}';

CREATE INDEX IF NOT EXISTS inventory_secondary_categories_gin_idx
  ON public.inventory USING gin (secondary_categories);
