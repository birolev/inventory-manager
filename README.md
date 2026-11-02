# Secondhand Inventory & Sales Manager

A cross-platform inventory and sales app for a secondhand clothing business. It combines AI-assisted item intake, searchable stock management, and sales reporting in one workflow.

**Status:** Active development · MVP

<!-- Add a short demo or product screenshots here. -->

## Overview

Staff can photograph new items and use Gemini to suggest product details and an estimated price. Suggestions stay editable for review before an item is saved. The same inventory can then be searched, updated, and added to recorded sales across store locations.

## Key Features

- **AI-assisted intake:** Analyze single or multiple item photos and prefill details such as category, brand, color, pattern, and estimated price.
- **Inventory management:** Browse, search, filter, edit, and track items across locations. Photo search uses the same inventory matching flow.
- **Sales recording:** Add inventory items to a sale, adjust sale prices, and record payment method, date, location, and notes.
- **Sales reporting:** Review daily and monthly totals, edit or delete sale records, and copy a daily sales summary.
- **Authenticated access:** Sign-in and password setup backed by Supabase Auth.

## Technology

| Area | Tools |
| --- | --- |
| App | Flutter, Dart |
| Backend | Supabase Auth, PostgreSQL, Storage, and Edge Functions |
| Image analysis | Google Gemini API |

Gemini requests run through a Supabase Edge Function, keeping the provider credential out of the client app.

## Platforms

Android and Web builds.
