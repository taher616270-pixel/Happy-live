export class GlobalGiftHub {
  private readonly sockets = new Set<WebSocket>();

  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);

    if (url.pathname === "/connect" && request.method === "GET") {
      if (request.headers.get("Upgrade")?.toLowerCase() !== "websocket") {
        return Response.json({ error: "websocket_upgrade_required" }, { status: 426 });
      }
      const pair = new WebSocketPair();
      const client = pair[0];
      const server = pair[1];
      server.accept();
      this.sockets.add(server);
      server.addEventListener("close", () => this.sockets.delete(server));
      server.addEventListener("error", () => this.sockets.delete(server));
      server.send(JSON.stringify({ type: "global_gift_ready" }));
      return new Response(null, {
        status: 101,
        webSocket: client,
        headers: { "Sec-WebSocket-Protocol": "happy-live-gifts" }
      });
    }

    if (url.pathname === "/broadcast" && request.method === "POST") {
      let payload: Record<string, unknown>;
      try { payload = await request.json() as Record<string, unknown>; }
      catch { return Response.json({ error: "invalid_json" }, { status: 400 }); }
      const message = JSON.stringify(payload);
      let delivered = 0;
      for (const socket of this.sockets) {
        try {
          socket.send(message);
          delivered++;
        } catch {
          this.sockets.delete(socket);
          try { socket.close(1011, "delivery_failed"); } catch {}
        }
      }
      return Response.json({ ok: true, delivered });
    }

    return Response.json({ error: "not_found" }, { status: 404 });
  }
}
