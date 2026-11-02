-- Store garment gender independently from its garment category.
ALTER TABLE public.inventory
  ADD COLUMN IF NOT EXISTS gender text;

-- Migrate rows created while gender values were stored in category.
UPDATE public.inventory
SET gender = category,
    category = 'other'
WHERE category IN ('női', 'férfi');

UPDATE public.inventory
SET gender = 'férfi'
WHERE gender IS NULL OR btrim(gender) = '';

ALTER TABLE public.inventory
  ALTER COLUMN gender SET DEFAULT 'férfi',
  ALTER COLUMN gender SET NOT NULL;

ALTER TABLE public.inventory
  ADD CONSTRAINT inventory_gender_check
  CHECK (gender IN ('női', 'férfi'));
