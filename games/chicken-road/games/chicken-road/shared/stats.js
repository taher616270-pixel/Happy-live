// سجل اللعب + ترتيب أفضل الفائزين (أمس / اليوم / أسبوعي). بالذاكرة؛ استبدله بقاعدة بيانات عند الحاجة.
(function (root) {
  'use strict';
  const DAY = 86400000;
  const dayStart = (t) => { const d = new Date(t); d.setHours(0, 0, 0, 0); return d.getTime(); };

  class Stats {
    constructor() { this.rows = []; this.hist = new Map(); }
    record(r) {
      r.ts = r.ts || Date.now();
      this.rows.push(r); if (this.rows.length > 50000) this.rows.shift();
      const h = this.hist.get(r.playerId) || []; h.push(r); if (h.length > 100) h.shift();
      this.hist.set(r.playerId, h);
    }
    history(pid, n = 30) {
      return (this.hist.get(pid) || []).slice(-n).reverse()
        .map((r) => ({ ts: r.ts, amount: r.amount, win: r.payout > 0, payout: r.payout }));
    }
    // صافي أرباح كل لاعب في الفترة، الأعلى أولاً
    top(range, n = 20, now = Date.now()) {
      const t0 = dayStart(now);
      const [from, to] = range === 'yesterday' ? [t0 - DAY, t0] : range === 'week' ? [t0 - 6 * DAY, now + 1] : [t0, now + 1];
      const sum = new Map();
      for (const r of this.rows) if (r.ts >= from && r.ts < to) sum.set(r.playerId, (sum.get(r.playerId) || 0) + r.payout - r.amount);
      return [...sum].filter(([, v]) => v > 0).sort((a, b) => b[1] - a[1]).slice(0, n)
        .map(([playerId, coins], i) => ({ rank: i + 1, playerId, coins: Math.floor(coins) }));
    }
  }
  if (typeof module !== 'undefined' && module.exports) module.exports = Stats; else root.CR_Stats = Stats;
})(typeof window !== 'undefined' ? window : globalThis);
