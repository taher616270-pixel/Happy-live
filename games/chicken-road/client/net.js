// Production-only Happy Live integration: authenticated session + canonical wallet.
(function () {
  const cfg = window.CR_CLIENT || {};
  const H = {};
  const API = 'https://happy-live-api.taher616270.workers.dev/api/v1/game';
  const MAX_CONNECT_ATTEMPTS = 3;
  const CONNECT_RETRY_DELAY_MS = 1500;
  const READY_TIMEOUT_MS = 10000;
  const Net = {
    me: null, player: null, connected: false,
    on(t, f) { (H[t] = H[t] || []).push(f); },
    fire(t, d) { (H[t] || []).forEach((f) => f(d)); },
    send() { return false; }
  };

  let sessionToken = '', expiresAt = 0, socket = null;
  let refreshTimer = 0, reconnectTimer = 0, readyTimer = 0;
  let stopped = false, refreshPromise = null, connectStarted = false;
  let connectAttempts = 0;

  function setConnectionUi(ready) {
    const balance = document.getElementById('bal');
    const play = document.getElementById('go');
    const top = document.getElementById('bTop');
    const history = document.getElementById('bLog');
    if (!ready && balance) balance.textContent = '—';
    if (play) play.disabled = !ready;
    if (top) top.disabled = !ready;
    if (history) history.disabled = !ready;
  }

  function showFatal(message) {
    stopped = true;
    Net.connected = false;
    clearTimeout(refreshTimer);
    clearTimeout(reconnectTimer);
    clearTimeout(readyTimer);
    setConnectionUi(false);
    if (socket && socket.readyState < WebSocket.CLOSING) {
      try { socket.close(4002, 'connection_failed'); } catch (_) {}
    }
    const toast = document.getElementById('toast');
    if (toast) {
      toast.textContent = message;
      toast.className = 'bad';
      toast.hidden = false;
    }
    Net.fire('connection-failed', { message });
  }

  function failSession() {
    showFatal('انتهت جلسة Happy Live أو لم تعد صالحة. أغلق اللعبة وافتحها مجدداً.');
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
      if (!response.ok || typeof data.expiresAt !== 'string') {
        throw new Error(data.error || 'game_session_refresh_failed');
      }
      const nextExpiry = Date.parse(data.expiresAt);
      if (!Number.isFinite(nextExpiry) || nextExpiry <= Date.now()) {
        throw new Error('invalid_game_session_expiry');
      }
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

  function connectionFailed() {
    showFatal('تعذر الاتصال بخادم Chicken Road بعد 3 محاولات. تحقق من اتصالك ثم أغلق اللعبة وافتحها مجدداً.');
  }

  function connectSocket() {
    if (stopped) return;
    if (!sessionToken || !expiresAt || Date.now() >= expiresAt) return failSession();
    if (typeof cfg.WS_URL !== 'string' || !cfg.WS_URL.startsWith('wss://')) {
      return showFatal('رابط اتصال اللعبة غير صالح. حدّث التطبيق ثم حاول مجدداً.');
    }
    if (connectAttempts >= MAX_CONNECT_ATTEMPTS) return connectionFailed();

    clearTimeout(reconnectTimer);
    clearTimeout(readyTimer);
    connectAttempts += 1;

    let ws;
    try {
      ws = new WebSocket(cfg.WS_URL, ['happy-live-game', 'session.' + sessionToken]);
    } catch (_) {
      if (connectAttempts >= MAX_CONNECT_ATTEMPTS) return connectionFailed();
      reconnectTimer = setTimeout(connectSocket, CONNECT_RETRY_DELAY_MS);
      return;
    }
    socket = ws;

    ws.onopen = () => {
      if (socket !== ws || stopped) return;
      readyTimer = setTimeout(() => {
        if (socket === ws && !Net.connected && ws.readyState < WebSocket.CLOSING) {
          try { ws.close(4000, 'init_timeout'); } catch (_) {}
        }
      }, READY_TIMEOUT_MS);
    };

    ws.onmessage = (event) => {
      if (socket !== ws || stopped) return;
      let message;
      try { message = JSON.parse(event.data); } catch (_) { return; }

      if (message.t === 'init') {
        const data = message.data || {};
        const balance = Number(data.balance);
        if (!Number.isFinite(balance) || balance < 0) {
          return showFatal('اتصلت اللعبة بالخادم، لكن تعذرت قراءة رصيد محفظة Happy Live. لم يتم عرض رصيد افتراضي.');
        }
        clearTimeout(readyTimer);
        Net.me = data.userCode || data.playerId || '';
        Net.player = data.player || null;
        Net.connected = true;
        connectAttempts = 0;
        setConnectionUi(true);
      }
      Net.fire(message.t, message.data);
    };

    ws.onerror = () => {
      if (socket === ws) {
        Net.connected = false;
        setConnectionUi(false);
        Net.fire('offline');
      }
    };

    ws.onclose = (event) => {
      if (socket !== ws || stopped) return;
      Net.connected = false;
      setConnectionUi(false);
      clearTimeout(readyTimer);

      if (event.code === 4001 || Date.now() >= expiresAt) return failSession();
      if (event.code === 4002) {
        return showFatal('تعذر التحقق من محفظة Happy Live أو بيانات اللاعب. أعد فتح اللعبة، وإذا استمرت المشكلة تواصل مع الدعم.');
      }

      Net.fire('offline', { code: event.code, reason: event.reason || '' });
      if (connectAttempts >= MAX_CONNECT_ATTEMPTS) return connectionFailed();
      reconnectTimer = setTimeout(connectSocket, CONNECT_RETRY_DELAY_MS);
    };

    Net.send = (message) => {
      if (!Net.connected || ws.readyState !== WebSocket.OPEN || stopped) return false;
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
    window.parent.postMessage(
      { type: 'happy-live-game-session-received' },
      window.location.origin
    );
    expiresAt = Date.now() + 14 * 60 * 1000;
    window.removeEventListener('message', receiveSession);
    scheduleRefresh();
    connectSocket();
  }

  Net.connect = () => {
    if (connectStarted) return;
    connectStarted = true;
    setConnectionUi(false);
    const balance = document.getElementById('bal');
    if (balance) balance.textContent = '—';
    window.addEventListener('message', receiveSession);
    setTimeout(() => {
      if (!sessionToken && !stopped) {
        showFatal('لم تصل جلسة تسجيل الدخول من Happy Live. أغلق اللعبة وافتحها مجدداً من داخل الغرفة.');
      }
    }, 12000);
  };

  window.CR_Net = Net;
})();
