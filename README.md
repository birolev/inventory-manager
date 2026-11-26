# Secondhand Inventory & Sales Manager

A Flutter application for managing clothing inventory and sales at a secondhand retail business, used in day-to-day operations across multiple store locations.

## Key Technical Highlights

### Embedded Vector Search (`pgvector`)
- **Image-to-vector matching:** A Supabase Edge Function (`image-embedding`) validates uploaded JPEG/PNG images (up to 6 MB) and generates 1536-dimensional embeddings using `gemini-embedding-2`.
- **Hybrid SQL + vector querying:** The PostgreSQL RPC `search_inventory_by_embedding` ranks items by `pgvector` cosine distance (`<=>`) while applying structured filters (location, category, gender, size, brand, color, pattern, and sale status) in the same query.
- **Embedding reuse & backfill:** `InventorySearchController` caches the current image's embedding so changing filters or sort order re-queries PostgreSQL without re-calling the embedding API. An incremental `backfillMissing` utility generates embeddings for legacy inventory rows that have images but no vector yet.
- **Automatic fallback:** In `automatic` mode, if vector search fails or returns no matches, the client falls back to vision-based attribute extraction and standard attribute filtering.

### AI Vision Integration & Fault Tolerance
- **Server-side vision pipeline:** The `gemini-vision` Supabase Edge Function extracts structured clothing attributes for inventory intake and search while keeping provider API keys server-side behind Supabase Auth JWT verification and CORS origin checks.
- **Resilient model orchestration:** Requests use per-attempt timeouts, exponential backoff retries on transient errors, and ordered fallback across Gemini and OpenAI models (`gemini-3.1-flash-lite`, `gemini-3.5-flash-lite`, `gpt-6-luna`).
- **Circuit breaker & quotas:** A PostgreSQL-backed circuit breaker (`claim_ai_model_for_edge`, `record_ai_model_success`, `record_ai_model_failure`) tracks model health with an in-memory fallback if the health store is unreachable, alongside per-user daily AI analysis quotas.
- **Human-in-the-loop review:** Staff can edit AI-suggested intake fields before saving; both the original AI output and final saved values are recorded in `ai_intake_reviews` for accuracy tracking.

### Backend Architecture & Database Security
- **PostgreSQL & Supabase:** Versioned SQL migrations define inventory, sales, AI health, quota, and review schemas, with Supabase Auth for access control and Supabase Storage for item photos.
- **Transactional RPCs & duplicate detection:** Sales are recorded, updated, and deleted via PostgreSQL RPCs (`record_sale`, `update_sale`, `delete_sale`). Possible duplicate items are flagged using `pg_trgm` trigram similarity (`find_possible_inventory_duplicates`) combined with attribute matching.
- **Security & `pgTAP` tests:** Role-based access rules restrict sensitive tables and functions, and `supabase/tests/security.test.sql` verifies with `pgTAP` that `anon` and unauthorized callers cannot execute privileged RPCs.

### Frontend Architecture & Testability
- **Decoupled state management:** `InventorySearchController` manages search mode transitions, filter state, and request sequence tokens (to ignore stale out-of-order async responses), communicating with the backend through an `InventorySearchGateway` abstraction.
- **Operational workflows:** Includes batch image intake (`BatchImageQueue`), reusable paginated inventory search (`InventorySearch`), sales recording, and sales/team statistics dashboards.
- **Automated unit & widget tests:** Flutter tests cover search controllers, query/sort behavior, sales screens, and stats calculations without requiring live network calls.

## CI/CD

GitHub Actions (`.github/workflows/web-ci-deploy.yml`) runs on pull requests to `main` and pushes to `main`:
- **Path filtering** skips Flutter and backend checks on documentation-only changes.
- **Quality checks** run `flutter analyze`, `flutter test`, and `deno test supabase/functions/gemini-vision` when relevant files change.
- **Web deployment** builds the Flutter web release and deploys PR previews (for same-repository PRs) or production (on pushes to `main`) to Netlify once checks pass.

## Tech Stack

- **Frontend:** Flutter, Dart
- **Backend & Database:** Supabase (Auth, PostgreSQL, `pgvector`, `pg_trgm`, Storage, Edge Functions in TypeScript/Deno)
- **AI Models:** Gemini (`gemini-embedding-2`, Gemini Vision), OpenAI Vision
- **Testing & CI/CD:** `flutter test`, `deno test`, `pgTAP`, GitHub Actions, Netlify

## Platforms

Android and Web
