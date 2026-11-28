// ===== نقطة الربط مع Happy Live (واجهة) =====
// المسارات نسبية لـ client/index.html. لو عرضت اللعبة من مسار مختلف عدّل ASSET_BASE فقط.
(function () {
  const B = window.CR_ASSET_BASE || '../assets/';
  window.CR_CLIENT = {
    // رابط WebSocket الكامل لـ Durable Object / Worker (فاضي = وضع تجريبي بدون خادم)
    // مثال: 'wss://YOUR-WORKER.workers.dev/api/games/chicken-road/ws'
    WS_URL: window.CR_WS_URL || '',
    // توكن المستخدم الحالي (يمرره Flutter قبل تحميل الصفحة: window.APP_USER_TOKEN = '...')
    TOKEN: () => window.APP_USER_TOKEN || 'guest',
    ASSETS: {
      chicken: B + 'chicken.svg', chickenDead: B + 'chicken-dead.svg', chickenWin: B + 'chicken-win.svg',
      cars: [B + 'car-1.svg', B + 'car-2.svg', B + 'car-3.svg'],
      music: B + 'music.mp3',
      sfx: { hop: B + 'hop.mp3', hit: B + 'hit.mp3', win: B + 'win.mp3', click: B + 'click.mp3' }
    }
  };
})();
