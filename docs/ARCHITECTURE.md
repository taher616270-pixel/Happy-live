# Happy Live Architecture

## Product boundaries
- `frontend/`: Flutter application for web first, then Android and iOS from the same codebase.
- `backend/worker/`: active TypeScript Cloudflare Worker JSON API.
- `backend/worker/migrations/`: D1 SQLite schema migrations.
- `admin/`: separate administration web client. It must use the same authenticated API and never connect directly to D1.
- `infra/`: optional local development tooling; it is not a production VPS requirement.

## Hosting-first runtime
- Flutter Web and the separate admin frontend are static deployments on Cloudflare Pages.
- The API runs on Cloudflare Workers.
- D1 stores durable relational application records.
- R2 stores images, avatars, covers, gift media and other object files.
- Workers KV is optional for cache/configuration only; D1 remains the source of truth.
- Agora is the planned audio transport. The backend must issue short-lived room credentials only after checking membership and permissions. Never expose an Agora App Certificate.

## Backend migration decision
Cloudflare Workers + D1 + R2 is the canonical target to minimize fixed hosting costs. The initial Laravel/MySQL/Redis scaffold is retained temporarily as historical reference and is not deployed or extended. No MySQL, Redis or paid VPS is required by the active architecture.

## Security invariants
- Never trust client-supplied balances, VIP levels, roles, gift prices or room permissions.
- Wallet changes must be append-only ledger transactions created by the backend.
- Admin routes require server-side role checks and audit records.
- Passwords, session tokens and OTPs must be securely hashed; never store plaintext credentials.
- Secrets belong in Cloudflare secrets, never in Git.
- Validate all input, rate-limit authentication and OTP endpoints, and avoid logging tokens or personal data.
- Media access rules and upload authorization must be enforced by the API, not by client-supplied object keys.

## Initial API surface
- `GET /api/v1`: API metadata.
- `GET /api/v1/health`: D1 and media binding health.
- Planned modules: auth, profiles, feed, communities, messaging, voice, gifts, wallet, VIP, subscriptions and administration.

## Delivery sequence
1. Establish Worker, D1 schema and R2 bindings.
2. Implement and test authentication, sessions, Google sign-in and OTP recovery.
3. Implement profiles, posts, follows, communities and messaging.
4. Integrate Agora rooms and server-issued tokens.
5. Add gifts, ledger, VIP and subscriptions.
6. Build the separate admin client and operational audit tools.
7. Security review, automated tests, staging and controlled release.

The legacy GABO LIVE repository remains a read-only product reference. No production service is connected by this scaffold.
