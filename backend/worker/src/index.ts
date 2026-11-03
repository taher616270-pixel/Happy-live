export interface Env {
  DB?: D1Database;
  APP_ENV?: string;
  ALLOWED_ORIGINS?: string;
  IMAGEKIT_PUBLIC_KEY?: string;
  IMAGEKIT_PRIVATE_KEY?: string;
}

const DEFAULT_ALLOWED_ORIGINS = [
  "http://localhost:3000",
  "http://localhost:5173",
  "http://localhost:8080",
  "http://127.0.0.1:3000",
  "http://127.0.0.1:5173",
  "http://127.0.0.1:8080",
  "https://happy-live.pages.dev"
];

function allowedOrigins(env: Env): Set<string> {
  const configured = (env.ALLOWED_ORIGINS ?? "")
    .split(",")
    .map((value) => value.trim())
    .filter(Boolean);
  return new Set([...DEFAULT_ALLOWED_ORIGINS, ...configured]);
}

function json(data: unknown, status = 200, origin?: string, env?: Env): Response {
  const headers = new Headers({
    "content-type": "application/json; charset=utf-8",
    "cache-control": "no-store",
    "x-content-type-options": "nosniff"
  });

  if (origin && env && allowedOrigins(env).has(origin)) {
    headers.set("access-control-allow-origin", origin);
    headers.set("vary", "Origin");
    headers.set("access-control-allow-credentials", "true");
    headers.set("access-control-allow-headers", "Content-Type, Authorization");
    headers.set("access-control-allow-methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS");
  }

  return new Response(JSON.stringify(data), { status, headers });
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    const origin = request.headers.get("Origin") ?? undefined;

    if (origin && !allowedOrigins(env).has(origin)) {
      return json({ error: "origin_not_allowed" }, 403);
    }

    if (request.method === "OPTIONS") {
      const headers = new Headers();
      if (origin) {
        headers.set("access-control-allow-origin", origin);
        headers.set("vary", "Origin");
        headers.set("access-control-allow-credentials", "true");
        headers.set("access-control-allow-headers", "Content-Type, Authorization");
        headers.set("access-control-allow-methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS");
      }
      return new Response(null, { status: 204, headers });
    }

    if (url.pathname === "/api/v1/health" && request.method === "GET") {
      let database = "not_configured";

      if (env.DB) {
        try {
          await env.DB.prepare("SELECT 1 AS ok").first();
          database = "connected";
        } catch {
          database = "unavailable";
        }
      }

      const healthy = database === "connected";
      return json({
        ok: healthy,
        service: "happy-live-api",
        environment: env.APP_ENV ?? "unknown",
        database
      }, healthy ? 200 : 503, origin, env);
    }

    if (url.pathname === "/api/v1/imagekit/auth" && request.method === "GET") {
      if (!env.DB || !env.IMAGEKIT_PUBLIC_KEY?.trim() || !env.IMAGEKIT_PRIVATE_KEY?.trim()) {
        return json({ error: "imagekit_not_configured" }, 503, origin, env);
      }

      // Require a live application session before issuing upload credentials.
      // Session tokens are stored only as SHA-256 hashes in D1.
      const authorization = request.headers.get("Authorization") ?? "";
      const bearerMatch = authorization.match(/^Bearer\\s+([A-Za-z0-9._~-]{32,512})$/i);
      if (!bearerMatch) {
        return json({ error: "authentication_required" }, 401, origin, env);
      }

      try {
        const tokenHashBytes = await crypto.subtle.digest(
          "SHA-256",
          new TextEncoder().encode(bearerMatch[1])
        );
        const tokenHash = Array.from(new Uint8Array(tokenHashBytes))
          .map((byte) => byte.toString(16).padStart(2, "0"))
          .join("");
        const session = await env.DB.prepare(
          "SELECT s.user_id FROM user_sessions s INNER JOIN users u ON u.id = s.user_id WHERE s.token_hash = ? AND s.revoked_at IS NULL AND s.expires_at > ? AND u.status = 'active' LIMIT 1"
        ).bind(tokenHash, new Date().toISOString()).first<{ user_id: string }>();

        if (!session) {
          return json({ error: "invalid_or_expired_session" }, 401, origin, env);
        }

        const ip = request.headers.get("CF-Connecting-IP") ?? "unknown";
        const now = Math.floor(Date.now() / 1000);
        const windowStart = now - 60;
        const rate = await env.DB.prepare(
          "INSERT INTO imagekit_auth_rate_limits (ip, window_start, request_count) VALUES (?, ?, 1) ON CONFLICT(ip) DO UPDATE SET window_start = CASE WHEN imagekit_auth_rate_limits.window_start <= ? THEN excluded.window_start ELSE imagekit_auth_rate_limits.window_start END, request_count = CASE WHEN imagekit_auth_rate_limits.window_start <= ? THEN 1 ELSE imagekit_auth_rate_limits.request_count + 1 END RETURNING request_count"
        ).bind(ip, now, windowStart, windowStart).first<{ request_count: number }>();

        if (!rate || rate.request_count > 8) {
          return json({ error: "rate_limit_exceeded", retry_after_seconds: 60 }, 429, origin, env);
        }

        const token = crypto.randomUUID();
        const expire = now + 300;
        const key = await crypto.subtle.importKey(
          "raw",
          new TextEncoder().encode(env.IMAGEKIT_PRIVATE_KEY),
          { name: "HMAC", hash: "SHA-1" },
          false,
          ["sign"]
        );
        const signatureBytes = await crypto.subtle.sign(
          "HMAC",
          key,
          new TextEncoder().encode(token + expire)
        );
        const signature = Array.from(new Uint8Array(signatureBytes))
          .map((byte) => byte.toString(16).padStart(2, "0"))
          .join("");

        return json({
          token,
          expire,
          signature,
          publicKey: env.IMAGEKIT_PUBLIC_KEY
        }, 200, origin, env);
      } catch {
        return json({ error: "imagekit_auth_unavailable" }, 503, origin, env);
      }
    }

    if (url.pathname === "/api/v1/imagekit/health" && request.method === "GET") {
      const publicKeyConfigured = Boolean(env.IMAGEKIT_PUBLIC_KEY?.trim());
      const privateKey = env.IMAGEKIT_PRIVATE_KEY?.trim() ?? "";
      let signing = "not_configured";

      if (privateKey) {
        try {
          const key = await crypto.subtle.importKey(
            "raw",
            new TextEncoder().encode(privateKey),
            { name: "HMAC", hash: "SHA-1" },
            false,
            ["sign"]
          );
          await crypto.subtle.sign(
            "HMAC",
            key,
            new TextEncoder().encode("happy-live-imagekit-configuration-check")
          );
          signing = "ready";
        } catch {
          signing = "error";
        }
      }

      const ok = publicKeyConfigured && signing === "ready";
      return json({
        ok,
        service: "imagekit",
        public_key: publicKeyConfigured ? "configured" : "missing",
        private_key: privateKey ? "configured" : "missing",
        signing
      }, ok ? 200 : 503, origin, env);
    }

    if (url.pathname === "/api/v1" && request.method === "GET") {
      return json({
        name: "Happy Live API",
        version: "v1",
        status: "scaffold",
        endpoints: ["/api/v1/health", "/api/v1/imagekit/health", "/api/v1/imagekit/auth"]
      }, 200, origin, env);
    }

    return json({ error: "not_found" }, 404, origin, env);
  }
};
