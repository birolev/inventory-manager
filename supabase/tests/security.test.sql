-- Run with `supabase test db` against a local database after the project's
-- existing public.inventory base schema has been provisioned. The base table
-- is managed outside this repository, so this test does not invent its DDL.
BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.plan(13);

SELECT extensions.ok(
  NOT pg_catalog.has_function_privilege(
    'anon', 'public.record_sale(text,text,jsonb,timestamptz,text)', 'EXECUTE'
  ), 'anon cannot execute record_sale'
);
SELECT extensions.ok(
  NOT pg_catalog.has_function_privilege(
    'anon', 'public.update_sale(uuid,timestamptz,text,text,text,jsonb)', 'EXECUTE'
  ), 'anon cannot execute update_sale'
);
SELECT extensions.ok(
  NOT pg_catalog.has_function_privilege('anon', 'public.delete_sale(uuid)', 'EXECUTE'),
  'anon cannot execute delete_sale'
);
SELECT extensions.ok(
  NOT pg_catalog.has_function_privilege('anon', 'public.consume_ai_analysis_quota(uuid)', 'EXECUTE')
  AND NOT pg_catalog.has_function_privilege('anon', 'public.claim_ai_model(text,integer)', 'EXECUTE')
  AND NOT pg_catalog.has_function_privilege('anon', 'public.claim_ai_model_for_edge(text,integer)', 'EXECUTE'),
  'anon cannot execute service-only AI functions'
);

SET LOCAL ROLE anon;
SELECT extensions.throws_ok(
  $$SELECT public.record_sale('Csengery', 'cash', '[{"item_name":"test","actual_price":1}]'::jsonb)$$,
  '42501', 'permission denied for function record_sale',
  'anon call to record_sale is rejected'
);
RESET ROLE;

INSERT INTO auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
VALUES (
  'a1000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated',
  'security-test@local.invalid', '', now(),
  '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()
)
ON CONFLICT (id) DO NOTHING;

CREATE TEMP TABLE _security_test_inventory (location text, inventory_id text);
GRANT SELECT ON _security_test_inventory TO authenticated;
INSERT INTO public.inventory (
  name, brand, price_est, category, gender, location, image_url,
  color, pattern, size, condition, is_sold
)
VALUES
  ('HARDENING_TEST_Csengery', '', 500, 'other', 'férfi', 'Csengery', '', '', '', '', 'Használt', false),
  ('HARDENING_TEST_Astoria', '', 700, 'other', 'férfi', 'Astoria', '', '', '', '', 'Használt', false);

-- Keep generated inventory identifiers in the temporary table for RPC calls.
INSERT INTO _security_test_inventory (location, inventory_id)
SELECT location, id::text
FROM public.inventory
WHERE name IN ('HARDENING_TEST_Csengery', 'HARDENING_TEST_Astoria');

SELECT pg_catalog.set_config(
  'request.jwt.claim.sub', 'a1000000-0000-4000-8000-000000000001', true
);
SELECT pg_catalog.set_config(
  'request.jwt.claims',
  '{"sub":"a1000000-0000-4000-8000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
SET LOCAL ROLE authenticated;

SELECT extensions.throws_ok(
  $$SELECT public.record_sale('Csengery', 'bitcoin', '[]'::jsonb)$$,
  'P0001', 'Invalid payment method', 'record_sale rejects an unsupported payment method'
);
SELECT extensions.throws_ok(
  $$SELECT public.record_sale('Csengery', 'cash', '[{"item_name":"test","actual_price":-1}]'::jsonb)$$,
  'P0001', 'Sale item actual_price cannot be negative',
  'record_sale rejects a negative price'
);

SELECT extensions.is(
  (SELECT count(*)::integer FROM public.inventory
   WHERE name LIKE 'HARDENING_TEST_%'),
  2, 'staff can read inventory at both locations'
);
SELECT extensions.lives_ok(
  $$UPDATE public.inventory SET brand = 'test edited' WHERE name = 'HARDENING_TEST_Astoria'$$,
  'staff can update inventory at either location'
);
SELECT extensions.is(
  (SELECT brand FROM public.inventory WHERE name = 'HARDENING_TEST_Astoria'),
  'test edited', 'the cross-location update is visible'
);
SELECT extensions.lives_ok(
  pg_catalog.format(
    'SELECT public.record_sale(%L, %L, %L::jsonb)',
    'Csengery', 'cash',
    (SELECT pg_catalog.jsonb_build_array(
      pg_catalog.jsonb_build_object('inventory_id', inventory_id, 'actual_price', 500)
    )::text FROM _security_test_inventory WHERE location = 'Csengery')
  ),
  'record_sale accepts a valid inventory sale'
);
SELECT extensions.throws_ok(
  pg_catalog.format(
    'SELECT public.record_sale(%L, %L, %L::jsonb)',
    'Csengery', 'cash',
    (SELECT pg_catalog.jsonb_build_array(
      pg_catalog.jsonb_build_object('inventory_id', inventory_id, 'actual_price', 500)
    )::text FROM _security_test_inventory WHERE location = 'Csengery')
  ),
  'P0001',
  pg_catalog.format(
    'Inventory item %s is missing or already sold',
    (SELECT inventory_id FROM _security_test_inventory WHERE location = 'Csengery')
  ),
  'record_sale rejects a second sale of the same item'
);
SELECT extensions.is(
  (SELECT is_sold FROM public.inventory WHERE name = 'HARDENING_TEST_Csengery'),
  true, 'a successful sale marks inventory sold atomically'
);

SELECT * FROM extensions.finish();
ROLLBACK;
