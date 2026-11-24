-- Track who uploaded each inventory item and expose personal + manager/admin
-- team statistics via secured RPCs.

ALTER TABLE public.inventory
  ADD COLUMN IF NOT EXISTS uploaded_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS uploaded_by_email text,
  ADD COLUMN IF NOT EXISTS uploaded_by_name text;

CREATE INDEX IF NOT EXISTS inventory_uploaded_by_idx
  ON public.inventory (uploaded_by);

-- Automatically stamp the authenticated uploader on insert so client code
-- cannot spoof another employee's identity.
CREATE OR REPLACE FUNCTION public.set_inventory_uploader()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_email text := NULLIF(pg_catalog.btrim(auth.jwt() ->> 'email'), '');
  v_name text := COALESCE(
    NULLIF(pg_catalog.btrim(auth.jwt() -> 'user_metadata' ->> 'display_name'), ''),
    NULLIF(pg_catalog.btrim(auth.jwt() -> 'user_metadata' ->> 'full_name'), ''),
    NULLIF(pg_catalog.btrim(auth.jwt() -> 'user_metadata' ->> 'name'), ''),
    v_email
  );
BEGIN
  IF v_uid IS NOT NULL THEN
    NEW.uploaded_by := v_uid;
  END IF;
  IF v_email IS NOT NULL THEN
    NEW.uploaded_by_email := v_email;
  END IF;
  IF v_name IS NOT NULL THEN
    NEW.uploaded_by_name := v_name;
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS inventory_set_uploader ON public.inventory;
CREATE TRIGGER inventory_set_uploader
  BEFORE INSERT ON public.inventory
  FOR EACH ROW
  EXECUTE FUNCTION public.set_inventory_uploader();

REVOKE ALL ON FUNCTION public.set_inventory_uploader()
  FROM PUBLIC, anon, authenticated;

-- Returns personal upload & sales statistics for the signed-in user, along with
-- whether the caller is allowed to view team-wide statistics.
CREATE OR REPLACE FUNCTION public.get_my_employee_stats()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_email text;
  v_display_name text;
  v_uploaded_count integer := 0;
  v_sales_count integer := 0;
  v_sold_items_count integer := 0;
  v_total_revenue numeric(14, 2) := 0;
  v_active_days integer := 0;
  v_roles text[] := ARRAY[]::text[];
  v_can_view_team boolean := false;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
  END IF;

  SELECT
    u.email,
    COALESCE(
      NULLIF(pg_catalog.btrim(u.raw_user_meta_data ->> 'display_name'), ''),
      NULLIF(pg_catalog.btrim(u.raw_user_meta_data ->> 'full_name'), ''),
      NULLIF(pg_catalog.btrim(u.raw_user_meta_data ->> 'name'), ''),
      u.email
    )
  INTO v_email, v_display_name
  FROM auth.users AS u
  WHERE u.id = v_uid;

  SELECT COALESCE(pg_catalog.array_agg(r.role ORDER BY r.role), ARRAY[]::text[])
  INTO v_roles
  FROM public.app_user_roles AS r
  WHERE r.user_id = v_uid;

  v_can_view_team := public.has_app_role('manager') OR public.has_app_role('admin');

  SELECT count(*)::integer
  INTO v_uploaded_count
  FROM public.inventory AS i
  WHERE i.uploaded_by = v_uid;

  WITH user_sales AS (
    SELECT
      s.id,
      (s.sold_at AT TIME ZONE 'Europe/Budapest')::date AS sale_day,
      COALESCE(SUM(si.actual_price), 0)::numeric(14, 2) AS sale_total,
      COUNT(si.id)::integer AS item_count
    FROM public.sales AS s
    LEFT JOIN public.sale_items AS si ON si.sale_id = s.id
    WHERE s.recorded_by = v_uid
    GROUP BY s.id, sale_day
  )
  SELECT
    COALESCE(COUNT(*), 0)::integer,
    COALESCE(SUM(item_count), 0)::integer,
    COALESCE(SUM(sale_total), 0)::numeric(14, 2),
    COALESCE(COUNT(DISTINCT sale_day), 0)::integer
  INTO v_sales_count, v_sold_items_count, v_total_revenue, v_active_days
  FROM user_sales;

  RETURN pg_catalog.jsonb_build_object(
    'user_id', v_uid,
    'email', COALESCE(v_email, ''),
    'display_name', COALESCE(v_display_name, v_email, ''),
    'roles', v_roles,
    'can_view_team_stats', v_can_view_team,
    'uploaded_items_count', v_uploaded_count,
    'sales_count', v_sales_count,
    'sold_items_count', v_sold_items_count,
    'total_sales_revenue', v_total_revenue,
    'active_sales_days', v_active_days,
    'daily_avg_revenue',
      CASE
        WHEN v_active_days > 0 THEN pg_catalog.round(v_total_revenue / v_active_days, 2)
        ELSE 0
      END,
    'daily_avg_sales_count',
      CASE
        WHEN v_active_days > 0 THEN pg_catalog.round(v_sales_count::numeric / v_active_days, 2)
        ELSE 0
      END
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.get_my_employee_stats() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_employee_stats() TO authenticated;

-- Returns upload & sales statistics for every employee. Restricted to manager
-- and admin roles.
CREATE OR REPLACE FUNCTION public.get_all_employee_stats()
RETURNS SETOF jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
  END IF;

  IF NOT (public.has_app_role('manager') OR public.has_app_role('admin')) THEN
    RAISE EXCEPTION 'Only managers and admins can view team statistics'
      USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  WITH relevant_users AS (
    SELECT r.user_id AS id FROM public.app_user_roles AS r
    UNION
    SELECT s.recorded_by AS id FROM public.sales AS s WHERE s.recorded_by IS NOT NULL
    UNION
    SELECT i.uploaded_by AS id FROM public.inventory AS i WHERE i.uploaded_by IS NOT NULL
  ),
  upload_counts AS (
    SELECT i.uploaded_by AS user_id, COUNT(*)::integer AS uploaded_items_count
    FROM public.inventory AS i
    WHERE i.uploaded_by IS NOT NULL
    GROUP BY i.uploaded_by
  ),
  sale_totals AS (
    SELECT
      s.recorded_by AS user_id,
      s.id AS sale_id,
      (s.sold_at AT TIME ZONE 'Europe/Budapest')::date AS sale_day,
      COALESCE(SUM(si.actual_price), 0)::numeric(14, 2) AS sale_total,
      COUNT(si.id)::integer AS item_count
    FROM public.sales AS s
    LEFT JOIN public.sale_items AS si ON si.sale_id = s.id
    WHERE s.recorded_by IS NOT NULL
    GROUP BY s.recorded_by, s.id, sale_day
  ),
  sales_by_user AS (
    SELECT
      st.user_id,
      COUNT(*)::integer AS sales_count,
      COALESCE(SUM(st.item_count), 0)::integer AS sold_items_count,
      COALESCE(SUM(st.sale_total), 0)::numeric(14, 2) AS total_sales_revenue,
      COUNT(DISTINCT st.sale_day)::integer AS active_sales_days
    FROM sale_totals AS st
    GROUP BY st.user_id
  ),
  roles_by_user AS (
    SELECT
      r.user_id,
      pg_catalog.array_agg(r.role ORDER BY r.role) AS roles
    FROM public.app_user_roles AS r
    GROUP BY r.user_id
  ),
  assembled AS (
    SELECT
      ru.id AS user_id,
      COALESCE(u.email, '') AS email,
      COALESCE(
        NULLIF(pg_catalog.btrim(u.raw_user_meta_data ->> 'display_name'), ''),
        NULLIF(pg_catalog.btrim(u.raw_user_meta_data ->> 'full_name'), ''),
        NULLIF(pg_catalog.btrim(u.raw_user_meta_data ->> 'name'), ''),
        u.email,
        'Ismeretlen'
      ) AS display_name,
      COALESCE(rbu.roles, ARRAY[]::text[]) AS roles,
      COALESCE(uc.uploaded_items_count, 0) AS uploaded_items_count,
      COALESCE(sbu.sales_count, 0) AS sales_count,
      COALESCE(sbu.sold_items_count, 0) AS sold_items_count,
      COALESCE(sbu.total_sales_revenue, 0)::numeric(14, 2) AS total_sales_revenue,
      COALESCE(sbu.active_sales_days, 0) AS active_sales_days
    FROM relevant_users AS ru
    LEFT JOIN auth.users AS u ON u.id = ru.id
    LEFT JOIN upload_counts AS uc ON uc.user_id = ru.id
    LEFT JOIN sales_by_user AS sbu ON sbu.user_id = ru.id
    LEFT JOIN roles_by_user AS rbu ON rbu.user_id = ru.id
  )
  SELECT pg_catalog.jsonb_build_object(
    'user_id', a.user_id,
    'email', a.email,
    'display_name', a.display_name,
    'roles', a.roles,
    'uploaded_items_count', a.uploaded_items_count,
    'sales_count', a.sales_count,
    'sold_items_count', a.sold_items_count,
    'total_sales_revenue', a.total_sales_revenue,
    'active_sales_days', a.active_sales_days,
    'daily_avg_revenue',
      CASE
        WHEN a.active_sales_days > 0 THEN pg_catalog.round(a.total_sales_revenue / a.active_sales_days, 2)
        ELSE 0
      END,
    'daily_avg_sales_count',
      CASE
        WHEN a.active_sales_days > 0 THEN pg_catalog.round(a.sales_count::numeric / a.active_sales_days, 2)
        ELSE 0
      END
  )
  FROM assembled AS a
  ORDER BY a.total_sales_revenue DESC, a.uploaded_items_count DESC, a.display_name ASC;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_all_employee_stats() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_all_employee_stats() TO authenticated;
