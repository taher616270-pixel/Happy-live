# Happy Live Architecture

## Product boundaries
- `frontend/`: Flutter application for web first, then Android and iOS.
- `backend/`: Laravel JSON API; the server is authoritative for identity, permissions, wallet ledger, gifts, subscriptions and moderation.
- `admin/`: separate administration web client. It must use the same authenticated API and never connect directly to the database.
- `infra/`: local development services.

## Runtime
- Flutter communicates with Laravel over versioned HTTPS JSON endpoints under `/api/v1`.
- Laravel uses MySQL for durable records and Redis for cache, queues and presence coordination.
- Agora is the planned audio transport. The backend issues short-lived room credentials after checking membership and permissions. Never expose Agora App Certificate.
- Media uploads should use server-issued signed upload policies; store metadata and access rules in the API.

## Security invariants
- Never trust client-supplied balances, VIP levels, roles, gift prices or room permissions.
- Wallet changes are append-only ledger transactions created by the backend.
- Admin routes require server-side role checks and audit records.
- Secrets belong in environment variables or a secret manager, never in Git.
- Validate all input, rate-limit authentication and OTP endpoints, and avoid logging tokens or personal data.

## Initial API surface
- `GET /api/v1/health`: liveness check.
- Future modules: auth, profiles, feed, communities, messaging, voice, gifts, wallet, VIP, subscriptions and administration.

## Delivery sequence
1. Establish reproducible local services and app shells.
2. Implement authentication and profile contracts.
3. Implement social features and moderation.
4. Integrate Agora rooms and server-issued tokens.
5. Add gifts, ledger, VIP and subscriptions.
6. Build the separate admin client and operational audit tools.
7. Security review, automated tests, staging and controlled release.

The legacy repository is a read-only product reference. No production service is connected by this scaffold.
