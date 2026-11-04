-- Return enough state for the Edge Function to cache healthy/blocked models
-- while preserving the database-backed single probe lease for half-open tests.
CREATE OR REPLACE FUNCTION public.claim_ai_model_for_edge(
  p_model_name text,
  p_probe_lease_seconds integer DEFAULT 90
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_health public.ai_model_health%ROWTYPE;
BEGIN
  IF p_model_name IS NULL OR pg_catalog.btrim(p_model_name) = '' THEN
    RETURN 'blocked';
  END IF;

  INSERT INTO public.ai_model_health (model_name)
  VALUES (p_model_name)
  ON CONFLICT (model_name) DO NOTHING;

  SELECT * INTO v_health
  FROM public.ai_model_health
  WHERE model_name = p_model_name
  FOR UPDATE;

  IF v_health.cooldown_until IS NULL THEN
    RETURN 'available';
  END IF;
  IF v_health.cooldown_until > now() THEN
    RETURN 'blocked';
  END IF;
  IF v_health.probe_lease_until IS NOT NULL AND v_health.probe_lease_until > now() THEN
    RETURN 'blocked';
  END IF;

  UPDATE public.ai_model_health
  SET probe_lease_until = now() + pg_catalog.make_interval(
        secs => GREATEST(15, LEAST(COALESCE(p_probe_lease_seconds, 90), 300))
      ),
      updated_at = now()
  WHERE model_name = p_model_name;
  RETURN 'probe';
END;
$function$;

REVOKE ALL ON FUNCTION public.claim_ai_model_for_edge(text, integer)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_ai_model_for_edge(text, integer) TO service_role;
