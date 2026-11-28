// الإعدادات المشتركة (سيرفر + واجهة). عدّل الأرقام من هنا فقط.
(function (root) {
  const CONFIG = {
    RTP: 0.97,              // نسبة العائد
    MAX_STEPS: 25,          // آخر خطوة = سحب تلقائي
    STEP_MIN_MS: 300,       // أقل وقت بين خطوتين (يمنع الضغط السريع)
    MIN_BET: 100,
    MAX_BET: 1000000,
    CHIPS: [100, 1000, 10000, 100000, 1000000],
    // death = احتمال أن تدعسك سيارة في كل خطوة
    DIFFICULTIES: {
      easy:   { label: 'سهل',  death: 0.06 },
      medium: { label: 'عادي', death: 0.14 },
      hard:   { label: 'صعب',  death: 0.22 }
    }
  };
  if (typeof module !== 'undefined' && module.exports) module.exports = CONFIG;
  else root.CR_CONFIG = CONFIG;
})(typeof window !== 'undefined' ? window : globalThis);
