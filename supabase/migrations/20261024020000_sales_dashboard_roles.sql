-- Keep employee roles outside user-editable metadata. Roles are granted by an
-- administrator through the Supabase SQL editor (or a trusted backend).
CREATE TABLE IF NOT EXISTS public.app_user_roles (
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role text NOT NULL CHECK (role IN ('admin', 'manager', 'staff')),
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, role)
);

-- The table may have been created manually before this migration was pushed.
-- Bring its role constraint forward without replacing or deleting its rows.
ALTER TABLE public.app_user_roles
  ADD COLUMN IF NOT EXISTS created_at timestamptz NOT NULL DEFAULT now();
ALTER TABLE public.app_user_roles
  DROP CONSTRAINT IF EXISTS app_user_roles_role_check;
ALTER TABLE public.app_user_roles
  ADD CONSTRAINT app_user_roles_role_check
  CHECK (role IN ('admin', 'manager', 'staff'));
CREATE UNIQUE INDEX IF NOT EXISTS app_user_roles_user_id_role_idx
  ON public.app_user_roles (user_id, role);

ALTER TABLE public.app_user_roles ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.app_user_roles FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public.has_app_role(p_role text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM public.app_user_roles AS roles
    WHERE roles.user_id = (SELECT auth.uid())
      AND roles.role = p_role
  );
$function$;

REVOKE ALL ON FUNCTION public.has_app_role(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.has_app_role(text) TO authenticated;

-- Give dashboard users a human-readable recorder label without exposing the
-- auth.users table through the Data API.
ALTER TABLE public.sales
  ADD COLUMN IF NOT EXISTS recorded_by_email text,
  ADD COLUMN IF NOT EXISTS recorded_by_name text;

UPDATE public.sales AS sales
SET recorded_by_email = users.email,
    recorded_by_name = COALESCE(
      NULLIF(btrim(users.raw_user_meta_data ->> 'display_name'), ''),
      NULLIF(btrim(users.raw_user_meta_data ->> 'full_name'), ''),
      NULLIF(btrim(users.raw_user_meta_data ->> 'name'), ''),
      users.email
    )
FROM auth.users AS users
WHERE sales.recorded_by = users.id
  AND (sales.recorded_by_email IS NULL OR sales.recorded_by_name IS NULL);

CREATE OR REPLACE FUNCTION public.set_sale_recorder_email()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $function$
BEGIN
  NEW.recorded_by_email := auth.jwt() ->> 'email';
  NEW.recorded_by_name := COALESCE(
    NULLIF(btrim(auth.jwt() -> 'user_metadata' ->> 'display_name'), ''),
    NULLIF(btrim(auth.jwt() -> 'user_metadata' ->> 'full_name'), ''),
    NULLIF(btrim(auth.jwt() -> 'user_metadata' ->> 'name'), ''),
    NEW.recorded_by_email
  );
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS sales_set_recorder_email ON public.sales;
CREATE TRIGGER sales_set_recorder_email
  BEFORE INSERT ON public.sales
  FOR EACH ROW
  EXECUTE FUNCTION public.set_sale_recorder_email();

DROP POLICY IF EXISTS "Authenticated users can read sales" ON public.sales;
DROP POLICY IF EXISTS "Authenticated users can read sale items" ON public.sale_items;
DROP POLICY IF EXISTS "Managers can read sales" ON public.sales;
DROP POLICY IF EXISTS "Managers can read sale items" ON public.sale_items;

CREATE POLICY "Managers can read sales"
  ON public.sales FOR SELECT TO authenticated
  USING (
    (SELECT public.has_app_role('manager'))
    OR (SELECT public.has_app_role('admin'))
  );

CREATE POLICY "Managers can read sale items"
  ON public.sale_items FOR SELECT TO authenticated
  USING (
    (SELECT public.has_app_role('manager'))
    OR (SELECT public.has_app_role('admin'))
  );

-- Example admin grant (run manually in the Supabase SQL editor after
-- replacing the email):
-- INSERT INTO public.app_user_roles (user_id, role)
-- SELECT id, 'admin' FROM auth.users
-- WHERE lower(email) = lower('manager@example.com')
-- ON CONFLICT DO NOTHING;
