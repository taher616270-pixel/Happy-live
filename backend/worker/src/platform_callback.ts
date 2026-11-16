type JsonReply = (data: unknown, status?: number) => Response;

function constantTimeEqual(left: string, right: string): boolean {
  if (left.length !== right.length) return false;
  let difference = 0;
  for (let index = 0; index < left.length; index++) {
    difference |= left.charCodeAt(index) ^ right.charCodeAt(index);
  }
  return difference === 0;
}

async function sha256(value: string): Promise<string> {
  return Array.from(
    new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value)))
  ).map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

/**
 * Server-to-server onboarding handshake for Happy Food Wheel.
 * The credential is issued by Happy Live, stored only as a SHA-256 hash,
 * and shown to the owner only once by the authenticated admin endpoint.
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
  const tokenMatch = authorization.match(/^Bearer\s+(\S{24,4096})$/i);
  if (!tokenMatch) return reply({ error: "authentication_required" }, 401);
  const apiToken = tokenMatch[1];
  if (/\s/.test(apiToken)) return reply({ error: "authentication_required" }, 401);

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

  const appId = body.appId;
  const challenge = body.challenge;
  if (body.platform !== "Happy Food Wheel" ||
      typeof appId !== "string" || !/^app_[A-Za-z0-9_-]{8,128}$/.test(appId) ||
      body.apiVersion !== "v1" ||
      typeof challenge !== "string" || challenge.length < 16 || challenge.length > 256) {
    return reply({ error: "invalid_handshake_payload" }, 400);
  }

  try {
    const [savedAppId, savedTokenHash] = await Promise.all([
      db.prepare("SELECT setting_value FROM platform_settings WHERE setting_key = 'happy_food_wheel_app_id' LIMIT 1")
        .first<{ setting_value: string }>(),
      db.prepare("SELECT setting_value FROM platform_settings WHERE setting_key = 'happy_food_wheel_token_hash' LIMIT 1")
        .first<{ setting_value: string }>()
    ]);
    if (!savedTokenHash?.setting_value) {
      return reply({ error: "integration_not_configured" }, 503);
    }
    if (!constantTimeEqual(await sha256(apiToken), savedTokenHash.setting_value)) {
      return reply({ error: "invalid_application_token" }, 401);
    }

    // If the platform App ID is not known yet, bind it to the first valid
    // handshake authenticated with the owner-issued token. Later handshakes
    // must present the same App ID.
    if (savedAppId?.setting_value) {
      if (!constantTimeEqual(appId, savedAppId.setting_value)) {
        return reply({ error: "app_id_mismatch" }, 403);
      }
    } else {
      const now = new Date().toISOString();
      await db.prepare(
        "INSERT INTO platform_settings (setting_key, setting_value, updated_at) VALUES ('happy_food_wheel_app_id', ?, ?) ON CONFLICT(setting_key) DO NOTHING"
      ).bind(appId, now).run();
      const boundAppId = await db.prepare(
        "SELECT setting_value FROM platform_settings WHERE setting_key = 'happy_food_wheel_app_id' LIMIT 1"
      ).first<{ setting_value: string }>();
      if (!boundAppId?.setting_value || !constantTimeEqual(appId, boundAppId.setting_value)) {
        return reply({ error: "app_id_mismatch" }, 403);
      }
    }
    return reply({ ok: true, appId, apiVersion: "v1", challenge }, 200);
  } catch {
    return reply({ error: "callback_validation_unavailable" }, 503);
  }
}
