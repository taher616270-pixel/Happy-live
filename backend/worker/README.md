# Happy Live Cloudflare API

The active backend is a TypeScript Cloudflare Worker. It is designed to keep the initial hosting footprint on Cloudflare's free allowances where possible.

## Components
- Workers: versioned JSON API.
- D1: relational SQLite database.
- R2: user-uploaded media and gift assets.
- Pages: Flutter Web and the separate admin frontend.

Free allowances and product limits can change. This architecture is intended to avoid a monthly VPS/database bill, not to promise unlimited free usage. Live audio is a separate provider and may incur charges beyond its current free quota.

## Current implementation
- `GET /api/v1`: API metadata.
- `GET /api/v1/health`: checks the D1 binding and reports media binding status.
- CORS allowlist for local development and the initial Pages hostname; additional deployed origins are configured with `ALLOWED_ORIGINS`.
- Initial D1 migration for accounts, hashed sessions, password-reset OTP records, profiles, admin roles and audit logs.

No registration, login, OTP delivery, profile mutation, wallet, gifts, or room endpoints are implemented yet. The health route is not an authentication system.

## Cloudflare setup (one-time)
1. The D1 database `happy-live-db` has already been created in the Cloudflare account in APAC, and the initial schema has been applied and verified. Its database ID is already in `wrangler.toml`.
2. Enable R2 Object Storage in the Cloudflare dashboard. The account currently returns an R2-not-enabled response, so the `happy-live-media` bucket cannot be created yet.
3. After R2 is enabled, create an R2 bucket named `happy-live-media`.
4. Install dependencies in this directory with `npm install`.
5. Apply the checked-in migration locally first, then remotely only after reviewing the target database. The schema has already been applied directly to the remote D1 database; the checked-in migration is idempotent and can safely register the same initial schema with Wrangler.
   - `npm run db:local`
   - `npm run db:remote`
6. Run `npm run typecheck` and `npm run dev`.
7. Deploy only after local checks pass with `npm run deploy`.

Do not deploy while the D1 ID is a placeholder. Never commit API tokens, email-provider credentials, Agora certificates, or other secrets. Add secrets with Wrangler's secret management or the Cloudflare dashboard.

## Local development
The project uses Wrangler's local D1 emulator. The R2 binding can be emulated locally by Wrangler. Keep real user data out of local fixtures and source control.
