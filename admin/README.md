# Happy Live Admin

The standalone Arabic admin console is served from `/admin/` by Cloudflare Pages:
- Source: `frontend/web/admin/index.html`
- API: `https://happy-live-api.taher616270.workers.dev/api/v1/admin`
- Authentication: the existing account login endpoint, followed by server-side verification against D1 `admin_roles`.

## First owner setup

1. Create a normal Happy Live user account and sign in to the application once.
2. In Cloudflare D1, open database `happy-live-db` and run the following SQL, replacing the value with the exact user UUID from the `users` table:

```sql
INSERT INTO admin_roles (user_id, role, granted_by, granted_at)
VALUES ('YOUR_EXISTING_USER_UUID', 'owner', NULL, strftime('%Y-%m-%dT%H:%M:%fZ', 'now'));
```

3. Open `https://happy-live.pages.dev/admin/` and sign in using that account.

Do not expose the D1 database to the browser. Do not put an admin role in local storage or accept role claims from requests. Every admin endpoint verifies the bearer session and looks up the role in D1. The initial owner grant is deliberately a one-time database operator action; there is no public self-promotion endpoint.

## Implemented sections

- Overview: live counts for users, active users, rooms and published posts.
- Users: search, view account status and activate/suspend ordinary accounts.
- Rooms: view rooms and open/close them.
- Audit: read recent administrative actions.
- Remaining sections (VIP, wallet/recharge, gifts and admin assignment) are shown as unavailable until their underlying API/data model is implemented.

## Roles

- `owner`: full access, including management of other admin accounts (admin assignment is not exposed in this initial UI).
- `admin`: view and manage ordinary users and rooms; read audit history.
- `moderator`: read-only dashboard access; no audit access or write operations.

All sensitive status changes are recorded in `admin_audit_logs`.
