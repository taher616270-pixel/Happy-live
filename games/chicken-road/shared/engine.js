// عرض المضاعف فقط. نتيجة الجولة واحتمال الاصطدام يحددهما الخادم حصراً.
(function (root) {
  'use strict';
  const C = root.CR_CONFIG;
  function multiplier(diff, step) {
    const difficulty = C.DIFFICULTIES[diff];
    if (!difficulty || step <= 0) return 1;
    const survival = Math.pow(1 - difficulty.death, step);
    return Math.floor((C.RTP / survival) * 100) / 100;
  }
  root.CR_Engine = Object.freeze({ multiplier });
})(window);
