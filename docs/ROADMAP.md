# Happy Live Roadmap

## Phase 0 — Cloudflare foundation
- [x] Initialize clean repository and document the product direction.
- [x] Add Flutter web-first app shell with Arabic RTL branding.
- [x] Select Cloudflare Workers + D1 + R2 as the canonical backend/hosting target.
- [x] Add Worker API scaffold, D1 initial migration and R2 binding configuration.
- [ ] Create the D1 database and R2 bucket in the user's Cloudflare account.
- [ ] Run dependency installation, typecheck, local migration and Worker smoke tests.
- [ ] Configure Pages builds for Flutter Web and the separate admin frontend.

## Phase 1 — accounts
- [ ] Email registration, login, logout and secure session lifecycle.
- [ ] Google sign-in with verified server-side token exchange.
- [ ] Email OTP password recovery with expiry, resend throttling and attempt limits.
- [ ] Profile, country, avatar, GABO ID and privacy settings.
- [ ] Admin roles, audit log and account moderation.

## Phase 2 — social
- [ ] Posts, comments, reactions and follows.
- [ ] Communities, membership and public chat.
- [ ] Private conversations and notifications.
- [ ] Reporting, blocking and moderation workflows.

## Phase 3 — live audio
- [ ] Agora token service and room lifecycle.
- [ ] Host, moderator, speaker and listener permissions.
- [ ] Exclusive microphone seat state and reconnect handling.
- [ ] Room chat, participant presence and moderation events.

## Phase 4 — economy and memberships
- [ ] Gift catalogue and media pipeline.
- [ ] Server-authoritative wallet ledger and transaction history.
- [ ] Sender/receiver progression, VIP tiers and configurable benefits.
- [ ] Subscription lifecycle, refunds and reconciliation.

## Phase 5 — operations
- [ ] Separate admin dashboard for users, rooms, gifts, VIP, reports and settings.
- [ ] Monitoring, backups, rate limits and incident procedures.
- [ ] Accessibility, responsive QA, load testing and security review.
- [ ] Staging sign-off before any production traffic is moved.

No real payments, wallet balances, production credentials or user records are part of this initial scaffold.
