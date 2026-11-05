-- Inventory is available to signed-in staff, who can work with both stores.
-- Anonymous clients have no inventory access; authenticated clients need CRUD
-- for intake, listing, sale selection, edits, and deletion. In particular,
-- do not grant TRUNCATE, REFERENCES, or TRIGGER to client roles.
ALTER TABLE public.inventory ENABLE ROW LEVEL SECURITY;

REVOKE ALL PRIVILEGES ON TABLE public.inventory FROM PUBLIC, anon, authenticated;

-- TRUNCATE is not governed by row-level security, so keep it unavailable to
-- every client role, including users with an application-level admin role.
REVOKE TRUNCATE ON TABLE public.inventory FROM PUBLIC, anon, authenticated;

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.inventory TO authenticated;
