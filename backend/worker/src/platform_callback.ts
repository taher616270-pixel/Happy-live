type JsonReply = (data: unknown, status?: number) => Response;

function constantTimeEqual(left: string, right: string): boolean {
  if (left.length !== right.length) return false;
  let difference = 0;
  for (let index = 0; index < left.length; index++) {
    difference |= left.charCodeAt(index) ^ right.charCodeAt(index);
  }
  return difference === 0;
}

/**
 * Validates the onboarding callback used by the Happy Food Wheel owner portal.
 * The supplied test token must be a live Happy Live application login token.
 * Only its SHA-256 hash is queried; the raw token is never stored or logged.
 */
export async function handlePlatformCallbackRequest(
  request: Request,
  db: D1Database | undefined,
  reply: JsonReply
): Promise<Response | null> {
  const url = new URL(request.url);
  if (url.pathname !== "/v1/platform/handshake") return null;
  if (request.method !== "POST") return reply({ error: "method_not_allowed" }, 405);
  if (!db) return reply({ error: "database_unavailable" }, 503);

  const authorization = request.headers.get("Authorization") ?? "";
  const tokenMatch = authorization.match(/^Bearer\\s+([A-Za-z0-9._~-]{32,512})$/i);
  if (!tokenMatch) return reply({ error: "authentication_required" }, 401);

  if (!(request.headers.get("Content-Type") ?? "").toLowerCase().includes("application/json")) {
    return reply({ error: "application_json_required" }, 415);
  }

  let body: Record<string, unknown>;
  try {
    const parsed = await request.json();
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
      return reply({ error: "invalid_handshake_payload" }, 400);
    }
    body = parsed as Record<string, unknown>;
  } catch {
    return reply({ error: "invalid_handshake_payload" }, 400);
  }

  const platform = body.platform;
  const appId = body.appId;
  const apiVersion = body.apiVersion;
  const uid = body.uid;
  const challenge = body.challenge;

  if (platform !== "Happy Food Wheel" ||
      typeof appId !== "string" || !/^app_[A-Za-z0-9_-]{8,128}$/.test(appId) ||
      apiVersion !== "v1" ||
      typeof uid !== "string" || uid.length < 1 || uid.length > 80 ||
      typeof challenge !== "string" || challenge.length < 16 || challenge.length > 256) {
    return reply({ error: "invalid_handshake_payload" }, 400);
  }

  const token = tokenMatch[1];
  const tokenHash = Array.from(
    new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(token)))
  ).map((byte) => byte.toString(16).padStart(2, "0")).join("");
  const now = new Date().toISOString();

  let account: { status: string; publicUid: string | null } | null;
  try {
    account = await db.prepare(
      "SELECT u.status, COALESCE(NULLIF(p.happy_id, ''), NULLIF(p.gabo_id, '')) AS publicUid " +
      "FROM user_sessions s INNER JOIN users u ON u.id = s.user_id " +
      "LEFT JOIN profiles p ON p.user_id = u.id " +
      "WHERE s.token_hash = ? AND s.revoked_at IS NULL AND s.expires_at > ? LIMIT 1"
    ).bind(tokenHash, now).first<{ status: string; publicUid: string | null }>();
  } catch {
    return reply({ error: "callback_validation_unavailable" }, 503);
  }

  if (!account || account.status !== "active") {
    return reply({ error: "invalid_test_account_token" }, 401);
  }
  if (!account.publicUid || !constantTimeEqual(account.publicUid, uid)) {
    return reply({ error: "test_account_uid_mismatch" }, 403);
  }

  return reply({ ok: true, appId, apiVersion: "v1", uid, challenge }, 200);
}
