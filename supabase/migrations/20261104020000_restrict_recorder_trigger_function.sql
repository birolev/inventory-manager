-- Trigger functions do not need client-callable EXECUTE grants once their
-- trigger has been created. Keep this helper unavailable through the Data API.
REVOKE ALL ON FUNCTION public.set_sale_recorder_email()
  FROM PUBLIC, anon, authenticated;
