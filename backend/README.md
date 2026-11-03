# Backend

## Active backend
The canonical backend is now the Cloudflare Workers API in [worker/](./worker/).

## Legacy scaffold
The Laravel files currently present in this directory are retained temporarily as historical scaffolding only. They are **not** the active backend, are not part of deployment, and must not be extended. They will be removed or archived after the Worker foundation is verified.

The active data store is Cloudflare D1 (SQLite), with Cloudflare R2 planned for media objects. Do not add MySQL, Redis, or server credentials to the active architecture.
