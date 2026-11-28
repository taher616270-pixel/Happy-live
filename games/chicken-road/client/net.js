// اتصال إنتاجي فقط: جلسة Happy Live المؤقتة + WebSocket خاص بالمستخدم.
(function () {
  const cfg = window.CR_CLIENT, H = {};
  const API = 'https://happy-live-api.taher616270.workers.dev/api/v1/game';
  const Net = {
    me: null, player: null, connected: false,
    on(t, f) { (H[t] = H[t] || []).push(f); },
    fire(t, d) { (H[t] || []).forEach((f) => f(d)); },
    send() { return false; }
  };
  let sessionToken = '', expiresAt = 0, socket = null, refreshTimer = 0, reconnectTimer = 0;
  let stopped = false, refreshPromise = null, connectStarted = false;

  function failSession() {
    stopped = true;
    clearTimeout(refreshTimer);
    clearTimeout(reconnectTimer);
    if (socket && socket.readyState < WebSocket.CLOSING) socket.close(4001, 'session_expired');
    Net.connected = false;
    Net.fire('unauthorized', { message: 'انتهت جلسة Happy Live، أعد فتح اللعبة' });
  }

  async function refreshSession() {
    if (refreshPromise) return refreshPromise;
    refreshPromise = (async () => {
      const response = await fetch(API + '/session/refresh', {
        method: 'POST',
        headers: { Authorization: 'Bearer ' + sessionToken }
      });
      const data = await response.json().catch(() => ({}));
      if (!response.ok || typeof data.expiresAt !== 'string') throw new Error(data.error || 'game_session_refresh_failed');
      const nextExpiry = Date.parse(data.expiresAt);
      if (!Number.isFinite(nextExpiry) || nextExpiry <= Date.now()) throw new Error('invalid_game_session_expiry');
      expiresAt = nextExpiry;
      scheduleRefresh();
    })();
    try { await refreshPromise; } finally { refreshPromise = null; }
  }

  function scheduleRefresh() {
    clearTimeout(refreshTimer);
    if (!expiresAt || stopped) return;
    refreshTimer = setTimeout(async () => {
      try { await refreshSession(); }
      catch (_) { failSession(); }
    }, Math.max(1000, expiresAt - Date.now() - 60000));
  }

  function connectSocket() {
    if (stopped || !sessionToken || Date.now() >= expiresAt) return failSession();
    clearTimeout(reconnectTimer);
    const ws = new WebSocket(cfg.WS_URL + '?token=' + encodeURIComponent(sessionToken));
    socket = ws;
    ws.onopen = () => { if (socket === ws) Net.connected = true; };
    ws.onmessage = (event) => {
      let message;
      try { message = JSON.parse(event.data); } catch (_) { return; }
      if (message.t === 'init') {
        Net.me = message.data?.userCode || '';
        Net.player = message.data?.player || null;
      }
      Net.fire(message.t, message.data);
    };
    ws.onerror = () => Net.fire('offline');
    ws.onclose = (event) => {
      if (socket === ws) Net.connected = false;
      if (stopped) return;
      if (event.code === 4001 || Date.now() >= expiresAt) return failSession();
      Net.fire('offline');
      reconnectTimer = setTimeout(connectSocket, 1500);
    };
    Net.send = (message) => {
      if (ws.readyState !== WebSocket.OPEN || stopped) return false;
      ws.send(JSON.stringify(message));
      return true;
    };
  }

  function receiveSession(event) {
    if (event.origin !== window.location.origin || event.source !== window.parent) return;
    const data = event.data;
    if (!data || data.type !== 'happy-live-game-session' ||
        typeof data.sessionToken !== 'string' || data.sessionToken.length < 32 ||
        data.sessionToken.length > 512 || sessionToken) return;
    sessionToken = data.sessionToken;
    window.CR_SESSION_TOKEN = sessionToken;
    expiresAt = Date.now() + 14 * 60 * 1000;
    window.removeEventListener('message', receiveSession);
    scheduleRefresh();
    connectSocket();
  }

  Net.connect = () => {
    if (connectStarted) return;
    connectStarted = true;
    window.addEventListener('message', receiveSession);
    setTimeout(() => {
      if (!sessionToken && !stopped) {
        stopped = true;
        Net.fire('unauthorized', { message: 'تعذر استلام جلسة Happy Live. أغلق اللعبة وافتحها مجدداً.' });
      }
    }, 12000);
  };
  window.CR_Net = Net;
})();