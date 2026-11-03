# Happy Live

A fresh, web-first rebuild of the GABO LIVE product.

## Project direction

- Flutter Web first, with Android and iOS sharing the Flutter application.
- Laravel API backend.
- MySQL for persistent application data.
- Redis for cache, queues, and realtime coordination.
- Agora for live audio rooms.
- A separate administration dashboard backed by the same API.
- Arabic RTL user interface with a premium black, gold, and purple visual identity.

## Repository principles

- This repository is the clean implementation workspace.
- The legacy GABO LIVE repository remains untouched and is retained as a reference.
- Do not commit secrets, production credentials, or real user data.
- Do not connect production traffic until the new application has been tested.

## Planned structure

- `frontend/` — Flutter application.
- `backend/` — Laravel API.
- `admin/` — administration dashboard.
- `infra/` — Docker and local development infrastructure.
- `docs/` — architecture, API contracts, and implementation notes.

## Status

Repository initialized. Application scaffolding and runtime verification are the next steps.
