import { DurableObject } from "cloudflare:workers";

export class GlobalGiftHub extends DurableObject {
  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);
    if (url.pathname !== "/connect" || request.method !== "GET" ||
        request.headers.get("Upgrade")?.toLowerCase() !== "websocket") {
      return Response.json({ error: "not_found" }, { status: 404 });
    }

    const pair = new WebSocketPair();
    const client = pair[0];
    const server = pair[1];
    // Use the hibernation API so idle application-wide connections do not pin
    // this Durable Object in memory. Connected clients survive hibernation.
    this.ctx.acceptWebSocket(server);
    return new Response(null, {
      status: 101,
      webSocket: client,
      headers: { "Sec-WebSocket-Protocol": "happy-live-gifts" }
    });
  }

  // RPC method called by the Worker for each fan-out shard.
  async broadcast(payload: Record<string, unknown>): Promise<number> {
    const message = JSON.stringify(payload);
    let delivered = 0;
    for (const socket of this.ctx.getWebSockets()) {
      try {
        socket.send(message);
        delivered++;
      } catch {
        try { socket.close(1011, "delivery_failed"); } catch {}
      }
    }
    return delivered;
  }
}
