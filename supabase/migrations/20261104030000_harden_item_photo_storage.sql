-- Item photos are intentionally public because the app stores public URLs in
-- inventory rows. Keep uploads authenticated, bounded, and image-only.
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('clothes-images', 'clothes-images', true, 10485760,
  ARRAY['image/jpeg', 'image/png', 'image/webp']::text[])
ON CONFLICT (id) DO UPDATE
SET public = EXCLUDED.public,
    file_size_limit = EXCLUDED.file_size_limit,
    allowed_mime_types = EXCLUDED.allowed_mime_types;

DROP POLICY IF EXISTS "Authenticated users can upload item photos" ON storage.objects;
CREATE POLICY "Authenticated users can upload item photos"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'clothes-images'
    AND (SELECT auth.uid()) IS NOT NULL
  );

-- These restrictive policies keep any older broad permissive Storage policies
-- from allowing anonymous writes or mutation/deletion of item photos.
DROP POLICY IF EXISTS "Item photo uploads require authentication" ON storage.objects;
CREATE POLICY "Item photo uploads require authentication"
  ON storage.objects AS RESTRICTIVE FOR INSERT TO public
  WITH CHECK (
    bucket_id <> 'clothes-images'
    OR (SELECT auth.uid()) IS NOT NULL
  );

DROP POLICY IF EXISTS "Item photos are immutable" ON storage.objects;
CREATE POLICY "Item photos are immutable"
  ON storage.objects AS RESTRICTIVE FOR UPDATE TO public
  USING (bucket_id <> 'clothes-images')
  WITH CHECK (bucket_id <> 'clothes-images');

DROP POLICY IF EXISTS "Item photos cannot be deleted by clients" ON storage.objects;
CREATE POLICY "Item photos cannot be deleted by clients"
  ON storage.objects AS RESTRICTIVE FOR DELETE TO public
  USING (bucket_id <> 'clothes-images');
