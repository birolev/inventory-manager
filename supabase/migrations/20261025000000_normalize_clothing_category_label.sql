-- Correct the legacy misspelling so existing inventory matches the canonical label.
UPDATE public.inventory
SET category = 'Póló'
WHERE category = 'Poló';
