# Happy Live Unified Game API

Every game registered in the Happy Live admin catalogue uses the same API gateway.

## 1. Start a game session from Happy Live

The Happy Live app calls this endpoint with the user's normal application access token:

- `POST /api/v1/game/auth`
- Header: `Authorization: Bearer <application-access-token>`
- JSON body: `{ "gameId": "<Game ID>" }`

The Worker verifies the signed-in user session and checks that the requested game exists, is enabled, has lifecycle status `active`, and has a valid HTTPS URL. It then issues a cryptographically random game token that expires after 15 minutes.

The token is stored only as a SHA-256 hash in D1. The raw token is returned once to the app and delivered to the game through an origin-locked `postMessage`; it is never placed in the game URL, query string, fragment, or referrer.

## 2. Receive the token in the game page

Install this listener before the game starts making API requests. The app sends the token from the Happy Live production origin:

```js
const HAPPY_LIVE_APP_ORIGIN = "https://happy-live.pages.dev";
let gameSessionToken = null;

function receiveHappyLiveSession(event) {
  if (event.origin !== HAPPY_LIVE_APP_ORIGIN) return;
  if (event.source !== window.opener) return;
  if (event.data?.type !== "happy-live-game-session") return;
  if (typeof event.data.sessionToken !== "string") return;

  gameSessionToken = event.data.sessionToken;
  window.removeEventListener("message", receiveHappyLiveSession);
  window.opener = null;
}

window.addEventListener("message", receiveHappyLiveSession);
```

The app retries delivery briefly while the game loads. The game must accept the first valid message only.

## 3. Call the unified API

Base path: `https://happy-live-api.taher616270.workers.dev/api/v1/game`

All game API requests use the temporary token:

```js
async function gameApi(path) {
  if (!gameSessionToken) throw new Error("game_session_required");
  const response = await fetch(
    "https://happy-live-api.taher616270.workers.dev/api/v1/game/" + path,
    { headers: { Authorization: "Bearer " + gameSessionToken } }
  );
  const data = await response.json();
  if (!response.ok) throw new Error(data.error || "game_api_failed");
  return data;
}

const session = await gameApi("session");
const profile = await gameApi("profile");
const wallet = await gameApi("wallet");
```

## 4. Available endpoints and permissions

| Endpoint | Method | Permission | Purpose |
| --- | --- | --- | --- |
| `/game/auth` | POST | App login required | Exchange app login for a game token |
| `/game/session` | GET | `session.read` | Check game session and expiry |
| `/game/profile` | GET | `profile.read` | Read public player profile |
| `/game/wallet` | GET | `wallet.read` | Read the canonical coin balance |
| `/game/session/revoke` | POST | Valid game token | Revoke the current game session |

The current game-token scopes are read-only: `session.read`, `profile.read`, and `wallet.read`. A game cannot debit, credit, transfer, or otherwise mutate a wallet through this token. Wallet-changing operations must be implemented and validated server-side per game, with idempotency and server-authoritative settlement.

## 5. Security rules

- Tokens are bound to one game, one authenticated player, and the exact HTTPS origin registered for that game.
- Tokens expire after 15 minutes and can be revoked.
- Each game token is bound to the exact Happy Live app login session that issued it; logging out or revoking that app session immediately invalidates the game token.
- Requests are limited to 120 per game session per minute.
- Deactivating a game, disabling its registry entry, disabling a player, or changing the game's origin invalidates its active game sessions.
- The Worker stores only token hashes; never log or persist raw tokens in game storage.
- Do not pass the normal Happy Live application token to an external game.
