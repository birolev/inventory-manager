-- Track per-user AI requests in UTC. The RPC is callable only by the trusted
-- Edge Function service role; app clients cannot read or change quota rows.
CREATE TABLE IF NOT EXISTS public.ai_analysis_usage (
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  usage_day date NOT NULL,
  request_count integer NOT NULL DEFAULT 0 CHECK (request_count >= 0),
  PRIMARY KEY (user_id, usage_day)
);

ALTER TABLE public.ai_analysis_usage ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.ai_analysis_usage FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.consume_ai_analysis_quota(p_user_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_count integer;
BEGIN
  IF p_user_id IS NULL THEN
    RETURN false;
  END IF;

  INSERT INTO public.ai_analysis_usage (user_id, usage_day, request_count)
  VALUES (p_user_id, (now() AT TIME ZONE 'UTC')::date, 1)
  ON CONFLICT (user_id, usage_day) DO UPDATE
    SET request_count = public.ai_analysis_usage.request_count + 1
    WHERE public.ai_analysis_usage.request_count < 20
  RETURNING request_count INTO v_count;

  RETURN FOUND;
END;
$function$;

REVOKE ALL ON FUNCTION public.consume_ai_analysis_quota(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.consume_ai_analysis_quota(uuid) TO service_role;
