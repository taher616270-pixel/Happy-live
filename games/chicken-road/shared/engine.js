// محرك اللعبة: لكل لاعب جولته الخاصة. يشتغل في Node وفي المتصفح (الوضع التجريبي).
(function (root) {
  'use strict';
  const C = typeof module !== 'undefined' && module.exports ? require('./config') : root.CR_CONFIG;

  const surv = (d) => 1 - C.DIFFICULTIES[d].death;
  const winChance = (d, n) => Math.pow(surv(d), n);                                   // نسبة النجاة التراكمية
  const multiplier = (d, n) => n <= 0 ? 1 : Math.floor((C.RTP / winChance(d, n)) * 100) / 100;
  // أول خطوة تدعس فيها السيارة الدجاجة (u عشوائي 0..1 خاص بالجولة)
  function crashAt(d, u) {
    for (let n = 1; n <= C.MAX_STEPS; n++) if (u >= winChance(d, n)) return n;
    return Infinity;
  }

  class Engine {
    // wallet:{debit,credit,balance}  emit(pid,type,data)  newRound(pid)->{u,commit,reveal}  onResult(record)
    constructor({ wallet, emit, newRound, onResult }) {
      Object.assign(this, { wallet, emit, newRound, onResult: onResult || (() => {}) });
      this.S = new Map();
    }

    async play(pid, amount, diff) {
      amount = Number(amount);
      const old = this.S.get(pid);
      if (old && (old.state === 'active' || old.state === 'pending')) return { error: 'عندك لعبة جارية' };
      if (!C.DIFFICULTIES[diff]) return { error: 'مستوى غير صحيح' };
      if (!(amount >= C.MIN_BET && amount <= C.MAX_BET)) return { error: `المبلغ من ${C.MIN_BET} إلى ${C.MAX_BET}` };
      this.S.set(pid, { state: 'pending' });                       // يمنع الخصم المزدوج
      if (!(await this.wallet.debit(pid, amount))) { this.S.delete(pid); return { error: 'الرصيد لا يكفي' }; }
      const r = this.newRound(pid);
      this.S.set(pid, { amount, diff, step: 0, crash: crashAt(diff, r.u), state: 'active', r, last: 0 });
      this.emit(pid, 'started', { amount, diff, commit: r.commit });
      this.emit(pid, 'balance', { balance: await this.wallet.balance(pid) });
      return { ok: true };
    }

    async step(pid) {
      const s = this.S.get(pid);
      if (!s || s.state !== 'active') return { error: 'لا توجد لعبة' };
      const now = Date.now();
      if (now - s.last < C.STEP_MIN_MS) return { error: 'أبطئ' };
      s.last = now; s.step++;
      if (s.step >= s.crash) {                                      // دعستها سيارة
        s.state = 'dead';
        this.emit(pid, 'dead', { step: s.step, amount: s.amount, reveal: s.r.reveal });
        this.onResult({ playerId: pid, amount: s.amount, diff: s.diff, step: s.step, mult: 0, payout: 0, ts: now });
      } else if (s.step >= C.MAX_STEPS) {
        this.emit(pid, 'step', { step: s.step, mult: multiplier(s.diff, s.step) });
        await this.cash(pid, true);
      } else this.emit(pid, 'step', { step: s.step, mult: multiplier(s.diff, s.step) });
      return { ok: true };
    }

    async cash(pid, auto) {
      const s = this.S.get(pid);
      if (!s || s.state !== 'active' || s.step < 1) return { error: 'لا يمكن السحب الآن' };
      s.state = 'cashed';
      const mult = multiplier(s.diff, s.step);
      const payout = Math.floor(s.amount * mult * 100) / 100;
      await this.wallet.credit(pid, payout);
      this.emit(pid, 'cashed', { step: s.step, mult, payout, reveal: s.r.reveal, auto: !!auto });
      this.emit(pid, 'balance', { balance: await this.wallet.balance(pid) });
      this.onResult({ playerId: pid, amount: s.amount, diff: s.diff, step: s.step, mult, payout, ts: Date.now() });
      return { ok: true };
    }

    snapshot(pid) {
      const s = this.S.get(pid);
      return s && s.state === 'active' ? { amount: s.amount, diff: s.diff, step: s.step } : null;
    }
  }

  const api = { Engine, crashAt, multiplier, winChance };
  if (typeof module !== 'undefined' && module.exports) module.exports = api; else root.CR_Engine = api;
})(typeof window !== 'undefined' ? window : globalThis);
