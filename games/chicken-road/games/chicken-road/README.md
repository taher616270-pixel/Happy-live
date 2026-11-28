# games/chicken-road  (ملفات الواجهة الناقصة في Happy-live)

انسخ هذا المجلد إلى جذر المستودع: games/chicken-road/

games/chicken-road/
├─ client/  index.html · style.css · game.js · net.js · client-config.js
├─ shared/  config.js · engine.js · stats.js
└─ assets/  chicken.svg · chicken-dead.svg · chicken-win.svg · car-1/2/3.svg · music.mp3 · hop/hit/win/click.mp3

## تجربة بدون خادم
افتح client/index.html (WS_URL فاضي = وضع تجريبي، رصيد وهمي).
ملاحظة: افتحه عبر خادم محلي (مثلاً npx serve .) وليس file:// حتى تُحمَّل الصور والأصوات.

## الربط مع chicken_road_hub.ts (يحتاج مطابقة)
الواجهة تتكلم هذا البروتوكول (JSON عبر WebSocket، ?token=... في الرابط):
  ترسل:   {t:'play',amount,diff} · {t:'step'} · {t:'cash'} · {t:'history'} · {t:'top',range} · {t:'sync'}
  تستقبل: {t,data} بالأنواع: init · started · step · dead · cashed · balance · history · top · error
diff = easy | medium | hard
لو رسائل chicken_road_hub.ts مختلفة، عدّل net.js (دالة remote) فقط لتترجم بين الصيغتين، ولا تلمس game.js.

## من Flutter
قبل تحميل الصفحة: window.APP_USER_TOKEN و window.CR_WS_URL، وإذا كان المسار مختلفاً window.CR_ASSET_BASE.
