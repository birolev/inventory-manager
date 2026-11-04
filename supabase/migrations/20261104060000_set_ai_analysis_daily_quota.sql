-- Set the owner-selected daily limit to 500 without editing the earlier
-- migration that introduced the quota table and RPC.
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
    WHERE public.ai_analysis_usage.request_count < 500
  RETURNING request_count INTO v_count;

  RETURN FOUND;
END;
$function$;

REVOKE ALL ON FUNCTION public.consume_ai_analysis_quota(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.consume_ai_analysis_quota(uuid) TO service_role;
