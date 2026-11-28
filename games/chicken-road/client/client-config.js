// Production-only Happy Live integration. No guest or local demo mode.
(function () {
  const B = window.CR_ASSET_BASE || '../assets/';
  window.CR_CLIENT = Object.freeze({
    WS_URL: 'wss://happy-live-api.taher616270.workers.dev/api/v1/game/chicken-road/ws',
    TOKEN: () => window.CR_SESSION_TOKEN || '',
    ASSETS: Object.freeze({
      chicken: B + 'chicken.svg',
      chickenDead: B + 'chicken-dead.svg',
      chickenWin: B + 'chicken-win.svg',
      cars: [B + 'car-1.svg', B + 'car-2.svg', B + 'car-3.svg'],
      music: B + 'music.mp3',
      sfx: { hop: B + 'hop.mp3', hit: B + 'hit.mp3', win: B + 'win.mp3', click: B + 'click.mp3' }
    })
  });
})();