CREATE TABLE public.ai_model_health (
  model_name text PRIMARY KEY,
  consecutive_failures integer NOT NULL DEFAULT 0,
  cooldown_until timestamptz,
  probe_lease_until timestamptz,
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.ai_model_health ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.claim_ai_model(
  p_model_name text,
  p_probe_lease_seconds integer DEFAULT 90
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_health public.ai_model_health%ROWTYPE;
BEGIN
  INSERT INTO public.ai_model_health (model_name)
  VALUES (p_model_name)
  ON CONFLICT (model_name) DO NOTHING;

  SELECT * INTO v_health
  FROM public.ai_model_health
  WHERE model_name = p_model_name
  FOR UPDATE;

  IF v_health.cooldown_until IS NULL THEN
    RETURN true;
  END IF;

  IF v_health.cooldown_until > now() THEN
    RETURN false;
  END IF;

  IF v_health.probe_lease_until IS NOT NULL
     AND v_health.probe_lease_until > now() THEN
    RETURN false;
  END IF;

  UPDATE public.ai_model_health
  SET probe_lease_until = now() + pg_catalog.make_interval(
    secs => GREATEST(15, LEAST(p_probe_lease_seconds, 300))
  ),
  updated_at = now()
  WHERE model_name = p_model_name;

  RETURN true;
END;
$function$;

CREATE OR REPLACE FUNCTION public.record_ai_model_success(p_model_name text)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $function$
  INSERT INTO public.ai_model_health (
    model_name,
    consecutive_failures,
    cooldown_until,
    probe_lease_until,
    updated_at
  )
  VALUES (p_model_name, 0, NULL, NULL, now())
  ON CONFLICT (model_name) DO UPDATE
  SET consecutive_failures = 0,
      cooldown_until = NULL,
      probe_lease_until = NULL,
      updated_at = now();
$function$;

CREATE OR REPLACE FUNCTION public.record_ai_model_failure(p_model_name text)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_failures integer;
  v_cooldown_seconds integer;
BEGIN
  INSERT INTO public.ai_model_health (model_name)
  VALUES (p_model_name)
  ON CONFLICT (model_name) DO NOTHING;

  UPDATE public.ai_model_health
  SET consecutive_failures = consecutive_failures + 1,
      probe_lease_until = NULL,
      updated_at = now()
  WHERE model_name = p_model_name
  RETURNING consecutive_failures INTO v_failures;

  v_cooldown_seconds := LEAST(
    1800::numeric,
    60::numeric * pg_catalog.power(
      2::numeric,
      LEAST(GREATEST(v_failures - 1, 0), 5)::numeric
    )
  );

  UPDATE public.ai_model_health
  SET cooldown_until = now() + pg_catalog.make_interval(secs => v_cooldown_seconds),
      updated_at = now()
  WHERE model_name = p_model_name;

  RETURN v_cooldown_seconds;
END;
$function$;

REVOKE ALL ON TABLE public.ai_model_health FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.claim_ai_model(text, integer)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.record_ai_model_success(text)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.record_ai_model_failure(text)
  FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.claim_ai_model(text, integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.record_ai_model_success(text) TO service_role;
GRANT EXECUTE ON FUNCTION public.record_ai_model_failure(text) TO service_role;
