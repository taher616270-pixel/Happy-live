# Happy Live

A fresh, web-first rebuild of the GABO LIVE product.

## Project direction
- Flutter Web first, with Android and iOS sharing the Flutter application.
- Cloudflare Workers for the API.
- Cloudflare D1 (SQLite) for relational application data.
- Cloudflare R2 for media and uploaded assets.
- Cloudflare Pages for the Flutter Web app and separate admin frontend.
- Agora for live audio rooms, subject to its free quota and pricing.
- Arabic RTL user interface with a premium black, gold, and purple visual identity.

## Repository principles
- This repository is the clean implementation workspace.
- The legacy GABO LIVE repository remains untouched and is retained as a read-only reference.
- Do not commit secrets, production credentials, or real user data.
- Do not connect production traffic until the new application has been tested.
- Cloudflare free plans have usage limits; this is a low-fixed-cost architecture, not unlimited free hosting.

## Planned structure
- `frontend/` — Flutter application.
- `backend/worker/` — active Cloudflare Workers API and D1 migrations.
- `backend/` — historical Laravel scaffold only; do not extend or deploy it.
- `admin/` — separate administration dashboard.
- `docs/` — architecture, roadmap, and implementation notes.

## Current scaffold
The repository contains the Flutter RTL application shell, a TypeScript Worker API with health and metadata routes, an initial D1 migration, R2 binding configuration, a separate admin boundary, and architecture/roadmap documentation.

The Cloudflare D1 database and R2 bucket still need to be created in the account. The Worker has not yet been installed, typechecked, locally run, or deployed. No production service has been changed.
