type JsonReply = (data: unknown, status?: number) => Response;
type AuthenticatedCallbackUser = { happy_id: string | null };

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
  authenticateUser: (request: Request, db: D1Database) => Promise<AuthenticatedCallbackUser | null>,
  reply: JsonReply
): Promise<Response | null> {
  const url = new URL(request.url);
  if (url.pathname !== "/v1/platform/handshake") return null;
  if (request.method !== "POST") return reply({ error: "method_not_allowed" }, 405);
  if (!db) return reply({ error: "database_unavailable" }, 503);

  if (!request.headers.has("Authorization")) {
    return reply({ error: "authentication_required" }, 401);
  }

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

  let account: AuthenticatedCallbackUser | null;
  try {
    account = await authenticateUser(request, db);
  } catch {
    return reply({ error: "callback_validation_unavailable" }, 503);
  }

  if (!account) {
    return reply({ error: "invalid_test_account_token" }, 401);
  }
  if (!account.happy_id || !constantTimeEqual(account.publicUid, uid)) {
    return reply({ error: "test_account_uid_mismatch" }, 403);
  }

  return reply({ ok: true, appId, apiVersion: "v1", uid, challenge }, 200);
}
