# Secondhand Inventory & Sales Manager

[![Web CI and deploy](https://github.com/birolev/yoaron-inventory-manager/actions/workflows/web-ci-deploy.yml/badge.svg?branch=main)](https://github.com/birolev/yoaron-inventory-manager/actions/workflows/web-ci-deploy.yml)

A Flutter application for managing the day-to-day operations of a secondhand clothing business. It brings AI-assisted intake, inventory search, sales recording, and reporting into one workflow.

**In daily use, managing approximately 2,000 clothing items across multiple store locations.**

<!-- Add a product preview here when screenshots or a demo are available. -->

## What it does

### AI-assisted intake

Staff can photograph one or multiple items and receive suggested product details, including brand, category, color, pattern, size, condition, and estimated price. Suggestions can be reviewed and edited before saving. If an AI provider is temporarily unavailable, the backend retries transient failures and can fall back to another model. Intake corrections are recorded for later accuracy analysis.

### Inventory operations

Browse, filter, sort, and edit the inventory; search by text or photo; track item locations and sale status; and add an item directly to a sale. Shared inventory search logic keeps results consistent across inventory, search, and sales workflows.

### Sales and reporting

Record sales with item-level prices, payment method, date, location, and notes. Review daily and monthly performance, update or remove sale records, and copy daily summaries for reporting.

### Access and data

Supabase Auth provides sign-in. PostgreSQL stores inventory and sales data, while Supabase Storage holds item photos. Sensitive AI provider calls run in Supabase Edge Functions rather than exposing provider credentials in the Flutter client.

## Built with

| Area | Technologies |
| --- | --- |
| Client | Flutter, Dart |
| Backend | Supabase Auth, PostgreSQL, Storage, Edge Functions |
| AI | Gemini and OpenAI vision models with retry and fallback handling |

## Platforms

Android and Web

## CI/CD

GitHub Actions runs Flutter analysis, the widget test suite, and a release web build for pull requests targeting `main`. Pull requests from this repository also receive a Netlify preview deployment. After changes are merged to `main`, the workflow builds the web app and deploys it to Netlify production.

The workflow pins Flutter to 3.47.7 and caches the Flutter SDK and Dart packages. Netlify deployments use the `NETLIFY_AUTH_TOKEN` and `NETLIFY_SITE_ID` GitHub Actions repository secrets.
