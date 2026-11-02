# Secondhand Inventory & Sales Manager

A Flutter application for managing inventory and sales at a secondhand clothing business. It is used in day-to-day operations across multiple store locations.

## Technical highlights

- **AI image analysis:** Supabase Edge Functions call Gemini and OpenAI vision APIs to generate structured clothing details and image-search criteria. Provider credentials stay server-side.
- **Resilient model orchestration:** Retry with exponential backoff for transient errors, fallback across providers and models, request timeouts, and a database-backed circuit breaker with a local fallback state.
- **Reviewable AI output:** Intake suggestions can be edited before saving; suggested and final values are recorded for later accuracy analysis.
- **Supabase backend:** PostgreSQL migrations define inventory, sales, model health, and AI review data. Supabase Auth handles access, Storage holds item images, and database RPCs support transactional sales operations.
- **Shared inventory querying:** A reusable Dart search service applies consistent filters and pagination across inventory workflows, including broader fallback searches.

## CI/CD

GitHub Actions runs for pull requests targeting `main` and pushes to `main`. A path filter skips Flutter checks for documentation-only changes. Flutter analysis and tests run when app or test code changes; the web release is built and deployed only when web-app inputs change. Same-repository pull requests deploy a Netlify preview, while pushes to `main` deploy to production. Deployment waits for applicable quality checks, and Netlify credentials are supplied through GitHub Secrets.

## Technology

Flutter, Dart, Supabase Auth, PostgreSQL, Supabase Storage, Supabase Edge Functions, TypeScript/Deno, Gemini Vision, OpenAI Vision, GitHub Actions, Netlify

## Platforms

Android and Web
