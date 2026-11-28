// Production-only Happy Live integration with explicit API/session/WS diagnostics.
(function () {
  const cfg = window.CR_CLIENT || {};
  const H = {};
  const API_BASE = 'https://happy-live-api.taher616270.workers.dev/api/v1/game';
  const HEALTH_URL = API_BASE + '/chicken-road/health';
  const SESSION_URL = API_BASE + '/session';
  const PROFILE_URL = API_BASE + '/profile';
  const WALLET_URL = API_BASE + '/wallet';
  const MAX_CONNECT_ATTEMPTS = 3;
  const CONNECT_RETRY_DELAY_MS = 1500;
  const READY_TIMEOUT_MS = 10000;
  const REQUEST_TIMEOUT_MS = 10000;
  const Net = {
    me: null, player: null, connected: false,
    on(t, f) { (H[t] = H[t] || []).push(f); },
    fire(t, d) { (H[t] || []).forEach((f) => f(d)); },
    send() { return false; }
  };

  let sessionToken = '', expiresAt = 0, socket = null;
  let walletSnapshot = null;
  let refreshTimer = 0, reconnectTimer = 0, readyTimer = 0;
  let stopped = false, refreshPromise = null, connectStarted = false;
  let connectAttempts = 0;

  function log(level, event, details) {
    const payload = Object.assign({
      event, api: API_BASE, websocket: cfg.WS_URL || '(missing)',
      origin: window.location.origin
    }, details || {});
    (console[level] || console.log).call(console, '[ChickenRoad]', payload);
  }

  function setConnectionUi(ready) {
    ['bal', 'go', 'bTop', 'bLog', 'bSync', 'clear'].forEach((id) => {
      const element = document.getElementById(id);
      if (element && 'disabled' in element) element.disabled = !ready;
    });
    ['chips', 'diffs'].forEach((id) => {
      const element = document.getElementById(id);
      if (element) Array.from(element.querySelectorAll('button')).forEach((button) => { button.disabled = !ready; });
    });
    const view = document.getElementById('view');
    if (view) view.style.pointerEvents = ready ? 'auto' : 'none';
    const balance = document.getElementById('bal');
    if (!ready && balance) balance.textContent = '---';
    const toast = document.getElementById('toast');
    if (!ready && toast) {
      toast.textContent = 'الخادم غير متصل';
      toast.className = 'bad';
      toast.hidden = false;
    }
  }

  function showFatal(message, code, details) {
    stopped = true;
    Net.connected = false;
    clearTimeout(refreshTimer);
    clearTimeout(reconnectTimer);
    clearTimeout(readyTimer);
    setConnectionUi(false);
    log('error', 'connection_stopped', Object.assign({ code: code || 'unknown', attempts: connectAttempts, message }, details || {}));
    if (socket && socket.readyState < WebSocket.CLOSING) {
      try { socket.close(4002, 'connection_failed'); } catch (_) {}
    }
    const toast = document.getElementById('toast');
    if (toast) {
      toast.textContent = message;
      toast.className = 'bad';
      toast.hidden = false;
    }
    Net.fire('connection-failed', { message, code });
  }

  function failSession(code, details) {
    showFatal('تعذر التحقق من جلسة Happy Live. أغلق اللعبة وافتحها مجدداً من داخل الغرفة.', code || 'SESSION_INVALID', details);
    Net.fire('unauthorized', { message: 'جلسة Happy Live غير صالحة' });
  }

  async function requestJson(url, options, label) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);
    try {
      const response = await fetch(url, Object.assign({}, options || {}, {
        cache: 'no-store', signal: controller.signal
      }));
      const raw = await response.text();
      let data = {};
      try { data = raw ? JSON.parse(raw) : {}; } catch (_) {}
      log(response.ok ? 'info' : 'error', 'http_response', {
        request: label, status: response.status, statusText: response.statusText,
        error: data.error || null, response: raw.slice(0, 500)
      });
      return { response, data };
    } catch (error) {
      const name = error && error.name ? error.name : 'NetworkError';
      const message = error && error.message ? error.message : String(error);
      const code = name === 'AbortError' ? 'TIMEOUT' : 'CORS_OR_NETWORK';
      log('error', 'http_request_failed', { request: label, code, errorName: name, message });
      throw Object.assign(new Error(message), { diagnosticCode: code });
    } finally {
      clearTimeout(timer);
    }
  }

  async function verifyServerAndSession() {
    const health = await requestJson(HEALTH_URL, { method: 'GET' }, 'health');
    if (!health.response.ok || health.data.ok !== true) {
      throw Object.assign(new Error(health.data.error || 'chicken_road_worker_unavailable'), {
        diagnosticCode: health.data.error || 'HEALTH_HTTP_' + health.response.status,
        details: health.data
      });
    }
    // Health is a Worker liveness endpoint, not a wallet/readiness gate.
    // Dependency readiness is established by the authenticated WebSocket init;
    // keep play controls locked until that init includes a real wallet balance.
    if (health.data.api !== 'ready') {
      throw Object.assign(new Error('chicken_road_api_not_ready'), {
        diagnosticCode: 'API_NOT_READY', details: health.data
      });
    }
    if (health.data.status === 'degraded') {
      log('warn', 'health_degraded_but_api_alive', {
        database: health.data.database,
        durableObject: health.data.durableObject,
        gameStatus: health.data.gameStatus,
        originMatches: health.data.originMatches,
        issues: health.data.issues || []
      });
    }
    if (!sessionToken || sessionToken.length < 32 || sessionToken.length > 512) {
      throw Object.assign(new Error('missing_or_invalid_game_session_token'), { diagnosticCode: 'TOKEN_MISSING' });
    }
    log('info', 'session_token_received', { present: true, length: sessionToken.length });
    const session = await requestJson(SESSION_URL, {
      method: 'GET', headers: { Authorization: 'Bearer ' + sessionToken }
    }, 'session');
    if (!session.response.ok || session.data.ok !== true) {
      const status = session.response.status;
      const code = session.data.error || 'SESSION_HTTP_' + status;
      throw Object.assign(new Error(code), { diagnosticCode: code, details: { status, response: session.data } });
    }
    if (!session.data.game || session.data.game.id !== 'f21d2c7a-8f1b-4d72-9a63-5c8f7e1d4b90') {
      throw Object.assign(new Error('wrong_game_session'), { diagnosticCode: 'GAME_SESSION_MISMATCH' });
    }
    log('info', 'session_verified', { gameId: session.data.game.id, expiresAt: session.data.expiresAt });

    const authHeaders = { Authorization: 'Bearer ' + sessionToken };
    const [profile, wallet] = await Promise.all([
      requestJson(PROFILE_URL, { method: 'GET', headers: authHeaders }, 'profile'),
      requestJson(WALLET_URL, { method: 'GET', headers: authHeaders }, 'wallet')
    ]);
    if (!profile.response.ok || profile.data.ok !== true || !profile.data.player) {
      const status = profile.response.status;
      const code = profile.data.error || 'PROFILE_HTTP_' + status;
      throw Object.assign(new Error(code), {
        diagnosticCode: code,
        details: { request: 'profile', status, statusText: profile.response.statusText, response: profile.data }
      });
    }
    const player = profile.data.player;
    const userCode = String(player.userCode || player.id || '').trim();
    if (!userCode || player.accountStatus !== 'active') {
      throw Object.assign(new Error('profile_identity_invalid'), {
        diagnosticCode: 'PROFILE_INVALID',
        details: { userCodePresent: Boolean(userCode), accountStatus: player.accountStatus, player }
      });
    }
    if (!wallet.response.ok || wallet.data.ok !== true) {
      const status = wallet.response.status;
      const code = wallet.data.error || 'WALLET_HTTP_' + status;
      throw Object.assign(new Error(code), {
        diagnosticCode: code,
        details: { request: 'wallet', status, statusText: wallet.response.statusText, response: wallet.data }
      });
    }
    const balance = wallet.data.balance;
    if (typeof balance !== 'number' || !Number.isSafeInteger(balance) || balance < 0 || wallet.data.currency !== 'coins') {
      throw Object.assign(new Error('wallet_response_invalid'), {
        diagnosticCode: 'WALLET_RESPONSE_INVALID',
        details: { request: 'wallet', status: wallet.response.status, response: wallet.data }
      });
    }
    walletSnapshot = { balance, player };
    log('info', 'unified_wallet_loaded', {
      endpoint: WALLET_URL, balanceReceived: true, balance,
      currency: wallet.data.currency, happyId: userCode
    });
  }

  async function refreshSession() {
    if (refreshPromise) return refreshPromise;
    refreshPromise = (async () => {
      const result = await requestJson(API_BASE + '/session/refresh', {
        method: 'POST', headers: { Authorization: 'Bearer ' + sessionToken }
      }, 'session_refresh');
      if (!result.response.ok || typeof result.data.expiresAt !== 'string') {
        throw new Error(result.data.error || 'game_session_refresh_failed');
      }
      const nextExpiry = Date.parse(result.data.expiresAt);
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
      catch (error) { failSession('SESSION_REFRESH_FAILED', { error: String(error) }); }
    }, Math.max(1000, expiresAt - Date.now() - 60000));
  }

  function connectionFailed(code, details) {
    showFatal('الخادم غير متصل. تعذر إنشاء اتصال آمن مع Chicken Road؛ لا يمكن اللعب أو المراهنة حالياً.', code || 'WEBSOCKET_FAILED', details);
  }

  async function connectSocket() {
    if (stopped) return;
    if (!sessionToken || !expiresAt || Date.now() >= expiresAt) return failSession('TOKEN_EXPIRED');
    if (typeof cfg.WS_URL !== 'string' || !cfg.WS_URL.startsWith('wss://')) {
      return showFatal('رابط اتصال Chicken Road غير صالح. لا يمكن بدء اللعب.', 'INVALID_WEBSOCKET_URL');
    }
    if (connectAttempts >= MAX_CONNECT_ATTEMPTS) return connectionFailed('RETRY_LIMIT');
    clearTimeout(reconnectTimer);
    clearTimeout(readyTimer);
    connectAttempts += 1;
    log('info', 'websocket_connecting', { attempt: connectAttempts, maxAttempts: MAX_CONNECT_ATTEMPTS, tokenPresent: true, tokenLength: sessionToken.length });
    let ws;
    try {
      ws = new WebSocket(cfg.WS_URL, ['happy-live-game', 'session.' + sessionToken]);
    } catch (error) {
      log('error', 'websocket_constructor_failed', { attempt: connectAttempts, error: String(error) });
      if (connectAttempts >= MAX_CONNECT_ATTEMPTS) return connectionFailed('WEBSOCKET_CONSTRUCTOR');
      reconnectTimer = setTimeout(connectSocket, 1500);
      return;
    }
    socket = ws;
    ws.onopen = () => {
      if (socket !== ws || stopped) return;
      log('info', 'websocket_open', { attempt: connectAttempts, protocol: ws.protocol });
      readyTimer = setTimeout(() => {
        if (socket === ws && !Net.connected && ws.readyState < WebSocket.CLOSING) {
          log('error', 'websocket_init_timeout', { attempt: connectAttempts });
          try { ws.close(4000, 'init_timeout'); } catch (_) {}
        }
      }, READY_TIMEOUT_MS);
    };
    ws.onmessage = (event) => {
      if (socket !== ws || stopped) return;
      let message;
      try { message = JSON.parse(event.data); }
      catch (error) { log('error', 'invalid_websocket_message', { error: String(error) }); return; }
      if (message.t === 'init_error') {
        const details = message.data || {};
        log('error', 'websocket_init_error', { details, fullMessage: message });
        return showFatal('اتصلت اللعبة بالخادم، لكن تعذر تهيئة حالة اللعبة. لا يمكن بدء اللعب.', details.code || 'GAME_INIT_FAILED', details);
      }
      if (message.t === 'init') {
        const data = message.data || {};
        if (!walletSnapshot) {
          return showFatal('لم يتم تحميل محفظة Happy Live الرئيسية. لم يتم السماح باللعب.', 'WALLET_NOT_LOADED');
        }
        data.balance = walletSnapshot.balance;
        data.player = walletSnapshot.player;
        data.userCode = walletSnapshot.player.userCode || walletSnapshot.player.id;
        const balance = Number(data.balance);
        if (!Number.isSafeInteger(balance) || balance < 0 || !data.userCode) {
          return showFatal('تعذر تحميل رصيد محفظة Happy Live أو بيانات الحساب. لم يتم السماح باللعب.', 'INVALID_WALLET_INIT', { walletSnapshot });
        }
        clearTimeout(readyTimer);
        Net.me = data.userCode;
        Net.player = data.player || null;
        Net.connected = true;
        connectAttempts = 0;
        setConnectionUi(true);
        log('info', 'game_ready', { happyId: data.userCode, walletBalanceReceived: true });
      }
      Net.fire(message.t, message.data);
    };
    ws.onerror = (event) => {
      if (socket === ws) {
        Net.connected = false;
        setConnectionUi(false);
        log('error', 'websocket_error', { attempt: connectAttempts, readyState: ws.readyState, eventType: event && event.type });
        Net.fire('offline');
      }
    };
    ws.onclose = (event) => {
      if (socket !== ws || stopped) return;
      Net.connected = false;
      setConnectionUi(false);
      clearTimeout(readyTimer);
      log('error', 'websocket_closed', { attempt: connectAttempts, code: event.code, reason: event.reason || '', wasClean: event.wasClean });
      if (event.code === 4001 || Date.now() >= expiresAt) return failSession('WS_UNAUTHORIZED', { closeCode: event.code, reason: event.reason });
      if (event.code === 4002) return connectionFailed('WS_SERVER_REJECTED', { closeCode: event.code, reason: event.reason });
      Net.fire('offline', { code: event.code, reason: event.reason || '' });
      if (connectAttempts >= MAX_CONNECT_ATTEMPTS) return connectionFailed(event.code === 1006 ? 'WS_HANDSHAKE_OR_SERVER_FAILURE' : 'WS_RETRY_LIMIT', { closeCode: event.code, reason: event.reason });
      reconnectTimer = setTimeout(connectSocket, CONNECT_RETRY_DELAY_MS);
    };
    Net.send = (message) => {
      if (!Net.connected || ws.readyState !== WebSocket.OPEN || stopped) {
        log('warn', 'game_action_blocked', { action: message && message.t || 'unknown', connected: Net.connected });
        return false;
      }
      ws.send(JSON.stringify(message));
      return true;
    };
  }

  function receiveSession(event) {
    if (event.source !== window.parent || event.origin !== window.location.origin) {
      log('warn', 'session_message_rejected', { sourceIsParent: event.source === window.parent, messageOrigin: event.origin });
      return;
    }
    const data = event.data;
    if (!data || data.type !== 'happy-live-game-session') return;
    if (typeof data.sessionToken !== 'string' || data.sessionToken.length < 32 || data.sessionToken.length > 512) {
      log('error', 'session_token_invalid', { present: Boolean(data.sessionToken), type: typeof data.sessionToken, length: typeof data.sessionToken === 'string' ? data.sessionToken.length : 0 });
      return;
    }
    if (sessionToken) return;
    sessionToken = data.sessionToken;
    window.CR_SESSION_TOKEN = sessionToken;
    log('info', 'session_token_received_from_parent', { present: true, length: sessionToken.length, origin: event.origin });
    window.parent.postMessage({ type: 'happy-live-game-session-received' }, window.location.origin);
    window.removeEventListener('message', receiveSession);
    expiresAt = Date.now() + 14 * 60 * 1000;
    scheduleRefresh();
    verifyServerAndSession().then(connectSocket).catch((error) => {
      showFatal('الخادم غير متصل: ' + (error.diagnosticCode || 'تعذر التحقق من الاتصال') + '. لا يمكن اللعب حالياً.', error.diagnosticCode || 'SERVER_CHECK_FAILED', error.details || { error: String(error) });
    });
  }

  Net.connect = () => {
    if (connectStarted) return;
    connectStarted = true;
    setConnectionUi(false);
    window.addEventListener('message', receiveSession);
    log('info', 'client_started', { apiConfigured: API_BASE.startsWith('https://'), websocketConfigured: typeof cfg.WS_URL === 'string' && cfg.WS_URL.startsWith('wss://') });
    setTimeout(() => {
      if (!sessionToken && !stopped) {
        showFatal('الخادم غير متصل: لم تصل جلسة تسجيل الدخول من Happy Live. أغلق اللعبة وافتحها مجدداً من داخل الغرفة.', 'SESSION_NOT_DELIVERED');
      }
    }, 12000);
  };
  window.CR_Net = Net;
})();
