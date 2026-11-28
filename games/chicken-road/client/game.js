// واجهة اللعبة: الطريق، الدجاجة، السيارات، الأزرار، النوافذ.
(function () {
  const C = CR_CONFIG, E = CR_Engine, Net = CR_Net, A = CR_CLIENT.ASSETS || {};
  const $ = (id) => document.getElementById(id);
  const S = { diff: 'easy', bet: 0, state: 'idle', step: 0, pos: 0, lock: false, music: true, first: true, tile: 80, side: 44 };
  const EMO_CARS = ['🚕', '🚗', '🚙', '🚌', '🏎️', '🚓', '🚚'];
  const fmt = (n) => Math.floor(n).toLocaleString('en-US');
  const SFX = {};
  function sfx(n) {                                                       // مؤثرات صوتية
    const u = (A.sfx || {})[n]; if (!S.music || !u) return;
    const a = (SFX[n] = SFX[n] || new Audio(u)).cloneNode(); a.volume = 0.6; a.play().catch(() => {});
  }
  function startMusic() {                                                  // تشتغل بعد أول لمسة (شرط المتصفح)
    if (!A.music) return;
    S.audio = S.audio || Object.assign(new Audio(A.music), { loop: true, volume: 0.35 });
    if (S.music) S.audio.play().catch(() => {});
  }
  document.addEventListener('pointerdown', startMusic, { once: true });
  const fmtM = (n) => (n >= 100 ? Math.round(n) : n.toFixed(2));   // مضاعف: خانتين، وبدون كسور فوق 100

  // ---------- الطريق ----------
  const view = $('view'), road = $('road'), tiles = [];
  const chicken = document.createElement('div'); chicken.id = 'chicken'; road.appendChild(chicken);
  for (let i = 0; i <= C.MAX_STEPS; i++) {
    const t = document.createElement('div');
    t.className = i === 0 ? 'tile side' : 'tile';
    if (i > 0) t.innerHTML = '<div class="m"><span></span></div>';
    road.appendChild(t); tiles.push(t);
  }
  const labels = () => tiles.forEach((t, i) => { if (i) t.querySelector('span').textContent = fmtM(E.multiplier(S.diff, i)) + 'X'; });
  function size() {                                                       // أربع مسارات ظاهرة تقريباً
    S.tile = (view.clientWidth - S.side) / 3.4;
    road.style.setProperty('--tile', S.tile + 'px'); road.style.setProperty('--side', S.side + 'px');
    road.style.width = S.side + C.MAX_STEPS * S.tile + 'px'; place(S.pos, true);
  }
  const cx = (i) => (i === 0 ? S.side * 0.5 : S.side + (i - 1) * S.tile + S.tile / 2);
  function place(i, instant) {
    S.pos = i;
    chicken.style.transition = instant ? 'none' : '';
    chicken.style.left = cx(i) - 24 + 'px';
    road.style.transform = `translateX(${-Math.max(0, i - 2) * S.tile}px)`;
    if (instant) requestAnimationFrame(() => (chicken.style.transition = ''));
    chicken.classList.add('hop'); setTimeout(() => chicken.classList.remove('hop'), 250);
  }
  function skin(state) {                                                  // صورة أو إيموجي
    const url = state === 'dead' ? A.chickenDead || A.chicken : state === 'win' ? A.chickenWin || A.chicken : A.chicken;
    chicken.className = (url ? 'img ' : '') + (state === 'dead' ? 'hit' : '');
    if (url) { chicken.style.backgroundImage = `url(${url})`; chicken.textContent = ''; }
    else { chicken.style.backgroundImage = ''; chicken.textContent = state === 'dead' ? '💥' : state === 'win' ? '😎' : '🐔'; }
  }

  // ---------- السيارات ----------
  function car(tile, ms, delay) {
    const c = document.createElement('div'); c.className = 'car';
    if (A.cars && A.cars.length) { c.classList.add('img'); c.style.backgroundImage = `url(${A.cars[(Math.random() * A.cars.length) | 0]})`; }
    else c.textContent = EMO_CARS[(Math.random() * EMO_CARS.length) | 0];
    tile.appendChild(c);
    const h = view.clientHeight, up = Math.random() < 0.4;
    const a = c.animate([{ transform: `translateY(${up ? h + 80 : -110}px)` }, { transform: `translateY(${up ? -110 : h + 80}px)` }],
      { duration: ms, delay: delay || 0, easing: 'linear', fill: 'both' });
    a.onfinish = () => c.remove();
    return c;
  }
  setInterval(() => {                                                      // سيارات ديكور بعيدة عن الدجاجة
    if (document.hidden) return;
    const i = Math.max(1, S.pos - 3) + ((Math.random() * 9) | 0);
    if (i > C.MAX_STEPS || i === S.pos || i === S.pos + 1) return;
    car(tiles[i], 1300 + Math.random() * 900);
  }, 420);
  // الدعس: الدجاجة تنزل على المسار ثم تدخل سيارة وتصدمها في منتصف الشاشة بالضبط
  function runOver(step) {
    tiles[step].querySelectorAll('.car').forEach((c) => c.remove());
    place(step);
    const ms = 420, delay = 260;                                           // تعبر المنتصف عند delay + ms/2
    car(tiles[step], ms, delay);
    setTimeout(() => { skin('dead'); sfx('hit'); }, delay + ms / 2);
  }

  // ---------- واجهة ----------
  function toast(t, cls) { const e = $('toast'); e.textContent = t; e.className = cls || ''; e.hidden = false; clearTimeout(toast.t); toast.t = setTimeout(() => (e.hidden = true), 2200); }
  function ui() {
    const active = S.state === 'active';
    $('betv').textContent = fmt(S.bet);
    $('go').className = 'play' + (active ? ' cash' : '');
    $('go').textContent = active ? 'سحب ' + fmt(S.bet * E.multiplier(S.diff, S.step)) : 'لعب';
    $('go').disabled = active ? S.step < 1 : S.bet < C.MIN_BET;
    document.querySelectorAll('#diffs button').forEach((b) => { b.classList.toggle('on', b.dataset.d === S.diff); b.disabled = active; });
    document.querySelectorAll('#chips button,#clear').forEach((b) => (b.disabled = active));
    $('mult').textContent = (active && S.step ? fmtM(E.multiplier(S.diff, S.step)) : '0') + 'x';
    $('hint').hidden = !(active && S.step === 0 && S.first);
    labels();
  }
  C.CHIPS.forEach((v) => {
    const b = document.createElement('button'); b.innerHTML = '<i class="coin"></i>' + v;
    b.onclick = () => { S.bet = v; ui(); }; $('chips').appendChild(b);
  });
  $('clear').onclick = () => { S.bet = 0; ui(); };
  Object.entries(C.DIFFICULTIES).reverse().forEach(([k, d]) => {          // صعب · عادي · سهل
    const b = document.createElement('button'); b.dataset.d = k; b.textContent = d.label;
    b.onclick = () => { S.diff = k; ui(); }; $('diffs').appendChild(b);
  });

  // ---------- اللعب ----------
  $('go').onclick = () => { sfx('click'); S.state === 'active' ? Net.send({ t: 'cash' }) : Net.send({ t: 'play', amount: S.bet, diff: S.diff }); };
  view.onclick = () => {                                                   // اضغط في أي مكان للخطوة التالية
    if (S.state !== 'active' || S.lock) return;
    S.lock = true; setTimeout(() => (S.lock = false), C.STEP_MIN_MS + 30);
    S.first = false; Net.send({ t: 'step' });
  };

  Net.on('init', (d) => {
    $('bal').textContent = fmt(d.balance);
    if (d.game) { Object.assign(S, { state: 'active', diff: d.game.diff, bet: d.game.amount, step: d.game.step }); place(d.game.step, true); }
    ui();
  });
  Net.on('balance', (d) => ($('bal').textContent = fmt(d.balance)));
  Net.on('error', (d) => toast(d.message, 'bad'));
  Net.on('offline', () => toast('الخادم غير متصل', 'bad'));
  Net.on('started', (d) => { Object.assign(S, { state: 'active', step: 0, bet: d.amount, diff: d.diff }); skin('idle'); place(0, true); ui(); });
  Net.on('step', (d) => { sfx('hop'); S.step = d.step; tiles[d.step].querySelectorAll('.car').forEach((c) => c.remove()); place(d.step); ui(); });
  Net.on('dead', (d) => {
    S.state = 'over'; S.step = d.step; runOver(d.step);
    setTimeout(() => toast('دعستك سيارة 💥 خسرت ' + fmt(d.amount), 'bad'), 700); ui();
  });
  Net.on('cashed', (d) => { S.state = 'over'; skin('win'); sfx('win'); toast(`ربحت ${fmt(d.payout)} 🎉  (${fmtM(d.mult)}x)`, 'good'); ui(); });

  // ---------- النوافذ ----------
  function modal(title, html) { $('mtitle').textContent = title; $('mbody').innerHTML = html; $('modal').hidden = false; }
  $('mclose').onclick = () => ($('modal').hidden = true);
  $('bHelp').onclick = () => modal('القواعد', `<ol class="rules"><li>اختر مبلغ لعبك ومستوى الصعوبة المطلوب</li>
    <li>تحرك عبر المسارات، وتجنب الاصطدامات لزيادة معامل الربح الخاص بك</li><li>قرر متى تفوز بناء على مدى تحملك للمخاطر</li></ol>`);
  $('bMusic').onclick = () => {
    S.music = !S.music; $('bMusic').classList.toggle('off', !S.music);
    if (S.music) startMusic(); else if (S.audio) S.audio.pause();
  };
  $('bSync').onclick = () => Net.send({ t: 'sync' });
  $('bLog').onclick = () => { modal('سجل اللعبة', '<div class="tbl"><div class="th"><span>الوقت</span><span>الأرباح</span><span>فوز</span><span>لعب</span></div><div id="rows"></div></div>'); Net.send({ t: 'history' }); };
  Net.on('history', (d) => {
    const r = $('rows'); if (!r) return;
    r.innerHTML = d.rows.map((x) => { const t = new Date(x.ts);
      return `<div class="tr"><span>${String(t.getHours()).padStart(2, '0')}:${String(t.getMinutes()).padStart(2, '0')}</span>
        <span class="${x.win ? 'g' : 'r'}">${fmt(x.win ? x.payout - x.amount : -x.amount)}</span><span>${x.win ? '✔' : '✘'}</span><span>${fmt(x.amount)}</span></div>`; }).join('');
  });
  function openTop() {
    modal('الفائزون اليوم', '<div id="top"></div>');
    Net.send({ t: 'top', range: 'today' });
  }
  $('bTop').onclick = () => openTop();
  Net.on('top', (d) => {
    const t = $('top'); if (!t) return;
    const esc = (value) => String(value ?? '').replace(/[&<>"']/g, (ch) => ({
      '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'
    })[ch]);
    t.innerHTML = (d.rows || []).length ? d.rows.map((x) => {
      const name = esc(x.name || 'لاعب');
      const code = esc(x.userCode || '');
      const avatar = typeof x.avatar === 'string' && /^https:\/\//i.test(x.avatar)
        ? ' style="background-image:url(' + x.avatar.replace(/["\\]/g, '') + ')"' : '';
      return '<div class="rk r' + Math.min(Number(x.rank) || 4, 4) + '"><b class="no">' + esc(x.rank) +
        '</b><div class="av"' + avatar + '>' + (avatar ? '' : name.slice(0, 1)) +
        '</div><span class="nm">' + name + (code ? '<small class="user-code"> #' + code + '</small>' : '') +
        '</span><span class="cn">' + fmt(x.coins) + '<i class="coin"></i></span></div>';
    }).join('') : '<p class="empty">لا يوجد فائزون منذ الساعة 12:00 صباحاً</p>';
  });

  window.addEventListener('resize', size); size(); skin('idle'); place(0, true); ui(); Net.connect();
})();
