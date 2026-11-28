// طبقة الاتصال: خادم حقيقي (WebSocket) أو وضع تجريبي محلي بنفس المحرك.
(function () {
  const cfg = window.CR_CLIENT, H = {};
  const Net = {
    me: null,
    on(t, f) { (H[t] = H[t] || []).push(f); },
    fire(t, d) { (H[t] || []).forEach((f) => f(d)); },
    send() {}
  };

  function remote() {
    const ws = new WebSocket(cfg.WS_URL + '?token=' + encodeURIComponent(cfg.TOKEN()));
    ws.onmessage = (e) => { const m = JSON.parse(e.data); if (m.t === 'init') Net.me = m.data.playerId; Net.fire(m.t, m.data); };
    ws.onclose = () => { Net.fire('offline'); setTimeout(remote, 2000); };
    Net.send = (o) => ws.readyState === 1 && ws.send(JSON.stringify(o));
  }

  function local() {
    let bal = 1000000;
    const wallet = {
      balance: async () => bal,
      debit: async (_, a) => (bal >= a ? ((bal = +(bal - a).toFixed(2)), true) : false),
      credit: async (_, a) => { bal = +(bal + a).toFixed(2); }
    };
    const stats = new CR_Stats();
    const fake = ['E DIEM', 'مالك', 'نور الدين', 'AhmeT', 'Faturu', 'IDRAK', 'دمعت', 'Fares'];
    const prof = { me: { name: 'أنت', avatar: '' } };
    fake.forEach((n, i) => {                                   // لاعبين وهميين لعرض نافذة الترتيب
      prof['f' + i] = { name: n, avatar: '' };
      [0, 1, 2].forEach((d) => stats.record({ playerId: 'f' + i, amount: 1000, payout: 1000 + Math.floor(Math.random() * 90000 / (i + 1)) * 10, ts: Date.now() - d * 86400000 * 0.9 }));
    });
    const engine = new CR_Engine.Engine({
      wallet, emit: (_, t, d) => Net.fire(t, d), onResult: (r) => stats.record(r),
      newRound: () => ({ u: Math.random(), commit: 'demo', reveal: 'demo' })
    });
    Net.me = 'me';
    Net.send = async (o) => {
      let r;
      if (o.t === 'play') r = await engine.play('me', o.amount, o.diff);
      else if (o.t === 'step') r = await engine.step('me');
      else if (o.t === 'cash') r = await engine.cash('me');
      else if (o.t === 'history') Net.fire('history', { rows: stats.history('me') });
      else if (o.t === 'top') Net.fire('top', { range: o.range, rows: stats.top(o.range).map((x) => ({ ...x, ...prof[x.playerId] })) });
      else if (o.t === 'sync') Net.fire('init', { playerId: 'me', balance: bal, game: engine.snapshot('me') });
      if (r && r.error && r.error !== 'أبطئ') Net.fire('error', { message: r.error });
    };
    Net.fire('init', { playerId: 'me', balance: bal, game: null });
  }

  Net.connect = () => (cfg.WS_URL ? remote() : local());
  window.CR_Net = Net;
})();
