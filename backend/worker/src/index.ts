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
        endpoints: ["/api/v1/health", "/api/v1/imagekit/health"]
      }, 200, origin, env);
    }

    return json({ error: "not_found" }, 404, origin, env);
  }
};
